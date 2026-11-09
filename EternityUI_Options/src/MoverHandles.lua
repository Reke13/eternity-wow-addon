-- The handle over each element: click to select, drag to move, arrows to nudge one pixel (ten
-- with Shift). Alt frees a drag from the snap. The selected element has a grip in its bottom right
-- corner: dragging it scales the element, keeping its top left corner in place.
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
Handles.handles = handles -- for the tests
local drag, resize

local GRIP = 14

local function session()
    return ns.MoverSession
end

-- The other elements' rects, as Snap wants them and as plain rects.
local function others(key)
    local list, rects = {}, {}
    for _, element in ipairs(Mover.List()) do
        -- Elements hidden in the Mover ("Elements" panel) don't pull or measure.
        if element.key ~= key and ns.MoverElements.IsShown(element.key) then
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
    local current = session().Entry(key)
    entry.locked = current.locked
    entry.scale = current.scale
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

-- Scale from the grip: the cursor's travel over the element's size, kept to 0.01 steps.
local function onResize()
    local x, y = cursor()
    local start = resize.rect
    local grow = ((start.w + x - resize.x) / start.w + (start.h + resize.y - y) / start.h) / 2
    local scale = resize.scale * math.max(grow, 0.01)
    scale = math.floor(math.min(math.max(scale, Mover.MIN_SCALE), Mover.MAX_SCALE) * 100 + 0.5) / 100
    local k = scale / resize.scale
    local top = start.b + start.h
    local rect = { l = start.l, w = start.w * k, h = start.h * k }
    rect.b = top - rect.h
    Geometry.Clamp(rect, UIParent:GetWidth(), UIParent:GetHeight())
    local entry = entryFor(resize.key, rect)
    entry.scale = scale ~= 1 and scale or nil
    session().Set(resize.key, entry)
end

local function startResize(grip)
    local key = grip:GetParent().key
    if session().Entry(key).locked then
        return
    end
    session().Checkpoint()
    local x, y = cursor()
    resize = {
        key = key,
        x = x,
        y = y,
        rect = Mover.Rect(Mover.elements[key], session().Entry(key)),
        scale = session().Entry(key).scale or 1,
    }
    grip:SetScript("OnUpdate", onResize)
end

local function stopResize(grip)
    grip:SetScript("OnUpdate", nil)
    resize = nil
end

local function gripFor(handle)
    local grip = CreateFrame("Button", nil, handle)
    grip:SetSize(GRIP, GRIP)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(handle:GetFrameLevel() + 2)
    grip.texture = grip:CreateTexture(nil, "OVERLAY")
    grip.texture:SetAllPoints()
    grip:SetScript("OnMouseDown", startResize)
    grip:SetScript("OnMouseUp", stopResize)
    return grip
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
    handle.grip = gripFor(handle)
    handles[element.key] = handle
    return handle
end

-- Puts one handle over its element; returns its rect when it's the selected one.
local function draw(element)
    local handle = handleFor(element)
    -- Hidden in the "Elements" panel: no handle (the element itself stays as it is).
    if not ns.MoverElements.IsShown(element.key) then
        handle:Hide()
        return nil
    end
    local rect = Mover.Rect(element, session().Entry(element.key))
    handle:ClearAllPoints()
    handle:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", rect.l, rect.b)
    handle:SetSize(rect.w, rect.h)
    handle.label:SetText(element.label)
    local entry = session().Entry(element.key)
    local size = string.format("%d × %d", math.floor(rect.w + 0.5), math.floor(rect.h + 0.5))
    if entry.scale then
        size = size .. string.format(" · x%.2f", entry.scale)
    end
    handle.size:SetText(size)
    local on = session().selected == element.key
    local a = Theme.accent
    handle.grip:SetShown(on and not entry.locked and Mover.IsScalable(element.key))
    handle.grip.texture:SetColorTexture(a[1], a[2], a[3], 1)
    local edge = on and { a[1], a[2], a[3], 1 } or { a[1], a[2], a[3], 0.45 }
    Shape.Paint(handle.shape, 5, { a[1], a[2], a[3], on and 0.34 or 0.14 }, edge)
    return on and rect or nil
end

--- Puts each handle over its element and marks the selected one.
function Handles.Refresh()
    local selectedRect
    for key, handle in pairs(handles) do
        handle:SetShown(Mover.elements[key] ~= nil)
    end
    for _, element in ipairs(Mover.List()) do
        selectedRect = draw(element) or selectedRect
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
