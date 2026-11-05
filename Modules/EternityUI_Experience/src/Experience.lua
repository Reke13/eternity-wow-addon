-- EternityUI_Experience: an experience bar with rested and quest XP, the level you'd reach by
-- turning quests in, XP per hour, time and kills to level; a configurable tooltip; and a Charts
-- tab with this session's XP, time per level and XP by source (EternityUIExperienceDB).
-- Data computes, Bar draws the bar and its tooltip, Charts is the tab. Disabling the module hides
-- the bar and gives Blizzard's status bars back.

---@type string, EternityUIExperienceNamespace
local addonName, ns = ...
local E = EternityUI
local Data, Bar, Charts, L = ns.Data, ns.Bar, ns.Charts, ns.L

---@class EternityUIExperienceModule: EternityUIModuleDefinition
---@field events table? event frame (created the first time it's enabled)
---@field ticker table?
---@field running boolean?
local Module = {
    schema = ns.OptionsSchema,
    tabs = { { key = "charts", text = L.TAB, build = Charts.Build } },
}
ns.Module = Module
-- Internals reachable from the tests.
Module.Data, Module.Bar, Module.Charts = Data, Bar, Charts

local EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_XP_UPDATE",
    "PLAYER_LEVEL_UP",
    "UPDATE_EXHAUSTION",
    "PLAYER_UPDATE_RESTING",
    "QUEST_LOG_UPDATE",
    "QUEST_TURNED_IN",
    "CHAT_MSG_COMBAT_XP_GAIN",
    "TIME_PLAYED_MSG",
    "ENABLE_XP_GAIN",
    "DISABLE_XP_GAIN",
}

--- Rescans the quest log a moment later (QUEST_LOG_UPDATE comes in bursts).
function Module:ScheduleQuests()
    if self.questsScheduled then
        return
    end
    self.questsScheduled = true
    C_Timer.After(0.5, function()
        self.questsScheduled = false
        if self.running then
            Data:ScanQuests()
            Bar:Update()
        end
    end)
end

function Module:OnEvent(event, ...)
    if event == "PLAYER_XP_UPDATE" then
        Data:OnXP()
    elseif event == "QUEST_TURNED_IN" then
        Data:Mark("quest")
        self:ScheduleQuests()
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        -- The message itself isn't read (it may be secret): only that a kill gave XP.
        Data:Mark("kill")
    elseif event == "QUEST_LOG_UPDATE" then
        self:ScheduleQuests()
        return
    elseif event == "TIME_PLAYED_MSG" then
        Data:OnPlayed(...)
    end
    Bar:Update()
end

function Module:OnEnable()
    self.running = true
    if Data.session then
        Data:Resync()
        Data:ScanQuests()
    else
        Data:Start()
    end
    if not self.events then
        self.events = CreateFrame("Frame")
        self.events:SetScript("OnEvent", function(_, event, ...)
            self:OnEvent(event, ...)
        end)
    end
    for _, event in ipairs(EVENTS) do
        -- An event this client doesn't have errors on RegisterEvent: skip it.
        pcall(self.events.RegisterEvent, self.events, event)
    end
    Bar:Start()
    self.ticker = C_Timer.NewTicker(1, function()
        Data:Tick()
        Bar:Update()
    end)
end

function Module:OnDisable()
    self.running = false
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
    if self.events then
        self.events:UnregisterAllEvents()
    end
    Data:Tick()
    Data:Resolve(true)
    Bar:Stop()
end

function Module:OnConfigChanged(path)
    if not self.running then
        return
    end
    -- path nil = reset or profile change: anything may have changed.
    if path == nil or path == "bar.hideBlizzard" then
        Bar:ApplyBlizzard(E.store:Get(addonName, "bar.hideBlizzard"))
    end
    Bar:ApplyLayout()
    if Charts.view and Charts.view:IsVisible() and (path == nil or path:find("^tracking%.")) then
        Charts.view:Refresh()
    end
end

E:RegisterModule(addonName, Module)
