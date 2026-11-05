-- Mover geometry: pure math over rectangles in UIParent units (no frames here, so the
-- tests can drive it directly).
--
-- A rect is { l, b, w, h } (left, bottom, width, height) with the origin at UIParent's
-- bottom-left. A layout entry { point = "TOP", x = 0, y = -4 } is the frame's `point` on
-- UIParent's `point`.
---@type string, EternityUINamespace
local _, ns = ...

---@class EternityMoverGeometry
local Geometry = {}
ns.MoverGeometry = Geometry
EternityUI.MoverGeometry = Geometry

-- Fraction of the width and height where each point sits, from the bottom-left corner.
Geometry.POINTS = {
    TOPLEFT = { 0, 1 },
    TOP = { 0.5, 1 },
    TOPRIGHT = { 1, 1 },
    LEFT = { 0, 0.5 },
    CENTER = { 0.5, 0.5 },
    RIGHT = { 1, 0.5 },
    BOTTOMLEFT = { 0, 0 },
    BOTTOM = { 0.5, 0 },
    BOTTOMRIGHT = { 1, 0 },
}
Geometry.SIDES = { TOP = true, BOTTOM = true, LEFT = true, RIGHT = true }
Geometry.ALIGNS = { start = true, center = true, ["end"] = true }

local function fraction(point)
    local f = Geometry.POINTS[point] or Geometry.POINTS.CENTER
    return f[1], f[2]
end

--- Rounds `v` to the nearest multiple of `step` (no rounding if step is nil or 0).
function Geometry.Round(v, step)
    if not step or step <= 0 then
        return v
    end
    return math.floor(v / step + 0.5) * step
end

--- Rect of a free entry for a frame of w×h on a screen of sw×sh.
function Geometry.RectFromFree(entry, w, h, sw, sh)
    local fx, fy = fraction(entry.point)
    return { l = sw * fx + (entry.x or 0) - w * fx, b = sh * fy + (entry.y or 0) - h * fy, w = w, h = h }
end

--- Free entry that puts `rect` with `point` on UIParent's `point`.
function Geometry.FreeFromRect(point, rect, sw, sh)
    local fx, fy = fraction(point)
    return { point = point, x = rect.l + rect.w * fx - sw * fx, y = rect.b + rect.h * fy - sh * fy }
end

--- Of the 9 points, the one nearest to the rect's center: TOP/BOTTOM split at half the screen
--- height and LEFT/center/RIGHT in thirds. Saving against it keeps the frame in place when the
--- resolution or UI scale changes.
function Geometry.NearestPoint(rect, sw, sh)
    local cx, cy = rect.l + rect.w / 2, rect.b + rect.h / 2
    local v = cy > sh * 2 / 3 and "TOP" or cy < sh / 3 and "BOTTOM" or ""
    local hz = cx > sw * 2 / 3 and "RIGHT" or cx < sw / 3 and "LEFT" or ""
    local point = v .. hz
    return point == "" and "CENTER" or point
end

--- Keeps a rect inside the screen.
function Geometry.Clamp(rect, sw, sh)
    rect.l = math.max(0, math.min(rect.l, sw - rect.w))
    rect.b = math.max(0, math.min(rect.b, sh - rect.h))
    return rect
end

--- Overlap of two spans [a, a + as] and [b, b + bs]: its middle, or nil if they don't overlap.
function Geometry.OverlapMiddle(a, as, b, bs)
    local lo, hi = math.max(a, b), math.min(a + as, b + bs)
    if hi <= lo then
        return nil
    end
    return (lo + hi) / 2
end

--- Distances from `rect` to the nearest of `others` (rects) on each side, among those that
--- face it (overlapping on the other axis). With sw/sh, a side with nobody measures to the
--- screen edge. Returns { { side, axis, from, to, at, value, screen? } }: the measure runs on
--- `axis` from `from` to `to`, drawn at `at` on the other axis.
function Geometry.Distances(rect, others, sw, sh)
    local best = {}
    local function offer(side, value, measure)
        if value >= 0 and (not best[side] or value < best[side].value) then
            measure.side, measure.value = side, value
            best[side] = measure
        end
    end
    local r, t = rect.l + rect.w, rect.b + rect.h
    for _, o in ipairs(others) do
        local atY = Geometry.OverlapMiddle(rect.b, rect.h, o.b, o.h)
        if atY then
            offer("RIGHT", o.l - r, { axis = "x", from = r, to = o.l, at = atY })
            offer("LEFT", rect.l - (o.l + o.w), { axis = "x", from = o.l + o.w, to = rect.l, at = atY })
        end
        local atX = Geometry.OverlapMiddle(rect.l, rect.w, o.l, o.w)
        if atX then
            offer("TOP", o.b - t, { axis = "y", from = t, to = o.b, at = atX })
            offer("BOTTOM", rect.b - (o.b + o.h), { axis = "y", from = o.b + o.h, to = rect.b, at = atX })
        end
    end
    if sw and sh then
        local cx, cy = rect.l + rect.w / 2, rect.b + rect.h / 2
        local edges = {
            LEFT = { axis = "x", from = 0, to = rect.l, at = cy, value = rect.l },
            RIGHT = { axis = "x", from = r, to = sw, at = cy, value = sw - r },
            BOTTOM = { axis = "y", from = 0, to = rect.b, at = cx, value = rect.b },
            TOP = { axis = "y", from = t, to = sh, at = cx, value = sh - t },
        }
        for side, measure in pairs(edges) do
            if not best[side] and measure.value > 0 then
                measure.side, measure.screen = side, true
                best[side] = measure
            end
        end
    end
    local out = {}
    for _, side in ipairs({ "LEFT", "RIGHT", "TOP", "BOTTOM" }) do
        if best[side] then
            out[#out + 1] = best[side]
        end
    end
    return out
end
