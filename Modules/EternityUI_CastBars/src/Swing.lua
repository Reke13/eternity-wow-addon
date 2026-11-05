-- Swing timer: main hand, off hand and ranged as one Mover element. Forever tells addons each
-- swing through PLAYER_SWING(swingDuration, swingType) (C_SwingTimer, Camelot only): the server's
-- real swing, with parry haste and resets already in it, so nothing is estimated and the combat
-- log (closed to addons on Forever) isn't needed. Each swing becomes a Duration object for
-- StatusBar:SetTimerDuration; a plain duration is only a fallback. Retail has no such API: the
-- swing timer is off there.

---@type string, EternityUICastBarsNamespace
local addonName, ns = ...
local E = EternityUI
local Theme = E.Theme
local Cast, Timer, L = ns.Cast, ns.Timer, ns.L

local GAP = 3
local OUT_OF_RANGE_ALPHA = 0.4
local types = Enum and Enum.PlayerSwingType
local HANDS = {
    { key = "mainHand", type = types and types.MainHand or 0, label = "MAIN_HAND", melee = true, preview = 0.7 },
    { key = "offHand", type = types and types.OffHand or 1, label = "OFF_HAND", melee = true, preview = 0.35 },
    { key = "ranged", type = types and types.Ranged or 2, label = "RANGED", preview = 0.5 },
}
-- Blizzard's own swing bars (Blizzard_SwingTimer), to leave their range checks alone.
local BLIZZARD =
    { mainHand = "SwingTimerMainHandFrame", offHand = "SwingTimerOffHandFrame", ranged = "SwingTimerRangedFrame" }

local EVENTS = {
    "PLAYER_SWING",
    "PLAYER_SWING_RANGE_UPDATE",
    "PLAYER_LEAVE_COMBAT",
    "STOP_AUTOREPEAT_SPELL",
    "PLAYER_REGEN_ENABLED",
}

---@class EternityUICastBarsSwing
---@field frame table container
---@field rows table<string, table> Timer bars by hand
---@field byType table<number, table> Timer bars by Enum.PlayerSwingType
---@field enabled boolean?
---@field previewing boolean?
---@field ranges table<number, boolean> range checks this module turned on
local Swing = { HANDS = HANDS }
Swing.__index = Swing
ns.Swing = Swing

--- Whether this client tells addons about swings.
function Swing.Supported()
    return C_SwingTimer ~= nil and Enum ~= nil and Enum.PlayerSwingType ~= nil
end

local function opt(path)
    return E.store:Get(addonName, path)
end

