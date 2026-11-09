-- EternityUI_Chat: the look of Blizzard's chat windows and the modes.
--   * Background, tabs and input box: Blizzard's textures go into a hidden parent and our shapes
--     are drawn instead; fonts and the input box position are changed with widget calls.
--   * One window: the dock's tab bar is hidden. Tabs: whispers can open in their own tab (Blizzard's
--     whisperMode while the mode is on; the player's value comes back afterwards).
-- Taint (lessons from EllesmereUI): nothing is written into Blizzard's frame tables (our state
-- lives in our own tables, keyed by frame); hooks are hooksecurefunc and HookScript only, and
-- the work they trigger is deferred to the next frame (C_Timer.After(0)), out of Blizzard's
-- chains. FCFTab_UpdateColors and FCF_SetChatWindowFontSize are never hooked.

---@type string, EternityUIChatNamespace
local _, ns = ...
local E = EternityUI
local Theme, UI = E.Theme, ns.UI
local opt = ns.opt

local TAB_PADDING, TAB_HEIGHT = 10, 22

local FRAME_TEXTURES = {
    "Background",
    "TopLeftTexture",
    "BottomLeftTexture",
    "TopRightTexture",
    "BottomRightTexture",
    "LeftTexture",
    "RightTexture",
    "BottomTexture",
    "TopTexture",
}
local SIDE_TEXTURES = {
    "ButtonFrameBackground",
    "ButtonFrameTopLeftTexture",
    "ButtonFrameBottomLeftTexture",
    "ButtonFrameTopRightTexture",
    "ButtonFrameBottomRightTexture",
    "ButtonFrameLeftTexture",
    "ButtonFrameRightTexture",
    "ButtonFrameBottomTexture",
    "ButtonFrameTopTexture",
}
local TAB_TEXTURES = {
    "Left",
    "Middle",
    "Right",
    "ActiveLeft",
    "ActiveMiddle",
    "ActiveRight",
    "HighlightLeft",
    "HighlightMiddle",
    "HighlightRight",
}
local EDIT_TEXTURES = { "Left", "Right", "Mid", "FocusLeft", "FocusRight", "FocusMid" }
-- Blizzard buttons per option.
local BUTTONS = {
    menu = { "ChatFrameMenuButton" },
    channels = { "ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton" },
    social = { "QuickJoinToastButton" },
    speech = { "TextToSpeechButtonFrame" },
}

---@class EternityUIChatSkin
---@field running boolean?
---@field hooked boolean?
---@field hidden table<table, table> Blizzard region -> its original parent (or { texture = file })
---@field fonts table<table, table> chat frame or tab text -> original font
---@field points table<table, table[]> input box -> original points
---@field decor table<table, table> chat frame / tab / input box -> our drawing
---@field whisperMode string? the player's whisperMode while ours is applied
local ChatSkin = { hidden = {}, fonts = {}, points = {}, decor = {}, placed = {}, placeHooks = {} }
ns.Skin = ChatSkin

local hider = CreateFrame("Frame")
hider:Hide()

-- Hiding and restoring Blizzard regions -----------------------------------------------------

local function hide(region)
    if not region or ChatSkin.hidden[region] then
        return
    end
    -- Regions accept SetParent; if one doesn't, its texture is cleared instead.
    local parent = region:GetParent()
    if pcall(region.SetParent, region, hider) then
        ChatSkin.hidden[region] = { parent = parent }
    elseif region.GetTexture then
        ChatSkin.hidden[region] = { texture = region:GetTexture() }
        region:SetTexture(nil)
    end
end

local function restore(region)
    local saved = region and ChatSkin.hidden[region]
    if not saved then
        return
    end
    ChatSkin.hidden[region] = nil
    if saved.parent then
        region:SetParent(saved.parent)
    else
        region:SetTexture(saved.texture)
    end
end

local function setHidden(region, hidden)
    if hidden then
        hide(region)
    else
        restore(region)
    end
end

-- Chat frames -------------------------------------------------------------------------------

