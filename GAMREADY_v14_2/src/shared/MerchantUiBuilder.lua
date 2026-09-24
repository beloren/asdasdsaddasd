--------------------------------------------------------------------------------
-- MerchantUiBuilder (v20) — лавка торговца + табло биржи руды.
-- Единый стиль UiKit (акцент Green). tools/BuildAllUI.lua → StarterGui;
-- client/MerchantUI.client.lua собирает сам, если в PlayerGui ничего нет.
--
-- КОНТРАКТ ИМЁН (читает client/MerchantUI.client.lua):
--   MerchantUi/Window/Header/{Timer, Restock(Label), Close(Label)}
--   MerchantUi/Window/Market/{Caption, Hint, Value, Bucket/Label}
--   MerchantUi/Window/Tabs/<Tab.Id> (ImageButton → Label)
--   MerchantUi/Window/Body/List            — ScrollingFrame
--   MerchantUi/Window/Body/List/ItemTemplate — строка (Visible = false)
--       ItemTemplate/Main/{IconBox/{Icon, Emoji}, Name, Stock, Price, Rarity/Label}
--       ItemTemplate/Effect, ItemTemplate/BuyRow/Buy/Label
--   MarketTicker (отдельный ScreenGui) / Pill/{Value, Timer, Pop}
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UiKit = require(script.Parent.UiKit)
local Theme = UiKit.Theme

local MerchantUiBuilder = {}
MerchantUiBuilder.VERSION = 20

local ACCENT = "Green"

-- Кнопка UiKit с подписью "Label" (так её ищет клиент).
local function button(parent, name, label, variant, props)
	local b, caption = UiKit.Button(parent, name, label, variant, props)
	caption.Name = "Label"
	return b
end

