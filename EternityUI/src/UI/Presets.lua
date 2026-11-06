-- The themes: full looks with palette, accent, second accent, corners, surfaces and font.
---@type string, EternityUINamespace
local _, ns = ...
local Theme = ns.Theme

-- Eternity's own.
Theme.RegisterPreset("midnight", {
    colors = {
        window = { 0.078, 0.067, 0.11 },
        windowTop = { 0.11, 0.09, 0.157 },
        text = { 0.94, 0.93, 0.97, 1 },
        textMuted = { 0.64, 0.62, 0.72, 1 },
        textDisabled = { 0.43, 0.41, 0.5, 1 },
        danger = { 0.97, 0.46, 0.56, 1 },
    },
    accent = "#8B5CF6",
    accent2 = "#38BDF8",
    corners = "round",
    style = "glass",
    font = "arialn",
})
Theme.RegisterPreset("obsidian", {
    colors = {
        window = { 0.067, 0.067, 0.075 },
        windowTop = { 0.1, 0.1, 0.11 },
        text = { 0.93, 0.93, 0.94, 1 },
        textMuted = { 0.62, 0.62, 0.66, 1 },
        textDisabled = { 0.41, 0.41, 0.44, 1 },
        danger = { 0.96, 0.44, 0.44, 1 },
    },
    accent = "#8B5CF6",
    accent2 = "#2DD4BF",
    corners = "round",
    style = "glass",
    font = "arialn",
})

-- Closer to WoW: warm stone, gold and the classic font.
Theme.RegisterPreset("azeroth", {
    colors = {
        window = { 0.086, 0.071, 0.051 },
        windowTop = { 0.149, 0.118, 0.078 },
        text = { 1, 0.96, 0.86, 1 },
        textMuted = { 0.78, 0.7, 0.55, 1 },
        textDisabled = { 0.5, 0.45, 0.36, 1 },
        danger = { 1, 0.32, 0.26, 1 },
        border = { 1, 0.82, 0.4, 0.16 },
        borderStrong = { 1, 0.82, 0.4, 0.34 },
        divider = { 1, 0.82, 0.4, 0.1 },
        surface = { 1, 0.9, 0.7, 0.035 },
    },
    accent = "#FFD100",
    accent2 = "#1EFF00",
    corners = "soft",
    style = "glass",
    font = "friz",
})
Theme.RegisterPreset("horde", {
    colors = {
        window = { 0.094, 0.051, 0.043 },
        windowTop = { 0.165, 0.071, 0.059 },
        text = { 0.98, 0.92, 0.88, 1 },
        textMuted = { 0.76, 0.61, 0.56, 1 },
        textDisabled = { 0.48, 0.38, 0.35, 1 },
        danger = { 1, 0.42, 0.3, 1 },
        border = { 1, 0.4, 0.3, 0.14 },
        borderStrong = { 1, 0.4, 0.3, 0.3 },
        divider = { 1, 0.4, 0.3, 0.09 },
    },
    accent = "#D4352B",
    accent2 = "#F59E0B",
    corners = "soft",
    style = "glass",
    font = "friz",
})
Theme.RegisterPreset("alliance", {
    colors = {
        window = { 0.047, 0.067, 0.118 },
        windowTop = { 0.078, 0.11, 0.188 },
        text = { 0.93, 0.95, 1, 1 },
        textMuted = { 0.62, 0.68, 0.8, 1 },
        textDisabled = { 0.4, 0.44, 0.54, 1 },
        danger = { 0.97, 0.44, 0.44, 1 },
        border = { 0.91, 0.73, 0.29, 0.14 },
        borderStrong = { 0.91, 0.73, 0.29, 0.3 },
        divider = { 0.91, 0.73, 0.29, 0.09 },
    },
    accent = "#E9B949",
    accent2 = "#3B82F6",
    corners = "soft",
    style = "glass",
    font = "friz",
})

