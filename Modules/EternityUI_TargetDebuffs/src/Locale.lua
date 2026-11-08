-- EternityUI_TargetDebuffs texts (enUS and esES). The options' texts live in options.json.

---The module's private table.
---@class EternityUITargetDebuffsNamespace
---@field OptionsSchema table schema generated from options.json (src/Generated/Options.lua)
---@field L table<string, string>
---@field opt fun(path: string): any
---@field Filters EternityUITargetDebuffsFilters
---@field Spells EternityUITargetDebuffsSpells
---@field SpellsTab EternityUITargetDebuffsSpellsTab

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
        TAB = "Spells",
        SPELLS_INTRO = "Spells shown first: Always, whoever cast them, or Only mine, when you (or your pet) cast them; someone else's isn't shown then. They're matched by spell ID, also in combat, on enemies' debuffs. Switch one off to keep it without using it.",
        SPELLS_EXAMPLE = "Type IDs or a spell's name (all its ranks are looked for). With the cursor in the box, shift-click a spell (spellbook, action bar, chat link) to put its ID.",
        SPELL_ID = "Spell ID or name",
        ADDED_NAME = "\"%s\" added: looking for its IDs…",
        ALREADY_NAME = "\"%s\" is already in the list",
        SEARCHING = "By name · looking for its IDs… %d found",
        NONE_FOUND = "By name · no ID found with this name",
        BY_NAME = "By name · %s",
        MORE = "(+%d)",
        SEARCH_AGAIN = "Search again",
        PROGRESS = "Looking for \"%s\" in the game's spells: %d%%",
        ADD = "Add",
        FROM_TARGET = "From the target",
        FROM_TARGET_SECRET = "In combat the game hides which spell each one is",
        FROM_TARGET_NONE = "The target has no debuffs",
        FROM_TARGET_NO_TARGET = "Target something first",
        PLACE_FRAME = "Place the frame",
        ADDED = "%d added",
        ALREADY = "%d already in the list",
        NOT_IDS = "not spell IDs: %s",
        NO_SPELLS = "No spells yet: type an ID above or pick one from the target.",
        REMOVE = "Remove",
        MODE_ALWAYS = "Always",
        MODE_MINE = "Only mine",
        UNKNOWN_SPELL = "Unknown spell",
        SPELL_ID_N = "ID %d",
    },
    esES = {
        TITLE = "Perjuicios del objetivo",
        NO_CONTAINER = "Perjuicios del objetivo: este cliente no tiene contenedor de auras, el marco no se puede mostrar.",
        IDS_TITLE = "Perjuicios de %s:",
        IDS_LINE = "  %s: %d",
        IDS_NONE = "%s no tiene perjuicios.",
        IDS_NO_TARGET = "Selecciona un objetivo primero.",
        IDS_SECRET = "En combate el juego oculta qué hechizo es cada perjuicio: prueba fuera de combate.",
        TAB = "Hechizos",
        SPELLS_INTRO = "Hechizos que salen los primeros: Siempre, los ponga quien los ponga, o Solo míos, cuando los pones tú (o tu mascota); entonces el de otro no sale. Se reconocen por su número de hechizo, también en combate, en los perjuicios de los enemigos. Desactiva uno para guardarlo sin usarlo.",
        SPELLS_EXAMPLE = "Escribe números o el nombre de un hechizo (se buscan todos sus rangos). Con el cursor en la casilla, Mayús-clic en un hechizo (libro de hechizos, barra de acción, enlace del chat) para poner su número.",
        SPELL_ID = "Número o nombre del hechizo",
        ADDED_NAME = "«%s» añadido: buscando sus números…",
        ALREADY_NAME = "«%s» ya está en la lista",
        SEARCHING = "Por nombre · buscando sus números… %d encontrados",
        NONE_FOUND = "Por nombre · ningún número con este nombre",
        BY_NAME = "Por nombre · %s",
        MORE = "(+%d)",
        SEARCH_AGAIN = "Buscar de nuevo",
        PROGRESS = "Buscando «%s» en los hechizos del juego: %d%%",
        ADD = "Añadir",
        FROM_TARGET = "Del objetivo",
        FROM_TARGET_SECRET = "En combate el juego oculta qué hechizo es cada uno",
        FROM_TARGET_NONE = "El objetivo no tiene perjuicios",
        FROM_TARGET_NO_TARGET = "Selecciona un objetivo primero",
        PLACE_FRAME = "Colocar el marco",
        ADDED = "%d añadidos",
        ALREADY = "%d ya estaban en la lista",
        NOT_IDS = "no son números de hechizo: %s",
        NO_SPELLS = "Aún no hay hechizos: escribe un número arriba o elige uno del objetivo.",
        REMOVE = "Quitar",
        MODE_ALWAYS = "Siempre",
        MODE_MINE = "Solo míos",
        UNKNOWN_SPELL = "Hechizo desconocido",
        SPELL_ID_N = "Número %d",
    },
}
ns.L = EternityUI.NewLocale(strings.enUS, strings.esES)
