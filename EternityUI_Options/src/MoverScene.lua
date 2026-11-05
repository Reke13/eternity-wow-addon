-- What the Mover draws over the screen: the grid, the center axes, snap guides and distances.
-- Textures are pooled: the grid alone is close to a hundred lines.
---@type string, table
local _, ns = ...
local E = EternityUI
local Pixel = E.Pixel
local Theme = E.Theme
local Widgets = E.Widgets

local Scene = {}
ns.MoverScene = Scene

local AXIS_COLOR = { 0.22, 0.74, 0.97, 0.6 }
local GRID_COLOR = { 1, 1, 1, 0.06 }
local root
local gridPool, measurePool = {}, {}
local guides = {}

local function option(id)
    return E.store:Get("EternityUI", "mover." .. id)
end

Scene.option = option

local function line(index, pool, color)
    local texture = pool[index]
    if not texture then
        texture = root:CreateTexture(nil, "BACKGROUND")
        pool[index] = texture
    end
    texture:SetColorTexture(color[1], color[2], color[3], color[4])
    texture:ClearAllPoints()
    texture:Show()
    return texture
end

local function vertical(texture, x)
    texture:SetPoint("TOPLEFT", root, "TOPLEFT", x, 0)
    texture:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", x, 0)
    texture:SetWidth(Pixel.Size(root))
end

local function horizontal(texture, y)
    texture:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, y)
    texture:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, y)
    texture:SetHeight(Pixel.Size(root))
end

-- Lines counted out from the center, so the center is always on the grid.
local function drawGrid()
    local width, height = root:GetSize()
    local used = 0
    if Scene.showGrid then
        local size = option("gridSize")
        for k = -math.floor(width / 2 / size), math.floor(width / 2 / size) do
            used = used + 1
            vertical(line(used, gridPool, k == 0 and AXIS_COLOR or GRID_COLOR), width / 2 + k * size)
        end
        for k = -math.floor(height / 2 / size), math.floor(height / 2 / size) do
            used = used + 1
            horizontal(line(used, gridPool, k == 0 and AXIS_COLOR or GRID_COLOR), height / 2 + k * size)
        end
    end
    for i = used + 1, #gridPool do
        gridPool[i]:Hide()
    end
end

--- Shows the guides of the current snap, or none.
---@param list table[]? { { axis, pos } }
function Scene.SetGuides(list)
    for i = 1, 2 do
        guides[i] = guides[i] or root:CreateTexture(nil, "ARTWORK")
        guides[i]:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        guides[i]:ClearAllPoints()
        local guide = list and list[i]
        guides[i]:SetShown(guide ~= nil)
        if guide then
            if guide.axis == "x" then
                vertical(guides[i], guide.pos)
            else
                horizontal(guides[i], guide.pos)
            end
        end
    end
end

-- A distance from the selected element: a line and its number.
local function drawMeasure(index, measure)
    local item = measurePool[index]
    if not item then
        item = { line = root:CreateTexture(nil, "ARTWORK"), text = Widgets.Text(root, 13, AXIS_COLOR) }
        measurePool[index] = item
    end
    item.line:SetColorTexture(0.22, 0.74, 0.97, 1)
    item.line:ClearAllPoints()
    local size = Pixel.Size(root)
    local middle = (measure.from + measure.to) / 2
    item.text:ClearAllPoints()
    if measure.axis == "x" then
        item.line:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", measure.from, measure.at)
        item.line:SetSize(measure.to - measure.from, size)
        item.text:SetPoint("BOTTOM", root, "BOTTOMLEFT", middle, measure.at + 3)
    else
        item.line:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", measure.at, measure.from)
        item.line:SetSize(size, measure.to - measure.from)
        item.text:SetPoint("LEFT", root, "BOTTOMLEFT", measure.at + 4, middle)
    end
    item.text:SetText(string.format("%d", math.floor(measure.value + 0.5)))
    item.line:Show()
    item.text:Show()
end

--- Draws the distances of the selected element to its neighbors.
---@param rect table?
---@param others table[]? rects
function Scene.SetMeasures(rect, others)
    local used = 0
    if rect and option("distances") then
        for _, measure in ipairs(ns.MoverDistances(rect, others)) do
            used = used + 1
            drawMeasure(used, measure)
        end
    end
    for i = used + 1, #measurePool do
        measurePool[i].line:Hide()
        measurePool[i].text:Hide()
    end
end

--- The frame everything hangs from.
---@return table
function Scene.Root()
    if not root then
        root = CreateFrame("Frame", nil, UIParent)
        root:SetAllPoints()
        root:SetFrameStrata("FULLSCREEN_DIALOG")
        root:EnableMouse(true)
        root:SetScript("OnMouseDown", function()
            ns.MoverSession.Select(nil)
        end)
        local veil = root:CreateTexture(nil, "BACKGROUND", nil, -8)
        veil:SetAllPoints()
        veil:SetColorTexture(0, 0, 0, 0.35)
        ns.MoverChrome.Build(root)
    end
    return root
end

--- Redraws the handles and the panel: all a drag needs.
function Scene.RefreshElements()
    ns.MoverHandles.Refresh()
    ns.MoverChrome.Refresh()
end

--- Redraws everything, the grid included.
function Scene.Refresh()
    drawGrid()
    Scene.RefreshElements()
end

function Scene.Show()
    if ns.MoverSession.active then
        Scene.showGrid = option("grid")
        Scene.snap = option("snap")
        Scene.Root():Show()
        Scene.Refresh()
    end
end

function Scene.Hide()
    if root then
        root:Hide()
    end
end

--- Puts the Mover under the options window (HIGH is below its DIALOG strata), or back on top.
---@param behind boolean
function Scene.SetBehind(behind)
    if root then
        root:SetFrameStrata(behind and "HIGH" or "FULLSCREEN_DIALOG")
    end
end
