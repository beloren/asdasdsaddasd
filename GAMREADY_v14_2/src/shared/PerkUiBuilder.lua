--------------------------------------------------------------------------------
-- PerkUiBuilder v2 (v9) — окно ПРЕСТИЖА деревом. Свой стиль: «звёздная
-- ночь» — тёмно-индиговая панель с золотой каймой, узлы-кружки как звёзды
-- созвездия, линии между ними. tools/BuildPerkUI.lua (или общий
-- tools/BuildAllUI.lua) кладёт в StarterGui/PerkUi; PerkUI.client.lua при
-- отсутствии/старой версии строит сам.
--
-- СТРУКТУРА (имена — контракт):
--   ScreenGui "PerkUi" (BuilderVersion)
--   └─ Frame "Panel" (UIScale "AutoScale")
--        ├─ Frame "Tab" → TextLabel "Title"
--        ├─ Frame "Points" → TextLabel "Text"          — "⭐ 5"
--        ├─ TextButton "CloseButton"
--        ├─ Frame "Tree"
--        │    ├─ Frame "BranchTemplate" → Frame "Header" → "Text"; Frame "Nodes"
--        │    ├─ TextButton "NodeTemplate" → "Icon", Frame "LevelChip" → "Level", "Lock", "CanBuy"
--        │    └─ Frame "LinkTemplate"
--        └─ Frame "Detail"
--             ├─ TextLabel "Icon", "Title", "Level", "Now", "Next", "Hint"
--             └─ TextButton "UpgradeButton" → TextLabel "Text"
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Builder = {}
Builder.Width = 780
Builder.Height = 480

local INK = Color3.fromRGB(10, 8, 24)          -- контур
local NIGHT = Color3.fromRGB(30, 22, 64)       -- панель
local NIGHT_DEEP = Color3.fromRGB(18, 13, 42)  -- дерево/подложки
local GOLD = Color3.fromRGB(255, 200, 70)
local GOLD_TEXT = Color3.fromRGB(255, 220, 110)
local STAR = Color3.fromRGB(80, 70, 150)       -- узел по умолчанию

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0, 12)
	c.Parent = parent
end
local function stroke(parent, thickness, color, contextual, name)
	local s = Instance.new("UIStroke")
	s.Name = name or "Outline"
	s.Thickness = thickness
	s.Color = color
	s.ApplyStrokeMode = contextual and Enum.ApplyStrokeMode.Contextual or Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end
local function gradient(parent, top, bottom, rotation)
	local g = Instance.new("UIGradient")
	g.Rotation = rotation or 90
	g.Color = ColorSequence.new(top, bottom)
	g.Parent = parent
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
	if zIndex then t.ZIndex = zIndex end
	t.Parent = parent
	stroke(t, 2, INK, true)
	return t
end
local function button(parent, name, size, position, color, label, zIndex)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.AutoButtonColor = false
	b.Size = size
	b.Position = position or UDim2.new()
	b.BackgroundColor3 = color
	if zIndex then b.ZIndex = zIndex end
	b.Parent = parent
	corner(b, UDim.new(0, 12))
	stroke(b, 3, INK)
	gradient(b, Color3.new(1, 1, 1), Color3.fromRGB(195, 195, 205))
	text(b, "Text", UDim2.new(1, -12, 1, -10), UDim2.fromOffset(6, 5), label or "", nil, nil, zIndex and zIndex + 1)
	return b
end

