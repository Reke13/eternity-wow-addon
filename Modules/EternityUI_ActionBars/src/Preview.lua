-- The live preview of the Bars tab: the chosen bar's grid with buttons skinned like the real ones
-- (Style:Apply: shape, border, backdrop, zoom, inner shadow, gloss, tint...), showing the icons of
-- your first action slots.
---@type string, EternityUIActionBarsNamespace
local addonName, ns = ...
local E = EternityUI

local HEIGHT = 120
local PADDING = 10
local SLOTS = 12
local EMPTY_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local function opt(path)
    return E.store:Get(addonName, path)
end

-- The icon of an action slot, or the question mark for an empty one.
local function iconFor(slot)
    local texture = C_ActionBar and C_ActionBar.GetActionTexture and C_ActionBar.GetActionTexture(slot)
    if texture == nil or (issecretvalue and issecretvalue(texture)) then
        return EMPTY_ICON
    end
    return texture
end

-- A plain button with an icon: Style skins it as it skins the bars' buttons.
local function newButton(parent)
    local button = CreateFrame("Button", nil, parent)
    button:EnableMouse(false)
    button.icon = button:CreateTexture(nil, "BACKGROUND")
    button.icon:SetAllPoints()
    return button
end

--- Builds the preview frame for the options page.
---@param parent table
---@return table
function ns.Preview(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(HEIGHT)
    frame.shape = E.Shape.New(frame)
    frame.grid = CreateFrame("Frame", nil, frame)
    frame.grid:SetPoint("CENTER")
    frame.buttons = {}
    for i = 1, SLOTS do
        frame.buttons[i] = newButton(frame.grid)
    end

    function frame:Paint()
        local c = E.Theme.colors
        E.Shape.Paint(self.shape, math.min(E.Theme.radius, 8), c.surface, c.line)
        if self.id then
            self:Refresh(self.id)
        end
    end

    --- Draws a bar of the option group `id`.
    ---@param id string
    function frame:Refresh(id)
        self.id = id
        -- "All bars" has no count or grid of its own: a full row of 12.
        local count = math.min(opt(id .. ".buttons") or SLOTS, SLOTS)
        local perRow = math.max(math.min(opt(id .. ".perRow") or count, count), 1)
        local size = opt(id .. ".size") or 36
        local spacing = opt(id .. ".spacing") or 2
        local rows = math.ceil(count / perRow)
        local width = perRow * size + (perRow - 1) * spacing
        local height = rows * size + (rows - 1) * spacing
        self.grid:SetSize(width, height)
        -- A tall or wide bar shrinks to fit the box; it never grows past its real size.
        local room = self:GetWidth() > 0 and (self:GetWidth() - PADDING * 2) / width or 1
        self.grid:SetScale(math.min(1, room, (HEIGHT - PADDING * 2) / height))
        -- The bar's opacity, as the bar has it when it isn't fading on mouseover.
        self.grid:SetAlpha(opt(id .. ".alpha") or 1)
        for i, button in ipairs(self.buttons) do
            button:SetShown(i <= count)
            if i <= count then
                button.icon:SetTexture(iconFor(i))
                button.icon:Show()
                ns.Style:Apply(button, size)
                button:ClearAllPoints()
                local column, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
                button:SetPoint("TOPLEFT", column * (size + spacing), -row * (size + spacing))
            end
        end
    end

    return E.Widgets.Track(frame)
end
