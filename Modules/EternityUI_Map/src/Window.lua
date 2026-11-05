-- The map's window: scale and a remembered position for the windowed map, and the maximized
-- map's black backdrop (its opacity, and letting clicks through to the world).
--
-- The map is a UIPanel: Blizzard places it with UpdateUIPanelPositions on every open, minimize
-- and quest log toggle. We never call that, never touch UIPanelWindows or the panel's
-- attributes (that would taint the panel manager) and never use StartMoving: a post-hook on
-- UpdateUIPanelPositions remembers Blizzard's spot ("home") and then puts the map where it was
-- dragged, with our scale. The map has no secure frames, so this is allowed in combat (seen in
-- NaowhForever's MapSize, to be checked in Forever: E161). The maximized map always keeps scale
-- 1 and Blizzard's spot. Everything stands down while the gamepad UI owns the panels.

---@type string, EternityUIMapNamespace
local _, ns = ...
local W = ns.Ui.W
local Core, L = ns.Core, ns.L
local opt = Core.Opt

-- Part of the map that must stay on screen when dragged (UIParent units).
local KEEP_ON_SCREEN = 60

---@class EternityUIMapWindow
---@field hooked boolean?
---@field home table? Blizzard's last anchor for the windowed map { point, relativeTo, relativePoint, x, y }
---@field moved boolean? the map is anchored by us now
---@field scaled boolean? the map has our scale now
---@field handle table? drag handle over the header
---@field dragging table? { cursorX, cursorY, left, top } while dragging
---@field blackout table? { mouse, alpha } of Blizzard's backdrop while we change it
local Window = {}
ns.Window = Window

local function windowed(map)
    return map:IsShown() and not (map.IsMaximized and map:IsMaximized())
end

--- Whether the module positions and scales the map now.
function Window:Wanted()
    return Core.running == true and not Core.Gamepad()
end

-- Scale and position ----------------------------------------------------------------------------

--- The scale the windowed map should have.
function Window.Scale()
    local scale = tonumber(opt("window.scale")) or 1
    return math.max(0.5, math.min(1.5, scale))
end

--- The map's top left corner in UIParent units (left from UIParent's left, top from its top).
function Window.Corner(map)
    local scale = map:GetScale()
    local left, top = map:GetLeft(), map:GetTop()
    if not (left and top) then
        return nil
    end
    return left * scale, top * scale - UIParent:GetHeight()
end

--- Anchors the map's top left corner at this spot (UIParent units), kept on screen. With a Margin
--- the whole map stays that far from every edge (Blizzard's spot, a remembered one or a drag).
function Window.Place(map, left, top)
    local scale = map:GetScale()
    local width, height = map:GetWidth() * scale, map:GetHeight() * scale
    local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
    local margin = tonumber(opt("window.margin")) or 0
    if margin > 0 then
        left = math.max(margin, math.min(screenW - margin - width, left))
        top = math.min(-margin, math.max(margin + height - screenH, top))
    else
        left = math.max(KEEP_ON_SCREEN - width, math.min(screenW - KEEP_ON_SCREEN, left))
        -- The header stays reachable: never above the screen, never below its bottom edge.
        top = math.min(0, math.max(KEEP_ON_SCREEN - screenH, top))
    end
    map:ClearAllPoints()
    map:SetPoint("TOPLEFT", UIParent, "TOPLEFT", left / scale, top / scale)
end

--- Remembers where Blizzard just anchored the map. UpdateUIPanelPositions divides the offsets by
--- the map's scale, so they're stored at scale 1.
local function rememberHome(map)
    local point, relativeTo, relativePoint, x, y = map:GetPoint(1)
    if point then
        local scale = map:GetScale()
        Window.home = { point, relativeTo, relativePoint, (x or 0) * scale, (y or 0) * scale }
    end
end

--- Anchors the map in Blizzard's spot for its current scale, at least the Margin option away from
--- the screen's edges.
local function goHome(map)
    local home = Window.home
    if not home then
        return
    end
    local scale = map:GetScale()
    map:ClearAllPoints()
    map:SetPoint(home[1], home[2], home[3], home[4] / scale, home[5] / scale)
    local left, top = Window.Corner(map)
    if (tonumber(opt("window.margin")) or 0) > 0 and left then
        Window.Place(map, left, top)
    end
end

--- Scale and spot for the map's current state (called after Blizzard placed it).
function Window:Layout()
    local map = Core.Map()
    if not map then
        return
    end
    if not (self:Wanted() and windowed(map)) then
        -- Maximized (or off): Blizzard's scale. Its spot comes from MaximizeUIPanel.
        if self.scaled then
            self.scaled = false
            map:SetScale(1)
        end
        self:UpdateHandle()
        return
    end
    local scale = Window.Scale()
    if map:GetScale() ~= scale then
        map:SetScale(scale)
    end
    self.scaled = scale ~= 1
    local saved = opt("window.remember") and Core.DB().position
    if saved then
        Window.Place(map, saved.left, saved.top)
        self.moved = true
    else
        goHome(map)
        self.moved = false
    end
    self:UpdateHandle()
end

--- Puts the map back in Blizzard's spot and forgets the dragged one.
function Window:Reset()
    Core.DB().position = nil
    self.moved = false
    local map = Core.Map()
    if map and windowed(map) then
        goHome(map)
        self:Layout()
    end
end

-- Dragging --------------------------------------------------------------------------------------

local function cursor()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    return x / scale, y / scale
end

function Window:CreateHandle(map)
    if self.handle then
        return self.handle
    end
    -- Over the header, leaving room for the portrait/tutorial (left) and the buttons (right).
    local handle = CreateFrame("Frame", nil, map.BorderFrame or map)
    handle:SetPoint("TOPLEFT", map, "TOPLEFT", 60, 0)
    handle:SetPoint("TOPRIGHT", map, "TOPRIGHT", -64, 0)
    handle:SetHeight(24)
    handle:EnableMouse(true)
    handle:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then
            return
        end
        local left, top = Window.Corner(map)
        if not left then
            return
        end
        local x, y = cursor()
        self.dragging = { x = x, y = y, left = left, top = top }
    end)
    handle:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            self:Reset()
            Core.Print(L.RESET_DONE)
            return
        end
        if self.dragging then
            self.dragging = nil
            local left, top = Window.Corner(map)
            if left then
                Core.DB().position = { left = left, top = top }
                self.moved = true
            end
        end
    end)
    handle:SetScript("OnUpdate", function()
        local drag = self.dragging
        if not drag then
            return
        end
        if not IsMouseButtonDown("LeftButton") then
            handle:GetScript("OnMouseUp")(handle, "LeftButton")
            return
        end
        local x, y = cursor()
        Window.Place(map, drag.left + (x - drag.x), drag.top + (y - drag.y))
    end)
    W.AttachTooltip(handle, function(tooltip)
        tooltip:SetTitle(L.TITLE)
        tooltip:AddHint(L.RESET_HINT)
    end, "BOTTOM")
    handle:Hide()
    self.handle = handle
    return handle
