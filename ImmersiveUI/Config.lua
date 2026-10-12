local _, ns = ...

-- Edit this file to choose what fades. Each group is a list of frame names;
-- the first name that exists in the game is used, so later names are fallbacks
-- for older or renamed Blizzard frames. Set enabled = false to leave a group alone.
-- hoverOnly = true means the group ignores combat/target and only shows on mouseover.
-- activityOnly = true means the group ignores combat/target and shows on new
-- messages, on mouseover and while typing (used for chat).
-- recovery = true means the group also stays visible out of combat while your
-- health (or mana) is below full, so you can see when to eat or drink.
-- partyHurt = true means the group also shows while someone in your party is hurt.
-- Minimap and the quest/objective tracker are never touched.
ns.groups = {
	{ key = "bar1",   label = "Action bar 1",    enabled = true, hoverOnly = true,  frames = { { "MainActionBar", "MainMenuBar" } } },
	{ key = "bar2",   label = "Action bar 2",    enabled = true, hoverOnly = true,  frames = { { "MultiBarBottomLeft" } } },
	{ key = "bar3",   label = "Action bar 3",    enabled = true, hoverOnly = true,  frames = { { "MultiBarBottomRight" } } },
	{ key = "bar4",   label = "Action bar 4",    enabled = false, hoverOnly = true, frames = { { "MultiBarRight" } } },
	{ key = "extra",  label = "Stance/pet bars", enabled = true, hoverOnly = true,  frames = { { "StanceBar" }, { "PetActionBar" } } },
	{ key = "player", label = "Player frame",    enabled = true,  recovery = true, frames = { { "PlayerFrame" } } },
	{ key = "party",  label = "Party frames",    enabled = true,  partyHurt = true, frames = { { "PartyFrame" }, { "CompactPartyFrame" } } },
	{ key = "menu",   label = "Main menu",       enabled = true,  frames = { { "MicroMenuContainer", "MicroButtonAndBagsBar" } } },
	{ key = "bags",   label = "Bag bar",         enabled = true,  frames = { { "BagsBar" } } },
	{ key = "xp",     label = "XP/rep bars",     enabled = true,  frames = { { "StatusTrackingBarManager" } } },
	{ key = "chat",   label = "Chat",            enabled = true,  activityOnly = true, frames = {
		{ "ChatFrame1" }, { "ChatFrame2" }, { "ChatFrame3" }, { "ChatFrame4" }, { "ChatFrame5" },
		{ "ChatFrame6" }, { "ChatFrame7" }, { "ChatFrame8" }, { "ChatFrame9" }, { "ChatFrame10" },
		{ "GeneralDockManager" }, { "ChatFrameMenuButton" }, { "ChatFrameChannelButton" },
		{ "ChatFrameToggleVoiceDeafenButton" }, { "ChatFrameToggleVoiceMuteButton" }, { "QuickJoinToastButton" },
	} },
	-- Built-in damage meter, plus the Details! addon's first window if installed.
	{ key = "meter",  label = "Damage meter",    enabled = true,  frames = { { "DamageMeter" }, { "DetailsBaseFrame1" }, { "DetailsRowFrame1" } } },
}

ns.defaults = {
	hiddenAlpha = 0,      -- alpha when nothing is happening (0 = invisible)
	fadeIn = 0.2,         -- seconds to fade in
	fadeOut = 1.0,        -- seconds to fade out
	fadeOutDelay = 2.0,   -- seconds to wait after combat/target ends before fading out
	chatVisible = 10,     -- seconds chat stays visible after a new message
	mouseover = true,     -- hovering a hidden element reveals it
	hostileOnly = false,  -- only count targets you can attack
	recovery = true,      -- player frame stays up while health/mana is below full
	partyHurt = true,     -- party frames show while a party member is hurt
	groups = {},          -- per-group enabled overrides, set via /iui toggle
	hoverOnly = {},       -- per-group hoverOnly overrides, set via /iui hover
}
