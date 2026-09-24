--------------------------------------------------------------------------------
-- ShopUi (v20.4) — магазин за Robux (стиль «Prospector's Shop»).
-- Клиент: CustomCartUI.client.lua (setupShopUi) — клонирует шаблоны под
-- реальные товары из Config.Shop.Items и Config.Shop.ForeverPack.
--
-- СТРУКТУРА (имена — контракт):
--   ScreenGui "ShopUi"
--   ├─ TextButton "Dimmer"
--   ├─ ImageLabel "Panel" (окно UiKit.Window, акцент Purple)
--   │    ├─ "TitleBar" → "Title", "Ribbon", "CloseButton"
--   │    └─ "Frame" → Frame "Content"
--   │         ├─ ScrollingFrame "NavBar" → ImageButton "Nav_<Tab>" (+ "Caption") —
--   │         │    клик листает список к секции
--   │         └─ ScrollingFrame "Body"
--   │              ├─ Frame "Section_Forever" — FOREVER PACK:
--   │              │    "SectionHeader", TextLabel "Refresh",
--   │              │    Frame "Row" → ImageLabel "Chain" [Inset] → "Step1".."Step<N>"
--   │              │    (ImageLabel [Card] → "Title", "IconHolder"(Rays, Icon→Emoji),
--   │              │     ImageButton "Button" → "Caption", TextLabel "Done"),
--   │              │    ImageButton "BigCard" [Card] → "Rays", "Glow", "Icon"→"Emoji",
--   │              │     "Title", "Subtitle", ImageButton "Button" → "Caption"
--   │              └─ Frame "Section_<Tab>" (по Config.Shop.Tabs)
--   │                   ├─ Frame "SectionHeader" → "Label", "LineLeft", "LineRight"
--   │                   └─ Frame "Cards_<Tab>" (UIGridLayout, 2 колонки)
--   ├─ ImageLabel "CardTemplate" (Visible=false)
--   │    ├─ ImageLabel "IconHolder" → "Rays", "IconGlow", ImageLabel "PlaceholderIcon" → "Emoji"
--   │    ├─ TextLabel "Title", TextLabel "Description"
--   │    ├─ ImageLabel "Badge" → TextLabel "Count"
--   │    └─ ImageButton "PriceButton" → TextLabel "Caption", ImageLabel "RobuxIcon"
--   └─ ImageLabel "EmptyCardTemplate" (Visible=false) — «?»: товара ещё нет
--
-- ПРОБЕЛЫ МЕЖДУ КАТЕГОРИЯМИ: подложки секций не участвуют в раскладке,
-- отступы — 10px между секциями, 6px внутри.
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = script.Parent.Parent
local UiKit = require(Shared.UiKit)
local Config = require(ReplicatedStorage.Shared.Config)

local Builder = {}
Builder.VERSION = 21

local DEFAULT_TAB_ACCENTS = {
	Cash = "Green", Boosts = "Gold", Passes = "Purple", Weather = "Blue",
	Geodes = "Orange", Dynamite = "Red", Deals = "Pink", Skins = "Teal", Forever = "Orange",
}

function Builder.TabAccent(tabName)
	local accents = Config.Shop and Config.Shop.TabAccents
	return (accents and accents[tabName]) or DEFAULT_TAB_ACCENTS[tabName] or "Purple"
end

local CARD_HEIGHT = 128
Builder.CARD_HEIGHT = CARD_HEIGHT

-- Лучи за иконкой (как сияние у товаров на референсе). Анимирует клиент.
function Builder.BuildRays(parent, count, color, transparency)
	local rays = UiKit.Group(parent, "Rays", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.6, 1.6),
		ZIndex = (parent.ZIndex or 1),
	})
	for i = 1, count do
		local ray = UiKit.Group(rays, "Ray" .. i, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0.09, 0, 1, 0),
			Rotation = (i - 1) * (180 / count),
			BackgroundColor3 = color or Color3.new(1, 1, 1),
			BackgroundTransparency = transparency or 0.75,
			ZIndex = rays.ZIndex,
		})
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = ray
	end
	return rays
end

