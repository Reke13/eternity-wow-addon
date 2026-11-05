-- EternityUI_Objectives feedback: a flash and a sound when an objective is done, a sound and an
-- optional chat line when a quest becomes ready to turn in, and the quest's zone and level in the
-- tooltip of its title.
-- Objective done: Blizzard sets the line's state to Completing (and plays its own check); a
-- hooksecurefunc on each line instance's SetState reacts to it. The flash is a frame of ours on
-- the line. Ready quests: the quest log is scanned (coalesced) on QUEST_LOG_UPDATE; the first scan
-- after enabling only learns the state, so nothing plays on login or /reload.

---@type string, EternityUIObjectivesNamespace
local _, ns = ...
local W = ns.Ui.W
local Core, L = ns.Core, ns.L
local opt = Core.Opt

local function weak()
    return setmetatable({}, { __mode = "k" })
end

---@class EternityUIObjectivesFeedback
---@field hooked table<table, boolean> lines whose SetState is hooked
---@field flashes table<table, table> line or block -> our flash frame
---@field ready table<number, boolean>? questID -> ready to turn in (nil until the first scan)
---@field seen table<number, boolean>? questIDs in the log at the last scan
---@field events table?
---@field scanQueued boolean?
local Feedback = { hooked = weak(), flashes = weak() }
ns.Feedback = Feedback

-- Flash ----------------------------------------------------------------------------------------------

function Feedback:Flash(frame)
    local flash = self.flashes[frame]
    if not flash then
        flash = CreateFrame("Frame", nil, frame)
        flash:SetAllPoints()
        flash:SetFrameLevel(frame:GetFrameLevel() + 5)
        flash.texture = flash:CreateTexture(nil, "OVERLAY")
        flash.texture:SetAllPoints()
        flash.texture:SetBlendMode("ADD")
        flash.anim = flash:CreateAnimationGroup()
        local fadeIn = flash.anim:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0)
        fadeIn:SetToAlpha(0.55)
        fadeIn:SetDuration(0.15)
        fadeIn:SetOrder(1)
        local fadeOut = flash.anim:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(0.55)
        fadeOut:SetToAlpha(0)
        fadeOut:SetDuration(0.7)
        fadeOut:SetOrder(2)
        flash.anim:SetScript("OnFinished", function()
            flash:Hide()
        end)
        self.flashes[frame] = flash
    end
    local r, g, b = Core.Color("colors.flash")
    -- Strong on the left, fading to the right.
    flash.texture:SetColorTexture(1, 1, 1, 1)
    flash.texture:SetGradient("HORIZONTAL", CreateColor(r, g, b, 1), CreateColor(r, g, b, 0))
    flash:SetAlpha(0)
    flash:Show()
    flash.anim:Stop()
    flash.anim:Play()
end

-- Objective done ---------------------------------------------------------------------------------------

local function completingState()
    local states = _G.ObjectiveTrackerAnimLineState
    return states and states.Completing
end

function Feedback:OnObjectiveDone(line)
    if opt("feedback.flash") then
        self:Flash(line)
    end
    Core.PlaySound(opt("feedback.objectiveSound"))
end

function Feedback:HookLine(line)
    if self.hooked[line] or not line.SetState then
        return
    end
    self.hooked[line] = true
    hooksecurefunc(line, "SetState", function(l, state)
        if Core.running and state ~= nil and state == completingState() then
            self:OnObjectiveDone(l)
        end
    end)
end

-- Quest ready to turn in ------------------------------------------------------------------------------

local function isReady(questID)
    local api = C_QuestLog.ReadyForTurnIn or C_QuestLog.IsComplete
    local ok, ready = pcall(api, questID)
    return ok and ready == true
end

--- The block Blizzard shows for a quest (campaign or normal section), if any.
local function questBlock(questID)
    for _, name in ipairs({ "QuestObjectiveTracker", "CampaignQuestObjectiveTracker" }) do
        local section = _G[name]
        if section and section.GetExistingBlock then
            local ok, block = pcall(section.GetExistingBlock, section, questID)
            if ok and block then
                return block
            end
        end
    end
    return nil
