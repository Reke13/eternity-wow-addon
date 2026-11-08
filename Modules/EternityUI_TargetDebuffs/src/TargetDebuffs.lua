-- EternityUI_TargetDebuffs: the target's debuffs in a frame of their own, placed with the Mover.
-- The icons live in Blizzard's custom aura container (CreateFrame("AuraContainer", ...,
-- "CustomAuraContainerTemplate")): it reads, filters, sorts and draws the auras itself, so it
-- keeps working in combat, when aura data is secret to addons. This file only configures it:
--   * Three aura groups (Filters.lua): the player's list of spells (Spells.lua, edited in the
--     "Spells" tab) first, whoever cast them or only when mine, then the rest.
--   * The buttons get our regions (icon, time shadow and text, stacks, dispel border) through
--     the container's initializer and setters; the container fills them.
-- Blizzard's target frame is never touched. Its own auras keep showing.
-- The container can't be anchored to (it resizes itself), so the Mover moves a holder of our own
-- and the container hangs from one of its corners.

---@type string, EternityUITargetDebuffsNamespace
local addonName, ns = ...
local E = EternityUI
local Shape, Theme = E.Shape, E.Theme
local L, Filters, Spells, SpellsTab, opt = ns.L, ns.Filters, ns.Spells, ns.SpellsTab, ns.opt

local SAMPLE_ICON = 136118 -- a generic debuff icon for the Mover's samples
local SAMPLE_ROWS = 2
-- The container's aura groups, in the order they're laid out.
local GROUPS = { "tracked", "mine", "main" }

---@class EternityUITargetDebuffsModule: EternityUIModuleDefinition
---@field holder table? our frame, moved by the Mover
---@field container table? Blizzard's aura container, once created
---@field buttons table[] aura buttons the container created
---@field samples table[]
---@field running boolean?
---@field moverOpen boolean?
local Module = {
    schema = ns.OptionsSchema,
    tabs = { { key = SpellsTab.TAB, text = L.TAB, build = SpellsTab.Build } },
    Filters = Filters,
    Spells = Spells,
    SpellsTab = SpellsTab,
    buttons = {},
    samples = {},
}

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

local function options()
    local always, mine = Spells.Sets()
    return {
        origin = opt("show.origin"),
        crowdControl = opt("show.crowdControl"),
        dispellable = opt("show.dispellable"),
        max = opt("show.max"),
        always = always,
        mine = mine,
    }
end

local function rowWidth()
    local size, spacing, perRow = opt("look.size"), opt("look.spacing"), opt("look.perRow")
    return perRow * size + (perRow - 1) * spacing
end

-- The corner the icons start from, from where they grow.
local function corner()
    local vertical = opt("look.wrap") == "up" and "BOTTOM" or "TOP"
    local horizontal = opt("look.growth") == "left" and "RIGHT" or "LEFT"
    return vertical .. horizontal
end

local function groupLayout()
    local size, spacing = opt("look.size"), opt("look.spacing")
    return { elementWidth = size, elementHeight = size, elementSpacing = spacing, lineSpacing = spacing }
end

-- Buttons ---------------------------------------------------------------------------------------

local function paintBack(button)
    local field, line = Theme.colors.field or { 0, 0, 0, 0.5 }, Theme.colors.lineStrong or { 0, 0, 0, 1 }
    Shape.Paint(button.etBack, math.min(Theme.radius or 0, 4), field, line)
end

