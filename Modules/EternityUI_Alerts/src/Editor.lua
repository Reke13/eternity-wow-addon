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

---@class EternityUIAlertsEditor
---@field view table? the tab's frame while it exists
local Editor = {}
ns.Editor = Editor

local function summary(rule)
    if rule.kind == "buff" then
        return rule.spells ~= "" and L.SUMMARY_buff:format(rule.spells) or L.SUMMARY_buff_EMPTY
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
    row.note:SetPoint("RIGHT", -70, 0)
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

    -- field: { frame, kinds = { kind = true } or nil, load = fun(rule), when = fun(rule): boolean }
    -- when: shown only if it returns true (fields that make no sense with another field's value).
    local function add(frame, kinds, load, when)
        frame:SetParent(form)
        form.fields[#form.fields + 1] = { frame = frame, kinds = kinds, load = load, when = when }
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
        add(Widgets.Row(form, label, box), kinds, function(rule)
            box:SetText(rule[key])
        end, when)
    end

    local function dropdown(label, key, list, kinds, after)
        local control = Widgets.Dropdown(form, list, function(value)
            set(key, value)
            if after then
                after(value)
            end
        end)
        local row = Widgets.Row(form, label, control)
        add(row, kinds, function(rule)
            control:SetValue(rule[key])
        end)
        return row
    end

    -- An "i" after a row's label, with a text that explains the field.
    local function info(row, text)
        row.info = Widgets.Info(row, row.label:GetText(), text)
        row.info:SetPoint("LEFT", row.label, "RIGHT", 6, 0)
        return row.info
    end

    local function toggle(label, key, kinds, when)
        local control = Widgets.Toggle(form, function(value)
            set(key, value)
        end)
        add(Widgets.Row(form, label, control), kinds, function(rule)
            control:SetValue(rule[key])
        end, when)
    end

    -- The icons can't be clicked in combat (they're secure buttons): no click fields then.
    local function clickable(rule)
        return rule.combat ~= "in"
    end

    local function slider(label, key, min, max, format, kinds)
        local control = Widgets.Slider(form, min, max, 1, format, function(value)
            set(key, value)
        end)
        add(Widgets.Row(form, label, control), kinds, function(rule)
            control:SetValue(rule[key])
        end)
    end

    textField(L.FIELD_NAME, "name")

    -- The buff list, with a button that picks from what's on the player now.
    local spells = input("spells", L.SPELLS_HINT)
    local holder = CreateFrame("Frame", nil, form)
    holder:SetSize(FIELD_WIDTH + 124, 30)
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
    add(spellsRow, { buff = true }, function(rule)
        spells:SetText(rule.spells)
    end)

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
    dropdown(L.FIELD_CLASS, "class", Editor.ClassChoices())
    slider(L.FIELD_LEVEL, "minLevel", 0, GetMaxPlayerLevel(), function(value)
        return value == 0 and L.ANY_LEVEL or tostring(value)
    end)
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

    heading(L.LOOK)
    toggle(L.FIELD_GLOW, "glow")
    dropdown(L.FIELD_SOUND, "sound", choices("SOUND_", Rules.SOUND_ORDER), nil, function(value)
        local sound = Rules.SOUNDS[value]
        if sound and SOUNDKIT[sound] then
            PlaySound(SOUNDKIT[sound])
        end
    end)

    --- Shows the fields of a rule's kind and returns the form's height.
    function form.Load(rule)
        local y = 0
        for _, field in ipairs(form.fields) do
            local shown = (not field.kinds or field.kinds[rule.kind]) and (not field.when or field.when(rule))
            field.frame:SetShown(shown and true or false)
            if shown then
                if field.load then
                    field.load(rule)
                end
                field.frame:ClearAllPoints()
                field.frame:SetPoint("TOPLEFT", 0, -y)
                field.frame:SetPoint("TOPRIGHT", 0, -y)
                y = y + field.frame:GetHeight()
            end
        end
        form:SetHeight(y)
        return y
    end

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
                view.form:SetPoint("TOPLEFT", 12, -y)
                view.form:SetPoint("TOPRIGHT", -12, -y)
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
