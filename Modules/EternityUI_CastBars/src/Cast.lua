-- Reading a unit's cast. On Forever another unit's cast and the UNIT_SPELLCAST_* payloads can be
-- secret values: they're only handed to widgets that take secrets (SetText, SetTexture,
-- SetTimerDuration, SetAlphaFromBoolean...), never compared, added or used as table keys.
-- Numbers that are needed for math (start and end times, stage sizes) are kept only when plain.

---@type string, EternityUICastBarsNamespace
local _, ns = ...

---@class EternityUICastInfo
---@field kind string "cast", "channel" or "empower"
---@field name any spell name (may be secret)
---@field icon any texture fileID (may be secret)
---@field notInterruptible any boolean (may be secret)
---@field spellID any (may be secret)
---@field tradeskill boolean
---@field startMs number? nil when secret
---@field endMs number? nil when secret (empowered: includes the hold at max)
---@field duration table? Duration object for StatusBar:SetTimerDuration (nil on clients without it)
---@field stages number? empower stages

---@class EternityUICastBarsCast
local Cast = {}
ns.Cast = Cast

--- True for a secret value (always false on clients without secrets).
function Cast.IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

--- The value when it can be used in math, nil when it's secret.
function Cast.Plain(value)
    if Cast.IsSecret(value) then
        return nil
    end
    return value
end

local function try(fn, ...)
    if not fn then
        return nil
    end
    local ok, result = pcall(fn, ...)
    if ok then
        return result
    end
    return nil
end

--- The unit's current cast, channel or empowered cast; nil when it isn't casting (or the game
--- refuses the unit to addons).
---@param unit string
---@return EternityUICastInfo?
function Cast.Read(unit)
    if UnitCastingInfo then
        local ok, name, _, icon, startMs, endMs, tradeskill, _, notInterruptible, spellID = pcall(UnitCastingInfo, unit)
        if ok and name then
            return {
                kind = "cast",
                name = name,
                icon = icon,
                startMs = Cast.Plain(startMs),
                endMs = Cast.Plain(endMs),
                tradeskill = tradeskill and true or false,
                notInterruptible = notInterruptible,
                spellID = spellID,
                duration = try(UnitCastingDuration, unit),
            }
        end
    end
    if UnitChannelInfo then
        local ok, name, _, icon, startMs, endMs, tradeskill, notInterruptible, spellID, empowered, stages =
            pcall(UnitChannelInfo, unit)
        if ok and name then
            local info = {
                kind = empowered and "empower" or "channel",
                name = name,
                icon = icon,
                startMs = Cast.Plain(startMs),
                endMs = Cast.Plain(endMs),
                tradeskill = tradeskill and true or false,
                notInterruptible = notInterruptible,
                spellID = spellID,
            }
            if empowered then
                info.stages = stages
                info.duration = try(UnitEmpoweredChannelDuration, unit, true) or try(UnitChannelDuration, unit)
                local hold = Cast.Plain(try(GetUnitEmpowerHoldAtMaxTime, unit))
                if info.endMs and hold then
                    info.endMs = info.endMs + hold
                end
            else
                info.duration = try(UnitChannelDuration, unit)
            end
            return info
        end
    end
    return nil
end

--- Where each empower stage ends, as fractions of the bar (0-1); nil if unknown or secret.
---@param unit string
---@return number[]?
function Cast.StageMarks(unit)
    local sections = try(UnitEmpoweredStagePercentages, unit, true)
    if type(sections) ~= "table" then
        return nil
    end
    local marks, total = {}, 0
    for i, section in ipairs(sections) do
        section = Cast.Plain(section)
        if type(section) ~= "number" then
            return nil
        end
        total = total + section
        -- The last section is the hold at max: no mark at the bar's end.
        if i < #sections then
            marks[#marks + 1] = math.min(total, 1)
        end
    end
    return marks
end

--- Parses "spellID=ticks, spellID=ticks" into { [spellID] = ticks }; bad entries are skipped.
---@param text string?
---@return table<number, number>
function Cast.ParseTicks(text)
    local ticks = {}
    for id, count in tostring(text or ""):gmatch("(%d+)%s*=%s*(%d+)") do
        count = tonumber(count)
        if count and count > 0 then
            ticks[tonumber(id)] = count
        end
    end
    return ticks
end

--- World latency in milliseconds (0 if unknown).
---@return number
function Cast.Latency()
    if not GetNetStats then
        return 0
    end
    local _, _, home, world = GetNetStats()
    return Cast.Plain(world) or Cast.Plain(home) or 0
end

--- A player's name from a GUID that isn't secret, for "interrupted by".
---@param guid any
---@return string?
function Cast.NameFromGUID(guid)
    guid = Cast.Plain(guid)
    if type(guid) ~= "string" or guid == "" or not GetPlayerInfoByGUID then
        return nil
    end
    local ok, _, _, _, _, _, name = pcall(GetPlayerInfoByGUID, guid)
    if ok and type(Cast.Plain(name)) == "string" and name ~= "" then
        return name
    end
    return nil
end
