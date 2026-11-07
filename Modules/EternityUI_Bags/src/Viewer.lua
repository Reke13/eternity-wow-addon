-- EternityUI_Bags: the saved view. What any character of the account carried in the bags, had in
-- the bank or saw in the guild bank, from what Inventory saved (EternityUIBagsDB). It's a window
-- of its own with plain buttons (icon, count, quality border, tooltip by item ID): nothing in it
-- is Blizzard's or can be used, and it works anywhere, with no bank open.

---@type string, EternityUIBagsNamespace
local addonName, ns = ...
local E = EternityUI
local Shape, Theme, Widgets = E.Shape, E.Theme, E.Widgets
local L, Inventory = ns.L, ns.Inventory

local PLACES = { "bags", "bank", "guild" }
local SECTION_TITLE = 18
local PAD = 12
local TOOLBAR = 30
local MIN_WIDTH = 420
local QUALITY_FROM = { poor = 0, common = 1, uncommon = 2, rare = 3, epic = 4 }

---@class EternityUIBagsViewer
---@field frame table?
---@field realm string?
---@field name string?
---@field place string bags, bank or guild
local Viewer = { place = "bags", slots = {}, titles = {} }
ns.Viewer = Viewer

local function opt(path)
    return E.store:Get(addonName, path)
end

--- "2 h ago" from a time().
---@param when number?
---@return string?
function Viewer.Ago(when, now)
    if not when then
        return nil
    end
    local seconds = math.max((now or time()) - when, 0)
    if seconds < 60 then
        return L.NOW
    elseif seconds < 3600 then
        return L.MINUTES_AGO:format(math.floor(seconds / 60))
    elseif seconds < 86400 then
        return L.HOURS_AGO:format(math.floor(seconds / 3600))
    end
    return L.DAYS_AGO:format(math.floor(seconds / 86400))
end

