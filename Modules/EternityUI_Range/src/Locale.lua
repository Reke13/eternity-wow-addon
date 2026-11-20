-- EternityUI_Range texts (enUS and esES). The options' texts live in options.json.

---The module's private table.
---@class EternityUIRangeNamespace
---@field OptionsSchema table schema generated from options.json (src/Generated/Options.lua)
---@field L table<string, string>
---@field Distance table works out the distance from spell ranges (Distance.lua)
---@field Module table

---@type string, EternityUIRangeNamespace
local _, ns = ...

ns.L = EternityUI.NewLocale({
    MOVER = "Range: distance to the target",
    UNIT = " yd",
    PREVIEW = "8-35",
}, {
    MOVER = "Distancia: al objetivo",
    UNIT = " m",
    PREVIEW = "8-35",
})
