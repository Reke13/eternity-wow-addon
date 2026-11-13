-- Startup metrics, off by default (account wide: EternityUIDB.startup). When on, each load of the
-- game is measured from Eternity's first file until a while after the first frame:
--   * the addons that load after Eternity: time between their ADDON_LOADED and heap growth;
--   * the core's milestones: ADDON_LOADED, PLAYER_LOGIN, modules started, PLAYER_ENTERING_WORLD,
--     loading screen gone, first frame;
--   * each Eternity module's OnEnable, and every Eternity event handler, message and
--     OnConfigChanged that runs in the window (count, total and worst time);
--   * frame times after the first frame, with the hitches (frames over HITCH_MS) and what ran in
--     them: Eternity's own work and, when the game's addon profiler is on, the addons that took
--     the most in that frame;
--   * at the end, every addon's memory and, when the game measures it, its CPU.
-- The report is kept in SavedVariables, newest first, as data and as text lines (readable in
-- WTF\Account\<account>\SavedVariables\EternityUI.lua). /et startup shows it.
--
-- Loads right after Events.lua so its ADDON_LOADED handler runs before any other Eternity code.
-- While it isn't recording, ns.probe is nil and nothing here costs anything.
---@type string, EternityUINamespace
local addonName, ns = ...
local Events = ns.Events

---@class EternityStartup
local Startup = {
    WINDOW = 20, -- seconds measured after the first frame
    HITCH_MS = 50, -- a frame longer than this is a hitch
    MAX_HITCHES = 40,
    KEEP = 3, -- reports kept
    SPAN_MS = 1, -- shorter work isn't listed in a hitch (it still counts in its total)
}
ns.Startup = Startup
EternityUI.Startup = Startup

local clock = debugprofilestop or function()
    return GetTime() * 1000
end
Startup.clock = clock

local run -- the measurement in progress, or nil

local function heap()
    return collectgarbage("count")
end

local function settings()
    local db = EternityUIDB
    if type(db) ~= "table" then
        return nil
    end
    if type(db.startup) ~= "table" then
        db.startup = { enabled = false, reports = {} }
    end
    db.startup.reports = type(db.startup.reports) == "table" and db.startup.reports or {}
    return db.startup
end

--- True when the next load will be measured.
---@return boolean
function Startup.IsEnabled()
    local saved = settings()
    return saved ~= nil and saved.enabled == true
end

--- Turns the measurement on or off. It takes effect from the next load (/reload or login).
---@param enabled boolean
function Startup.SetEnabled(enabled)
    local saved = settings()
    if saved then
        saved.enabled = enabled and true or false
    end
end

--- The saved reports, newest first.
---@return table[]
function Startup.Reports()
    local saved = settings()
    return saved and saved.reports or {}
end

--- Forgets the saved reports.
function Startup.Clear()
    local saved = settings()
    if saved then
        saved.reports = {}
    end
end

--- True while a load is being measured.
---@return boolean
function Startup.IsRecording()
    return run ~= nil
end

-- The name an event owner shows in the report: a module's name, a string, or "core".
local function ownerName(owner)
    if type(owner) == "string" then
        return owner
    elseif type(owner) == "table" and type(owner.name) == "string" then
        return owner.name
    end
    return "core"
end

