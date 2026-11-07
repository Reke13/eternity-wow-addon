-- One swing bar: a track, a rounded fill that follows a StatusBar through anchors (no Lua math on
-- a possibly secret duration), a spark, two texts and an optional weapon icon. It runs on a
-- Duration object (StatusBar:SetTimerDuration, secret-safe) or, without one, on plain times.

---@type string, EternityUISwingTimerNamespace
local addonName, ns = ...
local E = EternityUI
local Theme, UI = E.Theme, ns.UI

local ICON_GAP = 2
-- Below this height texts don't fit.
local TEXT_HEIGHT = 10

---@class EternityUISwingTimerBar
local Bar = {}
ns.Bar = Bar

local function opt(path)
    return E.store:Get(addonName, path)
end

local function newText(parent, justify)
    local text = UI.Text(parent)
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
    end
end

--- Colors the fill flat or with a vertical gradient ("theme" follows the glass setting).
---@param frame table
---@param color table { r, g, b, a }
function Bar.Paint(frame, color)
    local shape = frame.fill.shape
    local style = opt("look.texture")
    local r, g, b, a = color[1], color[2], color[3], color[4] or 1
    if style == "gradient" or (style == "theme" and Theme.surface == "glass") then
        local function light(c)
            return math.min(1, c * 1.15 + 0.1)
        end
        shape:SetColors({ r * 0.65, g * 0.65, b * 0.65, a }, nil, { light(r), light(g), light(b), a })
    else
        shape:SetColors({ r, g, b, a }, nil)
    end
end

--- A new hidden bar.
---@param parent table
---@return table frame
function Bar.Create(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:Hide()

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetPoint("LEFT")
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    frame.track = CreateFrame("Frame", nil, frame)
    frame.background = UI.Track(frame.track)

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
    fill.shape = UI.Shape(fill)
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
    frame.time:SetPoint("RIGHT", -UI.space, 0)
    frame.label = newText(overlay, "LEFT")
    frame.label:SetPoint("LEFT", UI.space, 0)
    frame.label:SetPoint("RIGHT", frame.time, "LEFT", -UI.space, 0)

    frame:SetScript("OnUpdate", update)
    return frame
end

--- Size, fill color, spark, texts, icon and background from the options.
---@param frame table
---@param width number
---@param height number
---@param color table { r, g, b, a }
function Bar.Layout(frame, width, height, color)
    frame:SetSize(width, height)
    local icon = opt("look.icon") and true or false
    frame.icon:SetShown(icon)
    frame.icon:SetSize(height, height)
    local left = icon and height + ICON_GAP or 0

    frame.track:ClearAllPoints()
    frame.track:SetPoint("TOPLEFT", left, 0)
    frame.track:SetPoint("BOTTOMRIGHT")
    frame.background.shape:SetAlpha(opt("look.background") and Theme.opacity or 0)

    local inset = height >= TEXT_HEIGHT and 2 or 1
    frame.bar:ClearAllPoints()
    frame.bar:SetPoint("TOPLEFT", left + inset, -inset)
    frame.bar:SetPoint("BOTTOMRIGHT", -inset, inset)
    Bar.Paint(frame, color)
    frame.spark:SetHeight(math.max(2, math.floor((height - inset * 2) * 0.6)))
    frame.spark:SetShown(opt("look.spark") and true or false)

    local font = opt("look.font")
    frame.label:SetStyle(font)
    frame.time:SetStyle(font)
    local texts = height >= TEXT_HEIGHT
    frame.label:SetShown(texts)
    frame.time:SetShown(texts)
    frame.showTime = texts and opt("look.time") and true or false
    if not frame.showTime then
        frame.time:SetText("")
    end
end

--- Runs the bar on a Duration object.
---@param frame table
---@param duration table
---@param drain boolean?
---@return boolean ok false when the client has no SetTimerDuration
function Bar.Run(frame, duration, drain)
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
function Bar.RunPlain(frame, start, total, drain)
    clearTimer(frame.bar)
    frame.timer, frame.duration = false, nil
    frame.start, frame.total, frame.drain = start, math.max(total, 0.001), drain
    frame.bar:SetMinMaxValues(0, frame.total)
    frame:Show()
    update(frame)
end

--- Draws a fixed fraction (previews, an idle bar) and stops any timer.
---@param frame table
---@param fraction number 0-1
function Bar.SetStatic(frame, fraction)
    clearTimer(frame.bar)
    frame.timer, frame.duration, frame.total = false, nil, nil
    frame.bar:SetMinMaxValues(0, 1)
    frame.bar:SetValue(fraction)
    frame.time:SetText("")
end

--- Stops the timer and hides the bar.
---@param frame table
function Bar.Stop(frame)
    Bar.SetStatic(frame, 0)
    frame:Hide()
end
