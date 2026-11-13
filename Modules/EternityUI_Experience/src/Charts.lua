-- The Charts tab: XP gained this session, time per level and XP by source. Charts are columns of
-- textures. Hovering a column shows its values; the tab refreshes itself while shown.

---@type string, EternityUIExperienceNamespace
local addonName, ns = ...
local E = EternityUI
local Shape, Theme, Widgets = E.Shape, E.Theme, E.Widgets
local Data, L = ns.Data, ns.L

---@class EternityUIExperienceCharts
---@field view table? the tab's frame while it exists
local Charts = {}
ns.Charts = Charts

local CHART_HEIGHT = 140
local LABELS_HEIGHT = 16
local PADDING = 16
local CARD_GAP = 16
local GAP = 2
local REFRESH = 5

-- Source series: key, label and color spec.
local SOURCES = {
    { key = "kill", label = L.SOURCE_KILL, color = "accent" },
    { key = "quest", label = L.SOURCE_QUEST, color = { 0.98, 0.75, 0.14, 1 } },
    { key = "other", label = L.SOURCE_OTHER, color = "textMuted" },
}
Charts.SOURCES = SOURCES

local function code(spec)
    local r, g, b = Theme.Color(spec)
    return "|cff" .. Theme.ToHex(r, g, b):sub(2)
end

-- Column chart -------------------------------------------------------------------------------------

--- Stacked column chart. :SetData(columns, colors, tooltip, format) draws it: columns is a list of
--- { label = string?, values = number[] } (one value per series, bottom to top), colors the
--- series' colors and tooltip(tip, column) fills each column's tooltip.
local function ColumnChart(parent)
    local chart = CreateFrame("Frame", nil, parent)
    chart:SetHeight(CHART_HEIGHT + LABELS_HEIGHT)
    chart.columns, chart.pool, chart.labels = {}, {}, {}
    chart.base = chart:CreateTexture(nil, "ARTWORK")
    chart.base:SetPoint("BOTTOMLEFT", 0, LABELS_HEIGHT)
    chart.base:SetPoint("BOTTOMRIGHT", 0, LABELS_HEIGHT)
    chart.top = Widgets.Text(chart, 11, "muted")
    chart.top:SetPoint("TOPRIGHT")

    local function column(i)
        local col = chart.pool[i]
        if not col then
            col = CreateFrame("Frame", nil, chart)
            col:EnableMouse(true)
            col.parts = {}
            col.hover = col:CreateTexture(nil, "BACKGROUND")
            col.hover:SetAllPoints()
            col.hover:Hide()
            col:SetScript("OnEnter", function(self)
                self.hover:SetColorTexture(Theme.Color("surfaceHover"))
                self.hover:Show()
            end)
            col:SetScript("OnLeave", function(self)
                self.hover:Hide()
            end)
            Widgets.AttachTooltip(col, function(tip, self)
                if chart.tooltip and self.data then
                    chart.tooltip(tip, self.data)
                end
            end, "TOP")
            chart.pool[i] = col
        end
        return col
    end

    local function label(i)
        local text = chart.labels[i]
        if not text then
            text = Widgets.Text(chart, 11, "muted")
            text:SetJustifyH("CENTER")
            chart.labels[i] = text
        end
        return text
    end

    function chart:SetData(columns, colors, tooltip, format)
        self.columns, self.colors, self.tooltip, self.format = columns, colors, tooltip, format
        self:Paint()
    end

    function chart:Paint()
        self.base:SetColorTexture(Theme.Color("border"))
        self.base:SetHeight(E.Pixel.Size(self))
        local columns, width = self.columns, self:GetWidth()
        if width <= 0 then
            return
        end
        local peak = 0
        for _, c in ipairs(columns) do
            local sum = 0
            for _, v in ipairs(c.values) do
                sum = sum + v
            end
            c.total = sum
            peak = math.max(peak, sum)
        end
        self.top:SetText(peak > 0 and (self.format or Data.Short)(peak) or "")
        local n = #columns
        local step = n > 0 and width / n or 0
        local every = math.max(1, math.ceil(n / 8))
        for i, c in ipairs(columns) do
            local col = column(i)
            col.data = c
            col:ClearAllPoints()
            col:SetPoint("BOTTOMLEFT", (i - 1) * step, LABELS_HEIGHT)
            col:SetSize(math.max(step, 1), CHART_HEIGHT)
            col:Show()
            local y = 0
            for s, v in ipairs(c.values) do
                local part = col.parts[s]
                if not part then
                    part = col:CreateTexture(nil, "ARTWORK")
                    col.parts[s] = part
                end
                local h = peak > 0 and v / peak * (CHART_HEIGHT - LABELS_HEIGHT) or 0
                part:ClearAllPoints()
                part:SetPoint("BOTTOMLEFT", GAP / 2, y)
                part:SetSize(math.max(step - GAP, 1), math.max(h, 1))
                part:SetColorTexture(Theme.Color(self.colors[s] or "accent"))
                part:SetShown(h >= 1)
                y = y + h
            end
            for s = #c.values + 1, #col.parts do
                col.parts[s]:Hide()
            end
            local text = label(i)
            text:ClearAllPoints()
            text:SetPoint("TOP", col, "BOTTOM", 0, -2)
            text:SetText(c.label or "")
            text:SetShown(c.label ~= nil and ((i - 1) % every == 0 or i == n))
        end
        for i = n + 1, #self.pool do
            self.pool[i]:Hide()
            self.labels[i]:Hide()
        end
    end

    chart:SetScript("OnSizeChanged", chart.Paint)
    return Widgets.Track(chart)
