-- Modules: one switch per part of the interface.
---@type string, table
local _, ns = ...
local L = ns.L
local E = EternityUI
local Widgets = E.Widgets

local rows = {}
local holder, empty

local function row(index)
    if rows[index] then
        return rows[index]
    end
    local entry = {}
    entry.toggle = Widgets.Toggle(holder, function(value)
        E.store:SetModuleEnabled(entry.name, value)
        ns.Window.Refresh()
    end)
    entry.frame = Widgets.Row(holder, "", entry.toggle)
    entry.note = Widgets.Text(entry.frame, 13, "muted")
    entry.note:SetPoint("RIGHT", entry.toggle, "LEFT", -12, 0)
    entry.note:SetText(L.NEEDS_RELOAD)
    entry.frame:SetPoint("TOPLEFT", 0, -(index - 1) * 40)
    entry.frame:SetPoint("TOPRIGHT", 0, -(index - 1) * 40)
    rows[index] = entry
    return entry
end

local function refresh()
    local modules = E:ListModules()
    empty:SetShown(#modules == 0)
    for i, module in ipairs(modules) do
        local entry = row(i)
        entry.name = module.name
        entry.frame.label:SetText(module.name)
        entry.toggle:SetValue(E.store:IsModuleEnabled(module.name))
        entry.note:SetShown(module.reloadPending == true)
    end
end

local function build(frame)
    holder = CreateFrame("Frame", nil, frame)
    holder:SetAllPoints()

    empty = CreateFrame("Frame", nil, frame)
    empty:SetAllPoints()
    local title = Widgets.Text(empty, 17, "text")
    title:SetPoint("TOP", 0, -60)
    title:SetText(L.NO_MODULES)
    local note = Widgets.Text(empty, 15, "muted")
    note:SetPoint("TOP", title, "BOTTOM", 0, -6)
    note:SetText(L.NO_MODULES_NOTE)
end

ns.Window.AddPage({ key = "modules", title = L.MODULES, note = L.MODULES_NOTE, Build = build, Refresh = refresh })
