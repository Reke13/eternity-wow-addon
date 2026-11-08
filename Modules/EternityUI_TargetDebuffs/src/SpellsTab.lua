-- The module's "Spells" tab in the options: the player's list of spell IDs. Each one has its
-- switch, whether it shows whoever cast it or only when it's mine, and a button to take it out. IDs are typed
-- (several at once, separated by commas), a name is typed (all its ranks are looked for), picked
-- from the target's debuffs, or put in the box by
-- shift-clicking a spell anywhere (spellbook, action bar, a link in the chat) while it has the
-- cursor: the game hands that click to ChatFrameUtil.InsertLink, which we only follow.

---@type string, EternityUITargetDebuffsNamespace
local addonName, ns = ...
local E = EternityUI
local Theme, Widgets = E.Theme, E.Widgets
local L, Spells, Filters = ns.L, ns.Spells, ns.Filters

local TAB = "spells"
local ROW = 44
local ICON = 28
local GAP = 10
local BAR = 30
local UNKNOWN_ICON = 134400

---@class EternityUITargetDebuffsSpellsTab
---@field frame table? the tab's view, once the options built it
local Tab = { TAB = TAB, rows = {} }
ns.SpellsTab = Tab

local function say(text)
    local v = Tab.frame
    if v then
        v.status:SetText(text or "")
    end
end

