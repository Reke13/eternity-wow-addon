-- EternityUI_Bags: what every character carries, saved for the whole account (EternityUIBagsDB),
-- and the lines it adds to the item tooltips ("who has it and how many").
--   * Bags (and keyring) and equipment are read on login and whenever they change. The bank and
--     the warband bank can only be read while the bank is open: they're updated on each visit and
--     the last snapshot is kept.
--   * Totals per item (what the tooltips read) and, for the Companion, where each item sits:
--     every bag or bank tab with its size and slots, and the equipment by slot.
--   * No links: only IDs and counts per slot, plus one account-wide entry per item with its
--     name, quality and icon (`items`), pruned to what someone still carries.
-- The tooltip lines use TooltipDataProcessor.AddTooltipPostCall (no taint, nothing replaced).
-- The hook can't be removed: it does nothing while `running` is false.

---@type string, EternityUIBagsNamespace
local addonName, ns = ...
local E = EternityUI
local L = ns.L

local SCHEMA_VERSION = 2
local FIRST_EQUIPPED, LAST_EQUIPPED = 1, 19 -- INVSLOT_HEAD .. INVSLOT_TABARD

---@class EternityUIBagsContainer one bag or bank tab as the Companion draws it
---@field id integer bag ID
---@field kind string backpack, bag, reagent, keyring or tab
---@field name string?
---@field size integer
---@field slots table<integer, integer[]> slot -> { itemID, count }

---@class EternityUIBagsLayout
---@field bags EternityUIBagsContainer[]
---@field bank EternityUIBagsContainer[]?
---@field equipped table<integer, integer>? inventory slot -> itemID

---@class EternityUIBagsItem
---@field name string?
---@field quality integer?
---@field icon integer? icon fileID

---@class EternityUIBagsCharacter
---@field class string? class file (MAGE, PRIEST...)
---@field faction string? Alliance / Horde
---@field updated number? time() of the last scan
---@field bankUpdated number? time() of the last bank visit
---@field bags table<integer, integer> itemID -> count
---@field bank table<integer, integer>
---@field equipped table<integer, integer>
---@field layout EternityUIBagsLayout?

---@class EternityUIBagsOwner
---@field name string display name (Name or Name-Realm)
---@field class string?
---@field current boolean
---@field warband boolean?
---@field bags integer
---@field bank integer
---@field equipped integer
---@field total integer

---@class EternityUIBagsInventory
---@field running boolean?
---@field hooked boolean?
---@field bankOpen boolean?
---@field db table? EternityUIBagsDB once bound
local Inventory = {}
ns.Inventory = Inventory

local function opt(path)
    return E.store:Get(addonName, path)
end

local function secret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

-- Bag lists ---------------------------------------------------------------------------------

local BagIndex = Enum.BagIndex or {}

