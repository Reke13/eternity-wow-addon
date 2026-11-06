-- EternityUI_Objectives: Blizzard's quest and objective tracker restyled with the Eternity look.
-- The tracker stays Blizzard's: it builds, lays out, collapses and positions everything (its
-- position, height and text size are a system of Blizzard's Edit Mode, and moving it from an
-- addon can make Blizzard's managed right column lay out protected frames with taint). Skin
-- repaints it, Fade fades it, Feedback adds the completion flash and sounds, Sections hides
-- sections on demand, Position puts it in the Mover when its option is on (that risk accepted).
-- Disabling the module gives everything back without /reload.

---@type string, EternityUIObjectivesNamespace
local addonName, ns = ...
local E = EternityUI
local W = ns.Ui.W
local Core, Skin, Fade, Feedback, Sections, Position = ns.Core, ns.Skin, ns.Fade, ns.Feedback, ns.Sections, ns.Position

---@class EternityUIObjectivesModule: EternityUIModuleDefinition
---@field events table?
---@field themeWatcher table?
local Module = { schema = ns.OptionsSchema }
-- Internals reachable from the tests.
Module.Core, Module.Skin, Module.Fade, Module.Feedback, Module.Sections = Core, Skin, Fade, Feedback, Sections

--- Applies everything to the tracker, if Blizzard has made it already.
function Module:Apply()
    local tracker = Core.Tracker()
    if not tracker then
        return
    end
    Skin:Apply(tracker)
    Fade:Enable(tracker)
    Sections:Apply(tracker)
    Position:Apply(tracker)
end

function Module:Install()
    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", function(_, event, name)
        if event == "PLAYER_REGEN_ENABLED" then
            -- A scale change (or giving it back after disabling) waited for the end of combat.
            local tracker = Core.Tracker()
            if tracker and Skin.pendingScale then
                Skin:ApplyScale(tracker)
            end
        elseif Core.running and (event ~= "ADDON_LOADED" or name == "Blizzard_ObjectiveTracker") then
            self:Apply()
        end
    end)
    -- A theme change repaints the tracker. Kept in the module: the theme only holds weak references.
    self.themeWatcher = W.Themed({}, function()
        local tracker = Core.Tracker()
        if Core.running and tracker then
            Skin:Apply(tracker)
        end
    end)
end

function Module:OnEnable()
    Core.running = true
    if not self.events then
        self:Install()
    end
    -- The tracker is set up on PLAYER_ENTERING_WORLD; ADDON_LOADED covers a late Blizzard addon.
    for _, event in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }) do
        self.events:RegisterEvent(event)
    end
    self:Apply()
    Feedback:Enable()
end

function Module:OnDisable()
    Core.running = false
    if self.events then
        self.events:UnregisterAllEvents()
        -- The scale comes back at the end of combat if it's on now.
        self.events:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    Feedback:Disable()
    Fade:Disable()
    Position:Stop()
    local tracker = Core.Tracker()
    Skin:Restore(tracker)
    if tracker then
        Sections:Apply(tracker)
    end
end

function Module:OnConfigChanged(path)
    local tracker = Core.Tracker()
    if not Core.running or not tracker then
        return
    end
    -- path nil = reset or profile change: anything may have changed.
    if path == nil or path:find("^fade%.") then
        Fade:Update(path == nil)
    end
    if path == nil or path:find("^sections%.") then
        Sections:Apply(tracker)
    end
    if path == nil or path:find("^position%.") or path:find("^size%.") then
        Position:Apply(tracker)
    end
    if
        path == nil
        or path:find("^look%.")
        or path:find("^colors%.")
        or path:find("^info%.")
        or path:find("^size%.")
    then
        Skin:Apply(tracker)
    end
end

E:RegisterModule(addonName, Module)
