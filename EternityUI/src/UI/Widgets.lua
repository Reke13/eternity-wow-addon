-- The controls the whole suite draws with. Each widget is a frame with a Paint method; every
-- painted widget repaints on Theme.CHANGED, and SetValue updates a control without calling back.
---@type string, EternityUINamespace
local _, ns = ...
local Events = ns.Events
local Shape = ns.Shape
local Theme = ns.Theme

---@class EternityWidgets
local Widgets = {}
ns.Widgets = Widgets
EternityUI.Widgets = Widgets

local painted = setmetatable({}, { __mode = "k" })

--- Repaints a widget now and on every theme change.
---@param widget table has a Paint method
---@return table
function Widgets.Track(widget)
    painted[widget] = true
    if Theme.accent then
        widget:Paint()
    end
    return widget
end

Events.Listen(Theme.CHANGED, Widgets, function()
    for widget in pairs(painted) do
        widget:Paint()
    end
end)

local function setColor(fontString, color)
    fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

--- A text. role: "text" or "muted", or a color table. Repaints with the theme's font.
---@param parent table
---@param size number
---@param role string|number[]?
---@return table
function Widgets.Text(parent, size, role)
    local text = parent:CreateFontString(nil, "OVERLAY")
    local holder = { size = size }
    function holder.Paint()
        text:SetFont(Theme.font, holder.size * Theme.fontScale, "")
        setColor(text, type(role) == "table" and role or Theme.colors[role or "text"])
    end
    text.holder = holder
    painted[holder] = true
    holder.Paint()
    return text
end

--- Changes the size of a text made with Widgets.Text.
---@param text table
---@param size number
function Widgets.SetTextSize(text, size)
    text.holder.size = size
    text.holder.Paint()
end

--- A flat rectangle (a line or a block) in a theme color.
---@param parent table
---@param color number[]
---@return table
function Widgets.Rect(parent, color)
    local rect = parent:CreateTexture(nil, "ARTWORK")
    rect:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    return rect
end

