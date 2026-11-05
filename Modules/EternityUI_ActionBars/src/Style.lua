-- The look of an action button, ours (LibActionButton) or Blizzard's (pet and stance buttons, which
-- the bars borrow): a shape mask on the icon, its backdrop and border; the button's own highlight,
-- pressed and checked textures recolored (the button keeps showing and hiding them); icon treatment
-- (desaturation, brightness, tint, glass shine, inner shadow); the cooldown swipe and the texts.
-- Blizzard's art is only made transparent and everything changed is saved, so Style:Remove gives a
-- borrowed button back as it was.

---@type string, EternityUIActionBarsNamespace
local addonName, ns = ...
local E = EternityUI
local Theme = E.Theme

---@class EternityUIActionBarsStyle
local Style = {}
ns.Style = Style

-- Mask of each shape (square has none).
local SHAPES = {
    rounded = Theme.MEDIA .. "rounded.tga",
    circle = Theme.MEDIA .. "circle.tga",
    diamond = Theme.MEDIA .. "diamond.tga",
    hexagon = Theme.MEDIA .. "hexagon.tga",
}
local SQUARE = "Interface\\Buttons\\WHITE8X8"
-- Template art made transparent while skinned.
local ART = { "NormalTexture", "SlotArt", "SlotBackground", "Border", "FlyoutBorderShadow" }
-- Regions whose anchors change (saved to restore them).
local MOVED = { "icon", "cooldown", "HotKey", "Count", "Name" }
-- The button's state textures, recolored in place.
local STATES = { highlight = "GetHighlightTexture", pushed = "GetPushedTexture", checked = "GetCheckedTexture" }
-- Vertex color FrameXML and LibActionButton give an icon that can't be used now.
local UNUSABLE = 0.4
local POINTS = {
    topleft = "TOPLEFT",
    top = "TOP",
    topright = "TOPRIGHT",
    left = "LEFT",
    center = "CENTER",
    right = "RIGHT",
    bottomleft = "BOTTOMLEFT",
    bottom = "BOTTOM",
    bottomright = "BOTTOMRIGHT",
}
Style.POINTS = POINTS

local function opt(path)
    return E.store:Get(addonName, path)
end

--- Color option ("#RRGGBB[AA]" or a theme color like "@accent") to r, g, b, a.
function Style.Color(hex)
    return Theme.Color(hex)
end

local function rgb(hex)
    local r, g, b = Style.Color(hex)
    return { r, g, b }
end

-- Long key names first: MOUSEWHEELUP before BUTTON, NUMPAD before PLUS.
local SHORT_KEYS = {
    { "CTRL%-", "c" },
    { "SHIFT%-", "s" },
    { "ALT%-", "a" },
    { "META%-", "m" },
    { "MOUSEWHEELUP", "WU" },
    { "MOUSEWHEELDOWN", "WD" },
    { "MIDDLEMOUSE", "M3" },
    { "BUTTON(%d+)", "M%1" },
    { "NUMPAD", "N" },
    { "PLUS", "+" },
    { "MINUS", "-" },
    { "MULTIPLY", "*" },
    { "DIVIDE", "/" },
    { "DECIMAL", "." },
    { "PAGEUP", "PU" },
    { "PAGEDOWN", "PD" },
    { "SPACE", "Sp" },
    { "INSERT", "Ins" },
    { "DELETE", "Del" },
    { "HOME", "Hm" },
    { "BACKSPACE", "BS" },
    { "CAPSLOCK", "Caps" },
    { "ESCAPE", "Esc" },
}

--- Short name of a key ("CTRL-SHIFT-1" -> "cs1", "BUTTON4" -> "M4").
---@param key string
---@return string
function Style.ShortKey(key)
    for _, pair in ipairs(SHORT_KEYS) do
        key = key:gsub(pair[1], pair[2])
    end
    return key
end

-- Offset that keeps a text inside the button at each anchor.
local function textOffset(point)
    local x = point:find("LEFT") and 2 or point:find("RIGHT") and -2 or 0
    local y = point:find("TOP") and -3 or point:find("BOTTOM") and 3 or 0
    return x, y
end

local function textConfig(prefix, colorHex)
    local point = POINTS[opt("text." .. prefix .. "Position")] or "CENTER"
    local x, y = textOffset(point)
    local outline = opt("text.outline")
    return {
        font = {
            font = Theme.font,
            size = opt("text." .. prefix .. "Size"),
            flags = outline ~= "NONE" and outline or "",
        },
        color = rgb(colorHex),
        position = { anchor = point, relAnchor = point, offsetX = x, offsetY = y },
        justifyH = point:find("LEFT") and "LEFT" or point:find("RIGHT") and "RIGHT" or "CENTER",
    }
