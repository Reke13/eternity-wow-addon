-- EternityUI_UnitFrames: frames for you, your pet, target, target of target, focus, group and raid.
-- Each one has its own size, bars, texts, auras and icons (Elements.lua), is placed with the Mover
-- and can hide Blizzard's (Blizzard.lua). Single frames are secure unit buttons (Frame.lua); the
-- group and the raid are secure group headers (Groups.lua).
-- Options page: "General" with the frame picked on top ("General" there holds the look and the
-- colors of all of them).
-- Everything protected (sizes, places, shown or not, header attributes) changes only out of
-- combat: a change made in combat waits for the end of it.

---@type string, EternityUIUnitFramesNamespace
local addonName, ns = ...
local E = EternityUI
local Theme = E.Theme
local L, Style, Frame, Groups, Blizzard = ns.L, ns.Style, ns.Frame, ns.Groups, ns.Blizzard
local Filters, FiltersTab = ns.Filters, ns.FiltersTab
local U = Style.U

local SECTIONS = { "", "Bars", "Text", "Auras", "Buffs", "Debuffs", "Indicators" }

local VIEWS = { { id = "general", text = L.GENERAL, sections = { { group = "look" }, { group = "colors" } } } }
for _, def in ipairs(ns.UNITS) do
    local sections = {}
    for _, section in ipairs(SECTIONS) do
        sections[#sections + 1] = { group = def.key .. section }
    end
    VIEWS[#VIEWS + 1] = { id = def.key, text = def.label, sections = sections }
end

---@class EternityUIUnitFramesModule: EternityUIModuleDefinition
---@field holders table<string, table>
---@field running boolean?
---@field moverOpen boolean?
local Module = {
    schema = ns.OptionsSchema,
    tabs = {
        {
            key = "frames",
            text = L.GENERAL,
            views = VIEWS,
            picker = "top",
            -- "Show preview" over the picker; the window follows the frame picked.
            preview = ns.Preview.Strip,
            onPick = function(id)
                ns.Preview.Pick(id)
            end,
        },
        { key = FiltersTab.TAB, text = L.FILTERS, build = FiltersTab.Build },
    },
    Filters = Filters,
    FiltersTab = FiltersTab,
    Preview = ns.Preview,
    holders = {},
    Frame = Frame,
    Groups = Groups,
    Blizzard = Blizzard,
    Style = Style,
    Elements = ns.Elements,
    AuraBox = ns.AuraBox,
}

local function moverKey(def)
    return addonName .. "." .. def.key
end

local function enabled(self, def)
    return self.running and U(def.key, "", "enabled") and true or false
end

-- Builds the holders the first time.
function Module:Build()
    if self.built then
        return
    end
    self.built = true
    for _, def in ipairs(ns.UNITS) do
        self.holders[def.key] = def.group and Groups.New(def) or Frame.NewSingle(def)
    end
end

--- Applies the options to every frame. Out of combat only: in combat it waits.
-- One frame: shown or not, size, inside, Blizzard's own and its Mover element.
function Module:ApplyFrame(def)
    local holder = self.holders[def.key]
    local on = enabled(self, def)
    if def.group then
        Groups.Apply(holder, on)
    else
        Frame.ApplySingle(holder, on)
        Frame.Preview(holder, self.moverOpen and on, on)
    end
    Blizzard.Apply(def.key, on and U(def.key, "", "hideBlizzard"))
    if on then
        E.Mover.Register({
            key = moverKey(def),
            owner = addonName,
            label = L.MOVER:format(def.label),
            frame = holder,
            point = "CENTER",
            x = def.x,
            y = def.y,
            openOptions = function()
                E:OpenOptions(addonName)
            end,
        })
    else
        E.Mover.Unregister(moverKey(def))
    end
end

--- Applies the options to every frame, or only to one (its key). Out of combat only: in
--- combat it waits, and then does them all.
---@param only string? a frame's key
function Module:ApplyAll(only)
    if InCombatLockdown() then
        if not self.pending then
            self.pending = true
            print(L.COMBAT_WAIT)
        end
        return
    end
    if only and self.built and not self.pending then
        self:ApplyFrame(ns.ByKey[only])
        return
    end
    self.pending = false
    self:Build()
    for _, def in ipairs(ns.UNITS) do
        self:ApplyFrame(def)
    end
end

--- The aura filters of the frames given (all without keys) again, after a filter changed:
--- nothing protected, also in combat.
---@param keys table<string, boolean>?
function Module:RefreshAuras(keys)
    for _, f in ipairs(Frame.all) do
        if f.uf and f.auraContainer and (not keys or keys[f.uf.key]) then
            ns.AuraBox.ApplyFilters(f)
        end
    end
end

function Module:OnEnable()
    self.running = true
    Filters.onChange = function(keys)
        self:RefreshAuras(keys)
    end
    Filters.ResumeSearches()
    Frame.Listen(true)
    E.Events.On("PLAYER_REGEN_ENABLED", self, function()
        if self.pending then
            self:ApplyAll()
        end
    end)
    E.Events.Listen(E.Mover.TOGGLED, self, function(_, open)
        self.moverOpen = open and true or false
        self:ApplyAll()
    end)
    E.Events.Listen(Theme.CHANGED, self, function()
        self:ApplyAll()
    end)
    -- Your power bar follows the Resources module being switched on or off.
    E.Events.Listen(E.CONFIG_CHANGED, self, function(_, module, path)
        if module == "EternityUI_Resources" and path == "@enabled" then
            self:ApplyAll("player")
        end
    end)
    self:ApplyAll()
end

function Module:OnDisable()
    self.running = false
    Filters.onChange = nil
    self.moverOpen = false
    self:ApplyAll()
    Frame.Listen(false)
    Blizzard.RestoreAll()
end

--- The frame an option belongs to ("partyBuffs.max" is the group's), or nil for the shared
--- ones (look, colors) and a reset (no path).
---@param path string?
---@return string?
function Module.FrameOf(path)
    local group = type(path) == "string" and path:match("^([^.]+)%.") or nil
    if not group then
        return nil
    end
    local best
    for key in pairs(ns.ByKey) do
        if group:sub(1, #key) == key and (not best or #key > #best) then
            best = key
        end
    end
    return best
end

function Module:OnConfigChanged(path)
    if self.running then
        -- Only the frame whose option changed: the others stay as they are.
        self:ApplyAll(Module.FrameOf(path))
    end
end

E:RegisterModule(addonName, Module)
