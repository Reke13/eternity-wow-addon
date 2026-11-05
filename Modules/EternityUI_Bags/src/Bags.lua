-- EternityUI_Bags: bags and bank with the Eternity look.
--   * Bags: every bag in one window (one grid or one section per bag), with search, sort,
--     gold and free slots. Bank: the character tabs and the warband ones, with deposit.
--   * The item buttons are Blizzard's (ContainerFrameItemButtonTemplate): clicks, drag, use,
--     sell, split and tooltips work exactly as in Blizzard's bags; only their look changes.
--   * Blizzard decides when bags open and close (vendor, mailbox, bank, keys...): its frames
--     keep working inside a hidden parent and our window mirrors whether any of them is shown.
--     The bank frame stays open (closing it ends the bank session) but invisible.
-- No taint: it replaces no Blizzard method (hooksecurefunc only) and touches no protected frame.
-- When disabled, Blizzard's frames go back to their parents, without /reload. Hooks can't be
-- removed: they're installed once and do nothing while `running` is false.

---@type string, EternityUIBagsNamespace
local addonName, ns = ...
local E = EternityUI
local Shape, Theme, Widgets = E.Shape, E.Theme, E.Widgets
local L, Inventory = ns.L, ns.Inventory

local CONTROL_HEIGHT = 32

local QUALITY_FROM = { poor = 0, common = 1, uncommon = 2, rare = 3, epic = 4 }
local QUEST_COLOR = { 1, 0.82, 0.2, 1 }
local SECTION_TITLE = 18
local ITEM_CLASS_WEAPON, ITEM_CLASS_ARMOR = 2, 4 -- Enum.ItemClass
local EVENTS = {
    "BAG_UPDATE_DELAYED",
    "BAG_CONTAINER_UPDATE",
    "ITEM_LOCK_CHANGED",
    "BAG_UPDATE_COOLDOWN",
    "INVENTORY_SEARCH_UPDATE",
    "BAG_NEW_ITEMS_UPDATED",
    "PLAYER_MONEY",
    "PLAYERBANKSLOTS_CHANGED",
    "BANK_TABS_CHANGED",
    "BANK_TAB_SETTINGS_UPDATED",
    "BANKFRAME_OPENED",
    "BANKFRAME_CLOSED",
}
-- Events that change which slots there are (a bag or tab swapped or bought): the grid is laid
-- out again. The rest only change how the items look.
local RELAYOUT = {
    BAG_CONTAINER_UPDATE = true,
    BANK_TABS_CHANGED = true,
    BANK_TAB_SETTINGS_UPDATED = true,
}

---@class EternityUIBagsModule: EternityUIModuleDefinition
---@field running boolean?
---@field hooked boolean?
---@field bagsHidden table<table, table>? Blizzard bag frame -> its original parent
---@field bankHidden table? BankFrame's original parent while it's hidden
---@field bankOpen boolean?
---@field blizzardBank boolean? this bank visit uses Blizzard's window
---@field bags EternityUIBagsGrid?
---@field bank EternityUIBagsGrid?
---@field inventory EternityUIBagsInventory
local Module = {
    schema = ns.OptionsSchema,
    inventory = Inventory, -- for the tests
}

local function opt(path)
    return E.store:Get(addonName, path)
end

local function registerEvents(frame, events)
    for _, event in ipairs(events) do
        -- An event this client doesn't have errors on RegisterEvent: skip it.
        pcall(frame.RegisterEvent, frame, event)
    end
end

local function bankTypes()
    local types = Enum.BankType
    return types and types.Character, types and types.Account
end

local hider = CreateFrame("Frame")
hider:Hide()

-- Item buttons ------------------------------------------------------------------------------

--- Font file of the theme (the counts use their own size).
local function themeFontPath()
    return Theme.font
end

-- The slots' corner radius follows the theme, capped so small slots still read as squares.
local function slotRadius()
    return math.min(Theme.radius, 4)
end

local function paintSlot(shape, fill, border)
    Shape.Paint(shape, slotRadius(), fill and Theme.RGBA(fill) or nil, border and Theme.RGBA(border) or nil)
end

local function qualityColor(quality)
    if quality and C_Item.GetItemQualityColor then
        local r, g, b = C_Item.GetItemQualityColor(quality)
        if r then
            return { r, g, b, 1 }
        end
    end
