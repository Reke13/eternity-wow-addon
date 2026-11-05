-- One cast bar (player, target, focus, pet, or one boss or arena enemy inside a Group): a themed
-- track with a StatusBar driven by the cast's Duration object (secret-safe) or, without one, by
-- plain start and end times; spell icon, name and time texts, spark, latency, channel ticks,
-- empower stages and an uninterruptible border. It listens to its own unit's UNIT_SPELLCAST_*
-- events; CastBars.lua owns the rest.

---@type string, EternityUICastBarsNamespace
local addonName, ns = ...
local E = EternityUI
local Theme, UI = E.Theme, ns.UI
local Cast, Timer, L = ns.Cast, ns.Timer, ns.L

local PREVIEW_ICON = 134400 -- INV_Misc_QuestionMark
local ICON_GAP = 4
-- Milliseconds past a cast's end before the bar closes it by itself: a pushback may be on its way.
local EXPIRY_MARGIN = 200

local UNIT_EVENTS = {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_EMPOWER_STOP",
    "UNIT_SPELLCAST_INTERRUPTIBLE",
    "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}
local REFRESH = {
    UNIT_SPELLCAST_START = true,
    UNIT_SPELLCAST_DELAYED = true,
    UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_CHANNEL_UPDATE = true,
    UNIT_SPELLCAST_EMPOWER_START = true,
    UNIT_SPELLCAST_EMPOWER_UPDATE = true,
}
local STOP = {
    UNIT_SPELLCAST_STOP = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_EMPOWER_STOP = true,
}
local CASTING = { cast = true, channel = true, empower = true }

---@class EternityUICastBarDefinition
---@field name string global frame name
---@field label string Mover label
---@field point string Mover default point
---@field x number?
---@field y number?
---@field parent table? a Group's container: the bar is placed by the Group, not by the Mover
---@field size string? "layout.<size>Width/Height" options (the unit by default)

---@class EternityUICastBar
---@field unit string
---@field size string
---@field key string Mover key
---@field definition EternityUICastBarDefinition
---@field frame table
---@field info EternityUICastInfo? the cast on screen
---@field state string? nil, "cast", "channel", "empower", "done" (holding or fading) or "preview"
---@field timer boolean? the StatusBar runs on a Duration object
---@field enabled boolean?
---@field previewing boolean? Mover is open
---@field sentTarget any the player's last UNIT_SPELLCAST_SENT target (may be secret)
---@field cfg table options read on every frame, cached by ApplyLayout
local Bar = { ticks = {} }
Bar.__index = Bar
ns.Bar = Bar

local function opt(path)
    return E.store:Get(addonName, path)
end

local function hexColor(hex)
    return Theme.RGBA(hex)
end

-- Frame --------------------------------------------------------------------------------------------

local function newText(parent, justify)
    local text = UI.Text(parent, "", "small", "text")
    text:SetShadowOffset(1, -1)
    text:SetShadowColor(0, 0, 0, 0.9)
    text:SetJustifyH(justify)
    text:SetWordWrap(false)
    return text
end

local function create(self)
    local parent = self.definition.parent
    local frame = CreateFrame("Frame", self.definition.name, parent or UIParent)
    if not parent then
        frame:SetFrameStrata("MEDIUM")
        frame:SetClampedToScreen(true)
    end
    frame:Hide()

    frame.background = UI.Panel(frame, { role = "control", fill = "track", border = "border" })

    -- The StatusBar only measures progress (its texture is invisible): the fill drawn is a rounded
    -- shape anchored to the texture's right edge, so it follows the timer through anchors alone
    -- (no Lua math on a possibly secret duration).
    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:GetStatusBarTexture():SetColorTexture(0, 0, 0, 0)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetFrameLevel(frame.background:GetFrameLevel() + 1)
    frame.bar = bar
    frame.progress = bar:GetStatusBarTexture()

    -- Latency at the bar's end, under the fill.
    frame.latency = CreateFrame("Frame", nil, bar)
    frame.latency:SetFrameLevel(bar:GetFrameLevel() + 1)
    frame.latency.shape = UI.Shape(frame.latency, "control")
    frame.latency:Hide()

    -- Two fills on top of each other: normal and uninterruptible. Only one is visible; with a
    -- secret "not interruptible" SetAlphaFromBoolean picks it.
    local fill = CreateFrame("Frame", nil, bar)
    fill:SetFrameLevel(bar:GetFrameLevel() + 2)
    fill:SetPoint("TOPLEFT")
    fill:SetPoint("BOTTOMRIGHT", frame.progress, "BOTTOMRIGHT")
    for _, key in ipairs({ "normal", "locked" }) do
        local layer = CreateFrame("Frame", nil, fill)
        layer:SetAllPoints()
        layer.shape = UI.Shape(layer, "control")
        fill[key] = layer
    end
    frame.fill = fill

    -- Spark near the fill's edge, shorter than the bar so it stays inside the rounded end.
    local sparkLayer = CreateFrame("Frame", nil, bar)
    sparkLayer:SetFrameLevel(bar:GetFrameLevel() + 3)
    frame.spark = sparkLayer:CreateTexture(nil, "OVERLAY")
    frame.spark:SetColorTexture(1, 1, 1, 0.85)
    frame.spark:SetBlendMode("ADD")
    frame.spark:SetWidth(2)
    frame.spark:SetPoint("CENTER", fill, "RIGHT", -1, 0)

    -- Marks (ticks or stages) and texts above the bar.
    local overlay = CreateFrame("Frame", nil, frame)
    overlay:SetAllPoints(bar)
    overlay:SetFrameLevel(bar:GetFrameLevel() + 4)
    frame.overlay = overlay
    frame.marks = {}
    frame.time = newText(overlay, "RIGHT")
    frame.time:SetPoint("RIGHT", -UI.space.sm, 0)
    frame.name = newText(overlay, "LEFT")
    frame.name:SetPoint("LEFT", UI.space.sm, 0)
    frame.name:SetPoint("RIGHT", frame.time, "LEFT", -UI.space.sm, 0)

    -- Uninterruptible border over the track.
    frame.shield = CreateFrame("Frame", nil, frame)
    frame.shield:SetFrameLevel(overlay:GetFrameLevel() + 1)
    frame.shield.shape = UI.Shape(frame.shield, "control")
    frame.shield:Hide()

    local icon = CreateFrame("Frame", nil, frame)
    icon.shape = UI.Shape(icon, "small")
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetPoint("TOPLEFT", 1, -1)
    icon.texture:SetPoint("BOTTOMRIGHT", -1, 1)
    icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.mask = icon:CreateMaskTexture()
    icon.mask:SetAllPoints(icon.texture)
    icon.mask:SetTexture(Theme.MEDIA .. "rounded.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    frame.icon = icon

    frame:SetScript("OnUpdate", function()
        self:OnUpdate()
    end)
    frame:SetScript("OnEvent", function(_, event, ...)
        self:OnEvent(event, ...)
    end)
    self.frame = frame
end

---@param unit string
---@param definition EternityUICastBarDefinition
---@return EternityUICastBar
function Bar.New(unit, definition)
    local self = setmetatable({
        unit = unit,
        size = definition.size or unit,
        key = addonName .. "." .. unit,
        definition = definition,
        cfg = {},
    }, Bar)
    create(self)
    return self
end

-- Look ---------------------------------------------------------------------------------------------

--- Size, icon, texts and the cached options. The position belongs to the Mover.
function Bar:ApplyLayout()
    local frame = self.frame
    local width, height = opt("layout." .. self.size .. "Width"), opt("layout." .. self.size .. "Height")
    local cfg = self.cfg
    cfg.time = opt("behavior.time")
    cfg.hold = opt("behavior.hold")
    cfg.fade = opt("behavior.fade")
    cfg.spark = opt("look.spark")

    -- A bar inside a Group takes the scale from its container.
    frame:SetScale(self.definition.parent and 1 or opt("layout.scale"))
    frame:SetSize(width, height)

    local side = opt("look.icon")
    local iconSpace = side == "none" and 0 or height + ICON_GAP
    local icon, background = frame.icon, frame.background
    icon:SetShown(side ~= "none")
    icon:SetSize(height, height)
    icon:ClearAllPoints()
    background:ClearAllPoints()
    if side == "right" then
        icon:SetPoint("TOPRIGHT")
        background:SetPoint("TOPLEFT")
        background:SetPoint("BOTTOMRIGHT", -iconSpace, 0)
    else
        icon:SetPoint("TOPLEFT")
        background:SetPoint("TOPLEFT", iconSpace, 0)
        background:SetPoint("BOTTOMRIGHT")
    end
    icon.shape:SetColors("track", "border")
    -- Rounded icon unless the theme's corners are sharp.
    icon.texture:RemoveMaskTexture(icon.mask)
    if Theme.radius ~= 0 then
        icon.texture:AddMaskTexture(icon.mask)
    end
    background.shape:SetAlpha(opt("look.background") and Theme.opacity or 0)
    frame.shield:SetAllPoints(background)
    frame.shield.shape:SetColors(nil, hexColor(opt("colors.locked")))

    -- The fill is a rounded shape too: a small even gap keeps it inside the track.
    local inset = 2
    frame.bar:ClearAllPoints()
    frame.bar:SetPoint("TOPLEFT", background, "TOPLEFT", inset, -inset)
    frame.bar:SetPoint("BOTTOMRIGHT", background, "BOTTOMRIGHT", -inset, inset)
    self.barWidth = math.max(width - iconSpace - inset * 2, 1)
    frame.spark:SetHeight(math.max(2, math.floor((height - inset * 2) * 0.6)))
    frame.spark:SetShown(cfg.spark and CASTING[self.state] or false)

    local font = opt("look.font")
    frame.name:SetStyle(font)
    frame.time:SetStyle(font)

    if CASTING[self.state] then
        self:Recolor()
        self:UpdateMarks()
        self:SetName()
    elseif self.state == "preview" then
        self:ShowPreview()
    end
end

--- Color for a kind of cast ("cast", "channel" or "empower").
function Bar:KindColor(kind)
    if kind == "channel" then
        return hexColor(opt("colors.channel"))
    elseif kind == "empower" then
        return hexColor(opt("colors.empower"))
    end
    return hexColor(opt("colors.cast"))
end

--- Colors one fill layer: flat or a vertical gradient (Timer.Paint).
local function paintLayer(layer, color)
    Timer.Paint(layer.shape, color)
end

--- Paints the fill in one color (the uninterruptible layer goes invisible).
function Bar:Paint(color)
    local fill = self.frame.fill
    paintLayer(fill.normal, color)
    fill.normal:SetAlpha(1)
    fill.locked:SetAlpha(0)
end

--- Fill and border by kind and interruptibility. A secret "not interruptible" goes straight to
--- the widgets that take secret booleans.
function Bar:Recolor()
    local info = self.info
    if not info then
        return
    end
    local normal = self:KindColor(info.kind)
    local locked = hexColor(opt("colors.locked"))
    local flag = info.notInterruptible
    local fill, shield = self.frame.fill, self.frame.shield
    if Cast.IsSecret(flag) then
        self:Paint(normal)
        if fill.normal.SetAlphaFromBoolean then
            paintLayer(fill.locked, locked)
            fill.normal:SetAlphaFromBoolean(flag, 0, 1)
            fill.locked:SetAlphaFromBoolean(flag, 1, 0)
        end
        if opt("look.shield") and shield.SetAlphaFromBoolean then
            shield:Show()
            shield:SetAlphaFromBoolean(flag, 1, 0)
        else
            shield:Hide()
        end
    else
        self:Paint(flag and locked or normal)
        shield:SetAlpha(1)
        shield:SetShown(flag and opt("look.shield") or false)
    end
end

--- Name, plus the spell's target on the player's bar when both are plain strings.
function Bar:SetName()
    local info, text = self.info, ""
    if info and opt("behavior.name") then
        text = info.name
        if self.unit == "player" and opt("player.spellTarget") then
            local name, target = Cast.Plain(info.name), Cast.Plain(self.sentTarget)
            if type(name) == "string" and type(target) == "string" and target ~= "" then
                text = name .. " > " .. target
            end
        end
    end
    self.frame.name:SetText(text)
end

--- Time text. remaining and total may be secret: SetFormattedText takes them as they are.
function Bar:SetTime(remaining, total)
    local text, mode = self.frame.time, self.cfg.time
    if mode == "none" or not remaining then
        text:SetText("")
    elseif mode == "both" and total then
        text:SetFormattedText("%.1f / %.1f", remaining, total)
    else
        text:SetFormattedText("%.1f", remaining)
    end
end

local function mark(frame, index)
    local texture = frame.marks[index]
    if not texture then
        texture = frame.overlay:CreateTexture(nil, "ARTWORK")
        texture:SetWidth(1)
        local r, g, b = Theme.Color("text")
        texture:SetColorTexture(r, g, b, 0.75)
        frame.marks[index] = texture
    end
    return texture
end

--- Channel ticks, empower stages and latency (player bar only; skipped when the data is secret).
function Bar:UpdateMarks()
    local frame, info = self.frame, self.info
    for _, texture in ipairs(frame.marks) do
        texture:Hide()
    end
    frame.latency:Hide()
    if self.unit ~= "player" or not info then
        return
    end
    local width = self.barWidth or frame.bar:GetWidth()

    local positions
    if info.kind == "channel" and opt("player.ticks") then
        local spellID = Cast.Plain(info.spellID)
        local count = spellID and Bar.ticks[spellID]
        if count and count > 1 then
            positions = {}
            for i = 1, count - 1 do
                positions[i] = i / count
            end
        end
    elseif info.kind == "empower" and opt("player.stages") then
        positions = Cast.StageMarks(self.unit)
    end
    for i, fraction in ipairs(positions or {}) do
        local texture = mark(frame, i)
        texture:ClearAllPoints()
        texture:SetPoint("TOP", frame.bar, "TOPLEFT", width * fraction, 0)
        texture:SetPoint("BOTTOM", frame.bar, "BOTTOMLEFT", width * fraction, 0)
        texture:Show()
    end

    if info.kind == "cast" and opt("player.latency") and info.startMs and info.endMs then
        local total = info.endMs - info.startMs
        local fraction = total > 0 and math.min(Cast.Latency() / total, 1) or 0
        if fraction > 0 then
            local latency = frame.latency
            latency:ClearAllPoints()
            latency:SetPoint("TOPRIGHT", frame.bar)
            latency:SetPoint("BOTTOMRIGHT", frame.bar)
            latency:SetWidth(math.max(1, width * fraction))
            latency.shape:SetColors(hexColor(opt("colors.latency")), nil)
            latency:Show()
        end
    end
end

-- Cast states --------------------------------------------------------------------------------------

local function clearTimer(bar)
    if bar.ClearTimerDuration then
        bar:ClearTimerDuration()
    end
end

--- Shows a cast from Cast.Read.
---@param info EternityUICastInfo
function Bar:Start(info)
    if info.tradeskill and not opt("behavior.tradeskill") then
        self:Hide()
        return
    end
    local frame, bar = self.frame, self.frame.bar
    self.info, self.state = info, info.kind
    frame:SetAlpha(1)
    frame.icon.texture:SetTexture(info.icon)

    local timers = Enum and Enum.StatusBarTimerDirection
    if info.duration and bar.SetTimerDuration and timers then
        local direction = info.kind == "channel" and timers.RemainingTime or timers.ElapsedTime
        local immediate = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or 0
        bar:SetTimerDuration(info.duration, immediate, direction)
        self.timer = true
    else
        clearTimer(bar)
        self.timer = false
        local total = info.startMs and info.endMs and info.endMs - info.startMs
        bar:SetMinMaxValues(0, total and total > 0 and total or 1)
        bar:SetValue(total and total > 0 and 0 or 1)
    end

    self:SetName()
    self:Recolor()
    self:UpdateMarks()
    frame.spark:SetShown(self.cfg.spark)
    frame:Show()
    self:OnUpdate()
end

--- Ends the cast on screen: "success" fills it; "failed" keeps it red with a message. Then it
--- holds (failures only) and fades out.
---@param result string "success" or "failed"
---@param message string?
function Bar:Finish(result, message)
    if not CASTING[self.state] then
        return
    end
    local frame, bar = self.frame, self.frame.bar
    clearTimer(bar)
    self.timer = false
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    self:Paint(hexColor(opt(result == "success" and "colors.success" or "colors.failed")))
    frame.shield:Hide()
    frame.spark:Hide()
    frame.latency:Hide()
    for _, texture in ipairs(frame.marks) do
        texture:Hide()
    end
    if message then
        frame.name:SetText(message)
    end
    frame.time:SetText("")
    self.state = "done"
    self.holdUntil = GetTime() + (result == "success" and 0 or self.cfg.hold)
    self:OnUpdate()
end

--- Hides the bar now (or goes back to the preview while Mover is open).
function Bar:Hide()
    clearTimer(self.frame.bar)
    self.info, self.state, self.timer = nil, nil, false
    if self.previewing then
        self:ShowPreview()
    else
        self.frame:Hide()
    end
end

--- Shows the unit's current cast, if any. force: also cut a finished cast's fade (target change).
---@param force boolean?
function Bar:Refresh(force)
    if not self.enabled then
        return
    end
    local info = Cast.Read(self.unit)
    if info then
        self:Start(info)
    elseif force or CASTING[self.state] then
        self:Hide()
    end
end

--- True once a cast's time is over, also if its end event never came or the game still reports
--- it. False while it can't be told, with secret times: then only the events end it.
---@param info EternityUICastInfo
---@return boolean
local function expired(info)
    if info.endMs then
        return GetTime() * 1000 >= info.endMs + EXPIRY_MARGIN
    end
    local duration = info.duration
    if duration and duration.HasExpired and not (duration.HasSecretValues and duration:HasSecretValues()) then
        return duration:HasExpired() == true
    end
    return false
end

function Bar:OnUpdate()
    local frame, info, state = self.frame, self.info, self.state
    if state == "done" then
        local now, hold = GetTime(), self.holdUntil or 0
        if now < hold then
            return
        end
        local fade = self.cfg.fade or 0
        local t = fade > 0 and (now - hold) / fade or 1
        if t >= 1 then
            self:Hide()
        else
            frame:SetAlpha(1 - t)
        end
        return
    end
    if not info or not CASTING[state] then
        return
    end
    if self.timer then
        local duration = frame.bar.GetTimerDuration and frame.bar:GetTimerDuration() or info.duration
        if duration then
            self:SetTime(duration:GetRemainingDuration(), duration:GetTotalDuration())
        end
    elseif info.startMs and info.endMs then
        local total = info.endMs - info.startMs
        local elapsed = math.min(math.max(GetTime() * 1000 - info.startMs, 0), total)
        frame.bar:SetValue(state == "channel" and total - elapsed or elapsed)
        self:SetTime((total - elapsed) / 1000, total / 1000)
    end
    if expired(info) then
        self:Finish("success")
    end
end

function Bar:OnEvent(event, _, ...)
    if event == "UNIT_SPELLCAST_SENT" then
        self.sentTarget = (...)
        return
    end
    if REFRESH[event] then
        self:Refresh()
    elseif STOP[event] then
        -- A new cast may already be running: the stop belongs to the old one.
        local info = Cast.Read(self.unit)
        if info and not expired(info) then
            self:Start(info)
        else
            self:Finish("success")
        end
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        -- Still casting: the failure was another attempt (e.g. a spell pressed mid-cast).
        if Cast.Read(self.unit) then
            return
        end
        local message = event == "UNIT_SPELLCAST_FAILED" and L.FAILED or L.INTERRUPTED
        if event == "UNIT_SPELLCAST_INTERRUPTED" and opt("behavior.interruptedBy") then
            local _, _, interruptedBy = ...
            local by = Cast.NameFromGUID(interruptedBy)
            if by then
                message = L.INTERRUPTED_BY:format(by)
            end
        end
        self:Finish("failed", message)
    elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        if self.info then
            self.info.notInterruptible = event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE"
            self:Recolor()
        end
    end
end

-- Preview and life cycle -------------------------------------------------------------------------

--- A sample cast while Mover is open, so the bar can be seen and moved.
function Bar:ShowPreview()
    local frame, bar = self.frame, self.frame.bar
    self.state = "preview"
    clearTimer(bar)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0.6)
    frame:SetAlpha(1)
    frame.icon.texture:SetTexture(PREVIEW_ICON)
    frame.name:SetText(self.definition.label)
    self:SetTime(1.5, 2.5)
    self:Paint(self:KindColor("cast"))
    frame.shield:Hide()
    frame.latency:Hide()
    frame.spark:SetShown(self.cfg.spark)
    frame:Show()
end

---@param on boolean
function Bar:SetPreview(on)
    self.previewing = on and true or false
    if on and not CASTING[self.state] and self.state ~= "done" then
        self:ShowPreview()
    elseif not on and self.state == "preview" then
        self.state = nil
        self.frame:Hide()
    end
end

function Bar:Enable()
    if self.enabled then
        return
    end
    self.enabled = true
    local frame = self.frame
    for _, event in ipairs(UNIT_EVENTS) do
        -- An event this client doesn't have errors on RegisterUnitEvent: skip it.
        pcall(frame.RegisterUnitEvent, frame, event, self.unit)
    end
    if self.unit == "player" then
        pcall(frame.RegisterUnitEvent, frame, "UNIT_SPELLCAST_SENT", "player")
    end
    self:ApplyLayout()
    local definition = self.definition
    if not definition.parent then
        E.Mover.Register({
            key = self.key,
            owner = addonName,
            label = definition.label,
            frame = frame,
            point = definition.point,
            x = definition.x,
            y = definition.y,
        })
    end
    self:Refresh(true)
end

function Bar:Disable()
    if not self.enabled then
        return
    end
    self.enabled = false
    self.frame:UnregisterAllEvents()
    if not self.definition.parent then
        E.Mover.Unregister(self.key)
    end
    self.previewing = false
    self:Hide()
end
