local addonName = ...

-- Lets you star items you want to keep. Starred items get a small star in your
-- bags and a line in their tooltip. At a vendor, a starred item asks before it
-- can be sold, and deleting one is refused until you unstar it.
--
-- Selling uses Blizzard's secure item buttons, which addons can't stop, so at a
-- vendor we lay a plain button over each starred item that catches the click
-- and asks first. Saying yes lifts that cover until you leave the vendor.
--
-- Each keepsake can carry a short story (why you kept it), shown in its tooltip.

local db
local merchantOpen = false
local unlocked = {}         -- itemID -> true, allowed to sell at this vendor visit
local decorated = {}        -- item button -> true once we've added our bits
local events = CreateFrame("Frame")

local function say(msg)
	print("|cffffd200Keepsakes:|r " .. msg)
end

local function isStarred(itemID)
	return itemID and db.stars[itemID] or false
end

local function itemLink(itemID)
	return select(2, C_Item.GetItemInfo(itemID)) or ("item " .. itemID)
end

-- Bag buttons -----------------------------------------------------------------

local function bagFrames()
	local frames = {}
	if ContainerFrameCombinedBags then table.insert(frames, ContainerFrameCombinedBags) end
	for i = 1, 13 do
		local f = _G["ContainerFrame" .. i]
		if f then table.insert(frames, f) end
	end
	return frames
end

local function eachButton(fn)
	for _, frame in ipairs(bagFrames()) do
		if frame:IsShown() then
			if frame.EnumerateValidItems then
				for _, button in frame:EnumerateValidItems() do fn(button) end
			elseif frame.Items then
				for _, button in ipairs(frame.Items) do
					if button:IsShown() then fn(button) end
				end
			end
		end
	end
end

local function buttonItemID(button)
	local bag = button.GetBagID and button:GetBagID()
	local slot = button:GetID()
	if not bag or not slot then return nil end
	return C_Container.GetContainerItemID(bag, slot)
end

local STAR_ATLASES = { "PetJournal-FavoritesIcon", "auctionhouse-icon-favorite" }

local function makeStar(button)
	local star = button:CreateTexture(nil, "OVERLAY", nil, 7)
	star:SetSize(16, 16)
	star:SetPoint("TOPLEFT", button, "TOPLEFT", -2, 2)
	local ok = false
	for _, atlas in ipairs(STAR_ATLASES) do
		if C_Texture.GetAtlasInfo(atlas) then
			star:SetAtlas(atlas)
			ok = true
			break
		end
	end
	if not ok then
		star:SetColorTexture(1, 0.82, 0, 0.9)
		star:SetSize(8, 8)
	end
	star:Hide()
	return star
end

-- Stories ---------------------------------------------------------------------

local function popupEditBox(dialog)
	return dialog.editBox or dialog.EditBox or (dialog.GetEditBox and dialog:GetEditBox())
end

local function saveStory(itemID, text)
	text = strtrim(text or "")
	db.stories[itemID] = text ~= "" and text or nil
	if text ~= "" then say("Story kept for " .. itemLink(itemID) .. ".") end
end

