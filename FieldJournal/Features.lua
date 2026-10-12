local _, ns = ...
local query, clean = ns.query, ns.clean

-- Places --------------------------------------------------------------------

function ns.MarkPlace()
	local mapID = C_Map and query(C_Map.GetBestMapForUnit, "player")
	local x, y
	if mapID then
		local pos = query(C_Map.GetPlayerMapPosition, mapID, "player")
		if pos then x, y = query(pos.GetXY, pos) end
	end
	local t = time()
	local sub = query(GetSubZoneText) or ""
	local entry = {
		id = ns.NewId(),
		name = sub ~= "" and sub or (query(GetRealZoneText) or "A quiet spot"),
		mapID = mapID, x = x, y = y,
		zone = ns.CurrentZone(),
		body = "", created = t, modified = t,
	}
	table.insert(ns.db.places, entry)
	local msg
	if not x then msg = "Marked, but the game gives no map position here, so this spot can't get a waypoint." end
	return entry, msg
end

function ns.DescribePlace(e)
	local where = e.zone or "?"
	if e.x and e.y then
		where = where .. string.format(" (%.1f, %.1f)", e.x * 100, e.y * 100)
	end
	return where .. "\nMarked " .. ns.Stamp(e.created)
end

function ns.SetWaypoint(e)
	if not (e.mapID and e.x and e.y and UiMapPoint and C_Map.SetUserWaypoint) then
		ns.Say("This place has no map position to point to.")
		return
	end
	if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(e.mapID) then
		ns.Say("The map doesn't allow a waypoint there.")
		return
	end
	local ok = pcall(function()
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(e.mapID, e.x, e.y))
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
			C_SuperTrack.SetSuperTrackedUserWaypoint(true)
		end
	end)
	ns.Say(ok and ("Waypoint set to " .. e.name .. ".") or "Couldn't set a waypoint.")
end

-- Quests --------------------------------------------------------------------

-- The quest you're looking at (quest giver, then quest log), or the one you're
-- following on screen.
function ns.CurrentQuestID()
	local id
	if QuestFrame and QuestFrame:IsShown() then id = query(GetQuestID) end
	if (not id or id == 0) and QuestMapFrame and QuestMapFrame.DetailsFrame and QuestMapFrame.DetailsFrame:IsVisible() then
		id = query(C_QuestLog.GetSelectedQuest)
	end
	if (not id or id == 0) and C_SuperTrack then id = query(C_SuperTrack.GetSuperTrackedQuestID) end
	if id == 0 then id = nil end
	return id
end

function ns.MuseQuest(questID)
	if not questID then
		return nil, "Open a quest in your quest log, or follow one, then try again."
	end
	for _, e in ipairs(ns.db.quests) do
		if e.questID == questID then return e end
	end
	local t = time()
	local entry = {
		id = ns.NewId(), questID = questID,
		title = query(C_QuestLog.GetTitleForQuestID, questID) or ("Quest " .. questID),
		zone = ns.CurrentZone(), body = "", created = t, modified = t,
	}
	table.insert(ns.db.quests, entry)
	return entry
end

function ns.DescribeQuest(e)
	local text = "Taken up in " .. (e.zone or "?") .. ", " .. ns.Stamp(e.created)
	if e.completed then text = text .. "\nCompleted " .. ns.Stamp(e.completed) end
	return text
end

function ns.ShowQuest(e)
	local inLog = query(C_QuestLog.GetLogIndexForQuestID, e.questID)
	if inLog and QuestMapFrame_OpenToQuestDetails then
		pcall(QuestMapFrame_OpenToQuestDetails, e.questID)
	else
		ns.Say("That quest is no longer in your quest log.")
	end
end

-- Chronicle -----------------------------------------------------------------

function ns.TodayPage()
	local day = date("%Y-%m-%d")
	for _, e in ipairs(ns.db.chronicle) do
		if e.day == day then return e end
	end
	local t = time()
	local entry = { id = ns.NewId(), day = day, title = date("%A %d %B %Y"), body = "", created = t, modified = t }
	table.insert(ns.db.chronicle, entry)
	return entry
end

function ns.Chronicle(text)
	if not ns.db.chronicleOn then return end
	local page = ns.TodayPage()
	local body = page.body or ""
	if body ~= "" and not body:match("\n$") then body = body .. "\n" end
	page.body = body .. date("%H:%M") .. "  " .. text .. "\n"
	page.modified = time()
	ns.EntryChanged(page)
end

local function where()
	return query(GetRealZoneText) or "unknown lands"
end

-- Screenshot memories: what was going on when a screenshot was taken.
-- The game names files WoWScrnShot_MMDDYY_HHMMSS, so the chronicle line
-- carries that name to match the picture in the Screenshots folder later.
local pendingShot

local function describeMoment()
	local bits = {}
	local target = query(UnitName, "target")
	if target and not query(UnitIsUnit, "target", "player") then
		if query(UnitIsDead, "target") then
			table.insert(bits, "standing over " .. target)
		elseif query(UnitCanAttack, "player", "target") then
			table.insert(bits, "facing " .. target)
		else
			table.insert(bits, "with " .. target)
		end
	end
	if query(UnitAffectingCombat, "player") then table.insert(bits, "in the middle of a fight") end
	if query(IsMounted) then table.insert(bits, "on horseback") end
	if query(IsResting) then table.insert(bits, "resting") end
	local group = query(GetNumGroupMembers) or 0
	if group > 1 then table.insert(bits, "with " .. (group - 1) .. " companion" .. (group > 2 and "s" or "")) end
	return table.concat(bits, ", ")
end

