-- Eternity's entry in Blizzard's addon compartment, the minimap's addon button. A failure here
-- leaves the rest of the addon working.
---@type string, EternityUINamespace
local _, ns = ...
local Events = ns.Events

local Integration = {}

local function register()
    if not ns.store:Get("EternityUI", "general.minimapEntry") then
        return
    end
    AddonCompartmentFrame:RegisterAddon({
        text = "Eternity",
        icon = "Interface\\Icons\\INV_Misc_Gear_01",
        notCheckable = true,
        func = function()
            EternityUI:ToggleOptions()
        end,
    })
end

Events.Listen(EternityUI.READY, Integration, function()
    local ok, err = pcall(register)
    if not ok then
        geterrorhandler()(err)
    end
end)
