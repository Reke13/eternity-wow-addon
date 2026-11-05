-- Small drawing helpers of the cast bars: texts with a role size, shapes that take color specs and
-- a role, and the track panel. They sit on the core's Shape, Theme and Widgets.

---@type string, EternityUICastBarsNamespace
local _, ns = ...
local E = EternityUI
local Shape, Theme, Widgets = E.Shape, E.Theme, E.Widgets

local UI = { space = { xs = 4, sm = 8, md = 12, lg = 16 } }
ns.UI = UI

local SIZES = { heading = 15, body = 14, small = 12, caption = 11 }

--- A text with a role size. :SetStyle(role) changes it.
---@param parent table
---@param text string
---@param style string?
---@param color string?
---@return table
function UI.Text(parent, text, style, color)
    local fontString = Widgets.Text(parent, SIZES[style or "body"], color or "text")
    fontString:SetText(text)
    function fontString.SetStyle(self, role)
        Widgets.SetTextSize(self, SIZES[role] or SIZES.small)
    end
    return fontString
end

-- A radius that fits the frame's height, so thin bars keep their round ends.
local function radiusOf(frame, role)
    local most = role == "small" and 4 or 5
    -- A bar drawing a secret cast has secret geometry, and Finish paints it in that state.
    local height = frame:GetHeight()
    if issecretvalue ~= nil and issecretvalue(height) then
        return math.min(Theme.radius, most)
    end
    return math.min(Theme.radius, most, math.floor(height / 2))
end

--- A shape on a frame. :SetColors(fill, border, top) takes color specs or nil, and with top the
--- fill is a vertical gradient. :SetAlpha(alpha) fades it.
---@param frame table
---@param role string "control" or "small"
---@return table
function UI.Shape(frame, role)
    local shape = Shape.New(frame)
    function shape.SetColors(_, fill, border, top)
        local bottom = fill and Theme.RGBA(fill) or nil
        Shape.Paint(shape, radiusOf(frame, role), bottom, border and Theme.RGBA(border) or nil)
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
---@param options table { role, fill, border }
---@return table
function UI.Panel(parent, options)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    panel.shape = UI.Shape(panel, options.role)
    function panel.Paint(self)
        self.shape:SetColors(options.fill, options.border)
    end
    panel:SetScript("OnSizeChanged", panel.Paint)
    return Widgets.Track(panel)
end
