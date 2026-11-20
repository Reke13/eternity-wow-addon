-- The row of icons on screen. The row takes no mouse, so it can sit over the world; only icons
-- with something to cast get a button. The Mover
-- moves one frame sized for the most icons; the icons share it out by the growth option. Previews
-- (the Mover, the Test button) fill the row with samples.

---@type string, EternityUIAlertsNamespace
local addonName, ns = ...
local E = EternityUI
local Shape, Theme, Widgets = E.Shape, E.Theme, E.Widgets
local L = ns.L

local LABEL_GAP = 3 -- between an icon and its name
local LABEL_SIDE = 8 -- a name beside its icon gets this many times its font size
local INSIDE = 2 -- texts inside an icon, from its edge
local MIN_TEXT = 8
local SAMPLE_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local TEST_SECONDS = 8
local CLICK_LEVEL = 40
local COUNTDOWN_TICK = 0.2
local SAMPLE_SECONDS = 45
-- The countdown's color (the countdown.color option). Its text paints with this table, so the
-- values written here recolor it on the next paint.
local countdownColor = { 1, 0.27, 0.27, 1 }
-- The countdown's border (countdown.outline): copies of its text in this color, moved this way
-- and that around it, behind it. A font's own outline is always black and of one width. The
-- copies sit in a frame under the countdown's: the client doesn't keep font strings of one frame
-- in the order of their draw sublevels.
local outlineColor = { 0, 0, 0, 1 }
local OUTLINE_DIRECTIONS = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 }, { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } }

---@class EternityUIAlertsDisplay
---@field frame table? the row, once started
local Display = { icons = {}, clicks = {}, items = {}, previews = {} }
ns.Display = Display

local function opt(path)
    return E.store:Get(addonName, path)
end

local function newIcon(parent)
    local icon = CreateFrame("Frame", nil, parent)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.border = Shape.New(icon)

    icon.pulse = CreateFrame("Frame", nil, icon)
    icon.pulse:SetAllPoints()
    icon.pulse.shape = Shape.New(icon.pulse)
    icon.animation = icon.pulse:CreateAnimationGroup()
    icon.animation:SetLooping("BOUNCE")
    local fade = icon.animation:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.15)
    fade:SetToAlpha(1)
    fade:SetDuration(0.7)
    fade:SetSmoothing("IN_OUT")

    -- Over the pulse, which fades. The name too: it can go inside the icon.
    icon.top = CreateFrame("Frame", nil, icon)
    icon.top:SetAllPoints()
    icon.top:SetFrameLevel(icon.pulse:GetFrameLevel() + 1)
    icon.value = Widgets.Text(icon.top, 13, "text")
    icon.value:SetShadowOffset(1, -1)
    -- The countdown over its border's copies, which are in icon.top.
    icon.front = CreateFrame("Frame", nil, icon)
    icon.front:SetAllPoints()
    icon.front:SetFrameLevel(icon.top:GetFrameLevel() + 1)
    icon.countdown = Widgets.Text(icon.front, 18, countdownColor)
    icon.countdown:SetShadowOffset(1, -1)
    icon.countdown:SetShadowColor(0, 0, 0, 1)
    icon.outline = {}
    for i = 1, #OUTLINE_DIRECTIONS do
        local copy = Widgets.Text(icon.top, 18, outlineColor)
        copy:Hide()
        icon.outline[i] = copy
    end
    icon.label = Widgets.Text(icon.top, 12, "text")
    icon.label:SetWordWrap(false)
    icon.label:SetShadowOffset(1, -1)

    -- glowColor: a rule's own glow ("#RRGGBB"), or the theme's accent. bordered: display.border.
    function icon.Paint(self)
        local glow = self.glowColor and Theme.RGBA(self.glowColor) or Theme.accent
        Shape.Paint(self.border, 0, nil, self.bordered ~= false and Theme.colors.lineStrong or nil)
        Shape.Paint(self.pulse.shape, 0, { glow[1], glow[2], glow[3], 0.2 }, glow)
    end
    return Widgets.Track(icon)
end

-- The room a name takes next to its icon: extra width (beside it) and extra height (over or
-- under it). Inside the icon it takes none.
local function labelRoom(position, size)
    if position == "left" or position == "right" then
        return size * LABEL_SIDE, 0
    elseif position == "below" or position == "above" then
        return 0, size + LABEL_GAP * 2
    end
    return 0, 0
end

-- The frame the Mover moves: room for the most icons along the growth, at the row's size.
local function resize(self, growth, roomW, roomH)
    local size, gap, most = opt("display.iconSize"), opt("display.spacing"), opt("display.maxIcons")
    local width, height = size + roomW, size + roomH
    if growth == "down" or growth == "up" then
        self.frame:SetSize(width, height * most + gap * (most - 1))
    else
        self.frame:SetSize(width * most + gap * (most - 1), height)
    end
