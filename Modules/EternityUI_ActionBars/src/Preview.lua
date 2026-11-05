-- The live preview of the Bars tab: the chosen bar's grid and button shape, with plain slots.
---@type string, EternityUIActionBarsNamespace
local addonName, ns = ...
local E = EternityUI

local HEIGHT = 120
local PADDING = 10
local SLOTS = 12
local SHAPES = { rounded = "rounded", circle = "circle", diamond = "diamond", hexagon = "hexagon" }

local function opt(path)
    return E.store:Get(addonName, path)
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
    frame.slots = {}
    for i = 1, SLOTS do
        frame.slots[i] = frame.grid:CreateTexture(nil, "ARTWORK")
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
        local count = math.min(opt(id .. ".buttons") or 8, SLOTS)
        local perRow = math.max(math.min(opt(id .. ".perRow") or count, count), 1)
        local size = opt(id .. ".size") or 36
        local spacing = opt(id .. ".spacing") or 2
        local rows = math.ceil(count / perRow)
        local shape = SHAPES[opt("buttons.shape")]
        local r, g, b = E.Theme.Color("accent")
        local width = perRow * size + (perRow - 1) * spacing
        local height = rows * size + (rows - 1) * spacing
        self.grid:SetSize(width, height)
        -- A tall or wide bar shrinks to fit the box; it never grows past its real size.
        local room = self:GetWidth() > 0 and (self:GetWidth() - PADDING * 2) / width or 1
        self.grid:SetScale(math.min(1, room, (HEIGHT - PADDING * 2) / height))
        for i, slot in ipairs(self.slots) do
            slot:SetShown(i <= count)
            if i <= count then
                if shape then
                    slot:SetTexture(E.Theme.MEDIA .. shape .. ".tga")
                    slot:SetVertexColor(r, g, b, 0.75)
                else
                    slot:SetColorTexture(r, g, b, 0.75)
                end
                slot:SetSize(size, size)
                slot:ClearAllPoints()
                local column, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
                slot:SetPoint("TOPLEFT", column * (size + spacing), -row * (size + spacing))
            end
        end
    end

    return E.Widgets.Track(frame)
end
