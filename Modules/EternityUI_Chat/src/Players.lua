-- EternityUI_Chat: who writes. Class and race come from the sender's GUID; the level isn't sent with
-- chat messages, so it's remembered from what the client does show: the group, the guild roster,
-- the friends list and players targeted, hovered or with a nameplate. Each entry lasts 30 days.
-- The sender's name is decorated (icon, level, class color) through Blizzard's sender name
-- filter registry (ChatFrameUtil.AddSenderNameFilter), which Blizzard calls securely; during
-- Blizzard's chat restrictions name and GUID are secret and the filter leaves them alone.

---@type string, EternityUIChatNamespace
local _, ns = ...
local opt, secret = ns.opt, ns.secret

local KEEP_DAYS = 30
local DAY = 86400
local GUILD_DELAY = 2 -- seconds: the roster fires in bursts

---@class EternityUIChatPlayer
---@field l integer? level
---@field c string? class file (MAGE...)
---@field r string? race file
---@field s integer? sex (2 male, 3 female)
---@field t number time() it was seen

---@class EternityUIChatPlayers
---@field running boolean?
---@field hooked boolean?
local Players = {}
ns.Players = Players

local function players()
    return ns.DB().players
end

--- Removes the entries older than KEEP_DAYS.
function Players:Prune(now)
    now = now or time()
    local list = players()
    for name, entry in pairs(list) do
        if type(entry) ~= "table" or (entry.t or 0) < now - KEEP_DAYS * DAY then
            list[name] = nil
        end
    end
end

---@param fullName string?
---@param info { level: integer?, class: string?, race: string?, sex: integer? }
function Players:Remember(fullName, info)
    if not fullName or secret(fullName) then
        return
    end
    local list = players()
    local entry = list[fullName] or {}
    if info.level and not secret(info.level) and info.level > 0 then
        entry.l = info.level
    end
    entry.c = info.class or entry.c
    entry.r = info.race or entry.r
    entry.s = info.sex or entry.s
    entry.t = time()
    list[fullName] = entry
end

---@return EternityUIChatPlayer?
function Players:Get(fullName)
    return fullName and players()[fullName] or nil
end

--- The class known for a player, or nil.
---@param fullName string?
---@return string?
function Players:KnownClass(fullName)
    local known = self:Get(fullName)
    return known and known.c or nil
end

