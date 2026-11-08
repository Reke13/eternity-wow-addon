-- Small drawing helpers of the resource bars: texts with a role size, a shape that takes color
-- specs and the track panel. They sit on the core's Shape, Theme and Widgets.

---@type string, EternityUIResourcesNamespace
local addonName, ns = ...
local E = EternityUI
local Shape, Theme, Widgets = E.Shape, E.Theme, E.Widgets

local UI = { space = 6 }
ns.UI = UI

local SIZES = { small = 12, caption = 11, body = 14 }
local OUTLINES = { none = "", thin = "OUTLINE", thick = "THICKOUTLINE" }
local MOST_RADIUS = 5

local function opt(path)
    return E.store:Get(addonName, path)
end

--- A text with a role size, the text color and outline options and a shadow. :SetStyle(role)
--- applies them again; they also survive theme changes, which repaint the core's texts.
---@param parent table
---@return table
function UI.Text(parent)
    local text = Widgets.Text(parent, SIZES.small, "text")
    local holder = text.holder
    function holder.Paint()
        local outline = OUTLINES[opt("look.outline")] or ""
        text:SetFont(Theme.font, holder.size * Theme.fontScale, outline)
        local c = Theme.RGBA(opt("look.textColor"))
        text:SetTextColor(c[1], c[2], c[3], c[4])
        text:SetShadowColor(0, 0, 0, outline == "" and 0.9 or 0)
    end
    function text.SetStyle(self, role)
        Widgets.SetTextSize(self, SIZES[role] or SIZES.small)
    end
    text:SetShadowOffset(1, -1)
    text:SetWordWrap(false)
    holder.Paint()
    return text
end

--- The corner radius the option asks for, at most the largest that fits height (nil: unknown).
---@param height number?
---@return integer
function UI.Radius(height)
    local corners = opt("look.corners")
    if corners == "square" then
        return 0
    end
    local radius = corners == "round" and MOST_RADIUS or math.min(Theme.radius, MOST_RADIUS)
    if height then
        radius = math.min(radius, math.floor(height / 2))
    end
    return radius
end

-- A radius that fits the frame's height, so thin bars keep their round ends.
local function radiusOf(frame)
    -- A frame anchored to a bar drawing a secret value has secret geometry.
    local height = frame:GetHeight()
    return UI.Radius(not E.Secret.Is(height) and height or nil)
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

--- A panel filling its parent, in the background and border options' colors (either may be off).
--- It keeps them when the theme or its size changes.
---@param parent table
---@return table
function UI.Track(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    panel.shape = UI.Shape(panel)
    function panel.Paint(self)
        local fill = opt("look.background") and opt("look.backgroundColor") or nil
        local border = opt("look.border") and opt("look.borderColor") or nil
        self.shape:SetColors(fill, border)
    end
    panel:SetScript("OnSizeChanged", panel.Paint)
    return Widgets.Track(panel)
end
