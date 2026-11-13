-- EternityUI_UnitFrames: the unit buttons and their events.
--   * Each frame is a SecureUnitButtonTemplate button (left click targets, right click opens the
--     unit's menu), so it works in combat. Its size, place and whether it's shown are protected:
--     they change only out of combat (the module queues them). What's drawn inside isn't.
--   * One event frame serves every unit button: unit events go to the buttons showing that unit.
--     Units without events of their own (target of target), the range fade and the combat and
--     PvP icons are refreshed on a short timer.
--   * While the Mover is open the single frames show you, so they can be placed.

---@type string, EternityUIUnitFramesNamespace
local addonName, ns = ...
local L, Style, Elements = ns.L, ns.Style, ns.Elements
local U = Style.U

local POLL = 0.2

---@class EternityUIUnitFramesFrame
---@field all table[] every unit button
---@field byUnit table<string, table<table, boolean>>
local Frame = { all = {}, byUnit = {}, singles = {} }
ns.Frame = Frame

local UNIT_EVENTS = {
    UNIT_HEALTH = "health",
    UNIT_MAXHEALTH = "health",
    UNIT_HEAL_PREDICTION = "heals",
    UNIT_ABSORB_AMOUNT_CHANGED = "heals",
    UNIT_CONNECTION = "health",
    UNIT_FLAGS = "flags", -- dead, combat, PvP
    UNIT_NAME_UPDATE = "health",
    UNIT_LEVEL = "health",
    UNIT_FACTION = "indicators",
    UNIT_POWER_UPDATE = "power",
    UNIT_MAXPOWER = "power",
    UNIT_DISPLAYPOWER = "power",
    UNIT_PORTRAIT_UPDATE = "portrait",
    UNIT_MODEL_CHANGED = "portrait",
    UNIT_SPELLCAST_START = "cast",
    UNIT_SPELLCAST_DELAYED = "cast",
    UNIT_SPELLCAST_CHANNEL_START = "cast",
    UNIT_SPELLCAST_CHANNEL_UPDATE = "cast",
    UNIT_SPELLCAST_INTERRUPTIBLE = "cast",
    UNIT_SPELLCAST_NOT_INTERRUPTIBLE = "cast",
    UNIT_SPELLCAST_STOP = "stop",
    UNIT_SPELLCAST_FAILED = "stop",
    UNIT_SPELLCAST_INTERRUPTED = "stop",
    UNIT_SPELLCAST_CHANNEL_STOP = "stop",
}
local GLOBAL_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED",
    "GROUP_ROSTER_UPDATE",
    "PARTY_LEADER_CHANGED",
    "RAID_TARGET_UPDATE",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_UPDATE_RESTING",
    "READY_CHECK",
    "READY_CHECK_CONFIRM",
    "READY_CHECK_FINISHED",
    "UNIT_PET",
    "PLAYER_FLAGS_CHANGED",
    "SPELLS_CHANGED",
}

local function run(f, what)
    if not f:IsVisible() or not f.unit then
        return
    end
    if what == "health" then
        Elements.UpdateHealth(f)
    elseif what == "flags" then
        Elements.UpdateHealth(f)
        Elements.UpdateStatus(f)
    elseif what == "heals" then
        Elements.UpdateHeals(f)
    elseif what == "power" then
        Elements.UpdatePower(f)
    elseif what == "portrait" then
        Elements.UpdatePortrait(f)
    elseif what == "auras" then
        Elements.UpdateAuras(f)
    elseif what == "cast" then
        Elements.UpdateCast(f)
    elseif what == "stop" then
        Elements.StopCast(f)
    elseif what == "indicators" then
        Elements.UpdateIndicators(f)
    end
end

local function each(fn)
    for _, f in ipairs(Frame.all) do
        if f:IsVisible() and f.unit then
            fn(f)
        end
    end
end

local function eachUnit(unit, fn)
    local list = Frame.byUnit[unit]
    if list then
        for f in pairs(list) do
            if f:IsVisible() then
                fn(f)
            end
        end
    end
end

local events = CreateFrame("Frame")
Frame.events = events

events:SetScript("OnEvent", function(_, event, unit, ...)
    if not Frame.running then
        return
    end
    local what = UNIT_EVENTS[event]
    if what then
        local list = type(unit) == "string" and Frame.byUnit[unit]
        if list then
            for f in pairs(list) do
                run(f, what)
            end
        end
        return
    end
    if event == "PLAYER_TARGET_CHANGED" then
        eachUnit("target", Elements.UpdateAll)
        eachUnit("targettarget", Elements.UpdateAll)
        each(Elements.UpdateTargeted)
        each(Elements.UpdateFade)
    elseif event == "PLAYER_FOCUS_CHANGED" then
        eachUnit("focus", Elements.UpdateAll)
    elseif event == "UNIT_PET" then
        if unit == "player" then
            eachUnit("pet", Elements.UpdateAll)
        end
    elseif event == "SPELLS_CHANGED" then
        Elements.ResetRangeSpells()
    elseif event == "RAID_TARGET_UPDATE" or event == "PARTY_LEADER_CHANGED" or event == "PLAYER_FLAGS_CHANGED" then
        each(Elements.UpdateIndicators)
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_UPDATE_RESTING" then
        eachUnit("player", Elements.UpdateIndicators)
        each(Elements.UpdateStatus)
        each(Elements.UpdateFade)
    elseif event == "READY_CHECK" or event == "READY_CHECK_CONFIRM" then
        each(function(f)
            f.readyFinished = nil
            Elements.UpdateReady(f)
        end)
    elseif event == "READY_CHECK_FINISHED" then
        each(function(f)
            f.readyFinished = true
        end)
        C_Timer.After(6, function()
            each(function(f)
                f.readyFinished = nil
                f.readyIcon:Hide()
            end)
        end)
    else -- entering the world, the group changed
        each(Elements.UpdateAll)
    end
end)

