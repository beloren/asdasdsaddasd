--------------------------------------------------------------------------------
-- MerchantUiBuilder — окно лавки торговца в стиле стока Grow a Garden:
-- травяная шапка с таймером "New stock in 3m 17s", синяя RESTOCK, красный X,
-- деревянная панель с заклёпками, строки товаров (иконка в светлой рамке,
-- крупное имя с обводкой, "X11 Stock", зелёная цена, плашка редкости).
--
-- Под шапкой — табло БИРЖИ: текущий курс продажи руды крупно, цветом
-- корзины (CRASH…JACKPOT). Курс и сток меняются одним таймером.
--
-- КОНТРАКТ ИМЁН (читает client/MerchantUI.client.lua):
--   MerchantUi/Window/Header/{Timer, Restock, Close}
--   MerchantUi/Window/Market/{Value, Bucket, Hint}
--   MerchantUi/Window/Body/List            — ScrollingFrame
--   MerchantUi/Window/Body/List/ItemTemplate — строка (Visible = false)
--       ItemTemplate/Main/{IconBox/{Icon, Emoji}, Name, Stock, Price, Rarity/Label}
--       ItemTemplate/BuyRow/Buy/Label
--   MarketTicker (отдельный ScreenGui) / Pill/{Value, Timer}
--------------------------------------------------------------------------------
local MerchantUiBuilder = {}

local FONT = Enum.Font.FredokaOne
local WOOD = Color3.fromRGB(128, 74, 40)
local WOOD_DARK = Color3.fromRGB(86, 46, 22)
local WOOD_DEEP = Color3.fromRGB(70, 36, 16)
local CARD = Color3.fromRGB(74, 36, 16)
local ICON_BOX = Color3.fromRGB(142, 90, 55)
local GRASS = Color3.fromRGB(96, 196, 64)
local GRASS_DARK = Color3.fromRGB(62, 150, 40)

local function corner(parent, radius)
	local instance = Instance.new("UICorner")
	instance.CornerRadius = UDim.new(0, radius or 8)
	instance.Parent = parent
	return instance
end

local function stroke(parent, color, thickness, mode)
	local instance = Instance.new("UIStroke")
	instance.Color = color
	instance.Thickness = thickness or 3
	if mode then instance.ApplyStrokeMode = mode end
	instance.Parent = parent
	return instance
end

local function frame(name, parent, props)
	local instance = Instance.new("Frame")
	instance.Name = name
	instance.BorderSizePixel = 0
	for key, value in props or {} do instance[key] = value end
	instance.Parent = parent
	return instance
end

-- Крупный текст с чёрной обводкой — фирменный вид GaG.
local function text(name, parent, props)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	for key, value in props or {} do
		-- MaxText/StrokeThickness — параметры хелпера, не свойства Instance.
		if key ~= "MaxText" and key ~= "StrokeThickness" then label[key] = value end
	end
	label.Parent = parent
	stroke(label, Color3.fromRGB(0, 0, 0), props and props.StrokeThickness or 2.5)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = props and props.MaxText or 40
	limit.Parent = label
	return label
end

local function button(name, parent, color, borderColor, props)
	local instance = Instance.new("TextButton")
	instance.Name = name
	instance.AutoButtonColor = true
	instance.BackgroundColor3 = color
	instance.BorderSizePixel = 0
	instance.Text = ""
	for key, value in props or {} do instance[key] = value end
	instance.Parent = parent
	corner(instance, 6)
	stroke(instance, borderColor, 3, Enum.ApplyStrokeMode.Border)
	return instance
end

-- Ряд "заклёпок" — мелких квадратиков по краю, как по периметру окна GaG.
local function studs(parent, color, count, y)
	local row = frame("Studs", parent, {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -16, 0, 8),
		Position = UDim2.new(0, 8, 0, y),
	})
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 10)
	layout.Parent = row
	for _ = 1, count do
		local stud = frame("Stud", row, { BackgroundColor3 = color, Size = UDim2.fromOffset(12, 8) })
		corner(stud, 2)
	end
	return row
end

