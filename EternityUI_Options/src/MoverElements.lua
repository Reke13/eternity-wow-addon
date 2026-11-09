-- The Mover's "Elements" panel: which elements the Mover draws a handle for, to place the rest
-- without the clutter. It only touches the Mover: a hidden element is still shown in the game,
-- in its place. The choice is kept for the account (raw.moverHidden[key] = true).
---@type string, table
local _, ns = ...
local L = ns.L
local E = EternityUI
local Mover = E.Mover
local Shape = E.Shape
local Theme = E.Theme
local Widgets = E.Widgets

local ROW = 28
local HEADER = 30
local WIDTH = 300
local HEIGHT = 420

local Elements = {}
ns.MoverElements = Elements
E.MoverElements = Elements

local panel

--- The account's hidden elements.
---@return table<string, boolean>
local function hiddenSet()
    E.store.raw.moverHidden = type(E.store.raw.moverHidden) == "table" and E.store.raw.moverHidden or {}
    return E.store.raw.moverHidden
end

--- Whether the Mover draws a handle for this element.
---@param key string
---@return boolean
function Elements.IsShown(key)
    local hidden = E.store.raw.moverHidden
    return not (type(hidden) == "table" and hidden[key])
end

local function changed()
    local selected = ns.MoverSession.selected
    if selected and not Elements.IsShown(selected) then
        ns.MoverSession.Select(nil)
    else
        ns.MoverScene.RefreshElements()
    end
    Elements.Refresh()
end

--- Shows or hides the handles of some elements.
---@param keys string[]
---@param shown boolean
function Elements.Set(keys, shown)
    local hidden = hiddenSet()
    for _, key in ipairs(keys) do
        hidden[key] = not shown or nil
    end
    changed()
end

-- The module that registered an element, by its title; elements of no module go last.
local function groups()
    local byOwner, list = {}, {}
    for _, element in ipairs(Mover.List()) do
        local owner = element.owner or ""
        local group = byOwner[owner]
        if not group then
            local module = element.owner and E:GetModule(element.owner)
            local title = module and module.schema and E.Localize(module.schema.title) or nil
            group = { owner = owner, title = title ~= "" and title or L.MOVER_ELEMENTS_OTHER, elements = {} }
            byOwner[owner] = group
            list[#list + 1] = group
        end
        group.elements[#group.elements + 1] = element
    end
    table.sort(list, function(a, b)
        if (a.owner == "") ~= (b.owner == "") then
            return b.owner == ""
        end
        return a.title < b.title
    end)
    return list
end

local function keysOf(elements)
    local keys = {}
    for _, element in ipairs(elements) do
        keys[#keys + 1] = element.key
    end
    return keys
end

-- Pooled rows: a module's title with its own switch, or an element with its switch.
local function row(index)
    local rows = panel.rows
    local r = rows[index]
    if r then
        return r
    end
    r = CreateFrame("Frame", nil, panel.scroll.child)
    r:SetHeight(ROW)
    r.label = Widgets.Text(r, 13, "text")
    r.label:SetPoint("LEFT", 6, 0)
    r.label:SetJustifyH("LEFT")
    r.toggle = Widgets.Toggle(r, function(value)
        Elements.Set(r.keys, value)
    end)
    r.toggle:SetPoint("RIGHT", -4, 0)
    r.label:SetPoint("RIGHT", r.toggle, "LEFT", -8, 0)
    rows[index] = r
    return r
end

--- Redraws the list from the elements registered now.
function Elements.Refresh()
    if not panel or not panel:IsShown() then
        return
    end
    local used, y = 0, 0
    for _, group in ipairs(groups()) do
        used = used + 1
        local head = row(used)
        head:SetHeight(HEADER)
        head.keys = keysOf(group.elements)
        head.label:SetText(group.title)
        Widgets.SetTextSize(head.label, 14)
        head.label:SetTextColor(Theme.Color("accentText"))
        local any = false
        for _, element in ipairs(group.elements) do
            any = any or Elements.IsShown(element.key)
        end
        head.toggle:SetValue(any)
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", 0, -y)
        head:SetPoint("TOPRIGHT", 0, -y)
        head:Show()
        y = y + HEADER
        for _, element in ipairs(group.elements) do
            used = used + 1
            local r = row(used)
            r:SetHeight(ROW)
            r.keys = { element.key }
            r.label:SetText(element.label)
            Widgets.SetTextSize(r.label, 13)
            r.label:SetTextColor(Theme.Color("text"))
            r.toggle:SetValue(Elements.IsShown(element.key))
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 12, -y)
            r:SetPoint("TOPRIGHT", 0, -y)
            r:Show()
            y = y + ROW
        end
    end
    for i = used + 1, #panel.rows do
        panel.rows[i]:Hide()
    end
    panel.scroll:SetContentHeight(math.max(y, 1))
end

local function build(root)
    panel = CreateFrame("Frame", nil, root)
    panel:SetSize(WIDTH, HEIGHT)
    panel:SetFrameLevel(root:GetFrameLevel() + 25)
    panel:EnableMouse(true)
    panel.shape = Shape.New(panel)
    function panel:Paint()
        Theme.PaintWindow(self.shape)
    end
    Widgets.Track(panel)
    panel:SetPoint("TOPLEFT", 16, -76)
    panel.rows = {}

    panel.title = Widgets.Text(panel, 16, "text")
    panel.title:SetPoint("TOPLEFT", 14, -14)
    panel.title:SetText(L.MOVER_ELEMENTS)
    panel.note = Widgets.Text(panel, 12, "muted")
    panel.note:SetPoint("TOPLEFT", 14, -36)
    panel.note:SetPoint("TOPRIGHT", -14, -36)
    panel.note:SetJustifyH("LEFT")
    panel.note:SetText(L.MOVER_ELEMENTS_NOTE)

    local all = Widgets.Button(panel, L.MOVER_ELEMENTS_ALL, "ghost", function()
        Elements.Set(keysOf(Mover.List()), true)
    end)
    local none = Widgets.Button(panel, L.MOVER_ELEMENTS_NONE, "ghost", function()
        Elements.Set(keysOf(Mover.List()), false)
    end)
    all:SetPoint("BOTTOMLEFT", 14, 12)
    all:SetPoint("RIGHT", panel, "BOTTOM", -4, 0)
    none:SetPoint("BOTTOMRIGHT", -14, 12)
    none:SetPoint("LEFT", panel, "BOTTOM", 4, 0)

    panel.scroll = Widgets.Scroll(panel)
    panel.scroll:SetPoint("TOPLEFT", 14, -70)
    panel.scroll:SetPoint("BOTTOMRIGHT", -10, 52)
    panel:Hide()
end

--- Opens or closes the panel.
---@param root table the Mover's root frame
function Elements.Toggle(root)
    if not panel then
        build(root)
    end
    panel:SetShown(not panel:IsShown())
    Elements.Refresh()
    ns.MoverChrome.Refresh()
end

--- Whether the panel is open.
function Elements.IsOpen()
    return panel ~= nil and panel:IsShown()
end

--- Closes the panel (when the Mover closes).
function Elements.Close()
    if panel then
        panel:Hide()
    end
end
