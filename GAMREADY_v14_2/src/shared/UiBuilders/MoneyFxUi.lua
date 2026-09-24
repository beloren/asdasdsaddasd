--------------------------------------------------------------------------------
-- MoneyFxUi (v20) — надпись «+$X» по центру экрана при начислении денег.
-- Клиент: CustomCartUI (setupMoneyGainFx).
--
-- СТРУКТУРА (контракт):
--   ScreenGui "MoneyGainFx" → Frame "Container" → ImageLabel "Icon" (монета,
--   Theme.Icons.Money), TextLabel "Label"
--------------------------------------------------------------------------------
local UiKit = require(script.Parent.Parent.UiKit)
local Theme = UiKit.Theme

local Builder = {}
Builder.VERSION = 20
Builder.SIZE = Vector2.new(280, 50)

function Builder.Build()
	local gui = UiKit.Screen("MoneyGainFx", { DisplayOrder = 95 })
	gui:SetAttribute("UiKitVersion", Builder.VERSION)
	local container = UiKit.Group(gui, "Container", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(Builder.SIZE.X, Builder.SIZE.Y),
	})
	UiKit.ThemeIcon(container, "Icon", "Money", "", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(40, 40),
		ImageTransparency = 1,
	})
	local label = UiKit.Text(container, "Label", "", {
		_Style = "Number",
		_Stroke = 3,
		_Gradient = { Color3.fromRGB(190, 255, 170), Theme.Colors.Positive },
		TextColor3 = Color3.new(1, 1, 1),
	})
	label.TextTransparency = 1
	return gui
end

return Builder
