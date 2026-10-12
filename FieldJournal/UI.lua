local _, ns = ...

-- The journal window: a parchment page with section tabs, a list of entries
-- on the left and the open entry on the right. Plain Lua frames, no XML.

local INK = { 0.20, 0.12, 0.05 }
local FAINT = { 0.42, 0.32, 0.20 }
local WIDTH, HEIGHT = 700, 480
local LIST_W, ROW_H = 176, 34
local PAGE_X = 240

local frame
local mode = "notes"
local current = {}  -- section key -> open entry
local filter = ""
local rows = {}
local w = {}        -- widgets
local activeFolder  -- folder id new notes go into (last folder clicked or note opened)
local moveMenu, folderMenu, askRename, showMeta -- defined further down

-- Sections ------------------------------------------------------------------
-- Each section says where its entries live and how to show them.
--   buttons: shown under the list. fn returns entry, message; focus is
--            "title" or "end" (cursor at the end of the text). "delete" tears
--            out the open entry.
--   action:  the button at the top right of the page, if any.
--   action2: a second page button, under the first (notes: the folder).

local function byNewest(field)
	return function(a, b) return (a[field] or 0) > (b[field] or 0) end
end

local ORDER = { "notes", "encounters", "places", "quests", "chronicle" }
local SECTIONS = {
	notes = {
		label = "Notes", titleField = "title", sort = byNewest("created"),
		sub = function(e) return date("%d %b %Y", e.created) end,
		meta = function(e)
			local text = "Written " .. ns.Stamp(e.created)
			if (e.modified or 0) - (e.created or 0) > 60 then text = text .. ", last touched " .. ns.Stamp(e.modified) end
			return text
		end,
		empty = "No pages yet.",
		hint = "Pick a page, or start a new one.",
		buttons = {
			{ text = "New", width = 60, fn = function() return ns.AddNote(nil, nil, activeFolder) end, focus = "title",
				tip = "Start a new page, in the folder you have open." },
			{ text = "Folder", width = 64, tip = "Start a new folder. Right-click a folder to rename or remove it.",
				fn = function()
					local f = ns.NewFolder()
					activeFolder = f.id
					ns.RefreshList()
					askRename(f)
				end },
			{ text = "Tear out", width = 72, delete = true },
		},
		action = {
			text = function(e) return ns.db.pinned == e.id and "Unpin" or "Pin" end,
			tip = "Keep this page on screen as a small scrap of paper. It tucks itself away in combat.",
			click = function(e) ns.TogglePin(e) end,
		},
		action2 = {
			text = function(e)
				local f = ns.FolderById(e.folder)
				local name = f and f.name or "No folder"
				return #name > 13 and (name:sub(1, 12) .. "...") or name
			end,
			tip = "Move this page into a folder. You can also right-click a page in the list.",
			click = function(e, owner) moveMenu(e, owner) end,
		},
	},
	encounters = {
		label = "Encounters", titleField = "name", sort = byNewest("lastMet"),
		sub = function(e) return e.kind .. " - " .. (e.zone or "") end,
		meta = function(e) return ns.DescribeEncounter(e) end,
		empty = "No one met yet.",
		hint = "Target someone and press Add target,\nor right-click a name in chat.",
		buttons = {
			{ text = "Add target", width = 86, fn = ns.CaptureTarget, focus = "end",
				tip = "Write about who or what you have targeted. With no target, logs a boss you fought in the last few minutes." },
			{ text = "New", width = 52, fn = ns.NewEncounter, focus = "title" },
			{ text = "Tear out", width = 58, delete = true },
		},
		action = {
			text = function(e) return e.kind end,
			tip = "Click to change what kind of encounter this is.",
			click = function(e)
				for i, k in ipairs(ns.kinds) do
					if k == e.kind then
						e.kind = ns.kinds[i % #ns.kinds + 1]
						return
					end
				end
				e.kind = ns.kinds[1]
			end,
		},
	},
	places = {
		label = "Places", titleField = "name", sort = byNewest("created"),
		sub = function(e) return e.zone or "" end,
		meta = function(e) return ns.DescribePlace(e) end,
		empty = "No places marked yet.",
		hint = "Stand somewhere worth remembering\nand press Mark this spot.",
		buttons = {
			{ text = "Mark this spot", width = 124, fn = ns.MarkPlace, focus = "title" },
			{ text = "Tear out", width = 72, delete = true },
		},
		action = {
			text = function() return "Waypoint" end,
			tip = "Put a waypoint on your map pointing here.",
			click = function(e) ns.SetWaypoint(e) end,
		},
	},
	quests = {
		label = "Quests", titleField = "title", sort = byNewest("created"),
		sub = function(e) return e.completed and "Completed" or (e.zone or "") end,
		meta = function(e) return ns.DescribeQuest(e) end,
		empty = "No quest thoughts yet.",
		hint = "Open a quest in your quest log (or follow one)\nand press This quest.",
		buttons = {
			{ text = "This quest", width = 124, fn = function() return ns.MuseQuest(ns.CurrentQuestID()) end, focus = "end",
				tip = "Write about the quest open in your quest log, at a quest giver, or the one you are following." },
			{ text = "Tear out", width = 72, delete = true },
		},
		action = {
			text = function() return "Show quest" end,
			tip = "Open this quest in your quest log.",
			click = function(e) ns.ShowQuest(e) end,
		},
	},
	chronicle = {
		label = "Chronicle", titleField = "title", sort = function(a, b) return a.day > b.day end,
		sub = function(e)
			local _, lines = (e.body or ""):gsub("\n", "")
			return lines == 1 and "1 line" or (lines .. " lines")
		end,
		meta = function()
			return "The journal writes your milestones here as they happen.\nAdd your own thoughts anywhere."
				.. (ns.db.chronicleOn and "" or " (Automatic writing is off: /fj auto)")
		end,
		empty = "Nothing chronicled yet.",
		hint = "Your days will be written here\nas you adventure.",
		buttons = {
			{ text = "Today", width = 124, fn = ns.TodayPage, focus = "end" },
			{ text = "Tear out", width = 72, delete = true },
		},
	},
}

-- Helpers -------------------------------------------------------------------

local function font(name, fallback)
	return _G[name] or _G[fallback] or GameFontNormal
end

local function ink(fs, color)
	color = color or INK
	fs:SetTextColor(color[1], color[2], color[3])
end

local function section() return SECTIONS[mode] end
local function list() return ns.db[mode] end
local function titleOf(e) return e[section().titleField] end

local function matchesIn(e, key)
	if filter == "" then return true end
	local text = (e[SECTIONS[key].titleField] or "") .. "\n" .. (e.body or "")
	local folder = key == "notes" and ns.FolderById(e.folder)
	if folder then text = text .. "\n" .. folder.name end
	text = text:lower()
	return text:find(filter, 1, true) ~= nil
end

local function matches(e) return matchesIn(e, mode) end

local function sorted()
	local out = {}
	for _, e in ipairs(list()) do
		if matches(e) then table.insert(out, e) end
	end
	table.sort(out, section().sort)
	return out
end

local function clearFocus()
	if not w.title then return end -- window not built yet
	w.title:ClearFocus()
	w.body:ClearFocus()
	w.search:ClearFocus()
end

local function tooltip(widget, title, text)
	widget:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(title)
		if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
		GameTooltip:Show()
	end)
	widget:SetScript("OnLeave", GameTooltip_Hide)
