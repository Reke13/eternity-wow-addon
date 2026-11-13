# Eternity

A full interface suite for **World of Warcraft: Forever**. A small core holds the look, the profiles and the Mover, and each part of the UI is its own addon: turn off what you don't want and Blizzard's version comes back.

> Alpha. Some modules have not been fully tried in game yet, so expect rough edges.

## Install

1. Download `Eternity-<version>-forever.zip` from [Releases](https://github.com/jaimesares/eternity-wow-addon/releases).
2. Unzip it into `World of Warcraft\_forever_\Interface\AddOns`.
3. Restart the game.

Type `/et` to open the options. `EternityUI` and `EternityUI_Options` are required; every other addon is optional.

## Modules

| Addon | What it does |
|---|---|
| `EternityUI_ActionBars` | Action bars, with key binding by hovering (`/kb`) |
| `EternityUI_Alerts` | Your own alerts for missing buffs, weapon enchants, durability, bag space and items |
| `EternityUI_Automation` | Small one-switch automations |
| `EternityUI_Bags` | Bags and bank |
| `EternityUI_Buffs` | Blizzard's buff and debuff frames in the Mover |
| `EternityUI_CastBars` | Cast bars, plus GCD and mirror timers |
| `EternityUI_Chat` | Chat look and tools |
| `EternityUI_Discs` | Radial discs of spells, items, toys and macros, opened with a key (`/etdiscs`) |
| `EternityUI_Experience` | Experience bar |
| `EternityUI_InfoBar` | Information bar |
| `EternityUI_Loot` | Loot window that can open at the mouse, searchable loot history (`/etloot`) and a Mover spot for group rolls |
| `EternityUI_Mail` | History of the letters every character sends and receives, from a button by the mailbox (`/etmail`), and the recipient kept after sending |
| `EternityUI_Map` | World map |
| `EternityUI_Minimap` | Minimap and button collector |
| `EternityUI_Objectives` | Quest tracker |
| `EternityUI_Stats` | Detailed stats panel |
| `EternityUI_SwingTimer` | Bars for your main hand, off hand and ranged auto attacks, one stack or each on its own |
| `EternityUI_Resources` | Power bar that follows the druid's forms, combo point pips and the druid's mana while shapeshifted |
| `EternityUI_Blacklist` | Your own list of players of either faction with the reason for each (`/bl`): added from a player's right-click menu, with a warning in the tooltip, on target and in your group |
| `EternityUI_Bugs` | Collects Lua errors, warnings and blocked actions and lists them to read, copy and clear (`/etbugs`) |
| `EternityUI_Auras` | The target's debuffs and your own buffs, each in a frame of its own: filtered by caster, type, duration and your own list of spells per frame, in combat too (`/etauras`) |
| `EternityUI_Tooltip` | Tooltips |
| `EternityUI_UnitFrames` | Frames for you, your pet, target, target of target, focus, group, raid and the group's pets: sizes, bars, texts, auras with buff filters, icons and range fading per frame, with a live preview |

## Your own background images

Four places can show an image of yours behind them. Put it in `World of Warcraft\_forever_\Interface\AddOns\EternityUI_Wallpapers` (a folder of its own, so updating Eternity never deletes it), as a `.tga` file named after where it shows, and switch it on in General > Appearance:

| File | Where it shows | Recommended size |
| --- | --- | --- |
| `Options.tga` | The options window | 1030 × 655 |
| `Chat.tga` | Behind the chat | 1024 × 512 |
| `Quests.tga` | Behind the quests (Objectives) | 512 × 1024 |
| `Bags.tga` | The bags and the bank windows (Bags) | 1024 × 1024 |

Other sizes work too: the image is cropped to the place's shape as if it had that one's proportions. "Image dimming" (Appearance) lays a veil over it so text stays readable. A new image file needs the game restarted.

## License

[MIT](LICENSE). `EternityUI_ActionBars/src/libs` holds third-party libraries under their own licenses: see the [list](Modules/EternityUI_ActionBars/src/libs/README.md).
