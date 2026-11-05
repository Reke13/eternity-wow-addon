-- Physical pixels. A UI unit is 768 / screen height of a pixel at scale 1, so a "1" border is
-- almost two pixels at 1440p. Anything meant to be N pixels asks here. Whether UIParent itself
-- changes scale is an option of the core, not something this file decides.
---@type string, EternityUINamespace
local _, ns = ...
local Events = ns.Events

---@class EternityPixel
local Pixel = {}
ns.Pixel = Pixel
EternityUI.Pixel = Pixel

Pixel.CHANGED = "ETERNITY_PIXEL_CHANGED"

--- The UIParent scale at which one UI unit is one physical pixel.
---@return number
function Pixel.PerfectScale()
    local _, height = GetPhysicalScreenSize()
    return 768 / height
end

--- UI units that one physical pixel measures inside this region.
---@param region table
---@return number
function Pixel.Size(region)
    return Pixel.PerfectScale() / region:GetEffectiveScale()
end

--- The value rounded to whole physical pixels of this region.
---@param value number
---@param region table
---@return number
function Pixel.Snap(value, region)
    local size = Pixel.Size(region)
    return math.floor(value / size + 0.5) * size
end

local function changed()
    Events.Send(Pixel.CHANGED)
end

local original -- UIParent's scale before the option changed it

--- Turns the optional pixel perfect scale of the whole interface on or off.
---@param enabled boolean
function Pixel.ApplyInterfaceScale(enabled)
    ns.Combat.Run(Pixel, function()
        if enabled then
            original = original or UIParent:GetScale()
            UIParent:SetScale(Pixel.PerfectScale())
        elseif original then
            UIParent:SetScale(original)
            original = nil
        end
        changed()
    end)
end

Events.On("UI_SCALE_CHANGED", Pixel, changed)
Events.On("DISPLAY_SIZE_CHANGED", Pixel, changed)
