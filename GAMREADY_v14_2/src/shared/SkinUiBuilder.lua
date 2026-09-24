--------------------------------------------------------------------------------
-- SkinUiBuilder (v20) — меню скинов кирки: сетка карточек → экран скина с
-- плюсами (▲) и минусами (▼) и кнопкой EQUIP. Единый стиль UiKit (Pink).
-- tools/BuildAllUI.lua → StarterGui/SkinUi; SkinUI.client.lua строит сам,
-- если в StarterGui нет свежей версии.
--
-- СТРУКТУРА (имена — контракт):
--   ScreenGui "SkinUi" (BuilderVersion)
--   ├─ TextButton "Dimmer"
--   └─ ImageLabel "Panel" (окно; UIScale "ResponsiveScale")
--        ├─ TitleBar → "Title", "Ribbon", "CloseButton"
--        └─ Frame → Body
--             ├─ Frame "GridView" → ScrollingFrame "Grid" → ImageButton "CardTemplate" [Card]
--             │     CardTemplate: ImageLabel "Image", "Name", "Rarity", "Equipped"
--             └─ Frame "DetailView"
--                  ├─ ImageButton "BackButton" → "Text"
--                  ├─ ImageLabel "PreviewCard" [Card] → ImageLabel "Image", TextLabel "Rarity"
--                  ├─ TextLabel "Name"
--                  ├─ Frame "Stats" → TextLabel "StatTemplate"
--                  └─ ImageButton "EquipButton" [Button_Green] → TextLabel "Text"
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local UiKit = require(script.Parent.UiKit)
local Theme = UiKit.Theme

local Builder = {}
Builder.VERSION = 21

-- Кнопка UiKit, у которой подпись называется "Text" (так её ищет клиент).
local function button(parent, name, label, variant, props)
	local b, caption = UiKit.Button(parent, name, label, variant, props)
	caption.Name = "Text"
	return b
end

function Builder.Build()
	local gui = UiKit.Screen("SkinUi", { DisplayOrder = 50 })
	gui:SetAttribute("BuilderVersion", math.max(Config.SkinUiVersion or 1, Builder.VERSION))
	UiKit.Dimmer(gui)

	local panel, parts = UiKit.Window(gui, "Panel", {
		Title = "Skins",
		Accent = "Pink",
		Size = UDim2.fromOffset(680, 480),
		Position = UDim2.fromScale(0.5, 0.53),
	})
	UiKit.Scale(panel, "ResponsiveScale", 1)
	panel:SetAttribute("BaseWidth", 680)
	panel:SetAttribute("BaseHeight", 480)
	local body = parts.Body

	local gridView = UiKit.Group(body, "GridView", {})
	local scroll = UiKit.Scroll(gridView, "Grid", {})
	UiKit.Grid(scroll, UDim2.fromOffset(116, 176), UDim2.fromOffset(12, 12))
	UiKit.Padding(scroll, 4, 4, 4, 8)

	local card = UiKit.CardButton(scroll, "CardTemplate", Theme.Rarity.Common, { Visible = false })
	UiKit.Icon(card, "Image", "", {
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(1, -16, 0, 96),
		ZIndex = 2,
	})
	UiKit.Text(card, "Name", "Skin", {
		_Style = "Heading",
		Position = UDim2.fromOffset(5, 108),
		Size = UDim2.new(1, -10, 0, 22),
		ZIndex = 2,
	})
	UiKit.Text(card, "Rarity", "RARE", {
		_Style = "Heading",
		Position = UDim2.fromOffset(5, 132),
		Size = UDim2.new(1, -10, 0, 16),
		TextColor3 = Theme.Rarity.Rare,
		ZIndex = 2,
	})
	UiKit.Text(card, "Equipped", "✅ EQUIPPED", {
		_Style = "Small",
		Position = UDim2.fromOffset(5, 154),
		Size = UDim2.new(1, -10, 0, 14),
		TextColor3 = Theme.Colors.Positive,
		Visible = false,
		ZIndex = 2,
	})

	local detail = UiKit.Group(body, "DetailView", { Visible = false })
	button(detail, "BackButton", "BACK", "Blue", { Size = UDim2.fromOffset(110, 38) })
	local preview = UiKit.Card(detail, "PreviewCard", Theme.Rarity.Common, {
		Position = UDim2.fromOffset(20, 50),
		Size = UDim2.fromOffset(170, 250),
	})
	UiKit.Icon(preview, "Image", "", {
		Position = UDim2.fromOffset(10, 12),
		Size = UDim2.new(1, -20, 0, 176),
		ZIndex = 2,
	})
	UiKit.Text(preview, "Rarity", "RARE", {
		_Style = "Title",
		Position = UDim2.new(0, 5, 1, -44),
		Size = UDim2.new(1, -10, 0, 30),
		TextColor3 = Theme.Rarity.Rare,
		ZIndex = 2,
	})
	UiKit.Text(detail, "Name", "Skin Name", {
		_Style = "Title",
		Position = UDim2.fromOffset(212, 4),
		Size = UDim2.new(1, -220, 0, 38),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local stats = UiKit.Group(detail, "Stats", {
		Position = UDim2.fromOffset(212, 52),
		Size = UDim2.new(1, -220, 0, 220),
	})
	UiKit.List(stats, { Padding = UDim.new(0, 8) })
	UiKit.Text(stats, "StatTemplate", "+10% Ore sell price", {
		_Style = "Heading",
		Size = UDim2.new(1, 0, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Colors.Positive,
		Visible = false,
	})
	button(detail, "EquipButton", "EQUIP", "Green", {
		Position = UDim2.new(0, 212, 1, -58),
		Size = UDim2.new(1, -220, 0, 54),
		_TextStyle = "Title",
	})
	return gui
end

return Builder
