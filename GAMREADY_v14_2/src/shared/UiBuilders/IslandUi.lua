--------------------------------------------------------------------------------
-- IslandUi (v20) — окно Island Keeper (покупка островов, улучшение печи)
-- + шаблон подписи над своим островом. Клиент: IslandUI.client.lua.
--
-- СТРУКТУРА (контракт):
--   ScreenGui "IslandUi" (Enabled=false)
--   ├─ TextButton "Dimmer"
--   └─ ImageLabel "Panel" [окно Blue, Flat] (UIScale "PanelScale")
--        ├─ TitleBar → "Title"; ImageButton "CloseButton"; TextLabel "Subtitle"
--        ├─ TextLabel "Toast" (под окном)
--        ├─ Frame "Content"
--        │   ├─ CanvasGroup "GridView" → ScrollingFrame "Cards", "Left", "Right"
--        │   │    (кнопки-стрелки), TextLabel "Hint", TextLabel "Footer"
--        │   └─ CanvasGroup "DetailView" → "Back", Frame "PreviewHolder",
--        │        Frame "Info" (UIListLayout) → "Title", "Desc", "PerksHeader",
--        │        Frame "Perks", ImageLabel "Upgrade" [Card] → "Title", "Pips", "Text";
--        │        TextLabel "Price", ImageButton "Action" [Button_Green]
--        └─ Folder "Templates"
--             ├─ ImageButton "Card" [Card] → "Shine", ImageLabel "Image", "Icon",
--             │    "Title", ImageLabel "Chip" [Pill] → "Text", "Lock", UIScale "Pop"
--             ├─ TextLabel "PerkLine"
--             ├─ ImageLabel "Pip" [Slot] → "Text"
--             └─ BillboardGui "IslandLabel" → "Title", "Tagline"
--------------------------------------------------------------------------------
local UiKit = require(script.Parent.Parent.UiKit)
local Theme = UiKit.Theme

local Builder = {}
Builder.VERSION = 20
Builder.PANEL_SIZE = Vector2.new(640, 470)
Builder.CARD_W = 140
Builder.CARD_H = 212

local function canvas(parent, name, visible)
	local c = Instance.new("CanvasGroup")
	c.Name = name
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Size = UDim2.fromScale(1, 1)
	c.Visible = visible
	c.ZIndex = 3
	c.Parent = parent
	return c
end

function Builder.BuildCard(parent, width, height)
	local card = UiKit.CardButton(parent, "Card", "Blue", {
		Size = UDim2.fromOffset(width or Builder.CARD_W, height or Builder.CARD_H),
		ZIndex = 4,
	})
	UiKit.Scale(card, "Pop", 1)
	local shine = UiKit.Group(card, "Shine", {
		BackgroundTransparency = 0.9,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 0.3, 0),
		ZIndex = 5,
	})
	UiKit.Gradient(shine, Color3.new(1, 1, 1), Color3.new(1, 1, 1), 90, "Fade").Transparency = UiKit.NSeq(0.2, 1)
	UiKit.Icon(card, "Image", "", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.1),
		Size = UDim2.fromScale(0.72, 0.36),
		ZIndex = 6,
	})
	UiKit.Text(card, "Icon", "🏝", {
		_Stroke = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.1),
		Size = UDim2.fromScale(0.72, 0.36),
		ZIndex = 6,
	}).FontFace = Font.fromEnum(Enum.Font.GothamBold)
	UiKit.Text(card, "Title", "ISLAND", {
		_Style = "Heading",
		Position = UDim2.new(0, 7, 0.5, 0),
		Size = UDim2.new(1, -14, 0.2, 0),
		ZIndex = 6,
	})
	local chip = UiKit.Plate(card, "Chip", "Pill", {
		_Accent = "Grey",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -16, 0.15, 0),
		ZIndex = 6,
	})
	UiKit.Text(chip, "Text", "$1K", {
		_Style = "Number",
		Position = UDim2.fromOffset(5, 3),
		Size = UDim2.new(1, -10, 1, -6),
		ZIndex = 7,
	})
	UiKit.Text(card, "Lock", "🔒", {
		_Stroke = 0,
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(28, 28),
		Visible = false,
		ZIndex = 8,
	}).FontFace = Font.fromEnum(Enum.Font.GothamBold)
	return card
