-- EternityUI_Auras texts (enUS and esES), and the two frames the module has. The options' texts
-- live in options.json.

---The module's private table.
---@class EternityUIAurasNamespace
---@field OptionsSchema table schema generated from options.json (src/Generated/Options.lua)
---@field L table<string, string>
---@field opt fun(path: string): any
---@field KINDS EternityUIAurasKind[]
---@field Filters EternityUIAurasFilters
---@field Spells EternityUIAurasSpells
---@field SpellsTab EternityUIAurasSpellsTab
---@field Frame table the frame class (Frame.lua)

---@type string, EternityUIAurasNamespace
local addonName, ns = ...

--- An option of this module ("group.option").
---@param path string
---@return any
function ns.opt(path)
    return EternityUI.store:Get(addonName, path)
end

local strings = {
    enUS = {
        TITLE = "Auras",
        GENERAL = "General",
        TARGET = "Target",
        PLAYER = "Character",
        TARGET_FRAME = "Target's debuffs",
        PLAYER_FRAME = "My buffs",
        NO_CONTAINER = "Auras: this client has no aura container, the frames can't be shown.",
        IDS_TITLE = "Debuffs of %s:",
        IDS_TITLE_PLAYER = "Your buffs:",
        IDS_LINE = "  %s: %d",
        IDS_NONE = "%s has no debuffs.",
        IDS_NONE_PLAYER = "You have no buffs.",
        IDS_NO_TARGET = "Target something first (or /etauras me for your buffs).",
        IDS_SECRET = "In combat the game hides which spell each aura is: try again out of combat.",
        TAB = "Spells",
        SPELLS_INTRO_TARGET = "Spells shown first in the target's frame: Always, whoever cast them, or Only mine, when you (or your pet) cast them; someone else's isn't shown then. They're matched by spell ID, also in combat, on enemies' debuffs. Switch one off to keep it without using it.",
        SPELLS_INTRO_PLAYER = "Buffs shown first in your frame: Always, whoever cast them on you, or Only mine, when you (or your pet) cast them; someone else's isn't shown then. They're matched by spell ID, also in combat. Switch one off to keep it without using it.",
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
        FROM_PLAYER = "From me",
        FROM_SECRET = "In combat the game hides which spell each one is",
        FROM_TARGET_NONE = "The target has no debuffs",
        FROM_PLAYER_NONE = "You have no buffs",
        FROM_TARGET_NO_TARGET = "Target something first",
        PLACE_FRAME = "Place the frames",
        ADDED = "%d added",
        ALREADY = "%d already in the list",
        NOT_IDS = "not spell IDs: %s",
        NO_SPELLS_TARGET = "No spells yet: type an ID above or pick one from the target.",
        NO_SPELLS_PLAYER = "No spells yet: type an ID above or pick one of your buffs.",
        FRAME_OFF = "This frame is switched off: turn on \"Show this frame\" in General > %s.",
        REMOVE = "Remove",
        MODE_ALWAYS = "Always",
        MODE_MINE = "Only mine",
        UNKNOWN_SPELL = "Unknown spell",
        SPELL_ID_N = "ID %d",
    },
    esES = {
        TITLE = "Auras",
        GENERAL = "General",
        TARGET = "Objetivo",
        PLAYER = "Personaje",
        TARGET_FRAME = "Perjuicios del objetivo",
        PLAYER_FRAME = "Mis bufos",
        NO_CONTAINER = "Auras: este cliente no tiene contenedor de auras, los marcos no se pueden mostrar.",
        IDS_TITLE = "Perjuicios de %s:",
        IDS_TITLE_PLAYER = "Tus bufos:",
        IDS_LINE = "  %s: %d",
        IDS_NONE = "%s no tiene perjuicios.",
        IDS_NONE_PLAYER = "No tienes bufos.",
        IDS_NO_TARGET = "Selecciona un objetivo primero (o /etauras yo para tus bufos).",
        IDS_SECRET = "En combate el juego oculta qué hechizo es cada aura: prueba fuera de combate.",
        TAB = "Hechizos",
        SPELLS_INTRO_TARGET = "Hechizos que salen los primeros en el marco del objetivo: Siempre, los ponga quien los ponga, o Solo míos, cuando los pones tú (o tu mascota); entonces el de otro no sale. Se reconocen por su número de hechizo, también en combate, en los perjuicios de los enemigos. Desactiva uno para guardarlo sin usarlo.",
        SPELLS_INTRO_PLAYER = "Bufos que salen los primeros en tu marco: Siempre, te los ponga quien te los ponga, o Solo míos, cuando los pones tú (o tu mascota); entonces el de otro no sale. Se reconocen por su número de hechizo, también en combate. Desactiva uno para guardarlo sin usarlo.",
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
        FROM_PLAYER = "De mí",
        FROM_SECRET = "En combate el juego oculta qué hechizo es cada uno",
        FROM_TARGET_NONE = "El objetivo no tiene perjuicios",
        FROM_PLAYER_NONE = "No tienes bufos",
        FROM_TARGET_NO_TARGET = "Selecciona un objetivo primero",
        PLACE_FRAME = "Colocar los marcos",
        ADDED = "%d añadidos",
        ALREADY = "%d ya estaban en la lista",
        NOT_IDS = "no son números de hechizo: %s",
        NO_SPELLS_TARGET = "Aún no hay hechizos: escribe un número arriba o elige uno del objetivo.",
        NO_SPELLS_PLAYER = "Aún no hay hechizos: escribe un número arriba o elige uno de tus bufos.",
        FRAME_OFF = "Este marco está desactivado: activa «Mostrar este marco» en General > %s.",
        REMOVE = "Quitar",
        MODE_ALWAYS = "Siempre",
        MODE_MINE = "Solo míos",
        UNKNOWN_SPELL = "Hechizo desconocido",
        SPELL_ID_N = "Número %d",
    },
}
local L = EternityUI.NewLocale(strings.enUS, strings.esES)
ns.L = L

---@class EternityUIAurasKind
---@field key string "target" or "player": the options' group prefix and the list's key
---@field unit string
---@field filter string "HARMFUL" or "HELPFUL"
---@field label string
---@field frameLabel string the Mover's label
---@field frameName string
---@field y number default place, below the screen's center

--- The module's frames, in order.
ns.KINDS = {
    { key = "target", unit = "target", filter = "HARMFUL", label = L.TARGET, frameLabel = L.TARGET_FRAME, frameName = "EternityUIAurasTarget", y = -140 },
    { key = "player", unit = "player", filter = "HELPFUL", label = L.PLAYER, frameLabel = L.PLAYER_FRAME, frameName = "EternityUIAurasPlayer", y = -220 },
}
