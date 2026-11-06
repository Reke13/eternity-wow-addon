-- Places Blizzard's group roll windows at a spot of the Mover. GroupLootContainer stays where it is
-- because it belongs to the managed bottom column; only the roll windows inside it are anchored
-- elsewhere, the way Blizzard lays them out: one above the other, from the bottom. Dragging a roll
-- window moves the spot, so it can be placed during a real roll as well as from the Mover.

---@type string, EternityUILootNamespace
local addonName, ns = ...
local E = EternityUI
local L, opt = ns.L, ns.opt

local KEY = addonName .. ".rolls"
local WIDTH, HEIGHT = 256, 100
local DEFAULT_RESERVED = 100
local ROLL_FRAMES = 4 -- GroupLootFrame1 to 4

---@class EternityUILootRolls
---@field holder table?
---@field hooked boolean?
---@field moving boolean?
---@field dragging boolean?
---@field handles table<table, boolean>? roll window -> whether it took the mouse before
local Rolls = {}
ns.Rolls = Rolls

--- Anchors each roll window to the holder, or back to the container.
function Rolls.Place()
    local container = _G.GroupLootContainer
    if not (Rolls.hooked and container and container.rollFrames) then
        return
    end
    local anchor = Rolls.moving and Rolls.holder or container
    local reserved = container.reservedSize or DEFAULT_RESERVED
    for i = 1, container.maxIndex or 0 do
        local frame = container.rollFrames[i]
        if frame then
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", anchor, "BOTTOM", 0, reserved * (i - 0.5))
        end
    end
end

local function startDrag()
    local entry = E.Mover.Entry(KEY)
    if Rolls.moving and not (entry and entry.locked) then
        Rolls.dragging = true
        Rolls.holder:StartMoving()
    end
end

-- Also when the roll ends under the cursor: a hidden frame gets no OnDragStop.
local function stopDrag()
    if Rolls.dragging then
        Rolls.dragging = false
        Rolls.holder:StopMovingOrSizing()
        Rolls.holder:SetUserPlaced(false)
        E.Mover.SaveFromFrame(KEY)
    end
end

-- Lets the roll windows be dragged, or gives them back as they were.
local function setDraggable(on)
    for i = 1, ROLL_FRAMES do
        local frame = _G["GroupLootFrame" .. i]
        if frame then
            Rolls.handles = Rolls.handles or {}
            if Rolls.handles[frame] == nil then
                Rolls.handles[frame] = frame:IsMouseEnabled()
                frame:HookScript("OnDragStart", startDrag)
                frame:HookScript("OnDragStop", stopDrag)
                frame:HookScript("OnHide", stopDrag)
            end
            if on then
                frame:EnableMouse(true)
                frame:RegisterForDrag("LeftButton")
            else
                frame:EnableMouse(Rolls.handles[frame])
                frame:RegisterForDrag()
            end
        end
    end
end

--- Brings everything in line with the options.
function Rolls.Apply()
    local moving = opt("rolls.move") and true or false
    if moving == Rolls.moving then
        return
    end
    Rolls.moving = moving
    setDraggable(moving)
    if moving then
        if not Rolls.holder then
            Rolls.holder = CreateFrame("Frame", "EternityUILootRollAnchor", UIParent)
            Rolls.holder:SetSize(WIDTH, HEIGHT)
            Rolls.holder:SetMovable(true)
            Rolls.holder:SetClampedToScreen(true)
        end
        if not Rolls.hooked and _G.GroupLootContainer_Update then
            Rolls.hooked = true
            hooksecurefunc("GroupLootContainer_Update", Rolls.Place)
        end
        E.Mover.Register({
            key = KEY,
            owner = addonName,
            label = L.ROLLS,
            frame = Rolls.holder,
            point = "BOTTOM",
            x = 0,
            y = 260,
            scalable = false,
            openOptions = function()
                E:OpenOptions(addonName)
            end,
        })
    else
        E.Mover.Unregister(KEY)
    end
    Rolls.Place()
end

function Rolls.Stop()
    stopDrag()
    Rolls.moving = false
    E.Mover.Unregister(KEY)
    setDraggable(false)
    Rolls.Place()
    Rolls.moving = nil
end
