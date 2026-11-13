-- The module's "Performance" tab in the options: a verdict on where the FPS go, the numbers of
-- now, the graphics settings that weigh most, this session's FPS drops and a table of the loaded
-- addons (CPU per frame and memory). It refreshes once per second while it's shown.

---@type string, EternityUIInfoBarNamespace
local _, ns = ...
local E = EternityUI
local Theme, Widgets = E.Theme, E.Widgets
local L, Perf, opt = ns.L, ns.Perf, ns.opt

local TAB = "performance"
local LINE = 22
local VALUE_X = 240
local ROW = 22
local GAP = 18
-- Columns of the addon table, from the right: { key, width }.
local COLUMNS = {
    { "memory", 84 },
    { "peak", 72 },
    { "average", 72 },
    { "share", 72 },
    { "now", 72 },
}
local HEADERS = {
    memory = "COL_MEMORY",
    peak = "COL_PEAK",
    average = "COL_AVERAGE",
    share = "COL_SHARE",
    now = "COL_NOW",
}
local HEAVY_SHARE = 0.10 -- an addon taking this much of the frame is shown in the alert color

---@class EternityUIInfoBarPerfTab
---@field frame table? the tab's view, once the options built it
local PerfTab = { TAB = TAB, sort = "now", rows = {} }
ns.PerfTab = PerfTab

local function ms(value)
    return value and string.format("%.2f ms", value) or L.UNKNOWN
end

local function memory(kb)
    if not kb then
        return L.UNKNOWN
    elseif kb >= 1024 then
        return string.format("%.1f MB", kb / 1024)
    end
    return string.format("%d KB", kb)
end

local function percent(share)
    return share and string.format("%d%%", math.floor(share * 100 + 0.5)) or L.UNKNOWN
end

local function alertColor()
    return Theme.RGBA(opt("alerts.color"))
end

local function paint(text, alert)
    local color = alert and alertColor() or Theme.colors.text
    text:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

--- A graphics CVar as the player reads it.
---@param name string
---@return string?
function PerfTab.CVarText(name)
    local value = Perf.CVar(name)
    if value == nil then
        return nil
    elseif name == "vsync" then
        return value == "1" and L.YES or L.NO
    elseif name == "maxFPS" or name == "maxFPSBk" then
        local use = Perf.CVar(name == "maxFPS" and "useMaxFPS" or "useMaxFPSBk")
        if use == "0" or value == "0" then
            return L.OFF
        end
        return value
    elseif name == "RenderScale" then
        local scale = tonumber(value)
        return scale and string.format("%d%%", math.floor(scale * 100 + 0.5)) or value
    end
    return value
end

