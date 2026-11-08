-- The Mover's toolbar and the panel of the selected element.
---@type string, table
local _, ns = ...
local L = ns.L
local E = EternityUI
local Mover = E.Mover
local Shape = E.Shape
local Theme = E.Theme
local Widgets = E.Widgets

local Chrome = {}
ns.MoverChrome = Chrome

local toolbar, panel, gridButton, snapButton

local function session()
    return ns.MoverSession
end

local function surface(frame)
    frame.shape = Shape.New(frame)
    frame:EnableMouse(true)
    function frame:Paint()
        Theme.PaintWindow(self.shape)
    end
    Widgets.Track(frame)
end

-- Dragged from any empty spot; the spot is kept for the account (raw[key], offsets from the
-- screen's top left). A right click puts it back where it starts (home).
local function draggable(frame, root, key, home)
    local function place()
        local saved = E.store.raw[key]
        frame:ClearAllPoints()
        if saved then
            frame:SetPoint("TOPLEFT", root, "TOPLEFT", saved.x, saved.y)
        else
            home(frame)
        end
    end
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetUserPlaced(false)
        local left, top = self:GetLeft(), self:GetTop()
        local rootLeft, rootTop = root:GetLeft(), root:GetTop()
        if left and top and rootLeft and rootTop then
            E.store.raw[key] = { x = left - rootLeft, y = top - rootTop }
        end
        place()
    end)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            E.store.raw[key] = nil
            place()
        end
    end)
    place()
end

-- A column of dots at the toolbar's left: where to grab it.
local function grip(frame)
    local dots = {}
    for row = 0, 2 do
        for column = 0, 1 do
            local dot = frame:CreateTexture(nil, "OVERLAY")
            dot:SetColorTexture(1, 1, 1, 1)
            dot:SetSize(3, 3)
            dot:SetPoint("LEFT", 9 + column * 5, (1 - row) * 6)
            dots[#dots + 1] = dot
        end
    end
    local paint = frame.Paint
    function frame:Paint()
        paint(self)
        for _, dot in ipairs(dots) do
            dot:SetVertexColor(Theme.Color("textMuted"))
        end
    end
    if Theme.accent then
        frame:Paint()
    end
end

local function buildToolbar(root)
    toolbar = CreateFrame("Frame", nil, root)
    toolbar:SetHeight(46)
    toolbar:SetFrameLevel(root:GetFrameLevel() + 20)
    surface(toolbar)
    grip(toolbar)
    -- Moved like the panel, by the grip or any gap between the buttons (raw.moverToolbar).
    draggable(toolbar, root, "moverToolbar", function(self)
        self:SetPoint("TOP", 0, -14)
    end)

    local x = 24
    local function add(button, width)
        button:SetWidth(width or math.max(button.label:GetStringWidth() + 24, 70))
        button:SetPoint("LEFT", x, 0)
        x = x + button:GetWidth() + 6
        return button
    end
    gridButton = add(Widgets.Button(toolbar, L.MOVER_GRID, "nav", function()
        ns.MoverScene.showGrid = not ns.MoverScene.showGrid
        ns.MoverScene.Refresh()
    end))
    snapButton = add(Widgets.Button(toolbar, L.MOVER_MAGNET, "nav", function()
        ns.MoverScene.snap = not ns.MoverScene.snap
        ns.MoverScene.Refresh()
    end))
    add(Widgets.Button(toolbar, L.MOVER_UNDO, "ghost", session().Undo))
    add(Widgets.Button(toolbar, L.MOVER_REDO, "ghost", session().Redo))
    add(Widgets.Button(toolbar, L.MOVER_DISCARD, "ghost", session().Discard))
    add(Widgets.Button(toolbar, L.MOVER_SAVE, "primary", session().Save))

    -- Blizzard's Edit Mode, for the frames it places (buff icons' layout, tracker size...). Opened
    -- by a secure macro button running /editmode, so no addon code opens the panel (that would
    -- taint it). The Mover then saves and closes.
    local editMode = add(Widgets.Button(toolbar, L.MOVER_EDITMODE, "ghost", function() end))
    local secure = CreateFrame("Button", nil, editMode, "SecureActionButtonTemplate")
    secure:SetAllPoints(editMode)
    secure:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
    secure:SetAttribute("useOnKeyDown", false)
    secure:SetAttribute("type", "macro")
    secure:SetAttribute("macrotext", "/editmode")
    -- Only on release: closing the Mover on the press would hide the button before the macro runs.
    secure:HookScript("OnClick", function(_, _, down)
        if not down and session().active then
            session().Save()
        end
    end)
    Widgets.AttachTooltip(secure, function(tip)
        tip:SetTitle(L.MOVER_EDITMODE)
        tip:AddLine(L.MOVER_EDITMODE_HINT, "textMuted")
    end)
    toolbar:SetWidth(x + 2)
end

local function setCoordinate(axis, text)
    local key = session().selected
    local value = tonumber(text)
    if not key or not value then
        ns.MoverScene.Refresh()
        return
    end
    session().Checkpoint()
    local entry = E.DeepCopy(session().Entry(key))
    entry[axis] = value
    session().Set(key, entry)
end

