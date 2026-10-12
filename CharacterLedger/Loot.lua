local addonName, ns = ...

-- Loot log: everything your characters receive, with where it came from,
-- the zone and the time, so you can look up "where did I get that?" later.
-- Items are read from your own loot lines in chat ("You receive loot: ...",
-- "You receive item: ...", "You create: ..."). The source comes from the loot
-- window (the corpse you're looting, the node you gathered, fishing).
--   db.loot = { { id, link, name, qty, src, how, zone, sub, t, char }, ... } newest last

local MAX_ENTRIES = 3000
local SOURCE_GRACE = 3 -- seconds after the loot window closes that its source still counts

local events = CreateFrame("Frame")
local pending = {}         -- itemID -> { src, how } from the open loot window
local lastSource           -- { src, how } for the loot window as a whole
local closedAt = 0
local lootOpen = false
local lastCast             -- { target, spell, t } from UNIT_SPELLCAST_SENT

local function clean(v)
	if v == nil then return nil end
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

local function query(fn, ...)
	if not fn then return end
	local ok, a, b, c, d, e = pcall(fn, ...)
	if not ok then return end
	return clean(a), clean(b), clean(c), clean(d), clean(e)
end

-- Turns a game message like "You receive loot: %sx%d." into a Lua pattern.
local function pattern(fmt)
	if not fmt then return nil end
	fmt = fmt:gsub("%%%d?%$?s", "\1"):gsub("%%%d?%$?d", "\2")
	fmt = fmt:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
	fmt = fmt:gsub("\1", "(.+)"):gsub("\2", "(%%d+)")
	return "^" .. fmt .. "$"
end

-- Multiple-count forms first, so "x2" isn't swallowed by the single form.
local MESSAGES = {}
for _, entry in ipairs({
	{ "LOOT_ITEM_SELF_MULTIPLE", nil, true }, { "LOOT_ITEM_SELF" },
	{ "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "Received", true }, { "LOOT_ITEM_PUSHED_SELF", "Received" },
	{ "LOOT_ITEM_CREATED_SELF_MULTIPLE", "Crafted", true }, { "LOOT_ITEM_CREATED_SELF", "Crafted" },
}) do
	local p = pattern(_G[entry[1]])
	if p then table.insert(MESSAGES, { pattern = p, how = entry[2], multiple = entry[3] }) end
end

-- Sources ---------------------------------------------------------------------

local function windowSource()
	if query(IsFishingLoot) then
		return { src = query(GetSubZoneText) ~= "" and query(GetSubZoneText) or query(GetZoneText), how = "Fishing" }
	end
	local recent = lastCast and GetTime() - lastCast.t < 6 and lastCast
	-- A corpse you're looting. Skinning it counts as the way you got it.
	for _, unit in ipairs({ "target", "mouseover" }) do
		if query(UnitExists, unit) and query(UnitIsDead, unit) then
			local name = query(UnitName, unit)
			local how = recent and recent.onCorpse and recent.target == name and recent.spell or nil
			return { src = name, how = how }
		end
	end
	-- Gathering and opening things: the spell you cast names the node or chest.
	-- Casts at living enemies don't count (that was a fight, not a gather).
	if recent and not recent.atEnemy then
		return { src = recent.target, how = recent.spell }
	end
	return nil
end

local function readWindow()
	local whole = windowSource()
	lastSource = whole
	wipe(pending)
	local n = query(GetNumLootItems) or 0
	for slot = 1, n do
		local link = query(GetLootSlotLink, slot)
		local id = link and query(C_Item.GetItemInfoInstant, link)
		if id then
			local src = whole
			if not src and GetLootSourceInfo then
				local guid = query(GetLootSourceInfo, slot)
				local kind = guid and strsplit("-", guid)
				if kind == "GameObject" then src = { src = "a container" } end
			end
			pending[id] = src
		end
	end
end

-- Recording -------------------------------------------------------------------

local function record(link, qty, how)
	local db, me = ns.DB(), ns.Me()
	if not db or not me then return end
	local id = query(C_Item.GetItemInfoInstant, link)
	if not id then return end
	local name = link:match("%[(.-)%]") or ("item " .. id)
	local src
	local fresh = lootOpen or (GetTime() - closedAt < SOURCE_GRACE)
	if not how and fresh then src = pending[id] or lastSource end
	db.loot = db.loot or {}
	table.insert(db.loot, {
		id = id, link = link, name = name, qty = qty or 1,
		src = src and src.src, how = how or (src and src.how),
		zone = query(GetRealZoneText), sub = query(GetSubZoneText),
		t = time(), char = me.name .. "-" .. me.realm,
	})
	while #db.loot > MAX_ENTRIES do table.remove(db.loot, 1) end
	if ns.Refresh then ns.Refresh() end
end

local function onLootMessage(msg)
	msg = clean(msg)
	if not msg then return end
	for _, m in ipairs(MESSAGES) do
		local link, qty = msg:match(m.pattern)
		if link and link:find("|Hitem:", 1, true) then
			record(link, tonumber(qty) or 1, m.how)
			return
		end
	end
end

-- Newest first, for the Loot tab.
function ns.LootEntries()
	local db = ns.DB()
	local list = {}
	for i = #(db.loot or {}), 1, -1 do table.insert(list, db.loot[i]) end
	return list
end

events:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_LOGIN" then
		for _, e in ipairs({ "LOOT_OPENED", "LOOT_READY", "LOOT_CLOSED", "CHAT_MSG_LOOT", "UNIT_SPELLCAST_SENT" }) do
			pcall(events.RegisterEvent, events, e)
		end
	elseif event == "LOOT_OPENED" or event == "LOOT_READY" then
		lootOpen = true
		readWindow()
	elseif event == "LOOT_CLOSED" then
		lootOpen = false
		closedAt = GetTime()
	elseif event == "CHAT_MSG_LOOT" then
		onLootMessage(...)
	elseif event == "UNIT_SPELLCAST_SENT" then
		local unit, target, _, spellID = ...
		if clean(unit) ~= "player" then return end
		target, spellID = clean(target), clean(spellID)
		if target and target ~= "" and spellID then
			local spell = C_Spell and C_Spell.GetSpellName and query(C_Spell.GetSpellName, spellID)
			local onTarget = query(UnitName, "target") == target
			lastCast = {
				target = target, spell = spell, t = GetTime(),
				onCorpse = onTarget and query(UnitIsDead, "target") or false,
				atEnemy = onTarget and not query(UnitIsDead, "target") or false,
			}
		end
	end
end)
events:RegisterEvent("PLAYER_LOGIN")
