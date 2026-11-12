-- EternityUI_Chat: copy a chat window's text. A small button on each chat window (option
-- copy.button) or /etchat copy opens an Eternity window with that window's lines in a read-only,
-- multi-line text box: click it, Ctrl+A and Ctrl+C copy them.
--   * Lines come from the chat frame itself (GetNumMessages / GetMessageInfo), read only.
--   * Colors, textures and icons are removed and links keep their text ("[Hearthstone]").
--   * Protected text can't be read: a secret line, or a |K...|k string inside one, shows as
--     "(protected)" instead. Nothing is compared or cut on a secret value.
-- The window looks like Eternity's options window: the theme's surface, opacity and edge, its
-- shadow, the "window" background image and the options' scale.
-- Taint: the buttons are our own frames in UIParent, following their chat window through
-- HookScript; nothing is written into Blizzard's frames. No secure templates: the window and the
-- buttons stay plain frames, so they also open and close in combat.

---@type string, EternityUIChatNamespace
local _, ns = ...
local E = EternityUI
local Theme, Widgets, UI = E.Theme, E.Widgets, ns.UI
local opt, L = ns.opt, ns.L

local WIDTH, HEIGHT = 640, 460
local PAD = 12
local BUTTON = 20
local GLYPH = 8

---@class EternityUIChatCopy
---@field buttons table<table, table> chat frame -> its copy button
---@field window table?
local Copy = { buttons = {} }
ns.Copy = Copy

-- Text --------------------------------------------------------------------------------------

local PIPE = "\2"
local PROTECTED = "\1"

--- A chat line as plain, readable text. A secret line is "(protected)".
---@param text any
---@return string
function Copy.Clean(text)
    if ns.secret(text) then
        return L.PROTECTED
    end
    if type(text) ~= "string" then
        return ""
    end
    text = text:gsub("||", PIPE)
    text = text:gsub("|K.-|k", PROTECTED) -- protected strings (names of Battle.net friends...)
    text = text:gsub("|H.-|h(.-)|h", "%1") -- links: their shown text
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|cn[^:|]*:", "") -- named colors (|cnGREEN_FONT_COLOR:)
    text = text:gsub("|r", "")
    text = text:gsub("|T.-|t", "") -- textures and icons
    text = text:gsub("|A.-|a", "") -- atlases
    text = text:gsub("|n", "\n")
    text = text:gsub(PROTECTED, L.PROTECTED)
    -- A literal pipe goes back escaped, so the text box shows it as one.
    text = text:gsub(PIPE, "||")
    return text
end

--- A chat frame's lines, oldest first, cleaned.
---@param frame table a chat frame (ScrollingMessageFrame)
---@return string[]
function Copy.Lines(frame)
    local lines = {}
    if not (frame and frame.GetNumMessages and frame.GetMessageInfo) then
        return lines
    end
    local ok, count = pcall(frame.GetNumMessages, frame)
    if not ok or ns.secret(count) or type(count) ~= "number" then
        return lines
    end
    for index = 1, count do
        local read, text = pcall(frame.GetMessageInfo, frame, index)
        lines[#lines + 1] = read and Copy.Clean(text) or L.PROTECTED
    end
    return lines
end

--- The name of a chat window, as its tab shows it.
---@param frame table
---@return string
function Copy.WindowName(frame)
    local name
    if frame.GetID and GetChatWindowInfo then
        local ok, value = pcall(GetChatWindowInfo, frame:GetID())
        name = ok and value or nil
    end
    if ns.secret(name) or type(name) ~= "string" or name == "" then
        local tab = frame.GetName and frame:GetName() and _G[frame:GetName() .. "Tab"]
        name = tab and tab.GetText and tab:GetText()
    end
    if ns.secret(name) or type(name) ~= "string" or name == "" then
        name = L.CHAT
    end
    return name
end

-- Window ------------------------------------------------------------------------------------

function Copy:Build()
    local w = Widgets.Window("EternityUIChatCopy", L.COPY, true)
    w:SetSize(WIDTH, HEIGHT)
    w:SetFrameStrata("DIALOG")
    w:SetToplevel(true)
    w:SetPoint("CENTER")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        frame:SetUserPlaced(false)
    end)
    -- The options window's background image (General > Appearance), over the theme's surface.
    w.wallpaper = Theme.NewWallpaper(w)
    w:HookScript("OnSizeChanged", function(frame)
        Theme.PaintWallpaper(frame.wallpaper, "window")
    end)

    local box = CreateFrame("ScrollFrame", nil, w.body)
    box:SetPoint("TOPLEFT", PAD, -PAD)
    box:SetPoint("BOTTOMRIGHT", -PAD, 0)
    box.shape = E.Shape.New(box)
    local edit = CreateFrame("EditBox", nil, box)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetTextInsets(8, 8, 8, 8)
    edit:SetWidth(WIDTH - PAD * 2)
    box:SetScrollChild(edit)
    box:EnableMouseWheel(true)
    local function range()
        return math.max(edit:GetHeight() - box:GetHeight(), 0)
    end
    box:SetScript("OnMouseWheel", function(self, delta)
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScroll() - delta * 48, range())))
    end)
    box:SetScript("OnSizeChanged", function(_, width)
        edit:SetWidth(width)
    end)
    box:SetScript("OnMouseDown", function()
        edit:SetFocus()
    end)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    edit:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    -- Read-only: typing puts the lines back.
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(w.text or "")
        end
    end)
    w:HookScript("OnHide", function()
        edit:ClearFocus()
    end)
    w.box, w.edit = box, edit
    function w.ScrollToEnd()
        box:SetVerticalScroll(range())
    end

    w.hint = Widgets.Text(w.footer, 12, "muted")
    w.hint:SetPoint("LEFT", PAD, 0)
    w.hint:SetPoint("RIGHT", -PAD, 0)
    w.hint:SetJustifyH("LEFT")
    w.hint:SetText(L.COPY_HINT)

    function w.onPaint(frame)
        Theme.PaintWallpaper(frame.wallpaper, "window")
        frame:SetScale(E.store:Get("EternityUI", "general.optionsScale") or 1)
        edit:SetFont(Theme.font, 13 * Theme.fontScale, "")
        local c = Theme.colors.text
        edit:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        E.Shape.Paint(box.shape, math.min(Theme.radius, 5), Theme.colors.hover, Theme.colors.line)
    end
    w:Paint()
    self.window = w
    -- The options' scale isn't part of the theme: it's repainted when it changes.
    E.Events.Listen(E.CONFIG_CHANGED, Copy, function(_, module, path)
        if module == "EternityUI" and path == "general.optionsScale" then
            w:Paint()
        end
    end)
    return w
