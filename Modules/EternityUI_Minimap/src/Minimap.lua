-- EternityUI_Minimap: the minimap with the Eternity look.
--   * Shape (round, rounded square or square), border, shadow, glow, opacity, scale and,
--     in Forever (no Edit Mode for the minimap), position.
--   * Its own information (zone, time and coordinates) inside or outside the map.
--   * Each Blizzard element (header, calendar, clock, tracking...) can be hidden.
--   * Collector: the buttons addons place around the minimap (LibDBIcon and any other named
--     button that is a child of Minimap or MinimapBackdrop) move to a panel opened from our own
--     button on the edge. Other addons' map pins stay where they are.
-- No taint: it replaces no Blizzard method and touches no protected frame. Hidden elements are
-- moved to a hidden frame (so it doesn't matter if Blizzard calls Show on them) and go back to their parent.
-- When disabled everything goes back to how it was, without /reload. Hooks can't be removed: they're
-- installed once and do nothing while `running` is false.

---The module's private table.
---@class EternityUIMinimapNamespace
---@field OptionsSchema table schema generated from options.json (src/Generated/Options.lua)

---@type string, EternityUIMinimapNamespace
local addonName, ns = ...
local E = EternityUI
local Shape, Theme, Widgets = E.Shape, E.Theme, E.Widgets

local strings = {
    enUS = {
        COLLECTOR = "Addon buttons",
        EMPTY = "No addon buttons",
        HINT_CLICK = "Click: open · Right-click: options · Drag: move",
        HINT_HOVER = "Right-click: options · Drag: move",
        MOVER = "Minimap",
    },
    esES = {
        COLLECTOR = "Botones de addons",
        EMPTY = "No hay botones de addons",
        HINT_CLICK = "Clic: abrir · Clic derecho: opciones · Arrastrar: mover",
        HINT_HOVER = "Clic derecho: opciones · Arrastrar: mover",
        MOVER = "Minimapa",
    },
}
local L = E.NewLocale(strings.enUS, strings.esES)

local WHITE = "Interface\\Buttons\\WHITE8X8"
-- Round mask in Retail (in Forever MinimapCluster:UpdateMinimapConfig sets it). Blizzard's
-- can't be requested by path ("Textures\\MinimapMask" leaves the map undrawn, seen
-- in Retail 12.1.5 on 2026-10-30): Eternity's circle is used instead.
local ROUND_MASK = Theme.MEDIA .. "circle.tga"
-- Mask and background (border) of each shape. The round one uses Blizzard's mask (ROUND_MASK in Retail).
local SHAPES = {
    round = { back = Theme.MEDIA .. "circle.tga" },
    rounded = { mask = Theme.MEDIA .. "rounded.tga", back = Theme.MEDIA .. "rounded.tga" },
    square = { mask = WHITE },
}
-- Radius of the glow.tga circle relative to half the texture (44 of 64 texels).
local GLOW_RATIO = 64 / 44
-- Blizzard's zone colors (Minimap_Update).
local ZONE_COLORS = {
    sanctuary = { 0.41, 0.8, 0.94 },
    arena = { 1, 0.1, 0.1 },
    combat = { 1, 0.1, 0.1 },
    hostile = { 1, 0.1, 0.1 },
    friendly = { 0.1, 1, 0.1 },
    contested = { 1, 0.7, 0 },
}
local TEXT_SIZES = { caption = 11, small = 12, body = 14, heading = 15 }
local GAP, PAD, MARGIN = 4, 8, 12
local INFO_ITEMS = { "zone", "clock", "coords" }
local INFO_SLOTS = { "above", "top", "bottom", "below" }

-- Blizzard elements that can be hidden: option → frames (those that exist on this client).
local function cluster()
    return _G.MinimapCluster
end
local BLIZZARD = {
    zoneText = function()
        -- BorderTop: the header background in Retail.
        local c = cluster()
        if c then
            return c.ZoneTextButton, c.BorderTop
        end
    end,
    calendar = function()
        return _G.GameTimeFrame
    end,
    clock = function()
        return _G.TimeManagerClockButton
    end,
    tracking = function()
        return cluster() and cluster().Tracking
    end,
    mail = function()
        return cluster() and cluster().IndicatorFrame
    end,
    compartment = function()
        return _G.AddonCompartmentFrame
    end,
    zoom = function()
        return Minimap.ZoomIn, Minimap.ZoomOut
    end,
    difficulty = function()
        return cluster() and cluster().InstanceDifficulty
    end,
    coords = function()
        return Minimap:GetParent().PlayerCoords
    end,
    expansion = function()
        return _G.ExpansionLandingPageMinimapButton
    end,
}

