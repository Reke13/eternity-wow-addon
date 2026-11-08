-- The player's lists of spells (EternityUIAurasDB, for the account), one per frame: spell IDs
-- shown first, whoever cast them ("always") or only when the player cast them ("only mine").
-- Each one can be switched off without losing it. The "Spells" tab edits them (SpellsTab.lua);
-- Filters.lua turns them into the containers' candidate filters.
-- An entry is a spell ID, or a name: the container only matches IDs, so a name keeps every ID
-- found with that name (all its ranks). They're found in the player's own spells and the
-- frame's unit's auras at once, and by going through the game's spell list in the background,
-- a slice per frame and never in combat.

---@type string, EternityUIAurasNamespace
local _, ns = ...

---@class EternityUIAurasSpell
---@field id integer? a spell ID entry
---@field name string? a name entry, as typed
---@field ids integer[]? (name) the IDs found with that name
---@field searching boolean? (name) still going through the spell list
---@field enabled boolean
---@field mine boolean? only when the player (or their pet) cast it

---@class EternityUIAurasSpells
---@field lists table<string, EternityUIAurasSpellList>
---@field onProgress fun(list: EternityUIAurasSpellList, entry: EternityUIAurasSpell, done: number)? while searching
local Spells = {
    SEARCH_LAST = 500000, -- highest spell ID looked at by name
    SEARCH_STEP = 4000, -- spell IDs looked at per frame
    lists = {},
}
ns.Spells = Spells

local function secret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

local function key(name)
    return (tostring(name):gsub("^%s+", ""):gsub("%s+$", "")):lower()
end

local function root()
    local saved = _G.EternityUIAurasDB
    if type(saved) ~= "table" then
        saved = {}
        _G.EternityUIAurasDB = saved
    end
    return saved
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

--- A unit's auras with their spell IDs: { name, id, icon }. nil while the game hides them (in
--- combat), {} when the unit isn't there.
---@param unit string
---@param filter string "HARMFUL" or "HELPFUL"
---@return table[]?
function Spells.Auras(unit, filter)
    local list = {}
    if not UnitExists(unit) then
        return list
    end
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, filter)
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

-- A list -----------------------------------------------------------------------------------------

---@class EternityUIAurasSpellList
---@field key string
---@field unit string
---@field filter string
---@field onChange fun(list: EternityUIAurasSpellList)? called after every change
local List = {}
List.__index = List

--- The list of a frame (created once).
---@param kind EternityUIAurasKind|{ key: string, unit: string, filter: string }
---@return EternityUIAurasSpellList
function Spells.New(kind)
    local list = Spells.lists[kind.key]
    if not list then
        list = setmetatable({ key = kind.key, unit = kind.unit, filter = kind.filter }, List)
        Spells.lists[kind.key] = list
    end
    return list
end

function List:changed()
    if self.onChange then
        self.onChange(self)
    end
end

--- The entries, in the order they were added.
---@return EternityUIAurasSpell[]
function List:List()
    local saved = root()
    local mine = saved[self.key]
    if type(mine) ~= "table" then
        mine = {}
        saved[self.key] = mine
    end
    if type(mine.spells) ~= "table" then
        mine.spells = {}
    end
    return mine.spells
end

--- The entry of a spell ID (or the entry itself), and where it is.
---@param id integer|EternityUIAurasSpell
---@return EternityUIAurasSpell?, integer?
function List:Find(id)
    for index, spell in ipairs(self:List()) do
        if spell == id or (spell.id ~= nil and spell.id == id) then
            return spell, index
        end
    end
end

