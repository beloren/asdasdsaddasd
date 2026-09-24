--------------------------------------------------------------------------------
-- MinerDialogUiBuilder — диалог шахтёра в стиле Grow a Garden (v14.3).
--
-- Реплика висит В МИРЕ справа от шахтёра (BillboardGui, прикреплённый к его
-- голове), под ней — варианты ответа. Один источник правды для:
--   • tools/BuildMinerDialogUI.lua (Command Bar) → StarterGui/MinerDialogUi,
--     дальше вид правится мышкой;
--   • MineExpeditionUI.client.lua — строит сам, если в StarterGui нет свежей
--     версии (атрибут MinerDialogVersion меньше VERSION).
--
-- СТРУКТУРА:
--   BillboardGui "MinerDialogUi"   (Adornee ставит клиент — голова шахтёра)
--   └─ Frame "Root"               (+ UIScale "Pop")
--        ├─ Frame "Bubble"         — облачко реплики
--        │    ├─ Frame "Tail"      — хвостик к шахтёру (слева)
--        │    ├─ Frame "NameTag" → TextLabel "Title"
--        │    └─ TextLabel "Text"
--        └─ Frame "Choices"        (UIListLayout)
--             └─ TextButton "ChoiceTemplate" (Visible = false, клиент клонирует)
--                  └─ TextLabel "Label"
-- Цвет кнопки клиент задаёт по смыслу ответа (зелёный — да, красный — нет,
-- дерево — вопрос). Позиция облачка относительно шахтёра —
-- BillboardGui.StudsOffset (X — вправо по экрану).
--------------------------------------------------------------------------------
local Builder = {}
Builder.VERSION = 1

Builder.CREAM = Color3.fromRGB(255, 246, 222)
Builder.OUTLINE = Color3.fromRGB(62, 38, 18)
Builder.CHOICE_COLORS = {
	Yes = Color3.fromRGB(96, 200, 72),
	No = Color3.fromRGB(226, 84, 70),
	Ask = Color3.fromRGB(214, 160, 84),
}

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

local function stroke(parent, color, thickness, contextual)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.ApplyStrokeMode = contextual and Enum.ApplyStrokeMode.Contextual or Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

function Builder.Build()
	local gui = Instance.new("BillboardGui")
	gui.Name = "MinerDialogUi"
	gui.ResetOnSpawn = false
	gui.Active = true
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 80
	gui.Size = UDim2.fromOffset(300, 250)
	gui.SizeOffset = Vector2.new(0.5, -0.1) -- растём вправо от точки крепления
	gui.StudsOffset = Vector3.new(2.2, 1.2, 0)
	gui.Enabled = false
	gui:SetAttribute("MinerDialogVersion", Builder.VERSION)

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = gui
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Parent = root

	local bubble = Instance.new("Frame")
	bubble.Name = "Bubble"
	bubble.Position = UDim2.fromOffset(14, 14)
	bubble.Size = UDim2.new(1, -18, 0, 104)
	bubble.BackgroundColor3 = Builder.CREAM
	bubble.BorderSizePixel = 0
	bubble.Parent = root
	corner(bubble, UDim.new(0, 16))
	stroke(bubble, Builder.OUTLINE, 3)

	local tail = Instance.new("Frame")
	tail.Name = "Tail"
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = UDim2.new(0, 0, 0, 62)
	tail.Size = UDim2.fromOffset(18, 18)
	tail.Rotation = 45
	tail.BackgroundColor3 = Builder.CREAM
	tail.BorderSizePixel = 0
	tail.ZIndex = 0
	tail.Parent = bubble
	stroke(tail, Builder.OUTLINE, 3)

	local nameTag = Instance.new("Frame")
	nameTag.Name = "NameTag"
	nameTag.AnchorPoint = Vector2.new(0, 0.5)
	nameTag.Position = UDim2.fromOffset(14, 0)
	nameTag.Size = UDim2.fromOffset(96, 26)
	nameTag.BackgroundColor3 = Color3.fromRGB(96, 200, 72)
	nameTag.BorderSizePixel = 0
	nameTag.ZIndex = 3
	nameTag.Parent = bubble
	corner(nameTag, UDim.new(1, 0))
	stroke(nameTag, Builder.OUTLINE, 2.5)
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -12, 1, -4)
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.5)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Text = "MINER"
	title.ZIndex = 4
	title.Parent = nameTag
	stroke(title, Builder.OUTLINE, 1.5, true)

	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Position = UDim2.fromOffset(14, 18)
	text.Size = UDim2.new(1, -28, 1, -26)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextSize = 19
	text.TextWrapped = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.TextColor3 = Color3.fromRGB(70, 44, 22)
	text.RichText = true
	text.Text = "Hey there! Wanna head into the mine?"
	text.ZIndex = 2
	text.Parent = bubble

	local choices = Instance.new("Frame")
	choices.Name = "Choices"
	choices.Position = UDim2.fromOffset(30, 128)
	choices.Size = UDim2.new(1, -40, 0, 120)
	choices.BackgroundTransparency = 1
	choices.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = choices

	local template = Instance.new("TextButton")
	template.Name = "ChoiceTemplate"
	template.Size = UDim2.new(1, 0, 0, 34)
	template.BackgroundColor3 = Builder.CHOICE_COLORS.Yes
	template.AutoButtonColor = true
	template.Text = ""
	template.Visible = false
	template.Parent = choices
	corner(template, UDim.new(0, 10))
	stroke(template, Builder.OUTLINE, 2.5)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200))
	gradient.Parent = template
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, -16, 1, -8)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = "Let's dig!"
	label.Parent = template
	stroke(label, Builder.OUTLINE, 1.5, true)

	return gui
end

return Builder
