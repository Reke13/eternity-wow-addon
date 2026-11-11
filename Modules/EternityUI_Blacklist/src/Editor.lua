-- The editor: one small window to add a player or change their entry. Name, faction, guild and
-- reason are written by hand; class, race and level are only shown, as the game told them.

---@type string, EternityUIBlacklistNamespace
local _, ns = ...
local E = EternityUI
local Widgets = E.Widgets
local L, List = ns.L, ns.List

local WIDTH = 420
local LABEL = 90
local ROW = 40
local CONFIRM_SECONDS = 4

---@class EternityUIBlacklistEditor
---@field frame table?
---@field oldName string? the name of the entry being edited; nil when adding
---@field info table? what was read of the unit when adding from it
local Editor = {}
ns.Editor = Editor

local function details(entry)
    local parts = {}
    if entry.level then
        parts[#parts + 1] = L.LEVEL:format(entry.level)
    end
    parts[#parts + 1] = entry.race
    parts[#parts + 1] = entry.className
    return table.concat(parts, " · ")
end

local function field(w, index, label, control)
    local text = Widgets.Text(w.body, 14, "muted")
    text:SetPoint("TOPLEFT", 14, -12 - (index - 1) * ROW - 8)
    text:SetText(label)
    control:SetPoint("TOPLEFT", 14 + LABEL, -12 - (index - 1) * ROW)
    return control
end

local function input(w, index, label, letters)
    local box = field(w, index, label, Widgets.Input(w.body))
    box:SetPoint("RIGHT", w.body, "RIGHT", -14, 0)
    box:SetMaxLetters(letters)
    return box
end

local function resetDelete()
    local w = Editor.frame
    w.confirming = false
    w.delete.label:SetText(L.DELETE)
end

local function message(text)
    local w = Editor.frame
    w.problem:SetText(text or "")
end

function Editor.Save()
    local w = Editor.frame
    local entry, problem = List.Save(Editor.oldName, {
        name = w.name:GetText(),
        faction = w.faction.value,
        guild = w.guild:GetText(),
        reason = w.reason:GetText(),
    })
    if problem == "name" then
        message(L.NAME_EMPTY)
        return
    elseif problem == "taken" then
        message(L.NAME_TAKEN:format(List.Clean(w.name:GetText()) or ""))
        return
    end
    if entry and Editor.info then
        List.Update(entry, Editor.info)
    end
    w:Hide()
end

local function delete()
    local w = Editor.frame
    if not w.confirming then
        w.confirming = true
        w.delete.label:SetText(L.DELETE_CONFIRM)
        C_Timer.After(CONFIRM_SECONDS, function()
            if w.confirming then
                resetDelete()
            end
        end)
        return
    end
    List.Remove(Editor.oldName)
    w:Hide()
end

local function create()
    local w = Widgets.Window("EternityUIBlacklistEditor", L.ADD_PLAYER, true)
    Editor.frame = w
    w:SetSize(WIDTH, 290)
    w:SetPoint("CENTER", 0, 80)
    w:SetFrameStrata("DIALOG")
    w:SetToplevel(true)
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        frame:SetUserPlaced(false)
    end)
    -- See the loot history: keys can't pass through a window opened in combat.
    w:HookScript("OnShow", function(frame)
        frame:EnableKeyboard(not InCombatLockdown())
    end)

    w.name = input(w, 1, L.NAME, 24)
    w.faction = field(
        w,
        2,
        L.FACTION,
        Widgets.Segmented(w.body, {
            { "", L.UNKNOWN },
            { "Horde", L.Horde },
            { "Alliance", L.Alliance },
        }, function() end)
    )
    w.guild = input(w, 3, L.GUILD, 48)
    w.reason = input(w, 4, L.REASON, 255)
    w.reason:SetScript("OnEnterPressed", function(box)
        box:ClearFocus()
        Editor.Save()
    end)
    w.name:SetScript("OnTabPressed", function()
        w.guild:SetFocus()
    end)
    w.guild:SetScript("OnTabPressed", function()
        w.reason:SetFocus()
    end)
    w.reason:SetScript("OnTabPressed", function()
        w.name:SetFocus()
    end)

    w.details = Widgets.Text(w.body, 13, "muted")
    w.details:SetPoint("TOPLEFT", 14 + LABEL, -12 - 4 * ROW - 4)
    w.problem = Widgets.Text(w.body, 13, "danger")
    w.problem:SetPoint("TOPLEFT", w.details, "BOTTOMLEFT", 0, -6)

    w.save = Widgets.Button(w.footer, L.SAVE, "primary", Editor.Save)
    w.save:SetHeight(28)
    w.save:SetPoint("RIGHT", -10, 0)
    w.delete = Widgets.Button(w.footer, L.DELETE, "danger", delete)
    w.delete:SetHeight(28)
    w.delete:SetPoint("LEFT", 10, 0)
end

--- Opens the editor. With an entry it edits it; otherwise it adds a player, filled from info.
---@param entry EternityUIBlacklistEntry?
---@param info table? what was read of the unit, or { name } only
function Editor.Open(entry, info)
    if not Editor.frame then
        create()
    end
    local w = Editor.frame
    Editor.oldName = entry and entry.name or nil
    Editor.info = info
    local source = entry or info or {}
    w.title:SetText(entry and L.EDIT_PLAYER or L.ADD_PLAYER)
    w.name:SetText(source.name or "")
    w.faction:SetValue(source.faction or "")
    w.guild:SetText(source.guild or "")
    w.reason:SetText(entry and entry.reason or "")
    w.details:SetText(details(source))
    w.delete:SetShown(entry ~= nil)
    resetDelete()
    message(nil)
    w:Show()
    w:Raise()
    if source.name then
        w.reason:SetFocus()
    else
        w.name:SetFocus()
    end
end

function Editor.Stop()
    if Editor.frame then
        Editor.frame:Hide()
    end
end