-- Collector: named frames inside the minimap that belong to Blizzard.
local BLIZZARD_NAMES = {
    MinimapBackdrop = true,
    ExpansionLandingPageMinimapButton = true,
    GameTimeFrame = true,
    AddonCompartmentFrame = true,
    TimeManagerClockButton = true,
    MiniMapMailFrame = true,
    MiniMapTracking = true,
    MinimapZoomIn = true,
    MinimapZoomOut = true,
    QueueStatusButton = true,
    GarrisonLandingPageMinimapButton = true,
}
-- Other addons' map pins: they must stay on the map.
local PIN_PATTERNS = { "^HereBeDragons", "^HandyNotes", "^GatherMate", "^TomTom", "^Questie", "Pin%d*$" }
local MIN_BUTTON, MAX_BUTTON = 14, 48
local CLOSE_DELAY = 1

---@class EternityMinimapCapture
---@field parent table
---@field points table[]
---@field scale number
---@field alpha number
---@field strata string
---@field level integer
---@field onDragStart function?
---@field onDragStop function?

---@class EternityMinimapModule: EternityUIModuleDefinition
---@field running boolean?
---@field hooked boolean?
---@field hidden table<table, table> hidden Blizzard frame -> { parent, level }
---@field captured table<table, EternityMinimapCapture> addon button -> its original state
---@field buttonHooks table<table, boolean>
---@field original table? the minimap's original scale, alpha, points and wheel
---@field layingOut boolean?
local Module = {
    schema = ns.OptionsSchema,
    captured = {},
    buttonHooks = {},
}

local function opt(path)
    return E.store:Get(addonName, path)
end

local function secret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

local function hexToRGB(hex)
    local r, g, b = Theme.Color(hex)
    return r, g, b
end

-- Blizzard elements ------------------------------------------------------------------------------

function Module:HideFrame(frame)
    E.Hider.Hide(frame, addonName)
end

function Module:RestoreFrame(frame)
    E.Hider.Restore(frame, addonName)
end

--- Hides or restores each element according to the options (all visible if the module isn't running).
function Module:ApplyBlizzard()
    for key, frames in pairs(BLIZZARD) do
        local show = not self.running or opt("blizzard." .. key)
        for _, frame in ipairs({ frames() }) do
            if show then
                self:RestoreFrame(frame)
            else
                self:HideFrame(frame)
            end
        end
    end
end

-- Shape, border and effects ---------------------------------------------------------------------

local function shapeName()
    return Module.running and opt("map.shape") or "round"
end

--- Shape for LibDBIcon and others (GetMinimapShape protocol).
local function minimapShape()
    return shapeName() == "round" and "ROUND" or "SQUARE"
end

local function createDecor(self)
    -- Behind the map: child of Minimap's container, one level below.
    local container = Minimap:GetParent()
    local decor = CreateFrame("Frame", nil, container)
    decor:SetFrameStrata(Minimap:GetFrameStrata())
    decor:SetFrameLevel(math.max(Minimap:GetFrameLevel() - 1, 0))
    decor:SetAllPoints(Minimap)
    decor.border = decor:CreateTexture(nil, "BACKGROUND", nil, 0)
    decor.shadow = decor:CreateTexture(nil, "BACKGROUND", nil, -8)
    decor.glow = decor:CreateTexture(nil, "BACKGROUND", nil, -7)
    decor.glow:SetBlendMode("ADD")
    self.decor = decor
    return decor
end

-- Border color for the style: r, g, b and, for the theme one, the gradient's top color.
local function borderColors(style)
    if style == "accent" then
        return { Theme.Color("accent") }
    elseif style == "custom" then
        return { hexToRGB(opt("border.color")) }
    end
    return { Theme.Color("window") }, Theme.surface == "glass" and { Theme.Color("windowTop") } or nil
end

--- Draws a shape texture (circle or rounded square) or a flat color around the map.
local function placeShape(texture, file, inset)
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -inset, inset)
    texture:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", inset, -inset)
    texture:SetTextureSliceMargins(0, 0, 0, 0)
    if file then
        texture:SetTexture(file)
    else
        texture:SetColorTexture(1, 1, 1, 1)
    end
