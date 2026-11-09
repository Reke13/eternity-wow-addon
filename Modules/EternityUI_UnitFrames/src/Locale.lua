-- EternityUI_UnitFrames texts (enUS and esES) and the list of frames. The options' texts live in
-- options.json.

---The module's private table.
---@class EternityUIUnitFramesNamespace
---@field OptionsSchema table schema generated from options.json (src/Generated/Options.lua)
---@field L table<string, string>
---@field UNITS EternityUIUnitFramesUnit[]
---@field ByKey table<string, EternityUIUnitFramesUnit>
---@field Style EternityUIUnitFramesStyle
---@field AuraBox EternityUIUnitFramesAuraBox
---@field Elements EternityUIUnitFramesElements
---@field Filters EternityUIUnitFramesFilters
---@field FiltersTab EternityUIUnitFramesFiltersTab
---@field Preview EternityUIUnitFramesPreview
---@field Frame EternityUIUnitFramesFrame
---@field Groups EternityUIUnitFramesGroups
---@field Blizzard EternityUIUnitFramesBlizzard

---@type string, EternityUIUnitFramesNamespace
local _, ns = ...

ns.L = EternityUI.NewLocale({
    GENERAL = "General",
    PLAYER = "You",
    PET = "Pet",
    TARGET = "Target",
    TARGETTARGET = "Target of target",
    FOCUS = "Focus",
    PARTY = "Group",
    RAID = "Raid",
    GROUP_PETS = "Group pets",
    MOVER = "Unit frames: %s",
    DEAD = "Dead",
    GHOST = "Ghost",
    OFFLINE = "Offline",
    LEVEL_UNKNOWN = "??",
    COMBAT_WAIT = "Unit frames: the changes are applied when you leave combat.",
    FILTERS = "Filters",
    FILTER_DEFAULT = "New filter",
    FILTER_PICK = "Filter: %s",
    FILTER_NEW = "New filter",
    FILTER_MADE = "Made \"%s\".",
    FILTER_DELETE = "Delete",
    FILTER_DELETE_SURE = "Sure? Click again",
    FILTER_DELETED = "Deleted \"%s\".",
    FILTER_NAME = "Filter name",
    FILTER_RENAME = "Rename",
    FILTER_APPLY = "Apply to these frames:",
    FILTER_INTRO = "Its buffs show first on those frames. With \"Only the ones of the filters\" (each frame's Buffs) they're all you see. \"Always\": whoever cast it; \"Only mine\": when you cast it. Works on buffs of friendly units: you, your group and raid.",
    FILTER_EXAMPLE = "Type spell IDs (1243, 21562) or a name (Power Word: Fortitude) and press Enter. Shift-clicking a spell while the box has the cursor puts its ID in.",
    FILTER_EMPTY = "No spells yet.",
    NO_FILTERS = "You have no filters. Make one with \"New filter\", add spells to it and pick the frames it applies to.",
    NO_FILTERS_SHORT = "No filters",
    SPELL_ID = "Spell ID or name",
    ADD = "Add",
    FROM_ME = "From my buffs",
    FROM_TARGET = "From my target's",
    FROM_SECRET = "Buffs can't be read in combat",
    FROM_NONE = "No buffs",
    FROM_NO_TARGET = "No target",
    ADDED = "%d added",
    ALREADY = "%d already there",
    ADDED_NAME = "Looking for every \"%s\"...",
    ALREADY_NAME = "\"%s\" is already there",
    REMOVE = "Remove",
    SEARCH_AGAIN = "Search again",
    MODE_ALWAYS = "Always",
    MODE_MINE = "Only mine",
    SEARCHING = "Searching... %d found",
    NONE_FOUND = "None found with that name",
    BY_NAME = "By name: %s",
    MORE = "(+%d)",
    UNKNOWN_SPELL = "Unknown spell",
    SPELL_ID_N = "ID %d",
    PROGRESS = "Looking for \"%s\": %d%%",
    PREVIEW_SHOW = "Show preview",
    PREVIEW_HIDE = "Hide preview",
    PREVIEW_HINT = "A window beside the options with the picked frame as your options draw it.",
    PREVIEW_TITLE = "Preview: %s",
    PREVIEW_NOTE = "You (or your target) on single frames, a made-up group on the group and raid. Auras, icons and the cast are examples.",
    PREVIEW_CAST = "Fireball",
}, {
    GENERAL = "General",
    PLAYER = "Tú",
    PET = "Mascota",
    TARGET = "Objetivo",
    TARGETTARGET = "Objetivo del objetivo",
    FOCUS = "Foco",
    PARTY = "Grupo",
    RAID = "Banda",
    GROUP_PETS = "Mascotas del grupo",
    MOVER = "Marcos de unidad: %s",
    DEAD = "Muerto",
    GHOST = "Fantasma",
    OFFLINE = "Desconectado",
    LEVEL_UNKNOWN = "??",
    COMBAT_WAIT = "Marcos de unidad: los cambios se aplican al salir de combate.",
    FILTERS = "Filtros",
    FILTER_DEFAULT = "Filtro nuevo",
    FILTER_PICK = "Filtro: %s",
    FILTER_NEW = "Nuevo filtro",
    FILTER_MADE = "Creado «%s».",
    FILTER_DELETE = "Borrar",
    FILTER_DELETE_SURE = "¿Seguro? Pulsa otra vez",
    FILTER_DELETED = "Borrado «%s».",
    FILTER_NAME = "Nombre del filtro",
    FILTER_RENAME = "Cambiar nombre",
    FILTER_APPLY = "Aplicar a estos marcos:",
    FILTER_INTRO = "Sus bufos salen primero en esos marcos. Con «Solo los de los filtros» (en Bufos de cada marco) son los únicos que ves. «Siempre»: los ponga quien los ponga; «Solo míos»: cuando los pones tú. Funciona en bufos de unidades amistosas: tú, tu grupo y tu banda.",
    FILTER_EXAMPLE = "Escribe números de hechizo (1243, 21562) o un nombre (Palabra de poder: entereza) y pulsa Intro. Con mayús+clic en un hechizo mientras la casilla tiene el cursor se pone su número.",
    FILTER_EMPTY = "Aún no hay habilidades.",
    NO_FILTERS = "No tienes filtros. Crea uno con «Nuevo filtro», añádele habilidades y elige los marcos a los que se aplica.",
    NO_FILTERS_SHORT = "Sin filtros",
    SPELL_ID = "Número o nombre del hechizo",
    ADD = "Añadir",
    FROM_ME = "De mis bufos",
    FROM_TARGET = "De los de mi objetivo",
    FROM_SECRET = "En combate no se pueden leer los bufos",
    FROM_NONE = "Sin bufos",
    FROM_NO_TARGET = "Sin objetivo",
    ADDED = "%d añadidos",
    ALREADY = "%d ya estaban",
    ADDED_NAME = "Buscando todos los «%s»...",
    ALREADY_NAME = "«%s» ya está",
    REMOVE = "Quitar",
    SEARCH_AGAIN = "Buscar otra vez",
    MODE_ALWAYS = "Siempre",
    MODE_MINE = "Solo míos",
    SEARCHING = "Buscando... %d encontrados",
    NONE_FOUND = "No se encontró ninguno con ese nombre",
    BY_NAME = "Por nombre: %s",
    MORE = "(+%d)",
    UNKNOWN_SPELL = "Hechizo desconocido",
    SPELL_ID_N = "ID %d",
    PROGRESS = "Buscando «%s»: %d%%",
    PREVIEW_SHOW = "Ver vista previa",
    PREVIEW_HIDE = "Ocultar vista previa",
    PREVIEW_HINT = "Una ventana junto a las opciones con el marco elegido tal como lo dibujan tus opciones.",
    PREVIEW_TITLE = "Vista previa: %s",
    PREVIEW_NOTE = "Tú (o tu objetivo) en los marcos individuales, un grupo inventado en grupo y banda. Auras, iconos y lanzamiento son de ejemplo.",
    PREVIEW_CAST = "Bola de fuego",
})

