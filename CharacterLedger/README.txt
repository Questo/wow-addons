Character Ledger 0.5.0

Install
1. Quit the game completely (a /reload does not pick up a new addon).
2. If you installed Who Has It, delete the WhoHasIt folder from your AddOns
   folder. Character Ledger replaces it.
3. Unzip CharacterLedger.zip into your AddOns folder, so you end up with
   World of Warcraft\_forever_\Interface\AddOns\CharacterLedger\CharacterLedger.toc
   (use the folder for your game version if it's named differently).
4. Start the game and make sure Character Ledger is ticked in the AddOns list.
   You should see "Character Ledger: loaded" in chat when you log in.

Getting started
- Log in once on each character so it gets remembered.
- Visit a banker once on each character so its bank gets remembered.
  The bank can only be read while it's open, so bank counts are from your last visit.
- Open each profession window once on each character so its recipes get
  remembered (the game only shares recipes while the window is open). Recipes you learn later are
  picked up the next time you open that profession.

Use
- /ledger (or the addon button by the minimap) opens the ledger.
- Characters tab: level, item level, gold, rested XP, played time, professions
  and where you left each character. The footer adds up gold and played time
  for all of them. Hover a row to also see time played at the current level.
  Played time is read a few seconds after you log in on each character
  (without the usual /played lines in chat). Hover a row for more detail. Rested XP for other
  characters is estimated from the time since you logged out.
- Items tab: type part of an item name to see who has it and how many.
  Hover an item for its tooltip, shift-click to link it in chat.
- Recipes tab: search everything your characters can craft, by recipe or
  profession name, and see who knows each recipe. The dropdown next to the
  search box shows one profession at a time, or all of them.
- Lockouts tab: which raids and dungeons each character is saved to, bosses
  killed and when it resets. A character's lockouts update when you log in on it.
- Mail tab: how many letters each character has waiting, how many are unread,
  items and gold attached, when the first letter with items or gold runs out,
  and when you last checked. Hover a row to see the letters. Mail is read when
  you open a mailbox, so open one once on each character. A small letter icon
  next to a name on the Characters tab means that character has mail waiting.
  When you log in, chat warns you if any character has mail with items or gold
  that runs out within 3 days (it would be sent back or lost).
- Loot tab: everything your characters loot, newest first: the item, how
  many, where it came from (the creature, the node you mined or picked, a
  chest, fishing), the zone, which character and when. Quest rewards and other
  items handed to you say "Received", things you make say "Crafted".
  Type in the search box to look through items, sources, zones and names.
  Hover an entry for the item, shift-click to link it in chat. The log keeps
  the newest 3000 entries and starts recording from this version on.
- Item tooltips (off by default): tick "Show in item tooltips" at the bottom
  of the ledger window, or type /ledger tooltip, and item tooltips list who
  has the item (bags, bank, equipped, warband bank and a total), who can craft
  it ("Crafted by") and whose recipes use it ("Used by").
- /ledger recipes <name>, /ledger lockouts, /ledger mail and /ledger loot <name> open those tabs directly.
- /whohas <item> opens the Items tab searching for that item.
- /ledger forget <name> removes a character you deleted.
- /ledger tooltip turns the tooltip lines on and off.