end

--- LibActionButton configuration for a button of a bar, from the options.
---@param bar table bar definition (Bars.LIST)
---@param index integer button index in the bar
function Style.ButtonConfig(bar, index)
    local tooltips = opt("general.tooltips")
    local rangeMode = opt("buttons.rangeMode")
    return {
        outOfRangeColoring = rangeMode,
        tooltip = tooltips == "always" and "enabled" or tooltips == "nocombat" and "nocombat" or "disabled",
        showGrid = opt(bar.id .. ".showGrid") or ns.Bars.binding or false,
        colors = { range = rgb(opt("buttons.rangeColor")), mana = rgb(opt("buttons.manaColor")) },
        hideElements = { macro = not opt("text.macro"), hotkey = not opt("text.hotkey") },
        keyBoundTarget = bar.binding and (bar.binding .. index) or false,
        keyBoundClickButton = "Keybind",
        flyoutDirection = opt("general.flyout"),
        text = {
            hotkey = textConfig("hotkey", opt("text.hotkeyColor")),
            count = textConfig("count", opt("text.countColor")),
            macro = textConfig("macro", "#FFFFFF"),
        },
    }
end

--- Makes a LibActionButton button show short key names when the option asks for it.
---@param button table
function Style.ShortenHotkeys(button)
    local original = button.GetHotkey
    function button:GetHotkey()
        local key = original(self)
        if key and opt("text.hotkeyShort") then
            return Style.ShortKey(key)
        end
        return key
    end
end

-- Skin ---------------------------------------------------------------------------------------------

local function savePoints(region)
    local points = {}
    for i = 1, region:GetNumPoints() do
        points[i] = { region:GetPoint(i) }
    end
    return points
end

local function restorePoints(region, points)
    region:ClearAllPoints()
    for _, p in ipairs(points) do
        region:SetPoint(unpack(p))
    end
end

local function inside(region, inset)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", inset, -inset)
    region:SetPoint("BOTTOMRIGHT", -inset, inset)
end

-- Desaturation the options ask for, from the icon's last vertex color (unusable = 0.4).
local function refreshIcon(button)
    local skin = button.eternitySkin
    local icon = button.icon
    local shown = skin.active and icon:IsShown()
    for _, overlay in ipairs(skin.overlays) do
        overlay:SetShown(shown and overlay.wanted)
    end
    if not skin.active then
        return
    end
    local mode = opt("icons.desaturate")
    if mode ~= "none" then
        skin.refreshing = true
        icon:SetDesaturated(mode == "always" or skin.unusable)
        skin.refreshing = false
    end
end

-- Follows what the button does to its icon (show, hide, usable color, desaturation).
local function hookIcon(button, skin)
    local icon = button.icon
    hooksecurefunc(icon, "SetVertexColor", function(_, r)
        skin.unusable = r == UNUSABLE
        refreshIcon(button)
    end)
    hooksecurefunc(icon, "SetDesaturated", function()
        if not skin.refreshing then
            refreshIcon(button)
        end
    end)
    hooksecurefunc(icon, "Show", function()
        refreshIcon(button)
    end)
    hooksecurefunc(icon, "Hide", function()
        refreshIcon(button)
    end)
end

