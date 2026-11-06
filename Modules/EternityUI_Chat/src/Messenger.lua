-- EternityUI_Chat: the messenger, a messaging-app window over the conversations of History.lua.
--   * Left: the conversations, most recent first, with avatar, level, last message, time and
--     unread count, and a search box. Right: the open one as bubbles (mine on the right in the
--     accent color, theirs on the left), with day separators and a box to write.
--   * Sending uses Blizzard's chat API from the Enter key or the button (a hardware event).
--     While Blizzard restricts the chat, the text goes to Blizzard's chat box instead.
--   * A button on the main chat window opens it and shows the unread count.

---@type string, EternityUIChatNamespace
local addonName, ns = ...
local E = EternityUI
local Theme, UI = E.Theme, ns.UI
local opt, L = ns.opt, ns.L

local NEW_WHISPER_SOUND = 3081 -- SOUNDKIT.TELL_MESSAGE
-- The Width and Height options' limits and step: the grip can't go past what they store.
local MIN_WIDTH, MIN_HEIGHT = 420, 300
local MAX_WIDTH, MAX_HEIGHT = 1400, 1000
local SIZE_STEP = 10
local BAR_HEIGHT = 40
local DAY = 86400
-- Avatar letter for the conversations that aren't a player.
local LETTERS =
    { guild = "G", officer = "O", party = "P", raid = "R", instance = "I", say = "S", channel = "#", bnet = "B" }
-- Chat type to send each kind with, and Blizzard's slash prefix when the chat is restricted.
local SEND = {
    guild = { "GUILD", "/g " },
    officer = { "OFFICER", "/o " },
    party = { "PARTY", "/p " },
    raid = { "RAID", "/ra " },
    instance = { "INSTANCE_CHAT", "/i " },
    say = { "SAY", "/s " },
}

---@class EternityUIChatMessenger
---@field running boolean?
---@field frame table? the window
---@field selected string? key of the open conversation
---@field rows table[]
---@field bubbles table[]
---@field separators table[]
local Messenger = { rows = {}, bubbles = {}, separators = {} }
ns.Messenger = Messenger

local function hexToRGB(hex)
    local r, g, b = Theme.Color(hex)
    return r, g, b
end

local function fontPath()
    local path = Theme.font
    return path
end

local function compact()
    return opt("bubbles.density") == "compact"
end

local function locked()
    return C_ChatInfo ~= nil and C_ChatInfo.InChatMessagingLockdown ~= nil and C_ChatInfo.InChatMessagingLockdown()
end

local function dayLabel(t)
    local today = date("%Y%m%d")
    if date("%Y%m%d", t) == today then
        return L.TODAY
    elseif date("%Y%m%d", t + DAY) == today then
        return L.YESTERDAY
    end
    return date("%d/%m/%Y", t)
end

local function shortTime(t)
    if date("%Y%m%d", t) == date("%Y%m%d") then
        return date("%H:%M", t)
    end
    return date("%d/%m", t)
end

-- Avatars -----------------------------------------------------------------------------------

-- The class of a conversation: a player met only after it started is known by now.
local function conversationClass(conversation)
    if not conversation.class and conversation.kind == "whisper" then
        conversation.class = ns.Players:KnownClass(conversation.target)
    end
    return conversation.class
end

--- Avatar: a pill with the class icon, or the conversation's letter.
local function createAvatar(parent, size)
    local avatar = CreateFrame("Frame", nil, parent)
    avatar:SetSize(size, size)
    avatar.shape = UI.Shape(avatar, "pill")
    avatar.icon = avatar:CreateTexture(nil, "ARTWORK")
    avatar.icon:SetPoint("TOPLEFT", 2, -2)
    avatar.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    avatar.letter = UI.Text(avatar, "", "small", "onAccent")
    avatar.letter:SetPoint("CENTER")
    function avatar.Set(_, kind, class, title)
        local atlas = class and ns.Players:IconAtlas(class, nil, nil, "class")
        avatar.icon:SetShown(atlas ~= nil)
        avatar.letter:SetShown(atlas == nil)
        if atlas then
            avatar.icon:SetAtlas(atlas)
            avatar.shape:SetColors("field", "border")
        else
            avatar.letter:SetText(LETTERS[kind] or (title or "?"):sub(1, 1):upper())
            avatar.shape:SetColors("accent", nil, "accentHover")
        end
    end
    return avatar
