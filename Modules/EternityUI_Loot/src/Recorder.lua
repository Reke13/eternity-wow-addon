-- What was looted, for the history. The chat lines say what really reached the bags (rolls and auto
-- loot included), and the contents of each open loot window say where it came from: a line takes the
-- source from the slot it matches. Chat lines can arrive secret; then the line is lost, so a slot
-- that was taken and never confirmed is recorded from the window, but only if a secret line was seen
-- around it (otherwise someone else took it).

---@type string, EternityUILootNamespace
local _, ns = ...
local E = EternityUI
local L, opt = ns.L, ns.opt
local Secret = E.Secret

-- A chat line matches a slot of a window open this long ago at most.
local MATCH_SECONDS = 30
-- Time for the chat line of a taken slot to arrive.
local SETTLE_SECONDS = 2
-- A secret line explains the slots taken around it.
local BLIND_SECONDS = 5
-- The log may pass the limit by this much, so it isn't cut on every entry.
local TRIM_MARGIN = 100

-- The game's texts, most specific first: "%sx%d" would also match the one without a count.
local ITEM_LINES = {
    { "LOOT_ITEM_SELF_MULTIPLE", own = true },
    { "LOOT_ITEM_SELF", own = true },
    { "LOOT_ITEM_PUSHED_SELF_MULTIPLE", own = true, pushed = true },
    { "LOOT_ITEM_PUSHED_SELF", own = true, pushed = true },
    { "LOOT_ITEM_MULTIPLE" },
    { "LOOT_ITEM" },
    { "LOOT_ITEM_PUSHED_MULTIPLE", pushed = true },
    { "LOOT_ITEM_PUSHED", pushed = true },
}
local MONEY_LINES = { "YOU_LOOT_MONEY", "LOOT_MONEY_SPLIT", "YOU_LOOT_MONEY_GUILD", "LOOT_MONEY_SPLIT_GUILD" }
local COINS = { { "GOLD_AMOUNT", 10000 }, { "SILVER_AMOUNT", 100 }, { "COPPER_AMOUNT", 1 } }

---@class EternityUILootRecorder
---@field db table? EternityUILootDB
---@field onAdd fun()? runs after an entry is saved
local Recorder = {}
ns.Recorder = Recorder

local session -- slot -> what the open loot window held
local recent = {} -- the slots of recent windows, to match chat lines against
local blindAt = -math.huge -- when the last secret line came

--- Turns one of the game's format strings into an anchored Lua pattern.
---@param format string
---@return string
function Recorder.Pattern(format)
    local pattern = format:gsub("%%%d%$([sd])", "%%%1")
    pattern = pattern:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
    pattern = pattern:gsub("%%s", "(.+)")
    pattern = pattern:gsub("%%d", "(%%d+)")
    return "^" .. pattern .. "$"
end

local itemLines, moneyLines, coinLines

