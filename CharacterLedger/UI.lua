local addonName, ns = ...

-- The ledger window. Each tab is a view: a set of columns, an optional search
-- box, and a build function that turns the saved data into rows.

local WIDTH, HEIGHT = 820, 440
local LIST_W = WIDTH - 70
local ROW_H = 22
local frame, mode
local w = {}
local button -- defined with the window code below

local function goldText(copper)
	if not copper then return "?" end
	if GetMoneyString then return GetMoneyString(copper, true) end
	return math.floor(copper / 10000) .. "g"
end

local function ago(t)
	if not t then return "" end
	local s = time() - t
	if s < 3600 then return "just now" end
	if s < 86400 then return math.floor(s / 3600) .. "h ago" end
	return math.floor(s / 86400) .. "d ago"
end

local function untilText(t)
	local s = t - time()
	if s < 3600 then return math.max(1, math.floor(s / 60)) .. "m" end
	if s < 86400 then return math.floor(s / 3600) .. "h" end
	return math.floor(s / 86400) .. "d " .. math.floor(s % 86400 / 3600) .. "h"
end

local function qualityName(itemID, name)
	local quality = itemID and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID)
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	return color and color.hex and (color.hex .. name .. "|r") or name
end

local function itemTooltip(itemID)
	return function(owner)
		GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(itemID)
		GameTooltip:Show()
	end
end

local function linkItem(itemID)
	return function()
		if IsModifiedClick("CHATLINK") then
			local link = select(2, C_Item.GetItemInfo(itemID))
			if link then ChatEdit_InsertLink(link) end
		end
	end
end

-- Views -----------------------------------------------------------------------

local VIEWS, ORDER = {}, { "chars", "items", "recipes", "lockouts", "mail", "loot" }

local MAIL_ICON = "|TInterface\\Icons\\INV_Letter_15:14:14|t "

VIEWS.chars = {
	label = "Characters",
	cols = {
		{ "Character", 0, 170, "LEFT" },
		{ "Level", 172, 36, "CENTER" },
		{ "Item level", 210, 56, "CENTER" },
		{ "Gold", 268, 110, "RIGHT" },
		{ "Rested", 384, 56, "CENTER" },
		{ "Played", 444, 66, "CENTER" },
		{ "Professions", 516, 120, "LEFT" },
		{ "Last seen", 640, 110, "LEFT" },
	},
	build = function()
		local rows, me, totalGold, totalPlayed = {}, ns.Me(), 0, 0
		local chars = ns.Characters()
		for _, char in ipairs(chars) do
			local rested
			if char.level and char.level >= ns.MaxLevel() then
				rested = "|cff999999max level|r"
			else
				local pct = ns.RestedPercent(char)
				rested = pct and (pct .. "%") or ""
			end
			local profs = {}
			for _, p in ipairs(char.professions or {}) do table.insert(profs, p.name .. " " .. p.rank) end
			local played, atLevel = ns.Played(char)
			totalPlayed = totalPlayed + (played or 0)
			local seen = char == me and "|cff00ff00Playing now|r" or ((char.zone or "") .. "  |cff999999" .. ago(char.lastSeen) .. "|r")
			table.insert(rows, {
				cells = { (ns.HasMail(char) and MAIL_ICON or "") .. ns.ColoredName(char), char.level or "?", char.ilvl or "", goldText(char.money), rested, played and ns.PlayedText(played) or "|cff999999?|r", table.concat(profs, ", "), seen },
				tooltip = function(owner)
					GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
					GameTooltip:AddLine(ns.ColoredName(char))
					if char.zone then
						local where = char.subzone and char.subzone ~= "" and (char.subzone .. ", " .. char.zone) or char.zone
						GameTooltip:AddDoubleLine("Location", where, 1, 0.82, 0, 1, 1, 1)
					end
					if played then
						GameTooltip:AddDoubleLine("Played", ns.PlayedText(played), 1, 0.82, 0, 1, 1, 1)
						if atLevel then
							GameTooltip:AddDoubleLine("At this level", ns.PlayedText(atLevel), 1, 0.82, 0, 1, 1, 1)
						end
					else
						GameTooltip:AddLine("Played time is read the next time you log in on this character.", 0.6, 0.6, 0.6, true)
					end
					if char.level and char.xp and char.xpMax and char.xpMax > 0 and char.level < ns.MaxLevel() then
						GameTooltip:AddDoubleLine("XP", math.floor(char.xp / char.xpMax * 100) .. "% of level " .. char.level, 1, 0.82, 0, 1, 1, 1)
						GameTooltip:AddDoubleLine("Resting", char.resting and "Yes, in an inn or city" or "No", 1, 0.82, 0, 1, 1, 1)
					end
					for _, p in ipairs(char.professions or {}) do
						local known = char.recipes and char.recipes[p.name]
						local n = 0
						for _ in pairs(known or {}) do n = n + 1 end
						local right = p.rank .. " / " .. p.max .. (known and ("  (" .. n .. " recipes)") or "  |cff999999(open it once to read recipes)|r")
						GameTooltip:AddDoubleLine(p.name, right, 1, 0.82, 0, 1, 1, 1)
					end
					if ns.HasMail(char) then
						GameTooltip:AddLine("Has mail waiting. See the Mail tab.", 1, 0.82, 0, true)
					end
					if not char.bankSeen then
						GameTooltip:AddLine("Bank not seen yet. Visit a banker on this character.", 0.6, 0.6, 0.6, true)
					end
					GameTooltip:Show()
				end,
			})
			totalGold = totalGold + (char.money or 0)
		end
		return rows, #chars .. " characters    Total gold: " .. goldText(totalGold) .. "    Total played: " .. ns.PlayedText(totalPlayed)
	end,
}