end

-- Cards --------------------------------------------------------------------------------------------

local CARD_HEIGHT = PADDING * 2 + 24 + 20 + CHART_HEIGHT + LABELS_HEIGHT

--- Card with a title (its hint in the "i" beside it), a line for the legend and a chart (or "no
--- data").
local function chartCard(parent, title, hint)
    local card = CreateFrame("Frame", nil, parent)
    card:SetHeight(CARD_HEIGHT)
    card.shape = Shape.New(card)
    function card:Paint()
        Shape.Paint(self.shape, Theme.radius, Theme.colors.surface, Theme.colors.border)
    end
    Widgets.Track(card)

    card.title = Widgets.Text(card, 16, "text")
    card.title:SetPoint("TOPLEFT", PADDING, -PADDING)
    card.title:SetText(title)
    card.info = Widgets.Info(card, title, hint)
    card.info:SetPoint("LEFT", card.title, "RIGHT", 8, 0)
    card.legend = Widgets.Text(card, 13, "text")
    card.legend:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -6)
    card.empty = Widgets.Text(card, 14, "muted")
    card.empty:SetPoint("CENTER", 0, -24)
    card.empty:SetText(L.NO_DATA)
    card.chart = ColumnChart(card)
    card.chart:SetPoint("BOTTOMLEFT", PADDING, PADDING)
    card.chart:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)

    function card:SetEmpty(empty)
        self.empty:SetShown(empty)
        self.chart:SetShown(not empty)
    end
    return card
end