--- What a place holds for a character: its containers, when it was saved and, if there's
--- nothing, why.
---@param place string
---@param realm string
---@param name string
---@return EternityUIBagsContainer[] containers
---@return number? updated
---@return string? missing
function Viewer.Containers(place, realm, name)
    local char = Inventory:Character(realm, name)
    local layout = char and char.layout
    if place == "bags" then
        local bags = layout and layout.bags
        if not (bags and #bags > 0) then
            return {}, nil, L.NO_SAVED_BAGS
        end
        return bags, char.updated, nil
    elseif place == "bank" then
        local bank = layout and layout.bank
        if not (bank and #bank > 0) then
            return {}, nil, L.NO_SAVED_BANK
        end
        return bank, char.bankUpdated, nil
    end
    if not (char and char.guild) then
        return {}, nil, L.NO_GUILD
    end
    local guild = Inventory:GuildOf(char)
    if not (guild and guild.tabs and #guild.tabs > 0) then
        return {}, nil, L.NO_SAVED_GUILD
    end
    return guild.tabs, guild.updated, nil
end

local function placeName(place)
    if place == "bank" then
        return L.SAVED_BANK
    elseif place == "guild" then
        return L.GUILD_BANK
    end
    return L.BAGS
end

local function containerTitle(container, index)
    local kind = container.kind
    if container.name and container.name ~= "" then
        return container.name
    elseif kind == "keyring" then
        return L.KEYRING
    elseif kind == "reagent" then
        return L.REAGENTS
    elseif kind == "backpack" then
        return L.BAGS
    end
    return L.BAG_N:format(index)
end

-- Slots ----------------------------------------------------------------------------------------

local function itemData(id)
    local saved = Inventory:Bind().items[id] or {}
    local icon = saved.icon or (C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or 134400
    local quality = saved.quality
    if quality == nil and C_Item.GetItemQualityByID then
        quality = C_Item.GetItemQualityByID(id)
    end
    return icon, quality, saved.name
end

local function onEnter(slot)
    if not slot.itemID then
        return
    end
    GameTooltip:SetOwner(slot, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(slot.itemID)
    GameTooltip:AddLine(L.SHIFT_LINK, 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function onLeave(slot)
    if GameTooltip:IsOwned(slot) then
        GameTooltip:Hide()
    end
end

local function onClick(slot)
    if slot.itemID and IsModifiedClick() then
        local _, link = C_Item.GetItemInfo(slot.itemID)
        if link then
            HandleModifiedItemClick(link)
        end
    end
end

local function newSlot(parent)
    local slot = CreateFrame("Button", nil, parent)
    slot.back = Shape.New(slot, "BACKGROUND", -8)
    slot.border = Shape.New(slot, "OVERLAY", 5)
    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetPoint("TOPLEFT", 1, -1)
    slot.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    slot.count = slot:CreateFontString(nil, "OVERLAY")
    slot.count:SetPoint("BOTTOMRIGHT", -2, 2)
    slot:SetScript("OnEnter", onEnter)
    slot:SetScript("OnLeave", onLeave)
    slot:SetScript("OnClick", onClick)
    return slot
end

local function paint(shape, fill, border)
    local radius = math.min(Theme.radius, 4)
    Shape.Paint(shape, radius, fill and Theme.RGBA(fill) or nil, border and Theme.RGBA(border) or nil)
end

local function fillSlot(slot, entry, size, needle)
    slot:SetSize(size, size)
    local crop = opt("slots.iconZoom") and 0.08 or 0
    slot.icon:SetTexCoord(crop, 1 - crop, crop, 1 - crop)
    slot.count:SetFont(Theme.font, opt("slots.countSize"), "OUTLINE")
    local id, count = entry and entry[1], entry and entry[2]
    slot.itemID = id
    local border
    if id then
        local icon, quality, name = itemData(id)
        slot.icon:SetTexture(icon)
        slot.icon:Show()
        slot.count:SetText(count and count > 1 and count or "")
        if quality and opt("quality.border") and quality >= QUALITY_FROM[opt("quality.from")] then
            local r, g, b = C_Item.GetItemQualityColor(quality)
            border = r and { r, g, b, 1 }
        end
        local matches = not needle or (name and name:lower():find(needle, 1, true) ~= nil)
        slot:SetAlpha(matches and 1 or 0.25)
    else
        slot.icon:Hide()
        slot.count:SetText("")
        slot:SetAlpha(needle and 0.25 or 1)
    end
    paint(slot.border, nil, border)
    if border and opt("quality.glow") then
        paint(slot.back, { border[1], border[2], border[3], 0.18 }, "border")
    else
        paint(slot.back, "field", "border")
    end
end

local function sectionTitle(index)
    local title = Viewer.titles[index]
    if not title then
        title = Widgets.Text(Viewer.frame.content, 12, "muted")
        Viewer.titles[index] = title
    end
    return title
end

-- Layout ---------------------------------------------------------------------------------------

--- Draws the chosen place of the chosen character and sizes the window.
function Viewer.Layout()
    local w = Viewer.frame
    if not (w and w:IsShown() and Viewer.realm) then
        return
    end
    local place = Viewer.place
    local containers, updated, missing = Viewer.Containers(place, Viewer.realm, Viewer.name)
    local size, gap = opt("slots.size"), opt("slots.spacing")
    local columns = opt(place == "bags" and "slots.columns" or "slots.bankColumns")
    local text = w.search:GetText()
    local needle = text ~= "" and text:lower() or nil
    local showTitles = opt("window.sectionTitles")
    local y, used, titleIndex = 0, 0, 0
    for index, container in ipairs(containers) do
        if container.kind ~= "keyring" or opt("windows.keyring") then
            if showTitles and (#containers > 1 or place == "guild") then
                titleIndex = titleIndex + 1
                local title = sectionTitle(titleIndex)
                title:SetText(containerTitle(container, index))
                title:ClearAllPoints()
                title:SetPoint("TOPLEFT", w.content, "TOPLEFT", 0, -y)
                title:Show()
                y = y + SECTION_TITLE
            end
            for i = 1, container.size or 0 do
                used = used + 1
                local slot = Viewer.slots[used]
                if not slot then
                    slot = newSlot(w.content)
                    Viewer.slots[used] = slot
                end
                fillSlot(slot, container.slots and container.slots[i], size, needle)
                local col, row = (i - 1) % columns, math.floor((i - 1) / columns)
                slot:ClearAllPoints()
                slot:SetPoint("TOPLEFT", w.content, "TOPLEFT", col * (size + gap), -(y + row * (size + gap)))
                slot:Show()
            end
            local rows = math.ceil((container.size or 0) / columns)
            y = y + rows * size + math.max(rows - 1, 0) * gap + (rows > 0 and gap + 4 or 0)
        end
    end
    for i = used + 1, #Viewer.slots do
        Viewer.slots[i]:Hide()
    end
    for i = titleIndex + 1, #Viewer.titles do
        Viewer.titles[i]:Hide()
    end

    w.missing:SetShown(missing ~= nil)
    w.missing:SetText(missing or "")
    local width = math.max(columns * (size + gap) - gap, MIN_WIDTH)
    local height = math.max(y, missing and 80 or 0)
    w.content:SetSize(width, height)
    w:SetSize(width + 2 * PAD, w.header:GetHeight() + TOOLBAR + height + 2 * PAD + w.footer:GetHeight())

    w.title:SetText(L.VIEW_TITLE:format(Viewer.name, placeName(place)))
    local ago = Viewer.Ago(updated)
    w.updated:SetText(ago and L.UPDATED:format(ago) or "")
    w.places:SetValue(place)
    w.character.label:SetText(Viewer.name)
end

-- Window ---------------------------------------------------------------------------------------

local function characterMenu(owner, onPick)
    local entries = {}
    for _, char in ipairs(Inventory:Characters()) do
        local text = char.name
        local myRealm = Inventory.Me()
        if char.realm ~= myRealm then
            text = text .. "-" .. char.realm
        end
        local color = char.class and C_ClassColor and C_ClassColor.GetClassColor(char.class)
        if color then
            text = color:WrapTextInColorCode(text)
        end
        entries[#entries + 1] = {
            text = text,
            onClick = function()
                onPick(char.realm, char.name)
            end,
        }
    end
    if #entries == 0 then
        entries[1] = { text = L.NO_CHARACTERS, onClick = function() end }
    end
    Widgets.Menu(owner, entries, 220)
end
Viewer.CharacterMenu = characterMenu

local function hint(frame, title, text)
    Widgets.AttachTooltip(frame, function(tip)
        tip:SetTitle(title)
        tip:AddLine(text, "textMuted")
    end)
end

local function create()
    local w = Widgets.Window("EternityUIBagsViewer", L.BAGS, true)
    Viewer.frame = w
    w:SetSize(480, 400)
    w:SetFrameStrata("HIGH")
    w:SetToplevel(true)
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        frame:SetUserPlaced(false)
    end)
    w:HookScript("OnHide", function()
        Widgets.CloseMenu()
    end)
    function w.onPaint(frame)
        frame.shape.fill:SetAlpha(opt("window.opacity"))
        frame.shadow:SetShown(opt("window.shadow"))
    end

    local choices = {}
    for i, place in ipairs(PLACES) do
        choices[i] = { place, place == "guild" and L.GUILD or placeName(place) }
    end
    w.places = Widgets.Segmented(w.body, choices, function(place)
        Viewer.place = place
        Viewer.Layout()
    end)
    w.places:SetPoint("TOPLEFT", PAD, -PAD)
    w.search = Widgets.Input(w.body, nil, L.SEARCH)
    w.search:SetMaxLetters(60)
    w.search:SetHeight(TOOLBAR)
    w.search:SetPoint("LEFT", w.places, "RIGHT", 8, 0)
    w.search:SetPoint("RIGHT", w.body, "RIGHT", -PAD, 0)
    w.search:HookScript("OnTextChanged", function(_, userInput)
        if userInput then
            Viewer.Layout()
        end
    end)

    w.content = CreateFrame("Frame", nil, w.body)
    w.content:SetPoint("TOPLEFT", PAD, -(PAD + TOOLBAR + PAD))
    w.missing = Widgets.Text(w.content, 13, "muted")
    w.missing:SetPoint("CENTER")

    w.character = Widgets.Button(w.footer, "", "ghost", function(self)
        characterMenu(self, function(realm, name)
            Viewer.realm, Viewer.name = realm, name
            Viewer.Layout()
        end)
    end)
    w.character:SetSize(160, 26)
    w.character:SetPoint("LEFT", PAD, 0)
    hint(w.character, L.OTHER_CHARACTERS, L.OTHER_CHARACTERS_HINT)
    w.updated = Widgets.Text(w.footer, 12, "muted")
    w.updated:SetPoint("RIGHT", -PAD, 0)
end

--- Opens the saved view on a place of a character (this one by default), beside `beside`.
---@param place string bags, bank or guild
---@param realm string?
---@param name string?
---@param beside table? window to open next to
function Viewer.Open(place, realm, name, beside)
    if not Viewer.frame then
        create()
    end
    local w = Viewer.frame
    local myRealm, myName = Inventory.Me()
    Viewer.place = place or "bags"
    Viewer.realm, Viewer.name = realm or myRealm, name or myName
    w:SetScale(opt("window.scale"))
    if not w:IsShown() then
        w:ClearAllPoints()
        if beside and beside:IsShown() and beside:GetLeft() then
            -- To the left of that window, or to its right when there's no room.
            if beside:GetLeft() * beside:GetEffectiveScale() > 500 * w:GetEffectiveScale() then
                w:SetPoint("TOPRIGHT", beside, "TOPLEFT", -12, 0)
            else
                w:SetPoint("TOPLEFT", beside, "TOPRIGHT", 12, 0)
            end
        else
            w:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
        end
    end
    w:Paint()
    w:Show()
    Viewer.Layout()
end

--- Redraws if it's open (the options changed, or something was saved).
function Viewer.Refresh()
    if Viewer.frame and Viewer.frame:IsShown() then
        Viewer.frame:SetScale(opt("window.scale"))
        Viewer.frame:Paint()
        Viewer.Layout()
    end
end

function Viewer.Stop()
    if Viewer.frame then
        Viewer.frame:Hide()
    end
end
