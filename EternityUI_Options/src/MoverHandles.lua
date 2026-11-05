-- The handle over each element: click to select, drag to move, arrows to nudge one pixel (ten
-- with Shift). Alt frees a drag from the snap.
---@type string, table
local _, ns = ...
local E = EternityUI
local Mover = E.Mover
local Shape = E.Shape
local Theme = E.Theme
local Widgets = E.Widgets
local Geometry = E.MoverGeometry
local Snap = E.MoverSnap

local Handles = {}
ns.MoverHandles = Handles

local handles = {}
local drag

local function session()
    return ns.MoverSession
end

-- The other elements' rects, as Snap wants them and as plain rects.
local function others(key)
    local list, rects = {}, {}
    for _, element in ipairs(Mover.List()) do
        if element.key ~= key then
            local rect = Mover.Rect(element, session().Entry(element.key))
            list[#list + 1] = { key = element.key, rect = rect }
            rects[#rects + 1] = rect
        end
    end
    return list, rects
end

ns.MoverDistances = function(rect, rects)
    return Geometry.Distances(rect, rects, UIParent:GetWidth(), UIParent:GetHeight())
end

-- The entry that keeps a rect in place, rounded to whole pixels.
local function entryFor(key, rect)
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    local entry = Geometry.FreeFromRect(Geometry.NearestPoint(rect, width, height), rect, width, height)
    local pixel = E.Pixel.Size(UIParent)
    entry.x = Geometry.Round(entry.x, pixel)
    entry.y = Geometry.Round(entry.y, pixel)
    entry.locked = session().Entry(key).locked
    return entry
end

local function cursor()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    return x / scale, y / scale
end

local function onUpdate()
    local x, y = cursor()
    local rect = {
        l = drag.rect.l + x - drag.x,
        b = drag.rect.b + y - drag.y,
        w = drag.rect.w,
        h = drag.rect.h,
    }
    local guides
    if ns.MoverScene.snap and not IsAltKeyDown() then
        rect, guides = Snap.Compute(rect, drag.others, {
            sw = UIParent:GetWidth(),
            sh = UIParent:GetHeight(),
            threshold = ns.MoverScene.option("threshold"),
            gap = 0,
            grid = ns.MoverScene.showGrid and ns.MoverScene.option("gridSize") or nil,
            screen = true,
            elements = true,
            spacing = true,
        })
    end
    Geometry.Clamp(rect, UIParent:GetWidth(), UIParent:GetHeight())
    session().Set(drag.key, entryFor(drag.key, rect))
    ns.MoverScene.SetGuides(guides)
end

local function startDrag(handle)
    local key = handle.key
    session().Select(key)
    if session().Entry(key).locked then
        return
    end
    session().Checkpoint()
    local x, y = cursor()
    drag = {
        key = key,
        x = x,
        y = y,
        rect = Mover.Rect(Mover.elements[key], session().Entry(key)),
        others = others(key),
    }
    handle:SetScript("OnUpdate", onUpdate)
end

local function stopDrag(handle)
    handle:SetScript("OnUpdate", nil)
    drag = nil
    ns.MoverScene.SetGuides(nil)
end

local function handleFor(element)
    local handle = handles[element.key]
    if handle then
        return handle
    end
    handle = CreateFrame("Button", nil, ns.MoverScene.Root())
    handle:SetFrameLevel(ns.MoverScene.Root():GetFrameLevel() + 5)
    handle.key = element.key
    handle.shape = Shape.New(handle)
    handle.label = Widgets.Text(handle, 14, "text")
    handle.label:SetPoint("CENTER", 0, 7)
    handle.size = Widgets.Text(handle, 12, "muted")
    handle.size:SetPoint("TOP", handle.label, "BOTTOM", 0, -2)
    handle:RegisterForClicks("AnyUp")
    handle:SetScript("OnMouseDown", startDrag)
    handle:SetScript("OnMouseUp", stopDrag)
    handles[element.key] = handle
    return handle
end

--- Puts each handle over its element and marks the selected one.
function Handles.Refresh()
    local selectedRect
    for key, handle in pairs(handles) do
        handle:SetShown(Mover.elements[key] ~= nil)
    end
    for _, element in ipairs(Mover.List()) do
        local handle = handleFor(element)
        local rect = Mover.Rect(element, session().Entry(element.key))
        handle:ClearAllPoints()
        handle:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", rect.l, rect.b)
        handle:SetSize(rect.w, rect.h)
        handle.label:SetText(element.label)
        handle.size:SetText(string.format("%d × %d", math.floor(rect.w + 0.5), math.floor(rect.h + 0.5)))
        local on = session().selected == element.key
        local a = Theme.accent
        local edge = on and { a[1], a[2], a[3], 1 } or { a[1], a[2], a[3], 0.45 }
        Shape.Paint(handle.shape, 5, { a[1], a[2], a[3], on and 0.34 or 0.14 }, edge)
        if on then
            selectedRect = rect
        end
    end
    local _, rects = others(session().selected)
    ns.MoverScene.SetMeasures(selectedRect, rects)
end

--- Moves the selected element by whole pixels.
---@param dx integer
---@param dy integer
function Handles.Nudge(dx, dy)
    local key = session().selected
    if not key or session().Entry(key).locked then
        return
    end
    session().Checkpoint()
    local pixel = E.Pixel.Size(UIParent)
    local rect = Snap.Nudge(Mover.Rect(Mover.elements[key], session().Entry(key)), dx, dy, pixel)
    Geometry.Clamp(rect, UIParent:GetWidth(), UIParent:GetHeight())
    session().Set(key, entryFor(key, rect))
end
