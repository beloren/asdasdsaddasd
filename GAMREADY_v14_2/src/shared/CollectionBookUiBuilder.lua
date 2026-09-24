--------------------------------------------------------------------------------
-- CollectionBookUiBuilder (v9) — КНИГА КОЛЛЕКЦИИ. Свой стиль: «музей
-- кристаллов» — глубокий сине-бирюзовый зал, витрины-ячейки с бирюзовой
-- подсветкой, латунная табличка-заголовок, вкладки-медальоны слева.
-- Строит MutationBookPanel внутрь ScreenGui "CollectionMenu".
-- tools/BuildMutationBookUI.lua (или tools/BuildAllUI.lua) — в StarterGui;
-- CollectionMenu.client.lua сам пересобирает старую версию.
--
-- СТРУКТУРА (имена — контракт CollectionMenu.client.lua):
--   ImageLabel "MutationBookPanel" (BuilderVersion)
--   ├─ ImageLabel "TitlePlaque" → TextLabel "TitleLabel"
--   ├─ TextButton "CloseButton"
--   ├─ Frame "Sidebar" → ImageButton "TabOreMutations" / "TabMobs" / "TabCrystals"
--   │     (у каждой UIStroke "SelectionStroke" и TextLabel "Icon")
--   ├─ Frame "LeftPage" → "PageTitle", Frame "ProgressChip" → "Text", ScrollingFrame "Scroller"
--   ├─ Frame "RightPage" → ViewportFrame "PreviewImage", "ItemNameLabel",
--   │     Frame "StatsRow" → "PriceLabel", "ChanceLabel"; "DescriptionLabel"
--   └─ Folder "Templates" → ImageButton "ItemCell", Frame "LockedCell" → "QuestionMark"
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Builder = {}
Builder.VERSION = 2

local INK = Color3.fromRGB(6, 16, 24)
local HALL = Color3.fromRGB(16, 40, 58)
local HALL_DEEP = Color3.fromRGB(9, 26, 38)
local GLASS = Color3.fromRGB(28, 70, 92)
local AQUA = Color3.fromRGB(90, 225, 235)
local BRASS = Color3.fromRGB(214, 170, 92)
local BRASS_TEXT = Color3.fromRGB(255, 222, 150)

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
local function gradient(parent, top, bottom)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(top, bottom)
	g.Parent = parent
end
local function text(parent, name, size, position, content, color, font)
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
	t.TextStrokeTransparency = 1
	t.Parent = parent
	stroke(t, 2, INK, true)
	return t
end

