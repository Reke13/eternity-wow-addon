-- EternityUI_Stats panel settings: a modal window over the panel (its gear button, a right click
-- on its title or on the character window's button) to show more or fewer stats. A dimmed layer
-- covers the panel and takes its clicks and mouse wheel while it's open; a click on that layer
-- closes it. The categories are an accordion: each one has a check, icons to turn all its stats
-- on or off, and unfolds to a check per stat laid out across the whole width.
--
-- Category checks and the display checks are the module's options (the store); the stats the
-- player hides are saved for the account in EternityUIStatsDB.hidden.

---@type string, EternityUIStatsNamespace
local addonName, ns = ...
local E = EternityUI
local Widgets = E.Widgets
local W, Theme = ns.Ui.W, ns.Ui.Theme
local Skin = W.Skin
local Core, Values, Panel, L = ns.Core, ns.Values, ns.Panel, ns.L
local opt = Core.Opt

local MIN_WIDTH, MIN_HEIGHT = 300, 380
local ROW = 22
local STAT_WIDTH = 150
local ICON_ON = "Interface\\Buttons\\UI-CheckBox-Check"
local ICON_OFF = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"

-- The display checks: option path and label.
local DISPLAY = {
    { "categories.hideZero", "SET_HIDE_ZERO" },
    { "categories.byClass", "SET_BY_CLASS" },
    { "categories.hideIrrelevant", "SET_IRRELEVANT" },
    { "categories.accordion", "SET_ACCORDION" },
}

---@class EternityUIStatsSettings
---@field frame table?
---@field overlay table? dimmed layer over the panel
---@field rows table<string, table> pooled rows by key
---@field open table<string, boolean> categories unfolded in this window
---@field width number content width at the last layout
local Settings = { rows = {}, open = {}, width = MIN_WIDTH }
ns.Settings = Settings

local function setOption(path, value)
    E.store:Set(addonName, path, value)
end

-- The stats one category lists here: those this client and the options have.
local function statsOf(category)
    local list = {}
    for _, stat in ipairs(Values.Of(category)) do
        if not stat.applies or stat.applies() then
            list[#list + 1] = stat
        end
    end
    return list
end

-- Controls -------------------------------------------------------------------------------------

--- A themed check box: :SetChecked(value); clicking it calls onChange(value).
local function checkBox(parent, onChange)
    local box = CreateFrame("Button", nil, parent)
    box:SetSize(14, 14)
    box.shape = Skin.Shape(box, "small")
    box.mark = box:CreateTexture(nil, "OVERLAY")
    box.mark:SetPoint("CENTER", 1, 0)
    box.mark:SetSize(18, 18)
    box.mark:SetTexture(ICON_ON)
    box.mark:SetDesaturated(true)
    function box.SetChecked(self, value)
        self.checked = value and true or false
        self.shape:SetColors(self.checked and "accent" or "hover", self.checked and "accent" or "lineStrong")
        self.mark:SetShown(self.checked)
        local r, g, b = Theme.Color("onAccent")
        self.mark:SetVertexColor(r, g, b, 1)
    end
    box:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        onChange(self.checked)
    end)
    box:SetChecked(false)
    return box
end

--- A small icon button with a tooltip.
local function iconButton(parent, texture, title, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(16, 16)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexture(texture)
    button.icon:SetAlpha(0.8)
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", function(self)
        self.icon:SetAlpha(1)
    end)
    button:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(0.8)
    end)
    W.AttachTooltip(button, function(tooltip)
        tooltip:SetTitle(title)
    end, "TOP")
    return button
end

-- Rows -----------------------------------------------------------------------------------------

