-- Hover key binding mode (/kb, /etbars keys), like Bartender's and ElvUI's: hover a button and press a
-- key, a mouse button or the wheel (with any modifiers) to bind it; Escape clears the button's keys.
-- Keys are bound to Blizzard's commands (ACTIONBUTTON1, MULTIACTIONBAR1BUTTON1, SHAPESHIFTBUTTON1,
-- BONUSACTIONBUTTON1...), never to our buttons: Blizzard.lua's override bindings then point those
-- keys at our bars, so the bindings stay right with the module off. Changes are kept in the current
-- binding set until Save (SaveBindings) or thrown away with Discard (LoadBindings). Binding is
-- protected in combat: the mode won't open in combat and closes, discarding, when combat starts.

---@type string, EternityUIActionBarsNamespace
local _, ns = ...
local E = EternityUI
local Widgets = E.Widgets
local Bars, Style, L = ns.Bars, ns.Style, ns.L

---@class EternityUIActionBarsKeybind
---@field active boolean?
---@field target table? the hovered button
---@field changed boolean? something was bound since the mode opened
local Keybind = {}
ns.Keybind = Keybind

-- Keys that are only modifiers: pressing them alone binds nothing.
local MODIFIERS = {
    LSHIFT = true,
    RSHIFT = true,
    LCTRL = true,
    RCTRL = true,
    LALT = true,
    RALT = true,
    LMETA = true,
    RMETA = true,
    UNKNOWN = true,
}
-- Mouse buttons as binding keys. Left and right clicks stay clicks.
local MOUSE = {
    MiddleButton = "BUTTON3",
    Button4 = "BUTTON4",
    Button5 = "BUTTON5",
}

--- Binding key for a key press with the modifiers held now ("SHIFT-1", "CTRL-BUTTON4").
---@param key string
---@param alt boolean?
---@param ctrl boolean?
---@param shift boolean?
---@param meta boolean?
---@return string
function Keybind.KeyName(key, alt, ctrl, shift, meta)
    return (alt and "ALT-" or "")
        .. (ctrl and "CTRL-" or "")
        .. (shift and "SHIFT-" or "")
        .. (meta and "META-" or "")
        .. key
end

local function held(key)
    return Keybind.KeyName(
        key,
        IsAltKeyDown(),
        IsControlKeyDown(),
        IsShiftKeyDown(),
        IsMetaKeyDown and IsMetaKeyDown() or false
    )
end

--- Blizzard's binding command of a button, or nil if it can't be bound here.
---@param button table
---@return string?
function Keybind.Command(button)
    return button and button.eternityCommand
end

--- Keys bound to a command.
---@param command string
---@return string[]
function Keybind.Keys(command)
    return { GetBindingKey(command) }
end

-- The overlay ----------------------------------------------------------------------------------

local overlay

