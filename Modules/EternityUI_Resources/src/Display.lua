-- The parts (main bar, combo points, the druid's mana) as one Mover element or one each. The main
-- bar shows whatever UnitPowerType says, so a Druid's bar follows the form by itself: energy in Cat
-- Form, rage in Bear Form, mana otherwise (UNIT_DISPLAYPOWER and UPDATE_SHAPESHIFT_FORM). Combo
-- points show for Rogues and for Druids on energy; the druid's mana bar while the main bar isn't
-- mana. Nothing here is protected, so every part is shown, hidden and moved at any time.

---@type string, EternityUIResourcesNamespace
local addonName, ns = ...
local E = EternityUI
local Power, Bar, Pips, L = ns.Power, ns.Bar, ns.Pips, ns.L
local TYPES = Power.TYPES

-- Top to bottom in the stack. y: default place of each part on its own (CENTER of the screen).
local PARTS = {
    { key = "power", option = "parts.power", height = "layout.powerHeight", mover = "MOVER_POWER", y = -180 },
    { key = "combo", option = "parts.combo", height = "layout.comboHeight", mover = "MOVER_COMBO", y = -200 },
    { key = "mana", option = "parts.druidMana", height = "layout.manaHeight", mover = "MOVER_MANA", y = -215 },
}
local BY_KEY = {}
for _, part in ipairs(PARTS) do
    BY_KEY[part.key] = part
end
-- What the Mover's preview shows.
local SAMPLE = { power = 0.7, combo = 3, mana = 0.45 }

local EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_TARGET_CHANGED",
    "COMBO_TARGET_CHANGED",
    "UPDATE_SHAPESHIFT_FORM",
}
local UNIT_EVENTS = {
    "UNIT_POWER_FREQUENT",
    "UNIT_POWER_UPDATE",
    "UNIT_MAXPOWER",
    "UNIT_DISPLAYPOWER",
    "UNIT_POWER_POINT_CHARGE",
}

---@class EternityUIResourcesDisplay
---@field stack table the frame the parts stack in
---@field free table<string, table> a frame per part, for moving each one on its own
---@field parts table<string, table> part frames by key
---@field registered table<string, boolean> Mover keys registered now
---@field powerType number the main bar's power now
---@field token string?
---@field inCombat boolean?
---@field enabled boolean?
---@field previewing boolean?
local Display = { PARTS = PARTS, SAMPLE = SAMPLE }
Display.__index = Display
ns.Display = Display

local function opt(path)
    return E.store:Get(addonName, path)
end

local function newHolder(name)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:Hide()
    return frame
end

---@return EternityUIResourcesDisplay
function Display.New()
    local self = setmetatable({ parts = {}, free = {}, registered = {}, powerType = TYPES.Mana }, Display)
    self.stack = newHolder("EternityUIResources")
    self.parts.power = Bar.Create(self.stack)
    self.parts.combo = Pips.Create(self.stack)
    self.parts.mana = Bar.Create(self.stack)
    for _, part in ipairs(PARTS) do
        self.parts[part.key].part = part
        self.free[part.key] = newHolder("EternityUIResources" .. part.key)
    end
    self.stack:SetScript("OnEvent", function(_, event, ...)
        self:OnEvent(event, ...)
    end)
    return self
end

-- Whether the player's class can have the part at all (it's then movable even when not in use).
local function forClass(key)
    local class = Power.Class()
    if key == "combo" then
        return class == "ROGUE" or class == "DRUID"
    elseif key == "mana" then
        return class == "DRUID"
    end
    return true
end

-- Whether the part is turned on and fits the class.
local function wanted(key)
    return opt(BY_KEY[key].option) and forClass(key) or false
end

--- Whether the part has something to show now (always, while previewing).
---@param key string
---@return boolean
function Display:InUse(key)
    if not wanted(key) then
        return false
    elseif self.previewing then
        return true
    elseif key == "combo" then
        return Power.UsesCombo() and (not opt("display.comboTarget") or UnitExists("target")) or false
    elseif key == "mana" then
        return self.powerType ~= TYPES.Mana
    end
    return true
end

--- Whether the visibility option lets the bars show now.
---@return boolean
function Display:Allowed()
    if self.previewing then
        return true
    end
    local visibility = opt("display.visibility")
    if visibility == "combat" then
        return self.inCombat or false
    elseif visibility == "target" then
        return self.inCombat or UnitExists("target") or false
    end
    return true
end

--- Registers what can be moved now and forgets the rest: the stack, or each part on its own.
function Display:UpdateMover()
    local separate = opt("display.separate")
    local function set(key, on, element)
        if on and not self.registered[key] then
            element.key, element.owner = key, addonName
            element.point, element.x = "CENTER", 0
            element.openOptions = function()
                E:OpenOptions(addonName)
            end
            self.registered[key] = true
            E.Mover.Register(element)
        elseif not on and self.registered[key] then
            self.registered[key] = nil
            E.Mover.Unregister(key)
        end
    end
    set(addonName .. ".stack", self.enabled and not separate, { label = L.TITLE, frame = self.stack, y = -190 })
    for _, part in ipairs(PARTS) do
        local on = self.enabled and separate and wanted(part.key)
        set(addonName .. "." .. part.key, on, { label = L[part.mover], frame = self.free[part.key], y = part.y })
    end
end

