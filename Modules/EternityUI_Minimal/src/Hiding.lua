-- Hides and shows frames for Minimal at once, in and out of combat:
--   * the alpha goes to 0 (SetAlpha isn't protected). A post-hook on SetAlpha keeps it there
--     while hidden: a module that fades its frame (range, auto fade) only changes the alpha the
--     frame gets back;
--   * frames that aren't protected also move to a hidden parent, so they stop taking the mouse,
--     and go back to the parent they had. Moving a frame that isn't protected is allowed in
--     combat, so this doesn't wait (the core's Hider would wait for the end of combat);
--   * protected frames (action bars, unit frames) only fade: moving them is forbidden in combat,
--     and showing them again there must work too. They still take clicks while invisible.
-- Frames another module already parks with the core's Hider are left to it. Nothing of
-- Blizzard's frames is replaced; the hooks do nothing for frames that aren't hidden.

---@type string, EternityUIMinimalNamespace
local _, ns = ...
local E = EternityUI

local Hiding = {}
ns.Hiding = Hiding

local parking = CreateFrame("Frame")
parking:Hide()
Hiding.parking = parking

local saved = {} -- frame -> { alpha = to give back, parent = when moved }
local hooked = setmetatable({}, { __mode = "k" })
local busy = false

local function zero(frame)
    busy = true
    frame:SetAlpha(0)
    busy = false
end

local function hook(frame)
    if hooked[frame] then
        return
    end
    hooked[frame] = true
    hooksecurefunc(frame, "SetAlpha", function(self, alpha)
        local state = saved[self]
        if busy or not state then
            return
        end
        if type(alpha) == "number" and not E.Secret.Is(alpha) then
            state.alpha = alpha
        end
        zero(self)
    end)
    if frame.SetAlphaFromBoolean then
        hooksecurefunc(frame, "SetAlphaFromBoolean", function(self)
            if not busy and saved[self] then
                zero(self)
            end
        end)
    end
    -- Blizzard may give the frame a new parent while it's parked: that's the one to go back to,
    -- and the frame goes back to the parking.
    hooksecurefunc(frame, "SetParent", function(self, parent)
        local state = saved[self]
        if busy or not state or not state.parent or parent == parking then
            return
        end
        state.parent = parent
        busy = true
        self:SetParent(parking)
        busy = false
    end)
end

local function movable(frame)
    if frame.IsProtected and frame:IsProtected() then
        return false
    end
    return not E.Hider.IsHidden(frame)
end

--- Hides a frame. fadeOnly keeps it where it is (only its alpha changes): for frames whose
--- children must keep working, like a chat window and its edit box.
---@param frame table
---@param fadeOnly boolean?
function Hiding.Hide(frame, fadeOnly)
    if saved[frame] or (frame.IsForbidden and frame:IsForbidden()) then
        return
    end
    local alpha = frame:GetAlpha()
    local state = { alpha = (type(alpha) == "number" and not E.Secret.Is(alpha)) and alpha or 1 }
    saved[frame] = state
    hook(frame)
    zero(frame)
    if not fadeOnly and movable(frame) and frame:GetParent() ~= parking then
        state.parent = frame:GetParent()
        busy = true
        frame:SetParent(parking)
        busy = false
    end
end

--- Shows a frame hidden by Hide again, with the alpha and parent it had.
---@param frame table
function Hiding.Show(frame)
    local state = saved[frame]
    if not state then
        return
    end
    saved[frame] = nil
    busy = true
    if state.parent and frame:GetParent() == parking then
        frame:SetParent(state.parent)
    end
    frame:SetAlpha(state.alpha)
    busy = false
end

--- The frames hidden now.
---@return table[]
function Hiding.Frames()
    local frames = {}
    for frame in pairs(saved) do
        frames[#frames + 1] = frame
    end
    return frames
end

--- Shows every hidden frame.
function Hiding.ShowAll()
    for _, frame in ipairs(Hiding.Frames()) do
        Hiding.Show(frame)
    end
end

--- True while the frame is hidden by Minimal.
---@param frame table
---@return boolean
function Hiding.IsHidden(frame)
    return saved[frame] ~= nil
end
