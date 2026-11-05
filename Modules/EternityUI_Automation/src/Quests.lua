-- Quest automations: accept, turn in (only with one reward or none), pick quests and the only safe
-- gossip option at NPCs, and share accepted quests with the group.

---@type string, EternityUIAutomationNamespace
local _, ns = ...
local Core, L = ns.Core, ns.L

local Quests = {}
Core.Quests = Quests

-- Gossip icons that only open a service (no quest, no cost, no teleport): vendor, trainer,
-- banker, innkeeper and flight master.
local SAFE_ICONS = {}
for path, fileID in pairs({
    ["Interface\\GossipFrame\\VendorGossipIcon"] = 132060,
    ["Interface\\GossipFrame\\TrainerGossipIcon"] = 132058,
    ["Interface\\GossipFrame\\BankerGossipIcon"] = 132050,
    ["Interface\\GossipFrame\\BinderGossipIcon"] = 132052,
    ["Interface\\GossipFrame\\TaxiGossipIcon"] = 132057,
}) do
    SAFE_ICONS[fileID] = true
    local resolved = GetFileIDFromPath and GetFileIDFromPath(path)
    if resolved then
        SAFE_ICONS[resolved] = true
    end
end

--- What to do at a quest giver: ("turnIn", quest), ("accept", quest) or nil. Takes the lists of
--- C_GossipInfo.GetActiveQuests/GetAvailableQuests. Pure, for the tests.
function Quests.Pick(active, available, accept, turnIn)
    if turnIn then
        for _, quest in ipairs(active or {}) do
            if quest.isComplete then
                return "turnIn", quest
            end
        end
    end
    if accept then
        for _, quest in ipairs(available or {}) do
            if not quest.isTrivial and not quest.isIgnored then
                return "accept", quest
            end
        end
    end
    return nil
end

--- The gossip option to pick on its own, or nil: only when it's the only one, available, with a
--- safe icon and Blizzard doesn't already pick it. Pure, for the tests.
function Quests.SafeOption(options)
    if type(options) ~= "table" or #options ~= 1 then
        return nil
    end
    local option = options[1]
    if option.selectOptionWhenOnlyOption then
        return nil
    end
    local available = Enum.GossipOptionStatus and Enum.GossipOptionStatus.Available
    if option.status ~= nil and available ~= nil and option.status ~= available then
        return nil
    end
    return SAFE_ICONS[option.icon] and option or nil
end

local function gossip()
    local accept, turnIn = Core.On("quests.autoAccept"), Core.On("quests.autoTurnIn")
    local active, available = C_GossipInfo.GetActiveQuests(), C_GossipInfo.GetAvailableQuests()
    local action, quest = Quests.Pick(active, available, accept, turnIn)
    if action == "turnIn" then
        C_GossipInfo.SelectActiveQuest(quest.questID)
    elseif action == "accept" then
        C_GossipInfo.SelectAvailableQuest(quest.questID)
    elseif
        Core.On("quests.autoGossip")
        and #(active or {}) == 0
        and #(available or {}) == 0
        and not InCombatLockdown()
    then
        local option = Quests.SafeOption(C_GossipInfo.GetOptions())
        if option then
            C_GossipInfo.SelectOptionByIndex(option.orderIndex)
        end
    end
end

-- The old greeting window (several quests, no gossip) only gives titles and flags.
local function greeting()
    if Core.On("quests.autoTurnIn") then
        for i = 1, GetNumActiveQuests() do
            local _, isComplete = GetActiveTitle(i)
            if isComplete then
                SelectActiveQuest(i)
                return
            end
        end
    end
    if Core.On("quests.autoAccept") then
        for i = 1, GetNumAvailableQuests() do
            local isTrivial = GetAvailableQuestInfo and GetAvailableQuestInfo(i)
            if not isTrivial then
                SelectAvailableQuest(i)
                return
            end
        end
    end
end

Core.Add({
    id = "questGivers",
    events = { "GOSSIP_SHOW", "QUEST_GREETING" },
    Enabled = function()
        return Core.On("quests.autoAccept") or Core.On("quests.autoTurnIn") or Core.On("quests.autoGossip")
    end,
    OnEvent = function(_, event)
        if event == "GOSSIP_SHOW" then
            gossip()
        else
            greeting()
        end
    end,
})

Core.Add({
    id = "acceptQuests",
    events = { "QUEST_DETAIL", "QUEST_ACCEPT_CONFIRM" },
    Enabled = function()
        return Core.On("quests.autoAccept")
    end,
    OnEvent = function(_, event)
        if event == "QUEST_ACCEPT_CONFIRM" then
            -- An escort quest started by a group member.
            ConfirmAcceptQuest()
            StaticPopup_Hide("QUEST_ACCEPT")
        elseif QuestGetAutoAccept() then
            CloseQuest()
        else
            AcceptQuest()
        end
    end,
})

Core.Add({
    id = "turnInQuests",
    events = { "QUEST_PROGRESS", "QUEST_COMPLETE" },
    Enabled = function()
        return Core.On("quests.autoTurnIn")
    end,
    OnEvent = function(_, event)
        if event == "QUEST_PROGRESS" then
            if IsQuestCompletable() then
                CompleteQuest()
            end
            return
        end
        local choices = GetNumQuestChoices()
        if choices <= 1 then
            GetQuestReward(choices)
        end
    end,
})

Core.Add({
    id = "shareQuests",
    events = { "QUEST_ACCEPTED" },
    Enabled = function()
        return Core.On("quests.shareQuests")
    end,
    OnEvent = function(_, _, questID)
        if not IsInGroup() or not questID or not C_QuestLog.IsPushableQuest(questID) then
            return
        end
        local index = C_QuestLog.GetLogIndexForQuestID(questID)
        if not index then
            return
        end
        C_QuestLog.SetSelectedQuest(questID)
        QuestLogPushQuest(index)
        Core.Report(L.QUEST_SHARED, C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID) or questID)
    end,
})
