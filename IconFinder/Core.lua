local addonName = ...

-- Adds a search panel next to the macro icon picker (and the equipment set
-- icon picker). The game doesn't tell addons the names of its icon files, so we
-- search by name instead: every spell in the game (built once per session in
-- the background), the items you carry, any item you type the exact name of,
-- and plain numbers as icon, spell or item IDs.
-- A row above the results shows icons you pinned (right-click any icon) and the
-- ones you picked most recently.

local MAX_SPELL_ID = 500000
local COLS, ROWS, SIZE, GAP = 8, 8, 34, 3
local MAX_RESULTS = COLS * ROWS
local QUICK = COLS -- slots in the pinned and recent row
local RESULTS_TOP = -60 - SIZE - 24

local db -- IconFinderDB: pinned = { { icon, name } }, recent = { { icon, name } }

local function say(msg)
	print("|cff66ccffIcon Finder:|r " .. msg)
end

-- Spell cache -----------------------------------------------------------------

local cacheNames, cacheIcons = {}, {}   -- parallel lists, one entry per unique icon
local cacheSeen = {}                     -- icon -> true
local scanned, scanDone, scanning = 0, false, false
local onScanProgress                     -- set by the panel

local function scanStep()
	local stop = debugprofilestop() + 8 -- milliseconds per frame
	while scanned < MAX_SPELL_ID and debugprofilestop() < stop do
		for id = scanned + 1, math.min(scanned + 200, MAX_SPELL_ID) do
			local name = C_Spell.GetSpellName(id)
			if name and name ~= "" then
				local icon = C_Spell.GetSpellTexture(id)
				if icon and not cacheSeen[icon] then
					cacheSeen[icon] = true
					table.insert(cacheNames, name:lower())
					table.insert(cacheIcons, { icon = icon, name = name, spellID = id })
				end
			end
		end
		scanned = math.min(scanned + 200, MAX_SPELL_ID)
	end
	if scanned >= MAX_SPELL_ID then
		scanDone, scanning = true, false
		if onScanProgress then onScanProgress() end
		return
	end
	if onScanProgress then onScanProgress() end
	C_Timer.After(0, scanStep)
end

local function startScan()
	if scanning or scanDone then return end
	scanning = true
	C_Timer.After(0, scanStep)
end

-- Searching -------------------------------------------------------------------

local function search(text)
	local results, seen = {}, {}
	local function add(icon, name, kind)
		if icon and not seen[icon] and #results < MAX_RESULTS then
			seen[icon] = true
			table.insert(results, { icon = icon, name = name, kind = kind })
		end
	end
	text = strtrim(text or "")
	if text == "" then return results end

	local n = tonumber(text)
	if n then
		add(n, "Icon ID " .. n, "icon")
		local spellIcon = C_Spell.GetSpellTexture(n)
		if spellIcon then add(spellIcon, C_Spell.GetSpellName(n) or ("Spell " .. n), "spell") end
		local itemIcon = C_Item.GetItemIconByID(n)
		if itemIcon then add(itemIcon, C_Item.GetItemNameByID(n) or ("Item " .. n), "item") end
		return results
	end

	local q = text:lower()

	-- Exact item name (works for items the game has seen this session).
	local _, _, _, _, exactIcon = C_Item.GetItemInfoInstant(text)
	if exactIcon then add(exactIcon, text, "item") end

	-- Items you're carrying or wearing.
	for bag = 0, 5 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID then
				local name = C_Item.GetItemNameByID(info.itemID)
				if name and name:lower():find(q, 1, true) then add(info.iconFileID, name, "item") end
			end
		end
	end
	for slot = 1, 19 do
		local id = GetInventoryItemID("player", slot)
		local name = id and C_Item.GetItemNameByID(id)
		if name and name:lower():find(q, 1, true) then add(GetInventoryItemTexture("player", slot), name, "item") end
	end

	-- Every spell: names that start with the text first, then the rest.
	local later = {}
	for i, name in ipairs(cacheNames) do
		local at = name:find(q, 1, true)
		if at == 1 then
			local e = cacheIcons[i]
			add(e.icon, e.name, "spell")
			if #results >= MAX_RESULTS then break end
		elseif at then
			table.insert(later, i)
		end
	end
	for _, i in ipairs(later) do
		if #results >= MAX_RESULTS then break end
		local e = cacheIcons[i]
		add(e.icon, e.name, "spell")
	end
	return results
end

-- Pinned and recent -------------------------------------------------------------

local function indexOf(list, icon)
	for i, e in ipairs(list) do
		if e.icon == icon then return i end
	end
end

local function remember(icon, name)
	if not db or not icon then return end
	local i = indexOf(db.recent, icon)
	if i then
		name = name or db.recent[i].name
		table.remove(db.recent, i)
	end
	table.insert(db.recent, 1, { icon = icon, name = name or ("Icon ID " .. tostring(icon)) })
	while #db.recent > QUICK do table.remove(db.recent) end
