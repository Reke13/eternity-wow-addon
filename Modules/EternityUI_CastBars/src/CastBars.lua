-- EternityUI_CastBars: Quartz-style cast bars for the player, target, focus and pet, boss and arena
-- groups, a GCD bar and mirror timers (breath, fatigue, feign death), each one
-- placed with the core's Mover. Cast reads casts (secret-safe), Bar draws one cast bar and Group
-- stacks five of them; Timer is the plain bar behind Gcd and Mirror; Blizzard hides
-- Blizzard's bars. Disabling the module hides the bars and gives Blizzard's back.

---@type string, EternityUICastBarsNamespace
local addonName, ns = ...
local E = EternityUI
local Cast, Bar, Group, Gcd, Mirror, Blizzard, L = ns.Cast, ns.Bar, ns.Group, ns.Gcd, ns.Mirror, ns.Blizzard, ns.L

local UNITS = { "player", "target", "focus", "pet" }
-- Default places: the player's above the action bars, the pet's under it, target and focus higher.
local DEFINITIONS = {
    player = { name = "EternityUICastBarPlayer", label = L.PLAYER, point = "BOTTOM", x = 0, y = 210 },
    target = { name = "EternityUICastBarTarget", label = L.TARGET, point = "BOTTOM", x = 0, y = 300 },
    focus = { name = "EternityUICastBarFocus", label = L.FOCUS, point = "CENTER", x = 0, y = 140 },
    pet = { name = "EternityUICastBarPet", label = L.PET, point = "BOTTOM", x = 0, y = 180 },
}
local GROUPS = { "boss", "arena" }
local GROUP_DEFINITIONS = {
    boss = {
        name = "EternityUICastBarBoss",
        prefix = "boss",
        label = L.BOSS,
        barLabel = L.BOSS_N,
        point = "RIGHT",
        x = -260,
        y = 160,
    },
    arena = {
        name = "EternityUICastBarArena",
        prefix = "arena",
        label = L.ARENA,
        barLabel = L.ARENA_N,
        point = "RIGHT",
        x = -260,
        y = -80,
    },
}
-- Everything Blizzard.lua can hide, by "blizzard.<kind>" option.
local HIDEABLE = { "player", "target", "focus", "pet", "boss", "arena", "mirror" }

---@class EternityUICastBarsModule: EternityUIModuleDefinition
---@field bars table<string, EternityUICastBar> (created the first time it's enabled)
---@field groups table<string, EternityUICastBarGroup>
---@field gcd EternityUICastBarsGcd?
---@field mirror EternityUICastBarsMirror?
---@field events table?
---@field running boolean?
---@field editing boolean? Eternity's Edit Mode is open
-- The Bars tab: what belongs to one bar, together. Stored paths stay as they are in options.json.
local function view(id, text, sections)
    return { id = id, text = text, sections = sections }
end

local function unitView(id, text, extra)
    local sections = {
        {
            label = L.SECTION_BAR,
            paths = {
                "bars." .. id,
                "blizzard." .. id,
                "layout." .. id .. "Width",
                "layout." .. id .. "Height",
            },
        },
    }
    if extra then
        sections[2] = { group = extra }
    end
    return view(id, text, sections)
end

local VIEWS = {
    unitView("player", L.SHORT_PLAYER, "player"),
    unitView("target", L.SHORT_TARGET),
    unitView("focus", L.SHORT_FOCUS),
    unitView("pet", L.SHORT_PET),
    unitView("boss", L.SHORT_BOSS, "groups"),
    unitView("arena", L.SHORT_ARENA, "groups"),
    view("gcd", L.SHORT_GCD, {
        { label = L.SECTION_BAR, paths = { "bars.gcd", "layout.gcdWidth", "layout.gcdHeight", "colors.gcd" } },
        { group = "gcd" },
    }),
    view("mirror", L.SHORT_MIRROR, {
        {
            label = L.SECTION_BAR,
            paths = { "bars.mirror", "blizzard.mirror", "layout.mirrorWidth", "layout.mirrorHeight" },
        },
        { label = L.SECTION_COLORS, paths = { "colors.breath", "colors.fatigue", "colors.feign" } },
    }),
}

local Module = {
    schema = ns.OptionsSchema,
    bars = {},
    groups = {},
    tabs = { { key = "bars", text = L.TAB, views = VIEWS } },
}
ns.Module = Module
-- Internals reachable from the tests.
Module.Cast, Module.Bar, Module.Blizzard = Cast, Bar, Blizzard
Module.Group, Module.Gcd, Module.Mirror = Group, Gcd, Mirror

local EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED",
    "UNIT_PET",
    "PLAYER_REGEN_ENABLED",
    "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
    "ARENA_OPPONENT_UPDATE",
}

