--------------------------------------------------------------------------------
-- ToastUiBuilder (v20) — всплывающие уведомления (единый стиль UiKit).
-- tools/BuildAllUI.lua кладёт результат в StarterGui/Toast; клиент
-- CustomCartUI.client.lua (setupToast) клонирует шаблон карточки.
--
-- СТРУКТУРА (имена — контракт):
--   ScreenGui "Toast" (ToastUiVersion)
--   └─ Frame "Stack" (сверху по центру) → UIScale "AutoScale"
--        └─ ImageLabel "Panel" [Toast] — ШАБЛОН карточки (Visible=false)
--             ├─ UIScale "Pop"
--             ├─ ImageLabel "Skin" — старое место под картинку (пусто)
--             ├─ ImageLabel "Accent" — цветная полоска слева (цвет по типу)
--             ├─ ImageLabel "Icon" / ViewportFrame "IconViewport"
--             ├─ TextLabel "Text", ImageLabel "Count" → нет, TextLabel "Count"
--             └─ ImageButton "ActionButton" [Button_Green] → TextLabel "Caption"
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UiKit = require(script.Parent.UiKit)
local Theme = UiKit.Theme

local Builder = {}
Builder.VERSION = 20

function Builder.Build()
	local okCfg, Config = pcall(require, ReplicatedStorage.Shared.Config)
	local defaultIcon = okCfg and Config.Notify and Config.Notify.Icons and Config.Notify.Icons.Default or 0

	local gui = UiKit.Screen("Toast", { DisplayOrder = 30 })
	gui:SetAttribute("ToastUiVersion", Builder.VERSION)

	local stack = UiKit.Group(gui, "Stack", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 58),
		Size = UDim2.fromOffset(320, 110),
	})
	UiKit.Scale(stack, "AutoScale", 1)

	local panel = UiKit.Plate(stack, "Panel", "Toast", {
		_Accent = "Green",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(310, 48),
		Visible = false,
	})
	UiKit.Scale(panel, "Pop", 1)
	UiKit.Icon(panel, "Skin", "", { ZIndex = 1 })

	UiKit.Plate(panel, "Accent", "Divider", {
		_Accent = Theme.Accents.Green.Main,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(0, 5, 1, 0),
		ZIndex = 3,
	})
	UiKit.Icon(panel, "Icon", defaultIcon, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(32, 32),
		ZIndex = 3,
	})
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "IconViewport"
	viewport.AnchorPoint = Vector2.new(0, 0.5)
	viewport.Position = UDim2.new(0, 12, 0.5, 0)
	viewport.Size = UDim2.fromOffset(36, 36)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(220, 220, 230)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-0.4, -1, -0.6)
	viewport.Visible = false
	viewport.ZIndex = 3
	viewport.Parent = panel

	UiKit.Text(panel, "Text", "", {
		_Style = "Heading",
		Position = UDim2.new(0, 54, 0, 5),
		Size = UDim2.new(1, -64, 1, -10),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
		_MaxTextSize = 21,
	})
	local count = UiKit.Text(panel, "Count", "x2", {
		_Style = "Number",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 8, 0, 2),
		Size = UDim2.fromOffset(36, 22),
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Colors.Close,
		Visible = false,
		ZIndex = 5,
	})
	UiKit.Corner(count, 999)

	local action = UiKit.Button(panel, "ActionButton", "Open Shop", "Green", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(90, 30),
		Visible = false,
		ZIndex = 4,
	})
	action.Caption.ZIndex = 5
	return gui
end

return Builder
