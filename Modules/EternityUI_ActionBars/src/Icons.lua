-- Icon per spell: the icons.replace option ("spell=icon, ...") swaps the icon a LibActionButton
-- button shows for a spell. The button's own GetTexture is wrapped, so every path LibActionButton
-- uses to draw the icon (full updates, shapeshift and summon-pet refreshes) gets the replacement.
-- Action textures and spell IDs aren't secret on Forever (only cooldowns and charges are).

---@type string, EternityUIActionBarsNamespace
local addonName, ns = ...
local E = EternityUI

---@class EternityUIActionBarsIcons
---@field source string? option text the maps were built from
---@field byId table<integer, string|integer>
---@field byName table<string, string|integer> lowercase spell name -> icon
local Icons = { byId = {}, byName = {} }
ns.Icons = Icons

--- Icon of an option value: a file ID, a path, or an icon name under Interface\Icons.
---@param value string
---@return string|integer
function Icons.Texture(value)
    local id = tonumber(value)
    if id then
        return id
    end
    if value:find("[\\/]") then
        return value
    end
    return "Interface\\Icons\\" .. value
end

--- Parses the option text into the maps (only when it changed).
---@param text string?
function Icons:Parse(text)
    text = text or ""
    if text == self.source then
        return
    end
    self.source = text
    wipe(self.byId)
    wipe(self.byName)
    for entry in text:gmatch("[^,]+") do
        local spell, icon = entry:match("^%s*(.-)%s*=%s*(.-)%s*$")
        if spell and spell ~= "" and icon and icon ~= "" then
            local id = tonumber(spell)
            if id then
                self.byId[id] = Icons.Texture(icon)
            else
                self.byName[spell:lower()] = Icons.Texture(icon)
            end
        end
    end
end

--- The replacement for a spell, if the option names it.
---@param spellID integer?
---@return string|integer?
function Icons:For(spellID)
    if not spellID or (next(self.byId) == nil and next(self.byName) == nil) then
        return nil
    end
    local icon = self.byId[spellID]
    if icon or next(self.byName) == nil then
        return icon
    end
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    return name and self.byName[name:lower()] or nil
end

--- Wraps a LibActionButton button's GetTexture (once).
---@param button table
function Icons.Hook(button)
    if button.eternityIcons then
        return
    end
    button.eternityIcons = true
    -- GetTexture comes from the button's type table (action, spell...): keep calling the current one.
    button.GetTexture = function(self)
        local texture = getmetatable(self).__index.GetTexture(self)
        if texture and self.GetSpellId then
            return Icons:For(self:GetSpellId()) or texture
        end
        return texture
    end
end

--- Reads the option; true when the replacements changed (the buttons need an update).
---@return boolean
function Icons:Refresh()
    local before = self.source
    self:Parse(E.store:Get(addonName, "icons.replace"))
    return before ~= self.source
end
