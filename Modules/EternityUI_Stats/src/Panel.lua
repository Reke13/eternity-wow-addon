-- EternityUI_Stats panel: the frame with a title bar, a collapsible section per category and a
-- row per stat. Values are read only while it's shown (events registered then, coalesced to one
-- refresh per 0.1 s); a refresh only repaints texts unless the set of visible rows changed.
-- Columns have a fixed width, so no secret text is ever measured.
--
-- In and out of combat the panel shows the same rows with the same texts: a stat the game hides
-- keeps the visibility of its last plain read, and is drawn from the game's values in the same
-- format (Values' raw readers) or, when that can't be done without math, with its last text.
--
-- The panel is dragged by its title bar. Dragging follows the cursor and never reads the panel's
-- geometry while moving (it can be secret once the rows show secret values); the spot is saved
-- for the account, in UIParent's units.
--
-- The grip in the bottom right corner resizes it: the columns then fit the width and the rows
-- scroll (mouse wheel) when they're taller than the panel. The size is saved for the account, in
-- the panel's own units. Scrolling uses the heights Layout computed, never the frames' geometry.

---@type string, EternityUIStatsNamespace
local _, ns = ...
local E = EternityUI
local W, Theme = ns.Ui.W, ns.Ui.Theme
local Skin = W.Skin
local Core, Values, L = ns.Core, ns.Values, ns.L
local opt = Core.Opt

local GEAR = "Interface\\Buttons\\UI-OptionsButton"

-- Beside the row, or at the cursor.
local function tooltipAnchor()
    if opt("tooltips.anchor") == "cursor" then
        return "CURSOR"
    end
    return opt("window.side") == "left" and "LEFT" or "RIGHT"
end

---@class EternityUIStatsPanel
---@field frame table?
---@field bar table? title bar: drag handle, title and settings button
---@field rows table<string, table> row frame per stat id
---@field sections table<string, table> header per category
---@field results table<string, EternityStatResult|false> last read per stat id (false = doesn't apply)
---@field last table<string, EternityStatResult> last plain result per stat id (drawn while secret)
---@field known table<string, boolean> visibility of each stat at its last plain read
---@field visible string[] stat ids drawn now, in order
---@field signature string? visible rows and collapsed sections at the last layout
---@field minHeight number? set by Character.lua with panel.matchHeight
---@field drag table? the drag in progress
---@field sizing table? the resize in progress
---@field scroll table? scroll frame holding the content
---@field content table? parent of the headers and rows
---@field offset number scroll offset
---@field width number? panel width at the last layout
---@field height number? panel height at the last layout
---@field contentHeight number height of the rows at the last layout
---@field viewHeight number height they have to show in
---@field sectionsLaid table[]? sections of the last layout (laid out again while resizing)
local Panel = {
    rows = {},
    sections = {},
    results = {},
    last = {},
    known = {},
    visible = {},
    offset = 0,
    contentHeight = 0,
    viewHeight = 0,
}
local MIN_HEIGHT = 120
local GRIP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-"
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

local function pack(...)
    return { n = select("#", ...), ... }
end

local function inCombat()
    return InCombatLockdown ~= nil and InCombatLockdown() == true
end

--- The cursor in UIParent's units.
local function cursor()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    return x / scale, y / scale
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
    frame:EnableMouse(true)
    frame:Hide()
    frame.shape = Skin.Shape(frame, "window")
    self.frame = frame
    self:CreateBar()
    self:CreateScroll()
    self:CreateGrip()

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
        self:StopDrag(true)
        self:StopResize()
        E.Widgets.HideTooltip()
        if ns.Settings then
            ns.Settings:Hide()
        end
    end)
    W.Themed(frame, function()
        self.signature = nil
        if frame:IsShown() then
            self:Refresh(true)
        end
    end)
    return frame
end

--- The title bar: drag handle, title and the settings button.
function Panel:CreateBar()
    local bar = CreateFrame("Button", nil, self.frame)
    bar:RegisterForDrag("LeftButton")
    bar:RegisterForClicks("RightButtonUp")
    bar.title = newText(bar, "LEFT")
    bar.title:SetPoint("LEFT")
    bar:SetScript("OnDragStart", function()
        self:StartDrag()
    end)
    bar:SetScript("OnDragStop", function()
        self:StopDrag()
    end)
    bar:SetScript("OnClick", function()
        ns.Settings:Toggle()
    end)
    W.AttachTooltip(bar, function(tooltip)
        tooltip:SetTitle(L.TITLE)
        if ns.Character:CanDrag() then
            tooltip:AddHint(L.DRAG_HINT)
        end
    end, "TOP")

    local gear = CreateFrame("Button", nil, bar)
    gear:SetSize(16, 16)
    gear:SetPoint("RIGHT")
    gear.icon = gear:CreateTexture(nil, "ARTWORK")
    gear.icon:SetAllPoints()
    gear.icon:SetTexture(GEAR)
    gear.icon:SetVertexColor(0.85, 0.85, 0.85, 1)
    gear:SetScript("OnClick", function()
        ns.Settings:Toggle()
    end)
    gear:SetScript("OnEnter", function(button)
        button.icon:SetVertexColor(1, 1, 1, 1)
    end)
    gear:SetScript("OnLeave", function(button)
        button.icon:SetVertexColor(0.85, 0.85, 0.85, 1)
    end)
    W.AttachTooltip(gear, function(tooltip)
        tooltip:SetTitle(L.SETTINGS)
        tooltip:AddHint(L.SETTINGS_HINT)
    end, "TOP")
    bar.gear = gear
    bar.title:SetPoint("RIGHT", gear, "LEFT", -4, 0)
    self.bar = bar
end

--- The scrolling area for the headers and rows, with a thin thumb.
function Panel:CreateScroll()
    local scroll = CreateFrame("ScrollFrame", nil, self.frame)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        self:ScrollTo(self.offset - delta * 40)
    end)
    self.thumb = scroll:CreateTexture(nil, "OVERLAY")
    self.thumb:SetWidth(3)
    self.thumb:Hide()
    self.scroll, self.content = scroll, content
