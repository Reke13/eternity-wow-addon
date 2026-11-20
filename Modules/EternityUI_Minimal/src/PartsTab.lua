-- The Parts tab of the options: a switch per part, Eternity's and then Blizzard's. A change is
-- saved at once and, while the interface is hidden, the part hides or shows right away.
-- build(parent, setHeight) as the options' ModulePage wants it.

---@type string, EternityUIMinimalNamespace
local _, ns = ...
local E = EternityUI
local L, Parts = ns.L, ns.Parts
local Widgets = E.Widgets

local PartsTab = {}
ns.PartsTab = PartsTab

local ROW = 40
local HEADER = 34

function PartsTab.Build(parent, setHeight)
    local view = CreateFrame("Frame", nil, parent)
    view:SetPoint("TOPLEFT")
    view:SetPoint("TOPRIGHT")
    view.rows, view.headers = {}, {}

    local function header(index, text, y)
        local h = view.headers[index]
        if not h then
            h = Widgets.Text(view, 16, "accent")
            view.headers[index] = h
        end
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", 0, -y - 10)
        h:SetText(text)
        h:Show()
        return y + HEADER
    end

    local function row(index, part, y)
        local r = view.rows[index]
        if not r then
            local toggle = Widgets.Toggle(view, function(value)
                local current = view.rows[index].part
                if current then
                    ns.Module:SetPart(current.key, value)
                end
            end)
            r = Widgets.Row(view, "", toggle)
            r.toggle = toggle
            view.rows[index] = r
        end
        r.part = part
        r.label:SetText(part.label)
        r.toggle:SetValue(ns.Module:IsPicked(part.key))
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -y)
        r:SetPoint("TOPRIGHT", 0, -y)
        r:Show()
        return y + ROW
    end

    function view:Refresh()
        local y, used = 0, 0
        y = header(1, L.ETERNITY, y)
        local eternity = Parts.Eternity()
        for _, part in ipairs(eternity) do
            used = used + 1
            y = row(used, part, y)
        end
        if not self.empty then
            self.empty = Widgets.Text(self, 14, "muted")
        end
        self.empty:ClearAllPoints()
        self.empty:SetPoint("TOPLEFT", 0, -y - 8)
        self.empty:SetText(L.NO_PARTS)
        self.empty:SetShown(#eternity == 0)
        if #eternity == 0 then
            y = y + ROW
        end
        y = header(2, L.BLIZZARD, y)
        for _, part in ipairs(Parts.Blizzard()) do
            used = used + 1
            y = row(used, part, y)
        end
        local addons = Parts.Addons()
        if #addons > 0 then
            y = header(3, L.ADDONS, y)
            for _, part in ipairs(addons) do
                used = used + 1
                y = row(used, part, y)
            end
        elseif self.headers[3] then
            self.headers[3]:Hide()
        end
        for i = used + 1, #self.rows do
            self.rows[i].part = nil
            self.rows[i]:Hide()
        end
        self:SetHeight(y)
        setHeight(y)
    end

    view:SetScript("OnShow", view.Refresh)
    view:Refresh()
    return view
end