function MerchantUiBuilder.Build()
	local okConfig, Config = pcall(require, ReplicatedStorage.Shared.Config)
	local tabs = okConfig and Config.Merchant and Config.Merchant.Tabs or { { Id = "Shop", Label = "SHOP" } }
	local accent = UiKit.Accent(ACCENT)

	local gui = UiKit.Screen("MerchantUi", { DisplayOrder = 30, Enabled = false })
	gui:SetAttribute("BuilderVersion", MerchantUiBuilder.VERSION)

	local window = UiKit.Plate(gui, "Window", "Panel", {
		_Accent = accent,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.44, 0.8),
	})
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(640, 720)
	sizeLimit.MinSize = Vector2.new(340, 380)
	sizeLimit.Parent = window
	UiKit.Scale(window, "OpenScale", 1)

	-- ШАПКА: таймер нового стока, RESTOCK, X.
	local header = UiKit.Plate(window, "Header", "TitleBar", {
		_Accent = accent,
		Size = UDim2.new(1, 0, 0, 58),
		ZIndex = 2,
	})
	UiKit.Ribbon(header, accent)
	UiKit.TitleText(header, "Timer", "New stock in 5m 00s", accent, {
		Position = UDim2.fromOffset(56, 8),
		Size = UDim2.new(1, -250, 0, 42),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
		_MaxTextSize = 34,
	})
	button(header, "Restock", "RESTOCK", "Blue", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -60, 0.5, 0),
		Size = UDim2.fromOffset(130, 38),
		ZIndex = 3,
	})
	local close = UiKit.CloseButton(header, { ZIndex = 4 })
	close.Name = "Close"
	close.Caption.Name = "Label"

	-- БИРЖА.
	local market = UiKit.Plate(window, "Market", "Inset", {
		Position = UDim2.fromOffset(12, 68),
		Size = UDim2.new(1, -24, 0, 58),
		ZIndex = 2,
	})
	UiKit.Text(market, "Caption", "ORE PRICE", {
		_Style = "Heading",
		Position = UDim2.fromOffset(12, 5),
		Size = UDim2.new(0.3, 0, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = accent.Light,
		ZIndex = 3,
	})
	UiKit.Text(market, "Hint", "Sell your ore now or wait?", {
		_Style = "Small",
		Position = UDim2.fromOffset(12, 33),
		Size = UDim2.new(0.34, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Colors.SubText,
		ZIndex = 3,
	})
	UiKit.Text(market, "Value", "x1.00", {
		_Style = "Number",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.52, 0.5),
		Size = UDim2.new(0.3, 0, 0, 44),
		ZIndex = 3,
	})
	local bucket = UiKit.Plate(market, "Bucket", "Pill", {
		_Accent = Theme.Accents.Grey,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.new(0.26, 0, 0, 34),
		BackgroundColor3 = Color3.fromRGB(120, 120, 120),
		BackgroundTransparency = 0,
		ZIndex = 3,
	})
	UiKit.Text(bucket, "Label", "NORMAL", {
		_Style = "Heading",
		Position = UDim2.fromScale(0.05, 0.1),
		Size = UDim2.fromScale(0.9, 0.8),
		ZIndex = 4,
	})

	-- ВКЛАДКИ.
	local tabsBar = UiKit.Group(window, "Tabs", {
		Position = UDim2.fromOffset(12, 134),
		Size = UDim2.new(1, -24, 0, 38),
		ZIndex = 2,
	})
	UiKit.List(tabsBar, { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) })
	for index, tab in tabs do
		local b = Instance.new("ImageButton")
		b.Name = tab.Id
		b.AutoButtonColor = false
		b.LayoutOrder = index
		b.Size = UDim2.new(1 / #tabs, -6, 1, 0)
		UiKit.ApplySkin(b, index == 1 and "TabActive" or "Tab", accent)
		UiKit.Text(b, "Label", tab.Label, {
			_Style = "Heading",
			Position = UDim2.fromScale(0.05, 0.12),
			Size = UDim2.fromScale(0.9, 0.76),
			ZIndex = 3,
		})
		b.ZIndex = 2
		b.Parent = tabsBar
	end

	-- СПИСОК.
	local body = UiKit.Plate(window, "Body", "Inset", {
		Position = UDim2.fromOffset(12, 180),
		Size = UDim2.new(1, -24, 1, -192),
		ZIndex = 2,
	})
	local list = UiKit.Scroll(body, "List", {
		Position = UDim2.fromOffset(4, 6),
		Size = UDim2.new(1, -8, 1, -12),
		ZIndex = 3,
	})
	UiKit.List(list, { Padding = UDim.new(0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center })
	UiKit.Padding(list, 6, 0, 6, 6)

	-- Строка товара: 118 свёрнута / 214 раскрыта (BuyRow).
	local item = UiKit.Card(list, "ItemTemplate", accent, {
		Size = UDim2.new(1, -18, 0, 118),
		Visible = false,
		ClipsDescendants = true,
		ZIndex = 3,
	})
	local main = Instance.new("TextButton")
	main.Name = "Main"
	main.BackgroundTransparency = 1
	main.Text = ""
	main.AutoButtonColor = false
	main.Size = UDim2.new(1, 0, 0, 118)
	main.ZIndex = 3
	main:SetAttribute("DisableGlobalHover", true)
	main.Parent = item

	local iconBox = UiKit.Slot(main, "IconBox", {
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(98, 98),
		ZIndex = 4,
	})
	UiKit.Icon(iconBox, "Icon", "", {
		Position = UDim2.fromScale(0.1, 0.1),
		Size = UDim2.fromScale(0.8, 0.8),
		ZIndex = 5,
	})
	local emoji = UiKit.Text(iconBox, "Emoji", "", {
		_Stroke = 0,
		Position = UDim2.fromScale(0.1, 0.1),
		Size = UDim2.fromScale(0.8, 0.8),
		ZIndex = 5,
	})
	emoji.FontFace = Font.fromEnum(Enum.Font.GothamBold)

	-- Плашка «LIMITED» над иконкой (включает клиент у лимитных товаров).
	local limited = UiKit.Plate(iconBox, "LimitedBadge", "Badge", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -6),
		Size = UDim2.new(1, 8, 0, 22),
		Visible = false,
		ZIndex = 7,
	})
	UiKit.Corner(limited, 0)
	UiKit.Text(limited, "Text", "LIMITED", { _Style = "Heading", ZIndex = 8 })

	UiKit.Text(main, "Name", "Item", {
		_Style = "Title",
		Position = UDim2.fromOffset(122, 8),
		Size = UDim2.new(1, -134, 0, 38),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
		_MaxTextSize = 34,
	})
	UiKit.Text(main, "Stock", "X0 Stock", {
		_Style = "Heading",
		Position = UDim2.fromOffset(122, 50),
		Size = UDim2.new(0.4, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Colors.SubText,
		ZIndex = 4,
	})
	UiKit.Text(main, "Price", "$0", {
		_Style = "Number",
		Position = UDim2.fromOffset(122, 76),
		Size = UDim2.new(0.4, 0, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Colors.Positive,
		ZIndex = 4,
	})
	local rarity = UiKit.Plate(main, "Rarity", "Pill", {
		_Accent = Theme.Accents.Grey,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -12),
		Size = UDim2.fromOffset(150, 38),
		BackgroundColor3 = Color3.fromRGB(170, 170, 170),
		BackgroundTransparency = 0,
		ZIndex = 4,
	})
	UiKit.Gradient(rarity, Color3.new(1, 1, 1), Color3.fromRGB(180, 180, 180), 90, "Shade")
	UiKit.Text(rarity, "Label", "Common", {
		_Style = "Heading",
		Position = UDim2.fromScale(0.05, 0.1),
		Size = UDim2.fromScale(0.9, 0.8),
		ZIndex = 5,
	})

	UiKit.Text(item, "Effect", "", {
		_Style = "Body",
		Position = UDim2.fromOffset(12, 120),
		Size = UDim2.new(1, -24, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 230, 170),
		ZIndex = 4,
	})
	local buyRow = UiKit.Group(item, "BuyRow", {
		Position = UDim2.fromOffset(10, 150),
		Size = UDim2.new(1, -20, 0, 56),
		ZIndex = 4,
	})
	button(buyRow, "Buy", "BUY", "Green", { Size = UDim2.fromScale(1, 1), ZIndex = 4, _TextStyle = "Title" })

	UiKit.Text(list, "EmptyNote", "Nothing in stock — wait for the next restock!", {
		_Style = "Heading",
		LayoutOrder = 99999,
		Size = UDim2.new(1, -30, 0, 70),
		TextColor3 = Theme.Colors.SubText,
		Visible = false,
		ZIndex = 3,
	})
	return gui
end

--------------------------------------------------------------------------------
-- ТАБЛО БИРЖИ (HUD): курс и время до смены — видно всегда, не только у банка.
--------------------------------------------------------------------------------
function MerchantUiBuilder.BuildMarketTicker()
	local gui = UiKit.Screen("MarketTicker", { DisplayOrder = 4, IgnoreGuiInset = false })
	local pill = UiKit.PlateButton(gui, "Pill", "Pill", {
		_Accent = ACCENT,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(250, 40),
	})
	pill:SetAttribute("DisableGlobalHover", true)
	UiKit.Text(pill, "Value", "ORE x1.00", {
		_Style = "Number",
		Position = UDim2.fromScale(0.05, 0.1),
		Size = UDim2.new(0.6, 0, 0.8, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
	})
	UiKit.Text(pill, "Timer", "5:00", {
		_Style = "Heading",
		Position = UDim2.fromScale(0.63, 0.15),
		Size = UDim2.new(0.32, 0, 0.7, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Colors.SubText,
		ZIndex = 2,
	})
	UiKit.Scale(pill, "Pop", 1)
	return gui
end

return MerchantUiBuilder