-- Futuristic.
Theme.RegisterPreset("holo", {
    colors = {
        window = { 0.02, 0.059, 0.086 },
        windowTop = { 0.039, 0.102, 0.141 },
        text = { 0.85, 0.97, 1, 1 },
        textMuted = { 0.5, 0.72, 0.8, 1 },
        textDisabled = { 0.3, 0.45, 0.52, 1 },
        danger = { 1, 0.36, 0.5, 1 },
        surface = { 0.6, 0.95, 1, 0.04 },
        field = { 0.6, 0.95, 1, 0.06 },
    },
    accent = "#22D3EE",
    accent2 = "#A78BFA",
    corners = "sharp",
    style = "neon",
    font = "arialn",
})
Theme.RegisterPreset("frost", {
    colors = {
        window = { 0.078, 0.11, 0.149 },
        windowTop = { 0.13, 0.17, 0.23 },
        text = { 0.95, 0.98, 1, 1 },
        textMuted = { 0.66, 0.75, 0.85, 1 },
        textDisabled = { 0.43, 0.5, 0.58, 1 },
        danger = { 0.98, 0.5, 0.58, 1 },
        surface = { 0.85, 0.95, 1, 0.05 },
        surfaceHover = { 0.85, 0.95, 1, 0.08 },
        border = { 0.85, 0.95, 1, 0.12 },
        borderStrong = { 0.85, 0.95, 1, 0.24 },
    },
    accent = "#7DD3FC",
    accent2 = "#C4B5FD",
    corners = "round",
    style = "glass",
    font = "arialn",
})

-- Cyberpunk.
Theme.RegisterPreset("neon", {
    colors = {
        window = { 0.051, 0.02, 0.078 },
        windowTop = { 0.09, 0.031, 0.129 },
        text = { 0.98, 0.9, 1, 1 },
        textMuted = { 0.72, 0.58, 0.82, 1 },
        textDisabled = { 0.45, 0.36, 0.52, 1 },
        danger = { 1, 0.24, 0.42, 1 },
    },
    accent = "#FF2BD6",
    accent2 = "#00F0FF",
    corners = "sharp",
    style = "neon",
    font = "arialn",
})
Theme.RegisterPreset("nightcity", {
    colors = {
        window = { 0.039, 0.039, 0.031 },
        windowTop = { 0.078, 0.078, 0.047 },
        text = { 0.98, 0.98, 0.85, 1 },
        textMuted = { 0.7, 0.7, 0.55, 1 },
        textDisabled = { 0.44, 0.44, 0.35, 1 },
        danger = { 1, 0, 0.235, 1 },
    },
    accent = "#FCEE0A",
    accent2 = "#FF003C",
    corners = "sharp",
    style = "neon",
    font = "arialn",
})

-- Full dark.
Theme.RegisterPreset("void", {
    colors = {
        window = { 0, 0, 0 },
        windowTop = { 0, 0, 0 },
        text = { 0.9, 0.9, 0.9, 1 },
        textMuted = { 0.55, 0.55, 0.55, 1 },
        textDisabled = { 0.34, 0.34, 0.34, 1 },
        danger = { 0.92, 0.36, 0.36, 1 },
        surface = { 1, 1, 1, 0.03 },
        border = { 1, 1, 1, 0.09 },
        borderStrong = { 1, 1, 1, 0.18 },
        shadow = { 0, 0, 0, 1 },
    },
    accent = "#E5E5E5",
    accent2 = "#737373",
    corners = "soft",
    style = "flat",
    font = "arialn",
})
Theme.RegisterPreset("graphite", {
    colors = {
        window = { 0.11, 0.11, 0.118 },
        windowTop = { 0.137, 0.137, 0.145 },
        text = { 0.9, 0.9, 0.91, 1 },
        textMuted = { 0.6, 0.6, 0.63, 1 },
        textDisabled = { 0.4, 0.4, 0.42, 1 },
        danger = { 0.94, 0.42, 0.42, 1 },
    },
    accent = "#94A3B8",
    accent2 = "#F97316",
    corners = "soft",
    style = "flat",
    font = "arialn",
})

