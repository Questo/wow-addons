local addonName, ns = ...

-- Recipes and lockouts.
--
-- Recipes: the game only shares a profession's recipes while its window is
-- open, so each time you open one of your own professions we note every
-- learned recipe, what it makes and what it uses. Item tooltips then say which
-- of your characters can craft the item ("Crafted by") and whose recipes use
-- it ("Used by").
--
-- Lockouts: raids and dungeons each character is saved to, with reset times.

local events = CreateFrame("Frame")
local index -- built on demand: { crafted = itemID -> {..}, used = itemID -> {..} }

-- Recipes ---------------------------------------------------------------------

local function professionName()
	local info = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
	if info and info.professionName and info.professionName ~= "" then return info.professionName end
	info = C_TradeSkillUI.GetChildProfessionInfo and C_TradeSkillUI.GetChildProfessionInfo()
	return info and info.parentProfessionName or (info and info.professionName)
end

local function viewingSomeoneElse()
	return (C_TradeSkillUI.IsTradeSkillLinked and C_TradeSkillUI.IsTradeSkillLinked())
		or (C_TradeSkillUI.IsTradeSkillGuild and C_TradeSkillUI.IsTradeSkillGuild())
		or (C_TradeSkillUI.IsNPCCrafting and C_TradeSkillUI.IsNPCCrafting())
end

local function scanRecipes()
	local me = ns.Me()
	if not me or viewingSomeoneElse() then return end
	if C_TradeSkillUI.IsTradeSkillReady and not C_TradeSkillUI.IsTradeSkillReady() then return end
	local prof = professionName()
	if not prof then return end

	local recipes, count = {}, 0
	for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
		local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
		if info and info.learned then
			local entry = { name = info.name, icon = info.icon }
			local schematic = C_TradeSkillUI.GetRecipeSchematic and C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
			if schematic then
				entry.item = schematic.outputItemID
				local reagents = {}
				for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
					for _, r in ipairs(slot.reagents or {}) do
						if r.itemID then table.insert(reagents, r.itemID) end
					end
				end
				if #reagents > 0 then entry.reagents = reagents end
			end
			recipes[recipeID] = entry
			count = count + 1
		end
	end
	if count == 0 then return end -- list not loaded yet

	me.recipes = me.recipes or {}
	me.recipes[prof] = recipes
	index = nil
	if ns.Refresh then ns.Refresh() end
end

local scanQueued = false
local function queueScan()
	if scanQueued then return end
	scanQueued = true
	C_Timer.After(0.5, function()
		scanQueued = false
		scanRecipes()
	end)
end

local function buildIndex()
	index = { crafted = {}, used = {} }
	for _, char in ipairs(ns.Characters()) do
		for prof, recipes in pairs(char.recipes or {}) do
			for _, r in pairs(recipes) do
				if r.item then
					local list = index.crafted[r.item] or {}
					index.crafted[r.item] = list
					list[char.name .. " (" .. prof .. ")"] = ns.ColoredName(char) .. " (" .. prof .. ")"
				end
				for _, reagent in ipairs(r.reagents or {}) do
					local list = index.used[reagent] or {}
					index.used[reagent] = list
					list[char.name .. " (" .. prof .. ")"] = ns.ColoredName(char) .. " (" .. prof .. ")"
				end
			end
		end
	end
end

local function joined(set)
	local keys = {}
	for k in pairs(set) do table.insert(keys, k) end
	table.sort(keys)
	local out = {}
	for _, k in ipairs(keys) do table.insert(out, set[k]) end
	return table.concat(out, ", ")
end

local function addToTooltip(tooltip, data)
	local db = ns.DB()
	if not db or not db.tooltip then return end
	if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
	local itemID = data and data.id
	if not itemID or (issecretvalue and issecretvalue(itemID)) then return end
	if not index then buildIndex() end
	local crafted, used = index.crafted[itemID], index.used[itemID]
	if not crafted and not used then return end
	tooltip:AddLine(" ")
	if crafted then tooltip:AddLine("Crafted by: |cffffffff" .. joined(crafted) .. "|r", 1, 0.82, 0, true) end
	if used then tooltip:AddLine("Used by: |cffffffff" .. joined(used) .. "|r", 1, 0.82, 0, true) end
	tooltip:Show()
end

function ns.ResetRecipeIndex() index = nil end

-- One entry per recipe, with everyone who knows it, for the Recipes tab.
function ns.AllRecipes()
	local byID, list = {}, {}
	for _, char in ipairs(ns.Characters()) do
		for prof, recipes in pairs(char.recipes or {}) do
			for id, r in pairs(recipes) do
				local e = byID[id]
				if not e then
					e = { id = id, name = r.name or ("Recipe " .. id), icon = r.icon, item = r.item, prof = prof, who = {} }
					byID[id] = e
					table.insert(list, e)
				end
				table.insert(e.who, char.name)
			end
		end
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	return list
end

-- Lockouts --------------------------------------------------------------------

local function scanLockouts()
	local me = ns.Me()
	if not me then return end
	local list = {}
	for i = 1, GetNumSavedInstances() do
		local name, _, reset, _, locked, extended, _, isRaid, _, difficultyName, numEncounters, progress = GetSavedInstanceInfo(i)
		if name and (locked or extended) and reset and reset > 0 then
			table.insert(list, {
				name = name,
				difficulty = difficultyName,
				resetAt = time() + reset,
				done = progress,
				total = numEncounters,
				raid = isRaid and true or false,
			})
		end
	end
	me.lockouts = list
	if ns.Refresh then ns.Refresh() end
end

-- Rows for the Lockouts tab, skipping ones that have already reset.
function ns.AllLockouts()
	local rows, now = {}, time()
	for _, char in ipairs(ns.Characters()) do
		for _, l in ipairs(char.lockouts or {}) do
			if l.resetAt > now then
				table.insert(rows, { char = char, lockout = l })
			end
		end
	end
	return rows
end

-- Events ----------------------------------------------------------------------

local function safeRegister(event)
	pcall(events.RegisterEvent, events, event)
end

events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		-- Let Data.lua set up the character first.
		C_Timer.After(0, function()
			TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, addToTooltip)
			safeRegister("TRADE_SKILL_SHOW")
			safeRegister("TRADE_SKILL_LIST_UPDATE")
			safeRegister("TRADE_SKILL_DATA_SOURCE_CHANGED")
			safeRegister("NEW_RECIPE_LEARNED")
			safeRegister("UPDATE_INSTANCE_INFO")
			safeRegister("BOSS_KILL")
			RequestRaidInfo()
		end)
	elseif event == "UPDATE_INSTANCE_INFO" then
		scanLockouts()
	elseif event == "BOSS_KILL" then
		C_Timer.After(2, RequestRaidInfo)
	else
		queueScan()
	end
end)
events:RegisterEvent("PLAYER_LOGIN")
