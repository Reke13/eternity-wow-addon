-- EternityUI_Objectives hidden sections: a section the options hide is taken out of Blizzard's
-- tracker with its own RemoveModule and hidden; it goes back with AddModule (Blizzard sorts the
-- sections again by their uiOrder). Out of combat only: changes wait for PLAYER_REGEN_ENABLED.
--
-- The one place where the module writes Blizzard's state, and why the options warn about it: the
-- tracker's section list is then changed by addon code, so every later layout reads tainted
-- values and the quest item buttons it sets up may be blocked in combat until /reload, even after
-- the section comes back or the module is turned off. Nothing is removed while every option is
-- off (the default), so the rest of the module stays taint-free. To be measured in Forever (E155).

---@type string, EternityUIObjectivesNamespace
local _, ns = ...
local Core = ns.Core
local opt = Core.Opt

---@class EternityUIObjectivesSections
---@field removed table<table, boolean> sections the module took out
---@field pending boolean? a change waits for the end of combat
---@field events table?
local Sections = { removed = {} }
ns.Sections = Sections

local function inTracker(tracker, section)
    local ok, has = pcall(tracker.HasModule, tracker, section)
    return ok and has == true
end

--- Takes out the sections the options hide and gives back the rest (all of them when the module
--- is off).
function Sections:Apply(tracker)
    if InCombatLockdown() then
        self.pending = true
        if not self.events then
            self.events = CreateFrame("Frame")
            self.events:SetScript("OnEvent", function(frame)
                frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
                if self.pending then
                    self:Apply(tracker)
                end
            end)
        end
        self.events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    self.pending = false
    Core.EachSection(function(section, definition)
        local hide = Core.running and opt("sections." .. definition.id)
        if hide and not self.removed[section] and inTracker(tracker, section) then
            self.removed[section] = true
            tracker:RemoveModule(section)
            section:Hide()
        elseif not hide and self.removed[section] then
            self.removed[section] = nil
            tracker:AddModule(section)
        end
    end)
end

--- Whether the module took this section out (for the tests).
function Sections:IsHidden(section)
    return self.removed[section] == true
end
