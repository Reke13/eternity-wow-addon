-- EternityUI_Tooltip: restyles Blizzard's tooltips (GameTooltip, ItemRefTooltip, the
-- comparison ones...) with the Eternity look: the theme's window background and fonts, and its own
-- scale. Also: border by quality or class, position, hide in
-- combat and IDs.
-- No taint: it replaces no Blizzard method; only hooksecurefunc, HookScript and
-- TooltipDataProcessor.AddTooltipPostCall. It stores nothing in the tables of Blizzard's frames.
-- It doesn't read secret values (if a piece of data is secret, it isn't used) and the health bar and auras stay
-- as Blizzard draws them.
-- When disabled everything goes back to how it was, without /reload: hooks can't be removed, so
-- they're installed once and do nothing while `running` is false.

---The module's private table.
---@class EternityUITooltipNamespace
---@field OptionsSchema table schema generated from options.json (src/Generated/Options.lua)

---@type string, EternityUITooltipNamespace
local addonName, ns = ...
local E = EternityUI
local Shape, Theme, Widgets = E.Shape, E.Theme, E.Widgets

local strings = {
    enUS = { MOVER = "Tooltips" },
    esES = { MOVER = "Tooltips" },
}
local L = E.NewLocale(strings.enUS, strings.esES)

-- Tooltips that get restyled, if they exist (some arrive with on-demand Blizzard addons).
-- EmbeddedItemTooltip isn't here: it lives inside others and Blizzard already hides its background.
local TOOLTIPS = {
    "GameTooltip",
    "ItemRefTooltip",
    "ShoppingTooltip1",
    "ShoppingTooltip2",
    "ItemRefShoppingTooltip1",
    "ItemRefShoppingTooltip2",
    "GameNoHeaderTooltip",
    "QuickKeybindTooltip",
    "SettingsTooltip",
    "FriendsTooltip",
    "BattlePetTooltip",
    "FloatingBattlePetTooltip",
}
-- SettingsTooltip manages its own scale (TopLevelParentScaleFrameTemplate).
local OWN_SCALE = { SettingsTooltip = true }
-- Shared fonts of Blizzard's tooltips and the theme style they get.
local FONTS = { GameTooltipHeaderText = 15, GameTooltipText = 14, GameTooltipTextSmall = 12 }
local MODIFIERS = { shift = IsShiftKeyDown, ctrl = IsControlKeyDown, alt = IsAltKeyDown }

---@class EternityTooltipSkin
---@field backdrop EternityTooltipBackdrop
---@field scale number the tooltip's original scale

---@class EternityTooltipModule: EternityUIModuleDefinition
---@field skinned table<table, EternityTooltipSkin> Blizzard tooltip -> its skin
---@field fontBackup table<string, table>? original fonts {path, size, flags}
---@field running boolean?
---@field hooked boolean?
---@field mover table?
---@field themeWatcher table?
local KEY = addonName
local Tooltip = {
    schema = ns.OptionsSchema,
    skinned = {},
}

-- The background of a tooltip: the theme's window, with an optional border color. It lives on the
-- tooltip's BACKGROUND and BORDER layers, so its text stays on top.
local function newBackdrop(tip)
    local backdrop = { shown = true, shape = Shape.New(tip) }
    function backdrop:SetBorderColor(color)
        self.borderColor = color
        self:Paint()
    end
    function backdrop:SetShown(shown)
        self.shown = shown and true or false
        self:Paint()
    end
    function backdrop:Paint()
        if not self.shown then
            Shape.Paint(self.shape, 0, nil, nil)
            return
        end
        Theme.PaintWindow(self.shape)
        if self.borderColor then
            local c = self.borderColor
            self.shape.border:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
        end
    end
    return Widgets.Track(backdrop)
end

local function opt(path)
    return E.store:Get(addonName, path)
end

local function secret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

-- Skinning and unskinning ------------------------------------------------------------------

