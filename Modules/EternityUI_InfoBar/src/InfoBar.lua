-- EternityUI_InfoBar: a small bar with the time, FPS, latency, gold, bag slots, level progress
-- and durability, each one switched on in the options. The items are laid out in rows (a number
-- per row, or shared out among a number of rows) and columns, with the bar's width fitted to
-- them or fixed. The Mover places it; a click opens its options, a right click its
-- "Performance" tab (Perf.lua, PerfTab.lua), which tells where the FPS go.

---@type string, EternityUIInfoBarNamespace
local addonName, ns = ...
local E = EternityUI
local Shape, Theme, Widgets = E.Shape, E.Theme, E.Widgets
local L, Perf, PerfTab = ns.L, ns.Perf, ns.PerfTab

local PADDING = 12
local GAP = 16 -- between columns, besides the separator

---@class EternityUIInfoBarModule: EternityUIModuleDefinition
---@field bar table? the bar's frame (created the first time it's enabled)
---@field cells table[] one text per item shown
---@field separators table[] texts between the items of a row
---@field ticker table?
---@field running boolean? between OnEnable and OnDisable (active is still false inside OnEnable)
local Module = {
    schema = ns.OptionsSchema,
    tabs = { { key = PerfTab.TAB, text = L.TAB, build = PerfTab.Build } },
    Perf = Perf,
    PerfTab = PerfTab,
    cells = {},
    separators = {},
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

--- Bag slots: free and total, of the bags that hold anything (not quivers, soul bags...).
---@return integer free
---@return integer total
function Module.BagSlots()
    local free, total = 0, 0
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        local empty, family = C_Container.GetContainerNumFreeSlots(bag)
        if slots > 0 and (family == nil or family == 0) then
            free = free + (empty or 0)
            total = total + slots
        end
    end
    return free, total
end

--- Durability of what's equipped, all together, as a fraction; and the most worn piece's.
--- nil when nothing equipped wears out.
---@return number? overall
---@return number? worst
---@return integer? worstSlot
function Module.Durability()
    local current, maximum, worst, worstSlot = 0, 0, nil, nil
    for slot = INVSLOT_FIRST_EQUIPPED or 1, INVSLOT_LAST_EQUIPPED or 19 do
        local now, most = GetInventoryItemDurability(slot)
        if now and most and most > 0 then
            current, maximum = current + now, maximum + most
            local share = now / most
            if not worst or share < worst then
                worst, worstSlot = share, slot
            end
        end
    end
    if maximum == 0 then
        return nil
    end
    return current / maximum, worst, worstSlot
end

--- Progress of the current level (0..1) and the level; nil at the top level.
---@return number?
---@return integer?
function Module.LevelProgress()
    local level = UnitLevel("player")
    local top = GetMaxPlayerLevel and GetMaxPlayerLevel()
    local most = UnitXPMax("player") or 0
    if (top and level >= top) or most <= 0 then
        return nil
    end
    return (UnitXP("player") or 0) / most, level
end

local function clockText()
    if opt("content.clockFormat") == "12h" then
        local hour = tonumber(date("%H"))
        return string.format("%d:%s %s", (hour - 1) % 12 + 1, date("%M"), hour < 12 and "AM" or "PM")
    end
    return date("%H:%M")
end

--- The texts of the items switched on, in order (empty if everything is off).
---@return string[]
function Module:BuildItems()
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
        local money = C_CurrencyInfo.GetCoinTextureString(GetMoney(), opt("layout.textSize"))
        items[#items + 1] = value .. money .. "|r"
    end
    if opt("content.bags") then
        local free, total = Module.BagSlots()
        local shown = opt("content.bagsFormat") == "used" and (total - free) or free
        local color = free <= opt("alerts.fewSlots") and alert or value
        items[#items + 1] = L.BAGS .. " " .. color .. shown .. "/" .. total .. "|r"
    end
    if opt("content.xp") then
        local progress, level = Module.LevelProgress()
        if progress then
            items[#items + 1] = L.LEVEL:format(level) .. " " .. value .. math.floor(progress * 100) .. "%|r"
        end
    end
    if opt("content.durability") then
        local overall = Module.Durability()
        if overall then
            local percent = math.floor(overall * 100 + 0.5)
            local color = percent < opt("alerts.lowDurability") and alert or value
            items[#items + 1] = L.DURABILITY .. " " .. color .. percent .. "%|r"
        end
    end
    return items
end

-- The separator between the items of a row, or nil for just a gap.
local function separatorText()
    -- User text: "|" is escaped ("||") so it doesn't break the color codes.
    local separator = opt("content.separator"):gsub("|", "||")
    if separator == "" then
        return nil
    end
    return code("textMuted") .. separator .. "|r"
end

--- The bar's items in one line (empty if everything is off).
---@return string
function Module:BuildText()
    local separator = separatorText()
    return table.concat(self:BuildItems(), separator and ("  " .. separator .. "  ") or "    ")
end

--- How many items go in each row, for n items: the number set, or them shared out among the
--- rows set.
---@param n integer
---@return integer
function Module.PerRow(n)
    local perRow = opt("layout.perRow")
    if perRow <= 0 then
        perRow = math.ceil(n / math.max(opt("layout.rows"), 1))
    end
    return math.max(math.min(perRow, n), 1)
end

local function pooled(bar, pool, index)
    local text = pool[index]
    if not text then
        text = Widgets.Text(bar, opt("layout.textSize"), "muted")
        text:SetWordWrap(false)
        pool[index] = text
    end
    return text
end

--- Refreshes the items and lays them out in rows and columns. The bar hides if there's nothing
--- to show.
function Module:Update()
    local bar = self.bar
    if not bar then
        return
    end
    local items = self:BuildItems()
    local n = #items
    local size, height = opt("layout.textSize"), opt("layout.height")
    local perRow = Module.PerRow(n)
    local rows = math.max(math.ceil(n / perRow), 1)
    local separator = separatorText()

    -- Measure: each column as wide as its widest item.
    local widths = {}
    for i, text in ipairs(items) do
        local cell = pooled(bar, self.cells, i)
        Widgets.SetTextSize(cell, size)
        cell:SetWidth(0)
        cell:SetText(text)
        local column = (i - 1) % perRow + 1
        widths[column] = math.max(widths[column] or 0, math.ceil(cell:GetStringWidth()))
    end
    local between = GAP
    if separator then
        local probe = pooled(bar, self.separators, 1)
        Widgets.SetTextSize(probe, size)
        probe:SetText(separator)
        between = math.ceil(probe:GetStringWidth()) + GAP
    end
    local columns = perRow
    local width = opt("layout.width")
    if width > 0 then
        -- Fixed: the columns share the room evenly.
        local each = (width - PADDING * 2 - (columns - 1) * between) / columns
        for c = 1, columns do
            widths[c] = math.max(each, 1)
        end
    else
        width = PADDING * 2 + (columns - 1) * between
        for c = 1, columns do
            width = width + (widths[c] or 0)
        end
    end

    -- Place.
    local used = 0
    for i = 1, n do
        local cell = self.cells[i]
        local column, row = (i - 1) % perRow + 1, math.floor((i - 1) / perRow)
        local x = PADDING
        for c = 1, column - 1 do
            x = x + widths[c] + between
        end
        local y = -(row * height + height / 2)
        cell:ClearAllPoints()
        cell:SetWidth(widths[column])
        cell:SetJustifyH("CENTER")
        cell:SetPoint("LEFT", bar, "TOPLEFT", x, y)
        cell:Show()
        -- A separator after it when another item follows in the same row.
        if separator and column < perRow and i < n then
            used = used + 1
            local sep = pooled(bar, self.separators, used)
            Widgets.SetTextSize(sep, size)
            sep:SetWidth(0)
            sep:SetText(separator)
            sep:ClearAllPoints()
            sep:SetPoint("CENTER", bar, "TOPLEFT", x + widths[column] + between / 2, y)
            sep:Show()
        end
    end
    for i = n + 1, #self.cells do
        self.cells[i]:Hide()
    end
    for i = used + 1, #self.separators do
        self.separators[i]:Hide()
    end
    bar:SetSize(math.max(width, 1), rows * height)
    bar:SetShown(self.running and n > 0)
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
    local overall, worst, slot = Module.Durability()
    if overall then
        tip:AddDoubleLine(L.DURABILITY_LINE, math.floor(overall * 100 + 0.5) .. "%")
        local link = slot and GetInventoryItemLink("player", slot)
        if link and worst and worst < 1 then
            tip:AddDoubleLine(L.WORST_PIECE, link .. " " .. math.floor(worst * 100 + 0.5) .. "%")
        end
    end
    tip:AddHint(L.HINT)
end

local function createBar(self)
    local bar = CreateFrame("Frame", "EternityUIInfoBar", UIParent)
    bar:SetFrameStrata("MEDIUM")
    bar:SetClampedToScreen(true)
    bar:EnableMouse(true)
    bar.shape = Shape.New(bar)

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
