-- EternityUI_UnitFrames: shared helpers. Options of a frame, secret checks, textures, fonts and
-- colors. A value that may be secret is only handed to widgets that take secrets (StatusBar
-- values, SetText, SetFormattedText, SetAlphaFromBoolean, SetTexture...), never compared.

---@type string, EternityUIUnitFramesNamespace
local addonName, ns = ...
local E = EternityUI
local Theme = E.Theme

local TEXTURES = {
    smooth = "Interface\\TargetingFrame\\UI-StatusBar",
    flat = "Interface\\Buttons\\WHITE8X8",
    blizzard = "Interface\\TargetingFrame\\UI-StatusBar",
    raid = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
}
-- Outline flags, and whether a shadow goes under the text too.
local OUTLINES = {
    none = { "", true },
    plain = { "", false },
    thin = { "OUTLINE", false },
    thinShadow = { "OUTLINE", true },
    thick = { "THICKOUTLINE", false },
    thickShadow = { "THICKOUTLINE", true },
    mono = { "MONOCHROME", true },
    thinMono = { "OUTLINE, MONOCHROME", false },
    thickMono = { "THICKOUTLINE, MONOCHROME", false },
}
-- The game's fonts and a size factor, so each reads about as big as the others (as the theme does).
local FONTS = {
    arialn = { "Fonts\\ARIALN.TTF", 1 },
    friz = { "Fonts\\FRIZQT__.TTF", 0.87 },
    morpheus = { "Fonts\\MORPHEUS.TTF", 1.05 },
    skurri = { "Fonts\\skurri.ttf", 0.95 },
}

---@class EternityUIUnitFramesStyle
local Style = { TEXTURES = TEXTURES }
ns.Style = Style

--- An option of the module ("group.option").
function Style.Opt(path)
    return E.store:Get(addonName, path)
end
local opt = Style.Opt

--- An option of a frame: Style.U("player", "Bars", "power") reads "playerBars.power".
---@param key string
---@param section string "" for the frame group, or "Bars", "Text", "Auras", "Indicators"
---@param id string
function Style.U(key, section, id)
    return opt(key .. section .. "." .. id)
end

--- True for a secret value (always false on clients without secrets).
function Style.Secret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end
local secret = Style.Secret

--- The value when it can be used in Lua, otherwise the fallback.
function Style.Plain(value, fallback)
    if secret(value) then
        return fallback
    end
    return value
end

--- { r, g, b, a } of a color option.
function Style.Color(path)
    return Theme.RGBA(opt("colors." .. path))
end

--- The bar texture file.
function Style.Texture()
    return TEXTURES[opt("look.texture")] or TEXTURES.smooth
end

--- The font file and scale of the "Font" option: one of the game's fonts, or the theme's. The
--- theme's font size option applies to all of them.
---@return string file
---@return number scale
function Style.FontFile()
    -- The core's list when it has one (it ships more fonts), ours otherwise.
    local fonts = Theme.FONTS or FONTS
    local font = fonts[opt("look.font")]
    if font then
        -- Theme.fontScale already has the theme font's own factor in it: take it out.
        local themeFactor = Theme.fontFactor
        if not themeFactor then
            themeFactor = 1
            for _, other in pairs(fonts) do
                if type(Theme.font) == "string" and other[1]:lower() == Theme.font:lower() then
                    themeFactor = other[2]
                end
            end
        end
        return font[1], font[2] * Theme.fontScale / themeFactor
    end
    return Theme.font, Theme.fontScale
end

--- The chosen font at a size, with the outline option and its shadow.
---@param text table FontString
---@param size number
function Style.Font(text, size)
    local outline = OUTLINES[opt("look.outline")] or OUTLINES.none
    local file, scale = Style.FontFile()
    if not text:SetFont(file, size * scale, outline[1]) then
        text:SetFont(Theme.font, size * Theme.fontScale, outline[1])
    end
    text:SetShadowOffset(1, -1)
    text:SetShadowColor(0, 0, 0, outline[2] and 0.9 or 0)
end

--- A status bar with the module's texture and a dark track behind it.
---@param parent table
---@return table
function Style.Bar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetAllPoints()
    Style.PaintBar(bar)
    return bar
end

--- Texture of a bar and its track from the options.
function Style.PaintBar(bar)
    local texture = Style.Texture()
    bar:SetStatusBarTexture(texture)
    bar.track:SetTexture(texture)
    bar.track:SetVertexColor(0.08, 0.08, 0.1, opt("look.background") and opt("look.backgroundAlpha") or 0)
end

local SHADES = { none = nil, soft = 0.7, strong = 0.45 }

--- A color with the tone options: intensity (toward its gray, or past it) and brightness.
---@return number r, number g, number b
function Style.Tone(r, g, b)
    local gray = r * 0.3 + g * 0.59 + b * 0.11
    local s = opt("look.saturation")
    r, g, b = gray + (r - gray) * s, gray + (g - gray) * s, gray + (b - gray) * s
    local light = opt("look.brightness")
    local function clamp(v)
        return math.max(0, math.min(1, v * light))
    end
    return clamp(r), clamp(g), clamp(b)
end

