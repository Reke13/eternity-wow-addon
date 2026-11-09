-- EternityUI_UnitFrames: the player's buff filters (EternityUIUnitFramesDB, for the account).
-- A filter has a name, a list of spells and the frames it applies to. On those frames its spells
-- show first (AuraBox.lua: "Always" ones whoever cast them, "Only mine" ones when the player
-- cast them) and, with the frame's "Only the ones of the filters", nothing else shows.
-- Spell IDs can be tested by Blizzard's aura container on buffs of friendly units (you, your
-- group and raid, their pets), which is what the filters are for.
-- An entry is a spell ID, or a name: the container only matches IDs, so a name keeps every ID
-- found with that name (all its ranks). They're found in the player's own spells and auras at
-- once, and by going through the game's spell list in the background, a slice per frame and
-- never in combat. The "Filters" tab edits them (FiltersTab.lua).

---@type string, EternityUIUnitFramesNamespace
local _, ns = ...

---@class EternityUIUnitFramesSpell
---@field id integer? a spell ID entry
---@field name string? a name entry, as typed
---@field ids integer[]? (name) the IDs found with that name
---@field searching boolean? (name) still going through the spell list
---@field enabled boolean
---@field mine boolean? only when the player (or their pet) cast it

---@class EternityUIUnitFramesFilter
---@field id integer
---@field name string
---@field spells EternityUIUnitFramesSpell[]
---@field frames table<string, boolean> frame keys it applies to

---@class EternityUIUnitFramesFilters
---@field onChange fun(keys: table<string, boolean>)? after a change, with the frames it touches
---@field onProgress fun(filter: EternityUIUnitFramesFilter, entry: EternityUIUnitFramesSpell, done: number)?
local Filters = {
    SEARCH_LAST = 500000, -- highest spell ID looked at by name
    SEARCH_STEP = 4000, -- spell IDs looked at per frame
}
ns.Filters = Filters

local function secret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

local function key(name)
    return (tostring(name):gsub("^%s+", ""):gsub("%s+$", "")):lower()
end

local function root()
    local saved = _G.EternityUIUnitFramesDB
    if type(saved) ~= "table" then
        saved = {}
        _G.EternityUIUnitFramesDB = saved
    end
    if type(saved.filters) ~= "table" then
        saved.filters = {}
    end
    saved.nextId = type(saved.nextId) == "number" and saved.nextId or 1
    return saved
end

-- Tells the frames a filter applies to (and any other frame key given) that it changed.
local function changed(filter, also)
    if not Filters.onChange then
        return
    end
    local keys = {}
    for key in pairs(filter and filter.frames or {}) do
        keys[key] = true
    end
    if also then
        keys[also] = true
    end
    Filters.onChange(keys)
end

--- Every filter, in the order they were made.
---@return EternityUIUnitFramesFilter[]
function Filters.All()
    return root().filters
end

--- A filter by its id, or nil.
---@param id integer?
---@return EternityUIUnitFramesFilter?
function Filters.Get(id)
    for _, filter in ipairs(Filters.All()) do
        if filter.id == id then
            return filter
        end
    end
    return nil
end

