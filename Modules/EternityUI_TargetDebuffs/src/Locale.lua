-- EternityUI_TargetDebuffs texts (enUS and esES). The options' texts live in options.json.

---The module's private table.
---@class EternityUITargetDebuffsNamespace
---@field OptionsSchema table schema generated from options.json (src/Generated/Options.lua)
---@field L table<string, string>
---@field opt fun(path: string): any
---@field Filters EternityUITargetDebuffsFilters

---@type string, EternityUITargetDebuffsNamespace
local addonName, ns = ...

--- An option of this module ("group.option").
---@param path string
---@return any
function ns.opt(path)
    return EternityUI.store:Get(addonName, path)
end

local strings = {
    enUS = {
        TITLE = "Target debuffs",
        NO_CONTAINER = "Target debuffs: this client has no aura container, the frame can't be shown.",
        IDS_TITLE = "Debuffs of %s:",
        IDS_LINE = "  %s: %d",
        IDS_NONE = "%s has no debuffs.",
        IDS_NO_TARGET = "Target something first.",
        IDS_SECRET = "In combat the game hides which spell each debuff is: try again out of combat.",
        BAD_IDS = "Target debuffs: these aren't spell IDs and were left out: %s",
    },
    esES = {
        TITLE = "Perjuicios del objetivo",
        NO_CONTAINER = "Perjuicios del objetivo: este cliente no tiene contenedor de auras, el marco no se puede mostrar.",
        IDS_TITLE = "Perjuicios de %s:",
        IDS_LINE = "  %s: %d",
        IDS_NONE = "%s no tiene perjuicios.",
        IDS_NO_TARGET = "Selecciona un objetivo primero.",
        IDS_SECRET = "En combate el juego oculta qué hechizo es cada perjuicio: prueba fuera de combate.",
        BAD_IDS = "Perjuicios del objetivo: esto no son números de hechizo y se han dejado fuera: %s",
    },
}
ns.L = EternityUI.NewLocale(strings.enUS, strings.esES)
