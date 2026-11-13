-- The module's "Filters" tab: the player's buff filters (Filters.lua). On top, the filter being
-- edited (picked from a menu), with buttons to make a new one, rename it and delete it, and the
-- frames it applies to. Under that, its spells, edited as in the Auras module: IDs typed
-- (several at once), a name typed (all its ranks are looked for), picked from your buffs or your
-- target's, or put in the box by shift-clicking a spell anywhere while it has the cursor (the
-- game hands that click to ChatFrameUtil.InsertLink, which we only follow). Each spell has its
-- switch, whether it shows whoever cast it or only when it's yours, and a button to take it out.

---@type string, EternityUIUnitFramesNamespace
local addonName, ns = ...
local E = EternityUI
local Theme, Widgets = E.Theme, E.Widgets
local L, Filters, AuraBox = ns.L, ns.Filters, ns.AuraBox

local TAB = "filters"
local ROW = 44
local ICON = 28
local GAP = 10
local BAR = 30
local CHECK = 26
local UNKNOWN_ICON = 134400

---@class EternityUIUnitFramesFiltersTab
---@field frame table? the tab's view, once the options built it
---@field current integer? the id of the filter being edited
local Tab = { TAB = TAB, rows = {}, checks = {} }
ns.FiltersTab = Tab

--- The filter being edited (the first one if none was picked), or nil when there are none.
---@return EternityUIUnitFramesFilter?
function Tab.Filter()
    local filter = Filters.Get(Tab.current)
    if not filter then
        filter = Filters.All()[1]
        Tab.current = filter and filter.id or nil
    end
    return filter
end

local function say(text)
    if Tab.frame then
        Tab.frame.status:SetText(text or "")
    end
end

--- Edits another filter.
function Tab.Pick(id)
    Tab.current = id
    say("")
    Tab.Refresh()
end

