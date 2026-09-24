--------------------------------------------------------------------------------
-- DropPreviewUi (v20) — окно шансов наград жеод и сундуков.
-- Клиент: DropPreviewUI.client.lua (строки и фишки — клоны Templates/*).
--
-- СТРУКТУРА (контракт):
--   ScreenGui "DropPreviewUi" (Enabled=false)
--   ├─ TextButton "Dimmer"
--   └─ ImageLabel "Panel" [окно, Flat] (UIScale "PanelScale")
--        ├─ TitleBar → "Title";  ImageButton "CloseButton"
--        ├─ Frame "SourceTabs" → ImageButton "Geode", "Chest" (+ Caption)
--        ├─ ScrollingFrame "Types"   — фишки типов
--        ├─ ImageLabel "RowsBg" [Inset] + ScrollingFrame "Rows"
--        ├─ ImageLabel "Detail" [Card] → "Glow", ViewportFrame "BigPreview",
--        │    "DragHint", "Rarity", "ItemName", "Chance", "Desc"
--        ├─ TextLabel "Footer"
--        └─ Folder "Templates"
--             ├─ ImageButton "RowTemplate" [Card] → UIStroke "Select", "Bar",
--             │    ViewportFrame "Preview", "Title", "Rarity", "Chance", "OneIn",
--             │    "Track" → "Fill"
--             └─ ImageButton "ChipTemplate" [Button_Dark] → "Caption"
--------------------------------------------------------------------------------
local UiKit = require(script.Parent.Parent.UiKit)
local Theme = UiKit.Theme

local Builder = {}
Builder.VERSION = 21
Builder.W, Builder.H = 800, 540

local function viewport(parent, name, props)
	local v = Instance.new("ViewportFrame")
	v.Name = name
	v.BackgroundTransparency = 1
	v.BorderSizePixel = 0
	for k, value in props do v[k] = value end
	v.Parent = parent
	return v
end

function Builder.Build()
	local gui = UiKit.Screen("DropPreviewUi", { DisplayOrder = 65 })
	gui.Enabled = false
	gui:SetAttribute("UiKitVersion", Builder.VERSION)
	UiKit.Dimmer(gui, { Visible = true })

	local panel, parts = UiKit.Window(gui, "Panel", {
		Title = "DROP CHANCES",
		Accent = "Gold",
		Size = UDim2.fromOffset(Builder.W, Builder.H),
		Visible = true,
		Flat = true,
		CloseInRoot = true,
	})
	UiKit.Scale(panel, "PanelScale", 1)
	local top, pad = parts.Top, parts.Pad

	local tabs = UiKit.Tabs(panel, "SourceTabs", {
		{ Name = "Geode", Text = "GEODES" },
		{ Name = "Chest", Text = "CHESTS" },
	}, "Gold", {
		Position = UDim2.fromOffset(pad, top),
		Size = UDim2.fromOffset(300, 38),
		ZIndex = 3,
	})
	tabs:FindFirstChildOfClass("UIListLayout").HorizontalAlignment = Enum.HorizontalAlignment.Left

	local chips = UiKit.Scroll(panel, "Types", {
		Position = UDim2.fromOffset(pad, top + 46),
		Size = UDim2.new(1, -pad * 2, 0, 40),
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollBarThickness = 3,
		ZIndex = 3,
	})
	UiKit.List(chips, { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Center })
	UiKit.Padding(chips, 0, 3, 3, 3)

	local listTop = top + 94
	local bottom = 44
	UiKit.Plate(panel, "RowsBg", "Inset", {
		Position = UDim2.fromOffset(pad, listTop),
		Size = UDim2.new(1, -(pad * 3 + 256), 1, -(listTop + bottom)),
		ZIndex = 2,
	})
	local rows = UiKit.Scroll(panel, "Rows", {
		Position = UDim2.fromOffset(pad, listTop),
		Size = UDim2.new(1, -(pad * 3 + 256), 1, -(listTop + bottom)),
		ZIndex = 3,
	})
	UiKit.List(rows, { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center })
	UiKit.Padding(rows, 8, 0, 8, 8)

	-- Большой предпросмотр справа.
	local detail = UiKit.Card(panel, "Detail", "Grey", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -pad, 0, listTop),
		Size = UDim2.new(0, 256, 1, -(listTop + bottom)),
		ZIndex = 3,
	})
	local glow = UiKit.Group(detail, "Glow", {
		BackgroundTransparency = 0.6,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.new(1, 0, 0, 180),
		ZIndex = 3,
	})
	local glowGradient = UiKit.Gradient(glow, Color3.new(1, 1, 1), Color3.new(1, 1, 1), 90, "Fade")
	glowGradient.Transparency = UiKit.NSeq(0.3, 1)
	viewport(detail, "BigPreview", {
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.new(1, -20, 0, 172),
		ZIndex = 4,
	})
	local function line(name, text, y, h, style, color)
		return UiKit.Text(detail, name, text, {
			_Style = style,
			Position = UDim2.fromOffset(12, y),
			Size = UDim2.new(1, -24, 0, h),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = color or Theme.Colors.Text,
			ZIndex = 5,
		})
	end
	line("DragHint", "drag to rotate", 162, 14, "Small", Theme.Colors.SubText).TextXAlignment = Enum.TextXAlignment.Center
	line("Rarity", "LEGENDARY", 186, 18, "Heading")
	line("ItemName", "CRYSTAL", 204, 30, "Title")
	line("Chance", "1%  ·  1 in 100", 236, 22, "Number", Theme.Colors.Money)
	local desc = line("Desc", "", 262, 60, "Body", Theme.Colors.SubText)
	desc.TextScaled = false
	desc.TextSize = 15
	desc.TextYAlignment = Enum.TextYAlignment.Top

	UiKit.Text(panel, "Footer", "", {
		_Style = "Body",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, pad, 1, -10),
		Size = UDim2.new(1, -pad * 2, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Colors.SubText,
		ZIndex = 3,
	})

	-- ШАБЛОНЫ
	local templates = Instance.new("Folder")
	templates.Name = "Templates"
	templates.Parent = panel

	local row = UiKit.CardButton(templates, "RowTemplate", "Grey", {
		Size = UDim2.new(1, -16, 0, 58),
		ZIndex = 4,
	})
	local select = UiKit.Stroke(row, Theme.Accents.Gold.Main, 3, 0, "Select")
	select.Enabled = false
	UiKit.Plate(row, "Bar", "Divider", {
		_Accent = "Grey",
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(0, 5, 1, -12),
		ZIndex = 5,
	})
	local preview = UiKit.Plate(row, "PreviewBg", "Slot", {
		Position = UDim2.fromOffset(18, 5),
		Size = UDim2.fromOffset(48, 48),
		ZIndex = 5,
	})
	viewport(preview, "Preview", { Size = UDim2.fromScale(1, 1), ZIndex = 6 })
	UiKit.Text(row, "Title", "CRYSTAL", {
		_Style = "Heading",
		Position = UDim2.fromOffset(74, 7),
		Size = UDim2.new(1, -220, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	})
	UiKit.Text(row, "Rarity", "COMMON", {
		_Style = "Small",
		Position = UDim2.fromOffset(74, 33),
		Size = UDim2.new(1, -220, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	})
	UiKit.Text(row, "Chance", "50%", {
		_Style = "Number",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 6),
		Size = UDim2.fromOffset(120, 26),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Colors.Money,
		ZIndex = 5,
	})
	UiKit.Text(row, "OneIn", "1 in 2", {
		_Style = "Small",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 34),
		Size = UDim2.fromOffset(120, 16),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Colors.SubText,
		ZIndex = 5,
	})
	UiKit.Bar(row, "Track", "Gold", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -10, 1, -4),
		Size = UDim2.fromOffset(120, 4),
		ZIndex = 5,
	})

	local chip = UiKit.Button(templates, "ChipTemplate", "STONE", "Dark", {
		Size = UDim2.fromOffset(110, 32),
		ZIndex = 4,
	})
	chip.LayoutOrder = 0
	UiKit.HideTemplates(gui) -- шаблоны выключены с рождения
	return gui
end

return Builder
