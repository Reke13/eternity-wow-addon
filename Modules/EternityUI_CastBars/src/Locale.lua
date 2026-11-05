-- EternityUI_CastBars texts (enUS and esES). The options' texts live in options.json.

---The module's private table.
---@class EternityUICastBarsNamespace
---@field OptionsSchema table schema generated from options.json (src/Generated/Options.lua)
---@field L table<string, string>
---@field Cast EternityUICastBarsCast
---@field Bar EternityUICastBar
---@field Blizzard EternityUICastBarsBlizzard
---@field Timer EternityUICastBarsTimer
---@field Group EternityUICastBarGroup
---@field Gcd EternityUICastBarsGcd
---@field Swing EternityUICastBarsSwing
---@field Mirror EternityUICastBarsMirror
---@field Module table

---@type string, EternityUICastBarsNamespace
local _, ns = ...

local strings = {
    enUS = {
        TAB = "Bars",
        SECTION_BAR = "Bar",
        SECTION_COLORS = "Colors",
        SHORT_PLAYER = "Player",
        SHORT_TARGET = "Target",
        SHORT_FOCUS = "Focus",
        SHORT_PET = "Pet",
        SHORT_BOSS = "Bosses",
        SHORT_ARENA = "Arena",
        SHORT_GCD = "GCD",
        SHORT_SWING = "Swing",
        SHORT_MIRROR = "Breath",
        PLAYER = "Cast bar: player",
        TARGET = "Cast bar: target",
        FOCUS = "Cast bar: focus",
        PET = "Cast bar: pet",
        PREVIEW = "Preview",
        INTERRUPTED = "Interrupted",
        INTERRUPTED_BY = "Interrupted by %s",
        FAILED = "Failed",
        GCD = "Global cooldown",
        SWING = "Swing timer",
        MIRROR = "Breath and fatigue",
        BOSS = "Cast bars: bosses",
        BOSS_N = "Boss %d",
        ARENA = "Cast bars: arena",
        ARENA_N = "Arena %d",
        MAIN_HAND = "Main hand",
        OFF_HAND = "Off hand",
        RANGED = "Ranged",
        BREATH = "Breath",
        FATIGUE = "Fatigue",
        FEIGN = "Feign death",
    },
    esES = {
        TAB = "Barras",
        SECTION_BAR = "Barra",
        SECTION_COLORS = "Colores",
        SHORT_PLAYER = "Jugador",
        SHORT_TARGET = "Objetivo",
        SHORT_FOCUS = "Foco",
        SHORT_PET = "Mascota",
        SHORT_BOSS = "Jefes",
        SHORT_ARENA = "Arena",
        SHORT_GCD = "GCD",
        SHORT_SWING = "Golpe",
        SHORT_MIRROR = "Aliento",
        PLAYER = "Barra de lanzamiento: jugador",
        TARGET = "Barra de lanzamiento: objetivo",
        FOCUS = "Barra de lanzamiento: foco",
        PET = "Barra de lanzamiento: mascota",
        PREVIEW = "Vista previa",
        INTERRUPTED = "Interrumpido",
        INTERRUPTED_BY = "Interrumpido por %s",
        FAILED = "Fallido",
        GCD = "Tiempo de reutilización global",
        SWING = "Temporizador de golpe",
        MIRROR = "Respiración y fatiga",
        BOSS = "Barras de lanzamiento: jefes",
        BOSS_N = "Jefe %d",
        ARENA = "Barras de lanzamiento: arena",
        ARENA_N = "Arena %d",
        MAIN_HAND = "Mano principal",
        OFF_HAND = "Mano secundaria",
        RANGED = "A distancia",
        BREATH = "Respiración",
        FATIGUE = "Fatiga",
        FEIGN = "Fingir muerte",
    },
}
ns.L = EternityUI.NewLocale(strings.enUS, strings.esES)
