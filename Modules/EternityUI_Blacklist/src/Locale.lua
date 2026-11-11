-- EternityUI_Blacklist texts (enUS and esES). The options' texts live in options.json.

---The module's private table.
---@class EternityUIBlacklistNamespace
---@field OptionsSchema table schema generated from options.json (src/Generated/Options.lua)
---@field L table<string, string>
---@field opt fun(path: string): any
---@field List EternityUIBlacklistList
---@field Editor EternityUIBlacklistEditor
---@field Window EternityUIBlacklistWindow
---@field Warnings EternityUIBlacklistWarnings
---@field Menu EternityUIBlacklistMenu

---@type string, EternityUIBlacklistNamespace
local addonName, ns = ...

--- An option of this module.
---@param path string
---@return any
function ns.opt(path)
    return EternityUI.store:Get(addonName, path)
end

local strings = {
    enUS = {
        TITLE = "Blacklist",
        OPEN = "Open the list",
        ADD = "Add",
        ADD_PLAYER = "Add a player",
        EDIT_PLAYER = "Edit player",
        SAVE = "Save",
        DELETE = "Delete",
        DELETE_CONFIRM = "Sure?",
        NAME = "Name",
        FACTION = "Faction",
        GUILD = "Guild",
        REASON = "Reason",
        UNKNOWN = "Unknown",
        Horde = "Horde",
        Alliance = "Alliance",
        ALL_FACTIONS = "Both factions",
        SEARCH = "Search",
        EMPTY = "Nobody on the list yet.",
        SUMMARY = "%d players",
        NO_GUILD = "No guild",
        LEVEL = "Level %d",
        ADDED = "Added %s by %s",
        SEEN = "Last seen %s",
        SEEN_IN = "Last seen %s in %s",
        DATE_FORMAT = "%Y-%m-%d",
        HINT_EDIT = "Click to edit",
        TOOLTIP = "Blacklist: %s",
        NO_REASON = "no reason given",
        MENU_ADD = "Add to the blacklist",
        MENU_EDIT = "Edit blacklist entry",
        MENU_REMOVE = "Remove from the blacklist",
        WARN_TARGET = "%s is on your blacklist: %s",
        WARN_GROUP = "%s, in your group, is on your blacklist: %s",
        ADDED_MSG = "%s added to the blacklist.",
        REMOVED_MSG = "%s removed from the blacklist.",
        NOT_FOUND = "%s isn't on the blacklist.",
        NEED_NAME = "Target a player or give a name: /bl add Name reason",
        NAME_TAKEN = "%s is already on the list.",
        NAME_EMPTY = "Write a name.",
        HELP = "/bl opens the list · /bl add name reason · /bl add alone edits your target · /bl remove name",
    },
    esES = {
        TITLE = "Lista negra",
        OPEN = "Abrir la lista",
        ADD = "Añadir",
        ADD_PLAYER = "Añadir un jugador",
        EDIT_PLAYER = "Editar jugador",
        SAVE = "Guardar",
        DELETE = "Borrar",
        DELETE_CONFIRM = "¿Seguro?",
        NAME = "Nombre",
        FACTION = "Facción",
        GUILD = "Hermandad",
        REASON = "Motivo",
        UNKNOWN = "Desconocida",
        Horde = "Horda",
        Alliance = "Alianza",
        ALL_FACTIONS = "Ambas facciones",
        SEARCH = "Buscar",
        EMPTY = "Todavía no hay nadie en la lista.",
        SUMMARY = "%d jugadores",
        NO_GUILD = "Sin hermandad",
        LEVEL = "Nivel %d",
        ADDED = "Añadido el %s por %s",
        SEEN = "Visto por última vez el %s",
        SEEN_IN = "Visto por última vez el %s en %s",
        DATE_FORMAT = "%d/%m/%Y",
        HINT_EDIT = "Clic para editar",
        TOOLTIP = "Lista negra: %s",
        NO_REASON = "sin motivo",
        MENU_ADD = "Añadir a la lista negra",
        MENU_EDIT = "Editar en la lista negra",
        MENU_REMOVE = "Quitar de la lista negra",
        WARN_TARGET = "%s está en tu lista negra: %s",
        WARN_GROUP = "%s, en tu grupo, está en tu lista negra: %s",
        ADDED_MSG = "%s añadido a la lista negra.",
        REMOVED_MSG = "%s quitado de la lista negra.",
        NOT_FOUND = "%s no está en la lista negra.",
        NEED_NAME = "Selecciona a un jugador o da un nombre: /bl add Nombre motivo",
        NAME_TAKEN = "%s ya está en la lista.",
        NAME_EMPTY = "Escribe un nombre.",
        HELP = "/bl abre la lista · /bl add nombre motivo · /bl add solo edita tu objetivo · /bl remove nombre",
    },
}
ns.L = EternityUI.NewLocale(strings.enUS, strings.esES)
