local addonName, ns = ...

-- Data lives in FieldJournalDB (per character: it is this character's journal).
--   notes      = { { id, title, body, created, modified, folder } } folder = a folder id or nil
--   folders    = { { id, name, collapsed } }
--   encounters = { { id, name, kind, info = {...}, zone, firstMet, lastMet, met, body, modified } }
--   places     = { { id, name, mapID, x, y, zone, body, created, modified } }
--   quests     = { { id, questID, title, zone, body, created, modified, completed } }
--   chronicle  = { { id, day, title, body, created, modified } } one page per day

ns.kinds = { "Player", "Creature", "Boss", "NPC", "Other" }

local defaults = {
	notes = {},
	folders = {},
	encounters = {},
	places = {},
	quests = {},
	chronicle = {},
	visited = {},         -- zone name -> true, for the chronicle's "first set foot in"
	chronicleOn = true,   -- write milestones into the chronicle automatically
	screenshotsOn = true, -- note each screenshot in the chronicle
	nextId = 1,
	-- point, pinned, pinPoint are set later
}

ns.onLoad = {} -- functions other files want run once the saved data is ready

local lastBoss -- { name, success, time } from the most recent ENCOUNTER_END

function ns.Stamp(t)
	return date("%d %b %Y, %H:%M", t)
end

function ns.NewId()
	local id = ns.db.nextId
	ns.db.nextId = id + 1
	return id
end

function ns.Remove(list, entry)
	for i, e in ipairs(list) do
		if e == entry then
			table.remove(list, i)
			return
		end
	end
end

-- Called whenever the addon itself changes an entry (not the player typing),
-- so the open window and the pinned page can catch up. UI.lua and Pin.lua
-- replace these.
function ns.EntryChanged() end
function ns.PinChanged() end

-- WoW: Forever hides some unit values from addons ("secret values"), mostly
-- in combat and instances. Anything secret is treated as unknown, and every
-- query is wrapped in pcall so a changed API can't break the journal.
local function clean(v)
	if v == nil then return nil end
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end
ns.clean = clean

local function query(fn, ...)
	if not fn then return end
	local ok, a, b, c = pcall(fn, ...)
	if not ok then return end
	return clean(a), clean(b), clean(c)
end
ns.query = query

function ns.CurrentZone()
	local zone = query(GetRealZoneText) or ""
	local sub = query(GetSubZoneText) or ""
	if sub ~= "" and sub ~= zone then
		return zone ~= "" and (sub .. ", " .. zone) or sub
	end
	return zone ~= "" and zone or "Unknown lands"
end

-- Notes ---------------------------------------------------------------------

function ns.AddNote(title, body, folder)
	local t = time()
	local note = { id = ns.NewId(), title = title or "Untitled page", body = body or "", created = t, modified = t, folder = folder }
	table.insert(ns.db.notes, note)
	return note
end

-- Folders -------------------------------------------------------------------

function ns.FolderById(id)
	if not id then return end
	for _, f in ipairs(ns.db.folders) do
		if f.id == id then return f end
	end
end

function ns.NewFolder(name)
	local folder = { id = ns.NewId(), name = name or "New folder" }
	table.insert(ns.db.folders, folder)
	return folder
end

-- Removes a folder. Its notes stay in the journal, outside any folder.
function ns.DeleteFolder(folder)
	for _, note in ipairs(ns.db.notes) do
		if note.folder == folder.id then note.folder = nil end
	end
	ns.Remove(ns.db.folders, folder)
end

-- Encounters ----------------------------------------------------------------

local function findEncounter(name, kind)
	local lname = name:lower()
	for _, e in ipairs(ns.db.encounters) do
		if e.kind == kind and e.name:lower() == lname then return e end
	end
end

local function visitHeader(t, zone, extra)
	return "-- " .. ns.Stamp(t) .. ", " .. zone .. (extra and (" (" .. extra .. ")") or "") .. " --\n"
end

-- Adds a meeting to the log. If this name/kind is already in the journal the
-- existing entry is reused and a dated line is added for the new meeting,
-- unless it was already logged here in the last five minutes.
function ns.LogEncounter(name, kind, info, extra)
	local t = time()
	local zone = ns.CurrentZone()
	local entry = findEncounter(name, kind)
	if entry then
		for k, v in pairs(info or {}) do entry.info[k] = v end
		if not (entry.zone == zone and t - (entry.lastMet or 0) < 300) then
			local body = entry.body or ""
			if body ~= "" and not body:match("\n$") then body = body .. "\n" end
			entry.body = body .. "\n" .. visitHeader(t, zone, extra)
			entry.met = (entry.met or 1) + 1
		end
		entry.zone = zone
		entry.lastMet = t
		entry.modified = t
		return entry, false
	end
	entry = {
		id = ns.NewId(), name = name, kind = kind, info = info or {},
		zone = zone, firstZone = zone, firstMet = t, lastMet = t, modified = t, met = 1,
		body = visitHeader(t, zone, extra),
	}
	table.insert(ns.db.encounters, entry)
	return entry, true
end

function ns.NewEncounter()
	local t = time()
	local zone = ns.CurrentZone()
	local entry = {
		id = ns.NewId(), name = "Unnamed encounter", kind = "Other", info = {},
		zone = zone, firstZone = zone, firstMet = t, lastMet = t, modified = t, met = 1, body = "",
	}
	table.insert(ns.db.encounters, entry)
	return entry
end

-- Reads a unit (usually "target") into the encounters log. Returns entry, message.
function ns.CaptureUnit(unit)
	local name, realm = query(UnitName, unit)
	local msg
	if not name or name == "" then
		name = "Unknown stranger"
		msg = "The game hides this name right now, so you can write it in yourself."
	elseif realm and realm ~= "" then
		name = name .. "-" .. realm
	end

	local info = {}
	local level = query(UnitLevel, unit)
	info.level = level
	local kind
	if query(UnitIsPlayer, unit) then
		kind = "Player"
		info.race = query(UnitRace, unit)
		info.class, info.classFile = query(UnitClass, unit)
		info.guild = query(GetGuildInfo, unit)
		info.faction = query(UnitFactionGroup, unit)
	else
		local classification = query(UnitClassification, unit)
		if classification == "worldboss" or level == -1 then
			kind = "Boss"
		elseif query(UnitCanAttack, "player", unit) then
			kind = "Creature"
		else
			kind = "NPC"
		end
		if classification == "elite" or classification == "rareelite" then info.elite = true end
		if classification == "rare" or classification == "rareelite" then info.rare = true end
		info.creatureType = query(UnitCreatureType, unit)
	end

	local entry, isNew = ns.LogEncounter(name, kind, info)
	return entry, msg or ((isNew and "New entry: " or "Turned to the page on ") .. name .. ".")
end

-- The current target, or with no target a boss fight that ended in the last
-- five minutes. Returns entry, message.
function ns.CaptureTarget()
	if query(UnitExists, "target") then
		return ns.CaptureUnit("target")
	end
	if lastBoss and time() - lastBoss.time < 300 then
		local entry = ns.LogEncounter(lastBoss.name, "Boss", {}, lastBoss.success and "victory" or "defeat")
		return entry, "Logged the fight with " .. lastBoss.name .. "."
	end
	return nil, "You have no target to write about."
end

-- A player known only by name, e.g. from a chat link. Opens their existing
-- page if there is one, without counting it as a meeting.
function ns.PlayerByName(name, realm)
	name = clean(name)
	if not name or name == "" then return nil, "Can't read that name right now." end
	realm = clean(realm)
	local home = query(GetNormalizedRealmName)
	if realm and realm ~= "" and realm ~= home and not name:find("-", 1, true) then
		name = name .. "-" .. realm
	end
	local lname = name:lower()
	local short = lname:match("^([^-]+)")
	for _, e in ipairs(ns.db.encounters) do
		if e.kind == "Player" then
			local ename = e.name:lower()
			if ename == lname or ename:match("^([^-]+)") == short and not ename:find("-", 1, true) then
				return e
			end
		end
	end
	return (ns.LogEncounter(name, "Player", {}, "first heard of"))
end

-- Meta line shown under an encounter's name.
function ns.DescribeEncounter(e)
	local i = e.info or {}
	local parts = {}
	if i.level then table.insert(parts, "Level " .. (i.level == -1 and "??" or i.level)) end
	if i.rare then table.insert(parts, "Rare") end
	if i.elite then table.insert(parts, "Elite") end
	if i.race then table.insert(parts, i.race) end
	if i.class then table.insert(parts, i.class) end
	if i.creatureType then table.insert(parts, i.creatureType) end
	local line = table.concat(parts, " ")
	if i.guild then line = line .. " <" .. i.guild .. ">" end
	if i.faction then line = line .. " (" .. i.faction .. ")" end
	local times = (e.met or 1) == 1 and "once" or ((e.met or 1) .. " times")
	local second = "First met " .. ns.Stamp(e.firstMet) .. " in " .. (e.firstZone or e.zone or "?") .. ", met " .. times
	if line == "" then return second end
	return line .. "\n" .. second
end

-- Events --------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("ENCOUNTER_END")
events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... ~= addonName then return end
		FieldJournalDB = FieldJournalDB or {}
		ns.db = FieldJournalDB
		for k, v in pairs(defaults) do
			if ns.db[k] == nil then ns.db[k] = type(v) == "table" and {} or v end
		end
		for _, fn in ipairs(ns.onLoad) do fn() end
	elseif event == "ENCOUNTER_END" then
		local _, encounterName, _, _, success = ...
		encounterName = clean(encounterName)
		if encounterName and encounterName ~= "" then
			lastBoss = { name = encounterName, success = clean(success) == 1, time = time() }
		end
	end
end)

