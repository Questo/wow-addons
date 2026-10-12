# WoW Addons

A small collection of World of Warcraft addons built for WoW Forever (interface 16001 and 120100).

| Addon | Version | Slash commands | What it does |
|---|---|---|---|
| [Immersive UI](ImmersiveUI) | 0.3.0 | `/iui` | Hides chosen UI until you're in combat or have a target. Action bars show on mouseover, chat and the damage meter fade when idle. The player frame stays up until your health and mana are full, and party frames show while someone in the group is hurt. |
| [Field Journal](FieldJournal) | 0.5.0 | `/fj`, `/journal` | In-character journal per character: notes in folders, encounters, places, quest thoughts, an automatic chronicle (which also notes each screenshot you take) and a pinned page. One search box looks through every section. |
| [Character Ledger](CharacterLedger) | 0.5.0 | `/ledger`, `/characterledger`, `/whohas` | Overview of all your characters (level, item level, gold, rested XP, played time, professions, location), item search, recipes, lockouts, mail waiting per character with expiry warnings, a searchable loot log, and optional item tooltip counts. |
| [Keepsakes](Keepsakes) | 0.2.0 | `/keep`, `/keepsakes` | Alt-click to star an item. Starred items ask before they're sold, can't be deleted, and can carry a short story shown in their tooltip. |
| [Window Mover](WindowMover) | 0.2.0 | `/wmover`, `/windowmover` | Adds a Move button to the bags, character pane, spellbook and talents, map and quest log, collections and professions so you can drag them. Right-click or `/wmover reset` puts them back. |
| [Icon Finder](IconFinder) | 0.2.0 | `/iconfinder` | Adds a search box to the macro and equipment set icon pickers. Search by spell or item name, or an icon ID. Pinned and recent icons sit in a row at the top. |
| [Emote Wheel](EmoteWheel) | 0.1.2 | `/ewheel`, `/emotewheel` | A ring of emotes, your own macros and custom /e lines that opens around the mouse with a key. Left-click to use a slot, right-click to change it. |

## Install

1. Copy the addon folders you want (for example `FieldJournal`) into
   `World of Warcraft/_retail_/Interface/AddOns/`.
   Each folder must sit directly inside `AddOns`, so the path ends in `AddOns/FieldJournal/FieldJournal.toc`.
2. Fully restart the game. A brand new addon is not picked up by `/reload`.
3. Check the addon is enabled in the AddOns list on the character select screen.

If you used the old **Who Has It** addon, delete its folder: Character Ledger replaces it and `/whohas` still works.

## Making release zips

From the repository root, zip each addon folder on its own. Each zip holds the folder itself, so it unzips to `FieldJournal/FieldJournal.toc` and so on.

On macOS or Linux:

```sh
for a in */; do zip -r "${a%/}.zip" "${a%/}"; done
```

On Windows, in PowerShell:

```powershell
Get-ChildItem -Directory | ForEach-Object {
    Compress-Archive -Path $_.FullName -DestinationPath "$($_.Name).zip" -Force
}
```

Zips are ignored by git (see `.gitignore`).