end

local function togglePin(icon, name)
	if not db or not icon then return end
	local i = indexOf(db.pinned, icon)
	if i then
		table.remove(db.pinned, i)
		say((name or "Icon") .. " unpinned.")
	elseif #db.pinned >= QUICK then
		say("You can pin " .. QUICK .. " icons. Right-click a pinned one to unpin it first.")
	else
		table.insert(db.pinned, { icon = icon, name = name or ("Icon ID " .. tostring(icon)) })
		say((name or "Icon") .. " pinned.")
	end
end

-- Pinned icons first, then recent ones that aren't pinned.
local function quickList()
	local list = {}
	if not db then return list end
	for _, e in ipairs(db.pinned) do table.insert(list, { icon = e.icon, name = e.name, pinned = true }) end
	for _, e in ipairs(db.recent) do
		if #list >= QUICK then break end
		if not indexOf(db.pinned, e.icon) then table.insert(list, { icon = e.icon, name = e.name }) end
	end
	return list
end

-- Picking ---------------------------------------------------------------------

local function choose(popup, icon, name)
	local area = popup.BorderBox and popup.BorderBox.SelectedIconArea
	local selected = area and area.SelectedIconButton
	if not (selected and selected.SetIconTexture) then
		say("Couldn't set the icon on this window. Its icon ID is " .. tostring(icon) .. ".")
		return
	end
	selected:SetIconTexture(icon)
	popup.iconFinderPicked = { icon = icon, name = name }
	-- Keep Blizzard's own grid in step when the icon is in its list.
	local provider = popup.iconDataProvider
	if provider and provider.GetIndexOfIcon and popup.IconSelector then
		local index = provider:GetIndexOfIcon(icon)
		if index and popup.IconSelector.SetSelectedIndex then
			popup.IconSelector:SetSelectedIndex(index)
			if popup.IconSelector.ScrollToSelectedIndex then popup.IconSelector:ScrollToSelectedIndex() end
		end
	end
end

-- Panel -----------------------------------------------------------------------

