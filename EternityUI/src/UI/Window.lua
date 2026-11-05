-- A movable themed window: a header with a title and a close button, a body and an optional
-- footer. Esc closes it through keyboard input, because UISpecialFrames taints.
---@type string, EternityUINamespace
local _, ns = ...
local Shape = ns.Shape
local Theme = ns.Theme
local Widgets = ns.Widgets

local HEADER = 40
local FOOTER = 40
local SHADOW_REACH = 24

--- Creates a hidden window. Use HookScript for OnShow; w.onPaint(w) runs after each repaint.
---@param name string? global name
---@param title string
---@param footer boolean?
---@return table window with .header, .title, .close, .body, .footer and .shadow
function Widgets.Window(name, title, footer)
    local w = CreateFrame("Frame", name, UIParent)
    w:Hide()
    w:SetClampedToScreen(true)
    w:SetMovable(true)
    w:EnableMouse(true)
    w:RegisterForDrag("LeftButton")
    w.shape = Shape.New(w)

    w.shadow = w:CreateTexture(nil, "BACKGROUND", nil, -8)
    w.shadow:SetPoint("TOPLEFT", -SHADOW_REACH, SHADOW_REACH)
    w.shadow:SetPoint("BOTTOMRIGHT", SHADOW_REACH, -SHADOW_REACH)

    w.header = CreateFrame("Frame", nil, w)
    w.header:SetPoint("TOPLEFT")
    w.header:SetPoint("TOPRIGHT")
    w.header:SetHeight(HEADER)
    w.title = Widgets.Text(w.header, 15, "text")
    w.title:SetPoint("LEFT", 12, 0)
    w.title:SetText(title)
    w.close = Widgets.Button(w.header, "×", "ghost", function()
        w:Hide()
    end)
    w.close:SetSize(26, 26)
    w.close:SetPoint("RIGHT", -8, 0)
    local line = Widgets.Rect(w.header, Theme.colors.line)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(ns.Pixel.Size(w.header))

    w.body = CreateFrame("Frame", nil, w)
    w.body:SetPoint("TOPLEFT", w.header, "BOTTOMLEFT")
    if footer then
        w.footer = CreateFrame("Frame", nil, w)
        w.footer:SetPoint("BOTTOMLEFT")
        w.footer:SetPoint("BOTTOMRIGHT")
        w.footer:SetHeight(FOOTER)
        w.body:SetPoint("BOTTOMRIGHT", w.footer, "TOPRIGHT")
    else
        w.body:SetPoint("BOTTOMRIGHT")
    end

    function w:Paint()
        Theme.PaintWindow(self.shape)
        self.shadow:SetTexture(Theme.MEDIA .. "shadow.tga")
        self.shadow:SetTextureSliceMargins(32, 32, 32, 32)
        self.shadow:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
        self.shadow:SetVertexColor(Theme.Color("shadow"))
        if self.onPaint then
            self:onPaint()
        end
    end

    w:EnableKeyboard(true)
    w:HookScript("OnShow", function(self)
        ns.Combat.Run(self, function()
            self:SetPropagateKeyboardInput(true)
        end)
    end)
    w:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" and not InCombatLockdown() then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        end
    end)
    return Widgets.Track(w)
end