end

--- Scrolls the rows to an offset, within what they overflow.
function Panel:ScrollTo(offset)
    local range = math.max(0, self.contentHeight - self.viewHeight)
    self.offset = math.max(0, math.min(offset or 0, range))
    self.scroll:SetVerticalScroll(self.offset)
    local thumb = self.thumb
    thumb:SetShown(range > 0)
    if range > 0 then
        local size = math.max(self.viewHeight * self.viewHeight / self.contentHeight, 20)
        local color = Core.Hex("@lineStrong")
        thumb:SetColorTexture(color[1], color[2], color[3], math.max(color[4] or 1, 0.5))
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", self.scroll, "TOPRIGHT", 0, -(self.viewHeight - size) * self.offset / range)
        thumb:SetHeight(size)
    end
end

--- The grip in the bottom right corner: drag to resize, right-click for the automatic size.
function Panel:CreateGrip()
    local grip = CreateFrame("Button", nil, self.frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(self.frame:GetFrameLevel() + 20)
    grip:SetNormalTexture(GRIP .. "Up")
    grip:SetPushedTexture(GRIP .. "Down")
    grip:SetHighlightTexture(GRIP .. "Highlight")
    grip:RegisterForClicks("RightButtonUp")
    grip:SetScript("OnMouseDown", function(_, mouse)
        if mouse == "LeftButton" then
            self:StartResize()
        end
    end)
    grip:SetScript("OnMouseUp", function(_, mouse)
        if mouse == "LeftButton" then
            self:StopResize(true)
        end
    end)
    grip:SetScript("OnClick", function()
        self:SetSize(nil)
    end)
    W.AttachTooltip(grip, function(tooltip)
        tooltip:SetTitle(L.RESIZE)
        tooltip:AddHint(L.RESIZE_HINT)
    end, "BOTTOM")
    self.grip = grip
end

--- Saves a size ({ w, h } in the panel's units) or nil for the automatic one, and lays out.
function Panel:SetSize(size)
    Core.Account().size = size
    if self.frame and self.frame:IsShown() then
        self:Refresh(true)
    end
end

function Panel:StartResize()
    if self.sizing or not self.width then
        return
    end
    local cx, cy = cursor()
    self.sizing = { w = self.width, h = self.height, cx = cx, cy = cy }
    self.grip:SetScript("OnUpdate", function()
        self:ResizeUpdate()
    end)
end

function Panel:ResizeUpdate()
    local sizing = self.sizing
    if not sizing then
        return
    end
    local cx, cy = cursor()
    local scale = self.frame:GetScale()
    scale = (type(scale) == "number" and not Core.Secret(scale) and scale > 0) and scale or 1
    local w = math.floor(sizing.w + (cx - sizing.cx) / scale + 0.5)
    local h = math.floor(sizing.h - (cy - sizing.cy) / scale + 0.5)
    local current = Core.Account().size
    if current and current.w == w and current.h == h then
        return
    end
    Core.Account().size = { w = w, h = h }
    self:Layout(self.sectionsLaid)
end

--- Ends a resize; save: keep the size (its minimum, as laid out).
function Panel:StopResize(save)
    if not self.sizing then
        return
    end
    if save then
        self:ResizeUpdate()
    end
    self.sizing = nil
    self.grip:SetScript("OnUpdate", nil)
    if save then
        if Core.Account().size then
            Core.Account().size = { w = self.width, h = self.height }
        end
        self:Refresh(true)
    end
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

-- Position and dragging ------------------------------------------------------------------------

--- Keeps a top left corner (UIParent units) where the title bar can still be grabbed.
local function clamp(x, y)
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if Core.Secret(width) or Core.Secret(height) then
        return x, y
    end
    return math.max(-100, math.min(x, width - 40)), math.max(24, math.min(y, height))
end

--- The panel's top left corner in UIParent's units: the saved spot, or where it is now (nil if
--- the game hides its geometry).
function Panel:Origin()
    local saved = Core.Account().position
    if saved then
        return saved.x, saved.y
    end
    local frame = self.frame
    local ok, left, top = pcall(function()
        return frame:GetLeft(), frame:GetTop()
    end)
    if not ok or Core.Secret(left) or Core.Secret(top) or type(left) ~= "number" or type(top) ~= "number" then
        return nil
    end
    local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return left * ratio, top * ratio
end

--- Puts the panel's top left corner at x, y (UIParent units), whatever its scale.
function Panel:PlaceAt(x, y)
    local frame = self:Create()
    local scale = frame:GetScale()
    scale = (type(scale) == "number" and not Core.Secret(scale) and scale > 0) and scale or 1
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
end

function Panel:StartDrag()
    if self.drag or not ns.Character:CanDrag() then
        return
    end
    local x, y = self:Origin()
    if not x then
        return
    end
    local cx, cy = cursor()
    self.drag = { x = x, y = y, cx = cx, cy = cy }
    self.bar:SetScript("OnUpdate", function()
        self:DragUpdate()
    end)
end

function Panel:DragUpdate()
    local drag = self.drag
    if not drag then
        return
    end
    local cx, cy = cursor()
    drag.nx, drag.ny = clamp(drag.x + cx - drag.cx, drag.y + cy - drag.cy)
    self:PlaceAt(drag.nx, drag.ny)
end

--- Ends a drag and saves the spot (cancel: back to where it was).
function Panel:StopDrag(cancel)
    local drag = self.drag
    if not drag then
        return
    end
    if not cancel then
        self:DragUpdate()
        if drag.nx then
            Core.Account().position = { x = drag.nx, y = drag.ny }
        end
    end
    self.drag = nil
    self.bar:SetScript("OnUpdate", nil)
    ns.Character:Update()
end

-- Rows and headers -----------------------------------------------------------------------------

function Panel:Section(category)
    local header = self.sections[category]
    if header then
        return header
    end
    header = CreateFrame("Button", nil, self.content)
    header.category = category
    header.bg = header:CreateTexture(nil, "BACKGROUND")
    header.bg:SetAllPoints()
    header.chevron = Skin.Icon(header, "chevronDown", 10)
    header.chevron:SetPoint("LEFT", 4, 0)
    header.chevron:SetWidth(12)
    header.text = newText(header, "LEFT")
    header.line = header:CreateTexture(nil, "ARTWORK")
    header.line:SetHeight(1)
    header.line:SetPoint("BOTTOMLEFT")
    header.line:SetPoint("BOTTOMRIGHT")
    header:SetScript("OnClick", function(button)
        self:ToggleSection(button.category)
    end)
    header:SetScript("OnEnter", function(button)
        button.hover = true
        self:PaintHeader(button)
    end)
    header:SetScript("OnLeave", function(button)
        button.hover = nil
        self:PaintHeader(button)
    end)
    self.sections[category] = header
    return header
end

function Panel:PaintHeader(header)
    local color = Core.Hex(opt("text.headerColor"))
    header.bg:SetColorTexture(color[1], color[2], color[3], header.hover and 0.16 or 0.07)
    header.line:SetColorTexture(color[1], color[2], color[3], 0.25)
end

--- Folds or unfolds a section (with categories.accordion, opening one folds the others).
function Panel:ToggleSection(category)
    if not opt("categories.collapsible") then
        return
    end
    local collapsed = Core.Char().collapsed
    local opening = collapsed[category] == true
    collapsed[category] = (not opening) or nil
    if opening and opt("categories.accordion") then
        for _, id in ipairs(Values.CATEGORIES) do
            if id ~= category then
                collapsed[id] = true
            end
        end
    end
    self:Refresh(true)
end

--- Folds (true) or unfolds (false) every section.
function Panel:CollapseAll(folded)
    local collapsed = Core.Char().collapsed
    for _, id in ipairs(Values.CATEGORIES) do
        collapsed[id] = folded or nil
    end
    if self.frame and self.frame:IsShown() then
        self:Refresh(true)
    end
end

function Panel:Row(stat)
    local row = self.rows[stat.id]
    if row then
        return row
    end
    row = CreateFrame("Frame", nil, self.content)
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
    return not (opt("categories.hideZero") and result.zero)
end

--- Reads one stat and returns whether its row shows. While the game hides values, a stat that
--- read fine before stays a secret result instead of vanishing, and keeps the visibility its
--- last plain read gave it: the rows don't change when combat starts or ends.
function Panel:ReadStat(stat)
    local result = Values.Read(stat)
    local applies = not stat.applies or stat.applies()
    if result == nil and applies and self.last[stat.id] and inCombat() then
        result = { secret = true }
    end
    local visible
    if result and result.secret then
        visible = self.known[stat.id] ~= false
    else
        visible = shows(result)
        self.known[stat.id] = visible
        if result then
            self.last[stat.id] = result
        end
    end
    self.results[stat.id] = result or false
    return visible
end

--- Reads every stat of the shown categories; returns the sections with their visible stats.
function Panel:Read()
    local sections = {}
    local collapsed = Core.Char().collapsed
    local parts = {}
    for _, category in ipairs(Values.Categories()) do
        local list = {}
        for _, stat in ipairs(Values.Of(category)) do
            if Core.StatHidden(stat.id) then
                self.results[stat.id] = false
            elseif self:ReadStat(stat) then
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
    -- A size the player gave it: as many columns as fit, widened to fill it.
    local size = Core.Account().size
    if size then
        size = { w = math.max(size.w, width + pad * 2), h = math.max(size.h, MIN_HEIGHT) }
        columns = math.max(1, math.floor((size.w - pad) / (width + pad)))
        width = math.floor((size.w - pad * (columns + 1)) / columns)
    end
    self.sectionsLaid = sections
    local font, headerFont = opt("text.font"), opt("text.headerFont")
    local rowHeight = fontSize(font) + 4
    local rowGap = opt("layout.rowSpacing")
    local sectionGap = opt("layout.sectionSpacing")
    local headers = opt("layout.headers")
    local headerHeight = headers and fontSize(headerFont) + 10 or 0
    local labels = opt("layout.labels")
    local alignRight = opt("layout.valueAlign") ~= "left"
    local collapsible = opt("categories.collapsible") and headers

    -- Window look on top of the theme.
    frame:SetScale(opt("window.scale"))
    local background = opt("window.background")
    frame.shape:SetColors("window", Theme.glass and "borderStrong" or "border", Theme.glass and "windowTop" or nil)
    frame.shape:SetAlpha(background and (Theme.opacity or 1) * opt("window.opacity") or 0)

    -- Title bar: always there (it's the drag handle and holds the settings button).
    local bar = self.bar
    local showTitle = opt("window.title")
    local barHeight = showTitle and math.max(18, fontSize("heading") + 4) or 18
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", pad, -pad + 2)
    bar:SetPoint("TOPRIGHT", -pad + 2, -pad + 2)
    bar:SetHeight(barHeight)
    bar.title:SetShown(showTitle)
    if showTitle then
        bar.title:SetFontObject(Theme.Font("heading"))
        bar.title:SetTextColor(Theme.Color("text"))
        bar.title:SetText(L.TITLE)
    end
    local top = pad + barHeight + Theme.space.xs

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
        local gap = section.collapsed and math.min(sectionGap, 4) or sectionGap
        local y = heights[column] + (heights[column] > 0 and gap or 0)

        if headers then
            local header = self:Section(section.category)
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", x, -y)
            header:SetSize(width, headerHeight - 2)
            header.text:SetFontObject(Theme.Font(headerFont))
            header.text:SetTextColor(unpack(headerColor))
            header.text:SetText(L["CAT_" .. section.category] or section.category)
            self:PaintHeader(header)
            header.chevron:SetShown(collapsible)
            if collapsible then
                header.chevron:SetIcon(section.collapsed and "chevronRight" or "chevronDown")
                header.chevron:SetColor("textMuted")
            end
            header.text:ClearAllPoints()
            if collapsible then
                header.text:SetPoint("LEFT", header.chevron, "RIGHT", 4, 0)
            else
                header.text:SetPoint("LEFT", 4, 0)
            end
            header.text:SetPoint("RIGHT", -4, 0)
            header:EnableMouse(collapsible)
            header:Show()
            y = y + headerHeight + 2
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
        heights[column] = y
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
    local frameWidth, frameHeight
    if size then
        frameWidth, frameHeight = size.w, size.h
    else
        frameWidth = pad * 2 + used * width + (used - 1) * pad
        frameHeight = math.max(top + tallest + pad, self.minHeight or 0)
    end
    frame:SetSize(frameWidth, frameHeight)
    self.width, self.height = frameWidth, frameHeight

    -- The rows scroll inside what's left under the title bar; the grip keeps its corner free.
    local bottom = size and math.max(pad, 18) or pad
    self.scroll:ClearAllPoints()
    self.scroll:SetPoint("TOPLEFT", 0, -top)
    self.scroll:SetPoint("TOPRIGHT", -2, -top)
    self.scroll:SetHeight(math.max(1, frameHeight - top - bottom))
    self.content:SetSize(frameWidth, math.max(1, tallest))
    self.contentHeight = tallest
    self.viewHeight = math.max(1, frameHeight - top - bottom)
    self:ScrollTo(self.offset)
end

-- Painting -------------------------------------------------------------------------------------

local function moodColor(result)
    if opt("values.colorBuffs") and result and result.mood == "buff" then
        return "text.buffColor"
    elseif opt("values.colorBuffs") and result and result.mood == "debuff" then
        return "text.debuffColor"
    end
    return "text.valueColor"
end

--- Draws a stat the game hides: from its values in the full format when the raw reader can,
--- else its last text. Returns whether the live values were drawn.
function Panel:PaintSecret(row)
    local stat, value = row.stat, row.value
    local known = self.last[stat.id]
    local live = false
    if opt("values.secretMode") ~= "last" and stat.raw then
        live = pcall(function()
            local args = pack(stat.raw(Values.S))
            if type(args[1]) ~= "string" then
                error("no raw text", 0)
            end
            value:SetFormattedText(unpack(args, 1, args.n))
        end)
    end
    if not live then
        value:SetText(known and known.text or "-")
    end
    local color = opt("values.greySecret") and "text.secretColor" or moodColor(known)
    value:SetTextColor(unpack(Core.Hex(opt(color))))
    return live
end

function Panel:Paint(row)
    if not row then
        return
    end
    local result = self.results[row.stat.id]
    local value = row.value
    if not result then
        value:SetText("")
        return
    end
    if result.secret then
        self:PaintSecret(row)
        return
    end
    value:SetText(result.text or "")
    value:SetTextColor(unpack(Core.Hex(opt(moodColor(result)))))
end

local function addLines(Tooltip, result)
    for _, line in ipairs(result.lines or {}) do
        if type(line) == "table" then
            Tooltip:AddDoubleLine(line[1], line[2])
        else
            Tooltip:AddLine(line, "textMuted")
        end
    end
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
        local known = self.last[stat.id]
        if known then
            Tooltip:AddLine(known.text or "")
            if opt("tooltips.detail") == "full" then
                addLines(Tooltip, known)
            end
        end
        local raw = opt("values.secretMode") ~= "last" and stat.raw ~= nil
        Tooltip:AddHint(raw and L.SECRET_RAW or L.SECRET)
    else
        Tooltip:AddLine(result.text or "")
        if opt("tooltips.detail") == "full" then
            addLines(Tooltip, result)
        end
    end
end

--- Shows or hides the panel (events follow).
function Panel:SetShown(shown)
    self:Create()
    self.frame:SetShown(shown)
end