--- Opacity for the state of combat (full while the Mover is open); the rest fade is per part.
function Display:UpdateAlpha()
    local alpha = self.previewing and 1 or opt(self.inCombat and "display.alphaCombat" or "display.alphaIdle")
    self.stack:SetAlpha(alpha)
    for _, frame in pairs(self.free) do
        frame:SetAlpha(alpha)
    end
end

-- The rest fade of a bar: only out of combat, never while previewing. May set a secret alpha.
local function restFade(self, frame, powerType)
    if self.previewing or self.inCombat or not opt("display.fadeAtRest") then
        frame:SetAlpha(1)
    else
        frame:SetAlpha(Power.RestAlpha(powerType, opt("display.restAlpha")))
    end
end

--- The main bar's value, text and rest fade.
function Display:UpdatePower()
    local frame = self.parts.power
    if self.previewing then
        Bar.SetValues(frame, SAMPLE.power, 1)
        frame.text:SetText("")
    else
        Bar.SetValues(frame, Power.Values(self.powerType))
        if frame.showText then
            Power.SetText(frame.text, opt("look.text"), self.powerType, opt("look.numbers"))
        end
    end
    restFade(self, frame, self.powerType)
end

--- The druid's mana bar.
function Display:UpdateMana()
    local frame = self.parts.mana
    if self.previewing then
        Bar.SetValues(frame, SAMPLE.mana, 1)
        frame.text:SetText("")
    else
        Bar.SetValues(frame, Power.Values(TYPES.Mana))
        if frame.showText then
            Power.SetText(frame.text, opt("look.manaText"), TYPES.Mana, opt("look.numbers"))
        end
    end
    restFade(self, frame, TYPES.Mana)
end

--- The combo points.
function Display:UpdateCombo()
    Pips.SetPoints(self.parts.combo, self.previewing and SAMPLE.combo or Power.ComboPoints())
end

--- Every value.
function Display:UpdateValues()
    if not self.enabled then
        return
    end
    self:UpdatePower()
    self:UpdateCombo()
    self:UpdateMana()
end

--- The power now, sizes, colors, places and what shows. A part not in use leaves the stack, so
--- the rest close up.
function Display:ApplyLayout()
    if not self.enabled then
        return
    end
    self.powerType, self.token = Power.Current()
    local width, gap, scale = opt("layout.width"), opt("layout.spacing"), opt("layout.scale")
    local separate = opt("display.separate")
    local up = opt("layout.grow") == "up"
    local allowed = self:Allowed()
    local offset, used = 0, 0
    local parts = self.parts

    Bar.Paint(parts.power, Power.Color(self.powerType, self.token))
    Bar.Paint(parts.mana, Power.Color(TYPES.Mana, "MANA", not opt("colors.blizzard") and "druidMana" or nil))
    Pips.Paint(parts.combo, E.Theme.RGBA(opt("colors.combo")), E.Theme.RGBA(opt("colors.comboFull")))

    self.stack:SetScale(scale)
    for _, part in ipairs(PARTS) do
        local key = part.key
        local frame, free = parts[key], self.free[key]
        local height = opt(part.height)
        if key == "combo" then
            Pips.Layout(frame, width, height, Power.ComboMax())
        else
            Bar.Layout(frame, width, height)
        end
        local inUse = self:InUse(key)
        free:SetScale(scale)
        free:SetSize(width, height)
        free:SetShown(separate and wanted(key) and allowed)
        frame:ClearAllPoints()
        if separate then
            frame:SetParent(free)
            frame:SetPoint("TOPLEFT")
        else
            frame:SetParent(self.stack)
            if inUse then
                frame:SetPoint(up and "BOTTOMLEFT" or "TOPLEFT", 0, up and offset or -offset)
                offset = offset + height + gap
                used = used + 1
            end
        end
        frame:SetShown(inUse)
    end
    self.stack:SetSize(width, used > 0 and offset - gap or opt("layout.powerHeight"))
    self.stack:SetShown(not separate and allowed)
    self:UpdateMover()
    self:UpdateAlpha()
    self:UpdateValues()
end

function Display:OnEvent(event)
    if event == "PLAYER_REGEN_DISABLED" then
        self.inCombat = true
        self:ApplyLayout()
    elseif event == "PLAYER_REGEN_ENABLED" then
        self.inCombat = false
        self:ApplyLayout()
    elseif event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_POINT_CHARGE" then
        self:UpdateValues()
    elseif event == "COMBO_TARGET_CHANGED" then
        self:UpdateCombo()
    else
        -- Form, maximum, target or world changes: what shows may change too.
        self:ApplyLayout()
    end
end

---@param on boolean
function Display:SetPreview(on)
    self.previewing = on and true or false
    self:ApplyLayout()
end

function Display:Enable()
    if self.enabled then
        return
    end
    self.enabled = true
    self.inCombat = InCombatLockdown() and true or false
    local frame = self.stack
    for _, event in ipairs(EVENTS) do
        -- An event this client doesn't have errors on RegisterEvent: skip it.
        pcall(frame.RegisterEvent, frame, event)
    end
    for _, event in ipairs(UNIT_EVENTS) do
        pcall(frame.RegisterUnitEvent, frame, event, "player")
    end
end

function Display:Disable()
    if not self.enabled then
        return
    end
    self.enabled = false
    self.previewing = false
    self.stack:UnregisterAllEvents()
    self:UpdateMover()
    self.stack:Hide()
    for _, frame in pairs(self.free) do
        frame:Hide()
    end
end
