-- The Mover: modules register the frames they own and the core owns their position. A position
-- is an entry { point, x, y, locked, scale } saved in the profile's layout: the frame's point on
-- the same point of UIParent. Only registered frames are touched, so Blizzard's Edit Mode is left
-- alone. Protected frames wait for the end of combat.
-- scale multiplies whatever scale the module gives its frame (its own Scale option, say): the
-- module keeps calling SetScale as before and the Mover puts its factor back on top.
---@type string, EternityUINamespace
local _, ns = ...
local Events = ns.Events
local Geometry = ns.MoverGeometry

---@class EternityMoverElement
---@field key string unique, e.g. "Chat.window"
---@field label string localized name
---@field frame table
---@field owner string? module name
---@field point string? default point, "CENTER" if omitted
---@field x number? default offset
---@field y number?
---@field openOptions fun()? opens this element's options
---@field scalable boolean? false: the Mover doesn't offer to resize it (an anchor, say)

---@class EternityMover
local Mover = { elements = {} }
ns.Mover = Mover
EternityUI.Mover = Mover

-- Sent with (open) when Mover mode opens or closes: modules show what they normally hide.
Mover.TOGGLED = "ETERNITY_MOVER_TOGGLED"

Mover.MIN_SCALE, Mover.MAX_SCALE = 0.5, 2.5

-- Scale factors: frame -> { base = the module's own scale, factor = the Mover's }.
local scaled = setmetatable({}, { __mode = "k" })

local function applyScale(frame)
    local state = scaled[frame]
    state.busy = true
    frame:SetScale(state.base * state.factor)
    state.busy = false
end

-- Applies the factor of an element; the first time it hooks SetScale to learn the module's scale.
local function setFactor(element, factor)
    local frame = element.frame
    local state = scaled[frame]
    if not state then
        if factor == 1 or element.scalable == false then
            return
        end
        state = { base = frame:GetScale(), factor = 1 }
        scaled[frame] = state
        hooksecurefunc(frame, "SetScale", function(self, value)
            local s = scaled[self]
            if s and not s.busy then
                s.base = value
                if s.factor ~= 1 then
                    ns.Combat.Run(s, function()
                        applyScale(self)
                    end)
                end
            end
        end)
    end
    if state.factor ~= factor then
        state.factor = factor
        applyScale(frame)
    end
end

--- True if the element can be resized from the Mover.
---@param key string
---@return boolean
function Mover.IsScalable(key)
    local element = Mover.elements[key]
    return element ~= nil and element.scalable ~= false
end

local function defaultEntry(element)
    return { point = element.point or "CENTER", x = element.x or 0, y = element.y or 0 }
end

--- The element's position in a layout (the saved one by default); nil if it isn't registered.
---@param key string
---@param layout table?
---@return table?
function Mover.Entry(key, layout)
    local element = Mover.elements[key]
    if not element then
        return nil
    end
    layout = layout or ns.store:GetProfile().layout
    return layout[key] or defaultEntry(element)
end

-- How much bigger one unit of the frame is than one unit of UIParent.
local function relativeScale(frame)
    return frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

--- The element's rect in UIParent units for a position.
---@param element EternityMoverElement
---@param entry table
---@return table
function Mover.Rect(element, entry)
    local scale = relativeScale(element.frame)
    local width, height = element.frame:GetWidth() * scale, element.frame:GetHeight() * scale
    return Geometry.RectFromFree(entry, width, height, UIParent:GetWidth(), UIParent:GetHeight())
end

--- Puts an element's frame on a position.
---@param element EternityMoverElement
---@param entry table
function Mover.Place(element, entry)
    ns.Combat.Run(element.frame, function()
        setFactor(element, element.scalable ~= false and entry.scale or 1)
        local scale = relativeScale(element.frame)
        element.frame:ClearAllPoints()
        element.frame:SetPoint(entry.point, UIParent, entry.point, entry.x / scale, entry.y / scale)
    end)
end

--- Places every element from a layout (the saved one by default).
---@param layout table?
function Mover.ApplyAll(layout)
    for key, element in pairs(Mover.elements) do
        Mover.Place(element, Mover.Entry(key, layout))
    end
end

--- Registers a frame. Returns false if the key is taken.
---@param element EternityMoverElement
---@return boolean
function Mover.Register(element)
    if Mover.elements[element.key] then
        return false
    end
    Mover.elements[element.key] = element
    if ns.store then
        Mover.Place(element, Mover.Entry(element.key))
    end
    return true
end

--- Forgets an element. Its frame stays where it is.
---@param key string
function Mover.Unregister(key)
    Mover.elements[key] = nil
end

--- Forgets every element of a module.
---@param owner string
function Mover.ReleaseOwner(owner)
    for key, element in pairs(Mover.elements) do
        if element.owner == owner then
            Mover.elements[key] = nil
        end
    end
end

--- The elements sorted by label.
---@return EternityMoverElement[]
function Mover.List()
    local list = {}
    for _, element in pairs(Mover.elements) do
        list[#list + 1] = element
    end
    table.sort(list, function(a, b)
        return a.label < b.label
    end)
    return list
end

--- A copy of the saved layout.
---@return table
function Mover.Layout()
    return ns.DeepCopy(ns.store:GetProfile().layout)
end

--- Saves a whole layout into the profile and applies it.
---@param layout table
function Mover.Save(layout)
    ns.store:ReplaceLayout(layout)
    Mover.ApplyAll()
end

--- Saves where a frame the player dragged by itself is now.
---@param key string
function Mover.SaveFromFrame(key)
    local element = Mover.elements[key]
    local left, bottom = element and element.frame:GetLeft(), element and element.frame:GetBottom()
    if not left or not bottom then
        return
    end
    local scale = relativeScale(element.frame)
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    local rect = {
        l = left * scale,
        b = bottom * scale,
        w = element.frame:GetWidth() * scale,
        h = element.frame:GetHeight() * scale,
    }
    local entry = Geometry.FreeFromRect(Mover.Entry(key).point, Geometry.Clamp(rect, width, height), width, height)
    entry.locked = Mover.Entry(key).locked
    entry.scale = Mover.Entry(key).scale
    ns.store:SetLayout(key, entry)
    Mover.Place(element, entry)
end

Events.Listen(EternityUI.READY, Mover, function()
    Mover.ApplyAll()
end)
Events.Listen(ns.CONFIG_CHANGED, Mover, function(_, _, path)
    if path == "@profile" then
        Mover.ApplyAll()
    end
end)
