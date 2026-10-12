local _, ns = ...

-- A pinned page: one note kept on screen as a small scrap of paper. It sits
-- faded until you hover it, and tucks itself away in combat. Drag to move,
-- click to open the note in the journal.

local INK = { 0.20, 0.12, 0.05 }
local RESTING_ALPHA = 0.7
local pin

local function pinnedNote()
	local id = ns.db.pinned
	if not id then return end
	for _, e in ipairs(ns.db.notes) do
		if e.id == id then return e end
	end
end

local function updateAlpha()
	if not pin then return end
	local inCombat = InCombatLockdown() or pin.combat
	pin:EnableMouse(not inCombat)
	if inCombat then
		pin:SetAlpha(0)
	else
		pin:SetAlpha(pin:IsMouseOver() and 1 or RESTING_ALPHA)
	end
end

local function create()
	pin = CreateFrame("Frame", "FieldJournalPinFrame", UIParent, "BackdropTemplate")
	pin:SetWidth(220)
	pin:SetFrameStrata("MEDIUM")
	pin:SetClampedToScreen(true)
	pin:SetMovable(true)
	pin:EnableMouse(true)
	pin:RegisterForDrag("LeftButton")
	pin:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	pin:SetBackdropColor(0.90, 0.83, 0.67, 0.95)
	pin:SetBackdropBorderColor(0.45, 0.33, 0.18, 1)

	pin.title = pin:CreateFontString(nil, "OVERLAY")
	pin.title:SetFontObject(GameFontNormal)
	pin.title:SetPoint("TOPLEFT", 10, -9)
	pin.title:SetPoint("RIGHT", -10, 0)
	pin.title:SetJustifyH("LEFT")
	pin.title:SetWordWrap(false)
	pin.title:SetTextColor(INK[1], INK[2], INK[3])

	pin.text = pin:CreateFontString(nil, "OVERLAY")
	pin.text:SetFontObject(GameFontHighlightSmall)
	pin.text:SetPoint("TOPLEFT", pin.title, "BOTTOMLEFT", 0, -5)
	pin.text:SetPoint("RIGHT", -10, 0)
	pin.text:SetJustifyH("LEFT")
	pin.text:SetJustifyV("TOP")
	pin.text:SetMaxLines(16)
	pin.text:SetTextColor(INK[1], INK[2], INK[3])

	pin:SetScript("OnDragStart", pin.StartMoving)
	pin:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		ns.db.pinPoint = { point, relPoint, x, y }
	end)
	-- A click (press and release without moving) opens the note.
	pin:SetScript("OnMouseDown", function(self)
		self.downX, self.downY = GetCursorPosition()
	end)
	pin:SetScript("OnMouseUp", function(self, button)
		local x, y = GetCursorPosition()
		if button == "LeftButton" and self.downX and math.abs(x - self.downX) + math.abs(y - self.downY) < 4 then
			local note = pinnedNote()
			if note then ns.Open("notes", note) end
		end
	end)
	pin:SetScript("OnEnter", function(self)
		updateAlpha()
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Pinned page")
		GameTooltip:AddLine("Click to open, drag to move. Unpin it from the page in your journal, or type /fj unpin.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	pin:SetScript("OnLeave", function()
		updateAlpha()
		GameTooltip:Hide()
	end)

	pin:RegisterEvent("PLAYER_REGEN_DISABLED")
	pin:RegisterEvent("PLAYER_REGEN_ENABLED")
	pin:SetScript("OnEvent", function(self, event)
		self.combat = event == "PLAYER_REGEN_DISABLED" -- InCombatLockdown() can lag this event
		updateAlpha()
	end)
end

function ns.PinChanged()
	local note = pinnedNote()
	if not note then
		if pin then pin:Hide() end
		return
	end
	if not pin then create() end
	pin:ClearAllPoints()
	local p = ns.db.pinPoint
	if p then
		pin:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		pin:SetPoint("RIGHT", UIParent, "RIGHT", -60, 120)
	end
	pin.title:SetText(note.title ~= "" and note.title or "(untitled)")
	pin.text:SetText(note.body or "")
	pin:SetHeight(pin.title:GetStringHeight() + pin.text:GetStringHeight() + 26)
	pin:Show()
	updateAlpha()
end

function ns.TogglePin(note)
	ns.db.pinned = ns.db.pinned ~= note.id and note.id or nil
	ns.PinChanged()
end

table.insert(ns.onLoad, function() ns.PinChanged() end)
