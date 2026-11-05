-- The world map's look: an Eternity window behind the map (W.Panel), its own title, and the
-- close, maximize/minimize and quest log buttons drawn with the core's icons.
--
-- Blizzard's buttons keep doing the work: their textures go to alpha 0 and an icon that doesn't
-- take the mouse is drawn on top, so every click is still a hardware click on Blizzard's own
-- button (no taint; closing and maximizing keep working in combat). Blizzard's regions are only
-- set to alpha 0 through a stash and given back as they were; nothing is reparented or replaced.
-- SetBorder re-applies the border on every maximize and minimize, so the hooks hide it again.

---@type string, EternityUIMapNamespace
local _, ns = ...
local Theme, W = ns.Ui.Theme, ns.Ui.W
local Skin = W.Skin
local Core = ns.Core
local opt = Core.Opt

local HEADER_HEIGHT = 26

---@class EternityUIMapSkin
---@field hooked boolean?
---@field active boolean? the Eternity look is on now
---@field stash EternityUIMapStash
---@field backdrop table? our window behind the map
---@field header table? our title bar (inside Blizzard's BorderFrame, which is over the map)
---@field questBackdrop table?
---@field overlays table<table, table> Blizzard button -> our icon drawn on it
---@field padding number room around the map inside our window (windowed map only)
local MapSkin = { stash = Core.NewStash(), overlays = {}, padding = 0 }
ns.Skin = MapSkin

-- Blizzard's buttons and the icon each one gets (seen in Forever FrameXML 1.60.1.70532).
local function buttons(map)
    local border = map.BorderFrame
    local maxMin = border and border.MaximizeMinimizeFrame
    local toggle = map.SidePanelToggle
    return {
        { border and border.CloseButton, "close", true },
        { maxMin and maxMin.MaximizeButton, "expand" },
        { maxMin and maxMin.MinimizeButton, "shrink" },
        { toggle and toggle.OpenButton, "menu" },
        { toggle and toggle.CloseButton, "chevronRight" },
    }
end

-- Blizzard's own drawings that our window replaces.
local function borderRegions(map)
    local border = map.BorderFrame
    if not border then
        return {}
    end
    return {
        border.NineSlice,
        border.PortraitContainer,
        border.portrait,
        border.TitleContainer,
        border.TopTileStreaks,
        border.InsetBorderTop,
        border.Underlay,
        -- Reparented to the map by WorldMapMixin:SetupTitle, the key stays on BorderFrame.
        border.Bg,
    }
end

local function questRegions()
    local quest, scroll = _G.QuestMapFrame, _G.QuestScrollFrame
    local list = {}
    if quest then
        list[#list + 1] = quest.VerticalSeparator
        list[#list + 1] = quest.Background
        if quest.DetailsFrame then
            list[#list + 1] = quest.DetailsFrame.BackFrame
            list[#list + 1] = quest.DetailsFrame.Bg
        end
    end
    if scroll then
        list[#list + 1] = scroll.Background
        list[#list + 1] = scroll.BorderFrame
        list[#list + 1] = scroll.Edge
    end
    return list
end

-- Our pieces ------------------------------------------------------------------------------------

function MapSkin:Create(map)
    if self.backdrop then
        return
    end
    local backdrop = W.Panel(map, { role = "window", fill = "window", border = "border" })
    backdrop:SetFrameLevel(map:GetFrameLevel())
    backdrop:Hide()
    self.backdrop = backdrop

    -- Inside BorderFrame (HIGH strata) so it's drawn over the map like Blizzard's title.
    local header = CreateFrame("Frame", nil, map.BorderFrame or map)
    header:SetHeight(HEADER_HEIGHT)
    header:EnableMouse(false)
    header.title = W.Text(header, "", "heading")
    header.title:SetPoint("LEFT", header, "LEFT", 14, -1)
    header:Hide()
    self.header = header
    self:SetPadding(self.padding)
end

--- Room between the map and the edge of our window: the window (and its title bar) grow outwards
--- by that much on every side. 0: the window is the map's size.
---@param padding number
function MapSkin:SetPadding(padding)
    self.padding = padding or 0
    local map = Core.Map()
    if not (map and self.backdrop) then
        return
    end
    local p = self.padding
    self.backdrop:ClearAllPoints()
    self.backdrop:SetPoint("TOPLEFT", map, "TOPLEFT", -p, p)
    self.backdrop:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", p, -p)
    self.header:ClearAllPoints()
    self.header:SetPoint("TOPLEFT", map, "TOPLEFT", -p, p)
    self.header:SetPoint("TOPRIGHT", map, "TOPRIGHT", p, p)
end

function MapSkin:CreateQuestBackdrop()
    local quest = _G.QuestMapFrame
    if self.questBackdrop or not quest then
        return
    end
    local panel = W.Panel(quest, { role = "card", fill = "surface", border = "divider" })
    panel:SetPoint("TOPLEFT", quest, "TOPLEFT", 2, 0)
    panel:SetPoint("BOTTOMRIGHT", quest, "BOTTOMRIGHT", -2, 2)
    panel:SetFrameLevel(math.max(0, quest:GetFrameLevel() - 1))
    panel:Hide()
    self.questBackdrop = panel
end

--- The title Blizzard shows ("Map and Quest Log" or "World Map").
function MapSkin:UpdateTitle()
    local map = Core.Map()
    if not (self.header and map and map.BorderFrame) then
        return
    end
    local container = map.BorderFrame.TitleContainer
    local text = container and container.TitleText and container.TitleText:GetText()
    self.header.title:SetText(type(text) == "string" and text or "")
end

-- Buttons ---------------------------------------------------------------------------------------

local function textures(button)
    return {
        button:GetNormalTexture(),
        button:GetPushedTexture(),
        button:GetHighlightTexture(),
        button:GetDisabledTexture(),
    }
end

--- Our icon over a Blizzard button (created once; it doesn't take the mouse).
function MapSkin:Overlay(button, icon, danger)
    local overlay = self.overlays[button]
    if overlay then
        return overlay
    end
    overlay = CreateFrame("Frame", nil, button)
    overlay:SetSize(22, 22)
    overlay:SetPoint("CENTER")
    overlay:EnableMouse(false)
    overlay:SetFrameLevel(button:GetFrameLevel() + 2)
    overlay.shape = Skin.Shape(overlay, "control")
    overlay.icon = Skin.Icon(overlay, icon, 10)
    overlay.icon:SetPoint("CENTER")
    W.Themed(overlay, function(frame)
        local hovered = button:IsMouseOver() and button:IsEnabled()
        if hovered and danger then
            frame.shape:SetColors({ Theme.Color("danger", 0.18) })
        else
            frame.shape:SetColors(hovered and "surfaceHover" or "field", "border")
        end
        frame.icon:SetColor(hovered and (danger and "danger" or "text") or "textMuted")
    end)
    -- Hooks can't be removed: they only repaint, and only while the overlay is shown.
    local repaint = function()
        if overlay:IsShown() then
            overlay:ApplyTheme()
        end
    end
    button:HookScript("OnEnter", repaint)
    button:HookScript("OnLeave", repaint)
    overlay:Hide()
    self.overlays[button] = overlay
    return overlay
end

-- Applying and giving back ----------------------------------------------------------------------

function MapSkin:InstallHooks(map)
    if self.hooked then
        return
    end
    self.hooked = true
    local reapply = function()
        if self.active then
            self:Apply()
        end
    end
    map:HookScript("OnShow", reapply)
    if map.Maximize then
        hooksecurefunc(map, "Maximize", reapply)
    end
    if map.Minimize then
        hooksecurefunc(map, "Minimize", reapply)
    end
    if map.BorderFrame and map.BorderFrame.SetTitle then
        hooksecurefunc(map.BorderFrame, "SetTitle", function()
            if self.active then
                self:UpdateTitle()
            end
        end)
    end
end

--- Whether the Eternity look should be on.
function MapSkin:Wanted()
    return Core.running == true and opt("look.skin") == true
end

--- Puts the look on or gives Blizzard's back, from the options. Safe to call again.
function MapSkin:Apply()
    local map = Core.Map()
    if not map then
        return
    end
    self:InstallHooks(map)
    local want = self:Wanted()
    if not want then
        self:Remove()
        return
    end
    self.active = true
    self:Create(map)
    local stash = self.stash
    for _, region in pairs(borderRegions(map)) do
        stash:Hide(region)
    end
    for _, entry in ipairs(buttons(map)) do
        local button, icon, danger = entry[1], entry[2], entry[3]
        if button then
            for _, texture in pairs(textures(button)) do
                stash:Hide(texture)
            end
            local overlay = self:Overlay(button, icon, danger)
            overlay:Show()
            overlay:ApplyTheme()
        end
    end
    local quest = opt("look.questLog") == true
    if quest then
        self:CreateQuestBackdrop()
        for _, region in pairs(questRegions()) do
            stash:Hide(region)
        end
    end
    if self.questBackdrop then
        self.questBackdrop:SetShown(quest)
    end
    -- The quest log option turned off: give its regions back without touching the rest.
    if not quest and self.questTaken then
        for _, region in pairs(questRegions()) do
            local alpha = stash.saved[region]
            if alpha ~= nil then
                region:SetAlpha(alpha)
                stash.saved[region] = nil
            end
        end
    end
    self.questTaken = quest
    self.backdrop:Show()
    self.header:Show()
    self:UpdateTitle()
end

--- Gives Blizzard's look back exactly as it was.
function MapSkin:Remove()
    self.active = false
    self.questTaken = false
    self.stash:RestoreAll()
    for _, overlay in pairs(self.overlays) do
        overlay:Hide()
    end
    if self.backdrop then
        self.backdrop:Hide()
        self.header:Hide()
    end
    if self.questBackdrop then
        self.questBackdrop:Hide()
    end
end
