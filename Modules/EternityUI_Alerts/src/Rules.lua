-- The rules, saved for the whole account (EternityUIAlertsDB): each one can be limited to a class,
-- so one list serves every character. Three sample rules are written the first time only; deleting
-- them is final.

---@type string, EternityUIAlertsNamespace
local _, ns = ...
local L = ns.L

---@class EternityUIAlertsRule
---@field id number
---@field kind string "buff", "enchant", "durability", "slots" or "item"
---@field enabled boolean
---@field name string
---@field spells string buff names or spell IDs, comma separated
---@field icon number|string? picked from a buff, or nil to look it up
---@field threshold number
---@field slot string "both", "main" or "off"
---@field item string item name or ID
---@field click boolean clicking the icon casts the buff
---@field clickUse string spell or item to use instead of the buff, "" for the buff itself
---@field glow boolean
---@field sound string key of Rules.SOUNDS
---@field class string class token, "" for any
---@field minLevel number
---@field group string "any", "solo", "group" or "raid"
---@field place string "any", "instance" or "world"
---@field hideResting boolean
---@field hideMounted boolean
---@field hideCombat boolean

---@class EternityUIAlertsRules
---@field db table? EternityUIAlertsDB once bound
---@field onChange fun()? set by the module
local Rules = {
    KINDS = { "buff", "enchant", "durability", "slots", "item" },
    -- Sounds a rule can pick: key -> SOUNDKIT name.
    SOUNDS = { ready = "READY_CHECK", raid = "RAID_WARNING", tell = "TELL_MESSAGE", ping = "MAP_PING" },
    SOUND_ORDER = { "none", "ready", "raid", "tell", "ping" },
}
ns.Rules = Rules

local DEFAULTS = {
    enabled = true,
    name = "",
    spells = "",
    threshold = 0,
    slot = "both",
    item = "",
    click = true,
    clickUse = "",
    glow = true,
    sound = "none",
    class = "",
    minLevel = 0,
    group = "any",
    place = "any",
    hideResting = false,
    hideMounted = false,
    hideCombat = true,
}

local THRESHOLDS = { buff = 0, enchant = 0, durability = 20, slots = 5, item = 5 }

local function fill(rule)
    for key, value in pairs(DEFAULTS) do
        if rule[key] == nil then
            rule[key] = value
        end
    end
    return rule
end

--- Adds a rule of a kind, at the end of the list.
---@param kind string
---@param fields table? values over the defaults
---@return EternityUIAlertsRule
function Rules.Add(kind, fields)
    local db = Rules.db
    local rule = fields or {}
    rule.id = db.nextId
    rule.kind = kind
    rule.name = rule.name or L["KIND_" .. kind]
    rule.threshold = rule.threshold or THRESHOLDS[kind]
    db.nextId = db.nextId + 1
    db.rules[#db.rules + 1] = fill(rule)
    return rule
end

local function seed()
    Rules.Add("durability", { name = L.SAMPLE_REPAIR, threshold = 20, sound = "ping" })
    Rules.Add("slots", { name = L.SAMPLE_BAGS, threshold = 5 })
    Rules.Add("buff", { name = L.SAMPLE_FOOD, spells = L.WELL_FED, place = "instance" })
end

--- Binds EternityUIAlertsDB (the client loads it before the modules start).
function Rules.Bind()
    if Rules.db then
        return
    end
    local db = _G.EternityUIAlertsDB
    if type(db) ~= "table" or type(db.rules) ~= "table" then
        db = { rules = {}, nextId = 1 }
        Rules.db = db
        seed()
    else
        Rules.db = db
        for _, rule in ipairs(db.rules) do
            fill(rule)
        end
    end
    _G.EternityUIAlertsDB = db
end

---@return EternityUIAlertsRule[]
function Rules.List()
    return Rules.db.rules
end

--- Removes a rule.
---@param rule EternityUIAlertsRule
function Rules.Remove(rule)
    for i, other in ipairs(Rules.db.rules) do
        if other == rule then
            table.remove(Rules.db.rules, i)
            return
        end
    end
end

--- Call after changing a rule.
function Rules.Changed()
    if Rules.onChange then
        Rules.onChange()
    end
end

--- The entries of a comma separated list: numbers as numbers, names trimmed.
---@param text string
---@return (number|string)[]
function Rules.Entries(text)
    local list = {}
    for entry in text:gmatch("[^,]+") do
        entry = entry:match("^%s*(.-)%s*$")
        if entry ~= "" then
            list[#list + 1] = tonumber(entry) or entry
        end
    end
    return list
end