end

--- Shadow or glow: a glow.tga halo on the round shape, a 9-slice shadow.tga on the others.
local function placeHalo(texture, shape, size)
    texture:ClearAllPoints()
    if shape == "round" then
        local extra = ((Minimap:GetWidth() / 2 + size) * GLOW_RATIO) - Minimap:GetWidth() / 2
        texture:SetTexture(Theme.MEDIA .. "glow.tga")
        texture:SetTextureSliceMargins(0, 0, 0, 0)
        texture:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -extra, extra)
        texture:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", extra, -extra)
    else
        texture:SetTexture(Theme.MEDIA .. "shadow.tga")
        texture:SetTextureSliceMargins(32, 32, 32, 32)
        texture:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
        texture:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -size - 24, size + 24)
        texture:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", size + 24, -size - 24)
    end
end

--- The map mask and Blizzard's ring according to the shape.
function Module:ApplyShape()
    local shape = shapeName()
    local def = SHAPES[shape]
    self.applyingShape = true
    if def.mask then
        Minimap:SetMaskTexture(def.mask)
    elseif cluster() and cluster().UpdateMinimapConfig then
        -- Blizzard's round mask depends on rotateMinimap: let Blizzard set it.
        cluster():UpdateMinimapConfig()
    else
        Minimap:SetMaskTexture(ROUND_MASK)
    end
    self.applyingShape = false
    local blizzardRing = shape == "round" and (not self.running or opt("border.style") == "blizzard")
    for _, name in ipairs({ "MinimapCompassTexture", "MinimapCompassTextureUnderlay" }) do
        local ring = _G[name]
        if ring then
            ring:SetAlpha(blizzardRing and 1 or 0)
        end
    end
end

--- Border, shadow, glow and opacity.
function Module:ApplyLook()
    self:ApplyShape()
    local decor = self.decor or createDecor(self)
    decor:SetShown(self.running and true or false)
    if not self.running then
        return
    end
    local shape = opt("map.shape")
    local style = opt("border.style")
    local size = opt("border.size")
    if style == "blizzard" and shape ~= "round" then
        style = "theme"
    end
    local hasBorder = style ~= "none" and style ~= "blizzard"

    local border = decor.border
    if hasBorder then
        placeShape(border, SHAPES[shape].back, size)
        local bottom, top = borderColors(style)
        top = top or bottom
        -- SetGradient paints the four corners: it also works for a flat color.
        border:SetGradient(
            "VERTICAL",
            CreateColor(bottom[1], bottom[2], bottom[3], 1),
            CreateColor(top[1], top[2], top[3], 1)
        )
    end
    border:SetShown(hasBorder)

    local edge = hasBorder and size or 0
    decor.shadow:SetShown(opt("effects.shadow"))
    if opt("effects.shadow") then
        placeHalo(decor.shadow, shape, edge)
        decor.shadow:SetVertexColor(Theme.Color("shadow"))
    end
    decor.glow:SetShown(opt("effects.glow"))
    if opt("effects.glow") then
        placeHalo(decor.glow, shape, edge)
        local r, g, b = Theme.Color("accent")
        decor.glow:SetVertexColor(r, g, b, 0.9)
    end
end

-- Information (zone, time, coordinates) -----------------------------------------------------------

local function createInfo(self)
    self.info = {}
    for _, key in ipairs(INFO_ITEMS) do
        local item = CreateFrame("Frame", nil, Minimap)
        item:SetFrameLevel(Minimap:GetFrameLevel() + 6)
        item.shape = Shape.New(item)
        item.text = Widgets.Text(item, TEXT_SIZES.small, "text")
        item.text:SetPoint("CENTER")
        item:Hide()
        self.info[key] = item
    end
end

local function zoneText()
    local text = GetMinimapZoneText()
    if not text or secret(text) then
        return ""
    end
    return text
end

local function clockText()
    local h, m
    if opt("info.clockSource") == "realm" then
        h, m = GetGameTime()
    else
        h, m = tonumber(date("%H")), tonumber(date("%M"))
    end
    if opt("info.clockFormat") == "12h" then
        local suffix = h < 12 and "AM" or "PM"
        h = h % 12
        return string.format("%d:%02d %s", h == 0 and 12 or h, m, suffix)
    end
    return string.format("%02d:%02d", h, m)
end

