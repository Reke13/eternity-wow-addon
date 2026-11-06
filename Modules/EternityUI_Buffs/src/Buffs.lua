-- EternityUI_Buffs: Blizzard's buff and debuff frames in the Mover.
-- Those frames belong to Edit Mode, so the Mover doesn't register them: each one gets a holder
-- (our own frame, invisible) that the Mover moves and scales, and Blizzard's frame follows it by
-- its top right corner, with the holder's scale. When Blizzard places its frame again (a layout
-- change, Edit Mode), the frame goes back to the holder on the next frame. While Edit Mode is
-- open the frames are Blizzard's; turning the module off gives them back to Edit Mode.
-- Layout: the icons' arrangement stays in Edit Mode. Blizzard reads the AuraContainer's values on
-- every aura update, so an addon writing them would taint those updates until /reload, and they
-- then fail on secret auras in combat. Its anchoring (ApplySystemAnchor) isn't called from here
-- either: the frame gets back the points Blizzard last gave it.
-- Samples: fake icons drawn by us over the frame's grid, to see the layout without real buffs.

---The module's private table.
---@class EternityUIBuffsNamespace
---@field OptionsSchema table schema generated from options.json (src/Generated/Options.lua)

---@type string, EternityUIBuffsNamespace
local addonName, ns = ...
local E = EternityUI

local L = E.NewLocale({
    BUFFS = "Buffs",
    DEBUFFS = "Debuffs",
}, {
    BUFFS = "Bufos",
    DEBUFFS = "Perjuicios",
})

local MIN_SIZE = 32 -- the holder's smallest side, so the Mover's handle can be grabbed

