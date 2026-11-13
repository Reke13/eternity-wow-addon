-- EternityUI_Mail: the class of a name, to color it. A letter doesn't say who's what, so it's
-- looked up when a letter is saved (and again when one is drawn): your own characters (each one
-- notes itself on login), your guild, your friends, your group and the units you're looking at.
-- What's found is kept (EternityUIMailDB.classes, by lowercase name without realm), so a name
-- found once keeps its color.

---@type string, EternityUIMailNamespace
local _, ns = ...

---@class EternityUIMailClasses
local Classes = {}
ns.Classes = Classes

local UNITS = { "target", "mouseover", "focus" }

local function secret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

local function text(value)
    return type(value) == "string" and not secret(value) and value ~= "" and value or nil
end

--- The key a name is kept by: lowercase, without its realm.
---@param name string
---@return string
function Classes.Key(name)
    return (name:gsub("%-.*$", "")):lower()
end

local function known()
    local db = ns.History.Bind()
    if type(db.classes) ~= "table" then
        db.classes = {}
    end
    return db.classes
end

--- Notes a name's class (class file: MAGE, PRIEST...).
function Classes.Learn(name, class)
    name, class = text(name), text(class)
    if name and class then
        known()[Classes.Key(name)] = class
    end
end

-- Localized class name -> class file, for the friends list (it gives the localized one).
local function classFile(localized)
    for _, list in ipairs({ _G.LOCALIZED_CLASS_NAMES_MALE, _G.LOCALIZED_CLASS_NAMES_FEMALE }) do
        if type(list) == "table" then
            for file, shown in pairs(list) do
                if shown == localized then
                    return file
                end
            end
        end
    end
    return nil
end

--- This character, the units at hand, the group, the guild and the friends: what they say now.
function Classes.Scan()
    local name, surname = UnitName("player")
    local _, class = UnitClass("player")
    name, surname = text(name), text(surname)
    if name then
        Classes.Learn(surname and (name .. " " .. surname) or name, class)
        Classes.Learn(name, class)
    end
    local units = { unpack(UNITS) }
    for i = 1, 4 do
        units[#units + 1] = "party" .. i
    end
    for i = 1, (IsInRaid and IsInRaid() and 40 or 0) do
        units[#units + 1] = "raid" .. i
    end
    for _, unit in ipairs(units) do
        if UnitExists(unit) and UnitIsPlayer(unit) then
            local unitName = UnitName(unit)
            local _, unitClass = UnitClass(unit)
            Classes.Learn(unitName, unitClass)
        end
    end
    if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
        local count = GetNumGuildMembers()
        for i = 1, type(count) == "number" and not secret(count) and count or 0 do
            local member, _, _, _, _, _, _, _, _, _, memberClass = GetGuildRosterInfo(i)
            Classes.Learn(member, memberClass)
        end
    end
    local friends = C_FriendList
    if friends and friends.GetNumFriends and friends.GetFriendInfoByIndex then
        for i = 1, friends.GetNumFriends() or 0 do
            local info = friends.GetFriendInfoByIndex(i)
            if type(info) == "table" and text(info.className) then
                Classes.Learn(info.name, classFile(info.className))
            end
        end
    end
end

--- A name's class, or nil if it's not known.
---@param name string?
---@return string?
function Classes.Find(name)
    name = text(name)
    if not name then
        return nil
    end
    local classes = known()
    local key = Classes.Key(name)
    if classes[key] then
        return classes[key]
    end
    -- Forever's names carry a surname: "Reke" is "Reke One" if only one known name starts so.
    local found, matches = nil, 0
    for saved, class in pairs(classes) do
        if saved:match("^(%S+)") == key then
            found, matches = class, matches + 1
        end
    end
    return matches == 1 and found or nil
end

--- The color of a class as "ffrrggbb", or nil.
---@param class string?
---@return string?
function Classes.Hex(class)
    if not class then
        return nil
    end
    if C_ClassColor and C_ClassColor.GetClassColor then
        local color = C_ClassColor.GetClassColor(class)
        if color and color.GenerateHexColor then
            return color:GenerateHexColor()
        end
    end
    local color = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[class]
    return color and color.colorStr or nil
end

--- A name in its class color (as it is when the class isn't known).
---@param name string
---@param class string? a class already known for it
---@return string
function Classes.Color(name, class)
    local hex = Classes.Hex(class or Classes.Find(name))
    if hex then
        return "|c" .. hex .. name .. "|r"
    end
    return name
end
