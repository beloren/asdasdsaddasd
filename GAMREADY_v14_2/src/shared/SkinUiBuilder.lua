--------------------------------------------------------------------------------
-- SkinUiBuilder — меню скинов v8 в стиле магазина улучшений/островов:
-- сетка вертикальных карточек → экран скина с плюсами (▲) и минусами (▼)
-- и кнопкой EQUIP. tools/BuildSkinUIv3.lua кладёт результат в
-- StarterGui/SkinUi; SkinUI.client.lua строит сам, если билдер не запускали
-- (или в StarterGui лежит старое меню без BuilderVersion).
--
-- СТРУКТУРА (имена — контракт):
--   ScreenGui "SkinUi" (BuilderVersion)
--   ├─ TextButton "Dimmer"
--   └─ Frame "Panel" (UIScale "ResponsiveScale")
--        ├─ Frame "Tab" → TextLabel "Title"
--        ├─ TextButton "CloseButton"
--        ├─ Frame "GridView" → ScrollingFrame "Grid" → TextButton "CardTemplate"
--        │     CardTemplate: ImageLabel "Image", TextLabel "Name", TextLabel "Rarity",
--        │                   TextLabel "Equipped", UIStroke "RarityStroke"
--        └─ Frame "DetailView"
--             ├─ TextButton "BackButton"
--             ├─ Frame "PreviewCard" → ImageLabel "Image", TextLabel "Rarity"
--             ├─ TextLabel "Name"
--             ├─ Frame "Stats" → TextLabel "StatTemplate"
--             └─ TextButton "EquipButton" → TextLabel "Text"
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Builder = {}
local OUTLINE = Color3.fromRGB(12, 14, 22)

local function corner(parent, px)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px or 10)
	c.Parent = parent
end
local function stroke(parent, thickness, color, contextual, name)
	local s = Instance.new("UIStroke")
	if name then s.Name = name end
	s.Thickness = thickness or 2
	s.Color = color or OUTLINE
	s.ApplyStrokeMode = contextual and Enum.ApplyStrokeMode.Contextual or Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end
local function text(parent, name, size, position, content, color, font)
	local t = Instance.new("TextLabel")
	t.Name = name
	t.Size = size
	t.Position = position or UDim2.new()
	t.BackgroundTransparency = 1
	t.Text = content or ""
	t.TextColor3 = color or Color3.new(1, 1, 1)
	t.Font = font or Enum.Font.FredokaOne
	t.TextScaled = true
	t.RichText = true
	t.Parent = parent
	stroke(t, 2, OUTLINE, true)
	return t
end
local function button(parent, name, size, position, color, label)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.AutoButtonColor = true
	b.Size = size
	b.Position = position or UDim2.new()
	b.BackgroundColor3 = color
	b.Parent = parent
	corner(b, 10)
	stroke(b, 3, OUTLINE)
	text(b, "Text", UDim2.new(1, -12, 1, -10), UDim2.fromOffset(6, 5), label or "")
	return b
end

