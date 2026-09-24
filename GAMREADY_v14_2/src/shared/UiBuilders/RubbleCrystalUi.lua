--------------------------------------------------------------------------------
-- RubbleCrystalUi (v20) — ячейка «кристалл в руках» над хотбаром.
-- Клиент: RubbleCrystalUI.client.lua.
--
-- СТРУКТУРА (контракт):
--   ScreenGui "RubbleCrystalHotbar"
--   └─ ImageLabel "Slot" [Slot, акцент Teal] (Visible=false)
--        ├─ ImageLabel "Icon"        — картинка кристалла (Config.Geodes.Ores[id].ImageId)
--        ├─ TextLabel "Placeholder"  — «?» пока картинки нет
--        └─ TextLabel "Label"        — подпись под ячейкой
--------------------------------------------------------------------------------
local UiKit = require(script.Parent.Parent.UiKit)

local Builder = {}
Builder.VERSION = 20

function Builder.Build()
	local gui = UiKit.Screen("RubbleCrystalHotbar", { DisplayOrder = 12 })
	gui:SetAttribute("UiKitVersion", Builder.VERSION)
	local slot = UiKit.Slot(gui, "Slot", {
		_Accent = "Teal",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -96),
		Size = UDim2.fromOffset(64, 64),
		Visible = false,
	})
	UiKit.ApplySkin(slot, "Slot", "Teal")
	local stroke = slot:FindFirstChild("SkinStroke")
	if stroke then stroke.Color = UiKit.Theme.Accents.Teal.Main end
	UiKit.Icon(slot, "Icon", "", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.72, 0.72),
		ZIndex = 2,
	})
	UiKit.Text(slot, "Placeholder", "?", {
		_Style = "Title",
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 1, -12),
		ZIndex = 2,
	})
	UiKit.Text(slot, "Label", "CRYSTAL", {
		_Style = "Small",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 2),
		Size = UDim2.new(1, 16, 0, 14),
		ZIndex = 2,
	})
	return gui
end

return Builder
