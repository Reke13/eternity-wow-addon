-- A plain themed timer bar for the GCD, swing and mirror timers: a track, a rounded fill that
-- follows a StatusBar through anchors (no Lua math on a possibly secret duration), a spark and two
-- texts. It runs on a Duration object (StatusBar:SetTimerDuration, secret-safe) or, without one,
-- on plain start and total times. Bar.lua paints its fills with Timer.Paint too.

---@type string, EternityUICastBarsNamespace
local addonName, ns = ...
local E = EternityUI
local Theme, UI = E.Theme, ns.UI

---@class EternityUICastBarsTimer
local Timer = {}
ns.Timer = Timer

local function opt(path)
    return E.store:Get(addonName, path)
end

local function rgba(color)
    return color[1], color[2], color[3], color[4] or 1
end

--- Colors a rounded shape flat or with a vertical gradient ("theme" follows the glass setting).
---@param shape table Skin.Shape
---@param color table { r, g, b, a }
function Timer.Paint(shape, color)
    local style = opt("look.texture")
    local r, g, b, a = rgba(color)
    if style == "gradient" or (style == "theme" and Theme.surface == "glass") then
        local light = function(c)
            return math.min(1, c * 1.15 + 0.1)
        end
        shape:SetColors({ r * 0.65, g * 0.65, b * 0.65, a }, nil, { light(r), light(g), light(b), a })
    else
        shape:SetColors({ r, g, b, a }, nil)
    end
end

local function newText(parent, justify)
    local text = UI.Text(parent, "", "small", "text")
    text:SetShadowOffset(1, -1)
    text:SetShadowColor(0, 0, 0, 0.9)
    text:SetJustifyH(justify)
    text:SetWordWrap(false)
    return text
end

local function clearTimer(bar)
    if bar.ClearTimerDuration then
        bar:ClearTimerDuration()
    end
end

