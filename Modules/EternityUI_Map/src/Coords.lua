-- Coordinates: the player's and the cursor's on the map (a small bar over the map) and,
-- optionally, the player's on screen with the map closed (an Eternity Edit Mode element).
--
-- Safe reads only: C_Map.GetPlayerMapPosition is nil in instances and while loading, the map can
-- show a map the player isn't on, and any value that comes back secret is dropped (a dash is
-- shown). The cursor's position is clamped to 0..1 by Blizzard, so it's only read while the
-- cursor is over the map's scroll container. Blizzard's own coordinates panel (CVars
-- worldMapShowPlayerCoords / worldMapShowCursorCoords) goes to alpha 0 while ours is on.

---@type string, EternityUIMapNamespace
local addonName, ns = ...
local E = EternityUI
local W = ns.Ui.W
local Core, L = ns.Core, ns.L
local opt = Core.Opt

local EDIT_KEY = "EternityUIMap.coords"
local INTERVAL = 0.1
local SCREEN_INTERVAL = 0.2

---@class EternityUIMapCoords
---@field bar table? the bar over the map
---@field screen table? the on-screen label (EternityUIMapScreenCoords)
---@field registered boolean? the on-screen label is an Edit Mode element
---@field stash EternityUIMapStash Blizzard's coordinates panel
---@field editing boolean? Eternity's Edit Mode is open
local Coords = { stash = Core.NewStash() }
ns.Coords = Coords

-- Reading positions -----------------------------------------------------------------------------

local function plainNumber(value)
    return type(value) == "number" and not Core.Secret(value) and value == value
end

--- The unit's x, y (0..1) on the map, or nil.
function Coords.UnitPosition(mapID, unit)
    if not (mapID and C_Map and C_Map.GetPlayerMapPosition) then
        return nil
    end
    local ok, position = pcall(C_Map.GetPlayerMapPosition, mapID, unit or "player")
    if not ok or position == nil or Core.Secret(position) then
        return nil
    end
    local okXY, x, y = pcall(position.GetXY, position)
    if not (okXY and plainNumber(x) and plainNumber(y)) then
        return nil
    end
    if x == 0 and y == 0 then
        return nil
    end
    return x, y
end

--- The map the player is on (nil while loading).
function Coords.PlayerMap()
    if not (C_Map and C_Map.GetBestMapForUnit) then
        return nil
    end
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if ok and plainNumber(mapID) then
        return mapID
    end
    return nil
end

local function mapName(mapID)
    local ok, info = pcall(C_Map.GetMapInfo, mapID)
    if ok and type(info) == "table" and type(info.name) == "string" and not Core.Secret(info.name) then
        return info.name
    end
    return nil
end

--- The player's position for the map shown: x, y and, when it's on another map (the shown one
--- doesn't contain the player), that map's name.
function Coords.Player(mapID)
    local x, y = Coords.UnitPosition(mapID)
    if x then
        return x, y
    end
    local best = Coords.PlayerMap()
    if best and best ~= mapID then
        x, y = Coords.UnitPosition(best)
        if x then
            return x, y, mapName(best)
        end
    end
    return nil
end

--- The cursor's x, y (0..1) on the map, or nil when it's not over it.
function Coords.Cursor(map)
    local container = map and map.ScrollContainer
    if not (container and container.GetNormalizedCursorPosition and container:IsMouseOver()) then
        return nil
    end
    local ok, x, y = pcall(container.GetNormalizedCursorPosition, container)
    if not (ok and plainNumber(x) and plainNumber(y)) then
        return nil
    end
    if x < 0 or x > 1 or y < 0 or y > 1 then
        return nil
    end
    return x, y
end

--- "45.2, 63.1" with the decimals of the options (a dash without a position).
function Coords.Format(x, y, decimals)
    if not x then
        return L.NO_POSITION
    end
    local pattern = ("%%.%df, %%.%df"):format(decimals, decimals)
    return pattern:format(x * 100, y * 100)
end

-- The bar over the map --------------------------------------------------------------------------

local function decimals()
    return math.floor(tonumber(opt("coords.decimals")) or 1)
end

function Coords:CreateBar(map)
    if self.bar then
        return self.bar
    end
    -- Inside BorderFrame (HIGH strata): over the map's pins, like Blizzard's overlay frames.
    local bar = CreateFrame("Frame", nil, map.BorderFrame or map)
    bar:SetSize(10, 22)
    bar:EnableMouse(false)
    bar.background = W.Panel(bar, { role = "control", fill = "window", border = "border" })
    bar.background:SetAllPoints()
    bar.background:SetFrameLevel(bar:GetFrameLevel())
    bar.player = W.Text(bar, "", "small")
    bar.cursor = W.Text(bar, "", "small")
    bar.player:SetPoint("LEFT", bar, "LEFT", 10, 0)
    bar.cursor:SetPoint("LEFT", bar.player, "RIGHT", 14, 0)
    bar.elapsed = 0
    bar:SetScript("OnUpdate", function(frame, elapsed)
        frame.elapsed = frame.elapsed + elapsed
        if frame.elapsed >= INTERVAL then
            frame.elapsed = 0
            self:UpdateBar()
        end
    end)
    bar:Hide()
    self.bar = bar
    return bar
end

function Coords:LayoutBar()
    local map, bar = Core.Map(), self.bar
    if not (map and bar) then
        return
    end
    local anchor = map.ScrollContainer or map
    bar:ClearAllPoints()
    local place = opt("coords.position")
    if place == "top" then
        bar:SetPoint("TOP", anchor, "TOP", 0, -6)
    elseif place == "bottomleft" then
        bar:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 8, 6)
    else
        bar:SetPoint("BOTTOM", anchor, "BOTTOM", 0, 6)
    end
    local font = opt("look.font")
    bar.player:SetStyle(font, opt("colors.player"))
    bar.cursor:SetStyle(font, opt("colors.cursor"))
    bar.background:SetShown(opt("look.coordsBackground") == true)
    bar.player:SetShown(opt("coords.player") == true)
    bar.cursor:SetShown(opt("coords.cursor") == true)
    bar.cursor:ClearAllPoints()
    if bar.player:IsShown() then
        bar.cursor:SetPoint("LEFT", bar.player, "RIGHT", 14, 0)
    else
        bar.cursor:SetPoint("LEFT", bar, "LEFT", 10, 0)
    end
    bar:SetHeight(font == "body" and 26 or 22)
