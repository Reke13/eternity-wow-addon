-- One of the module's frames (the target's debuffs, the player's buffs), placed with the Mover.
-- The icons live in Blizzard's custom aura container (CreateFrame("AuraContainer", ...,
-- "CustomAuraContainerTemplate")): it reads, filters, sorts and draws the auras itself, so it
-- keeps working in combat, when aura data is secret to addons. This file only configures it:
--   * Three aura groups (Filters.lua): the frame's list of spells (Spells.lua, edited in the
--     "Spells" tab) first, whoever cast them or only when mine, then the rest.
--   * The buttons get our regions (icon, time shadow and text, stacks, dispel border) through
--     the container's initializer and setters; the container fills them.
-- Blizzard's own frames are never touched: the target frame's auras and the buff frame keep
-- showing.
-- The container can't be anchored to (it resizes itself), so the Mover moves a holder of our own
-- and the container hangs from one of its corners.
-- A frame's options are the groups "<key>" (what to show), "<key>Frame" and "<key>Look".

---@type string, EternityUIAurasNamespace
local addonName, ns = ...
local E = EternityUI
local Shape, Theme = E.Shape, E.Theme
local L, Filters, Spells, opt = ns.L, ns.Filters, ns.Spells, ns.opt

local SAMPLE_ICONS = { target = 136118, player = 136051 } -- generic icons for the Mover's samples
local SAMPLE_ROWS = 2
-- The container's aura groups, in the order they're laid out.
local GROUPS = { "tracked", "mine", "main" }

---@class EternityUIAurasFrame
---@field kind EternityUIAurasKind
---@field list EternityUIAurasSpellList
---@field holder table? our frame, moved by the Mover
---@field container table? Blizzard's aura container, once created
---@field buttons table[] aura buttons the container created
---@field samples table[]
---@field running boolean? the module runs and this frame is switched on
---@field moverOpen boolean?
local Frame = {}
Frame.__index = Frame
ns.Frame = Frame

---@param kind EternityUIAurasKind
---@return EternityUIAurasFrame
function Frame.New(kind)
    local self = setmetatable({ kind = kind, list = Spells.New(kind), buttons = {}, samples = {} }, Frame)
    return self
end

function Frame:Opt(group, option)
    return opt(self.kind.key .. group .. "." .. option)
end

function Frame:Show(option)
    return self:Opt("", option)
end

function Frame:Look(option)
    return self:Opt("Look", option)
end

function Frame:FrameOpt(option)
    return self:Opt("Frame", option)
end

--- The Mover's key of this frame.
function Frame:MoverKey()
    return addonName .. "_" .. self.kind.key
end

local function sortMethod(key)
    local methods = AuraContainerSortMethod or {}
    if key == "name" then
        return methods.Name or 6
    elseif key == "default" then
        return methods.Default or 0
    end
    return methods.Expiration or 4
end

local function sortDirection()
    local directions = AuraContainerSortDirection or {}
    return directions.Normal or 0
end

--- What Filters.Groups needs, from this frame's options and list.
function Frame:FilterOptions()
    local always, mine = self.list:Sets()
    local helpful = self.kind.filter == "HELPFUL"
    return {
        filter = self.kind.filter,
        onlyList = self:Show("onlyList"),
        origin = self:Show("origin"),
        crowdControl = not helpful and self:Show("crowdControl") or nil,
        dispellable = not helpful and self:Show("dispellable") or nil,
        duration = helpful and self:Show("duration") or nil,
        maxMinutes = helpful and self:Show("maxMinutes") or nil,
        max = self:Show("max"),
        always = always,
        mine = mine,
    }
end

function Frame:RowWidth()
    local size, spacing, perRow = self:Look("size"), self:Look("spacing"), self:Look("perRow")
    return perRow * size + (perRow - 1) * spacing
end

-- The corner the icons start from, from where they grow.
function Frame:Corner()
    local vertical = self:Look("wrap") == "up" and "BOTTOM" or "TOP"
    local horizontal = self:Look("growth") == "left" and "RIGHT" or "LEFT"
    return vertical .. horizontal
end

function Frame:GroupLayout()
    local size, spacing = self:Look("size"), self:Look("spacing")
    return { elementWidth = size, elementHeight = size, elementSpacing = spacing, lineSpacing = spacing }
end

-- Buttons ---------------------------------------------------------------------------------------

local function paintBack(button)
    local field, line = Theme.colors.field or { 0, 0, 0, 0.5 }, Theme.colors.lineStrong or { 0, 0, 0, 1 }
    Shape.Paint(button.etBack, math.min(Theme.radius or 0, 4), field, line)
end