-- Pink.
Theme.RegisterPreset("bubblegum", {
    colors = {
        window = { 0.204, 0.055, 0.153 },
        windowTop = { 0.333, 0.086, 0.243 },
        text = { 1, 0.94, 0.97, 1 },
        textMuted = { 0.9, 0.66, 0.8, 1 },
        textDisabled = { 0.6, 0.42, 0.54, 1 },
        danger = { 1, 0.36, 0.36, 1 },
        surface = { 1, 0.75, 0.88, 0.05 },
        surfaceHover = { 1, 0.75, 0.88, 0.09 },
        border = { 1, 0.6, 0.8, 0.14 },
        borderStrong = { 1, 0.6, 0.8, 0.3 },
        divider = { 1, 0.6, 0.8, 0.09 },
    },
    accent = "#FF4FA3",
    accent2 = "#7DE3FF",
    corners = "round",
    style = "glass",
    font = "arialn",
})
Theme.RegisterPreset("sakura", {
    colors = {
        window = { 0.227, 0.133, 0.188 },
        windowTop = { 0.353, 0.212, 0.278 },
        text = { 1, 0.96, 0.97, 1 },
        textMuted = { 0.91, 0.75, 0.82, 1 },
        textDisabled = { 0.6, 0.48, 0.54, 1 },
        danger = { 1, 0.42, 0.42, 1 },
        surface = { 1, 0.85, 0.92, 0.05 },
        surfaceHover = { 1, 0.85, 0.92, 0.09 },
        border = { 1, 0.75, 0.85, 0.14 },
        borderStrong = { 1, 0.75, 0.85, 0.3 },
        divider = { 1, 0.75, 0.85, 0.09 },
    },
    accent = "#FFB3D1",
    accent2 = "#FFE8A3",
    corners = "round",
    style = "glass",
    font = "friz",
})
Theme.RegisterPreset("fuchsia", {
    colors = {
        window = { 0.141, 0.016, 0.11 },
        windowTop = { 0.239, 0.027, 0.188 },
        text = { 1, 0.94, 0.97, 1 },
        textMuted = { 0.88, 0.56, 0.78, 1 },
        textDisabled = { 0.55, 0.36, 0.5, 1 },
        danger = { 1, 0.3, 0.3, 1 },
    },
    accent = "#FF1FA8",
    accent2 = "#FFE14D",
    corners = "round",
    style = "neon",
    font = "arialn",
})
Theme.RegisterPreset("cottoncandy", {
    colors = {
        window = { 0.231, 0.137, 0.314 },
        windowTop = { 0.357, 0.227, 0.471 },
        text = { 0.98, 0.95, 1, 1 },
        textMuted = { 0.84, 0.74, 0.92, 1 },
        textDisabled = { 0.56, 0.48, 0.62, 1 },
        danger = { 1, 0.42, 0.5, 1 },
        surface = { 1, 0.85, 0.96, 0.05 },
        surfaceHover = { 1, 0.85, 0.96, 0.09 },
        border = { 1, 0.7, 0.9, 0.14 },
        borderStrong = { 1, 0.7, 0.9, 0.3 },
        divider = { 1, 0.7, 0.9, 0.09 },
    },
    accent = "#FF8FD0",
    accent2 = "#8FD8FF",
    corners = "round",
    style = "glass",
    font = "arialn",
})

-- For BTS and ARMY: their purple with a soft pink.
Theme.RegisterPreset("borahae", {
    colors = {
        window = { 0.165, 0.071, 0.271 },
        windowTop = { 0.267, 0.125, 0.431 },
        text = { 0.97, 0.94, 1, 1 },
        textMuted = { 0.78, 0.68, 0.92, 1 },
        textDisabled = { 0.5, 0.43, 0.62, 1 },
        danger = { 1, 0.42, 0.52, 1 },
        surface = { 0.85, 0.75, 1, 0.05 },
        surfaceHover = { 0.85, 0.75, 1, 0.09 },
        border = { 0.75, 0.6, 1, 0.16 },
        borderStrong = { 0.75, 0.6, 1, 0.34 },
        divider = { 0.75, 0.6, 1, 0.1 },
    },
    accent = "#9B5DE5",
    accent2 = "#F7C6E0",
    corners = "round",
    style = "glass",
    font = "arialn",
    -- Personal images, not shipped: see Tools/Install-Wallpaper.ps1. aspect is the crop's width / height.
    wallpaper = {
        window = { file = "borahae-window", aspect = 1030 / 655 },
        chat = { file = "borahae-chat", aspect = 2 },
    },
    -- Personal images too: see Tools/Install-Portraits.ps1. Six images share the classes.
    portraits = {
        PALADIN = "borahae-paladin",
        WARRIOR = "borahae-paladin",
        ROGUE = "borahae-rogue",
        HUNTER = "borahae-rogue",
        MAGE = "borahae-mage",
        PRIEST = "borahae-mage",
        SHAMAN = "borahae-shaman",
        EVOKER = "borahae-shaman",
        WARLOCK = "borahae-warlock",
        DEATHKNIGHT = "borahae-warlock",
        DEMONHUNTER = "borahae-warlock",
        DRUID = "borahae-druid",
        MONK = "borahae-druid",
    },
})