local function opt(path)
    return E.store:Get(addonName, path)
end

--- Every element with a preview (bars, groups, GCD, mirror).
local function elements(self)
    local list = {}
    for _, unit in ipairs(UNITS) do
        list[#list + 1] = self.bars[unit]
    end
    for _, kind in ipairs(GROUPS) do
        list[#list + 1] = self.groups[kind]
    end
    list[#list + 1] = self.gcd
    list[#list + 1] = self.mirror
    return list
end

function Module:Install()
    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", function(_, event, ...)
        self:OnEvent(event, ...)
    end)
    for _, unit in ipairs(UNITS) do
        self.bars[unit] = Bar.New(unit, DEFINITIONS[unit])
    end
    for _, kind in ipairs(GROUPS) do
        self.groups[kind] = Group.New(kind, GROUP_DEFINITIONS[kind])
    end
    self.gcd = Gcd.New()
    self.mirror = Mirror.New()
end

function Module:OnEvent(event, unit)
    local bars = self.bars
    if event == "PLAYER_TARGET_CHANGED" then
        bars.target:Refresh(true)
    elseif event == "PLAYER_FOCUS_CHANGED" then
        bars.focus:Refresh(true)
    elseif event == "UNIT_PET" then
        if unit == "player" then
            bars.pet:Refresh(true)
        end
    elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        if self.groups.boss.enabled then
            self.groups.boss:Refresh(true)
        end
    elseif event == "ARENA_OPPONENT_UPDATE" then
        if self.groups.arena.enabled then
            self.groups.arena:RefreshUnit(unit)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        for _, bar in pairs(bars) do
            bar:Refresh(true)
        end
        for _, group in pairs(self.groups) do
            if group.enabled then
                group:Refresh(true)
            end
        end
        -- Frames from addons Blizzard loads late get hidden too.
        Blizzard:Apply(Blizzard.units)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if Blizzard.pending then
            Blizzard:Apply(Blizzard.units)
        end
    end
end

-- Turns an element on (with its layout and preview) or off.
local function toggle(self, element, on, ...)
    if on then
        element:Enable(...)
        element:ApplyLayout(...)
        element:SetPreview(self.editing)
    else
        element:Disable()
    end
end

--- Turns each element on or off, redraws them and hides the Blizzard bars the options ask for.
function Module:Apply()
    Bar.ticks = Cast.ParseTicks(opt("player.tickList"))
    for _, unit in ipairs(UNITS) do
        toggle(self, self.bars[unit], opt("bars." .. unit))
    end
    for _, kind in ipairs(GROUPS) do
        toggle(self, self.groups[kind], opt("bars." .. kind))
    end
    -- After the player's bar: the GCD hangs from it.
    toggle(self, self.gcd, opt("bars.gcd"), self.bars.player)
    toggle(self, self.mirror, opt("bars.mirror"))
    local hide = {}
    for _, kind in ipairs(HIDEABLE) do
        hide[kind] = opt("blizzard." .. kind) or nil
    end
    Blizzard:Apply(hide)
end

function Module:OnEnable()
    self.running = true
    if not self.events then
        self:Install()
    end
    self.editing = E.MoverSession ~= nil and E.MoverSession.active or false
    for _, event in ipairs(EVENTS) do
        -- An event this client doesn't have errors on RegisterEvent: skip it.
        pcall(self.events.RegisterEvent, self.events, event)
    end
    -- Previews while the Mover is open; repaint on a theme change. The core releases both on disable.
    E.Events.Listen(E.Mover.TOGGLED, self, function(_, open)
        self.editing = open
        for _, element in ipairs(elements(self)) do
            if element.enabled then
                element:SetPreview(open)
            end
        end
    end)
    E.Events.Listen(E.Theme.CHANGED, self, function()
        self:Apply()
    end)
    self:Apply()
end

function Module:OnDisable()
    self.running = false
    if self.events then
        self.events:UnregisterAllEvents()
        -- Blizzard's bars come back at the end of combat if it's on now.
        self.events:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    for _, element in ipairs(elements(self)) do
        element:Disable()
    end
    Blizzard:Apply(nil)
end

function Module:OnConfigChanged()
    if self.running then
        self:Apply()
    end
end

E:RegisterModule(addonName, Module)
