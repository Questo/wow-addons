local addonName = ...

-- A ring of slots around the cursor. Each slot holds a game emote (/wave),
-- one of your own macros, or a custom emote line (/e bows deeply). Left-click a
-- slot to do it, right-click to change it.
--
-- Slots are secure macro buttons, so they can run your macros, but that also
-- means the wheel can't open or be changed during combat.

local MIN_SLOTS, MAX_SLOTS = 4, 12
local SLOT_SIZE = 45 -- same as an action bar button
local MACRO_ACCOUNT_MAX = MAX_ACCOUNT_MACROS or 120

-- Emotes offered in the slot menu: label, the command it runs, and an icon
-- (from Interface\Icons; a question mark is shown if the game lacks it).
local EMOTES = {
	{ "Wave", "/wave", "Ability_Warrior_RallyingCry" }, { "Hello", "/hello", "Ability_Warrior_RallyingCry" }, { "Bye", "/bye", "Ability_Warrior_RallyingCry" }, { "Bow", "/bow", "Spell_Holy_PrayerOfFortitude" },
	{ "Salute", "/salute", "Ability_Warrior_BattleShout" }, { "Kneel", "/kneel", "Spell_Holy_PrayerOfFortitude" }, { "Thank", "/thank", "Spell_Holy_HolyBolt" }, { "Cheer", "/cheer", "Achievement_General" },
	{ "Applaud", "/applaud", "Achievement_General" }, { "Laugh", "/laugh", "Spell_Magic_PolymorphChicken" }, { "Dance", "/dance", "Spell_Holy_Restoration" }, { "Sit", "/sit", "Spell_Nature_Sleep" },
	{ "Sleep", "/sleep", "Spell_Nature_Sleep" }, { "Eat", "/eat", "INV_Misc_Food_14" }, { "Drink", "/drink", "INV_Drink_07" }, { "Talk", "/talk", "INV_Misc_Note_01" },
	{ "Nod", "/nod", "INV_Misc_Note_01" }, { "No", "/no", "INV_Misc_Note_01" }, { "Shrug", "/shrug", "INV_Misc_Note_01" }, { "Point", "/point", "INV_Misc_Note_01" },
	{ "Flex", "/flex", "Ability_Warrior_BattleShout" }, { "Roar", "/roar", "Ability_Warrior_BattleShout" }, { "Cry", "/cry", "Spell_Frost_FrostShock" }, { "Shy", "/shy", "INV_ValentinesCandy" },
	{ "Beg", "/beg", "Spell_Holy_PrayerOfFortitude" }, { "Kiss", "/kiss", "INV_ValentinesCandy" }, { "Chicken", "/chicken", "Spell_Magic_PolymorphChicken" }, { "Rude", "/rude", "Ability_Warrior_Disarm" },
}

local DEFAULT_SLOTS = {
	{ kind = "emote", label = "Wave", text = "/wave" },
	{ kind = "emote", label = "Bow", text = "/bow" },
	{ kind = "emote", label = "Cheer", text = "/cheer" },
	{ kind = "emote", label = "Sit", text = "/sit" },
	{ kind = "emote", label = "Dance", text = "/dance" },
	{ kind = "emote", label = "Laugh", text = "/laugh" },
	{ kind = "emote", label = "Salute", text = "/salute" },
	{ kind = "emote", label = "Thank", text = "/thank" },
}

local db
local wheel
local slots = {}
local pendingRefresh = false
local debugClicks = false

local function say(msg)
	print("|cffff9966Emote Wheel:|r " .. msg)
end

local function copy(t)
	local out = {}
	for k, v in pairs(t) do out[k] = type(v) == "table" and copy(v) or v end
	return out
end

-- Slot contents -----------------------------------------------------------------
-- A slot is { kind = "emote" | "custom" | "macro", label, text } where text is
-- the command for emotes and custom lines, or the macro's name for macros.

local function macroInfo(name)
	if not name then return end
	local index = GetMacroIndexByName(name)
	if not index or index == 0 then return end
	local _, icon, body = GetMacroInfo(index)
	return icon, body
end

local QUESTION_MARK = 134400 -- the game's red question mark icon
local CUSTOM_ICON = "Interface\\Icons\\INV_Misc_Note_01"

local emoteIcons = {}
for _, e in ipairs(EMOTES) do emoteIcons[e[2]] = "Interface\\Icons\\" .. e[3] end

local function slotIcon(data)
	if not data then return nil end
	if data.kind == "macro" then return (macroInfo(data.text)) or QUESTION_MARK end
	if data.kind == "emote" then return emoteIcons[data.text] or CUSTOM_ICON end
	return CUSTOM_ICON
