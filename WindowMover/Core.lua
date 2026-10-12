local addonName = ...

-- Each movable window gets a small handle in its title bar. Dragging the handle
-- moves the window; right-clicking it puts the window back where Blizzard wants it.
-- Blizzard re-anchors these windows whenever they open (bags stack in the corner,
-- the character pane follows the panel layout), so we put saved positions back
-- after each of those updates.

-- Each window lists the frame names it can have; older or renamed Blizzard
-- frames are listed too, and whichever exists gets a button. Some of these
-- windows only load the first time you open them.
-- offset moves the button further left when the window has its own buttons
-- next to the close button (the map's maximize button).
local WINDOWS = {
	{ key = "character", label = "Character pane", frames = { "CharacterFrame" } },
	{ key = "bags", label = "Bags", frames = { "ContainerFrameCombinedBags" }, bags = true },
	{ key = "spellbook", label = "Spellbook and talents", frames = { "PlayerSpellsFrame", "SpellBookFrame", "ClassTalentFrame", "PlayerTalentFrame" } },
	{ key = "quests", label = "Map and quest log", frames = { "WorldMapFrame", "QuestLogFrame" }, offset = -50 },
	{ key = "collections", label = "Collections", frames = { "CollectionsJournal" } },
	{ key = "professions", label = "Professions", frames = { "ProfessionsFrame", "TradeSkillFrame" } },
}
for i = 1, 13 do
	table.insert(WINDOWS[2].frames, "ContainerFrame" .. i)
end

local LABELS = {}
for _, window in ipairs(WINDOWS) do LABELS[window.key] = window.label end

local db
local handles = {}          -- frame -> handle button
local frameKey = {}         -- frame -> window key ("bags" / "character")
local pending = {}          -- frames to reposition once combat ends
local events = CreateFrame("Frame")

local function say(msg)
	print("|cff66ccffWindow Mover:|r " .. msg)
end

-- Some windows can become protected; moving those in combat is blocked.
local raise

local function blocked(frame)
	return InCombatLockdown() and frame:IsProtected()
end

local function apply(frame)
	local pos = db.positions[frame:GetName()]
	if not pos then return end
	-- A maximized map fills the screen; leave it where Blizzard puts it.
	if frame.IsMaximized and frame:IsMaximized() then return end
	if blocked(frame) then
		pending[frame] = true
		return
	end
	local s = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", pos.x / s, pos.y / s)
end

-- key "panels" means every window except the bags.
local function applyAll(key)
	for frame, k in pairs(frameKey) do
		local match = not key or k == key or (key == "panels" and k ~= "bags")
		if match and frame:IsShown() then
			apply(frame)
		end
	end
end

local function save(frame)
	local s = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local left, top = frame:GetLeft(), frame:GetTop()
	if not left or not top then return end
	db.positions[frame:GetName()] = {
		x = left * s,
		y = top * s - UIParent:GetHeight(),
	}
end

-- Let Blizzard place the window again.
local function restoreDefault(frame)
	if blocked(frame) then return end
	if frameKey[frame] == "bags" then
		if UpdateContainerFrameAnchors then UpdateContainerFrameAnchors() end
	elseif UpdateUIPanelPositions then
		UpdateUIPanelPositions(frame)
	end
end

local function reset(key)
	if InCombatLockdown() then
		say("Can't reset while in combat. Try again after the fight.")
		return
	end
	for frame, k in pairs(frameKey) do
		if not key or k == key then
			db.positions[frame:GetName()] = nil
			if frame:IsShown() then restoreDefault(frame) end
		end
	end
end

local function updateHandles()
	for _, handle in pairs(handles) do
		handle:SetShown(not db.locked)
	end
end

-- The window's border and title art are child frames that can sit at a much
-- higher level than the window itself, so put the button above all of them.
local function topLevel(frame, depth)
	local top = frame:GetFrameLevel()
	if depth > 0 then
		for _, child in ipairs({ frame:GetChildren() }) do
			top = math.max(top, topLevel(child, depth - 1))
		end
	end
	return top
end

raise = function(handle, frame)
	handle:SetFrameStrata("DIALOG")
	handle:SetFrameLevel(math.min(topLevel(frame, 2) + 10, 9000))
end

local function addHandle(frame, offset)
	if handles[frame] then return end
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)

	-- A standard red game button reading "Move", so it always draws.
	local handle = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	handle:SetSize(48, 20)
	handle:SetText("Move")
	-- Top right of the window, left of the close button.
	handle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", offset or -26, -1)
	raise(handle, frame)

	handle:RegisterForDrag("LeftButton")
	handle:RegisterForClicks("RightButtonUp")

	handle:SetScript("OnDragStart", function()
		if blocked(frame) then
			say("This window can't be moved during combat.")
			return
		end
		frame.wmMoving = true
		frame:StartMoving()
	end)
	handle:SetScript("OnDragStop", function()
		if not frame.wmMoving then return end
		frame.wmMoving = nil
		frame:StopMovingOrSizing()
		-- Keep the position in our own saved data, not the game's layout cache.
		frame:SetUserPlaced(false)
		save(frame)
		apply(frame)
	end)
	handle:SetScript("OnClick", function(_, button)
		if button == "RightButton" then
			if InCombatLockdown() then
				say("Can't reset while in combat.")
				return
			end
			db.positions[frame:GetName()] = nil
			restoreDefault(frame)
		end
	end)
	handle:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Window Mover")
		GameTooltip:AddLine("Drag to move this window.", 1, 1, 1)
		GameTooltip:AddLine("Right-click to put it back.", 1, 1, 1)
		GameTooltip:Show()
	end)
	handle:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	-- Re-apply on show, and once more next frame in case Blizzard anchors after us.
	frame:HookScript("OnShow", function(self)
		raise(handle, self)
		apply(self)
		C_Timer.After(0, function() if self:IsShown() then apply(self) end end)
	end)

	handle:SetShown(not db.locked)
	handles[frame] = handle