--- True once a running timer has reached its end (false while it can't be told: secret times).
---@param frame table
function Timer.Expired(frame)
    if frame.timer then
        local duration = frame.duration
        if duration.HasSecretValues and duration:HasSecretValues() then
            return false
        end
        return duration.HasExpired and duration:HasExpired() == true or false
    elseif frame.total then
        return GetTime() - frame.start >= frame.total
    end
    return false
end

local function update(frame)
    if frame.timer then
        if frame.showTime then
            frame.time:SetFormattedText("%.1f", frame.duration:GetRemainingDuration())
        end
    elseif frame.total then
        local total = frame.total
        local elapsed = math.min(math.max(GetTime() - frame.start, 0), total)
        frame.bar:SetValue(frame.drain and total - elapsed or elapsed)
        if frame.showTime then
            frame.time:SetFormattedText("%.1f", total - elapsed)
        end
    else
        return
    end
    if frame.onDone and Timer.Expired(frame) then
        frame.onDone(frame)
    end
end

--- A new hidden timer bar. Set frame.showTime, frame.onDone(frame) or frame.onUpdate(frame,
--- elapsed) (replaces the built-in update) as needed.
---@param parent table
---@param name string?
---@return table frame
function Timer.Create(parent, name)
    local frame = CreateFrame("Frame", name, parent)
    frame:Hide()

    frame.background = UI.Panel(frame, { role = "control", fill = "track", border = "border" })
    frame.background:ClearAllPoints()
    frame.background:SetAllPoints()

    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:GetStatusBarTexture():SetColorTexture(0, 0, 0, 0)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetFrameLevel(frame.background:GetFrameLevel() + 1)
    frame.bar = bar
    frame.progress = bar:GetStatusBarTexture()

    local fill = CreateFrame("Frame", nil, bar)
    fill:SetFrameLevel(bar:GetFrameLevel() + 1)
    fill:SetPoint("TOPLEFT")
    fill:SetPoint("BOTTOMRIGHT", frame.progress, "BOTTOMRIGHT")
    fill.shape = UI.Shape(fill, "control")
    frame.fill = fill

    local sparkLayer = CreateFrame("Frame", nil, bar)
    sparkLayer:SetFrameLevel(bar:GetFrameLevel() + 2)
    frame.spark = sparkLayer:CreateTexture(nil, "OVERLAY")
    frame.spark:SetColorTexture(1, 1, 1, 0.85)
    frame.spark:SetBlendMode("ADD")
    frame.spark:SetWidth(2)
    frame.spark:SetPoint("CENTER", fill, "RIGHT", -1, 0)

    local overlay = CreateFrame("Frame", nil, frame)
    overlay:SetAllPoints(bar)
    overlay:SetFrameLevel(bar:GetFrameLevel() + 3)
    frame.time = newText(overlay, "RIGHT")
    frame.time:SetPoint("RIGHT", -UI.space.sm, 0)
    frame.label = newText(overlay, "LEFT")
    frame.label:SetPoint("LEFT", UI.space.sm, 0)
    frame.label:SetPoint("RIGHT", frame.time, "LEFT", -UI.space.sm, 0)

    frame:SetScript("OnUpdate", function(self, elapsed)
        (self.onUpdate or update)(self, elapsed)
    end)
    return frame
end

--- Size, fill color, spark, texts and background from the options.
---@param frame table
---@param width number? nil when anchors give the width
---@param height number
---@param color table { r, g, b, a }
function Timer.Layout(frame, width, height, color)
    if width then
        frame:SetSize(width, height)
    else
        frame:SetHeight(height)
    end
    local inset = height >= 10 and 2 or 1
    frame.bar:ClearAllPoints()
    frame.bar:SetPoint("TOPLEFT", inset, -inset)
    frame.bar:SetPoint("BOTTOMRIGHT", -inset, inset)
    frame.background.shape:SetAlpha(opt("look.background") and Theme.opacity or 0)
    frame.color = color
    Timer.Paint(frame.fill.shape, color)
    frame.spark:SetHeight(math.max(2, math.floor((height - inset * 2) * 0.6)))
    frame.spark:SetShown(opt("look.spark") and true or false)
    -- Texts only where they fit.
    local font = opt("look.font")
    frame.label:SetStyle(font)
    frame.time:SetStyle(font)
    local texts = height >= 10
    frame.label:SetShown(texts)
    frame.time:SetShown(texts)
end

--- Runs the bar on a Duration object (fills, or drains with drain = true).
---@param frame table
---@param duration table
---@param drain boolean?
---@return boolean ok false when the client has no SetTimerDuration
function Timer.Run(frame, duration, drain)
    local bar = frame.bar
    local timers = Enum and Enum.StatusBarTimerDirection
    if not (duration and bar.SetTimerDuration and timers) then
        return false
    end
    local immediate = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or 0
    bar:SetTimerDuration(duration, immediate, drain and timers.RemainingTime or timers.ElapsedTime)
    frame.timer, frame.duration, frame.total, frame.drain = true, duration, nil, drain
    frame:Show()
    return true
end

--- Runs the bar on plain times (seconds, GetTime() clock).
---@param frame table
---@param start number
---@param total number
---@param drain boolean?
function Timer.RunPlain(frame, start, total, drain)
    clearTimer(frame.bar)
    frame.timer, frame.duration = false, nil
    frame.start, frame.total, frame.drain = start, math.max(total, 0.001), drain
    frame.bar:SetMinMaxValues(0, frame.total)
    frame:Show()
    update(frame)
end

--- Draws a fixed fraction (previews, a full bar) and stops any timer.
---@param frame table
---@param fraction number 0-1
function Timer.SetStatic(frame, fraction)
    clearTimer(frame.bar)
    frame.timer, frame.duration, frame.total = false, nil, nil
    frame.bar:SetMinMaxValues(0, 1)
    frame.bar:SetValue(fraction)
end

--- Stops the timer and hides the bar.
---@param frame table
function Timer.Stop(frame)
    Timer.SetStatic(frame, 0)
    frame:Hide()
end