--- Our look on one of the container's buttons: size, fonts and which parts show.
function Frame:StyleButton(button)
    local size = self:Look("size")
    button:SetSize(size, size)
    button.etIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.etCount:SetFont(Theme.font, self:Look("countSize"), "OUTLINE")
    button.etTime:SetFont(Theme.font, self:Look("textSize"), "OUTLINE")
    button.etCooldown:SetDrawSwipe(self:FrameOpt("swipe"))
    paintBack(button)
    -- Parts the container fills are attached or detached: it owns what they show.
    pcall(function()
        if self:FrameOpt("durationText") then
            button:SetDurationText(button.etTime, {})
        else
            button:ClearDurationText()
            button.etTime:Hide()
        end
    end)
    pcall(function()
        local wanted = self:FrameOpt("dispelBorder")
        if wanted and not button.etDispelOn then
            button:AddDispelTypeTexture(button.etDispel, {
                style = Enum.CustomAuraButtonDispelTypeTextureStyle and Enum.CustomAuraButtonDispelTypeTextureStyle.Border,
            })
            button.etDispelOn = true
        elseif not wanted and button.etDispelOn then
            button:RemoveDispelTypeTexture(button.etDispel)
            button.etDispel:Hide()
            button.etDispelOn = false
        end
    end)
end

--- Called by the container for every button it creates.
function Frame:InitializeButton(button)
    button.etBack = Shape.New(button, "BACKGROUND", -8)
    button.etIcon = button:CreateTexture(nil, "ARTWORK")
    button.etIcon:SetPoint("TOPLEFT", 1, -1)
    button.etIcon:SetPoint("BOTTOMRIGHT", -1, 1)
    button.etCooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.etCooldown:SetAllPoints(button.etIcon)
    button.etCooldown:SetReverse(true)
    button.etCooldown:SetDrawEdge(false)
    button.etCooldown:SetHideCountdownNumbers(true)
    -- Texts over the shadow.
    local texts = CreateFrame("Frame", nil, button)
    texts:SetAllPoints()
    texts:SetFrameLevel(button.etCooldown:GetFrameLevel() + 2)
    button.etCount = texts:CreateFontString(nil, "OVERLAY")
    button.etCount:SetPoint("BOTTOMRIGHT", -1, 2)
    button.etTime = texts:CreateFontString(nil, "OVERLAY")
    button.etTime:SetPoint("TOP", button, "BOTTOM", 0, -1)
    button.etDispel = button:CreateTexture(nil, "OVERLAY")
    button.etDispel:SetAllPoints()
    button.etCount:SetFont(Theme.font, 12, "OUTLINE")
    button.etTime:SetFont(Theme.font, 11, "OUTLINE")

    button:SetIcon(button.etIcon)
    button:SetDurationCooldown(button.etCooldown)
    button:SetApplicationCount(button.etCount)
    self.buttons[#self.buttons + 1] = button
    self:StyleButton(button)
end

-- Container ---------------------------------------------------------------------------------------

function Frame:GroupOptions(group, layoutIndex)
    local layout = self:GroupLayout()
    layout.layoutIndex = layoutIndex
    return {
        maxFrameCount = group.max,
        candidateFilters = group.candidate,
        sortMethod = sortMethod(self:Show("sort")),
        sortDirection = sortDirection(),
        initializeFrame = function(button)
            self:InitializeButton(button)
        end,
        layout = layout,
    }
end

--- Creates the holder (once).
function Frame:CreateHolder()
    if self.holder then
        return
    end
    self.holder = CreateFrame("Frame", self.kind.frameName, UIParent)
    self.holder:SetFrameStrata("MEDIUM")
    self.holder:SetClampedToScreen(true)
    self.holder:Hide()
end

--- Creates the container with its groups (once). False when the client has none.
---@return boolean
function Frame:CreateContainer()
    if self.container then
        return true
    end
    if self.noContainer then
        return false
    end
    if C_AddOns and C_AddOns.LoadAddOn and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, self.holder, "CustomAuraContainerTemplate")
    if not ok or not container or not container.AddAuraGroup then
        self.noContainer = true
        return false
    end
    self.container = container
    container:SetUnit(self.kind.unit)
    local groups = Filters.Groups(self:FilterOptions())
    for index, key in ipairs(GROUPS) do
        container:AddAuraGroup(key, groups[key].filter, self:GroupOptions(groups[key], index))
        container:SetAuraGroupEnabled(key, groups[key].enabled)
    end
    return true
end

--- Filters, order and counts of the groups from the options.
function Frame:ApplyFilters()
    local container = self.container
    if not container then
        return
    end
    local groups = Filters.Groups(self:FilterOptions())
    local method, direction = sortMethod(self:Show("sort")), sortDirection()
    for _, key in ipairs(GROUPS) do
        local group = groups[key]
        container:SetAuraGroupFilterString(key, group.filter)
        container:SetAuraGroupCandidateFilters(key, group.candidate)
        container:SetAuraGroupMaxFrameCount(key, group.max)
        container:SetAuraGroupSortMethod(key, method, direction)
        container:SetAuraGroupEnabled(key, group.enabled)
    end
