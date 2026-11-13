-- EternityUI_UnitFrames: what goes inside a frame. Each element has Create (once per frame),
-- Layout (size and place from the options) and Update (from the unit, as it is now).
--   Health and Power: bars and texts. Values, maxima and percents may be secret: they go straight
--     to the StatusBar and to SetFormattedText. A color curve on UnitHealthPercent hides the
--     "missing" text at full health without reading the value.
--   Portrait: class icon, 2D portrait or 3D model.
--   Cast: the unit's cast or channel, on the cast's Duration object (SetTimerDuration).
--   Auras: buffs and debuffs in Blizzard's aura container (AuraBox.lua), so they show in combat.
--   Indicators: raid target, leader, combat, resting, PvP, ready check, highlights and range.

---@type string, EternityUIUnitFramesNamespace
local addonName, ns = ...
local E = EternityUI
local Shape, Theme = E.Shape, E.Theme
local L, Style, AuraBox = ns.L, ns.Style, ns.AuraBox
local opt, U, secret, Plain = Style.Opt, Style.U, Style.Secret, Style.Plain

local PORTRAIT_GAP = 0
local AURA_GAP = 2
local CLASS_ICONS = "Interface\\TargetingFrame\\UI-Classes-Circles"
local RAID_ICONS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local READY = {
    ready = "Interface\\RaidFrame\\ReadyCheck-Ready",
    notready = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    waiting = "Interface\\RaidFrame\\ReadyCheck-Waiting",
}

---@class EternityUIUnitFramesElements
local Elements = {}
ns.Elements = Elements

local function try(fn, ...)
    if not fn then
        return nil
    end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then
        return a, b, c, d
    end
    return nil
end

local function text(parent, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetWordWrap(false)
    Style.Font(fs, 12) -- Layout sets the real size; text may come before it
    return fs
end

-- A curve that's 0 at full (1.0) and 1 below it: the alpha of the "missing" text.
local missingCurve
local function fullHides()
    if missingCurve == nil then
        missingCurve = false
        if C_CurveUtil and C_CurveUtil.CreateCurve then
            local curve = C_CurveUtil.CreateCurve()
            if Enum and Enum.LuaCurveType then
                curve:SetType(Enum.LuaCurveType.Step)
            end
            curve:AddPoint(0, 1)
            curve:AddPoint(0.9995, 0)
            missingCurve = curve
        end
    end
    return missingCurve or nil
end

-- Frame ---------------------------------------------------------------------------------------

--- Builds every element on a frame (once).
---@param f table the unit button
function Elements.Create(f)
    f.shape = Shape.New(f, "BACKGROUND", -8)

    f.health = Style.Bar(f)
    -- Incoming heals and shields: bars that start where the health fill ends (anchored to its
    -- texture, so the game places them without Lua reading a value). Shields are clipped by the
    -- health bar; heals by a frame of their own that can reach past the bar's end (the frame's
    -- edge too), so a heal over full health shows, as far as the frame's option allows.
    f.health:SetClipsChildren(true)
    f.healsClip = CreateFrame("Frame", nil, f)
    f.healsClip:SetClipsChildren(true)
    f.heals = CreateFrame("StatusBar", nil, f.healsClip)
    f.heals:SetMinMaxValues(0, 1)
    f.heals:SetValue(0)
    f.absorbs = CreateFrame("StatusBar", nil, f.health)
    f.absorbs:SetMinMaxValues(0, 1)
    f.absorbs:SetValue(0)
    f.power = Style.Bar(f)

    f.overlay = CreateFrame("Frame", nil, f)
    f.overlay:SetAllPoints()
    f.overlay:SetFrameLevel(f.health:GetFrameLevel() + 5)
    f.healthLeft = text(f.overlay)
    f.healthRight = text(f.overlay)
    f.powerText = text(f.overlay)

    -- Portrait: a frame for the textures and a model, only one shown.
    f.portrait = CreateFrame("Frame", nil, f)
    f.portrait.texture = f.portrait:CreateTexture(nil, "ARTWORK")
    f.portrait.texture:SetAllPoints()
    f.portrait.model = CreateFrame("PlayerModel", nil, f.portrait)
    f.portrait.model:SetAllPoints()

    -- Cast bar under the frame, with the spell icon on its left.
    local cast = Style.Bar(f)
    cast.icon = cast:CreateTexture(nil, "ARTWORK")
    cast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    cast.name = text(cast)
    cast.time = text(cast)
    cast:Hide()
    f.cast = cast

    f.auras = CreateFrame("Frame", nil, f)

    -- Indicators on top of everything.
    local top = f.overlay
    f.raidIcon = top:CreateTexture(nil, "OVERLAY", nil, 2)
    f.raidIcon:SetTexture(RAID_ICONS)
    f.leaderIcon = top:CreateTexture(nil, "OVERLAY", nil, 2)
    f.leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
    f.combatIcon = top:CreateTexture(nil, "OVERLAY", nil, 2)
    f.combatIcon:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
    f.combatIcon:SetTexCoord(0.5, 1, 0, 0.49)
    f.restIcon = top:CreateTexture(nil, "OVERLAY", nil, 2)
    f.restIcon:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
    f.restIcon:SetTexCoord(0, 0.5, 0, 0.421875)
    f.pvpIcon = top:CreateTexture(nil, "OVERLAY", nil, 2)
    f.readyIcon = top:CreateTexture(nil, "OVERLAY", nil, 3)

    f.hover = f.overlay:CreateTexture(nil, "OVERLAY", nil, -1)
    f.hover:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.hover:SetBlendMode("ADD")
    f.hover:Hide()
    f.targeted = Shape.New(f.overlay, "OVERLAY", 4)

    f:HookScript("OnEnter", function(self)
        if self.uf and U(self.uf.key, "Indicators", "highlight") then
            self.hover:Show()
        end
        Elements.ShowTooltip(self)
    end)
    f:HookScript("OnLeave", function(self)
        self.hover:Hide()
        Elements.HideTooltip(self)
    end)
