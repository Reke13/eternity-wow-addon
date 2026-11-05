-- Secret values: the one place that asks whether a value can be read. Nothing here tries to work
-- out what a secret holds; a secret is either passed untouched to a widget that accepts it or
-- replaced by a fallback.
---@type string, EternityUINamespace
local _, ns = ...

---@class EternitySecret
local Secret = {}
ns.Secret = Secret

--- True if value is secret. Comparing or doing arithmetic on such a value throws.
---@param value any
---@return boolean
function Secret.Is(value)
    return issecretvalue ~= nil and issecretvalue(value) or false
end

--- The value, or fallback if it's secret.
---@param value any
---@param fallback any
---@return any
function Secret.Plain(value, fallback)
    if Secret.Is(value) then
        return fallback
    end
    return value
end

--- True if none of the arguments is secret.
---@return boolean
function Secret.Known(...)
    for i = 1, select("#", ...) do
        if Secret.Is((select(i, ...))) then
            return false
        end
    end
    return true
end

--- True while auras are secret. This can start before InCombatLockdown() turns true.
---@return boolean
function Secret.AurasRestricted()
    return C_Secrets ~= nil and C_Secrets.ShouldAurasBeSecret() and true or false
end
