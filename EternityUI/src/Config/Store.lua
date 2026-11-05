-- Profiles on top of the SavedVariables table. Only values that differ from the default are
-- stored, so a default changed later reaches whoever hasn't touched it.
--
-- raw.schemaVersion
-- raw.stats             = { logins, reloads }
-- raw.profiles[name]    = { values = { [module] = { ["group.option"] = value } },
--                           modules = { [module] = false }, layout = { [element] = entry } }
-- raw.characters[guid]  = profile name
--
-- Characters are keyed by GUID: UnitName isn't unique on Forever and can answer "Unknown" while
-- loading. Without a GUID the store works on the default profile and assigns nothing.
---@type string, EternityUINamespace
local _, ns = ...
local Schema = ns.Schema

---@class EternityUIStore
---@field raw table
---@field character string? the character's GUID
---@field onChange fun(module: string?, path: string?, value: any)?
local Store = {}
Store.__index = Store
ns.Store = Store

Store.DEFAULT_PROFILE = "Default"
Store.SCHEMA_VERSION = 2
-- Store.migrations[n] turns a table at version n - 1 into version n.
Store.migrations = {}

-- Version 2: the accent list became a free color, and appearance.surface is now appearance.style.
Store.migrations[2] = function(raw)
    for _, profile in pairs(raw.profiles or {}) do
        local values = profile.values.EternityUI
        if values then
            values["appearance.style"] = values["appearance.surface"]
            values["appearance.surface"] = nil
            if values["appearance.accent"] then
                values["general.themeAccent"] = false
                values["general.accentColor"] = values["appearance.accent"]
                values["appearance.accent"] = nil
            end
        end
    end
end

local function newProfile()
    return { values = {}, modules = {}, layout = {} }
end

--- Runs the migrations a table still needs. The version only advances after one succeeds.
---@param raw table
function Store.Migrate(raw)
    local version = raw.schemaVersion or Store.SCHEMA_VERSION
    while version < Store.SCHEMA_VERSION do
        version = version + 1
        local migrate = Store.migrations[version]
        if migrate then
            migrate(raw)
        end
        raw.schemaVersion = version
    end
    raw.schemaVersion = version
end

--- Creates a store over raw (modified in place).
---@param raw table
---@param character string?
---@param onChange fun(module: string?, path: string?, value: any)?
---@return EternityUIStore
function Store.New(raw, character, onChange)
    Store.Migrate(raw)
    raw.stats = raw.stats or { logins = 0, reloads = 0 }
    raw.profiles = raw.profiles or {}
    raw.characters = raw.characters or {}
    raw.profiles[Store.DEFAULT_PROFILE] = raw.profiles[Store.DEFAULT_PROFILE] or newProfile()
    local self = setmetatable({ raw = raw, character = character, onChange = onChange }, Store)
    if character and not raw.profiles[raw.characters[character] or ""] then
        raw.characters[character] = nil
    end
    return self
end

local function notify(self, module, path, value)
    if self.onChange then
        self.onChange(module, path, value)
    end
end

---@return string
function Store:GetProfileName()
    return self.character and self.raw.characters[self.character] or Store.DEFAULT_PROFILE
end

---@return table
function Store:GetProfile()
    return self.raw.profiles[self:GetProfileName()]
end

--- Effective value: the profile's or the default. Returns nil and the reason for an unknown path.
---@param module string
---@param path string
---@return any, string?
function Store:Get(module, path)
    local option = Schema.GetOption(module, path)
    if not option then
        return nil, "unknown option " .. module .. "/" .. path
    end
    local values = self:GetProfile().values[module]
    local value = values and values[path]
    if value == nil then
        return option.default
    end
    return value
end

--- Changes a value. Equal to the default means it's no longer stored.
---@param module string
---@param path string
---@param value any
---@return boolean, string?
function Store:Set(module, path, value)
    local option = Schema.GetOption(module, path)
    if not option then
        return false, "unknown option " .. module .. "/" .. path
    end
    local normalized, err = Schema.Validate(option, value)
    if normalized == nil then
        return false, err
    end
    local profile = self:GetProfile()
    local stored = normalized
    if stored == option.default then
        stored = nil
    end
    local values = profile.values[module]
    if (values and values[path]) == stored then
        return true
    end
    values = values or {}
    values[path] = stored
    profile.values[module] = next(values) and values or nil
    notify(self, module, path, normalized)
    return true
end

--- Puts a module's values back to their defaults.
---@param module string
function Store:Reset(module)
    self:GetProfile().values[module] = nil
    notify(self, module, nil, nil)
end

---@param module string
---@return boolean
function Store:IsModuleEnabled(module)
    return self:GetProfile().modules[module] ~= false
end