--- A check with its label (and the stat's icon); the whole row toggles it.
function Settings:Check(key)
    local row = self.rows[key]
    if row then
        return row
    end
    row = CreateFrame("Button", nil, self.scroll.child)
    row:SetHeight(ROW)
    row.kind = "check"
    row.check = checkBox(row, function(value)
        if row.onChange then
            row.onChange(value)
        end
    end)
    row.check:SetPoint("LEFT", 2, 0)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(14, 14)
    row.icon:SetPoint("LEFT", row.check, "RIGHT", 6, 0)
    row.label = W.Text(row, "", "caption", "text")
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.label:SetPoint("RIGHT", -2, 0)
    row:SetScript("OnClick", function()
        row.check:Click()
    end)
    self.rows[key] = row
    return row
end

--- A category of the accordion: chevron, check, name, and all on / all off icons.
function Settings:Category(category)
    local row = self.rows[category]
    if row then
        return row
    end
    row = CreateFrame("Button", nil, self.scroll.child)
    row:SetHeight(ROW + 2)
    row.kind = "category"
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.chevron = Skin.Icon(row, "chevronRight", 10)
    row.chevron:SetPoint("LEFT", 4, 0)
    row.chevron:SetWidth(12)
    row.check = checkBox(row, function(value)
        setOption("categories." .. category, value)
    end)
    row.check:SetPoint("LEFT", row.chevron, "RIGHT", 4, 0)
    row.label = W.Text(row, L["CAT_" .. category] or category, "small", "text")
    row.label:SetJustifyH("LEFT")
    row.label:SetPoint("LEFT", row.check, "RIGHT", 6, 0)
    row.off = iconButton(row, ICON_OFF, L.SET_NONE, function()
        self:SetAll(category, false)
    end)
    row.off:SetPoint("RIGHT", -6, 0)
    row.on = iconButton(row, ICON_ON, L.SET_ALL, function()
        self:SetAll(category, true)
    end)
    row.on:SetPoint("RIGHT", row.off, "LEFT", -6, 0)
    row.label:SetPoint("RIGHT", row.on, "LEFT", -6, 0)
    row:SetScript("OnClick", function()
        self.open[category] = not self.open[category] or nil
        self:Layout()
    end)
    row:SetScript("OnEnter", function()
        row.hover = true
        self:PaintCategory(row)
    end)
    row:SetScript("OnLeave", function()
        row.hover = nil
        self:PaintCategory(row)
    end)
    self.rows[category] = row
    return row
end

function Settings:PaintCategory(row)
    local accent = Core.Hex("@accent")
    row.bg:SetColorTexture(accent[1], accent[2], accent[3], row.hover and 0.16 or 0.08)
end

--- A section title with an accent line, optionally with all on / all off icons.
function Settings:Heading(key, text, withIcons)
    local row = self.rows[key]
    if not row then
        row = CreateFrame("Frame", nil, self.scroll.child)
        row:SetHeight(ROW + 4)
        row.kind = "heading"
        row.label = W.Text(row, text, "small", "muted")
        row.label:SetPoint("LEFT", 2, -2)
        row.line = row:CreateTexture(nil, "ARTWORK")
        row.line:SetHeight(1)
        row.line:SetPoint("BOTTOMLEFT", 0, 2)
        row.line:SetPoint("BOTTOMRIGHT", 0, 2)
        if withIcons then
            row.off = iconButton(row, ICON_OFF, L.SET_NONE_EVERY, function()
                self:SetAll(nil, false)
            end)
            row.off:SetPoint("RIGHT", -6, 0)
            row.on = iconButton(row, ICON_ON, L.SET_ALL_EVERY, function()
                self:SetAll(nil, true)
            end)
            row.on:SetPoint("RIGHT", row.off, "LEFT", -6, 0)
        end
        self.rows[key] = row
    end
    local accent = Core.Hex("@accent")
    row.line:SetColorTexture(accent[1], accent[2], accent[3], 0.35)
    return row
end

-- Window ---------------------------------------------------------------------------------------

function Settings:Create()
    if self.frame then
        return self.frame
    end
    local panel = Panel:Create()

    -- The dimmed layer: blocks the panel under it, a click closes the window.
    local overlay = CreateFrame("Frame", nil, panel)
    overlay:SetAllPoints(panel)
    overlay:SetFrameLevel(panel:GetFrameLevel() + 40)
    overlay:EnableMouse(true)
    overlay:EnableMouseWheel(true)
    overlay:SetScript("OnMouseWheel", function() end)
    overlay:SetScript("OnMouseDown", function()
        self:Hide()
    end)
    overlay.dim = overlay:CreateTexture(nil, "BACKGROUND")
    overlay.dim:SetAllPoints()
    overlay.dim:SetColorTexture(0, 0, 0, 0.6)
    overlay:Hide()
    self.overlay = overlay

    local frame = CreateFrame("Frame", "EternityUIStatsSettings", overlay)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function() end)
    frame:SetFrameLevel(overlay:GetFrameLevel() + 5)
    frame.shape = Skin.Shape(frame, "window")

    frame.title = W.Text(frame, L.SETTINGS, "heading", "text")
    frame.title:SetPoint("TOPLEFT", 14, -12)
    frame.close = W.IconButton(frame, {
        icon = "close",
        size = 20,
        onClick = function()
            self:Hide()
        end,
    })
    frame.close:SetPoint("TOPRIGHT", -8, -8)
    frame.hint = W.Text(frame, L.SETTINGS_HINT, "caption", "muted")
    frame.hint:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -4)
    frame.hint:SetPoint("RIGHT", -14, 0)
    frame.hint:SetJustifyH("LEFT")
    frame.hint:SetWordWrap(false)

    -- Buttons at the bottom, two by two across the width.
    local function button(text, onClick)
        local b = Widgets.Button(frame, text, "ghost", onClick)
        b:SetHeight(24)
        return b
    end
    local reset = button(L.SET_RESET_POSITION, function()
        Core.Account().position = nil
        ns.Character:Update()
    end)
    reset:SetPoint("BOTTOMLEFT", 12, 12)
    reset:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -3, 12)
    local autoSize = button(L.SET_AUTO_SIZE, function()
        Panel:SetSize(nil)
        self:Place()
    end)
    autoSize:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 3, 12)
    autoSize:SetPoint("BOTTOMRIGHT", -12, 12)
    local expand = button(L.SET_EXPAND, function()
        Panel:CollapseAll(false)
    end)
    expand:SetPoint("BOTTOMLEFT", reset, "TOPLEFT", 0, 6)
    expand:SetPoint("BOTTOMRIGHT", reset, "TOPRIGHT", 0, 6)
    local collapse = button(L.SET_COLLAPSE, function()
        Panel:CollapseAll(true)
    end)
    collapse:SetPoint("BOTTOMLEFT", autoSize, "TOPLEFT", 0, 6)
    collapse:SetPoint("BOTTOMRIGHT", autoSize, "TOPRIGHT", 0, 6)

    self.scroll = Widgets.Scroll(frame)
    self.scroll:SetPoint("TOPLEFT", 12, -50)
    self.scroll:SetPoint("BOTTOMRIGHT", collapse, "TOPRIGHT", 0, 10)

    W.Themed(frame, function()
        frame.shape:SetColors("window", "borderStrong", Theme.glass and "windowTop" or nil)
        if frame:IsShown() then
            self:Layout()
        end
    end)
    self.frame = frame
    return frame
