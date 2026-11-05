-- Option schemas and value validation. A schema has the options.json shape:
-- { module, groups = { { id, options = { { id, type, default, ... } } } } }. Paths are "group.option".
---@type string, EternityUINamespace
local _, ns = ...

---@class EternityUISchema
local Schema = {}
ns.Schema = Schema

local modules = {} -- module -> { ["group.option"] = option }

--- Forgets every schema. For tests.
function Schema.Clear()
    modules = {}
end

--- Registers a schema. Returns true, or false and the reason.
---@param schema table
---@return boolean, string?
function Schema.Register(schema)
    if type(schema) ~= "table" or type(schema.module) ~= "string" or type(schema.groups) ~= "table" then
        return false, "invalid schema"
    end
    local index = {}
    for _, group in ipairs(schema.groups) do
        for _, option in ipairs(group.options or {}) do
            local path = group.id .. "." .. option.id
            if index[path] then
                return false, "duplicate option " .. path
            end
            -- A text option may leave its default out: it starts empty.
            if option.type == "text" and option.default == nil then
                option.default = ""
            end
            index[path] = option
        end
    end
    modules[schema.module] = index
    return true
end

--- The option at path, or nil.
---@param module string
---@param path string
---@return table?
function Schema.GetOption(module, path)
    local index = modules[module]
    return index and index[path]
end

local validators = {}

function validators.toggle(_, value)
    if type(value) == "boolean" then
        return value
    end
    return nil, "expected boolean"
end

function validators.range(option, value)
    if type(value) ~= "number" or value ~= value then
        return nil, "expected number"
    end
    if value < option.min or value > option.max then
        return nil, "out of range"
    end
    -- Steps count from min; the format call drops binary noise such as 0.30000000000000004.
    local steps = math.floor((value - option.min) / option.step + 0.5)
    return math.min(option.max, tonumber(string.format("%.6f", option.min + steps * option.step)))
end

function validators.select(option, value)
    for _, entry in ipairs(option.values) do
        if entry.value == value then
            return value
        end
    end
    return nil, "not an allowed value"
end

function validators.color(_, value)
    if type(value) == "string" then
        if value:match("^#%x%x%x%x%x%x$") or value:match("^#%x%x%x%x%x%x%x%x$") then
            return value:upper()
        end
        if value:match("^@%a%w*$") or value:match("^@%a%w*:%x%x$") then
            return value
        end
    end
    return nil, "expected #RRGGBB, #RRGGBBAA or @token"
end

--- A schema text in the client's language: { enUS = ..., esES = ... }.
---@param text table|string|nil
---@return string
function EternityUI.Localize(text)
    if type(text) ~= "table" then
        return text and tostring(text) or ""
    end
    local locale = GetLocale()
    if locale == "esMX" then
        locale = "esES"
    end
    return text[locale] or text.enUS or ""
end

function validators.text(option, value)
    if type(value) ~= "string" then
        return nil, "expected text"
    end
    if option.maxLength and #value > option.maxLength then
        return nil, "text too long"
    end
    return value
end

--- Normalizes a value for an option. Returns the value, or nil and the reason.
---@param option table
---@param value any
---@return any, string?
function Schema.Validate(option, value)
    local validate = validators[option.type]
    if not validate then
        return nil, "unknown option type"
    end
    return validate(option, value)
end