end

-- Conversation list -------------------------------------------------------------------------

function Messenger:Row(index)
    local row = self.rows[index]
    if row then
        return row
    end
    local list = self.frame.listContent
    row = CreateFrame("Button", nil, list)
    row.shape = UI.Shape(row, "card")
    row.avatar = createAvatar(row, 32)
    row.title = UI.Text(row, "", "body")
    row.title:SetWordWrap(false)
    row.preview = UI.Text(row, "", "small", "textMuted")
    row.preview:SetWordWrap(false)
    row.time = UI.Text(row, "", "caption", "textMuted")
    row.badge = CreateFrame("Frame", nil, row)
    row.badge.shape = UI.Shape(row.badge, "pill")
    row.badge.text = UI.Text(row.badge, "", "caption", "onAccent")
    row.badge.text:SetPoint("CENTER")
    row:SetScript("OnClick", function(button)
        self:Select(button.key)
    end)
    UI.TrackHover(row, function(button)
        self:PaintRow(button)
    end)
    self.rows[index] = row
    return row
end

function Messenger:PaintRow(row)
    local selected = row.key == self.selected
    row.shape:SetColors(
        selected and "accentSoft" or (row.hovered and "surfaceHover" or nil),
        selected and "accent" or nil
    )
end

function Messenger:LayoutRow(row, conversation)
    local small = compact()
    local height = small and 40 or 52
    local avatarSize = small and 24 or 32
    row:SetHeight(height)
    row.key = conversation.key
    local avatars = opt("bubbles.avatars")
    row.avatar:SetShown(avatars)
    row.avatar:SetSize(avatarSize, avatarSize)
    row.avatar:ClearAllPoints()
    row.avatar:SetPoint("LEFT", UI.space.sm, 0)
    row.avatar:Set(conversation.kind, conversationClass(conversation), conversation.title)
    local left = avatars and (avatarSize + 2 * UI.space.sm) or UI.space.sm
    local title = conversation.title or "?"
    local color = conversation.kind == "whisper" and ns.Players:ClassHex(conversation.class)
    local known = conversation.kind == "whisper" and ns.Players:Get(conversation.target)
    if known and known.l and opt("names.level") then
        title = title .. " " .. ns.Players:LevelMarkup(known.l)
    end
    row.title:SetText(
        color and ("|c%s%s|r"):format(color, conversation.title) .. title:sub(#conversation.title + 1) or title
    )
    local last = conversation.messages[#conversation.messages]
    row.time:SetText(last and shortTime(last.t) or "")
    row.time:ClearAllPoints()
    row.time:SetPoint("TOPRIGHT", -UI.space.sm, small and -6 or -9)
    row.title:ClearAllPoints()
    row.title:SetPoint("TOPLEFT", left, small and -5 or -8)
    row.title:SetPoint("RIGHT", row.time, "LEFT", -UI.space.xs, 0)
    local preview = ""
    if last then
        preview = last.m and (L.YOU .. ": " .. last.x) or last.x
        if last.f and not last.m and conversation.kind ~= "whisper" and conversation.kind ~= "bnet" then
            preview = ns.ShortName(last.f) .. ": " .. last.x
        end
    end
    row.preview:SetText(preview)
    row.preview:SetShown(not small)
    row.preview:ClearAllPoints()
    row.preview:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
    row.preview:SetPoint("RIGHT", -UI.space.sm - 26, 0)
    local unread = conversation.unread or 0
    row.badge:SetShown(unread > 0)
    if unread > 0 then
        row.badge.text:SetText(unread > 99 and "99+" or tostring(unread))
        row.badge:SetSize(math.max(18, row.badge.text:GetStringWidth() + 10), 18)
        row.badge:ClearAllPoints()
        row.badge:SetPoint("BOTTOMRIGHT", -UI.space.sm, small and 6 or 9)
        row.badge.shape:SetColors("accent")
    end
    self:PaintRow(row)
end

function Messenger:UpdateList()
    local frame = self.frame
    if not frame then
        return
    end
    local filter = strtrim(frame.search:GetText() or ""):lower()
    local y, index = 0, 0
    for _, conversation in ipairs(ns.History:List()) do
        if filter == "" or (conversation.title or ""):lower():find(filter, 1, true) then
            index = index + 1
            local row = self:Row(index)
            self:LayoutRow(row, conversation)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame.listContent, "TOPLEFT", 0, -y)
            row:SetPoint("RIGHT", frame.listContent, "RIGHT", 0, 0)
            row:Show()
            y = y + row:GetHeight() + 2
        end
    end
    for i = index + 1, #self.rows do
        self.rows[i]:Hide()
    end
    frame.listEmpty:SetShown(index == 0)
    frame.list:SetContentHeight(math.max(y, 1))
    self:UpdateLauncher()
end

-- Bubbles -----------------------------------------------------------------------------------

function Messenger:Bubble(index)
    local bubble = self.bubbles[index]
    if bubble then
        return bubble
    end
    local content = self.frame.messagesContent
    bubble = CreateFrame("Frame", nil, content)
    bubble.shape = UI.Shape(bubble, "card")
    bubble.name = UI.Text(bubble, "", "small")
    bubble.text = bubble:CreateFontString(nil, "OVERLAY")
    bubble.text:SetJustifyH("LEFT")
    bubble.time = UI.Text(bubble, "", "caption", "textMuted")
    bubble.avatar = createAvatar(content, 26)
    -- Item, spell and player links in the text can be clicked as in the chat.
    bubble:SetHyperlinksEnabled(true)
    bubble:SetScript("OnHyperlinkClick", function(_, link, text, button)
        SetItemRef(link, text, button)
    end)
    self.bubbles[index] = bubble
    return bubble
end

function Messenger:Separator(index)
    local separator = self.separators[index]
    if not separator then
        separator = CreateFrame("Frame", nil, self.frame.messagesContent)
        separator.shape = UI.Shape(separator, "pill")
        separator.text = UI.Text(separator, "", "caption", "textMuted")
        separator.text:SetPoint("CENTER")
        self.separators[index] = separator
    end
    return separator
end

local function bubbleColors(message)
    if message.m then
        if opt("bubbles.mine") == "custom" then
            local r, g, b = hexToRGB(opt("bubbles.mineColor"))
            return { r, g, b, 1 }, "onAccent"
        end
        return "accent", "onAccent"
    end
    local style = opt("bubbles.theirs")
    if style == "custom" then
        local r, g, b = hexToRGB(opt("bubbles.theirsColor"))
        return { r, g, b, 1 }, "text"
    elseif style == "class" and message.c and C_ClassColor then
        local color = C_ClassColor.GetClassColor(message.c)
        if color then
            return { color.r * 0.35, color.g * 0.35, color.b * 0.35, 1 }, "text"
        end
    end
    return "field", "text"
end

--- Lays the open conversation out as bubbles and scrolls to the last one.
function Messenger:UpdateMessages()
    local frame = self.frame
    if not frame then
        return
    end
    local conversation = self.selected and ns.History:Get(self.selected)
    frame.noSelection:SetShown(conversation == nil)
    frame.header:SetShown(conversation ~= nil)
    frame.input:SetShown(conversation ~= nil)
    frame.send:SetShown(conversation ~= nil)
    local messages = conversation and conversation.messages or {}
    local content = frame.messagesContent
    local width = content:GetWidth()
    if width <= 1 then
        width = frame.messages:GetWidth() - 10
    end
    local small = compact()
    local padX, padY = small and 8 or 10, small and 4 or 7
    local gap = small and 3 or 6
    local group = conversation and conversation.kind ~= "whisper" and conversation.kind ~= "bnet"
    local avatars = opt("bubbles.avatars") and group
    local avatarSpace = avatars and 34 or 0
    local maxWidth = math.floor((width - avatarSpace) * opt("bubbles.maxWidth"))
    local textSize = opt("bubbles.textSize")
    local path = fontPath()
    local y, index, separators, lastDay, lastFrom = UI.space.sm, 0, 0, nil, nil
    for _, message in ipairs(messages) do
        local day = date("%Y%m%d", message.t)
        if day ~= lastDay then
            separators = separators + 1
            local separator = self:Separator(separators)
            separator.text:SetText(dayLabel(message.t))
            separator:SetSize(separator.text:GetStringWidth() + 20, 18)
            separator.shape:SetColors("surface", "border")
            separator:ClearAllPoints()
            separator:SetPoint("TOP", content, "TOP", 0, -y)
            separator:Show()
            y = y + 18 + gap * 2
            lastDay, lastFrom = day, nil
        end
        index = index + 1
        local bubble = self:Bubble(index)
        local fill, textColor = bubbleColors(message)
        bubble.shape:SetColors(fill, message.m and nil or "border")
        bubble.text:SetFont(path, textSize, "")
        bubble.text:SetTextColor(Theme.Color(textColor))
        bubble.text:SetWidth(maxWidth - 2 * padX)
        bubble.text:SetText(message.x)
        local textWidth = math.min(bubble.text:GetStringWidth(), maxWidth - 2 * padX)
        bubble.text:SetWidth(math.max(textWidth, 1) + 1)
        local textHeight = bubble.text:GetStringHeight()
        -- The sender's name on the first message of a run in group conversations.
        local showName = group and not message.m and message.f and message.f ~= lastFrom
        bubble.name:SetShown(showName and true or false)
        local nameHeight = 0
        if showName then
            local color = ns.Players:ClassHex(message.c)
            local name = ns.ShortName(message.f)
            bubble.name:SetText(color and ("|c%s%s|r"):format(color, name) or name)
            nameHeight = bubble.name:GetStringHeight() + 2
            textWidth = math.max(textWidth, bubble.name:GetStringWidth())
        end
        local times = opt("bubbles.times")
        bubble.time:SetShown(times)
        local timeHeight = 0
        if times then
            bubble.time:SetText(date("%H:%M", message.t))
            bubble.time:SetTextColor(Theme.Color(message.m and "onAccent" or "textMuted"))
            bubble.time:SetAlpha(message.m and 0.75 or 1)
            timeHeight = bubble.time:GetStringHeight() + 2
            textWidth = math.max(textWidth, bubble.time:GetStringWidth())
        end
        local bubbleWidth = textWidth + 2 * padX
        local bubbleHeight = nameHeight + textHeight + timeHeight + 2 * padY
        bubble:SetSize(bubbleWidth, bubbleHeight)
        bubble.name:ClearAllPoints()
        bubble.name:SetPoint("TOPLEFT", padX, -padY)
        bubble.text:ClearAllPoints()
        bubble.text:SetPoint("TOPLEFT", padX, -padY - nameHeight)
        bubble.time:ClearAllPoints()
        bubble.time:SetPoint("BOTTOMRIGHT", -padX, padY - 1)
        bubble:ClearAllPoints()
        if message.m then
            bubble:SetPoint("TOPRIGHT", content, "TOPRIGHT", -UI.space.sm, -y)
        else
            bubble:SetPoint("TOPLEFT", content, "TOPLEFT", UI.space.sm + avatarSpace, -y)
        end
        bubble:Show()
        local showAvatar = avatars and not message.m and message.f ~= lastFrom
        bubble.avatar:SetShown(showAvatar and true or false)
        if showAvatar then
            bubble.avatar:Set(
                "whisper",
                message.c or ns.Players:KnownClass(message.f),
                message.f and ns.ShortName(message.f)
            )
            bubble.avatar:ClearAllPoints()
            bubble.avatar:SetPoint("TOPLEFT", content, "TOPLEFT", UI.space.sm, -y)
        end
        lastFrom = message.m and "@me" or message.f
        y = y + bubbleHeight + gap
    end
    for i = index + 1, #self.bubbles do
        self.bubbles[i]:Hide()
        self.bubbles[i].avatar:Hide()
    end
    for i = separators + 1, #self.separators do
        self.separators[i]:Hide()
    end
    frame.messages:SetContentHeight(math.max(y, 1))
    frame.messages:ScrollToEnd()
    self:UpdateHeader(conversation)
end

function Messenger:UpdateHeader(conversation)
    local frame = self.frame
    frame.locked:SetShown(locked() and true or false)
    if not conversation then
        return
    end
    frame.header.avatar:SetShown(opt("bubbles.avatars"))
    frame.header.avatar:Set(conversation.kind, conversationClass(conversation), conversation.title)
    local color = conversation.kind == "whisper" and ns.Players:ClassHex(conversation.class)
    frame.header.title:SetText(color and ("|c%s%s|r"):format(color, conversation.title) or conversation.title)
    local known = conversation.kind == "whisper" and ns.Players:Get(conversation.target)
    frame.header.subtitle:SetText(known and known.l and L.LEVEL:format(known.l) or "")
end

-- Selecting and sending ---------------------------------------------------------------------

function Messenger:Select(key)
    self.selected = key
    local conversation = key and ns.History:Get(key)
    if conversation then
        conversation.unread = 0
    end
    self:UpdateList()
    self:UpdateMessages()
    if conversation and self.frame then
        self.frame.input:SetFocus()
    end
end

--- Battle.net account ID of a BattleTag (IDs change every session; the tag doesn't).
local function bnetID(tag)
    if not C_BattleNet or not C_BattleNet.GetFriendAccountInfo or not BNGetNumFriends then
        return nil
    end
    for i = 1, BNGetNumFriends() do
        local info = C_BattleNet.GetFriendAccountInfo(i)
        if info and info.battleTag == tag then
            return info.bnetAccountID
        end
    end
end

local function sendChat(text, chatType, target)
    if C_ChatInfo and C_ChatInfo.SendChatMessage then
        C_ChatInfo.SendChatMessage(text, chatType, nil, target)
    else
        SendChatMessage(text, chatType, nil, target)
    end
end

--- Sends `text` to the open conversation. Restricted chat: it goes to Blizzard's chat box.
function Messenger:Send(text)
    text = strtrim(text or "")
    local conversation = self.selected and ns.History:Get(self.selected)
    if text == "" or not conversation then
        return
    end
    local kind = conversation.kind
    if locked() then
        local prefix = SEND[kind] and SEND[kind][2]
        if kind == "whisper" then
            prefix = "/w " .. ns.WhisperTarget(conversation) .. " "
        elseif kind == "channel" then
            prefix = "/" .. (GetChannelName(conversation.target) or 1) .. " "
        end
        local util = _G.ChatFrameUtil
        if util and util.OpenChat then
            util.OpenChat((prefix or "") .. text)
        end
        self.frame.notice:SetText(L.LOCKED_SEND)
        self.frame.notice:Show()
        return
    end
    if kind == "whisper" then
        sendChat(text, "WHISPER", ns.WhisperTarget(conversation))
    elseif kind == "bnet" then
        local id = bnetID(conversation.target)
        if id then
            if C_BattleNet.SendWhisper then
                C_BattleNet.SendWhisper(id, text)
            else
                BNSendWhisper(id, text)
            end
        end
    elseif kind == "channel" then
        local id = GetChannelName(conversation.target)
        if id and id > 0 then
            sendChat(text, "CHANNEL", id)
        end
    elseif SEND[kind] then
        sendChat(text, SEND[kind][1])
    end
end

--- A new message (from History): unread count, sound, auto-open and repaint.
function Messenger:OnMessage(conversation, message)
    if
        not self.running
        or opt("mode.style") ~= "messenger"
        or not opt("messenger." .. ns.History.OPTION[conversation.kind])
    then
        return
    end
    local open = self.frame and self.frame:IsShown() and self.selected == conversation.key
    if not message.m and not open then
        conversation.unread = (conversation.unread or 0) + 1
    end
    local whisper = conversation.kind == "whisper" or conversation.kind == "bnet"
    if whisper and not message.m then
        if opt("messenger.sound") and not open then
            PlaySound(NEW_WHISPER_SOUND)
        end
        if opt("messenger.autoOpen") and not (self.frame and self.frame:IsShown()) then
            self:Open(conversation.key)
            return
        end
    end
    if self.frame and self.frame:IsShown() then
        self:UpdateList()
        if self.selected == conversation.key then
            self:UpdateMessages()
        end
    else
        self:UpdateLauncher()
    end
end

-- Window ------------------------------------------------------------------------------------

Messenger.KEY = addonName .. ".messenger"

function Messenger:Create()
    local w = CreateFrame("Frame", "EternityUIChatMessenger", UIParent)
    self.frame = w
    w:Hide()
    w:SetFrameStrata("HIGH")
    w:SetToplevel(true)
    w:SetClampedToScreen(true)
    w:SetMovable(true)
    w:SetResizable(true)
    w:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
    w:EnableMouse(true)
    w:RegisterForDrag("LeftButton")
    w.shape = UI.Shape(w, "card")
    w:SetScript("OnDragStart", function(frame)
        if not E.Mover.Entry(Messenger.KEY).locked then
            frame:StartMoving()
        end
    end)
    w:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        frame:SetUserPlaced(false)
        E.Mover.SaveFromFrame(Messenger.KEY)
    end)
    w:SetScript("OnShow", function(frame)
        E.Combat.Run(frame, function()
            frame:SetPropagateKeyboardInput(true)
        end)
        self:UpdateList()
        self:UpdateMessages()
    end)
    w:HookScript("OnSizeChanged", function()
        if w:IsShown() then
            self:UpdateMessages()
        end
    end)
    -- Esc closes it, through keyboard input: UISpecialFrames taints. Other keys go on to the game.
    w:EnableKeyboard(true)
    w:SetScript("OnKeyDown", function(frame, key)
        if key == "ESCAPE" and not InCombatLockdown() then
            frame:SetPropagateKeyboardInput(false)
            frame:Hide()
        end
    end)
    function w.Paint(frame)
        if self.running then
            self:ApplyLook()
            if frame:IsShown() then
                self:UpdateList()
                self:UpdateMessages()
            end
        end
    end

    -- The bar: title, menu and close. Dragging the window moves it.
    w.bar = CreateFrame("Frame", nil, w)
    w.bar:SetPoint("TOPLEFT")
    w.bar:SetPoint("TOPRIGHT")
    w.bar:SetHeight(BAR_HEIGHT)
    w.title = UI.Text(w.bar, L.MESSENGER, "heading")
    w.title:SetPoint("LEFT", UI.space.md, 0)
    w.close = E.Widgets.Button(w.bar, "×", "ghost", function()
        w:Hide()
    end)
    w.close:SetSize(26, 26)
    w.close:SetPoint("RIGHT", -UI.space.sm, 0)
    w.menu = E.Widgets.Button(w.bar, "", "ghost", function()
        self:OpenMenu(w.menu)
    end)
    w.menu:SetSize(26, 26)
    w.menu:SetPoint("RIGHT", w.close, "LEFT", -UI.space.xs, 0)
    w.menu.dots = UI.Dots(w.menu)
    w.barLine = UI.Divider(w.bar)
    w.barLine:SetPoint("BOTTOMLEFT")
    w.barLine:SetPoint("BOTTOMRIGHT")

    w.body = CreateFrame("Frame", nil, w)
    w.body:SetPoint("TOPLEFT", 0, -BAR_HEIGHT)
    w.body:SetPoint("BOTTOMRIGHT")

    -- The corner that resizes it.
    w.grip = CreateFrame("Button", nil, w)
    w.grip:SetSize(16, 16)
    w.grip:SetPoint("BOTTOMRIGHT", -2, 2)
    w.grip:SetFrameLevel(w:GetFrameLevel() + 20)
    w.grip.mark = w.grip:CreateTexture(nil, "ARTWORK")
    w.grip.mark:SetAllPoints()
    w.grip.mark:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    -- The top left corner stays put while the corner is dragged (the Mover may anchor the window by
    -- its center); on release the size goes to the options' step before the spot is saved, so the
    -- options don't change the size, and move the window, afterwards.
    w.grip:SetScript("OnMouseDown", function()
        local left, top = w:GetLeft(), w:GetTop()
        if left and top then
            w:ClearAllPoints()
            w:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
        w:StartSizing("BOTTOMRIGHT")
    end)
    w.grip:SetScript("OnMouseUp", function()
        w:StopMovingOrSizing()
        w:SetUserPlaced(false)
        local function snap(value, low, high)
            value = math.floor(value / SIZE_STEP + 0.5) * SIZE_STEP
            return math.max(low, math.min(high, value))
        end
        local width = snap(w:GetWidth(), MIN_WIDTH, MAX_WIDTH)
        local height = snap(w:GetHeight(), MIN_HEIGHT, MAX_HEIGHT)
        w:SetSize(width, height)
        E.Mover.SaveFromFrame(Messenger.KEY)
        E.store:Set(addonName, "window.width", width)
        E.store:Set(addonName, "window.height", height)
    end)

    -- Left: search and conversations.
    w.side = CreateFrame("Frame", nil, w.body)
    w.side:SetPoint("TOPLEFT")
    w.side:SetPoint("BOTTOMLEFT")
    w.search = UI.Input(w.side, L.SEARCH, 40)
    w.search:SetPoint("TOPLEFT", UI.space.sm, -UI.space.sm)
    w.search:SetPoint("TOPRIGHT", -UI.space.sm, -UI.space.sm)
    w.search:HookScript("OnTextChanged", function()
        self:UpdateList()
    end)
    w.list = E.Widgets.Scroll(w.side)
    w.list:SetPoint("TOPLEFT", w.search, "BOTTOMLEFT", 0, -UI.space.sm)
    w.list:SetPoint("BOTTOMRIGHT", -UI.space.xs, UI.space.sm)
    w.listContent = w.list.child
    w.listEmpty = UI.Text(w.side, L.NO_CONVERSATIONS, "small", "textMuted")
    w.listEmpty:SetPoint("CENTER")
    w.divider = UI.Divider(w.body, true)
    w.divider:SetPoint("TOPLEFT", w.side, "TOPRIGHT")
    w.divider:SetPoint("BOTTOMLEFT", w.side, "BOTTOMRIGHT")

    -- Right: header, bubbles and the box to write.
    w.pane = CreateFrame("Frame", nil, w.body)
    w.pane:SetPoint("TOPLEFT", w.side, "TOPRIGHT", 1, 0)
    w.pane:SetPoint("BOTTOMRIGHT")
    w.header = CreateFrame("Frame", nil, w.pane)
    w.header:SetPoint("TOPLEFT")
    w.header:SetPoint("TOPRIGHT")
    w.header:SetHeight(48)
    w.header.avatar = createAvatar(w.header, 32)
    w.header.avatar:SetPoint("LEFT", UI.space.md, 0)
    w.header.title = UI.Text(w.header, "", "heading")
    w.header.title:SetPoint("TOPLEFT", w.header.avatar, "TOPRIGHT", UI.space.sm, -1)
    w.header.subtitle = UI.Text(w.header, "", "small", "textMuted")
    w.header.subtitle:SetPoint("TOPLEFT", w.header.title, "BOTTOMLEFT", 0, -2)
    w.headerLine = UI.Divider(w.pane)
    w.headerLine:SetPoint("TOPLEFT", w.header, "BOTTOMLEFT")
    w.headerLine:SetPoint("TOPRIGHT", w.header, "BOTTOMRIGHT")

    w.input = UI.Input(w.pane, L.WRITE, 255, function(text)
        self:Send(text)
        w.input:SetText("")
        w.input:SetFocus()
    end)
    w.input:SetPoint("BOTTOMLEFT", UI.space.md, UI.space.md)
    w.send = E.Widgets.Button(w.pane, L.SEND, "primary", function()
        self:Send(w.input:GetText())
        w.input:SetText("")
    end)
    w.send:SetPoint("BOTTOMRIGHT", -UI.space.md, UI.space.md)
    w.input:SetPoint("RIGHT", w.send, "LEFT", -UI.space.sm, 0)
    w.locked = UI.Text(w.pane, L.LOCKED, "small", "warning")
    w.locked:SetPoint("BOTTOMLEFT", w.input, "TOPLEFT", 2, UI.space.sm)
    w.locked:SetPoint("RIGHT", -UI.space.md, 0)
    w.notice = UI.Text(w.pane, "", "small", "textMuted")
    w.notice:SetPoint("BOTTOMLEFT", w.locked, "TOPLEFT", 0, UI.space.xs)
    w.notice:Hide()

    w.messages = E.Widgets.Scroll(w.pane)
    w.messages:SetPoint("TOPLEFT", w.header, "BOTTOMLEFT", 0, -1)
    w.messages:SetPoint("BOTTOMRIGHT", w.send, "TOPRIGHT", 0, UI.space.sm + 18)
    w.messagesContent = w.messages.child
    w.noSelection = UI.Text(w.pane, L.NO_SELECTION, "body", "textMuted")
    w.noSelection:SetPoint("CENTER")
    E.Widgets.Track(w)
    return w
end

function Messenger:OpenMenu(owner)
    local entries = {
        {
            text = L.OPTIONS,
            onClick = function()
                E:OpenOptions(addonName, "general")
            end,
        },
    }
    if self.selected then
        entries[#entries + 1] = {
            text = L.CLEAR,
            onClick = function()
                ns.History:Clear(self.selected)
                self.selected = nil
                self:UpdateList()
                self:UpdateMessages()
            end,
        }
    end
    entries[#entries + 1] = {
        text = L.CLEAR_ALL,
        onClick = function()
            ns.History:ClearAll()
            self.selected = nil
            self:UpdateList()
            self:UpdateMessages()
        end,
    }
    E.Widgets.Menu(owner, entries, 240)
end

--- Size, list width, scale and look from the options. The position belongs to the Mover (at the
--- center by default); dragging the window saves it there too.
function Messenger:ApplyLook()
    local w = self.frame
    if not w then
        return
    end
    w:SetSize(opt("window.width"), opt("window.height"))
    w.side:SetWidth(opt("window.listWidth"))
    w:SetScale(opt("window.scale"))
    Theme.PaintWindow(w.shape)
    w.shape.fill:SetAlpha(opt("window.opacity"))
    w:SetAlpha(opt("window.alpha"))
    w.menu.dots:SetColor("text")
end

function Messenger:Open(key)
    if not self.running or opt("mode.style") ~= "messenger" then
        return
    end
    if not self.frame then
        self:Create()
    end
    self.frame:Show()
    if key then
        self:Select(key)
    end
end

function Messenger:Toggle()
    if self.frame and self.frame:IsShown() then
        self.frame:Hide()
    else
        self:Open()
    end
end

-- Launcher ----------------------------------------------------------------------------------

function Messenger:CreateLauncher()
    local b = CreateFrame("Button", "EternityUIChatLauncher", UIParent)
    b:SetSize(24, 24)
    b:SetFrameStrata("MEDIUM")
    b.shape = UI.Shape(b, "pill")
    b.icon = UI.Dots(b)
    b.badge = CreateFrame("Frame", nil, b)
    b.badge:SetPoint("CENTER", b, "TOPRIGHT", -3, -3)
    b.badge.shape = UI.Shape(b.badge, "pill")
    b.badge.text = UI.Text(b.badge, "", "caption", "onAccent")
    b.badge.text:SetPoint("CENTER")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            E:OpenOptions(addonName, "general")
        else
            self:Toggle()
        end
    end)
    E.Widgets.AttachTooltip(b, function(tip)
        tip:SetTitle(L.MESSENGER)
        local unread = self:Unread()
        if unread > 0 then
            tip:AddLine(L.UNREAD:format(unread), "accentText")
        end
        tip:AddHint(L.LAUNCHER_HINT)
    end, "TOP")
    UI.TrackHover(b, function(button)
        button:Paint()
    end)
    function b.Paint(button)
        button.shape:SetColors(button.hovered and "accent" or "window", "borderStrong")
        button.icon:SetColor(button.hovered and "onAccent" or "text")
        button.badge.shape:SetColors("accent")
    end
    self.launcher = E.Widgets.Track(b)
