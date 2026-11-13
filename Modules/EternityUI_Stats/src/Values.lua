-- EternityUI_Stats values: the registry of stats (category, label, icon, how to read and show it)
-- and the categories in the order the options ask for. The formulas follow Blizzard's own
-- character window on Forever (Camelot PaperDollFrameStats.lua).
--
-- Secret values: every read goes through S.Call, which stops the stat with a SECRET marker as
-- soon as the game returns a secret, so no math or comparison ever touches one. A stat with a
-- `raw` reader can still be drawn while secret: raw returns a format and the game's values,
-- passed untouched to SetFormattedText.

---@type string, EternityUIStatsNamespace
local _, ns = ...
local Core, L = ns.Core, ns.L

local SECRET, MISSING = {}, {}

---What a stat shows right now.
---@class EternityStatResult
---@field text string? plain text (nil when secret)
---@field mood string? "buff", "debuff" or nil
---@field zero boolean? nothing to show (hidden with categories.hideZero)
---@field lines table[]? tooltip lines: { left, right } pairs or plain strings
---@field secret boolean? the game hid a value

---@class EternityStatDefinition
---@field id string
---@field cat string
---@field label (string|fun(): string)?
---@field icon string? texture path
---@field atlas string? client atlas (drawn by the emulator too)
---@field get fun(S: table): EternityStatResult|nil nil = doesn't apply to this character
---@field raw (fun(S: table): string?, ...)? format and the game's values while secret; nil when
---the stat's full text can't be drawn from secret values
---@field applies (fun(): boolean)? false hides the stat (an option, for example)

---@class EternityUIStatsValues
---@field stats EternityStatDefinition[]
---@field byId table<string, EternityStatDefinition>
local Values = { stats = {}, byId = {}, SECRET = SECRET, MISSING = MISSING }
ns.Values = Values

Values.CATEGORIES = { "general", "attributes", "melee", "ranged", "spell", "defense", "resistances", "enhancements" }

-- Categories that matter most to each class (go first with categories.byClass) and the ones it
-- doesn't use (hidden with categories.hideIrrelevant).
Values.CLASS_FIRST = {
    WARRIOR = { "melee", "defense" },
    ROGUE = { "melee" },
    HUNTER = { "ranged" },
    MAGE = { "spell" },
    PRIEST = { "spell" },
    WARLOCK = { "spell" },
    PALADIN = { "melee", "spell", "defense" },
    SHAMAN = { "spell", "melee" },
    DRUID = { "spell", "melee" },
    DEATHKNIGHT = { "melee", "defense" },
}
Values.CLASS_UNUSED = {
    MAGE = { melee = true, ranged = true },
    PRIEST = { melee = true, ranged = true },
    WARLOCK = { melee = true, ranged = true },
    WARRIOR = { spell = true },
    ROGUE = { spell = true },
}

-- Combat rating indices: FrameXML globals on Forever, with the same numbers as a fallback.
local function cr(name, fallback)
    local value = _G["CR_" .. name]
    return type(value) == "number" and value or fallback
end
local CR = {
    DEFENSE = cr("DEFENSE_SKILL", 2),
    DODGE = cr("DODGE", 3),
    PARRY = cr("PARRY", 4),
    BLOCK = cr("BLOCK", 5),
    HIT_MELEE = cr("HIT_MELEE", 6),
    HIT_RANGED = cr("HIT_RANGED", 7),
    HIT_SPELL = cr("HIT_SPELL", 8),
    CRIT_MELEE = cr("CRIT_MELEE", 9),
    CRIT_RANGED = cr("CRIT_RANGED", 10),
    CRIT_SPELL = cr("CRIT_SPELL", 11),
    SPEED = cr("SPEED", 14),
    RESILIENCE = type(_G.COMBAT_RATING_RESILIENCE_PLAYER_DAMAGE_TAKEN) == "number"
            and _G.COMBAT_RATING_RESILIENCE_PLAYER_DAMAGE_TAKEN
        or 16,
    LIFESTEAL = cr("LIFESTEAL", 17),
    HASTE_MELEE = cr("HASTE_MELEE", 18),
    HASTE_RANGED = cr("HASTE_RANGED", 19),
    HASTE_SPELL = cr("HASTE_SPELL", 20),
    AVOIDANCE = cr("AVOIDANCE", 21),
    EXPERTISE = cr("EXPERTISE", 24),
    ARMOR_PENETRATION = cr("ARMOR_PENETRATION", 25),
    MASTERY = cr("MASTERY", 26),
    VERSATILITY = cr("VERSATILITY_DAMAGE_DONE", 29),
    VERSATILITY_TAKEN = cr("VERSATILITY_DAMAGE_TAKEN", 31),
}
Values.CR = CR