VIEWS.items = {
	label = "Items",
	search = "Search items...",
	icon = true,
	cols = {
		{ "Item", 0, 250, "LEFT" },
		{ "Total", 280, 50, "RIGHT" },
		{ "Who", 345, LIST_W - 350, "LEFT" },
	},
	build = function(q)
		local matches, missing = {}, false
		for _, id in ipairs(ns.AllItemIDs()) do
			local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id) or C_Item.GetItemInfo(id)
			if not name then
				missing = true
				C_Item.RequestLoadItemDataByID(id)
			elseif q == "" or name:lower():find(q, 1, true) then
				table.insert(matches, { id = id, name = name })
			end
		end
		table.sort(matches, function(a, b) return a.name < b.name end)
		local rows = {}
		for _, m in ipairs(matches) do
			local holders, total = ns.Holders(m.id)
			local who = {}
			for _, r in ipairs(holders) do table.insert(who, r.short .. " " .. r.count) end
			table.insert(rows, {
				icon = C_Item.GetItemIconByID(m.id),
				cells = { qualityName(m.id, m.name), total, table.concat(who, ", ") },
				tooltip = itemTooltip(m.id),
				click = linkItem(m.id),
			})
		end
		local empty = q == "" and "No items remembered yet." or "Nobody has an item matching that."
		return rows, nil, empty, missing
	end,
}

