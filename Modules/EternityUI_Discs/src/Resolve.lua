-- From stored slots to what the disc shows and does on this character: each slot becomes a node
-- with a label, an icon and either the secure action attributes or the children of a sub-disc.
-- Hearthstone and Professions are resolved here, so the same disc works on every character.
-- Also: what the cursor holds (drag and drop) and searching by name or ID.

---@type string, EternityUIDiscsNamespace
local addonName, ns = ...
local E = EternityUI
local L = ns.L

---What a slot does on this character.
---@class EternityUIDiscsNode
---@field label string
---@field icon number|string
---@field attrs table<string, any>? secure action attributes (type, spell, item, toy, macro, macrotext)
---@field children EternityUIDiscsNode[]? a sub-disc
---@field spell number? for cooldowns
---@field item number? for counts and cooldowns
---@field missing boolean? not available on this character (no item, unknown spell...)

---@class EternityUIDiscsResolve
local Resolve = {}
ns.Resolve = Resolve

local QUESTION = 134400 -- INV_Misc_QuestionMark
local HEARTHSTONE_ITEM = 6948
-- Hearthstone toys (same destination as the item). PlayerHasToy filters the ones the client
-- doesn't have or the character doesn't own.
local HEARTHSTONE_TOYS = {
    54452,
    64488,
    93672,
    142542,
    162973,
    163045,
    165669,
    165670,
    165802,
    166746,
    166747,
    168907,
    172179,
    188952,
    190237,
    193588,
    200630,
    208704,
    209035,
    212337,
    228940,
}
local MAX_DEPTH = 8

---@type table?
local ToyBox = _G.C_ToyBox

local function opt(path)
    return E.store:Get(addonName, path)
end

local function spellInfo(id)
    local info = C_Spell.GetSpellInfo(id)
    if info then
        return info.name, info.iconID, info.spellID
    end
end

local function itemName(id)
    return C_Item.GetItemNameByID(id) or ("item:" .. id)
end

local function itemIcon(id)
    return C_Item.GetItemIconByID(id) or QUESTION
end

local function ownsToy(id)
    return PlayerHasToy and PlayerHasToy(id) or false
end

