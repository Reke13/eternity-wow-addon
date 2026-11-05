-- What each kind of rule reads. A check returns firing, value and icon; firing nil means it can't
-- tell now (auras are secret in combat) and the rule keeps what it knew. Nothing here works out
-- what a secret holds: a secret value only makes the check give up.

---@type string, EternityUIAlertsNamespace
local _, ns = ...
local Rules = ns.Rules

local ICON_UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark"
local ICON_REPAIR = "Interface\\Icons\\Trade_BlackSmithing"
local ICON_BAGS = "Interface\\Icons\\INV_Misc_Bag_08"
local MAIN_HAND, OFF_HAND = 16, 17
local FIRST_ARMOR, LAST_EQUIPPED = 1, 18
-- The backpack, four bags and the reagent bag, whose family keeps it out of the count.
local LAST_BAG = 5
local MINUTE_MS = 60000
local MAX_AURAS = 40

---@class EternityUIAlertsChecks
local Checks = {}
ns.Checks = Checks

local function secret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

--- True while auras can't be read.
---@return boolean
function Checks.AurasRestricted()
    return C_Secrets ~= nil and C_Secrets.ShouldAurasBeSecret() and true or false
end

-- The buffs on the player, by spell ID and by lower case name. Read by index, the same call the
-- Rules tab lists them with: rules with Thorns or Mark of the Wild never cleared on the client with
-- the lookups by name and ID. A buff without a name or an ID (some zone and system auras) only
-- adds what it has; a secret one is skipped.
---@return table<number|string, boolean>?
local function playerBuffs()
    local buffs = {}
    for i = 1, MAX_AURAS do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok then
            return nil
        end
        if not aura then
            break
        end
        local id, name = aura.spellId, aura.name
        if type(id) == "number" and not secret(id) then
            buffs[id] = true
        end
        if type(name) == "string" and not secret(name) and name ~= "" then
            buffs[name:lower()] = true
        end
    end
    return buffs
end

-- A spell's name, to match an ID with any rank of the same buff (Forever's spells have ranks).
local function spellName(id)
    local ok, name = pcall(C_Spell.GetSpellName, id)
    if ok and type(name) == "string" and not secret(name) and name ~= "" then
        return name:lower()
    end
    return nil
end

local kinds = {}

-- Out of combat: an unreadable buff counts as not the one wanted. A rule that waited for every buff
-- to be readable could stay stuck for good on an aura the game always hides.
function kinds.buff(rule)
    local entries = Rules.Entries(rule.spells)
    if #entries == 0 then
        return false
    end
    if Checks.AurasRestricted() then
        return nil
    end
    local buffs = playerBuffs()
    if not buffs then
        return nil
    end
    for _, entry in ipairs(entries) do
        if type(entry) == "string" then
            if buffs[entry:lower()] then
                return false
            end
        elseif buffs[entry] then
            return false
        else
            local name = spellName(entry)
            if name and buffs[name] then
                return false
            end
        end
    end
    return true
end

-- The enchant on a weapon slot: true if it's fine, false if it fires, nil if it can't tell.
local function enchantFine(weaponSlot, threshold)
    local ok, enchants = pcall(C_Item.GetWeaponEnchantInfo, weaponSlot)
    if not ok or type(enchants) ~= "table" then
        return nil
    end
    for _, enchant in pairs(enchants) do
        if secret(enchant.hasEnchant) or secret(enchant.timeLeft) then
            return nil
        end
        if enchant.hasEnchant and enchant.timeLeft >= threshold * MINUTE_MS then
            return true
        end
    end
    return false
end

local function hasWeapon(slot)
    local id = GetInventoryItemID("player", slot)
    if not id then
        return false
    end
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(id)
    return classID == Enum.ItemClass.Weapon
end