end

--- Where each icon's cell goes in the row's frame, by the growth option. Cells can differ in size
--- (each rule has its own); across the growth they're centered. Coordinates from the frame's top
--- left, y downwards.
---@param cells { w: number, h: number }[]
---@param growth string
---@param gap number
---@param frameW number
---@param frameH number
---@return { x: number, y: number }[]
function Display.Cells(cells, growth, gap, frameW, frameH)
    local vertical = growth == "down" or growth == "up"
    local total = 0
    for i, cell in ipairs(cells) do
        total = total + (vertical and cell.h or cell.w) + (i > 1 and gap or 0)
    end
    local spots, at = {}, 0
    for i, cell in ipairs(cells) do
        local x, y
        if vertical then
            x = (frameW - cell.w) / 2
            y = growth == "down" and at or (frameH - at - cell.h)
            at = at + cell.h + gap
        else
            y = (frameH - cell.h) / 2
            if growth == "right" then
                x = at
            elseif growth == "left" then
                x = frameW - at - cell.w
            else
                x = (frameW - total) / 2 + at
            end
            at = at + cell.w + gap
        end
        spots[i] = { x = x, y = y }
    end
    return spots
end

-- A name by its icon, by display.labelPosition, as wide as the room it has.
-- shift: room left between the icon and a name over or under it (a countdown on that side).
local function placeLabel(icon, position, size, roomW, gap, shift)
    local label = icon.label
    label:ClearAllPoints()
    label:SetJustifyH("CENTER")
    if position == "above" then
        label:SetPoint("BOTTOM", icon, "TOP", 0, LABEL_GAP + shift)
        label:SetWidth(size + gap)
    elseif position == "left" then
        label:SetPoint("RIGHT", icon, "LEFT", -LABEL_GAP * 2, 0)
        label:SetJustifyH("RIGHT")
        label:SetWidth(roomW - LABEL_GAP * 2)
    elseif position == "right" then
        label:SetPoint("LEFT", icon, "RIGHT", LABEL_GAP * 2, 0)
        label:SetJustifyH("LEFT")
        label:SetWidth(roomW - LABEL_GAP * 2)
    elseif position == "inside" then
        label:SetPoint("TOP", icon, "TOP", 0, -INSIDE)
        label:SetWidth(size - INSIDE * 2)
    else
        label:SetPoint("TOP", icon, "BOTTOM", 0, -(LABEL_GAP + shift))
        label:SetWidth(size + gap)
    end
end

-- A text inside the icon at "top", "bottom" or "center".
local function placeInside(text, icon, where)
    text:ClearAllPoints()
    if where == "top" then
        text:SetPoint("TOP", icon, "TOP", 0, -INSIDE)
    elseif where == "bottom" then
        text:SetPoint("BOTTOM", icon, "BOTTOM", 0, INSIDE)
    else
        text:SetPoint("CENTER", icon, "CENTER", 0, 0)
    end
end

-- The countdown: inside the icon ("center", "top", "bottom") or just outside it ("above",
-- "below"), nearer the icon than a name on that side.
local function placeCountdown(text, icon, where)
    if where == "above" then
        text:ClearAllPoints()
        text:SetPoint("BOTTOM", icon, "TOP", 0, LABEL_GAP)
    elseif where == "below" then
        text:ClearAllPoints()
        text:SetPoint("TOP", icon, "BOTTOM", 0, -LABEL_GAP)
    else
        placeInside(text, icon, where)
    end
end

-- Countdown --------------------------------------------------------------------------------------

--- The text of a countdown: seconds under a minute, minutes and seconds over it ("" once over).
---@param left number seconds
---@return string
function Display.FormatLeft(left)
    if left <= 0 then
        return ""
    end
    local seconds = math.ceil(left)
    if seconds >= 60 then
        return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
    end
    return tostring(seconds)
end

local function setCountdown(icon, text)
    icon.countdown:SetText(text)
    for _, copy in ipairs(icon.outline) do
        copy:SetText(text)
    end
end

-- The border copies: shown and set around the countdown at width pixels, or hidden (0). The text
-- keeps its shadow only without a border.
local function outline(icon, size, width)
    for i, copy in ipairs(icon.outline) do
        if width > 0 then
            local direction = OUTLINE_DIRECTIONS[i]
            Widgets.SetTextSize(copy, size)
            copy:ClearAllPoints()
            copy:SetPoint("CENTER", icon.countdown, "CENTER", direction[1] * width, direction[2] * width)
            copy:Show()
        else
            copy:Hide()
        end
    end
    icon.countdown:SetShadowOffset(width > 0 and 0 or 1, width > 0 and 0 or -1)
