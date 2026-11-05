-- EternityUI_Buffs: Blizzard's buff and debuff frames in the Mover.
-- Those frames belong to Edit Mode, so the Mover doesn't register them: each one gets a holder
-- (our own frame, invisible) that the Mover moves and scales, and Blizzard's frame follows it by
-- its top right corner, with the holder's scale. When Blizzard places its frame again (a layout
-- change, Edit Mode), the frame goes back to the holder on the next frame. While Edit Mode is
-- open the frames are Blizzard's; turning the module off gives them back to Edit Mode.

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

---@type EternityUIBuffsItem[]
local ITEMS = {
    { id = "buffs", global = "BuffFrame", label = L.BUFFS, x = -205, y = -13 },
    { id = "debuffs", global = "DebuffFrame", label = L.DEBUFFS, x = -205, y = -150 },
}

---@class EternityUIBuffsModule: EternityUIModuleDefinition
---@field running boolean?
local Module = { schema = ns.OptionsSchema, items = ITEMS }

local function opt(path)
    return E.store:Get(addonName, path)
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
        item.holder:SetSize(math.max(frame:GetWidth(), MIN_SIZE), math.max(frame:GetHeight(), MIN_SIZE))
    end
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
            schedule(item)
        end
    end)
    frame:HookScript("OnSizeChanged", function()
        if item.on then
            syncSize(item)
        end
    end)
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
    local frame = _G[item.global]
    if not frame then
        return
    end
    E.Combat.Run(item, function()
        frame:SetScale(item.scale or 1)
        if frame.ApplySystemAnchor then
            pcall(frame.ApplySystemAnchor, frame)
        end
    end)
end

--- Starts or stops each frame from the options.
function Module:Apply()
    for _, item in ipairs(ITEMS) do
        if self.running and opt("frames." .. item.id) then
            start(item)
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
                if item.on and frame and frame.ApplySystemAnchor then
                    pcall(frame.ApplySystemAnchor, frame)
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
    self:Apply()
end

function Module:OnDisable()
    self.running = false
    self:Apply()
end

function Module:OnConfigChanged()
    self:Apply()
end

E:RegisterModule(addonName, Module)
