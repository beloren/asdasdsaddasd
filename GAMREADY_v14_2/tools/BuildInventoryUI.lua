-- Standalone Studio Command Bar builder: StarterGui/InventoryUi + StarterGui/HotbarUi.
-- Rerunning replaces only these two ScreenGui.
--
-- СТИЛЬ — единый с магазином/квестами/дейликами (см. tools/BuildShopUi.lua):
-- тёмные полупрозрачные панели, скругление 0-4px, тонкие рамки, цвет =
-- функция (жёлтый — действие, зелёный — успех/экипировано, красный —
-- закрыть/снять, синий — информация).
--
-- КОНТРАКТ (клиент src/client/InventoryUI.client.lua ищет ИМЕННО эти имена):
--   ScreenGui "InventoryUi"
--   ├─ TextButton "Dimmer"
--   └─ Frame "Panel"
--      ├─ Frame "TabBar" → TextButton "Tab_Backpack" / "Tab_Pickaxes" / "Tab_Index"
--      ├─ ImageButton "CloseButton"
--      ├─ Frame "Toolbar" → TextBox "SearchBox", TextButton "SortButton",
--      │                     TextLabel "CountLabel"
--      ├─ ScrollingFrame "Grid"        — сюда клонируется "ItemTemplate"
--      ├─ Frame "DetailPanel"          — правая колонка: превью выбранного
--      └─ Frame "ItemTemplate"         — шаблон ячейки (Visible = false)
--
--   ScreenGui "HotbarUi"
--   └─ Frame "Bar" → "Slot1".."Slot6" + "PickaxeSlot" (центральный, клавиша F)
--
-- Вкладка "Index" НЕ строит свою сетку: она просто открывает уже
-- существующее окно коллекции (CollectionMenu) — дублировать его внутри
-- инвентаря значило бы держать две копии одного и того же экрана.

local StarterGui = game:GetService("StarterGui")

local COLORS = {
	Panel = Color3.fromRGB(18, 17, 23),
	Header = Color3.fromRGB(12, 11, 16),
	Card = Color3.fromRGB(30, 28, 38),
	Stroke = Color3.fromRGB(70, 75, 90),
	Yellow = Color3.fromRGB(230, 185, 60),
	Green = Color3.fromRGB(80, 200, 90),
	Red = Color3.fromRGB(220, 70, 70),
	Blue = Color3.fromRGB(110, 175, 255),
	White = Color3.fromRGB(245, 247, 255),
}

-- Градиент на каждую вкладку — как у секций магазина, чтобы вкладки
-- различались с первого взгляда (см. референс).
local TAB_GRADIENTS = {
	Backpack = { From = Color3.fromRGB(120, 80, 20), To = Color3.fromRGB(40, 28, 14) },
	Cart     = { From = Color3.fromRGB(40, 100, 120), To = Color3.fromRGB(18, 38, 48) },
	Pickaxes = { From = Color3.fromRGB(110, 40, 40), To = Color3.fromRGB(38, 18, 18) },
	Index    = { From = Color3.fromRGB(30, 70, 110), To = Color3.fromRGB(16, 28, 42) },
}
local TAB_ORDER = { "Backpack", "Pickaxes", "Index" }

local function addCorner(inst, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0, 4)
	c.Parent = inst
	return c
end