local function chatFrames()
    local list = {}
    for _, name in ipairs(_G.CHAT_FRAMES or {}) do
        local frame = _G[name]
        if frame then
            list[#list + 1] = frame
        end
    end
    return list
end
ChatSkin.ChatFrames = chatFrames

local function fontPath()
    local path = Theme.font
    return path
end

--- Our background behind a chat frame: a sibling in UIParent below it, shown with it.
local function background(frame)
    local decor = ChatSkin.decor[frame]
    if decor then
        return decor
    end
    decor = CreateFrame("Frame", nil, UIParent)
    decor.shape = UI.Shape(decor, "card")
    decor.shadow = UI.Shadow(decor)
    decor.wallpaper = Theme.NewWallpaper(decor)
    decor:SetScript("OnSizeChanged", function(self)
        Theme.PaintWallpaper(self.wallpaper, "chat", opt("background.opacity") > 0)
    end)
    ChatSkin.decor[frame] = decor
    local function follow()
        ChatSkin:ApplyBackground(frame)
    end
    frame:HookScript("OnShow", follow)
    frame:HookScript("OnHide", follow)
    return decor
end

function ChatSkin:ApplyBackground(frame)
    local style = self.running and opt("background.style") or "blizzard"
    local name = frame:GetName()
    for _, key in ipairs(FRAME_TEXTURES) do
        setHidden(_G[name .. key], style ~= "blizzard")
    end
    local decor = (style == "eternity" or self.decor[frame]) and background(frame)
    if not decor then
        return
    end
    local show = style == "eternity" and frame:IsShown()
    decor:SetShown(show)
    if not show then
        return
    end
    local pad = opt("background.padding")
    decor:SetFrameStrata(frame:GetFrameStrata())
    decor:SetFrameLevel(math.max(frame:GetFrameLevel() - 1, 0))
    decor:ClearAllPoints()
    decor:SetPoint("TOPLEFT", frame, "TOPLEFT", -pad, pad)
    decor:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", pad, -pad)
    local alpha = opt("background.opacity")
    local r, g, b = Theme.Color("window")
    decor.shape:SetColors({ r, g, b, alpha }, opt("background.border") and "border" or nil)
    Theme.PaintWallpaper(decor.wallpaper, "chat", alpha > 0)
    decor.shadow:Update()
    if not opt("background.shadow") or alpha == 0 then
        decor.shadow:Hide()
    end
    self:ApplyCombat(frame)
end

--- The background's opacity for now: lower in combat if that option is on. Only our background
--- frame (a sibling of the chat): the messages keep theirs. Not protected, so also in combat.
---@param frame table a chat frame
function ChatSkin:ApplyCombat(frame)
    local decor = self.decor[frame]
    if not decor then
        return
    end
    local fight = InCombatLockdown() or UnitAffectingCombat("player")
    if self.running and opt("background.combatFade") and fight then
        decor:SetAlpha(opt("background.combatOpacity"))
    else
        decor:SetAlpha(1)
    end
end

function ChatSkin:ApplyFont(frame)
    if not self.fonts[frame] then
        local path, size, flags = frame:GetFont()
        local sx, sy = frame:GetShadowOffset()
        self.fonts[frame] = { path = path, size = size, flags = flags, sx = sx, sy = sy }
    end
    local saved = self.fonts[frame]
    if not self.running then
        if saved.path then
            frame:SetFont(saved.path, saved.size, saved.flags)
        end
        frame:SetShadowOffset(saved.sx or 0, saved.sy or 0)
        self.fonts[frame] = nil
        return
    end
    local outline = opt("text.outline")
    local path = opt("text.font") == "theme" and fontPath() or saved.path
    if path then
        frame:SetFont(path, opt("text.size"), outline ~= "none" and outline or "")
    end
    if opt("text.shadow") then
        frame:SetShadowOffset(1, -1)
    else
        frame:SetShadowOffset(0, 0)
    end
end

-- Tabs --------------------------------------------------------------------------------------

local function tabDecor(tab)
    local decor = ChatSkin.decor[tab]
    if decor then
        return decor
    end
    decor = {
        shape = UI.Shape(tab, "control"),
        line = tab:CreateTexture(nil, "ARTWORK"),
    }
    decor.line:SetHeight(2)
    -- Around the tab's text, which Blizzard doesn't center in the tab.
    local text = tab.Text or (tab:GetName() and _G[tab:GetName() .. "Text"])
    if text then
        for _, texture in ipairs({ decor.shape.fill, decor.shape.border }) do
            texture:ClearAllPoints()
            texture:SetPoint("LEFT", text, "LEFT", -TAB_PADDING, 0)
            texture:SetPoint("RIGHT", text, "RIGHT", TAB_PADDING, 0)
            texture:SetHeight(TAB_HEIGHT)
        end
        decor.line:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -3)
        decor.line:SetPoint("TOPRIGHT", text, "BOTTOMRIGHT", 0, -3)
    end
    ChatSkin.decor[tab] = decor
    tab:HookScript("OnEnter", function()
        decor.hovered = true
        ChatSkin:ApplyTab(tab)
    end)
    tab:HookScript("OnLeave", function()
        decor.hovered = false
        ChatSkin:ApplyTab(tab)
    end)
    return decor
