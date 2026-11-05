-- Mirror timers (breath, fatigue, feign death) as one Mover element of up to three bars.
-- MIRROR_TIMER_START/STOP/PAUSE and GetMirrorTimerInfo/Progress aren't secret on Forever (no
-- SecretReturns in its API docs), so the bars run on plain math like Blizzard's MirrorTimer:
-- milliseconds, a scale (negative drains) and a pause. Blizzard.lua hides MirrorTimerContainer.

---@type string, EternityUICastBarsNamespace
local addonName, ns = ...
local E = EternityUI
local Theme = E.Theme
local Cast, Timer, L = ns.Cast, ns.Timer, ns.L

local COUNT = 3
local GAP = 3
-- Color option and preview label per timer name.
local KINDS = {
    BREATH = { color = "colors.breath", label = "BREATH" },
    EXHAUSTION = { color = "colors.fatigue", label = "FATIGUE" },
    FEIGNDEATH = { color = "colors.feign", label = "FEIGN" },
}
local OTHER = { color = "colors.feign" }
local PREVIEW = {
    { name = "BREATH", value = 0.7 },
    { name = "EXHAUSTION", value = 0.4 },
}

local EVENTS = { "MIRROR_TIMER_START", "MIRROR_TIMER_STOP", "MIRROR_TIMER_PAUSE" }

---@class EternityUICastBarsMirror
---@field frame table container
---@field rows table[] Timer bars (fixed slots)
---@field enabled boolean?
---@field previewing boolean?
local Mirror = { KINDS = KINDS }
Mirror.__index = Mirror
ns.Mirror = Mirror

local function opt(path)
    return E.store:Get(addonName, path)
end

local function kind(name)
    return KINDS[name] or OTHER
end

local function isPaused(paused)
    paused = Cast.Plain(paused)
    return paused == true or (type(paused) == "number" and paused > 0)
end

--- Moves a running row's value: the game's progress when it gives one, else value + scale * dt.
local function update(row, elapsed)
    if not row.timerName then
        return
    end
    if not row.paused then
        local progress
        if GetMirrorTimerProgress then
            local ok, value = pcall(GetMirrorTimerProgress, row.timerName)
            progress = ok and Cast.Plain(value) or nil
        end
        if type(progress) == "number" then
            row.value = progress / 1000
        else
            row.value = row.value + row.scale * (elapsed or 0)
        end
        row.value = math.min(math.max(row.value, 0), row.max)
    end
    row.bar:SetValue(row.value)
    row.time:SetFormattedText("%d", math.ceil(row.value))
end

---@return EternityUICastBarsMirror
function Mirror.New()
    local self = setmetatable({ key = addonName .. ".mirror", rows = {} }, Mirror)
    local frame = CreateFrame("Frame", "EternityUICastBarMirror", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:Hide()
    for i = 1, COUNT do
        local row = Timer.Create(frame)
        row.onUpdate = update
        self.rows[i] = row
    end
    frame:SetScript("OnEvent", function(_, event, ...)
        self:OnEvent(event, ...)
    end)
    self.frame = frame
    return self
end

function Mirror:ApplyLayout()
    local frame = self.frame
    local width, height = opt("layout.mirrorWidth"), opt("layout.mirrorHeight")
    frame:SetScale(opt("layout.scale"))
    frame:SetSize(width, COUNT * (height + GAP) - GAP)
    for i, row in ipairs(self.rows) do
        Timer.Layout(row, width, height, Theme.RGBA(opt(kind(row.timerName or row.previewName).color)))
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(i - 1) * (height + GAP))
    end
end

local function rowFor(self, name)
    for _, row in ipairs(self.rows) do
        if row.timerName == name then
            return row
        end
    end
    for _, row in ipairs(self.rows) do
        if not row.timerName then
            return row
        end
    end
    return nil
end

--- A timer started (or was found running): value and max in milliseconds.
function Mirror:Start(name, value, maxValue, scale, paused, label)
    name = Cast.Plain(name)
    value, maxValue, scale = Cast.Plain(value), Cast.Plain(maxValue), Cast.Plain(scale)
    if type(name) ~= "string" or type(value) ~= "number" or type(maxValue) ~= "number" or maxValue <= 0 then
        return
    end
    local row = rowFor(self, name)
    if not row then
        return
    end
    row.timerName, row.previewName = name, nil
    row.value, row.max = value / 1000, maxValue / 1000
    row.scale = type(scale) == "number" and scale or -1
    row.paused = isPaused(paused)
    Timer.SetStatic(row, 0)
    row.bar:SetMinMaxValues(0, row.max)
    Timer.Paint(row.fill.shape, Theme.RGBA(opt(kind(name).color)))
    local text = Cast.Plain(label)
    row.label:SetText(type(text) == "string" and text ~= "" and text or (KINDS[name] and L[KINDS[name].label]) or "")
    row:Show()
    update(row, 0)
end

--- A timer ended: its row is freed (the preview comes back while Mover is open).
function Mirror:Stop(name)
    for _, row in ipairs(self.rows) do
        if row.timerName == name then
            row.timerName = nil
            Timer.Stop(row)
        end
    end
    if self.previewing then
        self:ShowPreview()
    end
end

function Mirror:OnEvent(event, ...)
    if event == "MIRROR_TIMER_START" then
        self:Start(...)
    elseif event == "MIRROR_TIMER_STOP" then
        self:Stop(Cast.Plain((...)))
    elseif event == "MIRROR_TIMER_PAUSE" then
        local name, paused = ...
        name = Cast.Plain(name)
        for _, row in ipairs(self.rows) do
            if row.timerName == name then
                row.paused = isPaused(paused)
            end
        end
    end
end

--- Picks up timers already running (enabled underwater, after /reload).
function Mirror:Scan()
    if not GetMirrorTimerInfo then
        return
    end
    for i = 1, COUNT do
        local ok, name, value, maxValue, scale, paused, label = pcall(GetMirrorTimerInfo, i)
        name = ok and Cast.Plain(name) or nil
        if type(name) == "string" and name ~= "UNKNOWN" then
            self:Start(name, value, maxValue, scale, paused, label)
        end
    end
end

--- Sample timers in the free rows while Mover is open.
function Mirror:ShowPreview()
    local index = 0
    for _, row in ipairs(self.rows) do
        if not row.timerName then
            index = index + 1
            local sample = PREVIEW[index]
            if sample then
                row.previewName = sample.name
                Timer.SetStatic(row, sample.value)
                Timer.Paint(row.fill.shape, Theme.RGBA(opt(KINDS[sample.name].color)))
                row.label:SetText(L[KINDS[sample.name].label])
                row.time:SetText("")
                row:Show()
            else
                row.previewName = nil
                Timer.Stop(row)
            end
        end
    end
end

---@param on boolean
function Mirror:SetPreview(on)
    self.previewing = on and true or false
    if self.previewing then
        self:ShowPreview()
    else
        for _, row in ipairs(self.rows) do
            if not row.timerName then
                row.previewName = nil
                Timer.Stop(row)
            end
        end
    end
end

function Mirror:Enable()
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
        label = L.MIRROR,
        frame = frame,
        point = "TOP",
        x = 0,
        y = -120,
    })
    self:Scan()
end

function Mirror:Disable()
    if not self.enabled then
        return
    end
    self.enabled = false
    self.previewing = false
    self.frame:UnregisterAllEvents()
    for _, row in ipairs(self.rows) do
        row.timerName, row.previewName = nil, nil
        Timer.Stop(row)
    end
    E.Mover.Unregister(self.key)
    self.frame:Hide()
end
