-- /etbags taint: a diagnostic for blocked item use ("EternityUI_Bags was forbidden to call
-- UNKNOWN()"). A few seconds after the command it checks, for the bag item under the mouse,
-- every value Blizzard's ContainerFrameItemButton_OnClick reads before UseContainerItem: the
-- button's own methods and fields, and the globals and frame fields on that path. Anything an
-- addon wrote taints the click; issecurevariable names which addon did it.
-- It only reads: nothing is changed, hooked or stored.

---@type string, EternityUIBagsNamespace
local _, ns = ...
local L = ns.L

local Taint = {}
ns.Taint = Taint

local DELAY = 3

-- On the button (ContainerFrameItemButtonMixin and ItemButton).
local BUTTON_KEYS = {
    "OnClick",
    "GetBagID",
    "GetSlotAndBagID",
    "bagID",
    "OnModifiedClick",
    "GetItemLocation",
    "SetItemButtonTexture",
    "UpdateTooltip",
}

-- Globals the click path reads.
local GLOBALS = {
    "ContainerFrameItemButton_OnClick",
    "ContainerFrameItemButtonMixin",
    "MerchantFrame_ResetRefundItem",
    "MerchantFrame_SetRefundItem",
    "MerchantFrame",
    "BankFrame",
    "GuildBankFrame",
    "MailFrame",
    "TradeFrame",
    "AuctionHouseFrame",
    "AuctionFrame",
    "AzeriteRespecFrame",
    "RuneforgeFrame",
    "ItemUpgradeFrame",
    "ObliterumForgeFrame",
    "ChallengesKeystoneFrame",
    "StackSplitFrame",
    "ItemButtonUtil",
    "ItemLocation",
    "BankUtil_IsAccountBankDepositRefundable",
    "C_Container",
    "C_Spell",
    "C_Item",
    "C_Cursor",
    "SpellCanTargetItem",
    "SpellCanTargetItemID",
    "IsModifiedClick",
    "GetCursorInfo",
    "CursorHasItem",
    "EventRegistry",
}

-- Fields of Blizzard frames read on the path: { global, field }.
local FIELDS = {
    { "BankFrame", "BankPanel" },
    { "BankFrame", "GetActiveBankType" },
    { "MerchantFrame", "refundItem" },
    { "MerchantFrame", "selectedTab" },
    { "ItemButtonUtil", "MarkItemSelectionFromBag" },
    { "ItemButtonUtil", "ClearPendingItemSelectionSource" },
    { "C_Container", "UseContainerItem" },
}

local function check(found, label, secure, by)
    if not secure then
        found[#found + 1] = ("%s (%s)"):format(label, by or "?")
    end
end

--- Every tainted value on the click path of `button`, as "name (addon)".
---@param button table
---@return string[]
function Taint.Check(button)
    local found = {}
    for _, key in ipairs(BUTTON_KEYS) do
        check(found, "button." .. key, issecurevariable(button, key))
    end
    local parent = button.GetParent and button:GetParent()
    if parent then
        check(found, "parent.GetID", issecurevariable(parent, "GetID"))
    end
    for _, name in ipairs(GLOBALS) do
        check(found, name, issecurevariable(name))
    end
    for _, pair in ipairs(FIELDS) do
        local owner = _G[pair[1]]
        if type(owner) == "table" then
            check(found, pair[1] .. "." .. pair[2], issecurevariable(owner, pair[2]))
        end
    end
    local panel = _G.BankFrame and _G.BankFrame.BankPanel
    if type(panel) == "table" then
        check(found, "BankFrame.BankPanel.bankType", issecurevariable(panel, "bankType"))
    end
    return found
end

--- The bag item button under the mouse, or nil.
local function hovered()
    local focus = GetMouseFoci and GetMouseFoci()[1]
    if focus and focus.GetBagID and focus.GetID then
        return focus
    end
end

function Taint.Run()
    print(L.TAINT_HOVER:format(DELAY))
    C_Timer.After(DELAY, function()
        local button = hovered()
        if not button then
            print(L.TAINT_NO_BUTTON)
            return
        end
        local found = Taint.Check(button)
        if #found == 0 then
            print(L.TAINT_NONE)
            return
        end
        print(L.TAINT_FOUND)
        for _, line in ipairs(found) do
            print("  " .. line)
        end
    end)
end

_G.SLASH_ETERNITYBAGS1 = "/etbags"
SlashCmdList.ETERNITYBAGS = function(msg)
    if (msg or ""):lower():match("^%s*taint") then
        Taint.Run()
    else
        print(L.TAINT_HELP)
    end
end
