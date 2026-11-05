-- EternityUI_Objectives core: helpers the other files share (options, Blizzard's tracker and its
-- sections, colors). Nothing here writes to Blizzard's frames.

---@type string, EternityUIObjectivesNamespace
local addonName, ns = ...
local E = EternityUI
local Theme = ns.Ui.Theme

---@class EternityUIObjectivesCore
---@field running boolean? between the module's OnEnable and OnDisable
local Core = {}
ns.Core = Core

-- Blizzard's tracker sections (Forever FrameXML 1.60.1.70532, ObjectiveTrackerManager:Init), in
-- their order, with the option (sections.<id>) that hides each one.
Core.SECTIONS = {
    { id = "scenario", global = "ScenarioObjectiveTracker" },
    { id = "widgets", global = "UIWidgetObjectiveTracker" },
    { id = "campaign", global = "CampaignQuestObjectiveTracker" },
    { id = "quests", global = "QuestObjectiveTracker" },
    { id = "adventure", global = "AdventureObjectiveTracker" },
    { id = "achievements", global = "AchievementObjectiveTracker" },
    { id = "monthly", global = "MonthlyActivitiesObjectiveTracker" },
    { id = "initiatives", global = "InitiativeTasksObjectiveTracker" },
    { id = "professions", global = "ProfessionsRecipeTracker" },
    { id = "bonus", global = "BonusObjectiveTracker" },
    { id = "worldQuests", global = "WorldQuestObjectiveTracker" },
}

--- An option of this module ("group.option").
function Core.Opt(path)
    return E.store:Get(addonName, path)
end

--- True for a secret value (always false on clients without secrets).
function Core.Secret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

--- Blizzard's tracker, once Blizzard_ObjectiveTracker has loaded and set it up.
function Core.Tracker()
    local tracker = _G.ObjectiveTrackerFrame
    if tracker and tracker.modules and _G.ObjectiveTrackerManager then
        return tracker
    end
    return nil
end

--- Calls fn(section, definition) for each tracker section this client has.
---@param fn fun(section: table, definition: table)
function Core.EachSection(fn)
    for _, definition in ipairs(Core.SECTIONS) do
        local section = _G[definition.global]
        if type(section) == "table" and section.Header then
            fn(section, definition)
        end
    end
end

--- Color option ("#RRGGBB[AA]" or "@token") as r, g, b, a.
function Core.Color(path)
    local color = Theme.RGBA(Core.Opt(path))
    return color[1], color[2], color[3], color[4] or 1
end

--- A chat line from the module, in the theme's accent color.
function Core.Print(text)
    local r, g, b = Theme.Color("accent")
    print(("|cff%02x%02x%02xEternity:|r %s"):format(r * 255, g * 255, b * 255, text))
end

--- Plays a SOUNDKIT entry by name ("none" or an unknown name plays nothing).
function Core.PlaySound(name)
    local kit = _G.SOUNDKIT
    local id = name ~= "none" and kit and kit[name]
    if id then
        PlaySound(id)
    end
end
