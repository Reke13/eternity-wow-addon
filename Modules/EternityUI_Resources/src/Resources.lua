-- EternityUI_Resources: a customizable bar for the player's power that follows the druid's forms,
-- combo points as pips and the druid's mana while shapeshifted. Display runs the parts and Power
-- reads the game without touching a secret. It changes nothing of Blizzard's, so disabling it only
-- hides its own frames (the core releases the Mover elements and listeners).

---@type string, EternityUIResourcesNamespace
local addonName, ns = ...
local E = EternityUI
local Display = ns.Display

---@class EternityUIResourcesModule: EternityUIModuleDefinition
---@field display EternityUIResourcesDisplay? (created the first time it's enabled)
---@field running boolean?
local Module = { schema = ns.OptionsSchema }
ns.Module = Module

function Module:Apply()
    self.display:ApplyLayout()
end

function Module:OnEnable()
    self.running = true
    self.display = self.display or Display.New()
    self.display:Enable()
    self.display.previewing = E.MoverSession ~= nil and E.MoverSession.active or false
    -- Previews while the Mover is open; repaint on a theme change. The core releases both on disable.
    E.Events.Listen(E.Mover.TOGGLED, self, function(_, open)
        self.display:SetPreview(open)
    end)
    E.Events.Listen(E.Theme.CHANGED, self, function()
        self:Apply()
    end)
    self:Apply()
end

function Module:OnDisable()
    self.running = false
    self.display:Disable()
end

function Module:OnConfigChanged()
    if self.running then
        self:Apply()
    end
end

E:RegisterModule(addonName, Module)
