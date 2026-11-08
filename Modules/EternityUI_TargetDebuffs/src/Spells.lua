-- The player's list of spells (EternityUITargetDebuffsDB, for the account): spell IDs that are
-- always shown first, whoever cast them, or never shown. Each one can be switched off without
-- losing it. The "Spells" tab edits it (SpellsTab.lua); Filters.lua turns it into the
-- container's candidate filters.

---@type string, EternityUITargetDebuffsNamespace
local _, ns = ...

---@class EternityUITargetDebuffsSpell
---@field id integer
---@field enabled boolean
---@field hide boolean? never show it, instead of always

---@class EternityUITargetDebuffsSpells
---@field onChange fun()? called after every change
local Spells = {}
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

---@param id integer
---@return EternityUITargetDebuffsSpell?, integer?
function Spells.Find(id)
    for index, spell in ipairs(Spells.List()) do
        if spell.id == id then
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

function Spells.Remove(id)
    local _, index = Spells.Find(id)
    if index then
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

function Spells.SetHidden(id, hide)
    local spell = Spells.Find(id)
    if spell then
        spell.hide = hide and true or nil
        changed()
    end
end

function Spells.Clear()
    db().spells = {}
    changed()
end

--- The switched-on spells: the ones to always show and the ones to never show, as sets.
---@return table<integer, boolean> show
---@return table<integer, boolean> hide
function Spells.Sets()
    local show, hide = {}, {}
    for _, spell in ipairs(Spells.List()) do
        if spell.enabled then
            if spell.hide then
                hide[spell.id] = true
            else
                show[spell.id] = true
            end
        end
    end
    return show, hide
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
