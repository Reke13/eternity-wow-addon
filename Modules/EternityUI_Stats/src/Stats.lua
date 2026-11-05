-- EternityUI_Stats: a detailed stats panel next to the character window (Values.lua reads the
-- stats, Panel.lua draws them, Character.lua ties the panel to the window). Disabling the module
-- hides the panel and the button and gives Blizzard's stats pane back as it was, without /reload.

---@type string, EternityUIStatsNamespace
local addonName, ns = ...
local E = EternityUI
local Core, L = ns.Core, ns.L

---@class EternityUIStats: EternityUIModuleDefinition
local Stats = {
    schema = ns.OptionsSchema,
    Core = Core,
    Values = ns.Values,
    Panel = ns.Panel,
    Character = ns.Character,
}

function Stats:OnEnable()
    Core.running = true
    ns.Character:Enable()
end

function Stats:OnDisable()
    Core.running = false
    ns.Character:Disable()
end

function Stats:OnConfigChanged()
    if Core.running then
        ns.Character:Refresh()
    end
end

_G.SLASH_ETERNITYSTATS1 = "/etstats"
SlashCmdList.ETERNITYSTATS = function()
    if not Core.running then
        return
    end
    Core.Print(ns.Character:Toggle() and L.SHOWN or L.HIDDEN)
end

E:RegisterModule(addonName, Stats)
