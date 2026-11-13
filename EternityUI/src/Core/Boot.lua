-- Startup. SavedVariables exist at ADDON_LOADED, but the character is only known for sure at
-- PLAYER_LOGIN, so the store and the modules start there.
---@type string, EternityUINamespace
local addonName, ns = ...
local Events = ns.Events
local L = ns.L

local Boot = {}

Events.On("ADDON_LOADED", Boot, function(_, loaded)
    if loaded ~= addonName then
        return
    end
    Events.Off("ADDON_LOADED", Boot)
    EternityUIDB = EternityUIDB or {}
    ns.db = EternityUIDB
end)

Events.On("PLAYER_LOGIN", Boot, function()
    Events.Off("PLAYER_LOGIN", Boot)
    -- Boot's handler runs before the metrics' own one: mark the event here, before the work.
    ns.Startup.Mark("PLAYER_LOGIN")
    ns.Schema.Register(ns.CoreOptions)
    ns.store = ns.Store.New(ns.db, ns.Secret.Plain(UnitGUID("player")), function(module, path, value)
        ns.Modules.OnStoreChanged(module, path, value)
        Events.Send(ns.CONFIG_CHANGED, module, path, value)
        if path == "appearance.pixelPerfect" then
            ns.Pixel.ApplyInterfaceScale(value)
        end
    end)
    EternityUI.store = ns.store
    ns.store:Sanitize("EternityUI")
    ns.Theme.Reload()
    ns.Startup.Mark("STORE_READY")
    ns.Modules.Start()
    ns.Startup.Mark("MODULES_STARTED")
    Events.Send(EternityUI.READY)
    ns.Startup.Mark("READY_SENT")
    if ns.store:Get("EternityUI", "appearance.pixelPerfect") then
        ns.Pixel.ApplyInterfaceScale(true)
    end
    if ns.store:Get("EternityUI", "general.loadMessage") then
        ns.Print(L.LOADED:format(EternityUI.version))
    end
end)

-- Logins and reloads are counted apart: a login count that survives quitting the game is the
-- proof that SavedVariables persist.
Events.On("PLAYER_ENTERING_WORLD", Boot, function(_, isLogin, isReload)
    Events.Off("PLAYER_ENTERING_WORLD", Boot)
    local stats = ns.store.raw.stats
    if isLogin then
        stats.logins = stats.logins + 1
    elseif isReload then
        stats.reloads = stats.reloads + 1
    end
end)