---@param module string
---@param enabled boolean
function Store:SetModuleEnabled(module, enabled)
    if self:IsModuleEnabled(module) == enabled then
        return
    end
    -- Enabled is the default, so only false is stored.
    if enabled then
        self:GetProfile().modules[module] = nil
    else
        self:GetProfile().modules[module] = false
    end
    notify(self, module, "@enabled", enabled)
end

--- A saved position of the Mover, or nil.
---@param element string
---@return table?
function Store:GetLayout(element)
    return self:GetProfile().layout[element]
end

--- Replaces the whole layout of the profile (a copy of it).
---@param layout table
function Store:ReplaceLayout(layout)
    self:GetProfile().layout = ns.DeepCopy(layout)
    notify(self, nil, "@layout", nil)
end

--- Saves or clears a position. Positions belong to the profile like any other value.
---@param element string
---@param entry table?
function Store:SetLayout(element, entry)
    self:GetProfile().layout[element] = entry
    notify(self, nil, "@layout", element)
end

---@return string[]
function Store:ListProfiles()
    local names = {}
    for name in pairs(self.raw.profiles) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

--- Creates a profile, optionally as a copy of another.
---@param name string
---@param copyFrom string?
---@return boolean, string?
function Store:CreateProfile(name, copyFrom)
    if type(name) ~= "string" or #name > 40 or not name:match("^[%w _%-]+$") then
        return false, "invalid profile name"
    end
    if self.raw.profiles[name] then
        return false, "profile already exists"
    end
    if copyFrom and not self.raw.profiles[copyFrom] then
        return false, "profile not found"
    end
    self.raw.profiles[name] = copyFrom and ns.DeepCopy(self.raw.profiles[copyFrom]) or newProfile()
    return true
end

--- Assigns a profile to this character.
---@param name string
---@return boolean, string?
function Store:UseProfile(name)
    if not self.raw.profiles[name] then
        return false, "profile not found"
    end
    if not self.character then
        return false, "character not known yet"
    end
    self.raw.characters[self.character] = name ~= Store.DEFAULT_PROFILE and name or nil
    notify(self, nil, "@profile", name)
    return true
end

--- Deletes a profile. Characters using it fall back to the default profile.
---@param name string
---@return boolean, string?
function Store:DeleteProfile(name)
    if name == Store.DEFAULT_PROFILE then
        return false, "the default profile can't be deleted"
    end
    if not self.raw.profiles[name] then
        return false, "profile not found"
    end
    local active = self:GetProfileName() == name
    self.raw.profiles[name] = nil
    for character, profile in pairs(self.raw.characters) do
        if profile == name then
            self.raw.characters[character] = nil
        end
    end
    if active then
        notify(self, nil, "@profile", Store.DEFAULT_PROFILE)
    end
    return true
end

local EXPORT_PREFIX = "ETERNITY1:"
local MAX_IMPORT = 1024 * 1024

--- The active profile as a text to share.
---@return string?, string?
function Store:ExportProfile()
    local method = Enum.CompressionMethod.Deflate
    local ok, text = pcall(function()
        local packed = C_EncodingUtil.CompressString(C_EncodingUtil.SerializeCBOR(self:GetProfile()), method)
        return C_EncodingUtil.EncodeBase64(packed)
    end)
    if not ok then
        return nil, "export failed"
    end
    return EXPORT_PREFIX .. text
end

--- Creates a profile from an exported text. Unknown options are dropped when their module loads.
---@param name string
---@param text string
---@return boolean, string?
function Store:ImportProfile(name, text)
    if type(text) ~= "string" or #text > MAX_IMPORT or text:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then
        return false, "not an Eternity profile"
    end
    local method = Enum.CompressionMethod.Deflate
    local ok, data = pcall(function()
        local packed = C_EncodingUtil.DecodeBase64(text:sub(#EXPORT_PREFIX + 1))
        return C_EncodingUtil.DeserializeCBOR(C_EncodingUtil.DecompressString(packed, method))
    end)
    if not ok or type(data) ~= "table" then
        return false, "not an Eternity profile"
    end
    local created, err = self:CreateProfile(name)
    if not created then
        return false, err
    end
    local profile = self.raw.profiles[name]
    for _, key in ipairs({ "values", "modules", "layout" }) do
        if type(data[key]) == "table" then
            profile[key] = data[key]
        end
    end
    return true
end

--- Removes stored values of a module that its schema no longer accepts. Returns how many.
---@param module string
---@return integer
function Store:Sanitize(module)
    local removed = 0
    for _, profile in pairs(self.raw.profiles) do
        local values = profile.values[module]
        for path, value in pairs(values or {}) do
            local option = Schema.GetOption(module, path)
            local normalized = option and Schema.Validate(option, value)
            if normalized == nil then
                values[path] = nil
                removed = removed + 1
            else
                values[path] = normalized
            end
        end
        if values and next(values) == nil then
            profile.values[module] = nil
        end
    end
    return removed
end