end

-- Secure attributes can only change out of combat.
local function applySlot(button)
	local data = db.slots[button.index]
	button.data = data
	if not InCombatLockdown() then
		button:SetAttribute("type1", nil)
		button:SetAttribute("macro1", nil)
		button:SetAttribute("macrotext1", nil)
		if data and data.kind == "macro" then
			button:SetAttribute("type1", "macro")
			button:SetAttribute("macro1", data.text)
		elseif data then
			button:SetAttribute("type1", "macro")
			button:SetAttribute("macrotext1", data.text)
		end
	end
	local icon = slotIcon(data)
	button.icon:SetShown(icon ~= nil)
	if icon then
		-- SetTexture reports false when the file isn't there.
		if button.icon:SetTexture(icon) == false then button.icon:SetTexture(QUESTION_MARK) end
	end
	button.label:SetText(data and (data.label or data.text) or "|cff999999Empty|r")
end

-- Layout ------------------------------------------------------------------------

local function radius()
	return math.max(80, db.count * 12)
end

local function layout()
	if InCombatLockdown() then
		pendingRefresh = true
		return
	end
	local r = radius()
	wheel:SetSize(r * 2 + SLOT_SIZE + 30, r * 2 + SLOT_SIZE + 30)
	for i = 1, MAX_SLOTS do
		local b = slots[i]
		if i <= db.count then
			local angle = math.pi / 2 - (i - 1) * 2 * math.pi / db.count -- first slot at the top, clockwise
			b:ClearAllPoints()
			b:SetPoint("CENTER", wheel, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
			applySlot(b)
			b:Show()
		else
			b:Hide()
		end
	end
end

-- Slot menu ---------------------------------------------------------------------

StaticPopupDialogs["EMOTEWHEEL_CUSTOM"] = {
	text = "Custom emote for slot %s.\n|cff999999Type what your character does, like: bows deeply.\nOr type any slash command, like /wave.|r",
	button1 = OKAY,
	button2 = CANCEL,
	hasEditBox = true,
	maxLetters = 200,
	editBoxWidth = 280,
	OnShow = function(self, index)
		local box = self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox())
		local data = db.slots[index]
		if box then
			box:SetText(data and data.kind == "custom" and data.raw or "")
			box:SetFocus()
		end
	end,
	OnAccept = function(self, index)
		local box = self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox())
		if box then EmoteWheel_SetCustom(index, box:GetText()) end
	end,
	EditBoxOnEnterPressed = function(box, index)
		EmoteWheel_SetCustom(index, box:GetText())
		box:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

local function setSlot(index, data)
	if InCombatLockdown() then
		say("Slots can't be changed during combat.")
		return
	end
	db.slots[index] = data
	applySlot(slots[index])
end

function EmoteWheel_SetCustom(index, text)
	text = strtrim(text or "")
	if text == "" then return end
	local command = text:sub(1, 1) == "/" and text or ("/e " .. text)
	local label = text:gsub("^/e%s+", ""):gsub("^/emote%s+", "")
	if #label > 18 then label = label:sub(1, 16) .. ".." end
	setSlot(index, { kind = "custom", label = label, text = command, raw = text })
end

local function macroList()
	local list = {}
	local global, perChar = GetNumMacros()
	local function add(i)
		local name, icon = GetMacroInfo(i)
		if name then table.insert(list, { name = name, icon = icon }) end
	end
	for i = 1, global or 0 do add(i) end
	for i = MACRO_ACCOUNT_MAX + 1, MACRO_ACCOUNT_MAX + (perChar or 0) do add(i) end
	return list
end

local function openSlotMenu(button)
	if InCombatLockdown() then
		say("Slots can't be changed during combat.")
		return
	end
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		say("Use /ewheel set " .. button.index .. " <emote, /command or macro name> to change this slot.")
		return
	end
	local index = button.index
	MenuUtil.CreateContextMenu(button, function(_, root)
		root:CreateTitle("Slot " .. index)
		local emotes = root:CreateButton("Emote")
		for _, e in ipairs(EMOTES) do
			emotes:CreateButton(e[1], function() setSlot(index, { kind = "emote", label = e[1], text = e[2] }) end)
		end
		local macros = root:CreateButton("Your macros")
		local list = macroList()
		if #list == 0 then
			macros:CreateTitle("You have no macros yet")
		end
		for _, m in ipairs(list) do
			local label = m.icon and ("|T" .. m.icon .. ":16:16|t " .. m.name) or m.name
			macros:CreateButton(label, function() setSlot(index, { kind = "macro", label = m.name, text = m.name }) end)
		end
		root:CreateButton("Custom emote...", function() StaticPopup_Show("EMOTEWHEEL_CUSTOM", index, nil, index) end)
		root:CreateButton("Clear slot", function() setSlot(index, nil) end)
	end)
