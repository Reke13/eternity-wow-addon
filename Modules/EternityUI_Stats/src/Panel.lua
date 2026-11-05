-- EternityUI_Stats panel: the frame with a section per category and a row per stat. Values are
-- read only while it's shown (events registered then, coalesced to one refresh per 0.1 s); a
-- refresh only repaints texts unless the set of visible rows changed. Columns have a fixed
-- width, so no secret text is ever measured.

---@type string, EternityUIStatsNamespace
local _, ns = ...
local E = EternityUI
local W, Theme = ns.Ui.W, ns.Ui.Theme
local Skin = W.Skin
local Core, Values, L = ns.Core, ns.Values, ns.L
local opt = Core.Opt

-- Beside the row, or at the cursor.
local function tooltipAnchor()
    if opt("tooltips.anchor") == "cursor" then
        return "CURSOR"
    end
    return opt("window.side") == "left" and "LEFT" or "RIGHT"
end

---@class EternityUIStatsPanel
---@field frame table?
---@field rows table<string, table> row frame per stat id
---@field sections table<string, table> header per category
---@field results table<string, EternityStatResult|false> last read per stat id (false = doesn't apply)
---@field last table<string, string> last plain text per stat id (shown grey while secret)
---@field visible string[] stat ids drawn now, in order
---@field signature string? visible rows and collapsed sections at the last layout
---@field minHeight number? set by Character.lua with panel.matchHeight
local Panel = { rows = {}, sections = {}, results = {}, last = {}, visible = {} }
ns.Panel = Panel

-- PaperDollFrame_OnLoad's list (Forever FrameXML), plus the ones the general rows need.
local EVENTS = {
    "PLAYER_EQUIPMENT_CHANGED",
    "COMBAT_RATING_UPDATE",
    "SPELL_POWER_CHANGED",
    "MASTERY_UPDATE",
    "PLAYER_DAMAGE_DONE_MODS",
    "SPEED_UPDATE",
    "LIFESTEAL_UPDATE",
    "AVOIDANCE_UPDATE",
    "PLAYER_AVG_ITEM_LEVEL_UPDATE",
    "PLAYER_LEVEL_UP",
    "SKILL_LINES_CHANGED",
    "CHARACTER_POINTS_CHANGED",
    "UPDATE_SHAPESHIFT_FORM",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_REGEN_DISABLED",
}
local UNIT_EVENTS = {
    "UNIT_STATS",
    "UNIT_ATTACK_POWER",
    "UNIT_RANGED_ATTACK_POWER",
    "UNIT_RESISTANCES",
    "UNIT_ATTACK_SPEED",
    "UNIT_DAMAGE",
    "UNIT_RANGEDDAMAGE",
    "UNIT_ATTACK",
    "UNIT_SPELL_HASTE",
    "UNIT_DEFENSE",
    "UNIT_MAXHEALTH",
    "UNIT_MAXPOWER",
    "UNIT_DISPLAYPOWER",
    "UNIT_AURA",
    "UNIT_INVENTORY_CHANGED",
    "UNIT_LEVEL",
}

local function fontSize(style)
    local font = Theme.Font(style)
    if not font then
        return 12
    end
    local _, size = font:GetFont()
    return type(size) == "number" and size or 12
end

local function newText(parent, justify)
    local text = parent:CreateFontString(nil, "OVERLAY")
    text:SetJustifyH(justify)
    text:SetWordWrap(false)
    text:SetShadowOffset(1, -1)
    text:SetShadowColor(0, 0, 0, 0.6)
    return text
end

-- Frame ----------------------------------------------------------------------------------------

function Panel:Create()
    if self.frame then
        return self.frame
    end
    local frame = CreateFrame("Frame", "EternityUIStatsPanel", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetSize(200, 200)
    frame:Hide()
    frame.shape = Skin.Shape(frame, "window")
    frame.title = newText(frame, "LEFT")
    self.frame = frame

    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", function()
        self:Queue()
    end)
    frame:SetScript("OnShow", function()
        self:Listen(true)
        self:Refresh(true)
    end)
    frame:SetScript("OnHide", function()
        self:Listen(false)
        E.Widgets.HideTooltip()
    end)
    W.Themed(frame, function()
        self.signature = nil
        if frame:IsShown() then
            self:Refresh(true)
        end
    end)
    return frame
end

function Panel:Listen(on)
    local events = self.events
    events:UnregisterAllEvents()
    if not on then
        return
    end
    for _, event in ipairs(EVENTS) do
        -- An event this client doesn't have errors on RegisterEvent: skip it.
        pcall(events.RegisterEvent, events, event)
    end
    for _, event in ipairs(UNIT_EVENTS) do
        if not pcall(events.RegisterUnitEvent, events, event, "player") then
            pcall(events.RegisterEvent, events, event)
        end
    end
end

--- One refresh 0.1 s after a burst of events.
function Panel:Queue()
    if self.pending then
        return
    end
    self.pending = true
    C_Timer.After(0.1, function()
        self.pending = false
        if self.frame and self.frame:IsShown() then
            self:Refresh()
        end
    end)
end

-- Rows and headers -----------------------------------------------------------------------------

function Panel:Section(category)
    local header = self.sections[category]
    if header then
        return header
    end
    header = CreateFrame("Button", nil, self.frame)
    header.category = category
    header.text = newText(header, "LEFT")
    header.text:SetPoint("LEFT")
    header.chevron = Skin.Icon(header, "chevronDown", 10)
    header.chevron:SetPoint("RIGHT", -2, 0)
    header.line = header:CreateTexture(nil, "ARTWORK")
    header.line:SetHeight(1)
    header.line:SetPoint("BOTTOMLEFT")
    header.line:SetPoint("BOTTOMRIGHT")
    header:SetScript("OnClick", function(button)
        if not opt("categories.collapsible") then
            return
        end
        local collapsed = Core.Char().collapsed
        collapsed[button.category] = not collapsed[button.category] or nil
        self:Refresh(true)
    end)
    self.sections[category] = header
    return header
end

function Panel:Row(stat)
    local row = self.rows[stat.id]
    if row then
        return row
    end
    row = CreateFrame("Frame", nil, self.frame)
    row.stat = stat
    row:EnableMouse(true)
    row.zebra = row:CreateTexture(nil, "BACKGROUND")
    row.zebra:SetAllPoints()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("LEFT")
    row.label = newText(row, "LEFT")
    row.value = newText(row, "RIGHT")
    W.AttachTooltip(row, function(tip, frame)
        self:BuildTooltip(tip, frame)
    end, tooltipAnchor)
    self.rows[stat.id] = row
    return row
end

-- Reading and layout ---------------------------------------------------------------------------

local function shows(result)
    if not result then
        return false
    end
    if result.secret then
        return true
    end
    return not (opt("categories.hideZero") and result.zero)
end

--- Reads every stat of the shown categories; returns the sections with their visible stats.
function Panel:Read()
    local sections = {}
    local collapsed = Core.Char().collapsed
    local parts = {}
    for _, category in ipairs(Values.Categories()) do
        local list = {}
        for _, stat in ipairs(Values.Of(category)) do
            local result = Values.Read(stat)
            self.results[stat.id] = result or false
            if shows(result) then
                list[#list + 1] = stat
                parts[#parts + 1] = stat.id
            end
        end
        if #list > 0 then
            local folded = opt("categories.collapsible") and opt("layout.headers") and collapsed[category] == true
            sections[#sections + 1] = { category = category, stats = list, collapsed = folded }
            parts[#parts + 1] = folded and ("-" .. category) or category
        end
    end
    return sections, table.concat(parts, ",")
end

--- Reads the stats and repaints; lays the rows out again when force or when what's visible
--- changed.
function Panel:Refresh(force)
    if not self.frame then
        return
    end
    local sections, signature = self:Read()
    if force or signature ~= self.signature then
        self.signature = signature
        self:Layout(sections)
    end
    for _, id in ipairs(self.visible) do
        self:Paint(self.rows[id])
    end
end

function Panel:Layout(sections)
    local frame = self.frame
    local pad = opt("window.padding")
    local width = opt("layout.columnWidth")
    local columns = math.max(1, math.floor(opt("layout.columns") or 1))
    local font, headerFont = opt("text.font"), opt("text.headerFont")
    local rowHeight = fontSize(font) + 4
    local rowGap = opt("layout.rowSpacing")
    local sectionGap = opt("layout.sectionSpacing")
    local headers = opt("layout.headers")
    local headerHeight = headers and fontSize(headerFont) + 8 or 0
    local labels = opt("layout.labels")
    local alignRight = opt("layout.valueAlign") ~= "left"
    local collapsible = opt("categories.collapsible") and headers

    -- Window look on top of the theme.
    frame:SetScale(opt("window.scale"))
    local background = opt("window.background")
    frame.shape:SetColors("window", Theme.glass and "borderStrong" or "border", Theme.glass and "windowTop" or nil)
    frame.shape:SetAlpha(background and (Theme.opacity or 1) * opt("window.opacity") or 0)

    local top = pad
    frame.title:SetShown(opt("window.title"))
    if opt("window.title") then
        frame.title:SetFontObject(Theme.Font("heading"))
        frame.title:SetTextColor(Theme.Color("text"))
        frame.title:SetText(L.TITLE)
        frame.title:ClearAllPoints()
        frame.title:SetPoint("TOPLEFT", pad, -pad)
        top = top + fontSize("heading") + Theme.space.sm + 2
    end

    for _, header in pairs(self.sections) do
        header:Hide()
    end
    for _, row in pairs(self.rows) do
        row:Hide()
    end
    self.visible = {}

    local headerColor = Core.Hex(opt("text.headerColor"))
    local labelColor = Core.Hex(opt("text.labelColor"))
    local heights = {}
    for i = 1, columns do
        heights[i] = 0
    end

    for index, section in ipairs(sections or {}) do
        local column = 1
        if opt("layout.flow") == "order" then
            column = (index - 1) % columns + 1
        else
            for i = 2, columns do
                if heights[i] < heights[column] then
                    column = i
                end
            end
        end
        local x = pad + (column - 1) * (width + pad)
        local y = top + heights[column] + (heights[column] > 0 and sectionGap or 0)

        if headers then
            local header = self:Section(section.category)
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", x, -y)
            header:SetSize(width, headerHeight - 4)
            header.text:SetFontObject(Theme.Font(headerFont))
            header.text:SetTextColor(unpack(headerColor))
            header.text:SetText(L["CAT_" .. section.category] or section.category)
            header.line:SetColorTexture(headerColor[1], headerColor[2], headerColor[3], 0.25)
            header.chevron:SetShown(collapsible)
            if collapsible then
                header.chevron:SetIcon(section.collapsed and "chevronRight" or "chevronDown")
                header.chevron:SetColor("textMuted")
            end
            header:EnableMouse(collapsible)
            header:Show()
            y = y + headerHeight
        end

        if not section.collapsed then
            for rowIndex, stat in ipairs(section.stats) do
                local row = self:Row(stat)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", x, -y)
                row:SetSize(width, rowHeight)
                row.zebra:SetColorTexture(1, 1, 1, opt("layout.zebra") and rowIndex % 2 == 0 and 0.04 or 0)

                local iconShown = labels ~= "name" and (stat.icon or stat.atlas) ~= nil
                row.icon:SetShown(iconShown)
                row.icon:SetSize(rowHeight - 2, rowHeight - 2)
                if iconShown then
                    if stat.atlas then
                        row.icon:SetAtlas(stat.atlas)
                        row.icon:SetTexCoord(0, 1, 0, 1)
                    else
                        row.icon:SetTexture(stat.icon)
                        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    end
                end
                row.label:SetFontObject(Theme.Font(font))
                row.label:SetTextColor(unpack(labelColor))
                row.label:ClearAllPoints()
                row.label:SetPoint(
                    "LEFT",
                    iconShown and row.icon or row,
                    iconShown and "RIGHT" or "LEFT",
                    iconShown and 4 or 0,
                    0
                )
                row.label:SetShown(labels ~= "icon" or not iconShown)
                row.label:SetText(Values.Label(stat))

                row.value:SetFontObject(Theme.Font(font))
                row.value:ClearAllPoints()
                if alignRight then
                    row.value:SetJustifyH("RIGHT")
                    row.value:SetPoint("RIGHT", -2, 0)
                    row.label:SetPoint("RIGHT", row.value, "LEFT", -4, 0)
                else
                    row.value:SetJustifyH("LEFT")
                    local after = row.label:IsShown() and row.label or row.icon
                    row.value:SetPoint("LEFT", after, "RIGHT", 6, 0)
                    row.value:SetPoint("RIGHT", -2, 0)
                end
                row:Show()
                self.visible[#self.visible + 1] = stat.id
                y = y + rowHeight + rowGap
            end
        end
        heights[column] = y - top
    end

    local tallest = 0
    for i = 1, columns do
        tallest = math.max(tallest, heights[i])
    end
    local used = 0
    for i = 1, columns do
        if heights[i] > 0 then
            used = i
        end
    end
    used = math.max(1, used)
    frame:SetSize(pad * 2 + used * width + (used - 1) * pad, math.max(top + tallest + pad, self.minHeight or 0))
end

-- Painting -------------------------------------------------------------------------------------

function Panel:Paint(row)
    if not row then
        return
    end
    local stat = row.stat
    local result = self.results[stat.id]
    local value = row.value
    if not result then
        value:SetText("")
        return
    end
    if result.secret then
        local drawn = false
        if opt("values.secretMode") == "raw" and stat.raw then
            drawn = pcall(function()
                value:SetFormattedText(stat.raw(Values.S))
            end)
            if drawn then
                value:SetTextColor(unpack(Core.Hex(opt("text.valueColor"))))
            end
        end
        if not drawn then
            value:SetText(self.last[stat.id] or "-")
            value:SetTextColor(unpack(Core.Hex(opt("text.secretColor"))))
        end
        return
    end
    self.last[stat.id] = result.text
    value:SetText(result.text or "")
    local color = "text.valueColor"
    if opt("values.colorBuffs") and result.mood == "buff" then
        color = "text.buffColor"
    elseif opt("values.colorBuffs") and result.mood == "debuff" then
        color = "text.debuffColor"
    end
    value:SetTextColor(unpack(Core.Hex(opt(color))))
end

function Panel:BuildTooltip(Tooltip, row)
    if not opt("tooltips.enabled") then
        return
    end
    local stat = row.stat
    local result = self.results[stat.id]
    Tooltip:SetTitle(Values.Label(stat))
    if not result then
        Tooltip:AddLine(L.NO_VALUE, "textMuted")
    elseif result.secret then
        local raw = opt("values.secretMode") == "raw" and stat.raw ~= nil
        if not raw and self.last[stat.id] then
            Tooltip:AddLine(self.last[stat.id])
        end
        Tooltip:AddHint(raw and L.SECRET_RAW or L.SECRET)
    else
        Tooltip:AddLine(result.text or "")
        if opt("tooltips.detail") == "full" then
            for _, line in ipairs(result.lines or {}) do
                if type(line) == "table" then
                    Tooltip:AddDoubleLine(line[1], line[2])
                else
                    Tooltip:AddLine(line, "textMuted")
                end
            end
        end
    end
end

--- Shows or hides the panel (events follow).
function Panel:SetShown(shown)
    self:Create()
    self.frame:SetShown(shown)
end
