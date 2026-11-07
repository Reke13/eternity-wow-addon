-- Small drawing helpers of the resource bars: texts with a role size, a shape that takes color
-- specs and the track panel. They sit on the core's Shape, Theme and Widgets.

---@type string, EternityUIResourcesNamespace
local _, ns = ...
local E = EternityUI
local Shape, Theme, Widgets = E.Shape, E.Theme, E.Widgets

local UI = { space = 6 }
ns.UI = UI

local SIZES = { small = 12, caption = 11, body = 14 }
local MOST_RADIUS = 5

--- A text with a role size and a shadow. :SetStyle(role) changes the size.
---@param parent table
---@return table
function UI.Text(parent)
    local text = Widgets.Text(parent, SIZES.small, "text")
    function text.SetStyle(self, role)
        Widgets.SetTextSize(self, SIZES[role] or SIZES.small)
    end
    text:SetShadowOffset(1, -1)
    text:SetShadowColor(0, 0, 0, 0.9)
    text:SetWordWrap(false)
    return text
end

-- A radius that fits the frame's height, so thin bars keep their round ends.
local function radiusOf(frame)
    -- A frame anchored to a bar drawing a secret value has secret geometry.
    local height = frame:GetHeight()
    if E.Secret.Is(height) then
        return math.min(Theme.radius, MOST_RADIUS)
    end
    return math.min(Theme.radius, MOST_RADIUS, math.floor(height / 2))
end

--- A shape on a frame. :SetColors(fill, border, top) takes color specs or nil, and with top the
--- fill is a vertical gradient. :SetAlpha(alpha) fades it.
---@param frame table
---@return table
function UI.Shape(frame)
    local shape = Shape.New(frame)
    function shape.SetColors(_, fill, border, top)
        local bottom = fill and Theme.RGBA(fill) or nil
        Shape.Paint(shape, radiusOf(frame), bottom, border and Theme.RGBA(border) or nil)
        if bottom and top then
            local upper = Theme.RGBA(top)
            shape.fill:SetVertexColor(1, 1, 1, 1)
            shape.fill:SetGradient("VERTICAL", CreateColor(unpack(bottom)), CreateColor(unpack(upper)))
        end
    end
    function shape.SetAlpha(_, alpha)
        shape.fill:SetAlpha(alpha)
        shape.border:SetAlpha(alpha)
    end
    return shape
end

--- Paints a shape with a color, flat or as a vertical gradient ("theme" follows the glass setting).
---@param shape table from UI.Shape
---@param color table { r, g, b, a }
---@param style string "theme", "flat" or "gradient"
function UI.Paint(shape, color, style)
    local r, g, b, a = color[1], color[2], color[3], color[4] or 1
    if style == "gradient" or (style == "theme" and Theme.surface == "glass") then
        local function light(c)
            return math.min(1, c * 1.15 + 0.1)
        end
        shape:SetColors({ r * 0.65, g * 0.65, b * 0.65, a }, nil, { light(r), light(g), light(b), a })
    else
        shape:SetColors({ r, g, b, a }, nil)
    end
end

--- A panel filling its parent. It keeps its colors when the theme or its size changes.
---@param parent table
---@return table
function UI.Track(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    panel.shape = UI.Shape(panel)
    function panel.Paint(self)
        self.shape:SetColors("track", "border")
    end
    panel:SetScript("OnSizeChanged", panel.Paint)
    return Widgets.Track(panel)
end
