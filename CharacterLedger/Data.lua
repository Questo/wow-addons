local addonName, ns = ...

-- Remembers every character you log in on: level, gold, rested XP, professions,
-- where you left them, and what they carry (bags, bank, equipped), plus the
-- warband bank. The bank can only be read while it is open, so each
-- character's bank is remembered from their last visit.

local db, me
local bankOpen = false
local events = CreateFrame("Frame")

function ns.Say(msg)
	print("|cff66ccffCharacter Ledger:|r " .. msg)
end
local say = ns.Say

function ns.DB() return db end
function ns.Me() return me end

-- Characters, current one first, then by name.
function ns.Characters()
	local list = {}
	for _, char in pairs(db.chars) do table.insert(list, char) end
	table.sort(list, function(a, b)
		if (a == me) ~= (b == me) then return a == me end
		if a.realm ~= b.realm then return a.realm < b.realm end
		return a.name < b.name
	end)
	return list
end

function ns.ColoredName(char)
	local c = char.class and C_ClassColor and C_ClassColor.GetClassColor(char.class)
	local name = c and c:WrapTextInColorCode(char.name) or char.name
	if me and char.realm ~= me.realm then
		name = name .. " |cff999999- " .. char.realm .. "|r"
	end
	return name
end

-- Container ids ---------------------------------------------------------------

local BAG_IDS = { 0, 1, 2, 3, 4, 5 } -- backpack, four bags, reagent bag
local BANK_IDS, WARBAND_IDS = {}, {}

local function collectIds()
	local bi = Enum and Enum.BagIndex or {}
	for i = 1, 12 do
		if bi["CharacterBankTab_" .. i] then table.insert(BANK_IDS, bi["CharacterBankTab_" .. i]) end
		if bi["AccountBankTab_" .. i] then table.insert(WARBAND_IDS, bi["AccountBankTab_" .. i]) end
	end
	if #BANK_IDS == 0 then
		-- Older bank layout: main bank, bank bags and reagent bank.
		table.insert(BANK_IDS, bi.Bank or -1)
		for i = 1, 7 do
			if bi["BankBag_" .. i] then table.insert(BANK_IDS, bi["BankBag_" .. i]) end
		end
		if bi.Reagentbank then table.insert(BANK_IDS, bi.Reagentbank) end
	end
end

-- Item scanning ---------------------------------------------------------------

-- Returns a table itemID -> count, or nil when none of the containers had slots
-- (which means the game had not loaded them, e.g. the bank was closed).
local function scan(ids)
	local counts, anySlots = {}, false
	for _, bag in ipairs(ids) do
		local n = C_Container.GetContainerNumSlots(bag) or 0
		if n > 0 then anySlots = true end
		for slot = 1, n do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID then
				counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
			end
		end
	end
	return anySlots and counts or nil
end

local function scanEquipped()
	local counts = {}
	for slot = 1, 19 do
		local id = GetInventoryItemID("player", slot)
		if id then counts[id] = (counts[id] or 0) + 1 end
	end
	me.equipped = counts
	local _, equippedIlvl = GetAverageItemLevel()
	me.ilvl = equippedIlvl and math.floor(equippedIlvl + 0.5) or me.ilvl
end

local function scanBags()
	me.bags = scan(BAG_IDS) or me.bags or {}
end

local function scanBank()
	if not bankOpen then return end
	local bank = scan(BANK_IDS)
	if bank then
		me.bank = bank
		me.bankSeen = true
	end
	if #WARBAND_IDS > 0 then
		local warband = scan(WARBAND_IDS)
		if warband then db.warband = warband end
	end
end

-- Character details -----------------------------------------------------------

local function updateMoney()
	me.money = GetMoney()
end

local function updateXP()
	me.level = UnitLevel("player")
	me.xp, me.xpMax = UnitXP("player"), UnitXPMax("player")
	me.rested = GetXPExhaustion() or 0
	me.resting = IsResting() and true or false
	me.restedAt = time()
end

local function updateZone()
	me.zone = GetZoneText()
	me.subzone = GetSubZoneText()
end

local function updateProfessions()
	local list = {}
	local indices = { GetProfessions() }
	for i = 1, 5 do
		local index = indices[i]
		if index then
			local name, _, rank, maxRank = GetProfessionInfo(index)
			if name then table.insert(list, { name = name, rank = rank, max = maxRank }) end
		end
	end
	me.professions = list
