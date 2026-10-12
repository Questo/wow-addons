# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Seven independent World of Warcraft addons for **WoW: Forever**, each in its own top-level folder (CharacterLedger, EmoteWheel, FieldJournal, IconFinder, ImmersiveUI, Keepsakes, WindowMover). They share no code; each folder is installed on its own into `Interface/AddOns/`. Plain Lua frames, no libraries (no Ace3/LibStub) and no XML other than the `Bindings.xml` files in FieldJournal and EmoteWheel.

## Build, test, release

There is no build step, linter or test suite. Code only runs inside the game client:

- Install by copying (or symlinking) an addon folder into `World of Warcraft/_forever_/Interface/AddOns/` (or `_retail_`, depending on the install). The path must end `AddOns/<Name>/<Name>.toc`.
- A **new** addon, or a new file added to a `.toc`, needs a full game restart. Edits to existing files are picked up by `/reload`.
- Release zips, one per addon, from the repo root (zips are gitignored). Each zip must contain the addon folder itself, not just its files. The README has the `sh` loop and a PowerShell `Compress-Archive` equivalent; keep both in sync if the process changes.

## Versioning

A version bump touches three places: `## Version:` in the addon's `.toc`, the first line of its `README.txt` (if it has one), and the table in the root `README.md`. The root README table also lists each addon's slash commands, so update it when those change.

## Architecture and conventions

- **The `.toc` sets load order.** Multi-file addons (CharacterLedger, FieldJournal, ImmersiveUI) share state through the addon-private table: `local addonName, ns = ...`. A later file can call functions an earlier file defined on `ns` only after load (e.g. in event handlers). Every `.toc` targets `## Interface: 16001, 120100`.
- **Two client versions, one codebase.** Blizzard frame and API names differ between the two interfaces, so code looks them up defensively:
  - Frame lists with fallbacks: the first name that exists wins (`ImmersiveUI/Config.lua` `ns.groups`, `WindowMover/Core.lua` `WINDOWS`).
  - Optional APIs are checked before use (`if GetMoneyString then ...`, `C_TradeSkillUI.GetBaseProfessionInfo and ...`).
  - Events that a client might not have are registered with `pcall(frame.RegisterEvent, frame, event)`.
- **Secret values.** WoW: Forever hides some unit values from addons, mostly in combat and instances. Wrap every value read from the game in a `clean()` helper that returns `nil` when `issecretvalue(v)` is true, and treat `nil` as unknown. FieldJournal's `ns.query(fn, ...)` (`FieldJournal/Core.lua`) does both: it calls through `pcall` and runs `clean` on the results. Use it for new game queries there.
- **Taint and combat lockdown.** Avoid tainting secure frames. ImmersiveUI fades only with `SetAlpha` and hooks it with `hooksecurefunc`; it never uses `Show`/`Hide` on protected frames. Keepsakes can't block a sale through Blizzard's secure item buttons, so it lays its own plain button over starred items at the vendor. Post-hook Blizzard functions with `hooksecurefunc`; never replace them.
- **SavedVariables.** Each addon creates its DB on `ADDON_LOADED` (matching `addonName`) or on `PLAYER_LOGIN`, then fills in missing keys from its defaults. Migrations are written inline as one-time flags (e.g. `db.tooltipDefaultOff` in `CharacterLedger/Data.lua`). FieldJournal uses `SavedVariablesPerCharacter`, so each journal belongs to one character; the others are account-wide. CharacterLedger stores characters under `db.chars["Name-Realm"]`.
- **Data the game only shows while a window is open.** The bank, mailbox and profession recipes can only be read while that window is open. CharacterLedger records a snapshot each time the window opens (typically after `C_Timer.After(0.5, ...)`) and shows it later.
- **Late-loading Blizzard UI.** Some Blizzard windows load on first open. WindowMover and FieldJournal watch `ADDON_LOADED` for Blizzard addons to hook those windows when they appear.
- **FieldJournal cross-file hooks.** `Core.lua` defines no-op `ns.EntryChanged` / `ns.PinChanged` that `UI.lua` and `Pin.lua` overwrite, and other files push init functions into `ns.onLoad`, which runs after the DB is ready. Global functions (`FieldJournal_Toggle`, etc.) exist for `Bindings.xml`. The `BINDING_*` strings are defined in `Core.lua`.
- Chat output goes through each addon's `say()`/`ns.Say()`, which adds a colored addon-name prefix. Addons that appear in the addon compartment define a global `<Name>_OnAddonCompartmentClick`, named in the `.toc`.

## Writing style

Code comments and user-facing text (chat messages, READMEs) use plain, friendly English addressed to the player ("you"), not developer jargon. Match that tone.