end

--- Sizes, growth and the holder the Mover moves.
function Frame:ApplyLayout()
    local holder = self.holder
    if not holder then
        return
    end
    -- Zoom on top of the Mover's own scale (the Mover multiplies the frame's scale).
    holder:SetScale(self:FrameOpt("scale"))
    local size, spacing = self:Look("size"), self:Look("spacing")
    local width = self:RowWidth()
    holder:SetSize(width, SAMPLE_ROWS * size + (SAMPLE_ROWS - 1) * spacing)
    local container = self.container
    if container then
        local point = self:Corner()
        container:ClearAllPoints()
        container:SetPoint(point, holder, point)
        local flow = AnchorUtil and AnchorUtil.FlowDirection
        if container.SetFlowLayoutAnchorPoint then
            container:SetFlowLayoutAnchorPoint(point)
        end
        if flow and container.SetFlowLayoutGrowthDirection then
            container:SetFlowLayoutGrowthDirection(
                self:Look("growth") == "left" and flow.Left or flow.Right,
                self:Look("wrap") == "up" and flow.Up or flow.Down
            )
        end
        if container.SetFlowLayoutMaximumLineSize then
            container:SetFlowLayoutMaximumLineSize(width)
        end
        for index, key in ipairs(GROUPS) do
            local layout = self:GroupLayout()
            layout.layoutIndex = index
            container:SetAuraGroupLayout(key, layout)
        end
    end
    for _, button in ipairs(self.buttons) do
        self:StyleButton(button)
    end
    self:ShowSamples()
end

--- Shown while it runs, in combat only if the option says so; always while moving.
function Frame:UpdateVisibility()
    if not self.holder then
        return
    end
    local show = self.running and (self.moverOpen or not self:Show("inCombatOnly") or InCombatLockdown())
    self.holder:SetShown(show and true or false)
end

-- Samples: fake icons over the holder while the Mover is open, to see the size and the rows.
function Frame:ShowSamples()
    local holder = self.holder
    if not holder then
        return
    end
    local size, spacing, perRow = self:Look("size"), self:Look("spacing"), self:Look("perRow")
    local count = (self.running and self.moverOpen) and perRow * SAMPLE_ROWS or 0
    local point = self:Corner()
    local dx = self:Look("growth") == "left" and -1 or 1
    local dy = self:Look("wrap") == "up" and 1 or -1
    for i = 1, math.max(count, #self.samples) do
        local sample = self.samples[i]
        if i <= count then
            if not sample then
                sample = CreateFrame("Frame", nil, holder)
                sample.etBack = Shape.New(sample, "BACKGROUND", -8)
                sample.icon = sample:CreateTexture(nil, "ARTWORK")
                sample.icon:SetPoint("TOPLEFT", 1, -1)
                sample.icon:SetPoint("BOTTOMRIGHT", -1, 1)
                sample.icon:SetTexture(SAMPLE_ICONS[self.kind.key])
                sample.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                self.samples[i] = sample
            end
            local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
            sample:SetSize(size, size)
            sample:ClearAllPoints()
            sample:SetPoint(point, holder, point, dx * col * (size + spacing), dy * row * (size + spacing))
            sample:SetAlpha(0.6)
            paintBack(sample)
            sample:Show()
        elseif sample then
            sample:Hide()
        end
    end
end

-- Running ------------------------------------------------------------------------------------------

--- Starts the frame: Mover, container, filters and layout. False when the client has no
--- container.
---@return boolean
function Frame:Start()
    self:CreateHolder()
    self.running = true
    E.Mover.Register({
        key = self:MoverKey(),
        owner = addonName,
        label = self.kind.frameLabel,
        frame = self.holder,
        point = "CENTER",
        x = 0,
        y = self.kind.y,
        openOptions = function()
            E:OpenOptions(addonName)
        end,
    })
    self.list:ResumeSearches()
    local ok = self:CreateContainer()
    if ok then
        self.container:SetEnabled(true)
        self:ApplyFilters()
        self.container:UpdateAllAuras()
    end
    self:ApplyLayout()
    self:UpdateVisibility()
    return ok
end

--- Stops the frame: out of the Mover, the container off, hidden.
function Frame:Stop()
    if not self.running then
        return
    end
    self.running = false
    E.Mover.Unregister(self:MoverKey())
    if self.container then
        self.container:SetEnabled(false)
    end
    self:ShowSamples()
    self:UpdateVisibility()
end

--- The unit changed (a new target): the container follows the token, not the unit.
function Frame:Refresh()
    if self.running and self.container then
        self.container:UpdateAllAuras()
    end
end
