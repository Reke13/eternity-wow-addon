-- EternityUI_Bags: data of the saved view. What any character of the account carried in the
-- bags, had in the bank or saw in its guild bank, from what Inventory saved (EternityUIBagsDB).
-- Bags.lua shows it in its own windows: the bags window switches to another character's bags,
-- and a window built like the real bank's (Grid, kind "saved") shows the banks. Their buttons are
-- plain item buttons: nothing can be used, and it works anywhere, with no bank open.

---@type string, EternityUIBagsNamespace
local _, ns = ...
local E = EternityUI
local Widgets = E.Widgets
local L, Inventory = ns.L, ns.Inventory

---@class EternityUIBagsViewer
---@field PLACES string[] what the saved bank window shows: bank, guild
---@field Open fun(place: string, realm: string?, name: string?, beside: table?) set by Bags.lua
local Viewer = { PLACES = { "bank", "guild" } }
ns.Viewer = Viewer

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
---@param place string bags, bank or guild
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

--- Title of a saved container: a guild tab's name, or the bank bag's.
---@param container EternityUIBagsContainer
---@param index integer
---@return string
function Viewer.ContainerTitle(container, index)
    if container.name and container.name ~= "" then
        return container.name
    elseif container.kind == "reagent" then
        return L.REAGENTS
    elseif container.kind == "keyring" then
        return L.KEYRING
    elseif container.kind == "backpack" then
        return L.BAGS
    elseif container.kind == "bag" then
        return L.BAG_N:format(index - 1)
    end
    return L.TAB_N:format(index)
end

-- Slots ----------------------------------------------------------------------------------------

--- Icon, quality and name of an item, from what was saved or the client's cache.
---@param id integer
---@return number|string icon
---@return integer? quality
---@return string? name
function Viewer.ItemData(id)
    local saved = Inventory:Bind().items[id] or {}
    local icon = saved.icon or (C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or 134400
    local quality = saved.quality
    if quality == nil and C_Item.GetItemQualityByID then
        quality = C_Item.GetItemQualityByID(id)
    end
    return icon, quality, saved.name
end

function Viewer.OnEnter(slot)
    if not slot.itemID then
        return
    end
    GameTooltip:SetOwner(slot, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(slot.itemID)
    GameTooltip:AddLine(L.SHIFT_LINK, 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

function Viewer.OnLeave(slot)
    if GameTooltip:IsOwned(slot) then
        GameTooltip:Hide()
    end
end

function Viewer.OnClick(slot)
    if slot.itemID and IsModifiedClick() then
        local _, link = C_Item.GetItemInfo(slot.itemID)
        if link then
            HandleModifiedItemClick(link)
        end
    end
end

-- Characters -------------------------------------------------------------------------------------

--- Menu of the remembered characters; onPick(realm, name).
function Viewer.CharacterMenu(owner, onPick)
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
