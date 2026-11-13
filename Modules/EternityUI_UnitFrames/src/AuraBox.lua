-- EternityUI_UnitFrames: the aura icons of a frame, in Blizzard's custom aura container
-- (CreateFrame("AuraContainer", ..., "CustomAuraContainerTemplate")). The container reads,
-- filters, sorts and draws the auras itself, so they keep showing in combat, when aura data is
-- secret to addons. This file only configures it, from the frame's "Buffs" and "Debuffs" options:
--   * Five aura groups, laid out in this order: debuffs of the "Always show" list, the other
--     debuffs, buffs of the filters applied to the frame (Filters.lua: "always", then "only
--     mine"), the other buffs. The listed spells don't repeat in the rest.
--   * The game's filter string: who cast it (PLAYER / !PLAYER), only dispellable (RAID), crowd
--     control (CROWD_CONTROL / !CROWD_CONTROL).
--   * The container's candidate filters: dispel types, boss auras, stealable, duration and the
--     spell ID lists. Spell IDs can only be tested on buffs of friendly units and debuffs of
--     enemies (the container's own rule, AuraContainerUtil.CanApplyIdentityCandidateFilters);
--     elsewhere a list matches nothing and an exclusion is ignored.
--   * The buttons get our regions (icon, time shadow, stacks, dispel border); the container fills
--     them.

---@type string, EternityUIUnitFramesNamespace
local addonName, ns = ...
local E = EternityUI
local Shape, Theme = E.Shape, E.Theme
local Style = ns.Style
local U = Style.U

local GAP = 2
local BORDER = 2 -- the debuff border's width
local TYPES = { magic = "Magic", curse = "Curse", disease = "Disease", poison = "Poison" }
-- Longer than any aura: "only the ones that run out" (maxDuration also leaves permanent ones out).
local NO_LIMIT = 365 * 24 * 3600

---@class EternityUIUnitFramesAuraBox
local AuraBox = {}
ns.AuraBox = AuraBox

--- A set of spell IDs from text like "7386, 11597": { [id] = true } and how many.
---@param text string?
---@return table<integer, boolean>
---@return integer
function AuraBox.ParseIDs(text)
    local ids, count = {}, 0
    for piece in tostring(text or ""):gmatch("[^,;%s]+") do
        local id = tonumber(piece)
        if id and id > 0 and id == math.floor(id) and not ids[id] then
            ids[id] = true
            count = count + 1
        end
    end
    return ids, count
end

local function origin(tokens, value)
    if value == "mine" then
        tokens[#tokens + 1] = "PLAYER"
    elseif value == "others" then
        tokens[#tokens + 1] = "!PLAYER"
    end
end

--- The four groups of a frame from its options: { [key] = { enabled, filter, candidate, max } }.
--- Pure data, for the container and the tests.
---@param key string the frame's options key ("party", "target"...)
---@return table
function AuraBox.Groups(key)
    local function B(id)
        return U(key, "Buffs", id)
    end
    local function D(id)
        return U(key, "Debuffs", id)
    end
    local groups = {}

    -- Debuffs.
    local dTokens = { "HARMFUL" }
    origin(dTokens, D("origin"))
    if D("dispellable") then
        dTokens[#dTokens + 1] = "RAID"
    end
    if D("crowdControl") == "hide" then
        dTokens[#dTokens + 1] = "!CROWD_CONTROL"
    elseif D("crowdControl") == "only" then
        dTokens[#dTokens + 1] = "CROWD_CONTROL"
    end
    local dFilter = table.concat(dTokens, "|")
    local dCandidate, any = {}, false
    local excluded, included, allTyped = {}, {}, true
    for id, name in pairs(TYPES) do
        if D(id) then
            included[name] = true
        else
            excluded[name], allTyped = true, false
        end
    end
    if not D("untyped") then
        -- Untyped auras have no dispel name to exclude: keep only the typed ones that are on.
        dCandidate.includeDispelTypes, any = included, true
    elseif not allTyped then
        dCandidate.excludeDispelTypes, any = excluded, true
    end
    if D("bossOnly") then
        dCandidate.isBossAura, any = true, true
    end
    local dAlways, dCount = AuraBox.ParseIDs(D("always"))
    local dHide = AuraBox.ParseIDs(D("hide"))
    local dSkip = {}
    for id in pairs(dAlways) do
        dSkip[id] = true
    end
    for id in pairs(dHide) do
        dSkip[id] = true
    end
    if next(dSkip) then
        dCandidate.excludeSpellIDs, any = dSkip, true
    end
    local debuffs = D("enabled") and true or false
    groups.debuffAlways = {
        enabled = debuffs and dCount > 0,
        filter = "HARMFUL",
        candidate = dCount > 0 and { includeSpellIDs = dAlways } or nil,
        max = math.max(dCount * 2, 1),
    }
    groups.debuffMain = { enabled = debuffs, filter = dFilter, candidate = any and dCandidate or nil, max = D("max") }

    -- Buffs.
    local bTokens = { "HELPFUL" }
    origin(bTokens, B("origin"))
    local bFilter = table.concat(bTokens, "|")
    local bCandidate
    any = false
    bCandidate = {}
    if B("duration") == "timed" then
        bCandidate.maxDuration, any = NO_LIMIT, true
    elseif B("duration") == "short" then
        bCandidate.maxDuration, any = B("maxMinutes") * 60, true
    end
    if B("stealable") then
        bCandidate.isStealable, any = true, true
    end
    local bAlways, bMine = ns.Filters.SetsFor(key)
    local bCount, mCount = 0, 0
    for _ in pairs(bAlways) do
        bCount = bCount + 1
    end
    for _ in pairs(bMine) do
        mCount = mCount + 1
    end
    local bHide = AuraBox.ParseIDs(B("hide"))
    local bSkip = {}
    for id in pairs(bAlways) do
        bSkip[id] = true
    end
    for id in pairs(bMine) do
        bSkip[id] = true
    end
    for id in pairs(bHide) do
        bSkip[id] = true
    end
    if next(bSkip) then
        bCandidate.excludeSpellIDs, any = bSkip, true
    end
    local buffs = B("enabled") and true or false
    groups.buffAlways = {
        enabled = buffs and bCount > 0,
        filter = "HELPFUL",
        candidate = bCount > 0 and { includeSpellIDs = bAlways } or nil,
        max = math.max(bCount * 2, 1),
    }
    groups.buffMine = {
        enabled = buffs and mCount > 0,
        filter = "HELPFUL|PLAYER",
        candidate = mCount > 0 and { includeSpellIDs = bMine } or nil,
        max = math.max(mCount * 2, 1),
    }
    groups.buffMain = {
        enabled = buffs and not B("onlyList"),
        filter = bFilter,
        candidate = any and bCandidate or nil,
        max = B("max"),
    }
    return groups
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

-- Buttons ---------------------------------------------------------------------------------------

local function styleButton(f, button)
    local key = f.uf.key
    local size = U(key, "Auras", "size")
    button:SetSize(size, size)
    -- The container's tooltip goes to the icon's left by default, under the icon before it, so it
    -- looked like that one's: centered under the icon (over it when the icons are above).
    if button.SetTooltipAnchorPoint then
        local position = U(key, "Auras", button.etKind == "buffs" and "buffPosition" or "debuffPosition")
        if position == "above" then
            pcall(button.SetTooltipAnchorPoint, button, "ANCHOR_TOP", 0, 4)
        else
            pcall(button.SetTooltipAnchorPoint, button, "ANCHOR_BOTTOM", 0, -4)
        end
    end
    Shape.Paint(button.etBack, 0, { 0, 0, 0, 0.6 }, Theme.colors.lineStrong or { 0, 0, 0, 1 })
    button.etCooldown:SetDrawSwipe(U(key, "Auras", "swipe") and true or false)
    Style.Font(button.etCount, math.max(8, math.floor(size * 0.5)))
    -- Debuffs: our own square behind the icon, tinted by the container with the dispel type's
    -- color (PreserveAsset keeps our texture and only colors it); untyped ones too, in red.
    pcall(function()
        local wanted = U(key, "Auras", "dispelBorder")
        if wanted and not button.etDispelOn then
            local styles = Enum.CustomAuraButtonDispelTypeTextureStyle
            button:AddDispelTypeTexture(button.etDispel, {
                style = styles and styles.PreserveAsset,
                showWhenHarmful = true,
                showWithoutDispelType = true,
            })
            button.etDispelOn = true
        elseif not wanted and button.etDispelOn then
            button:RemoveDispelTypeTexture(button.etDispel)
            button.etDispel:Hide()
            button.etDispelOn = false
        end
    end)
end

local function initializeButton(f, button, kind)
    button.etKind = kind
    button.etBack = Shape.New(button, "BACKGROUND", -8)
    button.etIcon = button:CreateTexture(nil, "ARTWORK")
    button.etIcon:SetPoint("TOPLEFT", BORDER, -BORDER)
    button.etIcon:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
    button.etIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.etCooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.etCooldown:SetAllPoints(button.etIcon)
    button.etCooldown:SetReverse(true)
    button.etCooldown:SetDrawEdge(false)
    button.etCooldown:SetHideCountdownNumbers(true)
    local texts = CreateFrame("Frame", nil, button)
    texts:SetAllPoints()
    texts:SetFrameLevel(button.etCooldown:GetFrameLevel() + 2)
    button.etCount = texts:CreateFontString(nil, "OVERLAY")
    button.etCount:SetPoint("BOTTOMRIGHT", 1, 0)
    Style.Font(button.etCount, 10)
    -- Behind the icon, over the plain back: the icon's inset leaves it as a border.
    button.etDispel = button:CreateTexture(nil, "BACKGROUND", nil, -5)
    button.etDispel:SetTexture("Interface\\Buttons\\WHITE8X8")
    button.etDispel:SetAllPoints()
    button.etDispel:Hide()
    button:SetIcon(button.etIcon)
    button:SetDurationCooldown(button.etCooldown)
    button:SetApplicationCount(button.etCount)
    f.auraButtons[#f.auraButtons + 1] = button
    styleButton(f, button)
end

-- Containers --------------------------------------------------------------------------------------
-- Two per frame, each placed on its own: debuffs (their groups) and buffs. f.auraContainers holds
-- them; f.auraContainer is the debuffs' one (any of them tells the frame has containers).

local KINDS = {
    { key = "debuffs", groups = { "debuffAlways", "debuffMain" } },
    { key = "buffs", groups = { "buffAlways", "buffMine", "buffMain" } },
}

-- Where a box goes and how its icons grow: the box's point, the frame's point, offsets, and the
-- growth across and down.
local PLACES = {
    below = { point = "TOPLEFT", to = "BOTTOMLEFT", x = 0, y = -1, across = "Right", down = "Down", stack = -1 },
    above = { point = "BOTTOMLEFT", to = "TOPLEFT", x = 0, y = 1, across = "Right", down = "Up", stack = 1 },
    left = { point = "TOPRIGHT", to = "TOPLEFT", x = -1, y = 0, across = "Left", down = "Down", stack = -1 },
    right = { point = "TOPLEFT", to = "TOPRIGHT", x = 1, y = 0, across = "Right", down = "Down", stack = -1 },
    insideLeft = { point = "BOTTOMLEFT", to = "BOTTOMLEFT", x = 1, y = 1, across = "Right", down = "Up", stack = 1, inside = true },
    insideRight = { point = "BOTTOMRIGHT", to = "BOTTOMRIGHT", x = -1, y = 1, across = "Left", down = "Up", stack = 1, inside = true },
}

AuraBox.PLACES = PLACES
AuraBox.GAP = GAP

local function groupLayout(f, index)
    local size = U(f.uf.key, "Auras", "size")
    return { elementWidth = size, elementHeight = size, elementSpacing = GAP, lineSpacing = GAP, layoutIndex = index }
end

--- Creates the frame's two containers (once). False when the client has none.
---@param f table
---@return boolean
function AuraBox.Create(f)
    if f.auraContainers then
        return true
    end
    if AuraBox.missing then
        return false
    end
    if C_AddOns and C_AddOns.LoadAddOn and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
    -- The container may make buttons as soon as a group is added.
    f.auraButtons = f.auraButtons or {}
    -- The options' preview draws example icons: only the boxes, no containers (they're costly).
    if f.previewOnly then
        f.auraBoxes = { debuffs = CreateFrame("Frame", nil, f.auras), buffs = CreateFrame("Frame", nil, f.auras) }
        f.auraContainers = {}
        return true
    end
    local groups = AuraBox.Groups(f.uf.key)
    local method, direction = sortMethod(U(f.uf.key, "Auras", "sort")), sortDirection()
    local containers, boxes = {}, {}
    for _, kind in ipairs(KINDS) do
        local box = CreateFrame("Frame", nil, f.auras)
        local ok, container = pcall(CreateFrame, "AuraContainer", nil, box, "CustomAuraContainerTemplate")
        if not ok or not container or not container.AddAuraGroup then
            AuraBox.missing = true
            return false
        end
        for index, name in ipairs(kind.groups) do
            local group = groups[name]
            container:AddAuraGroup(name, group.filter, {
                maxFrameCount = group.max,
                candidateFilters = group.candidate,
                sortMethod = method,
                sortDirection = direction,
                initializeFrame = function(button)
                    initializeButton(f, button, kind.key)
                end,
                layout = groupLayout(f, index),
            })
            container:SetAuraGroupEnabled(name, group.enabled)
        end
        if f.unit then
            container:SetUnit(f.unit)
        end
        containers[kind.key], boxes[kind.key] = container, box
    end
    f.auraContainers, f.auraBoxes = containers, boxes
    f.auraContainer = containers.debuffs
    return true
end

local waiting = {} -- buttons that showed someone in combat: their containers come after it
local afterCombat

--- Makes a group button's aura containers the first time it shows someone, out of combat (in
--- combat, as soon as it ends). True when the frame has them.
---@param f table
---@return boolean
function AuraBox.Ensure(f)
    if f.auraContainers or not f.aurasWaiting or not f.unit then
        return f.auraContainers ~= nil
    end
    if InCombatLockdown() then
        waiting[f] = true
        if not afterCombat then
            afterCombat = CreateFrame("Frame")
            afterCombat:SetScript("OnEvent", function()
                for button in pairs(waiting) do
                    waiting[button] = nil
                    if button.unit then
                        ns.Elements.UpdateAuras(button, true)
                    end
                end
            end)
            afterCombat:RegisterEvent("PLAYER_REGEN_ENABLED")
        end
        return false
    end
    f.aurasWaiting = nil
    AuraBox.Layout(f, f.auraWidth or f:GetWidth())
    return f.auraContainers ~= nil
end

-- How many rows of icons a kind can take at most (to stack the other kind after it).
local function rows(f, kind, groups, perRow)
    local count = 0
    for _, name in ipairs(kind.groups) do
        local group = groups[name]
        if group.enabled then
            count = count + group.max
        end
    end
    return math.ceil(math.min(count, 40) / math.max(perRow, 1))
end

--- Places both boxes, sizes and the way the icons grow, from the options.
---@param f table
---@param width number the frame's width
function AuraBox.Layout(f, width)
    -- A group or raid button gets its containers (costly: most of the time making each of the 85
    -- buttons) once someone is shown in it (AuraBox.Ensure).
    if f.uf.group and not f.auraContainers and not f.unit and not f.previewOnly then
        f.aurasWaiting, f.auraWidth = true, width
        return
    end
    if not AuraBox.Create(f) then
        return
    end
    local key = f.uf.key
    local size, perRow = U(key, "Auras", "size"), U(key, "Auras", "perRow")
    local line = perRow * size + (perRow - 1) * GAP
    local step = size + GAP
    local groups = AuraBox.Groups(key)
    local flow = AnchorUtil and AnchorUtil.FlowDirection
    local used = {} -- position -> rows already taken there
    for _, kind in ipairs(KINDS) do
        local position = U(key, "Auras", kind.key == "buffs" and "buffPosition" or "debuffPosition")
        local place = PLACES[position] or PLACES.below
        local box, container = f.auraBoxes[kind.key], f.auraContainers[kind.key]
        local anchor = place.inside and f.health or f
        local x = place.x * (GAP + 1)
        local y = place.y * (GAP + 1)
        if position == "below" then
            y = y - (f.castSpace or 0)
        end
        -- The second kind at a place goes after the first one's rows.
        local taken = used[position] or 0
        y = y + place.stack * taken * step
        box:ClearAllPoints()
        box:SetPoint(place.point, anchor, place.to, x, y)
        box:SetSize(math.max(line, 1), size)
        used[position] = taken + rows(f, kind, groups, perRow)
        if container then
            for index, name in ipairs(kind.groups) do
                container:SetAuraGroupLayout(name, groupLayout(f, index))
            end
            container:ClearAllPoints()
            container:SetPoint(place.point, box, place.point)
            if container.SetFlowLayoutAnchorPoint then
                container:SetFlowLayoutAnchorPoint(place.point)
            end
            if flow and container.SetFlowLayoutGrowthDirection then
                container:SetFlowLayoutGrowthDirection(flow[place.across], flow[place.down])
            end
            if container.SetFlowLayoutMaximumLineSize then
                container:SetFlowLayoutMaximumLineSize(line)
            end
        end
    end
    AuraBox.ApplyFilters(f)
    for _, button in ipairs(f.auraButtons) do
        styleButton(f, button)
    end
end

--- Only the filters, order, counts and whether the groups show: nothing moves. What a change in
--- a filter needs, for every frame at once.
---@param f table
function AuraBox.ApplyFilters(f)
    if not f.auraContainers then
        return
    end
    local groups = AuraBox.Groups(f.uf.key)
    local method, direction = sortMethod(U(f.uf.key, "Auras", "sort")), sortDirection()
    for _, kind in ipairs(KINDS) do
        local container = f.auraContainers[kind.key]
        if not container then
            return
        end
        local anything = false
        for _, name in ipairs(kind.groups) do
            local group = groups[name]
            container:SetAuraGroupFilterString(name, group.filter)
            container:SetAuraGroupCandidateFilters(name, group.candidate)
            container:SetAuraGroupMaxFrameCount(name, group.max)
            container:SetAuraGroupSortMethod(name, method, direction)
            container:SetAuraGroupEnabled(name, group.enabled)
            anything = anything or group.enabled
        end
        container:SetShown(anything)
    end
end

--- Which unit the containers show, and a full refresh. The container only refreshes itself
--- when its unit token changes (AuraContainerSharedMixin:SetUnit), not when someone else is now
--- behind the same token (a new target, a raid reshuffled, someone back in view): then
--- UpdateAllAuras, which Blizzard exposes for exactly that.
---@param f table
---@param unit string?
function AuraBox.SetUnit(f, unit)
    if not (f.auraContainers and unit) then
        return
    end
    for _, container in pairs(f.auraContainers) do
        if container.GetUnit and container:GetUnit() == unit then
            if container.UpdateAllAuras then
                pcall(container.UpdateAllAuras, container)
            end
        elseif container.SetUnit then
            pcall(container.SetUnit, container, unit)
        end
    end
end