end

local function setupFrames()
	for _, window in ipairs(WINDOWS) do
		for _, name in ipairs(window.frames) do
			local frame = _G[name]
			if frame and not handles[frame] then
				frameKey[frame] = window.key
				addHandle(frame, window.offset)
			end
		end
	end
end

local hooked = false
local function hookBlizzard()
	if hooked then return end
	hooked = true
	if UpdateContainerFrameAnchors then
		hooksecurefunc("UpdateContainerFrameAnchors", function() applyAll("bags") end)
	end
	if UpdateUIPanelPositions then
		hooksecurefunc("UpdateUIPanelPositions", function() applyAll("panels") end)
	end
	-- In case a window didn't exist yet at login, look again when one opens.
	for _, fn in ipairs({ "ToggleCharacter", "ToggleAllBags", "OpenAllBags", "ToggleBackpack", "ToggleBag", "OpenBag",
		"ToggleWorldMap", "ToggleQuestLog", "ToggleCollectionsJournal", "TogglePlayerSpellsFrame", "ToggleSpellBook", "ToggleTalentFrame" }) do
		if _G[fn] then
			hooksecurefunc(fn, function() setupFrames() end)
		end
	end
end

events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == addonName then
			WindowMoverDB = WindowMoverDB or {}
			db = WindowMoverDB
			db.positions = db.positions or {}
			if db.locked == nil then db.locked = false end
		end
		-- Some Blizzard windows load on demand; catch them when they appear.
		if db then setupFrames() end
	elseif event == "PLAYER_LOGIN" then
		setupFrames()
		hookBlizzard()
		say("loaded. Type /wmover for help.")
	elseif event == "PLAYER_REGEN_ENABLED" then
		for frame in pairs(pending) do
			pending[frame] = nil
			if frame:IsShown() then apply(frame) end
		end
	end
end)

SLASH_WINDOWMOVER1 = "/wmover"
SLASH_WINDOWMOVER2 = "/windowmover"
SlashCmdList.WINDOWMOVER = function(msg)
	local cmd, arg = strsplit(" ", strtrim(msg or ""):lower(), 2)
	if cmd == "reset" then
		if arg and LABELS[arg] then
			reset(arg)
			say(LABELS[arg] .. " back to the default position.")
		elseif not arg then
			reset()
			say("All windows back to their default positions.")
		else
			say("Use /wmover reset, or /wmover reset with one of: bags, character, spellbook, quests, collections, professions.")
		end
	elseif cmd == "lock" then
		db.locked = not db.locked
		updateHandles()
		say(db.locked and "Move buttons hidden. Windows stay where they are. /wmover lock shows them again."
			or "Move buttons shown.")
	elseif cmd == "status" then
		setupFrames()
		local count = 0
		for _, window in ipairs(WINDOWS) do
			for _, name in ipairs(window.frames) do
				local frame = _G[name]
				if frame then
					local handle = handles[frame]
					if frame:IsShown() or not name:match("^ContainerFrame%d") then
						say(name .. ": " .. (frame:IsShown() and "open" or "closed")
							.. (handle and (", button " .. (handle:IsVisible() and "visible" or "hidden")
								.. " (level " .. handle:GetFrameLevel() .. ")") or ", no button")
							.. (db.positions[name] and ", moved" or ""))
					end
					if handle then count = count + 1 end
				elseif name == "CharacterFrame" or name == "ContainerFrameCombinedBags" then
					say(name .. ": not found")
				end
			end
		end
		say(count .. " windows have a Move button." .. (db.locked and " Buttons are hidden (/wmover lock)." or ""))
	else
		say("Hold the Move button at the top of a window and drag. Right-click it to put the window back.")
		say("/wmover reset [bags|character|spellbook|quests|collections|professions] - restore default positions")
		say("/wmover lock - hide or show the Move buttons")
		say("/wmover status - list the windows Window Mover knows about")
	end
end
