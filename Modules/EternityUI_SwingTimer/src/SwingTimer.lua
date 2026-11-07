-- EternityUI_SwingTimer: bars for the player's auto attacks in the spirit of WeaponSwingTimer. Bar
-- draws one and Swing runs all three from the game's own swing events. Disabling the module hides
-- the bars and gives Blizzard's back (the core releases what the Hider holds).

---@type string, EternityUISwingTimerNamespace
local addonName, ns = ...
local E = EternityUI
local Swing = ns.Swing

---@class EternityUISwingTimerModule: EternityUIModuleDefinition
---@field swing EternityUISwingTimerSwing? (created the first time it's enabled)
---@field running boolean?
local Module = { schema = ns.OptionsSchema }
ns.Module = Module

local function opt(path)
    return E.store:Get(addonName, path)
end

-- Hides Blizzard's bars or gives them back. The Hider waits for the end of combat if it must.
local function applyBlizzard(self)
    local hide = opt("display.hideBlizzard")
    for _, name in pairs(Swing.BLIZZARD) do
        local frame = _G[name]
        if frame and hide then
            E.Hider.Hide(frame, self)
        elseif frame then
            E.Hider.Restore(frame, self)
        end
    end
end

function Module:Apply()
    self.swing:ApplyLayout()
    applyBlizzard(self)
end

function Module:OnEnable()
    self.running = true
    self.swing = self.swing or Swing.New()
    self.swing:Enable()
    self.swing.previewing = E.MoverSession ~= nil and E.MoverSession.active or false
    -- Previews while the Mover is open; repaint on a theme change. The core releases both on disable.
    E.Events.Listen(E.Mover.TOGGLED, self, function(_, open)
        self.swing:SetPreview(open)
    end)
    E.Events.Listen(E.Theme.CHANGED, self, function()
        self:Apply()
    end)
    self:Apply()
end

function Module:OnDisable()
    self.running = false
    self.swing:Disable()
end

function Module:OnConfigChanged()
    if self.running then
        self:Apply()
    end
end

E:RegisterModule(addonName, Module)