-- Helpers given to every stat ------------------------------------------------------------------

local S = {}
Values.S = S

local function pack(...)
    return { n = select("#", ...), ... }
end

--- Calls a game function: stops the stat with SECRET when any result is secret and with
--- MISSING when the function doesn't exist or errors (the stat then doesn't apply).
function S.Call(fn, ...)
    if type(fn) ~= "function" then
        error(MISSING, 0)
    end
    local results = pack(pcall(fn, ...))
    if not results[1] then
        error(MISSING, 0)
    end
    for i = 2, results.n do
        if Core.Secret(results[i]) then
            error(SECRET, 0)
        end
    end
    return unpack(results, 2, results.n)
end

--- Like S.Call, but nil (instead of stopping the stat) when the function is missing.
function S.Maybe(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    return S.Call(fn, ...)
end

function S.Number(value)
    return type(value) == "number" and value or 0
end

function S.Pct(value)
    local decimals = Core.Opt("values.decimals") or 2
    return ("%." .. decimals .. "f%%"):format(S.Number(value))
end

function S.Int(value)
    value = math.floor(S.Number(value) + 0.5)
    if Core.Opt("values.largeNumbers") == "short" and math.abs(value) >= 10000 then
        local ok, text = pcall(AbbreviateNumbers, value)
        if ok and type(text) == "string" then
            return text
        end
    end
    if BreakUpLargeNumbers then
        local ok, text = pcall(BreakUpLargeNumbers, value)
        if ok and type(text) == "string" then
            return text
        end
    end
    return tostring(value)
end

--- A percentage from a combat rating, shown as the values.ratings option asks.
function S.Rated(percent, index)
    local mode = Core.Opt("values.ratings")
    local rating = index and S.Maybe(GetCombatRating, index)
    if mode == "percent" or type(rating) ~= "number" then
        return S.Pct(percent)
    elseif mode == "rating" then
        return S.Int(rating)
    end
    return ("%s (%s)"):format(S.Pct(percent), S.Int(rating))
end

--- Tooltip line with the rating behind a percentage.
function S.RatingLine(lines, index)
    local rating = index and S.Maybe(GetCombatRating, index)
    if type(rating) == "number" and rating > 0 then
        local bonus = S.Maybe(GetCombatRatingBonus, index)
        lines[#lines + 1] = { L.TIP_RATING, ("%s (%s)"):format(S.Int(rating), S.Pct(bonus)) }
    end
    return lines
end

-- Raw readers: a format and the game's values for SetFormattedText, drawn while the values are
-- secret. They give the same text as the plain readers whenever that needs no math or comparison
-- on the values, so a stat looks the same in and out of combat; a raw reader that can't returns
-- nil and the panel shows the last value it knew.

--- Format and value that read like S.Int, for a value that may be secret: the game's own number
--- formatters when they take it, a plain number otherwise.
function S.RawInt(value)
    local formatter = Core.Opt("values.largeNumbers") == "short" and AbbreviateNumbers or BreakUpLargeNumbers
    if type(formatter) == "function" then
        local ok, text = pcall(formatter, value)
        if ok and type(text) == "string" then
            return "%s", text
        end
    end
    return "%.0f", value
end

--- A raw reader for a percentage with its combat rating, shown as values.ratings asks.
function S.RawRated(read, index)
    return function()
        local mode = Core.Opt("values.ratings")
        local pct = "%." .. (Core.Opt("values.decimals") or 2) .. "f%%"
        if not index or mode == "percent" or type(GetCombatRating) ~= "function" then
            return pct, (read())
        end
        local format, rating = S.RawInt(GetCombatRating(index))
        if mode == "rating" then
            return format, rating
        end
        return pct .. " (" .. format .. ")", (read()), rating
    end
end

--- "buff", "debuff" or nil from the positive and negative modifiers.
function S.Mood(pos, neg)
    if S.Number(neg) < 0 then
        return "debuff"
    elseif S.Number(pos) > 0 then
        return "buff"
    end
    return nil
end

--- A total with its modifiers: text (with "(+x -y)" when values.showMods), mood and lines.
function S.Modded(total, pos, neg, lines)
    pos, neg = S.Number(pos), S.Number(neg)
    local text = S.Int(total)
    if Core.Opt("values.showMods") and (pos ~= 0 or neg ~= 0) then
        local mods = {}
        if pos ~= 0 then
            mods[#mods + 1] = "+" .. S.Int(pos)
        end
        if neg ~= 0 then
            mods[#mods + 1] = S.Int(neg)
        end
        text = ("%s (%s)"):format(text, table.concat(mods, " "))
    end
    lines = lines or {}
    lines[#lines + 1] = { L.TIP_BASE, S.Int(S.Number(total) - pos - neg) }
    if pos ~= 0 then
        lines[#lines + 1] = { L.TIP_BONUS, "+" .. S.Int(pos) }
    end
    if neg ~= 0 then
        lines[#lines + 1] = { L.TIP_PENALTY, S.Int(neg) }
    end
    return { text = text, mood = S.Mood(pos, neg), zero = S.Number(total) == 0, lines = lines }
end

local function percent(value, index, lines)
    value = S.Number(value)
    return { text = S.Rated(value, index), zero = value == 0, lines = S.RatingLine(lines or {}, index) }
end

local function level()
    return S.Number(S.Maybe(UnitLevel, "player"))
end

-- Registry -------------------------------------------------------------------------------------

local ICON = "Interface\\Icons\\"

local function add(stat)
    Values.stats[#Values.stats + 1] = stat
    Values.byId[stat.id] = stat
    return stat
end

--- The label shown for a stat.
function Values.Label(stat)
    if type(stat.label) == "function" then
        local ok, text = pcall(stat.label)
        if ok and type(text) == "string" then
            return text
        end
    elseif type(stat.label) == "string" then
        return stat.label
    end
    return L[stat.id] or stat.id
end

--- Reads a stat: a result, a { secret = true } result, or nil when it doesn't apply.
---@param stat EternityStatDefinition
---@return EternityStatResult|nil
function Values.Read(stat)
    if stat.applies and not stat.applies() then
        return nil
    end
    local ok, result = pcall(stat.get, S)
    if ok then
        return result
    elseif result == SECRET then
        return { secret = true }
    end
    -- MISSING or an error in the stat: it doesn't apply on this client.
    return nil
end

--- The categories to show, in order, from the options.
function Values.Categories()
    local class = Core.Class()
    local order = {}
    local seen = {}
    local function push(id)
        if not seen[id] then
            seen[id] = true
            order[#order + 1] = id
        end
    end
    push("general")
    push("attributes")
    if Core.Opt("categories.byClass") and class and Values.CLASS_FIRST[class] then
        for _, id in ipairs(Values.CLASS_FIRST[class]) do
            push(id)
        end
    end
    for _, id in ipairs(Values.CATEGORIES) do
        push(id)
    end
    local unused = Core.Opt("categories.hideIrrelevant") and class and Values.CLASS_UNUSED[class] or {}
    local list = {}
    for _, id in ipairs(order) do
        if Core.Opt("categories." .. id) and not unused[id] then
            list[#list + 1] = id
        end
    end
    return list
end

--- The stats of one category, in registry order.
function Values.Of(category)
    local list = {}
    for _, stat in ipairs(Values.stats) do
        if stat.cat == category then
            list[#list + 1] = stat
        end
    end
    return list
end

-- General --------------------------------------------------------------------------------------

add({
    id = "health",
    cat = "general",
    icon = ICON .. "Spell_Holy_SealOfSacrifice",
    get = function()
        local value = S.Number(S.Call(UnitHealthMax, "player"))
        return { text = S.Int(value), zero = value == 0 }
    end,
    raw = function()
        return S.RawInt(UnitHealthMax("player"))
    end,
})

add({
    id = "power",
    cat = "general",
    icon = ICON .. "Spell_Frost_ManaRecharge",
    label = function()
        local _, token = UnitPowerType("player")
        local name = type(token) == "string" and _G[token]
        return type(name) == "string" and name or L.power
    end,
    get = function()
        local value = S.Number(S.Call(UnitPowerMax, "player"))
        return { text = S.Int(value), zero = value == 0 }
    end,
    raw = function()
        return S.RawInt(UnitPowerMax("player"))
    end,
})

add({
    id = "moveSpeed",
    cat = "general",
    icon = ICON .. "Ability_Rogue_Sprint",
    get = function()
        local current, run, flight, swim = S.Call(GetUnitSpeed, "player")
        local base = _G.BASE_MOVEMENT_SPEED or 7
        local shown = S.Number(current) > 0 and current or run
        return {
            text = S.Pct(S.Number(shown) / base * 100),
            lines = {
                { L.TIP_RUN, S.Pct(S.Number(run) / base * 100) },
                { L.TIP_SWIM, S.Pct(S.Number(swim) / base * 100) },
                { L.TIP_FLY, S.Pct(S.Number(flight) / base * 100) },
            },
        }
    end,
})

add({
    id = "itemLevel",
    cat = "general",
    icon = ICON .. "INV_Chest_Plate04",
    get = function()
        local overall, equipped = S.Call(GetAverageItemLevel)
        local shown = S.Number(equipped or overall)
        return {
            text = ("%.1f"):format(shown),
            zero = shown == 0,
            lines = {
                { L.TIP_EQUIPPED, ("%.1f"):format(shown) },
                { L.TIP_OVERALL, ("%.1f"):format(S.Number(overall)) },
            },
        }
    end,
})

-- Attributes -----------------------------------------------------------------------------------

local ATTRIBUTES = {
    { "strength", 1, "Spell_Nature_Strength" },
    { "agility", 2, "Ability_Rogue_QuickRecovery" },
    { "stamina", 3, "Spell_Holy_WordFortitude" },
    { "intellect", 4, "Spell_Holy_MagicalSentry" },
    { "spirit", 5, "Spell_Holy_DivineSpirit" },
}
for _, attribute in ipairs(ATTRIBUTES) do
    local id, index = attribute[1], attribute[2]
    add({
        id = id,
        cat = "attributes",
        icon = ICON .. attribute[3],
        label = function()
            local name = _G["SPELL_STAT" .. index .. "_NAME"]
            return type(name) == "string" and name or L[id]
        end,
        get = function()
            local _, effective, pos, neg = S.Call(UnitStat, "player", index)
            if effective == nil then
                error(MISSING, 0)
            end
            return S.Modded(effective, pos, neg)
        end,
        raw = function()
            -- "55 (+10 -3)" needs the modifiers compared with zero: not while they're secret.
            if Core.Opt("values.showMods") then
                return nil
            end
            return S.RawInt((select(2, UnitStat("player", index))))
        end,
    })
end

-- Melee and ranged -----------------------------------------------------------------------------

local function damageText(low, high)
    return L.TIP_RANGE:format(
        S.Int(math.max(1, math.floor(S.Number(low)))),
        S.Int(math.max(1, math.ceil(S.Number(high))))
    )
end

add({
    id = "meleeDamage",
    cat = "melee",
    label = function()
        return L.damage
    end,
    icon = ICON .. "INV_Sword_04",
    get = function()
        local low, high, offLow, offHigh, pos, neg = S.Call(UnitDamage, "player")
        if S.Number(high) == 0 then
            return { text = "0", zero = true }
        end
        local lines = { { L.TIP_MAIN, damageText(low, high) } }
        if S.Number(offHigh) > 0 then
            lines[#lines + 1] = { L.TIP_OFF, damageText(offLow, offHigh) }
        end
        return { text = damageText(low, high), mood = S.Mood(pos, neg), lines = lines }
    end,
})

add({
    id = "meleeSpeed",
    cat = "melee",
    label = function()
        return L.speed
    end,
    icon = ICON .. "Ability_Warrior_Revenge",
    get = function()
        local main, off = S.Call(UnitAttackSpeed, "player")
        main, off = S.Number(main), S.Number(off)
        local text = off > 0 and ("%.2f / %.2f"):format(main, off) or ("%.2f"):format(main)
        return { text = text, zero = main == 0 }
    end,
})

add({
    id = "meleeDps",
    cat = "melee",
    label = function()
        return L.dps
    end,
    icon = ICON .. "Ability_DualWield",
    get = function()
        local low, high, offLow, offHigh = S.Call(UnitDamage, "player")
        local main, off = S.Call(UnitAttackSpeed, "player")
        main, off = S.Number(main), S.Number(off)
        if main == 0 then
            return { text = "0", zero = true }
        end
        local mainDps = (S.Number(low) + S.Number(high)) / 2 / main
        local offDps = off > 0 and (S.Number(offLow) + S.Number(offHigh)) / 2 / off or 0
        local lines = { { L.TIP_MAIN, ("%.1f"):format(mainDps) } }
        if offDps > 0 then
            lines[#lines + 1] = { L.TIP_OFF, ("%.1f"):format(offDps) }
        end
        return { text = ("%.1f"):format(mainDps + offDps), lines = lines }
    end,
})

local function attackPower(fn)
    return function()
        local base, pos, neg = S.Call(fn, "player")
        local total = S.Number(base) + S.Number(pos) + S.Number(neg)
        local result = S.Modded(total, pos, neg)
        result.lines[#result.lines + 1] = { L.TIP_DPS_BONUS, ("%.1f"):format(math.max(0, total) / 14) }
        return result
    end
end

add({
    id = "meleeAttackPower",
    cat = "melee",
    label = function()
        return L.attackPower
    end,
    icon = ICON .. "Ability_Warrior_BattleShout",
    get = attackPower(UnitAttackPower),
})

add({
    id = "meleeHit",
    cat = "melee",
    label = function()
        return L.hit
    end,
    icon = ICON .. "Ability_Marksmanship",
    get = function()
        local rating = S.Number(S.Maybe(GetCombatRatingBonus, CR.HIT_MELEE))
        local gear = S.Number(S.Maybe(GetHitModifier))
        local result = percent(rating + gear, CR.HIT_MELEE)
        result.lines[#result.lines + 1] = { L.TIP_FROM_GEAR, S.Pct(gear) }
        return result
    end,
})

add({
    id = "meleeCrit",
    cat = "melee",
    label = function()
        return L.crit
    end,
    icon = ICON .. "Ability_CriticalStrike",
    get = function()
        return percent(S.Call(GetCritChance), CR.CRIT_MELEE)
    end,
    raw = S.RawRated(function()
        return GetCritChance()
    end, CR.CRIT_MELEE),
})

add({
    id = "meleeHaste",
    cat = "melee",
    label = function()
        return L.haste
    end,
    icon = ICON .. "Spell_Nature_BloodLust",
    get = function()
        return percent(S.Call(GetMeleeHaste), CR.HASTE_MELEE)
    end,
    raw = S.RawRated(function()
        return GetMeleeHaste()
    end, CR.HASTE_MELEE),
})

add({
    id = "expertise",
    cat = "melee",
    icon = ICON .. "INV_Sword_27",
    get = function()
        local main, off = S.Call(GetExpertise)
        main, off = S.Number(main), S.Number(off)
        local text = (off > 0 and off ~= main) and ("%s / %s"):format(S.Int(main), S.Int(off)) or S.Int(main)
        return { text = text, zero = main == 0 and off == 0, lines = S.RatingLine({}, CR.EXPERTISE) }
    end,
})

add({
    id = "armorPen",
    cat = "melee",
    icon = ICON .. "Ability_Warrior_Sunder",
    get = function()
        return percent(S.Call(GetArmorPenetration), CR.ARMOR_PENETRATION)
    end,
    raw = S.RawRated(function()
        return GetArmorPenetration()
    end, CR.ARMOR_PENETRATION),
})

add({
    id = "rangedDamage",
    cat = "ranged",
    label = function()
        return L.damage
    end,
    icon = ICON .. "INV_Weapon_Bow_02",
    get = function()
        local speed, low, high, pos, neg = S.Call(UnitRangedDamage, "player")
        if S.Number(speed) == 0 then
            return { text = "0", zero = true }
        end
        return { text = damageText(low, high), mood = S.Mood(pos, neg) }
    end,
})

add({
    id = "rangedSpeed",
    cat = "ranged",
    label = function()
        return L.speed
    end,
    icon = ICON .. "Ability_Hunter_RunningShot",
    get = function()
        local speed = S.Number((S.Call(UnitRangedDamage, "player")))
        return { text = ("%.2f"):format(speed), zero = speed == 0 }
    end,
})

add({
    id = "rangedDps",
    cat = "ranged",
    label = function()
        return L.dps
    end,
    icon = ICON .. "Ability_Hunter_SteadyShot",
    get = function()
        local speed, low, high = S.Call(UnitRangedDamage, "player")
        speed = S.Number(speed)
        if speed == 0 then
            return { text = "0", zero = true }
        end
        return { text = ("%.1f"):format((S.Number(low) + S.Number(high)) / 2 / speed) }
    end,
})

add({
    id = "rangedAttackPower",
    cat = "ranged",
    label = function()
        return L.attackPower
    end,
    icon = ICON .. "Ability_TrueShot",
    get = attackPower(UnitRangedAttackPower),
})

add({
    id = "rangedHit",
    cat = "ranged",
    label = function()
        return L.hit
    end,
    icon = ICON .. "Ability_Hunter_SniperShot",
    get = function()
        local rating = S.Number(S.Maybe(GetCombatRatingBonus, CR.HIT_RANGED))
        local gear = S.Number(S.Maybe(GetRangedHitModifier) or S.Maybe(GetHitModifier))
        local result = percent(rating + gear, CR.HIT_RANGED)
        result.lines[#result.lines + 1] = { L.TIP_FROM_GEAR, S.Pct(gear) }
        return result
    end,
})

add({
    id = "rangedCrit",
    cat = "ranged",
    label = function()
        return L.crit
    end,
    icon = ICON .. "Ability_Hunter_CriticalShot",
    get = function()
        return percent(S.Call(GetRangedCritChance), CR.CRIT_RANGED)
    end,
    raw = S.RawRated(function()
        return GetRangedCritChance()
    end, CR.CRIT_RANGED),
})

add({
    id = "rangedHaste",
    cat = "ranged",
    label = function()
        return L.haste
    end,
    icon = ICON .. "Ability_Hunter_RapidKilling",
    get = function()
        local haste, quiver = S.Call(GetRangedHaste)
        return percent(S.Number(haste) + S.Number(quiver), CR.HASTE_RANGED)
    end,
})

-- Spell ----------------------------------------------------------------------------------------

local SCHOOLS = {
    { "holy", 2, "Spell_Holy_HolyBolt" },
    { "fire", 3, "Spell_Fire_FlameBolt" },
    { "nature", 4, "Spell_Nature_StarFall" },
    { "frost", 5, "Spell_Frost_FrostBolt02" },
    { "shadow", 6, "Spell_Shadow_ShadowBolt" },
    { "arcane", 7, "Spell_Nature_StarFall" },
}
Values.SCHOOLS = SCHOOLS

add({
    id = "spellPower",
    cat = "spell",
    icon = ICON .. "Spell_Holy_MagicalSentry",
    applies = function()
        return Core.Opt("values.spellSchool") ~= "each"
    end,
    get = function()
        local lowest, highest
        local lines = { L.TIP_SCHOOLS }
        for _, school in ipairs(SCHOOLS) do
            local value = S.Number(S.Call(GetSpellBonusDamage, school[2]))
            lowest = lowest and math.min(lowest, value) or value
            highest = highest and math.max(highest, value) or value
            lines[#lines + 1] = { L[school[1]], S.Int(value) }
        end
        local shown = Core.Opt("values.spellSchool") == "lowest" and lowest or highest
        return { text = S.Int(shown), zero = S.Number(highest) == 0, lines = lines }
    end,
})

for _, school in ipairs(SCHOOLS) do
    local id, index = school[1], school[2]
    add({
        id = "spellPower_" .. id,
        cat = "spell",
        icon = ICON .. school[3],
        label = function()
            return ("%s (%s)"):format(L.spellPower, L[id])
        end,
        applies = function()
            return Core.Opt("values.spellSchool") == "each"
        end,
        get = function()
            local value = S.Number(S.Call(GetSpellBonusDamage, index))
            return { text = S.Int(value), zero = value == 0 }
        end,
        raw = function()
            return S.RawInt(GetSpellBonusDamage(index))
        end,
    })
end

add({
    id = "healing",
    cat = "spell",
    icon = ICON .. "Spell_Holy_FlashHeal",
    get = function()
        local value = S.Number(S.Call(GetSpellBonusHealing))
        return { text = S.Int(value), zero = value == 0 }
    end,
    raw = function()
        return S.RawInt(GetSpellBonusHealing())
    end,
})

add({
    id = "spellHit",
    cat = "spell",
    label = function()
        return L.hit
    end,
    icon = ICON .. "Spell_Arcane_ArcaneResilience",
    get = function()
        local rating = S.Number(S.Maybe(GetCombatRatingBonus, CR.HIT_SPELL))
        local gear = S.Number(S.Maybe(GetSpellHitModifier))
        local result = percent(rating + gear, CR.HIT_SPELL)
        result.lines[#result.lines + 1] = { L.TIP_FROM_GEAR, S.Pct(gear) }
        return result
    end,
})

local function spellCrit()
    -- Forever takes no school; a client that needs one (Retail) errors and gets the holy school.
    -- No comparison on the value: it can be secret.
    local ok, value = pcall(GetSpellCritChance)
    if ok then
        return value
    end
    return GetSpellCritChance(2)
end

add({
    id = "spellCrit",
    cat = "spell",
    label = function()
        return L.crit
    end,
    icon = ICON .. "Spell_Fire_SoulBurn",
    get = function()
        return percent(S.Call(spellCrit), CR.CRIT_SPELL)
    end,
    raw = S.RawRated(spellCrit, CR.CRIT_SPELL),
})

add({
    id = "spellHaste",
    cat = "spell",
    label = function()
        return L.haste
    end,
    icon = ICON .. "Spell_Nature_Lightning",
    get = function()
        return percent(S.Call(UnitSpellHaste, "player"), CR.HASTE_SPELL)
    end,
    raw = S.RawRated(function()
        return UnitSpellHaste("player")
    end, CR.HASTE_SPELL),
})

add({
    id = "spellPen",
    cat = "spell",
    icon = ICON .. "Spell_Shadow_ShadowWordPain",
    get = function()
        local value = S.Number(S.Call(GetSpellPenetration))
        return { text = S.Int(value), zero = value == 0 }
    end,
    raw = function()
        return S.RawInt(GetSpellPenetration())
    end,
})

add({
    id = "mp5",
    cat = "spell",
    icon = ICON .. "Spell_Magic_ManaGain",
    get = function()
        local base, casting = S.Call(GetManaRegen)
        base, casting = S.Number(base) * 5, S.Number(casting) * 5
        return {
            text = S.Int(casting),
            zero = base == 0 and casting == 0,
            lines = {
                { L.TIP_NOT_CASTING, ("%s %s"):format(S.Int(base), L.TIP_PER_5) },
                { L.TIP_CASTING, ("%s %s"):format(S.Int(casting), L.TIP_PER_5) },
            },
        }
    end,
})

-- Defense --------------------------------------------------------------------------------------

add({
    id = "armor",
    cat = "defense",
    icon = ICON .. "INV_Shield_06",
    get = function()
        local _, effective, _, bonus = S.Call(UnitArmor, "player")
        effective = S.Number(effective)
        local lines = {}
        local effectiveness = C_PaperDollInfo and S.Maybe(C_PaperDollInfo.GetArmorEffectiveness, effective, level())
        if type(effectiveness) == "number" then
            lines[1] = { L.TIP_REDUCTION, S.Pct(effectiveness * 100) }
        end
        local bonusValue = S.Number(bonus)
        return {
            text = S.Int(effective),
            mood = bonusValue > 0 and "buff" or bonusValue < 0 and "debuff" or nil,
            zero = effective == 0,
            lines = lines,
        }
    end,
    raw = function()
        return S.RawInt((select(2, UnitArmor("player"))))
    end,
})

add({
    id = "defenseSkill",
    cat = "defense",
    icon = ICON .. "Ability_Defend",
    get = function()
        local base, modifier = S.Call(UnitDefenseSkill, "player")
        local total = S.Number(base) + S.Number(modifier)
        local cap = level() * 5
        local lines = { { L.TIP_CAP, S.Int(cap) } }
        if total > cap then
            lines[2] = { L.TIP_ABOVE_CAP, "-" .. S.Pct((total - cap) * 0.04) }
        end
        local result = S.Modded(total, math.max(0, S.Number(modifier)), math.min(0, S.Number(modifier)), lines)
        result.zero = total == 0
        return result
    end,
})

local function chance(fn, index)
    return function()
        return percent(S.Call(fn), index)
    end
end

local function rawChance(fn, index)
    return S.RawRated(function()
        return fn()
    end, index)
end

add({
    id = "dodge",
    cat = "defense",
    icon = ICON .. "Spell_Nature_Invisibilty",
    get = chance(GetDodgeChance, CR.DODGE),
    raw = rawChance(GetDodgeChance, CR.DODGE),
})
add({
    id = "parry",
    cat = "defense",
    icon = ICON .. "Ability_Parry",
    get = chance(GetParryChance, CR.PARRY),
    raw = rawChance(GetParryChance, CR.PARRY),
})
add({
    id = "block",
    cat = "defense",
    icon = ICON .. "Ability_Defend",
    get = chance(GetBlockChance, CR.BLOCK),
    raw = rawChance(GetBlockChance, CR.BLOCK),
})

-- Total avoidance: the chance a melee attack from a mob of your level misses, is dodged or is
-- parried, shown without and with block. Miss is 5% plus 0.04% per defense point above the cap.
-- A sum of values: no raw reader, it shows its last value while they're secret.
add({
    id = "totalAvoidance",
    cat = "defense",
    icon = ICON .. "Ability_Rogue_Feint",
    get = function()
        local base, modifier = S.Maybe(UnitDefenseSkill, "player")
        local miss = 5
        if base ~= nil then
            local defense = S.Number(base) + S.Number(modifier)
            miss = math.max(0, 5 + (defense - level() * 5) * 0.04)
        end
        local dodge = S.Number(S.Call(GetDodgeChance))
        local parry = S.Number(S.Maybe(GetParryChance))
        local block = S.Number(S.Maybe(GetBlockChance))
        local total = miss + dodge + parry
        -- "without block / with block".
        return {
            text = ("%s / %s"):format(S.Pct(total), S.Pct(total + block)),
            zero = total == 0 and block == 0,
            lines = {
                { L.TIP_MISS, S.Pct(miss) },
                { L.dodge, S.Pct(dodge) },
                { L.parry, S.Pct(parry) },
                { L.block, S.Pct(block) },
                { L.TIP_WITHOUT_BLOCK, S.Pct(total) },
                { L.TIP_WITH_BLOCK, S.Pct(total + block) },
            },
        }
    end,
})

add({
    id = "blockValue",
    cat = "defense",
    icon = ICON .. "INV_Shield_05",
    get = function()
        local shield = C_PaperDollInfo and S.Maybe(C_PaperDollInfo.OffhandHasShield)
        local value = S.Number(S.Call(GetShieldBlock))
        return { text = S.Int(value), zero = value == 0 or shield == false }
    end,
    raw = function()
        return S.RawInt(GetShieldBlock())
    end,
})

add({
    id = "resilience",
    cat = "defense",
    icon = ICON .. "INV_Jewelry_Necklace_13",
    get = function()
        local rating = S.Number(S.Call(GetCombatRating, CR.RESILIENCE))
        return { text = S.Int(rating), zero = rating == 0 }
    end,
    raw = function()
        return S.RawInt(GetCombatRating(CR.RESILIENCE))
    end,
})

-- Resistances ----------------------------------------------------------------------------------

local function damageClass(name, fallback)
    local enum = Enum and Enum.Damageclass
    return enum and type(enum[name]) == "number" and enum[name] or fallback
end

local RESISTANCES = {
    { "arcane", "Arcane", 6 },
    { "fire", "Fire", 2 },
    { "frost", "Frost", 4 },
    { "nature", "Nature", 3 },
    { "shadow", "Shadow", 5 },
}
for _, resistance in ipairs(RESISTANCES) do
    local id, class = resistance[1], damageClass(resistance[2], resistance[3])
    add({
        id = "resist_" .. id,
        cat = "resistances",
        atlas = "UI-Character-Info-Resistance-" .. resistance[2],
        label = function()
            return L[id]
        end,
        get = function()
            local _, _, effective, bonus = S.Call(UnitResistance, "player", class)
            effective = S.Number(effective)
            local average = math.min(75, effective / math.max(1, level() * 5) * 75)
            local bonusValue = S.Number(bonus)
            return {
                text = S.Int(effective),
                mood = bonusValue > 0 and "buff" or bonusValue < 0 and "debuff" or nil,
                zero = effective == 0,
                lines = { { L.TIP_RESIST, S.Pct(average) } },
            }
        end,
        raw = function()
            return S.RawInt((select(3, UnitResistance("player", class))))
        end,
    })
end

-- Enhancements ---------------------------------------------------------------------------------

add({
    id = "mastery",
    cat = "enhancements",
    icon = ICON .. "Spell_Holy_ChampionsBond",
    get = function()
        local effect = S.Number((S.Call(GetMasteryEffect)))
        return percent(effect, CR.MASTERY)
    end,
    raw = S.RawRated(function()
        return GetMasteryEffect()
    end, CR.MASTERY),
})

add({
    id = "versatility",
    cat = "enhancements",
    icon = ICON .. "Spell_Holy_HolyGuidance",
    get = function()
        local done = S.Number(S.Maybe(GetCombatRatingBonus, CR.VERSATILITY))
            + S.Number(S.Maybe(GetVersatilityBonus, CR.VERSATILITY))
        local taken = S.Number(S.Maybe(GetCombatRatingBonus, CR.VERSATILITY_TAKEN))
            + S.Number(S.Maybe(GetVersatilityBonus, CR.VERSATILITY_TAKEN))
        local result = percent(done, CR.VERSATILITY)
        result.lines[#result.lines + 1] = { L.TIP_DAMAGE_DONE, S.Pct(done) }
        result.lines[#result.lines + 1] = { L.TIP_DAMAGE_TAKEN, "-" .. S.Pct(taken) }
        return result
    end,
})

add({
    id = "lifesteal",
    cat = "enhancements",
    icon = ICON .. "Spell_Shadow_LifeDrain02",
    get = chance(GetLifesteal, CR.LIFESTEAL),
    raw = rawChance(GetLifesteal, CR.LIFESTEAL),
})
add({
    id = "avoidance",
    cat = "enhancements",
    icon = ICON .. "Spell_Nature_Invisibilty",
    get = chance(GetAvoidance, CR.AVOIDANCE),
    raw = rawChance(GetAvoidance, CR.AVOIDANCE),
})
add({
    id = "bonusSpeed",
    cat = "enhancements",
    icon = ICON .. "Ability_Rogue_Sprint",
    get = chance(GetSpeed, CR.SPEED),
    raw = rawChance(GetSpeed, CR.SPEED),
})
