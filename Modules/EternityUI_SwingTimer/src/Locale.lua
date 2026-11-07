-- EternityUI_SwingTimer texts (enUS and esES). The options' texts live in options.json.

---The module's private table.
---@class EternityUISwingTimerNamespace
---@field OptionsSchema table schema generated from options.json (src/Generated/Options.lua)
---@field L table<string, string>
---@field UI table
---@field Bar EternityUISwingTimerBar
---@field Swing EternityUISwingTimerSwing
---@field Module table

---@type string, EternityUISwingTimerNamespace
local _, ns = ...

ns.L = EternityUI.NewLocale({
    TITLE = "Swing timer",
    MAIN_HAND = "Main hand",
    OFF_HAND = "Off hand",
    RANGED = "Ranged",
    MOVER_MAIN_HAND = "Swing timer: main hand",
    MOVER_OFF_HAND = "Swing timer: off hand",
    MOVER_RANGED = "Swing timer: ranged",
}, {
    TITLE = "Temporizador de golpe",
    MAIN_HAND = "Mano principal",
    OFF_HAND = "Mano secundaria",
    RANGED = "A distancia",
    MOVER_MAIN_HAND = "Temporizador de golpe: mano principal",
    MOVER_OFF_HAND = "Temporizador de golpe: mano secundaria",
    MOVER_RANGED = "Temporizador de golpe: a distancia",
})