end

local function itemLevel(info, bag, slot)
    if not info.itemID or not C_Item.GetItemInfoInstant then
        return nil
    end
    local _, _, _, equipLoc, _, classID = C_Item.GetItemInfoInstant(info.itemID)
    if (classID ~= ITEM_CLASS_WEAPON and classID ~= ITEM_CLASS_ARMOR) or not equipLoc or equipLoc == "" then
        return nil
    end
    if equipLoc == "INVTYPE_NON_EQUIP_IGNORE" or equipLoc == "INVTYPE_BAG" then
        return nil
    end
    local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
    local level = location and location:IsValid() and C_Item.GetCurrentItemLevel(location)
    if level and level > 1 then
        return level
    end
end

--- Eternity look for a Blizzard item button (once per button).
local function skinButton(b)
    b.etBack = Shape.New(b, "BACKGROUND", -8)
    b.etBorder = Shape.New(b, "OVERLAY", 5)
    b.etLevel = b:CreateFontString(nil, "OVERLAY")
    b.etLevel:SetFont(Theme.font, 12, "OUTLINE")
    local normal = b:GetNormalTexture()
    if normal then
        normal:SetAlpha(0)
    end
    b.etMask = b:CreateMaskTexture()
end

--- Rounds the icon (and the hover and pressed highlights) to the slot's corners with a fill-R
--- mask. The mask is stretched over the icon, so R is scaled from texture pixels to the icon size.
local function maskIcon(b, icon, size)
    local radius = slotRadius()
    local textures = { icon }
    for _, texture in ipairs({ b:GetHighlightTexture() or false, b:GetPushedTexture() or false }) do
        if texture then
            textures[#textures + 1] = texture
        end
    end
    if radius < 2 or size <= 2 then
        if b.etMasked then
            for _, texture in ipairs(textures) do
                texture:RemoveMaskTexture(b.etMask)
            end
            b.etMasked = false
        end
        return
    end
    local r = Shape.Nearest(math.max(4, math.min(16, math.floor((radius - 1) * 64 / (size - 2) + 0.5))))
    b.etMask:SetTexture(Theme.MEDIA .. "fill-" .. r .. ".tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    b.etMask:ClearAllPoints()
    b.etMask:SetAllPoints(icon)
    if not b.etMasked then
        for _, texture in ipairs(textures) do
            texture:AddMaskTexture(b.etMask)
        end
        b.etMasked = true
    end
end

--- Size, icon crop, texts and border of a button according to the options.
local function styleButton(b, size)
    b:SetSize(size, size)
    local icon = b.icon or b.Icon
    if icon then
        local crop = opt("slots.iconZoom") and 0.08 or 0
        icon:SetTexCoord(crop, 1 - crop, crop, 1 - crop)
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", -1, 1)
        maskIcon(b, icon, size)
    end
    local path = themeFontPath()
    if b.Count then
        b.Count:SetFont(path, opt("slots.countSize"), "OUTLINE")
        b.Count:ClearAllPoints()
        b.Count:SetPoint("BOTTOMRIGHT", -2, 2)
    end
    b.etLevel:SetFont(path, opt("slots.itemLevelSize"), "OUTLINE")
    local corner = opt("slots.itemLevelPosition")
    local inset = corner == "CENTER" and 0 or 2
    b.etLevel:ClearAllPoints()
    b.etLevel:SetPoint(
        corner,
        corner:find("LEFT") and inset or (corner:find("RIGHT") and -inset or 0),
        corner:find("TOP") and -inset or (corner:find("BOTTOM") and inset or 0)
    )
    if b.IconBorder then
        b.IconBorder:SetAlpha(opt("quality.border") and 0 or 1)
    end
    -- The slot shape follows the theme's corners: the shapes of every button are repainted.
    paintSlot(b.etBack, "field", "border")
end

--- What Blizzard's ContainerFrameMixin:UpdateItems does for one button, plus our look.
local function updateButton(b, tooltipOwner)
    local bag, slot = b:GetBagID(), b:GetID()
    local info = C_Container.GetContainerItemInfo(bag, slot)
    local texture = info and info.iconFileID
    local quality = info and info.quality
    local questInfo = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot) or {}

    ClearItemButtonOverlay(b)
    b:SetHasItem(texture)
    b:SetItemButtonTexture(texture)
    SetItemButtonQuality(b, quality, info and info.hyperlink, false, info and info.isBound)
    SetItemButtonCount(b, info and info.stackCount)
    SetItemButtonDesaturated(b, info and info.isLocked)
    if b.UpdateExtended then
        b:UpdateExtended()
    end
    if b.UpdateQuestItem then
        b:UpdateQuestItem(questInfo.isQuestItem, questInfo.questID, questInfo.isActive)
    end
    b:UpdateNewItem(quality)
    b:UpdateJunkItem(quality, info and info.hasNoValue)
    if b.UpdateItemContextMatching then
        b:UpdateItemContextMatching()
    end
    b:UpdateCooldown(texture)
    if b.SetReadable then
        b:SetReadable(info and info.isReadable)
    end
    if b.CheckUpdateTooltip then
        b:CheckUpdateTooltip(tooltipOwner)
    end
    b:SetMatchesSearch(not (info and info.isFiltered))

    -- Our options on top of Blizzard's.
    if not opt("items.newItems") then
        for _, key in ipairs({ "NewItemTexture", "BattlepayItemTexture" }) do
            if b[key] then
                b[key]:Hide()
            end
        end
        for _, key in ipairs({ "flashAnim", "newitemglowAnim" }) do
            if b[key] then
                b[key]:Stop()
            end
        end
    end
    if b.JunkIcon and opt("items.junk") and info and quality == 0 and not info.hasNoValue then
        b.JunkIcon:Show()
    end

    local border
    if info and questInfo.isQuestItem and opt("quality.questBorder") then
        border = QUEST_COLOR
    elseif info and quality and opt("quality.border") and quality >= QUALITY_FROM[opt("quality.from")] then
        border = qualityColor(quality)
    end
    paintSlot(b.etBorder, nil, border)
    if border and opt("quality.glow") then
        paintSlot(b.etBack, { border[1], border[2], border[3], 0.18 }, "border")
    else
        paintSlot(b.etBack, "field", "border")
    end

    local level = info and opt("items.itemLevel") and itemLevel(info, bag, slot)
    if level then
        b.etLevel:SetText(level)
        local color = opt("items.itemLevelColor") and qualityColor(quality)
        if color then
            b.etLevel:SetTextColor(color[1], color[2], color[3])
        else
            b.etLevel:SetTextColor(1, 1, 1)
        end
    end
    b.etLevel:SetShown(level and true or false)
end

-- Grid: one window (bags or bank) -----------------------------------------------------------

---@class EternityUIBagsSection
---@field title string?
---@field bags integer[]

---@class EternityUIBagsGrid
---@field kind string "bags" | "bank"
---@field frame table the window
---@field content table
---@field holders table<integer, table> bagID -> frame with that ID (the buttons' parent)
---@field buttons table<integer, table[]> bagID -> slot -> item button
---@field titles table[] section title pool
---@field bankType integer? (bank) the tab shown
---@field dirty boolean? the slots must be laid out again on show
local Grid = {}
Grid.__index = Grid

function Grid:Holder(bag)
    local holder = self.holders[bag]
    if not holder then
        holder = CreateFrame("Frame", nil, self.content)
        holder:SetAllPoints()
        -- The button reads its bag from this ID (ContainerFrameItemButtonMixin:GetBagID).
        holder:SetID(bag)
        self.holders[bag] = holder
        self.buttons[bag] = {}
    end
    return holder
end

function Grid:Button(bag, slot)
    local holder = self:Holder(bag)
    local b = self.buttons[bag][slot]
    if not b then
        b = CreateFrame("ItemButton", nil, holder, "ContainerFrameItemButtonTemplate")
        skinButton(b)
        -- Not Initialize: it stores this addon's frame on the button, IsCombined then runs our
        -- code inside its click, and the taint blocks UseContainerItem.
        b:SetID(slot)
        self.buttons[bag][slot] = b
    end
    return b
end

--- Bag name for a section title.
local function bagTitle(bag)
    local index = Enum.BagIndex or {}
    if bag == index.Keyring then
        return L.KEYRING
    elseif bag == index.ReagentBag then
        return L.REAGENTS
    elseif bag == (index.Backpack or 0) then
        return L.BAGS
    end
    local name = C_Container.GetBagName and C_Container.GetBagName(bag)
    return name or L.BAG_N:format(bag)
end

--- The sections of this window according to the layout.
---@return EternityUIBagsSection[]
function Grid:Sections()
    local split = opt("windows.layout") == "bags"
    local sections = {}
    if self.kind == "bank" then
        local tabs = C_Bank and C_Bank.FetchPurchasedBankTabData and C_Bank.FetchPurchasedBankTabData(self.bankType)
        if split then
            for i, tab in ipairs(tabs or {}) do
                sections[#sections + 1] =
                    { title = tab.name ~= "" and tab.name or L.TAB_N:format(i), bags = { tab.ID } }
            end
        else
            sections[1] = { bags = Inventory.BankBags(self.bankType) }
        end
        return sections
    end
    local index = Enum.BagIndex or {}
    local main = { bags = {} }
    sections[1] = main
    for _, bag in ipairs(Inventory.PlayerBags()) do
        local apart = bag == index.Keyring or (bag == index.ReagentBag and (split or opt("windows.reagents")))
        if split or apart then
            if C_Container.GetContainerNumSlots(bag) > 0 then
                sections[#sections + 1] = { title = bagTitle(bag), bags = { bag } }
            end
        else
            main.bags[#main.bags + 1] = bag
        end
    end
    if #main.bags == 0 then
        table.remove(sections, 1)
    end
    return sections
end

function Grid:SectionTitle(index)
    local title = self.titles[index]
    if not title then
        title = Widgets.Text(self.content, 12, "muted")
        self.titles[index] = title
    end
    return title
end

--- Places every slot and sizes the window.
function Grid:Layout()
    local size, gap = opt("slots.size"), opt("slots.spacing")
    local columns = opt(self.kind == "bank" and "slots.bankColumns" or "slots.columns")
    local used, y, titleIndex = {}, 0, 0
    local showTitles = opt("windows.sectionTitles")
    for _, section in ipairs(self:Sections()) do
        if section.title and showTitles then
            titleIndex = titleIndex + 1
            local title = self:SectionTitle(titleIndex)
            title:SetText(section.title)
            title:ClearAllPoints()
            title:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
            title:Show()
            y = y + SECTION_TITLE
        end
        local i = 0
        for _, bag in ipairs(section.bags) do
            used[bag] = {}
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local b = self:Button(bag, slot)
                styleButton(b, size)
                local col, row = i % columns, math.floor(i / columns)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", self.content, "TOPLEFT", col * (size + gap), -(y + row * (size + gap)))
                b:Show()
                used[bag][slot] = true
                i = i + 1
            end
        end
        local rows = math.ceil(i / columns)
        y = y + rows * size + math.max(rows - 1, 0) * gap + (rows > 0 and gap + 4 or 0)
    end
    for index = titleIndex + 1, #self.titles do
        self.titles[index]:Hide()
    end
    for bag, list in pairs(self.buttons) do
        for slot, b in pairs(list) do
            if not (used[bag] and used[bag][slot]) then
                b:Hide()
            end
        end
    end
    self.empty:SetShown(y == 0)
    local width = math.max(columns * size + (columns - 1) * gap, 260)
    local height = math.max(y - gap - 4, 0)
    if y == 0 then
        height = 40
    end
    self.content:SetSize(width, height)
    self:LayoutChrome(width, height)
    self.dirty = false
    self.slots = self:CountSlots()
    self:Refresh()
end

--- Total slots of the bags shown: if it changes, the grid is laid out again.
function Grid:CountSlots()
    local total = 0
    for _, bag in ipairs(self:Bags()) do
        total = total + C_Container.GetContainerNumSlots(bag)
    end
    return total
end

--- Header, toolbar and footer around the content; the window's size.
function Grid:LayoutChrome(width, height)
    local w, pad = self.frame, opt("window.padding")
    local header = opt("window.compact") and 40 or 56
    w.header:SetHeight(header)
    w.title:SetShown(opt("window.title"))
    local toolbar = self.toolbar
    toolbar:ClearAllPoints()
    toolbar:SetPoint("TOPLEFT", w.body, "TOPLEFT", pad, -pad)
    toolbar:SetSize(width, CONTROL_HEIGHT)
    local left = 0
    if self.tabs then
        self.tabs:SetShown(self.tabs.count > 1)
        if self.tabs.count > 1 then
            left = self.tabs:GetWidth() + 8
        end
    end
    self.sort:ClearAllPoints()
    self.sort:SetPoint("RIGHT", toolbar, "RIGHT", 0, 0)
    self.search:ClearAllPoints()
    self.search:SetPoint("LEFT", toolbar, "LEFT", left, 0)
    self.search:SetPoint("RIGHT", self.sort, "LEFT", -8, 0)
    self.content:ClearAllPoints()
    self.content:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -pad)
    w:SetSize(width + 2 * pad, header + 1 + CONTROL_HEIGHT + height + 3 * pad + 1 + w.footer:GetHeight())
    self:UpdateFooter()
end

--- Item states (count, lock, cooldown, search, borders) without moving anything.
function Grid:Refresh()
    if not self.frame:IsShown() then
        return
    end
    if self.dirty or self.slots ~= self:CountSlots() then
        self:Layout()
        return
    end
    local owner = GameTooltip:GetOwner()
    for _, list in pairs(self.buttons) do
        for _, b in pairs(list) do
            if b:IsShown() then
                updateButton(b, owner)
            end
        end
    end
    self:UpdateFooter()
end

function Grid:Bags()
    local list = {}
    for _, section in ipairs(self:Sections()) do
        for _, bag in ipairs(section.bags) do
            list[#list + 1] = bag
        end
    end
    return list
end

function Grid:UpdateFooter()
    local free, total = 0, 0
    for _, bag in ipairs(self:Bags()) do
        if bag ~= (Enum.BagIndex or {}).Keyring then
            free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0)
            total = total + C_Container.GetContainerNumSlots(bag)
        end
    end
    self.free:SetText(L.FREE:format(free, total))
    self.free:SetShown(opt("windows.freeSlots"))
    if self.money then
        self.money:SetText(GetMoneyString(GetMoney(), true))
        self.money:SetShown(opt("windows.money"))
    end
    if self.deposit then
        self.deposit:SetShown(C_Bank ~= nil and C_Bank.AutoDepositItemsIntoBank ~= nil)
    end
end

function Grid:Sort()
    if self.kind == "bank" then
        if C_Container.SortBank and self.bankType then
            C_Container.SortBank(self.bankType)
        elseif C_Container.SortBankBags then
            C_Container.SortBankBags()
        end
        return
    end
    -- Blizzard's direction setting just for this sort; the player's own is put back.
    local get, set = C_Container.GetSortBagsRightToLeft, C_Container.SetSortBagsRightToLeft
    local previous = get and get()
    if set then
        set(opt("windows.sortReverse"))
    end
    C_Container.SortBags()
    if set and previous ~= nil then
        set(previous)
    end
end

--- Scale. The position belongs to the Mover: bags at the bottom right corner and bank at the top
--- left one by default; dragging the window saves it there too.
function Grid:Place()
    self.frame:SetScale(opt("window.scale"))
end

function Grid:Key()
    return addonName .. "." .. self.kind
end

function Grid:Register()
    local bank = self.kind == "bank"
    E.Mover.Register({
        key = self:Key(),
        owner = addonName,
        label = bank and L.BANK or L.BAGS,
        frame = self.frame,
        point = bank and "TOPLEFT" or "BOTTOMRIGHT",
        x = bank and 24 or -24,
        y = bank and -120 or 96,
        openOptions = function()
            E:OpenOptions(addonName)
        end,
    })
end

function Grid:ClearSearch()
    if self.search:GetText() ~= "" then
        self.search:SetText("")
    end
    C_Container.SetItemSearch("")
end

function Grid:OpenMenu(owner)
    local entries = {
        {
            text = L.OPTIONS,
            onClick = function()
                E:OpenOptions(addonName, "general")
            end,
        },
    }
    local others = Inventory:Others()
    if #others == 0 then
        entries[#entries + 1] = { text = L.NO_CHARACTERS, onClick = function() end }
    end
    for _, char in ipairs(others) do
        entries[#entries + 1] = {
            text = L.FORGET:format(char.name .. "-" .. char.realm),
            onClick = function()
                Inventory:Forget(char.realm, char.name)
            end,
        }
    end
    Widgets.Menu(owner, entries, 220)
end

local function hint(frame, title, text)
    Widgets.AttachTooltip(frame, function(tip)
        tip:SetTitle(title)
        tip:AddLine(text, "textMuted")
    end)
end

---@param module EternityUIBagsModule
---@param kind string "bags" | "bank"
---@return EternityUIBagsGrid
function Grid.New(module, kind)
    local self = setmetatable({ kind = kind, holders = {}, buttons = {}, titles = {} }, Grid)
    local bank = kind == "bank"
    local w = Widgets.Window(bank and "EternityUIBankWindow" or "EternityUIBagsWindow", bank and L.BANK or L.BAGS, true)
    self.frame = w
    w:SetSize(480, 400)
    w:SetFrameStrata("HIGH")
    w:SetToplevel(true)
    w:SetScript("OnDragStart", function(frame)
        local entry = E.Mover.Entry(self:Key())
        if not (entry and entry.locked) then
            frame:StartMoving()
        end
    end)
    w:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        frame:SetUserPlaced(false)
        E.Mover.SaveFromFrame(self:Key())
    end)
    w:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            E:OpenOptions(addonName, "general")
        end
    end)
    w:HookScript("OnShow", function()
        self:Place()
        if self.dirty then
            self:Layout()
        else
            self:Refresh()
        end
    end)
    w:HookScript("OnHide", function()
        if opt("windows.clearSearch") then
            self:ClearSearch()
        end
        Widgets.CloseMenu()
        module:OnWindowHidden(self)
    end)
    -- Window opacity and shadow on top of the theme's: applied after every repaint.
    function w.onPaint(frame)
        if module.running then
            frame.shape.fill:SetAlpha(opt("window.opacity"))
            frame.shadow:SetShown(opt("window.shadow"))
        end
    end
    w:Paint()

    self.menu = Widgets.Button(w.header, "...", "ghost", function()
        self:OpenMenu(self.menu)
    end)
    self.menu:SetSize(26, 26)
    self.menu:SetPoint("RIGHT", w.close, "LEFT", -4, 0)
    hint(self.menu, L.CHARACTERS, L.CHARACTERS_HINT)

    self.toolbar = CreateFrame("Frame", nil, w.body)
    self.search = Widgets.Input(self.toolbar, nil, L.SEARCH)
    self.search:SetMaxLetters(60)
    self.search:HookScript("OnTextChanged", function(box, userInput)
        if userInput then
            C_Container.SetItemSearch(box:GetText())
        end
    end)
    self.sort = Widgets.Button(self.toolbar, L.SORT, "ghost", function()
        self:Sort()
    end)
    hint(self.sort, L.SORT, L.SORT_HINT)

    self.content = CreateFrame("Frame", nil, w.body)
    self.empty = Widgets.Text(self.content, 12, "muted")
    self.empty:SetText(L.NO_TABS)
    self.empty:SetPoint("CENTER")
    self.empty:Hide()

    local pad = 12
    self.free = Widgets.Text(w.footer, 12, "muted")
    self.free:SetPoint("RIGHT", w.footer, "RIGHT", -pad, 0)
    if bank then
        local character, account = bankTypes()
        self.bankType = character
        local items = { { "character", L.CHARACTER_BANK } }
        if account then
            items[2] = { "account", L.WARBAND_TAB }
        end
        self.tabs = Widgets.Segmented(self.toolbar, items, function(key)
            self.bankType = key == "account" and account or character
            self:Layout()
        end)
        self.tabs:SetPoint("LEFT", self.toolbar, "LEFT", 0, 0)
        self.tabs:SetValue("character")
        self.tabs.count = #items
        self.deposit = Widgets.Button(w.footer, L.DEPOSIT, "ghost", function()
            if self.bankType then
                C_Bank.AutoDepositItemsIntoBank(self.bankType)
            end
        end)
        self.deposit:SetPoint("LEFT", w.footer, "LEFT", pad, 0)
        hint(self.deposit, L.DEPOSIT, L.DEPOSIT_HINT)
        self.blizzard = Widgets.Button(w.footer, L.BLIZZARD_BANK, "ghost", function()
            module:UseBlizzardBank()
        end)
        self.blizzard:SetPoint("LEFT", self.deposit, "RIGHT", 4, 0)
        hint(self.blizzard, L.BLIZZARD_BANK, L.BLIZZARD_BANK_HINT)
    else
        self.money = Widgets.Text(w.footer, 12, "text")
        self.money:SetPoint("LEFT", w.footer, "LEFT", pad, 0)
    end
    self.dirty = true
    return self
end

--- Shows the warband tab only when that bank can be seen.
function Grid:UpdateTabs()
    if not self.tabs then
        return
    end
    local character, account = bankTypes()
    local warband = self.tabs.buttons[2]
    local canWarband = warband ~= nil and Inventory.CanViewBank(account)
    if warband then
        warband:SetShown(canWarband)
    end
    self.tabs.count = canWarband and 2 or 1
    if not canWarband and self.bankType == account then
        self.bankType = character
        self.tabs:SetValue("character")
    end
end

-- Blizzard's bags ---------------------------------------------------------------------------

--- Blizzard's bag frames: the combined one (child of UIParent) and the container of the others.
local function blizzardBagParents()
    local list = {}
    if _G.ContainerFrameCombinedBags then
        list[#list + 1] = _G.ContainerFrameCombinedBags
    end
    if _G.ContainerFrameContainer then
        list[#list + 1] = _G.ContainerFrameContainer
    end
    return list
end

local function blizzardBagFrames()
    local list = {}
    if _G.ContainerFrameCombinedBags then
        list[#list + 1] = _G.ContainerFrameCombinedBags
    end
    local container = _G.ContainerFrameContainer
    for _, frame in ipairs(container and container.ContainerFrames or {}) do
        list[#list + 1] = frame
    end
    return list
end

--- Whether Blizzard has any bag open (they're shown even inside the hidden parent).
function Module:AnyBlizzardBagOpen()
    for _, frame in ipairs(blizzardBagFrames()) do
        if frame:IsShown() then
            return true
        end
    end
    return false
end

function Module:BagsReplaced()
    return self.bagsHidden ~= nil
end

--- Hides or restores Blizzard's bag frames according to the options.
function Module:ApplyBags()
    local want = self.running and opt("windows.replaceBags")
    if want and not self.bagsHidden then
        self.bagsHidden = {}
        for _, frame in ipairs(blizzardBagParents()) do
            self.bagsHidden[frame] = frame:GetParent()
            frame:SetParent(hider)
        end
        self:SyncBags()
    elseif not want and self.bagsHidden then
        local hidden = self.bagsHidden
        self.bagsHidden = nil
        for frame, parent in pairs(hidden) do
            frame:SetParent(parent)
        end
        if self.bags then
            self.syncing = true
            self.bags.frame:Hide()
            self.syncing = false
        end
    end
end

--- Our bag window follows Blizzard's open/closed state.
function Module:SyncBags()
    if not self.running or not self:BagsReplaced() then
        return
    end
    local open = self:AnyBlizzardBagOpen()
    if open and not self.bags then
        self.bags = Grid.New(self, "bags")
    end
    if self.bags then
        self.syncing = true
        self.bags.frame:SetShown(open)
        self.syncing = false
    end
end

-- Blizzard's bank ---------------------------------------------------------------------------

local function bankFrame()
    return _G.BankFrame
end

--- Hides BankFrame inside our hidden parent (only while it's not visible: hiding it while
--- visible fires its OnHide, which ends the bank session) or gives it back.
function Module:ApplyBank()
    local frame = bankFrame()
    if not frame then
        return
    end
    local want = self.running and opt("windows.replaceBank") and not self.blizzardBank
    if want and not self.bankHidden and not frame:IsVisible() then
        self.bankHidden = frame:GetParent()
        frame:SetParent(hider)
    elseif not want and self.bankHidden then
        frame:SetParent(self.bankHidden)
        self.bankHidden = nil
    end
    self:SyncBank()
end

function Module:SyncBank()
    local show = self.running and self.bankOpen and self.bankHidden ~= nil
    if show and not self.bank then
        self.bank = Grid.New(self, "bank")
    end
    if self.bank then
        if show then
            self.bank:UpdateTabs()
            self.bank.dirty = true
        end
        self.syncing = true
        self.bank.frame:SetShown(show and true or false)
        self.syncing = false
    end
end

--- "Blizzard's bank" button: Blizzard's window for the rest of this visit.
function Module:UseBlizzardBank()
    self.blizzardBank = true
    self:ApplyBank()
end

--- The player closed one of our windows (close button or Escape).
function Module:OnWindowHidden(grid)
    if self.syncing or not self.running then
        return
    end
    if grid.kind == "bags" then
        if self:AnyBlizzardBagOpen() then
            CloseAllBags()
        end
    elseif self.bankOpen and not self.blizzardBank then
        if C_Bank and C_Bank.CloseBankFrame then
            C_Bank.CloseBankFrame()
        elseif _G.CloseBankFrame then
            _G.CloseBankFrame()
        end
    end
end

-- Events ------------------------------------------------------------------------------------

function Module:OnEvent(event)
    if event == "BANKFRAME_OPENED" then
        self.bankOpen = true
        self:ApplyBank()
        return
    elseif event == "BANKFRAME_CLOSED" then
        self.bankOpen = false
        self.blizzardBank = false
        self:ApplyBank()
        return
    end
    if not self.running then
        return
    end
    if event == "PLAYER_MONEY" then
        if self.bags then
            self.bags:UpdateFooter()
        end
        return
    end
    for _, grid in ipairs({ self.bags, self.bank }) do
        if grid then
            if RELAYOUT[event] then
                grid.dirty = true
            end
            if event == "BANK_TABS_CHANGED" then
                grid:UpdateTabs()
            end
            grid:Refresh()
        end
    end
end

-- Lifecycle ---------------------------------------------------------------------------------

function Module:InstallHooks()
    self.hooked = true
    for _, frame in ipairs(blizzardBagFrames()) do
        for _, method in ipairs({ "Show", "Hide", "SetShown" }) do
            hooksecurefunc(frame, method, function()
                self:SyncBags()
            end)
        end
    end
    local frame = bankFrame()
    if frame then
        -- If it was visible on enable, it's hidden as soon as Blizzard closes it.
        frame:HookScript("OnHide", function()
            if self.running and not self.bankHidden then
                self:ApplyBank()
            end
        end)
    end
    local events = CreateFrame("Frame")
    registerEvents(events, EVENTS)
    events:SetScript("OnEvent", function(_, event)
        self:OnEvent(event)
    end)
end

--- Applies every option (or undoes everything if the module isn't running).
function Module:ApplyAll()
    for _, grid in ipairs({ self.bags, self.bank }) do
        if grid then
            grid.dirty = true
            grid.frame:Paint()
            if grid.frame:IsShown() then
                grid:Place()
                grid:Layout()
            end
        end
    end
    self:ApplyBags()
    self:ApplyBank()
    self:RegisterWindows()
end

--- The windows in use are Mover elements (created hidden, so they can be placed before they
--- first open); the ones not in use leave it.
function Module:RegisterWindows()
    for _, kind in ipairs({ "bags", "bank" }) do
        local wanted = self.running and opt(kind == "bags" and "windows.replaceBags" or "windows.replaceBank")
        local grid = self[kind]
        if wanted then
            grid = grid or Grid.New(self, kind)
            self[kind] = grid
            grid:Place()
            grid:Register()
        elseif grid then
            E.Mover.Unregister(grid:Key())
        end
    end
end

function Module:OnEnable()
    self.running = true
    if not self.hooked then
        self:InstallHooks()
    end
    -- If the bank is already open (enabled from the options), the bank window shows on the next visit.
    self.bankOpen = bankFrame() ~= nil and bankFrame():IsShown()
    -- A theme change repaints the slot shapes and fonts. The core releases this on disable.
    E.Events.Listen(Theme.CHANGED, self, function()
        for _, grid in ipairs({ self.bags, self.bank }) do
            if grid then
                grid.dirty = true
                grid:Refresh()
            end
        end
    end)
    Inventory:Start()
    self:ApplyAll()
end

function Module:OnDisable()
    self.running = false
    Inventory:Stop()
    self:ApplyAll()
    for _, grid in ipairs({ self.bags, self.bank }) do
        if grid then
            self.syncing = true
            grid.frame:Hide()
            self.syncing = false
        end
    end
end

function Module:OnConfigChanged()
    -- Everything is idempotent and cheap: it's reapplied in full.
    self:ApplyAll()
end

E:RegisterModule(addonName, Module)