-- Scale typed in the panel, kept between the Mover's limits; 1 removes it.
local function setScale(text)
    local key = session().selected
    local value = tonumber(text)
    if not key or not value or not Mover.IsScalable(key) then
        ns.MoverScene.Refresh()
        return
    end
    value = math.floor(math.min(math.max(value, Mover.MIN_SCALE), Mover.MAX_SCALE) * 100 + 0.5) / 100
    session().Checkpoint()
    local entry = E.DeepCopy(session().Entry(key))
    entry.scale = value ~= 1 and value or nil
    session().Set(key, entry)
end

local function coordinate(parent, name, axis, x, y)
    y = y or -62
    local label = Widgets.Text(parent, 13, "muted")
    label:SetPoint("TOPLEFT", x, y)
    label:SetText(name)
    local box = Widgets.Input(parent, function(text)
        if axis == "scale" then
            setScale(text)
        else
            setCoordinate(axis, text)
        end
    end)
    box:SetPoint("TOPLEFT", x, y - 16)
    box:SetWidth(102)
    return box
end

local function buildPanel(root)
    panel = CreateFrame("Frame", nil, root)
    panel:SetSize(244, 286)
    panel:SetFrameLevel(root:GetFrameLevel() + 20)
    surface(panel)

    -- Moved by any empty spot (raw.moverPanel); a right click puts it back in its corner.
    draggable(panel, root, "moverPanel", function(self)
        self:SetPoint("TOPRIGHT", -16, -76)
    end)

    panel.title = Widgets.Text(panel, 18, "text")
    panel.title:SetPoint("TOPLEFT", 14, -14)
    panel.anchor = Widgets.Text(panel, 13, "muted")
    panel.anchor:SetPoint("TOPLEFT", 14, -38)
    panel.anchor:SetPoint("TOPRIGHT", -14, -38)
    panel.anchor:SetJustifyH("LEFT")
    panel.x = coordinate(panel, "X", "x", 14)
    panel.y = coordinate(panel, "Y", "y", 128)
    panel.scale = coordinate(panel, L.MOVER_SCALE, "scale", 14, -116)
    panel.scaleHint = Widgets.Text(panel, 12, "muted")
    panel.scaleHint:SetPoint("LEFT", panel.scale, "RIGHT", 10, 0)
    panel.scaleHint:SetPoint("RIGHT", -14, 0)
    panel.scaleHint:SetJustifyH("LEFT")
    panel.scaleHint:SetText(L.MOVER_SCALE_HINT)

    local function action(text, y, onClick)
        local button = Widgets.Button(panel, text, "ghost", onClick)
        button:SetPoint("TOPLEFT", 14, y)
        button:SetPoint("TOPRIGHT", -14, y)
        return button
    end
    panel.lock = action(L.MOVER_LOCK, -172, function()
        local key = session().selected
        session().Checkpoint()
        local entry = E.DeepCopy(session().Entry(key))
        entry.locked = not entry.locked or nil
        session().Set(key, entry)
    end)
    panel.options = action(L.MOVER_OPTIONS, -206, function()
        Mover.elements[session().selected].openOptions()
    end)
    panel.reset = action(L.MOVER_RESET, -240, function()
        session().Checkpoint()
        session().Set(session().selected, nil)
    end)
end

--- Builds the toolbar and the panel.
---@param root table
function Chrome.Build(root)
    buildToolbar(root)
    buildPanel(root)

    -- Arrows nudge; every other key goes on to the game. The Mover hides in combat.
    root:EnableKeyboard(true)
    root:SetScript("OnKeyDown", function(self, key)
        local step = IsShiftKeyDown() and 10 or 1
        local moves = { UP = { 0, step }, DOWN = { 0, -step }, LEFT = { -step, 0 }, RIGHT = { step, 0 } }
        local move = moves[key]
        local focused = GetCurrentKeyBoardFocus()
        self:SetPropagateKeyboardInput(not (move and session().selected and not focused))
        if move and session().selected and not focused then
            ns.MoverHandles.Nudge(move[1], move[2])
        end
    end)
end

--- Updates the toolbar's switches and the panel from the session.
function Chrome.Refresh()
    gridButton:SetActive(ns.MoverScene.showGrid)
    snapButton:SetActive(ns.MoverScene.snap)
    local key = session().selected
    local element = key and Mover.elements[key]
    panel:SetShown(element ~= nil)
    if not element then
        return
    end
    local entry = session().Entry(key)
    panel.title:SetText(element.label)
    panel.anchor:SetText(L.MOVER_ANCHOR:format(L["POINT_" .. entry.point]))
    if not panel.x:HasFocus() then
        panel.x:SetText(string.format("%.1f", entry.x))
    end
    if not panel.y:HasFocus() then
        panel.y:SetText(string.format("%.1f", entry.y))
    end
    if not panel.scale:HasFocus() then
        panel.scale:SetText(string.format("%.2f", entry.scale or 1))
    end
    local scalable = Mover.IsScalable(key)
    panel.scale:SetEnabled(scalable and not entry.locked)
    panel.scale:SetAlpha(scalable and 1 or 0.4)
    panel.lock.label:SetText(entry.locked and L.MOVER_UNLOCK or L.MOVER_LOCK)
    panel.options:SetShown(element.openOptions ~= nil)
end