end

-- Tooltip ---------------------------------------------------------------------------------------

--- True if the "Unit tooltip on mouseover" option lets it show now.
---@return boolean
function Elements.TooltipWanted()
    local mode = opt("look.tooltip")
    if mode == "never" then
        return false
    elseif mode == "nocombat" then
        return not InCombatLockdown()
    end
    return true
end

-- Keeps the tooltip current while the mouse stays (GameTooltip calls its owner's UpdateTooltip).
local function updateTooltip(self)
    Elements.ShowTooltip(self)
end

--- The game's tooltip of the frame's unit, where Blizzard's unit frames put it, with the hint
--- that a right click opens its menu.
---@param f table
function Elements.ShowTooltip(f)
    local unit = f.unit
    if not (unit and UnitExists(unit) and Elements.TooltipWanted()) then
        -- Combat started with the mouse on it ("Out of combat"), or the unit left.
        Elements.HideTooltip(f)
        return
    end
    GameTooltip_SetDefaultAnchor(GameTooltip, f)
    if GameTooltip:SetUnit(unit) then
        if GameTooltip_AddBlankLineToTooltip and GameTooltip_AddInstructionLine and UNIT_POPUP_RIGHT_CLICK then
            GameTooltip_AddBlankLineToTooltip(GameTooltip)
            GameTooltip_AddInstructionLine(GameTooltip, UNIT_POPUP_RIGHT_CLICK)
        end
        GameTooltip:Show()
        f.UpdateTooltip = updateTooltip
    else
        f.UpdateTooltip = nil
    end
end

--- Hides the tooltip if this frame showed it.
---@param f table
function Elements.HideTooltip(f)
    f.UpdateTooltip = nil
    if GameTooltip:IsOwned(f) then
        GameTooltip:Hide()
    end
end

local function place(region, point, parent, relative, x, y)
    region:ClearAllPoints()
    region:SetPoint(point, parent, relative or point, x or 0, y or 0)
end

local SIDES = { left = "LEFT", center = "", right = "RIGHT" }

--- Places a text: on its bar, at the top, middle or bottom of the frame, or above or below it,
--- on the left, in the center or on the right. Texts on a side get most of the width, so two of
--- them on one line don't run into each other.
---@param f table
---@param fs table FontString
---@param bar table the text's own bar
---@param v string "bar", "top", "center", "bottom", "above" or "below"
---@param h string "left", "center" or "right"
---@param inner number the bars' width
function Elements.PlaceText(f, fs, bar, v, h, inner)
    local side = SIDES[h] or ""
    local x = h == "left" and 4 or (h == "right" and -4 or 0)
    local horizontal = side ~= "" and side or "CENTER"
    fs:ClearAllPoints()
    if v == "top" then
        fs:SetPoint("TOP" .. side, f.health, "TOP" .. side, x, -2)
    elseif v == "bottom" then
        local lowest = f.power:IsShown() and f.power or f.health
        fs:SetPoint("BOTTOM" .. side, lowest, "BOTTOM" .. side, x, 2)
    elseif v == "center" then
        fs:SetPoint(horizontal, f, horizontal, x, 0)
    elseif v == "above" then
        fs:SetPoint("BOTTOM" .. side, f, "TOP" .. side, x, 2)
    elseif v == "below" then
        fs:SetPoint("TOP" .. side, f, "BOTTOM" .. side, x, -2)
    else
        fs:SetPoint(horizontal, bar, horizontal, x, 0)
    end
    fs:SetJustifyH(h == "left" and "LEFT" or (h == "right" and "RIGHT" or "CENTER"))
    fs:SetWidth(math.max(20, (inner or 100) * (h == "center" and 1 or 0.62)))
end

--- Whether the Resources module is installed and running (it shows your power on its own).
---@return boolean
function Elements.ResourcesOn()
    local resources = E.GetModule and E:GetModule("EternityUI_Resources")
    return resources ~= nil and resources.active == true
end

--- Sizes and places everything from the frame's options. The button's own size is set by the
--- caller (out of combat); here only its children move.
---@param f table
---@param width number
---@param height number
--- Health and power bars' heights: the power bar, if its option is on, unless the unit has no
--- power at all (most NPCs that don't cast, f.noPower), when the health bar fills the frame.
function Elements.FitBars(f)
    local bars = f.bars
    if not bars then
        return
    end
    local showPower = bars.power and not f.noPower
    local powerHeight = showPower and bars.powerHeight or 0
    f.health:SetHeight(math.max(1, bars.inner - powerHeight - (showPower and bars.gap or 0)))
    f.power:SetShown(showPower)
    f.powerText:SetShown(showPower and bars.powerText)
end

function Elements.Layout(f, width, height)
    local key = f.uf.key
    local border = opt("look.border")
    local inset = border and 1 or 0
    local gap = opt("look.spacing")
    Shape.Paint(f.shape, 0, opt("look.background") and { 0, 0, 0, opt("look.backgroundAlpha") * 0.6 } or nil,
        border and Theme.colors.border or nil)

    -- Portrait: a square on one side.
    local side = opt("look.portraitType") == "none" and "off" or U(key, "", "portrait")
    local portraitSize = height - inset * 2
    local left, right = inset, inset
    f.portrait:SetShown(side ~= "off")
    if side ~= "off" then
        f.portrait:SetSize(portraitSize, portraitSize)
        if side == "left" then
            place(f.portrait, "TOPLEFT", f, "TOPLEFT", inset, -inset)
            left = inset + portraitSize + gap + PORTRAIT_GAP
        else
            place(f.portrait, "TOPRIGHT", f, "TOPRIGHT", -inset, -inset)
            right = inset + portraitSize + gap + PORTRAIT_GAP
        end
    end

    -- Bars: health on top, power under it.
    local inner = height - inset * 2
    local showPower = U(key, "Bars", "power")
    -- Your own power bar steps aside for the Resources module, if that option is on.
    if showPower and f.uf.player and U(key, "Bars", "hideWithResources") and Elements.ResourcesOn() then
        showPower = false
    end
    local powerHeight = showPower and math.max(3, math.floor(inner * U(key, "Bars", "powerHeight") / 100)) or 0
    f.health:ClearAllPoints()
    f.health:SetPoint("TOPLEFT", f, "TOPLEFT", left, -inset)
    f.health:SetPoint("TOPRIGHT", f, "TOPRIGHT", -right, -inset)
    if showPower then
        f.power:ClearAllPoints()
        f.power:SetPoint("TOPLEFT", f.health, "BOTTOMLEFT", 0, -gap)
        f.power:SetPoint("TOPRIGHT", f.health, "BOTTOMRIGHT", 0, -gap)
        f.power:SetHeight(powerHeight)
    end
    f.bars = { inner = inner, gap = gap, power = showPower, powerHeight = powerHeight }
    Style.PaintBar(f.health)
    Style.PaintBar(f.power)
    Elements.LayoutHeals(f, width - left - right)

    -- Texts.
    local size = U(key, "Text", "textSize")
    for _, fs in ipairs({ f.healthLeft, f.healthRight, f.powerText }) do
        Style.Font(fs, size)
    end
    local inner = width - left - right
    Elements.PlaceText(f, f.healthLeft, f.health, U(key, "Text", "leftV"), U(key, "Text", "leftH"), inner)
    Elements.PlaceText(f, f.healthRight, f.health, U(key, "Text", "rightV"), U(key, "Text", "rightH"), inner)
    Elements.PlaceText(f, f.powerText, f.power, U(key, "Text", "powerV"), U(key, "Text", "powerH"), inner)
    f.bars.powerText = showPower and powerHeight >= size * 0.8
    Elements.FitBars(f)

    -- Cast bar.
    local cast = f.cast
    local castOn = f.uf.cast and U(key, "Bars", "cast")
    cast.enabled = castOn and true or false
    local below = 0
    if castOn then
        local castHeight = U(key, "Bars", "castHeight")
        local icon = U(key, "Bars", "castIcon")
        cast:SetHeight(castHeight)
        cast:ClearAllPoints()
        cast:SetPoint("TOPLEFT", f, "BOTTOMLEFT", icon and castHeight + gap or 0, -gap - 1)
        cast:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -gap - 1)
        cast.icon:SetSize(castHeight, castHeight)
        place(cast.icon, "RIGHT", cast, "LEFT", -gap, 0)
        cast.icon:SetShown(icon and true or false)
        Style.Font(cast.name, math.max(8, math.min(size, castHeight - 3)))
        Style.Font(cast.time, math.max(8, math.min(size, castHeight - 3)))
        place(cast.name, "LEFT", cast, "LEFT", 4, 0)
        place(cast.time, "RIGHT", cast, "RIGHT", -4, 0)
        cast.name:SetPoint("RIGHT", cast.time, "LEFT", -4, 0)
        cast.name:SetJustifyH("LEFT")
        Style.PaintBar(cast)
        below = castHeight + gap + 1
    else
        cast:Hide()
    end
    f.castSpace = below

    -- Indicators.
    local icon = math.max(12, math.min(20, math.floor(height * 0.45)))
    f.raidIcon:SetSize(icon, icon)
    -- The raid target icon in the middle of the bars (health and power, beside the portrait).
    place(f.raidIcon, "CENTER", f, "CENTER", (left - right) / 2, 0)
    f.leaderIcon:SetSize(icon * 0.8, icon * 0.8)
    place(f.leaderIcon, "CENTER", f, "TOPLEFT", left + 6, 0)
    f.combatIcon:SetSize(icon, icon)
    place(f.combatIcon, "CENTER", f, "BOTTOMLEFT", left + 4, 2)
    f.restIcon:SetSize(icon, icon)
    place(f.restIcon, "CENTER", f, "TOPLEFT", left + 4 + icon, 0)
    f.pvpIcon:SetSize(icon * 1.4, icon * 1.4)
    place(f.pvpIcon, "CENTER", f, "TOPRIGHT", -right - 4, -2)
    f.readyIcon:SetSize(icon * 1.2, icon * 1.2)
    place(f.readyIcon, "CENTER", f.health, "CENTER", 0, 0)
    f.hover:ClearAllPoints()
    f.hover:SetAllPoints(f.health)
    local hc = Style.Color("highlight")
    f.hover:SetVertexColor(hc[1], hc[2], hc[3], 0.12)
    Shape.Paint(f.targeted, 0, nil, { hc[1], hc[2], hc[3], 0.9 })
    Elements.LayoutAuras(f, width)
end

-- Health --------------------------------------------------------------------------------------

local function levelText(unit)
    local level = Plain(UnitLevel(unit), nil)
    if type(level) ~= "number" then
        return ""
    end
    local value = level > 0 and tostring(level) or L.LEVEL_UNKNOWN
    local kind = Plain(UnitClassification and UnitClassification(unit), nil)
    if kind == "elite" or kind == "worldboss" then
        value = value .. "+"
    elseif kind == "rareelite" then
        value = value .. "R+"
    elseif kind == "rare" then
        value = value .. "R"
    end
    return value
end

-- The color of the health bar: offline or dead, tapped, class, reaction or the health color.
local function healthColor(unit)
    if Plain(UnitIsConnected(unit), true) == false or Plain(UnitIsDeadOrGhost(unit), false) == true then
        return Style.Color("offline")
    end
    if Plain(UnitIsTapDenied(unit), false) == true then
        return Style.Color("tapped")
    end
    local player = Plain(UnitIsPlayer(unit), false)
    if (player or unit == "pet") and opt("colors.classHealth") then
        local _, class = UnitClass(unit)
        local color = Style.ClassColor(class)
        if color and player then
            return color
        end
    end
    if not player and opt("colors.reactionHealth") then
        local reaction = Plain(UnitReaction(unit, "player"), nil)
        if type(reaction) == "number" then
            if reaction <= 3 then
                return Style.Color("hostile")
            elseif reaction == 4 then
                return Style.Color("neutral")
            end
            return Style.Color("friendly")
        end
    end
    return Style.Color("health")
end

-- Dead, ghost or offline, or nil.
local function statusOf(unit)
    if Plain(UnitIsConnected(unit), true) == false then
        return L.OFFLINE
    elseif Plain(UnitIsGhost(unit), false) == true then
        return L.GHOST
    elseif Plain(UnitIsDead(unit), false) == true then
        return L.DEAD
    end
    return nil
end

local function healthLeftText(fs, mode, unit)
    if mode == "none" then
        fs:SetText("")
    elseif mode == "level" then
        fs:SetText(levelText(unit))
    elseif mode == "nameLevel" then
        fs:SetFormattedText("%s %s", levelText(unit), UnitName(unit) or "")
    else
        fs:SetText(UnitName(unit) or "")
    end
end

local function percentOf(fn, unit)
    if fn and CurveConstants and CurveConstants.ScaleTo100 then
        local ok, value = pcall(fn, unit, true, CurveConstants.ScaleTo100)
        if ok and (secret(value) or value ~= nil) then
            return value
        end
    end
    return nil
end

local function healthRightText(fs, mode, unit, style)
    fs:SetAlpha(1)
    -- "No numbers": no value and no percent.
    if mode == "none" or style == "none" then
        fs:SetText("")
        return
    end
    local current = UnitHealth(unit)
    if mode == "currentMax" then
        if Style.SetNumbersAs(style, fs, "# / #", current, UnitHealthMax(unit)) then
            return
        end
    elseif mode == "percent" or mode == "currentPercent" then
        local percent = percentOf(UnitHealthPercent, unit)
        if percent and mode == "percent" then
            fs:SetFormattedText("%.0f%%", percent)
            return
        elseif percent and Style.SetNumbersAs(style, fs, "#  %.0f%%", current, percent) then
            return
        end
    elseif mode == "missing" then
        if Style.SetNumbersAs(style, fs, "-#", try(UnitHealthMissing, unit, true)) then
            local curve = fullHides()
            local alpha = curve and try(UnitHealthPercent, unit, true, curve)
            if Style.Secret(alpha) or alpha ~= nil then
                fs:SetAlpha(alpha)
            end
            return
        end
    end
    if not Style.SetNumbersAs(style, fs, "#", current) then
        fs:SetText("")
    end
end

-- Incoming heals and shields -------------------------------------------------------------------

--- Places the heals and shields bars: as wide as the health bar, from where its fill ends. The
--- heals can go past the bar's end by the frame's "overheal" option (% of the bar's width).
---@param f table
---@param width number the health bar's width
function Elements.LayoutHeals(f, width)
    local key = f.uf.key
    local fill = f.health:GetStatusBarTexture()
    local texture = Style.Texture()
    local heals, absorbs = f.heals, f.absorbs
    local clip = f.healsClip
    local over = math.max(U(key, "Bars", "overheal") or 0, 0) / 100
    clip:ClearAllPoints()
    clip:SetPoint("TOPLEFT", f.health, "TOPLEFT")
    clip:SetPoint("BOTTOMLEFT", f.health, "BOTTOMLEFT")
    clip:SetWidth(math.max(width * (1 + over), 1))
    clip:SetFrameLevel(f.health:GetFrameLevel() + 1)
    heals:ClearAllPoints()
    heals:SetPoint("TOPLEFT", fill, "TOPRIGHT")
    heals:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT")
    heals:SetWidth(math.max(width, 1))
    heals:SetStatusBarTexture(texture)
    local hc = Style.Color("incomingHeals")
    heals:SetStatusBarColor(hc[1], hc[2], hc[3], 0.55)
    heals:SetShown(U(key, "Bars", "incomingHeals") and true or false)
    -- Shields go after the heals (or right after the health when heals are off).
    local after = heals:IsShown() and heals:GetStatusBarTexture() or fill
    absorbs:ClearAllPoints()
    absorbs:SetPoint("TOPLEFT", after, "TOPRIGHT")
    absorbs:SetPoint("BOTTOMLEFT", after, "BOTTOMRIGHT")
    absorbs:SetWidth(math.max(width, 1))
    absorbs:SetStatusBarTexture(texture)
    local ac = Style.Color("absorbs")
    absorbs:SetStatusBarColor(ac[1], ac[2], ac[3], 0.6)
    absorbs:SetShown(U(key, "Bars", "absorbs") and true or false)
    heals:SetFrameLevel(f.health:GetFrameLevel() + 1)
    absorbs:SetFrameLevel(f.health:GetFrameLevel() + 1)
end

-- A value that may be secret, or 0 when the game gives none.
local function amount(fn, ...)
    if not fn then
        return 0
    end
    local ok, value = pcall(fn, ...)
    if not ok or (not secret(value) and value == nil) then
        return 0
    end
    return value
end

--- The heals on their way to the unit and what its shields absorb, out of its maximum health.
function Elements.UpdateHeals(f)
    local unit = f.unit
    local max = UnitHealthMax(unit)
    if f.heals:IsShown() then
        f.heals:SetMinMaxValues(0, max)
        f.heals:SetValue(amount(UnitGetIncomingHeals, unit))
    end
    if f.absorbs:IsShown() then
        f.absorbs:SetMinMaxValues(0, max)
        f.absorbs:SetValue(amount(UnitGetTotalAbsorbs, unit))
    end
end

function Elements.UpdateHealth(f)
    local unit, key = f.unit, f.uf.key
    Style.SetBar(f.health, UnitHealth(unit), UnitHealthMax(unit))
    Elements.UpdateHeals(f)
    local color = healthColor(unit)
    Style.BarColor(f.health, color[1], color[2], color[3])
    healthLeftText(f.healthLeft, U(key, "Text", "healthLeft"), unit)
    local status = U(key, "Indicators", "status") and statusOf(unit)
    if status then
        f.healthRight:SetAlpha(1)
        f.healthRight:SetText(status)
    else
        healthRightText(f.healthRight, Style.TextMode(key, "healthRight"), unit, Style.NumberStyle(key))
    end
end

-- Power ---------------------------------------------------------------------------------------

-- Whether a unit has no power at all: a maximum of 0 (false when the game won't say).
local function powerless(unit)
    local max = try(UnitPowerMax, unit)
    return not secret(max) and max == 0
end

function Elements.UpdatePower(f)
    local unit, key = f.unit, f.uf.key
    local none = (unit and not f.previewing and powerless(unit)) or false
    if none ~= (f.noPower or false) then
        f.noPower = none
        Elements.FitBars(f)
    end
    if not f.power:IsShown() then
        return
    end
    local powerType, token = UnitPowerType(unit)
    Style.SetBar(f.power, UnitPower(unit, powerType), UnitPowerMax(unit, powerType))
    local color = Style.PowerColor(powerType, token)
    Style.BarColor(f.power, color[1], color[2], color[3])
    local mode = Style.TextMode(key, "powerText")
    local fs = f.powerText
    if mode == "none" or Style.NumberStyle(key) == "none" then
        fs:SetText("")
        return
    end
    local current = UnitPower(unit, powerType)
    if mode == "currentMax" then
        if Style.SetNumbersAs(Style.NumberStyle(key), fs, "# / #", current, UnitPowerMax(unit, powerType)) then
            return
        end
    elseif mode == "percent" and UnitPowerPercent and CurveConstants and CurveConstants.ScaleTo100 then
        local ok, percent = pcall(UnitPowerPercent, unit, powerType, false, CurveConstants.ScaleTo100)
        if ok and (secret(percent) or percent ~= nil) then
            fs:SetFormattedText("%.0f%%", percent)
            return
        end
    end
    if not Style.SetNumbersAs(Style.NumberStyle(key), fs, "#", current) then
        fs:SetText("")
    end
end

-- Portrait ------------------------------------------------------------------------------------

function Elements.UpdatePortrait(f)
    local p = f.portrait
    if not p:IsShown() then
        return
    end
    local unit = f.unit
    local kind = opt("look.portraitType")
    local _, class = UnitClass(unit)
    local coords = CLASS_ICON_TCOORDS and type(class) == "string" and not secret(class) and CLASS_ICON_TCOORDS[class]
    if kind == "model" then
        p.texture:Hide()
        p.model:Show()
        p.model:ClearModel()
        p.model:SetUnit(unit)
        p.model:SetPortraitZoom(1)
        p.model:SetCamDistanceScale(1)
        return
    end
    p.model:Hide()
    p.texture:Show()
    if kind == "class" and coords and Plain(UnitIsPlayer(unit), false) then
        p.texture:SetTexture(CLASS_ICONS)
        p.texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        p.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        SetPortraitTexture(p.texture, unit)
    end
end

-- Cast ----------------------------------------------------------------------------------------

local function readCast(unit)
    if UnitCastingInfo then
        local ok, name, _, icon, startMs, endMs, _, _, notInterruptible = pcall(UnitCastingInfo, unit)
        if ok and name then
            return { channel = false, name = name, icon = icon, startMs = Plain(startMs, nil), endMs = Plain(endMs, nil),
                locked = notInterruptible, duration = try(UnitCastingDuration, unit) }
        end
    end
    if UnitChannelInfo then
        local ok, name, _, icon, startMs, endMs, _, notInterruptible = pcall(UnitChannelInfo, unit)
        if ok and name then
            return { channel = true, name = name, icon = icon, startMs = Plain(startMs, nil), endMs = Plain(endMs, nil),
                locked = notInterruptible, duration = try(UnitChannelDuration, unit) }
        end
    end
    return nil
end

local function castOnUpdate(cast)
    local info = cast.info
    if not info then
        return
    end
    if cast.timer and info.duration then
        local ok, remaining = pcall(info.duration.GetRemainingDuration, info.duration)
        if ok and remaining ~= nil then
            cast.time:SetFormattedText("%.1f", remaining)
        end
        return
    end
    if info.startMs and info.endMs then
        local now = GetTime() * 1000
        local total = info.endMs - info.startMs
        local elapsed = math.min(math.max(now - info.startMs, 0), total)
        cast:SetValue(info.channel and (total - elapsed) or elapsed)
        cast.time:SetFormattedText("%.1f", (total - elapsed) / 1000)
        if now >= info.endMs + 300 then
            cast.info = nil
            cast:Hide()
        end
    end
end

function Elements.UpdateCast(f)
    local cast = f.cast
    if not cast.enabled then
        cast:Hide()
        return
    end
    local info = readCast(f.unit)
    cast.info = info
    if not info then
        cast:Hide()
        cast:SetScript("OnUpdate", nil)
        return
    end
    cast.name:SetText(info.name)
    cast.icon:SetTexture(info.icon)
    local normal, locked = Style.Color("cast"), Style.Color("castLocked")
    normal = { Style.Tone(normal[1], normal[2], normal[3]) }
    locked = { Style.Tone(locked[1], locked[2], locked[3]) }
    normal[4], locked[4] = 1, 1
    local texture = cast:GetStatusBarTexture()
    texture:SetAlpha(opt("look.barAlpha"))
    if texture.SetVertexColorFromBoolean and CreateColor then
        texture:SetVertexColorFromBoolean(info.locked, CreateColor(unpack(locked)), CreateColor(unpack(normal)))
    else
        local c = Plain(info.locked, false) and locked or normal
        texture:SetVertexColor(c[1], c[2], c[3], 1)
    end
    local timers = Enum and Enum.StatusBarTimerDirection
    cast.timer = false
    if info.duration and cast.SetTimerDuration and timers then
        local direction = info.channel and timers.RemainingTime or timers.ElapsedTime
        local immediate = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or 0
        cast.timer = pcall(cast.SetTimerDuration, cast, info.duration, immediate, direction)
    end
    if not cast.timer and info.startMs and info.endMs then
        cast:SetMinMaxValues(0, math.max(info.endMs - info.startMs, 1))
    end
    cast:SetScript("OnUpdate", castOnUpdate)
    cast:Show()
end

function Elements.StopCast(f)
    f.cast.info = nil
    f.cast:SetScript("OnUpdate", nil)
    f.cast:Hide()
end

-- Auras ---------------------------------------------------------------------------------------
-- Blizzard's aura container draws them (AuraBox.lua): it follows its unit on its own, also in
-- combat. Here they're only placed and pointed at the frame's unit.

--- Where the aura icons go, their filters and look.
function Elements.LayoutAuras(f, width)
    AuraBox.Layout(f, width)
end

--- Points the aura containers at the frame's unit and refreshes them when someone else is
--- behind it, or when it came back into view (far away its auras stop updating). Cheap when
--- nothing changed, so it's also checked on the frames' timer.
---@param f table
---@param force boolean? refresh anyway
function Elements.UpdateAuras(f, force)
    if not f.auraContainers or not f.unit then
        return
    end
    local guid, visible = UnitGUID(f.unit), UnitIsVisible(f.unit)
    if secret(guid) or secret(visible) then
        -- Can't tell who it is: refresh only when asked to.
        if force then
            AuraBox.SetUnit(f, f.unit)
        end
        return
    end
    local stamp = f.unit .. ":" .. tostring(guid) .. ":" .. tostring(visible)
    if force or stamp ~= f.auraStamp then
        f.auraStamp = stamp
        AuraBox.SetUnit(f, f.unit)
    end
end

-- Indicators ----------------------------------------------------------------------------------

-- Shows a texture by a boolean that may be secret.
local function showBy(texture, value)
    if secret(value) then
        texture:Show()
        texture:SetAlphaFromBoolean(value, 1, 0)
    else
        texture:SetAlpha(1)
        texture:SetShown(value and true or false)
    end
end

--- Shows raid target `index` (1-8) on a texture holding the icons' sheet. Forever always hands
--- GetRaidTargetIndex's answer as a secret: it can't be compared, but SetSpriteSheetCell takes it
--- as it is (Blizzard's SetRaidTargetIconTexture does the same, but it's Blizzard's code).
--- nil (no target icon) hides it.
---@param texture table
---@param index any
function Elements.SetRaidIcon(texture, index)
    if secret(index) or index then
        texture:SetSpriteSheetCell(index, 4, 4)
        texture:Show()
    else
        texture:Hide()
    end
end

function Elements.UpdateIndicators(f)
    local unit, key = f.unit, f.uf.key
    local function on(id)
        return U(key, "Indicators", id)
    end
    -- No "x and index or nil": `or` would test the secret.
    local index = nil
    if on("raidTarget") then
        index = GetRaidTargetIndex(unit)
    end
    Elements.SetRaidIcon(f.raidIcon, index)
    if on("leader") then
        showBy(f.leaderIcon, UnitIsGroupLeader(unit))
    else
        f.leaderIcon:Hide()
    end
    if f.uf.player then
        f.combatIcon:SetShown(on("combat") and UnitAffectingCombat("player") == true)
        f.restIcon:SetShown(on("resting") and IsResting() and not UnitAffectingCombat("player"))
    else
        f.combatIcon:Hide()
        f.restIcon:Hide()
    end
    local faction = Plain(UnitFactionGroup(unit), nil)
    if f.uf.pvp ~= false and on("pvp") and (faction == "Horde" or faction == "Alliance") then
        f.pvpIcon:SetTexture("Interface\\TargetingFrame\\UI-PVP-" .. faction)
        f.pvpIcon:SetTexCoord(0, 0.65, 0, 0.65)
        showBy(f.pvpIcon, UnitIsPVP(unit))
    else
        f.pvpIcon:Hide()
    end
    Elements.UpdateReady(f)
    Elements.UpdateTargeted(f)
end

function Elements.UpdateReady(f)
    if not (f.uf.group and U(f.uf.key, "Indicators", "readyCheck")) then
        f.readyIcon:Hide()
        return
    end
    local status = Plain(GetReadyCheckStatus and GetReadyCheckStatus(f.unit), nil)
    if status and READY[status] then
        f.readyIcon:SetTexture(READY[status])
        f.readyIcon:Show()
    elseif not f.readyFinished then
        f.readyIcon:Hide()
    end
end

function Elements.UpdateTargeted(f)
    local wanted = f.uf.group and U(f.uf.key, "Indicators", "targetHighlight")
    if not wanted then
        f.targeted.border:SetAlpha(0)
        return
    end
    local same = UnitIsUnit(f.unit, "target")
    if secret(same) then
        f.targeted.border:SetAlphaFromBoolean(same, 1, 0)
    else
        f.targeted.border:SetAlpha(same and 1 or 0)
    end
end

-- Spells of each class whose range tells whether a unit is in reach: an attack for enemies, a
-- heal or buff for friends. Forever's own (1.x) IDs. Of those the player knows, the one whose reach
-- is nearest the distance wanted is used; melee ones (Wing Clip, Sinister Strike, Heroic Strike,
-- Taunt) cover the dead zone up close of ranged attacks with a minimum range (Shoot, Throw, shots).
local RANGE_SPELLS = {
    hostile = {
        MAGE = { 133, 116, 5143 }, WARLOCK = { 686, 172 }, PRIEST = { 585, 589 }, DRUID = { 5176, 8921 },
        SHAMAN = { 403, 8042 }, HUNTER = { 75, 3044, 1978, 2974 }, PALADIN = { 879, 20271 },
        ROGUE = { 2764, 3018, 1752 }, WARRIOR = { 3018, 2764, 355, 78 },
    },
    friendly = {
        PRIEST = { 2050, 2061, 17 }, DRUID = { 5185, 774 }, SHAMAN = { 331, 8004 }, PALADIN = { 635, 19750 },
        MAGE = { 1459 }, WARLOCK = { 5697 },
    },
}
Elements.RANGE_SPELLS = RANGE_SPELLS
local rangeSpell = {}

-- A spell's minimum and maximum range in yards (0 and nil when the game doesn't say).
local function reach(id)
    local info = C_Spell and C_Spell.GetSpellInfo and try(C_Spell.GetSpellInfo, id)
    if type(info) ~= "table" then
        return 0, nil
    end
    local low, high = Plain(info.minRange, nil), Plain(info.maxRange, nil)
    return type(low) == "number" and low or 0, type(high) == "number" and high > 0 and high or nil
end

-- How far a spell's reach is from the distance wanted (lower is better): the longest reach within
-- it first, then the shortest beyond it, then spells whose reach is unknown (in the list's order).
local function score(high, yards)
    if not high then
        return 2000
    elseif high <= yards then
        return yards - high
    end
    return 1000 + high - yards
end

-- The spells for a kind ("hostile" or "friendly") and a distance, once found: the one to ask, its
-- minimum range, and a spell without one for up close. False when the player knows none.
local function spellFor(kind, yards)
    local id = kind .. ":" .. yards
    if rangeSpell[id] == nil then
        rangeSpell[id] = false
        local _, class = UnitClass("player")
        local best, bestScore, close, closeHigh
        for _, spell in ipairs((not secret(class) and RANGE_SPELLS[kind][class]) or {}) do
            if IsPlayerSpell and IsPlayerSpell(spell) then
                local low, high = reach(spell)
                local s = score(high, yards)
                if not best or s < bestScore then
                    best, bestScore = { spell = spell, low = low }, s
                end
                if low <= 0 and (not close or (high or 0) > closeHigh) then
                    close, closeHigh = spell, high or 0
                end
            end
        end
        if best then
            best.close = close ~= best.spell and close or nil
            rangeSpell[id] = best
        end
    end
    return rangeSpell[id]
end

--- Forgets the spells found (new spells learned).
function Elements.ResetRangeSpells()
    rangeSpell = {}
end

-- Whether a unit is the player: true, false, or nil when the game won't say (a secret answer).
local function isPlayer(unit)
    if unit == "player" then
        return true
    end
    local same = try(UnitIsUnit, unit, "player")
    if secret(same) or same == nil then
        return nil
    end
    return same == true
end

-- Tokens that always name another group member or their pet (party1, raid12, partypet2...).
local function groupToken(unit)
    return unit:match("^party%d") ~= nil or unit:match("^raid%d") ~= nil
        or unit:match("^partypet%d") ~= nil or unit:match("^raidpet%d") ~= nil
end

-- Whether the game's group range can be asked about a unit: a member of the player's group (or a
-- pet of one), known not to be the player. Forever hands UnitInRange's answers as secrets for
-- anyone, so they can't tell a member from a stranger (whose "in range" is always false), nor from
-- the player (never "checked": also false). A target of target, often the player, counts only
-- when the game says plainly it isn't.
local function inGroup(unit, me)
    if me ~= false and not groupToken(unit) then
        return false
    end
    return Plain(try(UnitPlayerOrPetInParty, unit), false) == true
        or Plain(try(UnitPlayerOrPetInRaid, unit), false) == true
end

-- Whether a spell reaches a unit: true, false, a secret boolean, or nil.
local function spellInRange(spell, unit)
    local ok, result = pcall(C_Spell.IsSpellInRange, spell, unit)
    if ok then
        return result
    end
    return nil
end

-- Whether a unit is within one of the game's interaction distances (3: duel, about 10 yards;
-- 4: follow, about 28): true, false, or nil when it can't be told. Out of combat only: in combat
-- the game may restrict it for enemies.
local function interact(unit, index)
    if not CheckInteractDistance or (InCombatLockdown and InCombatLockdown()) then
        return nil
    end
    local near = try(CheckInteractDistance, unit, index)
    if secret(near) or type(near) ~= "boolean" then
        return nil
    end
    return near
end

--- Whether a unit is in reach: true, false, a secret boolean, or nil when it can't be told.
---@param unit string
---@param yards number? the distance wanted (40 by default)
function Elements.InRange(unit, yards)
    yards = tonumber(yards) or 40
    local me = isPlayer(unit)
    if me then
        return true
    end
    -- Group members outside instances: the real distance.
    if UnitDistanceSquared then
        local ok, squared, measured = pcall(UnitDistanceSquared, unit)
        if ok and measured == true and type(squared) == "number" and not secret(squared) then
            return squared <= yards * yards
        end
    end
    -- Group members inside them: the game's group range (about 40 yards).
    if inGroup(unit, me) then
        local inRange, checked = UnitInRange(unit)
        if secret(checked) or checked == true then
            return inRange
        end
    end
    -- Anyone else: a spell of the player's class.
    local hostile = Plain(try(UnitCanAttack, "player", unit), nil)
    local found = hostile ~= nil and C_Spell and C_Spell.IsSpellInRange
        and spellFor(hostile and "hostile" or "friendly", yards)
    if found then
        local result = spellInRange(found.spell, unit)
        -- Too close for a spell with a minimum range: a melee spell, or the duel distance.
        if found.low > 0 and not secret(result) and result == false then
            if found.close and Plain(spellInRange(found.close, unit), false) == true then
                return true
            end
            if interact(unit, 3) then
                return true
            end
        end
        if secret(result) or result ~= nil then
            return result
        end
    end
    -- No spell can tell (a warrior and a friendly NPC, Throw without a thrown weapon): the
    -- game's follow distance, about 28 yards.
    return interact(unit, 4)
end

--- Faded out of range, if the frame's option is on. The answer may be secret: SetAlphaFromBoolean.
function Elements.UpdateRange(f)
    if f.uf.player then
        return
    end
    if not U(f.uf.key, "Indicators", "rangeFade") then
        if f.rangeFaded then
            f.rangeFaded = nil
            f:SetAlpha(1)
        end
        return
    end
    local alpha = U(f.uf.key, "Indicators", "rangeAlpha")
    local inRange = Elements.InRange(f.unit, U(f.uf.key, "Indicators", "rangeYards"))
    f.rangeFaded = true
    if secret(inRange) then
        f:SetAlphaFromBoolean(inRange, 1, alpha)
    elseif inRange == false then
        f:SetAlpha(alpha)
    else
        f:SetAlpha(1)
    end
end

--- The player's frame out of combat, without a target: faded (if that option is on).
function Elements.UpdateFade(f)
    if not f.uf.player then
        return
    end
    if U("player", "Indicators", "combatFade") and not UnitAffectingCombat("player") and not UnitExists("target") then
        f:SetAlpha(U("player", "Indicators", "idleAlpha"))
    else
        f:SetAlpha(1)
    end
end

--- Everything, from the unit as it is now.
function Elements.UpdateAll(f)
    if not f.unit or not UnitExists(f.unit) then
        return
    end
    Elements.UpdateHealth(f)
    Elements.UpdatePower(f)
    Elements.UpdatePortrait(f)
    Elements.UpdateCast(f)
    Elements.UpdateAuras(f)
    Elements.UpdateIndicators(f)
    Elements.UpdateFade(f)
end
