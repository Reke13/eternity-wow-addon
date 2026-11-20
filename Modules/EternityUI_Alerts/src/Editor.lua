-- The Rules tab: the list of rules, and under it the form of the one picked. The form is built once
-- and shows the fields of the rule's kind; a change is saved at once.

---@type string, EternityUIAlertsNamespace
local _, ns = ...
local E = EternityUI
local Shape, Theme, Widgets = E.Shape, E.Theme, E.Widgets
local L, Rules, Checks = ns.L, ns.Rules, ns.Checks

local ROW_HEIGHT = 48
local ROW_GAP = 4
local ICON = 28
local FIELD_WIDTH = 300
local HEADER = 44
local MAX_PICKS = 14
local MAX_AURAS = 40
local DELETE_SECONDS = 4
-- The options window's V2 layout (the core's general.optionsVersion): the form in two columns, like
-- the option lists. Every field has its control beside its label and the same height, so they pair
-- in order with no gaps; only a section's last field can be alone. Headings take the whole line.
local FIELD_X = 12
local LINE_GAP = 8
local COLUMN_GAP = 24
local RANGE_SHARE = 0.48
local TEXT_SHARE = 0.55 -- a text box takes about this much of its field
local DROPDOWN_SHARE = 0.5
local SPELLS_SHARE = 0.62 -- the buff list and "My buffs" together
local PICK_ROOM = 124 -- "My buffs" and its gap
local SLIDER = 230 -- the core's slider: its width and its readout's room
local SLIDER_READOUT = 50
local DROPDOWN = 240
local FALLBACK_WIDTH = 756 -- the form before it has a size
local FORM_MARGIN = 12 -- the form inside the tab, on each side

---@class EternityUIAlertsEditor
---@field view table? the tab's frame while it exists
local Editor = {}
ns.Editor = Editor

local function summary(rule)
    if rule.kind == "buff" then
        if rule.spells == "" then
            return L.SUMMARY_buff_EMPTY
        end
        local text = L.SUMMARY_buff:format(rule.spells)
        return rule.lowTime and (text .. L.SUMMARY_buff_LOW:format(rule.lowTimeSeconds)) or text
    elseif rule.kind == "enchant" then
        return rule.threshold > 0 and L.SUMMARY_enchant:format(rule.threshold) or L.SUMMARY_enchant_NONE
    elseif rule.kind == "durability" then
        return L.SUMMARY_durability:format(rule.threshold)
    elseif rule.kind == "slots" then
        return L.SUMMARY_slots:format(rule.threshold)
    end
    return rule.item ~= "" and L.SUMMARY_item:format(rule.item, rule.threshold) or L.SUMMARY_item_EMPTY
end
Editor.Summary = summary

local function choices(prefix, keys)
    local list = {}
    for i, key in ipairs(keys) do
        list[i] = { key, L[prefix .. key] }
    end
    return list
end

