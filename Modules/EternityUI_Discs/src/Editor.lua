-- The Discs tab of the options page: pick a disc, rename it, give it a key on this character, and
-- add, sort, rename or remove its slots. Slots come from the cursor (drag and drop), from a search
-- by name or ID, or from the special ones (hearthstone, professions, macro text, another disc).

---@type string, EternityUIDiscsNamespace
local _, ns = ...
local Theme, W = ns.Ui.Theme, ns.Ui.W
local Store, Resolve, L = ns.Store, ns.Resolve, ns.L

---@class EternityUIDiscsEditor
---@field view table? the tab's frame (built the first time the page opens)
---@field selected number? disc id shown
---@field editing { mode: string, index: integer }? slot being renamed or re-iconed
local Editor = {}
ns.Editor = Editor

local ROW_X = Theme.space.lg + 2
local ROW, SLOT_ROW, CONTROL = Theme.size.row, 40, Theme.size.controlColumn
local MODIFIERS =
    { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, LMETA = true, RMETA = true }

local function say(text)
    print("|cff8b5cf6Eternity Discs|r: " .. text)
end

-- Card with stacked rows separated by dividers (card:AddRow(height), card:Layout()).
local function rowCard(parent)
    local card = W.Card(parent)
    card.rows, card.dividers = {}, {}
    function card:AddRow(height)
        local row = CreateFrame("Frame", nil, self)
        row.height = height
        row:SetHeight(height)
        self.rows[#self.rows + 1] = row
        return row
    end
    function card:Layout()
        local y, shown = 0, 0
        for _, row in ipairs(self.rows) do
            if row:IsShown() then
                shown = shown + 1
                -- The first row has no divider, so this table is sparse.
                if shown > 1 then
                    local divider = self.dividers[shown] or W.Divider(self)
                    self.dividers[shown] = divider
                    divider:ClearAllPoints()
                    divider:SetPoint("TOPLEFT", ROW_X, -y)
                    divider:SetPoint("RIGHT", -ROW_X, 0)
                    divider:Show()
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -y)
                row:SetPoint("RIGHT")
                y = y + row.height
            end
        end
        for i, divider in pairs(self.dividers) do
            if i > shown then
                divider:Hide()
            end
        end
        self.height = math.max(y, 1)
        self:SetHeight(self.height)
    end
    return card
end

local function label(row, text, note)
    row.label = W.Text(row, text)
    if note then
        row.note = W.Text(row, note, "small", "muted")
        row.note:SetPoint("TOPLEFT", row, "LEFT", ROW_X, -3)
        row.note:SetPoint("RIGHT", row, "RIGHT", -CONTROL - 2 * ROW_X, 0)
        row.label:SetPoint("BOTTOMLEFT", row, "LEFT", ROW_X, 1)
    else
        row.label:SetPoint("LEFT", ROW_X, 0)
    end
end

local function keyText(key)
    return key and GetBindingText(key) or L.KEY_NONE
end

-- Discs card --------------------------------------------------------------------------------------

