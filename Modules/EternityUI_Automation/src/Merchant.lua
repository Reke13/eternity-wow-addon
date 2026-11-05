-- Merchant automations: sell junk and repair (guild funds first, then your own gold).

---@type string, EternityUIAutomationNamespace
local _, ns = ...
local Core, L = ns.Core, ns.L

local Merchant = {}
Core.Merchant = Merchant

--- Which money pays a repair: "guild", "player" or nil (none can). Pure, for the tests.
---@param mode string "off" | "player" | "guild"
---@param cost number
---@param guildCan boolean the guild bank can repair and you're in a guild
---@param guildMoney number what you may withdraw (-1 = no limit)
---@param money number your gold
function Merchant.RepairSource(mode, cost, guildCan, guildMoney, money)
    if mode == "off" or not cost or cost <= 0 then
        return nil
    end
    if mode == "guild" and guildCan and (guildMoney == -1 or guildMoney >= cost) then
        return "guild"
    end
    if money >= cost then
        return "player"
    end
    return nil
end

Core.Add({
    id = "sellJunk",
    events = { "MERCHANT_SHOW" },
    Enabled = function()
        return Core.On("merchant.sellJunk")
    end,
    OnEvent = function()
        local junk = C_MerchantFrame
        if not junk or not junk.SellAllJunkItems or not junk.GetNumJunkItems or junk.GetNumJunkItems() == 0 then
            return
        end
        if junk.IsSellAllJunkEnabled and not junk.IsSellAllJunkEnabled() then
            return
        end
        local before = GetMoney()
        junk.SellAllJunkItems()
        -- The money arrives a moment later.
        Core.After(1, function()
            local gained = GetMoney() - before
            if gained > 0 then
                Core.Report(L.SOLD_JUNK, Core.Money(gained))
            end
        end)
    end,
})

local function repair(useGuild)
    local cost = GetRepairAllCost()
    RepairAllItems(useGuild)
    Core.Report(useGuild and L.REPAIRED_GUILD or L.REPAIRED, Core.Money(cost))
end

Core.Add({
    id = "repair",
    events = { "MERCHANT_SHOW" },
    Enabled = function()
        return Core.On("merchant.repair")
    end,
    OnEvent = function()
        if not CanMerchantRepair() then
            return
        end
        local cost, needed = GetRepairAllCost()
        if not needed or cost <= 0 then
            return
        end
        local guildCan = IsInGuild() and CanGuildBankRepair ~= nil and CanGuildBankRepair() or false
        local guildMoney = guildCan and GetGuildBankWithdrawMoney() or 0
        local source = Merchant.RepairSource(Core.Opt("merchant.repair"), cost, guildCan, guildMoney, GetMoney())
        if source == "guild" then
            repair(true)
            -- The guild's daily limit can still refuse it: whatever is left goes on your gold.
            Core.After(0.5, function()
                local left = GetRepairAllCost()
                if left and left > 0 and GetMoney() >= left and CanMerchantRepair() then
                    repair(false)
                end
            end)
        elseif source == "player" then
            repair(false)
        else
            Core.Report(L.REPAIR_NO_MONEY, Core.Money(cost))
        end
    end,
})