end

function ChatSkin:ApplyTab(tab, frame)
    frame = frame or (tab:GetName() and _G[tab:GetName():gsub("Tab$", "")])
    local style = self.running and opt("tabs.style") or "blizzard"
    for _, key in ipairs(TAB_TEXTURES) do
        setHidden(tab[key], style ~= "blizzard")
    end
    local text = tab.Text or (tab:GetName() and _G[tab:GetName() .. "Text"])
    if text then
        if not self.fonts[text] then
            local path, size, flags = text:GetFont()
            self.fonts[text] = { path = path, size = size, flags = flags }
        end
        local saved = self.fonts[text]
        if style == "blizzard" then
            if saved.path then
                text:SetFont(saved.path, saved.size, saved.flags)
            end
        elseif saved.path then
            text:SetFont(opt("text.font") == "theme" and fontPath() or saved.path, opt("tabs.size"), "")
        end
    end
    local decor = (style ~= "blizzard" or self.decor[tab]) and tabDecor(tab)
    if not decor then
        return
    end
    local selected = frame and frame:IsShown()
    if style == "pill" then
        local fill = selected and "accentSoft" or (decor.hovered and "surfaceHover" or nil)
        decor.shape:SetColors(fill, selected and "accent" or nil)
    else
        decor.shape:SetColors(nil, nil)
    end
    decor.line:SetShown(style == "underline" and selected and true or false)
    decor.line:SetColorTexture(Theme.Color("accent"))
end

-- Input box ---------------------------------------------------------------------------------

local function editDecor(box)
    local decor = ChatSkin.decor[box]
    if decor then
        return decor
    end
    decor = CreateFrame("Frame", nil, UIParent)
    decor.shape = UI.Shape(decor, "control")
    ChatSkin.decor[box] = decor
    local function follow()
        ChatSkin:ApplyEditBox(box)
    end
    box:HookScript("OnShow", follow)
    box:HookScript("OnHide", follow)
    box:HookScript("OnEditFocusGained", follow)
    box:HookScript("OnEditFocusLost", follow)
    return decor
end

function ChatSkin:ApplyEditBox(box, frame)
    local style = self.running and opt("editBox.style") or "blizzard"
    local name = box:GetName()
    for _, key in ipairs(EDIT_TEXTURES) do
        setHidden(_G[name .. key], style ~= "blizzard")
    end
    -- Position: above the chat (over its tab) or Blizzard's place below it.
    -- Not GetParent: Blizzard can reparent the box, chatFrame is always its window.
    frame = frame or box.chatFrame or box:GetParent()
    local top = self.running and opt("editBox.position") == "top"
    if top and not self.points[box] and frame then
        local points = {}
        for i = 1, box:GetNumPoints() do
            points[i] = { box:GetPoint(i) }
        end
        self.points[box] = points
        local pad = opt("background.padding")
        box:ClearAllPoints()
        box:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", -5, pad + 26)
        box:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 5, pad + 26)
    elseif not top and self.points[box] then
        box:ClearAllPoints()
        for _, p in ipairs(self.points[box]) do
            box:SetPoint(unpack(p))
        end
        self.points[box] = nil
    end
    local decor = (style == "eternity" or self.decor[box]) and editDecor(box)
    if not decor then
        return
    end
    local show = style == "eternity" and box:IsShown()
    decor:SetShown(show)
    if not show then
        return
    end
    decor:SetFrameStrata(box:GetFrameStrata())
    decor:SetFrameLevel(math.max(box:GetFrameLevel() - 1, 0))
    decor:ClearAllPoints()
    -- As wide as the chat's background: the box's own edges stick out past it by a few units.
    local pad = opt("background.style") == "eternity" and opt("background.padding") or 0
    local left, right = 4, -4
    if frame and frame:GetLeft() and box:GetLeft() then
        left = frame:GetLeft() - pad - box:GetLeft()
        right = frame:GetRight() + pad - box:GetRight()
    end
    decor:SetPoint("TOPLEFT", box, "TOPLEFT", left, -3)
    decor:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", right, 3)
    local focused = box:HasFocus()
    local r, g, b = Theme.Color("window")
    -- While typing the field sits on the window color, so it reads the same over any background.
    -- Otherwise it follows the chat's background: Eternity's opacity and border, nothing at all
    -- without a background, and the solid field over Blizzard's.
    local backdrop = opt("background.style")
    local alpha, border = 0.92, "borderStrong"
    if focused then
        border = "focus"
    elseif backdrop == "eternity" then
        alpha = opt("background.opacity")
        border = opt("background.border") and "borderStrong" or nil
    elseif backdrop == "none" then
        alpha, border = 0, nil
    end
    decor.shape:SetColors({ r, g, b, alpha }, border)
