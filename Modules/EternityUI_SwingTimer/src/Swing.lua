-- The bars: main hand, off hand and ranged, as one Mover element or one each. Forever tells addons
-- each swing through PLAYER_SWING(swingDuration, swingType) (C_SwingTimer): the server's real
-- swing, with parry haste and resets already in it, so nothing is estimated and the combat log
-- (closed to addons on Forever) isn't needed. That also means only the player's swings exist here.
-- Each swing becomes a Duration object for StatusBar:SetTimerDuration; a plain duration is a
-- fallback.

---@type string, EternityUISwingTimerNamespace
local addonName, ns = ...
local E = EternityUI
local Secret, Theme = E.Secret, E.Theme
local Bar, L = ns.Bar, ns.L

local OUT_OF_RANGE_ALPHA = 0.4
local types = Enum and Enum.PlayerSwingType
-- attackSpeed: position of the hand in UnitAttackSpeed's returns. Slots as in Blizzard's paper doll.
local HANDS = {
    {
        key = "mainHand",
        type = types and types.MainHand or 0,
        attackSpeed = 1,
        slot = 16,
        label = "MAIN_HAND",
        mover = "MOVER_MAIN_HAND",
        melee = true,
        sound = true,
        preview = 0.7,
        y = 270,
    },
    {
        key = "offHand",
        type = types and types.OffHand or 1,
        attackSpeed = 2,
        slot = 17,
        label = "OFF_HAND",
        mover = "MOVER_OFF_HAND",
        melee = true,
        preview = 0.35,
        y = 250,
    },
    {
        key = "ranged",
        type = types and types.Ranged or 2,
        attackSpeed = 3,
        slot = 18,
        label = "RANGED",
        mover = "MOVER_RANGED",
        sound = true,
        preview = 0.5,
        y = 230,
    },
}
-- Blizzard's own swing bars (Blizzard_SwingTimer), to leave their range checks alone.
local BLIZZARD =
    { mainHand = "SwingTimerMainHandFrame", offHand = "SwingTimerOffHandFrame", ranged = "SwingTimerRangedFrame" }
local SOUNDS = { click = "IG_MAINMENU_OPTION_CHECKBOX_ON", ping = "MAP_PING" }

local EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_SWING",
    "PLAYER_SWING_RANGE_UPDATE",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_LEAVE_COMBAT",
    "STOP_AUTOREPEAT_SPELL",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "WEAPON_SLOT_CHANGED",
}

---@class EternityUISwingTimerSwing
---@field stack table the frame the bars stack in
---@field free table<string, table> a frame per hand, for moving each one on its own
---@field rows table<string, table> bars by hand
---@field byType table<number, table> bars by Enum.PlayerSwingType
---@field registered table<string, boolean> Mover keys registered now
---@field ranges table<number, boolean> range checks this module turned on
---@field enabled boolean?
---@field previewing boolean?
local Swing = { HANDS = HANDS, BLIZZARD = BLIZZARD }
Swing.__index = Swing
ns.Swing = Swing

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

---@return EternityUISwingTimerSwing
function Swing.New()
    local self = setmetatable({ rows = {}, byType = {}, free = {}, registered = {}, ranges = {} }, Swing)
    self.stack = newHolder("EternityUISwingTimer")
    for _, hand in ipairs(HANDS) do
        local row = Bar.Create(self.stack)
        row.hand = hand
        self.rows[hand.key] = row
        self.byType[hand.type] = row
        self.free[hand.key] = newHolder("EternityUISwingTimer" .. hand.key)
    end
    self.stack:SetScript("OnEvent", function(_, event, ...)
        self:OnEvent(event, ...)
    end)
    return self
end

local function wanted(row)
    return opt("hands." .. row.hand.key) and true or false
end

-- Whether the player can swing with this hand. An unreadable speed counts as yes.
local function hasWeapon(row)
    local attackSpeed = row.hand.attackSpeed
    if attackSpeed == 1 then
        return true
    end
    local speed = select(attackSpeed, UnitAttackSpeed("player"))
    if Secret.Is(speed) then
        return true
    end
    return speed ~= nil and speed > 0
end

local function isDrain()
    return opt("look.direction") == "drain"
end

-- The weapon's icon and the bar's text.
local function paintWeapon(row)
    local hand = row.hand
    row.icon:SetTexture(GetInventoryItemTexture("player", hand.slot))
    local mode = opt("look.label")
    local text = ""
    if mode == "hand" then
        text = L[hand.label]
    elseif mode == "weapon" then
        local id = GetInventoryItemID("player", hand.slot)
        text = id and C_Item.GetItemNameByID(id) or L[hand.label]
    end
    row.label:SetText(text)
end

