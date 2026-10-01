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
-- v21 (v20.106): вид как на референсе - иконка БЕЗ рамки, под ней таймер
-- «01:36» с обводкой; подсказка - тёмная полупрозрачная плашка с цветной
-- подложкой (цвет эффекта), крупный заголовок и описание.
Builder.VERSION = 21
Builder.ICON_SIZE = 62
Builder.TIMER_HEIGHT = 20
Builder.ICON_GAP = 10
Builder.ICONS_PER_ROW = 4

function Builder.Build()
	local gui = UiKit.Screen("BuffBar", { DisplayOrder = 12 })
	gui.IgnoreGuiInset = false
	gui:SetAttribute("UiKitVersion", Builder.VERSION)

	local size, gap, perRow = Builder.ICON_SIZE, Builder.ICON_GAP, Builder.ICONS_PER_ROW
	local cellH = size + Builder.TIMER_HEIGHT
	local bar = UiKit.Group(gui, "Bar", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 1, -16),
		Size = UDim2.fromOffset(size * perRow + gap * (perRow - 1), 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	UiKit.Grid(bar, UDim2.fromOffset(size, cellH), UDim2.fromOffset(gap, 4), {
		FillDirectionMaxCells = perRow,
		StartCorner = Enum.StartCorner.BottomRight,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
	})

	-- Подсказка: тёмная плашка + цветная подложка (Tint красит клиент).
	local tooltip = Instance.new("Frame")
	tooltip.Name = "Tooltip"
	tooltip.AnchorPoint = Vector2.new(1, 1)
	tooltip.Size = UDim2.fromOffset(300, 104)
	tooltip.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
	tooltip.BackgroundTransparency = 0.2
	tooltip.BorderSizePixel = 0
	tooltip.Visible = false
	tooltip.ZIndex = 20
	tooltip.Parent = gui
	local outline = Instance.new("UIStroke")
	outline.Thickness = 3
	outline.Color = Color3.fromRGB(0, 0, 0)
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outline.Parent = tooltip
	local tint = Instance.new("Frame")
	tint.Name = "Tint"
	tint.Size = UDim2.fromScale(1, 1)
	tint.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	tint.BackgroundTransparency = 0.55
	tint.BorderSizePixel = 0
	tint.ZIndex = 20
	tint.Parent = tooltip
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 0
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.85), NumberSequenceKeypoint.new(1, 0),
	})
	gradient.Parent = tint
	local title = UiKit.Text(tooltip, "Title", "", {
		_Style = "Heading",
		_Stroke = 2,
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -24, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = 21,
	})
	title.TextScaled = true
	local body = UiKit.Text(tooltip, "Body", "", {
		_Style = "Heading",
		_Stroke = 2,
		Position = UDim2.fromOffset(12, 40),
		Size = UDim2.new(1, -24, 1, -48),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = 21,
	})
	body.TextScaled = false
	body.TextWrapped = true
	body.TextSize = 20

	local templates = Instance.new("Folder")
	templates.Name = "Templates"
	templates.Parent = gui
	-- Иконка без рамки: прозрачная кнопка, картинка на всю ширину, таймер под ней.
	local icon = Instance.new("ImageButton")
	icon.Name = "IconTemplate"
	icon.BackgroundTransparency = 1
	icon.Image = ""
	icon.Size = UDim2.fromOffset(size, cellH)
	icon.AutoButtonColor = false
	icon.Parent = templates
	local skinStroke = Instance.new("UIStroke") -- контракт: клиент красит; у иконки без рамки не видна
	skinStroke.Name = "SkinStroke"
	skinStroke.Transparency = 1
	skinStroke.Parent = icon
	UiKit.Icon(icon, "Image", "", {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(size, size),
		ZIndex = 2,
	})
	local glyph = UiKit.Text(icon, "Glyph", "?", {
		_Style = "Heading",
		_Stroke = 2,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(size, size),
		ZIndex = 2,
	})
	glyph.TextScaled = true
	local timer = UiKit.Text(icon, "Timer", "", {
		_Style = "Number",
		_Stroke = 2,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, 8, 0, Builder.TIMER_HEIGHT),
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = 3,
	})
	timer.TextScaled = true
	UiKit.HideTemplates(gui) -- шаблоны выключены с рождения
	return gui
end

return Builder
