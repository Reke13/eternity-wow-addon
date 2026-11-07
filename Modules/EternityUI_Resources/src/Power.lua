-- Secret-safe power reads. On Forever UnitPower, UnitPowerMax, UnitPowerPercent and GetComboPoints
-- can be secret (SecretWhenUnitPowerRestricted in the API docs), the way the player's health is:
-- Lua can't compare them or do math on them. So a value here is only ever handed to something that
-- takes secrets (StatusBar:SetValue and SetMinMaxValues, SetFormattedText, AbbreviateNumbers,
-- SetAlpha, a curve through UnitPowerPercent). Plain math is the fallback for clients (and the
-- emulator) without those APIs. UnitPowerType isn't secret, so which resource is shown (and so the
-- druid's forms) is always known.

---@type string, EternityUIResourcesNamespace
local addonName, ns = ...
local E = EternityUI
local Secret, Theme = E.Secret, E.Theme

local function enum(name, fallback)
    return Enum and Enum.PowerType and Enum.PowerType[name] or fallback
end

local TYPES = {
    Mana = enum("Mana", 0),
    Rage = enum("Rage", 1),
    Focus = enum("Focus", 2),
    Energy = enum("Energy", 3),
    ComboPoints = enum("ComboPoints", 4),
    RunicPower = enum("RunicPower", 6),
}
-- Option key of each power type's color.
local COLOR_KEYS = {
    [TYPES.Mana] = "mana",
    [TYPES.Rage] = "rage",
    [TYPES.Focus] = "focus",
    [TYPES.Energy] = "energy",
}
-- Power that rests when empty (it builds up in combat); the rest rests when full.
local RESTS_EMPTY = { [TYPES.Rage] = true, [TYPES.RunicPower] = true }
local DEFAULT_COMBO = 5

---@class EternityUIResourcesPower
local Power = { TYPES = TYPES, RESTS_EMPTY = RESTS_EMPTY }
ns.Power = Power

local function opt(path)
    return E.store:Get(addonName, path)
end

local function known(value)
    return Secret.Is(value) or value ~= nil
end

--- The player's class token ("DRUID"...).
---@return string?
function Power.Class()
    local _, class = UnitClass("player")
    return Secret.Plain(class, nil)
end

--- The power the player uses now and its token. A Druid's changes with the form.
---@return number powerType
---@return string? token
function Power.Current()
    local powerType, token = UnitPowerType("player")
    powerType = Secret.Plain(powerType, nil)
    if type(powerType) ~= "number" then
        return TYPES.Mana, "MANA"
    end
    return powerType, Secret.Plain(token, nil)
end

--- Current and maximum of a power; either may be secret.
---@param powerType number
---@return any current
---@return any max
function Power.Values(powerType)
    return UnitPower("player", powerType), UnitPowerMax("player", powerType)
end

--- Plain fraction 0..1, or nil if a value is secret or the maximum is 0.
local function fraction(powerType)
    local current, max = Power.Values(powerType)
    current, max = Secret.Plain(current, nil), Secret.Plain(max, nil)
    if type(current) == "number" and type(max) == "number" and max > 0 then
        return math.max(0, math.min(1, current / max))
    end
    return nil
end
Power.Fraction = fraction

--- Percent 0..100: secret through UnitPowerPercent, plain otherwise, nil if unknown.
---@param powerType number
---@return any
function Power.Percent(powerType)
    if UnitPowerPercent and CurveConstants and CurveConstants.ScaleTo100 then
        local ok, value = pcall(UnitPowerPercent, "player", powerType, false, CurveConstants.ScaleTo100)
        if ok and known(value) then
            return value
        end
    end
    local f = fraction(powerType)
    return f and f * 100 or nil
end

--- A number as short text ("12.4K"), secret-safe.
---@param value any
---@return any
function Power.Abbreviate(value)
    if not known(value) then
        return nil
    end
    if AbbreviateNumbers then
        local ok, text = pcall(AbbreviateNumbers, value)
        if ok then
            return text
        end
    end
    value = Secret.Plain(value, nil)
    if type(value) ~= "number" then
        return nil
    end
    if value >= 1e6 then
        return ("%.1fM"):format(value / 1e6)
    elseif value >= 1e4 then
        return ("%.1fK"):format(value / 1e3)
    end
    return tostring(math.floor(value + 0.5))
end