--- Scale of a skinned tooltip (the options' one, except those that manage their own).
local function applyScale(tip, skin)
    if not OWN_SCALE[tip:GetName()] then
        tip:SetScale(Tooltip.running and opt("look.scale") or skin.scale)
    end
end

function Tooltip:Skin(tip)
    local skin = self.skinned[tip]
    if not skin then
        skin = { backdrop = newBackdrop(tip), scale = tip:GetScale() }
        self.skinned[tip] = skin
        if tip:HasScript("OnTooltipCleared") then
            tip:HookScript("OnTooltipCleared", function(t)
                self:ResetBorder(t)
            end)
        end
        tip:HookScript("OnShow", function(t)
            self:OnTooltipShow(t)
        end)
    else
        skin.scale = tip:GetScale()
    end
    skin.backdrop:SetBorderColor(nil)
    skin.backdrop:SetShown(true)
    -- Alpha and not Hide: SharedTooltip_SetBackdropStyle calls Show() on the NineSlice again.
    tip.NineSlice:SetAlpha(0)
    applyScale(tip, skin)
end

function Tooltip:Unskin(tip)
    local skin = self.skinned[tip]
    skin.backdrop:SetShown(false)
    tip.NineSlice:SetAlpha(1)
    if not OWN_SCALE[tip:GetName()] then
        tip:SetScale(skin.scale)
    end
end

--- Skins the tooltips that exist and aren't skinned yet (or all of them, after enabling).
function Tooltip:SkinAll()
    for _, name in ipairs(TOOLTIPS) do
        local tip = _G[name]
        if tip and tip.NineSlice and (not self.skinned[tip] or not self.skinned[tip].backdrop.shown) then
            self:Skin(tip)
        end
    end
end

function Tooltip:ResetBorder(tip)
    local skin = self.skinned[tip]
    if skin and self.running then
        skin.backdrop:SetBorderColor(nil)
    end
end

--- Theme fonts on the tooltips' shared fonts, or the original ones.
function Tooltip:ApplyFonts()
    local themed = self.running and opt("look.fonts")
    for name, size in pairs(FONTS) do
        local font = _G[name]
        if font then
            if themed then
                self.fontBackup = self.fontBackup or {}
                self.fontBackup[name] = self.fontBackup[name] or { font:GetFont() }
                font:SetFont(Theme.font, size * Theme.fontScale, self.fontBackup[name][3] or "")
            elseif self.fontBackup and self.fontBackup[name] then
                local original = self.fontBackup[name]
                font:SetFont(original[1], original[2], original[3] or "")
                self.fontBackup[name] = nil
            end
        end
    end
end

-- Tooltip data (post-calls) ---------------------------------------------------------------

local function addId(tip, id)
    local r, g, b = Theme.Color("textMuted")
    tip:AddDoubleLine("ID", tostring(id), r, g, b, r, g, b)
    if tip:IsShown() then
        tip:Show() -- recomputes the size
    end
end

local function setBorder(tip, r, g, b)
    Tooltip.skinned[tip].backdrop:SetBorderColor({ r, g, b, 1 })
end

function Tooltip:OnItem(tip, data)
    if not self.running or not self.skinned[tip] or not data or secret(data.id) or not data.id then
        return
    end
    if opt("look.qualityBorder") then
        local quality = C_Item.GetItemQualityByID(data.id)
        -- Common (1) keeps the theme border: white adds nothing.
        if quality and not secret(quality) and quality ~= 1 then
            local r, g, b = C_Item.GetItemQualityColor(quality)
            if r then
                setBorder(tip, r, g, b)
            end
        end
    end
    if opt("info.itemId") then
        addId(tip, data.id)
    end
end

function Tooltip:OnSpell(tip, data)
    if self.running and self.skinned[tip] and data and not secret(data.id) and data.id and opt("info.spellId") then
        addId(tip, data.id)
    end
end

function Tooltip:OnUnit(tip)
    if not self.running or not self.skinned[tip] or not opt("look.classBorder") then
        return
    end
    local _, unit = tip:GetUnit()
    if not unit or secret(unit) then
        return
    end
    local isPlayer = UnitIsPlayer(unit)
    if secret(isPlayer) or not isPlayer then
        return
    end
    local _, class = UnitClass(unit)
    if not class or secret(class) then
        return
    end
    local color = C_ClassColor.GetClassColor(class)
    if color then
        setBorder(tip, color.r, color.g, color.b)
    end
end

-- Combat and position -----------------------------------------------------------------------

local function modifierDown()
    local isDown = MODIFIERS[opt("combat.modifier")]
    return isDown ~= nil and isDown()
end

function Tooltip:OnTooltipShow(tip)
    local mode = opt("combat.hide")
    if not self.running or mode == "never" or not InCombatLockdown() or modifierDown() then
        return
    end
    if mode == "world" then
        -- Units in the world: GameTooltip with the default anchor (owner UIParent or WorldFrame).
        local owner = tip == GameTooltip and tip:GetOwner()
        if owner ~= UIParent and owner ~= WorldFrame then
            return
        end
    end
    tip:Hide()
end

--- After Blizzard's default anchor: next to the cursor or at the custom position.
function Tooltip:OnDefaultAnchor(tip, parent)
    if not self.running or not self.skinned[tip] then
        return
    end
    local anchor = opt("position.anchor")
    if anchor == "cursor" then
        tip:SetOwner(parent, "ANCHOR_CURSOR")
    elseif anchor == "custom" and self.anchor then
        tip:ClearAllPoints()
        tip:SetPoint("BOTTOMRIGHT", self.anchor, "BOTTOMRIGHT")
    end
end

--- With the custom position, an invisible frame marks the spot (the tooltips' bottom right
--- corner) and it's a Mover element: the Mover moves it and the tooltips follow.
function Tooltip:UpdateAnchor()
    local custom = self.running and opt("position.anchor") == "custom"
    if custom and not self.anchor then
        -- Global name for tests and screenshots.
        self.anchor = CreateFrame("Frame", "EternityTooltipAnchor", UIParent)
        self.anchor:SetSize(200, 64)
    end
    if custom then
        if not E.Mover.elements[KEY] then
            E.Mover.Register({
                key = KEY,
                owner = addonName,
                label = L.MOVER,
                frame = self.anchor,
                point = "BOTTOMRIGHT",
                x = -60,
                y = 120,
            })
        end
    else
        E.Mover.Unregister(KEY)
    end
end

-- Lifecycle ---------------------------------------------------------------------------------

function Tooltip:InstallHooks()
    self.hooked = true
    if TooltipDataProcessor and Enum.TooltipDataType then
        local types = Enum.TooltipDataType
        TooltipDataProcessor.AddTooltipPostCall(types.Item, function(tip, data)
            self:OnItem(tip, data)
        end)
        TooltipDataProcessor.AddTooltipPostCall(types.Spell, function(tip, data)
            self:OnSpell(tip, data)
        end)
        TooltipDataProcessor.AddTooltipPostCall(types.Unit, function(tip)
            self:OnUnit(tip)
        end)
    end
    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tip, parent)
        self:OnDefaultAnchor(tip, parent)
    end)
    -- Tooltips from Blizzard addons that load later (e.g. QuickKeybindTooltip).
    local events = CreateFrame("Frame")
    events:RegisterEvent("ADDON_LOADED")
    events:SetScript("OnEvent", function()
        if self.running then
            self:SkinAll()
        end
    end)
end

function Tooltip:OnEnable()
    self.running = true
    if not self.hooked then
        self:InstallHooks()
    end
    -- The backgrounds repaint on their own; the fonts need this. The core releases it on disable.
    E.Events.Listen(Theme.CHANGED, self, function()
        self:ApplyFonts()
    end)
    self:SkinAll()
    self:ApplyFonts()
    self:UpdateAnchor()
end

function Tooltip:OnDisable()
    self.running = false
    for tip, skin in pairs(self.skinned) do
        if skin.backdrop.shown then
            self:Unskin(tip)
        end
    end
    self:ApplyFonts()
    self:UpdateAnchor()
end

function Tooltip:OnConfigChanged(path)
    -- path nil = reset or profile change: anything may have changed.
    if path == nil or path == "look.scale" then
        for tip, skin in pairs(self.skinned) do
            applyScale(tip, skin)
        end
    end
    if path == nil or path == "look.fonts" then
        self:ApplyFonts()
    end
    if path == nil or path:find("^position%.") then
        self:UpdateAnchor()
    end
end

E:RegisterModule(addonName, Tooltip)
