-- The look of the suite. A theme (UI/Presets.lua) is a full look; the Appearance options can
-- override its corners, surfaces and font, and General its accent. Anything drawn reads colors
-- here and repaints on Theme.CHANGED.
---@type string, EternityUINamespace
local addonName, ns = ...
local Events = ns.Events

---@class EternityTheme
---@field colors table<string, number[]> the active palette
---@field accent number[] { r, g, b, a }
---@field surface string glass, flat or neon
---@field radius integer corner radius in physical pixels
---@field opacity number
---@field font string font file
---@field fontScale number
local Theme = {
    CHANGED = "ETERNITY_THEME_CHANGED",
    MEDIA = "Interface\\AddOns\\" .. addonName .. "\\media\\",
    WALLPAPERS = "Interface\\AddOns\\EternityUI_Wallpapers\\",
    presets = {},
}
ns.Theme = Theme
EternityUI.Theme = Theme

-- Layers of white over the window, lighter with depth. Only the accent adds color. A theme can
-- override any of them.
local SURFACES = {
    surface = { 1, 1, 1, 0.035 },
    surfaceHover = { 1, 1, 1, 0.06 },
    track = { 1, 1, 1, 0.14 },
    field = { 1, 1, 1, 0.06 },
    border = { 1, 1, 1, 0.075 },
    borderStrong = { 1, 1, 1, 0.16 },
    divider = { 1, 1, 1, 0.06 },
    onAccent = { 1, 1, 1, 1 },
    success = { 0.42, 0.86, 0.6, 1 },
    warning = { 0.98, 0.76, 0.32, 1 },
    shadow = { 0, 0, 0, 0.85 },
}

local RADII = { sharp = 0, soft = 5, round = 12 }

-- File and size factor, so every font reads about as big as Arial Narrow at one size.
local FONTS = {
    arialn = { "Fonts\\ARIALN.TTF", 1 },
    friz = { "Fonts\\FRIZQT__.TTF", 0.87 },
    morpheus = { "Fonts\\MORPHEUS.TTF", 1.05 },
    skurri = { "Fonts\\skurri.ttf", 0.95 },
}

--- Adds a theme.
---@param key string
---@param preset table
function Theme.RegisterPreset(key, preset)
    for token, color in pairs(SURFACES) do
        if preset.colors[token] == nil then
            preset.colors[token] = color
        end
    end
    Theme.presets[key] = preset
end

--- Converts "#RRGGBB" or "#RRGGBBAA" to { r, g, b, a }.
---@param hex string
---@return number[]
function Theme.FromHex(hex)
    local r, g, b, a = hex:match("^#(%x%x)(%x%x)(%x%x)(%x?%x?)$")
    return {
        tonumber(r, 16) / 255,
        tonumber(g, 16) / 255,
        tonumber(b, 16) / 255,
        a ~= "" and tonumber(a, 16) / 255 or 1,
    }
end

--- Converts r, g, b to "#RRGGBB".
---@return string
function Theme.ToHex(r, g, b)
    local function byte(value)
        return math.floor(value * 255 + 0.5)
    end
    return string.format("#%02X%02X%02X", byte(r), byte(g), byte(b))
end

local function luminance(c)
    return 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3]
end

local function option(path)
    return ns.store:Get("EternityUI", path)
end

-- The option's value, or the theme's when it's left on "preset".
local function pick(path, fromPreset)
    local value = option(path)
    return value == "preset" and fromPreset or value
end

--- Reads the options and tells everything to repaint.
function Theme.Reload()
    local preset = Theme.presets[option("appearance.theme")] or Theme.presets.midnight
    local colors = {}
    for token, color in pairs(preset.colors) do
        colors[token] = color
    end
    local accent = Theme.FromHex(option("general.themeAccent") and preset.accent or option("general.accentColor"))
    colors.accent = accent
    colors.accent2 = Theme.FromHex(preset.accent2)
    local r, g, b = accent[1], accent[2], accent[3]
    colors.accentHover = { r + (1 - r) * 0.18, g + (1 - g) * 0.18, b + (1 - b) * 0.18, 1 }
    colors.accentText = { r + (1 - r) * 0.4, g + (1 - g) * 0.4, b + (1 - b) * 0.4, 1 }
    colors.accentSoft = { r, g, b, 0.2 }
    colors.focus = { r, g, b, 0.85 }
    -- Light accents (gold, yellow, white) need dark text on top.
    if luminance(accent) > 0.55 then
        colors.onAccent = { 0.06, 0.05, 0.08, 1 }
    end
    Theme.surface = pick("appearance.style", preset.style)
    if Theme.surface == "neon" then
        colors.border = { accent[1], accent[2], accent[3], 0.32 }
        colors.borderStrong = { accent[1], accent[2], accent[3], 0.65 }
        colors.divider = { accent[1], accent[2], accent[3], 0.16 }
    end
    -- The names the widgets use.
    colors.raised = colors.windowTop
    colors.muted = colors.textMuted
    colors.line = colors.border
    colors.lineStrong = colors.borderStrong
    colors.hover = colors.surfaceHover

    Theme.colors = colors
    Theme.accent = accent
    Theme.radius = RADII[pick("appearance.corners", preset.corners)]
    Theme.opacity = option("appearance.opacity")
    local font = FONTS[pick("appearance.font", preset.font)]
    Theme.font = font[1]
    Theme.fontScale = font[2] * option("appearance.fontScale")
    Theme.wallpaper = option("appearance.wallpaper") and preset.wallpaper or nil
    Theme.wallpaperDim = option("appearance.wallpaperDim")
    Theme.portraits = option("appearance.portraits") and preset.portraits or nil
    Events.Send(Theme.CHANGED)