StaticPopupDialogs["KEEPSAKES_STORY"] = {
	text = "Why keep %s?\n|cff999999A line for its tooltip, or leave it empty.|r",
	button1 = OKAY,
	button2 = CANCEL,
	hasEditBox = true,
	maxLetters = 120,
	editBoxWidth = 260,
	OnShow = function(self, itemID)
		local box = popupEditBox(self)
		if box then
			box:SetText(db.stories[itemID] or "")
			box:HighlightText()
			box:SetFocus()
		end
	end,
	OnAccept = function(self, itemID)
		local box = popupEditBox(self)
		if box then saveStory(itemID, box:GetText()) end
	end,
	EditBoxOnEnterPressed = function(box, itemID)
		saveStory(itemID, box:GetText())
		box:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

local function askStory(itemID)
	StaticPopup_Show("KEEPSAKES_STORY", itemLink(itemID), nil, itemID)
end

StaticPopupDialogs["KEEPSAKES_SELL"] = {
	text = "%s is a keepsake.\nSell it anyway?",
	button1 = YES,
	button2 = NO,
	OnAccept = function(_, itemID)
		unlocked[itemID] = true
		Keepsakes_Refresh()
		say(itemLink(itemID) .. " can be sold until you leave this vendor. Right-click it again to sell.")
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

local function makeCover(button)
	local cover = CreateFrame("Button", nil, button)
	cover:SetAllPoints(button)
	cover:SetFrameLevel(button:GetFrameLevel() + 10)
	cover:RegisterForClicks("AnyUp")
	cover:RegisterForDrag("LeftButton")
	local tint = cover:CreateTexture(nil, "OVERLAY")
	tint:SetAllPoints()
	tint:SetColorTexture(1, 0.82, 0, 0.12)
	local function ask()
		local id = buttonItemID(button)
		if id then
			StaticPopup_Show("KEEPSAKES_SELL", itemLink(id), nil, id)
		end
	end
	cover:SetScript("OnClick", ask)
	cover:SetScript("OnDragStart", ask)
	cover:SetScript("OnEnter", function()
		local onEnter = button:GetScript("OnEnter")
		if onEnter then onEnter(button) end
	end)
	cover:SetScript("OnLeave", function()
		local onLeave = button:GetScript("OnLeave")
		if onLeave then onLeave(button) else GameTooltip:Hide() end
	end)
	cover:Hide()
	return cover
end

local function onButtonClick(button, mouse)
	if mouse ~= "LeftButton" or not IsAltKeyDown() then return end
	local id = buttonItemID(button)
	if not id then return end
	-- Alt-click may have picked the item up; put it back.
	local kind, cursorID = GetCursorInfo()
	if kind == "item" and cursorID == id then ClearCursor() end
	if IsShiftKeyDown() and isStarred(id) then
		askStory(id) -- Alt-Shift-click: write or change the story
	else
		Keepsakes_Toggle(id)
	end
end

local function decorate(button)
	if decorated[button] then return end
	if InCombatLockdown() then return end
	decorated[button] = true
	button.KeepsakeStar = makeStar(button)
	button.KeepsakeCover = makeCover(button)
	button:HookScript("OnClick", onButtonClick)
end

local function update(button)
	decorate(button)
	if not decorated[button] then return end
	local id = buttonItemID(button)
	local starred = isStarred(id)
	button.KeepsakeStar:SetShown(starred)
	local cover = starred and merchantOpen and not unlocked[id]
	if button.KeepsakeCover:IsShown() ~= (cover and true or false) then
		button.KeepsakeCover:SetShown(cover)
	end
end

function Keepsakes_Refresh()
	if not db then return end
	eachButton(update)
end

function Keepsakes_Toggle(itemID)
	if db.stars[itemID] then
		db.stars[itemID] = nil
		db.stories[itemID] = nil
		say(itemLink(itemID) .. " is no longer a keepsake.")
	else
		db.stars[itemID] = true
		say(itemLink(itemID) .. " is now a keepsake.")
		askStory(itemID)
	end
	Keepsakes_Refresh()
end

local function hookFrames()
	for _, frame in ipairs(bagFrames()) do
		if not frame.KeepsakesHooked then
			frame.KeepsakesHooked = true
			frame:HookScript("OnShow", function() C_Timer.After(0, Keepsakes_Refresh) end)
			if frame.UpdateItems then
				hooksecurefunc(frame, "UpdateItems", Keepsakes_Refresh)
			end
		end
	end
end

-- Deleting --------------------------------------------------------------------

local DELETE_POPUPS = { "DELETE_ITEM", "DELETE_GOOD_ITEM", "DELETE_QUEST_ITEM", "DELETE_GOOD_QUEST_ITEM" }

local function onDeleteConfirm()
	local kind, id = GetCursorInfo()
	if kind ~= "item" or not isStarred(id) then return end
	-- Blizzard shows its delete box on the same event; close it once it's up.
	C_Timer.After(0, function()
		for _, which in ipairs(DELETE_POPUPS) do StaticPopup_Hide(which) end
		ClearCursor()
		say(itemLink(id) .. " is a keepsake, so I put it back. Alt-click it in your bags to unstar it if you really want to delete it.")
	end)
end

-- Tooltip ---------------------------------------------------------------------

local function addToTooltip(tooltip, data)
	if not db then return end
	local id = data and data.id
	if not id or (issecretvalue and issecretvalue(id)) then return end
	if db.stars[id] then
		tooltip:AddLine("Keepsake", 1, 0.82, 0)
		local story = db.stories[id]
		if story then tooltip:AddLine("\"" .. story .. "\"", 0.9, 0.85, 0.7, true) end
	end
end

-- Slash command ---------------------------------------------------------------

SLASH_KEEPSAKES1 = "/keepsakes"
SLASH_KEEPSAKES2 = "/keep"
SlashCmdList.KEEPSAKES = function(msg)
	msg = strtrim(msg or "")
	if msg == "" or msg:lower() == "help" then
		say("Alt-click an item in your bags to star or unstar it.")
		print("   /keep <item> stars or unstars an item (shift-click a link in).")
		print("   Alt-Shift-click a keepsake to write or change its story.")
		print("   /keep story <item> writes the story for a keepsake.")
		print("   /keep list shows your keepsakes.")
		return
	end
	local sub, rest = msg:match("^(%S+)%s+(.+)$")
	if sub and sub:lower() == "story" then
		local id = C_Item.GetItemInfoInstant(rest)
		if not id then
			say("I don't know that item. Try shift-clicking it into the command.")
		elseif not isStarred(id) then
			say(itemLink(id) .. " isn't a keepsake yet. Alt-click it in your bags first.")
		else
			askStory(id)
		end
		return
	end
	if msg:lower() == "list" then
		local n = 0
		for id in pairs(db.stars) do
			n = n + 1
			local story = db.stories[id]
			print("   " .. itemLink(id) .. (story and ("  |cffe6d9b3\"" .. story .. "\"|r") or ""))
		end
		say(n == 0 and "You have no keepsakes yet." or (n .. " keepsakes."))
		return
	end
	local id = C_Item.GetItemInfoInstant(msg)
	if id then
		Keepsakes_Toggle(id)
	else
		say("I don't know that item. Try shift-clicking it into the command.")
	end
end

-- Events ----------------------------------------------------------------------

events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		KeepsakesDB = KeepsakesDB or {}
		db = KeepsakesDB
		db.stars = db.stars or {}
		db.stories = db.stories or {}
		hookFrames()
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, addToTooltip)
		events:RegisterEvent("BAG_UPDATE_DELAYED")
		events:RegisterEvent("MERCHANT_SHOW")
		events:RegisterEvent("MERCHANT_CLOSED")
		events:RegisterEvent("DELETE_ITEM_CONFIRM")
		events:RegisterEvent("PLAYER_REGEN_ENABLED")
		say("loaded. Alt-click an item in your bags to keep it safe.")
	elseif event == "MERCHANT_SHOW" then
		merchantOpen = true
		Keepsakes_Refresh()
	elseif event == "MERCHANT_CLOSED" then
		merchantOpen = false
		wipe(unlocked)
		StaticPopup_Hide("KEEPSAKES_SELL")
		Keepsakes_Refresh()
	elseif event == "DELETE_ITEM_CONFIRM" then
		onDeleteConfirm()
	else
		hookFrames()
		Keepsakes_Refresh()
	end
end)
events:RegisterEvent("PLAYER_LOGIN")