--- Registers what can be moved now and forgets the rest: the stack, or each hand on its own.
function Swing:UpdateMover()
    local separate = opt("display.separate")
    local function set(key, on, element)
        if on and not self.registered[key] then
            element.key, element.owner = key, addonName
            element.point, element.x = "BOTTOM", 0
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
    set(addonName .. ".stack", self.enabled and not separate, { label = L.TITLE, frame = self.stack, y = 250 })
    for _, hand in ipairs(HANDS) do
        local on = self.enabled and separate and wanted(self.rows[hand.key])
        set(addonName .. "." .. hand.key, on, { label = L[hand.mover], frame = self.free[hand.key], y = hand.y })
    end
end

--- Opacity for the state of combat (full while the Mover is open).
function Swing:UpdateAlpha()
    local alpha = opt(InCombatLockdown() and "display.alphaCombat" or "display.alphaIdle")
    if self.previewing then
        alpha = 1
    end
    self.stack:SetAlpha(alpha)
    for _, frame in pairs(self.free) do
        frame:SetAlpha(alpha)
    end
end

--- Size, colors and places. A bar keeps its slot while another stops, so nothing jumps.
function Swing:ApplyLayout()
    local width, height = opt("layout.width"), opt("layout.height")
    local gap, scale = opt("layout.spacing"), opt("layout.scale")
    local separate = opt("display.separate")
    local up = opt("layout.grow") == "up"
    local slot = 0
    self.stack:SetScale(scale)
    for _, hand in ipairs(HANDS) do
        local row, free = self.rows[hand.key], self.free[hand.key]
        local on = wanted(row)
        row.color = Theme.RGBA(opt("colors." .. hand.key))
        Bar.Layout(row, width, height, row.color)
        free:SetScale(scale)
        free:SetSize(width, height)
        free:SetShown(on and separate)
        row:ClearAllPoints()
        if on and separate then
            row:SetParent(free)
            row:SetPoint("TOPLEFT")
        else
            row:SetParent(self.stack)
            if on then
                local y = slot * (height + gap)
                row:SetPoint(up and "BOTTOMLEFT" or "TOPLEFT", 0, up and y or -y)
                slot = slot + 1
            end
        end
        if not on then
            row.running = false
        end
        paintWeapon(row)
        if not row.running then
            self:Idle(row)
        end
    end
    self.stack:SetSize(width, math.max(slot, 1) * (height + gap) - gap)
    self.stack:SetShown(not separate)
    self:UpdateMover()
    self:UpdateAlpha()
    self:UpdateRangeChecks()
    self:CheckRange()
end

--- A bar that isn't swinging: the preview while the Mover is open, empty if the visibility option
--- keeps it on, hidden otherwise.
function Swing:Idle(row)
    row.running = false
    local visibility = opt("display.visibility")
    if not wanted(row) then
        Bar.Stop(row)
    elseif self.previewing then
        Bar.SetStatic(row, row.hand.preview)
        row:Show()
    elseif hasWeapon(row) and (visibility == "always" or (visibility == "combat" and InCombatLockdown())) then
        Bar.SetStatic(row, 0)
        row:Show()
    else
        Bar.Stop(row)
    end
end

--- A swing started: the bar runs over its duration (a secret duration goes straight to the Duration
--- object).
---@param row table
---@param swingDuration any
function Swing:Start(row, swingDuration)
    row.running = true
    local drain = isDrain()
    local create = C_DurationUtil and C_DurationUtil.CreateDuration
    if create then
        row.durationObject = row.durationObject or create()
        local ok = pcall(row.durationObject.SetTimeFromStart, row.durationObject, GetTime(), swingDuration)
        if ok and Bar.Run(row, row.durationObject, drain) then
            return
        end
    end
    local plain = Secret.Plain(swingDuration, nil)
    if type(plain) == "number" and plain > 0 then
        Bar.RunPlain(row, GetTime(), plain, drain)
    else
        self:Idle(row)
    end
end

--- Dims or recolors a bar for its range state. Booleans that are secret can't be combined or used
--- to pick a color, so then it dims on "in range" alone.
---@param row table
---@param inRange any
---@param checksRange any
function Swing:SetRange(row, inRange, checksRange)
    local mode = opt("range.mode")
    if Secret.Is(inRange) or Secret.Is(checksRange) then
        if mode ~= "off" and row.SetAlphaFromBoolean then
            row:SetAlphaFromBoolean(inRange, 1, OUT_OF_RANGE_ALPHA)
        end
        return
    end
    local out = checksRange and not inRange and mode ~= "off"
    row:SetAlpha(out and mode == "dim" and OUT_OF_RANGE_ALPHA or 1)
    local color = out and mode == "color" and Theme.RGBA(opt("colors.outOfRange")) or row.color
    Bar.Paint(row, color)