--- Sets a bar's color with the tone, opacity and shading options; its track gets a darker shade.
---@param bar table
---@param r any may be secret (then it goes as it is, without tone or shading)
function Style.BarColor(bar, r, g, b)
    local alpha = opt("look.barAlpha")
    local texture = bar:GetStatusBarTexture()
    if secret(r) or secret(g) or secret(b) then
        bar:SetStatusBarColor(r, g, b, alpha)
        return
    end
    r, g, b = Style.Tone(r, g, b)
    local shade = SHADES[opt("look.shade")]
    if shade and texture and texture.SetGradient and CreateColor then
        bar:SetStatusBarColor(1, 1, 1, 1)
        texture:SetGradient("VERTICAL", CreateColor(r * shade, g * shade, b * shade, alpha), CreateColor(r, g, b, alpha))
    else
        if texture and texture.SetGradient and CreateColor then
            -- Clears an earlier gradient.
            texture:SetGradient("VERTICAL", CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1))
        end
        bar:SetStatusBarColor(r, g, b, alpha)
    end
    bar.track:SetVertexColor(r * 0.2, g * 0.2, b * 0.2, opt("look.background") and opt("look.backgroundAlpha") or 0)
end

--- Shows a value out of a maximum on a bar; both may be secret.
function Style.SetBar(bar, current, max)
    bar:SetMinMaxValues(0, max)
    local smooth = opt("look.smooth") and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
    if smooth then
        bar:SetValue(current, smooth)
    else
        bar:SetValue(current)
    end
end

--- A number as short text ("12.4K"), secret-safe: nil if it can't be read at all.
function Style.Short(value)
    if value == nil then
        return nil
    end
    if AbbreviateNumbers then
        local ok, text = pcall(AbbreviateNumbers, value)
        if ok then
            return text
        end
    end
    value = Style.Plain(value, nil)
    if type(value) ~= "number" then
        return nil
    end
    if value >= 1e6 then
        return ("%.1fM"):format(value / 1e6)
    elseif value >= 1e4 then
        return ("%.1fK"):format(value / 1e3)
    end
    return tostring(math.floor(value + 0.5))
end

--- A number in the "Number format" option's style, secret-safe. Returns what SetFormattedText
--- takes: a format piece and its value, or nil if it can't be read. A secret number only goes to
--- "%d" (formatted on the C side) or to BreakUpLargeNumbers / AbbreviateNumbers.
---@param value any
---@return string? piece
---@return any value
function Style.Number(value, style)
    if value == nil then
        return nil
    end
    style = style or Style.numberStyle or opt("look.numbers")
    if style == "full" or style == "separated" then
        if style == "separated" and BreakUpLargeNumbers then
            local ok, text = pcall(BreakUpLargeNumbers, value)
            if ok and (secret(text) or text ~= nil) then
                return "%s", text
            end
        end
        if secret(value) then
            return "%d", value
        end
        if type(value) == "number" then
            return "%d", math.floor(value + 0.5)
        end
        return nil
    end
    local short = Style.Short(value)
    if short then
        return "%s", short
    end
    return nil
end

--- The number format of a frame: its own (Texts > Number format), or General's when it says
--- "Like General".
---@param key string
---@return string
function Style.NumberStyle(key)
    local own = Style.U(key, "Text", "numbers")
    if own and own ~= "inherit" then
        return own
    end
    return opt("look.numbers")
end

--- A frame's text mode ("healthRight" or "powerText"): its own, or General's when it says
--- "Like General".
---@param key string
---@param id string
---@return string
function Style.TextMode(key, id)
    local own = Style.U(key, "Text", id)
    if own == "inherit" then
        return opt("look." .. id)
    end
    return own
end

--- Like SetNumbers, in a given number format.
function Style.SetNumbersAs(style, fs, pattern, ...)
    local previous = Style.numberStyle
    Style.numberStyle = style
    local ok, written = pcall(Style.SetNumbers, fs, pattern, ...)
    Style.numberStyle = previous
    return ok and written
end

--- Writes a format with numbers in it: pattern uses "#" where each number goes, e.g. "# / #".
--- Extra values (already formatted pieces, like a percent) follow with their own % codes.
---@param fs table FontString
---@param pattern string
---@return boolean written false when a number couldn't be read
function Style.SetNumbers(fs, pattern, ...)
    local args, n = {}, select("#", ...)
    local format = ""
    local index = 0
    for i = 1, #pattern do
        local c = pattern:sub(i, i)
        if c == "#" then
            index = index + 1
            local piece, value = Style.Number((select(index, ...)))
            if not piece then
                return false
            end
            format = format .. piece
            args[#args + 1] = value
        else
            format = format .. c
        end
    end
    for i = index + 1, n do
        args[#args + 1] = (select(i, ...))
    end
    fs:SetFormattedText(format, unpack(args, 1, #args))
    return true
end

-- Class colors -------------------------------------------------------------------------------

--- A class token's color, or nil.
function Style.ClassColor(class)
    if type(class) ~= "string" or secret(class) then
        return nil
    end
    local color = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
    return color and { color.r, color.g, color.b, 1 } or nil
end

--- A power type's color (Blizzard's or the option's).
function Style.PowerColor(powerType, token)
    if opt("colors.blizzardPower") then
        local colors = PowerBarColor
        local color = colors and ((token and not secret(token) and colors[token]) or (not secret(powerType) and colors[powerType]))
        if type(color) == "table" and color.r then
            return { color.r, color.g, color.b, 1 }
        end
    end
    return Style.Color("power")
end