---@class EternityUIBuffsItem
---@field id string option and key suffix
---@field global string Blizzard's frame
---@field label string
---@field x number default offset from the top right corner (when the frame isn't placed yet)
---@field y number
---@field holder table?
---@field on boolean? following its holder
---@field busy boolean? we are moving the frame ourselves
---@field hooked boolean?
---@field scale number? Blizzard's scale of the frame before we touched it
---@field points table[]? the frame's points as Blizzard last set them
---@field samples string[] icons of the samples
---@field debuff boolean? samples with a debuff border
---@field preview table? the sample icons' frame

---@type EternityUIBuffsItem[]
local ICONS = "Interface\\Icons\\"
local ITEMS = {
    {
        id = "buffs",
        global = "BuffFrame",
        label = L.BUFFS,
        x = -205,
        y = -13,
        samples = {
            "Spell_Holy_WordFortitude",
            "Spell_Nature_Regeneration",
            "Spell_Holy_MagicalSentry",
            "Spell_Holy_GreaterBlessingofKings",
            "Ability_Warrior_BattleShout",
            "Spell_Holy_PowerWordShield",
            "Spell_Nature_Rejuvenation",
            "INV_Potion_54",
            "Spell_Frost_FrostArmor02",
            "Spell_Holy_Renew",
            "Spell_Nature_LightningShield",
            "INV_Misc_Food_15",
        },
    },
    {
        id = "debuffs",
        global = "DebuffFrame",
        label = L.DEBUFFS,
        x = -205,
        y = -150,
        debuff = true,
        samples = {
            "Spell_Shadow_ShadowWordPain",
            "Spell_Shadow_CurseOfTounges",
            "Ability_Creature_Poison_02",
            "Spell_Frost_FrostNova",
            "Ability_Gouge",
        },
    },
}
local BORDER = { 0, 0, 0, 1 }
local DEBUFF_BORDER = { 0.8, 0.1, 0.1, 1 }

---@class EternityUIBuffsModule: EternityUIModuleDefinition
---@field running boolean?
local Module = { schema = ns.OptionsSchema, items = ITEMS }

local function opt(path)
    return E.store:Get(addonName, path)
end

-- A size that may be secret (a frame showing secret values returns secret geometry): the fallback
-- then, since doing math on a secret errors.
local function plain(value, fallback)
    if value == nil or (issecretvalue ~= nil and issecretvalue(value)) then
        return fallback
    end
    return value
end

local function keyOf(item)
    return addonName .. "." .. item.id
end

local function editModeActive()
    local manager = EditModeManagerFrame
    return manager ~= nil and manager.IsEditModeActive ~= nil and manager:IsEditModeActive()
end

-- The holder takes the frame's size (both have the same scale, so they cover the same area).
local function syncSize(item)
    local frame = _G[item.global]
    if frame and item.holder then
        local width, height = plain(frame:GetWidth(), nil), plain(frame:GetHeight(), nil)
        -- Secret in combat: the holder keeps its size until the frame can be measured again.
        if width and height then
            item.holder:SetSize(math.max(width, MIN_SIZE), math.max(height, MIN_SIZE))
        end
    end
end

-- Keeps where Blizzard put the frame, to give it back.
local function remember(item, frame)
    local points = {}
    for i = 1, frame:GetNumPoints() do
        local point = { frame:GetPoint(i) }
        if plain(point[4], nil) == nil or plain(point[5], nil) == nil then
            return
        end
        points[i] = point
    end
    if #points > 0 then
        item.points = points
    end
end

-- Back on Blizzard's points, without touching Edit Mode's code.
local function giveBack(item, frame)
    if not item.points then
        return
    end
    item.busy = true
    frame:ClearAllPoints()
    for _, point in ipairs(item.points) do
        frame:SetPoint(unpack(point))
    end
    item.busy = false
end

-- Puts Blizzard's frame on its holder, with the holder's scale.
local function follow(item)
    local frame = _G[item.global]
    if not (Module.running and item.on and frame and item.holder) or editModeActive() then
        return
    end
    E.Combat.Run(item, function()
        if not (Module.running and item.on) or editModeActive() then
            return
        end
        item.busy = true
        frame:SetScale(item.holder:GetScale())
        frame:ClearAllPoints()
        frame:SetPoint("TOPRIGHT", item.holder, "TOPRIGHT", 0, 0)
        item.busy = false
    end)
end

-- Blizzard placed the frame again: back to the holder, once, on the next frame.
local function schedule(item)
    if item.pending then
        return
    end
    item.pending = true
    C_Timer.After(0, function()
        item.pending = false
        follow(item)
    end)
end

-- Hooks are for good (they can't be removed): they do nothing while the item is off.
local function hook(item, frame)
    if item.hooked then
        return
    end
    item.hooked = true
    hooksecurefunc(frame, "SetPoint", function()
        if not item.busy and item.on then
            remember(item, frame)
            schedule(item)
        end
    end)
    frame:HookScript("OnSizeChanged", function()
        if item.on then
            syncSize(item)
        end
    end)
    -- Edit Mode laid the icons out again: the samples follow, next frame.
    if frame.UpdateGridLayout then
        hooksecurefunc(frame, "UpdateGridLayout", function()
            if item.on and item.preview and item.preview:IsShown() then
                C_Timer.After(0, function()
                    Module.Refresh(item)
                end)
            end
        end)
    end
end

-- Where the frame is now, as an offset of its top right corner from the screen's: the default
-- position, so turning the module on doesn't move anything.
local function currentOffset(item, frame)
    local right, top = frame:GetRight(), frame:GetTop()
    if not right or not top then
        return item.x, item.y
    end
    local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return right * scale - UIParent:GetRight(), top * scale - UIParent:GetTop()
end

-- Samples ---------------------------------------------------------------------------------------

local function sampleCell(preview, i)
    local cell = preview.cells[i]
    if cell then
        return cell
    end
    cell = CreateFrame("Frame", nil, preview)
    cell.border = cell:CreateTexture(nil, "BACKGROUND")
    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.duration = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    preview.cells[i] = cell
    return cell
end

--- Draws the samples on the frame's grid as Blizzard lays it out now.
local function updatePreview(item)
    local frame = _G[item.global]
    local wanted = Module.running and item.on and (opt("frames.preview") or Module.moverOpen)
    if not (wanted and frame) then
        if item.preview then
            item.preview:Hide()
        end
        return
    end
    if not item.preview then
        item.preview = CreateFrame("Frame", nil, UIParent)
        item.preview:SetFrameStrata("HIGH")
        item.preview.cells = {}
    end
    local preview = item.preview
    local c = frame.AuraContainer or {}
    local horizontal = c.isHorizontal ~= false
    local right, top = c.addIconsToRight == true, c.addIconsToTop == true
    local stride, pad, scale = c.iconStride or 10, c.iconPadding or 5, c.iconScale or 1
    local first = frame.auraFrames and frame.auraFrames[1]
    local width = plain(first and first:GetWidth(), 30)
    local height = plain(first and first:GetHeight(), 40)
    local iconSize = plain(first and first.Icon and first.Icon:GetWidth(), width)
    local corner = (top and "BOTTOM" or "TOP") .. (right and "LEFT" or "RIGHT")
    preview:SetScale(frame:GetScale())
    preview:ClearAllPoints()
    preview:SetAllPoints(frame)
    preview:Show()
    for i, name in ipairs(item.samples) do
        local cell = sampleCell(preview, i)
        local slot = i - 1
        local col, row = slot % stride, math.floor(slot / stride)
        if not horizontal then
            col, row = row, col
        end
        local x = col * (width + pad) * scale * (right and 1 or -1)
        local y = row * (height + pad) * scale * (top and 1 or -1)
        cell:ClearAllPoints()
        cell:SetPoint(corner, frame, corner, x, y)
        cell:SetSize(width * scale, height * scale)
        cell.icon:ClearAllPoints()
        cell.icon:SetPoint("TOP", cell, "TOP", 0, 0)
        cell.icon:SetSize(iconSize * scale, iconSize * scale)
        cell.icon:SetTexture(ICONS .. name)
        cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        cell.border:ClearAllPoints()
        cell.border:SetPoint("TOPLEFT", cell.icon, "TOPLEFT", -1, 1)
        cell.border:SetPoint("BOTTOMRIGHT", cell.icon, "BOTTOMRIGHT", 1, -1)
        cell.border:SetColorTexture(unpack(item.debuff and DEBUFF_BORDER or BORDER))
        cell.duration:ClearAllPoints()
        cell.duration:SetPoint("TOP", cell.icon, "BOTTOM", 0, -1)
        cell.duration:SetText((i * 3) .. " m")
        cell:Show()
    end
    for i = #item.samples + 1, #preview.cells do
        preview.cells[i]:Hide()
    end
end

local function start(item)
    local frame = _G[item.global]
    if not frame or item.on then
        return
    end
    item.scale = item.scale or frame:GetScale()
    if not item.holder then
        item.holder = CreateFrame("Frame", nil, UIParent)
        -- The Mover scales the holder; the frame takes the same scale.
        hooksecurefunc(item.holder, "SetScale", function()
            follow(item)
        end)
    end
    local x, y = currentOffset(item, frame)
    remember(item, frame)
    item.on = true
    hook(item, frame)
    syncSize(item)
    item.holder:Show()
    E.Mover.Register({
        key = keyOf(item),
        owner = addonName,
        label = item.label,
        frame = item.holder,
        point = "TOPRIGHT",
        x = x,
        y = y,
        openOptions = function()
            E:OpenOptions(addonName)
        end,
    })
    follow(item)
end

-- Gives the frame back to Edit Mode (its own position and scale).
local function stop(item)
    if not item.on then
        return
    end
    item.on = false
    E.Mover.Unregister(keyOf(item))
    if item.holder then
        item.holder:Hide()
    end
    updatePreview(item)
    local frame = _G[item.global]
    if not frame then
        return
    end
    E.Combat.Run(item, function()
        frame:SetScale(item.scale or 1)
        giveBack(item, frame)
    end)
end

--- The samples of one frame, from the options.
---@param item EternityUIBuffsItem
function Module.Refresh(item)
    updatePreview(item)
end

--- Starts or stops each frame from the options.
function Module:Apply()
    for _, item in ipairs(ITEMS) do
        if self.running and opt("frames." .. item.id) then
            start(item)
            Module.Refresh(item)
        else
            stop(item)
        end
    end
end

local function hookEditMode()
    local manager = EditModeManagerFrame
    if Module.editModeHooked or not manager then
        return
    end
    Module.editModeHooked = true
    -- Entering: Blizzard's own place, so Edit Mode shows its frames where it keeps them.
    if manager.EnterEditMode then
        hooksecurefunc(manager, "EnterEditMode", function()
            for _, item in ipairs(ITEMS) do
                local frame = _G[item.global]
                if item.on and frame then
                    E.Combat.Run(item, function()
                        giveBack(item, frame)
                    end)
                end
            end
        end)
    end
    if manager.ExitEditMode then
        hooksecurefunc(manager, "ExitEditMode", function()
            for _, item in ipairs(ITEMS) do
                schedule(item)
            end
        end)
    end
end

function Module:OnEnable()
    self.running = true
    hookEditMode()
    -- The samples are for a look now: they don't come back after a /reload.
    if opt("frames.preview") then
        E.store:Set(addonName, "frames.preview", false)
    end
    -- With the Mover open the samples show, so the frames have something to place.
    E.Events.Listen(E.Mover.TOGGLED, self, function(_, open)
        self.moverOpen = open and true or false
        for _, item in ipairs(ITEMS) do
            updatePreview(item)
        end
    end)
    self:Apply()
end

function Module:OnDisable()
    self.running = false
    self.moverOpen = false
    self:Apply()
end

function Module:OnConfigChanged()
    self:Apply()
end

E:RegisterModule(addonName, Module)