end

-- Wheel -------------------------------------------------------------------------

-- Looks like an action bar button. Built by hand on the plain secure button:
-- with the game's ActionButtonTemplate (0.1.1) clicks no longer ran the emote
-- or macro, so the template's look is copied with its own art instead.
local function atlasOr(texture, atlas, file)
	if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
		texture:SetAtlas(atlas)
		return true
	end
	texture:SetTexture(file)
	return false
end

local function newSlotButton(i)
	local b = CreateFrame("Button", "EmoteWheelSlot" .. i, wheel, "SecureActionButtonTemplate")
	b:SetSize(SLOT_SIZE, SLOT_SIZE)

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()

	local border = b:CreateTexture(nil, "OVERLAY")
	if atlasOr(border, "UI-HUD-ActionBar-IconFrame", "Interface\\Buttons\\UI-Quickslot2") then
		border:SetAllPoints()
		-- Modern action buttons round off the icon's corners under the frame.
		if b.CreateMaskTexture and C_Texture.GetAtlasInfo("UI-HUD-ActionBar-IconFrame-Mask") then
			local mask = b:CreateMaskTexture()
			mask:SetAtlas("UI-HUD-ActionBar-IconFrame-Mask")
			mask:SetAllPoints(b.icon)
			b.icon:AddMaskTexture(mask)
		end
	else
		border:SetPoint("TOPLEFT", -12, 12)
		border:SetPoint("BOTTOMRIGHT", 12, -12)
	end

	local pushed = b:CreateTexture(nil, "OVERLAY", nil, 1)
	atlasOr(pushed, "UI-HUD-ActionBar-IconFrame-Down", "Interface\\Buttons\\UI-Quickslot-Depress")
	pushed:SetAllPoints()
	b:SetPushedTexture(pushed)

	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	atlasOr(hl, "UI-HUD-ActionBar-IconFrame-Mouseover", "Interface\\Buttons\\ButtonHilight-Square")
	hl:SetAllPoints()
	if not hl:GetAtlas() then hl:SetBlendMode("ADD") end
	return b
end

local function showTooltip(button)
	local data = button.data
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	if not data then
		GameTooltip:SetText("Empty slot")
	elseif data.kind == "macro" then
		local _, body = macroInfo(data.text)
		GameTooltip:SetText(data.text)
		if body then
			GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true)
		else
			GameTooltip:AddLine("Macro not found. Right-click to pick it again.", 1, 0.3, 0.3, true)
		end
	else
		GameTooltip:SetText(data.label)
		GameTooltip:AddLine(data.text, 0.8, 0.8, 0.8, true)
	end
	if db.hint then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Left-click to use", 0, 1, 0)
		GameTooltip:AddLine("Right-click to change", 0, 1, 0)
	end
	GameTooltip:Show()
end

local function createSlot(i)
	local b = newSlotButton(i)
	b.index = i
	b:RegisterForClicks("AnyUp", "AnyDown")

	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.label:SetPoint("TOP", b, "BOTTOM", 0, -3)
	b.label:SetWidth(SLOT_SIZE + 24)
	b.label:SetWordWrap(true)
	b.label:SetMaxLines(2)

	b:SetScript("OnEnter", showTooltip)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:HookScript("OnClick", function(self, button, down)
		if debugClicks then
			say(("slot %d: %s %s, key-down setting %s, type %s, macro %s, text %s"):format(self.index, button,
				down and "down" or "up", tostring(GetCVarBool("ActionButtonUseKeyDown")), tostring(self:GetAttribute("type1")),
				tostring(self:GetAttribute("macro1")), tostring(self:GetAttribute("macrotext1"))))
		end
		if button == "RightButton" then
			if down then return end
			GameTooltip:Hide()
			openSlotMenu(self)
		elseif self.data and down == GetCVarBool("ActionButtonUseKeyDown") then
			-- The secure click just ran; close the wheel after it.
			if not InCombatLockdown() then wheel:Hide() end
		end
	end)
	slots[i] = b
	return b
end

