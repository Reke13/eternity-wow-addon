-- Blizzard's side: hides its action bars (moved to a hidden frame and back, out of combat) and points
-- the keys bound to its action buttons at ours with override bindings. The vehicle leave button lives
-- on the main bar, so it moves to UIParent while that bar is hidden. Override and possess bars are
-- only hidden while bar 1 shows those actions itself.

---@type string, EternityUIActionBarsNamespace
local addonName, ns = ...
local E = EternityUI
local Bars = ns.Bars

---@class EternityUIActionBarsBlizzard
---@field hidden table<table, boolean> Blizzard frames we keep hidden
local Blizzard = { hidden = {} }
ns.Blizzard = Blizzard

local BARS = {
    "MainActionBar",
    "MainMenuBar",
    "MultiBarBottomLeft",
    "MultiBarBottomRight",
    "MultiBarLeft",
    "MultiBarRight",
    "MultiBar5",
    "MultiBar6",
    "MultiBar7",
    "StanceBar",
    "PetActionBar",
}
local VEHICLE = { "OverrideActionBar", "PossessActionBar" }

local function opt(path)
    return E.store:Get(addonName, path)
end

local owner = CreateFrame("Frame")
Blizzard.owner = owner

local function hide(self, frame, wanted)
    wanted[frame] = true
    if not self.hidden[frame] then
        self.hidden[frame] = true
        E.Hider.Hide(frame, addonName)
    end
end

--- Hides the Blizzard bars the options ask for and gives back the rest (out of combat).
---@param active boolean? false gives them all back
function Blizzard:Apply(active)
    local wanted = {}
    if active and opt("general.hideBlizzard") then
        for _, name in ipairs(BARS) do
            local frame = _G[name]
            if frame then
                hide(self, frame, wanted)
            end
        end
        if opt("bar1.enabled") and opt("bar1.vehicle") then
            for _, name in ipairs(VEHICLE) do
                local frame = _G[name]
                if frame then
                    hide(self, frame, wanted)
                end
            end
        end
    end
    for frame in pairs(self.hidden) do
        if not wanted[frame] then
            self.hidden[frame] = nil
            E.Hider.Restore(frame, addonName)
        end
    end

    local leave = _G.MainMenuBarVehicleLeaveButton
    if leave then
        local main = _G.MainActionBar
        if main and self.hidden[main] then
            self.leaveParent = self.leaveParent or leave:GetParent()
            leave:SetParent(UIParent)
        elseif self.leaveParent then
            leave:SetParent(self.leaveParent)
            self.leaveParent = nil
        end
    end
end

--- Binds the keys of Blizzard's action buttons to ours (bars shown only), or frees them.
---@param active boolean?
function Blizzard:ApplyBindings(active)
    ClearOverrideBindings(owner)
    if not active or not opt("general.bindings") then
        return
    end
    for _, bar in ipairs(Bars.LIST) do
        if bar.binding and bar.frame and opt(bar.id .. ".enabled") then
            local count = math.min(opt(bar.id .. ".buttons"), #bar.buttons)
            for i = 1, count do
                local keys = { GetBindingKey(bar.binding .. i) }
                for _, key in ipairs(keys) do
                    SetOverrideBindingClick(owner, false, key, bar.buttons[i]:GetName(), "Keybind")
                end
            end
        end
    end
end