VIEWS.recipes = {
	label = "Recipes",
	search = "Search recipes...",
	icon = true,
	cols = {
		{ "Recipe", 0, 260, "LEFT" },
		{ "Profession", 290, 120, "LEFT" },
		{ "Who knows it", 415, LIST_W - 420, "LEFT" },
	},
	build = function(q)
		local view = VIEWS.recipes
		local rows, profs, seen = {}, {}, {}
		for _, r in ipairs(ns.AllRecipes()) do
			if not seen[r.prof] then
				seen[r.prof] = true
				table.insert(profs, r.prof)
			end
			if (not view.prof or r.prof == view.prof)
				and (q == "" or r.name:lower():find(q, 1, true) or r.prof:lower():find(q, 1, true)) then
				table.insert(rows, {
					icon = r.icon or (r.item and C_Item.GetItemIconByID(r.item)),
					cells = { qualityName(r.item, r.name), r.prof, table.concat(r.who, ", ") },
					tooltip = r.item and itemTooltip(r.item) or function(owner)
						GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
						GameTooltip:SetSpellByID(r.id)
						GameTooltip:Show()
					end,
					click = r.item and linkItem(r.item),
				})
			end
		end
		table.sort(profs)
		if view.prof and not seen[view.prof] then view.prof = nil end
		view.profs = profs
		local empty = #profs == 0 and "No recipes yet. Open each profession once on each character." or "No recipe matching that."
		return rows, nil, empty
	end,
	-- A dropdown next to the search box picks one profession, or all of them.
	decorate = function(view)
		local function pick(prof)
			view.prof = prof
			if mode == "recipes" then ns.Refresh() end
		end
		local function generator(_, root)
			root:CreateRadio("All professions", function() return view.prof == nil end, function() pick(nil) end)
			for _, p in ipairs(view.profs or {}) do
				root:CreateRadio(p, function() return view.prof == p end, function() pick(p) end)
			end
		end
		if not view.dropdown then
			local ok, dd = pcall(CreateFrame, "DropdownButton", nil, view.panel, "WowStyle1DropdownTemplate")
			if ok and dd and dd.SetupMenu then
				dd:SetupMenu(generator)
				view.nativeDropdown = true
			else
				-- Fallback: a plain button that opens the same list as a menu.
				dd = button(view.panel, "", 170)
				dd:SetScript("OnClick", function(self) MenuUtil.CreateContextMenu(self, generator) end)
			end
			dd:SetWidth(170)
			dd:SetPoint("LEFT", view.box, "RIGHT", 12, 0)
			view.dropdown = dd
		end
		-- Rebuild only when the list or the choice changed, so an open menu isn't closed.
		local key = table.concat(view.profs or {}, "|") .. "#" .. (view.prof or "")
		if key ~= view.dropdownKey then
			view.dropdownKey = key
			if view.nativeDropdown then
				view.dropdown:GenerateMenu()
			else
				view.dropdown:SetText((view.prof or "All professions") .. " v")
			end
		end
	end,
}

VIEWS.lockouts = {
	label = "Lockouts",
	cols = {
		{ "Character", 0, 170, "LEFT" },
		{ "Instance", 175, 230, "LEFT" },
		{ "Difficulty", 410, 110, "LEFT" },
		{ "Bosses", 525, 80, "CENTER" },
		{ "Resets in", 610, 130, "LEFT" },
	},
	build = function()
		local rows = {}
		for _, e in ipairs(ns.AllLockouts()) do
			local l = e.lockout
			local bosses = (l.total and l.total > 0) and ((l.done or 0) .. " / " .. l.total) or ""
			table.insert(rows, {
				cells = { ns.ColoredName(e.char), (l.raid and "" or "|cff999999") .. l.name .. "|r", l.difficulty or "", bosses, untilText(l.resetAt) },
			})
		end
		return rows, nil, "No lockouts. Characters show up here after they log in while saved to a raid or dungeon."
	end,
}

