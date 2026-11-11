-- Warnings when a listed player turns up: a line in the unit tooltip, a chat message when you
-- target one and when one is in your group. Each listed player seen this way also has their
-- faction, class, level and guild brought up to date. Nothing is read while it's secret.

---@type string, EternityUIBlacklistNamespace
local _, ns = ...
local E = EternityUI
local L, List, opt = ns.L, ns.List, ns.opt

local TARGET_COOLDOWN = 60
local PREFIX = "|cffff4040" .. "%s:|r "

---@class EternityUIBlacklistWarnings
---@field running boolean?
---@field hooked boolean?
---@field targeted table<string, number> key -> GetTime() of its last target warning
---@field grouped table<string, boolean> keys already warned about in this group
local Warnings = { targeted = {}, grouped = {} }
ns.Warnings = Warnings

local function reasonOf(entry)
    return entry.reason ~= "" and entry.reason or L.NO_REASON
end

--- Prints a warning, with a sound if the options want one.
---@param text string
function Warnings.Say(text)
    print(PREFIX:format(L.TITLE) .. text)
    if opt("warnings.sound") then
        PlaySound(SOUNDKIT.RAID_WARNING, "Master")
    end
end

--- The entry of a unit if it's a listed player, updated with what was read of it.
---@param unit any
---@return EternityUIBlacklistEntry?
function Warnings.Check(unit)
    local info = List.ReadUnit(unit)
    local entry = info and List.Get(info.name)
    if entry then
        List.Update(entry, info, true)
    end
    return entry
end

function Warnings.OnTooltip(tip)
    if not Warnings.running or not opt("warnings.tooltip") then
        return
    end
    local _, unit = tip:GetUnit()
    local entry = Warnings.Check(unit)
    if entry then
        tip:AddLine(L.TOOLTIP:format(reasonOf(entry)), 1, 0.25, 0.25, true)
        tip:Show()
    end
end

function Warnings.OnTarget()
    if not opt("warnings.target") then
        return
    end
    local entry = Warnings.Check("target")
    if not entry then
        return
    end
    local key = List.Key(entry.name)
    local last = Warnings.targeted[key]
    local now = GetTime()
    if last and now - last < TARGET_COOLDOWN then
        return
    end
    Warnings.targeted[key] = now
    Warnings.Say(L.WARN_TARGET:format(entry.name, reasonOf(entry)))
end

--- The unit tokens of the other members of the group.
---@return string[]
function Warnings.GroupUnits()
    local units = {}
    local count = GetNumGroupMembers()
    if IsInRaid() then
        for i = 1, count do
            units[#units + 1] = "raid" .. i
        end
    else
        for i = 1, count - 1 do
            units[#units + 1] = "party" .. i
        end
    end
    return units
end

function Warnings.OnGroup()
    if GetNumGroupMembers() == 0 then
        Warnings.grouped = {}
        return
    end
    if not opt("warnings.group") then
        return
    end
    for _, unit in ipairs(Warnings.GroupUnits()) do
        local entry = Warnings.Check(unit)
        local key = entry and List.Key(entry.name)
        if key and not Warnings.grouped[key] then
            Warnings.grouped[key] = true
            Warnings.Say(L.WARN_GROUP:format(entry.name, reasonOf(entry)))
        end
    end
end

function Warnings.Start(owner)
    Warnings.running = true
    if not Warnings.hooked and TooltipDataProcessor and Enum.TooltipDataType then
        -- A post-call can't be removed: it does nothing while the module is off.
        Warnings.hooked = true
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, Warnings.OnTooltip)
    end
    E.Events.On("PLAYER_TARGET_CHANGED", owner, Warnings.OnTarget)
    E.Events.On("GROUP_ROSTER_UPDATE", owner, Warnings.OnGroup)
    -- Already in a group when the module starts: say who is listed there.
    Warnings.OnGroup()
end

function Warnings.Stop()
    Warnings.running = false
end