end

-- List ----------------------------------------------------------------------

local FOLDER_H = 24

local function onRowClick(self, button)
	clearFocus()
	if self.header then return end
	if self.other then
		-- A match in another section: go there, keeping the search.
		ns.SetMode(self.other, true)
		ns.Select(self.entry)
		return
	end
	if self.folder then
		if button == "RightButton" then
			folderMenu(self.folder, self)
		else
			self.folder.collapsed = not self.folder.collapsed
			activeFolder = self.folder.id
			ns.RefreshList()
		end
	elseif button == "RightButton" and mode == "notes" then
		ns.Select(self.entry)
		moveMenu(self.entry, self)
	else
		ns.Select(self.entry)
	end
end

local function getRow(i)
	if rows[i] then return rows[i] end
	local row = CreateFrame("Button", nil, w.listChild)
	row:SetWidth(LIST_W)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(0.55, 0.38, 0.12, 0.15)

	row.sel = row:CreateTexture(nil, "BACKGROUND")
	row.sel:SetAllPoints()
	row.sel:SetColorTexture(0.55, 0.38, 0.12, 0.28)
	row.sel:Hide()

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(14, 14)
	row.icon:SetPoint("LEFT", 4, 0)

	row.text = row:CreateFontString(nil, "OVERLAY")
	row.text:SetFontObject(font("GameFontHighlight", "GameFontNormal"))
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	ink(row.text)

	row.sub = row:CreateFontString(nil, "OVERLAY")
	row.sub:SetFontObject(font("GameFontHighlightSmall", "GameFontNormalSmall"))
	row.sub:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -2)
	row.sub:SetPoint("RIGHT", -4, 0)
	row.sub:SetJustifyH("LEFT")
	row.sub:SetWordWrap(false)
	ink(row.sub, FAINT)

	row:SetScript("OnClick", onRowClick)
	rows[i] = row
	return row
