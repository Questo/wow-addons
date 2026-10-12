local addonName, ns = ...

-- Fading uses SetAlpha only. Alpha is not protected, so it works in combat
-- without taint, unlike Show/Hide on action bars and unit frames.

local db
local groups = ns.groups
local active = false        -- in combat or has a target
local inactiveSince = 0     -- GetTime() when active last turned false
local hooked = {}           -- frame -> true once SetAlpha is hooked
local setting = false       -- guard so our own SetAlpha doesn't re-trigger the hook
local lastActivity = 0      -- GetTime() of the last chat message
local activityHooked = {}   -- chat frame -> true once AddMessage is hooked

local function isEnabled(group)
	local override = db.groups[group.key]
	if override == nil then return group.enabled end
	return override
end

local function isHoverOnly(group)
	local override = db.hoverOnly[group.key]
	if override == nil then return group.hoverOnly or false end
	return override
end

local function resolve(group)
	group.resolved = group.resolved or {}
	for i, names in ipairs(group.frames) do
		if not group.resolved[i] then
			for _, name in ipairs(names) do
				local f = _G[name]
				if f and f.SetAlpha then
					group.resolved[i] = f
					if group.activityOnly and f.AddMessage and not activityHooked[f] then
						activityHooked[f] = true
						hooksecurefunc(f, "AddMessage", function() lastActivity = GetTime() end)
					end
					break
				end
			end
		end
	end
	return group.resolved
end

local function applyAlpha(frame, alpha)
	setting = true
	frame:SetAlpha(alpha)
	setting = false
end

local function hook(frame, group)
	if hooked[frame] then return end
	hooked[frame] = true
	-- Blizzard code sometimes resets alpha (vehicles, Edit Mode); put ours back.
	hooksecurefunc(frame, "SetAlpha", function(self)
		if setting or not group.alpha or not isEnabled(group) then return end
		applyAlpha(self, group.alpha)
	end)
end

local function inEditMode()
	return EditModeManagerFrame and EditModeManagerFrame:IsShown()
end

local function safeBool(v)
	if issecretvalue and issecretvalue(v) then return true end
	return v and true or false
end

local function computeActive()
	if InCombatLockdown() or safeBool(UnitAffectingCombat("player")) then return true end
	if not UnitExists("target") then return false end
	if db.hostileOnly then return safeBool(UnitCanAttack("player", "target")) end
	return true
end

local function refreshState()
	local now = computeActive()
	if active and not now then inactiveSince = GetTime() end
	active = now
end

-- Fraction (0-1) of a unit value, or nil if the game hides it (secret values).
local function fraction(cur, max)
	if issecretvalue and (issecretvalue(cur) or issecretvalue(max)) then return nil end
	if not cur or not max or max <= 0 then return nil end
	return cur / max
end

local function isRecovering()
	if UnitIsDeadOrGhost("player") then return false end
	local hp = fraction(UnitHealth("player"), UnitHealthMax("player"))
	if hp and hp < 1 then return true end
	-- Only mana counts: rage and energy don't need a rest.
	local manaType = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
	local mana = fraction(UnitPower("player", manaType), UnitPowerMax("player", manaType))
	if mana and mana < 1 then return true end
	return false
end

-- True when anyone else in your party (not raid) is alive and below full health.
local function isPartyHurt()
	if IsInRaid() then return false end
	for i = 1, 4 do
		local unit = "party" .. i
		if UnitExists(unit) and not UnitIsDeadOrGhost(unit) and UnitIsConnected(unit) then
			local hp = fraction(UnitHealth(unit), UnitHealthMax(unit))
			if hp and hp < 1 then return true end
		end
	end
	return false
end

local function isTyping()
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local box = _G["ChatFrame" .. i .. "EditBox"]
		if box and box:HasFocus() then return true end
	end
	return false
end

local function isHovered(frames)
	for _, f in pairs(frames) do
		if f:IsVisible() and f:IsMouseOver() then return true end
	end
	return false
end

local driver = CreateFrame("Frame")
local recovering = false
local partyHurt = false

local mouseTimer = 0
driver:SetScript("OnUpdate", function(_, elapsed)
	mouseTimer = mouseTimer + elapsed
	local checkMouse = mouseTimer > 0.1
	if checkMouse then mouseTimer = 0 end

	local showAll = active or inEditMode() or (GetTime() - inactiveSince < db.fadeOutDelay)
	if checkMouse then
		recovering = db.recovery and isRecovering()
		partyHurt = db.partyHurt and isPartyHurt()
	end

	for _, group in ipairs(groups) do
		local frames = resolve(group)
		if isEnabled(group) then
			local hoverOnly = isHoverOnly(group)
			if checkMouse then group.hover = (hoverOnly or db.mouseover) and isHovered(frames) end
			local shown
			if group.activityOnly then
				if checkMouse then group.hover = isHovered(frames) end
				shown = group.hover or inEditMode() or isTyping() or (GetTime() - lastActivity < db.chatVisible)
			else
				shown = group.hover or inEditMode() or (showAll and not hoverOnly)
					or (group.recovery and recovering and not hoverOnly)
					or (group.partyHurt and partyHurt and not hoverOnly)
			end
			local target = shown and 1 or db.hiddenAlpha
			local current = group.alpha or 1
			if current ~= target then
				local duration = target > current and db.fadeIn or db.fadeOut
				local step = duration > 0 and elapsed / duration or 1
				if target > current then
					current = math.min(target, current + step)
				else
					current = math.max(target, current - step)
				end
				group.alpha = current
				for _, f in pairs(frames) do
					hook(f, group)
					applyAlpha(f, current)
				end
			end
		elseif group.alpha then
			-- Group was just disabled: restore it and stop managing it.
			group.alpha = nil
			for _, f in pairs(frames) do applyAlpha(f, 1) end
		end
	end
end)

driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("PLAYER_REGEN_DISABLED")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:RegisterEvent("PLAYER_TARGET_CHANGED")
driver:RegisterEvent("UNIT_FLAGS")

driver:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= addonName then return end
		ImmersiveUIDB = ImmersiveUIDB or {}
		db = ImmersiveUIDB
		for k, v in pairs(ns.defaults) do
			if db[k] == nil then db[k] = type(v) == "table" and {} or v end
		end
		driver:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_REGEN_DISABLED" then
		active = true -- InCombatLockdown() may still be false during this event
	elseif event == "UNIT_FLAGS" and arg1 ~= "player" then
		return
	else
		refreshState()
	end
end)

-- Slash commands ------------------------------------------------------------

local function say(msg) print("|cff66ccffImmersive UI:|r " .. msg) end

local function onOff(v) return v and "|cff00ff00on|r" or "|cffff4444off|r" end

SLASH_IMMERSIVEUI1 = "/iui"
SlashCmdList.IMMERSIVEUI = function(msg)
	local cmd, arg = strsplit(" ", strtrim(msg or ""):lower(), 2)
	if cmd == "toggle" and arg then
		for _, group in ipairs(groups) do
			if group.key == arg then
				db.groups[arg] = not isEnabled(group)
				say(group.label .. " " .. onOff(db.groups[arg]))
				return
			end
		end
		say("Unknown element '" .. arg .. "'. Type /iui list.")
	elseif cmd == "hover" and arg then
		for _, group in ipairs(groups) do
			if group.key == arg then
				db.hoverOnly[arg] = not isHoverOnly(group)
				say(group.label .. " mouseover only " .. onOff(db.hoverOnly[arg]))
				return
			end
		end
		say("Unknown element '" .. arg .. "'. Type /iui list.")
	elseif cmd == "list" then
		for _, group in ipairs(groups) do
			local found = next(resolve(group)) and "" or " |cff888888(frame not found)|r"
			local hover = isHoverOnly(group) and " (mouseover only)" or ""
			say(group.key .. " - " .. group.label .. ": " .. onOff(isEnabled(group)) .. hover .. found)
		end
	elseif cmd == "mouseover" then
		db.mouseover = not db.mouseover
		say("Reveal on mouseover " .. onOff(db.mouseover))
	elseif cmd == "hostile" then
		db.hostileOnly = not db.hostileOnly
		say("Only hostile targets count " .. onOff(db.hostileOnly))
	elseif cmd == "recovery" then
		db.recovery = not db.recovery
		say("Player frame stays up while recovering " .. onOff(db.recovery))
	elseif cmd == "party" then
		db.partyHurt = not db.partyHurt
		say("Party frames show while someone is hurt " .. onOff(db.partyHurt))
	elseif cmd == "alpha" and tonumber(arg) then
		db.hiddenAlpha = math.max(0, math.min(1, tonumber(arg)))
		say("Hidden alpha set to " .. db.hiddenAlpha)
	elseif cmd == "delay" and tonumber(arg) then
		db.fadeOutDelay = math.max(0, tonumber(arg))
		say("Fade-out delay set to " .. db.fadeOutDelay .. "s")
	elseif cmd == "chat" and tonumber(arg) then
		db.chatVisible = math.max(0, tonumber(arg))
		say("Chat stays visible for " .. db.chatVisible .. "s after a message")
	elseif cmd == "reset" then
		wipe(db)
		for k, v in pairs(ns.defaults) do db[k] = type(v) == "table" and {} or v end
		say("Settings reset.")
	else
		say("commands:")
		print("  /iui list - show elements and whether they fade")
		print("  /iui toggle <element> - turn fading on/off for one element")
		print("  /iui hover <element> - show an element only on mouseover, even in combat")
		print("  /iui mouseover - reveal hidden elements on hover")
		print("  /iui hostile - only hostile targets reveal the UI")
		print("  /iui recovery - keep the player frame up until health/mana is full")
		print("  /iui party - show party frames while a party member is hurt")
		print("  /iui alpha <0-1> - how visible hidden elements are")
		print("  /iui delay <seconds> - wait before fading out")
		print("  /iui chat <seconds> - how long chat stays after a new message")
		print("  /iui reset - restore defaults")
	end
end
