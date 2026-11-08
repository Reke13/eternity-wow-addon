-- What a frame's container shows, from its options: pure data, no frames. Three aura groups:
--   * "tracked": the spells of the frame's list (Spells.lua) shown whoever cast them, first.
--   * "mine": the spells of the list shown only when the player cast them, next.
--   * "main": the rest, narrowed by the game's filter string (who cast it, crowd control,
--     dispellable) and the candidate filters (duration), without any spell of the list: a
--     "mine" one cast by someone else doesn't show at all.
-- Every filter is evaluated by Blizzard's aura container, not here: the filter string by the
-- game, and the spell ID lists by the container's own code, which matches spell IDs of debuffs
-- on enemies and of the player's own buffs even while they're secret to addons. That's why it
-- works in combat.

---@type string, EternityUIAurasNamespace
local _, ns = ...

---@class EternityUIAurasFilters
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

local function base(o)
    return o.filter or "HARMFUL"
end

--- The filter string of the main group.
---@param o table { filter = "HARMFUL"|"HELPFUL", origin, crowdControl?, dispellable? }
---@return string
function Filters.MainFilter(o)
    local tokens = { base(o) }
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

-- Longer than any aura: "only the ones that run out" (the container's maxDuration always leaves
-- out auras without a duration).
local NO_LIMIT = 365 * 24 * 3600

--- The longest duration the main group shows, in seconds, or nil for any (and permanent ones).
---@param o table { duration = "all"|"timed"|"short", maxMinutes }
---@return number?
function Filters.MaxDuration(o)
    if o.duration == "timed" then
        return NO_LIMIT
    elseif o.duration == "short" then
        return (o.maxMinutes or 5) * 60
    end
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
        -- A spell may be on the unit more than once (several casters).
        max = math.max(count * 2, 1),
    }
end

--- The three groups from the options and the list of spells.
---@param o table { filter, onlyList, origin, crowdControl, dispellable, duration, maxMinutes, max, always = set, mine = set }
---@return table groups { tracked, mine, main = { enabled, filter, candidate, max } }
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
    local candidate, any = {}, false
    -- The listed ones show in their own groups, or not at all.
    local skip = union(always, mine)
    if skip then
        candidate.excludeSpellIDs, any = skip, true
    end
    local maxDuration = Filters.MaxDuration(o)
    if maxDuration then
        candidate.maxDuration, any = maxDuration, true
    end
    return {
        tracked = listGroup(always, base(o)),
        mine = listGroup(mine, base(o) .. "|PLAYER"),
        main = {
            -- "Only my list": the rest of the auras stay out.
            enabled = not o.onlyList,
            filter = Filters.MainFilter(o),
            candidate = any and candidate or nil,
            max = o.max,
        },
    }
end
