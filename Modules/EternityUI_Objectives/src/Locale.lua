-- EternityUI_Objectives texts (enUS and esES). The options' texts live in options.json.

---The module's private table.
---@class EternityUIObjectivesNamespace
---@field OptionsSchema table schema generated from options.json (src/Generated/Options.lua)
---@field L table<string, string>
---@field Core EternityUIObjectivesCore
---@field Skin EternityUIObjectivesSkin
---@field Fade EternityUIObjectivesFade
---@field Feedback EternityUIObjectivesFeedback
---@field Sections EternityUIObjectivesSections

---@type string, EternityUIObjectivesNamespace
local _, ns = ...

local strings = {
    enUS = {
        ZONE = "Zone",
        LEVEL = "Level",
        READY = "Ready to turn in: %s",
    },
    esES = {
        ZONE = "Zona",
        LEVEL = "Nivel",
        READY = "Lista para entregar: %s",
    },
}
ns.L = setmetatable(strings[GetLocale()] or {}, { __index = strings.enUS })