function Builder.BuildCard()
	local card = UiKit.Card(nil, "CardTemplate", "Purple", {
		Size = UDim2.new(0.5, -6, 0, CARD_HEIGHT),
		Visible = false,
		ClipsDescendants = true,
	})
	local tint = UiKit.Gradient(card, Color3.new(1, 1, 1), Color3.new(1, 1, 1), 90, "Tint")
	tint.Transparency = UiKit.NSeq(0.55, 1)

	local holder = UiKit.Plate(card, "IconHolder", "Inset", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(CARD_HEIGHT - 24, CARD_HEIGHT - 24),
		ZIndex = 2,
	})
	UiKit.Corner(holder, 999)
	Builder.BuildRays(holder, 6, Color3.new(1, 1, 1), 0.82)
	UiKit.Plate(holder, "IconGlow", "Glow", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.35, 1.35),
		ZIndex = 2,
	})
	local icon = UiKit.Icon(holder, "PlaceholderIcon", "", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.82, 0.82),
		ZIndex = 3,
	})
	local emoji = UiKit.Text(icon, "Emoji", "🛒", { _Stroke = 0, ZIndex = 4 })
	emoji.FontFace = Font.fromEnum(Enum.Font.GothamBold)

	local left = CARD_HEIGHT - 4
	local purple = UiKit.Accent("Purple")
	UiKit.Text(card, "Title", "Item", {
		_Style = "Title",
		_Stroke = 2,
		_MaxTextSize = 28,
		_Gradient = { purple.Light, purple.Main },
		Position = UDim2.fromOffset(left, 8),
		Size = UDim2.new(1, -left - 10, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 2,
	})
	UiKit.Text(card, "Description", "", {
		_Style = "Heading",
		_MaxTextSize = 19,
		Position = UDim2.fromOffset(left, 40),
		Size = UDim2.new(1, -left - 10, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 2,
	})

	local badge = UiKit.Badge(card, "Badge", "NEW", {
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.fromOffset(46, 20),
		Visible = false,
		ZIndex = 5,
	})
	UiKit.Corner(badge, 0)

	UiKit.RobuxButton(card, "PriceButton", "99", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, left, 1, -10),
		Size = UDim2.new(1, -left - 10, 0, 38),
		ZIndex = 2,
	})
	return card
end

-- «?» — место под будущий товар (референс: пустая ячейка с вопросом).
function Builder.BuildEmptyCard()
	local card = UiKit.Card(nil, "EmptyCardTemplate", "Grey", {
		Size = UDim2.new(0.5, -6, 0, CARD_HEIGHT),
		Visible = false,
	})
	card.BackgroundTransparency = 0.35
	local stroke = card:FindFirstChild("SkinStroke")
	if stroke then stroke.Transparency = 0.5 end
	UiKit.Text(card, "Mark", "?", {
		_Style = "Title",
		_Stroke = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(70, 80),
		TextColor3 = Color3.fromRGB(120, 120, 130),
		ZIndex = 2,
	})
	UiKit.Text(card, "Soon", "COMING SOON", {
		_Style = "Small",
		_Stroke = 0,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -20, 0, 16),
		TextColor3 = Color3.fromRGB(120, 120, 130),
		ZIndex = 2,
	})
	return card
end

-- Звено цепочки Forever Pack.
local function buildStep(parent, index, width)
	local step = UiKit.Card(parent, "Step" .. index, "Orange", {
		LayoutOrder = index * 2,
		Size = UDim2.new(0, width, 1, 0),
		ClipsDescendants = true,
		ZIndex = 3,
	})
	UiKit.Text(step, "Title", "FREE", {
		_Style = "Title",
		_Stroke = 2,
		_Gradient = { Color3.fromRGB(255, 230, 170), Color3.fromRGB(255, 160, 60) },
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 0, 24),
		ZIndex = 5,
	})
	local holder = UiKit.Group(step, "IconHolder", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 2),
		Size = UDim2.fromOffset(78, 78),
		ZIndex = 4,
	})
	Builder.BuildRays(holder, 8, Color3.fromRGB(255, 190, 90), 0.7)
	local icon = UiKit.Icon(holder, "Icon", "", { ZIndex = 5 })
	UiKit.Text(icon, "Emoji", "💵", { _Stroke = 0, ZIndex = 6 }).FontFace = Font.fromEnum(Enum.Font.GothamBold)
	local button = UiKit.RobuxButton(step, "Button", "49", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -24, 0, 30),
		ZIndex = 5,
	})
	button:SetAttribute("StepIndex", index)
	UiKit.Text(step, "Done", "✔", {
		_Style = "Title",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(60, 60),
		TextColor3 = UiKit.Theme.Colors.Positive,
		Visible = false,
		ZIndex = 7,
	})
	return step
