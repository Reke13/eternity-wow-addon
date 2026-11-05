-- A stack of cast bars moved as one Mover element: the bosses (boss1-5) and the arena enemies
-- (arena1-5). Each bar is a normal Bar inside the group's container, so casts are read and drawn
-- exactly like the target's (secret-safe); the group only places them and previews all five.

---@type string, EternityUICastBarsNamespace
local addonName, ns = ...
local E = EternityUI
local Bar = ns.Bar

local COUNT = 5

---@class EternityUICastBarGroupDefinition
---@field name string container's global name (bars are <name>1..5)
---@field prefix string unit prefix: "boss" or "arena"
---@field label string Mover label
---@field barLabel string bar's preview label, "%d" = its number
---@field point string
---@field x number
---@field y number

---@class EternityUICastBarGroup
---@field kind string "boss" or "arena" (options use it: bars.<kind>, layout.<kind>Width...)
---@field key string Mover key
---@field definition EternityUICastBarGroupDefinition
---@field frame table container
---@field bars EternityUICastBar[]
---@field units table<string, EternityUICastBar>
---@field enabled boolean?
local Group = {}
Group.__index = Group
ns.Group = Group

local function opt(path)
    return E.store:Get(addonName, path)
end

---@param kind string
---@param definition EternityUICastBarGroupDefinition
---@return EternityUICastBarGroup
function Group.New(kind, definition)
    local self = setmetatable({
        kind = kind,
        key = addonName .. "." .. kind,
        definition = definition,
        bars = {},
        units = {},
    }, Group)
    local frame = CreateFrame("Frame", definition.name, UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:Hide()
    self.frame = frame
    for i = 1, COUNT do
        local unit = definition.prefix .. i
        local bar = Bar.New(unit, {
            name = definition.name .. i,
            label = definition.barLabel:format(i),
            parent = frame,
            size = kind,
        })
        self.bars[i] = bar
        self.units[unit] = bar
    end
    return self
end

--- Sizes each bar and stacks them from the group's top (grow down) or bottom (grow up).
function Group:ApplyLayout()
    local frame = self.frame
    local width, height = opt("layout." .. self.kind .. "Width"), opt("layout." .. self.kind .. "Height")
    local spacing = opt("groups.spacing")
    local up = opt("groups.grow") == "up"
    frame:SetScale(opt("layout.scale"))
    frame:SetSize(width, height * COUNT + spacing * (COUNT - 1))
    for i, bar in ipairs(self.bars) do
        bar:ApplyLayout()
        local offset = (i - 1) * (height + spacing)
        bar.frame:ClearAllPoints()
        if up then
            bar.frame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, offset)
        else
            bar.frame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -offset)
        end
    end
end

---@param on boolean
function Group:SetPreview(on)
    for _, bar in ipairs(self.bars) do
        bar:SetPreview(on)
    end
end

--- Shows each unit's current cast (force: hides the ones that aren't casting).
---@param force boolean?
function Group:Refresh(force)
    for _, bar in ipairs(self.bars) do
        bar:Refresh(force)
    end
end

--- One unit changed (an arena opponent seen or gone).
---@param unit string?
function Group:RefreshUnit(unit)
    local bar = unit and self.units[unit]
    if bar then
        bar:Refresh(true)
    end
end

function Group:Enable()
    if self.enabled then
        return
    end
    self.enabled = true
    self.frame:Show()
    self:ApplyLayout()
    for _, bar in ipairs(self.bars) do
        bar:Enable()
    end
    local definition = self.definition
    E.Mover.Register({
        key = self.key,
        owner = addonName,
        label = definition.label,
        frame = self.frame,
        point = definition.point,
        x = definition.x,
        y = definition.y,
    })
end

function Group:Disable()
    if not self.enabled then
        return
    end
    self.enabled = false
    for _, bar in ipairs(self.bars) do
        bar:Disable()
    end
    E.Mover.Unregister(self.key)
    self.frame:Hide()
end
