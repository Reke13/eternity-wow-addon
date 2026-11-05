-- EternityUI_Automation texts (enUS and esES). The options' texts live in options.json.

---The module's private table.
---@class EternityUIAutomationNamespace
---@field OptionsSchema table schema generated from options.json (src/Generated/Options.lua)
---@field L table<string, string>
---@field Core EternityUIAutomationCore

---@type string, EternityUIAutomationNamespace
local _, ns = ...

local strings = {
    enUS = {
        SOLD_JUNK = "Sold junk for %s.",
        REPAIRED_GUILD = "Repaired for %s (guild funds).",
        REPAIRED = "Repaired for %s.",
        REPAIR_NO_MONEY = "Not enough gold to repair (%s).",
        INVITE_ACCEPTED = "Accepted the group invite from %s.",
        INVITED = "Invited %s.",
        DUEL_DECLINED = "Declined a duel from %s.",
        PET_DUEL_DECLINED = "Declined a pet battle duel.",
        GUILD_DECLINED = "Declined the invite to <%s> from %s.",
        RESURRECT_ACCEPTED = "Accepted the resurrection from %s.",
        SUMMON_ACCEPTED = "Accepted the summon from %s to %s.",
        QUEST_SHARED = "Shared %s.",
        CINEMATIC_SKIPPED = "Skipped a cinematic.",
        MOVIE_SKIPPED = "Skipped a movie.",
        SOMEONE = "someone",
    },
    esES = {
        SOLD_JUNK = "Basura vendida por %s.",
        REPAIRED_GUILD = "Reparado por %s (fondos de hermandad).",
        REPAIRED = "Reparado por %s.",
        REPAIR_NO_MONEY = "No tienes oro para reparar (%s).",
        INVITE_ACCEPTED = "Aceptada la invitación a grupo de %s.",
        INVITED = "Invitado %s.",
        DUEL_DECLINED = "Rechazado un duelo de %s.",
        PET_DUEL_DECLINED = "Rechazado un duelo de mascotas.",
        GUILD_DECLINED = "Rechazada la invitación a <%s> de %s.",
        RESURRECT_ACCEPTED = "Aceptada la resurrección de %s.",
        SUMMON_ACCEPTED = "Aceptada la invocación de %s a %s.",
        QUEST_SHARED = "Compartida %s.",
        CINEMATIC_SKIPPED = "Cinemática saltada.",
        MOVIE_SKIPPED = "Vídeo saltado.",
        SOMEONE = "alguien",
    },
}
strings.esMX = strings.esES

ns.L = setmetatable(strings[GetLocale()] or {}, { __index = strings.enUS })
