-- EternityUI_Automation core: the feature registry and the helpers every feature shares (options,
-- pause key, chat report, money text, secret guard). Each feature file adds itself with
-- Core.Add; Automation.lua registers the module and only listens to the events of the features
-- that are switched on.

---@type string, EternityUIAutomationNamespace
local addonName, ns = ...
local E = EternityUI
local Theme = E.Theme

---A single automation.
---@class EternityUIAutomationFeature
---@field id string
---@field events string[] events it listens to while it's on
---@field Enabled fun(self: EternityUIAutomationFeature): boolean whether its options switch it on
---@field OnEvent fun(self: EternityUIAutomationFeature, event: string, ...)?
---@field OnApply fun(self: EternityUIAutomationFeature, on: boolean)? installs hooks (they can't be removed, so they check `on`)
---@field on boolean? set by Automation.lua

---@class EternityUIAutomationCore
---@field features EternityUIAutomationFeature[]
---@field byId table<string, EternityUIAutomationFeature>
---@field running boolean? between OnEnable and OnDisable
local Core = { features = {}, byId = {} }
ns.Core = Core

local MODIFIERS = { shift = "IsShiftKeyDown", ctrl = "IsControlKeyDown", alt = "IsAltKeyDown" }

--- An option of this module ("group.option").
function Core.Opt(path)
    return E.store:Get(addonName, path)
end

--- Whether an option switches something on: true, or a select other than "off".
function Core.On(path)
    local value = Core.Opt(path)
    return value ~= nil and value ~= false and value ~= "off" and value ~= ""
end

---@param feature EternityUIAutomationFeature
function Core.Add(feature)
    feature.events = feature.events or {}
    Core.features[#Core.features + 1] = feature
    Core.byId[feature.id] = feature
    return feature
end

--- Whether the pause key is held down.
function Core.Paused()
    local held = _G[MODIFIERS[Core.Opt("control.pauseModifier")] or ""]
    return held ~= nil and held() or false
end

--- Whether a hooked feature should act now (hooks stay after the feature is switched off).
---@param feature EternityUIAutomationFeature
function Core.Active(feature)
    return Core.running == true and feature.on == true and not Core.Paused()
end

--- Whether a value is a secret one (Forever and Retail hide some event arguments in combat).
function Core.Secret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

--- Text for an amount of copper with the coin icons.
function Core.Money(copper)
    return C_CurrencyInfo.GetCoinTextureString(copper)
end

--- Color option ("#RRGGBB[AA]" or a theme color like "@accentText") as a chat color code.
function Core.ColorCode(hex)
    local r, g, b = Theme.Color(hex)
    return string.format(
        "|cff%02X%02X%02X",
        math.floor(r * 255 + 0.5),
        math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5)
    )
end

--- Builds the chat line of a report (nil when reports are off). Split out for the tests.
function Core.FormatReport(text)
    if not Core.Opt("messages.report") then
        return nil
    end
    local prefix = Core.Opt("messages.prefix") and "Eternity: " or ""
    return Core.ColorCode(Core.Opt("messages.color")) .. prefix .. text .. "|r"
end

--- Says in chat what an automation did, when reports are on.
function Core.Report(fmt, ...)
    local line = Core.FormatReport(select("#", ...) > 0 and fmt:format(...) or fmt)
    if line then
        print(line)
    end
end

--- C_Timer.After that does nothing once the module has been disabled.
function Core.After(seconds, fn)
    C_Timer.After(seconds, function()
        if Core.running then
            fn()
        end
    end)
end

--- A name to show for a unit or a sender that may be nil or secret.
function Core.Name(name)
    if name == nil or Core.Secret(name) or name == "" then
        return ns.L.SOMEONE
    end
    return name
end