VIEWS.mail = {
	label = "Mail",
	cols = {
		{ "Character", 0, 190, "LEFT" },
		{ "Letters", 195, 55, "CENTER" },
		{ "Unread", 255, 55, "CENTER" },
		{ "Items", 315, 50, "CENTER" },
		{ "Gold", 370, 120, "RIGHT" },
		{ "Runs out", 505, 110, "LEFT" },
		{ "Checked", 620, 125, "LEFT" },
	},
	build = function()
		local rows, waiting = {}, 0
		for _, char in ipairs(ns.Characters()) do
			local m = char.mail
			local cells
			if m then
				local soon = ns.ExpiringMail(char)
				local runsOut = ""
				if m.expires then
					runsOut = m.expires <= time() and "|cffff4444may be gone|r" or untilText(m.expires)
					if soon and m.expires > time() then runsOut = "|cffff4444" .. runsOut .. "|r" end
				end
				local checked = ago(m.seen)
				if char.newMail and m.unread == 0 then checked = "|cffffd100new mail since|r  |cff999999" .. checked .. "|r" end
				cells = {
					ns.ColoredName(char), m.count, m.unread > 0 and ("|cffffd100" .. m.unread .. "|r") or 0,
					m.items, m.money > 0 and goldText(m.money) or "", runsOut, checked,
				}
			else
				cells = { ns.ColoredName(char), "", "", "", "", "",
					char.newMail and "|cffffd100new mail|r, not opened yet" or "|cff999999visit a mailbox|r" }
			end
			if ns.HasMail(char) then waiting = waiting + 1 end
			table.insert(rows, {
				cells = cells,
				tooltip = function(owner)
					GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
					GameTooltip:AddLine(ns.ColoredName(char))
					if not m then
						GameTooltip:AddLine("Mail is read when you open a mailbox on this character.", 0.6, 0.6, 0.6, true)
					elseif #m.letters == 0 then
						GameTooltip:AddLine("Empty mailbox.", 1, 1, 1)
					else
						for i, l in ipairs(m.letters) do
							if i > 15 then
								GameTooltip:AddLine("... and " .. (#m.letters - 15) .. " more", 0.6, 0.6, 0.6)
								break
							end
							local what = {}
							if l.items > 0 then table.insert(what, l.items .. " item" .. (l.items > 1 and "s" or "")) end
							if l.money > 0 then table.insert(what, goldText(l.money)) end
							if l.cod then table.insert(what, "C.O.D.") end
							local left = l.sender .. ": " .. (l.subject ~= "" and l.subject or "(no subject)")
							if not l.read then left = "|cffffd100" .. left .. "|r" end
							local right = table.concat(what, ", ")
							if l.expires then right = right .. (right ~= "" and "  " or "") .. "|cff999999" .. (l.expires > time() and untilText(l.expires) or "gone?") .. "|r" end
							GameTooltip:AddDoubleLine(left, right, 1, 1, 1, 1, 1, 1)
						end
					end
					GameTooltip:Show()
				end,
			})
		end
		return rows, waiting .. " character" .. (waiting == 1 and " has" or "s have") .. " mail waiting.  Mail is remembered from each character's last mailbox visit."
	end,
}

local function charName(key)
	local char = key and ns.DB().chars[key]
	return char and ns.ColoredName(char) or (key and key:match("^[^-]+") or "")
end

local function lootTime(t)
	if date("%Y%m%d", t) == date("%Y%m%d") then return "today " .. date("%H:%M", t) end
	return date("%d %b %Y", t)
end

local MAX_LOOT_SHOWN = 500

VIEWS.loot = {
	label = "Loot",
	search = "Search loot, places, sources...",
	icon = true,
	cols = {
		{ "Item", 0, 220, "LEFT" },
		{ "Qty", 222, 36, "RIGHT" },
		{ "From", 266, 160, "LEFT" },
		{ "Where", 430, 150, "LEFT" },
		{ "Who", 584, 80, "LEFT" },
		{ "When", 666, 84, "LEFT" },
	},
	build = function(q)
		local rows, total = {}, 0
		for _, e in ipairs(ns.LootEntries()) do
			local from = e.src or ""
			if e.how then from = from ~= "" and (from .. " |cff999999(" .. e.how .. ")|r") or e.how end
			local where = (e.sub and e.sub ~= "" and e.sub ~= e.zone) and (e.sub .. ", " .. (e.zone or "")) or (e.zone or "")
			local hay = (e.name .. "\n" .. (e.src or "") .. "\n" .. (e.how or "") .. "\n" .. where .. "\n" .. (e.char or "")):lower()
			if q == "" or hay:find(q, 1, true) then
				total = total + 1
				if #rows < MAX_LOOT_SHOWN then
					table.insert(rows, {
						icon = C_Item.GetItemIconByID(e.id),
						cells = { qualityName(e.id, e.name), e.qty or 1, from, where, charName(e.char), lootTime(e.t) },
						tooltip = function(owner)
							GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
							GameTooltip:SetHyperlink(e.link)
							GameTooltip:AddLine(" ")
							GameTooltip:AddLine("Looted " .. date("%d %b %Y, %H:%M", e.t) .. " by " .. charName(e.char), 0.6, 0.6, 0.6)
							GameTooltip:Show()
						end,
						click = function()
							if IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(e.link) end
						end,
					})
				end
			end
		end
		local footer
		if total > MAX_LOOT_SHOWN then
			footer = "Showing the newest " .. MAX_LOOT_SHOWN .. " of " .. total .. ". Type to narrow it down."
		elseif total > 0 then
			footer = total .. " loot entries. The log keeps the newest 3000."
		end
		local empty = q == "" and "Nothing looted yet. Everything your characters loot from now on shows up here." or "No loot matching that."
		return rows, footer, empty
	end,
}

-- Rows ------------------------------------------------------------------------

local function fontString(parent, fontObject)
	local fs = parent:CreateFontString(nil, "OVERLAY", fontObject or "GameFontHighlightSmall")
	fs:SetWordWrap(false)
	return fs
end

local function getRow(view, i)
	view.rows = view.rows or {}
	if view.rows[i] then return view.rows[i] end
	local row = CreateFrame("Button", nil, view.child)
	row:SetSize(LIST_W, ROW_H)
	row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
	local bg = row:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0)
	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.08)
	if view.icon then
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(ROW_H - 4, ROW_H - 4)
		row.icon:SetPoint("LEFT", 4, 0)
	end
	row.cells = {}
	for c, col in ipairs(view.cols) do
		local fs = fontString(row, c == 1 and "GameFontHighlight" or nil)
		local x, width = col[2] + 4, col[3]
		if c == 1 and view.icon then
			x, width = x + ROW_H + 2, width - ROW_H - 2
		end
		fs:SetPoint("LEFT", x, 0)
		fs:SetWidth(width)
		fs:SetJustifyH(col[4])
		row.cells[c] = fs
	end
	row:SetScript("OnEnter", function(self)
		if self.data and self.data.tooltip then self.data.tooltip(self) end
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row:SetScript("OnClick", function(self)
		if self.data and self.data.click then self.data.click() end
	end)
	view.rows[i] = row
	return row
end

local MAX_ROWS = 150
local retryQueued = false

local function render(key)
	local view = VIEWS[key]
	local q = view.box and strtrim(view.box:GetText()):lower() or ""
	local rows, footer, empty, missing = view.build(q)
	if view.decorate then view.decorate(view) end
	local shown = math.min(#rows, MAX_ROWS)
	for i = 1, shown do
		local row = getRow(view, i)
		local data = rows[i]
		row.data = data
		if row.icon then row.icon:SetTexture(data.icon) end
		for c, fs in ipairs(row.cells) do
			local v = data.cells[c]
			fs:SetText(v ~= nil and tostring(v) or "")
		end
		row:Show()
	end
	for i = shown + 1, #(view.rows or {}) do view.rows[i]:Hide() end
	view.child:SetHeight(math.max(1, shown * ROW_H))

	if footer then
		w.footer:SetText(footer)
	elseif #rows == 0 then
		w.footer:SetText(empty or "")
	elseif #rows > MAX_ROWS then
		w.footer:SetText("Showing " .. MAX_ROWS .. " of " .. #rows .. ". Type more to narrow it down.")
	else
		w.footer:SetText(#rows .. " " .. view.label:lower())
	end

	-- Item names load from the server on demand; try again shortly.
	if missing and not retryQueued then
		retryQueued = true
		C_Timer.After(1, function()
			retryQueued = false
			if frame:IsShown() and mode == key then render(key) end
		end)
	end
end

-- Window ----------------------------------------------------------------------

function ns.Refresh()
	if not frame or not frame:IsShown() or not mode then return end
	render(mode)
end

local function setMode(m)
	mode = m
	for key, view in pairs(VIEWS) do
		view.panel:SetShown(key == m)
		w.tabs[key]:SetEnabled(key ~= m)
	end
	render(m)
end

function button(parent, text, width)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(text)
	return b
end

local function createView(key, view)
	local panel = CreateFrame("Frame", nil, frame)
	panel:SetPoint("TOPLEFT", 22, -72)
	panel:SetPoint("BOTTOMRIGHT", -16, 40)
	view.panel = panel

	local top = 0
	if view.search then
		local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
		box:SetSize(200, 20)
		box:SetPoint("TOPLEFT", 6, 2)
		box:SetAutoFocus(false)
		local hint = fontString(box, "GameFontDisableSmall")
		hint:SetPoint("LEFT", 2, 0)
		hint:SetText(view.search)
		box:SetScript("OnTextChanged", function(self)
			hint:SetShown(self:GetText() == "")
			if mode == key then render(key) end
		end)
		box:SetScript("OnEscapePressed", box.ClearFocus)
		box:SetScript("OnEnterPressed", box.ClearFocus)
		view.box = box
		top = -26
	end

	for c, col in ipairs(view.cols) do
		local h = fontString(panel, "GameFontNormalSmall")
		local x = col[2] + 4
		if c == 1 and view.icon then x = x + ROW_H + 2 end
		h:SetPoint("TOPLEFT", x, top)
		h:SetWidth(col[3])
		h:SetJustifyH(col[4])
		h:SetText(col[1])
	end

	local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, top - 18)
	scroll:SetPoint("BOTTOMRIGHT", -24, 0)
	view.child = CreateFrame("Frame", nil, scroll)
	view.child:SetSize(LIST_W, 1)
	scroll:SetScrollChild(view.child)
end

local function create()
	frame = CreateFrame("Frame", "CharacterLedgerFrame", UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	tinsert(UISpecialFrames, "CharacterLedgerFrame") -- Escape closes it
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		edgeSize = 32,
		insets = { left = 8, right = 8, top = 8, bottom = 8 },
	})
	frame:SetBackdropColor(0.06, 0.06, 0.08, 0.95)

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	local heading = fontString(frame, "GameFontNormalLarge")
	heading:SetPoint("TOP", 0, -18)
	heading:SetText("Character Ledger")

	w.tabs = {}
	local prev
	for _, key in ipairs(ORDER) do
		local tab = button(frame, VIEWS[key].label, 106)
		if prev then
			tab:SetPoint("LEFT", prev, "RIGHT", 2, 0)
		else
			tab:SetPoint("TOPLEFT", 20, -40)
		end
		tab:SetScript("OnClick", function() setMode(key) end)
		w.tabs[key] = tab
		prev = tab
		createView(key, VIEWS[key])
	end

	w.footer = fontString(frame, "GameFontNormalSmall")
	w.footer:SetPoint("BOTTOMLEFT", 26, 18)
	w.footer:SetJustifyH("LEFT")

	-- Turns the ledger's lines in item tooltips on and off (off by default).
	local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	check:SetSize(24, 24)
	check:SetPoint("BOTTOMRIGHT", -150, 12)
	local label = fontString(check, "GameFontHighlightSmall")
	label:SetPoint("LEFT", check, "RIGHT", 2, 0)
	label:SetText("Show in item tooltips")
	check:SetScript("OnClick", function(self) ns.SetTooltip(self:GetChecked()) end)
	check:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Show in item tooltips")
		GameTooltip:AddLine("Adds who has the item, who can craft it and whose recipes use it to item tooltips.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	check:SetScript("OnLeave", GameTooltip_Hide)
	w.tooltipCheck = check
	ns.OnTooltipSetting = function() check:SetChecked(ns.DB().tooltip) end
	ns.OnTooltipSetting()

	frame:SetScript("OnShow", function() ns.Refresh() end)
end

function ns.Open(m, text)
	if not frame then create() end
	m = VIEWS[m] and m or mode or "chars"
	frame:Show()
	if text and text ~= "" and VIEWS[m].box then
		VIEWS[m].box:SetText(text)
	end
	setMode(m)
end

function ns.Toggle(m)
	if frame and frame:IsShown() and (not m or m == mode) then
		frame:Hide()
	else
		ns.Open(m)
	end
end
