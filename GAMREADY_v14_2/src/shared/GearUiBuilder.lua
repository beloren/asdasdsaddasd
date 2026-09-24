--------------------------------------------------------------------------------
-- GearUiBuilder (v20) — снаряжение (динамит, сундуки): подсказка прицела,
-- окно лута сундука, табличка таймера сундука. Единый стиль UiKit.
-- tools/BuildAllUI.lua кладёт результат в StarterGui/GearUi; клиент
-- GearHud.client.lua и сервер GearService берут шаблоны оттуда, а если
-- билдер не запускали — строят тем же модулем.
--
-- СТРУКТУРА (имена — контракт):
--   ScreenGui "GearUi" (BuilderVersion)
--   ├─ Frame "GearBar"            — слева, столбик слотов (сейчас скрыт)
--   │    └─ ImageButton "SlotTemplate" [Slot] (Visible=false)
--   │         ├─ ImageLabel "Image"  — пустой = эмодзи в "Icon"
--   │         ├─ TextLabel "Icon", TextLabel "Count", TextLabel "Key"
--   │         └─ UIStroke "Border", UIStroke "Selected" (толще, когда в руке)
--   ├─ ImageLabel "AimHint" [Toast] → "Title", "Text" — подсказка предмета в руке
--   ├─ ImageLabel "LootPopup" [Card] — окно лута сундука
--   │    ├─ TextLabel "Title"
--   │    └─ Frame "List" → TextLabel "LineTemplate" (Visible=false)
--   └─ BillboardGui "ChestTimerTemplate" (Enabled=false) — над сундуком:
--        ImageLabel "Plate" [Pill]; TextLabel "Title", TextLabel "Timer"
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local UiKit = require(script.Parent.UiKit)
local Theme = UiKit.Theme

local Builder = {}
Builder.VERSION = 21 -- v20.5: AimHint — плашка Title/Text

function Builder.BuildChestBillboard()
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ChestTimerTemplate"
	billboard.Enabled = false
	billboard.Size = UDim2.fromOffset(160, 56)
	billboard.StudsOffset = Vector3.new(0, 3.2, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 80
	billboard.LightInfluence = 0
	UiKit.Plate(billboard, "Plate", "Pill", { _Accent = "Gold", BackgroundTransparency = 0.4 })
	UiKit.Text(billboard, "Title", "Chest", {
		_Style = "Heading",
		Position = UDim2.fromOffset(6, 2),
		Size = UDim2.new(1, -12, 0.45, 0),
		ZIndex = 2,
	})
	UiKit.Text(billboard, "Timer", "0:30", {
		_Style = "Number",
		Position = UDim2.new(0, 6, 0.45, 0),
		Size = UDim2.new(1, -12, 0.5, -2),
		TextColor3 = Theme.Colors.Money,
		ZIndex = 2,
	})
	return billboard
end

function Builder.Build()
	local gui = UiKit.Screen("GearUi", { DisplayOrder = 13 })
	gui:SetAttribute("BuilderVersion", math.max(Config.Chests and Config.Chests.GearUiVersion or 1, Builder.VERSION))

	local bar = UiKit.Group(gui, "GearBar", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.55, 0),
		Size = UDim2.fromOffset(64, 330),
	})
	UiKit.List(bar, { Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Center })

	local slot = UiKit.Slot(bar, "SlotTemplate", { Size = UDim2.fromOffset(60, 60), Visible = false }, true)
	local skinStroke = slot:FindFirstChild("SkinStroke")
	if skinStroke then skinStroke.Name = "Border" end
	UiKit.Stroke(slot, Theme.Colors.Money, 0, 0, "Selected")
	UiKit.Icon(slot, "Image", "", {
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 1, -12),
		ZIndex = 2,
	})
	UiKit.Text(slot, "Icon", "🧨", {
		_Stroke = 0,
		Position = UDim2.fromOffset(5, 3),
		Size = UDim2.new(1, -10, 1, -18),
		ZIndex = 2,
	}).FontFace = Font.fromEnum(Enum.Font.GothamBold)
	UiKit.Text(slot, "Count", "x0", {
		_Style = "Number",
		Position = UDim2.new(0.4, -4, 1, -20),
		Size = UDim2.new(0.6, 0, 0, 18),
		TextColor3 = Theme.Colors.Money,
		ZIndex = 3,
	})
	UiKit.Text(slot, "Key", "", {
		_Style = "Number",
		Position = UDim2.fromOffset(3, 2),
		Size = UDim2.fromOffset(16, 16),
		ZIndex = 3,
	})

	-- v20.5: ПОДСКАЗКА ПРЕДМЕТА В РУКЕ (кроме руды) — плашка над хотбаром:
	-- «Title» — название (цвет предмета), «Text» — что делает · как применить.
	-- Тексты — Shared.ItemHints.
	local hint = UiKit.Plate(gui, "AimHint", "Toast", {
		_Accent = "Gold",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -96),
		Size = UDim2.fromOffset(460, 52),
		Visible = false,
	})
	UiKit.Text(hint, "Title", "Small Dynamite", {
		_Style = "Heading",
		_MaxTextSize = 20,
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -20, 0, 22),
		TextColor3 = Theme.Colors.Money,
		ZIndex = 2,
	})
	UiKit.Text(hint, "Text", "Blasts boulders · Click to throw", {
		_Style = "Body",
		_MaxTextSize = 16,
		Position = UDim2.fromOffset(10, 27),
		Size = UDim2.new(1, -20, 0, 20),
		TextColor3 = Theme.Colors.SubText,
		ZIndex = 2,
	})

	local popup = UiKit.Card(gui, "LootPopup", "Gold", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(340, 240),
		Visible = false,
	})
	UiKit.Scale(popup, "Pop", 1)
	UiKit.TitleText(popup, "Title", "CHEST OPENED!", "Gold", {
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(1, -20, 0, 38),
		ZIndex = 2,
	})
	local list = UiKit.Group(popup, "List", {
		Position = UDim2.fromOffset(16, 56),
		Size = UDim2.new(1, -32, 1, -68),
		ZIndex = 2,
	})
	UiKit.List(list, { Padding = UDim.new(0, 6) })
	UiKit.Text(list, "LineTemplate", "+ $1.2K", {
		_Style = "Heading",
		Size = UDim2.new(1, 0, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		ZIndex = 2,
	})

	Builder.BuildChestBillboard().Parent = gui
	return gui
end

return Builder
