--------------------------------------------------------------------------------
-- PrestigeUiBuilder (v10) — ОКНО ПРЕСТИЖА у NPC: что даст и какие условия
-- нужны. Стиль общий с магазином улучшений и деревом перков: тёмно-индиговая
-- панель, золотая вкладка-заголовок, слева чек-лист условий карточками,
-- справа «что получишь», снизу крупная кнопка.
-- tools/BuildRebirthDialogUI.lua (или tools/BuildAllUI.lua) → StarterGui;
-- CustomCartUI.client.lua строит это же окно сам, если его нет.
--
-- КОНТРАКТ (имена читает CustomCartUI.client.lua):
--   ScreenGui "RebirthDialogButtons" (BuilderVersion)
--   └─ Frame "Panel"
--        ├─ Frame "Tab" → TextLabel "Title"
--        ├─ TextLabel "Intro"
--        ├─ Frame "Requirements"           — чек-лист строит клиент
--        ├─ Frame "Bonuses" → "Title", Frame "MONEYRow"/"SPEEDRow"
--        │     (в каждом TextLabel "Label", "Current", "Next")
--        ├─ ImageButton "RebirthButton" → TextLabel "Caption"
--        └─ TextButton "CancelButton"
--------------------------------------------------------------------------------
local Builder = {}
Builder.VERSION = 2

local INK = Color3.fromRGB(10, 8, 24)
local NIGHT = Color3.fromRGB(30, 22, 64)
local NIGHT_DEEP = Color3.fromRGB(18, 13, 42)
local GOLD = Color3.fromRGB(255, 200, 70)
local GOLD_TEXT = Color3.fromRGB(255, 220, 110)
local GREEN = Color3.fromRGB(70, 195, 100)

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0, 12)
	c.Parent = parent
end
local function stroke(parent, thickness, color, contextual)
	local s = Instance.new("UIStroke")
	s.Name = "Outline"
	s.Thickness = thickness
	s.Color = color
	s.ApplyStrokeMode = contextual and Enum.ApplyStrokeMode.Contextual or Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end
local function text(parent, name, size, position, content, color, font, zIndex)
	local t = Instance.new("TextLabel")
	t.Name = name
	t.Size = size
	t.Position = position or UDim2.new()
	t.BackgroundTransparency = 1
	t.Text = content or ""
	t.TextColor3 = color or Color3.new(1, 1, 1)
	t.Font = font or Enum.Font.FredokaOne
	t.TextScaled = true
	t.RichText = true
	t.TextXAlignment = Enum.TextXAlignment.Left
	if zIndex then t.ZIndex = zIndex end
	t.Parent = parent
	stroke(t, 2, INK, true)
	return t
end

