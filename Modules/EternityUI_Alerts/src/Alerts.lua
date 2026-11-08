-- EternityUI_Alerts: rules of your own that show an icon while they apply: a missing buff or weapon
-- enchant, low durability, little bag space, few of an item. It's not WeakAuras: Forever closes
-- procs, enemy data and the combat log to addons, and buffs can only be read out of combat.
-- Rules holds them, Conditions says when each may show, Checks reads the game, Display draws the
-- row and Editor is the Rules tab. Disabling the module hides the row.

---@type string, EternityUIAlertsNamespace
local addonName, ns = ...
local E = EternityUI
local Rules, Conditions, Checks, Display, Editor, L = ns.Rules, ns.Conditions, ns.Checks, ns.Display, ns.Editor, ns.L

-- Events come in bursts (a zone change alone sends dozens of UNIT_AURA).
local DELAY = 0.3
-- Enchants run out without any event.
local TICK = 30
local MOVER_DELAY = 0.2

local EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_LEVEL_UP",
    "PLAYER_DEAD",
    "PLAYER_ALIVE",
    "PLAYER_UNGHOST",
    "PLAYER_UPDATE_RESTING",
    "PLAYER_MOUNT_DISPLAY_CHANGED",
    "GROUP_ROSTER_UPDATE",
    "ZONE_CHANGED_NEW_AREA",
    "UPDATE_INVENTORY_DURABILITY",
    "BAG_UPDATE_DELAYED",
}
local UNIT_EVENTS = { "UNIT_AURA", "UNIT_INVENTORY_CHANGED", "UNIT_SPELLCAST_SUCCEEDED" }
-- In combat buff rules run on an estimate that changes with time: checked every second.
local COMBAT_TICK = 1

---@class EternityUIAlertsModule: EternityUIModuleDefinition
---@field events table? event frame (created the first time it's enabled)
---@field ticker table?
---@field running boolean?
---@field armed boolean? sounds may play: the first evaluation is silent
local Module = {
    schema = ns.OptionsSchema,
    state = {},
    tabs = { { key = "rules", text = L.TAB, build = Editor.Build } },
    actions = {
        {
            text = L.TEST,
            onClick = function()
                Display.Test()
            end,
        },
    },
}
ns.Module = Module
-- Internals reachable from the tests.
Module.Rules, Module.Conditions, Module.Checks, Module.Display, Module.Editor =
    Rules, Conditions, Checks, Display, Editor

--- Checks every rule now and redraws the row.
function Module:Evaluate()
    local context = Conditions.Context()
    local items = {}
    local sound
    for _, rule in ipairs(Rules.List()) do
        local state = self.state[rule.id] or {}
        self.state[rule.id] = state
        local firing, value, icon = false, nil, nil
        if rule.enabled then
            firing, value, icon = Checks.Run(rule)
        end
        -- nil: it can't tell now, so it stays as it was.
        if firing ~= nil then
            state.firing, state.value, state.icon = firing, value, icon
        end
        local showing = state.firing and Conditions.Passes(rule, context) or false
        if showing then
            local action, use = Checks.Action(rule)
            items[#items + 1] = {
                name = rule.name ~= "" and rule.name or L["KIND_" .. rule.kind],
                icon = state.icon or Checks.Icon(rule),
                value = state.value,
                glow = rule.glow,
                action = action,
                use = use,
            }
            if not state.showing and rule.sound ~= "none" then
                sound = sound or rule.sound
            end
        end
        state.showing = showing
    end
    Display.Set(items)
    local kit = sound and SOUNDKIT[Rules.SOUNDS[sound]]
    if kit and self.armed and E.store:Get(addonName, "display.sounds") then
        PlaySound(kit)
    end
    self.armed = true
end

--- Evaluates a moment later, once for a burst of changes.
function Module:Schedule()
    if self.scheduled then
        return
    end
    self.scheduled = true
    C_Timer.After(DELAY, function()
        self.scheduled = false
        if self.running then
            self:Evaluate()
        end
    end)
end

function Module:OnEvent(event, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, _, spellID = ...
        if not Checks.OnCast(spellID) and not Checks.AurasRestricted() then
            -- Out of combat UNIT_AURA follows anyway; not one of the rules' buffs: nothing to do.
            return
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        Display.ClearClicks()
        if not self.combatTicker then
            self.combatTicker = C_Timer.NewTicker(COMBAT_TICK, function()
                if self.running then
                    self:Evaluate()
                end
            end)
        end
    elseif event == "PLAYER_REGEN_ENABLED" and self.combatTicker then
        self.combatTicker:Cancel()
        self.combatTicker = nil
    end
    self:Schedule()
end

function Module:OnEnable()
    self.running = true
    self.armed = false
    Rules.Bind()
    Rules.onChange = function()
        self:Schedule()
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
    for _, event in ipairs(UNIT_EVENTS) do
        pcall(self.events.RegisterUnitEvent, self.events, event, "player")
    end
    Display.Start()
    -- A preview while the Mover is open. The core releases this on disable.
    E.Events.Listen(E.Mover.TOGGLED, self, function(_, open)
        Display.SetPreview("mover", open)
        -- The Mover places the row after it closes.
        if not open then
            C_Timer.After(MOVER_DELAY, Display.Draw)
        end
    end)
    self.ticker = C_Timer.NewTicker(TICK, function()
        self:Evaluate()
    end)
    self:Evaluate()
end

function Module:OnDisable()
    self.running = false
    self.state = {}
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
    if self.combatTicker then
        self.combatTicker:Cancel()
        self.combatTicker = nil
    end
    if self.events then
        self.events:UnregisterAllEvents()
    end
    Rules.onChange = nil
    Display.Stop()
end

function Module:OnConfigChanged()
    if self.running then
        Display.Draw()
    end
end

--- /etavisos: what the module believes about each buff rule now (to find out why one doesn't show).
function Module:Report()
    -- The module may be off, and then the rules were never bound.
    Rules.Bind()
    local context = Conditions.Context()
    print(
        L.DEBUG_HEADER:format(
            tostring(context.combat),
            tostring(Checks.AurasRestricted()),
            Checks.known and L.YES or L.NO
        )
    )
    local now = GetTime()
    for _, rule in ipairs(Rules.List()) do
        if rule.kind == "buff" then
            local state = self.state[rule.id] or {}
            local left = {}
            for _, entry in ipairs(Rules.Entries(rule.spells)) do
                local key = type(entry) == "string" and entry:lower() or entry
                local expires = Checks.known and Checks.known[key]
                if expires == nil then
                    left[#left + 1] = tostring(entry) .. ": -"
                elseif expires == 0 then
                    left[#left + 1] = tostring(entry) .. ": " .. L.DEBUG_FOREVER
                else
                    left[#left + 1] = tostring(entry) .. ": " .. math.floor(expires - now) .. " s"
                end
            end
            print(
                L.DEBUG_RULE:format(
                    rule.name,
                    tostring(rule.enabled),
                    L["COMBAT_" .. tostring(rule.combat)] or tostring(rule.combat),
                    tostring(state.firing),
                    tostring(state.showing),
                    table.concat(left, ", ")
                )
            )
        end
    end
end

_G.SLASH_ETERNITYALERTS1 = "/etavisos"
_G.SLASH_ETERNITYALERTS2 = "/etalerts"
SlashCmdList.ETERNITYALERTS = function()
    Module:Report()
end

E:RegisterModule(addonName, Module)
