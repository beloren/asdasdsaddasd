--------------------------------------------------------------------------------
-- BankPodiumUiBuilder (v9) — окно ПОДИУМА БАНКА (какой кристалл стоит на
-- подиуме и приносит деньги). Свой стиль: «изумрудный сейф» — тёмно-
-- зелёная бронированная дверь с заклёпками, золотая окантовка, вкладка
-- «🏦 BANK VAULT», полоска дохода. Встраивается в ScreenGui "GeodeUi"
-- (GeodeUiBuilder вызывает Install).
--
-- СТРУКТУРА (контракт GeodeUI.client.lua):
--   ImageLabel "PodiumPanel" (UIScale "ResponsiveScale")
--   ├─ Frame "Header" → TextLabel "Title"
--   ├─ ImageButton "CloseButton" → TextLabel "Caption"
--   ├─ Frame "BankIncome" → TextLabel "Text"      — «💰 +$X/SEC»
--   └─ ScrollingFrame "CrystalGrid" (UIGridLayout "CardLayout")
--        └─ ImageButton "CrystalCardTemplate" → "Name", ImageLabel "IconBackground"
--             → ImageLabel "Icon"; "Income", "Installed"
--------------------------------------------------------------------------------
local Builder = {}

local INK = Color3.fromRGB(4, 18, 12)
local VAULT = Color3.fromRGB(18, 66, 50)
local VAULT_DEEP = Color3.fromRGB(8, 34, 26)
local STEEL = Color3.fromRGB(34, 96, 74)
local GOLD = Color3.fromRGB(255, 205, 80)
local GOLD_TEXT = Color3.fromRGB(255, 225, 130)
local CASH = Color3.fromRGB(110, 255, 140)

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
	return g
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
	t.TextStrokeTransparency = 1
	t.ZIndex = zIndex or 4
	t.Parent = parent
	stroke(t, 2, INK, true)
	return t
end