end

--- The edge color of a window or panel for the current surface.
---@return number[]
function Theme.Edge()
    if Theme.surface == "neon" then
        return Theme.accent
    end
    return Theme.surface == "glass" and Theme.colors.lineStrong or Theme.colors.line
end

--- Color of a spec: a token, "@token", "@token:AA" (AA is hex alpha) or "#RRGGBB[AA]".
---@param spec string|number[]
---@return number[] rgba a new table, white if the spec is not valid
function Theme.RGBA(spec)
    if type(spec) == "table" then
        return { spec[1], spec[2], spec[3], spec[4] or 1 }
    end
    if spec:sub(1, 1) == "#" then
        return Theme.FromHex(spec)
    end
    local token, alpha = spec:match("^@?(%w+):?(%x*)$")
    local color = token and Theme.colors[token]
    if not color then
        return { 1, 1, 1, 1 }
    end
    local a = color[4] or 1
    if alpha ~= "" then
        a = a * tonumber(alpha, 16) / 255
    end
    return { color[1], color[2], color[3], a }
end

--- r, g, b, a of a spec (see Theme.RGBA).
---@param spec string|number[]
---@return number, number, number, number
function Theme.Color(spec)
    return unpack(Theme.RGBA(spec))
end

--- Paints a window-like shape: a vertical gradient on glass, a flat color otherwise.
---@param shape table
function Theme.PaintWindow(shape)
    local c = Theme.colors
    local top, bottom = c.windowTop, c.window
    ns.Shape.Paint(shape, Theme.radius, { bottom[1], bottom[2], bottom[3], Theme.opacity }, Theme.Edge())
    if Theme.surface == "glass" then
        shape.fill:SetVertexColor(1, 1, 1, 1)
        shape.fill:SetGradient(
            "VERTICAL",
            CreateColor(bottom[1], bottom[2], bottom[3], Theme.opacity),
            CreateColor(top[1], top[2], top[3], Theme.opacity)
        )
    end
end

--- Adds a wallpaper to a frame: a photo over its shape's fill and a veil that keeps text readable.
---@param frame table
---@return table wallpaper
function Theme.NewWallpaper(frame)
    local wallpaper = {
        frame = frame,
        photo = frame:CreateTexture(nil, "BACKGROUND", nil, 1),
        veil = frame:CreateTexture(nil, "BACKGROUND", nil, 2),
    }
    wallpaper.veil:SetAllPoints(wallpaper.photo)
    return wallpaper
end

--- Paints a wallpaper for the current theme, covering the frame without stretching the photo. It
--- stays inside the shape's rounded corners. Hidden when the theme has no image for the slot.
---@param wallpaper table from Theme.NewWallpaper
---@param slot string window or chat
---@param visible boolean? false hides it whatever the theme says
function Theme.PaintWallpaper(wallpaper, slot, visible)
    local image = visible ~= false and Theme.wallpaper and Theme.wallpaper[slot]
    wallpaper.photo:SetShown(image and true or false)
    wallpaper.veil:SetShown(image and true or false)
    local frame = wallpaper.frame
    local width, height = frame:GetSize()
    if not image or width <= 0 or height <= 0 then
        return
    end
    -- A square inside a rounded corner clears it at 0.29 of the radius.
    local inset = math.ceil(Theme.radius * 0.3)
    wallpaper.photo:ClearAllPoints()
    wallpaper.photo:SetPoint("TOPLEFT", inset, -inset)
    wallpaper.photo:SetPoint("BOTTOMRIGHT", -inset, inset)
    wallpaper.photo:SetTexture(Theme.WALLPAPERS .. image.file .. ".tga")
    local box = width / height
    if box > image.aspect then
        local cut = (1 - image.aspect / box) / 2
        wallpaper.photo:SetTexCoord(0, 1, cut, 1 - cut)
    else
        local cut = (1 - box / image.aspect) / 2
        wallpaper.photo:SetTexCoord(cut, 1 - cut, 0, 1)
    end
    local r, g, b = Theme.Color("window")
    wallpaper.veil:SetColorTexture(r, g, b, Theme.wallpaperDim)
end

Events.Listen(ns.CONFIG_CHANGED, Theme, function(_, module, path)
    if path == "@profile" or (module == "EternityUI" and path and path:find("^appearance%.")) then
        Theme.Reload()
    elseif module == "EternityUI" and (path == "general.themeAccent" or path == "general.accentColor") then
        Theme.Reload()
    end
end)
