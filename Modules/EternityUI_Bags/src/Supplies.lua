-- EternityUI_Bags: supply crates, filled with a number of a material to make a shipment. Their
-- tooltip gets each material, how many the crate needs, how many you have and on which characters,
-- from what Inventory.lua saves (bags, bank, equipment and the warband bank).
--   * Season of Discovery's Waylaid Supplies (20 Copper Bars, 6 Copper Shortswords...): no API gives
--     their material, so they're listed here by item ID.
--   * Forever's Waylaid Crates (Apprentice Ingots...) take any one set from a list their own tooltip
--     writes ("- 20 de barra de cobre"): read from the tooltip and matched to items by name.

---@type string, EternityUIBagsNamespace
local addonName, ns = ...
local E = EternityUI
local L = ns.L

---@class EternityUIBagsSupplies
local Supplies = {}
ns.Supplies = Supplies

--- Crate itemID -> { material itemID, count }.
Supplies.CRATES = {
    -- Level 25
    [210771] = { 2840, 20 }, -- Copper Bars
    [211315] = { 2318, 14 }, -- Light Leather
    [211316] = { 2447, 20 }, -- Peacebloom
    [211317] = { 765, 20 }, -- Silverleaf
    [211318] = { 118, 20 }, -- Minor Healing Potions
    [211319] = { 2847, 6 }, -- Copper Shortswords
    [211320] = { 3473, 3 }, -- Runed Copper Pants
    [211321] = { 11287, 2 }, -- Lesser Magic Wands
    [211322] = { 20744, 2 }, -- Minor Wizard Oil
    [211323] = { 4360, 12 }, -- Rough Copper Bombs
    [211324] = { 4362, 3 }, -- Rough Boomsticks
    [211325] = { 4237, 5 }, -- Handstitched Leather Belts
    [211326] = { 2300, 3 }, -- Embossed Leather Vests
    [211327] = { 4343, 6 }, -- Brown Linen Pants
    [211328] = { 6238, 4 }, -- Brown Linen Robes
    [211329] = { 6888, 20 }, -- Herb Baked Eggs
    [211330] = { 2680, 20 }, -- Spiced Wolf Meat
    [211331] = { 6290, 20 }, -- Brilliant Smallfish
    [211332] = { 2581, 10 }, -- Heavy Linen Bandages
    [211933] = { 2835, 10 }, -- Rough Stone
    [211934] = { 929, 10 }, -- Healing Potions
    [211819] = { 2841, 12 }, -- Bronze Bars
    [211820] = { 2842, 6 }, -- Silver Bars
    [211821] = { 2319, 12 }, -- Medium Leather
    [211822] = { 2453, 20 }, -- Bruiseweed
    [211823] = { 2452, 20 }, -- Swiftthistle
    [211824] = { 3385, 20 }, -- Lesser Mana Potions
    [211825] = { 6350, 3 }, -- Rough Bronze Boots
    [211826] = { 15869, 14 }, -- Silver Skeleton Keys
    [211827] = { 6339, 1 }, -- Runed Silver Rods
    [211828] = { 20745, 2 }, -- Minor Mana Oil
    [211829] = { 4374, 12 }, -- Small Bronze Bombs
    [211830] = { 5507, 2 }, -- Ornate Spyglasses
    [211831] = { 2316, 2 }, -- Dark Leather Cloaks
    [211832] = { 4251, 2 }, -- Hillman's Shoulders
    [211833] = { 2587, 4 }, -- Gray Woolen Shirts
    [211834] = { 5542, 3 }, -- Pearl-clasped Cloaks
    [211835] = { 21072, 15 }, -- Smoked Sagefish
    [211836] = { 6890, 20 }, -- Smoked Bear Meat
    [211837] = { 5527, 8 }, -- Goblin Deviled Clams
    [211838] = { 3531, 15 }, -- Heavy Wool Bandages
    [211935] = { 6373, 15 }, -- Elixir of Firepower
    -- Level 40
    [215385] = { 3577, 4 }, -- Gold Bars
    [215386] = { 3860, 6 }, -- Mithril Bars
    [215387] = { 4235, 5 }, -- Heavy Hide
    [215388] = { 4304, 10 }, -- Thick Leather
    [215389] = { 3818, 16 }, -- Fadeleaf
    [215390] = { 3358, 10 }, -- Khadgar's Whisker
    [215391] = { 3819, 8 }, -- Wintersbite
    [215392] = { 8831, 8 }, -- Purple Lotus
    [215393] = { 1710, 16 }, -- Greater Healing Potions
    [215394] = { 4623, 20 }, -- Lesser Stoneshield Potions
    [215395] = { 8949, 6 }, -- Elixirs of Agility
    [215396] = { 8951, 14 }, -- Elixirs of Greater Defense
    [215397] = { 3855, 2 }, -- Massive Iron Axes
    [215398] = { 3835, 5 }, -- Green Iron Bracers
    [215399] = { 7919, 3 }, -- Heavy Mithril Gauntlets
    [215400] = { 7966, 5 }, -- Solid Grinding Stones
    [215401] = { 4391, 2 }, -- Compact Harvest Reaper Kits
    [215402] = { 4394, 8 }, -- Big Iron Bombs
    [215403] = { 10546, 2 }, -- Deadly Scopes
    [215404] = { 10508, 2 }, -- Mithril Blunderbuss
    [215405] = { 10724, 1 }, -- Gnomish Rocket Boots
    [215406] = { 10577, 14 }, -- Goblin Mortars
    [215407] = { 5964, 4 }, -- Barbaric Shoulders
    [215408] = { 5966, 5 }, -- Guardian Gloves
    [215409] = { 8198, 2 }, -- Turtle Scale Bracers
    [215410] = { 7387, 4 }, -- Dusky Belts
    [215411] = { 7377, 2 }, -- Frost Leather Cloaks
    [215413] = { 4334, 3 }, -- Formal White Shirts
    [215414] = { 7062, 4 }, -- Crimson Silk Pantaloons
    [215415] = { 4335, 5 }, -- Rich Purple Silk Shirts
    [215416] = { 10008, 3 }, -- White Bandit Masks
    [215417] = { 3729, 10 }, -- Soothing Turtle Bisque
    [215418] = { 17222, 5 }, -- Spider Sausages
    [215419] = { 6451, 10 }, -- Heavy Silk Bandages
    [215420] = { 4594, 40 }, -- Rockscale Cod
    [215421] = { 6371, 7 }, -- Fire Oil
    -- Level 50 (names as they come: the item cache has them)
    [220918] = { 16766, 16 }, -- Undermine Clam Chowder
    [220919] = { 13931, 8 },
    [220920] = { 18045, 12 },
    [220921] = { 8545, 14 },
    [220922] = { 8838, 15 },
    [220923] = { 13463, 6 },
    [220924] = { 6037, 12 },
    [220925] = { 12359, 16 },
    [220926] = { 8170, 14 },
    [220927] = { 8169, 8 },
    [220928] = { 12655, 4 },
    [220929] = { 13443, 6 },
    [220930] = { 13446, 8 },
    [220931] = { 10562, 16 },
    [220932] = { 15993, 3 },
    [220933] = { 15995, 2 },
    [220934] = { 7931, 3 },
    [220935] = { 12406, 5 },
    [220936] = { 7938, 2 },
    [220937] = { 15564, 12 },
    [220938] = { 15084, 6 },
    [220939] = { 15092, 5 },
    [220940] = { 10024, 5 },
    [220941] = { 13856, 6 },
    [220942] = { 10034, 4 },
}

