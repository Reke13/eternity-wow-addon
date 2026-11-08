-- What the container shows, from the options: pure data, no frames. Two aura groups:
--   * "tracked": the spells of the player's list (Spells.lua) to always show, whoever cast them,
--     first.
--   * "main": the rest, narrowed by the game's filter string (who cast it, crowd control,
--     dispellable) and without the tracked and hidden spells.
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

--- Both groups from the options and the list of spells.
---@param o table { origin, crowdControl, dispellable, max, show = set, hide = set }
---@return table groups { tracked = { enabled, filter, candidate, max }, main = { filter, candidate, max } }
function Filters.Groups(o)
    local show, hide = o.show or {}, o.hide or {}
    -- A spell both shown and hidden stays hidden.
    local include, count = {}, 0
    for id in pairs(show) do
        if not hide[id] then
            include[id] = true
            count = count + 1
        end
    end
    local skip = union(include, hide)
    return {
        tracked = {
            enabled = count > 0,
            filter = "HARMFUL",
            candidate = count > 0 and { includeSpellIDs = include } or nil,
            max = math.max(count, 1),
        },
        main = {
            filter = Filters.MainFilter(o),
            -- The tracked ones are already shown, and the hidden never are.
            candidate = skip and { excludeSpellIDs = skip } or nil,
            max = o.max,
        },
    }
end
