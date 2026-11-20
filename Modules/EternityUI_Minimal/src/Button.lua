-- The eye on screen (a Mover element) and the key. The eye is a plain button: left-click
-- toggles, right-click opens the options. The key is an override binding that clicks a hidden
-- named button (registered for key down, so one press toggles once); bindings can't change in
-- combat, so that waits for the end of it.

---@type string, EternityUIMinimalNamespace
local addonName, ns = ...
local E = EternityUI
local L, Parts = ns.L, ns.Parts
local Shape, Theme, Widgets = E.Shape, E.Theme, E.Widgets

local Button = {}
ns.Button = Button

local SIZE = 26
local ICON = "Interface\\Icons\\INV_Misc_Eye_01"

local function paint(frame, hidden)
    Shape.Paint(frame.shape, math.min(Theme.radius, SIZE / 2), Theme.colors.raised, Theme.colors.line)
    frame.icon:SetDesaturated(hidden)
    frame.icon:SetAlpha(hidden and 0.55 or 1)
end

--- Creates the eye (once) and the key's target. onToggle() runs on a left-click or the key.
---@param onToggle fun()
function Button.Create(onToggle)
    if Button.frame then
        return
    end
    local frame = CreateFrame("Button", nil, UIParent)
    frame:SetSize(SIZE, SIZE)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(50)
    frame:SetClampedToScreen(true)
    frame.shape = Shape.New(frame)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetTexture(ICON)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.icon:SetPoint("TOPLEFT", 4, -4)
    frame.icon:SetPoint("BOTTOMRIGHT", -4, 4)
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            E:OpenOptions(addonName)
        else
            onToggle()
        end
    end)
    Widgets.AttachTooltip(frame, function(tip)
        tip:SetTitle(L.TITLE)
        tip:AddLine(Button.hidden and L.TIP_SHOW or L.TIP_HIDE)
        tip:AddHint(L.TIP_OPTIONS)
    end)
    frame:Hide()
    Button.frame = frame

    -- The key's target: hidden, named for SetOverrideBindingClick.
    local key = CreateFrame("Button", "EternityUIMinimalToggle", UIParent)
    key:RegisterForClicks("AnyDown")
    key:SetScript("OnClick", function()
        onToggle()
    end)
    key:Hide()
    Button.keyTarget = key
end

--- Shows or hides the eye and registers it with the Mover.
---@param shown boolean
function Button.SetShown(shown)
    local frame = Button.frame
    if shown and not E.Mover.elements[Parts.OWN_KEY] then
        E.Mover.Register({
            key = Parts.OWN_KEY,
            owner = addonName,
            label = L.MOVER,
            frame = frame,
            point = "TOPRIGHT",
            x = -260,
            y = -6,
        })
    elseif not shown then
        E.Mover.Unregister(Parts.OWN_KEY)
    end
    frame:SetShown(shown)
end

--- Paints the eye for the hidden state.
---@param hidden boolean
function Button.SetState(hidden)
    Button.hidden = hidden
    if Button.frame then
        paint(Button.frame, hidden)
    end
end

--- Binds the key (or clears it). Waits for the end of combat.
---@param key string? "" or nil clears it
function Button.Bind(key)
    E.Combat.Run(Button, function()
        ClearOverrideBindings(Button.keyTarget)
        key = key and strtrim(key):upper() or ""
        if key == "" then
            return
        end
        local ok = pcall(SetOverrideBindingClick, Button.keyTarget, true, key, "EternityUIMinimalToggle", "LeftButton")
        if not ok then
            print(L.BAD_KEY:format(key))
        end
    end)
end
