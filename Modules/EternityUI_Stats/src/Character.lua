-- EternityUI_Stats and the character window: when the panel shows (with the window, or with its
-- equipment tab), where it goes (next to the window or free in the Mover) and the show/hide button.
--
-- Replaces no Blizzard method: HookScript only, installed once, doing nothing while
-- Core.running is false. Blizzard's right pane is left to its own button: calling
-- SetRightPaneCollapsed from here ran the UI panel layout tainted, and the taint reached the unit
-- frames, which then failed comparing secret health.

---@type string, EternityUIStatsNamespace
local addonName, ns = ...
local E = EternityUI
local W = ns.Ui.W
local Core, Panel, L = ns.Core, ns.Panel, ns.L
local opt = Core.Opt

local EDIT_KEY = "EternityUIStats"

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

--- Position: next to the character window, or an Edit Mode element.
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
    if not free and frame then
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
    if opt("window.matchHeight") and frame and frame:GetHeight() > 0 then
        local ratio = frame:GetEffectiveScale() / math.max(0.01, panel:GetEffectiveScale())
        Panel.minHeight = frame:GetHeight() * ratio
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
    self:UpdateButton()
end

-- Button on the character window ---------------------------------------------------------------

function Character:UpdateButton()
    local frame = characterFrame()
    if not frame then
        return
    end
    if not self.button then
        self.button = W.IconButton(frame, {
            icon = "minus",
            size = 20,
            onClick = function()
                self:Toggle()
            end,
        })
        self.button:SetFrameLevel(frame:GetFrameLevel() + 10)
        W.AttachTooltip(self.button, function(tooltip)
            tooltip:SetTitle(L.TOGGLE)
            tooltip:AddHint(L.TOGGLE_HINT)
        end, "BOTTOM")
    end
    local button = self.button
    button:ClearAllPoints()
    button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -4)
    button.icon:SetIcon(Core.Char().shown and "minus" or "plus")
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
    if self.button then
        self.button:Hide()
    end
end

function Character:Refresh()
    Panel.signature = nil
    self:Update()
end
