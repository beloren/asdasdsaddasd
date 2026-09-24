--------------------------------------------------------------------------------
-- ReturnScreenUi — «Welcome back!»: что накопилось, пока игрока не было.
-- Клиент: ReturnScreenUI.client.lua.
--
-- СТРУКТУРА (имена — контракт):
--   ScreenGui "ReturnScreenUi"
--   ├─ TextButton "Dimmer"
--   └─ ImageLabel "Panel" (окно, акцент Gold; UIScale "PanelScale")
--        ├─ TitleBar → "Title", "Ribbon", "CloseButton"
--        └─ Frame → Body (UIListLayout)
--             ├─ TextLabel "AwaySubtitle"
--             ├─ ImageLabel "RowCart"/"RowSafe"/"RowStreak" [Inset] → "Icon", "Label", "Value"
--             ├─ TextLabel "HintLabel"
--             └─ ImageButton "CollectButton" [Button_Green] → "Caption"
--------------------------------------------------------------------------------
local Shared = script.Parent.Parent
local UiKit = require(Shared.UiKit)
local Theme = UiKit.Theme

local Builder = {}

local function row(parent, name, order, emoji, caption, valueColor)
	local r = UiKit.Plate(parent, name, "Inset", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 48),
		Visible = false,
	})
	r:SetAttribute("RowValueColor", valueColor)
	UiKit.Text(r, "Icon", emoji, {
		_Stroke = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(30, 30),
		ZIndex = 2,
	}).FontFace = Font.fromEnum(Enum.Font.GothamBold)
	UiKit.Text(r, "Label", caption, {
		_Style = "Body",
		Position = UDim2.fromOffset(48, 6),
		Size = UDim2.new(0.55, -48, 1, -12),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Colors.SubText,
		ZIndex = 2,
	})
	UiKit.Text(r, "Value", "", {
		_Style = "Number",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 6),
		Size = UDim2.new(0.45, -12, 1, -12),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = valueColor,
		ZIndex = 2,
	})
	return r
end

function Builder.Build()
	local gui = UiKit.Screen("ReturnScreenUi", { DisplayOrder = 900 })
	local dimmer = UiKit.Dimmer(gui)
	dimmer.BackgroundTransparency = 1

	local panel, parts = UiKit.Window(gui, "Panel", {
		Title = "Welcome Back!",
		Accent = "Gold",
		Size = UDim2.fromOffset(440, 380),
	})
	UiKit.Scale(panel, "PanelScale", 0.9)
	local body = parts.Body
	UiKit.List(body, { Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center })

	UiKit.Text(body, "AwaySubtitle", "You were gone", {
		_Style = "Heading",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 24),
		TextColor3 = Theme.Colors.SubText,
	})
	row(body, "RowCart", 3, "⛏️", "Mine kept working", Color3.fromRGB(120, 220, 255))
	row(body, "RowSafe", 4, "🔐", "Safe accumulated", Color3.fromRGB(120, 255, 130))
	row(body, "RowStreak", 5, "🔥", "Streak", Color3.fromRGB(255, 200, 80))
	UiKit.Text(body, "HintLabel", "Your cart is loaded — deliver it to the bank", {
		_Style = "Small",
		LayoutOrder = 6,
		Size = UDim2.new(1, 0, 0, 18),
		TextColor3 = Theme.Colors.SubText,
		Visible = false,
	})
	UiKit.Button(body, "CollectButton", "COLLECT ALL", "Green", {
		LayoutOrder = 7,
		Size = UDim2.new(1, -40, 0, 50),
		_TextStyle = "Title",
	})
	return gui
end

return Builder
