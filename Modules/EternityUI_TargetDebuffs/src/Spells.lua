-- The player's list of spells (EternityUITargetDebuffsDB, for the account): spell IDs shown
-- first, whoever cast them ("always") or only when the player cast them ("only mine"). Each one
-- can be switched off without losing it. The "Spells" tab edits it (SpellsTab.lua); Filters.lua
-- turns it into the container's candidate filters.
-- An entry is a spell ID, or a name: the container only matches IDs, so a name keeps every ID
-- found with that name (all its ranks). They're found in the player's own spells and the
-- target's debuffs at once, and by going through the game's spell list in the background, a
-- slice per frame and never in combat.

---@type string, EternityUITargetDebuffsNamespace
local _, ns = ...

---@class EternityUITargetDebuffsSpell
---@field id integer? a spell ID entry
---@field name string? a name entry, as typed
---@field ids integer[]? (name) the IDs found with that name
---@field searching boolean? (name) still going through the spell list
---@field enabled boolean
---@field mine boolean? only when the player (or their pet) cast it

---@class EternityUITargetDebuffsSpells
---@field onChange fun()? called after every change
---@field onProgress fun(entry: EternityUITargetDebuffsSpell, done: number)? while searching
local Spells = {
    SEARCH_LAST = 500000, -- highest spell ID looked at by name
    SEARCH_STEP = 4000, -- spell IDs looked at per frame
}
ns.Spells = Spells

local function db()
    local saved = _G.EternityUITargetDebuffsDB
    if type(saved) ~= "table" then
        saved = {}
        _G.EternityUITargetDebuffsDB = saved
    end
    if type(saved.spells) ~= "table" then
        saved.spells = {}
    end
    -- "Never" became "only mine": switching a spell off already keeps it from showing first.
    for _, spell in ipairs(saved.spells) do
        if spell.hide then
            spell.hide, spell.mine = nil, true
        end
    end
    return saved
end

local function changed()
    if Spells.onChange then
        Spells.onChange()
    end
end

--- The list, in the order they were added.
---@return EternityUITargetDebuffsSpell[]
function Spells.List()
    return db().spells
end

--- The entry of a spell ID (or the entry itself), and where it is.
---@param id integer|EternityUITargetDebuffsSpell
---@return EternityUITargetDebuffsSpell?, integer?
function Spells.Find(id)
    for index, spell in ipairs(Spells.List()) do
        if spell == id or (spell.id ~= nil and spell.id == id) then
            return spell, index
        end
    end
end

local function key(name)
    return (tostring(name):gsub("^%s+", ""):gsub("%s+$", "")):lower()
end