local function compile()
    itemLines, moneyLines, coinLines = {}, {}, {}
    for _, line in ipairs(ITEM_LINES) do
        local format = _G[line[1]]
        if format then
            itemLines[#itemLines + 1] = { pattern = Recorder.Pattern(format), own = line.own, pushed = line.pushed }
        end
    end
    for _, name in ipairs(MONEY_LINES) do
        if _G[name] then
            moneyLines[#moneyLines + 1] = Recorder.Pattern(_G[name])
        end
    end
    for _, coin in ipairs(COINS) do
        if _G[coin[1]] then
            -- Not anchored: the amounts sit inside a longer line.
            local pattern = Recorder.Pattern(_G[coin[1]]):sub(2, -2)
            coinLines[#coinLines + 1] = { pattern, coin[2] }
        end
    end
end

local function linkOf(text)
    return text:match("(|c[^|]*|H.-|h.-|h|r)") or text:match("(|H.-|h.-|h)")
end

local function keyOf(link)
    return link and (link:match("item:(%d+)") or link:match("currency:(%d+)"))
end

--- Reads a CHAT_MSG_LOOT line. Nil for the other lines of that event (rolls, crafting...).
---@param text string
---@return table? line { link, count, own, pushed, looter }
function Recorder.ParseItem(text)
    if not itemLines then
        compile()
    end
    local link = linkOf(text)
    if not link then
        return nil
    end
    for _, line in ipairs(itemLines) do
        local captures = { text:match(line.pattern) }
        if captures[1] then
            local count, looter = 1, nil
            for _, capture in ipairs(captures) do
                if capture:match("^%d+$") then
                    count = tonumber(capture)
                elseif not capture:find("|H", 1, true) then
                    looter = capture
                end
            end
            return { link = link, count = count, own = line.own, pushed = line.pushed, looter = looter }
        end
    end
    return nil
end

--- The copper in a text like "1 Gold, 5 Silver".
---@param text string
---@return integer
function Recorder.ParseCopper(text)
    if not coinLines then
        compile()
    end
    local copper = 0
    for _, coin in ipairs(coinLines) do
        local amount = text:match(coin[1])
        if amount then
            copper = copper + tonumber(amount) * coin[2]
        end
    end
    return copper
end

--- Reads a CHAT_MSG_MONEY line. Nil if it isn't your own money.
---@param text string
---@return integer? copper
function Recorder.ParseMoney(text)
    if not moneyLines then
        compile()
    end
    for _, pattern in ipairs(moneyLines) do
        if text:match(pattern) then
            local copper = Recorder.ParseCopper(text)
            return copper > 0 and copper or nil
        end
    end
    return nil
end

--- Reads a CHAT_MSG_CURRENCY line.
---@param text string
---@return string? link
---@return integer count
function Recorder.ParseCurrency(text)
    local link = text:match("(|c[^|]*|Hcurrency:.-|h.-|h|r)") or text:match("(|Hcurrency:.-|h.-|h)")
    return link, tonumber(text:match("|h|?r?%s*x(%d+)")) or 1
end

-- The whole name: Forever's UnitName gives the first name and the surname apart.
local function characterKey()
    local name, surname = UnitName("player")
    if surname and surname ~= "" then
        return (name or "?") .. " " .. surname
    end
    return name or "?"
end

local function qualityOf(link)
    return C_Item.GetItemQualityByID(link) or tonumber(link:match("|cnIQ(%d+):")) or 1
end

local function trim(limit)
    local entries = Recorder.db.entries
    local extra = #entries - limit
    if extra <= 0 then
        return
    end
    local kept = {}
    for i = extra + 1, #entries do
        kept[#kept + 1] = entries[i]
    end
    Recorder.db.entries = kept
end

--- Loads the saved log. Safe to call more than once.
function Recorder.Bind()
    local db = _G.EternityUILootDB
    if type(db) ~= "table" then
        db = {}
        _G.EternityUILootDB = db
    end
    db.version = 1
    db.entries = db.entries or {}
    Recorder.db = db
end

--- Whether the options keep this entry.
---@param entry table
---@return boolean
function Recorder.Wanted(entry)
    if not opt("history.enabled") then
        return false
    elseif entry.kind == "money" then
        return opt("history.money")
    elseif entry.kind == "currency" then
        return opt("history.currency")
    elseif entry.looter and not opt("history.others") then
        return false
    elseif entry.pushed and not opt("history.received") then
        return false
    end
    return (entry.quality or 1) >= tonumber(opt("history.minQuality"))
end

--- Saves an entry, if the options want it.
---@param entry table kind, count and, for items and currencies, link, name, quality and icon
function Recorder.Add(entry)
    if not Recorder.Wanted(entry) then
        return
    end
    entry.time = time()
    entry.character = characterKey()
    entry.zone = GetRealZoneText()
    local entries = Recorder.db.entries
    entries[#entries + 1] = entry
    local limit = opt("history.limit")
    if #entries > limit + TRIM_MARGIN then
        trim(limit)
    end
    if Recorder.onAdd then
        Recorder.onAdd()
    end
end

--- Cuts the log to the limit, after the option changes.
function Recorder.Trim()
    trim(opt("history.limit"))
end

--- Empties the log.
function Recorder.Clear()
    Recorder.db.entries = {}
end

--- The characters in the log, sorted.
---@return string[]
function Recorder.Characters()
    local seen, list = {}, {}
    for _, entry in ipairs(Recorder.db.entries) do
        if entry.character and not seen[entry.character] then
            seen[entry.character] = true
            list[#list + 1] = entry.character
        end
    end
    table.sort(list)
    return list
end

-- The slot of a recent window that a chat line talks about, if any.
local function claim(kind, key)
    local now = GetTime()
    for i = #recent, 1, -1 do
        local slot = recent[i]
        if now - slot.at > MATCH_SECONDS then
            break
        end
        if not slot.used and slot.kind == kind and (kind == "money" or slot.key == key) then
            slot.used = true
            return slot
        end
    end
    return nil
end

local function itemEntry(line)
    local slot = line.own and claim("item", keyOf(line.link))
    return {
        kind = "item",
        link = line.link,
        name = line.link:match("|h%[(.-)%]|h"),
        quality = slot and slot.quality or qualityOf(line.link),
        icon = C_Item.GetItemIconByID(line.link),
        count = line.count,
        source = slot and slot.source or nil,
        looter = line.looter,
        pushed = line.pushed,
    }
end

local function currencyEntry(link, count)
    local info = C_CurrencyInfo.GetCurrencyInfoFromLink(link)
    local slot = claim("currency", keyOf(link))
    return {
        kind = "currency",
        link = link,
        name = link:match("|h%[(.-)%]|h"),
        quality = info and info.quality or 1,
        icon = info and info.iconFileID,
        count = count,
        source = slot and slot.source or nil,
    }
end

--- Takes a loot chat line. Secret ones can't be read: see the top of this file.
---@param event string
---@param text any
function Recorder.OnChat(event, text)
    if Secret.Is(text) then
        blindAt = GetTime()
    elseif event == "CHAT_MSG_LOOT" then
        local line = Recorder.ParseItem(text)
        if line then
            Recorder.Add(itemEntry(line))
        end
    elseif event == "CHAT_MSG_MONEY" then
        local copper = Recorder.ParseMoney(text)
        if copper then
            local slot = claim("money")
            Recorder.Add({ kind = "money", count = copper, source = slot and slot.source or nil })
        end
    else
        local link, count = Recorder.ParseCurrency(text)
        if link then
            Recorder.Add(currencyEntry(link, count))
        end
    end
end

-- Where a slot's loot comes from, when the game lets it be known.
local function sourceOf(slot)
    if IsFishingLoot() then
        return L.FISHING
    end
    local guid = GetLootSourceInfo(slot)
    if not guid or Secret.Is(guid) then
        return nil
    end
    for _, unit in ipairs({ "target", "mouseover" }) do
        if Secret.Plain(UnitGUID(unit)) == guid then
            return Secret.Plain((UnitName(unit)))
        end
    end
    local kind = guid:match("^(%a+)-")
    return kind == "GameObject" and L.OBJECT or kind == "Item" and L.CONTAINER or nil
end
Recorder.SourceOf = sourceOf

local function kindOf(slot)
    local slotType = GetLootSlotType(slot)
    if slotType == Enum.LootSlotType.Money then
        return "money"
    elseif slotType == Enum.LootSlotType.Currency then
        return "currency"
    elseif slotType == Enum.LootSlotType.Item then
        return "item"
    end
    return nil
end

local function snapshot(slot)
    local icon, name, count, currencyID, quality = GetLootSlotInfo(slot)
    local link = GetLootSlotLink(slot)
    local kind = kindOf(slot)
    if not kind or not name or not Secret.Known(icon, name, count, currencyID, quality, link) then
        return nil
    end
    return {
        kind = kind,
        key = kind == "currency" and tostring(currencyID) or keyOf(link),
        link = link,
        name = name,
        icon = icon,
        count = kind == "money" and Recorder.ParseCopper(name) or count,
        quality = quality,
        source = sourceOf(slot),
        at = GetTime(),
    }
end

--- Notes what the loot window holds. LOOT_READY and LOOT_OPENED both call it; once is enough.
function Recorder.Open()
    if session then
        return
    end
    session = {}
    -- Only the last moments matter: drop the rest.
    local now, kept = GetTime(), {}
    for _, slot in ipairs(recent) do
        if now - slot.at <= MATCH_SECONDS then
            kept[#kept + 1] = slot
        end
    end
    recent = kept
    for index = 1, GetNumLootItems() do
        local slot = snapshot(index)
        if slot then
            session[index] = slot
            recent[#recent + 1] = slot
        end
    end
end

--- Records a taken slot whose chat line never came, if the line was lost to secrecy.
---@param slot table
function Recorder.Settle(slot)
    if slot.used or GetTime() - blindAt > BLIND_SECONDS then
        return
    end
    slot.used = true
    Recorder.Add({
        kind = slot.kind,
        link = slot.link,
        name = slot.name,
        quality = slot.quality,
        icon = slot.icon,
        count = slot.count,
        source = slot.source,
    })
end

--- A slot was emptied.
---@param index integer
function Recorder.Cleared(index)
    local slot = session and session[index]
    if slot then
        session[index] = nil
        C_Timer.After(SETTLE_SECONDS, function()
            Recorder.Settle(slot)
        end)
    end
end

--- The loot window closed.
function Recorder.Close()
    session = nil
end