--- The player's bags: backpack, bags 1-4, reagent bag and keyring (those this client has).
---@return integer[]
function Inventory.PlayerBags()
    local list = {}
    if BagIndex.Keyring and C_Container.GetContainerNumSlots(BagIndex.Keyring) > 0 then
        list[#list + 1] = BagIndex.Keyring
    end
    for bag = BagIndex.Backpack or 0, BagIndex.Bag_4 or 4 do
        list[#list + 1] = bag
    end
    if BagIndex.ReagentBag then
        list[#list + 1] = BagIndex.ReagentBag
    end
    return list
end

--- Bags of a bank type (Enum.BankType.Character or Account): its purchased tabs.
---@param bankType integer?
---@return integer[]
function Inventory.BankBags(bankType)
    local list = {}
    if bankType == nil or not C_Bank or not C_Bank.FetchPurchasedBankTabData then
        return list
    end
    for _, tab in ipairs(C_Bank.FetchPurchasedBankTabData(bankType) or {}) do
        list[#list + 1] = tab.ID
    end
    return list
end

--- Whether the bank of that type can be seen right now (bank open and not locked).
function Inventory.CanViewBank(bankType)
    if bankType == nil or not C_Bank then
        return false
    end
    if C_Bank.CanViewBank then
        return C_Bank.CanViewBank(bankType)
    end
    return true
end

local function bankTypes()
    local types = Enum.BankType
    return types and types.Character, types and types.Account
end

-- Database ----------------------------------------------------------------------------------

local function realmName()
    return GetRealmName() or "?"
end

-- The whole name: Forever's UnitName gives the first name and the surname apart, and two characters
-- of a realm can share a first name.
local function playerName()
    local name, surname = UnitName("player")
    if surname and surname ~= "" then
        return (name or "?") .. " " .. surname
    end
    return name or "?"
end

--- Binds EternityUIBagsDB (the client loads it before ADDON_LOADED of this addon).
function Inventory:Bind()
    if self.db then
        return self.db
    end
    local db = _G.EternityUIBagsDB
    if type(db) ~= "table" or type(db.realms) ~= "table" then
        db = { realms = {} }
    end
    -- v1 → v2 only adds fields (layout, items, warband.tabs): the next scan fills them.
    db.version = SCHEMA_VERSION
    db.warband = type(db.warband) == "table" and db.warband or { items = {} }
    db.items = type(db.items) == "table" and db.items or {}
    _G.EternityUIBagsDB = db
    self.db = db
    return db
end

---@return EternityUIBagsCharacter
function Inventory:Current()
    local db = self:Bind()
    local realm, name = realmName(), playerName()
    db.realms[realm] = db.realms[realm] or {}
    local char = db.realms[realm][name]
    if type(char) ~= "table" then
        char = { bags = {}, bank = {}, equipped = {} }
        db.realms[realm][name] = char
    end
    local _, class = UnitClass("player")
    char.class = class
    char.faction = UnitFactionGroup("player")
    return char
end

--- Characters remembered other than this one: { realm, name, class }, sorted.
function Inventory:Others()
    local db = self:Bind()
    local list = {}
    local myRealm, myName = realmName(), playerName()
    for realm, chars in pairs(db.realms) do
        for name, char in pairs(chars) do
            if not (realm == myRealm and name == myName) then
                list[#list + 1] = { realm = realm, name = name, class = char.class }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.realm ~= b.realm then
            return a.realm < b.realm
        end
        return a.name < b.name
    end)
    return list
end

function Inventory:Forget(realm, name)
    local db = self:Bind()
    if db.realms[realm] then
        db.realms[realm][name] = nil
        if next(db.realms[realm]) == nil then
            db.realms[realm] = nil
        end
    end
    self:PruneItems()
end

-- Scanning ----------------------------------------------------------------------------------

local function nameFromLink(link)
    return type(link) == "string" and not secret(link) and link:match("%[(.-)%]") or nil
end

--- Remembers an item's name, quality and icon for the Companion (the first values seen win;
--- missing ones are filled later).
function Inventory:Remember(id, name, quality, icon)
    local items = self:Bind().items
    local entry = items[id]
    if not entry then
        entry = {}
        items[id] = entry
    end
    if entry.name == nil and type(name) == "string" and name ~= "" and not secret(name) then
        entry.name = name
    end
    if entry.quality == nil and type(quality) == "number" and not secret(quality) then
        entry.quality = quality
    end
    if entry.icon == nil and type(icon) == "number" and not secret(icon) then
        entry.icon = icon
    end
end

--- Adds a bag's items to `items` (itemID -> count) and returns its slots for the layout.
function Inventory:ReadContainer(items, bag)
    local size = C_Container.GetContainerNumSlots(bag)
    local slots = {}
    for slot = 1, size do
        local info = C_Container.GetContainerItemInfo(bag, slot)
        local id = info and info.itemID
        if id and not secret(id) then
            local count = info.stackCount or 1
            if secret(count) then
                count = 1
            end
            items[id] = (items[id] or 0) + count
            slots[slot] = { id, count }
            self:Remember(id, info.itemName or nameFromLink(info.hyperlink), info.quality, info.iconFileID)
        end
    end
    return size, slots
end

local function bagKind(bag)
    local index = Enum.BagIndex or {}
    if bag == index.Keyring then
        return "keyring"
    elseif bag == index.ReagentBag then
        return "reagent"
    elseif bag == (index.Backpack or 0) then
        return "backpack"
    end
    return "bag"
end

--- Reads the bank tabs of a type: totals and containers.
function Inventory:ReadBank(bankType)
    local items, containers = {}, {}
    local tabs = C_Bank.FetchPurchasedBankTabData and C_Bank.FetchPurchasedBankTabData(bankType) or {}
    for i, tab in ipairs(tabs) do
        local size, slots = self:ReadContainer(items, tab.ID)
        local name = tab.name
        containers[#containers + 1] = {
            id = tab.ID,
            kind = "tab",
            name = type(name) == "string" and name ~= "" and name or L.TAB_N:format(i),
            size = size,
            slots = slots,
        }
    end
    return items, containers
end

local function layoutOf(char)
    if type(char.layout) ~= "table" then
        char.layout = { bags = {} }
    end
    return char.layout
end

function Inventory:ScanBags()
    local items, containers = {}, {}
    for _, bag in ipairs(Inventory.PlayerBags()) do
        local size, slots = self:ReadContainer(items, bag)
        if size > 0 then
            local kind = bagKind(bag)
            local name = kind == "bag" and C_Container.GetBagName and C_Container.GetBagName(bag) or nil
            containers[#containers + 1] = { id = bag, kind = kind, name = name, size = size, slots = slots }
        end
    end
    local char = self:Current()
    char.bags = items
    layoutOf(char).bags = containers
    char.updated = time()
end

function Inventory:ScanEquipped()
    local items, bySlot = {}, {}
    for slot = FIRST_EQUIPPED, LAST_EQUIPPED do
        local id = GetInventoryItemID("player", slot)
        if id and not secret(id) then
            items[id] = (items[id] or 0) + 1
            bySlot[slot] = id
            self:Remember(
                id,
                nameFromLink(GetInventoryItemLink("player", slot)),
                GetInventoryItemQuality("player", slot),
                GetInventoryItemTexture("player", slot)
            )
        end
    end
    local char = self:Current()
    char.equipped = items
    layoutOf(char).equipped = bySlot
end

--- The bank only while it's open: closed, its bags report 0 slots and would wipe the snapshot.
function Inventory:ScanBank()
    if not self.bankOpen then
        return
    end
    local character, account = bankTypes()
    if Inventory.CanViewBank(character) then
        local items, containers = self:ReadBank(character)
        local char = self:Current()
        char.bank = items
        layoutOf(char).bank = containers
        char.bankUpdated = time()
    end
    if opt("inventory.warband") and Inventory.CanViewBank(account) then
        local items, containers = self:ReadBank(account)
        local warband = self:Bind().warband
        warband.items = items
        warband.tabs = containers
        warband.updated = time()
    end
end

--- Forgets the item entries nobody carries any more.
function Inventory:PruneItems()
    local db = self:Bind()
    local used = {}
    local function mark(items)
        for id in pairs(type(items) == "table" and items or {}) do
            used[id] = true
        end
    end
    for _, chars in pairs(db.realms) do
        for _, char in pairs(chars) do
            mark(char.bags)
            mark(char.bank)
            mark(char.equipped)
        end
    end
    mark(db.warband.items)
    for id in pairs(db.items) do
        if not used[id] then
            db.items[id] = nil
        end
    end
end

function Inventory:ScanAll()
    self:ScanBags()
    self:ScanEquipped()
    self:ScanBank()
    self:PruneItems()
end

-- Counting ----------------------------------------------------------------------------------

local function countIn(items, id)
    return type(items) == "table" and items[id] or 0
end

--- Who has the item, according to the tooltip options: owners sorted (this character first,
--- then by count) and the total.
---@param itemID integer
---@return EternityUIBagsOwner[] owners
---@return integer total
function Inventory:Owners(itemID)
    local db = self:Bind()
    local myRealm, myName = realmName(), playerName()
    local myFaction = UnitFactionGroup("player")
    local allRealms = opt("tooltip.realms") == "all"
    local sameFaction = opt("tooltip.faction") == "same"
    local owners, total = {}, 0
    for realm, chars in pairs(db.realms) do
        if allRealms or realm == myRealm then
            for name, char in pairs(chars) do
                local current = realm == myRealm and name == myName
                local shown = (not current or opt("tooltip.current"))
                    and (not sameFaction or current or char.faction == myFaction)
                if shown then
                    local bags = countIn(char.bags, itemID)
                    local bank = countIn(char.bank, itemID)
                    local equipped = countIn(char.equipped, itemID)
                    local sum = bags + bank + equipped
                    if sum > 0 then
                        owners[#owners + 1] = {
                            name = realm == myRealm and name or (name .. "-" .. realm),
                            class = char.class,
                            current = current,
                            bags = bags,
                            bank = bank,
                            equipped = equipped,
                            total = sum,
                        }
                        total = total + sum
                    end
                end
            end
        end
    end
    table.sort(owners, function(a, b)
        if a.current ~= b.current then
            return a.current
        end
        if a.total ~= b.total then
            return a.total > b.total
        end
        return a.name < b.name
    end)
    if opt("tooltip.warband") then
        local count = countIn(db.warband.items, itemID)
        if count > 0 then
            owners[#owners + 1] = {
                name = L.WARBAND,
                warband = true,
                current = false,
                bags = 0,
                bank = count,
                equipped = 0,
                total = count,
            }
            total = total + count
        end
    end
    return owners, total
end

-- Tooltip -----------------------------------------------------------------------------------

local MODIFIERS = { shift = IsShiftKeyDown, ctrl = IsControlKeyDown, alt = IsAltKeyDown }

local function modifierHeld()
    local check = MODIFIERS[opt("tooltip.modifier")]
    return check == nil or check()
end

local function breakdown(owner)
    if owner.warband then
        return tostring(owner.total)
    end
    local places = {}
    for _, place in ipairs({ { L.IN_BAGS, owner.bags }, { L.IN_BANK, owner.bank }, { L.EQUIPPED, owner.equipped } }) do
        if place[2] > 0 then
            places[#places + 1] = place
        end
    end
    -- A single place: "12 (bank)"; several: "12 (bags 3, bank 9)".
    if #places == 1 then
        return owner.total .. " (" .. places[1][1] .. ")"
    end
    local parts = {}
    for i, place in ipairs(places) do
        parts[i] = place[1] .. " " .. place[2]
    end
    return owner.total .. " (" .. table.concat(parts, ", ") .. ")"
end

local function nameColor(owner)
    if owner.warband then
        return 0.6, 0.8, 1
    end
    if opt("tooltip.classColors") and owner.class and C_ClassColor then
        local color = C_ClassColor.GetClassColor(owner.class)
        if color then
            return color:GetRGB()
        end
    end
    return 1, 0.82, 0
end

--- Lines for the item in `tip`: one per owner and the total.
function Inventory:AddLines(tip, itemID)
    local owners, total = self:Owners(itemID)
    if #owners == 0 then
        return
    end
    local detail = opt("tooltip.breakdown")
    tip:AddLine(" ")
    for _, owner in ipairs(owners) do
        local r, g, b = nameColor(owner)
        tip:AddDoubleLine(owner.name, detail and breakdown(owner) or tostring(owner.total), r, g, b, 1, 1, 1)
    end
    if opt("tooltip.total") and #owners > 1 then
        tip:AddDoubleLine(L.TOTAL, tostring(total), 0.64, 0.62, 0.72, 1, 1, 1)
    end
end

function Inventory:OnTooltipItem(tip, data)
    if not self.running or not opt("tooltip.enabled") or not modifierHeld() then
        return
    end
    -- Only GameTooltip-like frames (the comparison and embedded ones too, but not shopping lists).
    if not tip or not tip.AddDoubleLine or (tip.IsForbidden and tip:IsForbidden()) then
        return
    end
    local id = data and data.id
    if not id or secret(id) or type(id) ~= "number" then
        return
    end
    self:AddLines(tip, id)
end

-- Lifecycle ---------------------------------------------------------------------------------

local EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "BAG_UPDATE_DELAYED",
    "PLAYER_EQUIPMENT_CHANGED",
    "BANKFRAME_OPENED",
    "BANKFRAME_CLOSED",
    "PLAYERBANKSLOTS_CHANGED",
}

function Inventory:OnEvent(event)
    if event == "BANKFRAME_OPENED" then
        self.bankOpen = true
    elseif event == "BANKFRAME_CLOSED" then
        -- No last read: once closing, the bank bags may already report 0 slots.
        self.bankOpen = false
        return
    end
    if not self.running or not opt("inventory.track") then
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        self:ScanAll()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        self:ScanEquipped()
    elseif event == "BAG_UPDATE_DELAYED" then
        self:ScanBags()
        self:ScanBank()
    else
        self:ScanBank()
    end
end

function Inventory:InstallHooks()
    self.hooked = true
    if TooltipDataProcessor and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip, data)
            self:OnTooltipItem(tip, data)
        end)
    end
    -- Bank state is followed even while stopped, so enabling with the bank open knows it.
    local events = CreateFrame("Frame")
    for _, event in ipairs(EVENTS) do
        -- An event this client doesn't have errors on RegisterEvent: skip it.
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", function(_, event)
        self:OnEvent(event)
    end)
    self.events = events
end

function Inventory:Start()
    self.running = true
    if not self.hooked then
        self:InstallHooks()
        -- Enabled with the bank already open: the events of this visit were missed.
        self.bankOpen = _G.BankFrame ~= nil and _G.BankFrame:IsShown()
    end
    self:Bind()
    if opt("inventory.track") then
        self:ScanAll()
    end
end

function Inventory:Stop()
    self.running = false
end
