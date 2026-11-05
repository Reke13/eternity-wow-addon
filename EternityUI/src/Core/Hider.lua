-- Reversible hiding of Blizzard's frames: a frame moves to a hidden parent and goes back to the
-- parent it had. Several owners may hide one frame; it returns when the last one lets go. The
-- frame's methods are never replaced (that taints) and Hide() isn't used, because Blizzard's
-- layout code shows frames again. Nothing moves in combat: the change waits for the end of it.
---@type string, EternityUINamespace
local _, ns = ...
local Combat = ns.Combat

---@class EternityHider
local Hider = {}
ns.Hider = Hider
EternityUI.Hider = Hider

local parking = CreateFrame("Frame")
parking:Hide()
Hider.parking = parking

local states = {} -- frame -> { parent, owners = { [owner] = true } }
local hooked = setmetatable({}, { __mode = "k" })

-- Brings the frame in line with its state.
local function apply(frame)
    local state = states[frame]
    if not state then
        return
    end
    if next(state.owners) then
        if frame:GetParent() ~= parking then
            state.parent = frame:GetParent()
            state.level = frame:GetFrameLevel()
            frame:SetParent(parking)
        end
    else
        states[frame] = nil
        if frame:GetParent() == parking then
            frame:SetParent(state.parent)
            if state.level then
                frame:SetFrameLevel(state.level)
            end
        end
    end
end

local function schedule(frame)
    Combat.Run(frame, function()
        apply(frame)
    end)
end

local function hook(frame)
    if hooked[frame] then
        return
    end
    hooked[frame] = true
    -- Blizzard may re-parent a hidden frame: that becomes the parent to return to.
    hooksecurefunc(frame, "SetParent", function(self, parent)
        local state = states[self]
        if state and parent ~= parking and next(state.owners) then
            state.parent = parent
            schedule(self)
        end
    end)
end

--- Hides a frame on behalf of owner. Returns false for a missing or forbidden frame.
---@param frame table?
---@param owner any
---@return boolean
function Hider.Hide(frame, owner)
    if not frame or (frame.IsForbidden and frame:IsForbidden()) then
        return false
    end
    hook(frame)
    local state = states[frame]
    if not state then
        state = { parent = frame:GetParent(), owners = {} }
        states[frame] = state
    end
    state.owners[owner] = true
    schedule(frame)
    return true
end

--- Lets go of a frame; it returns to its parent when no owner is left.
---@param frame table
---@param owner any
function Hider.Restore(frame, owner)
    local state = states[frame]
    if state then
        state.owners[owner] = nil
        schedule(frame)
    end
end

--- Lets go of every frame of owner: a module calls it when it's disabled.
---@param owner any
function Hider.RestoreAll(owner)
    for frame, state in pairs(states) do
        if state.owners[owner] then
            state.owners[owner] = nil
            schedule(frame)
        end
    end
end

--- True if the frame is being hidden, or waiting to be.
---@param frame table
---@return boolean
function Hider.IsHidden(frame)
    local state = states[frame]
    return state ~= nil and next(state.owners) ~= nil
end