local function buildDiscsCard(view)
    local card = rowCard(view)

    local toolbar = card:AddRow(ROW)
    view.picker = W.Dropdown(toolbar, {
        width = 220,
        placeholder = L.DISC,
        onChange = function(id)
            Editor.selected = id
            Editor.editing = nil
            view:Refresh()
        end,
    })
    view.picker:SetPoint("LEFT", ROW_X, 0)
    view.generate = W.Button(toolbar, {
        text = L.GENERATE,
        variant = "primary",
        icon = "plus",
        onClick = function()
            Editor.selected = Store:Generate().id
            view:Refresh()
        end,
    })
    view.generate:SetPoint("RIGHT", -ROW_X, 0)
    W.AttachTooltip(view.generate, function(tip)
        tip:SetTitle(L.GENERATE)
        tip:AddLine(L.GENERATE_HINT)
    end, "TOP")
    view.new = W.Button(toolbar, {
        text = L.NEW,
        icon = "plus",
        onClick = function()
            Editor.selected = Store:Create().id
            view:Refresh()
        end,
    })
    view.new:SetPoint("RIGHT", view.generate, "LEFT", -Theme.space.sm, 0)

    view.emptyRow = card:AddRow(ROW)
    view.empty = W.Text(view.emptyRow, L.NO_DISCS, "body", "muted")
    view.empty:SetPoint("LEFT", ROW_X, 0)
    view.empty:SetPoint("RIGHT", -ROW_X, 0)

    local nameRow = card:AddRow(ROW)
    label(nameRow, L.NAME)
    view.name = W.Input(nameRow, {
        width = CONTROL,
        maxLetters = 40,
        onEnter = function(text)
            Store:Rename(Editor.selected, strtrim(text))
        end,
        onFocusLost = function(text)
            Store:Rename(Editor.selected, strtrim(text))
        end,
    })
    view.name:SetPoint("RIGHT", -ROW_X, 0)

    local keyRow = card:AddRow(72)
    label(keyRow, L.KEY, L.KEY_HINT)
    view.key = W.Button(keyRow, { text = L.KEY_NONE, width = CONTROL })
    view.key:SetPoint("RIGHT", -ROW_X, 0)
    view.key:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    view.key:SetScript("OnClick", function(button, mouse)
        if mouse == "RightButton" then
            button:StopCapture()
            Store:SetKey(Editor.selected, nil)
        else
            button:StartCapture()
        end
    end)
    function view.key:StartCapture()
        if InCombatLockdown() then
            say(L.COMBAT)
            return
        end
        self.capturing = true
        self:SetText(L.KEY_PRESS)
        self:EnableKeyboard(true)
        self:SetPropagateKeyboardInput(false)
    end
    function view.key:StopCapture()
        self.capturing = false
        self:EnableKeyboard(false)
        self:SetText(keyText(Store:Keys()[Editor.selected]))
    end
    view.key:SetScript("OnKeyDown", function(button, key)
        if MODIFIERS[key] then
            return
        end
        button:StopCapture()
        if key ~= "ESCAPE" then
            local combo = (IsAltKeyDown() and "ALT-" or "")
                .. (IsControlKeyDown() and "CTRL-" or "")
                .. (IsShiftKeyDown() and "SHIFT-" or "")
                .. key
            Store:SetKey(Editor.selected, combo)
        end
    end)
    view.key:SetScript("OnHide", function(button)
        if button.capturing then
            button:StopCapture()
        end
    end)

    local deleteRow = card:AddRow(ROW)
    view.delete = W.Button(deleteRow, {
        text = L.DELETE,
        variant = "danger",
        onClick = function()
            Store:Delete(Editor.selected)
            Editor.selected = nil
            view:Refresh()
        end,
    })
    view.delete:SetPoint("RIGHT", -ROW_X, 0)

    view.discRows = { nameRow, keyRow, deleteRow }
    return card
end

-- Slots card --------------------------------------------------------------------------------------

local function slotMenu(view, button, index)
    local id = Editor.selected
    local disc = Store:Get(id)
    local entries = {}
    if index > 1 then
        entries[#entries + 1] = {
            text = L.MOVE_UP,
            onClick = function()
                Store:MoveSlot(id, index, -1)
            end,
        }
    end
    if index < #disc.slots then
        entries[#entries + 1] = {
            text = L.MOVE_DOWN,
            onClick = function()
                Store:MoveSlot(id, index, 1)
            end,
        }
    end
    entries[#entries + 1] = {
        text = L.RENAME,
        onClick = function()
            Editor.editing = { mode = "rename", index = index }
            view:Refresh()
        end,
    }
    entries[#entries + 1] = {
        text = L.SET_ICON,
        onClick = function()
            Editor.editing = { mode = "icon", index = index }
            view:Refresh()
        end,
    }
    local slot = disc.slots[index]
    if slot.name or slot.icon then
        entries[#entries + 1] = {
            text = L.RESET_LOOK,
            onClick = function()
                Store:SetSlotLook(id, index, nil, nil)
            end,
        }
    end
    entries[#entries + 1] = {
        text = L.REMOVE,
        onClick = function()
            Store:RemoveSlot(id, index)
        end,
    }
    W.Menu.Open(button, entries, 220)
end