function MerchantUiBuilder.Build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "MerchantUi"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 30
	gui.Enabled = false

	local window = frame("Window", gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.44, 0.8),
		BackgroundColor3 = WOOD,
	})
	corner(window, 8)
	stroke(window, WOOD_DEEP, 4)
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(640, 720)
	sizeLimit.MinSize = Vector2.new(320, 360)
	sizeLimit.Parent = window
	local windowScale = Instance.new("UIScale")
	windowScale.Name = "OpenScale"
	windowScale.Parent = window

	----------------------------------------------------------------------
	-- ШАПКА
	----------------------------------------------------------------------
	local header = frame("Header", window, {
		Size = UDim2.new(1, 0, 0, 70),
		BackgroundColor3 = GRASS,
	})
	corner(header, 8)
	local grassGradient = Instance.new("UIGradient")
	grassGradient.Rotation = 90
	grassGradient.Color = ColorSequence.new(Color3.fromRGB(140, 225, 90), GRASS)
	grassGradient.Parent = header
	-- Нижний край шапки без скругления + травяная кромка с заклёпками.
	frame("Lip", header, { Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -14), BackgroundColor3 = GRASS_DARK })
	studs(header, Color3.fromRGB(120, 215, 80), 20, 58)

	text("Timer", header, {
		Text = "New stock in 5m 00s",
		Size = UDim2.new(1, -250, 0, 44),
		Position = UDim2.fromOffset(14, 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 34, StrokeThickness = 3,
	})
	local restock = button("Restock", header, Color3.fromRGB(30, 130, 255), Color3.fromRGB(10, 60, 170), {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -70, 0, 9),
		Size = UDim2.fromOffset(160, 42),
	})
	text("Label", restock, { Text = "RESTOCK", Size = UDim2.fromScale(0.9, 0.8), Position = UDim2.fromScale(0.05, 0.1), MaxText = 28 })
	local close = button("Close", header, Color3.fromRGB(225, 35, 35), Color3.fromRGB(120, 10, 10), {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 9),
		Size = UDim2.fromOffset(46, 42),
	})
	text("Label", close, { Text = "X", Size = UDim2.fromScale(0.8, 0.85), Position = UDim2.fromScale(0.1, 0.07), MaxText = 32 })

	----------------------------------------------------------------------
	-- БИРЖА
	----------------------------------------------------------------------
	local market = frame("Market", window, {
		Size = UDim2.new(1, -24, 0, 58),
		Position = UDim2.fromOffset(12, 80),
		BackgroundColor3 = WOOD_DEEP,
	})
	corner(market, 8)
	stroke(market, Color3.fromRGB(50, 24, 10), 3)
	text("Caption", market, {
		Text = "ORE PRICE", Size = UDim2.new(0.3, 0, 0, 26), Position = UDim2.fromOffset(12, 6),
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(230, 210, 180), MaxText = 22,
	})
	text("Hint", market, {
		Text = "Sell your ore now or wait?", Size = UDim2.new(0.34, 0, 0, 18), Position = UDim2.fromOffset(12, 33),
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(200, 180, 150), MaxText = 16, StrokeThickness = 1.5,
	})
	text("Value", market, {
		Text = "x1.00", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.52, 0.5),
		Size = UDim2.new(0.3, 0, 0, 46), MaxText = 44, StrokeThickness = 3,
	})
	local bucket = frame("Bucket", market, {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.new(0.26, 0, 0, 34), BackgroundColor3 = Color3.fromRGB(120, 120, 120),
	})
	corner(bucket, 17)
	stroke(bucket, Color3.fromRGB(30, 30, 30), 2.5, Enum.ApplyStrokeMode.Border)
	text("Label", bucket, { Text = "NORMAL", Size = UDim2.fromScale(0.9, 0.78), Position = UDim2.fromScale(0.05, 0.11), MaxText = 22 })

	----------------------------------------------------------------------
	-- СПИСОК
	----------------------------------------------------------------------
	local body = frame("Body", window, {
		Size = UDim2.new(1, -24, 1, -162),
		Position = UDim2.fromOffset(12, 150),
		BackgroundColor3 = WOOD_DARK,
	})
	corner(body, 8)
	stroke(body, WOOD_DEEP, 3)

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.new(1, -8, 1, -12)
	list.Position = UDim2.fromOffset(4, 6)
	list.ScrollBarThickness = 8
	list.ScrollBarImageColor3 = Color3.fromRGB(230, 200, 160)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Parent = body
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = list
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.Parent = list

	-- Строка товара. Высота = 118 свёрнута / 186 раскрыта (BuyRow).
	local item = frame("ItemTemplate", list, {
		Size = UDim2.new(1, -18, 0, 118),
		BackgroundColor3 = CARD,
		Visible = false,
		ClipsDescendants = true,
	})
	corner(item, 8)
	stroke(item, Color3.fromRGB(50, 22, 8), 3)

	local main = Instance.new("TextButton")
	main.Name = "Main"
	main.BackgroundTransparency = 1
	main.Text = ""
	main.AutoButtonColor = false
	main.Size = UDim2.new(1, 0, 0, 118)
	main.Parent = item

	local iconBox = frame("IconBox", main, {
		Size = UDim2.fromOffset(98, 98),
		Position = UDim2.fromOffset(10, 10),
		BackgroundColor3 = ICON_BOX,
	})
	corner(iconBox, 6)
	stroke(iconBox, Color3.fromRGB(60, 30, 12), 3)
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromScale(0.8, 0.8)
	icon.Position = UDim2.fromScale(0.1, 0.1)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = iconBox
	local emoji = Instance.new("TextLabel")
	emoji.Name = "Emoji"
	emoji.BackgroundTransparency = 1
	emoji.Size = UDim2.fromScale(0.8, 0.8)
	emoji.Position = UDim2.fromScale(0.1, 0.1)
	emoji.TextScaled = true
	emoji.Font = Enum.Font.GothamBold
	emoji.Text = ""
	emoji.Parent = iconBox

	text("Name", main, {
		Text = "Item", Size = UDim2.new(1, -134, 0, 40), Position = UDim2.fromOffset(122, 8),
		TextXAlignment = Enum.TextXAlignment.Left, MaxText = 34, StrokeThickness = 3,
	})
	text("Stock", main, {
		Text = "X0 Stock", Size = UDim2.new(0.4, 0, 0, 24), Position = UDim2.fromOffset(122, 52),
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(205, 205, 205), MaxText = 24, StrokeThickness = 2,
	})
	text("Price", main, {
		Text = "$0", Size = UDim2.new(0.4, 0, 0, 34), Position = UDim2.fromOffset(122, 78),
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(40, 255, 40), MaxText = 34, StrokeThickness = 3,
	})
	local rarity = frame("Rarity", main, {
		AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -12),
		Size = UDim2.fromOffset(150, 40), BackgroundColor3 = Color3.fromRGB(170, 170, 170),
	})
	corner(rarity, 6)
	stroke(rarity, Color3.fromRGB(235, 235, 235), 2.5, Enum.ApplyStrokeMode.Border)
	local rarityShade = Instance.new("UIGradient")
	rarityShade.Rotation = 90
	rarityShade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190))
	rarityShade.Parent = rarity
	text("Label", rarity, { Text = "Common", Size = UDim2.fromScale(0.9, 0.8), Position = UDim2.fromScale(0.05, 0.1), MaxText = 28 })

	-- Раскрывающаяся полоса покупки.
	local buyRow = frame("BuyRow", item, {
		Size = UDim2.new(1, -20, 0, 56),
		Position = UDim2.fromOffset(10, 122),
		BackgroundTransparency = 1,
	})
	local buy = button("Buy", buyRow, Color3.fromRGB(60, 200, 60), Color3.fromRGB(20, 100, 20), {
		Size = UDim2.fromScale(1, 1),
	})
	local buyShade = Instance.new("UIGradient")
	buyShade.Rotation = 90
	buyShade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200))
	buyShade.Parent = buy
	text("Label", buy, { Text = "BUY", Size = UDim2.fromScale(0.9, 0.72), Position = UDim2.fromScale(0.05, 0.14), MaxText = 32, StrokeThickness = 3 })

	return gui
