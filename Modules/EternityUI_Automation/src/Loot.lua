-- Loot and item automations: fast loot, opening containers and filling in "DELETE".

---@type string, EternityUIAutomationNamespace
local _, ns = ...
local Core = ns.Core

local Loot = {}
Core.Loot = Loot

Core.Add({
    id = "fastLoot",
    events = { "LOOT_READY" },
    Enabled = function()
        return Core.On("loot.fastLoot")
    end,
    OnEvent = function(_, _, autoLoot)
        if autoLoot == nil then
            autoLoot = GetCVarBool("autoLootDefault") ~= IsModifiedClick("AUTOLOOTTOGGLE")
        end
        if not autoLoot then
            return
        end
        -- From the end, so taking a slot doesn't shift the ones still to take. What doesn't fit
        -- stays in the loot window.
        for slot = GetNumLootItems(), 1, -1 do
            LootSlot(slot)
        end
    end,
})

-- Windows where using an item does something else (sell it, deposit it, trade it...).
local BUSY_FRAMES = {
    "MerchantFrame",
    "BankFrame",
    "MailFrame",
    "TradeFrame",
    "AuctionHouseFrame",
    "GuildBankFrame",
    "LootFrame",
    "EternityUILootWindow",
}

function Loot.Busy()
    if InCombatLockdown() then
        return true
    end
    for _, name in ipairs(BUSY_FRAMES) do
        local frame = _G[name]
        if frame and frame:IsShown() then
            return true
        end
    end
    return false
end

-- Slots already tried this session, so a locked box isn't used over and over.
local tried = {}

function Loot.NextContainer()
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local key = bag * 1000 + slot
            if info and info.hasLoot and not info.isLocked and tried[key] ~= info.itemID then
                return bag, slot, key, info.itemID
            end
        end
    end
    return nil
end

Core.Add({
    id = "openContainers",
    events = { "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED", "LOOT_CLOSED", "MERCHANT_CLOSED" },
    Enabled = function()
        return Core.On("loot.openContainers")
    end,
    OnEvent = function()
        if Loot.Busy() then
            return
        end
        -- One at a time: opening it changes the bags and brings the next BAG_UPDATE_DELAYED.
        local bag, slot, key, itemID = Loot.NextContainer()
        if bag then
            tried[key] = itemID
            C_Container.UseContainerItem(bag, slot)
        end
    end,
})

local DELETE_POPUPS = { DELETE_GOOD_ITEM = true, DELETE_GOOD_QUEST_ITEM = true }

local deleteConfirm = Core.Add({
    id = "fillDeleteConfirm",
    Enabled = function()
        return Core.On("loot.fillDeleteConfirm")
    end,
})

function deleteConfirm:OnApply(on)
    if not on or self.hooked then
        return
    end
    self.hooked = true
    hooksecurefunc("StaticPopup_Show", function(which)
        if not DELETE_POPUPS[which] or not Core.Active(self) then
            return
        end
        local dialog = StaticPopup_FindVisible(which)
        local editBox = dialog and (dialog.GetEditBox and dialog:GetEditBox() or dialog.editBox)
        if not editBox then
            return
        end
        editBox:SetText(DELETE_ITEM_CONFIRM_STRING)
        -- Text set from code doesn't enable Yes in Forever: run the dialog's own check.
        local info = StaticPopupDialogs[which]
        if info and info.EditBoxOnTextChanged then
            info.EditBoxOnTextChanged(editBox, dialog.data)
        end
    end)
end