-- Class IDs have gaps (Forever's druid is 11 of 9 classes), so GetNumClasses can't bound them.
local MAX_CLASS_ID = 20

--- The game's classes in Blizzard's order.
---@return table[] choices { token, name }
function Editor.ClassChoices()
    local names = {}
    for id = 1, MAX_CLASS_ID do
        local info = C_CreatureInfo.GetClassInfo(id)
        if info then
            names[info.classFile] = info.className
        end
    end
    local list = { { "", L.ANY_CLASS } }
    for _, token in ipairs(CLASS_SORT_ORDER) do
        list[#list + 1] = { token, names[token] or token }
    end
    return list
end

-- The buffs on the player, once per name. Empty while auras are secret.
local function currentBuffs()
    local list, seen = {}, {}
    if Checks.AurasRestricted() then
        return list
    end
    for i = 1, MAX_AURAS do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not aura then
            break
        end
        local name = aura.name
        local readable = type(name) == "string" and not (issecretvalue and issecretvalue(name)) and name ~= ""
        if readable and not seen[name] and #list < MAX_PICKS then
            seen[name] = true
            list[#list + 1] = aura
        end
    end
    return list
end

--- True while the options window uses its V2 layout. A core without the setting answers nil.
---@return boolean
function Editor.TwoColumns()
    return E.store:Get("EternityUI", "general.optionsVersion") == "v2"
end

-- List ---------------------------------------------------------------------------------------------

local function newRow(view)
    local row = CreateFrame("Button", nil, view)
    row:SetHeight(ROW_HEIGHT)
    row.shape = Shape.New(row)
    row.toggle = Widgets.Toggle(row, function(value)
        row.rule.enabled = value
        Rules.Changed()
    end)
    row.toggle:SetPoint("LEFT", 10, 0)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.icon:SetPoint("LEFT", row.toggle, "RIGHT", 12, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.name = Widgets.Text(row, 15, "text")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, 2)
    row.note = Widgets.Text(row, 12, "muted")
    row.note:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, -2)
    row.note:SetPoint("RIGHT", -150, 0)
    row.note:SetJustifyH("LEFT")
    row.note:SetWordWrap(false)

    -- Two clicks: the first one asks for confirmation for a few seconds.
    row.delete = Widgets.Button(row, "×", "danger", function(self)
        if not row.armed then
            row.armed = true
            self.label:SetText(L.DELETE_CONFIRM)
            self:SetWidth(84)
            C_Timer.After(DELETE_SECONDS, function()
                row.armed = false
                self.label:SetText("×")
                self:SetWidth(34)
            end)
            return
        end
        row.armed = false
        self.label:SetText("×")
        self:SetWidth(34)
        Editor.Delete(row.rule)
    end)
    row.delete:SetWidth(34)
    row.delete:SetPoint("RIGHT", -8, 0)

    -- Beside the delete button (it widens to the left while it asks): a copy under the rule.
    row.duplicate = Widgets.Button(row, L.DUPLICATE, "ghost", function()
        Editor.Duplicate(row.rule)
    end)
    row.duplicate:SetWidth(96)
    row.duplicate:SetPoint("RIGHT", row.delete, "LEFT", -6, 0)

    function row.Paint(self)
        local accent = Theme.accent
        local picked = self.rule and self.rule == Editor.current
        Shape.Paint(
            self.shape,
            math.min(Theme.radius, 6),
            picked and { accent[1], accent[2], accent[3], 0.16 } or (self:IsMouseOver() and Theme.colors.hover or nil),
            Theme.colors.line
        )
    end
    row:SetScript("OnEnter", row.Paint)
    row:SetScript("OnLeave", row.Paint)
    row:SetScript("OnClick", function(self)
        Editor.Select(self.rule ~= Editor.current and self.rule or nil)
    end)
    return Widgets.Track(row)
end

-- Form ---------------------------------------------------------------------------------------------

local function buildForm(view)
    local form = CreateFrame("Frame", nil, view)
    form.fields, form.inputs = {}, {}

    local function set(key, value)
        local rule = Editor.current
        if rule and rule[key] ~= value then
            rule[key] = value
            Rules.Changed()
            view:RefreshList()
        end
    end

    -- field: { frame, kinds = { kind = true } or nil, load = fun(rule), when = fun(rule): boolean,
    -- shape = "inline" (a field) or nil (a heading, on its own line), fit = fun(width?) }
    -- when: shown only if it returns true (fields that make no sense with another field's value).
    -- fit: sizes the control for a column of that width, or back to its own size without one.
    local function add(frame, kinds, load, when, shape, fit)
        frame:SetParent(form)
        local field = { frame = frame, kinds = kinds, load = load, when = when, shape = shape, fit = fit }
        form.fields[#form.fields + 1] = field
        return field
    end

    local function heading(text)
        local holder = CreateFrame("Frame", nil, form)
        holder:SetHeight(38)
        local label = Widgets.Text(holder, 13, "muted")
        label:SetPoint("BOTTOMLEFT", 0, 6)
        label:SetText(text:upper())
        add(holder)
    end

    local function input(key, placeholder)
        local box = Widgets.Input(form, nil, placeholder)
        box:SetWidth(FIELD_WIDTH)
        local function commit()
            set(key, (box:GetText():gsub("^%s+", ""):gsub("%s+$", "")))
        end
        box:SetScript("OnEnterPressed", box.ClearFocus)
        box:HookScript("OnEditFocusLost", commit)
        form.inputs[#form.inputs + 1] = box
        return box
    end

    local function textField(label, key, placeholder, kinds, when)
        local box = input(key, placeholder)
        add(
            Widgets.Row(form, label, box),
            kinds,
            function(rule)
                box:SetText(rule[key])
            end,
            when,
            "inline",
            function(width)
                box:SetWidth(width and math.max(120, math.floor(width * TEXT_SHARE)) or FIELD_WIDTH)
            end
        )
    end

    local function dropdown(label, key, list, kinds, after)
        local control = Widgets.Dropdown(form, list, function(value)
            set(key, value)
            if after then
                after(value)
            end
        end)
        local row = Widgets.Row(form, label, control)
        add(
            row,
            kinds,
            function(rule)
                control:SetValue(rule[key])
            end,
            nil,
            "inline",
            function(width)
                control:SetWidth(
                    width and math.max(140, math.min(DROPDOWN, math.floor(width * DROPDOWN_SHARE))) or DROPDOWN
                )
            end
        )
        return row
    end

    -- An "i" after a row's label, with a text that explains the field.
    local function info(row, text)
        row.info = Widgets.Info(row, row.label:GetText(), text)
        row.info:SetPoint("LEFT", row.label, "RIGHT", 6, 0)
        return row.info
    end

    local function toggle(label, key, kinds, when, after)
        local control = Widgets.Toggle(form, function(value)
            set(key, value)
            if after then
                after(value)
            end
        end)
        local row = Widgets.Row(form, label, control)
        add(row, kinds, function(rule)
            control:SetValue(rule[key])
        end, when, "inline")
        return row
    end

    local function color(label, key, kinds, when)
        local control = Widgets.Color(form, function(value)
            set(key, value)
        end)
        local row = Widgets.Row(form, label, control)
        add(row, kinds, function(rule)
            control:SetValue(rule[key])
        end, when, "inline")
        return row
    end

    -- The icons can't be clicked in combat (they're secure buttons): no click fields then.
    local function clickable(rule)
        return rule.combat ~= "in"
    end

    local function slider(label, key, min, max, format, kinds, when, after)
        local control = Widgets.Slider(form, min, max, 1, format, function(value)
            set(key, value)
            if after then
                after(value)
            end
        end)
        local row = Widgets.Row(form, label, control)
        -- In a column it takes about half of it, less its readout.
        local bar = control.bar and control.bar:GetParent()
        add(
            row,
            kinds,
            function(rule)
                control:SetValue(rule[key])
            end,
            when,
            "inline",
            function(width)
                local room = width and math.max(140, math.min(SLIDER, math.floor(width * RANGE_SHARE))) or SLIDER
                control:SetWidth(room)
                if bar then
                    bar:SetWidth(room - SLIDER_READOUT)
                end
            end
        )
        return row
    end

    textField(L.FIELD_NAME, "name")

    -- The buff list, with a button that picks from what's on the player now.
    local spells = input("spells", L.SPELLS_HINT)
    local holder = CreateFrame("Frame", nil, form)
    holder:SetSize(FIELD_WIDTH + PICK_ROOM, 30)
    spells:SetParent(holder)
    spells:SetPoint("LEFT")
    local pick
    pick = Widgets.Button(holder, L.MY_BUFFS, "ghost", function()
        local entries = {}
        for _, aura in ipairs(currentBuffs()) do
            entries[#entries + 1] = {
                text = aura.name,
                onClick = function()
                    local rule = Editor.current
                    if rule then
                        rule.spells = rule.spells == "" and aura.name or (rule.spells .. ", " .. aura.name)
                        rule.icon = rule.icon or aura.icon
                        spells:SetText(rule.spells)
                        Rules.Changed()
                        view:RefreshList()
                    end
                end,
            }
        end
        if #entries == 0 then
            entries[1] = { text = L.NO_BUFFS, onClick = function() end }
        end
        Widgets.Menu(pick, entries, 260)
    end)
    pick:SetWidth(112)
    pick:SetPoint("RIGHT")
    local spellsRow = Widgets.Row(form, L.FIELD_SPELLS, holder)
    form.spellsInfo = info(spellsRow, L.BUFF_REMINDER)
    add(
        spellsRow,
        { buff = true },
        function(rule)
            spells:SetText(rule.spells)
        end,
        nil,
        "inline",
        function(width)
            local room = width and math.max(PICK_ROOM + 120, math.floor(width * SPELLS_SHARE))
                or (FIELD_WIDTH + PICK_ROOM)
            holder:SetWidth(room)
            spells:SetWidth(room - PICK_ROOM)
        end
    )

    -- "Seconds left": a buff about to run out counts as missing. The seconds only with it on.
    local lowTimeRow = toggle(L.FIELD_LOW_TIME, "lowTime", { buff = true }, nil, function()
        view:Refresh()
    end)
    form.lowTimeRow, form.lowTimeInfo = lowTimeRow, info(lowTimeRow, L.LOW_TIME_HINT)
    form.lowTimeSecondsRow = slider(
        L.FIELD_LOW_TIME_SECONDS,
        "lowTimeSeconds",
        Rules.LOW_TIME_MIN,
        Rules.LOW_TIME_MAX,
        function(value)
            return L.SECONDS:format(value)
        end,
        { buff = true },
        function(rule)
            return rule.lowTime
        end
    )

    toggle(L.FIELD_CLICK, "click", { buff = true }, clickable)
    textField(L.FIELD_CLICK_USE, "clickUse", L.CLICK_USE_HINT, { buff = true }, clickable)
    textField(L.FIELD_ITEM, "item", L.ITEM_HINT, { item = true })
    dropdown(L.FIELD_SLOT, "slot", choices("SLOT_", { "both", "main", "off" }), { enchant = true })

    local function percent(value)
        return string.format("%d%%", value)
    end
    local function minutes(value)
        return value == 0 and L.MISSING_ONLY or L.MINUTES:format(value)
    end
    slider(L.FIELD_ENCHANT, "threshold", 0, 60, minutes, { enchant = true })
    slider(L.FIELD_DURABILITY, "threshold", 1, 100, percent, { durability = true })
    slider(L.FIELD_SLOTS, "threshold", 1, 40, tostring, { slots = true })
    slider(L.FIELD_COUNT, "threshold", 1, 200, tostring, { item = true })

    heading(L.WHEN)
    -- From and up to level, one after the other so the two columns pair them. Moving one past the
    -- other drags the other along.
    local function levels(changed)
        return function()
            local rule = Editor.current
            if rule and Rules.FitLevels(rule, changed) then
                view:Refresh()
            end
        end
    end
    local maxLevel = GetMaxPlayerLevel()
    form.minLevelRow = slider(L.FIELD_LEVEL, "minLevel", 0, maxLevel, function(value)
        return value == 0 and L.ANY_LEVEL or tostring(value)
    end, nil, nil, levels("minLevel"))
    form.maxLevelRow = slider(L.FIELD_MAX_LEVEL, "maxLevel", 0, maxLevel, function(value)
        return value == 0 and L.NO_MAX_LEVEL or tostring(value)
    end, nil, nil, levels("maxLevel"))
    form.levelInfo = info(form.maxLevelRow, L.LEVEL_HINT)
    dropdown(L.FIELD_CLASS, "class", Editor.ClassChoices())
    dropdown(L.FIELD_GROUP, "group", choices("GROUP_", { "any", "solo", "group", "raid" }))
    dropdown(L.FIELD_PLACE, "place", choices("PLACE_", { "any", "instance", "world" }))
    local combatRow = dropdown(L.FIELD_COMBAT, "combat", choices("COMBAT_", { "out", "any", "in" }), nil, function()
        view:Refresh()
    end)
    -- Buff rules that show in combat: what they can't know there.
    form.combatInfo = info(combatRow, L.COMBAT_BUFF_HINT)
    local combatField = form.fields[#form.fields]
    local loadCombat = combatField.load
    combatField.load = function(rule)
        loadCombat(rule)
        form.combatInfo:SetShown(rule.kind == "buff" and rule.combat ~= "out")
    end
    toggle(L.HIDE_RESTING, "hideResting")
    toggle(L.HIDE_MOUNTED, "hideMounted")

    -- This rule's icon: its own size, name, glow color and icon, over the General tab's look.
    heading(L.LOOK)
    local function refresh()
        view:Refresh()
    end
    toggle(L.FIELD_GLOW, "glow", nil, nil, refresh)
    toggle(L.FIELD_CUSTOM_GLOW, "customGlow", nil, function(rule)
        return rule.glow
    end, refresh)
    form.glowColorRow = color(L.FIELD_GLOW_COLOR, "glowColor", nil, function(rule)
        return rule.glow and rule.customGlow
    end)
    form.scaleRow = slider(L.FIELD_SCALE, "scale", Rules.SCALE_MIN, Rules.SCALE_MAX, percent)
    form.showNameRow = dropdown(L.FIELD_SHOW_NAME, "showName", choices("SHOW_NAME_", Rules.SHOW_NAME))
    textField(L.FIELD_ICON, "iconOverride", L.ICON_HINT)
    form.countdownRow = toggle(L.FIELD_COUNTDOWN, "countdown", { buff = true }, function(rule)
        return rule.lowTime
    end)
    dropdown(L.FIELD_SOUND, "sound", choices("SOUND_", Rules.SOUND_ORDER), nil, function(value)
        local sound = Rules.SOUNDS[value]
        if sound and SOUNDKIT[sound] then
            PlaySound(SOUNDKIT[sound])
        end
    end)

    form.dividers = {}

    -- The line between the columns, for each run of lines one under the other.
    local function drawDividers(runs)
        local c = Theme.colors.line
        for i, run in ipairs(runs) do
            local divider = form.dividers[i]
            if not divider then
                divider = form:CreateTexture(nil, "ARTWORK")
                divider:SetWidth(E.Pixel.Size(form))
                form.dividers[i] = divider
            end
            divider:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
            divider:ClearAllPoints()
            divider:SetPoint("TOPLEFT", form, "TOPLEFT", run.x, -run.top)
            divider:SetPoint("BOTTOMLEFT", form, "TOPLEFT", run.x, -run.bottom)
            divider:Show()
        end
        for i = #runs + 1, #form.dividers do
            form.dividers[i]:Hide()
        end
    end

    -- A row sized for its column, or back to its own size, then repainted (the core's V2 field).
    local function shapeRow(field, columns)
        local frame = field.frame
        if field.fit then
            field.fit(columns and form.columnWidth or nil)
        end
        if frame.label then
            frame.label:SetWordWrap(not columns)
            frame.label:SetWidth(0)
        end
        if frame.Paint then
            frame:Paint()
        end
    end

    -- Cuts a label with "..." when it would run into the control beside it.
    local function fitLabel(field, width)
        local row = field.frame
        if not row.label then
            return
        end
        local beside = row.control and row.control:GetWidth() or 0
        local room = width - FIELD_X * 2 - beside - 16 - (row.info and 22 or 0)
        local natural = row.label:GetStringWidth()
        row.label:SetWidth(math.max(math.min(natural, room), 40))
    end

    --- Shows the fields of a rule's kind and returns the form's height.
    function form.Load(rule)
        local columns = Editor.TwoColumns()
        -- The first time the form has no anchors yet: the tab's width, less the form's margins.
        local width = form:GetWidth()
        if not width or width < 200 then
            width = (view:GetWidth() or 0) - FORM_MARGIN * 2
        end
        if width < 200 then
            width = FALLBACK_WIDTH
        end
        local half = (width - COLUMN_GAP) / 2
        form.columnWidth, form.laidWidth = half, width
        local y = 0
        local open, started = nil, false -- the top of a line with its right column free; a line was set
        local runs, run = {}, nil
        for _, field in ipairs(form.fields) do
            local shown = (not field.kinds or field.kinds[rule.kind]) and (not field.when or field.when(rule))
            local frame = field.frame
            frame:SetShown(shown and true or false)
            if shown then
                if field.load then
                    field.load(rule)
                end
                shapeRow(field, columns)
                frame:ClearAllPoints()
                if not columns or not field.shape then
                    -- The whole line: every field in V1, headings in V2 (they start a new run).
                    open, run, started = nil, nil, false
                    frame:SetPoint("TOPLEFT", 0, -y)
                    frame:SetPoint("TOPRIGHT", 0, -y)
                    y = y + frame:GetHeight()
                else
                    local height = frame:GetHeight()
                    local x, top
                    if open then
                        x, top, open = half + COLUMN_GAP, open, nil
                    else
                        if started then
                            y = y + LINE_GAP
                        end
                        started = true
                        x, top = 0, y
                        open = y
                        if run and run.bottom + LINE_GAP == y then
                            run.bottom = y + height
                        else
                            run = { x = half + COLUMN_GAP / 2, top = y, bottom = y + height }
                            runs[#runs + 1] = run
                        end
                        y = y + height
                    end
                    frame:SetPoint("TOPLEFT", x, -top)
                    frame:SetWidth(half)
                    fitLabel(field, half)
                end
            end
        end
        drawDividers(columns and runs or {})
        form:SetHeight(y)
        return y
    end

    -- The columns follow the window's width: laid out again when it changes.
    form:SetScript("OnSizeChanged", function(self, width)
        if Editor.TwoColumns() and Editor.current and self.laidWidth and math.abs(width - self.laidWidth) > 1 then
            view:Refresh()
        end
    end)

    return form
end

-- Tab ----------------------------------------------------------------------------------------------

--- Picks a rule to edit, or none.
---@param rule EternityUIAlertsRule?
function Editor.Select(rule)
    local view = Editor.view
    if view and view.form then
        -- A box still holding the focus saves into the rule it belongs to.
        for _, box in ipairs(view.form.inputs) do
            box:ClearFocus()
        end
    end
    Editor.current = rule
    if view then
        view:Refresh()
    end
end

--- Copies a rule under itself and opens the copy.
---@param rule EternityUIAlertsRule
function Editor.Duplicate(rule)
    if not rule then
        return
    end
    local copy = Rules.Duplicate(rule)
    Rules.Changed()
    Editor.Select(copy)
end

--- Deletes a rule.
---@param rule EternityUIAlertsRule
function Editor.Delete(rule)
    if rule == Editor.current then
        Editor.Select(nil)
    end
    Rules.Remove(rule)
    Rules.Changed()
    if Editor.view then
        Editor.view:Refresh()
    end
end

--- Builds the tab.
---@param parent table
---@param setHeight fun(height: number)
---@return table
function Editor.Build(parent, setHeight)
    local view = CreateFrame("Frame", nil, parent)
    view:SetPoint("TOPLEFT")
    view:SetPoint("TOPRIGHT")
    view.rows = {}
    Editor.view = view

    local empty = Widgets.Text(view, 14, "muted")
    empty:SetPoint("TOPLEFT", 0, -HEADER - 6)
    empty:SetText(L.EMPTY)

    local add
    add = Widgets.Button(view, L.NEW_RULE, "primary", function()
        local entries = {}
        for i, kind in ipairs(Rules.KINDS) do
            entries[i] = {
                text = L["KIND_" .. kind],
                onClick = function()
                    local rule = Rules.Add(kind)
                    Rules.Changed()
                    Editor.Select(rule)
                end,
            }
        end
        Widgets.Menu(add, entries, 240)
    end)
    add:SetPoint("TOPRIGHT", 0, -6)

    --- Redraws the rows: names and summaries change while editing.
    function view.RefreshList()
        local rules = Rules.List()
        for i, rule in ipairs(rules) do
            local row = view.rows[i] or newRow(view)
            view.rows[i] = row
            row.rule = rule
            row.toggle:SetValue(rule.enabled)
            row.icon:SetTexture(Checks.Icon(rule))
            row.name:SetText(rule.name ~= "" and rule.name or L["KIND_" .. rule.kind])
            row.note:SetText(summary(rule))
            row:Paint()
            row:Show()
        end
        for i = #rules + 1, #view.rows do
            view.rows[i].rule = nil
            view.rows[i]:Hide()
        end
        empty:SetShown(#rules == 0)
    end

    function view.Refresh()
        view:RefreshList()
        view.form = view.form or buildForm(view)
        local y = HEADER
        local rules = Rules.List()
        local height = 0
        for i = 1, #rules do
            local row = view.rows[i]
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", 0, -y)
            y = y + ROW_HEIGHT + ROW_GAP
            if rules[i] == Editor.current then
                -- The form opens under its own rule.
                height = view.form.Load(rules[i])
                view.form:ClearAllPoints()
                view.form:SetPoint("TOPLEFT", FORM_MARGIN, -y)
                view.form:SetPoint("TOPRIGHT", -FORM_MARGIN, -y)
                y = y + height + 12
            end
        end
        view.form:SetShown(height > 0)
        view:SetHeight(y + 12)
        setHeight(y + 12)
    end

    view:SetScript("OnShow", view.Refresh)
    view:Refresh()
    return view
end
