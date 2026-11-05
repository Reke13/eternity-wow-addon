-- EternityUI_Map: Blizzard's world map with the Eternity look (Skin.lua), player and cursor
-- coordinates (Coords.lua), scale and a remembered spot (Window.lua), fade while moving
-- (Fade.lua) and the unexplored areas (Unexplored.lua).
--
-- Replaces no Blizzard method: hooksecurefunc and HookScript only, installed once and doing
-- nothing while Core.running is false. Disabling the module (its page or the addon list) gives
-- Blizzard's map back as it was, without /reload: regions to their alpha, scale 1, Blizzard's
-- spot, its backdrop and its coordinates panel.

---@type string, EternityUIMapNamespace
local addonName, ns = ...
local E = EternityUI
local Core, L = ns.Core, ns.L

---@class EternityUIMapModule: EternityUIModuleDefinition
---@field events table?
local Module = {
    schema = ns.OptionsSchema,
    Core = Core,
    Skin = ns.Skin,
    Coords = ns.Coords,
    Window = ns.Window,
    Fade = ns.Fade,
    Unexplored = ns.Unexplored,
}
ns.Module = Module

--- Applies every part from the options (each one turns itself off when the module is off).
function Module:Apply()
    if not Core.Map() then
        ns.Coords:ApplyScreen()
        if not Core.running then
            return
        end
        -- Blizzard_WorldMap isn't loaded yet: wait for it.
        if not self.events then
            self.events = CreateFrame("Frame")
            self.events:SetScript("OnEvent", function(_, _, name)
                if name == "Blizzard_WorldMap" then
                    self.events:UnregisterEvent("ADDON_LOADED")
                    self:Apply()
                end
            end)
        end
        self.events:RegisterEvent("ADDON_LOADED")
        return
    end
    ns.Skin:Apply()
    ns.Window:Apply()
    ns.Fade:Apply()
    ns.Coords:Apply()
    ns.Unexplored:Apply()
end

function Module:OnEnable()
    Core.running = true
    self:Apply()
end

function Module:OnDisable()
    Core.running = false
    if self.events then
        self.events:UnregisterAllEvents()
    end
    self:Apply()
end

function Module:OnConfigChanged()
    if Core.running then
        self:Apply()
    end
end

_G.SLASH_ETERNITYMAP1 = "/etmap"
SlashCmdList.ETERNITYMAP = function(text)
    if not Core.running then
        return
    end
    if strtrim(text or ""):lower() == "reset" then
        ns.Window:Reset()
        Core.Print(L.RESET_DONE)
    else
        Core.Print(L.USAGE)
    end
end

E:RegisterModule(addonName, Module)
