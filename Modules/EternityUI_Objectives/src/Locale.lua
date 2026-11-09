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
---@field Position EternityUIObjectivesPosition
---@field ZoneFilter EternityUIObjectivesZoneFilter
---@field Ui table

---@type string, EternityUIObjectivesNamespace
local _, ns = ...

local strings = {
    enUS = {
        ZONE = "Zone",
        LEVEL = "Level",
        READY = "Ready to turn in: %s",
        MOVER = "Quests",
        ZONE_ONLY = "This zone only",
        ZONE_ONLY_OFF = "Click to track only the quests of the zone you're in.",
        ZONE_ONLY_ON = "On: only this zone's quests, following you from zone to zone. Click to get yours back.",
    },
    esES = {
        ZONE = "Zona",
        LEVEL = "Nivel",
        READY = "Lista para entregar: %s",
        MOVER = "Misiones",
        ZONE_ONLY = "Solo esta zona",
        ZONE_ONLY_OFF = "Haz clic para seguir solo las misiones de la zona en la que estás.",
        ZONE_ONLY_ON = "Activo: solo las misiones de esta zona, y cambia contigo de zona. Haz clic para recuperar las tuyas.",
    },
}
ns.L = setmetatable(strings[GetLocale()] or {}, { __index = strings.enUS })
