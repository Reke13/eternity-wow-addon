-- The bars in the core's Mover: every enabled bar with buttons is an element, and protected bars
-- wait for the end of combat to move. While Mover mode is open the bars show even if they'd be
-- hidden or faded (Bars.unlocked), and an element's options open that bar in the Bars tab.

---@type string, EternityUIActionBarsNamespace
local addonName, ns = ...
local E = EternityUI
local Bars = ns.Bars

---@class EternityUIActionBarsMover
local Mover = {}
ns.Mover = Mover

-- Default position of each bar: its fixed point (the bar grows away from it) and the offset
-- from the same point of the screen, in UIParent units.
Mover.DEFAULTS = {
    bar1 = { "BOTTOM", 0, 14 },
    bar2 = { "BOTTOM", 0, 58 },
    bar3 = { "BOTTOM", 0, 102 },
    bar4 = { "RIGHT", -8, 0 },
    bar5 = { "RIGHT", -52, 0 },
    bar6 = { "CENTER", 0, -120 },
    bar7 = { "CENTER", 0, -164 },
    bar8 = { "CENTER", 0, -208 },
    stance = { "BOTTOM", -150, 146 },
    pet = { "BOTTOM", 150, 146 },
    micro = { "BOTTOMRIGHT", -4, 4 },
    bags = { "BOTTOMRIGHT", -4, 48 },
    totem = { "BOTTOM", 0, 190 },
    extra = { "BOTTOM", 0, 250 },
}

local function opt(path)
    return E.store:Get(addonName, path)
end

-- The bar's localized name (its option group label).
local function label(bar)
    for _, group in ipairs(ns.OptionsSchema.groups) do
        if group.id == bar.id then
            return E.Localize(group.label)
        end
    end
    return bar.id
end

---@param bar EternityUIActionBarsBar
function Mover.Key(bar)
    return addonName .. "." .. bar.id
end

--- Registers the bars in use and unregisters the rest.
function Mover:Sync()
    for _, bar in ipairs(Bars.LIST) do
        local key = Mover.Key(bar)
        local wanted = Bars.running and bar.frame and opt(bar.id .. ".enabled") and Bars.Count(bar) > 0
        if wanted and not E.Mover.elements[key] then
            local default = Mover.DEFAULTS[bar.id] or { "CENTER", 0, 0 }
            E.Mover.Register({
                key = key,
                owner = addonName,
                label = label(bar),
                frame = bar.frame,
                point = default[1],
                x = default[2],
                y = default[3],
                openOptions = function()
                    E:OpenOptions(addonName, "bars", bar.id)
                end,
            })
        elseif not wanted then
            E.Mover.Unregister(key)
        end
    end
end

--- Mover mode opened or closed: the bars show for placing them (rebuilt out of combat).
---@param open boolean
function Mover:OnMoverToggled(open)
    if Bars.unlocked == open then
        return
    end
    Bars.unlocked = open
    if Bars.running then
        ns.Module:Apply()
    end
end