function kinds.enchant(rule)
    local icon
    local firing = false
    local function check(wanted, inventorySlot, weaponSlot)
        if wanted and hasWeapon(inventorySlot) then
            local fine = enchantFine(weaponSlot, rule.threshold)
            if fine == nil then
                firing = nil
            elseif not fine and firing ~= nil then
                firing = true
                icon = icon or GetInventoryItemTexture("player", inventorySlot)
            end
        end
    end
    check(rule.slot ~= "off", MAIN_HAND, Enum.WeaponSlot.MainHand)
    check(rule.slot ~= "main", OFF_HAND, Enum.WeaponSlot.OffHand)
    return firing, nil, icon
end

--- The lowest durability among worn pieces, in percent, or nil if there's nothing to read.
---@return number?
function Checks.LowestDurability()
    local lowest
    for slot = FIRST_ARMOR, LAST_EQUIPPED do
        local current, maximum = GetInventoryItemDurability(slot)
        if secret(current) or secret(maximum) then
            return nil
        end
        if current and maximum and maximum > 0 then
            local percent = current / maximum * 100
            lowest = lowest and math.min(lowest, percent) or percent
        end
    end
    return lowest
end

function kinds.durability(rule)
    local lowest = Checks.LowestDurability()
    if not lowest then
        return nil
    end
    return lowest < rule.threshold, string.format("%d%%", math.floor(lowest)), ICON_REPAIR
end

--- Free slots in normal bags.
---@return number?
function Checks.FreeSlots()
    local total = 0
    for bag = 0, LAST_BAG do
        local free, family = C_Container.GetContainerNumFreeSlots(bag)
        if secret(free) or secret(family) then
            return nil
        end
        if family == 0 then
            total = total + free
        end
    end
    return total
end

function kinds.slots(rule)
    local free = Checks.FreeSlots()
    if not free then
        return nil
    end
    return free < rule.threshold, tostring(free), ICON_BAGS
end

function kinds.item(rule)
    local entry = Rules.Entries(rule.item)[1]
    if not entry then
        return false
    end
    local count = C_Item.GetItemCount(entry, false, true)
    if secret(count) then
        return nil
    end
    return count < rule.threshold, tostring(count), C_Item.GetItemIconByID(entry)
end

-- Free text from a rule can be anything: a lookup that fails is just no icon.
local function lookup(fn, entry)
    if entry == nil then
        return nil
    end
    local ok, icon = pcall(fn, entry)
    return ok and icon or nil
end

--- The icon a rule shows when its check gives none.
---@param rule EternityUIAlertsRule
---@return number|string
function Checks.Icon(rule)
    if rule.icon then
        return rule.icon
    end
    if rule.kind == "buff" then
        local entry = Rules.Entries(rule.spells)[1]
        return lookup(C_Spell.GetSpellTexture, entry) or ICON_UNKNOWN
    elseif rule.kind == "durability" then
        return ICON_REPAIR
    elseif rule.kind == "slots" then
        return ICON_BAGS
    elseif rule.kind == "item" then
        local entry = Rules.Entries(rule.item)[1]
        return lookup(C_Item.GetItemIconByID, entry) or ICON_UNKNOWN
    end
    return GetInventoryItemTexture("player", MAIN_HAND) or ICON_UNKNOWN
end

--- What clicking a rule's icon does: "spell" or "item" and which one, or nil.
---@param rule EternityUIAlertsRule
---@return string? action
---@return string? use
function Checks.Action(rule)
    if rule.kind ~= "buff" or not rule.click then
        return nil
    end
    local custom = Rules.Entries(rule.clickUse)[1]
    local entries = custom and { custom } or Rules.Entries(rule.spells)
    for _, entry in ipairs(entries) do
        -- By name it only answers for spells the character knows.
        local known = lookup(C_Spell.GetSpellInfo, entry)
        if known then
            return "spell", tostring(entry)
        end
    end
    if custom then
        return "item", type(custom) == "number" and ("item:" .. custom) or custom
    end
    return nil
end

--- Runs a rule's check.
---@param rule EternityUIAlertsRule
---@return boolean? firing
---@return string? value
---@return number|string? icon
function Checks.Run(rule)
    local check = kinds[rule.kind]
    if not check then
        return false
    end
    local ok, firing, value, icon = pcall(check, rule)
    if not ok then
        return nil
    end
    return firing, value, icon or Checks.Icon(rule)
end