end

function Coords:UpdateBar()
    local map, bar = Core.Map(), self.bar
    if not (map and bar) then
        return
    end
    local places = decimals()
    local width = 20
    if bar.player:IsShown() then
        local x, y, other = Coords.Player(map.GetMapID and map:GetMapID() or nil)
        local text = L.PLAYER .. "  " .. Coords.Format(x, y, places)
        if other then
            text = text .. " (" .. other .. ")"
        end
        bar.player:SetText(text)
        width = width + bar.player:GetStringWidth()
    end
    if bar.cursor:IsShown() then
        local x, y = Coords.Cursor(map)
        bar.cursor:SetText(L.CURSOR .. "  " .. Coords.Format(x, y, places))
        width = width + bar.cursor:GetStringWidth() + (bar.player:IsShown() and 14 or 0)
    end
    bar:SetWidth(math.max(40, width))
end

--- Blizzard's own coordinates panel: an overlay frame the map doesn't keep a key for.
function Coords.BlizzardPanel(map)
    for _, frame in ipairs(map.overlayFrames or {}) do
        if frame.PlayerCoords and frame.CursorCoords then
            return frame
        end
    end
    return nil
end

-- On screen -------------------------------------------------------------------------------------

function Coords:CreateScreen()
    if self.screen then
        return self.screen
    end
    local frame = CreateFrame("Frame", "EternityUIMapScreenCoords", UIParent)
    frame:SetSize(90, 22)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -60)
    frame:SetFrameStrata("LOW")
    frame.background = W.Panel(frame, { role = "control", fill = "window", border = "border" })
    frame.background:SetAllPoints()
    frame.text = W.Text(frame, "", "small")
    frame.text:SetPoint("CENTER")
    frame.elapsed = SCREEN_INTERVAL
    frame:SetScript("OnUpdate", function(f, elapsed)
        f.elapsed = f.elapsed + elapsed
        if f.elapsed >= SCREEN_INTERVAL then
            f.elapsed = 0
            self:UpdateScreen()
        end
    end)
    frame:Hide()
    self.screen = frame
    return frame
end

function Coords:UpdateScreen()
    local frame = self.screen
    if not frame then
        return
    end
    local x, y = Coords.UnitPosition(Coords.PlayerMap())
    frame.text:SetText(Coords.Format(x, y, decimals()))
    frame:SetWidth(math.max(60, frame.text:GetStringWidth() + 20))
end

function Coords:ApplyScreen()
    local want = Core.running == true and opt("coords.screen") == true
    if want then
        local frame = self:CreateScreen()
        if not self.registered then
            self.registered = true
            E.Mover.Register({
                key = EDIT_KEY,
                owner = addonName,
                label = L.SCREEN_COORDS,
                frame = frame,
                point = "TOP",
                x = 0,
                y = -60,
            })
        end
        frame.text:SetStyle(opt("look.font"), opt("colors.player"))
        frame.background:SetShown(opt("look.coordsBackground") == true)
        frame:Show()
        self:UpdateScreen()
    else
        if self.registered then
            self.registered = false
            E.Mover.Unregister(EDIT_KEY)
        end
        if self.screen then
            self.screen:Hide()
        end
    end
end

-- Life cycle ------------------------------------------------------------------------------------

--- Shows or hides the bar and Blizzard's panel from the options. Safe to call again.
function Coords:Apply()
    local map = Core.Map()
    self:ApplyScreen()
    if not map then
        return
    end
    local want = Core.running == true and opt("coords.enabled") == true
    if want then
        self:CreateBar(map)
        self:LayoutBar()
        self.bar:Show()
        self:UpdateBar()
    elseif self.bar then
        self.bar:Hide()
    end
    local hideBlizzard = want and opt("coords.blizzard") == true
    if hideBlizzard then
        self.stash:Hide(Coords.BlizzardPanel(map))
    else
        self.stash:RestoreAll()
    end
end