--- One line of a drop: when, how long, how low and what was going on.
---@param drop EternityUIInfoBarDrop
---@return string
function PerfTab.DropText(drop)
    local c = drop.context
    local parts = {}
    if c.zone then
        parts[#parts + 1] = c.zone
    end
    if c.combat then
        parts[#parts + 1] = L.IN_COMBAT
    end
    parts[#parts + 1] = L.DROP_PLATES:format(c.plates)
    if c.group > 1 then
        parts[#parts + 1] = L.DROP_GROUP:format(c.group)
    end
    if c.share then
        parts[#parts + 1] = L.DROP_ADDONS:format(math.floor(c.share * 100 + 0.5))
    end
    if c.top and c.topTime then
        parts[#parts + 1] = L.DROP_TOP:format(c.top, c.topTime)
    end
    return L.DROP_LINE:format(date("%H:%M:%S", drop.time), drop.seconds, drop.min, table.concat(parts, " · "))
end

-- A label on the left and a value at VALUE_X.
local function keyValue(parent, label)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(LINE)
    row.label = Widgets.Text(row, 13, "muted")
    row.label:SetPoint("LEFT")
    row.label:SetText(label)
    row.value = Widgets.Text(row, 13, "text")
    row.value:SetPoint("LEFT", VALUE_X, 0)
    row.value:SetPoint("RIGHT")
    row.value:SetJustifyH("LEFT")
    row.value:SetWordWrap(false)
    return row
end

local function heading(parent, title, size)
    local text = Widgets.Text(parent, size or 16, "text")
    text:SetJustifyH("LEFT")
    text:SetText(title)
    return text
end

-- A heading with an "i" right after its text, which explains the block.
local function headingWithInfo(parent, title, text)
    local line = heading(parent, title)
    line.info = Widgets.Info(parent, title, text)
    return line
end

local function addonRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW)
    row.cells = {}
    local right = 0
    for _, column in ipairs(COLUMNS) do
        local cell = Widgets.Text(row, 13, "text")
        cell:SetPoint("RIGHT", -right, 0)
        cell:SetWidth(column[2])
        cell:SetJustifyH("RIGHT")
        cell:SetWordWrap(false)
        row.cells[column[1]] = cell
        right = right + column[2]
    end
    row.name = Widgets.Text(row, 13, "text")
    row.name:SetPoint("LEFT")
    row.name:SetPoint("RIGHT", -right - 8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.stripe = Widgets.Rect(row, Theme.colors.hover)
    row.stripe:SetAllPoints()
    row.stripe:SetDrawLayer("BACKGROUND")
    return row
end

local function fillAddonRow(row, entry, index)
    row.name:SetText(entry.name)
    row.cells.now:SetText(ms(entry.now))
    row.cells.share:SetText(percent(entry.share))
    row.cells.average:SetText(ms(entry.average))
    row.cells.peak:SetText(ms(entry.peak))
    row.cells.memory:SetText(memory(entry.memory))
    local heavy = entry.share ~= nil and entry.share >= HEAVY_SHARE
    paint(row.name, heavy)
    paint(row.cells.now, heavy)
    paint(row.cells.share, heavy)
    row.stripe:SetShown(index % 2 == 0)
end

-- Places the blocks one under the other with their current heights and gives the total.
local function layout(v)
    local y = 0
    for _, block in ipairs(v.blocks) do
        local region, gap = block[1], block[2] or 0
        if region:IsShown() then
            y = y + gap
            region:ClearAllPoints()
            region:SetPoint("TOPLEFT", 0, -y)
            region:SetPoint("TOPRIGHT", 0, -y)
            if region.info then
                region.info:ClearAllPoints()
                region.info:SetPoint("LEFT", region, "LEFT", region:GetStringWidth() + 8, 0)
            end
            local height = region.GetStringHeight and region:GetStringHeight() or region:GetHeight()
            y = y + math.max(height, 1)
        end
    end
    y = y + 12
    v:SetHeight(y)
    v.setHeight(y)
end

--- Builds the tab (see definition.tabs in the options).
---@param parent table
---@param setHeight fun(height: number)
---@return table view
function PerfTab.Build(parent, setHeight)
    local v = CreateFrame("Frame", nil, parent)
    v:SetPoint("TOPLEFT")
    v:SetPoint("TOPRIGHT")
    v.setHeight = setHeight
    PerfTab.frame = v
    local blocks = {}
    v.blocks = blocks
    local function add(region, gap)
        blocks[#blocks + 1] = { region, gap }
        return region
    end

    v.verdict = add(Widgets.Text(v, 15, "text"), 8)
    v.verdict:SetJustifyH("LEFT")

    -- Now.
    add(heading(v, L.NOW), GAP)
    v.now = {}
    for _, key in ipairs({
        "FPS",
        "FRAME_TIME",
        "ADDONS_TIME",
        "HITCHES",
        "ADDON_HITCHES",
        "LATENCY",
        "BANDWIDTH",
        "MEMORY",
        "SCENE",
    }) do
        v.now[key] = add(keyValue(v, L[key]), key == "FPS" and 6 or 0)
    end

    -- Graphics.
    add(headingWithInfo(v, L.GRAPHICS, L.GRAPHICS_NOTE), GAP)
    v.graphics = {}
    for i, name in ipairs(Perf.CVARS) do
        if Perf.CVar(name) ~= nil then
            v.graphics[name] = add(keyValue(v, L["CVAR_" .. name]), i == 1 and 6 or 0)
        end
    end

    -- Drops.
    v.dropsHeading = add(headingWithInfo(v, L.DROPS), GAP)
    v.drops = add(Widgets.Text(v, 13, "text"), 6)
    v.drops:SetJustifyH("LEFT")

    -- Addons.
    add(headingWithInfo(v, L.ADDONS, L.ADDONS_NOTE), GAP)
    local choices = {}
    for i, sort in ipairs(Perf.SORTS) do
        choices[i] = { sort, L["SORT_" .. sort] }
    end
    local sortHolder = add(CreateFrame("Frame", nil, v), 8)
    sortHolder:SetHeight(30)
    v.sort = Widgets.Segmented(sortHolder, choices, function(value)
        PerfTab.sort = value
        PerfTab.Refresh()
    end)
    v.sort:SetPoint("LEFT")
    v.sort:SetValue(PerfTab.sort)
    v.header = add(addonRow(v), 8)
    v.header.name:SetText(L.COL_ADDON)
    for key, cell in pairs(v.header.cells) do
        cell:SetText(L[HEADERS[key]])
    end
    for _, region in pairs(v.header.cells) do
        Widgets.SetTextSize(region, 12)
    end
    Widgets.SetTextSize(v.header.name, 12)
    v.header.stripe:Hide()
    v.table = add(CreateFrame("Frame", nil, v), 2)

    v:SetScript("OnShow", function()
        Perf.UpdateMemory(true)
        PerfTab.Refresh()
        if not v.ticker then
            v.ticker = C_Timer.NewTicker(1, PerfTab.Refresh)
        end
    end)
    v:SetScript("OnHide", function()
        if v.ticker then
            v.ticker:Cancel()
            v.ticker = nil
        end
    end)
    v.Refresh = PerfTab.Refresh
    PerfTab.Refresh()
    return v
end

local function refreshNow(v, fps)
    local now = v.now
    local low, average, high = Perf.Summary(Perf.history)
    local threshold = opt("alerts.lowFps")
    local fpsText = tostring(math.floor(fps + 0.5))
    if low then
        fpsText = fpsText .. "  ·  " .. L.MIN_AVG_MAX:format(low, math.floor(average + 0.5), high)
    end
    now.FPS.value:SetText(fpsText)
    paint(now.FPS.value, fps < threshold)

    local share, addons, app = Perf.AddonShare()
    now.FRAME_TIME.value:SetText(app and ms(app) or (fps > 0 and ms(1000 / fps) or L.UNKNOWN))
    if addons and app then
        now.ADDONS_TIME.value:SetText(L.ADDONS_TIME_VALUE:format(ms(addons), ms(app), math.floor((share or 0) * 100 + 0.5)))
    else
        now.ADDONS_TIME.value:SetText(L.UNKNOWN)
    end
    paint(now.ADDONS_TIME.value, share ~= nil and share >= Perf.ADDONS_HEAVY)

    local function counts(scope)
        local a = Perf.Metric(scope, "CountTimeOver50Ms")
        if not a then
            return L.UNKNOWN
        end
        return L.HITCHES_VALUE:format(a, Perf.Metric(scope, "CountTimeOver100Ms") or 0, Perf.Metric(scope, "CountTimeOver500Ms") or 0)
    end
    now.HITCHES.value:SetText(counts("app"))
    now.ADDON_HITCHES.value:SetText(counts("overall"))

    local bandIn, bandOut, home, world = GetNetStats()
    home = home or 0
    world = world or home
    now.LATENCY.value:SetText(string.format("%d ms  ·  %d ms", home, world))
    paint(now.LATENCY.value, math.max(home, world) > opt("alerts.highLatency"))
    now.BANDWIDTH.value:SetText(string.format("%.1f KB/s  ·  %.1f KB/s", bandIn or 0, bandOut or 0))
    now.MEMORY.value:SetText(memory(Perf.TotalMemory()))

    local context = Perf.Context()
    local scene = L.SCENE_VALUE:format(context.plates, context.group)
    if context.combat then
        scene = scene .. "  ·  " .. L.IN_COMBAT
    end
    now.SCENE.value:SetText(scene)
end

--- Updates every number of the tab.
function PerfTab.Refresh()
    local v = PerfTab.frame
    if not v then
        return
    end
    local fps = GetFramerate()
    local threshold = opt("alerts.lowFps")
    local key, a, b = Perf.Verdict(fps, threshold)
    v.verdict:SetText(L[key]:format(a or 0, b or 0))
    paint(v.verdict, key == "VERDICT_ADDONS" or key == "VERDICT_GAME")

    refreshNow(v, fps)

    for name, row in pairs(v.graphics) do
        row.value:SetText(PerfTab.CVarText(name) or L.UNKNOWN)
    end

    v.dropsHeading.info:Set(L.DROPS, L.DROPS_NOTE:format(threshold, Perf.DROP_SECONDS))
    local lines = {}
    for i, drop in ipairs(Perf.drops) do
        lines[i] = PerfTab.DropText(drop)
    end
    v.drops:SetText(#lines > 0 and table.concat(lines, "\n") or L.NO_DROPS)

    Perf.UpdateMemory()
    local list = Perf.AddOns(PerfTab.sort)
    local rows = PerfTab.rows
    for i, entry in ipairs(list) do
        local row = rows[i]
        if not row then
            row = addonRow(v.table)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
            row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW)
            rows[i] = row
        end
        row:Show()
        fillAddonRow(row, entry, i)
    end
    for i = #list + 1, #rows do
        rows[i]:Hide()
    end
    v.table:SetHeight(math.max(#list * ROW, 1))
    layout(v)
end

--- Opens the options on this tab.
function PerfTab.Open(addonName)
    E:OpenOptions(addonName, TAB)
end
