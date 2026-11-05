-- Work that can't happen in combat waits here until PLAYER_REGEN_ENABLED. Each key keeps only its
-- latest function, so a value changed five times during a fight is applied once, in order of the
-- key's first request.
---@type string, EternityUINamespace
local _, ns = ...
local Events = ns.Events

---@class EternityCombat
local Combat = {}
ns.Combat = Combat
EternityUI.Combat = Combat

local order = {} -- keys, oldest first
local queued = {} -- key -> fn

--- Runs fn now, or after combat if combat lockdown is on.
---@param key any identifies the job; defaults to fn
---@param fn function
function Combat.Run(key, fn)
    if not InCombatLockdown() then
        queued[key] = nil
        fn()
        return
    end
    if queued[key] == nil then
        order[#order + 1] = key
    end
    queued[key] = fn
end

--- Jobs waiting for the end of combat.
---@return integer
function Combat.Pending()
    local count = 0
    for _ in pairs(queued) do
        count = count + 1
    end
    return count
end

--- Runs every waiting job. Exposed for tests; PLAYER_REGEN_ENABLED calls it.
function Combat.Flush()
    local keys = order
    order = {}
    for _, key in ipairs(keys) do
        local fn = queued[key]
        queued[key] = nil
        if fn then
            local ok, err = pcall(fn)
            if not ok then
                geterrorhandler()(err)
            end
        end
    end
end

Events.On("PLAYER_REGEN_ENABLED", Combat, Combat.Flush)
