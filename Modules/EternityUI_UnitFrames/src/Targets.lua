-- EternityUI_UnitFrames: the targets of group members and raid tanks. Each of their buttons gets
-- a small one of its own beside it, showing what that member is targeting: a health bar, a small
-- icon and, if wanted, the name and the health percent.
--   * It's a secure unit button whose unit is its parent's ("useparent-unit") plus "target"
--     (unitsuffix), so it follows the header's changes of who sits in each button, in combat
--     too, and the unit watch shows it only while there's a target. Clicks target that unit.
--   * The game sends no events for party1target and the like: it's redrawn on the frames' timer
--     (Frame.lua) while shown, and at once when its member changes target (UNIT_TARGET).
--   * Making, placing and sizing it are protected: out of combat only (in combat they wait).
--   * Health values may be secret: they go straight to the bar and the text, never compared.

---@type string, EternityUIUnitFramesNamespace
local _, ns = ...
local E = EternityUI
local Shape, Theme = E.Shape, E.Theme
local Style, Elements = ns.Style, ns.Elements
local U, secret, Plain = Style.U, Style.Secret, Style.Plain

local CLASS_ICONS = "Interface\\TargetingFrame\\UI-Classes-Circles"
local RAID_ICONS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

---@class EternityUIUnitFramesTargets
local Targets = {}
ns.Targets = Targets

local function on(f, id)
    return U(f.uf.key, "Targets", id)
end

local function try(fn, ...)
    if not fn then
        return nil
    end
    local ok, a, b = pcall(fn, ...)
    if ok then
        return a, b
    end
    return nil
end

--- The unit a frame's target button shows ("party1" -> "party1target"), or nil.
---@param f table
---@return string?
function Targets.UnitOf(f)
    return f.unit and (f.unit .. "target") or nil
end

-- Builds the button (once). Preview frames get a plain one, for samples.
local function create(f)
    local t
    if f.previewOnly then
        t = CreateFrame("Frame", nil, f)
    else
        t = CreateFrame("Button", nil, f, "SecureUnitButtonTemplate")
        t:RegisterForClicks("AnyUp")
        t:SetAttribute("useparent-unit", true)
        t:SetAttribute("unitsuffix", "target")
        t:SetAttribute("*type1", "target")
        t:SetAttribute("*type2", "togglemenu")
    end
    t.owner = f
    t.shape = Shape.New(t, "BACKGROUND", -8)
    -- Never a field named "bar" on this button: SecureButton_GetModifiedAttribute takes
    -- `frame.bar` as the parent for "useparent-unit", so Blizzard's unit watch would read a
    -- value of ours every 0.2 s, taint its whole pass and get every Show, Hide and SetAttribute
    -- after it blocked in combat (also "buttonType", "isExtra" and "popup" are read there).
    t.healthBar = Style.Bar(t)
    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.overlay = CreateFrame("Frame", nil, t)
    t.overlay:SetAllPoints()
    t.overlay:SetFrameLevel(t.healthBar:GetFrameLevel() + 2)
    t.name = t.overlay:CreateFontString(nil, "OVERLAY")
    t.name:SetWordWrap(false)
    t.name:SetJustifyH("LEFT")
    t.value = t.overlay:CreateFontString(nil, "OVERLAY")
    t.value:SetWordWrap(false)
    t.value:SetJustifyH("RIGHT")
    Style.Font(t.name, 9)
    Style.Font(t.value, 9)
    t:Hide()
    f.targetButton = t
    return t
end

-- Where the button goes beside its frame.
local ANCHORS = {
    right = { "LEFT", "RIGHT", 1, 0 },
    left = { "RIGHT", "LEFT", -1, 0 },
    above = { "BOTTOM", "TOP", 0, 1 },
    below = { "TOP", "BOTTOM", 0, -1 },
}

-- Size, place and inside of the button from the frame's options.
local function layout(f, t)
    local width, height = on(f, "width"), on(f, "height")
    local gap = on(f, "gap")
    local anchor = ANCHORS[on(f, "anchor")] or ANCHORS.right
    t:SetSize(width, height)
    t:ClearAllPoints()
    t:SetPoint(anchor[1], f, anchor[2], anchor[3] * gap, anchor[4] * gap)
    local border = Style.Opt("look.border")
    local inset = border and 1 or 0
    Shape.Paint(t.shape, 0, { 0, 0, 0, 0.6 }, border and Theme.colors.border or nil)

    local icon = on(f, "icon")
    local size = height - inset * 2
    local left, right = inset, inset
    t.icon:ClearAllPoints()
    t.icon:SetSize(size, size)
    t.iconKind = icon
    if icon ~= "none" then
        if on(f, "iconSide") == "right" then
            t.icon:SetPoint("RIGHT", t, "RIGHT", -inset, 0)
            right = inset + size + 1
        else
            t.icon:SetPoint("LEFT", t, "LEFT", inset, 0)
            left = inset + size + 1
        end
    end
    t.icon:SetShown(icon ~= "none")
    t.healthBar:ClearAllPoints()
    t.healthBar:SetPoint("TOPLEFT", t, "TOPLEFT", left, -inset)
    t.healthBar:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -right, inset)
    Style.PaintBar(t.healthBar)

    local textSize = on(f, "textSize")
    Style.Font(t.name, textSize)
    Style.Font(t.value, textSize)
    t.name:ClearAllPoints()
    t.name:SetPoint("LEFT", t.healthBar, "LEFT", 2, 0)
    t.value:ClearAllPoints()
    t.value:SetPoint("RIGHT", t.healthBar, "RIGHT", -2, 0)
    t.showValue = on(f, "health") == "percent"
    t.name:SetPoint("RIGHT", t.healthBar, "RIGHT", t.showValue and -(textSize * 3.2) or -2, 0)
    t.name:SetShown(on(f, "name") and true or false)
    t.value:SetShown(t.showValue)