end

--- Asks the game about the current target. No answer (nil) isn't "out of range".
function Swing:CheckRange()
    local ask = C_SwingTimer and C_SwingTimer.IsTargetWithinSwingRange
    if not (ask and self.enabled) then
        return
    end
    for _, hand in ipairs(HANDS) do
        local ok, inRange = pcall(ask, hand.type)
        local known = ok and (Secret.Is(inRange) or inRange ~= nil)
        self:SetRange(self.rows[hand.key], ok and inRange, known)
    end
end

-- The weapon in a slot changed: a running swing restarts with its speed, as Blizzard's does.
function Swing:OnWeaponChanged()
    for _, row in pairs(self.rows) do
        paintWeapon(row)
        if row.running and hasWeapon(row) then
            self:Start(row, (select(row.hand.attackSpeed, UnitAttackSpeed("player"))))
        else
            self:Idle(row)
        end
    end
end

function Swing:OnEvent(event, ...)
    if event == "PLAYER_SWING" then
        local swingDuration, swingType = ...
        local row = self.byType[Secret.Plain(swingType, nil)]
        if row and wanted(row) then
            self:Start(row, swingDuration)
            local kit = row.hand.sound and SOUNDKIT[SOUNDS[opt("sound.swing")]]
            if kit then
                PlaySound(kit)
            end
        end
    elseif event == "PLAYER_SWING_RANGE_UPDATE" then
        local swingType, inRange, checksRange = ...
        local row = self.byType[Secret.Plain(swingType, nil)]
        if row then
            self:SetRange(row, inRange, checksRange)
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        self:CheckRange()
    elseif event == "PLAYER_LEAVE_COMBAT" then
        -- Auto attack stopped.
        for _, row in pairs(self.rows) do
            if row.hand.melee then
                self:Idle(row)
            end
        end
    elseif event == "STOP_AUTOREPEAT_SPELL" then
        self:Idle(self.rows.ranged)
    elseif event == "PLAYER_REGEN_DISABLED" then
        self:UpdateAlpha()
        for _, row in pairs(self.rows) do
            if not row.running then
                self:Idle(row)
            end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UpdateAlpha()
        for _, row in pairs(self.rows) do
            self:Idle(row)
        end
    elseif event == "WEAPON_SLOT_CHANGED" then
        self:OnWeaponChanged()
    elseif event == "UNIT_INVENTORY_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        -- WEAPON_SLOT_CHANGED isn't reliable on entering the world (Blizzard's comment says so).
        for _, row in pairs(self.rows) do
            paintWeapon(row)
            if not row.running then
                self:Idle(row)
            end
        end
    end
end

local function blizzardChecks(hand)
    local frame = _G[BLIZZARD[hand.key]]
    return frame ~= nil and frame.isRangeCheckEnabled == true
end

--- Asks the game for range updates on the hands shown (and gives back the ones it doesn't need,
--- unless Blizzard's own bar still uses them).
function Swing:UpdateRangeChecks()
    if not (C_SwingTimer and C_SwingTimer.EnableRangeCheck) then
        return
    end
    for _, hand in ipairs(HANDS) do
        local on = self.enabled and opt("range.mode") ~= "off" and wanted(self.rows[hand.key]) or false
        if on and not self.ranges[hand.type] then
            self.ranges[hand.type] = true
            pcall(C_SwingTimer.EnableRangeCheck, hand.type, true)
        elseif not on and self.ranges[hand.type] then
            self.ranges[hand.type] = nil
            if not blizzardChecks(hand) then
                pcall(C_SwingTimer.EnableRangeCheck, hand.type, false)
            end
        end
    end
end

---@param on boolean
function Swing:SetPreview(on)
    self.previewing = on and true or false
    self:UpdateAlpha()
    for _, row in pairs(self.rows) do
        if not row.running then
            self:Idle(row)
        end
    end
end

function Swing:Enable()
    if self.enabled then
        return
    end
    self.enabled = true
    local frame = self.stack
    for _, event in ipairs(EVENTS) do
        -- An event this client doesn't have errors on RegisterEvent: skip it.
        pcall(frame.RegisterEvent, frame, event)
    end
    pcall(frame.RegisterUnitEvent, frame, "UNIT_INVENTORY_CHANGED", "player")
end

function Swing:Disable()
    if not self.enabled then
        return
    end
    self.enabled = false
    self.previewing = false
    self.stack:UnregisterAllEvents()
    self:UpdateMover()
    self:UpdateRangeChecks()
    for _, row in pairs(self.rows) do
        row.running = false
        Bar.Stop(row)
    end
    self.stack:Hide()
    for _, frame in pairs(self.free) do
        frame:Hide()
    end
end
