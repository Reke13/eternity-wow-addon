-- EternityUI_InfoBar: a small bar with the time, FPS, latency and gold. The Mover places it; a
-- click opens its options, a right click its "Performance" tab (Perf.lua, PerfTab.lua), which
-- tells where the FPS go.

---@type string, EternityUIInfoBarNamespace
local addonName, ns = ...
local E = EternityUI
local Shape, Theme, Widgets = E.Shape, E.Theme, E.Widgets
local L, Perf, PerfTab = ns.L, ns.Perf, ns.PerfTab

local TEXT_SIZE = 13
local HEIGHT = 26
local PADDING = 12

---@class EternityUIInfoBarModule: EternityUIModuleDefinition
---@field bar table? the bar's frame (created the first time it's enabled)
---@field ticker table?
---@field running boolean? between OnEnable and OnDisable (active is still false inside OnEnable)
local Module = {
    schema = ns.OptionsSchema,
    tabs = { { key = PerfTab.TAB, text = L.TAB, build = PerfTab.Build } },
    Perf = Perf,
    PerfTab = PerfTab,
}

local opt = ns.opt

local function code(spec)
    local r, g, b = Theme.Color(spec)
    return string.format("|cff%02x%02x%02x", r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5)
end

-- Latency in ms (realm and world). The exported API may give only the realm's.
local function latency()
    local _, _, home, world = GetNetStats()
    home = home or 0
    return home, world or home
end

local function clockText()
    if opt("content.clockFormat") == "12h" then
        local hour = tonumber(date("%H"))
        return string.format("%d:%s %s", (hour - 1) % 12 + 1, date("%M"), hour < 12 and "AM" or "PM")
    end
    return date("%H:%M")
end

--- The bar's text with the current configuration (empty if everything is disabled).
---@return string
function Module:BuildText()
    local value = code(opt("layout.accentValues") and "accentText" or "text")
    local alert = code(opt("alerts.color"))
    local items = {}
    if opt("content.clock") then
        items[#items + 1] = value .. clockText() .. "|r"
    end
    if opt("content.fps") then
        local fps = math.floor(GetFramerate() + 0.5)
        items[#items + 1] = (fps < opt("alerts.lowFps") and alert or value) .. fps .. "|r FPS"
    end
    if opt("content.latency") then
        local ms = math.max(latency())
        items[#items + 1] = (ms > opt("alerts.highLatency") and alert or value) .. ms .. "|r MS"
    end
    if opt("content.gold") then
        local money = C_CurrencyInfo.GetCoinTextureString(GetMoney(), TEXT_SIZE)
        items[#items + 1] = value .. money .. "|r"
    end
    -- User text: "|" is escaped ("||") so it doesn't break the color codes.
    local separator = opt("content.separator"):gsub("|", "||")
    local joiner = separator == "" and "    " or ("  " .. code("textMuted") .. separator .. "|r  ")
    return table.concat(items, joiner)
end

--- Refreshes the text and adjusts the width. The bar hides if there's nothing to show.
function Module:Update()
    local bar = self.bar
    if not bar then
        return
    end
    local text = self:BuildText()
    bar.text:SetText(text)
    bar:SetSize(math.ceil(bar.text:GetStringWidth()) + PADDING * 2, HEIGHT)
    bar:SetShown(self.running and text ~= "")
end

--- Scale and background. The position belongs to the Mover.
function Module:ApplyLayout()
    local bar = self.bar
    if not bar then
        return
    end
    bar:SetScale(opt("layout.scale"))
    bar:Paint()
end

local function buildTooltip(tip)
    local home, world = latency()
    tip:SetTitle(E.Localize(ns.OptionsSchema.title))
    tip:AddDoubleLine(L.LATENCY_HOME, home .. " ms")
    tip:AddDoubleLine(L.LATENCY_WORLD, world .. " ms")
    local low, average, high = Perf.Summary(Perf.history)
    if low then
        tip:AddDoubleLine(L.LAST_MINUTE, L.MIN_AVG_MAX:format(low, math.floor(average + 0.5), high))
    end
    local share, addons = Perf.AddonShare()
    if share then
        tip:AddDoubleLine(L.ADDONS_LINE, string.format("%.2f ms (%d%%)", addons, math.floor(share * 100 + 0.5)))
    end
    tip:AddHint(L.HINT)
end

local function createBar(self)
    local bar = CreateFrame("Frame", "EternityUIInfoBar", UIParent)
    bar:SetFrameStrata("MEDIUM")
    bar:SetClampedToScreen(true)
    bar:EnableMouse(true)
    bar.shape = Shape.New(bar)
    bar.text = Widgets.Text(bar, TEXT_SIZE, "muted")
    bar.text:SetPoint("CENTER")

    function bar.Paint(frame)
        if opt("layout.background") then
            Theme.PaintWindow(frame.shape)
        else
            Shape.Paint(frame.shape, 0, nil, nil)
        end
        -- Colors and width follow the theme.
        self:Update()
    end

    bar:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            E:OpenOptions(addonName)
        elseif button == "RightButton" then
            PerfTab.Open(addonName)
        end
    end)
    Widgets.AttachTooltip(bar, buildTooltip, "BOTTOM")
    self.bar = bar
    Widgets.Track(bar)
end

function Module:OnEnable()
    self.running = true
    if not self.bar then
        createBar(self)
    end
    E.Mover.Register({
        key = addonName,
        owner = addonName,
        label = E.Localize(ns.OptionsSchema.title),
        frame = self.bar,
        point = "TOP",
        x = 0,
        y = -6,
    })
    self:ApplyLayout()
    self:Update()
    self.ticker = C_Timer.NewTicker(1, function()
        Perf.Sample(GetFramerate(), opt("alerts.lowFps"))
        self:Update()
    end)
end

function Module:OnDisable()
    self.running = false
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
    E.Mover.Unregister(addonName)
    if self.bar then
        self.bar:Hide()
    end
end

function Module:OnConfigChanged(path)
    -- path nil = reset or profile change: anything may have changed.
    if path == nil or path:find("^layout%.") then
        self:ApplyLayout()
    end
    self:Update()
end

E:RegisterModule(addonName, Module)
