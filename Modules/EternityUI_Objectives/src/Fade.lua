-- EternityUI_Objectives auto fade: in combat, boss encounters, dungeons, raids or PvP the tracker
-- fades to an opacity instead of collapsing. Blizzard's SetCollapsed runs a layout from the
-- caller's (tainted) code and would block quest items in combat; SetAlpha on these plain frames
-- is allowed at any time. With "keep the main header", the sections fade and the header stays.
-- While nearly invisible, an invisible frame of ours on top eats the clicks, so hidden quest
-- items aren't used by accident. The alpha each frame had is given back when it stops fading.

---@type string, EternityUIObjectivesNamespace
local _, ns = ...
local Core = ns.Core
local opt = Core.Opt

local HIDDEN = 0.1 -- below this opacity the blocker takes the clicks

---@class EternityUIObjectivesFade
---@field driver table? our event and OnUpdate frame
---@field blocker table? EternityUIObjectivesBlocker
---@field touched table<table, number> frame we faded -> its alpha before
---@field alpha number current opacity of the faded frames
---@field target number opacity it's going to
---@field encounter boolean? a boss encounter is on
local Fade = { touched = {}, alpha = 1, target = 1 }
ns.Fade = Fade

local EVENTS = {
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "ENCOUNTER_START",
    "ENCOUNTER_END",
    "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA",
}

--- Whether the options and the situation ask for the fade now.
function Fade:ShouldFade()
    if not Core.running then
        return false
    end
    if opt("fade.combat") and (InCombatLockdown() or UnitAffectingCombat("player")) then
        return true
    end
    if opt("fade.boss") and self.encounter then
        return true
    end
    local inInstance, kind = IsInInstance()
    if inInstance then
        if kind == "raid" then
            return opt("fade.raid") and true or false
        elseif kind == "party" or kind == "scenario" then
            return opt("fade.dungeon") and true or false
        elseif kind == "arena" or kind == "pvp" then
            return opt("fade.pvp") and true or false
        end
    end
    return false
end

--- Frames that fade: every section (the header stays) or the whole tracker.
function Fade:Targets(tracker)
    local targets = {}
    if opt("fade.keepHeader") then
        Core.EachSection(function(section)
            targets[section] = true
        end)
    else
        targets[tracker] = true
    end
    return targets
end

local function setAlpha(self, alpha)
    self.alpha = alpha
    local tracker = Core.Tracker()
    if not tracker then
        return
    end
    local targets = self:Targets(tracker)
    -- A frame that isn't a target anymore (keepHeader changed) gets its alpha back.
    for frame, original in pairs(self.touched) do
        if not targets[frame] then
            frame:SetAlpha(original)
            self.touched[frame] = nil
        end
    end
    if alpha >= 1 then
        for frame, original in pairs(self.touched) do
            frame:SetAlpha(original)
        end
        self.touched = {}
    else
        for frame in pairs(targets) do
            if self.touched[frame] == nil then
                self.touched[frame] = frame:GetAlpha()
            end
            frame:SetAlpha(self.touched[frame] * alpha)
        end
    end
    self:UpdateBlocker(tracker)
end

function Fade:UpdateBlocker(tracker)
    local block = Core.running
        and opt("fade.blockMouse")
        and self.alpha < HIDDEN
        and self.target < HIDDEN
        and tracker:IsVisible()
    if block and not self.blocker then
        -- Global name for tests and screenshots.
        self.blocker = CreateFrame("Frame", "EternityUIObjectivesBlocker", UIParent)
        self.blocker:SetFrameStrata("MEDIUM")
        self.blocker:EnableMouse(true)
        self.blocker:EnableMouseWheel(true)
        self.blocker:SetScript("OnMouseWheel", function() end)
    end
    if not self.blocker then
        return
    end
    if block then
        self.blocker:ClearAllPoints()
        if opt("fade.keepHeader") and tracker.Header then
            self.blocker:SetPoint("TOPLEFT", tracker.Header, "BOTTOMLEFT")
        else
            self.blocker:SetPoint("TOPLEFT", tracker, "TOPLEFT")
        end
        self.blocker:SetPoint("BOTTOMRIGHT", tracker, "BOTTOMRIGHT")
    end
    self.blocker:SetShown(block and true or false)
end

local function onUpdate(driver, elapsed)
    local self = Fade
    local duration = opt("fade.duration") or 0
    local alpha = self.target
    if duration > 0 then
        local step = elapsed / duration
        if self.alpha < self.target then
            alpha = math.min(self.alpha + step, self.target)
        else
            alpha = math.max(self.alpha - step, self.target)
        end
    end
    setAlpha(self, alpha)
    if alpha == self.target then
        driver:SetScript("OnUpdate", nil)
    end
end

--- Recomputes where the fade should go and starts moving there (instantly with `now`).
function Fade:Update(now)
    local wanted = self:ShouldFade() and (opt("fade.alpha") or 0) or 1
    self.target = wanted
    if not self.driver then
        return
    end
    if now or not Core.running then
        self.driver:SetScript("OnUpdate", nil)
        setAlpha(self, wanted)
    elseif self.alpha ~= wanted then
        self.driver:SetScript("OnUpdate", onUpdate)
    else
        setAlpha(self, wanted) -- same opacity, but the targets or the blocker may have changed
    end
end

function Fade:OnEvent(event)
    if event == "ENCOUNTER_START" then
        self.encounter = true
    elseif event == "ENCOUNTER_END" or event == "PLAYER_ENTERING_WORLD" then
        self.encounter = false
    end
    self:Update(event == "PLAYER_ENTERING_WORLD")
end

function Fade:Install(tracker)
    if self.driver then
        return
    end
    self.driver = CreateFrame("Frame")
    self.driver:SetScript("OnEvent", function(_, event)
        self:OnEvent(event)
    end)
    local refresh = function()
        if Core.running then
            self:UpdateBlocker(tracker)
        end
    end
    tracker:HookScript("OnShow", refresh)
    tracker:HookScript("OnHide", refresh)
end

function Fade:Enable(tracker)
    self:Install(tracker)
    for _, event in ipairs(EVENTS) do
        -- An event this client doesn't have errors on RegisterEvent: skip it.
        pcall(self.driver.RegisterEvent, self.driver, event)
    end
    self:Update(true)
end

--- Stops fading and gives every frame its alpha back (Core.running is already false).
function Fade:Disable()
    if self.driver then
        self.driver:UnregisterAllEvents()
    end
    self.encounter = false
    self:Update(true)
end
