--------------------------------------------------------------------------------
-- OfferUiBuilder (v20) — КОНТЕКСТНЫЕ ПРЕДЛОЖЕНИЯ («купоны» с ценой) и
-- кнопка 🚀 Rocket Pickaxe. Единый стиль UiKit.
-- tools/BuildAllUI.lua → StarterGui/OfferUi; OfferPrompts.client.lua без неё
-- строит сам.
--
-- СТРУКТУРА (контракт):
--   ScreenGui "OfferUi" (BuilderVersion)
--   ├─ Frame "Stack" (UIListLayout, UIScale "AutoScale")
--   │    └─ ImageButton "OfferTemplate" [Card] → "Icon", "Label",
--   │         ImageLabel "Price" [Button_Green] → "Text", ImageButton "Close",
--   │         UIScale "Pop", UIStroke "Glow"
--   └─ ImageButton "RocketButton" [Round] → "Icon", "State", ImageLabel "Cooldown" (шторка),
--        UIStroke "Glow"
--------------------------------------------------------------------------------
local UiKit = require(script.Parent.UiKit)
local Theme = UiKit.Theme

local Builder = {}
Builder.VERSION = 21

function Builder.Build()
	local gui = UiKit.Screen("OfferUi", { DisplayOrder = 20 })
	gui:SetAttribute("BuilderVersion", Builder.VERSION)

	local stack = UiKit.Group(gui, "Stack", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.55, 0),
		Size = UDim2.fromOffset(260, 260),
	})
	UiKit.List(stack, {
		Padding = UDim.new(0, 8),
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
	})
	UiKit.Scale(stack, "AutoScale", 1)

	-- КУПОН
	local offer = UiKit.CardButton(stack, "OfferTemplate", "Gold", {
		Size = UDim2.fromOffset(250, 56),
		Visible = false,
	})
	local glow = UiKit.Stroke(offer, Theme.Accents.Gold.Main, 2, 0.2, "Glow")
	glow.Transparency = 0.2
	UiKit.Scale(offer, "Pop", 1)
	UiKit.Text(offer, "Icon", "🛡", {
		_Stroke = 0,
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(40, 40),
		ZIndex = 2,
	}).FontFace = Font.fromEnum(Enum.Font.GothamBold)
	UiKit.Text(offer, "Label", "Shield now", {
		_Style = "Heading",
		Position = UDim2.fromOffset(52, 10),
		Size = UDim2.new(1, -140, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
	})
	local price = UiKit.Plate(offer, "Price", "Button_Green", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(74, 36),
		ZIndex = 2,
	})
	UiKit.Text(price, "Text", "R$ 9", {
		_Style = "Number",
		_StrokeColor = Theme.Skins.Button_Green.TextStroke,
		Position = UDim2.fromOffset(4, 3),
		Size = UDim2.new(1, -8, 1, -6),
		ZIndex = 3,
	})
	local close = UiKit.CloseButton(offer, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 2, 0, 2),
		Size = UDim2.fromOffset(22, 22),
		ZIndex = 4,
	})
	close.Name = "Close"

	-- 🚀 КНОПКА РАКЕТНОЙ КИРКИ
	local rocket = UiKit.PlateButton(gui, "RocketButton", "Round", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -150),
		Size = UDim2.fromOffset(74, 74),
		BackgroundColor3 = Color3.fromRGB(60, 50, 90),
		BackgroundTransparency = 0.1,
		ClipsDescendants = true,
		Visible = false,
	})
	local rocketGlow = UiKit.Stroke(rocket, Color3.fromRGB(255, 120, 60), 2, 1, "Glow")
	rocketGlow.Transparency = 1
	-- v20.21: иконка — ImageLabel "Icon" (UiTheme.Icons.Rocket или Image в Studio).
	UiKit.ThemeIcon(rocket, "Icon", "Rocket", "🚀", {
		Position = UDim2.fromOffset(11, 6),
		Size = UDim2.new(1, -22, 1, -30),
		ZIndex = 2,
	})
	UiKit.Text(rocket, "State", "OFF [R]", {
		_Style = "Number",
		Position = UDim2.new(0, 5, 1, -22),
		Size = UDim2.new(1, -10, 0, 18),
		TextColor3 = Theme.Colors.SubText,
		ZIndex = 3,
	})
	local shade = UiKit.Plate(rocket, "Cooldown", "Dimmer", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundTransparency = 0.4,
		ZIndex = 4,
	})
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	return gui
end

return Builder
