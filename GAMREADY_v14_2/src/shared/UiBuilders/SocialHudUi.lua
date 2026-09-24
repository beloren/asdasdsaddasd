--------------------------------------------------------------------------------
-- SocialHudUi (v20) — кнопка «👥» в топбаре с меню наград за группу/избранное.
-- Клиент: SocialHud.client.lua (кнопку переносит в TopbarDock).
--
-- СТРУКТУРА (контракт):
--   ScreenGui "SocialHud"
--   └─ ImageButton "Gift" [Round] → ImageLabel "Icon" (→ TextLabel "Emoji"),
--        ImageLabel "Dot" [Badge], UIScale "Pop",
--        Frame "Menu" (UIListLayout, открывается вниз)
--          → ImageButton "GroupButton" [Button_Blue], "FavoriteButton" [Button_Purple] (+ "Caption")
--------------------------------------------------------------------------------
local UiKit = require(script.Parent.Parent.UiKit)
local Theme = UiKit.Theme

local Builder = {}
Builder.VERSION = 20

function Builder.Build()
	local gui = UiKit.Screen("SocialHud", { DisplayOrder = 5 })
	gui.IgnoreGuiInset = false
	gui:SetAttribute("UiKitVersion", Builder.VERSION)

	local button = UiKit.PlateButton(gui, "Gift", "Round", {
		Position = UDim2.new(0, 12, 0.36, 0),
		Size = UDim2.fromOffset(56, 56),
	})
	UiKit.Scale(button, "Pop", 1)
	UiKit.ThemeIcon(button, "Icon", "Social", "👥", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.62, 0.62),
		ZIndex = 2,
	})
	UiKit.Plate(button, "Dot", "Badge", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(14, 14),
		ZIndex = 4,
	})

	local menu = UiKit.Group(button, "Menu", {
		Position = UDim2.new(0, 0, 1, 10),
		Size = UDim2.fromOffset(230, 100),
		Visible = false,
		ZIndex = 5,
	})
	UiKit.List(menu, { Padding = UDim.new(0, 6) })
	UiKit.Button(menu, "GroupButton", "GROUP: +10% CASH", "Blue", {
		Size = UDim2.new(1, 0, 0, 44),
		LayoutOrder = 1,
		ZIndex = 5,
	})
	UiKit.Button(menu, "FavoriteButton", "FAVORITE: FREE SKIN", "Purple", {
		Size = UDim2.new(1, 0, 0, 44),
		LayoutOrder = 2,
		ZIndex = 5,
	})
	return gui
end

return Builder