local function slotRow(view, card, i)
    local row = card:AddRow(SLOT_ROW)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(26, 26)
    row.icon:SetPoint("LEFT", ROW_X, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.text = W.Text(row, "")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", Theme.space.sm, 0)
    row.kind = W.Text(row, "", "small", "muted")
    row.menu = W.IconButton(row, {
        icon = "menu",
        onClick = function(button)
            slotMenu(view, button, row.index)
        end,
    })
    row.menu:SetPoint("RIGHT", -ROW_X + 4, 0)
    row.kind:SetPoint("RIGHT", row.menu, "LEFT", -Theme.space.sm, 0)
    row.text:SetPoint("RIGHT", row.kind, "LEFT", -Theme.space.sm, 0)
    row.text:SetWordWrap(false)
    row.index = i
    return row
end

local function buildSlotsCard(view)
    local card = rowCard(view)
    view.slotRows = {}

    -- Inline editor for a slot's name or icon (shown above the list while editing).
    view.editRow = card:AddRow(ROW)
    view.editLabel = W.Text(view.editRow, "")
    view.editLabel:SetPoint("LEFT", ROW_X, 0)
    view.editInput = W.Input(view.editRow, {
        width = CONTROL,
        maxLetters = 60,
        onEnter = function(text)
            local editing = Editor.editing
            Editor.editing = nil
            if not editing then
                return
            end
            local slot = Store:Get(Editor.selected).slots[editing.index]
            text = strtrim(text)
            if editing.mode == "rename" then
                Store:SetSlotLook(Editor.selected, editing.index, text ~= "" and text or nil, slot.icon)
            else
                Store:SetSlotLook(Editor.selected, editing.index, slot.name, text ~= "" and Resolve.Icon(text) or nil)
            end
        end,
        onEscape = function()
            Editor.editing = nil
            view:Refresh()
        end,
    })
    view.editInput:SetPoint("RIGHT", -ROW_X, 0)

    view.slotsEmpty = card:AddRow(ROW)
    local empty = W.Text(view.slotsEmpty, L.EMPTY, "body", "muted")
    empty:SetPoint("LEFT", ROW_X, 0)
    view.slotsCard = card
    return card
end

-- Add card ----------------------------------------------------------------------------------------

local function addSlot(view, slot)
    if not slot then
        return
    end
    local ok, reason = Store:AddSlot(Editor.selected, slot)
    if not ok and reason == "cycle" then
        say(L.CYCLE)
    end
    view:Refresh()
end

local function buildAddCard(view)
    local card = rowCard(view)

    local dropRow = card:AddRow(ROW + 8)
    view.drop = W.Button(dropRow, {
        text = L.DROP,
        icon = "plus",
        onClick = function()
            local slot = Resolve.FromCursor()
            if slot then
                ClearCursor()
                addSlot(view, slot)
            end
        end,
    })
    view.drop:SetPoint("LEFT", ROW_X, 0)
    view.drop:SetPoint("RIGHT", -ROW_X, 0)
    view.drop:SetScript("OnReceiveDrag", function(button)
        button:Click()
    end)
    W.AttachTooltip(view.drop, function(tip)
        tip:SetTitle(L.DROP)
        tip:AddLine(L.DROP_HINT)
    end, "TOP")

    local searchRow = card:AddRow(ROW)
    label(searchRow, L.SEARCH)
    view.search = W.Input(searchRow, {
        width = CONTROL,
        maxLetters = 80,
        onEnter = function(text)
            local slot = Resolve.Search(text)
            if slot then
                view.search:SetText("")
                addSlot(view, slot)
            else
                say(L.SEARCH_NOT_FOUND)
            end
        end,
    })
    view.search:SetPoint("RIGHT", -ROW_X, 0)

    local specialRow = card:AddRow(ROW)
    label(specialRow, L.ADD_SPECIAL)
    view.special = W.Dropdown(specialRow, {
        width = CONTROL,
        placeholder = L.ADD_SPECIAL,
        onChange = function(value)
            view.special:SetValue(nil)
            if value == "text" then
                view.textRow:Show()
                view:Relayout()
                view.text:SetFocus()
            elseif value == "hearthstone" or value == "professions" then
                addSlot(view, { kind = value })
            elseif type(value) == "number" then
                addSlot(view, { kind = "disc", disc = value })
            end
        end,
    })
    view.special:SetPoint("RIGHT", -ROW_X, 0)

    view.textRow = card:AddRow(ROW)
    label(view.textRow, L.MACROTEXT)
    view.text = W.Input(view.textRow, {
        width = CONTROL,
        maxLetters = 255,
        placeholder = L.MACROTEXT_HINT,
        onEnter = function(text)
            text = strtrim((text:gsub("\\n", "\n")))
            view.text:SetText("")
            view.textRow:Hide()
            if text ~= "" then
                addSlot(view, { kind = "text", text = text })
            else
                view:Relayout()
            end
        end,
    })
    view.text:SetPoint("RIGHT", -ROW_X, 0)
    view.textRow:Hide()
    return card
end

-- The tab -------------------------------------------------------------------------------------------

--- Builds the Discs tab.
---@param parent table
---@param setHeight fun(height: number)
---@return table
function Editor.Build(parent, setHeight)
    local view = W.Stack(parent)
    Editor.view = view
    view.discsCard = view:Add(buildDiscsCard(view))
    view.slotsCaption = view:Add(W.Text(view, L.SLOTS, "caption", "muted"), Theme.space.xxl)
    view:Add(buildSlotsCard(view), Theme.space.sm + 2)
    view.addCaption = view:Add(W.Text(view, L.ADD, "caption", "muted"), Theme.space.xxl)
    view.addCard = view:Add(buildAddCard(view), Theme.space.sm + 2)

    function view:Relayout()
        self.discsCard:Layout()
        self.slotsCard:Layout()
        self.addCard:Layout()
        setHeight(self:Layout())
    end

    function view:Refresh()
        local discs = Store:List()
        if not Store:Get(Editor.selected) then
            Editor.selected = discs[1] and discs[1].id or nil
        end
        local disc = Store:Get(Editor.selected)

        local options = {}
        for _, d in ipairs(discs) do
            options[#options + 1] = { value = d.id, text = d.name }
        end
        self.picker:SetOptions(options)
        self.picker:SetValue(Editor.selected)
        self.emptyRow:SetShown(disc == nil)
        for _, row in ipairs(self.discRows) do
            row:SetShown(disc ~= nil)
        end
        self.slotsCaption:SetShown(disc ~= nil)
        self.slotsCard:SetShown(disc ~= nil)
        self.addCaption:SetShown(disc ~= nil)
        self.addCard:SetShown(disc ~= nil)
        if not disc then
            self:Relayout()
            return
        end

        if not self.name:HasFocus() then
            self.name:SetText(disc.name)
        end
        if not self.key.capturing then
            self.key:SetText(keyText(Store:Keys()[disc.id]))
        end

        -- Slots.
        for i, slot in ipairs(disc.slots) do
            local row = self.slotRows[i] or slotRow(self, self.slotsCard, i)
            self.slotRows[i] = row
            local text, icon, kind = Resolve.Describe(slot)
            row.icon:SetTexture(icon)
            row.text:SetText(text)
            row.kind:SetText(kind)
            row:Show()
        end
        for i = #disc.slots + 1, #self.slotRows do
            self.slotRows[i]:Hide()
        end
        self.slotsEmpty:SetShown(#disc.slots == 0)
        local editing = Editor.editing
        self.editRow:SetShown(editing ~= nil and disc.slots[editing.index] ~= nil)
        -- A refresh while typing leaves the box alone.
        if self.editRow:IsShown() and not self.editInput:HasFocus() then
            local slot = disc.slots[editing.index]
            self.editLabel:SetText(editing.mode == "rename" and L.RENAME or L.SET_ICON)
            self.editInput:SetText(editing.mode == "rename" and (slot.name or Resolve.Describe(slot)) or "")
            self.editInput.placeholder:SetText(editing.mode == "icon" and L.ICON_HINT or "")
            self.editInput:SetFocus()
        end

        -- Special slots: hearthstone, professions, macro text and the discs that can go inside.
        local special = {
            { value = "hearthstone", text = L.HEARTHSTONE },
            { value = "professions", text = L.PROFESSIONS },
            { value = "text", text = L.MACROTEXT },
        }
        for _, d in ipairs(discs) do
            if not Store:Reaches(d.id, disc.id) then
                special[#special + 1] = { value = d.id, text = L.KIND_disc .. ": " .. d.name }
            end
        end
        self.special:SetOptions(special)
        self.drop:SetUsable(#disc.slots < Store.MAX_SLOTS)
        self:Relayout()
    end

    Store:OnChange(function()
        if view:IsVisible() then
            view:Refresh()
        end
    end)
    view:SetScript("OnShow", view.Refresh)
    view:Refresh()
    return view
end
