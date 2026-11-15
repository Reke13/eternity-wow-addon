-- The V2 layout of a module's option lists (general.optionsVersion = "v2"), from the same schema
-- as V1: each section is a card with its title, how many of its options changed and a button that
-- resets them. Options go two per line in columns with a line between them: a switch beside its
-- label, any other control under it, as wide as the column; an option shown only for another one's
-- value (visibleWhen on a path of the same card) is indented under it. A changed option has a thin
-- accent border inside its field (the shape's own border: no room taken) and a reset button before
-- its control. Items keep V1's fields (row, path, y), so the
-- search reveals them the same way. At the Basic level (general.optionsLevel) the options a schema
-- marks `advanced` (on the option or its group) hide, unless changed; a card says how many.
---@type string, table
local _, ns = ...
local L = ns.L
local E = EternityUI
local Shape = E.Shape
local Theme = E.Theme
local Widgets = E.Widgets

local ListV2 = {}
ns.ListV2 = ListV2

local PAD = 16 -- inside a card
local HEADER = 46 -- the card's title line
-- Each option is a field: a block in a lighter tone (general.optionsFieldShade) with its label and
-- control inside. Vertical rhythm: a field is one of two heights, with the same gap between lines.
local FIELD_X = 12 -- inside a field, left of the control's end and right of it
local CELL = 40 -- a field with its label and control on one line
local STACK_TOP = 8 -- a stacked field (a dropdown or text box): its label on top...
local STACK_LABEL = 18
local STACK_CONTROL = 30 -- ...and the control's slot under it, as wide as the field
local STACK = STACK_TOP + STACK_LABEL + 6 + STACK_CONTROL + 8
local LINE_GAP = 8 -- between two lines of fields
local INDENT = 22 -- an option that depends on another
local COLUMN_GAP = 24
local CARD_GAP = 14
local LABEL_X = 12 -- the label in its field, as far in as the control's end
local RANGE_SHARE = 0.48 -- an inline slider takes about this much of its field
local SLIDER_READOUT = 60 -- a slider's room for its value on the right
local RESET_ICON = "Interface\\Buttons\\UI-RefreshButton"
local CONFIRM_SECONDS = 3
local LEVEL_BAR = 44 -- the Basic / Advanced choice above the cards
local MORE = 34 -- a card's "Show N more" line
local CORE = "EternityUI"
local newChevron -- below
local TAB_HEIGHT = 38 -- a page tab, above the line under them all
local DIVIDER_INSET = 2 -- the line between two columns stops short of their top and bottom
local CHEVRON = 14 -- the fold mark's box

-- Folded cards, for the whole account like the Mover's sections: raw.optionsCollapsed[key] = true.
-- A card's key is its module and its first option's path, which don't depend on the language.
local function isCollapsed(key)
    local folded = E.store.raw.optionsCollapsed
    return type(folded) == "table" and folded[key] == true
end

local function setCollapsed(key, value)
    local folded = E.store.raw.optionsCollapsed
    if type(folded) ~= "table" then
        folded = {}
        E.store.raw.optionsCollapsed = folded
    end
    folded[key] = value or nil
end

local function level()
    return E.store:Get(CORE, "general.optionsLevel")
end

local function showAdvanced()
    E.store:Set(CORE, "general.optionsLevel", "advanced")
end

-- The default as the player reads it (for an inheriting option, what it inherits now).
local function defaultText(option, value)
    if option.type == "toggle" then
        return value and L.V2_ON or L.V2_OFF
    elseif option.type == "select" then
        for _, entry in ipairs(option.values) do
            if entry.value == value then
                return E.Localize(entry.label)
            end
        end
    elseif option.type == "range" then
        return ns.ModulePage.Format(option)(value)
    end
    if value == nil or value == "" then
        return L.V2_EMPTY
    end
    return tostring(value)
end

--- Whether the profile stores a value of its own for the option (the store keeps none when it's
--- the default).
---@param module string
---@param path string
---@return boolean
function ListV2.IsChanged(module, path)
    local values = E.store:GetProfile().values[module]
    return values ~= nil and values[path] ~= nil
end

local function resetButton(parent, module, path, option, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(20, 20)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexture(RESET_ICON)
    button.icon:SetDesaturated(true)
    function button:Paint()
        local color = self:IsMouseOver() and Theme.colors.text or Theme.colors.textMuted
        self.icon:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    end
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", button.Paint)
    button:SetScript("OnLeave", button.Paint)
    Widgets.AttachTooltip(button, function(tip)
        tip:SetTitle(L.V2_RESET)
        tip:AddLine(L.V2_DEFAULT:format(defaultText(option, E.store:GetDefault(module, path))), "textMuted")
    end)
    return Widgets.Track(button)
end

-- The paths an option's visibility depends on.
local function dependsOn(option, paths)
    for path in pairs(option.visibleWhen or {}) do
        if paths[path] then
            return true
        end
    end
    return false
end

local function newRow(card, page, entry, makeControl, indented)
    local option, path = entry.option, entry.path
    local module = page.module.name
    local row = CreateFrame("Frame", nil, card)
    local item = {
        row = row,
        path = path,
        option = option,
        card = card,
        -- A switch, slider or color sits beside its label; a dropdown or text box goes under it.
        kind = (option.type == "select" or option.type == "text") and "stacked" or "inline",
        indented = indented,
        advanced = entry.advanced,
    }
    local stacked = item.kind == "stacked"
    row:SetHeight(stacked and STACK or CELL)

    -- The field's block, and for an indented option a line down its left joining it to the one it
    -- depends on.
    row.field = Shape.New(row)
    local guide
    if indented then
        guide = row:CreateTexture(nil, "ARTWORK")
        guide:SetPoint("TOPLEFT", -INDENT + 8, 0)
        guide:SetPoint("BOTTOMLEFT", -INDENT + 8, 0)
        guide:SetWidth(E.Pixel.Size(row) * 2)
    end
    function row:Paint()
        local tone = Theme.colors.text
        local shade = E.store:Get(CORE, "general.optionsFieldShade") or 0
        -- Changed: a thin border in the theme's accent, drawn inside the field.
        local border = self.changed and Theme.accent or nil
        Shape.Paint(self.field, math.min(Theme.radius, 6), { tone[1], tone[2], tone[3], shade }, border)
        if guide then
            local c = Theme.colors.line
            guide:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        end
    end
    Widgets.Track(row)

    row.label = Widgets.Text(row, 14, "text")
    if stacked then
        row.label:SetPoint("TOPLEFT", LABEL_X, -STACK_TOP)
        row.label:SetHeight(STACK_LABEL)
    else
        row.label:SetPoint("LEFT", LABEL_X, 0)
    end
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.label:SetText(E.Localize(option.label))

    -- The "i" with the description, and the /reload badge, after the label.
    local after = row.label
    local description = option.description and E.Localize(option.description)
    if description and description ~= "" then
        row.info = Widgets.Info(row, E.Localize(option.label), description)
        row.info:SetPoint("LEFT", row.label, "RIGHT", 6, 0)
        after = row.info
    end
    if option.requiresReload then
        row.reload = Widgets.Text(row, 12, Theme.colors.warning)
        row.reload:SetText(L.V2_RELOAD)
        row.reload:SetPoint("LEFT", after, "RIGHT", 8, 0)
    end

    item.control = makeControl(row, page, entry)
    item.control:SetParent(row)
    item.control:ClearAllPoints()
    item.reset = resetButton(row, module, path, option, function()
        E.store:Set(module, path, E.store:GetDefault(module, path))
        page.Refresh()
    end)
    if stacked then
        item.control:SetPoint("LEFT", row, "TOPLEFT", LABEL_X, -(STACK_TOP + STACK_LABEL + 6 + STACK_CONTROL / 2))
        item.reset:SetPoint("RIGHT", row, "TOPRIGHT", -FIELD_X + 2, -(STACK_TOP + STACK_LABEL / 2))
    else
        item.control:SetPoint("RIGHT", -FIELD_X, 0)
        item.reset:SetPoint("RIGHT", item.control, "LEFT", -10, 0)
    end
    return item
end

-- The fold mark: a thin chevron of two bars, pointing down when open and right when folded; muted,
-- lit while the title line is under the mouse.
local CHEVRON_BARS = {
    open = { { -2.5, 1, -45 }, { 2.5, 1, 45 } },
    closed = { { 1, 2.5, -45 }, { 1, -2.5, 45 } },
}

function newChevron(parent)
    local mark = CreateFrame("Frame", nil, parent)
    mark:SetSize(CHEVRON, CHEVRON)
    mark.bars = {}
    for i = 1, 2 do
        local bar = mark:CreateTexture(nil, "ARTWORK")
        bar:SetTexture("Interface\\Buttons\\WHITE8X8")
        bar:SetSize(8, 2)
        mark.bars[i] = bar
    end
    function mark:SetOpen(open)
        self.open = open
        for i, spec in ipairs(CHEVRON_BARS[open and "open" or "closed"]) do
            local bar = self.bars[i]
            bar:ClearAllPoints()
            bar:SetPoint("CENTER", spec[1], spec[2])
            bar:SetRotation(math.rad(spec[3]))
        end
        self:Paint()
    end
    function mark:Paint()
        local c = parent:IsMouseOver() and Theme.colors.text or Theme.colors.textMuted
        for _, bar in ipairs(self.bars) do
            bar:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
        end
    end
    mark:SetOpen(true)
    return Widgets.Track(mark)
end

local function newCard(child, page, section, list, makeControl)
    local card = CreateFrame("Frame", nil, child)
    card.shape = Shape.New(card)
    card.dividers = {} -- the lines between two columns, made as Layout needs them
    function card:Paint()
        Shape.Paint(self.shape, math.min(Theme.radius, 10), Theme.colors.surface, Theme.colors.line)
        local c = Theme.colors.line
        for _, divider in ipairs(self.dividers) do
            divider:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        end
    end
    Widgets.Track(card)

    card.key = page.module.name .. ":" .. (section.entries[1] and section.entries[1].path or "")

    -- The title line folds the card: a click anywhere on it (the reset button keeps its own).
    card.header = CreateFrame("Button", nil, card)
    card.header:SetPoint("TOPLEFT")
    card.header:SetPoint("TOPRIGHT")
    card.header:SetHeight(HEADER)
    card.header:SetScript("OnClick", function()
        setCollapsed(card.key, not isCollapsed(card.key))
        page.Refresh()
    end)
    card.fold = newChevron(card.header)
    card.fold:SetPoint("RIGHT", card.header, "RIGHT", -PAD, 0)
    card.header:SetScript("OnEnter", function()
        card.fold:Paint()
    end)
    card.header:SetScript("OnLeave", function()
        card.fold:Paint()
    end)

    -- Bold: there's no bold font file. The title is drawn twice, the copy a little to the right, and
    -- each one's shadow (in its own color, to the right) thickens it.
    card.title = Widgets.Text(card, 17, "text")
    card.title:SetPoint("LEFT", card.header, "LEFT", PAD, 0)
    card.title:SetText(E.Localize(section.label))
    card.titleCopy = Widgets.Text(card, 17, "text")
    card.titleCopy:SetPoint("TOPLEFT", card.title, "TOPLEFT", 0.6, 0)
    card.titleCopy:SetText(E.Localize(section.label))
    local paintTitle = card.title.holder.Paint
    card.title.holder.Paint = function()
        paintTitle()
        local c = Theme.colors.text
        for _, text in ipairs({ card.title, card.titleCopy }) do
            text:SetShadowColor(c[1], c[2], c[3], c[4] or 1)
            text:SetShadowOffset(1, 0)
        end
    end
    card.title.holder.Paint()
    card.changed = Widgets.Text(card, 12, "muted")
    card.changed:SetPoint("LEFT", card.title, "RIGHT", 10, 0)

    card.items = {}
    local paths = {}
    for _, entry in ipairs(section.entries) do
        paths[entry.path] = true
    end
    for _, entry in ipairs(section.entries) do
        local item = newRow(card, page, entry, makeControl, dependsOn(entry.option, paths))
        card.items[#card.items + 1] = item
        list.items[#list.items + 1] = item
    end

    -- Resets the whole group: the first click asks, a second one within a few seconds does it.
    local reset
    reset = Widgets.Button(card, L.V2_RESET_GROUP, "ghost", function()
        if not reset.armed then
            reset.armed = true
            reset.label:SetText(L.V2_RESET_SURE)
            C_Timer.After(CONFIRM_SECONDS, function()
                reset.armed = nil
                reset.label:SetText(L.V2_RESET_GROUP)
            end)
            return
        end
        reset.armed = nil
        reset.label:SetText(L.V2_RESET_GROUP)
        for _, item in ipairs(card.items) do
            E.store:Set(page.module.name, item.path, E.store:GetDefault(page.module.name, item.path))
        end
        page.Refresh()
    end)
    reset:SetHeight(26)
    reset:SetPoint("RIGHT", card.fold, "LEFT", -12, 0)
    Widgets.AttachTooltip(reset, function(tip)
        tip:SetTitle(L.V2_RESET_GROUP)
        tip:AddLine(L.V2_RESET_GROUP_HINT, "textMuted")
    end)
    card.reset = reset

    -- At the Basic level, under the rows: how many advanced options this card hides.
    card.more = Widgets.Button(card, "", "ghost", function()
        showAdvanced()
        page.Refresh()
    end)
    card.more:SetHeight(24)
    card.more:SetPoint("BOTTOMLEFT", PAD - 4, 10)
    return card
end

--- The tabs of a module's page in V2: plain labels on a line, the open one lit and underlined in the
--- accent color. Same interface as Widgets.Segmented: choices = { { value, text } }, SetValue.
---@param parent table
---@param choices table[]
---@param onSelect fun(value: any)
---@return table
function ListV2.Tabs(parent, choices, onSelect)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(TAB_HEIGHT + 2)
    bar.line = bar:CreateTexture(nil, "BORDER")
    bar.line:SetPoint("BOTTOMLEFT")
    bar.line:SetPoint("BOTTOMRIGHT")
    bar.line:SetHeight(E.Pixel.Size(bar))
    bar.buttons = {}

    function bar:SetValue(value)
        self.value = value
        self:Paint()
    end

    function bar:Paint()
        local colors = Theme.colors
        local line = colors.line
        self.line:SetColorTexture(line[1], line[2], line[3], line[4] or 1)
        local x = 0
        for _, button in ipairs(self.buttons) do
            local on = button.value == self.value
            local hovered = button:IsMouseOver()
            local width = button.label:GetStringWidth() + 32
            button:SetSize(width, TAB_HEIGHT)
            button:ClearAllPoints()
            button:SetPoint("BOTTOMLEFT", x, 0)
            x = x + width + 4
            local text = (on or hovered) and colors.text or colors.textMuted
            button.label:SetTextColor(text[1], text[2], text[3], text[4] or 1)
            local a = Theme.accent
            button.underline:SetColorTexture(a[1], a[2], a[3], 1)
            button.underline:SetShown(on)
            if on then
                button.fill:SetColorTexture(a[1], a[2], a[3], 0.1)
            else
                local h = colors.hover
                button.fill:SetColorTexture(h[1], h[2], h[3], h[4] or 1)
            end
            button.fill:SetShown(on or hovered)
        end
    end

    for i, choice in ipairs(choices) do
        local button = CreateFrame("Button", nil, bar)
        button.value = choice[1]
        button.fill = button:CreateTexture(nil, "BACKGROUND")
        button.fill:SetAllPoints()
        button.underline = button:CreateTexture(nil, "ARTWORK")
        button.underline:SetPoint("BOTTOMLEFT")
        button.underline:SetPoint("BOTTOMRIGHT")
        button.underline:SetHeight(E.Pixel.Size(button) * 2)
        button.label = Widgets.Text(button, 15, "text")
        button.label:SetPoint("CENTER", 0, 1)
        button.label:SetText(choice[2])
        -- The label's own repaint (theme or font change) puts back the tab's colors after it.
        local paintLabel = button.label.holder.Paint
        button.label.holder.Paint = function()
            paintLabel()
            bar:Paint()
        end
        button:SetScript("OnClick", function()
            bar:SetValue(choice[1])
            onSelect(choice[1])
        end)
        button:SetScript("OnEnter", function()
            bar:Paint()
        end)
        button:SetScript("OnLeave", function()
            bar:Paint()
        end)
        bar.buttons[i] = button
    end
    return Widgets.Track(bar)
end

--- Makes a list's cards and items. makeControl(parent, page, entry) returns an option's control,
--- already saving to the store.
---@param list table
---@param child table the scroll's content
---@param page table
---@param sections table[]
---@param makeControl function
function ListV2.Fill(list, child, page, sections, makeControl)
    list.cards = {}
    for _, section in ipairs(sections) do
        list.cards[#list.cards + 1] = newCard(child, page, section, list, makeControl)
    end
    -- The Basic / Advanced choice, only when some option here is advanced.
    for _, item in ipairs(list.items) do
        if item.advanced then
            local bar = CreateFrame("Frame", nil, child)
            bar:SetHeight(LEVEL_BAR - 10)
            bar:SetPoint("TOPLEFT")
            bar:SetPoint("TOPRIGHT")
            bar.label = Widgets.Text(bar, 13, "muted")
            bar.label:SetPoint("LEFT", 2, 0)
            bar.label:SetText(L.V2_LEVEL)
            bar.choice = Widgets.Segmented(bar, {
                { "basic", L.V2_BASIC },
                { "advanced", L.V2_ADVANCED },
            }, function(value)
                E.store:Set(CORE, "general.optionsLevel", value)
                page.Refresh()
            end)
            bar.choice:SetPoint("LEFT", bar.label, "RIGHT", 10, 0)
            bar.hidden = Widgets.Text(bar, 13, "muted")
            bar.hidden:SetPoint("LEFT", bar.choice, "RIGHT", 14, 0)
            list.levelBar = bar
            break
        end
    end
    -- The rows' widths follow the window's: laid out again when the scroll gets its size.
    list.scroll:HookScript("OnSizeChanged", function()
        if list.module and list.version == "v2" then
            ListV2.Layout(list, list.module, list.isVisible)
        end
    end)
end

-- A stacked control as wide as its column: dropdowns, sliders (less their readout) and text boxes.
-- A color swatch keeps its size.
local function fitControl(item, width)
    local control, kind = item.control, item.option.type
    if kind == "select" or kind == "text" then
        control:SetWidth(math.max(width - LABEL_X - FIELD_X, 80))
    elseif kind == "range" then
        local room = math.max(140, math.min(240, math.floor(width * RANGE_SHARE)))
        control:SetWidth(room)
        control.bar:GetParent():SetWidth(room - SLIDER_READOUT)
    end
end

-- Cuts a label with "..." when it would run into what's on its right.
local function fitLabel(item, width)
    local row = item.row
    local beside = item.kind == "inline" and item.control:GetWidth() or 0
    local room = width - LABEL_X - FIELD_X - beside - 36
    if row.info then
        room = room - 22
    end
    if row.reload then
        room = room - row.reload:GetStringWidth() - 8
    end
    row.label:SetWidth(0)
    local natural = row.label:GetStringWidth()
    row.label:SetWidth(math.max(math.min(natural, room), 40))
end

-- Draws the line between two columns for each run of switch lines: runs = { { x, top, bottom } }.
local function drawDividers(card, runs)
    local c = Theme.colors.line
    for i, run in ipairs(runs) do
        local divider = card.dividers[i]
        if not divider then
            divider = card:CreateTexture(nil, "ARTWORK")
            divider:SetWidth(E.Pixel.Size(card))
            card.dividers[i] = divider
        end
        divider:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        divider:ClearAllPoints()
        divider:SetPoint("TOPLEFT", card, "TOPLEFT", run.x, -(run.top + DIVIDER_INSET))
        divider:SetPoint("BOTTOMLEFT", card, "TOPLEFT", run.x, -(run.bottom - DIVIDER_INSET))
        divider:Show()
    end
    for i = #runs + 1, #card.dividers do
        card.dividers[i]:Hide()
    end
end

--- Places the cards and their rows from the current values, and hides what visibleWhen hides.
---@param list table
---@param module table
---@param isVisible fun(module: table, option: table): boolean
function ListV2.Layout(list, module, isVisible)
    list.module, list.isVisible = module, isVisible
    local child = list.scroll.child
    local width = child:GetWidth()
    if width < 200 then
        width = 780 -- not sized yet: laid out again when it is
    end
    local inner = width - PAD * 2
    local basic = level() ~= "advanced"
    local y = list.levelBar and LEVEL_BAR or 0
    local hiddenTotal = 0
    for _, card in ipairs(list.cards) do
        local cy = HEADER
        local started = false -- a line was placed (the next one leaves a gap)
        local open -- the line a switch left half used: { y, indented }
        local runs, run = {}, nil -- lines of switches in two columns, for the line between them
        local changed, hidden, any = 0, 0, false
        local collapsed = isCollapsed(card.key)
        card.fold:SetOpen(not collapsed)
        for _, item in ipairs(card.items) do
            local isChanged = ListV2.IsChanged(module.name, item.path)
            local shown = isVisible(module, item.option)
            -- Basic hides an advanced option, unless it was changed (it stays in sight to undo).
            if shown and basic and item.advanced and not isChanged then
                shown = false
                hidden = hidden + 1
            end
            item.row:SetShown(shown and not collapsed)
            if isChanged then
                changed = changed + 1
            end
            if shown then
                any = true
            end
            if shown and not collapsed then
                local value = E.store:Get(module.name, item.path)
                if item.control.SetValue then
                    item.control:SetValue(value)
                elseif not item.control:HasFocus() then
                    item.control:SetText(value)
                end
                item.row.changed = isChanged
                item.reset:SetShown(isChanged)

                local indent = item.indented and INDENT or 0
                local x, top, rowWidth
                -- Two per line; a line holds options of one kind (same height) and one indent.
                local height = item.kind == "inline" and CELL or STACK
                -- The two columns are the same for every line of the card, so fields and the line
                -- between them stay aligned; an indented field starts further in its column.
                local half = (inner - COLUMN_GAP) / 2
                rowWidth = half - indent
                if open and open.indented == item.indented and open.kind == item.kind then
                    x, top = PAD + half + COLUMN_GAP + indent, open.y
                    open = nil
                else
                    if started then
                        cy = cy + LINE_GAP
                    end
                    started = true
                    x, top = PAD + indent, cy
                    open = { y = cy, indented = item.indented, kind = item.kind }
                    local middle = PAD + half + COLUMN_GAP / 2
                    if run and run.x == middle and run.bottom + LINE_GAP == cy then
                        run.bottom = cy + height
                    else
                        run = { x = middle, top = cy, bottom = cy + height }
                        runs[#runs + 1] = run
                    end
                    cy = cy + height
                end
                fitControl(item, rowWidth)
                item.row:Paint()
                item.row:ClearAllPoints()
                item.row:SetPoint("TOPLEFT", card, "TOPLEFT", x, -top)
                item.row:SetWidth(rowWidth)
                fitLabel(item, rowWidth)
                item.y = y + top
            end
        end
        drawDividers(card, runs)
        hiddenTotal = hiddenTotal + hidden
        card:SetShown(any)
        if any then
            card.changed:SetText(changed > 0 and L.V2_CHANGED:format(changed) or "")
            card.reset:SetShown(changed > 0)
            card.more:SetShown(hidden > 0 and not collapsed)
            if collapsed then
                cy = HEADER - PAD + 4 -- the title line alone
            elseif hidden > 0 then
                card.more.label:SetText(L.V2_SHOW_HIDDEN:format(hidden))
                card.more:SetWidth(card.more.label:GetStringWidth() + 20)
                cy = cy + MORE
            end
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
            card:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -y)
            card:SetHeight(cy + PAD)
            y = y + cy + PAD + CARD_GAP
        end
    end
    if list.levelBar then
        list.levelBar.choice:SetValue(basic and "basic" or "advanced")
        list.levelBar.hidden:SetText(hiddenTotal > 0 and L.V2_HIDDEN:format(hiddenTotal) or "")
    end
    list.scroll:SetContentHeight(y + 8)
end

--- Unfolds the card that holds an option, for the search. Returns true when it was folded.
---@param page table
---@param path string
---@return boolean
function ListV2.Unfold(page, path)
    for _, list in ipairs(page.lists or {}) do
        for _, item in ipairs(list.items) do
            if item.path == path and item.card and isCollapsed(item.card.key) then
                setCollapsed(item.card.key, false)
                return true
            end
        end
    end
    return false
end

--- Whether the Basic level hides an option of the page now (V2 only), so a search can show it.
---@param page table
---@param path string
---@return boolean
function ListV2.HiddenByLevel(page, path)
    if ns.ModulePage.Version() ~= "v2" or level() == "advanced" or not page.lists then
        return false
    end
    for _, list in ipairs(page.lists) do
        for _, item in ipairs(list.items) do
            if item.path == path and item.advanced then
                return not ListV2.IsChanged(page.module.name, path)
            end
        end
    end
    return false
end