end

local function updateCountdowns()
    local now = GetTime()
    local running = false
    for _, icon in ipairs(Display.icons) do
        if icon:IsShown() and icon.ends then
            local text = Display.FormatLeft(icon.ends - now)
            setCountdown(icon, text)
            running = running or text ~= ""
        else
            setCountdown(icon, "")
        end
    end
    return running
end

-- One ticker while some icon counts down; it stops by itself when none does.
local function countdowns()
    if not updateCountdowns() then
        if Display.ticker then
            Display.ticker:Cancel()
            Display.ticker = nil
        end
        return
    end
    Display.ticker = Display.ticker or C_Timer.NewTicker(COUNTDOWN_TICK, countdowns)
end

-- Clicks ---------------------------------------------------------------------------------------------

-- Secure buttons over the icons that cast something. They hang from UIParent at a measured spot,
-- not from the icons: an anchor to a protected frame would block moving the icons in combat. They
-- can't be changed in combat, so they hide as it starts and come back with the next draw.

local function clickTooltip(tip, button)
    tip:SetTitle(button.title)
    tip:AddHint(L.CLICK_HINT:format(button.use))
end

local function clickButton(index)
    local button = Display.clicks[index]
    if not button then
        button = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
        button:SetFrameStrata("MEDIUM")
        button:SetFrameLevel(CLICK_LEVEL)
        -- Both: the template acts on one or the other by the ActionButtonUseKeyDown CVar.
        button:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
        -- On yourself, even with a friend targeted.
        button:SetAttribute("unit", "player")
        Widgets.AttachTooltip(button, clickTooltip, "BOTTOM")
        Display.clicks[index] = button
    end
    return button
end

local function placeClick(button, icon, item)
    local x, y = icon:GetCenter()
    local width = icon:GetWidth()
    if not x then
        button:Hide()
        return
    end
    local scale = icon:GetEffectiveScale() / UIParent:GetEffectiveScale()
    button:ClearAllPoints()
    button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * scale, y * scale)
    button:SetSize(width * scale, width * scale)
    button.title, button.use = item.name, item.use
    button:SetAttribute("type", item.action)
    button:SetAttribute(item.action, item.use)
    button:Show()
end

--- Hides the click buttons. Called as combat starts, while they can still be changed.
function Display.ClearClicks()
    if InCombatLockdown() then
        return
    end
    for _, button in ipairs(Display.clicks) do
        button:Hide()
    end
end

local function refreshClicks(items, count)
    if InCombatLockdown() then
        return
    end
    Display.ClearClicks()
    if next(Display.previews) then
        return
    end
    local used = 0
    for i = 1, count do
        if items[i].action then
            used = used + 1
            placeClick(clickButton(used), Display.icons[i], items[i])
        end
    end
end

