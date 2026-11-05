-- The row of icons on screen. The row takes no mouse, so it can sit over the world; only icons
-- with something to cast get a button. The Mover
-- moves one frame sized for the most icons; the icons share it out by the growth option. Previews
-- (the Mover, the Test button) fill the row with samples.

---@type string, EternityUIAlertsNamespace
local addonName, ns = ...
local E = EternityUI
local Shape, Theme, Widgets = E.Shape, E.Theme, E.Widgets
local L = ns.L

local LABEL_HEIGHT = 18
local SAMPLE_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local TEST_SECONDS = 8
local CLICK_LEVEL = 40

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

    -- Over the pulse, which fades.
    icon.top = CreateFrame("Frame", nil, icon)
    icon.top:SetAllPoints()
    icon.top:SetFrameLevel(icon.pulse:GetFrameLevel() + 1)
    icon.value = Widgets.Text(icon.top, 13, "text")
    icon.value:SetPoint("BOTTOM", 0, 2)
    icon.value:SetShadowOffset(1, -1)
    icon.label = Widgets.Text(icon, 12, "text")
    icon.label:SetPoint("TOP", icon, "BOTTOM", 0, -3)
    icon.label:SetWordWrap(false)
    icon.label:SetShadowOffset(1, -1)

    function icon.Paint(self)
        local accent = Theme.accent
        Shape.Paint(self.border, 0, nil, Theme.colors.lineStrong)
        Shape.Paint(self.pulse.shape, 0, { accent[1], accent[2], accent[3], 0.2 }, accent)
    end
    return Widgets.Track(icon)
end

local function place(icon, index, count, step)
    local growth = opt("display.growth")
    icon:ClearAllPoints()
    if growth == "right" then
        icon:SetPoint("TOPLEFT", (index - 1) * step, 0)
    elseif growth == "left" then
        icon:SetPoint("TOPRIGHT", -(index - 1) * step, 0)
    elseif growth == "down" then
        icon:SetPoint("TOP", 0, -(index - 1) * step)
    elseif growth == "up" then
        icon:SetPoint("BOTTOM", 0, (index - 1) * step)
    else
        icon:SetPoint("TOP", (index - (count + 1) / 2) * step, 0)
    end
end

-- The frame the Mover moves: room for the most icons along the growth.
local function resize(self)
    local size, gap, most = opt("display.iconSize"), opt("display.spacing"), opt("display.maxIcons")
    local labels = opt("display.labels")
    local tall = size + (labels and LABEL_HEIGHT or 0)
    local growth = opt("display.growth")
    if growth == "down" or growth == "up" then
        self.frame:SetSize(size, tall * most + gap * (most - 1))
        return tall + gap, labels
    end
    self.frame:SetSize(size * most + gap * (most - 1), tall)
    return size + gap, labels
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
    local step, labels = resize(self)
    self.frame:SetAlpha(opt("display.opacity"))
    local size, most = opt("display.iconSize"), opt("display.maxIcons")
    local items = self.items
    if next(self.previews) then
        items = {}
        for i = 1, most do
            items[i] = { name = L.ROW, icon = SAMPLE_ICON, value = tostring(i), glow = i == 1 }
        end
    end
    local count = math.min(#items, most)
    for i = 1, count do
        local item = items[i]
        local icon = self.icons[i] or newIcon(self.frame)
        self.icons[i] = icon
        icon:SetSize(size, size)
        icon.texture:SetTexture(item.icon)
        icon.value:SetText(item.value or "")
        icon.label:SetText(item.name)
        icon.label:SetWidth(step)
        icon.label:SetShown(labels)
        place(icon, i, count, step)
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
        self.icons[i]:Hide()
    end
    refreshClicks(items, count)
end

--- Shows these items: { name, icon, value, glow }.
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
