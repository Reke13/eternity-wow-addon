-- The list itself: players by name, shared by every character of the account. Forever has one
-- realm, so a name is enough and a "-Realm" suffix is dropped. What the game tells about a unit
-- (faction, class, race, level, guild) is read only when it isn't secret, and kept up to date each
-- time a listed player is seen.

---@type string, EternityUIBlacklistNamespace
local _, ns = ...
local Secret = EternityUI.Secret

---@class EternityUIBlacklistEntry
---@field name string
---@field faction string? "Horde" or "Alliance"
---@field class string? class file, such as "WARRIOR"
---@field className string? the class as the game named it
---@field race string?
---@field level integer?
---@field guild string?
---@field reason string
---@field added integer time() it was added
---@field addedBy string? the character that added it
---@field seen integer? time() it was last seen
---@field seenZone string?

---@class EternityUIBlacklistList
---@field db table? EternityUIBlacklistDB
---@field onChange fun()? called after any change
local List = {}
ns.List = List

local FACTIONS = { Horde = true, Alliance = true }

local function plain(value)
    if Secret.Is(value) then
        return nil
    end
    return value
end

-- Text without surrounding spaces, or nil if nothing is left.
local function trim(text)
    if type(text) ~= "string" then
        return nil
    end
    text = text:match("^%s*(.-)%s*$")
    return text ~= "" and text or nil
end

--- Binds the saved list, creating it the first time.
function List.Bind()
    local db = _G.EternityUIBlacklistDB
    if type(db) ~= "table" then
        db = {}
        _G.EternityUIBlacklistDB = db
    end
    db.version = 1
    db.players = db.players or {}
    List.db = db
end

--- A name without realm or surrounding spaces, or nil if nothing is left.
---@param name any
---@return string?
function List.Clean(name)
    local clean = trim(name)
    return clean and trim(clean:match("^[^%-]*"))
end

--- The key a name is stored under.
---@param name any
---@return string?
function List.Key(name)
    local clean = List.Clean(name)
    return clean and clean:lower()
end

---@param name any
---@return EternityUIBlacklistEntry?
function List.Get(name)
    local key = List.Key(name)
    return key and List.db.players[key] or nil
end

local function changed()
    if List.onChange then
        List.onChange()
    end
end

--- The name of the character playing, if the game gives it.
---@return string?
function List.Me()
    return List.Clean(plain(UnitName("player")))
end

--- What can be read of a unit that is another player, or nil.
---@param unit any
---@return table? info with name and, when known, faction, class, className, race, level and guild
function List.ReadUnit(unit)
    if type(unit) ~= "string" or Secret.Is(unit) then
        return nil
    end
    if not plain(UnitExists(unit)) or not plain(UnitIsPlayer(unit)) or plain(UnitIsUnit(unit, "player")) then
        return nil
    end
    local name = List.Clean(plain(UnitName(unit)))
    if not name then
        return nil
    end
    local info = { name = name }
    local faction = plain(UnitFactionGroup(unit))
    info.faction = FACTIONS[faction] and faction or nil
    local className, class = UnitClass(unit)
    info.className, info.class = plain(className), plain(class)
    info.race = plain(UnitRace(unit))
    local level = plain(UnitLevel(unit))
    info.level = type(level) == "number" and level > 0 and level or nil
    local guild = plain(GetGuildInfo(unit))
    info.guild = guild ~= "" and guild or nil
    return info
end

local FIELDS = { "faction", "class", "className", "race", "level", "guild" }

--- Updates an entry with what was read of the player. Unknown fields keep their old value.
---@param entry EternityUIBlacklistEntry
---@param info table
---@param seen boolean? also note when and where it was seen
function List.Update(entry, info, seen)
    for _, field in ipairs(FIELDS) do
        if info[field] ~= nil then
            entry[field] = info[field]
        end
    end
    if seen then
        entry.seen = time()
        entry.seenZone = plain(GetRealZoneText())
    end
end

--- Adds a player or updates them if listed. Returns the entry, or nil if the name is empty.
---@param info table at least { name }; reason and the unit fields are optional
---@return EternityUIBlacklistEntry?
function List.Add(info)
    local key = List.Key(info.name)
    if not key then
        return nil
    end
    local entry = List.db.players[key]
    if not entry then
        entry = { name = List.Clean(info.name), reason = "", added = time(), addedBy = List.Me() }
        List.db.players[key] = entry
    end
    List.Update(entry, info)
    if info.reason ~= nil then
        entry.reason = info.reason
    end
    changed()
    return entry
end

--- Saves what the editor holds. oldName is the name the entry had, to rename it.
---@param oldName string?
---@param fields table name, faction ("" for unknown), guild and reason
---@return EternityUIBlacklistEntry? entry
---@return string? problem "name" if the name is empty, "taken" if another entry has it
function List.Save(oldName, fields)
    local key = List.Key(fields.name)
    if not key then
        return nil, "name"
    end
    local oldKey = List.Key(oldName)
    local players = List.db.players
    if players[key] and key ~= oldKey then
        return nil, "taken"
    end
    local entry = oldKey and players[oldKey]
    if entry and oldKey ~= key then
        players[oldKey] = nil
        players[key] = entry
    end
    if not entry then
        entry = { reason = "", added = time(), addedBy = List.Me() }
        players[key] = entry
    end
    entry.name = List.Clean(fields.name)
    entry.faction = FACTIONS[fields.faction] and fields.faction or nil
    entry.guild = trim(fields.guild)
    entry.reason = trim(fields.reason) or ""
    changed()
    return entry
end

--- Removes a player. Returns the entry removed, if any.
---@param name any
---@return EternityUIBlacklistEntry?
function List.Remove(name)
    local key = List.Key(name)
    local entry = key and List.db.players[key]
    if entry then
        List.db.players[key] = nil
        changed()
    end
    return entry
end

local function contains(value, needle)
    return type(value) == "string" and value:lower():find(needle, 1, true) ~= nil
end

--- The entries that match a filter, sorted by name.
---@param players table<string, EternityUIBlacklistEntry>
---@param filter table { text, faction = "all" | "Horde" | "Alliance" | "unknown" }
---@return EternityUIBlacklistEntry[]
function List.Filter(players, filter)
    local needle = filter.text ~= "" and filter.text:lower() or nil
    local view = {}
    for _, entry in pairs(players) do
        local faction = entry.faction or "unknown"
        if filter.faction == "all" or filter.faction == faction then
            if
                not needle
                or contains(entry.name, needle)
                or contains(entry.guild, needle)
                or contains(entry.reason, needle)
                or contains(entry.className, needle)
            then
                view[#view + 1] = entry
            end
        end
    end
    table.sort(view, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    return view
end

--- How many players are listed.
---@return integer
function List.Count()
    local count = 0
    for _ in pairs(List.db.players) do
        count = count + 1
    end
    return count
end