--- A button. style: "primary", "ghost", "nav" or "danger".
---@param parent table
---@param text string
---@param style string
---@param onClick fun()
---@return table
function Widgets.Button(parent, text, style, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetHeight(style == "nav" and 32 or 30)
    button.shape = Shape.New(button)
    button.label = Widgets.Text(button, style == "nav" and 15 or 14, "text")
    button.label:SetText(text)
    if style == "nav" then
        button.label:SetPoint("LEFT", 10, 0)
    else
        button.label:SetPoint("CENTER")
        button:SetWidth(math.max(90, button.label:GetStringWidth() + 28))
    end
    button:SetScript("OnClick", onClick)

    function button:SetActive(active)
        self.isActive = active
        self:Paint()
    end

    function button:Paint()
        local radius = math.min(Theme.radius, 5)
        local hovered = self:IsMouseOver()
        local colors = Theme.colors
        if style == "primary" then
            Shape.Paint(self.shape, radius, Theme.accent, nil)
            setColor(self.label, colors.onAccent)
        elseif style == "nav" then
            local fill = self.isActive and { Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.2 }
                or (hovered and colors.hover or nil)
            Shape.Paint(self.shape, radius, fill, nil)
            setColor(self.label, colors.text)
        else
            Shape.Paint(self.shape, radius, hovered and colors.hover or nil, colors.lineStrong)
            setColor(self.label, style == "danger" and colors.danger or colors.text)
        end
    end

    button:SetScript("OnEnter", button.Paint)
    button:SetScript("OnLeave", button.Paint)
    return Widgets.Track(button)
end

--- Mutually exclusive choices in a row. choices = { { value, text } }. Set group.buttonHeight
--- (30 by default) and call Paint to change the buttons' height.
---@param parent table
---@param choices table[]
---@param onSelect fun(value: any)
---@return table
function Widgets.Segmented(parent, choices, onSelect)
    local group = CreateFrame("Frame", nil, parent)
    group:SetHeight(30)
    group.buttons = {}
    for i, choice in ipairs(choices) do
        local button = CreateFrame("Button", nil, group)
        button.value = choice[1]
        button.shape = Shape.New(button)
        button.label = Widgets.Text(button, 14, "text")
        button.label:SetText(choice[2])
        button.label:SetPoint("CENTER")
        button:SetScript("OnClick", function()
            group:SetValue(choice[1])
            onSelect(choice[1])
        end)
        group.buttons[i] = button
    end
    function group:SetValue(value)
        self.value = value
        self:Paint()
    end

    function group:Paint()
        local x = 0
        for _, button in ipairs(self.buttons) do
            local on = button.value == self.value
            local width = button.label:GetStringWidth() + 28
            button:SetSize(width, self.buttonHeight or 30)
            button:SetPoint("LEFT", x, 0)
            x = x + width + 6
            local radius = math.min(Theme.radius, 5)
            Shape.Paint(
                button.shape,
                radius,
                on and Theme.accent or Theme.colors.hover,
                on and Theme.accent or Theme.colors.line
            )
            setColor(button.label, on and Theme.colors.onAccent or Theme.colors.text)
        end
        self:SetWidth(x)
    end

    return Widgets.Track(group)
end

--- A row of color choices. colors = { hex, ... }.
---@param parent table
---@param colors string[]
---@param onSelect fun(hex: string)
---@return table
function Widgets.Swatches(parent, colors, onSelect)
    local group = CreateFrame("Frame", nil, parent)
    group:SetSize(#colors * 36, 30)
    group.buttons = {}
    for i, hex in ipairs(colors) do
        local button = CreateFrame("Button", nil, group)
        button:SetSize(30, 30)
        button:SetPoint("LEFT", (i - 1) * 36, 0)
        button.hex = hex
        button.shape = Shape.New(button)
        button:SetScript("OnClick", function()
            group:SetValue(hex)
            onSelect(hex)
        end)
        group.buttons[i] = button
    end

    function group:SetValue(hex)
        self.value = hex
        self:Paint()
    end

    function group:Paint()
        for _, button in ipairs(self.buttons) do
            local on = button.hex == self.value
            Shape.Paint(
                button.shape,
                math.min(Theme.radius, 5),
                Theme.FromHex(button.hex),
                on and Theme.colors.text or nil
            )
        end
    end

    return Widgets.Track(group)
end

--- An on/off switch.
---@param parent table
---@param onChange fun(value: boolean)
---@return table
function Widgets.Toggle(parent, onChange)
    local toggle = CreateFrame("Button", nil, parent)
    toggle:SetSize(38, 20)
    toggle.track = Shape.New(toggle)
    toggle.thumb = CreateFrame("Frame", nil, toggle)
    toggle.thumb:SetSize(14, 14)
    toggle.thumb.shape = Shape.New(toggle.thumb)

    function toggle:SetValue(value)
        self.value = value and true or false
        self:Paint()
    end

    function toggle:Paint()
        Shape.Paint(self.track, 10, self.value and Theme.accent or Theme.colors.hover, Theme.colors.line)
        Shape.Paint(self.thumb.shape, 6, self.value and Theme.colors.onAccent or Theme.colors.text, nil)
        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("LEFT", self.value and 21 or 3, 0)
    end

    toggle:SetScript("OnClick", function(self)
        self:SetValue(not self.value)
        onChange(self.value)
    end)
    return Widgets.Track(toggle)
end

--- A slider with its value at the right. format turns the value into text.
---@param parent table
---@param min number
---@param max number
---@param step number
---@param format fun(value: number): string
---@param onChange fun(value: number)
---@return table
function Widgets.Slider(parent, min, max, step, format, onChange)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(230, 20)
    local slider = CreateFrame("Slider", nil, holder)
    slider:SetPoint("LEFT")
    slider:SetSize(180, 20)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetHitRectInsets(0, 0, -4, -4)
    holder.bar = Widgets.Rect(slider, Theme.colors.line)
    holder.bar:SetPoint("LEFT")
    holder.bar:SetPoint("RIGHT")
    holder.bar:SetHeight(4)
    holder.thumb = slider:CreateTexture(nil, "OVERLAY")
    holder.thumb:SetSize(12, 16)
    slider:SetThumbTexture(holder.thumb)
    holder.readout = Widgets.Text(holder, 14, "muted")
    holder.readout:SetPoint("RIGHT")

    function holder:SetValue(value)
        self.silent = true
        slider:SetValue(value)
        self.silent = false
        self.readout:SetText(format(value))
    end

    function holder:Paint()
        self.thumb:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    end

    slider:SetScript("OnValueChanged", function(_, value, byUser)
        holder.readout:SetText(format(value))
        if byUser and not holder.silent then
            onChange(value)
        end
    end)
    return Widgets.Track(holder)
end

--- A dropdown. choices = { { value, text } }. A click anywhere else closes the menu.
---@param parent table
---@param choices table[]
---@param onSelect fun(value: any)
---@return table
function Widgets.Dropdown(parent, choices, onSelect)
    local dropdown = Widgets.Button(parent, "", "ghost", function() end)
    dropdown:SetWidth(240)
    dropdown.label:ClearAllPoints()
    dropdown.label:SetPoint("LEFT", 10, 0)

    -- Parented to UIParent: inside a scroll area the menu would be clipped.
    local menu = CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -4)
    menu:SetPoint("TOPRIGHT", dropdown, "BOTTOMRIGHT", 0, -4)
    menu:SetHeight(#choices * 32 + 8)
    menu:EnableMouse(true)
    menu:Hide()
    menu.shape = Shape.New(menu)
    function menu:Paint()
        Theme.PaintWindow(self.shape)
    end
    Widgets.Track(menu)

    dropdown:HookScript("OnHide", function()
        menu:Hide()
    end)
    menu:SetScript("OnShow", function(self)
        self:SetScale(dropdown:GetEffectiveScale() / UIParent:GetEffectiveScale())
        Events.On("GLOBAL_MOUSE_DOWN", self, function()
            if not self:IsMouseOver() and not dropdown:IsMouseOver() then
                self:Hide()
            end
        end)
    end)
    menu:SetScript("OnHide", function(self)
        Events.Off("GLOBAL_MOUSE_DOWN", self)
    end)

    function dropdown:SetValue(value)
        self.value = value
        for _, choice in ipairs(choices) do
            if choice[1] == value then
                self.label:SetText(choice[2])
            end
        end
    end

    for i, choice in ipairs(choices) do
        local row = Widgets.Button(menu, choice[2], "nav", function()
            menu:Hide()
            dropdown:SetValue(choice[1])
            onSelect(choice[1])
        end)
        row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 32)
        row:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * 32)
    end
    dropdown:SetScript("OnClick", function()
        menu:SetShown(not menu:IsShown())
    end)
    return dropdown