end

local function updateAll()
	me.class = select(2, UnitClass("player"))
	updateMoney()
	updateXP()
	updateZone()
	updateProfessions()
	scanBags()
	scanEquipped()
	me.lastSeen = time()
end

-- Rested XP as a percent of the level bar, including an estimate of what was
-- gained since the character logged out: 5% of a level per 8 hours in an inn
-- or city, a quarter of that elsewhere, up to 150%.
function ns.RestedPercent(char)
	if not char.xpMax or char.xpMax == 0 then return nil end
	local rested = char.rested or 0
	if char ~= me and char.restedAt then
		local hours = (time() - char.restedAt) / 3600
		local perHour = char.xpMax * 0.05 / 8
		if not char.resting then perHour = perHour / 4 end
		rested = math.min(rested + hours * perHour, char.xpMax * 1.5)
	end
	return math.floor(rested / char.xpMax * 100 + 0.5)
end

function ns.MaxLevel()
	return GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or 60
end

-- Item counts -----------------------------------------------------------------

local SOURCES = {
	{ key = "bags", label = "Bags" },
	{ key = "bank", label = "Bank" },
	{ key = "equipped", label = "Equipped" },
}

-- Returns rows { name, count, detail } for one item, and the grand total.
function ns.Holders(itemID)
	local rows, total = {}, 0
	for _, char in ipairs(ns.Characters()) do
		local sum, parts = 0, {}
		for _, src in ipairs(SOURCES) do
			local n = char[src.key] and char[src.key][itemID]
			if n and n > 0 then
				sum = sum + n
				table.insert(parts, src.label .. " " .. n)
			end
		end
		if sum > 0 then
			total = total + sum
			table.insert(rows, { name = ns.ColoredName(char), short = char.name, count = sum, detail = table.concat(parts, ", ") })
		end
	end
	local wb = db.warband and db.warband[itemID]
	if wb and wb > 0 then
		total = total + wb
		table.insert(rows, { name = "|cff66ccffWarband bank|r", short = "Warband bank", count = wb, detail = "" })
	end
	return rows, total
end

-- Every item id anyone has, for the Items tab.
function ns.AllItemIDs()
	local seen, list = {}, {}
	local function add(t)
		for id in pairs(t or {}) do
			if not seen[id] then
				seen[id] = true
				table.insert(list, id)
			end
		end
	end
	for _, char in pairs(db.chars) do
		add(char.bags); add(char.bank); add(char.equipped)
	end
	add(db.warband)
	return list
end

local function addToTooltip(tooltip, data)
	if not db or not db.tooltip then return end
	if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
	local itemID = data and data.id
	if not itemID or (issecretvalue and issecretvalue(itemID)) then return end
	local rows, total = ns.Holders(itemID)
	if #rows == 0 then return end
	tooltip:AddLine(" ")
	for _, r in ipairs(rows) do
		local right = r.detail ~= "" and (r.count .. "  |cff999999(" .. r.detail .. ")|r") or tostring(r.count)
		tooltip:AddDoubleLine(r.name, right, 1, 1, 1, 1, 1, 1)
	end
	if #rows > 1 then
		tooltip:AddDoubleLine("Total", tostring(total), 1, 0.82, 0, 1, 0.82, 0)
	end
	tooltip:Show()
end

-- Slash commands --------------------------------------------------------------

function ns.Forget(name)
	for key, char in pairs(db.chars) do
		if char.name:lower() == name:lower() or key:lower() == name:lower() then
			if char == me then
				say("You can't forget the character you're playing.")
				return
			end
			db.chars[key] = nil
			if ns.ResetRecipeIndex then ns.ResetRecipeIndex() end
			say("Forgot " .. key .. ".")
			if ns.Refresh then ns.Refresh() end
			return
		end
	end
	say("No character called " .. name .. ".")
end

function ns.SetTooltip(on)
	db.tooltip = on and true or false
	say("Ledger lines in item tooltips " .. (db.tooltip and "on." or "off."))
	if ns.OnTooltipSetting then ns.OnTooltipSetting() end
end