end

local function buildForever(body)
	local forever = (Config.Shop and Config.Shop.ForeverPack) or { Steps = { "Free" } }
	local section = UiKit.Group(body, "Section_Forever", {
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	UiKit.List(section, { Padding = UDim.new(0, 6) })
	local header = UiKit.SectionHeader(section, "SectionHeader", forever.Title or "Forever Pack", Builder.TabAccent("Forever"))
	header.LayoutOrder = 1
	UiKit.Text(section, "Refresh", "Refresh in: 3h 58m", {
		_Style = "Heading",
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 190, 120),
		LayoutOrder = 2,
	})

	local row = UiKit.Group(section, "Row", { Size = UDim2.new(1, 0, 0, 200), LayoutOrder = 3 })
	local bigWidth = 230
	local chain = UiKit.Plate(row, "Chain", "Inset", {
		_Accent = "Orange",
		Size = UDim2.new(1, -(bigWidth + 12), 1, 0),
		ZIndex = 2,
	})
	local chainStroke = chain:FindFirstChild("SkinStroke") or UiKit.Stroke(chain, UiKit.Accent("Orange").Main, 1.5, 0, "SkinStroke")
	chainStroke.Color = UiKit.Accent("Orange").Main
	UiKit.Padding(chain, 10)
	UiKit.List(chain, {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
	})
	local steps = #forever.Steps
	local stepWidth = math.floor((780 - 40 - bigWidth - 12 - 20 - (steps - 1) * 22) / steps)
	for index = 1, steps do
		buildStep(chain, index, stepWidth)
		if index < steps then
			UiKit.Text(chain, "Arrow" .. index, "›", {
				_Style = "Title",
				LayoutOrder = index * 2 + 1,
				Size = UDim2.fromOffset(16, 40),
				TextColor3 = Color3.fromRGB(255, 190, 120),
				ZIndex = 3,
			})
		end
	end

	-- САМЫЙ ДОРОГОЙ ПАК — справа, большая карточка с анимацией.
	local big = UiKit.CardButton(row, "BigCard", "Gold", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, bigWidth, 1, 0),
		ClipsDescendants = true,
		ZIndex = 3,
	})
	local bigStroke = big:FindFirstChild("SkinStroke")
	if bigStroke then bigStroke.Thickness = 2.5 end
	UiKit.Gradient(big, Color3.fromRGB(255, 225, 150), Color3.fromRGB(120, 70, 20), 90, "Tint").Transparency = UiKit.NSeq(0.55, 0.9)
	local raysHolder = UiKit.Group(big, "RaysHolder", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.47),
		Size = UDim2.fromOffset(170, 170),
		ZIndex = 3,
	})
	local rays = Builder.BuildRays(raysHolder, 12, Color3.fromRGB(255, 220, 120), 0.55)
	rays.Name = "Rays"
	UiKit.Plate(big, "Glow", "Glow", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.47),
		Size = UDim2.fromOffset(120, 120),
		BackgroundColor3 = Color3.fromRGB(255, 210, 110),
		BackgroundTransparency = 0.6,
		ZIndex = 4,
	})
	UiKit.Corner(big.Glow, 999)
	local bigIcon = UiKit.Icon(big, "Icon", "", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.47),
		Size = UDim2.fromOffset(96, 96),
		ZIndex = 5,
	})
	UiKit.Scale(bigIcon, "Pulse", 1)
	UiKit.Text(bigIcon, "Emoji", "🏦", { _Stroke = 0, ZIndex = 6 }).FontFace = Font.fromEnum(Enum.Font.GothamBold)
	local gold = UiKit.Accent("Gold")
	UiKit.Text(big, "Title", forever.BigTitle or "Mega Cash", {
		_Style = "Title",
		_Stroke = 2.5,
		_Gradient = { gold.Light, gold.Main },
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(1, -16, 0, 30),
		ZIndex = 6,
	})
	UiKit.Text(big, "Subtitle", "BEST VALUE!", {
		_Style = "Heading",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -46),
		Size = UDim2.new(1, -16, 0, 22),
		TextColor3 = gold.Light,
		ZIndex = 6,
	})
	UiKit.RobuxButton(big, "Button", "119", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -30, 0, 34),
		ZIndex = 6,
	})
	return section
