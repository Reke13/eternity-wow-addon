-- Small drawing helpers of the chat: text sizes by role, shapes that take color specs and a role,
-- a soft shadow and the dotted icon. They sit on the core's Shape, Theme and Widgets.

---@type string, EternityUIChatNamespace
local _, ns = ...
local E = EternityUI
local Shape, Theme, Widgets = E.Shape, E.Theme, E.Widgets

local UI = { space = { xs = 4, sm = 8, md = 12, lg = 16 } }
ns.UI = UI

local SIZES = { heading = 15, body = 14, small = 12, caption = 11 }
local SHADOW_REACH = 24
local DOT = 3

--- A text with a role size and a theme color token.
---@param parent table
---@param text string
---@param style string?
---@param color string?
---@return table
function UI.Text(parent, text, style, color)
    local fontString = Widgets.Text(parent, SIZES[style or "body"], color or "text")
    fontString:SetText(text)
    return fontString
end

local function radiusOf(frame, role)
    if Theme.radius == 0 then
        return 0
    end
    if role == "pill" then
        local height = frame:GetHeight()
        return height > 0 and math.floor(height / 2) or 8
    end
    return math.min(Theme.radius, role == "control" and 5 or 8)
end

--- A shape on a frame: :SetColors(fill, border) takes color specs or nil, :SetAlpha the fill's.
---@param frame table
---@param role string "card", "control" or "pill"
---@return table
function UI.Shape(frame, role)
    local shape = Shape.New(frame)
    function shape.SetColors(_, fill, border)
        Shape.Paint(
            shape,
            radiusOf(frame, role),
            fill and Theme.RGBA(fill) or nil,
            border and Theme.RGBA(border) or nil
        )
    end
    function shape.SetAlpha(_, alpha)
        shape.fill:SetAlpha(alpha)
    end
    return shape
end

--- A soft shadow around a frame.
---@param frame table
---@return table
function UI.Shadow(frame)
    local shadow = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    shadow:SetPoint("TOPLEFT", -SHADOW_REACH, SHADOW_REACH)
    shadow:SetPoint("BOTTOMRIGHT", SHADOW_REACH, -SHADOW_REACH)
    function shadow.Update()
        shadow:SetTexture(Theme.MEDIA .. "shadow.tga")
        shadow:SetTextureSliceMargins(32, 32, 32, 32)
        shadow:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
        shadow:SetVertexColor(Theme.Color("shadow"))
        shadow:Show()
    end
    return shadow
end

--- Sets frame.hovered and calls fn on enter and leave.
---@param frame table
---@param fn fun(frame: table)
function UI.TrackHover(frame, fn)
    frame:HookScript("OnEnter", function(self)
        self.hovered = true
        fn(self)
    end)
    frame:HookScript("OnLeave", function(self)
        self.hovered = false
        fn(self)
    end)
end

--- A line of one physical pixel. vertical: the caller sets its two ends.
---@param parent table
---@param vertical boolean?
---@return table
function UI.Divider(parent, vertical)
    local line = Widgets.Rect(parent, Theme.colors.line)
    if vertical then
        line:SetWidth(E.Pixel.Size(parent))
    else
        line:SetHeight(E.Pixel.Size(parent))
    end
    return line
end

--- A text field with a placeholder.
---@param parent table
---@param placeholder string
---@param maxLetters integer
---@param onEnter fun(text: string)?
---@return table
function UI.Input(parent, placeholder, maxLetters, onEnter)
    local box = Widgets.Input(parent, onEnter)
    box:SetMaxLetters(maxLetters)
    local hint = Widgets.Text(box, 14, "muted")
    hint:SetPoint("LEFT", 10, 0)
    hint:SetText(placeholder)
    box:HookScript("OnTextChanged", function(self)
        hint:SetShown(self:GetText() == "")
    end)
    return box
end

--- Three dots centered on a frame: the icon of the messenger's buttons.
---@param frame table
---@return table icon :SetColor(spec)
function UI.Dots(frame)
    local icon = {}
    for i = 1, 3 do
        local dot = frame:CreateTexture(nil, "ARTWORK")
        dot:SetSize(DOT, DOT)
        dot:SetPoint("CENTER", (i - 2) * (DOT + 2), 0)
        icon[i] = dot
    end
    function icon.SetColor(_, spec)
        for i = 1, 3 do
            icon[i]:SetColorTexture(Theme.Color(spec))
        end
    end
    return icon
end
