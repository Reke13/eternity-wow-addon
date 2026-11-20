-- EternityUI_Minimal texts (enUS and esES). The options' texts live in options.json.

---The module's private table.
---@class EternityUIMinimalNamespace
---@field OptionsSchema table schema generated from options.json (src/Generated/Options.lua)
---@field L table<string, string>
---@field Parts table the parts that can be hidden (Parts.lua)
---@field Hiding table hides and shows frames (Hiding.lua)
---@field Button table the eye on screen (Button.lua)
---@field PartsTab table the Parts tab of the options (PartsTab.lua)
---@field Module table

---@type string, EternityUIMinimalNamespace
local _, ns = ...

ns.L = EternityUI.NewLocale({
    TITLE = "Minimal",
    MOVER = "Minimal: button",
    TAB = "Parts",
    TAB_HINT = "Pick what hides. Eternity's parts are the ones the Mover knows. Action bars and unit frames turn invisible but still take clicks: the game doesn't let addons hide them in combat. The chat comes back while you type. Frames of other addons not listed here go in the Other frames option.",
    ETERNITY = "Eternity",
    BLIZZARD = "Blizzard",
    ADDONS = "Other addons",
    NO_PARTS = "No Eternity parts yet: enable some modules.",
    HIDDEN = "Interface hidden.",
    SHOWN = "Interface shown.",
    NOTHING = "Nothing picked to hide: choose the parts in the options (right-click the eye).",
    TIP_HIDE = "Click: hide the picked parts",
    TIP_SHOW = "Click: show the hidden parts",
    TIP_OPTIONS = "Right-click: options",
    BAD_KEY = 'Minimal: the key "%s" isn\'t valid.',
    -- Blizzard's parts.
    B_MINIMAP = "Minimap",
    B_TRACKER = "Quest tracker",
    B_BUFFS = "Buffs and debuffs",
    B_CHAT = "Chat",
    B_ACTIONBARS = "Action bars",
    B_PET_STANCE = "Pet and stance bars",
    B_MICRO = "Game menu",
    B_BAGSBAR = "Bag buttons",
    B_XP = "Experience and reputation bars",
    B_PLAYER = "Player frame",
    B_TARGET = "Target and focus frames",
    B_GROUP = "Party and raid frames",
    B_CASTBAR = "Cast bar",
}, {
    TITLE = "Minimalista",
    MOVER = "Minimalista: botón",
    TAB = "Partes",
    TAB_HINT = "Elige qué se oculta. Las partes de Eternity son las que conoce el Mover. Las barras de acción y los marcos de unidad se vuelven invisibles pero siguen recibiendo clics: el juego no deja a los addons ocultarlos en combate. El chat vuelve mientras escribes. Los marcos de otros addons que no salen aquí van en la opción Otros marcos.",
    ETERNITY = "Eternity",
    BLIZZARD = "Blizzard",
    ADDONS = "Otros addons",
    NO_PARTS = "Aún no hay partes de Eternity: activa algún módulo.",
    HIDDEN = "Interfaz oculta.",
    SHOWN = "Interfaz visible.",
    NOTHING = "No has elegido nada que ocultar: elige las partes en las opciones (clic derecho en el ojo).",
    TIP_HIDE = "Clic: oculta las partes elegidas",
    TIP_SHOW = "Clic: muestra las partes ocultas",
    TIP_OPTIONS = "Clic derecho: opciones",
    BAD_KEY = 'Minimalista: la tecla "%s" no es válida.',
    B_MINIMAP = "Minimapa",
    B_TRACKER = "Seguimiento de misiones",
    B_BUFFS = "Beneficios y perjuicios",
    B_CHAT = "Chat",
    B_ACTIONBARS = "Barras de acción",
    B_PET_STANCE = "Barras de mascota y actitud",
    B_MICRO = "Menú del juego",
    B_BAGSBAR = "Botones de bolsas",
    B_XP = "Barras de experiencia y reputación",
    B_PLAYER = "Marco del jugador",
    B_TARGET = "Marcos de objetivo y foco",
    B_GROUP = "Marcos de grupo y banda",
    B_CASTBAR = "Barra de lanzamiento",
})
