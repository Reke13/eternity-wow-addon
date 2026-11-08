-- EternityUI_Auras: the target's debuffs and the player's own buffs, each in a frame of its own
-- placed with the Mover (Frame.lua). Both are built the same way, on Blizzard's aura container,
-- so they keep working in combat; each one has its own filters, list of spells, frame and icon
-- options, and can be switched off on its own.
-- Options page: "General" (Target / Character picked on top, then what to show, the frame and
-- the icons of that frame) and "Spells" (the list of each frame, picked the same way,
-- SpellsTab.lua). Picking a frame in one tab picks it in the other.

---@type string, EternityUIAurasNamespace
local addonName, ns = ...
local E = EternityUI
local Theme = E.Theme
local L, Filters, Spells, SpellsTab, Frame = ns.L, ns.Filters, ns.Spells, ns.SpellsTab, ns.Frame

-- "General": one view per frame, with its three groups.
local VIEWS = {}
for _, kind in ipairs(ns.KINDS) do
    VIEWS[#VIEWS + 1] = {
        id = kind.key,
        text = kind.label,
        sections = { { group = kind.key }, { group = kind.key .. "Frame" }, { group = kind.key .. "Look" } },
    }
end
local TABS = {
    { key = "frames", text = L.GENERAL, views = VIEWS, picker = "top", onPick = SpellsTab.Pick },
    { key = SpellsTab.TAB, text = L.TAB, build = SpellsTab.Build },
}

---@class EternityUIAurasModule: EternityUIModuleDefinition
---@field frames table<string, EternityUIAurasFrame>
---@field running boolean?
---@field moverOpen boolean?
local Module = {
    schema = ns.OptionsSchema,
    tabs = TABS,
    Filters = Filters,
    Spells = Spells,
    SpellsTab = SpellsTab,
    frames = {},
}

for _, kind in ipairs(ns.KINDS) do
    Module.frames[kind.key] = Frame.New(kind)
end

--- Starts or stops a frame by its "Show this frame" option.
---@param frame EternityUIAurasFrame
function Module:Sync(frame)
    local wanted = self.running and ns.opt(frame.kind.key .. ".enabled")
    if wanted and not frame.running then
        frame.moverOpen = self.moverOpen
        if not frame:Start() and not self.warned then
            self.warned = true
            print(L.NO_CONTAINER)
        end
    elseif not wanted and frame.running then
        frame:Stop()
    end
end

-- /etauras: the target's debuffs (or, with "me", the player's buffs) with their spell IDs, to
-- fill the lists.

local function secret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

function Module.PrintIDs(arg)
    local mine = type(arg) == "string" and (arg:lower():find("^%s*me") or arg:lower():find("^%s*yo")) ~= nil
    local unit, filter = mine and "player" or "target", mine and "HELPFUL" or "HARMFUL"
    if not UnitExists(unit) then
        print(L.IDS_NO_TARGET)
        return
    end
    local lines = {}
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, filter)
        if not aura then
            break
        end
        if secret(aura.spellId) or secret(aura.name) then
            print(L.IDS_SECRET)
            return
        end
        lines[#lines + 1] = L.IDS_LINE:format(aura.name, aura.spellId)
    end
    local name = UnitName(unit)
    if secret(name) then
        name = L.TARGET
    end
    if #lines == 0 then
        print(mine and L.IDS_NONE_PLAYER or L.IDS_NONE:format(name or ""))
        return
    end
    print(mine and L.IDS_TITLE_PLAYER or L.IDS_TITLE:format(name or ""))
    for _, line in ipairs(lines) do
        print(line)
    end
end

_G.SLASH_ETERNITYAURAS1 = "/etauras"
SlashCmdList.ETERNITYAURAS = Module.PrintIDs

-- Lifecycle ---------------------------------------------------------------------------------------

function Module:OnEnable()
    self.running = true
    -- A change in a list of spells reaches its container at once.
    for _, frame in pairs(self.frames) do
        frame.list.onChange = function()
            if frame.running then
                frame:ApplyFilters()
            end
            if SpellsTab.frame and SpellsTab.frame:IsVisible() then
                SpellsTab.Refresh()
            end
        end
    end
    for _, kind in ipairs(ns.KINDS) do
        self:Sync(self.frames[kind.key])
    end
    E.Events.On("PLAYER_TARGET_CHANGED", self, function()
        self.frames.target:Refresh()
    end)
    for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        E.Events.On(event, self, function()
            for _, frame in pairs(self.frames) do
                frame:UpdateVisibility()
            end
        end)
    end
    E.Events.Listen(E.Mover.TOGGLED, self, function(_, open)
        self.moverOpen = open and true or false
        for _, frame in pairs(self.frames) do
            frame.moverOpen = self.moverOpen
            frame:ShowSamples()
            frame:UpdateVisibility()
        end
    end)
    E.Events.Listen(Theme.CHANGED, self, function()
        for _, frame in pairs(self.frames) do
            if frame.running then
                frame:ApplyLayout()
            end
        end
    end)
end

function Module:OnDisable()
    self.running = false
    for _, frame in pairs(self.frames) do
        frame:Stop()
    end
end

function Module:OnConfigChanged(path)
    if not self.running then
        return
    end
    for key, frame in pairs(self.frames) do
        local mine = path == nil or path:sub(1, #key) == key
        if mine then
            self:Sync(frame)
            if frame.running then
                local group = path and path:match("^(%a+)%.") or nil
                if group == nil or group == key then
                    frame:ApplyFilters()
                end
                if group == nil or group ~= key or path == key .. ".sort" then
                    frame:ApplyLayout()
                end
                frame:UpdateVisibility()
            end
        end
    end
    if SpellsTab.frame and SpellsTab.frame:IsVisible() then
        SpellsTab.Refresh()
    end
end

E:RegisterModule(addonName, Module)
