-- EternityUI_Loot texts (enUS and esES). The options' texts live in options.json.

---The module's private table.
---@class EternityUILootNamespace
---@field OptionsSchema table schema generated from options.json (src/Generated/Options.lua)
---@field L table<string, string>
---@field opt fun(path: string): any
---@field Recorder EternityUILootRecorder
---@field Window EternityUILootWindow
---@field History EternityUILootHistory
---@field Rolls EternityUILootRolls

---@type string, EternityUILootNamespace
local addonName, ns = ...

--- An option of this module.
---@param path string
---@return any
function ns.opt(path)
    return EternityUI.store:Get(addonName, path)
end

local strings = {
    enUS = {
        WINDOW = "Loot window",
        ROLLS = "Group rolls",
        HISTORY = "Loot history",
        OPEN_HISTORY = "Open the history",
        PREVIEW = "Preview the window",
        TAKE_ALL = "Take all",
        HISTORY_SHORT = "History",
        LOOT = "Loot",
        FISHING = "Fishing",
        CONTAINER = "Container",
        OBJECT = "Object",
        SAMPLE_GOLD = "12 Gold, 34 Silver",
        SAMPLE_COMMON = "Linen Cloth",
        SAMPLE_RARE = "Blade of the Sample",
        SAMPLE_EPIC = "Crown of the Preview",
        SEARCH = "Search",
        EMPTY = "Nothing here yet.",
        ALL_KINDS = "Everything",
        KIND_item = "Items",
        KIND_money = "Gold",
        KIND_currency = "Currencies",
        ANY_QUALITY = "Any quality",
        ALL_CHARACTERS = "All characters",
        PERIOD_all = "All time",
        PERIOD_today = "Today",
        PERIOD_week = "7 days",
        PERIOD_month = "30 days",
        SUMMARY = "%d entries",
        SUMMARY_GOLD = "%d entries · %s",
        CLEAR = "Clear",
        CLEAR_CONFIRM = "Sure?",
        DATE_FORMAT = "%Y-%m-%d",
        LOOTED_BY = "%s looted",
        HINT_LINK = "Shift-click to link it",
    },
    esES = {
        WINDOW = "Ventana de botín",
        ROLLS = "Tiradas de grupo",
        HISTORY = "Historial de botín",
        OPEN_HISTORY = "Abrir el historial",
        PREVIEW = "Probar la ventana",
        TAKE_ALL = "Coger todo",
        HISTORY_SHORT = "Historial",
        LOOT = "Botín",
        FISHING = "Pesca",
        CONTAINER = "Contenedor",
        OBJECT = "Objeto",
        SAMPLE_GOLD = "12 de oro, 34 de plata",
        SAMPLE_COMMON = "Paño de lino",
        SAMPLE_RARE = "Hoja de ejemplo",
        SAMPLE_EPIC = "Corona de la prueba",
        SEARCH = "Buscar",
        EMPTY = "Aquí no hay nada todavía.",
        ALL_KINDS = "Todo",
        KIND_item = "Objetos",
        KIND_money = "Oro",
        KIND_currency = "Monedas",
        ANY_QUALITY = "Cualquier calidad",
        ALL_CHARACTERS = "Todos los personajes",
        PERIOD_all = "Todo el tiempo",
        PERIOD_today = "Hoy",
        PERIOD_week = "7 días",
        PERIOD_month = "30 días",
        SUMMARY = "%d entradas",
        SUMMARY_GOLD = "%d entradas · %s",
        CLEAR = "Borrar",
        CLEAR_CONFIRM = "¿Seguro?",
        DATE_FORMAT = "%d/%m/%Y",
        LOOTED_BY = "Lo despojó %s",
        HINT_LINK = "Mayús-clic para enlazarlo",
    },
}
ns.L = EternityUI.NewLocale(strings.enUS, strings.esES)
