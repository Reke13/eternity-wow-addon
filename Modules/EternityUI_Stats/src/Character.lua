-- EternityUI_Stats and the character window: when the panel shows (with the window, or with its
-- equipment tab), where it goes (next to the window, where the player dragged it, or free in the
-- Mover) and the show/hide button among the equipment tab's sidebar tabs.
--
-- Replaces no Blizzard method: HookScript only, installed once, doing nothing while
-- Core.running is false. Blizzard's right pane is left to its own button: calling
-- SetRightPaneCollapsed from here ran the UI panel layout tainted, and the taint reached the unit
-- frames, which then failed comparing secret health. Nothing here is protected: the panel and the
-- button are plain frames, so showing, hiding and moving them works in combat.

---@type string, EternityUIStatsNamespace
local addonName, ns = ...
local E = EternityUI
local W = ns.Ui.W
local Core, Panel, L = ns.Core, ns.Panel, ns.L
local opt = Core.Opt

local EDIT_KEY = "EternityUIStats"
local ICON = "Interface\\Icons\\INV_Misc_Note_05"
local TAB_SIZE = 42

---@class EternityUIStatsCharacter
---@field hooked boolean? hooks installed
---@field editing boolean? Eternity's Edit Mode is open
---@field registered boolean? the panel is an Edit Mode element (panel.attach = "free")
local Character = {}
ns.Character = Character

local function characterFrame()
    return _G.CharacterFrame
end

local function paperDoll()
    return _G.PaperDollFrame
end

--- The rightmost sidebar tab shown (Titles, or the pet's tab after it), nil when the equipment
--- tab's sidebar tabs are hidden.
local function lastSidebarTab()
    local tabs = _G.PaperDollSidebarTabs
    if not (tabs and tabs:IsShown()) then
        return nil
    end
    local pet, titles = _G.PaperDollSidebarTab4, _G.PaperDollSidebarTab3
    if pet and pet:IsShown() then
        return pet
    end
    if titles and titles:IsShown() then
        return titles
    end
    return nil
end

function Character:InstallHooks()
    if self.hooked then
        return
    end
    self.hooked = true
    local refresh = function()
        if Core.running then
            self:Update()
        end
    end
    local button = function()
        if Core.running then
            self:UpdateButton()
        end
    end
    local frame, doll = characterFrame(), paperDoll()
    if frame then
        frame:HookScript("OnShow", refresh)
        frame:HookScript("OnHide", refresh)
        frame:HookScript("OnSizeChanged", refresh)
    end
    if doll then
        doll:HookScript("OnShow", refresh)
        doll:HookScript("OnHide", refresh)
    end
    for _, name in ipairs({ "PaperDollSidebarTabs", "PaperDollSidebarTab3", "PaperDollSidebarTab4" }) do
        local tab = _G[name]
        if tab then
            tab:HookScript("OnShow", button)
            tab:HookScript("OnHide", button)
        end
    end
    E.Events.Listen(E.Mover.TOGGLED, self, function(_, open)
        self.editing = open
        refresh()
    end)
end

--- Whether the panel should be on screen now.
function Character:ShouldShow()
    if not (Core.running and opt("panel.enabled")) then
        return false
    end
    if self.editing and opt("panel.attach") == "free" then
        return true
    end
    if not Core.Char().shown then
        return false
    end
    local frame = characterFrame()
    if not (frame and frame:IsShown()) then
        return false
    end
    if opt("panel.showWith") == "paperdoll" then
        local doll = paperDoll()
        return doll ~= nil and doll:IsShown()
    end
    return true
end

--- Whether the player can drag the panel by its title (not while the Mover places it).
function Character:CanDrag()
    return Core.running == true and opt("panel.movable") == true and opt("panel.attach") ~= "free"
end

--- Position: where the player dragged it, next to the character window, or an Edit Mode element.
function Character:Anchor()
    local panel = Panel:Create()
    local frame = characterFrame()
    local free = opt("panel.attach") == "free"
    if free and not self.registered then
        self.registered = true
        E.Mover.Register({
            key = EDIT_KEY,
            owner = addonName,
            label = L.TITLE,
            frame = panel,
            point = "LEFT",
            x = 40,
            y = 0,
        })
    elseif not free and self.registered then
        self.registered = false
        E.Mover.Unregister(EDIT_KEY)
    end
    if frame then
        panel:SetFrameStrata(frame:GetFrameStrata())
        panel:SetFrameLevel(frame:GetFrameLevel() + 20)
    end
    -- Scale first: the saved spot is placed in the panel's own scale.
    panel:SetScale(opt("window.scale"))
    local saved = Core.Account().position
    if Panel.drag then
        -- The drag places it.
    elseif not free and saved and opt("panel.movable") then
        Panel:PlaceAt(saved.x, saved.y)
    elseif not free and frame then
        panel:ClearAllPoints()
        local gap, y = opt("window.gap"), opt("window.offsetY")
        if opt("window.side") == "left" then
            panel:SetPoint("TOPRIGHT", frame, "TOPLEFT", -gap, y)
        else
            panel:SetPoint("TOPLEFT", frame, "TOPRIGHT", gap, y)
        end
    end
    -- Same height as the window, in the panel's own scale.
    Panel.minHeight = nil
    if opt("window.matchHeight") and frame then
        local height = frame:GetHeight()
        if not Core.Secret(height) and height > 0 then
            local ratio = frame:GetEffectiveScale() / math.max(0.01, panel:GetEffectiveScale())
            Panel.minHeight = height * ratio
        end
    end
end

--- Shows or hides the panel and the button from the current state.
function Character:Update()
    self:Anchor()
    local was = Panel.frame:IsShown()
    -- Showing it refreshes it (OnShow); one already shown is laid out again for the new options.
    Panel:SetShown(self:ShouldShow())
    if was and Panel.frame:IsShown() then
        Panel:Refresh(true)
    end
    ns.Settings:Refresh()
    self:UpdateButton()
end

-- Button among the sidebar tabs ----------------------------------------------------------------

--- A button like the sidebar tabs (Character, Equipment manager, Titles), with its own icon. Not
--- a secure template: a plain Button, safe to show, hide and move in combat.
function Character:CreateButton(frame)
    local button = CreateFrame("Button", "EternityUIStatsToggleButton", frame)
    button:SetSize(TAB_SIZE, TAB_SIZE)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button.icon = button:CreateTexture(nil, "BACKGROUND")
    button.icon:SetPoint("CENTER")
    button.icon:SetSize(TAB_SIZE - 12, TAB_SIZE - 12)
    button.icon:SetTexture(ICON)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.border = button:CreateTexture(nil, "BORDER")
    button.border:SetPoint("CENTER")
    button.border:SetAtlas("UI-Character-Info-StatTab", true)
    button.selected = button:CreateTexture(nil, "OVERLAY")
    button.selected:SetPoint("CENTER")
    button.selected:SetAtlas("UI-Character-Info-StatTab-Selected", true)
    button.selected:SetBlendMode("ADD")
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    local highlight = button:GetHighlightTexture()
    if highlight then
        highlight:ClearAllPoints()
        highlight:SetPoint("CENTER")
        highlight:SetSize(TAB_SIZE - 12, TAB_SIZE - 12)
    end
    button:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            if not Core.Char().shown then
                self:Toggle()
            end
            ns.Settings:Toggle()
        else
            self:Toggle()
        end
    end)
    W.AttachTooltip(button, function(tooltip)
        tooltip:SetTitle(L.TOGGLE)
        tooltip:AddHint(L.TOGGLE_HINT)
    end, "BOTTOM")
    return button
