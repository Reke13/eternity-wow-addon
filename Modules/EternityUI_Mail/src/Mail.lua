-- EternityUI_Mail: the history of the letters every character sends and receives (History), shown
-- in a tab of the module's options (List), opened from a button by the mailbox or /etmail; and
-- the recipient kept after sending (Recipient). This file starts and stops them.
-- The button is a frame of ours in UIParent that follows the mailbox (shown on MAIL_SHOW, hidden
-- on MAIL_CLOSED): nothing is written into Blizzard's mail frames.

---@type string, EternityUIMailNamespace
local addonName, ns = ...
local E = EternityUI
local Widgets = E.Widgets
local L, History, List, Recipient, opt = ns.L, ns.History, ns.List, ns.Recipient, ns.opt

---@class EternityUIMailModule: EternityUIModuleDefinition
local Module = {
    schema = ns.OptionsSchema,
    tabs = { { key = List.TAB, text = L.TAB, build = List.Build } },
}
-- Internals reachable from the tests.
Module.History, Module.List, Module.Recipient, Module.L = History, List, Recipient, L
Module.Classes = ns.Classes

-- The button by the mailbox ---------------------------------------------------------------------

local BUTTON_SIZE = 20
local BUTTON_ICON = "Interface\\Icons\\INV_Letter_15"
local STRATA_ABOVE = {
    BACKGROUND = "LOW",
    LOW = "MEDIUM",
    MEDIUM = "HIGH",
    HIGH = "DIALOG",
    DIALOG = "FULLSCREEN",
    FULLSCREEN = "FULLSCREEN_DIALOG",
    FULLSCREEN_DIALOG = "TOOLTIP",
}

--- A small icon button, like the mailbox's own close button: it sits just left of it.
function Module:Button()
    if self.button then
        return self.button
    end
    local button = CreateFrame("Button", nil, UIParent)
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    button:Hide()
    button.back = button:CreateTexture(nil, "BACKGROUND")
    button.back:SetPoint("TOPLEFT", -1, 1)
    button.back:SetPoint("BOTTOMRIGHT", 1, -1)
    button.back:SetColorTexture(0, 0, 0, 0.8)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexture(BUTTON_ICON)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetScript("OnMouseDown", function()
        button.icon:SetPoint("TOPLEFT", 1, -1)
        button.icon:SetPoint("BOTTOMRIGHT", 1, -1)
    end)
    button:SetScript("OnMouseUp", function()
        button.icon:ClearAllPoints()
        button.icon:SetAllPoints()
    end)
    button:SetScript("OnClick", List.Open)
    Widgets.AttachTooltip(button, function(tip)
        tip:SetTitle(L.BUTTON)
        tip:AddLine(L.BUTTON_HINT, "textMuted")
    end)
    self.button = button
    return button
end

--- Follows the mailbox window itself: Blizzard opens and closes it through the interaction
--- manager, and MAIL_CLOSED doesn't always come when it's closed with its X. HookScript only.
function Module:HookMailFrame()
    local frame = _G.MailFrame
    if self.frameHooked or not frame then
        return
    end
    self.frameHooked = true
    frame:HookScript("OnShow", function()
        self:UpdateButton()
    end)
    frame:HookScript("OnHide", function()
        -- Closed: the same as MAIL_CLOSED, which may not come.
        History.OnEvent("MAIL_CLOSED")
        Recipient.OnEvent("MAIL_CLOSED")
        self:UpdateButton()
    end)
end

--- Shows the button on the open mailbox while the module runs and the option is on.
function Module:UpdateButton()
    self:HookMailFrame()
    local frame = _G.MailFrame
    local show = self.running and opt("history.button") and frame ~= nil and frame:IsShown()
    if not show then
        if self.button then
            self.button:Hide()
        end
        return
    end
    local button = self:Button()
    local close = frame.CloseButton or _G.MailFrameCloseButton
    button:ClearAllPoints()
    if close then
        button:SetPoint("RIGHT", close, "LEFT", -2, 0)
    else
        button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -3)
    end
    -- The mailbox is a toplevel frame: clicked or opened, it's raised above any level of its
    -- strata, so a level over it isn't enough. The next strata keeps the button on top.
    button:SetFrameStrata(STRATA_ABOVE[frame:GetFrameStrata()] or "HIGH")
    button:Show()
end

-- Lifecycle ------------------------------------------------------------------------------------

function Module:OnEvent(event)
    History.OnEvent(event)
    Recipient.OnEvent(event)
    self:UpdateButton()
end

function Module:OnEnable()
    self.running = true
    History.onChange = List.Schedule
    for _, event in ipairs(History.EVENTS) do
        E.Events.On(event, self, function(name)
            self:OnEvent(name)
        end)
    end
    History.Start()
    Recipient.Start()
    self:UpdateButton()
end

function Module:OnDisable()
    self.running = false
    History.onChange = nil
    History.Stop()
    Recipient.Stop()
    self:UpdateButton()
end

function Module:OnConfigChanged(path)
    if path == nil or path == "history.limit" then
        History.Trim()
    end
    Recipient.Apply()
    self:UpdateButton()
    List.Refresh()
end

_G.SLASH_ETERNITYMAIL1 = "/etmail"
SlashCmdList.ETERNITYMAIL = function()
    List.Open()
end

E:RegisterModule(addonName, Module)