--- A milestone of the load, in ms since Eternity's first file.
---@param label string
function Startup.Mark(label)
    if run then
        run.marks[#run.marks + 1] = { label = label, at = clock() - run.origin }
    end
end

local function pack(...)
    return { n = select("#", ...), ... }
end

-- Adds a measured piece of work to the totals and to the frame being measured. Work measured
-- inside other measured work (outer false) is listed, but its time already counts in the outer.
local function record(owner, label, ms, kb, outer)
    local name = ownerName(owner)
    local key = name .. "\001" .. label
    local entry = run.work[key]
    if not entry then
        entry = { owner = name, label = label, count = 0, total = 0, worst = 0, heap = 0 }
        run.work[key] = entry
    end
    entry.count = entry.count + 1
    entry.total = entry.total + ms
    if ms > entry.worst then
        entry.worst = ms
    end
    if kb then
        entry.heap = entry.heap + kb
    end
    if outer ~= false then
        run.frameWork = run.frameWork + ms
    end
    if ms >= Startup.SPAN_MS then
        local spans = run.frameSpans
        spans[#spans + 1] = { owner = name, label = label, ms = ms }
    end
end

--- Runs fn(...) and, while recording, measures it as owner's label. Modules may use it for
--- deferred work (a refresh in C_Timer.After, a skin pass) so it shows in the report. Errors
--- reach the error handler, as with events.
---@param owner any a module (its name is used) or a string
---@param label string
---@param fn function
function Startup.Measure(owner, label, fn, ...)
    if not run then
        return fn(...)
    end
    local start, kb = clock(), heap()
    run.depth = run.depth + 1
    local results = pack(pcall(fn, ...))
    run.depth = run.depth - 1
    if run then
        record(owner, label, clock() - start, heap() - kb, run.depth == 0)
    end
    if not results[1] then
        geterrorhandler()(results[2])
        return
    end
    return unpack(results, 2, results.n)
end

-- What Events and Modules call around each handler while recording.
local function probe(owner, label, ms, kb)
    if run and owner ~= Startup then
        record(owner, label, ms, kb, run.depth == 0)
    end
end

-- The game's addon profiler (C_AddOnProfiler), when this client has it and it's on.
local function profilerMetric(name)
    local enum = Enum and Enum.AddOnProfilerMetric
    local profiler = C_AddOnProfiler
    if not (enum and enum[name] and profiler and profiler.GetAddOnMetric) then
        return nil
    end
    local ok, enabled = pcall(profiler.IsEnabled)
    if not ok or enabled ~= true then
        return nil
    end
    return enum[name]
end

local function plainNumber(fn, ...)
    if not fn then
        return nil
    end
    local ok, value = pcall(fn, ...)
    if ok and type(value) == "number" and not (issecretvalue and issecretvalue(value)) then
        return value
    end
    return nil
end

-- The loaded addons' names, in load order.
local function loadedAddOns()
    local list = {}
    local addons = C_AddOns
    local count = addons and plainNumber(addons.GetNumAddOns) or 0
    for i = 1, count do
        local ok, name = pcall(addons.GetAddOnInfo, i)
        if ok and type(name) == "string" and addons.IsAddOnLoaded(i) then
            list[#list + 1] = name
        end
    end
    return list
end

-- The addons that took the most in the last frame, by the profiler's LastTime: "Name 12.3".
local function topAddOnsLastFrame()
    local metric = profilerMetric("LastTime")
    if not metric then
        return nil
    end
    local list = {}
    for _, name in ipairs(run.addonNames or {}) do
        local ms = plainNumber(C_AddOnProfiler.GetAddOnMetric, name, metric)
        if ms and ms >= Startup.SPAN_MS then
            list[#list + 1] = { name = name, ms = ms }
        end
    end
    table.sort(list, function(a, b)
        return a.ms > b.ms
    end)
    for i = #list, 4, -1 do
        list[i] = nil
    end
    return list
end

local function topSpans(spans)
    table.sort(spans, function(a, b)
        return a.ms > b.ms
    end)
    local top = {}
    for i = 1, math.min(#spans, 3) do
        top[i] = spans[i]
    end
    return top
end

local watcher = CreateFrame("Frame")

--- One frame drawn: ms is the time since the previous one. Public for the tests.
---@param now number clock() now
function Startup.OnFrame(now)
    if not run then
        return
    end
    local frames = run.frames
    if not run.firstFrame then
        run.firstFrame = now
        Startup.Mark("FIRST_FRAME")
        run.lastFrame = now
        run.frameWork, run.frameSpans = 0, {}
        return
    end
    local ms = now - run.lastFrame
    run.lastFrame = now
    frames.count = frames.count + 1
    frames.total = frames.total + ms
    if ms > frames.worst then
        frames.worst = ms
    end
    if ms > 100 then
        frames.over100 = frames.over100 + 1
    end
    if ms > Startup.HITCH_MS then
        frames.over50 = frames.over50 + 1
        if #run.hitches < Startup.MAX_HITCHES then
            run.hitches[#run.hitches + 1] = {
                at = (now - run.firstFrame) / 1000,
                ms = ms,
                eternity = run.frameWork,
                spans = topSpans(run.frameSpans),
                addons = topAddOnsLastFrame(),
            }
        end
    end
    run.frameWork, run.frameSpans = 0, {}
    if (now - run.firstFrame) / 1000 >= Startup.WINDOW then
        Startup.Finish()
    end
end

local function onUpdate()
    Startup.OnFrame(clock())
end

--- Starts measuring this load. origin: the clock when Eternity's first file ran.
---@param origin number?
function Startup.Begin(origin)
    local now = clock()
    run = {
        origin = origin or now,
        marks = {},
        addons = {},
        work = {},
        hitches = {},
        frames = { count = 0, total = 0, worst = 0, over50 = 0, over100 = 0 },
        frameWork = 0,
        frameSpans = {},
        depth = 0, -- Measure calls in progress
        lastAddOn = now,
        lastHeap = heap(),
        heapAtStart = heap(),
    }
    ns.probe = probe
    Startup.Mark("ADDON_LOADED " .. addonName)
    for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "LOADING_SCREEN_DISABLED" }) do
        Events.On(event, Startup, function(_, isLogin, isReload)
            Events.Off(event, Startup)
            if event ~= "PLAYER_LOGIN" then
                Startup.Mark(event) -- Boot marks PLAYER_LOGIN before its own work
            end
            if event == "PLAYER_ENTERING_WORLD" then
                run.kind = isLogin and "login" or (isReload and "reload" or "zone")
            elseif event == "PLAYER_LOGIN" then
                run.addonNames = loadedAddOns()
            end
        end)
    end
    watcher:SetScript("OnUpdate", onUpdate)
end

--- An addon finished loading (its files ran and its SavedVariables exist).
---@param name string
function Startup.AddOnLoaded(name)
    if not run then
        return
    end
    local now, kb = clock(), heap()
    run.addons[#run.addons + 1] = {
        name = name,
        at = now - run.origin,
        ms = now - run.lastAddOn,
        heap = kb - run.lastHeap,
    }
    run.lastAddOn, run.lastHeap = now, kb
end

-- Memory and CPU of every loaded addon, at the end of the window.
local function addonTotals()
    local canMemory = UpdateAddOnMemoryUsage and not InCombatLockdown()
    if canMemory then
        pcall(UpdateAddOnMemoryUsage)
    end
    local average, peak, slow = profilerMetric("SessionAverageTime"), profilerMetric("PeakTime"), profilerMetric("CountTimeOver50Ms")
    local scriptProfile = GetCVarBool and GetCVarBool("scriptProfile")
    if scriptProfile and UpdateAddOnCPUUsage then
        pcall(UpdateAddOnCPUUsage)
    end
    local list = {}
    for _, name in ipairs(loadedAddOns()) do
        local entry = { name = name }
        if canMemory then
            entry.memory = plainNumber(GetAddOnMemoryUsage, name)
        end
        if average then
            entry.cpuAverage = plainNumber(C_AddOnProfiler.GetAddOnMetric, name, average)
            entry.cpuPeak = plainNumber(C_AddOnProfiler.GetAddOnMetric, name, peak)
            entry.slowFrames = slow and plainNumber(C_AddOnProfiler.GetAddOnMetric, name, slow)
        elseif scriptProfile then
            entry.cpuTotal = plainNumber(GetAddOnCPUUsage, name)
        end
        list[#list + 1] = entry
    end
    table.sort(list, function(a, b)
        local x, y = a.cpuPeak or a.cpuTotal or a.memory or 0, b.cpuPeak or b.cpuTotal or b.memory or 0
        if x ~= y then
            return x > y
        end
        return a.name < b.name
    end)
    return list, average and "profiler" or (scriptProfile and "scriptProfile" or nil), canMemory
end

local function sortedWork()
    local list = {}
    for _, entry in pairs(run.work) do
        list[#list + 1] = entry
    end
    table.sort(list, function(a, b)
        if a.total ~= b.total then
            return a.total > b.total
        end
        return a.owner .. a.label < b.owner .. b.label
    end)
    return list
end

--- Ends the measurement and saves the report. Returns it (nil if nothing was recording).
---@return table?
function Startup.Finish()
    if not run then
        return nil
    end
    watcher:SetScript("OnUpdate", nil)
    Events.Release(Startup)
    ns.probe = nil
    local finished = run
    local work = sortedWork()
    run = nil
    local addons, cpu, memory = addonTotals()
    local version, build = GetBuildInfo()
    local report = {
        date = date("%Y-%m-%d %H:%M:%S"),
        version = EternityUI.version,
        build = string.format("%s.%s", tostring(version), tostring(build)),
        kind = finished.kind or "?",
        window = Startup.WINDOW,
        hitchMs = Startup.HITCH_MS,
        marks = finished.marks,
        addonsLoaded = finished.addons,
        work = work,
        hitches = finished.hitches,
        frames = finished.frames,
        addons = addons,
        cpu = cpu,
        memoryKnown = memory,
        heapGrowth = heap() - finished.heapAtStart,
    }
    report.lines = Startup.Lines(report)
    local saved = settings()
    if saved then
        table.insert(saved.reports, 1, report)
        for i = #saved.reports, Startup.KEEP + 1, -1 do
            saved.reports[i] = nil
        end
    end
    if ns.Print and ns.L then
        ns.Print(ns.L.STARTUP_READY:format(finished.frames.over50))
    end
    return report
end

local function ms(value)
    return value and string.format("%.1f", value) or "-"
end

local function kb(value)
    if not value then
        return "-"
    elseif math.abs(value) >= 1024 then
        return string.format("%.1f MB", value / 1024)
    end
    return string.format("%.0f KB", value)
end

local function pad(text, width)
    text = tostring(text)
    if #text >= width then
        return text
    end
    return text .. string.rep(" ", width - #text)
end

-- A milestone's name in the client's language; addons keep theirs ("ADDON_LOADED Name").
local function markLabel(L, label)
    local key = "STARTUP_MARK_" .. label
    local text = L[key]
    return text ~= key and text or label
end

--- The report as text lines, in the client's language.
---@param report table
---@return string[]
function Startup.Lines(report)
    local L = ns.L
    local lines = {}
    local function add(text, ...)
        lines[#lines + 1] = select("#", ...) > 0 and text:format(...) or text
    end

    add(L.STARTUP_HEADER, report.version, report.date, L["STARTUP_KIND_" .. report.kind] or report.kind, report.build)
    add("")
    add(L.STARTUP_TIMELINE)
    local previous
    for _, mark in ipairs(report.marks) do
        local delta = previous and string.format("  (+%s)", ms(mark.at - previous)) or ""
        add("  %s %10s ms%s", pad(markLabel(L, mark.label), 34), ms(mark.at), delta)
        previous = mark.at
    end

    add("")
    add(L.STARTUP_FRAMES, report.window)
    local frames = report.frames
    local average = frames.count > 0 and frames.total / frames.count or nil
    add(L.STARTUP_FRAMES_LINE, frames.count, ms(average), ms(frames.worst), report.hitchMs, frames.over50, frames.over100)

    add("")
    add(L.STARTUP_HITCHES, report.hitchMs)
    if #report.hitches == 0 then
        add(L.STARTUP_NONE)
    end
    for _, hitch in ipairs(report.hitches) do
        local parts = {}
        for _, span in ipairs(hitch.spans) do
            parts[#parts + 1] = string.format("%s/%s %s", span.owner, span.label, ms(span.ms))
        end
        local addons = {}
        for _, entry in ipairs(hitch.addons or {}) do
            addons[#addons + 1] = string.format("%s %s", entry.name, ms(entry.ms))
        end
        add(
            L.STARTUP_HITCH_LINE,
            hitch.at,
            ms(hitch.ms),
            ms(hitch.eternity),
            #parts > 0 and table.concat(parts, ", ") or "-",
            hitch.addons and (#addons > 0 and table.concat(addons, ", ") or "-") or L.STARTUP_NO_PROFILER
        )
    end

    add("")
    add(L.STARTUP_ADDONS)
    local loaded = {}
    for i, entry in ipairs(report.addonsLoaded) do
        loaded[i] = entry
    end
    table.sort(loaded, function(a, b)
        return a.ms > b.ms
    end)
    local total = 0
    for _, entry in ipairs(loaded) do
        total = total + entry.ms
        add("  %s %8s ms  %10s", pad(entry.name, 34), ms(entry.ms), kb(entry.heap))
    end
    add(L.STARTUP_ADDONS_TOTAL, #loaded, ms(total))

    add("")
    add(L.STARTUP_WORK)
    if #report.work == 0 then
        add(L.STARTUP_NONE)
    end
    for i, entry in ipairs(report.work) do
        if i > 40 then
            add(L.STARTUP_MORE, #report.work - 40)
            break
        end
        add(
            "  %s %4dx %8s ms  %s: %8s ms  %10s",
            pad(entry.owner .. " · " .. entry.label, 44),
            entry.count,
            ms(entry.total),
            L.STARTUP_WORST,
            ms(entry.worst),
            kb(entry.heap)
        )
    end

    add("")
    add(L.STARTUP_TOTALS)
    if report.cpu == "profiler" then
        add(L.STARTUP_CPU_PROFILER)
    elseif report.cpu == "scriptProfile" then
        add(L.STARTUP_CPU_SCRIPT)
    else
        add(L.STARTUP_CPU_NONE)
    end
    if not report.memoryKnown then
        add(L.STARTUP_MEMORY_COMBAT)
    end
    for _, entry in ipairs(report.addons) do
        local cpu
        if report.cpu == "profiler" then
            cpu = string.format("%s / %s ms  >50 ms: %s", ms(entry.cpuAverage), ms(entry.cpuPeak), tostring(entry.slowFrames or "-"))
        elseif report.cpu == "scriptProfile" then
            cpu = ms(entry.cpuTotal) .. " ms"
        else
            cpu = ""
        end
        add("  %s %10s  %s", pad(entry.name, 34), kb(entry.memory), cpu)
    end
    add(L.STARTUP_HEAP, kb(report.heapGrowth))
    return lines
end

--- The report as one text, to copy.
---@param report table
---@return string
function Startup.Text(report)
    return table.concat(report.lines or Startup.Lines(report), "\n")
end

-- Eternity's own ADDON_LOADED comes first: SavedVariables say whether to measure this load.
-- Later ones are the addons that load after Eternity.
Events.On("ADDON_LOADED", Startup, function(_, loaded)
    if loaded == addonName then
        EternityUIDB = EternityUIDB or {}
        if Startup.IsEnabled() then
            Startup.Begin(ns.firstFile)
        else
            Events.Off("ADDON_LOADED", Startup)
        end
    elseif run and not run.firstFrame then
        Startup.AddOnLoaded(loaded)
    elseif run then
        -- Loaded on demand while playing: shown on the timeline, next to the hitches.
        Startup.Mark("ADDON_LOADED " .. loaded)
    end
end)
