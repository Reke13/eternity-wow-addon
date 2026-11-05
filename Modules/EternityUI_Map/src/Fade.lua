-- Fade while moving: the map goes to the options' opacity while the player moves and back when
-- it stops (or while the cursor is over it).
--
-- Blizzard has its own fade (PlayerMovementFrameFader, on with the mapFade CVar), added on every
-- WorldMapMixin:OnShow. While ours is on, the OnShow hook takes the map out of Blizzard's fader
-- with its own RemoveFrame and our ticker sets the alpha. Turning ours off doesn't put the map
-- back in Blizzard's fader (calling it from addon code would run our predicate inside it): the
-- map stays opaque and Blizzard adds it again on the next open.

---@type string, EternityUIMapNamespace
local _, ns = ...
local Core = ns.Core
local opt = Core.Opt

---@class EternityUIMapFade
---@field hooked boolean?
---@field ticker table? frame whose OnUpdate sets the map's alpha
---@field taken boolean? the map is out of Blizzard's fader and ours sets its alpha
local Fade = {}
ns.Fade = Fade

function Fade:Wanted()
    return Core.running == true and opt("fade.enabled") == true
end

--- The alpha the map should go to now.
function Fade.Target(map)
    local moving = IsPlayerMoving and IsPlayerMoving() == true
    if not moving then
        return 1
    end
    if opt("fade.mouseOver") and map:IsMouseOver() then
        return 1
    end
    return tonumber(opt("fade.opacity")) or 0.5
end

--- One step of the fade towards the target (a linear move that takes fade.duration from 0 to 1).
function Fade.Step(alpha, target, elapsed, duration)
    if duration <= 0 or math.abs(target - alpha) < 0.001 then
        return target
    end
    local delta = elapsed / duration
    if alpha < target then
        return math.min(target, alpha + delta)
    end
    return math.max(target, alpha - delta)
end

function Fade:CreateTicker(map)
    if self.ticker then
        return self.ticker
    end
    local ticker = CreateFrame("Frame")
    ticker:Hide()
    ticker:SetScript("OnUpdate", function(_, elapsed)
        local target = Fade.Target(map)
        local alpha = map:GetAlpha()
        if alpha ~= target then
            map:SetAlpha(Fade.Step(alpha, target, elapsed, tonumber(opt("fade.duration")) or 0.2))
        end
    end)
    self.ticker = ticker
    return ticker
end

--- Takes the shown map from Blizzard's fader and starts ours.
function Fade:Take(map)
    if PlayerMovementFrameFader and PlayerMovementFrameFader.RemoveFrame then
        PlayerMovementFrameFader.RemoveFrame(map)
    end
    self.taken = true
    self:CreateTicker(map):Show()
end

--- Stops ours: the map goes back to full alpha.
function Fade:Release(map)
    if self.ticker then
        self.ticker:Hide()
    end
    if self.taken then
        self.taken = false
        map:SetAlpha(1)
    end
end

function Fade:InstallHooks(map)
    if self.hooked then
        return
    end
    self.hooked = true
    -- After WorldMapMixin:OnShow, which has just added the map to Blizzard's fader.
    map:HookScript("OnShow", function()
        if self:Wanted() then
            self:Take(map)
        end
    end)
    map:HookScript("OnHide", function()
        self:Release(map)
    end)
end

--- Starts or stops the fade from the options. Safe to call again.
function Fade:Apply()
    local map = Core.Map()
    if not map then
        return
    end
    self:InstallHooks(map)
    if self:Wanted() then
        if map:IsShown() and not self.taken then
            self:Take(map)
        end
    else
        self:Release(map)
    end
end