end

function Builder.BuildLabel()
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "IslandLabel"
	billboard.Size = UDim2.fromOffset(360, 92)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 1500
	UiKit.Text(billboard, "Title", "ISLAND", {
		_Style = "Title",
		_Stroke = 3,
		Size = UDim2.fromScale(1, 0.55),
	})
	UiKit.Text(billboard, "Tagline", "", {
		_Style = "Heading",
		_Stroke = 2,
		Position = UDim2.fromScale(0, 0.58),
		Size = UDim2.fromScale(1, 0.4),
		TextColor3 = Theme.Colors.SubText,
	})
	return billboard
end

function Builder.Build()
	local gui = UiKit.Screen("IslandUi", { DisplayOrder = 30 })
	gui.Enabled = false
	gui:SetAttribute("UiKitVersion", Builder.VERSION)
	UiKit.Dimmer(gui, { Visible = true })

	local size = Builder.PANEL_SIZE
	local panel, parts = UiKit.Window(gui, "Panel", {
		Title = "Islands",
		Accent = "Blue",
		TitleAlign = "Left",
		Size = UDim2.fromOffset(size.X, size.Y),
		Position = UDim2.fromScale(0.5, 0.52),
		Visible = true,
		Flat = true,
		CloseInRoot = true,
	})
	UiKit.Scale(panel, "PanelScale", 1)
	local top, pad = parts.Top, parts.Pad
	UiKit.Text(panel, "Subtitle", "Unlock islands behind your base!", {
		_Style = "Body",
		_MaxTextSize = 17,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -60, 0, math.floor(Theme.Metrics.TitleBarHeight / 2)),
		Size = UDim2.fromOffset(300, 22),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Colors.SubText,
		ZIndex = 5,
	})

	local toast = UiKit.Text(panel, "Toast", "", {
		_Style = "Heading",
		_MaxTextSize = 20,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 10),
		Size = UDim2.new(1, -40, 0, 26),
		ZIndex = 9,
	})
	toast.TextTransparency = 1

	local content = UiKit.Group(panel, "Content", {
		Position = UDim2.fromOffset(pad, top - 4),
		Size = UDim2.new(1, -pad * 2, 1, -(top + pad - 4)),
		ClipsDescendants = true,
		ZIndex = 3,
	})

	-- ЭКРАН 1: карточки
	local grid = canvas(content, "GridView", true)
	UiKit.Scroll(grid, "Cards", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.new(1, -92, 0, Builder.CARD_H + 36),
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		HorizontalScrollBarInset = Enum.ScrollBarInset.None,
		ElasticBehavior = Enum.ElasticBehavior.Always,
		ZIndex = 3,
	})
	UiKit.List(grid.Cards, {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 16),
	})
	UiKit.Padding(grid.Cards, 0, 10, 8, 14)
	UiKit.Button(grid, "Left", "◀", "Blue", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.45, 0),
		Size = UDim2.fromOffset(36, 60),
		ZIndex = 4,
	})
	UiKit.Button(grid, "Right", "▶", "Blue", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.45, 0),
		Size = UDim2.fromOffset(36, 60),
		ZIndex = 4,
	})
	UiKit.Text(grid, "Hint", "Tap a card to see what it gives", {
		_Style = "Body",
		_MaxTextSize = 15,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -30),
		Size = UDim2.new(1, -20, 0, 18),
		TextColor3 = Theme.Colors.SubText,
		ZIndex = 4,
	})
	UiKit.Text(grid, "Footer", "", {
		_Style = "Heading",
		_MaxTextSize = 17,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, -20, 0, 22),
		ZIndex = 4,
	})

	-- ЭКРАН 2: выбранный остров
	local detail = canvas(content, "DetailView", false)
	UiKit.Button(detail, "Back", "◀ BACK", "Blue", {
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.fromOffset(110, 38),
		ZIndex = 4,
	})
	UiKit.Group(detail, "PreviewHolder", {
		Position = UDim2.fromOffset(28, 50),
		Size = UDim2.fromOffset(150, 224),
		ZIndex = 3,
	})
	local info = UiKit.Group(detail, "Info", {
		Position = UDim2.fromOffset(216, 4),
		Size = UDim2.new(1, -220, 1, -70),
		ZIndex = 3,
	})
	UiKit.List(info, { Padding = UDim.new(0, 6) })
	local function infoText(name, style, h, order, color, maxSize)
		return UiKit.Text(info, name, "", {
			_Style = style,
			_MaxTextSize = maxSize,
			Size = UDim2.new(1, 0, 0, h),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = color or Theme.Colors.Text,
			LayoutOrder = order,
			ZIndex = 4,
		})
	end
	infoText("Title", "Title", 34, 1, nil, 30)
	infoText("Desc", "Body", 40, 2, Theme.Colors.SubText, 16).TextYAlignment = Enum.TextYAlignment.Top
	infoText("PerksHeader", "Heading", 20, 3, Theme.Accents.Gold.Light, 17)
	local perks = UiKit.Group(info, "Perks", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 4,
		ZIndex = 3,
	})
	UiKit.List(perks, { Padding = UDim.new(0, 3) })
	local upgrade = UiKit.Card(info, "Upgrade", "Gold", {
		Size = UDim2.new(1, 0, 0, 108),
		LayoutOrder = 5,
		Visible = false,
		ZIndex = 3,
	})
	UiKit.Text(upgrade, "Title", "FURNACE", {
		_Style = "Heading",
		_MaxTextSize = 18,
		Position = UDim2.fromOffset(8, 6),
		Size = UDim2.new(1, -16, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	local pips = UiKit.Group(upgrade, "Pips", {
		Position = UDim2.fromOffset(8, 34),
		Size = UDim2.new(1, -16, 0, 26),
		ZIndex = 4,
	})
	UiKit.List(pips, { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) })
	local upgradeText = UiKit.Text(upgrade, "Text", "", {
		_Style = "Body",
		_MaxTextSize = 15,
		Position = UDim2.fromOffset(8, 64),
		Size = UDim2.new(1, -16, 0, 38),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Theme.Colors.SubText,
		ZIndex = 4,
	})
	upgradeText.LayoutOrder = 0
	UiKit.Text(detail, "Price", "", {
		_Style = "Number",
		_MaxTextSize = 24,
		Position = UDim2.new(0, 8, 1, -54),
		Size = UDim2.fromOffset(190, 28),
		TextColor3 = Theme.Colors.Money,
		ZIndex = 4,
	})
	UiKit.Button(detail, "Action", "BUY", "Green", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -4, 1, -6),
		Size = UDim2.new(1, -236, 0, 50),
		ZIndex = 4,
	})

	-- ШАБЛОНЫ
	local templates = Instance.new("Folder")
	templates.Name = "Templates"
	templates.Parent = panel
	Builder.BuildCard(templates)
	UiKit.Text(templates, "PerkLine", "✔ Perk", {
		_Style = "Body",
		_MaxTextSize = 16,
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	local pip = UiKit.Plate(templates, "Pip", "Slot", { Size = UDim2.fromOffset(46, 24), ZIndex = 5 })
	UiKit.Text(pip, "Text", "x1", {
		_Style = "Number",
		Position = UDim2.fromOffset(3, 2),
		Size = UDim2.new(1, -6, 1, -4),
		ZIndex = 6,
	})
	Builder.BuildLabel().Parent = templates
	return gui
end

return Builder