--- Redraws the row from the items it holds, or from samples during a preview.
function Display.Draw()
    local self = Display
    if not self.frame then
        return
    end
    self.frame:SetAlpha(opt("display.opacity"))
    local base, gap, most = opt("display.iconSize"), opt("display.spacing"), opt("display.maxIcons")
    local growth = opt("display.growth")
    local items = self.items
    if next(self.previews) then
        items = {}
        for i = 1, most do
            items[i] = { name = L.ROW, icon = SAMPLE_ICON, value = tostring(i), glow = i == 1 }
        end
        -- One sample with the countdown, to see how it looks.
        if items[2] then
            items[2].ends = GetTime() + SAMPLE_SECONDS
        end
    end
    local count = math.min(#items, most)

    -- Names: shown by display.labels, unless a rule says otherwise. Room is kept for them when
    -- any shows.
    local labels, position = opt("display.labels"), opt("display.labelPosition") or "below"
    local labelSize = opt("display.labelSize") or 12
    local named = labels
    for i = 1, count do
        if items[i].showName then
            named = true
        end
    end
    local roomW, roomH = 0, 0
    if named then
        roomW, roomH = labelRoom(position, labelSize)
    end
    local outlineWidth = opt("countdown.outline") and (opt("countdown.outlineSize") or 1) or 0
    -- A countdown outside the icon takes a line over or under it, while some icon counts down.
    local countdownShare = (opt("countdown.size") or 42) / 100
    local countdownAt = opt("countdown.position") or "center"
    local countdownRoom = 0
    if countdownAt == "above" or countdownAt == "below" then
        for i = 1, count do
            if items[i].ends then
                local text = math.max(MIN_TEXT, math.floor(base * (items[i].scale or 1) * countdownShare))
                countdownRoom = math.max(countdownRoom, text + LABEL_GAP * 2 + outlineWidth * 2)
            end
        end
    end
    resize(self, growth, roomW, roomH + countdownRoom)
    local frameW, frameH = self.frame:GetSize()

    local color = opt("countdown.color")
    if color then
        local rgba = Theme.RGBA(color)
        countdownColor[1], countdownColor[2], countdownColor[3] = rgba[1], rgba[2], rgba[3]
    end
    local border = opt("countdown.outlineColor")
    if border then
        local rgba = Theme.RGBA(border)
        outlineColor[1], outlineColor[2], outlineColor[3] = rgba[1], rgba[2], rgba[3]
    end
    -- The value goes to the top when the countdown takes the bottom.
    local valueAt = countdownAt == "bottom" and "top" or "bottom"
    local valueSize = opt("display.valueSize") or 13
    local bordered = opt("display.border") ~= false

    local cells = {}
    for i = 1, count do
        local size = math.floor(base * (items[i].scale or 1) + 0.5)
        cells[i] = { w = size + roomW, h = size + roomH + countdownRoom, size = size }
    end
    local spots = Display.Cells(cells, growth, gap, frameW, frameH)
    for i = 1, count do
        local item, size = items[i], cells[i].size
        local icon = self.icons[i] or newIcon(self.frame)
        self.icons[i] = icon
        icon:SetSize(size, size)
        icon.texture:SetTexture(item.icon)
        icon.glowColor, icon.bordered = item.glowColor, bordered
        icon:Paint()
        Widgets.SetTextSize(icon.value, valueSize)
        icon.value:SetText(item.value or "")
        placeInside(icon.value, icon, valueAt)
        icon.ends = item.ends
        local countdownSize = math.max(MIN_TEXT, math.floor(size * countdownShare))
        Widgets.SetTextSize(icon.countdown, countdownSize)
        placeCountdown(icon.countdown, icon, countdownAt)
        outline(icon, countdownSize, outlineWidth)
        local showName = item.showName
        if showName == nil then
            showName = labels
        end
        Widgets.SetTextSize(icon.label, labelSize)
        icon.label:SetText(item.name)
        placeLabel(icon, position, size, roomW, gap, position == countdownAt and countdownRoom or 0)
        icon.label:SetShown(showName and true or false)
        -- In its cell: after the room of a name on its left, or of a name or countdown above it.
        local x = spots[i].x + (position == "left" and roomW or 0)
        local y = spots[i].y + (position == "above" and roomH or 0) + (countdownAt == "above" and countdownRoom or 0)
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -y)
        icon.pulse:SetAlpha(item.glow and 1 or 0)
        if item.glow then
            icon.animation:Play()
        else
            icon.animation:Stop()
        end
        icon:Show()
    end
    for i = count + 1, #self.icons do
        self.icons[i].animation:Stop()
        self.icons[i].ends = nil
        self.icons[i]:Hide()
    end
    countdowns()
    refreshClicks(items, count)
end

--- Shows these items: { name, icon, value, glow, ends, glowColor, scale, showName }; ends counts
--- down inside the icon, scale sizes it against display.iconSize, showName overrides display.labels.
---@param items table[]
function Display.Set(items)
    Display.items = items
    Display.Draw()
end

--- Turns a preview on or off. Each reason counts apart.
---@param reason string
---@param on boolean
function Display.SetPreview(reason, on)
    Display.previews[reason] = on or nil
    Display.Draw()
end

--- Shows the samples for a few seconds.
function Display.Test()
    Display.testRun = (Display.testRun or 0) + 1
    local run = Display.testRun
    Display.SetPreview("test", true)
    C_Timer.After(TEST_SECONDS, function()
        if run == Display.testRun then
            Display.SetPreview("test", false)
        end
    end)
end

function Display.Start()
    local self = Display
    if not self.frame then
        self.frame = CreateFrame("Frame", "EternityUIAlertsRow", UIParent)
        self.frame:SetFrameStrata("MEDIUM")
    end
    self.frame:Show()
    self:Draw()
    E.Mover.Register({
        key = addonName,
        owner = addonName,
        label = L.ROW,
        frame = self.frame,
        point = "TOP",
        x = 0,
        y = -160,
        openOptions = function()
            E:OpenOptions(addonName)
        end,
    })
end

function Display.Stop()
    local self = Display
    self.previews = {}
    self.items = {}
    self.ClearClicks()
    if self.frame then
        self:Draw()
        self.frame:Hide()
    end
    E.Mover.Unregister(addonName)
end