--- The entry of a name (case doesn't matter), and where it is.
---@param name string
---@return EternityUITargetDebuffsSpell?, integer?
function Spells.FindName(name)
    local wanted = key(name)
    for index, spell in ipairs(Spells.List()) do
        if spell.name and key(spell.name) == wanted then
            return spell, index
        end
    end
end

--- Adds a spell ID (switched on, shown). False if it's already there or isn't an ID.
---@param id integer
---@return boolean
function Spells.Add(id)
    if type(id) ~= "number" or id <= 0 or id ~= math.floor(id) or Spells.Find(id) then
        return false
    end
    local list = Spells.List()
    list[#list + 1] = { id = id, enabled = true }
    changed()
    return true
end

-- Searching by name ------------------------------------------------------------------------------

local function secretValue(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

local function spellName(id)
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    if type(name) == "string" and not secretValue(name) then
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

--- IDs found at once: the player's own spell with that name and the target's debuffs.
local function findNow(entry)
    local wanted = key(entry.name)
    if C_Spell and C_Spell.GetSpellIDForSpellIdentifier then
        local ok, id = pcall(C_Spell.GetSpellIDForSpellIdentifier, entry.name)
        if ok and type(id) == "number" and not secretValue(id) then
            addFound(entry, id)
        end
    end
    for _, debuff in ipairs(Spells.TargetDebuffs() or {}) do
        if key(debuff.name) == wanted then
            addFound(entry, debuff.id)
        end
    end
end

local queue = {} -- name entries still to go through the spell list: { entry, next }
local searcher

--- Looks at the next slice of spell IDs for the first entry in the queue. Returns true while
--- there's work left. Out of combat only.
---@param step integer? how many IDs (SEARCH_STEP)
---@return boolean
function Spells.SearchStep(step)
    local job = queue[1]
    if not job then
        return false
    end
    if InCombatLockdown() then
        return true
    end
    local entry = job.entry
    local wanted = key(entry.name)
    local last = math.min(job.next + (step or Spells.SEARCH_STEP) - 1, Spells.SEARCH_LAST)
    local found = false
    for id = job.next, last do
        local name = spellName(id)
        if name and key(name) == wanted then
            found = addFound(entry, id) or found
        end
    end
    job.next = last + 1
    if job.next > Spells.SEARCH_LAST then
        table.remove(queue, 1)
        entry.searching = nil
        changed()
    elseif found then
        changed()
    end
    if Spells.onProgress then
        Spells.onProgress(entry, (last) / Spells.SEARCH_LAST)
    end
    return queue[1] ~= nil
end

local function startSearch(entry)
    for _, job in ipairs(queue) do
        if job.entry == entry then
            return
        end
    end
    entry.searching = true
    queue[#queue + 1] = { entry = entry, next = 1 }
    if not searcher then
        searcher = CreateFrame("Frame")
    end
    searcher:SetScript("OnUpdate", function(frame)
        if not Spells.SearchStep() then
            frame:SetScript("OnUpdate", nil)
        end
    end)
end

--- Adds a spell by name and starts looking for its IDs. False if the name is already there or
--- empty.
---@param name string
---@return EternityUITargetDebuffsSpell|false
function Spells.AddName(name)
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or Spells.FindName(name) then
        return false
    end
    local entry = { name = name, ids = {}, enabled = true }
    local list = Spells.List()
    list[#list + 1] = entry
    findNow(entry)
    changed()
    startSearch(entry)
    return entry
end

--- Looks for a name entry's IDs again (new ranks, or the first search was cut by a /reload).
---@param entry EternityUITargetDebuffsSpell
function Spells.SearchAgain(entry)
    if entry and entry.name then
        findNow(entry)
        changed()
        startSearch(entry)
    end
end

--- A /reload stops a search: the ones left half done go on.
function Spells.ResumeSearches()
    for _, spell in ipairs(Spells.List()) do
        if spell.name and spell.searching then
            startSearch(spell)
        end
    end
end

function Spells.Remove(id)
    local spell, index = Spells.Find(id)
    if index then
        for i = #queue, 1, -1 do
            if queue[i].entry == spell then
                table.remove(queue, i)
            end
        end
        table.remove(Spells.List(), index)
        changed()
    end
end

function Spells.SetEnabled(id, enabled)
    local spell = Spells.Find(id)
    if spell then
        spell.enabled = enabled and true or false
        changed()
    end
end

function Spells.SetMine(id, mine)
    local spell = Spells.Find(id)
    if spell then
        spell.mine = mine and true or nil
        changed()
    end
end

function Spells.Clear()
    db().spells = {}
    for i = #queue, 1, -1 do
        queue[i] = nil
    end
    changed()
end

--- The switched-on spells: the ones shown whoever cast them and the ones shown only when mine.
---@return table<integer, boolean> always
---@return table<integer, boolean> mine
function Spells.Sets()
    local always, mine = {}, {}
    for _, spell in ipairs(Spells.List()) do
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
    return always, mine
end

local function secret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

--- Name and icon of a spell ID, when the client knows them.
---@param id integer
---@return string? name
---@return number|string? icon
function Spells.Info(id)
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

--- The target's debuffs with their spell IDs: { name, id, icon }. nil while the game hides them
--- (in combat), {} without a target.
---@return table[]?
function Spells.TargetDebuffs()
    local list = {}
    if not UnitExists("target") then
        return list
    end
    for i = 1, 40 do
        local aura = C_UnitAuras.GetDebuffDataByIndex("target", i)
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
