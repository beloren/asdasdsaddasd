--------------------------------------------------------------------------------
-- ShiftLockUi (v20) — круглая кнопка шифтлока для телефона (левый нижний угол).
-- Клиент: CustomCartUI (setupShiftLock) включает её только на тач-экранах.
--
-- СТРУКТУРА (контракт):
--   ScreenGui "MobileShiftLockButton" → ImageButton "ShiftLockButton" [Round]
--     → ImageLabel "Icon" (Theme.Icons.Lock) → TextLabel "Emoji" (🔒)
--------------------------------------------------------------------------------
local UiKit = require(script.Parent.Parent.UiKit)

local Builder = {}
Builder.VERSION = 20

function Builder.Build()
	local gui = UiKit.Screen("MobileShiftLockButton", { DisplayOrder = 10 })
	gui.IgnoreGuiInset = false
	gui.Enabled = false -- включает клиент, только на тач-экранах
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
		gui.ClipToDeviceSafeArea = true
	end)
	gui:SetAttribute("UiKitVersion", Builder.VERSION)
	local button = UiKit.PlateButton(gui, "ShiftLockButton", "Round", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 18, 1, -18),
		Size = UDim2.fromOffset(44, 44),
	})
	UiKit.ThemeIcon(button, "Icon", "Lock", "🔒", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.62, 0.62),
		ZIndex = 2,
	})
	return gui
end

return Builder