--- Adds the IDs in a text ("1243, 21562"), or a spell by name when there's no ID in it.
---@param text string
function Tab.AddText(text)
    local filter = Tab.Filter()
    if not filter then
        return
    end
    local ids, count = AuraBox.ParseIDs(text)
    local invalid = {}
    for piece in tostring(text or ""):gmatch("[^,;%s]+") do
        if not tonumber(piece) then
            invalid[#invalid + 1] = piece
        end
    end
    if count == 0 and #invalid == 0 then
        return
    end
    if count == 0 then
        local name = tostring(text):gsub("^%s+", ""):gsub("%s+$", "")
        say(Filters.AddName(filter, name) and L.ADDED_NAME:format(name) or L.ALREADY_NAME:format(name))
    else
        local sorted, added, already = {}, 0, 0
        for id in pairs(ids) do
            sorted[#sorted + 1] = id
        end
        table.sort(sorted)
        for _, id in ipairs(sorted) do
            if Filters.Add(filter, id) then
                added = added + 1
            else
                already = already + 1
            end
        end
        local parts = {}
        if added > 0 then
            parts[#parts + 1] = L.ADDED:format(added)
        end
        if already > 0 then
            parts[#parts + 1] = L.ALREADY:format(already)
        end
        say(table.concat(parts, " · "))
    end
    if Tab.frame then
        Tab.frame.input:SetText("")
    end
    Tab.Refresh()
end

--- The spell ID of a link ("|Hspell:1243:0|h[...]|h"), or nil.
function Tab.SpellIDFromLink(link)
    if type(link) ~= "string" or (issecretvalue ~= nil and issecretvalue(link)) then
        return nil
    end
    return tonumber(link:match("|Hspell:(%d+)") or link:match("^spell:(%d+)"))
end

--- A shift-clicked spell goes into the box when it has the cursor.
function Tab.OnInsertLink(link)
    local v = Tab.frame
    local id = Tab.SpellIDFromLink(link)
    if not (v and id and v.input:IsVisible() and v.input:HasFocus()) then
        return false
    end
    local text = v.input:GetText():gsub("[,%s]+$", "")
    v.input:SetText(text == "" and tostring(id) or (text .. ", " .. id))
    v.input:SetCursorPosition(#v.input:GetText())
    return true
end

local hooked = false
local function hookLinks()
    if hooked then
        return
    end
    hooked = true
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        hooksecurefunc(ChatFrameUtil, "InsertLink", Tab.OnInsertLink)
    elseif ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", Tab.OnInsertLink)
    end
end

-- "Your buffs" / "Your target's": a menu with the unit's buffs, to add one.
local function aurasMenu(owner, unit)
    local auras = Filters.Auras(unit)
    local entries = {}
    if auras == nil then
        entries[1] = { text = L.FROM_SECRET, onClick = function() end }
    elseif #auras == 0 then
        entries[1] = { text = UnitExists(unit) and L.FROM_NONE or L.FROM_NO_TARGET, onClick = function() end }
    end
    for _, aura in ipairs(auras or {}) do
        local icon = aura.icon and ("|T" .. aura.icon .. ":16:16:0:0:64:64:5:59:5:59|t ") or ""
        entries[#entries + 1] = {
            text = icon .. aura.name .. "  |cff999999" .. aura.id .. "|r",
            onClick = function()
                Tab.AddText(tostring(aura.id))
            end,
        }
    end
    Widgets.Menu(owner, entries, 280)
end

-- The filter picker: every filter, and a new one.
local function filtersMenu(owner)
    local entries = {}
    for _, filter in ipairs(Filters.All()) do
        entries[#entries + 1] = {
            text = filter.name,
            onClick = function()
                Tab.Pick(filter.id)
            end,
        }
    end
    if #entries == 0 then
        entries[1] = { text = L.NO_FILTERS_SHORT, onClick = function() end }
    end
    Widgets.Menu(owner, entries, 240)
end

-- Rows ------------------------------------------------------------------------------------------

local function newRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.icon:SetPoint("LEFT", 0, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.name = Widgets.Text(row, 14, "text")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -1)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.id = Widgets.Text(row, 12, "muted")
    row.id:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, 1)
    row.remove = Widgets.Button(row, L.REMOVE, "ghost", function()
        Filters.Remove(Tab.Filter(), row.spell)
        Tab.Refresh()
    end)
    row.remove:SetHeight(26)
    row.remove:SetWidth(row.remove.label:GetStringWidth() + 24)
    row.remove:SetPoint("RIGHT")
    row.again = Widgets.Button(row, L.SEARCH_AGAIN, "ghost", function()
        Filters.SearchAgain(Tab.Filter(), row.spell)
        Tab.Refresh()
    end)
    row.again:SetHeight(26)
    row.again:SetWidth(row.again.label:GetStringWidth() + 24)
    row.again:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)
    row.mode = Widgets.Segmented(row, { { "always", L.MODE_ALWAYS }, { "mine", L.MODE_MINE } }, function(value)
        Filters.SetMine(Tab.Filter(), row.spell, value == "mine")
    end)
    row.mode.buttonHeight = 26
    row.toggle = Widgets.Toggle(row, function(value)
        Filters.SetEnabled(Tab.Filter(), row.spell, value)
        Tab.Refresh()
    end)
    row.toggle:SetPoint("RIGHT", row.mode, "LEFT", -12, 0)
    row.name:SetPoint("RIGHT", row.toggle, "LEFT", -10, 0)
    local line = Widgets.Rect(row, Theme.colors.line)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    return row
end

local function idList(ids)
    local shown = {}
    for i = 1, math.min(#ids, 4) do
        shown[i] = tostring(ids[i])
    end
    local text = table.concat(shown, ", ")
    if #ids > 4 then
        text = text .. " " .. L.MORE:format(#ids - 4)
    end
    return text
end

local function fillRow(row, spell)
    row.spell = spell
    local byName = spell.name ~= nil
    local first = spell.id or (spell.ids and spell.ids[1])
    local name, icon
    if first then
        name, icon = Filters.Info(first)
    end
    row.icon:SetTexture(icon or UNKNOWN_ICON)
    row.icon:SetDesaturated(not spell.enabled)
    if byName then
        local ids = spell.ids or {}
        row.name:SetText(spell.name)
        if spell.searching then
            row.id:SetText(L.SEARCHING:format(#ids))
        elseif #ids == 0 then
            row.id:SetText(L.NONE_FOUND)
        else
            row.id:SetText(L.BY_NAME:format(idList(ids)))
        end
    else
        row.name:SetText(name or L.UNKNOWN_SPELL)
        row.id:SetText(L.SPELL_ID_N:format(spell.id))
    end
    row.again:SetShown(byName and not spell.searching)
    row.mode:ClearAllPoints()
    row.mode:SetPoint("RIGHT", row.again:IsShown() and row.again or row.remove, "LEFT", -10, 0)
    row.toggle:SetValue(spell.enabled)
    row.mode:SetValue(spell.mine and "mine" or "always")
    row.mode:Paint()
    row:SetAlpha(spell.enabled and 1 or 0.55)
end

-- A frame's "apply to" switch with its name.
local function newCheck(parent, def)
    local check = CreateFrame("Frame", nil, parent)
    check:SetHeight(CHECK)
    check.toggle = Widgets.Toggle(check, function(value)
        local filter = Tab.Filter()
        if filter then
            Filters.SetFrame(filter, def.key, value)
        end
    end)
    check.toggle:SetPoint("LEFT")
    check.label = Widgets.Text(check, 13, "text")
    check.label:SetPoint("LEFT", check.toggle, "RIGHT", 8, 0)
    check.label:SetText(def.label)
    check:SetWidth(check.toggle:GetWidth() + 8 + check.label:GetStringWidth() + 18)
    check.def = def
    return check
end

-- Refresh -----------------------------------------------------------------------------------------

--- Redraws the tab for the filter being edited.
function Tab.Refresh()
    local v = Tab.frame
    if not v then
        return
    end
    local filter = Tab.Filter()
    local has = filter ~= nil
    v.picker.label:SetText(has and L.FILTER_PICK:format(filter.name) or L.NO_FILTERS_SHORT)
    v.picker:SetWidth(math.max(160, v.picker.label:GetStringWidth() + 28))
    for _, part in ipairs({ v.rename, v.renameButton, v.delete, v.applyLabel, v.input, v.add, v.fromMe, v.fromTarget, v.status, v.example, v.list }) do
        part:SetShown(has)
    end
    v.empty:SetShown(not has)
    if not has then
        local height = GAP + BAR + GAP + v.empty:GetStringHeight() + GAP
        v:SetHeight(height)
        v.setHeight(height)
        return
    end
    if not v.rename:HasFocus() then
        v.rename:SetText(filter.name)
    end

    -- "Apply to": the frames' switches, wrapped to the width.
    local width = math.max(v:GetWidth(), 300)
    local x, y = 0, GAP + BAR + GAP + BAR + GAP + 18
    for _, check in ipairs(Tab.checks) do
        check.toggle:SetValue(filter.frames[check.def.key] and true or false)
        if x > 0 and x + check:GetWidth() > width then
            x, y = 0, y + CHECK + 4
        end
        check:ClearAllPoints()
        check:SetPoint("TOPLEFT", x, -y)
        check:Show()
        x = x + check:GetWidth()
    end
    local top = y + CHECK + GAP

    v.input:ClearAllPoints()
    v.input:SetPoint("TOPLEFT", 0, -top)
    top = top + BAR + GAP + 16 + v.example:GetStringHeight() + GAP

    local list = filter.spells
    for i, spell in ipairs(list) do
        local row = Tab.rows[i]
        if not row then
            row = newRow(v.list)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
            row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW)
            Tab.rows[i] = row
        end
        fillRow(row, spell)
        row:Show()
    end
    for i = #list + 1, #Tab.rows do
        Tab.rows[i]:Hide()
    end
    v.none:SetShown(#list == 0)
    local listHeight = math.max(#list * ROW, 40)
    v.list:SetHeight(listHeight)
    v.list:ClearAllPoints()
    v.list:SetPoint("TOPLEFT", 0, -top)
    v.list:SetPoint("TOPRIGHT", 0, -top)
    local height = top + listHeight + GAP
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

    -- The filter being edited, new, rename, delete.
    v.picker = Widgets.Button(v, "", "ghost", function(button)
        filtersMenu(button)
    end)
    v.picker:SetHeight(BAR)
    v.picker:SetPoint("TOPLEFT", 0, -GAP)
    v.new = Widgets.Button(v, L.FILTER_NEW, "primary", function()
        local filter = Filters.Create(L.FILTER_DEFAULT)
        Tab.Pick(filter.id)
        say(L.FILTER_MADE:format(filter.name))
    end)
    v.new:SetHeight(BAR)
    v.new:SetPoint("LEFT", v.picker, "RIGHT", 8, 0)
    v.delete = Widgets.Button(v, L.FILTER_DELETE, "danger", function(button)
        local filter = Tab.Filter()
        if not filter then
            return
        end
        -- A second click within a few seconds deletes it.
        if button.armed then
            button.armed = nil
            button.label:SetText(L.FILTER_DELETE)
            Filters.Delete(filter)
            Tab.current = nil
            say(L.FILTER_DELETED:format(filter.name))
            Tab.Refresh()
        else
            button.armed = true
            button.label:SetText(L.FILTER_DELETE_SURE)
            C_Timer.After(4, function()
                if button.armed then
                    button.armed = nil
                    button.label:SetText(L.FILTER_DELETE)
                end
            end)
        end
    end)
    v.delete:SetHeight(BAR)
    v.delete:SetPoint("TOPRIGHT", 0, -GAP)

    v.rename = Widgets.Input(v, function(text)
        local filter = Tab.Filter()
        if filter then
            Filters.Rename(filter, text)
            Tab.Refresh()
        end
    end, L.FILTER_NAME)
    v.rename:SetHeight(BAR)
    v.rename:SetWidth(240)
    v.rename:SetMaxLetters(40)
    v.rename:SetPoint("TOPLEFT", 0, -(GAP + BAR + GAP))
    v.renameButton = Widgets.Button(v, L.FILTER_RENAME, "ghost", function()
        local filter = Tab.Filter()
        if filter then
            Filters.Rename(filter, v.rename:GetText())
            v.rename:ClearFocus()
            Tab.Refresh()
        end
    end)
    v.renameButton:SetHeight(BAR)
    v.renameButton:SetPoint("LEFT", v.rename, "RIGHT", 8, 0)

    v.applyLabel = Widgets.Text(v, 13, "muted")
    v.applyLabel:SetPoint("TOPLEFT", 0, -(GAP + BAR + GAP + BAR + GAP))
    v.applyLabel:SetText(L.FILTER_APPLY)
    for _, def in ipairs(ns.UNITS) do
        Tab.checks[#Tab.checks + 1] = newCheck(v, def)
    end

    v.input = Widgets.Input(v, Tab.AddText, L.SPELL_ID)
    hookLinks()
    v.input:SetHeight(BAR)
    v.input:SetWidth(240)
    v.add = Widgets.Button(v, L.ADD, "primary", function()
        Tab.AddText(v.input:GetText())
    end)
    v.add:SetHeight(BAR)
    v.add:SetPoint("LEFT", v.input, "RIGHT", 8, 0)
    v.fromMe = Widgets.Button(v, L.FROM_ME, "ghost", function(button)
        aurasMenu(button, "player")
    end)
    v.fromMe:SetHeight(BAR)
    v.fromMe:SetPoint("LEFT", v.add, "RIGHT", 8, 0)
    v.fromTarget = Widgets.Button(v, L.FROM_TARGET, "ghost", function(button)
        aurasMenu(button, "target")
    end)
    v.fromTarget:SetHeight(BAR)
    v.fromTarget:SetPoint("LEFT", v.fromMe, "RIGHT", 8, 0)

    v.status = Widgets.Text(v, 12, "muted")
    v.status:SetPoint("TOPLEFT", v.input, "BOTTOMLEFT", 0, -4)
    v.status:SetPoint("RIGHT")
    v.status:SetJustifyH("LEFT")
    v.example = Widgets.Text(v, 12, "muted")
    v.example:SetPoint("TOPLEFT", v.input, "BOTTOMLEFT", 0, -20)
    v.example:SetPoint("RIGHT")
    v.example:SetJustifyH("LEFT")
    v.example:SetText(L.FILTER_EXAMPLE)

    v.list = CreateFrame("Frame", nil, v)
    v.none = Widgets.Text(v.list, 13, "muted")
    v.none:SetPoint("TOPLEFT", 0, -10)
    v.none:SetText(L.FILTER_EMPTY)

    v.empty = Widgets.Text(v, 13, "muted")
    v.empty:SetPoint("TOPLEFT", 0, -(GAP + BAR + GAP))
    v.empty:SetPoint("RIGHT")
    v.empty:SetJustifyH("LEFT")
    v.empty:SetText(L.NO_FILTERS)

    v:SetScript("OnShow", function()
        say("")
        Tab.Refresh()
    end)
    Filters.onProgress = function(filter, entry, done)
        if v:IsVisible() and filter == Tab.Filter() then
            say(L.PROGRESS:format(entry.name, math.floor(done * 100)))
            Tab.Refresh()
        end
    end
    v:SetScript("OnSizeChanged", Tab.Refresh)
    v.Refresh = Tab.Refresh
    Tab.Refresh()
    return v
end