local function opt(path)
    return E.store:Get(addonName, path)
end

local function secret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

-- What starts a line of a crate's list: hyphen, en dash, bullet.
local BULLETS = { "-", "\226\128\147", "\226\128\162" }

local function trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Item names already matched, lowercased -> itemID, and names not found, lowercased -> GetTime()
-- of the miss (looked for again after a few seconds: the tooltip asks on every refresh).
local MISS_GAP = 5
local byName, missed = {}, {}

-- The item Inventory remembers with that name (lowercased), or nil.
local function rememberedItem(key)
    for id, entry in pairs(ns.Inventory:Bind().items) do
        if type(entry) == "table" and type(entry.name) == "string" and entry.name:lower() == key then
            return id
        end
    end
    return nil
end

-- The item in the client's cache with that name, or nil.
local function cachedItem(name)
    local getInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
    if not getInfo then
        return nil
    end
    for _, candidate in ipairs({ name, name:sub(1, 1):upper() .. name:sub(2) }) do
        local _, link = getInfo(candidate)
        local id = type(link) == "string" and not secret(link) and tonumber(link:match("item:(%d+)"))
        if id then
            return id
        end
    end
    return nil
end

--- The itemID of an item by its name as the crate's tooltip writes it ("barra de cobre",
--- "Copper Bar"): from the items Inventory remembers, or the client's item cache.
---@param name string
---@return integer?
function Supplies.ItemByName(name)
    local key = name:lower()
    if byName[key] then
        return byName[key]
    end
    if missed[key] and GetTime() - missed[key] < MISS_GAP then
        return nil
    end
    local id = rememberedItem(key) or cachedItem(name)
    if id then
        byName[key], missed[key] = id, nil
    else
        missed[key] = GetTime()
    end
    return id
end

