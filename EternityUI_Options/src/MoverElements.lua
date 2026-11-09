-- The Mover's "Elements" panel: which elements the Mover draws a handle for, to place the rest
-- without the clutter. It only touches the Mover: a hidden element is still shown in the game,
-- in its place. The choice is kept for the account (raw.moverHidden[key] = true).
-- The panel moves by any empty spot and resizes by its corner; both are kept for the account
-- (raw.moverElements, raw.moverElementsSize). A right click on it puts it back where it starts.
-- Each module's section folds by its title (raw.moverElementsOpen[owner] = true when open);
-- in a module's own Mover its only section is always open.
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
local MIN_W, MIN_H, MAX_W, MAX_H = 240, 240, 700, 1000
local GRIP = 16

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

-- A Mover opened from a module's page shows only that module (Session.only), with its own
-- switches for the session (Session.onlyHidden); the account's choice stays as it was.
local function only()
    local session = ns.MoverSession
    return session and session.active and session.only or nil
end

--- Whether the Mover draws a handle for this element.
---@param key string
---@return boolean
function Elements.IsShown(key)
    local owner = only()
    if owner then
        local element = Mover.elements[key]
        return element ~= nil and element.owner == owner and not ns.MoverSession.onlyHidden[key]
    end
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
    local hidden = only() and ns.MoverSession.onlyHidden or hiddenSet()
    for _, key in ipairs(keys) do
        hidden[key] = not shown or nil
    end
    changed()
end

-- The module that registered an element, by its title; elements of no module go last.
local function groups()
    local byOwner, list = {}, {}
    local filter = only()
    local function add(element, owner)
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
    for _, element in ipairs(Mover.List()) do
        local owner = element.owner or ""
        -- In a module's Mover, another module's elements aren't listed.
        if not filter or owner == filter then
            add(element, owner)
        end
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

-- Whether a module's section is unfolded.
local function isOpen(owner)
    if only() then
        return true
    end
    local open = E.store.raw.moverElementsOpen
    return type(open) == "table" and open[owner] == true
end

local function setOpen(owner, value)
    E.store.raw.moverElementsOpen = type(E.store.raw.moverElementsOpen) == "table" and E.store.raw.moverElementsOpen or {}
    E.store.raw.moverElementsOpen[owner] = value or nil
end

