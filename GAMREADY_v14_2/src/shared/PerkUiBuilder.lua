--------------------------------------------------------------------------------
-- PerkUiBuilder (v20) — окно ПЕРКОВ ПРЕСТИЖА деревом + святилища.
-- Единый стиль UiKit (акцент Gold). tools/BuildAllUI.lua → StarterGui/PerkUi;
-- PerkUI.client.lua при отсутствии/старой версии строит сам.
--
-- СТРУКТУРА (имена — контракт; всё — прямые дети Panel):
--   ScreenGui "PerkUi" (BuilderVersion)
--   └─ ImageLabel "Panel" (окно; UIScale "AutoScale")
--        ├─ TitleBar → "Title", "Ribbon"
--        ├─ ImageButton "CloseButton"
--        ├─ ImageLabel "Points" [Pill] → TextLabel "Text"          — "⭐ 5"
--        ├─ Frame "Tabs" → ImageButton "PerksTab" / "ShrinesTab" (→ "Text")
--        ├─ ScrollingFrame "Shrines" → ImageButton "ShrineTemplate" (Icon, Title, Status)
--        ├─ ImageLabel "Tree" [Inset]
--        │    ├─ Frame "BranchTemplate" → ImageLabel "Header" → "Text"; Frame "Nodes"
--        │    ├─ ImageButton "NodeTemplate" → "Icon", ImageLabel "LevelChip" → "Level", "Lock", "CanBuy"
--        │    └─ ImageLabel "LinkTemplate"
--        └─ ImageLabel "Detail" [Card]
--             ├─ TextLabel "Icon", "Title", "Level", "Now", "Next", "Hint"
--             └─ ImageButton "UpgradeButton" → TextLabel "Text"
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local UiKit = require(script.Parent.UiKit)
local Theme = UiKit.Theme

local Builder = {}
Builder.Width = 800
Builder.Height = 520
Builder.VERSION = 22

local GOLD = Theme.Accents.Gold
local STAR = Color3.fromRGB(80, 70, 150)

local function button(parent, name, label, variant, props)
	local b, caption = UiKit.Button(parent, name, label, variant, props)
	caption.Name = "Text"
	caption.TextWrapped = false -- v20.21: «🗿 SHRINES» не разваливается на две строки
	return b
end

-- v20.21: иконка на кнопке — ImageLabel "Icon" (впиши Image в Studio или
-- ImageId в Config), без картинки виден эмодзи-запасной "Emoji" внутри.
local function iconSlot(parent, name, emoji, props)
	local zIndex = props.ZIndex or 4
	props._Stroke = nil
	local icon = UiKit.Icon(parent, name, "", props)
	local text = UiKit.Text(icon, "Emoji", emoji, { _Stroke = 0, ZIndex = zIndex })
	text.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	return icon
end

local function emojiText(parent, name, content, props)
	local t = UiKit.Text(parent, name, content, props)
	t.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	return t
end