local L = ns.L

---@class EternityUIUnitFramesUnit
---@field key string option group and Mover key
---@field unit string unit token (party and raid: the first one, for previews)
---@field label string
---@field group boolean? party or raid: a secure group header
---@field poll boolean? its unit has no events of its own (target of target): updated on a timer
---@field cast boolean? can have a cast bar
---@field player boolean? the player's frame (combat, resting, fade)
---@field range boolean? faded out of range (group frames)
---@field pets boolean? the group's and raid's pets (SecureGroupPetHeaderTemplate)
---@field x number default position
---@field y number

ns.UNITS = {
    { key = "player", unit = "player", label = L.PLAYER, cast = true, player = true, x = -260, y = -180 },
    { key = "pet", unit = "pet", label = L.PET, cast = true, x = -310, y = -235 },
    { key = "target", unit = "target", label = L.TARGET, cast = true, x = 260, y = -180 },
    { key = "targettarget", unit = "targettarget", label = L.TARGETTARGET, poll = true, x = 310, y = -235 },
    { key = "focus", unit = "focus", label = L.FOCUS, cast = true, x = -480, y = 40 },
    { key = "party", unit = "party1", label = L.PARTY, group = true, range = true, x = -760, y = 120 },
    { key = "raid", unit = "raid1", label = L.RAID, group = true, range = true, x = -760, y = 260 },
    { key = "grouppets", unit = "partypet1", label = L.GROUP_PETS, group = true, pets = true, range = true, x = -560, y = 120 },
}
ns.ByKey = {}
for _, def in ipairs(ns.UNITS) do
    ns.ByKey[def.key] = def
end