end

--- Centered on the panel and as large as it (with a margin), never smaller than the minimum.
function Settings:Place()
    local frame = self.frame
    local width = math.max((Panel.width or 0) - 16, MIN_WIDTH)
    local height = math.max((Panel.height or 0) - 16, MIN_HEIGHT)
    frame:ClearAllPoints()
    frame:SetPoint("TOP", Panel.frame, "TOP", 0, -8)
    frame:SetSize(width, height)
    -- Scroll area: the window less its margins and the scroll thumb.
    self.width = width - 24 - 12
    self.scroll.child:SetWidth(self.width)
end

function Settings:Show()
    if not (Panel.frame and Panel.frame:IsShown()) then
        return
    end
    self:Create()
    self:Place()
    self.overlay:Show()
    self.frame:Show()
    self:Layout()
end

function Settings:Hide()
    if self.overlay then
        self.overlay:Hide()
    end
end

function Settings:Toggle()
    if self:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function Settings:IsShown()
    return self.overlay ~= nil and self.overlay:IsShown()
end

--- Repaints the checks when the options change elsewhere.
function Settings:Refresh()
    if self:IsShown() then
        self:Layout()
    end
end

--- Turns every stat of a category (nil: of every category) on or off. Turning on also turns
--- the category on, and with every category, what hides stats on its own.
function Settings:SetAll(category, on)
    local hidden = Core.Account().hidden
    for _, id in ipairs(Values.CATEGORIES) do
        if category == nil or id == category then
            for _, stat in ipairs(Values.Of(id)) do
                hidden[stat.id] = (not on) or nil
            end
            if on then
                setOption("categories." .. id, true)
            end
        end
    end
    if on and category == nil then
        setOption("categories.hideZero", false)
        setOption("categories.hideIrrelevant", false)
    end
    Panel:Refresh(true)
    self:Layout()