--- One line of the crate's list: "- 20 de barra de cobre", "- 20 Copper Bar", "• 20x Copper Bar".
--- Colors and textures are left out first.
---@param text string
---@return integer? count
---@return string? name
function Supplies.ParseLine(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
    text = trim(text)
    -- The bullet: a hyphen, an en dash or a dot.
    local rest
    for _, bullet in ipairs(BULLETS) do
        if text:sub(1, #bullet) == bullet then
            rest = text:sub(#bullet + 1)
            break
        end
    end
    if not rest then
        return nil
    end
    local count, name = rest:match("^%s*(%d+)%s*[xX]?%s+(.+)$")
    if not count then
        return nil
    end
    name = trim(name):gsub("^de%s+", ""):gsub("[%.,;:]$", "")
    if name == "" then
        return nil
    end
    return tonumber(count), name
end

-- Adds the lines of `text` (one tooltip line can hold several, split by line breaks).
local function addLines(texts, text)
    if type(text) ~= "string" or secret(text) then
        return
    end
    for piece in (text .. "\n"):gmatch("(.-)\r?\n") do
        texts[#texts + 1] = piece
    end
end

-- The texts of the tooltip's left lines: from the tooltip data and from its font strings (the
-- data can leave the use text out, the font strings have what's shown).
local function tooltipTexts(tip, data)
    local texts = {}
    local lines = type(data) == "table" and data.lines
    if type(lines) == "table" then
        for _, line in ipairs(lines) do
            if type(line) == "table" then
                addLines(texts, line.leftText)
            end
        end
    end
    local name = tip and tip.GetName and tip:GetName()
    if type(name) == "string" and tip.NumLines then
        for i = 1, tip:NumLines() do
            local font = _G[name .. "TextLeft" .. i]
            addLines(texts, font and font.GetText and font:GetText())
        end
    end
    return texts
end

--- What a supply crate can be filled with: { id, name, count } for each choice, or nil if the
--- item isn't a crate. The Season of Discovery crates come from CRATES; Forever's Waylaid Crates
--- list their choices in their own tooltip ("- 20 de barra de cobre"), read from there.
---@param itemID integer
---@param tip GameTooltip?
---@param data table? the tooltip data
---@return { id: integer?, name: string?, count: integer }[]?
function Supplies.Needs(itemID, tip, data)
    local fixed = Supplies.CRATES[itemID]
    if fixed then
        return { { id = fixed[1], count = fixed[2] } }
    end
    local needs, seen = {}, {}
    for _, text in ipairs(tooltipTexts(tip, data)) do
        local count, name = Supplies.ParseLine(text)
        local key = name and count .. " " .. name:lower()
        if count and count > 0 and not seen[key] then
            seen[key] = true
            needs[#needs + 1] = { id = Supplies.ItemByName(name), name = name, count = count }
        end
    end
    return #needs > 0 and needs or nil
end

--- The material's name with its icon, from the item cache or from what Inventory remembers.
---@param itemID integer
---@return string
function Supplies.MaterialText(itemID)
    local saved = ns.Inventory:Bind().items[itemID]
    local name, icon
    if C_Item and C_Item.GetItemNameByID then
        name = C_Item.GetItemNameByID(itemID)
    end
    if C_Item and C_Item.GetItemIconByID then
        icon = C_Item.GetItemIconByID(itemID)
    end
    name = type(name) == "string" and name ~= "" and name or (saved and saved.name)
    icon = type(icon) == "number" and icon or (saved and saved.icon)
    if not name then
        -- Not cached yet: ask for it, the next tooltip has it.
        if C_Item and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(itemID)
        end
        name = L.ITEM_N:format(itemID)
    end
    if icon then
        return "|T" .. icon .. ":0|t " .. name
    end
    return name
end

--- The crate's lines: for each material it takes, how many you have against what it needs and on
--- which characters. This character and the warband bank always count; realms and faction follow
--- the tooltip options.
---@param tip GameTooltip
---@param crateID integer
---@param data table? the tooltip data
---@return boolean added
function Supplies.AddLines(tip, crateID, data)
    local needs = Supplies.Needs(crateID, tip, data)
    if not needs then
        return false
    end
    local Inventory = ns.Inventory
    local detail = opt("tooltip.breakdown")
    local force = { current = true, warband = opt("inventory.warband") }
    tip:AddLine(" ")
    tip:AddLine(L.SUPPLY_TITLE, 1, 0.82, 0)
    for _, need in ipairs(needs) do
        local owners, total = {}, 0
        if need.id then
            owners, total = Inventory:Owners(need.id, force)
        end
        local label = need.count .. " × " .. (need.id and Supplies.MaterialText(need.id) or need.name)
        local have = total .. " / " .. need.count
        local crates = math.floor(total / need.count)
        if crates > 0 then
            tip:AddDoubleLine(label, have .. "  " .. L.SUPPLY_ENOUGH:format(crates), 1, 1, 1, 0.25, 1, 0.25)
        else
            tip:AddDoubleLine(label, have, 1, 1, 1, 1, 0.35, 0.35)
        end
        for _, owner in ipairs(owners) do
            local r, g, b = Inventory.NameColor(owner)
            local count = detail and Inventory.Breakdown(owner) or tostring(owner.total)
            tip:AddDoubleLine("    " .. owner.name, count, r, g, b, 1, 1, 1)
        end
    end
    return true
end