end

function Window:UpdateHandle()
    local map = Core.Map()
    if not map then
        return
    end
    local want = self:Wanted() and opt("window.remember") == true and windowed(map)
    if want then
        self:CreateHandle(map):Show()
    elseif self.handle then
        self.dragging = nil
        self.handle:Hide()
    end
end

-- The maximized map's backdrop ------------------------------------------------------------------

--- Opacity and click-through of Blizzard's BlackoutFrame (it covers the screen when maximized).
function Window:ApplyBlackout()
    local map = Core.Map()
    local frame = map and map.BlackoutFrame
    if not frame then
        return
    end
    local texture = frame.Blackout
    if self:Wanted() then
        if not self.blackout then
            self.blackout = { mouse = frame:IsMouseEnabled(), alpha = texture and texture:GetAlpha() or 1 }
        end
        frame:EnableMouse(opt("window.clickThrough") ~= true)
        if texture then
            texture:SetAlpha(tonumber(opt("window.backdrop")) or 1)
        end
    elseif self.blackout then
        frame:EnableMouse(self.blackout.mouse)
        if texture then
            texture:SetAlpha(self.blackout.alpha)
        end
        self.blackout = nil
    end
end

-- Life cycle ------------------------------------------------------------------------------------

function Window:InstallHooks(map)
    if self.hooked then
        return
    end
    self.hooked = true
    -- Blizzard just placed its panels: that's the map's home; then our spot and scale.
    hooksecurefunc("UpdateUIPanelPositions", function()
        if not windowed(map) then
            return
        end
        rememberHome(map)
        if self:Wanted() then
            self:Layout()
        end
    end)
    local relayout = function()
        if self:Wanted() or self.scaled then
            self:Layout()
        end
    end
    if map.Maximize then
        hooksecurefunc(map, "Maximize", relayout)
    end
    if map.Minimize then
        hooksecurefunc(map, "Minimize", relayout)
    end
    map:HookScript("OnShow", function()
        if not self:Wanted() then
            return
        end
        -- In case Blizzard placed it before showing it (the hook above skips hidden maps).
        if windowed(map) and not self.moved then
            rememberHome(map)
        end
        self:ApplyBlackout()
        self:Layout()
    end)
    map:HookScript("OnHide", function()
        self.dragging = nil
    end)
end

--- Applies scale, spot and backdrop from the options, or gives Blizzard's back. Safe to call again.
function Window:Apply()
    local map = Core.Map()
    if not map then
        return
    end
    self:InstallHooks(map)
    self:ApplyBlackout()
    if self:Wanted() then
        self:Layout()
        return
    end
    -- Off: scale 1 and Blizzard's spot. The next open is placed by Blizzard anyway.
    self.dragging = nil
    if self.scaled or map:GetScale() ~= 1 then
        self.scaled = false
        map:SetScale(1)
    end
    if self.moved then
        self.moved = false
        if windowed(map) then
            goHome(map)
        end
    end
    self:UpdateHandle()
end
