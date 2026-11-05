-- When a rule may show: its class, level, group, place, combat and the moments it hides in. Nobody
-- needs a reminder while dead, so that one isn't an option.

---@type string, EternityUIAlertsNamespace
local _, ns = ...

---@class EternityUIAlertsConditions
local Conditions = {}
ns.Conditions = Conditions

--- The player's state, read once per evaluation.
---@return table
function Conditions.Context()
    local _, class = UnitClass("player")
    local inInstance = IsInInstance()
    return {
        class = class,
        level = UnitLevel("player"),
        dead = UnitIsDeadOrGhost("player"),
        combat = InCombatLockdown(),
        resting = IsResting(),
        mounted = IsMounted(),
        raid = IsInRaid(),
        party = IsInGroup(),
        instance = inInstance,
    }
end

local GROUPS = {
    any = function()
        return true
    end,
    solo = function(context)
        return not context.party
    end,
    group = function(context)
        return context.party
    end,
    raid = function(context)
        return context.raid
    end,
}

--- Whether a rule may show now.
---@param rule EternityUIAlertsRule
---@param context table from Context
---@return boolean
function Conditions.Passes(rule, context)
    if context.dead then
        return false
    end
    if (rule.combat == "out" and context.combat) or (rule.combat == "in" and not context.combat) then
        return false
    end
    if (rule.hideResting and context.resting) or (rule.hideMounted and context.mounted) then
        return false
    end
    if rule.class ~= "" and rule.class ~= context.class then
        return false
    end
    if context.level < rule.minLevel then
        return false
    end
    if rule.place == "instance" and not context.instance then
        return false
    end
    if rule.place == "world" and context.instance then
        return false
    end
    local group = GROUPS[rule.group] or GROUPS.any
    return group(context) and true or false
end