end

local popup

--- Closes the menu opened by Widgets.Menu, if any.
function Widgets.CloseMenu()
    if popup then
        popup:Hide()
    end
end

--- Opens a small menu under a frame. entries = { { text, onClick } }. A click elsewhere closes it.
---@param owner table
---@param entries table[]
---@param width number
function Widgets.Menu(owner, entries, width)
    if not popup then
        popup = CreateFrame("Frame", nil, UIParent)
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetClampedToScreen(true)
        popup:EnableMouse(true)
        popup:Hide()
        popup.shape = Shape.New(popup)
        function popup:Paint()
            Theme.PaintWindow(self.shape)
        end
        Widgets.Track(popup)
        popup.rows = {}
        popup:SetScript("OnShow", function(self)
            Events.On("GLOBAL_MOUSE_DOWN", self, function()
                if not self:IsMouseOver() then
                    self:Hide()
                end
            end)
        end)
        popup:SetScript("OnHide", function(self)
            Events.Off("GLOBAL_MOUSE_DOWN", self)
        end)
    end
    for i, entry in ipairs(entries) do
        local row = popup.rows[i]
        if not row then
            row = Widgets.Button(popup, "", "nav", function(self)
                popup:Hide()
                self.onPick()
            end)
            row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 32)
            row:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * 32)
            popup.rows[i] = row
        end
        row.label:SetText(entry.text)
        row.onPick = entry.onClick
        row:Show()
    end
    for i = #entries + 1, #popup.rows do
        popup.rows[i]:Hide()
    end
    popup:SetSize(width, #entries * 32 + 8)
    popup:ClearAllPoints()
    popup:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -4)
    popup:Show()
end

