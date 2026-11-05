-- A rounded fill and a one pixel border, at any size, with two textures. Both are 9-sliced, and
-- slice margins are drawn in physical pixels, so corners stay crisp at any UI scale.
---@type string, EternityUINamespace
local _, ns = ...
local Theme = ns.Theme

---@class EternityShape
local Shape = {}
ns.Shape = Shape
EternityUI.Shape = Shape

local RADII = { 0, 4, 5, 6, 8, 10, 12, 14, 16 }

-- The largest generated radius that fits.
local function nearest(radius)
    local best = 0
    for _, candidate in ipairs(RADII) do
        if candidate <= radius then
            best = candidate
        end
    end
    return best
end
Shape.Nearest = nearest

local function paint(texture, file, radius, color)
    texture:SetTexture(Theme.MEDIA .. file .. "-" .. radius .. ".tga")
    local margin = math.max(radius, 2)
    texture:SetTextureSliceMargins(margin, margin, margin, margin)
    texture:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
    texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
end

--- Adds a shape's textures to a frame. layer and sublevel put both on one layer, the border just
--- above the fill; by default they're BACKGROUND and BORDER.
---@param frame table
---@param layer string?
---@param sublevel integer?
---@return table shape
function Shape.New(frame, layer, sublevel)
    local shape = {
        fill = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0),
        border = frame:CreateTexture(nil, layer or "BORDER", nil, sublevel and sublevel + 1 or 0),
    }
    shape.fill:SetAllPoints()
    shape.border:SetAllPoints()
    return shape
end

--- Paints a shape. A nil color hides that part.
---@param shape table
---@param radius integer
---@param fill number[]?
---@param border number[]?
function Shape.Paint(shape, radius, fill, border)
    radius = nearest(radius)
    shape.fill:SetShown(fill ~= nil)
    shape.border:SetShown(border ~= nil)
    if fill then
        paint(shape.fill, "fill", radius, fill)
    end
    if border then
        paint(shape.border, "border", radius, border)
    end
end