-- Slash commands and bindings ----------------------------------------------

local function say(msg) print("|cffc8a46eField Journal:|r " .. msg) end
ns.Say = say

function FieldJournal_Toggle()
	ns.Toggle()
end

function FieldJournal_AddTarget()
	local entry, msg = ns.CaptureTarget()
	if msg then say(msg) end
	if entry then ns.Open("encounters", entry, "end") end
end

function FieldJournal_MarkPlace()
	local entry, msg = ns.MarkPlace()
	if msg then say(msg) end
	if entry then ns.Open("places", entry, "title") end
end

function FieldJournal_MuseQuest()
	local entry, msg = ns.MuseQuest(ns.CurrentQuestID())
	if msg then say(msg) end
	if entry then ns.Open("quests", entry, "end") end
end

function FieldJournal_OnAddonCompartmentClick()
	ns.Toggle()
end

BINDING_HEADER_FIELDJOURNAL = "Field Journal"
BINDING_NAME_FIELDJOURNAL_TOGGLE = "Open/close journal"
BINDING_NAME_FIELDJOURNAL_ADDTARGET = "Write about current target"
BINDING_NAME_FIELDJOURNAL_MARKPLACE = "Mark this spot"
BINDING_NAME_FIELDJOURNAL_MUSEQUEST = "Write about current quest"