-- Pooled rows: a module's title (it folds its section) with a switch for all of it, or an
-- element with its switch.
local function row(index)
    local rows = panel.rows
    local r = rows[index]
    if r then
        return r
    end
    r = CreateFrame("Button", nil, panel.scroll.child)
    r:SetHeight(ROW)
    r:RegisterForClicks("LeftButtonUp")
    r.fold = r:CreateTexture(nil, "ARTWORK")
    r.fold:SetSize(14, 14)
    r.fold:SetPoint("LEFT", 2, 0)
    r.label = Widgets.Text(r, 13, "text")
    r.label:SetJustifyH("LEFT")
    r.toggle = Widgets.Toggle(r, function(value)
        Elements.Set(r.keys, value)
    end)
    r.toggle:SetPoint("RIGHT", -4, 0)
    r.label:SetPoint("RIGHT", r.toggle, "LEFT", -8, 0)
    r:SetScript("OnClick", function(self)
        if self.owner and not only() then
            setOpen(self.owner, not isOpen(self.owner))
            Elements.Refresh()
        end
    end)
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
        local open = isOpen(group.owner)
        head:SetHeight(HEADER)
        head.owner = group.owner
        head.keys = keysOf(group.elements)
        head.fold:Show()
        head.fold:SetTexture(open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
        head.label:ClearAllPoints()
        head.label:SetPoint("LEFT", head.fold, "RIGHT", 6, 0)
        head.label:SetPoint("RIGHT", head.toggle, "LEFT", -8, 0)
        head.label:SetText(("%s  (%d)"):format(group.title, #group.elements))
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
        for _, element in ipairs(open and group.elements or {}) do
            used = used + 1
            local r = row(used)
            r:SetHeight(ROW)
            r.owner = nil
            r.fold:Hide()
            r.label:ClearAllPoints()
            r.label:SetPoint("LEFT", 6, 0)
            r.label:SetPoint("RIGHT", r.toggle, "LEFT", -8, 0)
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
    local size = E.store.raw.moverElementsSize
    panel:SetSize(size and size.w or WIDTH, size and size.h or HEIGHT)
    panel:SetFrameLevel(root:GetFrameLevel() + 25)
    panel:EnableMouse(true)
    panel.shape = Shape.New(panel)
    function panel:Paint()
        Theme.PaintWindow(self.shape)
    end
    Widgets.Track(panel)
    panel.rows = {}
    ns.MoverChrome.Draggable(panel, root, "moverElements", function(self)
        self:SetPoint("TOPLEFT", 16, -76)
    end)

    -- Resized by the bottom right corner. The size follows the cursor (no StartSizing: with the
    -- panel kept on screen the game re-anchors it while sizing, and it jumped); the top left
    -- corner stays put and the panel never leaves the screen.
    local grip = CreateFrame("Button", nil, panel)
    grip:SetSize(GRIP, GRIP)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(panel:GetFrameLevel() + 10)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    local function pin()
        -- Anchored by the top left corner to the Mover's root, where it is now.
        local left, top = panel:GetLeft(), panel:GetTop()
        local rootLeft, rootTop = root:GetLeft(), root:GetTop()
        if left and top and rootLeft and rootTop then
            panel:ClearAllPoints()
            panel:SetPoint("TOPLEFT", root, "TOPLEFT", left - rootLeft, top - rootTop)
            E.store.raw.moverElements = { x = left - rootLeft, y = top - rootTop }
        end
    end
    local function limits()
        local left, top = panel:GetLeft() or 0, panel:GetTop() or 0
        local right, bottom = root:GetRight() or MAX_W, root:GetBottom() or 0
        return math.min(MAX_W, right - left), math.min(MAX_H, top - bottom)
    end
    grip:SetScript("OnMouseDown", function()
        pin()
        local x, y = GetCursorPosition()
        local scale = panel:GetEffectiveScale()
        grip.start = { x = x / scale, y = y / scale, w = panel:GetWidth(), h = panel:GetHeight() }
        grip:SetScript("OnUpdate", function()
            local cx, cy = GetCursorPosition()
            cx, cy = cx / scale, cy / scale
            local maxW, maxH = limits()
            local w = math.min(math.max(grip.start.w + cx - grip.start.x, MIN_W), math.max(maxW, MIN_W))
            local h = math.min(math.max(grip.start.h + grip.start.y - cy, MIN_H), math.max(maxH, MIN_H))
            panel:SetSize(math.floor(w + 0.5), math.floor(h + 0.5))
        end)
    end)
    grip:SetScript("OnMouseUp", function()
        grip:SetScript("OnUpdate", nil)
        grip.start = nil
        E.store.raw.moverElementsSize = { w = math.floor(panel:GetWidth() + 0.5), h = math.floor(panel:GetHeight() + 0.5) }
        pin()
        Elements.Refresh()
    end)
    grip:SetScript("OnHide", function()
        grip:SetScript("OnUpdate", nil)
    end)
    panel.grip = grip

    panel.title = Widgets.Text(panel, 16, "text")
    panel.title:SetPoint("TOPLEFT", 14, -14)
    panel.title:SetText(L.MOVER_ELEMENTS)
    -- Closes it from here too, like the core's windows (the toolbar button still toggles it).
    panel.close = Widgets.Button(panel, "×", "ghost", function()
        Elements.Toggle(root)
    end)
    panel.close:SetSize(26, 26)
    panel.close:SetPoint("TOPRIGHT", -8, -8)
    panel.title:SetPoint("RIGHT", panel.close, "LEFT", -8, 0)
    panel.title:SetJustifyH("LEFT")
    panel.note = Widgets.Text(panel, 12, "muted")
    panel.note:SetPoint("TOPLEFT", 14, -36)
    panel.note:SetPoint("TOPRIGHT", -14, -36)
    panel.note:SetJustifyH("LEFT")
    panel.note:SetText(L.MOVER_ELEMENTS_NOTE)

    -- Every element of the list (in a module's Mover, only its own).
    local function listed()
        local elements = {}
        for _, group in ipairs(groups()) do
            for _, element in ipairs(group.elements) do
                elements[#elements + 1] = element
            end
        end
        return keysOf(elements)
    end
    local all = Widgets.Button(panel, L.MOVER_ELEMENTS_ALL, "ghost", function()
        Elements.Set(listed(), true)
    end)
    local none = Widgets.Button(panel, L.MOVER_ELEMENTS_NONE, "ghost", function()
        Elements.Set(listed(), false)
    end)
    all:SetPoint("BOTTOMLEFT", 14, 12)
    all:SetPoint("RIGHT", panel, "BOTTOM", -4, 0)
    none:SetPoint("BOTTOMRIGHT", -14, 12)
    none:SetPoint("LEFT", panel, "BOTTOM", 4, 0)

    panel.scroll = Widgets.Scroll(panel)
    panel.scroll:SetPoint("TOPLEFT", 14, -70)
    panel.scroll:SetPoint("BOTTOMRIGHT", -10, 52)
    panel:SetScript("OnSizeChanged", function()
        Elements.Refresh()
    end)
    panel:Hide()
end

--- Opens or closes the panel.
---@param root table the Mover's root frame
function Elements.Toggle(root)
    if not panel then
        build(root)
    end
    if not panel:IsShown() then
        -- The size the player left it at.
        local size = E.store.raw.moverElementsSize
        if type(size) == "table" and size.w and size.h then
            panel:SetSize(size.w, size.h)
        end
    end
    panel:SetShown(not panel:IsShown())
    panel.note:SetText(only() and L.MOVER_ELEMENTS_ONLY or L.MOVER_ELEMENTS_NOTE)
    Elements.Refresh()
    ns.MoverChrome.Refresh()
end

--- The panel, once built (for the tests).
function Elements.Panel()
    return panel
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
