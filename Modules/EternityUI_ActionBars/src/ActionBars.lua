-- EternityUI_ActionBars: your own action bars (Bartender-like). Eight action bars on LibActionButton,
-- plus bars that borrow Blizzard's frames: stance, pet, micro menu, bags, totems (shamans) and the
-- extra and zone abilities; size, grid, shape, texts, position and visibility of each bar come from
-- the options (the Bars tab picks the bar). Blizzard's bars are hidden and its key bindings point at
-- ours. Everything protected waits for the end of combat.
-- Paging picks bar 1's page, Icons swaps icons per spell, Bars builds and lays out, Sources says
-- where each borrowed bar takes its frames from, Style skins the buttons, Blizzard hides its bars
-- and binds the keys, Keybind is the hover binding mode (/etbars keys), Mover makes the bars
-- elements of the core's Mover (/etbars, /et move). Disabling the module gives Blizzard everything
-- back.

---@type string, EternityUIActionBarsNamespace
local addonName, ns = ...
local E = EternityUI
local Bars, Blizzard, Keybind, Mover, Style, L = ns.Bars, ns.Blizzard, ns.Keybind, ns.Mover, ns.Style, ns.L

local BAR_GROUPS = {}
for _, bar in ipairs(Bars.LIST) do
    BAR_GROUPS[#BAR_GROUPS + 1] = bar.id
end

---@class EternityUIActionBarsModule: EternityModuleDefinition
---@field events table? event frame (created the first time it's enabled)
---@field running boolean?
---@field scheduled boolean?
---@field warned boolean? the "after combat" notice was printed for the pending change
local Module = {
    schema = ns.OptionsSchema,
    tabs = {
        {
            key = "bars",
            text = L.TAB,
            groups = BAR_GROUPS,
            short = {
                bar1 = "1",
                bar2 = "2",
                bar3 = "3",
                bar4 = "4",
                bar5 = "5",
                bar6 = "6",
                bar7 = "7",
                bar8 = "8",
                stance = L.SHORT_STANCE,
                pet = L.SHORT_PET,
                micro = L.SHORT_MICRO,
                bags = L.SHORT_BAGS,
                totem = L.SHORT_TOTEM,
                extra = L.SHORT_EXTRA,
            },
            -- Set in Preview.lua, which loads before this file.
            preview = ns.Preview,
        },
    },
}
ns.Module = Module
Module.actions = {
    {
        text = L.KEYS_TITLE,
        onClick = function()
            Module:ToggleKeys()
        end,
    },
}
-- Internals reachable from the tests.
Module.Bars, Module.Blizzard, Module.Mover, Module.Style = Bars, Blizzard, Mover, Style
Module.Paging, Module.Icons, Module.Sources, Module.Keybind = ns.Paging, ns.Icons, ns.Sources, Keybind

local EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_ENABLED",
    "UPDATE_BINDINGS",
    "UPDATE_SHAPESHIFT_FORMS",
    "PET_BAR_UPDATE",
}

local function say(text)
    print("|cff8b5cf6Eternity Action Bars|r: " .. text)
end

--- Applies everything (or leaves it for after combat).
function Module:Apply()
    if not self.running then
        return
    end
    if Bars:Build() then
        Blizzard:Apply(true)
        Blizzard:ApplyBindings(true)
        Mover:Sync()
        self.warned = false
    elseif not self.warned then
        self.warned = true
        say(L.QUEUED)
    end
end

--- Applies on the next frame: option changes come in bursts (a drag saves x and y).
function Module:Schedule()
    if self.scheduled then
        return
    end
    self.scheduled = true
    C_Timer.After(0, function()
        self.scheduled = false
        self:Apply()
    end)
end

function Module:OnEvent(event)
    if event == "PLAYER_REGEN_ENABLED" then
        if Bars.pending then
            if self.running then
                self:Apply()
            else
                self:Release()
            end
        end
    elseif event == "UPDATE_BINDINGS" then
        if self.running and not InCombatLockdown() then
            Blizzard:ApplyBindings(true)
        end
    else
        -- New forms or a new pet change which borrowed buttons are shown.
        self:Schedule()
    end
end

function Module:Install()
    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", function(_, event, ...)
        self:OnEvent(event, ...)
    end)
    _G.SLASH_ETERNITYBARS1 = "/etbars"
    SlashCmdList.ETERNITYBARS = function(input)
        self:Slash(input)
    end
    _G.SLASH_ETERNITYKEYS1 = "/kb"
    SlashCmdList.ETERNITYKEYS = function()
        self:ToggleKeys()
    end
end

--- Opens or closes the hover key binding mode.
function Module:ToggleKeys()
    if self.running then
        E.Widgets.HideTooltip()
        if E.OptionsWindow and E.OptionsWindow.frame then
            E.OptionsWindow.frame:Hide()
        end
        Keybind:Toggle()
    end
end

function Module:Slash(input)
    local command = strtrim(input or ""):lower()
    if command == "options" then
        E:OpenOptions(addonName, "bars")
    elseif command == "keys" then
        self:ToggleKeys()
    elseif command == "" then
        if self.running then
            E:ToggleMover()
        end
    else
        print(L.SLASH_HELP)
    end
end

function Module:OnEnable()
    self.running = true
    Bars.running = true
    if not self.events then
        self:Install()
    end
    for _, event in ipairs(EVENTS) do
        -- An event this client doesn't have errors on RegisterEvent: skip it.
        pcall(self.events.RegisterEvent, self.events, event)
    end
    -- The core releases these two when the module is disabled.
    E.Events.Listen(E.Mover.TOGGLED, self, function(_, open)
        Mover:OnMoverToggled(open)
    end)
    E.Events.Listen(E.Theme.CHANGED, self, function()
        self:Schedule()
    end)
    self:Apply()
end

function Module:OnDisable()
    self.running = false
    Keybind:Stop(false)
    Bars.running = false
    Bars.unlocked = false
    Mover:Sync()
    -- PLAYER_REGEN_ENABLED stays registered to finish a Stop left for after combat.
    for _, event in ipairs(EVENTS) do
        if event ~= "PLAYER_REGEN_ENABLED" then
            pcall(self.events.UnregisterEvent, self.events, event)
        end
    end
    self:Release()
end

--- Hides our bars and gives Blizzard its bars and keys back (or leaves it for after combat).
function Module:Release()
    if Bars:Stop() then
        Blizzard:ApplyBindings(false)
        Blizzard:Apply(false)
    else
        say(L.QUEUED)
    end
end

function Module:OnConfigChanged()
    self:Schedule()
end

E:RegisterModule(addonName, Module)
