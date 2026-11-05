-- EternityUI_Automation: small automations, each one with its own switch (see the feature files).
-- Only the events of the features that are on are registered; disabling the module unregisters
-- them all. Hooks can't be removed, so they check Core.Active and do nothing while off: Blizzard's
-- UI is left as it was, without /reload.

---@type string, EternityUIAutomationNamespace
local addonName, ns = ...
local E = EternityUI
local Core = ns.Core

---@class EternityUIAutomation: EternityUIModuleDefinition
---@field events table? frame that receives the events
---@field handlers table<string, EternityUIAutomationFeature[]> features per registered event
---@field running boolean? between OnEnable and OnDisable (active is still false inside OnEnable)
local Automation = {
    schema = ns.OptionsSchema,
    handlers = {},
    Core = Core,
}

local function report(err)
    geterrorhandler()(err)
end

function Automation:OnEvent(event, ...)
    local list = self.handlers[event]
    if not list or Core.Paused() then
        return
    end
    local args = { n = select("#", ...), ... }
    for _, feature in ipairs(list) do
        -- One failing feature doesn't stop the others.
        xpcall(function()
            feature:OnEvent(event, unpack(args, 1, args.n))
        end, report)
    end
end

--- Registers the events of the features that are on and installs their hooks.
function Automation:Apply()
    if not self.events then
        self.events = CreateFrame("Frame")
        self.events:SetScript("OnEvent", function(_, event, ...)
            self:OnEvent(event, ...)
        end)
    end
    self.events:UnregisterAllEvents()
    wipe(self.handlers)
    for _, feature in ipairs(Core.features) do
        local on = self.running == true and feature:Enabled() == true
        feature.on = on
        if feature.OnApply then
            xpcall(function()
                feature:OnApply(on)
            end, report)
        end
        if on and feature.OnEvent then
            for _, event in ipairs(feature.events) do
                local list = self.handlers[event]
                if not list then
                    -- An event this client doesn't have errors on RegisterEvent: skip it.
                    if pcall(self.events.RegisterEvent, self.events, event) then
                        list = {}
                        self.handlers[event] = list
                    end
                end
                if list then
                    list[#list + 1] = feature
                end
            end
        end
    end
end

--- Whether the module listens to an event right now (for the tests).
function Automation:IsListening(event)
    return self.handlers[event] ~= nil
end

function Automation:OnEnable()
    self.running = true
    Core.running = true
    self:Apply()
end

function Automation:OnDisable()
    self.running = false
    Core.running = false
    self:Apply()
end

function Automation:OnConfigChanged()
    if self.running then
        self:Apply()
    end
end

E:RegisterModule(addonName, Automation)
