-- Performance readings for the "Performance" tab: FPS of the last minute, how much of each frame
-- the addons take (Blizzard's addon profiler, C_AddOnProfiler), memory, network, the graphics
-- settings that weigh most and a log of this session's FPS drops with what was happening.
-- Only reads: nothing here changes a setting. Memory is read at most every 15 s and never in
-- combat, as Blizzard's addon list does (UpdateAddOnMemoryUsage is expensive).

---@type string, EternityUIInfoBarNamespace
local _, ns = ...

local HISTORY = 60 -- seconds of FPS kept
local DROP_SECONDS = 3 -- this long below the threshold is a drop
local DROPS_KEPT = 20
local MEMORY_EVERY = 15
local ADDONS_HEAVY = 0.25 -- share of the frame from which addons are the cause

---@class EternityUIInfoBarDrop
---@field time number time() when it started
---@field seconds integer
---@field min integer lowest FPS
---@field context table what was happening at the lowest FPS (see Perf.Context)

---@class EternityUIInfoBarPerf
---@field history integer[] FPS once per second, oldest first
---@field drops EternityUIInfoBarDrop[] newest first
---@field current EternityUIInfoBarDrop? the drop going on now
local Perf = {
    history = {},
    drops = {},
    HISTORY = HISTORY,
    DROP_SECONDS = DROP_SECONDS,
    ADDONS_HEAVY = ADDONS_HEAVY,
    SORTS = { "now", "average", "peak", "memory" },
    -- What weighs most on FPS, in the order of the game's Graphics settings.
    CVARS = {
        "graphicsQuality",
        "RenderScale",
        "graphicsViewDistance",
        "graphicsShadowQuality",
        "graphicsSSAO",
        "graphicsParticleDensity",
        "graphicsSpellDensity",
        "graphicsComputeEffects",
        "graphicsLiquidDetail",
        "graphicsEnvironmentDetail",
        "graphicsGroundClutter",
        "graphicsTextureResolution",
        "vsync",
        "maxFPS",
        "maxFPSBk",
    },
}
ns.Perf = Perf

local function secret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

-- A number from an API call, or nil if it fails or isn't a readable number.
local function number(fn, ...)
    if not fn then
        return nil
    end
    local ok, value = pcall(fn, ...)
    if ok and type(value) == "number" and not secret(value) then
        return value
    end
    return nil
end

local function metric(name)
    local enum = Enum and Enum.AddOnProfilerMetric
    return enum and enum[name]
end

--- True when the game measures the addons' CPU (C_AddOnProfiler).
---@return boolean
function Perf.HasProfiler()
    local profiler = C_AddOnProfiler
    if not (profiler and profiler.GetAddOnMetric and metric("RecentAverageTime")) then
        return false
    end
    local ok, enabled = pcall(profiler.IsEnabled)
    return ok and enabled == true
end

--- Milliseconds (or a count) of a profiler metric: for one addon, for all of them ("overall") or
--- for the whole game ("app"). nil without the profiler.
---@param scope string "app", "overall" or an addon's name
---@param name string a value of Enum.AddOnProfilerMetric ("RecentAverageTime"...)
---@return number?
function Perf.Metric(scope, name)
    if not Perf.HasProfiler() then
        return nil
    end
    local value = metric(name)
    if scope == "app" then
        return number(C_AddOnProfiler.GetApplicationMetric, value)
    elseif scope == "overall" then
        return number(C_AddOnProfiler.GetOverallMetric, value)
    end
    return number(C_AddOnProfiler.GetAddOnMetric, scope, value)
end

--- Share of the game's frame time the addons take now (0..1), with both times in ms.
---@return number? share
---@return number? addons
---@return number? app
function Perf.AddonShare()
    local app = Perf.Metric("app", "RecentAverageTime")
    local addons = Perf.Metric("overall", "RecentAverageTime")
    if not app or not addons or app <= 0 then
        return nil, addons, app
    end
    return math.min(addons / app, 1), addons, app
end

--- min, average and max of a list of numbers (nil when it's empty).
---@param list number[]
---@return number? min
---@return number? average
---@return number? max
function Perf.Summary(list)
    if #list == 0 then
        return nil
    end
    local low, high, sum = math.huge, -math.huge, 0
    for _, value in ipairs(list) do
        low, high, sum = math.min(low, value), math.max(high, value), sum + value
    end
    return low, sum / #list, high
end

--- A CVar's value as a string, or nil if the client doesn't have it.
---@param name string
---@return string?
function Perf.CVar(name)
    local get = C_CVar and C_CVar.GetCVar or GetCVar
    if not get then
        return nil
    end
    local ok, value = pcall(get, name)
    if ok and type(value) == "string" and not secret(value) then
        return value
    end
    return nil
end

--- The foreground FPS limit, or nil when there's none.
---@return number?
function Perf.Cap()
    if Perf.CVar("useMaxFPS") == "0" then
        return nil
    end
    local cap = tonumber(Perf.CVar("maxFPS") or "")
    return cap and cap > 0 and cap or nil
end

--- What's happening now that can explain low FPS.
---@return table
function Perf.Context()
    local zone = GetRealZoneText and GetRealZoneText()
    local sub = GetSubZoneText and GetSubZoneText()
    if type(zone) ~= "string" or secret(zone) then
        zone = nil
    end
    if type(sub) == "string" and not secret(sub) and sub ~= "" and sub ~= zone then
        zone = zone and (zone .. ", " .. sub) or sub
    end
    local plates = 0
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, list = pcall(C_NamePlate.GetNamePlates)
        plates = ok and type(list) == "table" and #list or 0
    end
    local share = Perf.AddonShare()
    local top, topTime
    if Perf.HasProfiler() and C_AddOnProfiler.GetTopKAddOnsForMetric then
        local ok, list = pcall(C_AddOnProfiler.GetTopKAddOnsForMetric, metric("RecentAverageTime"), 1)
        local first = ok and type(list) == "table" and list[1]
        if first and type(first.addOnName) == "string" then
            top = first.addOnName
            topTime = Perf.Metric(top, "RecentAverageTime")
        end
    end
    return {
        zone = zone,
        combat = InCombatLockdown() == true,
        plates = plates,
        group = math.max(number(GetNumGroupMembers) or 0, 1),
        share = share,
        top = top,
        topTime = topTime,
    }
end

--- Takes one FPS reading (once per second): keeps the last minute and logs drops below the
--- threshold that last DROP_SECONDS or more.
---@param fps number
---@param threshold number
function Perf.Sample(fps, threshold)
    fps = math.floor(fps + 0.5)
    local history = Perf.history
    history[#history + 1] = fps
    while #history > HISTORY do
        table.remove(history, 1)
    end
    if fps >= threshold then
        Perf.current = nil
        return
    end
    local drop = Perf.current
    if not drop then
        drop = { time = time(), seconds = 0, min = fps, context = Perf.Context() }
        Perf.current = drop
    elseif fps < drop.min then
        drop.min = fps
        drop.context = Perf.Context()
    end
    drop.seconds = drop.seconds + 1
    -- Logged once it's long enough; it keeps updating while it lasts.
    if drop.seconds == DROP_SECONDS then
        table.insert(Perf.drops, 1, drop)
        while #Perf.drops > DROPS_KEPT do
            table.remove(Perf.drops)
        end
    end
end

--- What to tell the player: a locale key and its numbers.
---@param fps number
---@param threshold number
---@return string key
---@return number ...
function Perf.Verdict(fps, threshold)
    local share = Perf.AddonShare()
    local percent = share and math.floor(share * 100 + 0.5) or 0
    local cap = Perf.Cap()
    if not share and not Perf.HasProfiler() then
        return "VERDICT_NO_PROFILER"
    elseif share and share >= ADDONS_HEAVY then
        return "VERDICT_ADDONS", percent
    elseif cap and fps >= cap - 2 and fps < threshold * 2 then
        return "VERDICT_CAPPED", cap
    elseif fps < threshold then
        return "VERDICT_GAME", percent
    end
    return "VERDICT_OK", math.floor(fps + 0.5), percent
end

local lastMemory = -math.huge

--- Asks the game for the addons' memory, at most every MEMORY_EVERY seconds and never in combat.
---@param force boolean? ignore the wait (not combat)
function Perf.UpdateMemory(force)
    if not UpdateAddOnMemoryUsage or InCombatLockdown() then
        return
    end
    local now = GetTime()
    if force or now - lastMemory >= MEMORY_EVERY then
        lastMemory = now
        pcall(UpdateAddOnMemoryUsage)
    end
end

--- The loaded addons with their numbers, sorted (largest first).
---@param sort string one of Perf.SORTS
---@return table[] { name, now, average, peak, share, memory } (ms, 0..1, KB; nil if unknown)
function Perf.AddOns(sort)
    local list = {}
    local addons = C_AddOns
    local count = addons and number(addons.GetNumAddOns) or 0
    local app = Perf.Metric("app", "RecentAverageTime")
    for i = 1, count do
        local ok, name = pcall(addons.GetAddOnInfo, i)
        local loaded = ok and type(name) == "string" and addons.IsAddOnLoaded(i)
        if loaded then
            local now = Perf.Metric(name, "RecentAverageTime")
            list[#list + 1] = {
                name = name,
                now = now,
                average = Perf.Metric(name, "SessionAverageTime"),
                peak = Perf.Metric(name, "PeakTime"),
                share = now and app and app > 0 and now / app or nil,
                memory = number(GetAddOnMemoryUsage, name),
            }
        end
    end
    table.sort(list, function(a, b)
        local x, y = a[sort] or -1, b[sort] or -1
        if x ~= y then
            return x > y
        end
        return a.name < b.name
    end)
    return list
end

--- Total memory of the addons in KB (Lua's heap).
---@return number
function Perf.TotalMemory()
    return collectgarbage("count")
end