--- The entry of a name (case doesn't matter), and where it is.
---@param name string
---@return EternityUIAurasSpell?, integer?
function List:FindName(name)
    local wanted = key(name)
    for index, spell in ipairs(self:List()) do
        if spell.name and key(spell.name) == wanted then
            return spell, index
        end
    end
end

--- Adds a spell ID (switched on, shown). False if it's already there or isn't an ID.
---@param id integer
---@return boolean
function List:Add(id)
    if type(id) ~= "number" or id <= 0 or id ~= math.floor(id) or self:Find(id) then
        return false
    end
    local list = self:List()
    list[#list + 1] = { id = id, enabled = true }
    self:changed()
    return true
end

--- The unit's auras of this list's kind (see Spells.Auras).
---@return table[]?
function List:Auras()
    return Spells.Auras(self.unit, self.filter)
end

-- Searching by name ------------------------------------------------------------------------------

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

--- IDs found at once: the player's own spell with that name and the unit's auras.
local function findNow(list, entry)
    local wanted = key(entry.name)
    if C_Spell and C_Spell.GetSpellIDForSpellIdentifier then
        local ok, id = pcall(C_Spell.GetSpellIDForSpellIdentifier, entry.name)
        if ok and type(id) == "number" and not secret(id) then
            addFound(entry, id)
        end
    end
    for _, aura in ipairs(list:Auras() or {}) do
        if key(aura.name) == wanted then
            addFound(entry, aura.id)
        end
    end
end

local queue = {} -- name entries still to go through the spell list: { list, entry, next }
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
        job.list:changed()
    elseif found then
        job.list:changed()
    end
    if Spells.onProgress then
        Spells.onProgress(job.list, entry, last / Spells.SEARCH_LAST)
    end
    return queue[1] ~= nil
end

local function startSearch(list, entry)
    for _, job in ipairs(queue) do
        if job.entry == entry then
            return
        end
    end
    entry.searching = true
    queue[#queue + 1] = { list = list, entry = entry, next = 1 }
    if not searcher then
        searcher = CreateFrame("Frame")
    end
    searcher:SetScript("OnUpdate", function(frame)
        if not Spells.SearchStep() then
            frame:SetScript("OnUpdate", nil)
        end
    end)
end

local function dropSearches(entry)
    for i = #queue, 1, -1 do
        if entry == nil or queue[i].entry == entry then
            table.remove(queue, i)
        end
    end
end

--- Adds a spell by name and starts looking for its IDs. False if the name is already there or
--- empty.
---@param name string
---@return EternityUIAurasSpell|false
function List:AddName(name)
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or self:FindName(name) then
        return false
    end
    local entry = { name = name, ids = {}, enabled = true }
    local list = self:List()
    list[#list + 1] = entry
    findNow(self, entry)
    self:changed()
    startSearch(self, entry)
    return entry
end

--- Looks for a name entry's IDs again (new ranks, or the first search was cut by a /reload).
---@param entry EternityUIAurasSpell
function List:SearchAgain(entry)
    if entry and entry.name then
        findNow(self, entry)
        self:changed()
        startSearch(self, entry)
    end
end

--- A /reload stops a search: the ones left half done go on.
function List:ResumeSearches()
    for _, spell in ipairs(self:List()) do
        if spell.name and spell.searching then
            startSearch(self, spell)
        end
    end
end

function List:Remove(id)
    local spell, index = self:Find(id)
    if index then
        dropSearches(spell)
        table.remove(self:List(), index)
        self:changed()
    end
end

function List:SetEnabled(id, enabled)
    local spell = self:Find(id)
    if spell then
        spell.enabled = enabled and true or false
        self:changed()
    end
end

function List:SetMine(id, mine)
    local spell = self:Find(id)
    if spell then
        spell.mine = mine and true or nil
        self:changed()
    end
end

function List:Clear()
    for _, spell in ipairs(self:List()) do
        dropSearches(spell)
    end
    root()[self.key].spells = {}
    self:changed()
end

--- The switched-on spells: the ones shown whoever cast them and the ones shown only when mine.
---@return table<integer, boolean> always
---@return table<integer, boolean> mine
function List:Sets()
    local always, mine = {}, {}
    for _, spell in ipairs(self:List()) do
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

for _, kind in ipairs(ns.KINDS) do
    Spells.New(kind)
end
