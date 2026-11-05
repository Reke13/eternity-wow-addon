-- EternityUI_Experience texts (enUS and esES). The options' texts live in options.json.

---The module's private table.
---@class EternityUIExperienceNamespace
---@field OptionsSchema table schema generated from options.json (src/Generated/Options.lua)
---@field L table<string, string>
---@field Data EternityUIExperienceData
---@field Bar EternityUIExperienceBar
---@field Charts EternityUIExperienceCharts
---@field Module table

---@type string, EternityUIExperienceNamespace
local _, ns = ...

local strings = {
    enUS = {
        TAB = "Charts",
        LEVEL = "Level %d",
        MAX_LEVEL = "Max level",
        XP = "Experience",
        PERCENT = "Progress",
        REMAINING = "Left to level",
        RESTED = "Rested",
        RESTED_NONE = "None",
        RESTING = "Resting",
        QUESTS_DONE = "Completed quests",
        QUESTS_ALL = "Whole quest log",
        PROJECTED_DONE = "Level after turning in",
        PROJECTED_ALL = "Level after the whole log",
        SESSION = "This session",
        GAINED = "XP gained",
        RATE = "XP per hour",
        ETA = "Time to level",
        KILLS = "Kills to level",
        LAST_KILL = "Last kill",
        TIME_LEVEL = "Time at this level",
        PLAYED = "Played",
        UNKNOWN = "—",
        HINT = "Click for options · /et move to move it",
        CHART_SESSION = "XP this session",
        CHART_SESSION_HINT = "XP gained in each bar's minutes. The rate window and minutes per bar are in General.",
        CHART_LEVELS = "Time per level",
        CHART_LEVELS_HINT = "Time spent online at each level by this character, since the module was installed.",
        CHART_SOURCES = "XP by source",
        CHART_SOURCES_HINT = 'Where each level\'s XP came from. "Other" covers exploration, gathering and bonuses.',
        SOURCE_KILL = "Kills",
        SOURCE_QUEST = "Quests",
        SOURCE_OTHER = "Other",
        NO_DATA = "No data yet: keep playing.",
        RESET = "Clear history",
        RESET_CONFIRM = "Click again to clear",
        RESET_HINT = "Clears this character's level history.",
    },
    esES = {
        TAB = "Gráficas",
        LEVEL = "Nivel %d",
        MAX_LEVEL = "Nivel máximo",
        XP = "Experiencia",
        PERCENT = "Progreso",
        REMAINING = "Falta para subir",
        RESTED = "Descanso",
        RESTED_NONE = "Ninguno",
        RESTING = "Descansando",
        QUESTS_DONE = "Misiones completadas",
        QUESTS_ALL = "Todo el registro",
        PROJECTED_DONE = "Nivel al entregarlas",
        PROJECTED_ALL = "Nivel con todo el registro",
        SESSION = "Esta sesión",
        GAINED = "XP ganada",
        RATE = "XP por hora",
        ETA = "Tiempo hasta subir",
        KILLS = "Muertes hasta subir",
        LAST_KILL = "Última muerte",
        TIME_LEVEL = "Tiempo en este nivel",
        PLAYED = "Jugado",
        UNKNOWN = "—",
        HINT = "Clic para las opciones · /et move para moverla",
        CHART_SESSION = "XP de esta sesión",
        CHART_SESSION_HINT = "XP ganada en los minutos de cada barra. La ventana de XP/hora y los minutos por barra están en General.",
        CHART_LEVELS = "Tiempo por nivel",
        CHART_LEVELS_HINT = "Tiempo conectado en cada nivel con este personaje, desde que se instaló el módulo.",
        CHART_SOURCES = "XP por origen",
        CHART_SOURCES_HINT = 'De dónde salió la XP de cada nivel. "Otros" incluye exploración, recolección y bonificaciones.',
        SOURCE_KILL = "Muertes",
        SOURCE_QUEST = "Misiones",
        SOURCE_OTHER = "Otros",
        NO_DATA = "Aún no hay datos: sigue jugando.",
        RESET = "Borrar el historial",
        RESET_CONFIRM = "Pulsa otra vez para borrar",
        RESET_HINT = "Borra el historial de niveles de este personaje.",
    },
}
ns.L = EternityUI.NewLocale(strings.enUS, strings.esES)