SLASH_CHARACTERLEDGER1 = "/ledger"
SLASH_CHARACTERLEDGER2 = "/characterledger"
SlashCmdList.CHARACTERLEDGER = function(msg)
	msg = strtrim(msg or "")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()
	if cmd == "" then
		ns.Toggle("chars")
	elseif cmd == "items" or cmd == "recipes" or cmd == "lockouts" or cmd == "mail" then
		ns.Open(cmd, rest)
	elseif cmd == "forget" and rest ~= "" then
		ns.Forget(rest)
	elseif cmd == "tooltip" then
		ns.SetTooltip(not db.tooltip)
	else
		say("/ledger opens the ledger. /ledger items <name> or /ledger recipes <name> searches, /ledger lockouts shows lockouts, /ledger mail shows mail.")
		print("   /ledger forget <name> removes a character, /ledger tooltip turns tooltip counts off and on.")
	end
end

-- /whohas <item> opens the Items tab searching for that item.
SLASH_CHARACTERLEDGERWHO1 = "/whohas"
SlashCmdList.CHARACTERLEDGERWHO = function(msg)
	msg = strtrim(msg or "")
	local name = msg:match("%[(.-)%]") or msg
	ns.Open("items", name)
end

function CharacterLedger_OnAddonCompartmentClick()
	ns.Toggle("chars")
end

-- Events ----------------------------------------------------------------------

local function safeRegister(event)
	pcall(events.RegisterEvent, events, event)
end

local function onBankOpened()
	bankOpen = true
	-- Bank contents arrive a moment after the window opens.
	scanBank()
	C_Timer.After(0.5, scanBank)
end

local function changed()
	if ns.Refresh then ns.Refresh() end
end

local handlers = {
	BAG_UPDATE_DELAYED = function() scanBags(); scanBank() end,
	PLAYER_EQUIPMENT_CHANGED = scanEquipped,
	PLAYER_MONEY = updateMoney,
	PLAYER_XP_UPDATE = updateXP,
	UPDATE_EXHAUSTION = updateXP,
	PLAYER_LEVEL_UP = function() C_Timer.After(0.5, updateXP) end,
	PLAYER_UPDATE_RESTING = updateXP,
	ZONE_CHANGED = updateZone,
	ZONE_CHANGED_INDOORS = updateZone,
	ZONE_CHANGED_NEW_AREA = updateZone,
	SKILL_LINES_CHANGED = updateProfessions,
	PLAYERBANKSLOTS_CHANGED = scanBank,
	PLAYERREAGENTBANKSLOTS_CHANGED = scanBank,
	BANKFRAME_OPENED = onBankOpened,
	BANKFRAME_CLOSED = function() scanBank(); bankOpen = false end,
	PLAYER_LOGOUT = function() updateXP(); me.lastSeen = time() end,
}

events:SetScript("OnEvent", function(_, event, arg1)
	if event == "PLAYER_LOGIN" then
		CharacterLedgerDB = CharacterLedgerDB or {}
		db = CharacterLedgerDB
		db.chars = db.chars or {}
		db.warband = db.warband or {}
		-- Tooltip lines are off unless you turn them on (0.2.3 changed the default,
		-- so earlier installs are switched off once too).
		if not db.tooltipDefaultOff then
			db.tooltip = false
			db.tooltipDefaultOff = true
		end

		local name, realm = UnitFullName("player")
		realm = realm or GetRealmName()
		local key = name .. "-" .. realm
		db.chars[key] = db.chars[key] or {}
		me = db.chars[key]
		me.name, me.realm = name, realm
		me.bags, me.bank, me.equipped = me.bags or {}, me.bank or {}, me.equipped or {}

		collectIds()
		updateAll()
		C_Timer.After(3, updateProfessions) -- profession data can arrive late
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, addToTooltip)

		for e in pairs(handlers) do safeRegister(e) end
		safeRegister("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
		safeRegister("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
		say("loaded. Type /ledger to open it.")
	elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
		local pit = Enum.PlayerInteractionType
		if pit and (arg1 == pit.Banker or arg1 == pit.AccountBanker or arg1 == pit.CharacterBanker) then
			if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
				onBankOpened()
			else
				scanBank()
				bankOpen = false
			end
		end
	elseif handlers[event] then
		handlers[event]()
		me.lastSeen = time()
		changed()
	end
end)
events:RegisterEvent("PLAYER_LOGIN")