local function addStroke(inst, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 1
	s.Parent = inst
	return s
end

local function label(parent, name, text, size, position, textSize, color)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.Text = text
	l.TextColor3 = color or COLORS.White
	l.TextSize = textSize or 16
	l.TextStrokeColor3 = Color3.new(0, 0, 0)
	l.TextStrokeTransparency = 0
	l.Parent = parent
	return l
end

--------------------------------------------------------------------------------
-- ОКНО ИНВЕНТАРЯ
--------------------------------------------------------------------------------
local existing = StarterGui:FindFirstChild("InventoryUi")
if existing then existing:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "InventoryUi"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 26
gui.Enabled = false
gui.Parent = StarterGui

local dimmer = Instance.new("TextButton")
dimmer.Name = "Dimmer"
dimmer.Size = UDim2.fromScale(1, 1)
dimmer.BackgroundColor3 = Color3.new(0, 0, 0)
dimmer.BackgroundTransparency = 1
dimmer.Text = ""
dimmer.AutoButtonColor = false
dimmer.ZIndex = 1
dimmer.Parent = gui

local panel = Instance.new("ImageLabel")
panel.Name = "Panel"
panel.Position = UDim2.new(0.5, 0, 1, 260)
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Size = UDim2.fromOffset(820, 220)
panel.BackgroundColor3 = COLORS.Panel
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel = 0
panel.ZIndex = 2
panel.Parent = gui
addCorner(panel)
addStroke(panel, Color3.fromRGB(150, 100, 210), 1)
local panelGradient = Instance.new("UIGradient")
panelGradient.Color = ColorSequence.new(Color3.fromRGB(42, 30, 64), Color3.fromRGB(16, 20, 30))
panelGradient.Rotation = 90
panelGradient.Parent = panel

-- ВКЛАДКИ — крупные цветные кнопки сверху (см. референс).
local tabBar = Instance.new("Frame")
tabBar.Name = "TabBar"
tabBar.Position = UDim2.fromOffset(14, 12)
tabBar.Size = UDim2.new(1, -110, 0, 52)
tabBar.BackgroundTransparency = 1
tabBar.ZIndex = 3
tabBar.Parent = panel
tabBar.Visible = false

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 10)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Parent = tabBar

for i, tabName in TAB_ORDER do
	local tab = Instance.new("TextButton")
	tab.Name = "Tab_" .. tabName
	tab.LayoutOrder = i
	tab.Size = UDim2.fromOffset(170, 52)
	tab.BackgroundColor3 = Color3.new(1, 1, 1)
	tab.AutoButtonColor = false
	tab.Font = Enum.Font.FredokaOne
	tab.TextSize = 22
	tab.TextColor3 = COLORS.White
	tab.TextStrokeColor3 = Color3.new(0, 0, 0)
	tab.TextStrokeTransparency = 0
	tab.Text = tabName
	tab.ZIndex = 3
	tab.Parent = tabBar
	addCorner(tab)
	addStroke(tab, COLORS.Stroke, 1)
	local grad = TAB_GRADIENTS[tabName]
	if grad then
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Color = ColorSequence.new(grad.From, grad.To)
		gradient.Parent = tab
	end
end

local close = Instance.new("ImageButton")
close.Name = "CloseButton"
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -14, 0, 12)
close.Size = UDim2.fromOffset(52, 52)
close.BackgroundColor3 = Color3.fromRGB(60, 26, 26)
close.AutoButtonColor = false
close.ZIndex = 3
close.Parent = panel
addCorner(close)
addStroke(close, COLORS.Red, 2)
local closeX = label(close, "Caption", "X", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 26, COLORS.Red)
closeX.TextXAlignment = Enum.TextXAlignment.Center
closeX.ZIndex = 4

-- ПАНЕЛЬ ИНСТРУМЕНТОВ: поиск / сортировка / продать всё / счётчик слотов.
local toolbar = Instance.new("Frame")
toolbar.Name = "Toolbar"
toolbar.Position = UDim2.fromOffset(14, 74)
toolbar.Size = UDim2.new(1, -28, 0, 44)
toolbar.BackgroundTransparency = 1
toolbar.ZIndex = 3
toolbar.Parent = panel
toolbar.Visible = false

local search = Instance.new("TextBox")
search.Name = "SearchBox"
search.Position = UDim2.fromOffset(0, 0)
search.Size = UDim2.fromOffset(300, 44)
search.BackgroundColor3 = COLORS.Card
search.BorderSizePixel = 0
search.Font = Enum.Font.FredokaOne
search.PlaceholderText = "Search"
search.Text = ""
search.TextSize = 18
search.TextColor3 = COLORS.White
search.TextXAlignment = Enum.TextXAlignment.Left
search.ClearTextOnFocus = false
search.ZIndex = 3
search.Parent = toolbar
addCorner(search)
addStroke(search, COLORS.Stroke, 1)
local searchPad = Instance.new("UIPadding")
searchPad.PaddingLeft = UDim.new(0, 12)
searchPad.Parent = search

