-- One resource bar: a track, a rounded fill that follows a StatusBar through anchors (no Lua math
-- on a possibly secret value), a spark and a text. Its values go straight to the StatusBar.

---@type string, EternityUIResourcesNamespace
local addonName, ns = ...
local E = EternityUI
local Theme, UI = E.Theme, ns.UI

-- Below this height the text doesn't fit.
local TEXT_HEIGHT = 10
local JUSTIFY = { left = "LEFT", center = "CENTER", right = "RIGHT" }

---@class EternityUIResourcesBar
local Bar = {}
ns.Bar = Bar

local function opt(path)
    return E.store:Get(addonName, path)
end

--- A new bar.
---@param parent table
---@return table frame
function Bar.Create(parent)
    local frame = CreateFrame("Frame", nil, parent)

    frame.track = CreateFrame("Frame", nil, frame)
    frame.track:SetAllPoints()
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
    frame.text = UI.Text(overlay)
    return frame
end

--- Paints the fill with a color.
---@param frame table
---@param color table { r, g, b, a }
function Bar.Paint(frame, color)
    frame.color = color
    UI.Paint(frame.fill.shape, color, opt("look.texture"))
end

--- Size, spark, background and text from the options.
---@param frame table
---@param width number
---@param height number
function Bar.Layout(frame, width, height)
    frame:SetSize(width, height)
    frame.background.shape:SetAlpha(opt("look.background") and Theme.opacity or 0)

    local inset = height >= TEXT_HEIGHT and 2 or 1
    frame.bar:ClearAllPoints()
    frame.bar:SetPoint("TOPLEFT", inset, -inset)
    frame.bar:SetPoint("BOTTOMRIGHT", -inset, inset)
    frame.spark:SetHeight(math.max(2, math.floor((height - inset * 2) * 0.6)))
    frame.spark:SetShown(opt("look.spark") and true or false)

    local text, align = frame.text, opt("look.align")
    text:SetStyle(opt("look.font"))
    text:ClearAllPoints()
    text:SetPoint(JUSTIFY[align] or "CENTER", align == "left" and UI.space or align == "right" and -UI.space or 0, 0)
    text:SetJustifyH(JUSTIFY[align] or "CENTER")
    frame.showText = height >= TEXT_HEIGHT
    text:SetShown(frame.showText)
    if frame.color then
        Bar.Paint(frame, frame.color)
    end
end

--- Shows a value out of a maximum; both may be secret.
---@param frame table
---@param current any
---@param max any
function Bar.SetValues(frame, current, max)
    frame.bar:SetMinMaxValues(0, max)
    frame.bar:SetValue(current)
end
