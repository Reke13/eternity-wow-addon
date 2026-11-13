-- The module's "Content" tab in the options: every item the bar can show, in the bar's order,
-- each with its switch and arrows to move it. The order is kept in the "content.order" option
-- (ids separated by commas); ids it doesn't name go at the end, in the default order, so a new
-- item never gets lost.

---@type string, EternityUIInfoBarNamespace
local addonName, ns = ...
local E = EternityUI
local Theme, Widgets = E.Theme, E.Widgets
local L, opt = ns.L, ns.opt

local TAB = "content"
local ROW = 44
local GAP = 10
local ARROW = 28
-- Every item, in the default order.
local IDS = { "clock", "fps", "latency", "gold", "bags", "xp", "durability" }

---@class EternityUIInfoBarContentTab
---@field frame table? the tab's view, once the options built it
local Tab = { TAB = TAB, IDS = IDS, rows = {} }
ns.ContentTab = Tab

--- The option paths this tab sets (they leave General).
---@return string[]
function Tab.Paths()
    local paths = { "content.order" }
    for _, id in ipairs(IDS) do
        paths[#paths + 1] = "content." .. id
    end
    return paths
end

--- The items' ids in the chosen order: every known id once.
---@param text string? an order to read instead of the option's
---@return string[]
function Tab.Order(text)
    local known, seen, order = {}, {}, {}
    for _, id in ipairs(IDS) do
        known[id] = true
    end
    for id in tostring(text or opt("content.order") or ""):gmatch("[^,%s]+") do
        if known[id] and not seen[id] then
            seen[id] = true
            order[#order + 1] = id
        end
    end
    for _, id in ipairs(IDS) do
        if not seen[id] then
            order[#order + 1] = id
        end
    end
    return order
end

--- Moves an item one place up (-1) or down (1).
---@param id string
---@param step integer
function Tab.Move(id, step)
    local order = Tab.Order()
    for index, current in ipairs(order) do
        if current == id then
            local other = index + step
            if other >= 1 and other <= #order then
                order[index], order[other] = order[other], order[index]
                E.store:Set(addonName, "content.order", table.concat(order, ","))
            end
            break
        end
    end
    Tab.Refresh()
end

local function arrow(row, texture, tip, onClick)
    local button = CreateFrame("Button", nil, row)
    button:SetSize(ARROW, ARROW)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(16, 16)
    button.icon:SetPoint("CENTER")
    button.icon:SetTexture(texture)
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(1, 1, 1, 1)
    end)
    button:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(0.75, 0.75, 0.8, self:IsEnabled() and 1 or 0.3)
    end)
    Widgets.AttachTooltip(button, function(t)
        t:SetTitle(tip)
    end)
    return button
end

local function newRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW)
    row.up = arrow(row, "Interface\\Buttons\\Arrow-Up-Up", L.MOVE_UP, function()
        Tab.Move(row.id, -1)
    end)
    row.up:SetPoint("LEFT", 0, 0)
    row.down = arrow(row, "Interface\\Buttons\\Arrow-Down-Up", L.MOVE_DOWN, function()
        Tab.Move(row.id, 1)
    end)
    row.down:SetPoint("LEFT", row.up, "RIGHT", 2, 0)
    row.name = Widgets.Text(row, 14, "text")
    row.name:SetPoint("LEFT", row.down, "RIGHT", 12, 0)
    row.toggle = Widgets.Toggle(row, function(value)
        E.store:Set(addonName, "content." .. row.id, value)
        Tab.Refresh()
    end)
    row.toggle:SetPoint("RIGHT")
    local line = Widgets.Rect(row, Theme.colors.line)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    return row
end

local function setEnabled(button, enabled)
    button:SetEnabled(enabled)
    button.icon:SetVertexColor(0.75, 0.75, 0.8, enabled and 1 or 0.3)
end

--- Redraws the list in the current order.
function Tab.Refresh()
    local v = Tab.frame
    if not v then
        return
    end
    local order = Tab.Order()
    local top = GAP
    for i, id in ipairs(order) do
        local row = Tab.rows[i]
        if not row then
            row = newRow(v)
            Tab.rows[i] = row
        end
        row.id = id
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(top + (i - 1) * ROW))
        row:SetPoint("TOPRIGHT", 0, -(top + (i - 1) * ROW))
        row.name:SetText(L["ITEM_" .. id])
        local on = opt("content." .. id) and true or false
        row.toggle:SetValue(on)
        row.name:SetAlpha(on and 1 or 0.55)
        setEnabled(row.up, i > 1)
        setEnabled(row.down, i < #order)
        row:Show()
    end
    local height = top + #order * ROW + GAP
    v:SetHeight(height)
    v.setHeight(height)
end

--- Builds the tab (see definition.tabs in the options).
---@param parent table
---@param setHeight fun(height: number)
---@return table view
function Tab.Build(parent, setHeight)
    local v = CreateFrame("Frame", nil, parent)
    v:SetPoint("TOPLEFT")
    v:SetPoint("TOPRIGHT")
    v.setHeight = setHeight
    Tab.frame = v
    v:SetScript("OnShow", Tab.Refresh)
    v:SetScript("OnSizeChanged", Tab.Refresh)
    v.Refresh = Tab.Refresh
    Tab.Refresh()
    return v
end