--- The hearthstone the option picks: { kind = "toy" | "item", id }.
function Resolve.Hearthstone()
    local mode = opt("general.hearthstone")
    if mode ~= "item" then
        local owned = {}
        for _, id in ipairs(HEARTHSTONE_TOYS) do
            if ownsToy(id) then
                owned[#owned + 1] = id
            end
        end
        if #owned > 0 then
            return { kind = "toy", id = mode == "random" and owned[math.random(#owned)] or owned[1] }
        end
    end
    return { kind = "item", id = HEARTHSTONE_ITEM }
end

-- Spells of a profession (its line in the spellbook), without passives.
local function professionSpells(index)
    local name, icon, _, _, numAbilities, offset = GetProfessionInfo(index)
    local spells = {}
    local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    for i = 1, numAbilities or 0 do
        local info = C_SpellBook.GetSpellBookItemInfo(offset + i, bank)
        if info and info.spellID and not info.isPassive then
            spells[#spells + 1] = { kind = "spell", id = info.spellID }
        end
    end
    return name, icon, spells
end

--- The character's professions as slots: one spell each, or a sub-disc with all its abilities.
---@return EternityUIDiscsSlot[]
function Resolve.Professions()
    local primary1, primary2, archaeology, fishing, cooking = GetProfessions()
    local secondary = opt("general.secondary")
    local indexes = {
        primary1,
        primary2,
        secondary and cooking,
        secondary and fishing,
        secondary and archaeology,
    }
    local slots = {}
    for i = 1, 5 do
        local index = indexes[i]
        if index then
            local name, icon, spells = professionSpells(index)
            if #spells > 1 and opt("general.abilities") then
                slots[#slots + 1] = { kind = "group", name = name, icon = icon, slots = spells }
            elseif spells[1] then
                slots[#slots + 1] = spells[1]
            end
        end
    end
    return slots
end

local nodeOf

-- A list of slots → nodes. Dynamic slots (professions) expand in place.
local function nodesOf(slots, depth, path)
    local nodes = {}
    for _, slot in ipairs(slots) do
        if slot.kind == "professions" then
            for _, generated in ipairs(Resolve.Professions()) do
                nodes[#nodes + 1] = nodeOf(generated, depth, path)
            end
        else
            local node = nodeOf(slot, depth, path)
            if node then
                nodes[#nodes + 1] = node
            end
        end
    end
    return nodes
end

--- One slot → node (nil for a sub-disc that would loop or go too deep).
---@param slot table
---@param depth integer?
---@param path table<number, boolean>? discs already open above (against loops)
---@return EternityUIDiscsNode?
function nodeOf(slot, depth, path)
    depth, path = depth or 0, path or {}
    local node
    local kind = slot.kind
    if kind == "hearthstone" then
        local stone = Resolve.Hearthstone()
        node = nodeOf(stone, depth, path)
        if node then
            node.label = L.HEARTHSTONE
        end
    elseif kind == "spell" then
        local name, icon = spellInfo(slot.id)
        node = {
            label = name or ("spell:" .. tostring(slot.id)),
            icon = icon or QUESTION,
            attrs = { type = "spell", spell = slot.id },
            spell = slot.id,
            missing = name == nil,
        }
    elseif kind == "item" then
        node = {
            label = itemName(slot.id),
            icon = itemIcon(slot.id),
            attrs = { type = "item", item = "item:" .. slot.id },
            item = slot.id,
        }
    elseif kind == "toy" then
        node = {
            label = itemName(slot.id),
            icon = itemIcon(slot.id),
            attrs = { type = "toy", toy = slot.id },
            item = slot.id,
            missing = not ownsToy(slot.id),
        }
    elseif kind == "macro" then
        local name, icon = GetMacroInfo(slot.macro or "")
        node = {
            label = name or slot.macro or "?",
            icon = icon or QUESTION,
            attrs = { type = "macro", macro = slot.macro },
            missing = name == nil,
        }
    elseif kind == "text" then
        local first = (slot.text or ""):match("^[^\n]*")
        node = {
            label = first ~= "" and first or L.KIND_text,
            icon = QUESTION,
            attrs = { type = "macro", macrotext = slot.text or "" },
        }
    elseif kind == "disc" or kind == "group" then
        local disc = kind == "disc" and ns.Store:Get(slot.disc) or slot
        if not disc or depth >= MAX_DEPTH or (kind == "disc" and path[slot.disc]) then
            return nil
        end
        if kind == "disc" then
            path[slot.disc] = true
        end
        local children = nodesOf(disc.slots, depth + 1, path)
        if kind == "disc" then
            path[slot.disc] = nil
        end
        node = {
            label = disc.name or L.KIND_disc,
            icon = disc.icon or (children[1] and children[1].icon) or QUESTION,
            children = children,
        }
    else
        return nil
    end
    if slot.name and slot.name ~= "" then
        node.label = slot.name
    end
    if slot.icon then
        node.icon = slot.icon
    end
    return node
end

Resolve.Node = nodeOf

--- A whole disc as a node (its slots are the children).
---@param disc EternityUIDiscsDisc
---@return EternityUIDiscsNode
function Resolve.Disc(disc)
    local children = nodesOf(disc.slots, 0, { [disc.id] = true })
    return {
        label = disc.name,
        icon = disc.icon or (children[1] and children[1].icon) or QUESTION,
        children = children,
    }
end

--- How the editor lists a stored slot: label, icon and kind text.
function Resolve.Describe(slot)
    if slot.kind == "professions" then
        return slot.name or L.PROFESSIONS, slot.icon or 136243, L.KIND_professions
    end
    local node = nodeOf(slot) or { label = L.MISSING, icon = QUESTION }
    return node.label, node.icon, L["KIND_" .. slot.kind]
end

-- Cursor and search ----------------------------------------------------------------------------

local function itemSlot(id)
    if ownsToy(id) and ToyBox and ToyBox.GetToyInfo and ToyBox.GetToyInfo(id) then
        return { kind = "toy", id = id }
    end
    return { kind = "item", id = id }
end

--- What the cursor holds as a slot (spell, item, toy, macro or mount), or nil.
---@return EternityUIDiscsSlot?
function Resolve.FromCursor()
    local kind, a, b, c = GetCursorInfo()
    if kind == "spell" then
        local id = c or b
        return type(id) == "number" and { kind = "spell", id = id } or nil
    elseif kind == "item" and type(a) == "number" then
        return itemSlot(a)
    elseif kind == "toy" and type(a) == "number" then
        return { kind = "toy", id = a }
    elseif kind == "macro" and a then
        local name = GetMacroInfo(a)
        return name and { kind = "macro", macro = name } or nil
    elseif kind == "mount" and C_MountJournal and C_MountJournal.GetMountInfoByID then
        local _, spellID = C_MountJournal.GetMountInfoByID(a)
        return spellID and { kind = "spell", id = spellID } or nil
    end
end

--- A spell or item by name or ID (spells first: the spellbook knows them by name).
---@param text string
---@return EternityUIDiscsSlot?
function Resolve.Search(text)
    text = strtrim(text or "")
    if text == "" then
        return nil
    end
    local number = tonumber(text)
    local _, _, spellID = spellInfo(number or text)
    if spellID then
        return { kind = "spell", id = spellID }
    end
    local itemID = C_Item.GetItemInfoInstant(number or text)
    if itemID then
        return itemSlot(itemID)
    end
end

--- An icon from an ID or from a spell's or item's name.
---@return number|string|nil
function Resolve.Icon(text)
    text = strtrim(text or "")
    local number = tonumber(text)
    if number and number > 100000 then
        return number -- a fileID
    end
    local _, icon = spellInfo(number or text)
    if icon then
        return icon
    end
    local itemID, _, _, _, itemIcon2 = C_Item.GetItemInfoInstant(number or text)
    if itemID then
        return itemIcon2
    end
    return number
end