---@return EternityUICastBarsSwing
function Swing.New()
    local self = setmetatable({ key = addonName .. ".swing", rows = {}, byType = {}, ranges = {} }, Swing)
    local frame = CreateFrame("Frame", "EternityUICastBarSwing", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:Hide()
    for _, hand in ipairs(HANDS) do
        local row = Timer.Create(frame)
        row.hand = hand
        row.showTime = true
        self.rows[hand.key] = row
        self.byType[hand.type] = row
    end
    frame:SetScript("OnEvent", function(_, event, ...)
        self:OnEvent(event, ...)
    end)
    self.frame = frame
    return self
end

local function wanted(row)
    return opt("swing." .. row.hand.key) and true or false
end

--- Size, colors and fixed slots for the hands that are on (a bar doesn't jump when another stops).
function Swing:ApplyLayout()
    local frame = self.frame
    local width, height = opt("layout.swingWidth"), opt("layout.swingHeight")
    frame:SetScale(opt("layout.scale"))
    local slot = 0
    for _, hand in ipairs(HANDS) do
        local row = self.rows[hand.key]
        Timer.Layout(row, width, height, Theme.RGBA(opt("colors." .. hand.key)))
        row:ClearAllPoints()
        if wanted(row) then
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -slot * (height + GAP))
            slot = slot + 1
        else
            Timer.Stop(row)
            row.running = false
        end
        row.label:SetText(opt("swing.names") and L[hand.label] or "")
        if not row.running then
            self:Idle(row)
        end
    end
    frame:SetSize(width, math.max(slot, 1) * (height + GAP) - GAP)
    self:UpdateRangeChecks()
end

--- A row that isn't swinging: the preview while Mover is open, hidden otherwise.
function Swing:Idle(row)
    row.running = false
    row:SetAlpha(1)
    if self.previewing and wanted(row) then
        Timer.SetStatic(row, row.hand.preview)
        row.time:SetText("")
        row:Show()
    else
        Timer.Stop(row)
    end
end

--- A swing started: the bar fills over its duration (a secret duration goes straight to the
--- Duration object).
---@param row table
---@param swingDuration any
function Swing:Start(row, swingDuration)
    row.running = true
    local create = C_DurationUtil and C_DurationUtil.CreateDuration
    if create then
        row.durationObject = row.durationObject or create()
        local ok = pcall(row.durationObject.SetTimeFromStart, row.durationObject, GetTime(), swingDuration)
        if ok and Timer.Run(row, row.durationObject) then
            return
        end
    end
    local plain = Cast.Plain(swingDuration)
    if type(plain) == "number" and plain > 0 then
        Timer.RunPlain(row, GetTime(), plain)
    else
        self:Idle(row)
    end
end

function Swing:OnEvent(event, ...)
    if event == "PLAYER_SWING" then
        local swingDuration, swingType = ...
        local row = self.byType[Cast.Plain(swingType)]
        if row and wanted(row) then
            self:Start(row, swingDuration)
        end
    elseif event == "PLAYER_SWING_RANGE_UPDATE" then
        local swingType, inRange, checksRange = ...
        local row = self.byType[Cast.Plain(swingType)]
        if not row or not opt("swing.range") then
            return
        end
        if Cast.IsSecret(inRange) or Cast.IsSecret(checksRange) then
            -- Can't combine secret booleans: dim on "in range" alone.
            if row.SetAlphaFromBoolean then
                row:SetAlphaFromBoolean(inRange, 1, OUT_OF_RANGE_ALPHA)
            end
        else
            row:SetAlpha((checksRange and not inRange) and OUT_OF_RANGE_ALPHA or 1)
        end
    elseif event == "PLAYER_LEAVE_COMBAT" then
        -- Auto attack stopped.
        for _, row in pairs(self.rows) do
            if row.hand.melee then
                self:Idle(row)
            end
        end
    elseif event == "STOP_AUTOREPEAT_SPELL" then
        self:Idle(self.rows.ranged)
    elseif event == "PLAYER_REGEN_ENABLED" then
        for _, row in pairs(self.rows) do
            self:Idle(row)
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
        local on = self.enabled and opt("swing.range") and wanted(self.rows[hand.key]) or false
        if on and not self.ranges[hand.type] then
            self.ranges[hand.type] = true
            pcall(C_SwingTimer.EnableRangeCheck, hand.type, true)
        elseif not on and self.ranges[hand.type] then
            self.ranges[hand.type] = nil
            if not blizzardChecks(hand) then
                pcall(C_SwingTimer.EnableRangeCheck, hand.type, false)
            end
        end
        if not on then
            self.rows[hand.key]:SetAlpha(1)
        end
    end
end

---@param on boolean
function Swing:SetPreview(on)
    self.previewing = on and true or false
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
    local frame = self.frame
    for _, event in ipairs(EVENTS) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:Show()
    self:ApplyLayout()
    E.Mover.Register({
        key = self.key,
        owner = addonName,
        label = L.SWING,
        frame = frame,
        point = "BOTTOM",
        x = 0,
        y = 250,
    })
end

function Swing:Disable()
    if not self.enabled then
        return
    end
    self.enabled = false
    self.previewing = false
    self.frame:UnregisterAllEvents()
    self:UpdateRangeChecks()
    for _, row in pairs(self.rows) do
        self:Idle(row)
    end
    E.Mover.Unregister(self.key)
    self.frame:Hide()
end
