--------------------------------------------------------------------------------
-- PlacementUi (v20) — подсказки режима установки: тележки (CartPlacement)
-- и предметов на базе (PlacementGhost) + круглые кнопки для телефона.
--
-- СТРУКТУРА (контракт; ScreenGui всегда включён, клиенты прячут группы):
--   ScreenGui "PlacementUi"
--   ├─ Frame "CartHud" (Visible=false) → ImageLabel "Hint" [Pill] → "Text"
--   └─ Frame "GhostHud" (Visible=false)
--        ├─ ImageLabel "Hint" [Pill] → "Text"
--        └─ Frame "MobileBar" → ImageButton "Rotate" [Button_Blue], "Place" [Button_Green]
--             (подпись — "Caption")
--------------------------------------------------------------------------------
local UiKit = require(script.Parent.Parent.UiKit)
local Theme = UiKit.Theme

local Builder = {}
Builder.VERSION = 21

local function hintPill(parent, props)
	local pill = UiKit.Plate(parent, "Hint", "Pill", props)
	UiKit.Text(pill, "Text", "", {
		_Style = "Heading",
		Position = UDim2.fromOffset(12, 3),
		Size = UDim2.new(1, -24, 1, -6),
		ZIndex = 2,
	})
	return pill
end

function Builder.Build()
	local gui = UiKit.Screen("PlacementUi", { DisplayOrder = 26 })
	gui:SetAttribute("UiKitVersion", Builder.VERSION)

	local cart = UiKit.Group(gui, "CartHud", { Visible = false })
	hintPill(cart, {
		_Accent = "Green",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -120),
		Size = UDim2.fromOffset(420, 40),
	})

	local ghost = UiKit.Group(gui, "GhostHud", { Visible = false })
	local hint = hintPill(ghost, {
		_Accent = "Gold",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(560, 38),
	})
	hint.Text.TextColor3 = Theme.Accents.Gold.Light
	hint.Visible = false -- v20.24: только для ошибок (PlacementGhost), подсказку пишет GearUi/AimHint
	local bar = UiKit.Group(ghost, "MobileBar", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -150),
		Size = UDim2.fromOffset(200, 64),
	})
	UiKit.List(bar, {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 10),
	})
	-- v20.9: без символов ↻/✔ (в шрифтах Roblox их нет → «квадратик»).
	UiKit.Button(bar, "Rotate", "R", "Blue", { _TextStyle = "Title", Size = UDim2.fromOffset(62, 62), LayoutOrder = 1 })
	local place = UiKit.Button(bar, "Place", "", "Green", { _TextStyle = "Title", Size = UDim2.fromOffset(62, 62), LayoutOrder = 2 })
	UiKit.Shape(place, "Icon", "Check", { Size = UDim2.fromScale(0.6, 0.6), ZIndex = place.ZIndex + 2 })
	return gui
end

return Builder