end

function Messenger:Unread()
    local total = 0
    for _, conversation in ipairs(ns.History:List()) do
        total = total + (conversation.unread or 0)
    end
    return total
end

function Messenger:UpdateLauncher()
    local show = self.running and opt("mode.style") == "messenger" and opt("messenger.launcher")
    if show and not self.launcher then
        self:CreateLauncher()
    end
    local b = self.launcher
    if not b then
        return
    end
    b:SetShown(show and true or false)
    if not show then
        return
    end
    local anchor = _G.ChatFrame1
    b:ClearAllPoints()
    if anchor then
        local pad = opt("background.padding")
        b:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", pad, pad + 4)
    else
        b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 240)
    end
    local unread = self:Unread()
    b.badge:SetShown(unread > 0)
    if unread > 0 then
        b.badge.text:SetText(unread > 99 and "99+" or tostring(unread))
        b.badge:SetSize(math.max(14, b.badge.text:GetStringWidth() + 6), 14)
    end
end

-- Lifecycle ---------------------------------------------------------------------------------

function Messenger:Apply()
    local messenger = self.running and opt("mode.style") == "messenger"
    -- In messenger mode the window is a Mover element (created hidden, so it can be placed before
    -- it first opens).
    if messenger and not self.frame then
        self:Create()
    end
    if messenger and not E.Mover.elements[Messenger.KEY] then
        E.Mover.Register({
            key = Messenger.KEY,
            owner = addonName,
            label = L.MESSENGER,
            frame = self.frame,
            point = "CENTER",
            openOptions = function()
                E:OpenOptions(addonName)
            end,
        })
    elseif not messenger then
        E.Mover.Unregister(Messenger.KEY)
    end
    if self.frame then
        self:ApplyLook()
        if not messenger then
            self.frame:Hide()
        elseif self.frame:IsShown() then
            self:UpdateList()
            self:UpdateMessages()
        end
    end
    self:UpdateLauncher()
end

function Messenger:Start()
    self.running = true
    self:Apply()
end

function Messenger:Stop()
    self.running = false
    self:Apply()
end