local sections = { notes = true, encounters = true, places = true, quests = true, chronicle = true }

SLASH_FIELDJOURNAL1 = "/journal"
SLASH_FIELDJOURNAL2 = "/fj"
SlashCmdList.FIELDJOURNAL = function(msg)
	msg = strtrim(msg or "")
	local cmd, rest = strsplit(" ", msg, 2)
	cmd = (cmd or ""):lower()
	if cmd == "" then
		ns.Toggle()
	elseif cmd == "add" or cmd == "target" then
		FieldJournal_AddTarget()
	elseif cmd == "place" or cmd == "mark" then
		FieldJournal_MarkPlace()
	elseif cmd == "quest" then
		FieldJournal_MuseQuest()
	elseif cmd == "note" and rest and rest ~= "" then
		ns.AddNote(rest:sub(1, 40), rest)
		say("Written down.")
		ns.Refresh()
	elseif sections[cmd] then
		ns.Open(cmd)
	elseif cmd == "auto" then
		ns.db.chronicleOn = not ns.db.chronicleOn
		say("Automatic chronicle " .. (ns.db.chronicleOn and "|cff00ff00on|r" or "|cffff4444off|r"))
	elseif cmd == "search" or cmd == "find" then
		ns.Search(rest)
	elseif cmd == "screenshots" or cmd == "shots" then
		ns.db.screenshotsOn = not ns.db.screenshotsOn
		say("Screenshot memories " .. (ns.db.screenshotsOn and "|cff00ff00on|r" or "|cffff4444off|r"))
	elseif cmd == "unpin" then
		ns.db.pinned = nil
		ns.PinChanged()
	elseif cmd == "reset" then
		ns.db.point = nil
		ns.db.pinPoint = nil
		ns.ResetPosition()
		ns.PinChanged()
		say("Window positions reset.")
	else
		say("commands:")
		print("  /fj - open or close the journal (also /journal)")
		print("  /fj add - write about your target (or a boss you just fought)")
		print("  /fj place - mark the spot you are standing on")
		print("  /fj quest - write about the quest you have open or are following")
		print("  /fj note <text> - jot down a quick new page")
		print("  /fj search <words> - search every page in the journal")
		print("  /fj notes, encounters, places, quests, chronicle - open a section")
		print("  /fj auto - turn the automatic chronicle on/off")
		print("  /fj screenshots - turn screenshot notes in the chronicle on/off")
		print("  /fj unpin - take the pinned page off your screen")
		print("  /fj reset - move the windows back to the center")
		print("  Key bindings: Options > Keybindings > AddOns")
	end
end