--- Makes a filter. The name is made unique ("Healers", "Healers 2"...).
---@param name string?
---@return EternityUIUnitFramesFilter
function Filters.Create(name)
    local saved = root()
    name = Filters.UniqueName(name)
    local filter = { id = saved.nextId, name = name, spells = {}, frames = {} }
    saved.nextId = saved.nextId + 1
    saved.filters[#saved.filters + 1] = filter
    changed(filter)
    return filter
end

--- A name no other filter has, from the one wanted.
---@param wanted string?
---@param except EternityUIUnitFramesFilter? a filter whose own name doesn't count
---@return string
function Filters.UniqueName(wanted, except)
    local base = tostring(wanted or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if base == "" then
        base = ns.L.FILTER_DEFAULT
    end
    local function taken(name)
        for _, filter in ipairs(Filters.All()) do
            if filter ~= except and key(filter.name) == key(name) then
                return true
            end
        end
        return false
    end
    local name, n = base, 1
    while taken(name) do
        n = n + 1
        name = base .. " " .. n
    end
    return name
end

function Filters.Rename(filter, name)
    filter.name = Filters.UniqueName(name, filter)
    changed(filter)
end

function Filters.Delete(filter)
    local list = Filters.All()
    for i, other in ipairs(list) do
        if other == filter then
            Filters.DropSearches(filter)
            table.remove(list, i)
            changed(filter)
            return
        end
    end
end

--- Applies a filter to a frame, or stops applying it.
function Filters.SetFrame(filter, frameKey, on)
    filter.frames[frameKey] = on and true or nil
    changed(filter, frameKey)
end

--- The spells of the filters applied to a frame, switched on: shown whoever cast them, and shown
--- only when mine.
---@param frameKey string
---@return table<integer, boolean> always
---@return table<integer, boolean> mine
function Filters.SetsFor(frameKey)
    local always, mine = {}, {}
    for _, filter in ipairs(Filters.All()) do
        if filter.frames[frameKey] then
            for _, spell in ipairs(filter.spells) do
                if spell.enabled then
                    local set = spell.mine and mine or always
                    if spell.id then
                        set[spell.id] = true
                    end
                    for _, id in ipairs(spell.ids or {}) do
                        set[id] = true
                    end
                end
            end
        end
    end
    -- A spell in both stays "always".
    for id in pairs(always) do
        mine[id] = nil
    end
    return always, mine
end

--- Whether any filter applies to a frame.
function Filters.AppliesTo(frameKey)
    for _, filter in ipairs(Filters.All()) do
        if filter.frames[frameKey] then
            return true
        end
    end
    return false
end

-- Spells ------------------------------------------------------------------------------------------

--- Name and icon of a spell ID, when the client knows them.
---@param id integer
---@return string? name
---@return number|string? icon
function Filters.Info(id)
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
    if secret(name) then
        name = nil
    end
    if secret(icon) then
        icon = nil
    end
    return name, icon
end

--- A unit's buffs with their spell IDs: { name, id, icon }. nil while the game hides them (in
--- combat), {} when the unit isn't there.
---@param unit string
---@return table[]?
function Filters.Auras(unit)
    local list = {}
    if not UnitExists(unit) then
        return list
    end
    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
        if not ok then
            return nil
        end
        if not aura then
            break
        end
        if secret(aura.spellId) or secret(aura.name) then
            return nil
        end
        list[#list + 1] = { name = aura.name, id = aura.spellId, icon = not secret(aura.icon) and aura.icon or nil }
    end
    return list
end

--- The entry of a spell ID (or the entry itself), and where it is.
---@param filter EternityUIUnitFramesFilter
---@param id integer|EternityUIUnitFramesSpell
function Filters.Find(filter, id)
    for i, spell in ipairs(filter.spells) do
        if spell == id or (spell.id ~= nil and spell.id == id) then
            return spell, i
        end
    end
    return nil, nil
end

local function findName(filter, name)
    local wanted = key(name)
    for _, spell in ipairs(filter.spells) do
        if spell.name and key(spell.name) == wanted then
            return spell
        end
    end
end

--- Adds a spell ID. False if it's there already.
function Filters.Add(filter, id)
    if Filters.Find(filter, id) then
        return false
    end
    filter.spells[#filter.spells + 1] = { id = id, enabled = true }
    changed(filter)
    return true
end

local function spellName(id)
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    if type(name) == "string" and not secret(name) then
        return name
    end
end

local function addFound(entry, id)
    entry.ids = entry.ids or {}
    for _, known in ipairs(entry.ids) do
        if known == id then
            return false
        end
    end
    entry.ids[#entry.ids + 1] = id
    table.sort(entry.ids)
    return true
end

-- IDs found at once: the player's own spell with that name, and the player's and target's buffs.
local function findNow(entry)
    local wanted = key(entry.name)
    if C_Spell and C_Spell.GetSpellIDForSpellIdentifier then
        local ok, id = pcall(C_Spell.GetSpellIDForSpellIdentifier, entry.name)
        if ok and type(id) == "number" and not secret(id) then
            addFound(entry, id)
        end
    end
    for _, unit in ipairs({ "player", "target" }) do
        for _, aura in ipairs(Filters.Auras(unit) or {}) do
            if key(aura.name) == wanted then
                addFound(entry, aura.id)
            end
        end
    end
end

local queue = {} -- name entries still to go through the spell list: { filter, entry, next }
local searcher

--- Looks at the next slice of spell IDs for the first entry in the queue. Returns true while
--- there's work left. Out of combat only.
---@param step integer?
---@return boolean
function Filters.SearchStep(step)
    local job = queue[1]
    if not job then
        return false
    end
    if InCombatLockdown() then
        return true
    end
    local entry = job.entry
    local wanted = key(entry.name)
    local last = math.min(job.next + (step or Filters.SEARCH_STEP) - 1, Filters.SEARCH_LAST)
    local found = false
    for id = job.next, last do
        local name = spellName(id)
        if name and key(name) == wanted then
            found = addFound(entry, id) or found
        end
    end
    job.next = last + 1
    if job.next > Filters.SEARCH_LAST then
        table.remove(queue, 1)
        entry.searching = nil
        changed(job.filter)
    elseif found then
        changed(job.filter)
    end
    if Filters.onProgress then
        Filters.onProgress(job.filter, entry, last / Filters.SEARCH_LAST)
    end
    return queue[1] ~= nil
end

local function startSearch(filter, entry)
    for _, job in ipairs(queue) do
        if job.entry == entry then
            return
        end
    end
    entry.searching = true
    queue[#queue + 1] = { filter = filter, entry = entry, next = 1 }
    if not searcher then
        searcher = CreateFrame("Frame")
    end
    searcher:SetScript("OnUpdate", function(frame)
        if not Filters.SearchStep() then
            frame:SetScript("OnUpdate", nil)
        end
    end)
end

--- Stops the searches of a filter's entries (or of one entry).
function Filters.DropSearches(filter, entry)
    for i = #queue, 1, -1 do
        local job = queue[i]
        if job.filter == filter and (entry == nil or job.entry == entry) then
            table.remove(queue, i)
        end
    end
end

--- Adds a spell by name and starts looking for its IDs. False if the name is already there or
--- empty.
function Filters.AddName(filter, name)
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or findName(filter, name) then
        return false
    end
    local entry = { name = name, ids = {}, enabled = true }
    filter.spells[#filter.spells + 1] = entry
    findNow(entry)
    changed(filter)
    startSearch(filter, entry)
    return entry
end

--- Looks for a name entry's IDs again.
function Filters.SearchAgain(filter, entry)
    if entry and entry.name then
        findNow(entry)
        changed(filter)
        startSearch(filter, entry)
    end
end

--- A /reload stops a search: the ones left half done go on.
function Filters.ResumeSearches()
    for _, filter in ipairs(Filters.All()) do
        for _, spell in ipairs(filter.spells) do
            if spell.name and spell.searching then
                startSearch(filter, spell)
            end
        end
    end
end

function Filters.Remove(filter, id)
    local spell, index = Filters.Find(filter, id)
    if index then
        Filters.DropSearches(filter, spell)
        table.remove(filter.spells, index)
        changed(filter)
    end
end

function Filters.SetEnabled(filter, id, enabled)
    local spell = Filters.Find(filter, id)
    if spell then
        spell.enabled = enabled and true or false
        changed(filter)
    end
end

function Filters.SetMine(filter, id, mine)
    local spell = Filters.Find(filter, id)
    if spell then
        spell.mine = mine and true or nil
        changed(filter)
    end
end
