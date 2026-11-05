-- Small drawing layer on the core's Theme, Shape and Widgets, copied from EternityUI_Objectives and
-- extended with what the Discs tab draws: option-table buttons, inputs and dropdowns, the menu,
-- cards, stacks and dividers. The core has no icons, so icons are plain glyphs.

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
    space = { xs = 4, sm = 8, md = 12, lg = 16, xl = 20, xxl = 24 },
    size = { row = 44, controlColumn = 300 },
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
            font = CreateFont("EternityUIDiscsFont" .. key)
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
    local size = options.size or 26
    button:SetSize(size, size)
    button.icon = iconOf(button, options.icon, 14)
    button.icon:SetPoint("CENTER")
    button:SetScript("OnClick", options.onClick)
    return button
end

-- Controls ------------------------------------------------------------------------------------------

--- A text. style: a role of SIZES; color: "text", "muted" or a color table. Left aligned, for rows
--- anchored on both sides.
function W.Text(parent, text, style, color)
    local label = Widgets.Text(parent, SIZES[style] or SIZES.body, color)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    return label
end

--- A button. options = { text, variant, icon, width, onClick }. variant: "primary", "danger" or
--- nothing for the plain one. onClick gets (button, mouseButton).
function W.Button(parent, options)
    local prefix = options.icon and (GLYPHS[options.icon] .. " ") or ""
    local button = Widgets.Button(parent, prefix .. options.text, options.variant or "ghost", options.onClick)
    if options.width then
        button:SetWidth(options.width)
    end
    function button.SetText(self, text)
        self.label:SetText(prefix .. text)
    end
    --- Enabled or not, and looking like it.
    function button.SetUsable(self, usable)
        self:SetEnabled(usable)
        self:SetAlpha(usable and 1 or 0.5)
    end
    return button
end

--- A text field. options = { width, maxLetters, placeholder, onEnter, onEscape, onFocusLost }.
--- box.placeholder is the hint, whose text can change.
function W.Input(parent, options)
    local box = Widgets.Input(parent, options.onEnter)
    box:SetWidth(options.width)
    if options.maxLetters then
        box:SetMaxLetters(options.maxLetters)
    end
    box.placeholder = Widgets.Text(box, SIZES.body, "muted")
    box.placeholder:SetPoint("LEFT", 10, 0)
    box.placeholder:SetText(options.placeholder or "")
    box:HookScript("OnTextChanged", function(self)
        self.placeholder:SetShown(self:GetText() == "")
    end)
    if options.onEscape then
        box:HookScript("OnEscapePressed", options.onEscape)
    end
    if options.onFocusLost then
        box:HookScript("OnEditFocusLost", function(self)
            options.onFocusLost(self:GetText())
        end)
    end
    return box
end

W.Menu = { Open = Widgets.Menu }

--- A dropdown whose list changes (the core's is fixed at creation). options = { width, placeholder,
--- onChange }; SetOptions takes { { value, text } }. The list is the core's menu.
function W.Dropdown(parent, options)
    local dropdown = Widgets.Button(parent, "", "ghost", function(self)
        local entries = {}
        for i, option in ipairs(self.options) do
            entries[i] = {
                text = option.text,
                onClick = function()
                    self:SetValue(option.value)
                    options.onChange(option.value)
                end,
            }
        end
        if #entries > 0 then
            Widgets.Menu(self, entries, options.width)
        end
    end)
    dropdown.options = {}
    dropdown:SetWidth(options.width)
    dropdown.label:ClearAllPoints()
    dropdown.label:SetPoint("LEFT", 10, 0)
    dropdown.label:SetPoint("RIGHT", -10, 0)
    dropdown.label:SetJustifyH("LEFT")
    dropdown.label:SetWordWrap(false)

    function dropdown.SetValue(self, value)
        self.value = value
        local text = options.placeholder or ""
        for _, option in ipairs(self.options) do
            if option.value == value then
                text = option.text
            end
        end
        self.label:SetText(text)
    end

    function dropdown.SetOptions(self, list)
        self.options = list
        self:SetValue(self.value)
    end

    dropdown:SetValue(nil)
    return dropdown
end

--- A rounded block for rows. Set card.height when its content changes.
function W.Card(parent)
    local card = CreateFrame("Frame", nil, parent)
    card.shape = shapeOf(card, "card")
    function card.Paint(self)
        self.shape:SetColors("surface", "border")
    end
    card:SetScript("OnSizeChanged", card.Paint)
    return Widgets.Track(card)
end

--- A line between rows, in the theme's color.
function W.Divider(parent)
    local divider = CreateFrame("Frame", nil, parent)
    divider:SetHeight(1)
    divider.line = divider:CreateTexture(nil, "ARTWORK")
    divider.line:SetAllPoints()
    function divider.Paint(self)
        self.line:SetColorTexture(Core.Color("divider"))
    end
    return Widgets.Track(divider)
end

--- A column filling its parent's width. Add(widget, gap) returns the widget; Layout() places the
--- shown ones, each with its .height or its own height, and returns the total.
function W.Stack(parent)
    local stack = CreateFrame("Frame", nil, parent)
    stack:SetPoint("TOPLEFT")
    stack:SetPoint("TOPRIGHT")
    stack.items = {}

    function stack.Add(self, widget, gap)
        self.items[#self.items + 1] = { widget = widget, gap = gap or 0 }
        return widget
    end

    function stack.Layout(self)
        local y = 0
        for _, item in ipairs(self.items) do
            local widget = item.widget
            if widget:IsShown() then
                if y > 0 then
                    y = y + item.gap
                end
                widget:ClearAllPoints()
                widget:SetPoint("TOPLEFT", 0, -y)
                widget:SetPoint("TOPRIGHT", 0, -y)
                y = y + (widget.height or widget:GetHeight())
            end
        end
        self:SetHeight(math.max(y, 1))
        return y
    end
    return stack
end
