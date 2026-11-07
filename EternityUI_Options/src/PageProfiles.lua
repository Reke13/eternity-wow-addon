-- Profiles: which one this character uses, new ones, and sharing them as text.
---@type string, table
local _, ns = ...
local L = ns.L
local E = EternityUI
local Widgets = E.Widgets

local rows = {}
local list, nameBox, shareBox, message

local function report(err)
    message:SetText(err and L.IMPORT_FAILED:format(err) or "")
end

local function row(index)
    if rows[index] then
        return rows[index]
    end
    local entry = {}
    entry.use = Widgets.Button(list, L.USE, "ghost", function()
        E.store:UseProfile(entry.name)
    end)
    entry.remove = Widgets.Button(list, L.DELETE, "danger", function()
        E.store:DeleteProfile(entry.name)
        ns.Window.Refresh()
    end)
    entry.frame = Widgets.Row(list, "", entry.use)
    entry.remove:SetParent(entry.frame)
    entry.remove:SetPoint("RIGHT", entry.use, "LEFT", -8, 0)
    entry.frame:SetPoint("TOPLEFT", 0, -(index - 1) * 40)
    entry.frame:SetPoint("TOPRIGHT", 0, -(index - 1) * 40)
    rows[index] = entry
    return entry
end

local function refresh()
    local active = E.store:GetProfileName()
    local names = E.store:ListProfiles()
    for i, name in ipairs(names) do
        local entry = row(i)
        entry.name = name
        entry.frame.label:SetText(name == active and (name .. "  ·  " .. L.IN_USE) or name)
        entry.use:SetShown(name ~= active)
        entry.remove:SetShown(name ~= E.store.DEFAULT_PROFILE)
        entry.frame:Show()
    end
    for i = #names + 1, #rows do
        rows[i].frame:Hide()
    end
    list:SetHeight(math.max(#names, 1) * 40)
end

local function build(frame)
    list = CreateFrame("Frame", nil, frame)
    list:SetPoint("TOPLEFT")
    list:SetPoint("TOPRIGHT")

    local actions = CreateFrame("Frame", nil, frame)
    actions:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -22)
    actions:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", 0, -22)
    actions:SetHeight(120)

    local nameLabel = Widgets.Text(actions, 13, "muted")
    nameLabel:SetPoint("TOPLEFT")
    nameLabel:SetText(L.PROFILE_NAME)
    nameBox = Widgets.Input(actions)
    nameBox:SetPoint("TOPLEFT", 0, -20)
    nameBox:SetWidth(260)
    local create = Widgets.Button(actions, L.NEW_PROFILE, "primary", function()
        local ok, err = E.store:CreateProfile(nameBox:GetText(), E.store:GetProfileName())
        report(not ok and err or nil)
        if ok then
            nameBox:SetText("")
            ns.Window.Refresh()
        end
    end)
    create:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)

    local shareLabel = Widgets.Text(actions, 13, "muted")
    shareLabel:SetPoint("TOPLEFT", 0, -66)
    shareLabel:SetText(L.SHARE_TEXT)
    shareBox = Widgets.Input(actions)
    shareBox:SetPoint("TOPLEFT", 0, -86)
    shareBox:SetPoint("TOPRIGHT", -216, -86)
    -- Not HighlightText itself: the handler gets extra arguments it would take as a range.
    shareBox:SetScript("OnEditFocusGained", function(box)
        box:HighlightText()
    end)

    local export = Widgets.Button(actions, L.EXPORT, "ghost", function()
        local text, err = E.store:ExportProfile()
        report(err)
        shareBox:SetText(text or "")
        shareBox:SetFocus()
    end)
    export:SetPoint("LEFT", shareBox, "RIGHT", 8, 0)
    local import = Widgets.Button(actions, L.IMPORT, "ghost", function()
        local ok, err = E.store:ImportProfile(nameBox:GetText(), shareBox:GetText())
        report(not ok and err or nil)
        if ok then
            nameBox:SetText("")
            shareBox:SetText("")
            ns.Window.Refresh()
        end
    end)
    import:SetPoint("LEFT", export, "RIGHT", 8, 0)

    message = Widgets.Text(actions, 13, E.Theme.colors.danger)
    message:SetPoint("TOPLEFT", 0, -124)
end

ns.Window.AddPage({ key = "profiles", title = L.PROFILES, note = L.PROFILES_NOTE, Build = build, Refresh = refresh })