end

function Builder.Build()
	local gui = UiKit.Screen("ShopUi", { DisplayOrder = 25 })
	gui:SetAttribute("UiKitVersion", Builder.VERSION)
	UiKit.Dimmer(gui)

	local panel, parts = UiKit.Window(gui, "Panel", {
		Title = (Config.Shop and Config.Shop.WindowTitle) or "Prospector's Shop",
		Accent = "Purple",
		Size = UDim2.fromOffset(800, 600),
		BodyName = "Content",
		ZIndex = 2,
	})
	local content = parts.Body
	local tabs = (Config.Shop and Config.Shop.Tabs) or { "Passes", "Deals" }
	local names = (Config.Shop and Config.Shop.TabDisplayNames) or {}
	local emojis = (Config.Shop and Config.Shop.TabEmoji) or {}

	-- НАВИГАЦИЯ: кнопки категорий, клик листает список к секции.
	local nav = UiKit.Scroll(content, "NavBar", {
		Size = UDim2.new(1, 0, 0, 40),
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollBarThickness = 2,
		ZIndex = 3,
	})
	UiKit.List(nav, { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Center })
	UiKit.Padding(nav, 0, 2, 2, 2)
	local navEntries = { { "Forever", "⭐ " .. ((Config.Shop.ForeverPack and Config.Shop.ForeverPack.Title) or "Forever") } }
	for _, tabName in tabs do
		table.insert(navEntries, { tabName, ((emojis[tabName] and (emojis[tabName] .. " ")) or "") .. (names[tabName] or tabName) })
	end
	for order, entry in navEntries do
		local button, caption = UiKit.Button(nav, "Nav_" .. entry[1], entry[2], "Dark", {
			LayoutOrder = order,
			Size = UDim2.fromOffset(46 + utf8.len(entry[2]) * 9, 32),
			ZIndex = 3,
		})
		caption.TextWrapped = false
		caption.TextScaled = true
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 18
		limit.Parent = caption
		local stroke = button:FindFirstChild("SkinStroke")
		if stroke then
			stroke.Color = UiKit.Accent(Builder.TabAccent(entry[1])).Main
			stroke.Thickness = 2
		end
		caption.TextColor3 = UiKit.Accent(Builder.TabAccent(entry[1])).Light
	end

	local body = UiKit.Scroll(content, "Body", {
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 1, -46),
		ZIndex = 2,
	}, UiKit.Accent("Purple"))
	UiKit.List(body, { Padding = UDim.new(0, 10) })
	UiKit.Padding(body, 2, 4, 2, 8)

	buildForever(body)

	for i, tabName in tabs do
		local section = UiKit.Group(body, "Section_" .. tabName, {
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		})
		UiKit.List(section, { Padding = UDim.new(0, 6) })
		local header = UiKit.SectionHeader(section, "SectionHeader", names[tabName] or tabName, Builder.TabAccent(tabName))
		header.LayoutOrder = 1
		local cards = UiKit.Group(section, "Cards_" .. tabName, {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		})
		UiKit.Grid(cards, UDim2.new(0.5, -5, 0, CARD_HEIGHT), UDim2.fromOffset(10, 10))
		UiKit.Padding(cards, 2)
	end

	Builder.BuildCard().Parent = gui
	Builder.BuildEmptyCard().Parent = gui
	panel:SetAttribute("CardHeight", CARD_HEIGHT)
	return gui
end

return Builder
