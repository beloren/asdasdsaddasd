--------------------------------------------------------------------------------
-- BuffBarUi (v20) — панель активных эффектов (справа снизу) + подсказка.
-- Клиент: BuffBar.client.lua (клонирует Templates/IconTemplate).
--
-- СТРУКТУРА (контракт):
--   ScreenGui "BuffBar"
--   ├─ Frame "Bar" (UIGridLayout, растёт вверх, по 3 в ряд)
--   ├─ ImageLabel "Tooltip" [Toast] → TextLabel "Title", TextLabel "Body"
--   └─ Folder "Templates"
--        └─ ImageButton "IconTemplate" [Slot] → ImageLabel "Image" (свой ассет),
--             TextLabel "Glyph" (запасная подпись), TextLabel "Timer",
--             UIStroke "SkinStroke" (красится цветом эффекта)
--------------------------------------------------------------------------------
local UiKit = require(script.Parent.Parent.UiKit)
local Theme = UiKit.Theme

local Builder = {}
Builder.VERSION = 20
Builder.ICON_SIZE = 42
Builder.ICON_GAP = 6
Builder.ICONS_PER_ROW = 3

function Builder.Build()
	local gui = UiKit.Screen("BuffBar", { DisplayOrder = 12 })
	gui.IgnoreGuiInset = false
	gui:SetAttribute("UiKitVersion", Builder.VERSION)

	local size, gap, perRow = Builder.ICON_SIZE, Builder.ICON_GAP, Builder.ICONS_PER_ROW
	local bar = UiKit.Group(gui, "Bar", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -18),
		Size = UDim2.fromOffset(size * perRow + gap * (perRow - 1), 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	UiKit.Grid(bar, UDim2.fromOffset(size, size), UDim2.fromOffset(gap, gap), {
		FillDirectionMaxCells = perRow,
		StartCorner = Enum.StartCorner.BottomRight,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
	})

	local tooltip = UiKit.Plate(gui, "Tooltip", "Toast", {
		_Accent = "Grey",
		AnchorPoint = Vector2.new(1, 1),
		Size = UDim2.fromOffset(250, 82),
		Visible = false,
		ZIndex = 20,
	})
	UiKit.Text(tooltip, "Title", "", {
		_Style = "Heading",
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.new(1, -20, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 21,
	})
	local body = UiKit.Text(tooltip, "Body", "", {
		_Style = "Body",
		_Stroke = 1,
		Position = UDim2.fromOffset(10, 30),
		Size = UDim2.new(1, -20, 1, -36),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Theme.Colors.SubText,
		ZIndex = 21,
	})
	body.TextScaled = false
	body.TextSize = 14

	local templates = Instance.new("Folder")
	templates.Name = "Templates"
	templates.Parent = gui
	local icon = UiKit.Slot(templates, "IconTemplate", { Size = UDim2.fromOffset(size, size) }, true)
	UiKit.Icon(icon, "Image", "", {
		Position = UDim2.fromOffset(5, 3),
		Size = UDim2.new(1, -10, 1, -14),
		ZIndex = 2,
	})
	UiKit.Text(icon, "Glyph", "?", {
		_Style = "Heading",
		Position = UDim2.fromOffset(4, 3),
		Size = UDim2.new(1, -8, 0.58, 0),
		ZIndex = 2,
	})
	UiKit.Text(icon, "Timer", "", {
		_Style = "Number",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -2),
		Size = UDim2.new(1, -4, 0, 13),
		ZIndex = 3,
	})
	return gui
end

return Builder
