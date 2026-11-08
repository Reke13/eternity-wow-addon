# Notes for coding agents

Eternity is a UI suite for **World of Warcraft: Forever** (wowlua flavor `camelot`, Interface 16001). It targets Forever only.

## Layout

- `EternityUI/`: the core. It exposes one global, `EternityUI`: store, modules, theme, widgets, Mover, combat queue and events.
- `EternityUI_Options/`: the options window and the Mover, loaded on demand.
- `Modules/EternityUI_*/`: one addon per part of the UI, each with `wowlua.json`, `options.json`, `src/` and `tests/`.

Modules register with `EternityUI:RegisterModule(name, definition)`. A module's own tabs are `definition.tabs`, with `build(parent, setHeight)` returning a view that has a `Refresh` method. Read options with `EternityUI.store:Get(module, path)` and register movable frames with `EternityUI.Mover.Register`, setting `owner` to the module's name.

## Building

The build scripts live in a private workspace, not here, so this repository can't build or run its tests on its own. Don't add a second build system. Install from the zip in Releases.

Don't edit generated output by hand: `src/Generated/Options.lua` comes from each module's `options.json`, and TOC files come from `wowlua.json`. Change the source, and say in your pull request that the options need regenerating.

## Releases and versions

Every addon in the repository shares one version: `package.version` in each `wowlua.json` matches the release tag (`v0.1.6`). Bump them all together when releasing.

### Changelog

Each release's notes list what changed since the previous tag, so players know what they're getting. Build them from `git log <previous tag>..HEAD` and the merged pull requests:

- Keep the install line at the top: unzip into `World of Warcraft\_forever_\Interface\AddOns` and restart the game.
- Then, by addon (Core, Options, then each module in the README's order), only the ones that changed, under **Added**, **Changed**, **Fixed** and **Removed**.
- Write for players, not for code: what they see or can now do ("The info bar can show bag slots"), not function names. One line per change.
- Add **Upgrading** when a player has to do something or will notice a loss: a new or removed addon folder (restart the game, delete the old folder), settings that go back to their defaults, a frame placed again with the Mover, a renamed slash command.
- Name the pull requests or contributors that brought each part.

### Which number to raise

Versions follow `MAJOR.MINOR.PATCH`. While the suite is `0.x` (pre-releases), MINOR does the job of MAJOR and MINOR together:

| Raise | When a release has... | Examples |
| --- | --- | --- |
| **PATCH** (`0.1.6` → `0.1.7`) | Only fixes, texts, translations, performance or looks, with no new option and nothing for players to do | An error fixed, a wrong color, a faster update |
| **MINOR** (`0.1.6` → `0.2.0`) | A new module, a new feature or new options, still compatible with saved settings | A new module, a new tab, new items in a bar |
| **MAJOR** (from `1.0.0`; before it, MINOR) | Something that breaks what players or modules relied on | Saved settings or saved data dropped or renamed without migration, a module removed or renamed, the core's API changed for modules, a client change that needs a fresh install |

- The highest kind of change in the release decides: one new option among ten fixes is still MINOR.
- Reset the lower numbers when raising one (`0.1.7` → `0.2.0`).
- Go to `1.0.0` when the suite is meant to be stable for everyone, and stop marking releases as pre-releases from then on.
- When unsure between two, pick the higher one and say why in the notes.

## Rules

- Code, comments and docs are in English. Player-facing text is enUS and esES.
- Lua 5.1. Tests are `*.test.wowlua`.
- Addons are independent. No module depends on another, and disabling one gives Blizzard's UI back, without `/reload` whenever possible.
- Use the core's widgets when they exist. Addon `src/Ui.lua` files are thin layers over them.
- Blizzard's restrictions are not worked around: secret values, protected frames and taint are limits to design for.
- `src/libs/` holds third-party libraries, kept exactly as published.
- Don't call anything tested in game unless it was run on the real client. Tests run in an emulator.

## Forever pitfalls

Check every API against what the client exports: [wow-ui-source](https://github.com/Gethe/wow-ui-source) shows what Forever ships, and much of it differs from Retail.

- **Secret values:** comparing or doing arithmetic on one errors. Check with `issecretvalue` first, or pass the value untouched to a widget that accepts it.
- **Geometry can be secret:** `GetWidth` and `GetHeight` of a frame showing secret values return secrets, so check before doing math on them.
- **Auras:** they can't be read while `C_Secrets.ShouldAurasBeSecret()` is true, which covers combat. A check that can't tell should keep its last state.
- **Secure buttons:** register `LeftButtonUp` and `LeftButtonDown`. `SecureActionButton_OnClick` acts on the press when the `ActionButtonUseKeyDown` CVar is on, so an up-only button does nothing and shows no error. With both registered, set `useOnKeyDown = false` and make wrapper snippets ignore the press, or a click runs twice.
- **Restricted snippets:** `RunAttribute` scrubs its return values, so a frame handle comes back nil. Return an index and fetch the frame with `GetFrameRef`.
- **Combat:** protected frames only change out of combat. Queue that work with `EternityUI.Combat.Run`.
- **Taint:** don't call Blizzard methods that run its panel or Edit Mode layout, don't write fields on Blizzard's frames and tables, don't replace Blizzard methods (use `hooksecurefunc` or `HookScript`), and don't use `UISpecialFrames`. Tainted code that later meets a secret value errors, and nothing clears it short of `/reload`.
- **Bag buttons:** never call `ContainerFrameItemButtonMixin:Initialize` from an addon. `SetID` on the parent and on the button is enough.
- **Textures:** `texture:SetAlpha` replaces the alpha of its vertex color, so put opacity in the color. TGAs have no mipmaps, so a large texture scaled far down comes out jagged.
- **Fonts:** `FontString:SetText` errors until the string has a font.
- **Events:** registering an unknown event errors. `EternityUI.Events.On` checks first.
