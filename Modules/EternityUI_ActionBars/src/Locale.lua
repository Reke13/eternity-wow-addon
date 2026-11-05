-- Eternity_ActionBars texts (enUS and esES). The options' texts live in options.json.

---The module's private table.
---@class EternityUIActionBarsNamespace
---@field OptionsSchema table schema generated from options.json (src/Generated/Options.lua)
---@field L table<string, string>
---@field Style EternityUIActionBarsStyle
---@field Paging EternityUIActionBarsPaging
---@field Icons EternityUIActionBarsIcons
---@field Bars EternityUIActionBarsBars
---@field Sources table<string, EternityUIActionBarsSource>
---@field Blizzard EternityUIActionBarsBlizzard
---@field Keybind EternityUIActionBarsKeybind
---@field Mover EternityUIActionBarsMover
---@field Module table

---@type string, EternityUIActionBarsNamespace
local _, ns = ...

local strings = {
    enUS = {
        TAB = "Bars",
        SHORT_STANCE = "Stance",
        SHORT_PET = "Pet",
        SHORT_MICRO = "Menu",
        SHORT_BAGS = "Bags",
        SHORT_TOTEM = "Totems",
        SHORT_EXTRA = "Extra",
        QUEUED = "Changes will apply after combat.",
        SLASH_HELP = "/etbars: move the bars · /kb: bind keys by hovering · /etbars options: open the options",
        KEYS_TITLE = "Key bindings",
        KEYS_HELP = "Hover a button and press a key, a mouse button or the wheel. Escape clears the button's keys.",
        KEYS_HINT = "Press a key to bind it, Escape to clear.",
        KEYS_NONE = "Not bound",
        KEYS_SAVE = "Save",
        KEYS_DISCARD = "Discard",
        KEYS_COMBAT = "|cff8b5cf6Eternity Action Bars|r: key bindings can't be changed in combat.",
    },
    esES = {
        TAB = "Barras",
        SHORT_STANCE = "Postura",
        SHORT_PET = "Mascota",
        SHORT_MICRO = "Menú",
        SHORT_BAGS = "Bolsas",
        SHORT_TOTEM = "Tótems",
        SHORT_EXTRA = "Extra",
        QUEUED = "Los cambios se aplicarán al salir de combate.",
        SLASH_HELP = "/etbars: mueve las barras · /kb: asigna teclas pasando el ratón · /etbars options: abre las opciones",
        KEYS_TITLE = "Atajos de teclado",
        KEYS_HELP = "Pasa el ratón por un botón y pulsa una tecla, un botón del ratón o la rueda. Escape borra las teclas del botón.",
        KEYS_HINT = "Pulsa una tecla para asignarla, Escape para borrar.",
        KEYS_NONE = "Sin asignar",
        KEYS_SAVE = "Guardar",
        KEYS_DISCARD = "Descartar",
        KEYS_COMBAT = "|cff8b5cf6Eternity Action Bars|r: los atajos no se pueden cambiar en combate.",
    },
}
ns.L = EternityUI.NewLocale(strings.enUS, strings.esES)
