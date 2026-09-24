--------------------------------------------------------------------------------
-- ShopUi — магазин за Robux (стиль «Prospector's Shop»).
-- Клиент: CustomCartUI.client.lua (setupShopUi) — клонирует CardTemplate в
-- каждую секцию под реальные товары из Config.Shop.Items.
--
-- СТРУКТУРА (имена — контракт):
--   ScreenGui "ShopUi"
--   ├─ TextButton "Dimmer"
--   ├─ ImageLabel "Panel" (окно UiKit.Window, акцент Purple)
--   │    ├─ "TitleBar" → "Title", "Ribbon", "CloseButton"
--   │    └─ "Frame" → ScrollingFrame "Body"
--   │         └─ Frame "Section_<Tab>" (по Config.Shop.Tabs)
--   │              ├─ Frame "SectionHeader" → "Label", "LineLeft", "LineRight"
--   │              └─ Frame "Cards_<Tab>" (UIGridLayout, 2 колонки)
--   └─ ImageLabel "CardTemplate" (Visible=false)
--        ├─ ImageLabel "IconHolder" → ImageLabel "IconGlow", ImageLabel "PlaceholderIcon" → TextLabel "Emoji"
--        ├─ TextLabel "Title", TextLabel "Description"
--        ├─ ImageLabel "Badge" → TextLabel "Count"
--        └─ ImageButton "PriceButton" → TextLabel "Caption", ImageLabel "RobuxIcon"
--
-- ПРОБЕЛЫ МЕЖДУ КАТЕГОРИЯМИ (исправлено в v20): раньше полупрозрачная
-- подложка секции лежала ВНУТРИ UIListLayout секции и участвовала в
-- раскладке как обычный элемент высотой «вся секция + 4px» — каждая
-- категория становилась вдвое выше, отсюда огромные пустоты. Теперь
-- подложки в раскладке нет, отступы: 10px между секциями, 6px внутри.
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = script.Parent.Parent
local UiKit = require(Shared.UiKit)
local Config = require(ReplicatedStorage.Shared.Config)

local Builder = {}

-- Акцент заголовка секции по категории (можно переопределить Config.Shop.TabAccents).
local DEFAULT_TAB_ACCENTS = {
	Boosts = "Gold",
	Passes = "Purple",
	Cash = "Green",
	Events = "Red",
	Deals = "Blue",
}

function Builder.TabAccent(tabName)
	local accents = Config.Shop and Config.Shop.TabAccents
	return (accents and accents[tabName]) or DEFAULT_TAB_ACCENTS[tabName] or "Purple"
end

local CARD_HEIGHT = 128

function Builder.BuildCard()
	local card = UiKit.Card(nil, "CardTemplate", "Purple", {
		Size = UDim2.new(0.5, -6, 0, CARD_HEIGHT),
		Visible = false,
	})

	local holder = UiKit.Plate(card, "IconHolder", "Inset", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(CARD_HEIGHT - 24, CARD_HEIGHT - 24),
		ZIndex = 2,
	})
	UiKit.Corner(holder, 999)
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
		_Gradient = { purple.Light, purple.Main },
		Position = UDim2.fromOffset(left, 8),
		Size = UDim2.new(1, -left - 10, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 2,
	})
	UiKit.Text(card, "Description", "", {
		_Style = "Heading",
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
	})
	UiKit.Corner(badge, 0)

	UiKit.RobuxButton(card, "PriceButton", "99", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0, left + (0.5 * 0), 1, -10),
		Size = UDim2.new(1, -left - 10, 0, 38),
		ZIndex = 2,
	})
	card.PriceButton.AnchorPoint = Vector2.new(0, 1)
	return card
end

function Builder.Build()
	local gui = UiKit.Screen("ShopUi", { DisplayOrder = 25 })
	UiKit.Dimmer(gui)

	local panel, parts = UiKit.Window(gui, "Panel", {
		Title = (Config.Shop and Config.Shop.WindowTitle) or "Prospector's Shop",
		Accent = "Purple",
		Size = UDim2.fromOffset(780, 580),
		Scroll = true,
		ZIndex = 2,
	})
	local body = parts.Body
	UiKit.List(body, { Padding = UDim.new(0, 10) })
	UiKit.Padding(body, 2, 4, 2, 8)

	local tabs = (Config.Shop and Config.Shop.Tabs) or { "Passes", "Deals" }
	local names = (Config.Shop and Config.Shop.TabDisplayNames) or {}
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

	local card = Builder.BuildCard()
	card.Parent = gui
	panel:SetAttribute("CardHeight", CARD_HEIGHT)
	return gui
end

return Builder
