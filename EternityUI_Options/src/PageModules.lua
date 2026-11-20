-- Modules: one switch per part of the interface, in a list that scrolls when they don't fit. With
-- the V2 layout (general.optionsVersion) two per line, with a line between the columns.
---@type string, table
local _, ns = ...
local L = ns.L
local E = EternityUI
local Widgets = E.Widgets

local ROW = 40
local COLUMN_GAP = 24

local rows = {}
local scroll, holder, empty, divider

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
    rows[index] = entry
    return entry
end

-- V1: one per line across. V2: two per line in fixed columns.
local function place(count)
    local columns = E.store:Get("EternityUI", "general.optionsVersion") == "v2" and 2 or 1
    local width = holder:GetWidth()
    if width < 100 then
        width = math.max(scroll:GetWidth() - 12, 100) -- not sized yet
    end
    local half = (width - COLUMN_GAP) / 2
    for i = 1, count do
        local frame = rows[i].frame
        frame:ClearAllPoints()
        if columns == 2 then
            local column, line = (i - 1) % 2, math.floor((i - 1) / 2)
            frame:SetPoint("TOPLEFT", column * (half + COLUMN_GAP), -line * ROW)
            frame:SetWidth(half)
        else
            frame:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
            frame:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW)
        end
    end
    local lines = columns == 2 and math.ceil(count / 2) or count
    divider:SetShown(columns == 2 and count > 1)
    divider:ClearAllPoints()
    divider:SetPoint("TOPLEFT", half + COLUMN_GAP / 2, -3)
    divider:SetPoint("BOTTOMLEFT", holder, "TOPLEFT", half + COLUMN_GAP / 2, -(lines * ROW - 3))
    local c = E.Theme.colors.line
    divider:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    scroll:SetContentHeight(lines * ROW + 8)
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
    place(#modules)
end

local function build(frame)
    scroll = Widgets.Scroll(frame)
    scroll:SetAllPoints()
    holder = scroll.child
    divider = holder:CreateTexture(nil, "ARTWORK")
    divider:SetWidth(E.Pixel.Size(holder))
    -- The columns follow the window's width.
    scroll:HookScript("OnSizeChanged", function()
        refresh()
    end)

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
