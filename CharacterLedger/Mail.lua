local addonName, ns = ...

-- Mail: what each character has waiting at the mailbox. The inbox can only be
-- read while the mailbox is open, so each character's mail is remembered from
-- their last visit. Outside the mailbox the game only says "you have new mail".
--   char.mail = { seen, count, unread, items, money, cod, expires, letters = { ... } }
--   char.newMail = true when the game says new mail has arrived since the last visit

local WARN_DAYS = 3
local MAX_LETTERS = 60
local events = CreateFrame("Frame")
local mailboxOpen = false

local function clean(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

local function scanInbox()
	local me = ns.Me()
	if not me or not mailboxOpen or not GetInboxNumItems then return end
	local shown, total = GetInboxNumItems()
	shown = clean(shown) or 0
	local now = time()
	local mail = { seen = now, count = clean(total) or shown, unread = 0, items = 0, money = 0, cod = 0, letters = {} }
	for i = 1, shown do
		local _, _, sender, subject, money, cod, daysLeft, itemCount, wasRead, wasReturned =
			GetInboxHeaderInfo(i)
		money, cod, itemCount = clean(money) or 0, clean(cod) or 0, clean(itemCount) or 0
		daysLeft = clean(daysLeft)
		if not clean(wasRead) then mail.unread = mail.unread + 1 end
		mail.items = mail.items + itemCount
		mail.money = mail.money + money
		if cod > 0 then mail.cod = mail.cod + 1 end
		local expires = daysLeft and (now + math.floor(daysLeft * 86400)) or nil
		-- Only letters carrying something can be lost when they run out.
		if expires and (itemCount > 0 or money > 0) and (not mail.expires or expires < mail.expires) then
			mail.expires = expires
		end
		if #mail.letters < MAX_LETTERS then
			table.insert(mail.letters, {
				sender = clean(sender) or "?", subject = clean(subject) or "",
				items = itemCount, money = money, cod = cod > 0, returned = clean(wasReturned) and true or nil,
				read = clean(wasRead) and true or nil, expires = expires,
			})
		end
	end
	me.mail = mail
	me.newMail = mail.unread > 0
	if ns.Refresh then ns.Refresh() end
end

local function updateNewMail()
	local me = ns.Me()
	if not me or mailboxOpen then return end
	local has = HasNewMail and clean(HasNewMail())
	if has then me.newMail = true end
	if ns.Refresh then ns.Refresh() end
end

-- True when this character has something waiting worth a trip to the mailbox.
function ns.HasMail(char)
	if char.newMail then return true end
	local m = char.mail
	return m and (m.unread > 0 or m.items > 0 or m.money > 0) or false
end

-- Letters with items or gold that run out within WARN_DAYS, for one character.
function ns.ExpiringMail(char)
	local m = char.mail
	if not m or not m.expires then return nil end
	if m.expires - time() > WARN_DAYS * 86400 then return nil end
	return m.expires
end

local function warnExpiring()
	local lines = {}
	for _, char in ipairs(ns.Characters()) do
		local at = ns.ExpiringMail(char)
		if at then
			local left = at - time()
			local when = left <= 0 and "may already have run out"
				or left < 86400 and ("runs out in " .. math.max(1, math.floor(left / 3600)) .. "h")
				or ("runs out in " .. math.floor(left / 86400) .. "d")
			table.insert(lines, ns.ColoredName(char) .. ": mail with items or gold " .. when .. ".")
		end
	end
	if #lines > 0 then
		ns.Say("mail that could be lost or sent back:")
		for _, l in ipairs(lines) do print("   " .. l) end
	end
end

events:SetScript("OnEvent", function(_, event, arg1)
	if event == "PLAYER_LOGIN" then
		for _, e in ipairs({ "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE", "UPDATE_PENDING_MAIL",
			"PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" }) do
			pcall(events.RegisterEvent, events, e)
		end
		C_Timer.After(2, updateNewMail)
		C_Timer.After(8, warnExpiring)
	elseif event == "MAIL_SHOW" then
		mailboxOpen = true
		C_Timer.After(0.5, scanInbox)
	elseif event == "MAIL_CLOSED" then
		scanInbox()
		mailboxOpen = false
	elseif event == "MAIL_INBOX_UPDATE" then
		scanInbox()
	elseif event == "UPDATE_PENDING_MAIL" then
		updateNewMail()
	elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
		local pit = Enum.PlayerInteractionType
		if pit and arg1 == pit.MailInfo then
			if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
				mailboxOpen = true
				C_Timer.After(0.5, scanInbox)
			else
				scanInbox()
				mailboxOpen = false
			end
		end
	end
end)
events:RegisterEvent("PLAYER_LOGIN")