local function noteScreenshot()
	local shot = pendingShot or { t = time(), zone = ns.CurrentZone(), doing = describeMoment() }
	pendingShot = nil
	local line = "Captured a moment in " .. shot.zone
	if shot.doing ~= "" then line = line .. ", " .. shot.doing end
	ns.Chronicle(line .. ". [" .. date("WoWScrnShot_%m%d%y_%H%M%S", shot.t) .. "]")
end

local chronicler = CreateFrame("Frame")
local function visitZone(firstTime)
	local zone = query(GetRealZoneText)
	if not zone or zone == "" or ns.db.visited[zone] then return end
	ns.db.visited[zone] = true
	if firstTime then
		ns.Chronicle("Opened a fresh journal in " .. zone .. ".")
	else
		ns.Chronicle("First set foot in " .. zone .. ".")
	end
end

chronicler:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
		visitZone(next(ns.db.visited) == nil)
	elseif event == "PLAYER_LEVEL_UP" then
		local level = clean(...)
		if level then ns.Chronicle("Reached level " .. level .. " in " .. where() .. ".") end
	elseif event == "ENCOUNTER_END" then
		local _, name, _, _, success = ...
		name, success = clean(name), clean(success)
		if name and success == 1 then
			local instance = query(GetInstanceInfo)
			ns.Chronicle("Defeated " .. name .. (instance and (" in " .. instance) or "") .. ".")
		end
	elseif event == "SCREENSHOT_STARTED" then
		pendingShot = { t = time(), zone = ns.CurrentZone(), doing = describeMoment() }
	elseif event == "SCREENSHOT_SUCCEEDED" then
		if ns.db.screenshotsOn then noteScreenshot() end
		pendingShot = nil
	elseif event == "SCREENSHOT_FAILED" then
		pendingShot = nil
	elseif event == "PLAYER_DEAD" then
		ns.Chronicle("Fell in " .. where() .. ".")
	elseif event == "NEW_MOUNT_ADDED" then
		local mountID = clean(...)
		local name = mountID and C_MountJournal and query(C_MountJournal.GetMountInfoByID, mountID)
		if name then ns.Chronicle("Earned a new mount: " .. name .. ".") end
	elseif event == "ACHIEVEMENT_EARNED" then
		local achievementID = clean(...)
		local _, name = query(GetAchievementInfo, achievementID)
		if name then ns.Chronicle("Achievement: " .. name .. ".") end
	elseif event == "QUEST_TURNED_IN" then
		local questID = clean(...)
		for _, e in ipairs(ns.db.quests) do
			if e.questID == questID and not e.completed then
				e.completed = time()
				local body = e.body or ""
				if body ~= "" and not body:match("\n$") then body = body .. "\n" end
				e.body = body .. "\n-- Completed " .. ns.Stamp(e.completed) .. " --\n"
				e.modified = e.completed
				ns.EntryChanged(e)
				ns.Chronicle("Finished the quest \"" .. e.title .. "\".")
			end
		end
	end
end)

table.insert(ns.onLoad, function()
	for _, event in ipairs({
		"PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP", "ENCOUNTER_END",
		"PLAYER_DEAD", "NEW_MOUNT_ADDED", "ACHIEVEMENT_EARNED", "QUEST_TURNED_IN",
		"SCREENSHOT_STARTED", "SCREENSHOT_SUCCEEDED", "SCREENSHOT_FAILED",
	}) do
		pcall(chronicler.RegisterEvent, chronicler, event) -- skip any event this client lacks
	end
end)

-- Right-click menus: "Write in Field Journal" --------------------------------

local function addMenuButton(_, root, context)
	if not context then return end
	root:CreateDivider()
	root:CreateButton("Write in Field Journal", function()
		local entry, msg
		local unit = clean(context.unit)
		if unit and query(UnitExists, unit) then
			entry, msg = ns.CaptureUnit(unit)
		else
			entry, msg = ns.PlayerByName(context.name, context.server)
		end
		if msg and not entry then ns.Say(msg) end
		if entry then ns.Open("encounters", entry, "end") end
	end)
end

if Menu and Menu.ModifyMenu then
	for _, tag in ipairs({
		"MENU_UNIT_FRIEND",          -- names in chat
		"MENU_UNIT_PLAYER", "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER",
		"MENU_UNIT_TARGET", "MENU_UNIT_FOCUS",
		"MENU_UNIT_COMMUNITIES_GUILD_MEMBER", "MENU_UNIT_COMMUNITIES_WOW_MEMBER",
	}) do
		pcall(Menu.ModifyMenu, tag, addMenuButton)
	end
end

-- Quest log button ------------------------------------------------------------

-- A small book on the quest details page that opens your thoughts on it.
local questButton
local function addQuestButton()
	if questButton or not (QuestMapFrame and QuestMapFrame.DetailsFrame) then return end
	questButton = CreateFrame("Button", nil, QuestMapFrame.DetailsFrame)
	questButton:SetSize(24, 24)
	questButton:SetPoint("TOPRIGHT", QuestMapFrame.DetailsFrame, "TOPRIGHT", -6, -6)
	questButton:SetFrameLevel(QuestMapFrame.DetailsFrame:GetFrameLevel() + 10)
	questButton:SetNormalTexture("Interface\\Icons\\INV_Misc_Book_09")
	questButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	questButton:SetScript("OnClick", FieldJournal_MuseQuest)
	questButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Field Journal")
		GameTooltip:AddLine("Write down your thoughts on this quest.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	questButton:SetScript("OnLeave", GameTooltip_Hide)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function()
	addQuestButton()
	if questButton then loader:UnregisterAllEvents() end
end)
