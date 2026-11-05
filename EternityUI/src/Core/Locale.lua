-- The core's texts: enUS plus esES. A missing esES text falls back to enUS.
---@type string, EternityUINamespace
local _, ns = ...

local enUS = {
    LOADED = "Eternity %s. Type /et to open the options.",
    HELP = "/et · /et move · /et status · /et diag · /et pixel",
    OPTIONS_MISSING = "The options window could not load. Check that Eternity Options is enabled.",
    STATUS = "Eternity %s · profile %s · %d logins, %d reloads",
    MODULE_LINE = "  %s: %s",
    MODULE_ON = "on",
    MODULE_OFF = "off",
    MODULE_RELOAD = "off after /reload",
    NO_MODULES = "  No modules yet",
    DIAG_TITLE = "Eternity diagnostics",
    PIXEL_TITLE = "1 pixel test",
    PIXEL_HINT = "All four lines should look thin and even. /et pixel closes this.",
    YES = "yes",
    NO = "no",
}

local esES = {
    LOADED = "Eternity %s. Escribe /et para abrir las opciones.",
    OPTIONS_MISSING = "No se pudo cargar la ventana de opciones. Comprueba que Eternity Options esté activado.",
    STATUS = "Eternity %s · perfil %s · %d inicios, %d recargas",
    MODULE_ON = "activo",
    MODULE_OFF = "apagado",
    MODULE_RELOAD = "se apaga con /reload",
    NO_MODULES = "  Aún no hay módulos",
    DIAG_TITLE = "Diagnóstico de Eternity",
    PIXEL_TITLE = "Prueba de 1 píxel",
    PIXEL_HINT = "Las cuatro líneas deben verse finas y uniformes. /et pixel la cierra.",
    YES = "sí",
    NO = "no",
}

--- A text table for this client: esES where it has the text, otherwise enUS.
---@param english table<string, string>
---@param spanish table<string, string>
---@return table<string, string>
function EternityUI.NewLocale(english, spanish)
    local locale = GetLocale()
    local active = (locale == "esES" or locale == "esMX") and spanish or {}
    return setmetatable({}, {
        __index = function(_, key)
            return active[key] or english[key] or key
        end,
    })
end

ns.L = EternityUI.NewLocale(enUS, esES)
