-- The core's own options. Same shape as options.json; texts live in the options window.
---@type string, EternityUINamespace
local _, ns = ...

local function values(...)
    local list = {}
    for i = 1, select("#", ...) do
        list[i] = { value = (select(i, ...)) }
    end
    return list
end

ns.CoreOptions = {
    module = "EternityUI",
    groups = {
        {
            id = "general",
            options = {
                { id = "loadMessage", type = "toggle", default = true },
                { id = "minimapEntry", type = "toggle", default = true },
                { id = "optionsScale", type = "range", default = 1, min = 0.7, max = 1.5, step = 0.05 },
                { id = "themeAccent", type = "toggle", default = true },
                { id = "accentColor", type = "color", default = "#8B5CF6" },
                { id = "profileNote", type = "text", default = "", maxLength = 80 },
            },
        },
        {
            id = "mover",
            options = {
                { id = "grid", type = "toggle", default = true },
                { id = "gridSize", type = "range", default = 32, min = 8, max = 64, step = 4 },
                { id = "snap", type = "toggle", default = true },
                { id = "threshold", type = "range", default = 6, min = 1, max = 16, step = 1 },
                { id = "distances", type = "toggle", default = true },
            },
        },
        {
            id = "appearance",
            options = {
                {
                    id = "theme",
                    type = "select",
                    default = "midnight",
                    values = values(
                        "midnight",
                        "obsidian",
                        "azeroth",
                        "horde",
                        "alliance",
                        "holo",
                        "frost",
                        "neon",
                        "nightcity",
                        "void",
                        "graphite",
                        "bubblegum",
                        "sakura",
                        "fuchsia",
                        "cottoncandy",
                        "borahae"
                    ),
                },
                {
                    id = "corners",
                    type = "select",
                    default = "preset",
                    values = values("preset", "round", "soft", "sharp"),
                },
                {
                    id = "style",
                    type = "select",
                    default = "preset",
                    values = values("preset", "glass", "flat", "neon"),
                },
                { id = "opacity", type = "range", default = 0.92, min = 0.6, max = 1, step = 0.02 },
                {
                    id = "font",
                    type = "select",
                    default = "preset",
                    values = values("preset", "arialn", "friz", "morpheus", "skurri"),
                },
                { id = "fontScale", type = "range", default = 1, min = 0.8, max = 1.3, step = 0.05 },
                { id = "pixelPerfect", type = "toggle", default = false },
                { id = "wallpaper", type = "toggle", default = false },
                { id = "wallpaperDim", type = "range", default = 0.6, min = 0.2, max = 0.9, step = 0.05 },
                { id = "portraits", type = "toggle", default = false },
            },
        },
    },
}