end

--------------------------------------------------------------------------------
-- ТАБЛО БИРЖИ (HUD): курс и время до смены — видно всегда, не только у банка.
--------------------------------------------------------------------------------
function MerchantUiBuilder.BuildMarketTicker()
	local gui = Instance.new("ScreenGui")
	gui.Name = "MarketTicker"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 4

	local pill = Instance.new("TextButton")
	pill.Name = "Pill"
	pill.Text = ""
	pill.AutoButtonColor = false
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.new(0.5, 0, 0, 6)
	pill.Size = UDim2.fromOffset(250, 40)
	pill.BackgroundColor3 = WOOD_DARK
	pill.BorderSizePixel = 0
	pill.Parent = gui
	corner(pill, 20)
	stroke(pill, WOOD_DEEP, 3, Enum.ApplyStrokeMode.Border)
	text("Value", pill, {
		Text = "ORE x1.00", Size = UDim2.new(0.6, 0, 0.8, 0), Position = UDim2.fromScale(0.05, 0.1),
		TextXAlignment = Enum.TextXAlignment.Left, MaxText = 24,
	})
	text("Timer", pill, {
		Text = "5:00", Size = UDim2.new(0.32, 0, 0.7, 0), Position = UDim2.fromScale(0.63, 0.15),
		TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Color3.fromRGB(230, 210, 180), MaxText = 20,
	})
	local scale = Instance.new("UIScale")
	scale.Name = "Pop"
	scale.Parent = pill
	return gui
end

return MerchantUiBuilder