function Builder.Build()
	local gui = UiKit.Screen("PerkUi", { DisplayOrder = 31, Enabled = false })
	gui:SetAttribute("BuilderVersion", math.max(Config.Prestige and Config.Prestige.PerkUiVersion or 2, Builder.VERSION))

	local panel, parts = UiKit.Window(gui, "Panel", {
		Title = "⭐ Prestige Perks",
		Accent = "Gold",
		Size = UDim2.fromOffset(Builder.Width, Builder.Height),
		Position = UDim2.fromScale(0.5, 0.53),
		Visible = true,
		Flat = true,
		CloseInRoot = true,
		TitleAlign = "Left",
	})
	UiKit.Scale(panel, "AutoScale", 1)
	local top, pad = parts.Top, parts.Pad

	-- Очки престижа — справа в полосе заголовка.
	local points = UiKit.Plate(panel, "Points", "Pill", {
		_Accent = GOLD,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -60, 0, 27),
		Size = UDim2.fromOffset(120, 34),
		ZIndex = 6,
	})
	UiKit.Text(points, "Text", "⭐ 0", {
		_Style = "Number",
		Position = UDim2.fromOffset(6, 3),
		Size = UDim2.new(1, -12, 1, -6),
		TextColor3 = GOLD.Light,
		ZIndex = 7,
	})

	-- Вкладки PERKS / SHRINES.
	local tabs = UiKit.Group(panel, "Tabs", {
		Position = UDim2.fromOffset(pad, top),
		Size = UDim2.fromOffset(290, 36),
		ZIndex = 3,
	})
	UiKit.List(tabs, { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) })
	button(tabs, "PerksTab", "PERKS", "Yellow", { LayoutOrder = 1, Size = UDim2.fromOffset(120, 36), ZIndex = 3 })
	button(tabs, "ShrinesTab", "🗿 SHRINES", "Dark", { LayoutOrder = 2, Size = UDim2.fromOffset(150, 36), ZIndex = 3 })

	local contentTop = top + 46
	local contentSize = UDim2.new(1, -(pad * 2 + 300), 1, -(contentTop + pad))

	-- СВЯТИЛИЩА.
	local shrines = UiKit.Scroll(panel, "Shrines", {
		Position = UDim2.fromOffset(pad, contentTop),
		Size = contentSize,
		Visible = false,
		ZIndex = 3,
	})
	UiKit.Grid(shrines, UDim2.fromOffset(142, 96), UDim2.fromOffset(10, 10), { HorizontalAlignment = Enum.HorizontalAlignment.Center })
	UiKit.Padding(shrines, 10, 4, 10, 10)
	local shrine = UiKit.CardButton(shrines, "ShrineTemplate", STAR, { Visible = false, ZIndex = 3 })
	shrine.BackgroundColor3 = Color3.fromRGB(34, 30, 60)
	iconSlot(shrine, "Icon", "🗿", { Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(40, 40), ZIndex = 4 })
	UiKit.Text(shrine, "Title", "Shrine", {
		_Style = "Heading",
		Position = UDim2.fromOffset(52, 10),
		Size = UDim2.new(1, -60, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	UiKit.Text(shrine, "Status", "⭐ 3", {
		_Style = "Number",
		Position = UDim2.new(0, 8, 1, -34),
		Size = UDim2.new(1, -16, 0, 26),
		TextColor3 = GOLD.Light,
		ZIndex = 4,
	})

	-- ДЕРЕВО.
	local tree = UiKit.Plate(panel, "Tree", "Inset", {
		Position = UDim2.fromOffset(pad, contentTop),
		Size = contentSize,
		ZIndex = 3,
	})
	UiKit.List(tree, {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 10),
	})
	UiKit.Padding(tree, 0, 0, 10, 10)

	local branch = UiKit.Group(tree, "BranchTemplate", { Visible = false, Size = UDim2.new(0.31, 0, 1, 0) })
	local header = UiKit.Plate(branch, "Header", "Pill", {
		_Accent = GOLD,
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = GOLD.Main,
		BackgroundTransparency = 0,
		ZIndex = 4,
	})
	UiKit.Text(header, "Text", "BRANCH", {
		_Style = "Heading",
		Position = UDim2.fromOffset(7, 4),
		Size = UDim2.new(1, -14, 1, -8),
		ZIndex = 5,
	})
	UiKit.Group(branch, "Nodes", { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40) })

	-- Узел-«звезда»: круглая кнопка, заливку красит клиент по ветке.
	local node = Instance.new("ImageButton")
	node.Name = "NodeTemplate"
	node.AutoButtonColor = false
	node.Visible = false
	node.AnchorPoint = Vector2.new(0.5, 0)
	node.Size = UDim2.fromOffset(70, 70)
	UiKit.ApplySkin(node, "Round")
	node.BackgroundColor3 = STAR
	node.BackgroundTransparency = 0
	node.ZIndex = 5
	node.Parent = tree
	local skinStroke = node:FindFirstChild("SkinStroke")
	if skinStroke then skinStroke:Destroy() end
	UiKit.Stroke(node, Color3.fromRGB(10, 8, 24), 3, 0, "Outline")
	UiKit.Gradient(node, Color3.new(1, 1, 1), Color3.fromRGB(175, 175, 200), 90, "Shade")
	UiKit.Scale(node, "PressScale", 1)
	iconSlot(node, "Icon", "💰", { Position = UDim2.new(0.18, 0, 0.1, 0), Size = UDim2.fromScale(0.64, 0.6), ZIndex = 6 })
	local chip = UiKit.Plate(node, "LevelChip", "Pill", {
		_Accent = GOLD,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, -2),
		Size = UDim2.fromOffset(58, 22),
		BackgroundTransparency = 0.1,
		ZIndex = 7,
	})
	UiKit.Text(chip, "Level", "0/25", {
		_Style = "Number",
		Position = UDim2.fromOffset(4, 2),
		Size = UDim2.new(1, -8, 1, -4),
		TextColor3 = GOLD.Light,
		ZIndex = 8,
	})
	emojiText(node, "Lock", "🔒", { _Stroke = 0, Position = UDim2.new(1, -22, 0, -8), Size = UDim2.fromOffset(28, 28), Visible = false, ZIndex = 9 })
	UiKit.Text(node, "CanBuy", "+", {
		_Style = "Title",
		Position = UDim2.new(1, -18, 0, -8),
		Size = UDim2.fromOffset(26, 26),
		TextColor3 = Theme.Colors.Positive,
		Visible = false,
		ZIndex = 9,
	})

	local link = UiKit.Plate(tree, "LinkTemplate", "Divider", {
		_Accent = GOLD,
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(6, 26),
		ZIndex = 4,
	})
	link.BackgroundColor3 = GOLD.Main

	-- ПАНЕЛЬ ПЕРКА справа.
	local detail = UiKit.Card(panel, "Detail", GOLD, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -pad, 0, top),
		Size = UDim2.new(0, 290, 1, -(top + pad)),
		ZIndex = 3,
	})
	iconSlot(detail, "Icon", "💰", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.fromOffset(90, 90), ZIndex = 4 })
	UiKit.Text(detail, "Title", "Money", { _Style = "Title", Position = UDim2.fromOffset(10, 110), Size = UDim2.new(1, -20, 0, 36), ZIndex = 4 })
	UiKit.Text(detail, "Level", "LV 0/25", { _Style = "Number", Position = UDim2.fromOffset(10, 148), Size = UDim2.new(1, -20, 0, 24), TextColor3 = GOLD.Light, ZIndex = 4 })
	UiKit.Text(detail, "Now", "+0%", { _Style = "Body", Position = UDim2.fromOffset(10, 186), Size = UDim2.new(1, -20, 0, 24), TextColor3 = Theme.Colors.SubText, ZIndex = 4 })
	UiKit.Text(detail, "Next", "> +4%", { _Style = "Heading", Position = UDim2.fromOffset(10, 214), Size = UDim2.new(1, -20, 0, 28), TextColor3 = Theme.Colors.Positive, ZIndex = 4 })
	UiKit.Text(detail, "Hint", "", { _Style = "Small", Position = UDim2.new(0, 10, 1, -108), Size = UDim2.new(1, -20, 0, 22), TextColor3 = Color3.fromRGB(255, 160, 110), Visible = false, ZIndex = 4 })
	button(detail, "UpgradeButton", "⭐ 1", "Green", {
		Position = UDim2.new(0, 14, 1, -74),
		Size = UDim2.new(1, -28, 0, 60),
		ZIndex = 4,
		_TextStyle = "Title",
	})
	return gui
end

return Builder