end

function Character:UpdateButton()
    local frame = characterFrame()
    if not frame then
        return
    end
    self.button = self.button or self:CreateButton(frame)
    local button = self.button
    button:SetFrameLevel(frame:GetFrameLevel() + 10)
    button:ClearAllPoints()
    -- To the right of Titles (or the pet's tab); in the window's corner when the tabs are hidden.
    local tab = lastSidebarTab()
    if tab then
        button:SetScale(1)
        button:SetPoint("LEFT", tab, "RIGHT", 0, 0)
    else
        button:SetScale(0.6)
        button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -50, -6)
    end
    button.selected:SetShown(Core.Char().shown == true)
    button.icon:SetDesaturated(not Core.Char().shown)
    button:SetShown(Core.running == true and opt("panel.enabled") and opt("panel.toggleButton"))
end

--- Shows or hides the panel for this character (the button and /etstats).
function Character:Toggle()
    local char = Core.Char()
    char.shown = not char.shown
    if Core.running then
        self:Update()
    end
    return char.shown
end

-- Life cycle -----------------------------------------------------------------------------------

function Character:Enable()
    self:InstallHooks()
    self.editing = (E.MoverSession ~= nil and E.MoverSession.active == true)
    self:Update()
end

function Character:Disable()
    if self.registered then
        self.registered = false
        E.Mover.Unregister(EDIT_KEY)
    end
    if Panel.frame then
        Panel.frame:Hide()
    end
    ns.Settings:Hide()
    if self.button then
        self.button:Hide()
    end
end

function Character:Refresh()
    Panel.signature = nil
    self:Update()
end