local sort = Instance.new("TextButton")
sort.Name = "SortButton"
sort.Position = UDim2.fromOffset(312, 0)
sort.Size = UDim2.fromOffset(190, 44)
sort.BackgroundColor3 = COLORS.Card
sort.AutoButtonColor = false
sort.Font = Enum.Font.FredokaOne
sort.TextSize = 18
sort.TextColor3 = COLORS.White
sort.Text = "Sort By Rarity"
sort.ZIndex = 3
sort.Parent = toolbar
addCorner(sort)
addStroke(sort, COLORS.Stroke, 1)

local countLabel = label(toolbar, "CountLabel", "0/24", UDim2.fromOffset(120, 44), UDim2.new(1, -164, 0, 0), 18, COLORS.Blue)
countLabel.TextXAlignment = Enum.TextXAlignment.Right
countLabel.ZIndex = 3

-- СЕТКА ПРЕДМЕТОВ (слева) + ПАНЕЛЬ ДЕТАЛЕЙ (справа), как на референсе.
local grid = Instance.new("ScrollingFrame")
grid.Name = "Grid"
grid.Position = UDim2.fromOffset(14, 14)
grid.Size = UDim2.new(1, -28, 1, -28)
grid.BackgroundColor3 = COLORS.Card
grid.BackgroundTransparency = 0.4
grid.BorderSizePixel = 0
grid.ScrollBarThickness = 6
grid.ScrollBarImageColor3 = Color3.fromRGB(150, 100, 210)
grid.CanvasSize = UDim2.new(0, 0, 0, 0)
grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
grid.ZIndex = 3
grid.Parent = panel
grid.BackgroundTransparency = 1
addCorner(grid)
addStroke(grid, COLORS.Stroke, 1)

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.fromOffset(96, 96)
gridLayout.CellPadding = UDim2.fromOffset(8, 8)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = grid
local gridPad = Instance.new("UIPadding")
gridPad.PaddingTop = UDim.new(0, 8)
gridPad.PaddingLeft = UDim.new(0, 8)
gridPad.Parent = grid

local detail = Instance.new("Frame")
detail.Name = "DetailPanel"
detail.AnchorPoint = Vector2.new(1, 0)
detail.Position = UDim2.new(1, -14, 0, 128)
detail.Size = UDim2.fromOffset(258, 0)
detail.AutomaticSize = Enum.AutomaticSize.None
detail.BackgroundColor3 = COLORS.Card
detail.BackgroundTransparency = 0.4
detail.BorderSizePixel = 0
detail.ZIndex = 3
detail.Parent = panel
detail.Visible = false
detail.Size = UDim2.new(0, 258, 1, -142)
addCorner(detail)
addStroke(detail, COLORS.Stroke, 1)

local detailViewport = Instance.new("ImageLabel")
detailViewport.Name = "Preview"
detailViewport.AnchorPoint = Vector2.new(0.5, 0)
detailViewport.Position = UDim2.new(0.5, 0, 0, 14)
detailViewport.Size = UDim2.fromOffset(190, 190)
detailViewport.BackgroundTransparency = 1
detailViewport.ScaleType = Enum.ScaleType.Fit
detailViewport.Image = ""
detailViewport.ZIndex = 4
detailViewport.Parent = detail

local detailName = label(detail, "NameLabel", "", UDim2.new(1, -20, 0, 30), UDim2.fromOffset(10, 212), 20)
detailName.TextXAlignment = Enum.TextXAlignment.Center
detailName.ZIndex = 4
local detailRarity = label(detail, "RarityLabel", "", UDim2.new(1, -20, 0, 24), UDim2.fromOffset(10, 244), 16, COLORS.Blue)
detailRarity.TextXAlignment = Enum.TextXAlignment.Center
detailRarity.ZIndex = 4
local detailStats = label(detail, "StatsLabel", "", UDim2.new(1, -20, 0, 120), UDim2.fromOffset(10, 272), 15)
detailStats.TextXAlignment = Enum.TextXAlignment.Left
detailStats.TextYAlignment = Enum.TextYAlignment.Top
detailStats.TextWrapped = true
detailStats.ZIndex = 4

