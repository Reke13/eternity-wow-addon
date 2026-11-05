-- EternityUI_Map texts (enUS and esES). The options' texts live in options.json.

---The module's private table.
---@class EternityUIMapNamespace
---@field OptionsSchema table schema generated from options.json (src/Generated/Options.lua)
---@field L table<string, string>
---@field Core EternityUIMapCore
---@field Overlays table generated from the client's DB2 tables (src/Data/Overlays.lua)
---@field Skin EternityUIMapSkin
---@field Coords EternityUIMapCoords
---@field Window EternityUIMapWindow
---@field Fade EternityUIMapFade
---@field Unexplored EternityUIMapUnexplored
---@field Module table

---@type string, EternityUIMapNamespace
local _, ns = ...

local strings = {
    enUS = {
        TITLE = "Map",
        PLAYER = "Player",
        CURSOR = "Cursor",
        NO_POSITION = "—",
        SCREEN_COORDS = "Map: player coordinates",
        RESET_HINT = "Drag to move · Right-click: Blizzard's spot",
        RESET_DONE = "the map is back in Blizzard's spot.",
        USAGE = "/etmap reset puts the map back in Blizzard's spot.",
    },
    esES = {
        TITLE = "Mapa",
        PLAYER = "Jugador",
        CURSOR = "Cursor",
        NO_POSITION = "—",
        SCREEN_COORDS = "Mapa: coordenadas del jugador",
        RESET_HINT = "Arrastra para mover · Clic derecho: sitio de Blizzard",
        RESET_DONE = "el mapa ha vuelto al sitio de Blizzard.",
        USAGE = "/etmap reset devuelve el mapa al sitio de Blizzard.",
    },
}
ns.L = setmetatable(strings[GetLocale()] or {}, { __index = strings.enUS })