function Builder.Build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "SkinUi"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui:SetAttribute("BuilderVersion", Config.SkinUiVersion or 1)

	local dimmer = Instance.new("TextButton")
	dimmer.Name = "Dimmer"
	dimmer.Text = ""
	dimmer.AutoButtonColor = false
	dimmer.Size = UDim2.fromScale(1, 1)
	dimmer.BackgroundColor3 = Color3.new(0, 0, 0)
	dimmer.BackgroundTransparency = 0.5
	dimmer.Visible = false
	dimmer.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.53)
	panel.Size = UDim2.fromOffset(660, 440)
	panel.BackgroundColor3 = Color3.fromRGB(22, 26, 40)
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 14)
	stroke(panel, 5, OUTLINE)
	local scale = Instance.new("UIScale")
	scale.Name = "ResponsiveScale"
	scale.Parent = panel

	local tab = Instance.new("Frame")
	tab.Name = "Tab"
	tab.Position = UDim2.fromOffset(-12, -24)
	tab.Size = UDim2.fromOffset(220, 48)
	tab.BackgroundColor3 = Color3.fromRGB(150, 90, 255)
	tab.Parent = panel
	corner(tab, 8)
	stroke(tab, 3, OUTLINE)
	text(tab, "Title", UDim2.new(1, -24, 1, -10), UDim2.fromOffset(14, 5), "SKINS").TextXAlignment = Enum.TextXAlignment.Left

	local close = button(panel, "CloseButton", UDim2.fromOffset(46, 46), UDim2.new(1, -27, 0, -19), Color3.fromRGB(225, 50, 55), "X")
	close.ZIndex = 5

	local grid = Instance.new("Frame")
	grid.Name = "GridView"
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromOffset(16, 40)
	grid.Size = UDim2.new(1, -32, 1, -56)
	grid.Parent = panel
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Grid"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = grid
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(112, 172)
	layout.CellPadding = UDim2.fromOffset(12, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 6)
	padding.Parent = scroll

	local card = Instance.new("TextButton")
	card.Name = "CardTemplate"
	card.Visible = false
	card.Text = ""
	card.AutoButtonColor = true
	card.BackgroundColor3 = Color3.fromRGB(40, 44, 60)
	card.Parent = scroll
	corner(card, 12)
	stroke(card, 4, Color3.fromRGB(200, 200, 200), false, "RarityStroke")
	local image = Instance.new("ImageLabel")
	image.Name = "Image"
	image.BackgroundTransparency = 1
	image.Size = UDim2.new(1, -16, 0, 96)
	image.Position = UDim2.fromOffset(8, 8)
	image.ScaleType = Enum.ScaleType.Fit
	image.Parent = card
	text(card, "Name", UDim2.new(1, -10, 0, 22), UDim2.fromOffset(5, 108), "Skin")
	text(card, "Rarity", UDim2.new(1, -10, 0, 16), UDim2.fromOffset(5, 132), "RARE", Color3.fromRGB(120, 180, 255), Enum.Font.GothamBlack)
	local equipped = text(card, "Equipped", UDim2.new(1, -10, 0, 14), UDim2.fromOffset(5, 152), "✔ EQUIPPED", Color3.fromRGB(120, 255, 150), Enum.Font.GothamBlack)
	equipped.Visible = false

	local detail = Instance.new("Frame")
	detail.Name = "DetailView"
	detail.BackgroundTransparency = 1
	detail.Position = UDim2.fromOffset(16, 40)
	detail.Size = UDim2.new(1, -32, 1, -56)
	detail.Visible = false
	detail.Parent = panel
	button(detail, "BackButton", UDim2.fromOffset(110, 38), UDim2.fromOffset(0, 0), Color3.fromRGB(55, 140, 255), "◀ BACK")
	local preview = Instance.new("Frame")
	preview.Name = "PreviewCard"
	preview.Position = UDim2.fromOffset(20, 50)
	preview.Size = UDim2.fromOffset(160, 240)
	preview.BackgroundColor3 = Color3.fromRGB(40, 44, 60)
	preview.Parent = detail
	corner(preview, 14)
	stroke(preview, 4, Color3.fromRGB(200, 200, 200), false, "RarityStroke")
	local previewImage = image:Clone()
	previewImage.Size = UDim2.new(1, -20, 0, 170)
	previewImage.Position = UDim2.fromOffset(10, 12)
	previewImage.Parent = preview
	text(preview, "Rarity", UDim2.new(1, -10, 0, 24), UDim2.new(0, 5, 1, -40), "RARE", Color3.fromRGB(120, 180, 255), Enum.Font.GothamBlack)

	text(detail, "Name", UDim2.new(1, -220, 0, 36), UDim2.fromOffset(208, 4), "Skin Name").TextXAlignment = Enum.TextXAlignment.Left
	local stats = Instance.new("Frame")
	stats.Name = "Stats"
	stats.BackgroundTransparency = 1
	stats.Position = UDim2.fromOffset(208, 50)
	stats.Size = UDim2.new(1, -220, 0, 220)
	stats.Parent = detail
	local statsLayout = Instance.new("UIListLayout")
	statsLayout.Padding = UDim.new(0, 8)
	statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statsLayout.Parent = stats
	local statLine = text(stats, "StatTemplate", UDim2.new(1, 0, 0, 30), UDim2.new(), "▲ +10% Ore sell price", Color3.fromRGB(110, 255, 150), Enum.Font.GothamBlack)
	statLine.TextXAlignment = Enum.TextXAlignment.Left
	statLine.Visible = false
	local equipButton = button(detail, "EquipButton", UDim2.new(1, -220, 0, 52), UDim2.new(0, 208, 1, -58), Color3.fromRGB(70, 200, 95), "EQUIP")
	equipButton.AutoButtonColor = true
	return gui
end

return Builder