end

function Feedback:OnQuestReady(questID)
    Core.PlaySound(opt("feedback.questSound"))
    local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
    if opt("feedback.chat") and type(title) == "string" and not Core.Secret(title) then
        Core.Print(L.READY:format(title))
    end
    local block = questBlock(questID)
    if block and opt("feedback.flash") and block:IsVisible() then
        self:Flash(block)
    end
end

--- Compares the quests ready to turn in with the last scan. Only a quest that was in the log and
--- not ready before counts: on login the log fills in after the first scan, and a quest accepted
--- already complete isn't news.
function Feedback:Scan()
    self.scanQueued = false
    if not Core.running then
        return
    end
    local ready, seen = {}, {}
    local count = C_QuestLog.GetNumQuestLogEntries()
    for index = 1, count do
        local info = C_QuestLog.GetInfo(index)
        local questID = info and not info.isHeader and info.questID
        if type(questID) == "number" and not Core.Secret(questID) then
            seen[questID] = true
            ready[questID] = isReady(questID) or nil
        end
    end
    local before, beforeSeen = self.ready, self.seen
    self.ready, self.seen = ready, seen
    if before and beforeSeen then
        for questID in pairs(ready) do
            if beforeSeen[questID] and not before[questID] then
                self:OnQuestReady(questID)
            end
        end
    end
end

function Feedback:QueueScan()
    if self.scanQueued then
        return
    end
    self.scanQueued = true
    C_Timer.After(0.2, function()
        self:Scan()
    end)
end

-- Tooltip: zone and level ---------------------------------------------------------------------------

--- The quest's log entry and the zone header it sits under.
local function questDetails(questID)
    local index = C_QuestLog.GetLogIndexForQuestID(questID)
    if not index then
        return nil, nil
    end
    local info = C_QuestLog.GetInfo(index)
    local zone
    for i = index - 1, 1, -1 do
        local entry = C_QuestLog.GetInfo(i)
        if entry and entry.isHeader then
            zone = entry.title
            break
        end
    end
    return info, zone
end

function Feedback:OnBlockEnter(block, questID, tooltipShown)
    if not Core.running or not opt("info.tooltip") or type(questID) ~= "number" or Core.Secret(questID) then
        return
    end
    local info, zone = questDetails(questID)
    if not info then
        return
    end
    local tip = GameTooltip
    if not tooltipShown then
        tip:SetOwner(block, "ANCHOR_NONE")
        tip:ClearAllPoints()
        tip:SetPoint("TOPRIGHT", block, "TOPLEFT", -4, 0)
        tip:AddLine(info.title or "", 1, 0.82, 0)
    end
    local r, g, b = W.Theme.Color("textMuted")
    local level = info.difficultyLevel or info.level
    if type(level) == "number" and level > 0 then
        tip:AddDoubleLine(L.LEVEL, tostring(level), r, g, b, 1, 1, 1)
    end
    if type(zone) == "string" and zone ~= "" then
        tip:AddDoubleLine(L.ZONE, zone, r, g, b, 1, 1, 1)
    end
    tip:Show()
end

-- Lifecycle -------------------------------------------------------------------------------------------

function Feedback:Install()
    if self.events then
        return
    end
    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", function(_, _, unit)
        if unit == nil or unit == "player" then
            self:QueueScan()
        end
    end)
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("OnQuestBlockHeader.OnEnter", function(_, block, questID, tooltipShown)
            self:OnBlockEnter(block, questID, tooltipShown)
        end, self)
    end
end

function Feedback:Enable()
    self:Install()
    self.ready = nil
    self.seen = nil
    for _, event in ipairs({ "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "QUEST_TURNED_IN" }) do
        pcall(self.events.RegisterEvent, self.events, event)
    end
    self:Scan()
end

function Feedback:Disable()
    if self.events then
        self.events:UnregisterAllEvents()
    end
    self.ready = nil
    self.seen = nil
    for _, flash in pairs(self.flashes) do
        flash.anim:Stop()
        flash:Hide()
    end
end