end

local function sortedFolders()
	local out = {}
	for _, f in ipairs(ns.db.folders) do table.insert(out, f) end
	table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
	return out
end

-- While searching, matches from the other sections follow under a heading,
-- as { entry = e, other = sectionKey }.
local function addOthers(items)
	if filter == "" then return end
	local first = true
	for _, key in ipairs(ORDER) do
		if key ~= mode then
			local found = {}
			for _, e in ipairs(ns.db[key]) do
				if matchesIn(e, key) then table.insert(found, e) end
			end
			table.sort(found, SECTIONS[key].sort)
			for _, e in ipairs(found) do
				if first then
					table.insert(items, { header = "In other sections" })
					first = false
				end
				table.insert(items, { entry = e, other = key })
			end
		end
	end
end

-- What the list shows: { entry = e, indent = bool } or { folder = f, count = n }.
-- Notes are grouped under their folders, loose pages after them. While
-- searching, folders open up and empty ones are left out.
local function listItems()
	local entries = sorted()
	local items = {}
	if mode ~= "notes" then
		for _, e in ipairs(entries) do table.insert(items, { entry = e }) end
		addOthers(items)
		return items, #entries
	end
	local byFolder, loose = {}, {}
	for _, e in ipairs(entries) do
		if ns.FolderById(e.folder) then
			byFolder[e.folder] = byFolder[e.folder] or {}
			table.insert(byFolder[e.folder], e)
		else
			table.insert(loose, e)
		end
	end
	for _, f in ipairs(sortedFolders()) do
		local notes = byFolder[f.id] or {}
		if filter == "" or #notes > 0 then
			table.insert(items, { folder = f, count = #notes })
			if not f.collapsed or filter ~= "" then
				for _, e in ipairs(notes) do table.insert(items, { entry = e, indent = true }) end
			end
		end
	end
	for _, e in ipairs(loose) do table.insert(items, { entry = e }) end
	addOthers(items)
	return items, #entries
end

function ns.RefreshList()
	if not frame then return end
	local s = section()
	local items, matched = listItems()
	local y = 0
	for i, item in ipairs(items) do
		local row = getRow(i)
		row.entry, row.folder, row.other, row.header = item.entry, item.folder, item.other, item.header
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -y)
		row.text:ClearAllPoints()
		ink(row.text)
		if item.header then
			row:SetHeight(FOLDER_H)
			row.icon:Hide()
			row.text:SetPoint("LEFT", 6, -2)
			row.text:SetPoint("RIGHT", -4, 0)
			row.text:SetText(item.header)
			ink(row.text, FAINT)
			row.sub:Hide()
			row.sel:Hide()
		elseif item.other then
			local e, other = item.entry, SECTIONS[item.other]
			row:SetHeight(ROW_H)
			row.icon:Hide()
			row.text:SetPoint("TOPLEFT", 6, -4)
			row.text:SetPoint("RIGHT", -4, 0)
			local title = e[other.titleField]
			row.text:SetText((title and title ~= "") and title or "(untitled)")
			row.sub:SetText(other.label .. " - " .. other.sub(e))
			row.sub:Show()
			row.sel:Hide()
		elseif item.folder then
			local f = item.folder
			row:SetHeight(FOLDER_H)
			local open = not f.collapsed or filter ~= ""
			row.icon:SetTexture(open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
			row.icon:Show()
			row.text:SetPoint("LEFT", 22, 0)
			row.text:SetPoint("RIGHT", -4, 0)
			row.text:SetText(f.name .. " (" .. item.count .. ")")
			row.sub:Hide()
			row.sel:SetShown(activeFolder == f.id and not (current.notes and current.notes.folder == f.id))
		else
			local e = item.entry
			row:SetHeight(ROW_H)
			row.icon:Hide()
			row.text:SetPoint("TOPLEFT", item.indent and 22 or 6, -4)
			row.text:SetPoint("RIGHT", -4, 0)
			local title = titleOf(e)
			row.text:SetText((title and title ~= "") and title or "(untitled)")
			row.sub:SetText(s.sub(e))
			row.sub:Show()
			row.sel:SetShown(e == current[mode])
		end
		row:Show()
		y = y + row:GetHeight()
	end
	for i = #items + 1, #rows do rows[i]:Hide() end
	w.listChild:SetHeight(math.max(1, y))

	w.emptyList:SetShown(#items == 0)
	if matched == 0 and #items > 0 then
		-- Nothing here, but other sections have matches: say so above the heading.
		w.emptyList:SetShown(false)
	end
	w.emptyList:SetText((#list() == 0 or matched == 0 and filter == "") and s.empty or "Nothing matches.")
end

-- Page ----------------------------------------------------------------------

function showMeta(e)
	local s = section()
	w.meta:SetText(s.meta(e))
	if s.action then w.action:SetText(s.action.text(e)) end
	if s.action2 then w.action2:SetText(s.action2.text(e)) end
end

function ns.Select(e)
	local s = section()
	current[mode] = e
	if e and mode == "notes" then activeFolder = e.folder end
	local has = e ~= nil
	w.title:SetShown(has)
	w.underline:SetShown(has)
	w.meta:SetShown(has)
	w.bodyScroll:SetShown(has)
	w.action:SetShown(has and s.action ~= nil)
	w.action2:SetShown(has and s.action2 ~= nil)
	w.emptyPage:SetShown(not has)
	for _, b in ipairs(s.widgets) do
		if b.def.delete then b:SetEnabled(has) end
	end
	if has then
		w.title:SetText(titleOf(e) or "")
		w.title:SetCursorPosition(0)
		w.body:SetText(e.body or "")
		w.body:SetCursorPosition(0)
		w.bodyScroll:SetVerticalScroll(0)
		showMeta(e)
	end
	ns.RefreshList()
end

-- The addon changed an entry by itself (chronicle line, completed quest).
-- Reload it if it is open, keeping the cursor where it was.
function ns.EntryChanged(e)
	if not (frame and frame:IsShown()) then return end
	if current[mode] == e then
		local pos = w.body:GetCursorPosition()
		w.body:SetText(e.body or "")
		w.body:SetCursorPosition(math.min(pos, #(e.body or "")))
		showMeta(e)
	end
	ns.RefreshList()
end

-- keepSearch leaves the search text in place (jumping to a match elsewhere).
function ns.SetMode(m, keepSearch)
	mode = m
	clearFocus()
	if not keepSearch then
		w.search:SetText("")
		filter = ""
	end
	for key, tab in pairs(w.tabs) do tab:SetEnabled(key ~= m) end
	for key, s in pairs(SECTIONS) do
		for _, b in ipairs(s.widgets) do b:SetShown(key == m) end
	end

	local s = section()
	w.title:ClearAllPoints()
	w.title:SetPoint("TOPLEFT", PAGE_X, -74)
	w.title:SetPoint("RIGHT", frame, "RIGHT", s.action and -124 or -24, 0)
	w.meta:ClearAllPoints()
	w.meta:SetPoint("TOPLEFT", PAGE_X, -106)
	w.meta:SetPoint("RIGHT", frame, "RIGHT", s.action2 and -124 or -24, 0)
	w.emptyPage:SetText(s.hint)

	local e = current[m]
	if e and not tContains(list(), e) then e = nil end
	if not e then
		local items = listItems()
		for _, item in ipairs(items) do
			if item.entry and not item.other then e = item.entry break end
		end
	end
	ns.Select(e)
end

-- Folders -------------------------------------------------------------------

local function moveTo(e, folderId)
	e.folder = folderId
	activeFolder = folderId
	local f = ns.FolderById(folderId)
	if f then f.collapsed = nil end
	if current[mode] == e then showMeta(e) end
	ns.RefreshList()
end

function askRename(f)
	local data = f
	local popup = StaticPopup_Show("FIELDJOURNAL_RENAME_FOLDER", nil, nil, data)
	if popup then popup.data = data end
end

local function askDeleteFolder(f)
	local popup = StaticPopup_Show("FIELDJOURNAL_DELETE_FOLDER", f.name, nil, f)
	if popup then popup.data = f end
end

local hasMenus = MenuUtil and MenuUtil.CreateContextMenu

-- Pick a folder for a page. Without the game's menu system, each click moves
-- the page on to the next folder instead.
function moveMenu(e, owner)
	local folders = sortedFolders()
	if not hasMenus then
		local nextId
		if not e.folder then
			nextId = folders[1] and folders[1].id
		else
			for i, f in ipairs(folders) do
				if f.id == e.folder then nextId = folders[i + 1] and folders[i + 1].id end
			end
		end
		moveTo(e, nextId)
		return
	end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("Move to folder")
		root:CreateRadio("No folder", function() return e.folder == nil end, function() moveTo(e, nil) end)
		for _, f in ipairs(folders) do
			root:CreateRadio(f.name, function() return e.folder == f.id end, function() moveTo(e, f.id) end)
		end
		root:CreateDivider()
		root:CreateButton("New folder...", function()
			local f = ns.NewFolder()
			moveTo(e, f.id)
			askRename(f)
		end)
	end)
end

function folderMenu(f, owner)
	if not hasMenus then
		askRename(f)
		return
	end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(f.name)
		root:CreateButton("New page here", function()
			activeFolder = f.id
			f.collapsed = nil
			local note = ns.AddNote(nil, nil, f.id)
			ns.Select(note)
			w.title:SetFocus()
			w.title:HighlightText()
		end)
		root:CreateButton("Rename", function() askRename(f) end)
		root:CreateButton("Remove folder", function() askDeleteFolder(f) end)
	end)
end

-- Window --------------------------------------------------------------------

local function button(parent, text, width)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(text)
	return b
end

local function scrollingEdit(parent, editFont)
	local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(editFont)
	edit:SetTextColor(INK[1], INK[2], INK[3])
	edit:SetMaxLetters(0)
	edit:SetTextInsets(2, 2, 2, 2)
	scroll:SetScrollChild(edit)
	scroll:SetScript("OnSizeChanged", function(_, width)
		edit:SetWidth(width) -- height grows on its own as text is added
	end)
	-- Clicking the empty part of the page puts the cursor at the end.
	scroll:EnableMouse(true)
	scroll:SetScript("OnMouseDown", function()
		edit:SetFocus()
		edit:SetCursorPosition(#edit:GetText())
	end)
	edit:SetScript("OnEscapePressed", edit.ClearFocus)
	-- Keep the cursor in view while typing.
	edit:SetScript("OnCursorChanged", function(_, _, y, _, h)
		y = -y
		local top = scroll:GetVerticalScroll()
		local height = scroll:GetHeight()
		if y < top then
			scroll:SetVerticalScroll(y)
		elseif y + h > top + height then
			scroll:UpdateScrollChildRect()
			scroll:SetVerticalScroll(math.min(scroll:GetVerticalScrollRange(), y + h - height))
		end
	end)
	return scroll, edit
end

local function savePosition()
	local point, _, relPoint, x, y = frame:GetPoint()
	ns.db.point = { point, relPoint, x, y }
end

function ns.ResetPosition()
	if not frame then return end
	frame:ClearAllPoints()
	local p = ns.db.point
	if p then
		frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		frame:SetPoint("CENTER")
	end
end

local function focusEntry(how)
	if how == "title" then
		w.title:SetFocus()
		w.title:HighlightText()
	elseif how == "end" then
		w.body:SetFocus()
		w.body:SetCursorPosition(#w.body:GetText())
	end
end

local function sectionButtons(key, s)
	s.widgets = {}
	local prev
	for _, def in ipairs(s.buttons) do
		local b = button(frame, def.text, def.width)
		b.def = def
		if prev then
			b:SetPoint("LEFT", prev, "RIGHT", 2, 0)
		else
			b:SetPoint("BOTTOMLEFT", 18, 16)
		end
		if def.tip then tooltip(b, def.text, def.tip) end
		if def.delete then
			b:SetScript("OnClick", function()
				local e = current[key]
				if not e then return end
				local data = { key = key, entry = e }
				local popup = StaticPopup_Show("FIELDJOURNAL_DELETE", titleOf(e) or "this page", nil, data)
				if popup then popup.data = data end
			end)
		else
			b:SetScript("OnClick", function()
				local e, msg = def.fn()
				if msg then ns.Say(msg) end
				if e then
					w.search:SetText("")
					ns.Select(e)
					focusEntry(def.focus)
				end
			end)
		end
		table.insert(s.widgets, b)
		prev = b
	end
end

local function create()
	frame = CreateFrame("Frame", "FieldJournalFrame", UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		savePosition()
	end)
	frame:SetScript("OnHide", clearFocus)
	frame:Hide()
	tinsert(UISpecialFrames, "FieldJournalFrame") -- Escape closes it
	ns.ResetPosition()

	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		edgeSize = 32,
		insets = { left = 8, right = 8, top = 8, bottom = 8 },
	})
	frame:SetBackdropColor(0.90, 0.83, 0.67, 1)
	-- Real parchment art if the game has it; the plain color above otherwise.
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("QuestBG-Parchment") then
		local paper = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
		paper:SetPoint("TOPLEFT", 9, -9)
		paper:SetPoint("BOTTOMRIGHT", -9, 9)
		paper:SetAtlas("QuestBG-Parchment")
	end

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	local heading = frame:CreateFontString(nil, "OVERLAY")
	heading:SetFontObject(font("QuestTitleFont", "GameFontNormalLarge"))
	heading:SetPoint("TOP", 0, -18)
	heading:SetText("Field Journal")
	ink(heading)

	-- Tabs
	w.tabs = {}
	local prevTab
	for _, key in ipairs(ORDER) do
		local tab = button(frame, SECTIONS[key].label, 92)
		if prevTab then
			tab:SetPoint("LEFT", prevTab, "RIGHT", 0, 0)
		else
			tab:SetPoint("TOPLEFT", 18, -40)
		end
		tab:SetScript("OnClick", function() ns.SetMode(key) end)
		w.tabs[key] = tab
		prevTab = tab
	end

	-- Search
	w.search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	w.search:SetSize(LIST_W + 10, 20)
	w.search:SetPoint("TOPLEFT", 26, -72)
	w.search:SetAutoFocus(false)
	local hint = w.search:CreateFontString(nil, "OVERLAY")
	hint:SetFontObject(font("GameFontDisableSmall", "GameFontNormalSmall"))
	hint:SetPoint("LEFT", 2, 0)
	hint:SetText("Search all pages...")
	w.search:SetScript("OnTextChanged", function(self)
		filter = strtrim(self:GetText()):lower()
		hint:SetShown(self:GetText() == "")
		ns.RefreshList()
	end)
	w.search:SetScript("OnEscapePressed", w.search.ClearFocus)
	w.search:SetScript("OnEnterPressed", w.search.ClearFocus)

	-- Entry list
	local listScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	listScroll:SetPoint("TOPLEFT", 20, -100)
	listScroll:SetPoint("BOTTOMLEFT", 20, 46)
	listScroll:SetWidth(LIST_W)
	w.listChild = CreateFrame("Frame", nil, listScroll)
	w.listChild:SetSize(LIST_W, 1)
	listScroll:SetScrollChild(w.listChild)

	w.emptyList = frame:CreateFontString(nil, "OVERLAY")
	w.emptyList:SetFontObject(font("GameFontHighlightSmall", "GameFontNormalSmall"))
	w.emptyList:SetPoint("TOP", listScroll, "TOP", 0, -12)
	ink(w.emptyList, FAINT)

	for key, s in pairs(SECTIONS) do sectionButtons(key, s) end

	-- Spine between list and page
	local spine = frame:CreateTexture(nil, "ARTWORK")
	spine:SetColorTexture(INK[1], INK[2], INK[3], 0.3)
	spine:SetPoint("TOPLEFT", 224, -68)
	spine:SetPoint("BOTTOMLEFT", 224, 16)
	spine:SetWidth(1)

	-- Page: title, action, meta, body
	w.title = CreateFrame("EditBox", nil, frame)
	w.title:SetHeight(26)
	w.title:SetAutoFocus(false)
	w.title:SetFontObject(font("QuestTitleFont", "GameFontNormalLarge"))
	w.title:SetTextColor(INK[1], INK[2], INK[3])
	w.title:SetMaxLetters(80)
	w.title:SetScript("OnEscapePressed", w.title.ClearFocus)
	w.title:SetScript("OnEnterPressed", function()
		w.title:ClearFocus()
		w.body:SetFocus()
	end)
	w.title:SetScript("OnTabPressed", function() w.body:SetFocus() end)
	w.title:SetScript("OnTextChanged", function(self, userInput)
		local e = current[mode]
		if not userInput or not e then return end
		e[section().titleField] = self:GetText()
		e.modified = time()
		ns.RefreshList()
		if mode == "notes" and ns.db.pinned == e.id then ns.PinChanged() end
	end)

	w.underline = frame:CreateTexture(nil, "ARTWORK")
	w.underline:SetColorTexture(INK[1], INK[2], INK[3], 0.35)
	w.underline:SetHeight(1)
	w.underline:SetPoint("TOPLEFT", w.title, "BOTTOMLEFT", 0, 0)
	w.underline:SetPoint("TOPRIGHT", w.title, "BOTTOMRIGHT", 0, 0)

	w.action = button(frame, "", 96)
	w.action:SetPoint("TOPRIGHT", -24, -76)
	w.action:SetScript("OnClick", function(self)
		local e = current[mode]
		local action = section().action
		if not (e and action) then return end
		action.click(e)
		self:SetText(action.text(e))
		ns.RefreshList()
	end)
	w.action:SetScript("OnEnter", function(self)
		local action = section().action
		if not action then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(action.tip, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	w.action:SetScript("OnLeave", GameTooltip_Hide)

	w.action2 = button(frame, "", 96)
	w.action2:SetPoint("TOPRIGHT", -24, -102)
	w.action2:SetScript("OnClick", function(self)
		local e = current[mode]
		local action = section().action2
		if e and action then action.click(e, self) end
	end)
	w.action2:SetScript("OnEnter", function(self)
		local action = section().action2
		if not action then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(action.tip, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	w.action2:SetScript("OnLeave", GameTooltip_Hide)

	w.meta = frame:CreateFontString(nil, "OVERLAY")
	w.meta:SetFontObject(font("GameFontHighlightSmall", "GameFontNormalSmall"))
	w.meta:SetJustifyH("LEFT")
	ink(w.meta, FAINT)

	w.bodyScroll, w.body = scrollingEdit(frame, font("QuestFont", "GameFontHighlight"))
	w.bodyScroll:SetPoint("TOPLEFT", PAGE_X, -138)
	w.bodyScroll:SetPoint("BOTTOMRIGHT", -40, 20)
	w.body:SetScript("OnTextChanged", function(self, userInput)
		local e = current[mode]
		if not userInput or not e then return end
		e.body = self:GetText()
		e.modified = time()
		if mode == "notes" and ns.db.pinned == e.id then ns.PinChanged() end
	end)

	w.emptyPage = frame:CreateFontString(nil, "OVERLAY")
	w.emptyPage:SetFontObject(font("QuestFont", "GameFontHighlight"))
	w.emptyPage:SetPoint("CENTER", frame, "CENTER", PAGE_X / 2 - 10, 0)
	ink(w.emptyPage, FAINT)

	local function popupEditBox(dialog)
		return (dialog.GetEditBox and dialog:GetEditBox()) or dialog.editBox or dialog.EditBox
	end
	local function rename(folder, text)
		text = strtrim(text or "")
		if folder and text ~= "" then folder.name = text end
		ns.RefreshList()
		if current.notes and mode == "notes" then showMeta(current.notes) end
	end
	StaticPopupDialogs.FIELDJOURNAL_RENAME_FOLDER = {
		text = "Name this folder:",
		button1 = OKAY or "Okay",
		button2 = CANCEL or "Cancel",
		hasEditBox = 1,
		maxLetters = 40,
		OnShow = function(self, data)
			data = data or self.data
			local eb = popupEditBox(self)
			if eb and data then
				eb:SetText(data.name or "")
				eb:SetFocus()
				eb:HighlightText()
			end
		end,
		OnAccept = function(self, data)
			local eb = popupEditBox(self)
			if eb then rename(data or self.data, eb:GetText()) end
		end,
		EditBoxOnEnterPressed = function(eb)
			local dialog = eb:GetParent()
			rename(dialog.data, eb:GetText())
			dialog:Hide()
		end,
		EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
	}
	StaticPopupDialogs.FIELDJOURNAL_DELETE_FOLDER = {
		text = "Remove the folder \"%s\"? The pages inside stay in your journal, outside any folder.",
		button1 = YES,
		button2 = NO,
		OnAccept = function(self, data)
			data = data or self.data
			if not data then return end
			ns.DeleteFolder(data)
			if activeFolder == data.id then activeFolder = nil end
			ns.RefreshList()
			if current.notes and mode == "notes" then showMeta(current.notes) end
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
	}

	StaticPopupDialogs.FIELDJOURNAL_DELETE = {
		text = "Tear \"%s\" out of your journal? This can't be undone.",
		button1 = YES,
		button2 = NO,
		OnAccept = function(self, data)
			data = data or self.data
			if not data then return end
			ns.Remove(ns.db[data.key], data.entry)
			if current[data.key] == data.entry then current[data.key] = nil end
			if data.key == "notes" and ns.db.pinned == data.entry.id then
				ns.db.pinned = nil
				ns.PinChanged()
			end
			if frame:IsShown() and mode == data.key then ns.Select(sorted()[1]) end
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
	}

	ns.SetMode(mode)
end

-- Public --------------------------------------------------------------------

-- Opens the journal with a search across every section.
function ns.Search(text)
	if not ns.db then return end
	if not frame then create() end
	frame:Show()
	ns.SetMode(mode)
	w.search:SetText(text or "")
	w.search:SetFocus()
end

function ns.Toggle()
	if not ns.db then return end
	if not frame then create() end
	if frame:IsShown() then
		frame:Hide()
	else
		frame:Show()
		ns.SetMode(mode)
	end
end

-- Opens the journal on a section, optionally on an entry. focus is "title"
-- or "end" (cursor at the end of the text).
function ns.Open(m, entry, focus)
	if not ns.db then return end
	if not frame then create() end
	frame:Show()
	ns.SetMode(m)
	if entry then
		ns.Select(entry)
		focusEntry(focus)
	end
end

function ns.Refresh()
	if frame and frame:IsShown() then ns.SetMode(mode) end
end