--- A scrolling area. Put content in .child and call SetContentHeight.
---@param parent table
---@return table
function Widgets.Scroll(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll.child = CreateFrame("Frame", nil, scroll)
    scroll.child:SetSize(1, 1)
    scroll:SetScrollChild(scroll.child)
    local thumb = scroll:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(4)

    local function place()
        local height = scroll:GetHeight()
        local range = math.max(scroll.child:GetHeight() - height, 0)
        scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), range))
        thumb:SetShown(range > 0)
        if range > 0 then
            local size = math.max(height * height / scroll.child:GetHeight(), 24)
            thumb:ClearAllPoints()
            thumb:SetPoint("TOPRIGHT", 0, -(height - size) * scroll:GetVerticalScroll() / range)
            thumb:SetHeight(size)
        end
    end

    function scroll:SetContentHeight(height)
        self.child:SetHeight(height)
        place()
    end

    --- Scrolls to the bottom of the content.
    function scroll:ScrollToEnd()
        self:SetVerticalScroll(math.max(self.child:GetHeight() - self:GetHeight(), 0))
        place()
    end

    --- Scrolls to an offset, within the content.
    ---@param offset number
    function scroll:ScrollTo(offset)
        local range = math.max(self.child:GetHeight() - self:GetHeight(), 0)
        self:SetVerticalScroll(math.max(0, math.min(offset, range)))
        place()
    end

    function scroll:Paint()
        local c = Theme.colors.lineStrong
        thumb:SetColorTexture(c[1], c[2], c[3], c[4])
    end

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = math.max(self.child:GetHeight() - self:GetHeight(), 0)
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScroll() - delta * 48, range)))
        place()
    end)
    scroll:SetScript("OnSizeChanged", function(self, width)
        self.child:SetWidth(width - 12)
        place()
    end)
    return Widgets.Track(scroll)
end

--- A color swatch that opens Blizzard's color picker.
---@param parent table
---@param onChange fun(hex: string)
---@return table
function Widgets.Color(parent, onChange)
    local swatch = CreateFrame("Button", nil, parent)
    swatch:SetSize(52, 26)
    swatch.shape = Shape.New(swatch)

    function swatch:SetValue(hex)
        self.value = hex
        self:Paint()
    end

    function swatch:Paint()
        if self.value then
            Shape.Paint(self.shape, math.min(Theme.radius, 5), Theme.RGBA(self.value), Theme.colors.lineStrong)
        end
    end

    swatch:SetScript("OnClick", function(self)
        local before = self.value
        local color = Theme.RGBA(before)
        ColorPickerFrame:SetupColorPickerAndShow({
            r = color[1],
            g = color[2],
            b = color[3],
            hasOpacity = false,
            swatchFunc = function()
                local hex = Theme.ToHex(ColorPickerFrame:GetColorRGB())
                self:SetValue(hex)
                onChange(hex)
            end,
            cancelFunc = function()
                self:SetValue(before)
                onChange(before)
            end,
        })
    end)
    return Widgets.Track(swatch)
end

--- A one-line text field. onEnter runs on Enter.
---@param parent table
---@param onEnter fun(text: string)?
---@return table
function Widgets.Input(parent, onEnter, placeholder)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetHeight(30)
    box:SetAutoFocus(false)
    box:SetTextInsets(10, 10, 0, 0)
    box.shape = Shape.New(box)
    if placeholder then
        local hint = Widgets.Text(box, 14, "muted")
        hint:SetPoint("LEFT", 10, 0)
        hint:SetText(placeholder)
        box:HookScript("OnTextChanged", function(self)
            hint:SetShown(self:GetText() == "")
        end)
    end

    function box:Paint()
        self:SetFont(Theme.font, 14 * Theme.fontScale, "")
        setColor(self, Theme.colors.text)
        Shape.Paint(self.shape, math.min(Theme.radius, 5), Theme.colors.hover, Theme.colors.line)
    end

    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if onEnter then
            onEnter(self:GetText())
        end
    end)
    return Widgets.Track(box)
end

--- A row of the options: label on the left, control on the right, a line below.
---@param parent table
---@param label string
---@param control table?
---@return table
function Widgets.Row(parent, label, control)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(40)
    row.label = Widgets.Text(row, 15, "text")
    row.label:SetPoint("LEFT")
    row.label:SetText(label)
    local line = Widgets.Rect(row, Theme.colors.line)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(ns.Pixel.Size(row))
    if control then
        control:SetParent(row)
        control:ClearAllPoints()
        control:SetPoint("RIGHT")
    end
    return row
end