function Builder.Build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "PerkUi"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 31
	gui.Enabled = false
	gui:SetAttribute("BuilderVersion", Config.Prestige.PerkUiVersion or 2)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.53)
	panel.Size = UDim2.fromOffset(Builder.Width, Builder.Height)
	panel.BackgroundColor3 = NIGHT
	panel.Parent = gui
	corner(panel, UDim.new(0, 18))
	stroke(panel, 5, INK)
	gradient(panel, Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 140, 200))
	local scale = Instance.new("UIScale")
	scale.Name = "AutoScale"
	scale.Parent = panel
	-- Золотая кайма внутри.
	local trim = Instance.new("Frame")
	trim.Name = "GoldTrim"
	trim.BackgroundTransparency = 1
	trim.Position = UDim2.fromOffset(6, 6)
	trim.Size = UDim2.new(1, -12, 1, -12)
	trim.Parent = panel
	corner(trim, UDim.new(0, 14))
	stroke(trim, 2, GOLD, false, "Trim")
	-- Россыпь «звёзд» на фоне.
	local rng = Random.new(7)
	for i = 1, 26 do
		local dot = Instance.new("Frame")
		dot.Name = "Star" .. i
		local size = rng:NextInteger(2, 4)
		dot.Size = UDim2.fromOffset(size, size)
		dot.Position = UDim2.fromScale(rng:NextNumber(0.03, 0.97), rng:NextNumber(0.05, 0.95))
		dot.BackgroundColor3 = Color3.fromRGB(255, 240, 200)
		dot.BackgroundTransparency = rng:NextNumber(0.3, 0.7)
		dot.BorderSizePixel = 0
		dot.Parent = panel
		corner(dot, UDim.new(1, 0))
	end

	local tab = Instance.new("Frame")
	tab.Name = "Tab"
	tab.Position = UDim2.fromOffset(-12, -26)
	tab.Size = UDim2.fromOffset(270, 50)
	tab.BackgroundColor3 = GOLD
	tab.ZIndex = 5
	tab.Parent = panel
	corner(tab, UDim.new(0, 10))
	stroke(tab, 3, INK)
	gradient(tab, Color3.fromRGB(255, 245, 200), Color3.fromRGB(230, 160, 40))
	text(tab, "Title", UDim2.new(1, -24, 1, -10), UDim2.fromOffset(14, 5), "⭐ PRESTIGE", nil, nil, 6).TextXAlignment = Enum.TextXAlignment.Left

	local points = Instance.new("Frame")
	points.Name = "Points"
	points.Position = UDim2.new(1, -196, 0, 14)
	points.Size = UDim2.fromOffset(130, 36)
	points.BackgroundColor3 = NIGHT_DEEP
	points.Parent = panel
	corner(points, UDim.new(1, 0))
	stroke(points, 2, GOLD)
	text(points, "Text", UDim2.new(1, -14, 1, -8), UDim2.fromOffset(7, 4), "⭐ 0", GOLD_TEXT, Enum.Font.GothamBlack)

	button(panel, "CloseButton", UDim2.fromOffset(46, 46), UDim2.new(1, -27, 0, -19), Color3.fromRGB(225, 50, 70), "X", 7)

	-- v4: ВКЛАДКИ PERKS / SHRINES (святилища за очки престижа).
	local tabs = Instance.new("Frame")
	tabs.Name = "Tabs"
	tabs.BackgroundTransparency = 1
	tabs.Position = UDim2.fromOffset(276, 14)
	tabs.Size = UDim2.fromOffset(290, 36)
	tabs.Parent = panel
	local tabsLayout = Instance.new("UIListLayout")
	tabsLayout.FillDirection = Enum.FillDirection.Horizontal
	tabsLayout.Padding = UDim.new(0, 8)
	tabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabsLayout.Parent = tabs
	local perksTab = button(tabs, "PerksTab", UDim2.fromOffset(120, 36), nil, GOLD, "PERKS", 3)
	perksTab.LayoutOrder = 1
	local shrinesTab = button(tabs, "ShrinesTab", UDim2.fromOffset(140, 36), nil, STAR, "🗿 SHRINES", 3)
	shrinesTab.LayoutOrder = 2

	-- СПИСОК СВЯТИЛИЩ (на месте дерева, видим во вкладке SHRINES).
	local shrines = Instance.new("ScrollingFrame")
	shrines.Name = "Shrines"
	shrines.Visible = false
	shrines.BackgroundColor3 = NIGHT_DEEP
	shrines.BackgroundTransparency = 0.2
	shrines.BorderSizePixel = 0
	shrines.Position = UDim2.fromOffset(18, 62)
	shrines.Size = UDim2.new(1, -322, 1, -80)
	shrines.ScrollBarThickness = 6
	shrines.AutomaticCanvasSize = Enum.AutomaticSize.Y
	shrines.CanvasSize = UDim2.new()
	shrines.Parent = panel
	corner(shrines, UDim.new(0, 14))
	stroke(shrines, 3, INK)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(142, 96)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = shrines
	local shrinesPad = Instance.new("UIPadding")
	shrinesPad.PaddingTop = UDim.new(0, 10)
	shrinesPad.PaddingBottom = UDim.new(0, 10)
	shrinesPad.Parent = shrines

	local card = Instance.new("TextButton")
	card.Name = "ShrineTemplate"
	card.Visible = false
	card.Text = ""
	card.AutoButtonColor = false
	card.BackgroundColor3 = STAR
	card.Parent = shrines
	corner(card, UDim.new(0, 12))
	stroke(card, 3, INK)
	gradient(card, Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 200))
	text(card, "Icon", UDim2.fromOffset(40, 40), UDim2.fromOffset(8, 8), "🗿", nil, nil, 3)
	text(card, "Title", UDim2.new(1, -60, 0, 36), UDim2.fromOffset(52, 10), "Shrine", nil, nil, 3).TextXAlignment = Enum.TextXAlignment.Left
	text(card, "Status", UDim2.new(1, -16, 0, 26), UDim2.new(0, 8, 1, -34), "⭐ 3", GOLD_TEXT, Enum.Font.GothamBlack, 3)

	-- ДЕРЕВО
	local tree = Instance.new("Frame")
	tree.Name = "Tree"
	tree.BackgroundColor3 = NIGHT_DEEP
	tree.BackgroundTransparency = 0.2
	tree.Position = UDim2.fromOffset(18, 62)
	tree.Size = UDim2.new(1, -322, 1, -80)
	tree.Parent = panel
	corner(tree, UDim.new(0, 14))
	stroke(tree, 3, INK)
	local treeLayout = Instance.new("UIListLayout")
	treeLayout.FillDirection = Enum.FillDirection.Horizontal
	treeLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	treeLayout.Padding = UDim.new(0, 10)
	treeLayout.SortOrder = Enum.SortOrder.LayoutOrder
	treeLayout.Parent = tree
	local treePad = Instance.new("UIPadding")
	treePad.PaddingTop = UDim.new(0, 10)
	treePad.PaddingBottom = UDim.new(0, 10)
	treePad.Parent = tree

	local branch = Instance.new("Frame")
	branch.Name = "BranchTemplate"
	branch.Visible = false
	branch.BackgroundTransparency = 1
	branch.Size = UDim2.new(0.31, 0, 1, 0)
	branch.Parent = tree
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 30)
	header.BackgroundColor3 = GOLD
	header.Parent = branch
	corner(header, UDim.new(1, 0))
	stroke(header, 3, INK)
	text(header, "Text", UDim2.new(1, -14, 1, -8), UDim2.fromOffset(7, 4), "BRANCH")
	local nodes = Instance.new("Frame")
	nodes.Name = "Nodes"
	nodes.BackgroundTransparency = 1
	nodes.Position = UDim2.fromOffset(0, 40)
	nodes.Size = UDim2.new(1, 0, 1, -40)
	nodes.Parent = branch

	local node = Instance.new("TextButton")
	node.Name = "NodeTemplate"
	node.Visible = false
	node.Text = ""
	node.AutoButtonColor = false
	node.AnchorPoint = Vector2.new(0.5, 0)
	node.Size = UDim2.fromOffset(70, 70)
	node.BackgroundColor3 = STAR
	node.ZIndex = 2
	node.Parent = tree
	corner(node, UDim.new(1, 0)) -- круглые «звёзды»
	stroke(node, 4, INK)
	gradient(node, Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 200))
	local press = Instance.new("UIScale")
	press.Name = "PressScale"
	press.Parent = node
	text(node, "Icon", UDim2.new(1, -20, 1, -26), UDim2.fromOffset(10, 6), "💰", nil, nil, 3)
	local levelChip = Instance.new("Frame")
	levelChip.Name = "LevelChip"
	levelChip.AnchorPoint = Vector2.new(0.5, 0.5)
	levelChip.Position = UDim2.new(0.5, 0, 1, -2)
	levelChip.Size = UDim2.fromOffset(58, 22)
	levelChip.BackgroundColor3 = INK
	levelChip.ZIndex = 4
	levelChip.Parent = node
	corner(levelChip, UDim.new(1, 0))
	stroke(levelChip, 2, GOLD)
	text(levelChip, "Level", UDim2.new(1, -8, 1, -4), UDim2.fromOffset(4, 2), "0/25", GOLD_TEXT, Enum.Font.GothamBlack, 5)
	local lock = text(node, "Lock", UDim2.fromOffset(28, 28), UDim2.new(1, -22, 0, -8), "🔒", nil, nil, 6)
	lock.Visible = false
	local canBuy = text(node, "CanBuy", UDim2.fromOffset(26, 26), UDim2.new(1, -18, 0, -8), "+", Color3.fromRGB(120, 255, 150), nil, 6)
	canBuy.Visible = false

	local link = Instance.new("Frame")
	link.Name = "LinkTemplate"
	link.Visible = false
	link.AnchorPoint = Vector2.new(0.5, 0)
	link.Size = UDim2.fromOffset(8, 26)
	link.BackgroundColor3 = GOLD
	link.BorderSizePixel = 0
	link.ZIndex = 1
	link.Parent = tree
	stroke(link, 2, INK)

	-- ПАНЕЛЬ ПЕРКА
	local detail = Instance.new("Frame")
	detail.Name = "Detail"
	detail.BackgroundColor3 = NIGHT_DEEP
	detail.Position = UDim2.new(1, -292, 0, 62)
	detail.Size = UDim2.new(0, 274, 1, -80)
	detail.Parent = panel
	corner(detail, UDim.new(0, 14))
	stroke(detail, 3, GOLD)
	text(detail, "Icon", UDim2.fromOffset(90, 90), UDim2.new(0.5, -45, 0, 14), "💰")
	text(detail, "Title", UDim2.new(1, -20, 0, 34), UDim2.fromOffset(10, 110), "Money")
	text(detail, "Level", UDim2.new(1, -20, 0, 22), UDim2.fromOffset(10, 146), "LV 0/25", GOLD_TEXT, Enum.Font.GothamBlack)
	text(detail, "Now", UDim2.new(1, -20, 0, 24), UDim2.fromOffset(10, 184), "+0%", Color3.fromRGB(190, 190, 220), Enum.Font.GothamBold)
	text(detail, "Next", UDim2.new(1, -20, 0, 28), UDim2.fromOffset(10, 212), "▶ +4%", Color3.fromRGB(120, 255, 150), Enum.Font.GothamBlack)
	local hint = text(detail, "Hint", UDim2.new(1, -20, 0, 22), UDim2.new(0, 10, 1, -104), "", Color3.fromRGB(255, 160, 110), Enum.Font.GothamBold)
	hint.Visible = false
	button(detail, "UpgradeButton", UDim2.new(1, -28, 0, 60), UDim2.new(0, 14, 1, -74), Color3.fromRGB(70, 200, 95), "⭐ 1")
	return gui
end

return Builder
