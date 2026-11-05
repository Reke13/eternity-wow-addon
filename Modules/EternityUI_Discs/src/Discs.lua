-- EternityUI_Discs: radial discs of spells, items, toys and macros, nested at will and opened with
-- a key. Store (EternityUIDiscsDB) keeps the discs, Resolve turns them into actions on this
-- character, Ring draws them securely and Editor is the Discs tab of the options page.
-- Disabling the module closes the discs and frees their keys (in combat, when the fight ends).

---@type string, EternityUIDiscsNamespace
local addonName, ns = ...
local E = EternityUI
local Store, Ring, Editor, L = ns.Store, ns.Ring, ns.Editor, ns.L

local DELAY = 0.5

---@class EternityUIDiscsModule: EternityUIModuleDefinition
---@field installed boolean? the listeners and the slash command exist
---@field running boolean?
---@field scheduled boolean? a build is on its way
local Module = {
    schema = ns.OptionsSchema,
    tabs = { { key = "discs", text = L.TAB, build = Editor.Build } },
}
ns.Module = Module
-- Internals reachable from the tests.
Module.Store, Module.Ring, Module.Resolve = Store, Ring, ns.Resolve

-- What changes the resolved discs: professions, spells, bags, toys and macros.
local EVENTS = {
    "SKILL_LINES_CHANGED",
    "SPELLS_CHANGED",
    "BAG_UPDATE_DELAYED",
    "TOYS_UPDATED",
    "UPDATE_MACROS",
    "NEW_TOY_ADDED",
}

--- Rebuilds the discs a moment later (several changes in a row cost one build). A rebuild closes
--- the disc, so it waits while one is open.
function Module:Schedule()
    if self.scheduled or not self.running then
        return
    end
    self.scheduled = true
    C_Timer.After(DELAY, function()
        self.scheduled = false
        if Ring:IsOpen() then
            self:Schedule()
        elseif self.running then
            Ring:Build()
        end
    end)
end

function Module:Install()
    self.installed = true
    Store:OnChange(function()
        if not self.running then
            return
        end
        if InCombatLockdown() then
            print("|cff8b5cf6Eternity Discs|r: " .. L.COMBAT)
        end
        self:Schedule()
    end)
    _G.SLASH_ETERNITYDISCS1 = "/etdiscs"
    SlashCmdList.ETERNITYDISCS = function(input)
        self:Slash(input)
    end
end

function Module:Slash(input)
    local command = strtrim(input or ""):lower()
    if command == "general" then
        Editor.selected = Store:Generate().id
        print("|cff8b5cf6Eternity Discs|r: " .. L.GENERATED)
    elseif command ~= "" then
        print(L.SLASH_HELP)
        return
    end
    E:OpenOptions(addonName, "discs")
end

function Module:OnEnable()
    self.running = true
    Store:Bind()
    if not self.installed then
        self:Install()
    end
    -- The core releases these on disable.
    local function changed()
        self:Schedule()
    end
    for _, event in ipairs(EVENTS) do
        E.Events.On(event, self, changed)
    end
    E.Events.Listen(E.Theme.CHANGED, self, changed)
    Ring:Start()
end

function Module:OnDisable()
    self.running = false
    Ring:Stop()
end

function Module:OnConfigChanged()
    self:Schedule()
end

E:RegisterModule(addonName, Module)
