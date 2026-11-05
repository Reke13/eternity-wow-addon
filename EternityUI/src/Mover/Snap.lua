-- Mover snapping: pure math, like Geometry. Given the rect being dragged and the
-- other elements' rects, it pulls the rect onto the nearest line within `threshold` on each
-- axis and tells which guides to draw and which element it ended up glued to.
--
-- Lines it snaps to, per axis (left/center/right of the dragged rect against each):
--   screen   : the screen's edges and center
--   grid     : grid lines, counted out from the screen center
--   elements : other elements' edges and centers (aligned), and their outer edges plus `gap`
--              (side by side: that's the glue that can turn into an anchor on drop)
--   spacing  : a gap already used between two elements in a row or column, next to another
--              one in the same row (guides with `marks` to draw both equal gaps)
---@type string, EternityUINamespace
local _, ns = ...
local Geometry = ns.MoverGeometry

---@class EternityMoverSnap
local Snap = {}
ns.MoverSnap = Snap
EternityUI.MoverSnap = Snap

local EPSILON = 0.5

---@class EternityMoverSnapOptions
---@field sw number screen width (UIParent units)
---@field sh number screen height
---@field threshold number pull distance
---@field gap number distance kept between glued elements
---@field grid number? grid step (nil = don't snap to the grid)
---@field screen boolean? snap to the screen's edges and center
---@field elements boolean? snap to other elements
---@field spacing boolean? snap to the gaps already used between other elements

-- Edges of the dragged rect on one axis: start, center, end.
local function edges(start, size)
    return { start, start + size / 2, start + size }
end

-- Best candidate on one axis: lines = { { pos, kind, key?, glue? } }; returns delta, line.
local function best(start, size, lines, threshold)
    local bestDelta, bestLine
    local own = edges(start, size)
    for _, line in ipairs(lines) do
        for i = 1, 3 do
            if not line.edge or line.edge == i then
                local delta = line.pos - own[i]
                if math.abs(delta) <= threshold and (not bestDelta or math.abs(delta) < math.abs(bestDelta)) then
                    bestDelta, bestLine = delta, line
                end
            end
        end
    end
    return bestDelta, bestLine
end

local function gridLines(lines, center, size, step, extent)
    if not step or step <= 0 then
        return
    end
    -- Only the lines near the rect: the rest can't be within the threshold.
    local first = math.floor((size.lo - center) / step) - 1
    local last = math.ceil((size.hi - center) / step) + 1
    for k = first, last do
        local pos = center + k * step
        if pos >= 0 and pos <= extent then
            lines[#lines + 1] = { pos = pos, kind = "grid" }
        end
    end
end

local function overlaps(aStart, aSize, bStart, bSize, margin)
    return aStart < bStart + bSize + margin and bStart < aStart + aSize + margin
end

-- Axis names for one axis ("x": left/width, "y": bottom/height) and the other one.
local AXES = {
    x = { start = "l", size = "w", across = "b", acrossSize = "h" },
    y = { start = "b", size = "h", across = "l", acrossSize = "w" },
}

-- Equal spacing on one axis: the gaps already used between pairs of other elements in a row
-- (or column), offered next to each element in the dragged rect's row, plus the middle point
-- between two elements with the rect in between.
local function spacingLines(lines, rect, others, axis)
    local a = AXES[axis]
    local function across(o)
        return Geometry.OverlapMiddle(rect[a.across], rect[a.acrossSize], o[a.across], o[a.acrossSize])
    end
    local gaps = {}
    for i, one in ipairs(others) do
        for j, two in ipairs(others) do
            local p, q = one.rect, two.rect
            local gap = q[a.start] - (p[a.start] + p[a.size])
            if i ~= j and gap > EPSILON then
                local at = Geometry.OverlapMiddle(p[a.across], p[a.acrossSize], q[a.across], q[a.acrossSize])
                if at then
                    gaps[#gaps + 1] = { value = gap, from = p[a.start] + p[a.size], to = q[a.start], at = at }
                end
            end
        end
    end
    for _, other in ipairs(others) do
        local o = other.rect
        if across(o) then
            for _, gap in ipairs(gaps) do
                lines[#lines + 1] =
                    { pos = o[a.start] + o[a.size] + gap.value, kind = "spacing", edge = 1, ref = gap, near = o }
                lines[#lines + 1] = { pos = o[a.start] - gap.value, kind = "spacing", edge = 3, ref = gap, near = o }
            end
        end
    end
    for _, one in ipairs(others) do
        for _, two in ipairs(others) do
            local p, q = one.rect, two.rect
            local room = q[a.start] - (p[a.start] + p[a.size]) - rect[a.size]
            if room > 0 and across(p) and across(q) then
                lines[#lines + 1] = {
                    pos = p[a.start] + p[a.size] + room / 2,
                    kind = "spacing",
                    edge = 1,
                    between = { p, q },
                }
            end
        end
    end
end

-- Measures that show an equal spacing once the rect sits on `line` (see Geometry.Distances).
local function spacingMarks(line, rect, axis)
    local a = AXES[axis]
    local function mark(from, to, o)
        local at = Geometry.OverlapMiddle(rect[a.across], rect[a.acrossSize], o[a.across], o[a.acrossSize])
        return { axis = axis, from = from, to = to, at = at or (rect[a.across] + rect[a.acrossSize] / 2) }
    end
    local marks = {}
    if line.between then
        local p, q = line.between[1], line.between[2]
        marks[1] = mark(p[a.start] + p[a.size], rect[a.start], p)
        marks[2] = mark(rect[a.start] + rect[a.size], q[a.start], q)
    else
        local o = line.near
        if line.edge == 1 then
            marks[1] = mark(o[a.start] + o[a.size], rect[a.start], o)
        else
            marks[1] = mark(rect[a.start] + rect[a.size], o[a.start], o)
        end
        local ref = line.ref
        marks[2] = { axis = axis, from = ref.from, to = ref.to, at = ref.at }
    end
    for _, m in ipairs(marks) do
        m.value = m.to - m.from
    end
    return marks
end

--- Snaps `rect` (not modified) against `others` ({ { key, rect } }). Returns the new rect, the
--- guides to draw ({ { axis = "x"|"y", pos } }) and the glue ({ key, side, align } or nil):
--- the element the rect ended up next to, side by side at `gap`.
---@param rect table
---@param others table[]
---@param opts EternityMoverSnapOptions
function Snap.Compute(rect, others, opts)
    local threshold, gap = opts.threshold or 6, opts.gap or 0
    local xs, ys = {}, {}
    if opts.screen then
        for _, pos in ipairs({ 0, opts.sw / 2, opts.sw }) do
            xs[#xs + 1] = { pos = pos, kind = "screen" }
        end
        for _, pos in ipairs({ 0, opts.sh / 2, opts.sh }) do
            ys[#ys + 1] = { pos = pos, kind = "screen" }
        end
    end
    gridLines(xs, opts.sw / 2, { lo = rect.l, hi = rect.l + rect.w }, opts.grid, opts.sw)
    gridLines(ys, opts.sh / 2, { lo = rect.b, hi = rect.b + rect.h }, opts.grid, opts.sh)
    if opts.elements then
        for _, other in ipairs(others) do
            local o = other.rect
            for _, pos in ipairs(edges(o.l, o.w)) do
                xs[#xs + 1] = { pos = pos, kind = "element", key = other.key }
            end
            for _, pos in ipairs(edges(o.b, o.h)) do
                ys[#ys + 1] = { pos = pos, kind = "element", key = other.key }
            end
            -- Side by side with the gap: our left on its right + gap, our right on its left - gap...
            xs[#xs + 1] = { pos = o.l + o.w + gap, kind = "glue", key = other.key, edge = 1 }
            xs[#xs + 1] = { pos = o.l - gap, kind = "glue", key = other.key, edge = 3 }
            ys[#ys + 1] = { pos = o.b + o.h + gap, kind = "glue", key = other.key, edge = 1 }
            ys[#ys + 1] = { pos = o.b - gap, kind = "glue", key = other.key, edge = 3 }
        end
    end
    if opts.spacing then
        spacingLines(xs, rect, others, "x")
        spacingLines(ys, rect, others, "y")
    end

    local out = { l = rect.l, b = rect.b, w = rect.w, h = rect.h }
    local guides = {}
    local dx, lineX = best(rect.l, rect.w, xs, threshold)
    if dx then
        out.l = out.l + dx
    end
    local dy, lineY = best(rect.b, rect.h, ys, threshold)
    if dy then
        out.b = out.b + dy
    end
    -- Guides once both axes have moved (spacing marks measure the final rect).
    for axis, line in pairs({ x = dx and lineX, y = dy and lineY }) do
        if line then
            local guide = { axis = axis, pos = line.pos, kind = line.kind }
            if line.kind == "spacing" then
                guide.marks = spacingMarks(line, out, axis)
            end
            guides[#guides + 1] = guide
        end
    end
    table.sort(guides, function(a, b)
        return a.axis < b.axis
    end)
    return out, guides, Snap.FindGlue(out, others, gap)
end

-- Alignment along a side: which of start / center / end lines up (start if none does).
local function alignOf(aStart, aSize, bStart, bSize, vertical)
    if math.abs((aStart + aSize / 2) - (bStart + bSize / 2)) < EPSILON then
        return "center"
    end
    local startMatch = math.abs(aStart - bStart) < EPSILON
    local endMatch = math.abs((aStart + aSize) - (bStart + bSize)) < EPSILON
    -- Along a vertical side "start" is the top (the higher end).
    if vertical then
        startMatch, endMatch = endMatch, startMatch
    end
    if endMatch and not startMatch then
        return "end"
    end
    return "start"
end

--- Element that `rect` touches side by side at `gap` (overlapping on the other axis):
--- { key, side, align } with `side` the target's side, or nil.
function Snap.FindGlue(rect, others, gap)
    for _, other in ipairs(others) do
        local o = other.rect
        local side
        if overlaps(rect.b, rect.h, o.b, o.h, 0) then
            if math.abs(rect.l - (o.l + o.w + gap)) < EPSILON then
                side = "RIGHT"
            elseif math.abs((rect.l + rect.w) - (o.l - gap)) < EPSILON then
                side = "LEFT"
            end
        end
        if not side and overlaps(rect.l, rect.w, o.l, o.w, 0) then
            if math.abs(rect.b - (o.b + o.h + gap)) < EPSILON then
                side = "TOP"
            elseif math.abs((rect.b + rect.h) - (o.b - gap)) < EPSILON then
                side = "BOTTOM"
            end
        end
        if side then
            local vertical = side == "LEFT" or side == "RIGHT"
            local align = vertical and alignOf(rect.b, rect.h, o.b, o.h, true) or alignOf(rect.l, rect.w, o.l, o.w)
            return { key = other.key, side = side, align = align }
        end
    end
    return nil
end

--- Moves `rect` by a whole number of `step` on an axis (keyboard nudge). Returns a new rect.
function Snap.Nudge(rect, dx, dy, step)
    return { l = rect.l + dx * step, b = rect.b + dy * step, w = rect.w, h = rect.h }
end