-- Главная кнопка детали: для руды — "Hold" (взять в руки), для кирки —
-- "Equip"/"Unequip". Текст и цвет ставит клиент.
local detailAction = Instance.new("TextButton")
detailAction.Name = "ActionButton"
detailAction.AnchorPoint = Vector2.new(0.5, 1)
detailAction.Position = UDim2.new(0.5, 0, 1, -12)
detailAction.Size = UDim2.new(1, -20, 0, 46)
detailAction.BackgroundColor3 = COLORS.Green
detailAction.AutoButtonColor = false
detailAction.Font = Enum.Font.FredokaOne
detailAction.TextSize = 20
detailAction.TextColor3 = Color3.fromRGB(12, 30, 16)
detailAction.Text = "Hold"
detailAction.Visible = false
detailAction.ZIndex = 4
detailAction.Parent = detail
addCorner(detailAction)

-- ШАБЛОН ЯЧЕЙКИ — клиент клонирует его под каждый предмет.
local itemTemplate = Instance.new("ImageButton")
itemTemplate.Name = "ItemTemplate"
itemTemplate.Size = UDim2.fromOffset(96, 96)
itemTemplate.BackgroundColor3 = COLORS.Card
itemTemplate.AutoButtonColor = false
itemTemplate.Image = ""
itemTemplate.Visible = false
itemTemplate.ZIndex = 3
itemTemplate.Parent = panel
addCorner(itemTemplate)
local itemStroke = addStroke(itemTemplate, COLORS.Stroke, 1)
itemStroke.Name = "RarityStroke" -- клиент красит по редкости предмета

local itemViewport = Instance.new("ImageLabel")
itemViewport.Name = "Preview"
itemViewport.AnchorPoint = Vector2.new(0.5, 0)
itemViewport.Position = UDim2.new(0.5, 0, 0, 4)
itemViewport.Size = UDim2.fromOffset(64, 64)
itemViewport.BackgroundTransparency = 1
itemViewport.ScaleType = Enum.ScaleType.Fit
itemViewport.Image = ""
itemViewport.ZIndex = 4
itemViewport.Parent = itemTemplate

local itemCount = label(itemTemplate, "CountLabel", "", UDim2.fromOffset(44, 20), UDim2.new(1, -48, 1, -24), 15, COLORS.White)
itemCount.TextXAlignment = Enum.TextXAlignment.Right
itemCount.ZIndex = 5
local itemName = label(itemTemplate, "NameLabel", "", UDim2.new(1, -8, 0, 18), UDim2.fromOffset(4, 72), 13)
itemName.TextXAlignment = Enum.TextXAlignment.Left
itemName.ZIndex = 5

--------------------------------------------------------------------------------
-- ХОТБАР — 6 обычных слотов + ЦЕНТРАЛЬНЫЙ слот кирки (клавиша F).
-- Порядок на экране: 1 2 3 [F] 4 5 6 — как на референсе.
--------------------------------------------------------------------------------
local oldEntry = StarterGui:FindFirstChild("InventoryEntry")
if oldEntry then oldEntry:Destroy() end

local existingHotbar = StarterGui:FindFirstChild("HotbarUi")
if existingHotbar then existingHotbar:Destroy() end

local hotbarGui = Instance.new("ScreenGui")
hotbarGui.Name = "HotbarUi"
hotbarGui.ResetOnSpawn = false
hotbarGui.IgnoreGuiInset = true
hotbarGui.DisplayOrder = 12
hotbarGui.Parent = StarterGui

local bar = Instance.new("Frame")
bar.Name = "Bar"
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -14)
	bar.Size = UDim2.fromOffset(7 * 55, 60)
bar.BackgroundTransparency = 1
bar.Parent = hotbarGui

local barLayout = Instance.new("UIListLayout")
barLayout.FillDirection = Enum.FillDirection.Horizontal
barLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
barLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	barLayout.Padding = UDim.new(0, 6)
barLayout.SortOrder = Enum.SortOrder.LayoutOrder
barLayout.Parent = bar