function Builder.Install(gui)
	local existing = gui:FindFirstChild("PodiumPanel")
	if existing then existing:Destroy() end

	local panel = Instance.new("ImageLabel")
	panel.Name = "PodiumPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.52)
	panel.Size = UDim2.fromOffset(780, 510)
	panel.BackgroundColor3 = VAULT
	panel.Image = ""
	panel.Visible = false
	panel.ZIndex = 2
	panel.Parent = gui
	corner(panel, UDim.new(0, 20))
	stroke(panel, 6, INK)
	gradient(panel, Color3.fromRGB(255, 255, 255), Color3.fromRGB(120, 150, 135))
	local responsive = Instance.new("UIScale")
	responsive.Name = "ResponsiveScale"
	responsive.Parent = panel

	-- Золотая окантовка с медленным бликом (анимирует GeodeUI.client).
	local trim = Instance.new("Frame")
	trim.Name = "GoldTrim"
	trim.BackgroundTransparency = 1
	trim.Position = UDim2.fromOffset(7, 7)
	trim.Size = UDim2.new(1, -14, 1, -14)
	trim.ZIndex = 2
	trim.Parent = panel
	corner(trim, UDim.new(0, 15))
	local trimStroke = stroke(trim, 3, GOLD, false, "Trim")
	local shimmer = gradient(trimStroke, Color3.new(1, 1, 1), Color3.new(1, 1, 1), 0)
	shimmer.Name = "Shimmer"
	shimmer.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(190, 140, 40)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 248, 200)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 140, 40)),
	})
	-- Заклёпки по углам, как на двери сейфа.
	for _, anchor in { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) } do
		local rivet = Instance.new("Frame")
		rivet.Name = "Rivet"
		rivet.AnchorPoint = anchor
		rivet.Position = UDim2.new(anchor.X, anchor.X == 0 and 16 or -16, anchor.Y, anchor.Y == 0 and 16 or -16)
		rivet.Size = UDim2.fromOffset(14, 14)
		rivet.BackgroundColor3 = GOLD
		rivet.ZIndex = 3
		rivet.Parent = panel
		corner(rivet, UDim.new(1, 0))
		stroke(rivet, 2, INK)
	end

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Position = UDim2.fromOffset(-12, -26)
	header.Size = UDim2.fromOffset(300, 52)
	header.BackgroundColor3 = Color3.fromRGB(60, 200, 110)
	header.ZIndex = 6
	header.Parent = panel
	corner(header, UDim.new(0, 10))
	stroke(header, 3, INK)
	gradient(header, Color3.fromRGB(220, 255, 220), Color3.fromRGB(40, 150, 80))
	text(header, "Title", UDim2.new(1, -24, 1, -10), UDim2.fromOffset(14, 5), "🏦 BANK VAULT", nil, nil, 7).TextXAlignment = Enum.TextXAlignment.Left

	local close = Instance.new("ImageButton")
	close.Name = "CloseButton"
	close.Image = ""
	close.AutoButtonColor = false
	close.Position = UDim2.new(1, -27, 0, -19)
	close.Size = UDim2.fromOffset(46, 46)
	close.BackgroundColor3 = Color3.fromRGB(215, 55, 60)
	close.ZIndex = 8
	close.Parent = panel
	corner(close, UDim.new(0, 12))
	stroke(close, 3, INK)
	local closeCaption = text(close, "Caption", UDim2.new(1, -12, 1, -10), UDim2.fromOffset(6, 5), "X", nil, nil, 9)
	closeCaption.Name = "Caption"

	local income = Instance.new("Frame")
	income.Name = "BankIncome"
	income.Position = UDim2.new(1, -330, 0, 16)
	income.Size = UDim2.fromOffset(250, 36)
	income.BackgroundColor3 = VAULT_DEEP
	income.ZIndex = 5
	income.Parent = panel
	corner(income, UDim.new(1, 0))
	stroke(income, 2, GOLD)
	text(income, "Text", UDim2.new(1, -16, 1, -8), UDim2.fromOffset(8, 4), "PICK A CRYSTAL", GOLD_TEXT, Enum.Font.GothamBlack, 6)

	local grid = Instance.new("ScrollingFrame")
	grid.Name = "CrystalGrid"
	grid.Position = UDim2.fromOffset(22, 68)
	grid.Size = UDim2.new(1, -44, 1, -88)
	grid.BackgroundColor3 = VAULT_DEEP
	grid.BackgroundTransparency = 0.25
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 6
	grid.ScrollBarImageColor3 = GOLD
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.ZIndex = 3
	grid.Parent = panel
	corner(grid, UDim.new(0, 14))
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.Parent = grid
	local layout = Instance.new("UIGridLayout")
	layout.Name = "CardLayout"
	layout.CellSize = UDim2.fromOffset(170, 214)
	layout.CellPadding = UDim2.fromOffset(16, 16)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	-- Карточка кристалла — «ячейка сейфа»: стальная дверца, золотая рамка.
	local card = Instance.new("ImageButton")
	card.Name = "CrystalCardTemplate"
	card.Image = ""
	card.AutoButtonColor = false
	card.BackgroundColor3 = STEEL
	card.Visible = false
	card.ZIndex = 3
	card.Parent = grid
	corner(card, UDim.new(0, 14))
	stroke(card, 3, GOLD)
	gradient(card, Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 175, 165))
	text(card, "Name", UDim2.new(1, -12, 0, 24), UDim2.fromOffset(6, 6), "CRYSTAL")
	local background = Instance.new("ImageLabel")
	background.Name = "IconBackground"
	background.AnchorPoint = Vector2.new(0.5, 0)
	background.Position = UDim2.new(0.5, 0, 0, 34)
	background.Size = UDim2.fromOffset(140, 140)
	background.BackgroundColor3 = VAULT_DEEP
	background.ScaleType = Enum.ScaleType.Stretch
	background.ZIndex = 4
	background.Parent = card
	corner(background, UDim.new(1, 0)) -- круглая «витрина»
	stroke(background, 3, INK)
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.72, 0.72)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 5
	icon.Parent = background
	local incomeLabel = text(card, "Income", UDim2.new(1, -16, 0, 26), UDim2.new(0, 8, 1, -32), "$0/SEC", CASH, Enum.Font.GothamBlack)
	incomeLabel.ZIndex = 5
	local installed = text(card, "Installed", UDim2.fromOffset(84, 20), UDim2.new(1, -90, 0, 34), "ON", GOLD_TEXT)
	installed.TextXAlignment = Enum.TextXAlignment.Right
	installed.Visible = false
	installed.ZIndex = 6
	return panel
end

return Builder