local function coordsText()
    if not C_Map then
        return ""
    end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID or secret(mapID) then
        return ""
    end
    local position = C_Map.GetPlayerMapPosition(mapID, "player")
    if not position then
        return ""
    end
    local x, y = position:GetXY()
    if not x or secret(x) or secret(y) or (x == 0 and y == 0) then
        return ""
    end
    if opt("info.coordsDecimals") then
        return string.format("%.1f, %.1f", x * 100, y * 100)
    end
    return string.format("%d, %d", math.floor(x * 100 + 0.5), math.floor(y * 100 + 0.5))
end

local TEXTS = { zone = zoneText, clock = clockText, coords = coordsText }

--- Fills the texts and puts each one in its slot (those in the same slot, stacked).
function Module:UpdateInfo()
    if not self.info then
        createInfo(self)
    end
    local style = opt("text.style")
    local background = opt("text.background")
    local stacks = { above = {}, top = {}, bottom = {}, below = {} }
    for _, key in ipairs(INFO_ITEMS) do
        local item = self.info[key]
        local text = self.running and opt("info." .. key) and TEXTS[key]() or ""
        Widgets.SetTextSize(item.text, TEXT_SIZES[style] or TEXT_SIZES.small)
        item.text:SetTextColor(Theme.Color("text"))
        item.text:SetText(text)
        if key == "zone" and text ~= "" and opt("info.zoneColor") then
            local pvpType = C_PvP and C_PvP.GetZonePVPInfo()
            local color = not secret(pvpType) and ZONE_COLORS[pvpType]
            if color then
                item.text:SetTextColor(color[1], color[2], color[3])
            end
        end
        local shown = text ~= ""
        item:SetShown(shown)
        if shown then
            local padX, padY = background and PAD or 0, background and 3 or 0
            local height = item.text:GetStringHeight() + 2 * padY
            item:SetSize(item.text:GetStringWidth() + 2 * padX, height)
            if background then
                local fill = Theme.RGBA("window")
                fill[4] = Theme.opacity
                Shape.Paint(item.shape, math.min(Theme.radius, math.floor(height / 2)), fill, Theme.colors.lineStrong)
            else
                Shape.Paint(item.shape, 0, nil, nil)
            end
            local slot = stacks[opt("text." .. key)]
            slot[#slot + 1] = item
        end
    end
    local gap = GAP
    local edge = (opt("border.style") ~= "none" and opt("border.size") or 0) + gap
    for _, slot in ipairs(INFO_SLOTS) do
        local previous
        for _, item in ipairs(stacks[slot]) do
            item:ClearAllPoints()
            if slot == "above" then
                item:SetPoint("BOTTOM", previous or Minimap, "TOP", 0, previous and 2 or edge)
            elseif slot == "top" then
                item:SetPoint(
                    "TOP",
                    previous or Minimap,
                    previous and "BOTTOM" or "TOP",
                    0,
                    previous and -2 or -gap * 2
                )
            elseif slot == "bottom" then
                item:SetPoint(
                    "BOTTOM",
                    previous or Minimap,
                    previous and "TOP" or "BOTTOM",
                    0,
                    previous and 2 or gap * 2
                )
            else
                item:SetPoint("TOP", previous or Minimap, "BOTTOM", 0, previous and -2 or -edge)
            end
            previous = item
        end
    end
end

-- Map: scale, position, opacity and zoom ---------------------------------------------------------

function Module:SaveOriginal()
    if self.original then
        return
    end
    local c = cluster()
    local points = {}
    for i = 1, c:GetNumPoints() do
        points[i] = { c:GetPoint(i) }
    end
    self.original = {
        scale = c:GetScale(),
        alpha = c:GetAlpha(),
        points = points,
        wheel = Minimap:IsMouseWheelEnabled(),
    }
end

function Module:ApplyMap()
    local c = cluster()
    if not c then
        return
    end
    self:SaveOriginal()
    local original = self.original
    if not self.running then
        E.Mover.Unregister(addonName)
        c:SetScale(original.scale)
        c:SetAlpha(original.alpha)
        if self.moved then
            c:ClearAllPoints()
            for _, p in ipairs(original.points) do
                c:SetPoint(unpack(p))
            end
            self.moved = false
        end
        Minimap:EnableMouseWheel(original.wheel)
        return
    end
    local scale = original.scale * opt("map.scale")
    c:SetScale(scale)
    local inCombat = self.inCombat or InCombatLockdown()
    c:SetAlpha(inCombat and opt("effects.combatAlpha") or opt("effects.alpha"))
    -- Forever has no Edit Mode for the minimap: the Mover places it, top right by default.
    if not E.Mover.elements[addonName] then
        E.Mover.Register({
            key = addonName,
            owner = addonName,
            label = L.MOVER,
            frame = c,
            point = "TOPRIGHT",
            openOptions = function()
                E:OpenOptions(addonName)
            end,
        })
        self.moved = true
    end
    Minimap:EnableMouseWheel(opt("behavior.wheelZoom"))
end

--- After a zoom change, schedules going back to zoom 0 (if the option asks for it).
function Module:OnZoom()
    local delay = self.running and opt("behavior.resetZoom") or 0
    if delay <= 0 or Minimap:GetZoom() == 0 then
        return
    end
    self.zoomToken = (self.zoomToken or 0) + 1
    local token = self.zoomToken
    C_Timer.After(delay, function()
        if self.running and token == self.zoomToken then
            Minimap:SetZoom(0)
        end
    end)
end

-- Button collector -------------------------------------------------------------------------------

local function excludedTokens()
    local list = {}
    for token in opt("buttons.exclude"):gmatch("[^,]+") do
        token = strtrim(token):lower()
        if token ~= "" then
            list[#list + 1] = token
        end
    end
    return list
end

local function isExcluded(name, tokens)
    local lower = name:lower()
    for _, token in ipairs(tokens) do
        if lower:find(token, 1, true) then
            return true
        end
    end
    return false
end

local function isCandidate(frame)
    local name = frame:GetName()
    if not name or secret(name) or BLIZZARD_NAMES[name] or name:find("^EternityMinimap") then
        return false
    end
    if (frame.IsForbidden and frame:IsForbidden()) or frame:IsProtected() then
        return false
    end
    for _, pattern in ipairs(PIN_PATTERNS) do
        if name:find(pattern) then
            return false
        end
    end
    if name:find("^LibDBIcon10_") then
        return true
    end
    if not frame:IsObjectType("Button") then
        return false
    end
    local w, h = frame:GetSize()
    return w >= MIN_BUTTON and w <= MAX_BUTTON and h >= MIN_BUTTON and h <= MAX_BUTTON
end

--- Display name (without the LibDBIcon prefix).
local function displayName(button)
    return (button:GetName():gsub("^LibDBIcon10_", ""))
end

function Module:Capture(button)
    local points = {}
    for i = 1, button:GetNumPoints() do
        points[i] = { button:GetPoint(i) }
    end
    self.captured[button] = {
        parent = button:GetParent(),
        points = points,
        scale = button:GetScale(),
        alpha = button:GetAlpha(),
        strata = button:GetFrameStrata(),
        level = button:GetFrameLevel(),
        onDragStart = button:GetScript("OnDragStart"),
        onDragStop = button:GetScript("OnDragStop"),
    }
    if not self.buttonHooks[button] then
        self.buttonHooks[button] = true
        -- If its addon repositions it (LibDBIcon when the saved position changes) or shows or
        -- hides it, the grid is rebuilt.
        local function relayout(b)
            if self.captured[b] and not self.layingOut then
                self:Layout()
            end
        end
        hooksecurefunc(button, "SetPoint", relayout)
        hooksecurefunc(button, "Show", relayout)
        hooksecurefunc(button, "Hide", relayout)
        hooksecurefunc(button, "SetShown", relayout)
    end
    button:SetScript("OnDragStart", nil)
    button:SetScript("OnDragStop", nil)
    button:SetParent(self.panel)
    button:SetAlpha(1)
end

function Module:Release(button)
    local saved = self.captured[button]
    self.captured[button] = nil
    button:SetParent(saved.parent)
    button:SetScale(saved.scale)
    button:SetAlpha(saved.alpha)
    button:SetFrameStrata(saved.strata)
    button:SetFrameLevel(saved.level)
    button:ClearAllPoints()
    for _, p in ipairs(saved.points) do
        button:SetPoint(unpack(p))
    end
    button:SetScript("OnDragStart", saved.onDragStart)
    button:SetScript("OnDragStop", saved.onDragStop)
end

function Module:ReleaseAll()
    for button in pairs(self.captured) do
        self:Release(button)
    end
end

--- Looks for new buttons, releases excluded ones and rebuilds the grid.
function Module:Scan()
    if not self.running or not opt("buttons.collect") then
        self:ReleaseAll()
        self:Layout()
        return
    end
    local tokens = excludedTokens()
    for button in pairs(self.captured) do
        if isExcluded(button:GetName(), tokens) then
            self:Release(button)
        end
    end
    for _, parent in ipairs({ Minimap, _G.MinimapBackdrop }) do
        for _, child in ipairs({ parent:GetChildren() }) do
            if not self.captured[child] and isCandidate(child) and not isExcluded(child:GetName(), tokens) then
                self:Capture(child)
            end
        end
    end
    self:Layout()
end

--- Searches on the next frame (addons create their buttons on their ADDON_LOADED or later).
function Module:ScheduleScan()
    if self.scanPending then
        return
    end
    self.scanPending = true
    C_Timer.After(0, function()
        self.scanPending = false
        self:Scan()
    end)
end

--- Collected, visible buttons, by name.
function Module:VisibleButtons()
    local buttons = {}
    for button in pairs(self.captured) do
        if button:IsShown() then
            buttons[#buttons + 1] = button
        end
    end
    table.sort(buttons, function(a, b)
        return a:GetName() < b:GetName()
    end)
    return buttons
end

function Module:Layout()
    local panel = self.panel
    if not panel then
        return
    end
    local buttons = self:VisibleButtons()
    local size, gap, pad = opt("collector.iconSize"), GAP, PAD
    local columns = math.min(opt("collector.columns"), math.max(#buttons, 1))
    local rows = math.max(math.ceil(#buttons / columns), 1)
    self.layingOut = true
    for i, button in ipairs(buttons) do
        local col, row = (i - 1) % columns, math.floor((i - 1) / columns)
        local scale = size / math.max(button:GetWidth(), button:GetHeight(), 1)
        button:SetScale(scale)
        button:SetFrameStrata(panel:GetFrameStrata())
        button:SetFrameLevel(panel:GetFrameLevel() + 2)
        button:ClearAllPoints()
        -- Offsets are in the button's scale.
        button:SetPoint(
            "TOPLEFT",
            panel,
            "TOPLEFT",
            (pad + col * (size + gap)) / scale,
            -(pad + row * (size + gap)) / scale
        )
    end
    self.layingOut = false
    panel.empty:SetShown(#buttons == 0)
    if #buttons == 0 then
        panel:SetSize(panel.empty:GetStringWidth() + 2 * MARGIN, size + 2 * pad)
    else
        panel:SetSize(2 * pad + columns * size + (columns - 1) * gap, 2 * pad + rows * size + (rows - 1) * gap)
    end
    self:UpdateToggle()
end

-- Collector button and panel

local function anchorPanel(self)
    local panel, toggle = self.panel, self.toggle
    local grow = opt("collector.grow")
    local x, y = toggle:GetCenter()
    local cx, cy = UIParent:GetCenter()
    local scale = toggle:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local right = x and (x * scale > cx) -- the button is on the right: the panel opens to the left
    local top = y and (y * scale > cy)
    local gap = GAP
    panel:ClearAllPoints()
    if grow == "left" then
        panel:SetPoint("TOPRIGHT", toggle, "TOPLEFT", -gap, 0)
    elseif grow == "right" then
        panel:SetPoint("TOPLEFT", toggle, "TOPRIGHT", gap, 0)
    else
        local down = grow == "down" or (grow == "auto" and top)
        local side = right and "RIGHT" or "LEFT"
        if down then
            panel:SetPoint("TOP" .. side, toggle, "BOTTOM" .. side, 0, -gap)
        else
            panel:SetPoint("BOTTOM" .. side, toggle, "TOP" .. side, 0, gap)
        end
    end
end

function Module:ShowPanel()
    if not self.running then
        return
    end
    self:Scan()
    anchorPanel(self)
    Widgets.HideTooltip()
    self.closeTimer = 0
    self.panel:Show()
end

function Module:HidePanel()
    if self.panel then
        self.panel:Hide()
    end
end

function Module:TogglePanel()
    if self.panel:IsShown() then
        self:HidePanel()
    else
        self:ShowPanel()
    end
end

--- Auto-close: after CLOSE_DELAY s with the mouse outside the panel and the button.
function Module:CheckAutoClose(elapsed)
    if not opt("buttons.autoClose") and opt("buttons.open") ~= "hover" then
        return
    end
    if self.panel:IsMouseOver() or self.toggle:IsMouseOver() then
        self.closeTimer = 0
        return
    end
    self.closeTimer = (self.closeTimer or 0) + elapsed
    if self.closeTimer >= CLOSE_DELAY then
        self:HidePanel()
    end
end

local function createPanel(self)
    local panel = CreateFrame("Frame", "EternityMinimapPanel", UIParent)
    panel:SetFrameStrata("HIGH")
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel.shape = Shape.New(panel)
    function panel.Paint(frame)
        Theme.PaintWindow(frame.shape)
    end
    Widgets.Track(panel)
    panel.empty = Widgets.Text(panel, TEXT_SIZES.small, "muted")
    panel.empty:SetText(L.EMPTY)
    panel.empty:SetPoint("CENTER")
    panel:Hide()
    panel:SetScript("OnUpdate", function(_, elapsed)
        self:CheckAutoClose(elapsed)
    end)
    -- Esc closes it, through keyboard input: UISpecialFrames taints. Other keys go on to the game.
    panel:EnableKeyboard(true)
    panel:SetScript("OnShow", function(frame)
        E.Combat.Run(frame, function()
            frame:SetPropagateKeyboardInput(true)
        end)
    end)
    panel:SetScript("OnKeyDown", function(frame, key)
        if key == "ESCAPE" and not InCombatLockdown() then
            frame:SetPropagateKeyboardInput(false)
            frame:Hide()
        end
    end)
    self.panel = panel
end

--- Button position on the edge: angle in degrees (0 = right, 90 = up).
function Module:PlaceToggle(angle)
    local rad = math.rad(angle or opt("collector.angle"))
    local x, y = math.cos(rad), math.sin(rad)
    if minimapShape() == "SQUARE" then
        local m = math.max(math.abs(x), math.abs(y))
        x, y = x / m, y / m
    end
    local radius = Minimap:GetWidth() / 2
    self.toggle:ClearAllPoints()
    self.toggle:SetPoint("CENTER", Minimap, "CENTER", x * radius, y * radius)
end

function Module:DragUpdate()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    local angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
    self.dragAngle = math.floor(angle + 0.5) % 360
    self:PlaceToggle(self.dragAngle)
end

function Module:DragStop()
    if self.dragAngle then
        E.store:Set(addonName, "collector.angle", self.dragAngle)
        self.dragAngle = nil
    end
    self:PlaceToggle()
end

-- The collector's tooltip. It stays empty, so it doesn't show, while the panel is open.
local function buildToggleTooltip(self, tip)
    if opt("buttons.open") == "hover" or self.panel:IsShown() then
        return
    end
    tip:SetTitle(L.COLLECTOR)
    local buttons = self:VisibleButtons()
    if #buttons == 0 then
        tip:AddLine(L.EMPTY, "textMuted")
    end
    for _, button in ipairs(buttons) do
        tip:AddLine(displayName(button), "textMuted")
    end
    tip:AddHint(L.HINT_CLICK)
end

local function createToggle(self)
    local b = CreateFrame("Button", "EternityMinimapButton", Minimap)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b.shape = Shape.New(b)
    -- A menu icon: three bars.
    b.bars = {}
    for i = 1, 3 do
        b.bars[i] = b:CreateTexture(nil, "ARTWORK")
    end
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            E:OpenOptions(addonName, "general")
        elseif opt("buttons.open") == "click" then
            self:TogglePanel()
        end
    end)
    b:SetScript("OnEnter", function(frame)
        frame.hovered = true
        frame:Paint()
        if opt("buttons.open") == "hover" then
            self:ShowPanel()
        end
    end)
    b:SetScript("OnLeave", function(frame)
        frame.hovered = false
        frame:Paint()
    end)
    b:SetScript("OnDragStart", function(frame)
        Widgets.HideTooltip()
        frame:SetScript("OnUpdate", function()
            self:DragUpdate()
        end)
    end)
    b:SetScript("OnDragStop", function(frame)
        frame:SetScript("OnUpdate", nil)
        self:DragStop()
    end)
    Widgets.AttachTooltip(b, function(tip)
        buildToggleTooltip(self, tip)
    end, "LEFT")
    function b.Paint(frame)
        local fill = Theme.RGBA(frame.hovered and "accent" or "window")
        local radius = math.min(16, math.floor(frame:GetHeight() / 2))
        Shape.Paint(frame.shape, Theme.radius == 0 and 0 or radius, fill, Theme.colors.lineStrong)
        local r, g, b2, a = Theme.Color(frame.hovered and "onAccent" or "text")
        for _, bar in ipairs(frame.bars) do
            bar:SetColorTexture(r, g, b2, a)
        end
    end
    self.toggle = Widgets.Track(b)
end

--- Size, position and visibility of the collector button.
function Module:UpdateToggle()
    local toggle = self.toggle
    if not toggle then
        return
    end
    local size = opt("collector.buttonSize")
    toggle:SetSize(size, size)
    local barWidth = math.floor(size / 2)
    local barGap = math.max(math.floor(size / 7), 2)
    for i, bar in ipairs(toggle.bars) do
        bar:SetSize(barWidth, E.Pixel.Size(toggle) * 2)
        bar:ClearAllPoints()
        bar:SetPoint("CENTER", 0, (2 - i) * barGap)
    end
    toggle:Paint()
    self:PlaceToggle()
    local empty = next(self.captured) == nil
    local show = self.running and opt("buttons.collect") and not (empty and opt("collector.hideWhenEmpty"))
    toggle:SetShown(show and true or false)
    if not show then
        self:HidePanel()
    end
    -- Always anchored, even closed: collected buttons sit in the panel and their addons read
    -- their position (Zygor compares ZygorGuidesViewerMapIcon:GetLeft() at startup).
    anchorPanel(self)
end

-- Lifecycle -----------------------------------------------------------------------------------

function Module:InstallHooks()
    self.hooked = true
    createPanel(self)
    createToggle(self)
    -- Blizzard puts the round mask back when rotateMinimap changes.
    if cluster() and cluster().UpdateMinimapConfig then
        hooksecurefunc(cluster(), "UpdateMinimapConfig", function()
            if self.running and not self.applyingShape then
                self:ApplyShape()
            end
        end)
    end
    hooksecurefunc(Minimap, "SetZoom", function()
        self:OnZoom()
    end)
    -- GetMinimapShape protocol (LibDBIcon and others), if nobody has defined it yet.
    if _G.GetMinimapShape == nil then
        _G.GetMinimapShape = minimapShape
    end
    -- LibDBIcon reports when it creates a button.
    local LibStub = _G.LibStub
    local ldbi = LibStub and LibStub("LibDBIcon-1.0", true)
    if ldbi and ldbi.RegisterCallback then
        ldbi.RegisterCallback(self, "LibDBIcon_IconCreated", function()
            self:ScheduleScan()
        end)
    end
    local events = CreateFrame("Frame")
    for _, event in ipairs({
        "ADDON_LOADED",
        "PLAYER_ENTERING_WORLD",
        "ZONE_CHANGED",
        "ZONE_CHANGED_INDOORS",
        "ZONE_CHANGED_NEW_AREA",
        "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED",
    }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function(_, event)
        if not self.running then
            return
        end
        if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
            self.inCombat = event == "PLAYER_REGEN_DISABLED"
            self:ApplyMap()
        elseif event == "ADDON_LOADED" or event == "PLAYER_ENTERING_WORLD" then
            -- Elements that arrive late (clock, difficulty) and new addon buttons.
            self:ApplyBlizzard()
            self:ScheduleScan()
            self:UpdateInfo()
        else
            self:UpdateInfo()
        end
    end)
end

--- Applies every option (or undoes everything if the module isn't running).
function Module:ApplyAll()
    self:ApplyBlizzard()
    self:ApplyLook()
    self:ApplyMap()
    self:UpdateInfo()
    self:Scan()
end

function Module:OnEnable()
    self.running = true
    if not self.hooked then
        self:InstallHooks()
    end
    -- Theme border, accent and shadow change with the theme. The core releases this on disable.
    E.Events.Listen(Theme.CHANGED, self, function()
        self:ApplyLook()
        self:UpdateInfo()
        self:UpdateToggle()
    end)
    self:ApplyAll()
    -- Time and coordinates.
    self.ticker = C_Timer.NewTicker(0.25, function()
        if self.running and (opt("info.clock") or opt("info.coords")) then
            self:UpdateInfo()
        end
    end)
end

function Module:OnDisable()
    self.running = false
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
    self.inCombat = false
    self:ApplyAll()
end

function Module:OnConfigChanged()
    -- Everything is idempotent and cheap: it's reapplied in full.
    self:ApplyAll()
end

E:RegisterModule(addonName, Module)