local function createWheel()
	wheel = CreateFrame("Frame", "EmoteWheelFrame", UIParent)
	wheel:SetFrameStrata("DIALOG")
	wheel:SetClampedToScreen(true)
	wheel:EnableMouse(false)
	wheel:Hide()
	tinsert(UISpecialFrames, "EmoteWheelFrame") -- Escape closes it

	for i = 1, MAX_SLOTS do createSlot(i) end
end

function EmoteWheel_Toggle()
	if not db then return end
	if InCombatLockdown() then
		say("The wheel can't open during combat.")
		return
	end
	if wheel:IsShown() then
		wheel:Hide()
		return
	end
	if pendingRefresh then
		pendingRefresh = false
	end
	layout()
	wheel:ClearAllPoints()
	if db.atCursor then
		local x, y = GetCursorPosition()
		local scale = UIParent:GetEffectiveScale()
		wheel:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
	else
		wheel:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	end
	wheel:Show()
end

BINDING_HEADER_EMOTEWHEEL = "Emote Wheel"
BINDING_NAME_EMOTEWHEEL_TOGGLE = "Open/close the emote wheel"

-- Slash command -----------------------------------------------------------------

SLASH_EMOTEWHEEL1 = "/emotewheel"
SLASH_EMOTEWHEEL2 = "/ewheel"
SlashCmdList.EMOTEWHEEL = function(msg)
	msg = strtrim(msg or "")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()
	if cmd == "" then
		EmoteWheel_Toggle()
	elseif cmd == "slots" and tonumber(rest) then
		if InCombatLockdown() then return say("Not during combat.") end
		db.count = math.max(MIN_SLOTS, math.min(MAX_SLOTS, math.floor(tonumber(rest))))
		layout()
		say("The wheel has " .. db.count .. " slots.")
	elseif cmd == "set" then
		local n, what = rest:match("^(%d+)%s+(.+)$")
		n = tonumber(n)
		if not n or n < 1 or n > MAX_SLOTS then
			return say("Use /ewheel set <slot number> <emote, /command or macro name>.")
		end
		if macroInfo(what) then
			setSlot(n, { kind = "macro", label = what, text = what })
		else
			for _, e in ipairs(EMOTES) do
				if e[1]:lower() == what:lower() or e[2] == what:lower() then
					setSlot(n, { kind = "emote", label = e[1], text = e[2] })
					return
				end
			end
			EmoteWheel_SetCustom(n, what)
		end
	elseif cmd == "cursor" then
		db.atCursor = not db.atCursor
		say(db.atCursor and "The wheel opens at your mouse." or "The wheel opens in the middle of the screen.")
	elseif cmd == "hint" then
		db.hint = not db.hint
		say("Click hints in slot tooltips " .. (db.hint and "on." or "off."))
	elseif cmd == "debug" then
		debugClicks = not debugClicks
		say("Click details in chat " .. (debugClicks and "on." or "off."))
	elseif cmd == "reset" then
		if InCombatLockdown() then return say("Not during combat.") end
		db.slots = copy(DEFAULT_SLOTS)
		db.count = 8
		layout()
		say("Slots back to the defaults.")
	else
		say("commands:")
		print("   /ewheel - open or close the wheel (better: bind a key in Options > Keybindings > AddOns)")
		print("   Left-click a slot to use it, right-click to put an emote, one of your macros or a custom line on it.")
		print("   /ewheel slots <4-12> - how many slots the wheel has")
		print("   /ewheel set <slot> <emote, /command or macro name> - fill a slot by typing")
		print("   /ewheel cursor - open at the mouse or in the middle of the screen")
		print("   /ewheel hint - show or hide the click hints in slot tooltips")
		print("   /ewheel reset - back to the default emotes")
	end
end

-- Events ------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("UPDATE_MACROS")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= addonName then return end
		EmoteWheelDB = EmoteWheelDB or {}
		db = EmoteWheelDB
		if not db.slots then db.slots = copy(DEFAULT_SLOTS) end
		db.count = db.count or 8
		if db.atCursor == nil then db.atCursor = true end
		if db.hint == nil then db.hint = true end
	elseif event == "PLAYER_LOGIN" then
		createWheel()
		layout()
		say("loaded. Bind a key under Options > Keybindings > AddOns, or type /ewheel.")
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- Last chance before combat locks the secure slots.
		if wheel and wheel:IsShown() then wheel:Hide() end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pendingRefresh and wheel then
			pendingRefresh = false
			layout()
		end
	elseif event == "UPDATE_MACROS" then
		-- Macro icons or names may have changed.
		if wheel then
			if InCombatLockdown() then pendingRefresh = true else layout() end
		end
	end
end)
