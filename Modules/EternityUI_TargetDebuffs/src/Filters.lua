-- What the container shows, from the options: pure data, no frames. Three aura groups:
--   * "tracked": the spells of the player's list (Spells.lua) shown whoever cast them, first.
--   * "mine": the spells of the list shown only when the player cast them, next.
--   * "main": the rest, narrowed by the game's filter string (who cast it, crowd control,
--     dispellable) and without any spell of the list: a "mine" one cast by someone else doesn't
--     show at all.
-- Both kinds of filter are evaluated by Blizzard's aura container, not here: the filter string
-- by the game, and the spell ID lists by the container's own code, which may match spell IDs
-- of debuffs on enemies even while they're secret to addons. That's why it works in combat.

---@type string, EternityUITargetDebuffsNamespace
local _, ns = ...

---@class EternityUITargetDebuffsFilters
local Filters = {}
ns.Filters = Filters

--- A set of spell IDs from text like "7386, 11597": { [id] = true }, how many, and the pieces
--- that weren't IDs.
---@param text string?
---@return table<integer, boolean> ids
---@return integer count
---@return string[] invalid
function Filters.ParseIDs(text)
    local ids, count, invalid = {}, 0, {}
    for piece in tostring(text or ""):gmatch("[^,;%s]+") do
        local id = tonumber(piece)
        if id and id > 0 and id == math.floor(id) then
            if not ids[id] then
                ids[id] = true
                count = count + 1
            end
        else
            invalid[#invalid + 1] = piece
        end
    end
    return ids, count, invalid
end

local function union(a, b)
    local out, any = {}, false
    for id in pairs(a) do
        out[id], any = true, true
    end
    for id in pairs(b) do
        out[id], any = true, true
    end
    return any and out or nil
end

--- The filter string of the main group.
---@param o table { origin, crowdControl, dispellable }
---@return string
function Filters.MainFilter(o)
    local tokens = { "HARMFUL" }
    if o.origin == "mine" then
        tokens[#tokens + 1] = "PLAYER"
    elseif o.origin == "others" then
        tokens[#tokens + 1] = "!PLAYER"
    end
    if o.crowdControl == "hide" then
        tokens[#tokens + 1] = "!CROWD_CONTROL"
    elseif o.crowdControl == "only" then
        tokens[#tokens + 1] = "CROWD_CONTROL"
    end
    if o.dispellable then
        tokens[#tokens + 1] = "DISPELLABLE"
    end
    return table.concat(tokens, "|")
end

local function listGroup(ids, filter)
    local count = 0
    for _ in pairs(ids) do
        count = count + 1
    end
    return {
        enabled = count > 0,
        filter = filter,
        candidate = count > 0 and { includeSpellIDs = ids } or nil,
        -- A spell may be on the target more than once (several casters).
        max = math.max(count * 2, 1),
    }
end

--- The three groups from the options and the list of spells.
---@param o table { origin, crowdControl, dispellable, max, always = set, mine = set }
---@return table groups { tracked, mine, main = { enabled?, filter, candidate, max } }
function Filters.Groups(o)
    local always, mine = {}, {}
    for id in pairs(o.always or {}) do
        always[id] = true
    end
    -- A spell in both stays "always".
    for id in pairs(o.mine or {}) do
        if not always[id] then
            mine[id] = true
        end
    end
    local skip = union(always, mine)
    return {
        tracked = listGroup(always, "HARMFUL"),
        mine = listGroup(mine, "HARMFUL|PLAYER"),
        main = {
            enabled = true,
            filter = Filters.MainFilter(o),
            -- The listed ones show in their own groups, or not at all.
            candidate = skip and { excludeSpellIDs = skip } or nil,
            max = o.max,
        },
    }
end
