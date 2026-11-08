-- EternityUI_Bugs texts (enUS and esES). The options' texts live in options.json.

---The module's private table.
---@class EternityUIBugsNamespace
---@field OptionsSchema table schema generated from options.json (src/Generated/Options.lua)
---@field L table<string, string>
---@field opt fun(path: string): any
---@field Recorder EternityUIBugsRecorder
---@field List EternityUIBugsList

---@type string, EternityUIBugsNamespace
local addonName, ns = ...

--- An option of this module.
---@param path string
---@return any
function ns.opt(path)
    return EternityUI.store:Get(addonName, path)
end

local strings = {
    enUS = {
        TAB = "Errors",
        SEARCH = "Search",
        EMPTY = "No errors. All good.",
        NOTHING_SELECTED = "Pick an error on the left.",
        SESSION_current = "This session",
        SESSION_previous = "Last session",
        SESSION_all = "All sessions",
        KIND_error = "Error",
        KIND_warning = "Warning",
        KIND_blocked = "Blocked action",
        SUMMARY = "%d errors · %d this session",
        COPY = "Select all",
        COPY_HINT = "Selects the text: copy it with Ctrl+C",
        DELETE = "Delete",
        CLEAR = "Clear all",
        CLEAR_CONFIRM = "Sure?",
        DATE = "Date",
        COUNT = "Times",
        SESSION = "Session",
        STACK = "Stack",
        LOCALS = "Locals",
        SECRET = "<secret value: the game doesn't let addons read it>",
        BLOCKED = "%s tried to call the protected function %s",
        BLOCKED_FORBIDDEN = "%s was forbidden from calling %s",
        UNKNOWN_ADDON = "An addon",
        NEW = "|cffff5f5fEternity|r: new error caught (%s). /etbugs to see it.",
        AGAIN = "|cffff5f5fEternity|r: the error happened again (x%d). /etbugs to see it.",
    },
    esES = {
        TAB = "Errores",
        SEARCH = "Buscar",
        EMPTY = "No hay errores. Todo bien.",
        NOTHING_SELECTED = "Elige un error a la izquierda.",
        SESSION_current = "Esta sesión",
        SESSION_previous = "Sesión anterior",
        SESSION_all = "Todas las sesiones",
        KIND_error = "Error",
        KIND_warning = "Aviso",
        KIND_blocked = "Acción bloqueada",
        SUMMARY = "%d errores · %d en esta sesión",
        COPY = "Seleccionar todo",
        COPY_HINT = "Selecciona el texto: cópialo con Ctrl+C",
        DELETE = "Borrar",
        CLEAR = "Borrar todo",
        CLEAR_CONFIRM = "¿Seguro?",
        DATE = "Fecha",
        COUNT = "Veces",
        SESSION = "Sesión",
        STACK = "Pila",
        LOCALS = "Variables locales",
        SECRET = "<valor secreto: el juego no deja leerlo a los addons>",
        BLOCKED = "%s intentó llamar a la función protegida %s",
        BLOCKED_FORBIDDEN = "%s tenía prohibido llamar a %s",
        UNKNOWN_ADDON = "Un addon",
        NEW = "|cffff5f5fEternity|r: nuevo error capturado (%s). /etbugs para verlo.",
        AGAIN = "|cffff5f5fEternity|r: el error se ha repetido (x%d). /etbugs para verlo.",
    },
}
ns.L = EternityUI.NewLocale(strings.enUS, strings.esES)