local function newOverlay(button, skin, sublevel)
    local texture = button:CreateTexture(nil, "BACKGROUND", nil, sublevel)
    skin.overlays[#skin.overlays + 1] = texture
    return texture
end

-- Our layers and the saved state of the button, created the first time it's skinned.
local function prepare(button)
    local skin = button.eternitySkin
    if skin then
        return skin
    end
    skin = { points = {}, art = {}, states = {}, overlays = {} }
    button.eternitySkin = skin
    for _, key in ipairs(MOVED) do
        local region = button[key]
        if region then
            skin.points[key] = savePoints(region)
        end
    end
    skin.border = button:CreateTexture(nil, "BACKGROUND", nil, -8)
    skin.border:SetAllPoints()
    skin.backdrop = button:CreateTexture(nil, "BACKGROUND", nil, -7)
    skin.outerMask = button:CreateMaskTexture()
    skin.outerMask:SetAllPoints(skin.border)
    skin.innerMask = button:CreateMaskTexture()
    -- Icon overlays, above the icon (sublevel 0) and below the cooldown.
    skin.shade = newOverlay(button, skin, 1)
    skin.tint = newOverlay(button, skin, 2)
    skin.shadows = {}
    for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local shadow = newOverlay(button, skin, 3)
        shadow.side = side
        skin.shadows[i] = shadow
    end
    skin.gloss = newOverlay(button, skin, 4)
    hookIcon(button, skin)
    return skin
end

local function setMask(texture, mask, path)
    texture:RemoveMaskTexture(mask)
    if path then
        texture:AddMaskTexture(mask)
    end
end

-- Recolors the button's highlight, pressed and checked textures (saving them the first time).
local function applyStates(button, skin, inset, path)
    local cr, cg, cb = Theme.Color("accent")
    local colors = {
        highlight = { Style.Color(opt("buttons.highlightColor")) },
        pushed = { Style.Color(opt("buttons.pushedColor")) },
        checked = { cr, cg, cb, 0.35 },
    }
    for key, getter in pairs(STATES) do
        local texture = button[getter] and button[getter](button)
        if texture then
            if not skin.states[key] then
                skin.states[key] = {
                    texture = texture,
                    atlas = texture:GetAtlas(),
                    file = texture:GetTexture(),
                    blend = texture:GetBlendMode(),
                    points = savePoints(texture),
                }
            end
            texture:SetColorTexture(unpack(colors[key]))
            texture:SetBlendMode("BLEND")
            inside(texture, inset)
            setMask(texture, skin.innerMask, path)
        end
    end
end

-- Brightness, tint, inner shadow and glass shine over the icon.
local function applyIcon(button, skin, inset, size, path)
    local icon = button.icon
    local brightness = opt("icons.brightness")
    skin.shade.wanted = brightness ~= 0
    if brightness > 0 then
        skin.shade:SetColorTexture(1, 1, 1, brightness)
        skin.shade:SetBlendMode("ADD")
    else
        skin.shade:SetColorTexture(0, 0, 0, -brightness)
        skin.shade:SetBlendMode("BLEND")
    end

    local tint = opt("icons.tint")
    skin.tint.wanted = tint
    if tint then
        local r, g, b = Style.Color(opt("icons.tintColor"))
        skin.tint:SetColorTexture(r, g, b, opt("icons.tintStrength"))
    end

    -- Inner shadow: a gradient strip on each side, dark at the edge.
    local strength = opt("icons.shadow")
    local depth = math.max((size - 2 * inset) * 0.3, 1)
    for _, shadow in ipairs(skin.shadows) do
        shadow.wanted = strength > 0
        shadow:SetColorTexture(1, 1, 1, 1)
        shadow:ClearAllPoints()
        local side = shadow.side
        local dark, clear = CreateColor(0, 0, 0, strength), CreateColor(0, 0, 0, 0)
        if side == "TOP" or side == "BOTTOM" then
            local y = side == "TOP" and -inset or inset
            shadow:SetPoint(side .. "LEFT", inset, y)
            shadow:SetPoint(side .. "RIGHT", -inset, y)
            shadow:SetHeight(depth)
            if side == "TOP" then
                shadow:SetGradient("VERTICAL", clear, dark)
            else
                shadow:SetGradient("VERTICAL", dark, clear)
            end
        else
            local x = side == "LEFT" and inset or -inset
            shadow:SetPoint("TOP" .. side, x, -inset)
            shadow:SetPoint("BOTTOM" .. side, x, inset)
            shadow:SetWidth(depth)
            if side == "LEFT" then
                shadow:SetGradient("HORIZONTAL", dark, clear)
            else
                shadow:SetGradient("HORIZONTAL", clear, dark)
            end
        end
    end

    -- Glass shine: white fading from the top edge to the middle.
    local gloss = opt("icons.gloss")
    skin.gloss.wanted = gloss > 0
    skin.gloss:SetColorTexture(1, 1, 1, 1)
    skin.gloss:ClearAllPoints()
    skin.gloss:SetPoint("TOPLEFT", inset, -inset)
    skin.gloss:SetPoint("TOPRIGHT", -inset, -inset)
    skin.gloss:SetHeight(math.max((size - 2 * inset) / 2, 1))
    skin.gloss:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, gloss))

    inside(skin.shade, inset)
    inside(skin.tint, inset)
    for _, overlay in ipairs(skin.overlays) do
        setMask(overlay, skin.innerMask, path)
    end

    if opt("icons.desaturate") == "none" then
        skin.refreshing = true
        icon:SetDesaturated(false)
        skin.refreshing = false
    end
    refreshIcon(button)
end

