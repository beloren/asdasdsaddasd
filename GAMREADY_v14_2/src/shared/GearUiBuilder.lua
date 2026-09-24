--------------------------------------------------------------------------------
-- GearUiBuilder — интерфейс снаряжения v8 (динамит, сундуки).
-- tools/BuildGearUI.lua кладёт результат в StarterGui/GearUi; клиент
-- GearHud.client.lua и сервер GearService берут шаблоны оттуда, а если
-- билдер не запускали — строят тем же модулем.
--
-- СТРУКТУРА (имена — контракт):
--   ScreenGui "GearUi" (BuilderVersion)
--   ├─ Frame "GearBar"            — слева, столбик слотов
--   │    └─ TextButton "SlotTemplate" (Visible=false)
--   │         ├─ ImageLabel "Image"  — пустой = эмодзи в "Icon"
--   │         ├─ TextLabel "Icon", TextLabel "Count", TextLabel "Key"
--   │         └─ UIStroke "Selected" (толще, когда предмет в руке)
--   ├─ TextLabel "AimHint"        — подсказка, пока предмет в руке
--   ├─ Frame "LootPopup"          — окно лута сундука
--   │    ├─ TextLabel "Title"
--   │    └─ Frame "List" → TextLabel "LineTemplate" (Visible=false)
--   └─ BillboardGui "ChestTimerTemplate" (Enabled=false) — над сундуком:
--        TextLabel "Title", TextLabel "Timer"
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Builder = {}
local OUTLINE = Color3.fromRGB(12, 14, 22)

local function corner(parent, px)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px or 8)
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

function Builder.BuildChestBillboard()
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ChestTimerTemplate"
	billboard.Enabled = false
	billboard.Size = UDim2.fromOffset(150, 52)
	billboard.StudsOffset = Vector3.new(0, 3.2, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 80
	billboard.LightInfluence = 0
	text(billboard, "Title", UDim2.new(1, 0, 0.45, 0), UDim2.new(), "Chest")
	text(billboard, "Timer", UDim2.new(1, 0, 0.55, 0), UDim2.fromScale(0, 0.45), "0:30")
	return billboard
end

function Builder.Build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "GearUi"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 13
	gui:SetAttribute("BuilderVersion", Config.Chests.GearUiVersion or 1)

	local bar = Instance.new("Frame")
	bar.Name = "GearBar"
	bar.AnchorPoint = Vector2.new(0, 0.5)
	bar.Position = UDim2.new(0, 12, 0.55, 0)
	bar.Size = UDim2.fromOffset(64, 330)
	bar.BackgroundTransparency = 1
	bar.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = bar

	local slot = Instance.new("TextButton")
	slot.Name = "SlotTemplate"
	slot.Visible = false
	slot.Text = ""
	slot.AutoButtonColor = false
	slot.Size = UDim2.fromOffset(60, 60)
	slot.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
	slot.BackgroundTransparency = 0.1
	slot.Parent = bar
	corner(slot, 12)
	stroke(slot, 3, OUTLINE, false, "Border")
	stroke(slot, 0, Color3.fromRGB(255, 215, 80), false, "Selected")
	local image = Instance.new("ImageLabel")
	image.Name = "Image"
	image.BackgroundTransparency = 1
	image.Image = ""
	image.Size = UDim2.new(1, -12, 1, -12)
	image.Position = UDim2.fromOffset(6, 6)
	image.Parent = slot
	text(slot, "Icon", UDim2.new(1, -10, 1, -18), UDim2.fromOffset(5, 3), "🧨")
	text(slot, "Count", UDim2.new(0.6, 0, 0, 18), UDim2.new(0.4, -4, 1, -20), "x0", Color3.fromRGB(255, 225, 120))
	text(slot, "Key", UDim2.fromOffset(16, 16), UDim2.fromOffset(3, 2), "", Color3.fromRGB(200, 205, 220), Enum.Font.GothamBlack)

	local hint = text(gui, "AimHint", UDim2.fromOffset(460, 26), UDim2.new(0.5, 0, 1, -150), "", Color3.fromRGB(255, 235, 150), Enum.Font.GothamBlack)
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Visible = false

	local popup = Instance.new("Frame")
	popup.Name = "LootPopup"
	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.Position = UDim2.fromScale(0.5, 0.42)
	popup.Size = UDim2.fromOffset(320, 230)
	popup.BackgroundColor3 = Color3.fromRGB(22, 26, 40)
	popup.BackgroundTransparency = 0.05
	popup.Visible = false
	popup.Parent = gui
	corner(popup, 14)
	stroke(popup, 4, OUTLINE)
	local popScale = Instance.new("UIScale")
	popScale.Name = "Pop"
	popScale.Parent = popup
	text(popup, "Title", UDim2.new(1, -20, 0, 34), UDim2.fromOffset(10, 10), "CHEST OPENED!", Color3.fromRGB(255, 215, 80))
	local list = Instance.new("Frame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(16, 52)
	list.Size = UDim2.new(1, -32, 1, -64)
	list.Parent = popup
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.Parent = list
	local line = text(list, "LineTemplate", UDim2.new(1, 0, 0, 26), UDim2.new(), "+ $1.2K", Color3.new(1, 1, 1), Enum.Font.GothamBold)
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.Visible = false

	Builder.BuildChestBillboard().Parent = gui
	return gui
end

return Builder
