-- The rules, saved in the Eternity profile (the store's data of the module), so each profile has its
-- own list; a rule can still be limited to a class or to levels. A profile copied from another
-- takes its rules; one with none gets three sample rules, and deleting them is final.
-- They used to be saved for the whole account (EternityUIAlertsDB): the first start with profiles
-- copies that list into every profile and clears it, so no character loses its rules.

---@type string, EternityUIAlertsNamespace
local addonName, ns = ...
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
---@field maxLevel number 0 for no limit; never under minLevel
---@field group string "any", "solo", "group" or "raid"
---@field place string "any", "instance" or "world"
---@field hideResting boolean
---@field hideMounted boolean
---@field combat string "out" (only out of combat), "in" (only in combat) or "any"
---@field lowTime boolean buff rules: a buff with lowTimeSeconds or less left counts as missing
---@field lowTimeSeconds number 1 to 600
---@field scale number the icon's size, in percent of the row's (50 to 200)
---@field showName string "default" (as the row), "show" or "hide"
---@field customGlow boolean glows in glowColor instead of the theme's accent
---@field glowColor string "#RRGGBB"
---@field countdown boolean buff rules: count down the seconds left inside the icon
---@field iconOverride string a spell or item ID, or a texture; "" for the rule's own

---@class EternityUIAlertsRules
---@field db table? the active profile's { rules, nextId } once bound
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
    maxLevel = 0,
    group = "any",
    place = "any",
    hideResting = false,
    hideMounted = false,
    combat = "out",
    lowTime = false,
    lowTimeSeconds = 60,
    scale = 100,
    showName = "default",
    customGlow = false,
    glowColor = "#FFD100",
    countdown = true,
    iconOverride = "",
}

Rules.LOW_TIME_MIN, Rules.LOW_TIME_MAX = 1, 600
Rules.SCALE_MIN, Rules.SCALE_MAX = 50, 200
Rules.SHOW_NAME = { "default", "show", "hide" }

local THRESHOLDS = { buff = 0, enchant = 0, durability = 20, slots = 5, item = 5 }

local function fill(rule)
    -- Rules saved before "combat": the old "Hide in combat" switch.
    if rule.combat == nil and rule.hideCombat ~= nil then
        rule.combat = rule.hideCombat and "out" or "any"
    end
    rule.hideCombat = nil
    for key, value in pairs(DEFAULTS) do
        if rule[key] == nil then
            rule[key] = value
        end
    end
    -- Hand edited or broken saved values: back into range.
    local seconds = tonumber(rule.lowTimeSeconds) or DEFAULTS.lowTimeSeconds
    rule.lowTimeSeconds = math.min(Rules.LOW_TIME_MAX, math.max(Rules.LOW_TIME_MIN, math.floor(seconds)))
    rule.lowTime = rule.lowTime == true
    rule.minLevel = math.max(0, math.floor(tonumber(rule.minLevel) or 0))
    rule.maxLevel = math.max(0, math.floor(tonumber(rule.maxLevel) or 0))
    Rules.FitLevels(rule, "minLevel")
    local scale = tonumber(rule.scale) or DEFAULTS.scale
    rule.scale = math.min(Rules.SCALE_MAX, math.max(Rules.SCALE_MIN, math.floor(scale)))
    if rule.showName ~= "show" and rule.showName ~= "hide" then
        rule.showName = "default"
    end
    if type(rule.glowColor) ~= "string" or not rule.glowColor:match("^#%x%x%x%x%x%x$") then
        rule.glowColor = DEFAULTS.glowColor
    end
    if type(rule.iconOverride) ~= "string" then
        rule.iconOverride = ""
    end
    return rule
end

--- Adds a rule of a kind, at the end of the list.
---@param kind string
---@param fields table? values over the defaults
---@return EternityUIAlertsRule
function Rules.Add(kind, fields)
    local db = Rules.Current()
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

--- Moves the rules once saved for the whole account into every profile that has none yet.
local function migrate(store)
    local legacy = _G.EternityUIAlertsDB
    if type(legacy) ~= "table" then
        return
    end
    if type(legacy.rules) == "table" then
        local nextId = tonumber(legacy.nextId) or 1
        for _, rule in ipairs(legacy.rules) do
            if type(rule.id) == "number" and rule.id >= nextId then
                nextId = rule.id + 1
            end
        end
        store:SeedData(addonName, { rules = legacy.rules, nextId = nextId })
    end
    _G.EternityUIAlertsDB = nil
end

--- Binds the active profile's rules (the store exists before the modules start). Called again
--- when the profile changes; a profile without rules gets the sample ones.
function Rules.Bind()
    local store = EternityUI.store
    migrate(store)
    local db = store:GetData(addonName)
    if type(db) ~= "table" or type(db.rules) ~= "table" then
        db = { rules = {}, nextId = 1 }
        store:SetData(addonName, db)
        Rules.db = db
        seed()
        return
    end
    db.nextId = tonumber(db.nextId) or (#db.rules + 1)
    for _, rule in ipairs(db.rules) do
        fill(rule)
    end
    Rules.db = db
end

--- The active profile's { rules, nextId }, bound again if the profile changed since.
---@return table
function Rules.Current()
    if not Rules.db or Rules.db ~= EternityUI.store:GetData(addonName) then
        Rules.Bind()
    end
    return Rules.db
end

---@return EternityUIAlertsRule[]
function Rules.List()
    return Rules.Current().rules
end

--- Keeps "up to level" from going under "from level": the one that wasn't just changed gives way.
--- Returns true when it changed one.
---@param rule EternityUIAlertsRule
---@param changed string "minLevel" or "maxLevel"
---@return boolean
function Rules.FitLevels(rule, changed)
    if rule.maxLevel <= 0 or rule.maxLevel >= rule.minLevel then
        return false
    end
    if changed == "maxLevel" then
        rule.minLevel = rule.maxLevel
    else
        rule.maxLevel = rule.minLevel
    end
    return true
end

--- Removes a rule.
---@param rule EternityUIAlertsRule
function Rules.Remove(rule)
    for i, other in ipairs(Rules.List()) do
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
