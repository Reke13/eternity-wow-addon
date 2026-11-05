-- Small drawing layer on the core's Theme, Shape and Widgets: font objects per role, shapes that
-- take color specs and a role, panels, texts, plain-glyph icons. It's copied as is by the modules
-- restyling Blizzard's frames (Objectives, Map and Stats).

local _, ns = ...
local E = EternityUI
local Core, Shape, Widgets = E.Theme, E.Shape, E.Widgets

local SIZES = { heading = 15, body = 14, small = 12, caption = 11 }
local RADII = { control = 5, small = 4, card = 8 }
local GLYPHS = {
    chevronRight = "+",
    chevronDown = "–",
    plus = "+",
    minus = "–",
    close = "×",
    expand = "+",
    shrink = "–",
    menu = "=",
}

local Ui = { W = {} }
ns.Ui = Ui
local W = Ui.W

-- Theme ---------------------------------------------------------------------------------------------

local fonts = {}

local Theme = setmetatable({
    space = { xs = 4, sm = 8, md = 12, lg = 16 },
    --- r, g, b, a of a spec, with an optional alpha over it.
    Color = function(spec, alpha)
        local r, g, b, a = Core.Color(spec)
        return r, g, b, alpha or a
    end,
    RGBA = Core.RGBA,
    --- A font object of a role, kept up with the theme.
    Font = function(style)
        local key = SIZES[style] and style or "small"
        local font = fonts[key]
        if not font then
            font = CreateFont("EternityUIMapFont" .. key)
            fonts[key] = font
        end
        font:SetFont(Core.font, SIZES[key] * Core.fontScale, "")
        return font
    end,
}, {
    __index = function(_, key)
        if key == "glass" then
            return Core.surface == "glass"
        end
        return Core[key]
    end,
})
Ui.Theme = Theme
W.Theme = Theme

-- Shapes --------------------------------------------------------------------------------------------

local function radiusOf(frame, role)
    local most = RADII[role] or Core.radius
    local height = frame:GetHeight()
    if issecretvalue ~= nil and issecretvalue(height) then
        return math.min(Core.radius, most)
    end
    return math.min(Core.radius, most, math.max(math.floor(height / 2), 0))
end

local function shapeOf(frame, role, layer, sublevel)
    local shape = Shape.New(frame, layer, sublevel)
    local alpha = 1
    local specs = {}

    -- A texture's SetAlpha replaces the alpha of its vertex color, which is where translucent
    -- tokens keep theirs, so the shape's alpha goes into the colors.
    local function faded(spec)
        local color = Core.RGBA(spec)
        color[4] = color[4] * alpha
        return color
    end

    function shape.SetColors(_, fill, border, top)
        specs.fill, specs.border, specs.top = fill, border, top
        local bottom = fill and faded(fill) or nil
        Shape.Paint(shape, radiusOf(frame, role), bottom, border and faded(border) or nil)
        if bottom and top then
            shape.fill:SetVertexColor(1, 1, 1, 1)
            shape.fill:SetGradient("VERTICAL", CreateColor(unpack(bottom)), CreateColor(unpack(faded(top))))
        end
    end

    function shape.SetAlpha(_, value)
        alpha = value
        shape:SetColors(specs.fill, specs.border, specs.top)
    end
    return shape
end

--- A themed text glyph standing in for an icon.
local function iconOf(parent, name, size)
    local icon = Widgets.Text(parent, math.max(size or 12, 12), "muted")
    function icon.SetIcon(self, glyph)
        self:SetText(GLYPHS[glyph] or "")
    end
    function icon.SetColor(self, spec)
        self:SetTextColor(Core.Color(spec))
    end
    icon:SetIcon(name)
    return icon
end

W.Skin = { Shape = shapeOf, Icon = iconOf }

--- A panel filling its parent; it keeps its colors when the theme or its size changes.
function W.Panel(parent, options)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    panel.shape = shapeOf(panel, options.role)
    function panel.Paint(self)
        self.shape:SetColors(options.fill, options.border)
    end
    panel:SetScript("OnSizeChanged", panel.Paint)
    return Widgets.Track(panel)
end

-- Widgets -------------------------------------------------------------------------------------------

--- A text with a role size. :SetStyle(role, color) changes it.
function W.Text(parent, text, style, color)
    local fontString = Widgets.Text(parent, SIZES[style or "body"] or SIZES.small, color or "text")
    fontString:SetText(text)
    function fontString.SetStyle(self, role, spec)
        Widgets.SetTextSize(self, SIZES[role] or SIZES.small)
        if spec then
            self:SetTextColor(Core.Color(spec))
        end
    end
    return fontString
end

--- Runs fn(frame) now, on every theme change while the frame lives, and on frame:ApplyTheme().
function W.Themed(frame, fn)
    function frame.ApplyTheme()
        fn(frame)
    end
    frame.themed = { Paint = frame.ApplyTheme }
    Widgets.Track(frame.themed)
    return frame
end

W.AttachTooltip = Widgets.AttachTooltip

--- A small round button with a glyph. options = { icon, size, onClick }.
function W.IconButton(parent, options)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(options.size, options.size)
    button.icon = iconOf(button, options.icon, 14)
    button.icon:SetPoint("CENTER")
    button:SetScript("OnClick", options.onClick)
    return button
end
