--------------------------------------------------------------------------------
-- LootFeedUi (v20) — лента добычи справа + баннер редкого дропа по центру.
-- Клиент: LootFeed.client.lua (клонирует Templates/CardTemplate).
--
-- СТРУКТУРА (контракт):
--   ScreenGui "LootFeedUi"
--   ├─ Frame "Feed" (UIListLayout, UIScale "AutoScale")
--   ├─ Frame "Banner" (UIScale "Pop") → TextLabel "Title", TextLabel "Text"
--   │    (UIGradient "TextGradient" — переливается цветом редкости)
--   └─ Folder "Templates"
--        └─ Frame "CardTemplate" → ImageLabel "Body" [Card]
--             ├─ ImageLabel "Strip" (полоска цвета редкости)
--             ├─ ImageLabel "Image" (свой ассет) + TextLabel "Emoji" (запасной)
--             ├─ TextLabel "Title", TextLabel "Sub"
--             └─ Frame "Shine" (блик)
--------------------------------------------------------------------------------
local UiKit = require(script.Parent.Parent.UiKit)
local Theme = UiKit.Theme

local Builder = {}
Builder.VERSION = 20

function Builder.Build()
	local gui = UiKit.Screen("LootFeedUi", { DisplayOrder = 40 })
	gui:SetAttribute("UiKitVersion", Builder.VERSION)

	local feed = UiKit.Group(gui, "Feed", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(300, 420),
	})
	UiKit.Scale(feed, "AutoScale", 1)
	UiKit.List(feed, {
		Padding = UDim.new(0, 6),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
	})

	local banner = UiKit.Group(gui, "Banner", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(560, 120),
		Visible = false,
	})
	UiKit.Scale(banner, "Pop", 1)
	UiKit.Text(banner, "Title", "RARE DROP!", {
		_Style = "Title",
		_Stroke = 3,
		Size = UDim2.fromScale(1, 0.45),
	})
	UiKit.Text(banner, "Text", "Crystal", {
		_Style = "Title",
		_Stroke = 3.5,
		_Gradient = { Color3.new(1, 1, 1), Color3.new(1, 1, 1) },
		Position = UDim2.fromScale(0, 0.45),
		Size = UDim2.fromScale(1, 0.55),
	})

	local templates = Instance.new("Folder")
	templates.Name = "Templates"
	templates.Parent = gui
	local card = UiKit.Group(templates, "CardTemplate", { Size = UDim2.fromOffset(290, 58) })
	local body = UiKit.Card(card, "Body", "Grey", {
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
	})
	UiKit.Plate(body, "Strip", "Divider", {
		_Accent = "Grey",
		Position = UDim2.fromOffset(5, 5),
		Size = UDim2.new(0, 5, 1, -10),
		ZIndex = 2,
	})
	UiKit.Icon(body, "Image", "", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(40, 40),
		ZIndex = 2,
	})
	local emoji = UiKit.Text(body, "Emoji", "✨", {
		_Stroke = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(40, 40),
		ZIndex = 2,
	})
	emoji.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	UiKit.Text(body, "Title", "+1 Crystal", {
		_Style = "Heading",
		_MaxTextSize = 24,
		Position = UDim2.fromOffset(62, 6),
		Size = UDim2.new(1, -70, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
	})
	UiKit.Text(body, "Sub", "", {
		_Style = "Body",
		_MaxTextSize = 16,
		Position = UDim2.fromOffset(62, 32),
		Size = UDim2.new(1, -70, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Colors.SubText,
		ZIndex = 2,
	})
	UiKit.Group(body, "Shine", {
		BackgroundTransparency = 0.7,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Position = UDim2.new(-0.2, 0, 0, 0),
		Size = UDim2.new(0, 26, 1, 0),
		Rotation = 12,
		ZIndex = 3,
	})
	UiKit.HideTemplates(gui) -- шаблоны выключены с рождения
	return gui
end

return Builder