function Builder.Build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RebirthDialogButtons"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 15
	gui.Enabled = false
	gui:SetAttribute("BuilderVersion", Builder.VERSION)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(660, 440)
	panel.BackgroundColor3 = NIGHT
	panel.Parent = gui
	corner(panel, UDim.new(0, 18))
	stroke(panel, 5, INK)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 140, 200))
	gradient.Parent = panel

	local tab = Instance.new("Frame")
	tab.Name = "Tab"
	tab.Position = UDim2.fromOffset(-12, -26)
	tab.Size = UDim2.fromOffset(280, 50)
	tab.BackgroundColor3 = GOLD
	tab.ZIndex = 4
	tab.Parent = panel
	corner(tab, UDim.new(0, 10))
	stroke(tab, 3, INK)
	text(tab, "Title", UDim2.new(1, -24, 1, -10), UDim2.fromOffset(14, 5), "⭐ PRESTIGE", nil, nil, 5)

	local cancel = Instance.new("TextButton")
	cancel.Name = "CancelButton"
	cancel.Position = UDim2.new(1, -27, 0, -19)
	cancel.Size = UDim2.fromOffset(46, 46)
	cancel.BackgroundColor3 = Color3.fromRGB(225, 50, 70)
	cancel.AutoButtonColor = false
	cancel.Font = Enum.Font.FredokaOne
	cancel.Text = "X"
	cancel.TextScaled = true
	cancel.TextColor3 = Color3.new(1, 1, 1)
	cancel.ZIndex = 6
	cancel.Parent = panel
	corner(cancel, UDim.new(0, 12))
	stroke(cancel, 3, INK)

	text(panel, "Intro", UDim2.new(1, -48, 0, 34), UDim2.fromOffset(24, 40), "", Color3.fromRGB(200, 200, 225), Enum.Font.GothamBold)

	-- ЛЕВО: чек-лист условий (строки строит клиент по status.Requirements).
	local requirementsCard = Instance.new("Frame")
	requirementsCard.Name = "RequirementsCard"
	requirementsCard.Position = UDim2.fromOffset(20, 84)
	requirementsCard.Size = UDim2.fromOffset(360, 260)
	requirementsCard.BackgroundColor3 = NIGHT_DEEP
	requirementsCard.Parent = panel
	corner(requirementsCard, UDim.new(0, 14))
	stroke(requirementsCard, 3, INK)
	text(requirementsCard, "Header", UDim2.new(1, -24, 0, 24), UDim2.fromOffset(12, 8), "WHAT YOU NEED", GOLD_TEXT)
	local requirements = Instance.new("Frame")
	requirements.Name = "Requirements"
	requirements.Position = UDim2.fromOffset(12, 40)
	requirements.Size = UDim2.new(1, -24, 1, -52)
	requirements.BackgroundTransparency = 1
	requirements.Parent = requirementsCard

	-- ПРАВО: что даст престиж.
	local bonuses = Instance.new("Frame")
	bonuses.Name = "Bonuses"
	bonuses.Position = UDim2.fromOffset(396, 84)
	bonuses.Size = UDim2.fromOffset(244, 260)
	bonuses.BackgroundColor3 = NIGHT_DEEP
	bonuses.Parent = panel
	corner(bonuses, UDim.new(0, 14))
	stroke(bonuses, 3, GOLD)
	text(bonuses, "Title", UDim2.new(1, -24, 0, 24), UDim2.fromOffset(12, 8), "WHAT YOU GET", GOLD_TEXT)

	local function bonusRow(name, label, icon, y)
		local row = Instance.new("Frame")
		row.Name = name
		row.Position = UDim2.fromOffset(12, y)
		row.Size = UDim2.new(1, -24, 0, 92)
		row.BackgroundColor3 = Color3.fromRGB(40, 32, 76)
		row.Parent = bonuses
		corner(row, UDim.new(0, 10))
		stroke(row, 2, INK)
		text(row, "Label", UDim2.new(1, -16, 0, 20), UDim2.fromOffset(8, 6), icon .. " " .. label, Color3.fromRGB(175, 175, 205), Enum.Font.GothamBlack)
		text(row, "Current", UDim2.new(1, -16, 0, 26), UDim2.fromOffset(8, 30), "", Color3.fromRGB(205, 205, 225), Enum.Font.GothamBold)
		text(row, "Next", UDim2.new(1, -16, 0, 28), UDim2.fromOffset(8, 58), "", Color3.fromRGB(120, 255, 160))
		return row
	end
	bonusRow("MONEYRow", "PRESTIGE POINTS", "⭐", 38)
	bonusRow("SPEEDRow", "AFTER PRESTIGE", "🕳", 140)

	-- НИЗ: крупная кнопка.
	local confirm = Instance.new("ImageButton")
	confirm.Name = "RebirthButton"
	confirm.Image = ""
	confirm.AutoButtonColor = false
	confirm.AnchorPoint = Vector2.new(0.5, 1)
	confirm.Position = UDim2.new(0.5, 0, 1, -18)
	confirm.Size = UDim2.fromOffset(320, 62)
	confirm.BackgroundColor3 = GREEN
	confirm.Parent = panel
	corner(confirm, UDim.new(0, 14))
	stroke(confirm, 3, INK)
	local buttonGradient = Instance.new("UIGradient")
	buttonGradient.Rotation = 90
	buttonGradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 200))
	buttonGradient.Parent = confirm
	local caption = text(confirm, "Caption", UDim2.new(1, -20, 1, -12), UDim2.fromOffset(10, 6), "PRESTIGE")
	caption.TextXAlignment = Enum.TextXAlignment.Center
	return gui
end

return Builder
