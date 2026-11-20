-- EternityUI_Range: the target's distance as a text the player places with the Mover. Distance
-- works it out; this draws it ten times a second while there's a target. Disabling the module
-- hides the text; nothing of Blizzard's is touched.

---@type string, EternityUIRangeNamespace
local addonName, ns = ...
local E = EternityUI
local L, Distance = ns.L, ns.Distance
local Theme = E.Theme

local KEY = addonName .. ".text"
local INTERVAL = 0.1

---@class EternityUIRangeModule: EternityUIModuleDefinition
---@field running boolean?
---@field frame table?
---@field previewing boolean?
local Module = { schema = ns.OptionsSchema, Distance = Distance }
ns.Module = Module

local function opt(path)
    return E.store:Get(addonName, path)
end

local ZONE_COLOR =
    { melee = "colors.melee", dead = "colors.deadZone", ["in"] = "colors.inRange", out = "colors.outOfRange" }

local function color(zone)
    if opt("colors.mode") == "single" then
        return Theme.RGBA(opt("colors.single"))
    end
    return Theme.RGBA(opt(ZONE_COLOR[zone] or "colors.outOfRange"))
end

-- What to measure for the target: "hostile", "friendly" or nil (nothing to show).
local function kindOf(unit)
    if not UnitExists(unit) then
        return nil
    end
    local dead = UnitIsDeadOrGhost(unit)
    if dead == true then
        return nil
    end
    local canAttack = UnitCanAttack("player", unit)
    if E.Secret.Is(canAttack) then
        return nil
    end
    if canAttack then
        return "hostile"
    end
    if opt("display.friendly") and not UnitIsUnit(unit, "player") then
        return "friendly"
    end
    return nil
end

function Module:Draw()
    local frame = self.frame
    if self.previewing then
        local c = color("in")
        frame.text:SetText(L.PREVIEW .. (opt("display.suffix") and L.UNIT or ""))
        frame.text:SetTextColor(c[1], c[2], c[3], 1)
        frame.text:Show()
        return
    end
    local kind = kindOf("target")
    if not kind or (opt("display.combatOnly") and not InCombatLockdown()) then
        frame.text:Hide()
        return
    end
    local low, high, zone = Distance.Measure("target", kind)
    if not low then
        frame.text:Hide()
        return
    end
    local c = color(zone)
    frame.text:SetText(Distance.Format(low, high) .. (opt("display.suffix") and L.UNIT or ""))
    frame.text:SetTextColor(c[1], c[2], c[3], 1)
    frame.text:Show()
end

function Module:Style()
    local frame = self.frame
    frame.text:SetFont(Theme.font, opt("display.size"), opt("display.outline") and "OUTLINE" or "")
    frame:SetSize(opt("display.size") * 5, opt("display.size") + 8)
    self:Draw()
end

local function create(self)
    local frame = CreateFrame("Frame", "EternityUIRangeText", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetFont(Theme.font, 20, "OUTLINE")
    frame.text:SetPoint("CENTER")
    local elapsed = 0
    frame:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed >= INTERVAL then
            elapsed = 0
            self:Draw()
        end
    end)
    self.frame = frame
end

function Module:OnEnable()
    self.running = true
    if not self.frame then
        create(self)
    end
    E.Mover.Register({
        key = KEY,
        owner = addonName,
        label = L.MOVER,
        frame = self.frame,
        point = "CENTER",
        x = 0,
        y = -110,
    })
    self.previewing = E.MoverSession ~= nil and E.MoverSession.active or false
    E.Events.Listen(E.Mover.TOGGLED, self, function(_, open)
        self.previewing = open
        self:Draw()
    end)
    E.Events.Listen(E.Theme.CHANGED, self, function()
        self:Style()
    end)
    -- New spells change what can be measured.
    for _, event in ipairs({ "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_TALENT_UPDATE" }) do
        E.Events.On(event, self, function()
            Distance.Reset()
        end)
    end
    self.frame:Show()
    self:Style()
end

function Module:OnDisable()
    self.running = false
    self.frame:Hide()
end

function Module:OnConfigChanged()
    if self.running then
        self:Style()
    end
end

E:RegisterModule(addonName, Module)