--- Adds the IDs in a text ("7386, 11597"), or a spell by name when there's no ID in it; says
--- what happened.
---@param text string
function Tab.AddText(text)
    local ids, count, invalid = Filters.ParseIDs(text)
    if count == 0 and #invalid == 0 then
        return
    end
    if count == 0 then
        local name = tostring(text):gsub("^%s+", ""):gsub("%s+$", "")
        if Spells.AddName(name) then
            say(L.ADDED_NAME:format(name))
        else
            say(L.ALREADY_NAME:format(name))
        end
        if Tab.frame then
            Tab.frame.input:SetText("")
        end
        Tab.Refresh()
        return
    end
    local added, already = 0, 0
    local sorted = {}
    for id in pairs(ids) do
        sorted[#sorted + 1] = id
    end
    table.sort(sorted)
    for _, id in ipairs(sorted) do
        if Spells.Add(id) then
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
    if #invalid > 0 then
        parts[#parts + 1] = L.NOT_IDS:format(table.concat(invalid, ", "))
    end
    say(table.concat(parts, " · "))
    if Tab.frame then
        Tab.frame.input:SetText("")
    end
    Tab.Refresh()
end

--- The spell ID of a link ("|Hspell:7386:0|h[...]|h"), or nil.
---@param link string?
---@return integer?
function Tab.SpellIDFromLink(link)
    if type(link) ~= "string" or (issecretvalue ~= nil and issecretvalue(link)) then
        return nil
    end
    return tonumber(link:match("|Hspell:(%d+)") or link:match("^spell:(%d+)"))
end

--- A shift-clicked spell goes into the box when it has the cursor: its ID, after a comma when
--- there's text already.
---@param link string?
---@return boolean put
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
    -- After Blizzard's own handling: nothing of it is replaced.
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        hooksecurefunc(ChatFrameUtil, "InsertLink", Tab.OnInsertLink)
    elseif ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", Tab.OnInsertLink)
    end
end

-- "From the target": a menu with the target's debuffs, to add one.
local function targetMenu(owner)
    local debuffs = Spells.TargetDebuffs()
    local entries = {}
    if debuffs == nil then
        entries[1] = { text = L.FROM_TARGET_SECRET, onClick = function() end }
    elseif #debuffs == 0 then
        entries[1] = { text = UnitExists("target") and L.FROM_TARGET_NONE or L.FROM_TARGET_NO_TARGET, onClick = function() end }
    end
    for _, debuff in ipairs(debuffs or {}) do
        local icon = debuff.icon and ("|T" .. debuff.icon .. ":16:16:0:0:64:64:5:59:5:59|t ") or ""
        entries[#entries + 1] = {
            text = icon .. debuff.name .. "  |cff999999" .. debuff.id .. "|r",
            onClick = function()
                Tab.AddText(tostring(debuff.id))
            end,
        }
    end
    Widgets.Menu(owner, entries, 280)
end

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
        Spells.Remove(row.spell)
        Tab.Refresh()
    end)
    row.remove:SetHeight(26)
    row.remove:SetWidth(row.remove.label:GetStringWidth() + 24)
    row.remove:SetPoint("RIGHT")
    -- Name entries only: look for their IDs again.
    row.again = Widgets.Button(row, L.SEARCH_AGAIN, "ghost", function()
        Spells.SearchAgain(row.spell)
        Tab.Refresh()
    end)
    row.again:SetHeight(26)
    row.again:SetWidth(row.again.label:GetStringWidth() + 24)
    row.again:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)
    row.mode = Widgets.Segmented(row, { { "always", L.MODE_ALWAYS }, { "mine", L.MODE_MINE } }, function(value)
        Spells.SetMine(row.spell, value == "mine")
    end)
    row.mode.buttonHeight = 26
    row.toggle = Widgets.Toggle(row, function(value)
        Spells.SetEnabled(row.spell, value)
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

-- "7386, 7405, 8380 (+2)"
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
    row.spell, row.spellID = spell, spell.id
    local byName = spell.name ~= nil
    local first = spell.id or (spell.ids and spell.ids[1])
    local name, icon
    if first then
        name, icon = Spells.Info(first)
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

--- Redraws the list.
function Tab.Refresh()
    local v = Tab.frame
    if not v then
        return
    end
    local list = Spells.List()
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
    v.empty:SetShown(#list == 0)
    local listHeight = math.max(#list * ROW, 40)
    v.list:SetHeight(listHeight)
    local top = v.intro:GetStringHeight() + GAP + BAR + GAP + 16 + v.example:GetStringHeight() + GAP
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

    v.intro = Widgets.Text(v, 13, "muted")
    v.intro:SetPoint("TOPLEFT", 0, -GAP)
    v.intro:SetPoint("TOPRIGHT", 0, -GAP)
    v.intro:SetJustifyH("LEFT")
    v.intro:SetText(L.SPELLS_INTRO)

    v.input = Widgets.Input(v, Tab.AddText, L.SPELL_ID)
    hookLinks()
    v.input:SetHeight(BAR)
    v.input:SetWidth(240)
    v.input:SetPoint("TOPLEFT", v.intro, "BOTTOMLEFT", 0, -GAP)
    v.add = Widgets.Button(v, L.ADD, "primary", function()
        Tab.AddText(v.input:GetText())
    end)
    v.add:SetHeight(BAR)
    v.add:SetPoint("LEFT", v.input, "RIGHT", 8, 0)
    v.fromTarget = Widgets.Button(v, L.FROM_TARGET, "ghost", function(button)
        targetMenu(button)
    end)
    v.fromTarget:SetHeight(BAR)
    v.fromTarget:SetWidth(v.fromTarget.label:GetStringWidth() + 28)
    v.fromTarget:SetPoint("LEFT", v.add, "RIGHT", 8, 0)
    v.place = Widgets.Button(v, L.PLACE_FRAME, "ghost", function()
        E:ToggleMover()
    end)
    v.place:SetHeight(BAR)
    v.place:SetWidth(v.place.label:GetStringWidth() + 28)
    v.place:SetPoint("TOPRIGHT", v.intro, "BOTTOMRIGHT", 0, -GAP)

    v.status = Widgets.Text(v, 12, "muted")
    v.status:SetPoint("TOPLEFT", v.input, "BOTTOMLEFT", 0, -4)
    v.status:SetPoint("RIGHT")
    v.status:SetJustifyH("LEFT")
    v.example = Widgets.Text(v, 12, "muted")
    v.example:SetPoint("TOPLEFT", v.input, "BOTTOMLEFT", 0, -20)
    v.example:SetPoint("RIGHT")
    v.example:SetJustifyH("LEFT")
    v.example:SetText(L.SPELLS_EXAMPLE)

    v.list = CreateFrame("Frame", nil, v)
    v.empty = Widgets.Text(v.list, 13, "muted")
    v.empty:SetPoint("TOPLEFT", 0, -10)
    v.empty:SetText(L.NO_SPELLS)

    v:SetScript("OnShow", function()
        say("")
        Tab.Refresh()
    end)
    -- While a name is being looked for, how far it got.
    Spells.onProgress = function(entry, done)
        if v:IsVisible() then
            say(L.PROGRESS:format(entry.name, math.floor(done * 100)))
        end
    end
    v:SetScript("OnSizeChanged", Tab.Refresh)
    v.Refresh = Tab.Refresh
    Tab.Refresh()
    return v
end