--- Writes a power's text in a format ("current", "currentMax", "percent", "currentPercent",
--- "none"). Secret pieces go to SetFormattedText untouched.
---@param text table FontString
---@param mode string
---@param powerType number
function Power.SetText(text, mode, powerType)
    if mode == "none" then
        text:SetText("")
        return
    end
    local current, max = Power.Values(powerType)
    local short = Power.Abbreviate(current)
    if mode == "currentMax" then
        local shortMax = Power.Abbreviate(max)
        if short and shortMax then
            text:SetFormattedText("%s / %s", short, shortMax)
            return
        end
    elseif mode == "percent" or mode == "currentPercent" then
        local percent = Power.Percent(powerType)
        if percent and mode == "percent" then
            text:SetFormattedText("%.0f%%", percent)
            return
        elseif percent and short then
            text:SetFormattedText("%s  %.0f%%", short, percent)
            return
        end
    end
    if short then
        text:SetFormattedText("%s", short)
    else
        text:SetText("")
    end
end

-- Opacity at rest -------------------------------------------------------------------------------

local curves = {}

-- A step curve from the power's fraction to an opacity: full opacity, and alpha at the resting end.
local function restCurve(restsEmpty, alpha)
    local key = (restsEmpty and "empty" or "full") .. alpha
    if curves[key] ~= nil then
        return curves[key] or nil
    end
    local curve = false
    if C_CurveUtil and C_CurveUtil.CreateCurve then
        curve = C_CurveUtil.CreateCurve()
        if Enum and Enum.LuaCurveType then
            curve:SetType(Enum.LuaCurveType.Step)
        end
        if restsEmpty then
            -- Any rage at all (1 of 100 is 0.01) is above the step.
            curve:AddPoint(0, alpha)
            curve:AddPoint(0.001, 1)
        else
            curve:AddPoint(0, 1)
            curve:AddPoint(1, alpha)
        end
    end
    curves[key] = curve
    return curve or nil
end

--- The opacity of a bar for its power: alpha when at rest, 1 otherwise. It may be secret (it goes
--- straight to SetAlpha); 1 when nothing can be read.
---@param powerType number
---@param alpha number
---@return any
function Power.RestAlpha(powerType, alpha)
    local restsEmpty = RESTS_EMPTY[powerType] or false
    local curve = restCurve(restsEmpty, alpha)
    if curve and UnitPowerPercent then
        local ok, value = pcall(UnitPowerPercent, "player", powerType, false, curve)
        if ok and known(value) then
            return value
        end
    end
    local f = fraction(powerType)
    if f == nil then
        return 1
    end
    local resting = restsEmpty and f <= 0 or (not restsEmpty and f >= 1)
    return resting and alpha or 1
end

-- Combo points ----------------------------------------------------------------------------------

--- Whether the player has combo points now: Rogues always, Druids in Cat Form (on energy).
---@return boolean
function Power.UsesCombo()
    local class = Power.Class()
    if class == "ROGUE" then
        return true
    end
    return class == "DRUID" and (Power.Current()) == TYPES.Energy
end

--- How many combo points fit (plain; 5 if it can't be read).
---@return number
function Power.ComboMax()
    local max = Secret.Plain(UnitPowerMax("player", TYPES.ComboPoints), nil)
    if type(max) == "number" and max > 0 then
        return math.min(max, 10)
    end
    return DEFAULT_COMBO
end

--- The player's combo points, kept on the target as Forever does; may be secret.
---@return any
function Power.ComboPoints()
    if GetComboPoints then
        local ok, points = pcall(GetComboPoints, "player", "target")
        if ok and known(points) then
            return points
        end
    end
    local points = UnitPower("player", TYPES.ComboPoints)
    return known(points) and points or 0
end

-- Colors ----------------------------------------------------------------------------------------

local function blizzardColor(powerType, token)
    local colors = PowerBarColor
    local color = colors and ((token and colors[token]) or colors[powerType])
    if type(color) == "table" and color.r then
        return { color.r, color.g, color.b, 1 }
    end
    return nil
end

--- A power's color: Blizzard's when that option is on (and it has one), the option's otherwise.
---@param powerType number
---@param token string?
---@param key string? color option to use instead of the power's own
---@return table { r, g, b, a }
function Power.Color(powerType, token, key)
    if opt("colors.blizzard") then
        local color = blizzardColor(powerType, token)
        if color then
            return color
        end
    end
    return Theme.RGBA(opt("colors." .. (key or COLOR_KEYS[powerType] or "other")))
end