--- Skins a button for a size in units (the button is resized to it).
---@param button table
---@param size number
function Style:Apply(button, size)
    local skin = prepare(button)
    skin.active = true
    button:SetSize(size, size)

    local shape = opt("buttons.shape")
    local path = SHAPES[shape]
    local border = opt("buttons.border")
    local inset = border and opt("buttons.borderSize") or 0
    skin.inset = inset

    for _, key in ipairs(ART) do
        local region = button[key] or (key == "NormalTexture" and button:GetNormalTexture())
        if region then
            skin.art[key] = skin.art[key] or region:GetAlpha()
            region:SetAlpha(0)
        end
    end

    -- Masks: the outer one shapes the border, the inner one everything inside it.
    skin.outerMask:SetTexture(path or SQUARE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    skin.innerMask:SetTexture(path or SQUARE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    inside(skin.innerMask, inset)

    local r, g, b, a = Style.Color(opt("buttons.borderColor"))
    if opt("buttons.borderClass") then
        local color = C_ClassColor.GetClassColor(select(2, UnitClass("player")))
        if color then
            r, g, b = color:GetRGB()
        end
    end
    skin.border:SetColorTexture(r, g, b, a)
    skin.border:SetShown(border)
    setMask(skin.border, skin.outerMask, path)

    inside(skin.backdrop, inset)
    skin.backdrop:SetColorTexture(Style.Color(opt("buttons.backdropColor")))
    skin.backdrop:SetShown(opt("buttons.backdrop"))
    setMask(skin.backdrop, skin.innerMask, path)

    local icon = button.icon
    if button.IconMask then
        icon:RemoveMaskTexture(button.IconMask)
    end
    setMask(icon, skin.innerMask, path)
    inside(icon, inset)
    local zoom = opt("buttons.zoom")
    icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)

    applyStates(button, skin, inset, path)
    applyIcon(button, skin, inset, size, path)

    local cooldown = button.cooldown
    if cooldown then
        inside(cooldown, inset)
        cooldown:SetSwipeTexture(path or SQUARE)
        cooldown:SetSwipeColor(0, 0, 0, opt("buttons.swipeAlpha"))
        cooldown:SetDrawEdge(opt("buttons.cooldownEdge") and (shape == "square" or shape == "circle"))
        cooldown:SetUseCircularEdge(shape == "circle")
    end
end

--- Texts of a button LibActionButton doesn't manage (pet and stance), like Style.ButtonConfig.
---@param button table
function Style:ApplyTexts(button)
    local specs = { HotKey = "hotkey", Count = "count", Name = "macro" }
    for key, prefix in pairs(specs) do
        local text = button[key]
        if text then
            local color = prefix == "hotkey" and opt("text.hotkeyColor")
                or prefix == "count" and opt("text.countColor")
                or "#FFFFFF"
            local spec = textConfig(prefix, color)
            text:SetFont(spec.font.font, spec.font.size, spec.font.flags)
            text:SetTextColor(unpack(spec.color))
            text:ClearAllPoints()
            local p = spec.position
            text:SetPoint(p.anchor, button, p.relAnchor, p.offsetX, p.offsetY)
            text:SetJustifyH(spec.justifyH)
        end
    end
    if button.HotKey then
        button.HotKey:SetAlpha(opt("text.hotkey") and 1 or 0)
    end
    if button.Name then
        button.Name:SetAlpha(opt("text.macro") and 1 or 0)
    end
end

--- Gives a skinned (borrowed) button its Blizzard look back. The size is restored by the caller.
---@param button table
function Style:Remove(button)
    local skin = button.eternitySkin
    if not skin or not skin.active then
        return
    end
    skin.active = false
    for key, alpha in pairs(skin.art) do
        local region = button[key] or (key == "NormalTexture" and button:GetNormalTexture())
        if region then
            region:SetAlpha(alpha)
        end
    end
    skin.border:Hide()
    skin.backdrop:Hide()
    local icon = button.icon
    icon:RemoveMaskTexture(skin.innerMask)
    if button.IconMask then
        icon:AddMaskTexture(button.IconMask)
    end
    icon:SetTexCoord(0, 1, 0, 1)
    for key, points in pairs(skin.points) do
        restorePoints(button[key], points)
    end
    for _, saved in pairs(skin.states) do
        local texture = saved.texture
        texture:RemoveMaskTexture(skin.innerMask)
        if saved.atlas then
            texture:SetAtlas(saved.atlas)
        else
            texture:SetTexture(saved.file)
        end
        texture:SetBlendMode(saved.blend)
        texture:SetVertexColor(1, 1, 1, 1)
        restorePoints(texture, saved.points)
    end
    refreshIcon(button)
    if button.cooldown then
        button.cooldown:SetSwipeTexture(SQUARE)
        button.cooldown:SetSwipeColor(0, 0, 0, 0.8)
        button.cooldown:SetDrawEdge(true)
        button.cooldown:SetUseCircularEdge(false)
    end
end