-- Units without events, and range: on a timer.
local elapsed = 0
events:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < POLL or not Frame.running then
        return
    end
    elapsed = 0
    for _, f in ipairs(Frame.all) do
        if f:IsVisible() and f.unit then
            if f.uf.poll then
                Elements.UpdateAll(f)
            else
                -- Someone else behind the token, or back in view: fresh auras.
                Elements.UpdateAuras(f)
                Elements.UpdateStatus(f)
            end
            Elements.UpdateRange(f)
        end
    end
end)

--- Starts or stops listening.
function Frame.Listen(on)
    Frame.running = on
    events:UnregisterAllEvents()
    if not on then
        return
    end
    for event in pairs(UNIT_EVENTS) do
        pcall(events.RegisterEvent, events, event)
    end
    for _, event in ipairs(GLOBAL_EVENTS) do
        pcall(events.RegisterEvent, events, event)
    end
end

--- Which unit a button shows (nil: none); the event map follows.
function Frame.SetUnit(f, unit)
    if f.unit == unit then
        return
    end
    if f.unit and Frame.byUnit[f.unit] then
        Frame.byUnit[f.unit][f] = nil
    end
    f.unit = unit
    if unit then
        Frame.byUnit[unit] = Frame.byUnit[unit] or {}
        Frame.byUnit[unit][f] = true
        Elements.UpdateAll(f)
    end
end

--- Builds the inside of a unit button (once): elements and the unit's attribute.
---@param f table
---@param def EternityUIUnitFramesUnit
function Frame.Build(f, def)
    if f.uf then
        return
    end
    f.uf = def
    Elements.Create(f)
    f:HookScript("OnAttributeChanged", function(self, name, value)
        if name == "unit" and not self.previewing then
            Frame.SetUnit(self, value)
        end
    end)
    f:HookScript("OnShow", function(self)
        if Frame.running and self.unit then
            Elements.UpdateAll(self)
        end
    end)
    Frame.all[#Frame.all + 1] = f
    Frame.SetUnit(f, f:GetAttribute("unit"))
end

--- Size and inside of a button from its options (out of combat).
function Frame.Style(f)
    local key = f.uf.key
    local width, height = U(key, "", "width"), U(key, "", "height")
    -- A secure button's size is protected (a group button made in combat got it from its header).
    if not InCombatLockdown() then
        f:SetSize(width, height)
    end
    Elements.Layout(f, width, height)
    if f.unit then
        Elements.UpdateAll(f)
    end
end

-- Single frames --------------------------------------------------------------------------------

--- The button and its holder for a single unit (player, pet, target, target of target, focus).
---@param def EternityUIUnitFramesUnit
---@return table holder
function Frame.NewSingle(def)
    local holder = CreateFrame("Frame", "EternityUIUnitFrames_" .. def.key, UIParent)
    holder:SetSize(10, 10)
    holder:SetPoint("CENTER", def.x, def.y)
    local f = CreateFrame("Button", "EternityUIUnitFrames_" .. def.key .. "Button", holder, "SecureUnitButtonTemplate")
    f:SetAllPoints(holder)
    f:RegisterForClicks("AnyUp")
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "togglemenu")
    f:SetAttribute("unit", def.unit)
    f:Hide()
    holder.button = f
    Frame.Build(f, def)
    Frame.singles[def.key] = holder
    return holder
end

--- Shows or hides a single frame by its options (out of combat).
function Frame.ApplySingle(holder, enabled)
    local f, key = holder.button, holder.button.uf.key
    local width, height = U(key, "", "width"), U(key, "", "height")
    holder:SetSize(width, height)
    holder:SetScale(U(key, "", "scale"))
    Frame.Style(f)
    if f.previewing then
        return
    end
    if not enabled then
        UnregisterUnitWatch(f)
        f:Hide()
    elseif f.uf.unit == "player" then
        UnregisterUnitWatch(f)
        f:Show()
    else
        RegisterUnitWatch(f)
    end
end

--- While the Mover is open a single frame shows you, to place it (out of combat).
function Frame.Preview(holder, on, enabled)
    local f = holder.button
    if on and enabled and not f.previewing then
        f.previewing = true
        UnregisterUnitWatch(f)
        f:Show()
        Frame.SetUnit(f, "player")
    elseif not on and f.previewing then
        f.previewing = nil
        Frame.SetUnit(f, f:GetAttribute("unit"))
        Frame.ApplySingle(holder, enabled)
    end
end

Frame.L = L