end

--- Lays checks out in a grid across the width from y; returns the y under them.
local function grid(rows, y, width, columns, indent)
    local cellWidth = (width - indent) / columns
    for index, row in ipairs(rows) do
        local column = (index - 1) % columns
        local line = math.floor((index - 1) / columns)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", indent + column * cellWidth, -(y + line * ROW))
        row:SetWidth(cellWidth - 4)
        row:Show()
    end
    return y + math.ceil(#rows / columns) * ROW
end

function Settings:Layout()
    if not self.frame then
        return
    end
    for _, row in pairs(self.rows) do
        row:Hide()
    end
    local width = self.width
    local y = 0
    local function full(row)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetWidth(width)
        row:Show()
        y = y + row:GetHeight()
    end

    full(self:Heading("@display", L.SET_DISPLAY))
    local checks = {}
    for _, entry in ipairs(DISPLAY) do
        local path, text = entry[1], entry[2]
        local row = self:Check("@" .. path)
        row.icon:Hide()
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row.check, "RIGHT", 6, 0)
        row.label:SetPoint("RIGHT", -2, 0)
        row.label:SetText(L[text])
        row.label:SetAlpha(1)
        row.check:SetChecked(opt(path) == true)
        row.onChange = function(value)
            setOption(path, value)
        end
        checks[#checks + 1] = row
    end
    y = grid(checks, y, width, width >= 380 and 2 or 1, 0) + 8

    full(self:Heading("@stats", L.SET_STATS, true))
    y = y + 2
    local columns = math.max(1, math.floor((width - 20) / STAT_WIDTH))
    for _, category in ipairs(Values.CATEGORIES) do
        local stats = statsOf(category)
        if #stats > 0 then
            local row = self:Category(category)
            local enabled = opt("categories." .. category) == true
            row.check:SetChecked(enabled)
            row.chevron:SetIcon(self.open[category] and "chevronDown" or "chevronRight")
            row.chevron:SetColor("textMuted")
            self:PaintCategory(row)
            full(row)
            y = y + 2
            if self.open[category] then
                local statRows = {}
                for _, stat in ipairs(stats) do
                    local statRow = self:Check("stat:" .. stat.id)
                    local hasIcon = (stat.icon or stat.atlas) ~= nil
                    statRow.icon:SetShown(hasIcon)
                    if stat.atlas then
                        statRow.icon:SetAtlas(stat.atlas)
                        statRow.icon:SetTexCoord(0, 1, 0, 1)
                    elseif stat.icon then
                        statRow.icon:SetTexture(stat.icon)
                        statRow.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    end
                    statRow.label:ClearAllPoints()
                    statRow.label:SetPoint("LEFT", hasIcon and statRow.icon or statRow.check, "RIGHT", 6, 0)
                    statRow.label:SetPoint("RIGHT", -2, 0)
                    statRow.label:SetText(Values.Label(stat))
                    statRow.label:SetAlpha(enabled and 1 or 0.5)
                    statRow.check:SetChecked(not Core.StatHidden(stat.id))
                    statRow.onChange = function(value)
                        Core.SetStatHidden(stat.id, not value)
                        Panel:Refresh(true)
                    end
                    statRows[#statRows + 1] = statRow
                end
                y = grid(statRows, y, width, columns, 20) + 6
            end
        end
    end
    self.scroll:SetContentHeight(y)
end