--- Our look on one of the container's buttons: size, fonts and which parts show.
local function styleButton(button)
    local size = opt("look.size")
    button:SetSize(size, size)
    button.etIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.etCount:SetFont(Theme.font, opt("look.countSize"), "OUTLINE")
    button.etTime:SetFont(Theme.font, opt("look.textSize"), "OUTLINE")
    button.etCooldown:SetDrawSwipe(opt("frame.swipe"))
    paintBack(button)
    -- Parts the container fills are attached or detached: it owns what they show.
    pcall(function()
        if opt("frame.durationText") then
            button:SetDurationText(button.etTime, {})
        else
            button:ClearDurationText()
            button.etTime:Hide()
        end
    end)
    pcall(function()
        local wanted = opt("frame.dispelBorder")
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
Module.StyleButton = styleButton

--- Called by the container for every button it creates.
local function initializeButton(button)
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
    Module.buttons[#Module.buttons + 1] = button
    styleButton(button)
end

-- Container ---------------------------------------------------------------------------------------

local function groupOptions(group, layoutIndex)
    local layout = groupLayout()
    layout.layoutIndex = layoutIndex
    return {
        maxFrameCount = group.max,
        candidateFilters = group.candidate,
        sortMethod = sortMethod(opt("show.sort")),
        sortDirection = sortDirection(),
        initializeFrame = initializeButton,
        layout = layout,
    }
end

--- Creates the container with its two groups (once). False when the client has none.
---@return boolean
function Module:CreateContainer()
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
        print(L.NO_CONTAINER)
        return false
    end
    self.container = container
    container:SetUnit("target")
    local groups = Filters.Groups(options())
    for index, key in ipairs(GROUPS) do
        container:AddAuraGroup(key, groups[key].filter, groupOptions(groups[key], index))
        container:SetAuraGroupEnabled(key, groups[key].enabled)
    end
    return true
end

--- Filters, order and counts of both groups from the options.
function Module:ApplyFilters()
    local container = self.container
    if not container then
        return
    end
    local groups = Filters.Groups(options())
    local method, direction = sortMethod(opt("show.sort")), sortDirection()
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
function Module:ApplyLayout()
    local holder = self.holder
    -- Zoom on top of the Mover's own scale (the Mover multiplies the frame's scale).
    holder:SetScale(opt("frame.scale"))
    local size, spacing = opt("look.size"), opt("look.spacing")
    local width = rowWidth()
    holder:SetSize(width, SAMPLE_ROWS * size + (SAMPLE_ROWS - 1) * spacing)
    local container = self.container
    if container then
        local point = corner()
        container:ClearAllPoints()
        container:SetPoint(point, holder, point)
        local flow = AnchorUtil and AnchorUtil.FlowDirection
        if container.SetFlowLayoutAnchorPoint then
            container:SetFlowLayoutAnchorPoint(point)
        end
        if flow and container.SetFlowLayoutGrowthDirection then
            container:SetFlowLayoutGrowthDirection(
                opt("look.growth") == "left" and flow.Left or flow.Right,
                opt("look.wrap") == "up" and flow.Up or flow.Down
            )
        end
        if container.SetFlowLayoutMaximumLineSize then
            container:SetFlowLayoutMaximumLineSize(width)
        end
        for index, key in ipairs(GROUPS) do
            local layout = groupLayout()
            layout.layoutIndex = index
            container:SetAuraGroupLayout(key, layout)
        end
    end
    for _, button in ipairs(self.buttons) do
        styleButton(button)
    end
    self:ShowSamples()
end

--- Shown while the module runs, in combat only if the option says so; always while moving.
function Module:UpdateVisibility()
    if not self.holder then
        return
    end
    local show = self.running and (self.moverOpen or not opt("show.inCombatOnly") or InCombatLockdown())
    self.holder:SetShown(show and true or false)
end

-- Samples: fake icons over the holder while the Mover is open, to see the size and the rows.
function Module:ShowSamples()
    local holder = self.holder
    local size, spacing, perRow = opt("look.size"), opt("look.spacing"), opt("look.perRow")
    local count = self.moverOpen and perRow * SAMPLE_ROWS or 0
    local point = corner()
    local dx = opt("look.growth") == "left" and -1 or 1
    local dy = opt("look.wrap") == "up" and 1 or -1
    for i = 1, math.max(count, #self.samples) do
        local sample = self.samples[i]
        if i <= count then
            if not sample then
                sample = CreateFrame("Frame", nil, holder)
                sample.etBack = Shape.New(sample, "BACKGROUND", -8)
                sample.icon = sample:CreateTexture(nil, "ARTWORK")
                sample.icon:SetPoint("TOPLEFT", 1, -1)
                sample.icon:SetPoint("BOTTOMRIGHT", -1, 1)
                sample.icon:SetTexture(SAMPLE_ICON)
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

-- /etdebuffs: the target's debuffs with their spell IDs, to fill the list.

local function secret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

function Module.PrintIDs()
    if not UnitExists("target") then
        print(L.IDS_NO_TARGET)
        return
    end
    local name = UnitName("target")
    local lines = {}
    for i = 1, 40 do
        local aura = C_UnitAuras.GetDebuffDataByIndex("target", i)
        if not aura then
            break
        end
        if secret(aura.spellId) or secret(aura.name) then
            print(L.IDS_SECRET)
            return
        end
        lines[#lines + 1] = L.IDS_LINE:format(aura.name, aura.spellId)
    end
    if secret(name) then
        name = L.TITLE
    end
    if #lines == 0 then
        print(L.IDS_NONE:format(name or ""))
        return
    end
    print(L.IDS_TITLE:format(name or ""))
    for _, line in ipairs(lines) do
        print(line)
    end
end

_G.SLASH_ETERNITYTARGETDEBUFFS1 = "/etdebuffs"
SlashCmdList.ETERNITYTARGETDEBUFFS = Module.PrintIDs

-- Lifecycle ---------------------------------------------------------------------------------------

function Module:OnEnable()
    self.running = true
    if not self.holder then
        self.holder = CreateFrame("Frame", "EternityUITargetDebuffs", UIParent)
        self.holder:SetFrameStrata("MEDIUM")
        self.holder:SetClampedToScreen(true)
    end
    E.Mover.Register({
        key = addonName,
        owner = addonName,
        label = L.TITLE,
        frame = self.holder,
        point = "CENTER",
        x = 0,
        y = -140,
        openOptions = function()
            E:OpenOptions(addonName)
        end,
    })
    -- A change in the list of spells reaches the container at once.
    Spells.onChange = function()
        if self.running then
            self:ApplyFilters()
        end
        if SpellsTab.frame and SpellsTab.frame:IsVisible() then
            SpellsTab.Refresh()
        end
    end
    Spells.ResumeSearches()
    if self:CreateContainer() then
        self.container:SetEnabled(true)
        self:ApplyFilters()
    end
    self:ApplyLayout()
    -- A new target refreshes the container: it follows the "target" token, not the unit.
    E.Events.On("PLAYER_TARGET_CHANGED", self, function()
        if self.container then
            self.container:UpdateAllAuras()
        end
    end)
    for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        E.Events.On(event, self, function()
            self:UpdateVisibility()
        end)
    end
    E.Events.Listen(E.Mover.TOGGLED, self, function(_, open)
        self.moverOpen = open and true or false
        self:ShowSamples()
        self:UpdateVisibility()
    end)
    E.Events.Listen(Theme.CHANGED, self, function()
        self:ApplyLayout()
    end)
    self:UpdateVisibility()
end

function Module:OnDisable()
    self.running = false
    E.Mover.Unregister(addonName)
    if self.container then
        self.container:SetEnabled(false)
    end
    self:UpdateVisibility()
end

function Module:OnConfigChanged(path)
    if not self.running then
        return
    end
    if path == nil or path:find("^show%.") then
        self:ApplyFilters()
    end
    if path == nil or path:find("^look%.") or path:find("^frame%.") or path == "show.sort" then
        self:ApplyLayout()
    end
    self:UpdateVisibility()
end

E:RegisterModule(addonName, Module)