--- Class, race and sex from a GUID (nil if it's secret or unknown).
function Players:FromGUID(guid)
    if not guid or secret(guid) or guid == "" or not GetPlayerInfoByGUID then
        return nil
    end
    local _, class, _, race, sex = GetPlayerInfoByGUID(guid)
    if secret(class) then
        return nil
    end
    return class, race, sex
end

-- Sources -----------------------------------------------------------------------------------

function Players:ScanUnit(unit)
    if not UnitExists(unit) or not UnitIsPlayer(unit) then
        return
    end
    local name, realm = UnitFullName(unit)
    if not name or secret(name) or secret(realm) then
        return
    end
    local _, class = UnitClass(unit)
    local _, race = UnitRace(unit)
    local level = UnitLevel(unit)
    self:Remember(realm and realm ~= "" and (name .. "-" .. realm) or ns.FullName(name), {
        level = not secret(level) and level or nil,
        class = not secret(class) and class or nil,
        race = not secret(race) and race or nil,
        sex = UnitSex(unit),
    })
end

function Players:ScanGroup()
    self:ScanUnit("player")
    local raid = IsInRaid()
    for i = 1, GetNumGroupMembers() do
        self:ScanUnit(raid and ("raid" .. i) or ("party" .. i))
    end
end

function Players:ScanGuild()
    if not GetNumGuildMembers or not GetGuildRosterInfo then
        return
    end
    for i = 1, GetNumGuildMembers() do
        local name, _, _, level, _, _, _, _, _, _, class = GetGuildRosterInfo(i)
        if name and not secret(name) then
            self:Remember(ns.FullName(name), { level = level, class = class })
        end
    end
end

function Players:ScanFriends()
    if not C_FriendList or not C_FriendList.GetNumFriends then
        return
    end
    for i = 1, C_FriendList.GetNumFriends() do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and info.name and not secret(info.name) then
            local class, race, sex = self:FromGUID(info.guid)
            self:Remember(ns.FullName(info.name), { level = info.level, class = class, race = race, sex = sex })
        end
    end
end

-- Decoration --------------------------------------------------------------------------------

local function atlasExists(atlas)
    return C_Texture == nil or C_Texture.GetAtlasInfo == nil or C_Texture.GetAtlasInfo(atlas) ~= nil
end

--- Atlas of the icon chosen in the options (class or race), or nil.
function Players:IconAtlas(class, race, sex, kind)
    kind = kind or opt("names.icon")
    local atlas
    if kind == "class" and class then
        atlas = "classicon-" .. class:lower()
    elseif kind == "race" and race then
        atlas = ("raceicon-%s-%s"):format(race:lower(), sex == 3 and "female" or "male")
    end
    if atlas and atlasExists(atlas) then
        return atlas
    end
end

function Players:IconMarkup(class, race, sex)
    local atlas = self:IconAtlas(class, race, sex)
    if not atlas then
        return ""
    end
    local size = opt("names.iconSize")
    return ("|A:%s:%d:%d|a"):format(atlas, size, size)
end

local function hex(r, g, b)
    return ("ff%02x%02x%02x"):format(r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5)
end

function Players:LevelMarkup(level)
    if not level then
        return ""
    end
    if opt("names.levelColor") and GetQuestDifficultyColor then
        local color = GetQuestDifficultyColor(level)
        if color then
            return ("|c%s%d|r"):format(hex(color.r, color.g, color.b), level)
        end
    end
    return tostring(level)
end

--- Class color as "ffRRGGBB", or nil.
function Players:ClassHex(class)
    local color = class and C_ClassColor and C_ClassColor.GetClassColor(class)
    if color then
        return hex(color.r, color.g, color.b)
    end
end

--- Name with the options' icon, level and class color. `name` is what's shown (it may already
--- carry Blizzard's class color: it's kept).
---@param name string
---@param fullName string?
---@param guid string?
---@return string
function Players:Decorate(name, fullName, guid)
    local class, race, sex = self:FromGUID(guid)
    local known = self:Get(fullName)
    if known then
        class, race, sex = class or known.c, race or known.r, sex or known.s
    end
    if guid and fullName and class then
        self:Remember(fullName, { class = class, race = race, sex = sex })
    end
    local text = name
    if opt("names.classColor") and class and not name:find("^|c") then
        local color = self:ClassHex(class)
        if color then
            text = ("|c%s%s|r"):format(color, name)
        end
    end
    local prefix = {}
    local icon = self:IconMarkup(class, race, sex)
    if icon ~= "" then
        prefix[#prefix + 1] = icon
    end
    if opt("names.level") and known and known.l then
        prefix[#prefix + 1] = self:LevelMarkup(known.l)
    end
    if #prefix == 0 then
        return text
    end
    return table.concat(prefix, " ") .. " " .. text
end

--- Blizzard's sender name filter: returns the decorated name, or nil to leave it as it is.
function Players:OnSenderName(event, decorated, ...)
    if not self.running then
        return nil
    end
    local senderName = select(2, ...)
    local guid = select(12, ...)
    if secret(decorated) or secret(senderName) or secret(guid) or type(decorated) ~= "string" then
        return nil
    end
    if not guid or guid == "" then
        return nil
    end
    return self:Decorate(decorated, ns.FullName(senderName), guid)
end

-- Lifecycle ---------------------------------------------------------------------------------

local EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "GROUP_ROSTER_UPDATE",
    "PLAYER_TARGET_CHANGED",
    "UPDATE_MOUSEOVER_UNIT",
    "NAME_PLATE_UNIT_ADDED",
    "GUILD_ROSTER_UPDATE",
    "FRIENDLIST_UPDATE",
    "PLAYER_LEVEL_UP",
}

function Players:OnEvent(event, arg)
    if not self.running then
        return
    end
    if event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_LEVEL_UP" then
        self:ScanGroup()
    elseif event == "PLAYER_TARGET_CHANGED" then
        self:ScanUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        self:ScanUnit("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if arg and not secret(arg) then
            self:ScanUnit(arg)
        end
    elseif event == "GUILD_ROSTER_UPDATE" then
        if not self.guildPending then
            self.guildPending = true
            C_Timer.After(GUILD_DELAY, function()
                self.guildPending = false
                if self.running then
                    self:ScanGuild()
                end
            end)
        end
    elseif event == "FRIENDLIST_UPDATE" then
        self:ScanFriends()
    end
end

function Players:InstallHooks()
    self.hooked = true
    local events = CreateFrame("Frame")
    for _, event in ipairs(EVENTS) do
        -- An event this client doesn't have errors on RegisterEvent: skip it.
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", function(_, event, arg)
        self:OnEvent(event, arg)
    end)
    self.filter = function(...)
        return self:OnSenderName(...)
    end
end

function Players:Start()
    self.running = true
    if not self.hooked then
        self:InstallHooks()
    end
    self:Prune()
    self:ScanGroup()
    local util = _G.ChatFrameUtil
    if util and util.AddSenderNameFilter and not self.filtering then
        util.AddSenderNameFilter(self.filter)
        self.filtering = true
    end
end

function Players:Stop()
    self.running = false
    local util = _G.ChatFrameUtil
    if util and util.RemoveSenderNameFilter and self.filtering then
        util.RemoveSenderNameFilter(self.filter)
        self.filtering = false
    end
end
