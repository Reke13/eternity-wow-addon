-- Death and travel automations: accept resurrections and summons, release in battlegrounds and
-- dismount at flight masters.

---@type string, EternityUIAutomationNamespace
local _, ns = ...
local Core, L = ns.Core, ns.L

local RESURRECT_POPUPS = { "RESURRECT", "RESURRECT_NO_SICKNESS", "RESURRECT_NO_TIMER" }

Core.Add({
    id = "acceptResurrect",
    events = { "RESURRECT_REQUEST" },
    Enabled = function()
        return Core.On("death.acceptResurrect")
    end,
    OnEvent = function(_, _, offerer)
        -- A combat resurrection in the middle of a fight is the player's call.
        if type(offerer) == "string" and not Core.Secret(offerer) and UnitAffectingCombat(offerer) then
            return
        end
        AcceptResurrect()
        for _, which in ipairs(RESURRECT_POPUPS) do
            StaticPopup_Hide(which)
        end
        Core.Report(L.RESURRECT_ACCEPTED, Core.Name(offerer))
    end,
})

Core.Add({
    id = "acceptSummon",
    events = { "CONFIRM_SUMMON" },
    Enabled = function()
        return Core.On("death.acceptSummon")
    end,
    OnEvent = function()
        if InCombatLockdown() or not C_SummonInfo then
            return
        end
        -- Blizzard's popup is set up on the same event; confirm a moment later.
        Core.After(1, function()
            if InCombatLockdown() or C_SummonInfo.GetSummonConfirmTimeLeft() <= 0 then
                return
            end
            local summoner = C_SummonInfo.GetSummonConfirmSummoner()
            local area = C_SummonInfo.GetSummonConfirmAreaName()
            C_SummonInfo.ConfirmSummon()
            StaticPopup_Hide("CONFIRM_SUMMON")
            Core.Report(L.SUMMON_ACCEPTED, Core.Name(summoner), Core.Name(area))
        end)
    end,
})

local function canSelfResurrect()
    local options = C_DeathInfo and C_DeathInfo.GetSelfResurrectOptions and C_DeathInfo.GetSelfResurrectOptions()
    return type(options) == "table" and #options > 0
end

local function inBattleground()
    if C_PvP and C_PvP.IsBattleground and C_PvP.IsBattleground() then
        return true
    end
    local _, kind = IsInInstance()
    return kind == "pvp"
end

Core.Add({
    id = "releaseInBattleground",
    events = { "PLAYER_DEAD" },
    Enabled = function()
        return Core.On("death.releaseInBattleground")
    end,
    OnEvent = function()
        if not inBattleground() or canSelfResurrect() then
            return
        end
        Core.After(0.5, function()
            local suppressed = C_InstanceEncounter
                and C_InstanceEncounter.IsEncounterSuppressingRelease
                and C_InstanceEncounter.IsEncounterSuppressingRelease()
            if UnitIsDead("player") and not UnitIsGhost("player") and not suppressed then
                RepopMe()
            end
        end)
    end,
})

Core.Add({
    id = "dismountOnTaxi",
    events = { "TAXIMAP_OPENED" },
    Enabled = function()
        return Core.On("death.dismountOnTaxi")
    end,
    OnEvent = function()
        if IsMounted() and not IsFlying() then
            Dismount()
        end
    end,
})
