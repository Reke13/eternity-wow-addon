-- EternityUI_Resources texts (enUS and esES). The options' texts live in options.json.

---The module's private table.
---@class EternityUIResourcesNamespace
---@field OptionsSchema table schema generated from options.json (src/Generated/Options.lua)
---@field L table<string, string>
---@field UI table
---@field Power EternityUIResourcesPower
---@field Bar EternityUIResourcesBar
---@field Pips EternityUIResourcesPips
---@field Display EternityUIResourcesDisplay
---@field Module table

---@type string, EternityUIResourcesNamespace
local _, ns = ...

ns.L = EternityUI.NewLocale({
    TITLE = "Resources",
    MOVER_POWER = "Resources: main bar",
    MOVER_COMBO = "Resources: combo points",
    MOVER_MANA = "Resources: druid's mana",
}, {
    TITLE = "Recursos",
    MOVER_POWER = "Recursos: barra principal",
    MOVER_COMBO = "Recursos: puntos de combo",
    MOVER_MANA = "Recursos: maná del druida",
})
