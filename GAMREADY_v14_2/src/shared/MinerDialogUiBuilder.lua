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
local UiKit = require(script.Parent.UiKit)
local Theme = UiKit.Theme

local Builder = {}
Builder.VERSION = 20

Builder.CREAM = Color3.fromRGB(255, 246, 222)
Builder.OUTLINE = Color3.fromRGB(12, 10, 16)
-- Цвет кнопки ответа по смыслу: да / нет / вопрос.
Builder.CHOICE_COLORS = {
	Yes = Theme.Skins.Button_Green.Color,
	No = Theme.Skins.Button_Red.Color,
	Ask = Theme.Skins.Button_Yellow.Color,
}

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
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui:SetAttribute("MinerDialogVersion", Builder.VERSION)

	local root = UiKit.Group(gui, "Root", {})
	UiKit.Scale(root, "Pop", 1)

	-- Облачко реплики.
	local bubble = UiKit.Card(root, "Bubble", "Gold", {
		Position = UDim2.fromOffset(14, 14),
		Size = UDim2.new(1, -18, 0, 104),
	})
	bubble.BackgroundTransparency = 0.1
	local tail = UiKit.Plate(bubble, "Tail", "Card", {
		_Accent = "Gold",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0, 62),
		Size = UDim2.fromOffset(18, 18),
		Rotation = 45,
		ZIndex = 0,
	})
	tail.BackgroundTransparency = 0.1

	local nameTag = UiKit.Plate(bubble, "NameTag", "Pill", {
		_Accent = "Green",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.fromOffset(100, 26),
		BackgroundColor3 = Theme.Skins.Button_Green.Color,
		BackgroundTransparency = 0,
		ZIndex = 3,
	})
	UiKit.Text(nameTag, "Title", "MINER", {
		_Style = "Heading",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -12, 1, -4),
		ZIndex = 4,
	})

	local text = UiKit.Text(bubble, "Text", "Hey there! Wanna head into the mine?", {
		_Style = "Body",
		Position = UDim2.fromOffset(14, 18),
		Size = UDim2.new(1, -28, 1, -26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 2,
	})
	text.TextScaled = false
	text.TextSize = 20

	local choices = UiKit.Group(root, "Choices", {
		Position = UDim2.fromOffset(30, 128),
		Size = UDim2.new(1, -40, 0, 120),
	})
	UiKit.List(choices, { Padding = UDim.new(0, 6) })

	local template, caption = UiKit.Button(choices, "ChoiceTemplate", "Let's dig!", "Green", {
		Size = UDim2.new(1, 0, 0, 36),
		Visible = false,
	})
	caption.Name = "Label"
	return gui
end

return Builder
