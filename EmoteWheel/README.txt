Emote Wheel 0.1.2

Install
1. Quit the game completely (a /reload does not pick up a new addon).
2. Unzip EmoteWheel.zip into your AddOns folder, so you end up with
   World of Warcraft\_forever_\Interface\AddOns\EmoteWheel\EmoteWheel.toc
   (use the folder for your game version if it's named differently).
3. Start the game and make sure Emote Wheel is ticked in the AddOns list.
   You should see "Emote Wheel: loaded" in chat when you log in.

Use
- Bind a key: Options > Keybindings > AddOns > Emote Wheel. Press it and the
  wheel opens around your mouse. Press it again (or Escape) to close it.
  /ewheel does the same.
- Left-click a slot to do it. The wheel closes afterwards.
- Right-click a slot to change it:
  - Emote: pick from a list (wave, bow, cheer, sit, dance and more).
  - Your macros: put one of your own macros on the slot, with its icon.
    This is how your existing emote macros go on the wheel.
  - Custom emote: type what your character does, like "bows deeply", and it's
    said as /e bows deeply. Starting with / runs that command instead.
  - Clear slot.
- The slots look like action bar buttons. Hover one for a tooltip with what it does.

Commands
- /ewheel slots <4-12> sets how many slots the wheel has (8 to start).
- /ewheel set <slot> <text> fills a slot by typing: an emote name (wave), a
  macro name, a /command, or a custom line.
- /ewheel cursor switches between opening at the mouse and in the middle of the screen.
- /ewheel hint hides or shows the click hints in the slot tooltips.
- /ewheel reset puts the default emotes back.
- /ewheel debug prints what each click does in chat (handy if a slot does nothing).

Good to know
- The slots can run your macros, which the game only allows outside combat,
  so the wheel can't be opened or changed during a fight. It closes itself
  when combat starts.
- A macro slot follows the macro's name. If you rename the macro, set the slot again.
