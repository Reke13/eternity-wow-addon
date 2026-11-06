-- EternityUI_Objectives position: the tracker in the core's Mover, when the option asks for it.
-- The tracker is a system of Blizzard's Edit Mode inside its managed right column, so the Mover
-- doesn't register it: an invisible holder is moved instead and the tracker follows it by its top
-- right corner. When Blizzard places the tracker again (a layout of the right column, leaving Edit
-- Mode) it goes back to the holder on the next frame; while Edit Mode is open it's Blizzard's.
-- Known risk, accepted by the option: anchoring a frame of the managed right column from an addon
-- can taint Blizzard's next layout of that column. The scale stays the Size > Scale option.

---@type string, EternityUIObjectivesNamespace
local addonName, ns = ...
local E = EternityUI
local Core, L = ns.Core, ns.L
local opt = Core.Opt

local KEY = addonName .. ".tracker"
local MIN_SIZE = 32

---@class EternityUIObjectivesPosition
---@field holder table?
---@field on boolean? the tracker follows the holder
---@field busy boolean? we are anchoring the tracker ourselves
---@field hooked boolean?
---@field pending boolean?
---@field points table[]? the tracker's points as Blizzard last set them
local Position = {}
ns.Position = Position

local function plain(value)
    if value == nil or Core.Secret(value) then
        return nil
    end
    return value
end

local function editModeActive()
    local manager = _G.EditModeManagerFrame
    return manager ~= nil and manager.IsEditModeActive ~= nil and manager:IsEditModeActive()
end

-- The holder covers the tracker: its size in UIParent units.
local function syncSize(tracker)
    local holder = Position.holder
    local width, height = plain(tracker:GetWidth()), plain(tracker:GetHeight())
    if not (holder and width and height) then
        return
    end
    local ratio = tracker:GetEffectiveScale() / UIParent:GetEffectiveScale()
    holder:SetSize(math.max(width * ratio, MIN_SIZE), math.max(height * ratio, MIN_SIZE))
end

-- Keeps where Blizzard put the tracker, to give it back.
local function remember(tracker)
    local points = {}
    for i = 1, tracker:GetNumPoints() do
        local point = { tracker:GetPoint(i) }
        if plain(point[4]) == nil or plain(point[5]) == nil then
            return
        end
        points[i] = point
    end
    if #points > 0 then
        Position.points = points
    end
end

--- Puts the tracker on its holder (after combat if it's on now).
function Position:Follow()
    local tracker = Core.Tracker()
    if not (self.on and tracker and self.holder) or editModeActive() then
        return
    end
    E.Combat.Run(self, function()
        if not self.on or editModeActive() then
            return
        end
        self.busy = true
        tracker:ClearAllPoints()
        tracker:SetPoint("TOPRIGHT", self.holder, "TOPRIGHT", 0, 0)
        self.busy = false
    end)
end

-- Blizzard placed the tracker again: back to the holder, once, on the next frame.
function Position:Schedule()
    if self.pending then
        return
    end
    self.pending = true
    C_Timer.After(0, function()
        self.pending = false
        self:Follow()
    end)
end

local function hook(tracker)
    if Position.hooked then
        return
    end
    Position.hooked = true
    hooksecurefunc(tracker, "SetPoint", function()
        if Position.on and not Position.busy then
            remember(tracker)
            Position:Schedule()
        end
    end)
    tracker:HookScript("OnSizeChanged", function(self)
        if Position.on then
            syncSize(self)
        end
    end)
    local manager = _G.EditModeManagerFrame
    if manager and manager.ExitEditMode then
        hooksecurefunc(manager, "ExitEditMode", function()
            if Position.on then
                Position:Schedule()
            end
        end)
    end
end

-- Where the tracker is now, as an offset of its top right corner from the screen's: the default
-- position, so turning the option on moves nothing.
local function currentOffset(tracker)
    local right, top = plain(tracker:GetRight()), plain(tracker:GetTop())
    if not (right and top) then
        return -60, -200
    end
    local ratio = tracker:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return right * ratio - UIParent:GetRight(), top * ratio - UIParent:GetTop()
end

local function start(tracker)
    if Position.on then
        Position:Follow()
        return
    end
    if not Position.holder then
        Position.holder = CreateFrame("Frame", nil, UIParent)
    end
    local x, y = currentOffset(tracker)
    remember(tracker)
    Position.on = true
    hook(tracker)
    syncSize(tracker)
    Position.holder:Show()
    E.Mover.Register({
        key = KEY,
        owner = addonName,
        label = L.MOVER,
        frame = Position.holder,
        point = "TOPRIGHT",
        x = x,
        y = y,
        -- Its size is the module's Scale option.
        scalable = false,
        openOptions = function()
            E:OpenOptions(addonName)
        end,
    })
    Position:Follow()
end

--- Gives the tracker back the points Blizzard last gave it.
function Position:Stop()
    if not self.on then
        return
    end
    self.on = false
    E.Mover.Unregister(KEY)
    if self.holder then
        self.holder:Hide()
    end
    local tracker = Core.Tracker()
    local points = self.points
    if not (tracker and points) then
        return
    end
    E.Combat.Run(self, function()
        self.busy = true
        tracker:ClearAllPoints()
        for _, point in ipairs(points) do
            tracker:SetPoint(unpack(point))
        end
        self.busy = false
    end)
end

--- In the Mover or not, from the option.
---@param tracker table
function Position:Apply(tracker)
    if Core.running and opt("position.mover") then
        start(tracker)
        syncSize(tracker)
    else
        self:Stop()
    end
end
