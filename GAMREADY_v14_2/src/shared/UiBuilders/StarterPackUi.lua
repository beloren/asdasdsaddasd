--------------------------------------------------------------------------------
-- StarterPackUi — стартовый набор: баннер с радужной надписью и таймером
-- (справа снизу) + окно «что внутри». Клиент: StarterPackUI.client.lua.
--
-- СТРУКТУРА (имена — контракт):
--   ScreenGui "StarterPackOffer"
--   ├─ ImageButton "Banner" [Card, акцент Pink] → ImageLabel "Icon",
--   │     TextLabel "RainbowTitle", TextLabel "Countdown"
--   ├─ TextButton "Dimmer"
--   └─ ImageLabel "Details" (окно, UIScale "ResponsiveScale")
--        ├─ TitleBar → "Title", "Ribbon", "CloseButton"
--        └─ Frame → Body → Frame "Contents" (строки "Row<N>" → "Checkmark", "Text"),
--             ImageButton "BuyButton" [Button_Green] → "Caption"
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = script.Parent.Parent
local UiKit = require(Shared.UiKit)
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = UiKit.Theme

local Builder = {}
Builder.DEFAULT_ICON = "rbxassetid://100116175987177"

function Builder.Build()
	local pack = (Config.DevProducts and Config.DevProducts.StarterPack) or { Contents = {}, PriceRobux = 99 }
	local gui = UiKit.Screen("StarterPackOffer", {
		DisplayOrder = 400,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	})

	local banner = UiKit.CardButton(gui, "Banner", "Pink", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -20),
		Size = UDim2.fromOffset(290, 88),
		Visible = false,
		ZIndex = 10,
	})
	UiKit.Icon(banner, "Icon", Builder.DEFAULT_ICON, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(66, 66),
		ZIndex = 11,
	})
	UiKit.Text(banner, "RainbowTitle", "STARTER KIT", {
		_Style = "Title",
		Position = UDim2.fromOffset(84, 8),
		Size = UDim2.new(1, -94, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 90, 90),
		ZIndex = 11,
	})
	UiKit.Text(banner, "Countdown", "10:00", {
		_Style = "Number",
		Position = UDim2.fromOffset(84, 46),
		Size = UDim2.new(1, -94, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Colors.SubText,
		ZIndex = 11,
	})

	local dimmer = UiKit.Dimmer(gui)
	dimmer.BackgroundTransparency = 0.35

	local rows = math.max(1, #(pack.Contents or {}))
	local height = 54 + 6 + 24 + rows * 44 + 70
	local details, parts = UiKit.Window(gui, "Details", {
		Title = "Starter Kit",
		Accent = "Pink",
		Size = UDim2.fromOffset(440, height),
	})
	UiKit.Scale(details, "ResponsiveScale", 1)
	local contents = UiKit.Group(parts.Body, "Contents", {
		Size = UDim2.new(1, 0, 0, rows * 44),
	})
	UiKit.List(contents, { Padding = UDim.new(0, 6) })
	for index, line in pack.Contents or {} do
		local row = UiKit.Plate(contents, "Row" .. index, "Inset", {
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 38),
		})
		local check = UiKit.Text(row, "Checkmark", "✔", {
			_Style = "Title",
			Position = UDim2.fromOffset(8, 2),
			Size = UDim2.fromOffset(30, 34),
			TextColor3 = Theme.Colors.Positive,
			ZIndex = 2,
		})
		check.FontFace = Font.fromEnum(Enum.Font.GothamBold)
		UiKit.Text(row, "Text", line, {
			_Style = "Heading",
			Position = UDim2.fromOffset(44, 4),
			Size = UDim2.new(1, -52, 1, -8),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 2,
		})
	end
	UiKit.Button(parts.Body, "BuyButton", ("BUY FOR R$ %d"):format(pack.PriceRobux or 99), "Green", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, -20, 0, 52),
		_TextStyle = "Title",
	})
	return gui
end

return Builder
