-- Combo points as a row of pips. Each pip is a StatusBar from i - 1 to i that gets the whole
-- count: it lights when the count reaches it, with no comparison in Lua, so a secret count is
-- drawn as it comes. The lit part is a full rounded pip seen through a frame that clips to the
-- StatusBar's progress, so an unlit pip shows nothing of it.

---@type string, EternityUIResourcesNamespace
local addonName, ns = ...
local E = EternityUI
local Secret, UI = E.Secret, ns.UI

local MAX_PIPS = 10

---@class EternityUIResourcesPips
local Pips = { MAX = MAX_PIPS }
ns.Pips = Pips

local function opt(path)
    return E.store:Get(addonName, path)
end

local function newPip(parent, index)
    local pip = CreateFrame("Frame", nil, parent)
    pip.background = UI.Track(pip)

    local bar = CreateFrame("StatusBar", nil, pip)
    bar:SetAllPoints()
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:GetStatusBarTexture():SetColorTexture(0, 0, 0, 0)
    bar:SetMinMaxValues(index - 1, index)
    bar:SetValue(0)
    bar:SetFrameLevel(pip.background:GetFrameLevel() + 1)
    pip.bar = bar

    local clip = CreateFrame("Frame", nil, bar)
    clip:SetPoint("TOPLEFT")
    clip:SetPoint("BOTTOMRIGHT", bar:GetStatusBarTexture(), "BOTTOMRIGHT")
    clip:SetClipsChildren(true)
    clip:SetFrameLevel(bar:GetFrameLevel() + 1)

    local lit = CreateFrame("Frame", nil, clip)
    lit:SetAllPoints(pip)
    lit.shape = UI.Shape(lit)
    pip.lit = lit
    return pip
end

--- A new row of hidden pips.
---@param parent table
---@return table frame
function Pips.Create(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame.pips = {}
    for i = 1, MAX_PIPS do
        frame.pips[i] = newPip(frame, i)
        frame.pips[i]:Hide()
    end
    frame.count = 0
    return frame
end

--- Lays out count pips across width.
---@param frame table
---@param width number
---@param height number
---@param count number
function Pips.Layout(frame, width, height, count)
    count = math.max(1, math.min(count, MAX_PIPS))
    frame.count = count
    frame:SetSize(width, height)
    local gap = opt("layout.pipSpacing")
    local size = math.max(1, (width - gap * (count - 1)) / count)
    for i, pip in ipairs(frame.pips) do
        pip:ClearAllPoints()
        if i <= count then
            pip:SetSize(size, height)
            pip:SetPoint("LEFT", (i - 1) * (size + gap), 0)
            pip.background:Paint()
            pip:Show()
        else
            pip:Hide()
        end
    end
    if frame.colors then
        Pips.Paint(frame, frame.colors[1], frame.colors[2])
    end
end

--- Colors of the lit pips: color, or full once every pip is lit (only when the count is plain).
---@param frame table
---@param color table { r, g, b, a }
---@param full table { r, g, b, a }
function Pips.Paint(frame, color, full)
    frame.colors = { color, full }
    local style = opt("look.texture")
    local points = frame.points
    local maxed = points ~= nil and not Secret.Is(points) and points >= frame.count
    for _, pip in ipairs(frame.pips) do
        UI.Paint(pip.lit.shape, maxed and full or color, style)
    end
    frame.maxed = maxed
end

--- Shows a count of points; it may be secret.
---@param frame table
---@param points any
function Pips.SetPoints(frame, points)
    frame.points = points
    for _, pip in ipairs(frame.pips) do
        pip.bar:SetValue(points)
    end
    -- Repaint only when the "all lit" state changes.
    local maxed = not Secret.Is(points) and points >= frame.count
    if frame.colors and maxed ~= frame.maxed then
        Pips.Paint(frame, frame.colors[1], frame.colors[2])
    end
end
