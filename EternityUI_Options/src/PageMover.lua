-- Mover: the button that enters the mode and the mode's settings.
---@type string, table
local _, ns = ...
local L = ns.L
local E = EternityUI
local Widgets = E.Widgets

local CORE = "EternityUI"
local controls = {}

local function setter(id)
    return function(value)
        E.store:Set(CORE, "mover." .. id, value)
    end
end

local function pixels(value)
    return string.format("%d", math.floor(value + 0.5))
end

local function build(frame)
    local enter = Widgets.Button(frame, L.MOVER_ENTER, "primary", function()
        ns.MoverSession.Toggle()
    end)
    enter:SetPoint("TOPLEFT")

    controls.grid = Widgets.Toggle(frame, setter("grid"))
    controls.gridSize = Widgets.Slider(frame, 8, 64, 4, pixels, setter("gridSize"))
    controls.snap = Widgets.Toggle(frame, setter("snap"))
    controls.threshold = Widgets.Slider(frame, 1, 16, 1, pixels, setter("threshold"))
    controls.distances = Widgets.Toggle(frame, setter("distances"))
    local rows = {
        { L.MOVER_GRID, controls.grid },
        { L.MOVER_GRID_SIZE, controls.gridSize },
        { L.MOVER_SNAP, controls.snap },
        { L.MOVER_THRESHOLD, controls.threshold },
        { L.MOVER_DISTANCES, controls.distances },
    }
    for i, entry in ipairs(rows) do
        local row = Widgets.Row(frame, entry[1], entry[2])
        row:SetPoint("TOPLEFT", 0, -6 - i * 40)
        row:SetPoint("TOPRIGHT", 0, -6 - i * 40)
    end
end

local function refresh()
    for id, control in pairs(controls) do
        control:SetValue(E.store:Get(CORE, "mover." .. id))
    end
end

ns.Window.AddPage({ key = "mover", title = L.MOVER, note = L.MOVER_NOTE, Build = build, Refresh = refresh })