local function showTooltip(button)
    local command = Keybind.Command(button)
    if not command then
        return
    end
    GameTooltip:SetOwner(overlay, "ANCHOR_TOP")
    GameTooltip:AddLine(_G["BINDING_NAME_" .. command] or command, 1, 1, 1)
    local keys = Keybind.Keys(command)
    if #keys == 0 then
        GameTooltip:AddLine(L.KEYS_NONE, 0.6, 0.6, 0.6)
    else
        for _, key in ipairs(keys) do
            GameTooltip:AddLine(GetBindingText and GetBindingText(key) or key, 0.4, 0.8, 1)
        end
    end
    GameTooltip:AddLine(L.KEYS_HINT, 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

--- Binds a key to the hovered button's command (Escape clears its keys).
---@param key string binding key with modifiers ("SHIFT-1"), or "ESCAPE"
---@return boolean bound
function Keybind:Bind(key)
    local command = Keybind.Command(self.target)
    if not self.active or not command or InCombatLockdown() then
        return false
    end
    if key == "ESCAPE" then
        for _, old in ipairs(Keybind.Keys(command)) do
            SetBinding(old)
        end
    else
        SetBinding(key, command)
    end
    self.changed = true
    showTooltip(self.target)
    return true
end

local function createOverlay()
    overlay = CreateFrame("Button", "EternityUIActionBarsKeybind", UIParent)
    overlay:SetFrameStrata("DIALOG")
    overlay:EnableMouse(true)
    overlay:EnableMouseWheel(true)
    overlay:RegisterForClicks("AnyUp")
    overlay:Hide()
    overlay.tint = overlay:CreateTexture(nil, "OVERLAY")
    overlay.tint:SetAllPoints()

    overlay:SetScript("OnKeyDown", function(_, key)
        if MODIFIERS[key] then
            return
        end
        Keybind:Bind(key == "ESCAPE" and key or held(key))
    end)
    overlay:SetScript("OnMouseDown", function(_, button)
        local key = MOUSE[button]
        if key then
            Keybind:Bind(held(key))
        end
    end)
    overlay:SetScript("OnMouseWheel", function(_, delta)
        Keybind:Bind(held(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"))
    end)
    overlay:SetScript("OnLeave", function()
        Keybind:Hover(nil)
    end)
    overlay:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            Keybind:Stop(false)
        end
    end)
end

-- The panel: what to do, Save and Discard.
local panel

local function createPanel()
    panel = CreateFrame("Frame", nil, UIParent)
    panel:SetFrameStrata("DIALOG")
    panel:SetSize(360, 112)
    panel:SetPoint("TOP", 0, -120)
    panel:EnableMouse(true)
    panel.shape = E.Shape.New(panel)
    function panel:Paint()
        E.Theme.PaintWindow(self.shape)
    end
    Widgets.Track(panel)
    panel.title = Widgets.Text(panel, 15, "text")
    panel.title:SetPoint("TOPLEFT", 14, -12)
    panel.title:SetText(L.KEYS_TITLE)
    panel.help = Widgets.Text(panel, 13, "muted")
    panel.help:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -6)
    panel.help:SetPoint("RIGHT", -14, 0)
    panel.help:SetJustifyH("LEFT")
    panel.help:SetText(L.KEYS_HELP)
    panel.save = Widgets.Button(panel, L.KEYS_SAVE, "primary", function()
        Keybind:Stop(true)
    end)
    panel.save:SetPoint("BOTTOMRIGHT", -12, 10)
    panel.discard = Widgets.Button(panel, L.KEYS_DISCARD, "ghost", function()
        Keybind:Stop(false)
    end)
    panel.discard:SetPoint("RIGHT", panel.save, "LEFT", -8, 0)
    panel:Hide()
end

--- Puts the overlay over a hovered button (nil hides it).
---@param button table?
function Keybind:Hover(button)
    if not self.active then
        return
    end
    if not button or not Keybind.Command(button) then
        self.target = nil
        overlay:EnableKeyboard(false)
        overlay:Hide()
        GameTooltip:Hide()
        return
    end
    self.target = button
    overlay:ClearAllPoints()
    overlay:SetAllPoints(button)
    overlay:Show()
    overlay:EnableKeyboard(true)
    showTooltip(button)
end

-- Every bindable button (ours and the borrowed stance and pet ones) calls Hover on enter (once).
local function hookButtons()
    for _, bar in ipairs(Bars.LIST) do
        for _, button in ipairs(bar.buttons) do
            if button.eternityCommand and not button.eternityKeybindHook then
                button.eternityKeybindHook = true
                button:HookScript("OnEnter", function(self)
                    if Keybind.active then
                        Keybind:Hover(self)
                    end
                end)
            end
        end
    end
end

--- Opens the mode (not in combat).
---@return boolean opened
function Keybind:Start()
    if self.active then
        return true
    end
    if InCombatLockdown() or not Bars.running then
        print(L.KEYS_COMBAT)
        return false
    end
    if not overlay then
        createOverlay()
        createPanel()
    end
    self.active = true
    self.changed = false
    local r, g, b = Style.Color("accent")
    overlay.tint:SetColorTexture(r, g, b, 0.35)
    overlay:RegisterEvent("PLAYER_REGEN_DISABLED")
    panel:Show()
    -- Every bar and empty slot shows while binding, so any button can be hovered.
    Bars.binding = true
    ns.Module:Apply()
    hookButtons()
    return true
end

--- Closes the mode, saving the changes or throwing them away.
---@param save boolean
function Keybind:Stop(save)
    if not self.active then
        return
    end
    self.active = false
    self.target = nil
    overlay:UnregisterEvent("PLAYER_REGEN_DISABLED")
    overlay:EnableKeyboard(false)
    overlay:Hide()
    panel:Hide()
    GameTooltip:Hide()
    if self.changed then
        local set = GetCurrentBindingSet()
        if save then
            SaveBindings(set)
        else
            LoadBindings(set)
        end
    end
    self.changed = false
    Bars.binding = false
    ns.Module:Apply()
end

--- Opens or closes (discarding) the mode.
function Keybind:Toggle()
    if self.active then
        self:Stop(false)
    else
        self:Start()
    end
end
