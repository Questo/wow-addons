local addonName, ns = ...

-- Played time: each character's total /played and time at their current level.
-- The game only tells addons this when asked, and the answer normally prints in
-- chat, so the ledger asks once after login with the chat lines held back.
-- For the character you're on, time since that answer is added as you play.
--   char.played = { total, level, at, lvl }  (seconds; at = when it was read)

local events = CreateFrame("Frame")
local asking = false
local muted = {}

local function muteChat(on)
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local cf = _G["ChatFrame" .. i]
		if cf and cf.IsEventRegistered then
			if on and cf:IsEventRegistered("TIME_PLAYED_MSG") then
				pcall(cf.UnregisterEvent, cf, "TIME_PLAYED_MSG")
				muted[cf] = true
			elseif not on and muted[cf] then
				pcall(cf.RegisterEvent, cf, "TIME_PLAYED_MSG")
				muted[cf] = nil
			end
		end
	end
end

local function ask()
	if not RequestTimePlayed then return end
	asking = true
	muteChat(true)
	RequestTimePlayed()
	-- If no answer comes, give chat its lines back anyway.
	C_Timer.After(10, function()
		if asking then
			asking = false
			muteChat(false)
		end
	end)
end

-- Seconds played in total and at this level, counting live time for the
-- character you're on. nil when never read.
function ns.Played(char)
	local p = char.played
	if not p or not p.total then return nil end
	local extra = 0
	if char == ns.Me() and p.at then extra = math.max(0, time() - p.at) end
	local level = p.level and (p.lvl == char.level) and (p.level + extra) or nil
	return p.total + extra, level
end

function ns.PlayedText(seconds)
	if not seconds then return "" end
	local d = math.floor(seconds / 86400)
	local h = math.floor(seconds % 86400 / 3600)
	local m = math.floor(seconds % 3600 / 60)
	if d > 0 then return d .. "d " .. h .. "h" end
	if h > 0 then return h .. "h " .. m .. "m" end
	return m .. "m"
end

local function store(total, level)
	local me = ns.Me()
	if not me then return end
	me.played = { total = total, level = level, at = time(), lvl = me.level }
	if ns.Refresh then ns.Refresh() end
end

events:SetScript("OnEvent", function(_, event, total, level)
	if event == "PLAYER_LOGIN" then
		events:RegisterEvent("TIME_PLAYED_MSG")
		events:RegisterEvent("PLAYER_LEVEL_UP")
		events:RegisterEvent("PLAYER_LOGOUT")
		C_Timer.After(6, ask)
	elseif event == "TIME_PLAYED_MSG" then
		if issecretvalue and (issecretvalue(total) or issecretvalue(level)) then return end
		store(total, level)
		if asking then
			asking = false
			-- Chat frames get this event too; give them their lines back after it.
			C_Timer.After(0, function() muteChat(false) end)
		end
	elseif event == "PLAYER_LEVEL_UP" then
		-- Time at this level starts again; ask for fresh numbers.
		C_Timer.After(2, ask)
	elseif event == "PLAYER_LOGOUT" then
		local me = ns.Me()
		local p = me and me.played
		if p and p.total then
			local total, level = ns.Played(me)
			me.played = { total = total, level = level, at = time(), lvl = me.level }
		end
	end
end)
events:RegisterEvent("PLAYER_LOGIN")