function Builder.BuildPanel()
	local panel = Instance.new("ImageLabel")
	panel.Name = "MutationBookPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(864, 504)
	panel.BackgroundColor3 = HALL
	panel.Image = ""
	panel.ClipsDescendants = false
	panel.Visible = false
	panel.ZIndex = 6 -- над Dimmer (ZIndex 5)
	panel:SetAttribute("BuilderVersion", Builder.VERSION)
	corner(panel, UDim.new(0, 18))
	stroke(panel, 5, INK)
	gradient(panel, Color3.new(1, 1, 1), Color3.fromRGB(130, 160, 180))
	-- Бирюзовая «подсветка витрины» по краю.
	local glowFrame = Instance.new("Frame")
	glowFrame.Name = "GlassEdge"
	glowFrame.BackgroundTransparency = 1
	glowFrame.Position = UDim2.fromOffset(6, 6)
	glowFrame.Size = UDim2.new(1, -12, 1, -12)
	glowFrame.ZIndex = 6
	glowFrame.Parent = panel
	corner(glowFrame, UDim.new(0, 14))
	local edge = stroke(glowFrame, 2, AQUA, false, "Edge")
	edge.Transparency = 0.35

	local plaque = Instance.new("ImageLabel")
	plaque.Name = "TitlePlaque"
	plaque.AnchorPoint = Vector2.new(0.5, 1)
	plaque.Position = UDim2.new(0.5, 0, 0, 14)
	plaque.Size = UDim2.fromOffset(250, 50)
	plaque.BackgroundColor3 = BRASS
	plaque.Image = ""
	plaque.ZIndex = 8
	plaque.Parent = panel
	corner(plaque, UDim.new(0, 10))
	stroke(plaque, 3, INK)
	gradient(plaque, Color3.fromRGB(255, 240, 200), Color3.fromRGB(170, 120, 50))
	local title = text(plaque, "TitleLabel", UDim2.new(1, -20, 1, -10), UDim2.fromOffset(10, 5), "📖 COLLECTION")
	title.ZIndex = 9

	local close = Instance.new("TextButton")
	close.Name = "CloseButton"
	close.AnchorPoint = Vector2.new(0, 0)
	close.Position = UDim2.new(1, -27, 0, -19)
	close.Size = UDim2.fromOffset(46, 46)
	close.BackgroundColor3 = Color3.fromRGB(215, 60, 70)
	close.AutoButtonColor = false
	close.Text = ""
	close.ZIndex = 9
	close.Parent = panel
	corner(close, UDim.new(0, 12))
	stroke(close, 3, INK)
	text(close, "Text", UDim2.new(1, -12, 1, -10), UDim2.fromOffset(6, 5), "X").ZIndex = 10

	local sidebar = Instance.new("Frame")
	sidebar.Name = "Sidebar"
	sidebar.AnchorPoint = Vector2.new(1, 0)
	sidebar.Position = UDim2.new(0, 6, 0, 64)
	sidebar.Size = UDim2.fromOffset(62, 220)
	sidebar.BackgroundTransparency = 1
	sidebar.ZIndex = 7
	sidebar.Parent = panel
	local sideLayout = Instance.new("UIListLayout")
	sideLayout.Padding = UDim.new(0, 12)
	sideLayout.SortOrder = Enum.SortOrder.LayoutOrder
	sideLayout.Parent = sidebar
	for order, info in { { "TabOreMutations", "💎" }, { "TabMobs", "👺" }, { "TabCrystals", "🔮" } } do
		local tab = Instance.new("ImageButton")
		tab.Name = info[1]
		tab.LayoutOrder = order
		tab.Size = UDim2.fromOffset(60, 60)
		tab.BackgroundColor3 = GLASS
		tab.Image = ""
		tab.AutoButtonColor = false
		tab.ZIndex = 7
		tab.Parent = sidebar
		corner(tab, UDim.new(1, 0)) -- медальоны
		local selection = stroke(tab, 2, BRASS, false, "SelectionStroke")
		selection.Thickness = 2
		local icon = text(tab, "Icon", UDim2.new(1, -16, 1, -16), UDim2.fromOffset(8, 8), info[2])
		icon.ZIndex = 8
	end

	local function page(name, x)
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.Position = UDim2.fromOffset(x, 56)
		frame.Size = UDim2.fromOffset(390, 428)
		frame.BackgroundColor3 = HALL_DEEP
		frame.ZIndex = 6
		frame.Parent = panel
		corner(frame, UDim.new(0, 14))
		stroke(frame, 3, INK)
		return frame
	end

	local left = page("LeftPage", 28)
	local pageTitle = text(left, "PageTitle", UDim2.new(1, -150, 0, 28), UDim2.fromOffset(14, 8), "ORES", BRASS_TEXT)
	pageTitle.TextXAlignment = Enum.TextXAlignment.Left
	pageTitle.ZIndex = 7
	local chip = Instance.new("Frame")
	chip.Name = "ProgressChip"
	chip.Position = UDim2.new(1, -124, 0, 8)
	chip.Size = UDim2.fromOffset(112, 28)
	chip.BackgroundColor3 = INK
	chip.ZIndex = 7
	chip.Parent = left
	corner(chip, UDim.new(1, 0))
	stroke(chip, 2, AQUA)
	text(chip, "Text", UDim2.new(1, -12, 1, -6), UDim2.fromOffset(6, 3), "0/0", AQUA, Enum.Font.GothamBlack).ZIndex = 8
	local scroller = Instance.new("ScrollingFrame")
	scroller.Name = "Scroller"
	scroller.Position = UDim2.new(0, 10, 0, 44)
	scroller.Size = UDim2.new(1, -20, 1, -54)
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.ScrollBarThickness = 6
	scroller.ScrollBarImageColor3 = AQUA
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.CanvasSize = UDim2.new()
	scroller.ZIndex = 7
	scroller.Parent = left
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(112, 112)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.FillDirectionMaxCells = 3
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroller

	local right = page("RightPage", 446)
	local preview = Instance.new("ViewportFrame")
	preview.Name = "PreviewImage"
	preview.AnchorPoint = Vector2.new(0.5, 0)
	preview.Position = UDim2.new(0.5, 0, 0, 14)
	preview.Size = UDim2.fromOffset(180, 180)
	preview.BackgroundColor3 = GLASS
	preview.ZIndex = 7
	preview.Parent = right
	corner(preview, UDim.new(0, 16))
	stroke(preview, 3, AQUA)
	local camera = Instance.new("Camera")
	camera.Name = "PreviewCamera"
	camera.Parent = preview
	preview.CurrentCamera = camera
	local nameLabel = text(right, "ItemNameLabel", UDim2.new(1, -20, 0, 32), UDim2.fromOffset(10, 204), "PICK AN ITEM")
	nameLabel.ZIndex = 7
	local stats = Instance.new("Frame")
	stats.Name = "StatsRow"
	stats.Position = UDim2.fromOffset(10, 244)
	stats.Size = UDim2.new(1, -20, 0, 28)
	stats.BackgroundTransparency = 1
	stats.ZIndex = 7
	stats.Parent = right
	local price = text(stats, "PriceLabel", UDim2.new(0.5, -5, 1, 0), UDim2.new(), "", Color3.fromRGB(110, 255, 150))
	price.ZIndex = 8
	local chance = text(stats, "ChanceLabel", UDim2.new(0.5, -5, 1, 0), UDim2.new(0.5, 5, 0, 0), "", BRASS_TEXT)
	chance.ZIndex = 8
	local description = Instance.new("TextLabel")
	description.Name = "DescriptionLabel"
	description.Position = UDim2.fromOffset(14, 282)
	description.Size = UDim2.new(1, -28, 1, -292)
	description.BackgroundTransparency = 1
	description.Font = Enum.Font.GothamBold
	description.TextSize = 15
	description.TextWrapped = true
	description.RichText = true
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.TextColor3 = Color3.fromRGB(190, 215, 225)
	description.Text = ""
	description.ZIndex = 7
	description.Parent = right

	local templates = Instance.new("Folder")
	templates.Name = "Templates"
	templates.Parent = panel
	local item = Instance.new("ImageButton")
	item.Name = "ItemCell"
	item.Size = UDim2.fromOffset(112, 112)
	item.BackgroundColor3 = GLASS
	item.AutoButtonColor = false
	item.ScaleType = Enum.ScaleType.Fit
	item.Visible = false
	item.ZIndex = 8
	item.Parent = templates
	corner(item, UDim.new(0, 14))
	stroke(item, 3, AQUA)
	gradient(item, Color3.new(1, 1, 1), Color3.fromRGB(150, 190, 205))
	local locked = Instance.new("Frame")
	locked.Name = "LockedCell"
	locked.Size = UDim2.fromOffset(112, 112)
	locked.BackgroundColor3 = Color3.fromRGB(20, 34, 44)
	locked.Visible = false
	locked.ZIndex = 8
	locked.Parent = templates
	corner(locked, UDim.new(0, 14))
	stroke(locked, 3, INK)
	local mark = text(locked, "QuestionMark", UDim2.new(1, -40, 1, -40), UDim2.fromOffset(20, 20), "?", Color3.fromRGB(80, 110, 125))
	mark.ZIndex = 9
	return panel
end

-- Ставит панель в ScreenGui "CollectionMenu" (заменяя старую).
function Builder.Install(collectionGui)
	local existing = collectionGui:FindFirstChild("MutationBookPanel")
	if existing then existing:Destroy() end
	local panel = Builder.BuildPanel()
	panel.Parent = collectionGui
	return panel
end

return Builder