local function legend()
    local parts = {}
    for _, source in ipairs(SOURCES) do
        parts[#parts + 1] = code(source.color) .. source.label .. "|r"
    end
    return table.concat(parts, "   ")
end

-- Data per chart -----------------------------------------------------------------------------------

--- Session columns: XP per bucket of `minutes`, labeled by minutes from the start.
---@param minutes number
function Charts.SessionColumns(minutes)
    local columns = {}
    for i, xp in ipairs(Data:Buckets(minutes)) do
        columns[i] = { label = ((i - 1) * minutes) .. "m", values = { xp }, from = (i - 1) * minutes, to = i * minutes }
    end
    return columns
end

--- History columns, one per level with data (ascending).
---@param values fun(record: table): number[]
function Charts.LevelColumns(values)
    local levels = {}
    for level in pairs(Data:Bind().levels) do
        levels[#levels + 1] = level
    end
    table.sort(levels)
    local columns = {}
    for _, level in ipairs(levels) do
        local record = Data:LevelRecord(level)
        columns[#columns + 1] = { label = tostring(level), level = level, record = record, values = values(record) }
    end
    return columns
end

local function hasData(columns)
    for _, c in ipairs(columns) do
        for _, v in ipairs(c.values) do
            if v > 0 then
                return true
            end
        end
    end
    return false
end

-- The tab ------------------------------------------------------------------------------------------

--- Builds the Charts tab.
---@param parent table
---@param setHeight fun(height: number)
---@return table view
function Charts.Build(parent, setHeight)
    local view = CreateFrame("Frame", nil, parent)
    view:SetPoint("TOPLEFT")
    view:SetPoint("TOPRIGHT")
    Charts.view = view

    local y = 8
    local function add(card)
        card:SetPoint("TOPLEFT", 0, -y)
        card:SetPoint("TOPRIGHT", 0, -y)
        y = y + card:GetHeight() + CARD_GAP
        return card
    end
    view.session = add(chartCard(view, L.CHART_SESSION, L.CHART_SESSION_HINT))
    view.levels = add(chartCard(view, L.CHART_LEVELS, L.CHART_LEVELS_HINT))
    view.sources = add(chartCard(view, L.CHART_SOURCES, L.CHART_SOURCES_HINT))
    view.sources.legend:SetText(legend())

    -- Two clicks: the first one asks for confirmation for a few seconds.
    local armed = false
    local reset
    reset = Widgets.Button(view, L.RESET, "danger", function()
        if not armed then
            armed = true
            reset.label:SetText(L.RESET_CONFIRM)
            C_Timer.After(4, function()
                armed = false
                reset.label:SetText(L.RESET)
            end)
            return
        end
        armed = false
        reset.label:SetText(L.RESET)
        Data:ResetHistory()
        view:Refresh()
    end)
    reset:SetWidth(180)
    reset:SetPoint("TOPLEFT", 0, -y)
    Widgets.AttachTooltip(reset, function(tip)
        tip:SetTitle(L.RESET)
        tip:AddLine(L.RESET_HINT)
    end, "TOP")
    local height = y + reset:GetHeight() + 8
    view:SetHeight(height)

    function view:Refresh()
        local minutes = E.store:Get(addonName, "tracking.chartBucket")
        local session = Charts.SessionColumns(minutes)
        self.session:SetEmpty(not hasData(session))
        self.session.chart:SetData(session, { "accent" }, function(tip, column)
            tip:SetTitle(string.format("%d–%d min", column.from, column.to))
            tip:AddDoubleLine(L.GAINED, Data.Short(column.values[1]))
        end)

        local levels = Charts.LevelColumns(function(record)
            return { record.seconds }
        end)
        self.levels:SetEmpty(not hasData(levels))
        self.levels.chart:SetData(levels, { "accent" }, function(tip, column)
            tip:SetTitle(string.format(L.LEVEL, column.level))
            tip:AddDoubleLine(L.TIME_LEVEL, Data.Duration(column.record.seconds))
        end, Data.Duration)

        local colors = {}
        for i, source in ipairs(SOURCES) do
            colors[i] = source.color
        end
        local sources = Charts.LevelColumns(function(record)
            local values = {}
            for i, source in ipairs(SOURCES) do
                values[i] = record[source.key]
            end
            return values
        end)
        self.sources:SetEmpty(not hasData(sources))
        self.sources.chart:SetData(sources, colors, function(tip, column)
            tip:SetTitle(string.format(L.LEVEL, column.level))
            for i, source in ipairs(SOURCES) do
                tip:AddDoubleLine(source.label, Data.Short(column.values[i]), nil, source.color)
            end
            if column.record.kills > 0 then
                tip:AddDoubleLine(L.SOURCE_KILL .. " (#)", tostring(column.record.kills))
            end
        end)
        setHeight(height)
    end

    -- Live while shown.
    local elapsed = 0
    view:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= REFRESH then
            elapsed = 0
            self:Refresh()
        end
    end)
    view:SetScript("OnHide", function()
        elapsed = 0
    end)
    return view
end