local function makeSlot(name, keyText, layoutOrder, isPickaxe)
	local slot = Instance.new("ImageButton")
	slot.Name = name
	slot.LayoutOrder = layoutOrder
	slot.Size = isPickaxe and UDim2.fromOffset(52, 52) or UDim2.fromOffset(45, 45)
	slot.BackgroundColor3 = isPickaxe and Color3.fromRGB(44, 40, 30) or Color3.fromRGB(26, 25, 32)
	slot.BackgroundTransparency = 0.15
	slot.AutoButtonColor = false
	slot.Image = ""
	slot.Parent = bar
	addCorner(slot)
	addStroke(slot, isPickaxe and COLORS.Yellow or COLORS.Stroke, isPickaxe and 2 or 1)

	local preview = Instance.new("ImageLabel")
	preview.Name = "Preview"
	preview.AnchorPoint = Vector2.new(0.5, 0.5)
	preview.Position = UDim2.fromScale(0.5, 0.5)
	preview.Size = UDim2.new(1, -6, 1, -6)
	preview.BackgroundTransparency = 1
	preview.ScaleType = Enum.ScaleType.Fit
	preview.Image = ""
	preview.ZIndex = 2
	preview.Parent = slot
	if isPickaxe then
		local shieldLabel = label(slot, "ShieldLabel", "SHIELD", UDim2.new(1, -6, 0, 22), UDim2.fromOffset(3, 15), 11, COLORS.Yellow)
		shieldLabel.TextXAlignment = Enum.TextXAlignment.Center
		shieldLabel.Visible = false
		shieldLabel.ZIndex = 4
		local cooldown = Instance.new("ImageLabel")
		cooldown.Name = "CooldownOverlay"
		cooldown.Size = UDim2.fromScale(1, 1)
		cooldown.BackgroundColor3 = Color3.new(0, 0, 0)
		cooldown.BackgroundTransparency = 0.35
		cooldown.Image = ""
		cooldown.Visible = false
		cooldown.ZIndex = 3
		cooldown.Parent = slot
		local cooldownText = Instance.new("TextLabel")
		cooldownText.Name = "CooldownText"
		cooldownText.AnchorPoint = Vector2.new(0.5, 0.5)
		cooldownText.Position = UDim2.fromScale(0.5, 0.5)
		cooldownText.Size = UDim2.fromScale(0.8, 0.5)
		cooldownText.BackgroundTransparency = 1
		cooldownText.Font = Enum.Font.FredokaOne
		cooldownText.TextScaled = true
		cooldownText.TextColor3 = COLORS.White
		cooldownText.Visible = false
		cooldownText.ZIndex = 4
		cooldownText.Parent = slot
	end

	-- Значок клавиши над слотом (см. референс — "1".."6" и "F").
	local key = Instance.new("TextLabel")
	key.Name = "KeyBadge"
	key.AnchorPoint = Vector2.new(0.5, 1)
	key.Position = UDim2.new(0.5, 0, 0, 2)
	key.Size = UDim2.fromOffset(26, 22)
	key.BackgroundColor3 = isPickaxe and COLORS.Yellow or Color3.fromRGB(70, 78, 100)
	key.Font = Enum.Font.FredokaOne
	key.Text = keyText
	key.TextSize = 15
	key.TextColor3 = isPickaxe and Color3.fromRGB(30, 24, 8) or COLORS.White
	key.ZIndex = 3
	key.Parent = slot
	addCorner(key, UDim.new(0, 3))

	local count = label(slot, "CountLabel", "", UDim2.fromOffset(34, 18), UDim2.new(1, -36, 1, -20), 14, COLORS.White)
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.ZIndex = 3
	return slot
end

-- 1 2 3 | F | 4 5 6 — LayoutOrder расставляет кирку ровно в центр.
makeSlot("Slot1", "1", 1, false)
makeSlot("Slot2", "2", 2, false)
makeSlot("Slot3", "3", 3, false)
makeSlot("PickaxeSlot", "F", 4, true)
makeSlot("Slot4", "4", 5, false)
makeSlot("Slot5", "5", 6, false)
makeSlot("Slot6", "6", 7, false)

print("[BuildInventoryUI] Done: StarterGui/InventoryUi + StarterGui/HotbarUi created.")