end

--- Opens the copy window with a chat frame's lines (the newest at the bottom, in view).
---@param frame table? a chat frame; the selected one by default
function Copy:Open(frame)
    frame = frame or _G.SELECTED_CHAT_FRAME or _G.DEFAULT_CHAT_FRAME or _G.ChatFrame1
    if not frame then
        return
    end
    local w = self.window or self:Build()
    local lines = Copy.Lines(frame)
    w.source = frame
    w.text = #lines > 0 and table.concat(lines, "\n") or L.COPY_EMPTY
    w.title:SetText(L.COPY_TITLE:format(Copy.WindowName(frame)))
    w.edit:SetText(w.text)
    w:Show()
    w:Raise()
    w.ScrollToEnd()
    -- The box takes its height from the text on the next frame.
    C_Timer.After(0, function()
        if w:IsShown() and w.source == frame then
            w.ScrollToEnd()
        end
    end)
end

-- Buttons -----------------------------------------------------------------------------------

-- Two overlapping squares: the "copy" icon.
local function glyph(parent)
    local icon = { lines = {}, fill = parent:CreateTexture(nil, "ARTWORK", nil, 1) }
    local function square(x, y, layer)
        local edges = {
            { "TOPLEFT", x, y, GLYPH, 1 },
            { "TOPLEFT", x, y - GLYPH + 1, GLYPH, 1 },
            { "TOPLEFT", x, y, 1, GLYPH },
            { "TOPLEFT", x + GLYPH - 1, y, 1, GLYPH },
        }
        for _, edge in ipairs(edges) do
            local line = parent:CreateTexture(nil, "ARTWORK", nil, layer)
            line:SetPoint(edge[1], parent, "CENTER", edge[2], edge[3])
            line:SetSize(edge[4], edge[5])
            icon.lines[#icon.lines + 1] = line
        end
    end
    square(-GLYPH / 2 - 1, GLYPH / 2 + 1, 0) -- back
    icon.fill:SetPoint("TOPLEFT", parent, "CENTER", -GLYPH / 2 + 2, GLYPH / 2 - 1)
    icon.fill:SetSize(GLYPH, GLYPH)
    square(-GLYPH / 2 + 2, GLYPH / 2 - 1, 2) -- front, over its own fill
    function icon.SetColors(_, line, fill)
        for _, texture in ipairs(icon.lines) do
            texture:SetColorTexture(Theme.Color(line))
        end
        icon.fill:SetColorTexture(Theme.Color(fill))
    end
    return icon
end

function Copy:CreateButton(frame)
    local b = CreateFrame("Button", nil, UIParent)
    b:SetSize(BUTTON, BUTTON)
    b.shape = UI.Shape(b, "pill")
    b.icon = glyph(b)
    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnClick", function()
        self:Open(frame)
    end)
    E.Widgets.AttachTooltip(b, function(tip)
        tip:SetTitle(L.COPY)
        tip:AddHint(L.COPY_BUTTON_HINT)
    end, "TOP")
    UI.TrackHover(b, function(button)
        button:Paint()
    end)
    function b.Paint(button)
        local fill = button.hovered and "accent" or "window"
        button.shape:SetColors(fill, "borderStrong")
        button.icon:SetColors(button.hovered and "onAccent" or "text", fill)
        button:SetAlpha(button.hovered and 1 or 0.6)
    end
    local function follow()
        self:ApplyButton(frame)
    end
    frame:HookScript("OnShow", follow)
    frame:HookScript("OnHide", follow)
    self.buttons[frame] = E.Widgets.Track(b)
    return b
end

--- A chat frame's button: in its top right corner, shown with it while the option is on.
---@param frame table
function Copy:ApplyButton(frame)
    local want = ns.running and opt("copy.button") and true or false
    local b = self.buttons[frame]
    if not b then
        if not want then
            return
        end
        b = self:CreateButton(frame)
    end
    local show = want and frame:IsShown()
    b:SetShown(show)
    if not show then
        return
    end
    b:SetFrameStrata(frame:GetFrameStrata())
    b:SetFrameLevel(frame:GetFrameLevel() + 10)
    b:ClearAllPoints()
    b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
end

--- Every chat window's button (also the temporary whisper windows).
function Copy:Apply()
    for _, frame in ipairs(ns.Skin.ChatFrames()) do
        self:ApplyButton(frame)
    end
    for frame in pairs(self.buttons) do
        self:ApplyButton(frame)
    end
    if not ns.running and self.window then
        self.window:Hide()
    end
end