end

--- Makes, places and shows (by the unit watch) or hides the target button of a group or tanks
--- frame, by its options. Out of combat; in combat it waits.
---@param f table
function Targets.Layout(f)
    if not f.uf then
        return
    end
    -- A preview frame may have shown another kind of frame before.
    local wanted = (f.uf.targets and on(f, "enabled")) and true or false
    if not f.previewOnly and InCombatLockdown() then
        if wanted or f.targetButton then
            E.Combat.Run("EternityUI_UnitFrames.targets:" .. tostring(f), function()
                Targets.Layout(f)
            end)
        end
        return
    end
    local t = f.targetButton
    if not wanted then
        if t then
            if not f.previewOnly then
                UnregisterUnitWatch(t)
            end
            t:Hide()
        end
        return
    end
    t = t or create(f)
    layout(f, t)
    if f.previewOnly then
        t:Show()
        return
    end
    RegisterUnitWatch(t)
    Targets.Update(f)
end

-- The small icon: the raid target mark, the class of a player, or the portrait.
local function updateIcon(t, unit)
    local kind = t.iconKind
    if kind == "none" then
        return
    elseif kind == "raidTarget" then
        t.icon:SetTexture(RAID_ICONS)
        local index = GetRaidTargetIndex(unit)
        if secret(index) or index then
            t.icon:SetSpriteSheetCell(index, 4, 4)
            t.icon:SetAlpha(1)
        else
            -- No mark: the slot stays, empty.
            t.icon:SetAlpha(0)
        end
        return
    end
    t.icon:SetAlpha(1)
    local _, class = UnitClass(unit)
    local coords = CLASS_ICON_TCOORDS and type(class) == "string" and not secret(class) and CLASS_ICON_TCOORDS[class]
    if kind == "class" and coords and Plain(try(UnitIsPlayer, unit), false) then
        t.icon:SetTexture(CLASS_ICONS)
        t.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        SetPortraitTexture(t.icon, unit)
    end
end

--- Redraws a frame's target button from its unit's target as it is now.
---@param f table
function Targets.Update(f)
    local t = f.targetButton
    if not (t and t:IsVisible()) then
        return
    end
    local unit = Targets.UnitOf(f)
    if not (unit and UnitExists(unit)) then
        return
    end
    Style.SetBar(t.healthBar, UnitHealth(unit), UnitHealthMax(unit))
    local color
    if on(f, "colorBy") == "health" then
        color = Style.Color("health")
    else
        color = Elements.HealthColor(unit)
    end
    Style.BarColor(t.healthBar, color[1], color[2], color[3])
    if t.name:IsShown() then
        t.name:SetText(UnitName(unit) or "")
    end
    if t.showValue then
        local percent = Elements.HealthPercent(unit)
        if secret(percent) or percent ~= nil then
            t.value:SetFormattedText("%.0f%%", percent)
        else
            t.value:SetText("")
        end
    end
    updateIcon(t, unit)
end

--- A made-up target on a preview frame (its options as they are).
---@param f table
---@param index integer the sample's number (1-based)
function Targets.Sample(f, index)
    local t = f.targetButton
    if not (t and t:IsShown()) then
        return
    end
    local health = ({ 0.82, 0.45, 1, 0.2 })[(index - 1) % 4 + 1]
    t.healthBar:SetMinMaxValues(0, 1)
    t.healthBar:SetValue(health)
    local color = on(f, "colorBy") == "health" and Style.Color("health") or Style.Color("hostile")
    Style.BarColor(t.healthBar, color[1], color[2], color[3])
    t.name:SetText(ns.L.SAMPLE_TARGET)
    t.value:SetFormattedText("%.0f%%", health * 100)
    if t.iconKind == "raidTarget" then
        t.icon:SetTexture(RAID_ICONS)
        t.icon:SetSpriteSheetCell(8, 4, 4)
        t.icon:SetAlpha(1)
    elseif t.iconKind ~= "none" then
        t.icon:SetAlpha(1)
        t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        t.icon:SetTexture("Interface\\Icons\\INV_Misc_Head_Dragon_01")
    end
end
