-- Small drawing helpers of the swing bars: texts with a role size, a shape that takes color specs
-- and the track panel. They sit on the core's Shape, Theme and Widgets.

---@type string, EternityUISwingTimerNamespace
local _, ns = ...
local E = EternityUI
local Shape, Theme, Widgets = E.Shape, E.Theme, E.Widgets

local UI = { space = 8 }
ns.UI = UI

local SIZES = { small = 12, caption = 11, body = 14 }
local MOST_RADIUS = 5

--- A text with a role size. :SetStyle(role) changes it.
---@param parent table
---@return table
function UI.Text(parent)
    local text = Widgets.Text(parent, SIZES.small, "text")
    function text.SetStyle(self, role)
        Widgets.SetTextSize(self, SIZES[role] or SIZES.small)
    end
    return text
end

-- A radius that fits the frame's height, so thin bars keep their round ends.
local function radiusOf(frame)
    -- A bar drawing a secret duration has secret geometry.
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