end

-- Buttons and modes -------------------------------------------------------------------------

-- Blizzard frames anchored elsewhere (the chat's alert frame, the scroll to bottom buttons): their
-- points are saved and given back. Blizzard may anchor them again: everything is applied again on
-- the next frame.
---@param frame table
---@param place fun(frame: table)? sets the new points; nil gives Blizzard's back
function ChatSkin:Place(frame, place)
    if not frame then
        return
    end
    local saved = self.placed[frame]
    if place then
        if not saved then
            saved = {}
            for i = 1, frame:GetNumPoints() do
                saved[i] = { frame:GetPoint(i) }
            end
            self.placed[frame] = saved
        end
        if not self.placeHooks[frame] then
            self.placeHooks[frame] = true
            hooksecurefunc(frame, "SetPoint", function(placedFrame)
                if not self.placing and self.placed[placedFrame] then
                    self:Schedule()
                end
            end)
        end
        self.placing = true
        frame:ClearAllPoints()
        place(frame)
        self.placing = false
    elseif saved then
        self.placed[frame] = nil
        self.placing = true
        frame:ClearAllPoints()
        for _, p in ipairs(saved) do
            frame:SetPoint(unpack(p))
        end
        self.placing = false
    end
end

-- How far our background reaches past the chat's text (0 without it).
local function backgroundPadding()
    return opt("background.style") == "eternity" and opt("background.padding") or 0
end

--- The social button (it lives in ChatAlertFrame with the chat's other alerts) and the scroll to
--- bottom buttons, which Blizzard anchors over the resize grip: in our background's corner.
function ChatSkin:ApplyPlacements()
    local main = _G.DEFAULT_CHAT_FRAME or _G.ChatFrame1
    local where = self.running and opt("buttons.socialPosition") or "blizzard"
    if main and where ~= "blizzard" then
        local pad, x, y = backgroundPadding(), opt("buttons.socialX"), opt("buttons.socialY")
        self:Place(_G.ChatAlertFrame, function(alert)
            if where == "left" then
                alert:SetPoint("BOTTOMRIGHT", main, "BOTTOMLEFT", -pad - 4 + x, -pad + y)
            elseif where == "right" then
                alert:SetPoint("BOTTOMLEFT", main, "BOTTOMRIGHT", pad + 4 + x, -pad + y)
            else
                alert:SetPoint("BOTTOMLEFT", main, "TOPLEFT", -pad + x, pad + TAB_HEIGHT + 4 + y)
            end
        end)
    else
        self:Place(_G.ChatAlertFrame, nil)
    end
    local aligned = self.running and opt("background.style") == "eternity"
    for _, frame in ipairs(chatFrames()) do
        local button, bar = frame.ScrollToBottomButton, frame.ScrollBar
        if aligned and button and bar then
            -- One column, centered: Blizzard lines the bar and the button up by their left edges,
            -- and they aren't the same width, so the button's arrow sat off the bar's. Both are
            -- anchored by their centers on the column where Blizzard puts the bar (just right of the
            -- frame); the button goes down to our background's bottom edge.
            local half = (bar:GetWidth() or 0) / 2
            local inset = math.min(backgroundPadding(), 2)
            self:Place(button, function(scroll)
                scroll:SetPoint("BOTTOM", frame, "BOTTOMRIGHT", half, inset - backgroundPadding())
            end)
            self:Place(bar, function(scrollBar)
                scrollBar:SetPoint("TOP", frame, "TOPRIGHT", half, 0)
                scrollBar:SetPoint("BOTTOM", button, "TOP", 0, 2)
            end)
        else
            self:Place(button, nil)
            self:Place(bar, nil)
        end
    end
end

function ChatSkin:ApplyButtons()
    for option, names in pairs(BUTTONS) do
        local show = not self.running or opt("buttons." .. option)
        for _, name in ipairs(names) do
            setHidden(_G[name], not show)
        end
    end
    local side = not self.running or opt("buttons.side")
    for _, frame in ipairs(chatFrames()) do
        local name = frame:GetName()
        for _, key in ipairs(SIDE_TEXTURES) do
            setHidden(_G[name .. key], not side)
        end
        local buttonFrame = _G[name .. "ButtonFrame"]
        if buttonFrame and buttonFrame.minimizeButton then
            setHidden(buttonFrame.minimizeButton, not side)
        end
    end
end

--- One window: the dock's tab bar (with the docked tabs) is hidden.
function ChatSkin:ApplyMode()
    local dock = _G.GeneralDockManager
    if dock then
        setHidden(dock, self.running and opt("mode.style") == "single")
    end
    local want = self.running and opt("mode.style") == "tabs" and opt("mode.whisperTabs")
    local db = ns.DB()
    if want and not db.whisperMode then
        db.whisperMode = GetCVar("whisperMode") or "inline"
        SetCVar("whisperMode", "popout")
    elseif not want and db.whisperMode then
        SetCVar("whisperMode", db.whisperMode)
        db.whisperMode = nil
    end
end

--- Everything, for every chat window (also the temporary whisper ones).
function ChatSkin:ApplyAll()
    for _, frame in ipairs(chatFrames()) do
        self:ApplyBackground(frame)
        self:ApplyFont(frame)
        local name = frame:GetName()
        local tab = _G[name .. "Tab"]
        if tab then
            self:ApplyTab(tab, frame)
        end
        local box = _G[name .. "EditBox"]
        if box then
            self:ApplyEditBox(box, frame)
        end
    end
    self:ApplyButtons()
    self:ApplyPlacements()
    self:ApplyMode()
end

function ChatSkin:Schedule()
    if self.pending then
        return
    end
    self.pending = true
    C_Timer.After(0, function()
        self.pending = false
        if self.running then
            self:ApplyAll()
        end
    end)
end

function ChatSkin:InstallHooks()
    self.hooked = true
    for _, name in ipairs({
        "FCF_OpenTemporaryWindow",
        "FCF_Close",
        "FCFDock_SelectWindow",
        "FCF_DockFrame",
        "FCF_UnDockFrame",
    }) do
        if type(_G[name]) == "function" then
            hooksecurefunc(name, function()
                self:Schedule()
            end)
        end
    end
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS" }) do
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", function()
        if self.running then
            self:Schedule()
        end
    end)
    E.Events.Listen(Theme.CHANGED, self, function()
        if self.running then
            self:Schedule()
        end
    end)
end

local function onCombat()
    for frame in pairs(ChatSkin.decor) do
        ChatSkin:ApplyCombat(frame)
    end
end

function ChatSkin:Start()
    self.running = true
    if not self.hooked then
        self:InstallHooks()
    end
    -- In and out of combat: the background's combat opacity.
    E.Events.On("PLAYER_REGEN_DISABLED", self, onCombat)
    E.Events.On("PLAYER_REGEN_ENABLED", self, onCombat)
    self:ApplyAll()
end

function ChatSkin:Stop()
    self.running = false
    E.Events.Off("PLAYER_REGEN_DISABLED", self)
    E.Events.Off("PLAYER_REGEN_ENABLED", self)
    self:ApplyAll()
end