local function createPanel(popup)
	local panel = CreateFrame("Frame", nil, popup, "BackdropTemplate")
	panel:SetSize(COLS * (SIZE + GAP) + 28, ROWS * (SIZE + GAP) + 92 - RESULTS_TOP - 60)
	panel:SetPoint("TOPLEFT", popup, "TOPRIGHT", 2, 0)
	panel:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		edgeSize = 24,
		insets = { left = 6, right = 6, top = 6, bottom = 6 },
	})
	panel:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
	panel:EnableMouse(true)

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 16, -14)
	title:SetText("Search icons")

	local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
	box:SetSize(COLS * (SIZE + GAP) - 6, 20)
	box:SetPoint("TOPLEFT", 20, -32)
	box:SetAutoFocus(false)
	local hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("LEFT", 2, 0)
	hint:SetText("Spell or item name, or an ID")

	local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	status:SetPoint("BOTTOMLEFT", 16, 14)
	status:SetPoint("BOTTOMRIGHT", -16, 14)
	status:SetJustifyH("LEFT")
	status:SetWordWrap(false)

	local refresh -- defined below

	local function iconButton(x, y)
		local b = CreateFrame("Button", nil, panel)
		b:SetSize(SIZE, SIZE)
		b:SetPoint("TOPLEFT", x, y)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b.tex = b:CreateTexture(nil, "ARTWORK")
		b.tex:SetAllPoints()
		b.pin = b:CreateTexture(nil, "OVERLAY")
		b.pin:SetSize(8, 8)
		b.pin:SetPoint("TOPRIGHT", -2, -2)
		b.pin:SetColorTexture(1, 0.82, 0, 1)
		b.pin:Hide()
		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		b:SetScript("OnEnter", function(self)
			local pinned = db and indexOf(db.pinned, self.result.icon)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(self.result.name, 1, 1, 1)
			GameTooltip:AddLine("Icon ID " .. tostring(self.result.icon), 0.6, 0.6, 0.6)
			GameTooltip:AddLine("Click to use this icon", 0.4, 0.8, 1)
			GameTooltip:AddLine(pinned and "Right-click to unpin" or "Right-click to pin", 0.4, 0.8, 1)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", GameTooltip_Hide)
		b:SetScript("OnClick", function(self, mouse)
			if mouse == "RightButton" then
				togglePin(self.result.icon, self.result.name)
				refresh()
				if self:IsMouseOver() then self:GetScript("OnEnter")(self) end
			else
				choose(popup, self.result.icon, self.result.name)
			end
		end)
		b:Hide()
		return b
	end

	local quickLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	quickLabel:SetPoint("TOPLEFT", 18, -60)
	quickLabel:SetText("Pinned and recent")
	local quickEmpty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	quickEmpty:SetPoint("TOPLEFT", 18, -60 - 16 - SIZE / 2 + 6)
	quickEmpty:SetText("Icons you pick or right-click to pin show up here.")
	local quick = {}
	for i = 1, QUICK do
		quick[i] = iconButton(16 + (i - 1) * (SIZE + GAP), -60 - 14)
	end

	local buttons = {}
	for i = 1, MAX_RESULTS do
		local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
		buttons[i] = iconButton(16 + col * (SIZE + GAP), RESULTS_TOP - row * (SIZE + GAP))
	end

	refresh = function()
		local function fill(list, results)
			for i, b in ipairs(list) do
				local r = results[i]
				b.result = r
				if r then
					b.tex:SetTexture(r.icon)
					b.pin:SetShown(db and indexOf(db.pinned, r.icon) and true or false)
				end
				b:SetShown(r ~= nil)
			end
		end
		local quickResults = quickList()
		fill(quick, quickResults)
		quickEmpty:SetShown(#quickResults == 0)
		local text = box:GetText()
		local results = search(text)
		fill(buttons, results)
		if not scanDone then
			status:SetText(("Reading spell names... %d%%"):format(scanned / MAX_SPELL_ID * 100))
		elseif strtrim(text) == "" then
			status:SetText("Type to search " .. #cacheIcons .. " spell icons and your items.")
		elseif #results == 0 then
			status:SetText("No icons found.")
		elseif #results >= MAX_RESULTS then
			status:SetText("Showing the first " .. MAX_RESULTS .. ". Type more to narrow it down.")
		else
			status:SetText(#results .. " icons found.")
		end
	end

	local pending = false
	box:SetScript("OnTextChanged", function(self)
		hint:SetShown(self:GetText() == "")
		refresh()
	end)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	box:SetScript("OnEnterPressed", box.ClearFocus)

	-- While spells are still being read, refresh now and then so results fill in.
	panel.onScanProgress = function()
		if pending or not panel:IsVisible() then return end
		pending = true
		C_Timer.After(0.5, function()
			pending = false
			if panel:IsVisible() then refresh() end
		end)
	end

	panel:SetScript("OnShow", function()
		onScanProgress = panel.onScanProgress
		startScan()
		refresh()
	end)
	onScanProgress = panel.onScanProgress
	startScan()
	refresh()
	return panel
end

local attached = {}

-- The icon shown as selected in the popup, whichever way it was picked.
local function selectedIcon(popup)
	local area = popup.BorderBox and popup.BorderBox.SelectedIconArea
	local selected = area and area.SelectedIconButton
	if not selected then return end
	local ok, icon = pcall(function()
		if selected.GetIconTexture then return selected:GetIconTexture() end
		return selected.Icon and selected.Icon:GetTexture()
	end)
	return ok and icon or nil
end

local function attach(popupName)
	local popup = _G[popupName]
	if not popup or attached[popup] then return end
	attached[popup] = createPanel(popup)
	popup:HookScript("OnShow", function() popup.iconFinderPicked = nil end)
	-- When the macro or set is saved with Okay, remember its icon as recent.
	local okay = popup.BorderBox and popup.BorderBox.OkayButton
	if okay then
		okay:HookScript("OnClick", function()
			local icon = selectedIcon(popup)
			local picked = popup.iconFinderPicked
			if not icon and picked then icon = picked.icon end
			local name = picked and picked.icon == icon and picked.name or nil
			if icon and icon ~= 134400 then remember(icon, name) end -- 134400 is the red question mark
		end)
	end
end

-- Events ----------------------------------------------------------------------

local POPUPS = {
	Blizzard_MacroUI = "MacroPopupFrame",
}

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" and name == addonName then
		IconFinderDB = IconFinderDB or {}
		db = IconFinderDB
		db.pinned = db.pinned or {}
		db.recent = db.recent or {}
		return
	end
	if event == "PLAYER_LOGIN" then
		for addon, popup in pairs(POPUPS) do
			if C_AddOns.IsAddOnLoaded(addon) then attach(popup) end
		end
		-- The equipment set popup lives with the character pane.
		if GearManagerPopupFrame then
			GearManagerPopupFrame:HookScript("OnShow", function() attach("GearManagerPopupFrame") end)
		end
	elseif POPUPS[name] then
		attach(POPUPS[name])
	end
end)

SLASH_ICONFINDER1 = "/iconfinder"
SlashCmdList.ICONFINDER = function()
	say("Open a macro and click Change to pick its icon. The search panel sits to the right of the icon list.")
	print("   Right-click any icon in the panel to pin it to the top row. Icons you used last show there too.")
	print("   Tip: the red question mark icon with #showtooltip at the top of a macro shows the icon of whatever the macro casts.")
end
