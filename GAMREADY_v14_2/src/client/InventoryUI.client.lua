--------------------------------------------------------------------------------
-- InventoryUI (LocalScript) — инвентарь в стиле Satchel + хотбар, кирки,
-- руда в руках, дарение.
--
-- ЧТО ЭТО. Панель инвентаря построена по модели Satchel
-- (https://github.com/RyanLua/Satchel): тёмная полупрозрачная панель
-- ВЫЕЗЖАЕТ ПРЯМО НАД ХОТБАРОМ, той же ширины, с шапкой-поиском сверху и
-- сеткой квадратных ячеек 60x60 под ней. Открывается клавишей `~` (она же
-- русская `ё` — это ОДНА И ТА ЖЕ физическая клавиша Backquote, поэтому
-- раскладка значения не имеет), закрывается ей же или Escape.
--
-- ХОТБАР НЕ ПЕРЕДЕЛЫВАЕТСЯ. Скрипт берёт уже существующий StarterGui/
-- HotbarUi как есть (Bar → Slot1..Slot6 + PickaxeSlot) и только рисует в
-- нём содержимое. Вся новая геометрия — только у панели инвентаря, и она
-- ПРИВЯЗЫВАЕТСЯ к фактическому положению хотбара на экране
-- (AbsolutePosition/AbsoluteSize), а не к жёстким числам: подвинут хотбар —
-- панель поедет за ним сама.
--
-- ПЕРЕТАСКИВАНИЕ (главное, чего не хватало). Зажал руду → она "отрывается"
-- под курсор/палец → бросил на слот хотбара → она там. Бросил на другую
-- ячейку сетки → порядок в рюкзаке поменялся. Утащил из хотбара в сетку →
-- слот хотбара освободился. Короткое нажатие БЕЗ перетаскивания = взять в
-- руки. Ровно та же модель, что в Satchel и в популярных играх Roblox.
--
-- ГРАНИЦА ДОВЕРИЯ. Вся экономика и проверки — на СЕРВЕРЕ (см.
-- InventoryService). Этот скрипт только рисует снимок, который присылает
-- сервер, и отправляет НАМЕРЕНИЯ ("положи это в слот", "переставь",
-- "экипируй кирку", "подари"). Он ничего не начисляет и ничему не верит на
-- слово: после каждого действия ждёт нового Sync и перерисовывается по нему.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local Config = require(ReplicatedStorage.Shared.Config)
local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local UiRegistry = require(ReplicatedStorage.Shared.UiRegistry)
local UiKit = require(ReplicatedStorage.Shared.UiKit)
local hotbarGui = UiRegistry.Get("HotbarUi")
if not hotbarGui then
	warn("[InventoryUI] StarterGui/HotbarUi is missing. Run tools/BuildAllUI.lua.")
	return
end

local remote = ReplicatedStorage.Shared:WaitForChild("InventoryRequest", 10)
if not remote then
	warn("[InventoryUI] RemoteEvent InventoryRequest не появился — инвентарь работать не будет.")
	return
end

local bar = hotbarGui:WaitForChild("Bar")

-- v9: снаряжение (динамит, сундуки) живёт в этом же инвентаре. Данные —
-- GearService (data.Gear), слоты рюкзака не тратит; в хотбаре Uid "gear:<Key>".
local gearRemote = ReplicatedStorage.Shared:WaitForChild("GearRequest", 10)
local GEAR_INFO = {
	-- v12: упаковка тележки. Лежит в том же data.Gear, что динамит и сундуки,
	-- поэтому слот, иконка и перетаскивание достались ей даром — нужна была
	-- только подпись (см. CartService, раздел про владение тележкой).
	CartPackage = { Name = "Cart Package", Icon = "🛒", Color = Color3.fromRGB(120, 210, 255) },
	Dynamite = { Name = "Small Dynamite", Icon = "🧨", Color = Color3.fromRGB(215, 45, 45) },
	Dynamite_Medium = { Name = "Dynamite Bundle", Icon = "🧨", Color = Color3.fromRGB(255, 120, 40) },
	Dynamite_Mega = { Name = "Mega TNT", Icon = "💣", Color = Color3.fromRGB(255, 200, 40) },
	Chest_Common = { Name = "Common Chest", Icon = "📦" },
	Chest_Rare = { Name = "Rare Chest", Icon = "🎁" },
	Chest_Epic = { Name = "Epic Chest", Icon = "💜" },
	Chest_Legendary = { Name = "Legendary Chest", Icon = "👑" },
}
-- Зелья торговца: имя, иконка и цвет — из Config.Potions.
for potionKey, potionInfo in (Config.Potions and Config.Potions.Types) or {} do
	GEAR_INFO[potionKey] = { Name = potionInfo.DisplayName, Icon = potionInfo.Icon, Color = potionInfo.Color }
end
-- v18: эссенции мутаций (из жеод) — имя/цвет по мутации.
for _, mutationId in Config.Mutations.Order do
	local mutation = Config.Mutations[mutationId]
	if mutation then
		GEAR_INFO["Essence_" .. mutationId] = {
			Name = (mutation.DisplayName or mutationId) .. " Essence", Icon = "🧪",
			Color = mutation.Color or Color3.fromRGB(200, 120, 255),
		}
	end
end
-- v14: тотемы, декор и реликвии — тоже снаряжение. Подпись/иконка/цвет —
-- из PlaceableCatalog и Config.Relics (ключ реликвии: "Relic:<Id>:<Serial>:<Uid>").
local PlaceableCatalog = require(ReplicatedStorage.Shared.PlaceableCatalog)
local function gearInfo(key)
	if typeof(key) ~= "string" then return nil end
	local known = GEAR_INFO[key]
	if known then return known end
	local placeable = PlaceableCatalog.Info(key)
	if placeable then
		return { Name = placeable.DisplayName, Icon = placeable.Icon, Color = placeable.TierColor or placeable.Color }
	end
	local relicId, serial = key:match("^Relic:([%w]+):(%d+):")
	local relic = relicId and Config.Relics and Config.Relics.Types[relicId]
	if relic then
		local number = tonumber(serial) or 0
		return { Name = relic.DisplayName .. (number > 0 and (" #" .. number) or ""), Icon = relic.Icon, Color = PlaceableCatalog.RarityColor(relic.Rarity) }
	end
	return nil
end
local function gearCategory(key)
	if typeof(key) ~= "string" then return "Tools" end
	if key:match("^Totem_") then return "Totems" end
	if key:match("^Decor_") then return "Decor" end
	if key:match("^Relic:") then return "Relics" end
	return "Tools"
end
local function gearColor(key)
	local rarity = key and key:match("^Chest_(%a+)$")
	local info = rarity and Config.Chests and Config.Chests.Types[rarity]
	local known = gearInfo(key)
	return (info and info.Color) or (known and known.Color) or Color3.fromRGB(230, 70, 60)
end
local function gearKeyOf(uid)
	return type(uid) == "string" and uid:match("^gear:(.+)$") or nil
end

-- Старое окно инвентаря (и его отдельная кнопка входа) больше не нужны:
-- панель Satchel строится этим скриптом с нуля. Если в опубликованном
-- StarterGui остались объекты прошлой сборки — гасим, иначе они висят
-- поверх новой панели и перехватывают клики.
local legacyGui = playerGui:FindFirstChild("InventoryUi")
if legacyGui then legacyGui.Enabled = false end
local legacyEntry = playerGui:FindFirstChild("InventoryEntry")
if legacyEntry then legacyEntry:Destroy() end

--------------------------------------------------------------------------------
-- КОНСТАНТЫ SATCHEL (взяты из src/Satchel/SatchelScript/init.lua)
--------------------------------------------------------------------------------
local ICON_SIZE = 60
local ICON_BUFFER = 5
local INVENTORY_HEADER_SIZE = 40
local INVENTORY_TABS_SIZE = 32 -- v14: полоса вкладок сортировки под шапкой
local INVENTORY_ROWS_FULL = 4
local INVENTORY_ROWS_MINI = 2
local HOTBAR_SLOTS_WIDTH_CUTOFF = 1024

local BACKGROUND_COLOR = Color3.new(25 / 255, 27 / 255, 29 / 255)
local BACKGROUND_FADE = 0.3
local BACKGROUND_CORNER_RADIUS = UDim.new(0, 8)
local SLOT_CORNER_RADIUS = UDim.new(0, 8)
local SLOT_EQUIP_COLOR = Color3.new(0, 162 / 255, 1)
local SLOT_EQUIP_THICKNESS = 5
local SLOT_FADE_LOCKED = 0.3
local SLOT_BORDER_COLOR = Color3.new(1, 1, 1)

local SEARCH_WIDTH = 200
local SEARCH_BUFFER = 5
local SEARCH_CORNER_RADIUS = UDim.new(0, 3)
local SEARCH_BACKGROUND_COLOR = Color3.new(25 / 255, 27 / 255, 29 / 255)
local SEARCH_BACKGROUND_FADE = 0.2
local SEARCH_BORDER_COLOR = Color3.new(1, 1, 1)
local SEARCH_BORDER_FADE = 0.8
local SEARCH_BORDER_THICKNESS = 1

local TEXT_COLOR = Color3.new(1, 1, 1)
local TEXT_FADE = 0.5
local TEXT_FADE_COLOR = Color3.new(0, 0, 0)
local FONT_SIZE = 14

local DRAG_THRESHOLD = 8 -- пикселей: меньше — это клик, больше — перетаскивание

local function isSmallScreen()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
	return UserInputService.TouchEnabled and viewport.X < HOTBAR_SLOTS_WIDTH_CUTOFF
end

--------------------------------------------------------------------------------
-- СОСТОЯНИЕ
--------------------------------------------------------------------------------
local state = {
	Backpack = {},
	Cart = { Items = {}, Capacity = 0 },
	Hotbar = {},
	Gear = {},
	Slots = 24,
	PickaxeTier = 1,
	PickaxeMaxTier = 1,
	PickaxeSkin = "Default",
}

local isOpen = false
local searchText = ""
local heldStackIndex = nil -- какая стопка сейчас "в руках" (модель и позу рисует OreCarryPose)
local togglePickaxe
local renderGrid
local renderHotbar
-- Объявлены заранее: привязка слотов хотбара (refreshHotbarSlots) живёт
-- ВЫШЕ их определений, потому что хотбар может собраться раньше панели.
local bindDragSource
local toggleHotbarSlot
local handleSlotClick
local setCarried

local function rarityColor(rarity)
	return Config.RarityColors and Config.RarityColors[rarity] or Color3.fromRGB(200, 200, 200)
end

local function oreInfoFor(stack)
	return stack and stack.Ore and Config.OreByKey[stack.Ore] or nil
end

local function stackDisplayName(stack)
	if stack and stack.Gear then
		local gear = gearInfo(stack.Gear)
		return gear and gear.Name or stack.Gear
	end
	local info = oreInfoFor(stack)
	if not info then return stack and stack.Ore or "?" end
	local variant = Config.OreVariants[stack.Variant or 1]
	local name = info.DisplayName .. (variant and (" " .. variant.DisplayName) or "")
	if stack.Mutations and stack.Mutations ~= "" then
		name = stack.Mutations:upper() .. " " .. name
	end
	-- Слиток из плавильни (см. IslandService) — отдельная стопка с ценой x2.5.
	if stack.Smelted then
		name ..= " INGOT"
	end
	return name
end

-- Рюкзак приезжает RemoteEvent'ом и МОЖЕТ приехать словарём со строковыми
-- ключами (так бывает после круга через DataStore/JSON). Оператор `#` на
-- таком не работает и молча вернул бы 0 — считаем руками.
local function backpackCount()
	local total = 0
	for _ in state.Backpack do
		total += 1
	end
	return total
end

-- Хотбар приезжает ПЛОТНЫМ МАССИВОМ строк-Uid ("" = пустой слот). Это
-- единственная форма, которая переживает RemoteEvent без сюрпризов:
-- разреженный числовой словарь режется, а числовые ключи по дороге
-- превращаются в строки (см. документацию Roblox по remote-событиям).
local function hotbarAt(slotIndex)
	local uid = state.Hotbar[slotIndex]
	if type(uid) ~= "string" or uid == "" then return nil end
	return uid
end

-- Стопка по Uid. Предметы адресуются ТОЛЬКО так: индекс в массиве
-- меняется при каждом подборе/продаже/перестановке, Uid — никогда.
local function stackByUid(uid)
	if type(uid) ~= "string" or uid == "" then return nil end
	if gearKeyOf(uid) then
		for _, gearStack in state.Gear or {} do
			if gearStack.Uid == uid then return gearStack end
		end
		return nil
	end
	for _, stack in state.Backpack do
		if stack.Uid == uid then return stack end
	end
	return nil
end

--------------------------------------------------------------------------------
-- ПРЕВЬЮ ПРЕДМЕТА
--------------------------------------------------------------------------------
local function fillViewport(viewport, model)
	if viewport:IsA("ImageLabel") or viewport:IsA("ImageButton") then
		return
	end
	viewport:ClearAllChildren()
	if not model then return end
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	model.Parent = world
	local size
	if model:IsA("Model") then
		local _, boundsSize = model:GetBoundingBox()
		size = boundsSize
		model:PivotTo(CFrame.new())
	else
		size = model.Size
		model.CFrame = CFrame.new()
	end
	local distance = math.max(size.X, size.Y, size.Z) * 2.2 + 1
	local camera = Instance.new("Camera")
	camera.CFrame = CFrame.lookAt(Vector3.new(distance * 0.5, distance * 0.4, distance), Vector3.new())
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

local function setImagePreview(viewport, imageId)
	if not (viewport and (viewport:IsA("ImageLabel") or viewport:IsA("ImageButton"))) then
		return false
	end
	if imageId and imageId ~= 0 and tostring(imageId) ~= "0" then
		local text = tostring(imageId)
		viewport.Image = text:match("^rbxassetid://") and text or "rbxassetid://" .. text
	else
		viewport.Image = ""
	end
	return true
end

local function buildOrePreview(stack)
	local info = oreInfoFor(stack)
	if not info then return nil end
	local variant = Config.OreVariants[stack.Variant or 1]
	local ok, model = pcall(PlaceholderFactory.OreCrystal, info, variant)
	if not ok then return nil end
	for _, d in (model:IsA("Model") and model:GetDescendants() or { model }) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
	return model
end

-- ЗАПАСНАЯ ЗАЛИВКА: если у руды нет ImageId (или картинка не загрузилась),
-- ImageLabel остаётся ПУСТЫМ — визуально предмет просто исчезает, хотя он
-- на месте. Поэтому под картинку всегда кладём кружок цвета руды: даже без
-- иконки ячейка остаётся читаемой, а не пустой.
local function applyPreview(preview, stack)
	if not preview then return end
	-- v9: снаряжение — эмодзи-иконка на кружке своего цвета.
	local gearIcon = preview:FindFirstChild("GearIcon")
	if stack and stack.Gear then
		if not gearIcon then
			gearIcon = Instance.new("TextLabel")
			gearIcon.Name = "GearIcon"
			gearIcon.BackgroundTransparency = 1
			gearIcon.Size = UDim2.fromScale(1, 1)
			gearIcon.TextScaled = true
			require(game:GetService("ReplicatedStorage").Shared.UiKit).StyleText(gearIcon, "Heading") -- v20: шрифт темы
			gearIcon.ZIndex = (preview.ZIndex or 1) + 1
			gearIcon.Parent = preview
		end
		gearIcon.Visible = true
		gearIcon.Text = gearInfo(stack.Gear) and gearInfo(stack.Gear).Icon or "?"
		local fallbackGear = preview:FindFirstChild("ColorFallback")
		if fallbackGear then
			fallbackGear.Visible = true
			fallbackGear.BackgroundColor3 = gearColor(stack.Gear):Lerp(Color3.new(0, 0, 0), 0.35)
		end
		setImagePreview(preview, nil)
		return
	elseif gearIcon then
		gearIcon.Visible = false
	end
	local info = oreInfoFor(stack)

	local fallback = preview:FindFirstChild("ColorFallback")
	if not fallback then
		fallback = Instance.new("Frame")
		fallback.Name = "ColorFallback"
		fallback.AnchorPoint = Vector2.new(0.5, 0.5)
		fallback.Position = UDim2.fromScale(0.5, 0.5)
		fallback.Size = UDim2.fromScale(0.62, 0.62)
		fallback.BorderSizePixel = 0
		fallback.ZIndex = (preview.ZIndex or 1) - 1
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = fallback
		fallback.Parent = preview
	end
	fallback.Visible = stack ~= nil
	fallback.BackgroundColor3 = (info and info.Color) or Color3.fromRGB(150, 150, 160)

	if not setImagePreview(preview, info and info.ImageId or nil) then
		fillViewport(preview, stack and buildOrePreview(stack) or nil)
	end
end

--------------------------------------------------------------------------------
-- РУДА В РУКАХ + ЯРЛЫК РЕДКОСТИ
--------------------------------------------------------------------------------
-- РУДА В РУКАХ ТЕПЕРЬ СТРОИТСЯ НЕ ЗДЕСЬ.
--
-- Раньше этот файл сам собирал модель руды и приваривал её к кисти
-- игрока. Проблема была в том, что модель создавалась в workspace НА
-- КЛИЕНТЕ — то есть её видел ровно один человек, тот, кто взял руду.
-- Остальные игроки видели его с пустыми руками.
--
-- Теперь клиент только сообщает СЕРВЕРУ "я держу стопку N" ("Hold"), тот
-- выставляет на игроке реплицируемые атрибуты HeldOre/HeldOreVariant/
-- HeldOreMutations (см. InventoryService:SetHeldOre), а картинку и позу
-- рук строит отдельный скрипт у КАЖДОГО клиента — см.
-- client/OreCarryPose.client.lua. Это ровно та же схема, по которой
-- работает хват за тележку: сервер владеет фактом, клиенты — картинкой.
local function clearHeld()
	if heldStackIndex == nil then return end
	heldStackIndex = nil
	remote:FireServer("Hold") -- nil = руки пустые
end

local function holdStack(stackIndex)
	-- stackIndex здесь — Uid стопки, а не позиция в массиве.
	local stack = stackByUid(stackIndex)
	if not stack then return end
	-- v9: снаряжение берёт в руку GearService (повторный вызов — убрать).
	if stack.Gear then
		if heldStackIndex ~= nil then clearHeld() end
		if gearRemote then gearRemote:FireServer("Equip", stack.Gear) end
		return
	end
	-- v9: с телегой в руках руду не взять.
	if player:GetAttribute("CarryingCart") == true then return end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:UnequipTools() -- руда и кирка не могут быть в руках одновременно
	end
	heldStackIndex = stackIndex
	remote:FireServer("Hold", stackIndex)
end

--------------------------------------------------------------------------------
-- ПОСТРОЕНИЕ ПАНЕЛИ SATCHEL
--------------------------------------------------------------------------------
-- v20: панель собирается билдером (Shared.UiBuilders.InventoryUi →
-- StarterGui/SatchelInventory), здесь только логика.
local gui = UiRegistry.Get("SatchelInventory")
gui.ResetOnSpawn = false
gui.Enabled = false

local inventoryFrame = gui:WaitForChild("InventoryFrame")
local header = inventoryFrame:WaitForChild("Header")
local countLabel = header:WaitForChild("CountLabel")
local searchFrame = header:WaitForChild("SearchFrame")
local searchBox = searchFrame:WaitForChild("SearchBox")
local searchClear = searchFrame:WaitForChild("SearchClear")
searchClear.Visible = false

--------------------------------------------------------------------------------
-- v14: ВКЛАДКИ СОРТИРОВКИ — ALL / ORES / TOOLS / TOTEMS / DECOR / RELICS.
-- Фильтруют только сетку; хотбар не трогают.
--------------------------------------------------------------------------------
local INVENTORY_FILTERS = {
	{ Id = "All", Label = "ALL" }, { Id = "Ores", Label = "ORES" }, { Id = "Tools", Label = "TOOLS" },
	{ Id = "Totems", Label = "TOTEMS" }, { Id = "Decor", Label = "DECOR" }, { Id = "Relics", Label = "RELICS" },
}
local currentFilter = "All"
local filterButtons = {}
local tabsStrip = inventoryFrame:WaitForChild("FilterTabs")
local function paintFilterTabs()
	for id, button in filterButtons do
		local active = id == currentFilter
		if button:GetAttribute("UiSkin") then
			UiKit.ApplySkin(button, active and "TabActive" or "Tab")
			local caption = button:FindFirstChild("Caption")
			if caption then caption.TextColor3 = active and Color3.new(1, 1, 1) or UiKit.Theme.Skins.Tab.TextColor end
		else
			button.BackgroundColor3 = active and Color3.fromRGB(90, 160, 255) or SEARCH_BACKGROUND_COLOR
			button.BackgroundTransparency = active and 0.1 or SEARCH_BACKGROUND_FADE
		end
	end
end
for index, filter in INVENTORY_FILTERS do
	local button = tabsStrip:FindFirstChild(filter.Id)
	if not button then
		button = Instance.new("TextButton")
		button.Name = filter.Id
		button.LayoutOrder = index
		button.AutomaticSize = Enum.AutomaticSize.X
		button.Size = UDim2.new(0, 0, 1, 0)
		require(game:GetService("ReplicatedStorage").Shared.UiKit).StyleText(button, "Body") -- v20: шрифт темы
		button.TextSize = FONT_SIZE - 2
		button.Text = filter.Label
		button.BorderSizePixel = 0
		button.Parent = tabsStrip
	end
	filterButtons[filter.Id] = button
	button.Activated:Connect(function()
		currentFilter = filter.Id
		paintFilterTabs()
		if renderGrid then renderGrid() end
	end)
end
paintFilterTabs()

local scrollingFrame = inventoryFrame:WaitForChild("ScrollingFrame")
local gridFrame = scrollingFrame:WaitForChild("UIGridFrame")

-- Слой перетаскивания — в ОТДЕЛЬНОМ, всегда включённом ScreenGui
-- (InventoryDragOverlay): панель инвентаря выключается, когда закрыта, и
-- «призрак» ячейки вместе с ней стал бы невидимым.
local overlayGui = UiRegistry.Get("InventoryDragOverlay")
overlayGui.ResetOnSpawn = false
local dragLayer = overlayGui:WaitForChild("DragLayer")
dragLayer.Visible = false

--------------------------------------------------------------------------------
-- РАЗМЕТКА: панель всегда ровно над фактическим хотбаром
--------------------------------------------------------------------------------
local function inventoryRows()
	return isSmallScreen() and INVENTORY_ROWS_MINI or INVENTORY_ROWS_FULL
end

local function updateLayout()
	local hotbarSize = bar.AbsoluteSize
	local hotbarPosition = bar.AbsolutePosition
	local inset = GuiService:GetGuiInset()

	local slotCount = Config.Inventory.HotbarSlots
	-- Ширина по формуле Satchel, но не уже реального хотбара: панель
	-- обязана совпадать с ним по краям, иначе это выглядит как два
	-- случайных элемента, а не один блок.
	local width = math.max(ICON_BUFFER + slotCount * (ICON_SIZE + ICON_BUFFER), hotbarSize.X)
	local rows = inventoryRows()
	local height = rows * (ICON_SIZE + ICON_BUFFER) + ICON_BUFFER + INVENTORY_HEADER_SIZE + INVENTORY_TABS_SIZE

	inventoryFrame.Size = UDim2.fromOffset(width, height)
	-- AbsolutePosition отсчитывается БЕЗ GUI-инсета, а ScreenGui у нас с
	-- IgnoreGuiInset = true — компенсируем, иначе панель уезжает вверх
	-- ровно на высоту топбара.
	inventoryFrame.Position = UDim2.fromOffset(
		math.round(hotbarPosition.X + hotbarSize.X / 2 - width / 2 + inset.X),
		math.round(hotbarPosition.Y + inset.Y - height - ICON_BUFFER)
	)
	scrollingFrame.Size = UDim2.new(1, 0, 0, height - INVENTORY_HEADER_SIZE - INVENTORY_TABS_SIZE)
end

local function updateCanvasSize()
	local columns = math.max(1, math.floor(scrollingFrame.AbsoluteSize.X / (ICON_SIZE + ICON_BUFFER)))
	local cells = 0
	for _, child in gridFrame:GetChildren() do
		if child:IsA("GuiObject") then cells += 1 end
	end
	local rows = math.ceil(cells / columns)
	scrollingFrame.CanvasSize = UDim2.fromOffset(0, rows * (ICON_SIZE + ICON_BUFFER) + ICON_BUFFER)
end

bar:GetPropertyChangedSignal("AbsolutePosition"):Connect(updateLayout)
bar:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateLayout)
scrollingFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateCanvasSize)
updateLayout()

--------------------------------------------------------------------------------
-- ЯЧЕЙКА
--------------------------------------------------------------------------------
local cellTemplate = gui:WaitForChild("Templates"):WaitForChild("Slot")
local function makeCell()
	local cell = cellTemplate:Clone()
	cell.Visible = true
	return cell
end

--------------------------------------------------------------------------------
-- ХОТБАР (переиспользуем существующий, НЕ переделываем)
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- СЛОТЫ ХОТБАРА (штатный StarterGui/HotbarUi) + НАВЕДЕНИЕ
--
-- Перенос больше НЕ полагается на вычисление цели в момент отпускания.
-- Известная ловушка Roblox: когда курсор стоит над другим GuiObject
-- (а слот хотбара — это ровно другой GuiObject), отпускание кнопки над
-- ним детектится ненадёжно, и бросок уходит в никуда.
--
-- Поэтому цель определяется ЗАРАНЕЕ, событиями самого движка:
-- MouseEnter/MouseLeave на каждом слоте держат hoveredTarget. Что бы ни
-- случилось с координатами, инсетом и хит-тестом — движок сам сказал нам,
-- над чем курсор. GetGuiObjectsAtPosition остаётся запасным путём (он
-- нужен для тача, где MouseEnter не срабатывает).
--------------------------------------------------------------------------------
local hotbarSlots = {}

-- Над чем сейчас курсор: { Kind = "Hotbar"|"Grid", Slot = n } | { Kind = "Grid", Uid = "..." }
local hoveredTarget = nil

local function trackHover(guiObject, target)
	guiObject.MouseEnter:Connect(function() hoveredTarget = target end)
	guiObject.MouseLeave:Connect(function()
		-- Сбрасываем ТОЛЬКО если ушли именно с нас: курсор мог уже войти в
		-- соседний слот, и его MouseEnter отработал раньше нашего
		-- MouseLeave — затирать свежую цель нельзя.
		if hoveredTarget == target then hoveredTarget = nil end
	end)
end

local function bindHotbarSlot(slot, slotIndex)
	slot:SetAttribute("DropKind", "Hotbar")
	slot:SetAttribute("DropSlot", slotIndex)
	if slot:GetAttribute("DragBound") then return end
	slot:SetAttribute("DragBound", true)

	trackHover(slot, { Kind = "Hotbar", Slot = slotIndex })

	bindDragSource(slot, function()
		return {
			StackIndex = hotbarAt(slotIndex),
			Origin = "Hotbar",
			OriginSlot = slotIndex,
		}
	end, function()
		handleSlotClick("Hotbar", slotIndex, hotbarAt(slotIndex))
	end)
end

-- Ищем слоты заново каждый раз, когда состав бара меняется: хотбар может
-- собирать/пересобирать другой скрипт уже ПОСЛЕ нашего запуска, и
-- одноразовый поиск при старте оставил бы список пустым навсегда.
local function refreshHotbarSlots()
	local found = {}
	for _, child in bar:GetChildren() do
		local index = tonumber(child.Name:match("^Slot(%d+)$"))
		if index and child:IsA("GuiObject") then found[index] = child end
	end
	-- Запасной путь: имена другие — берём кликабельные элементы по порядку
	-- раскладки, пропустив слот кирки.
	if next(found) == nil then
		local candidates = {}
		for _, child in bar:GetChildren() do
			if child:IsA("GuiButton") and not child.Name:lower():find("pickaxe") then
				table.insert(candidates, child)
			end
		end
		table.sort(candidates, function(a, b)
			if a.LayoutOrder ~= b.LayoutOrder then return a.LayoutOrder < b.LayoutOrder end
			return a.Name < b.Name
		end)
		for i, child in candidates do
			if i <= Config.Inventory.HotbarSlots then found[i] = child end
		end
	end
	hotbarSlots = found
	for slotIndex, slot in hotbarSlots do
		bindHotbarSlot(slot, slotIndex)
	end
end

-- Слот кирки остаётся чужим: им владеет CustomCartUI.
local pickaxeSlot = bar:FindFirstChild("PickaxeSlot")
local shieldLabel = pickaxeSlot and pickaxeSlot:FindFirstChild("ShieldLabel")

renderHotbar = function()
	for slotIndex, slot in hotbarSlots do
		if slot then
			local uid = hotbarAt(slotIndex)
			local stack = stackByUid(uid)
			applyPreview(slot:FindFirstChild("Preview"), stack)
			local count = slot:FindFirstChild("CountLabel")
			if count then count.Text = stack and ("x" .. stack.Count) or "" end
			local nameLabel = slot:FindFirstChild("ToolName")
			if nameLabel then nameLabel.Text = stack and stackDisplayName(stack) or "" end
			local stroke = slot:FindFirstChildWhichIsA("UIStroke")
			if stroke then
				-- Слот, который сейчас В РУКАХ, подсвечивается тем же
				-- синим, что и экипированный слот в Satchel.
				local gearKey = gearKeyOf(uid)
				local equipped = (heldStackIndex ~= nil and uid == heldStackIndex)
					or (gearKey ~= nil and (player:GetAttribute("HeldGear") or "") == gearKey)
				stroke.Color = equipped and SLOT_EQUIP_COLOR or (gearKey and gearColor(gearKey)) or Color3.fromRGB(70, 75, 90)
				stroke.Thickness = equipped and 2 or 1
			end
		end
	end
	if pickaxeSlot then
		local key = pickaxeSlot:FindFirstChild("KeyBadge")
		local isCart = state.Cart and state.Cart.Carrying == true
		if key then key.Text = isCart and "S" or "F" end
		if shieldLabel then shieldLabel.Visible = isCart end
		local count = pickaxeSlot:FindFirstChild("CountLabel")
		if count then count.Text = isCart and "SHIELD" or ("T" .. tostring(state.PickaxeTier)) end
	end
end

-- v9: ОТКАТ ДИНАМИТА на слоте хотбара — тёмная шторка сверху вниз и
-- секунды. Время готовности шлёт сервер атрибутом DynamiteReadyAt_<key>.
local function cooldownOverlay(slot)
	local overlay = slot:FindFirstChild("CooldownShade")
	if overlay then return overlay end
	overlay = Instance.new("Frame")
	overlay.Name = "CooldownShade"
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.35
	overlay.BorderSizePixel = 0
	overlay.AnchorPoint = Vector2.new(0, 1)
	overlay.Position = UDim2.fromScale(0, 1)
	overlay.Size = UDim2.fromScale(1, 0)
	overlay.ZIndex = (slot.ZIndex or 1) + 5
	overlay.Visible = false
	overlay.Parent = slot
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = overlay
	local seconds = Instance.new("TextLabel")
	seconds.Name = "Seconds"
	seconds.BackgroundTransparency = 1
	seconds.AnchorPoint = Vector2.new(0.5, 0.5)
	seconds.Position = UDim2.fromScale(0.5, 0.5)
	seconds.Size = UDim2.fromScale(0.8, 0.5)
	require(game:GetService("ReplicatedStorage").Shared.UiKit).StyleText(seconds, "Heading") -- v20: шрифт темы
	seconds.TextScaled = true
	seconds.TextColor3 = Color3.new(1, 1, 1)
	seconds.ZIndex = overlay.ZIndex + 1
	seconds.Visible = false
	seconds.Parent = slot
	return overlay
end

local function updateCooldowns()
	local now = workspace:GetServerTimeNow()
	for slotIndex, slot in hotbarSlots do
		if slot then
			local key = gearKeyOf(hotbarAt(slotIndex))
			local info = key and Config.Dynamite and Config.Dynamite.Types[key]
			local left = 0
			if info then
				left = math.max(0, (tonumber(player:GetAttribute("DynamiteReadyAt_" .. key)) or 0) - now)
			end
			local overlay = slot:FindFirstChild("CooldownShade")
			if left > 0 or overlay then
				overlay = cooldownOverlay(slot)
				local secondsLabel = slot:FindFirstChild("Seconds")
				overlay.Visible = left > 0
				if left > 0 then
					overlay.Size = UDim2.fromScale(1, math.clamp(left / math.max(0.1, info.Cooldown or 4), 0, 1))
				end
				if secondsLabel then
					secondsLabel.Visible = left > 0
					secondsLabel.Text = tostring(math.ceil(left))
				end
			end
		end
	end
end
task.spawn(function()
	while true do
		task.wait(0.1)
		pcall(updateCooldowns)
	end
end)

toggleHotbarSlot = function(slotIndex)
	local stackIndex = hotbarAt(slotIndex)
	if not stackIndex then return end
	if gearKeyOf(stackIndex) then
		holdStack(stackIndex) -- сервер сам переключает: взять / убрать
		renderHotbar()
		return
	end
	if heldStackIndex == stackIndex then
		clearHeld() -- повторное нажатие — убрать из рук
	else
		holdStack(stackIndex)
	end
	renderHotbar()
	renderGrid()
end

--------------------------------------------------------------------------------
-- ПЕРЕТАСКИВАНИЕ
--------------------------------------------------------------------------------
local drag = nil

local function pointerPosition()
	local location = UserInputService:GetMouseLocation()
	local inset = GuiService:GetGuiInset()
	-- GetMouseLocation отдаёт координаты БЕЗ инсета, а ScreenGui у нас с
	-- IgnoreGuiInset — приводим к одной системе, иначе призрак висит
	-- выше пальца ровно на высоту топбара.
	return Vector2.new(location.X + inset.X, location.Y + inset.Y)
end

local function endDrag()
	if drag and drag.Ghost then drag.Ghost:Destroy() end
	drag = nil
	dragLayer.Visible = false
end

-- ОПРЕДЕЛЕНИЕ ЦЕЛИ БРОСКА — ЧЕРЕЗ САМ ROBLOX, А НЕ СВОЮ МАТЕМАТИКУ.
--
-- ЗДЕСЬ БЫЛА ПРИЧИНА "не перемещается в хотбар и обратно". Раньше цель
-- искалась вручную: точка курсора сравнивалась с AbsolutePosition/
-- AbsoluteSize каждого слота, с ручной поправкой на GUI-инсет (высоту
-- верхней полосы Roblox). Инсет входит в разные системы координат
-- по-разному — у ScreenGui с IgnoreGuiInset = true (наша панель) и
-- false (хотбар) начало отсчёта отличается ровно на его высоту. Любая
-- ошибка в знаке этой поправки означает, что попадание в слот не
-- засчитывается НИКОГДА: бросок молча уходил в никуда, предмет оставался
-- на месте, а слот хотбара так и стоял пустым.
--
-- Теперь этой математики нет вообще. PlayerGui:GetGuiObjectsAtPosition
-- сам проверяет попадание средствами движка, в его собственной системе
-- координат, с учётом инсета, ZIndex, обрезки и невидимых элементов.
-- Что бы ни возвращал GetMouseLocation на конкретной платформе, эти два
-- API согласованы между собой по построению.
--
-- Слоты и ячейки помечены атрибутами (DropKind/DropSlot/BackpackIndex),
-- поэтому в списке под курсором мы просто ищем первый помеченный объект.
local function resolveDropTarget()
	-- 1) ГЛАВНЫЙ ПУТЬ — то, над чем курсор СЕЙЧАС, по данным самого движка
	--    (MouseEnter/MouseLeave слотов). Никакой математики с координатами
	--    и GUI-инсетом, а значит и нечему разъезжаться.
	if hoveredTarget then
		if hoveredTarget.Kind == "Hotbar" then
			return "Hotbar", hoveredTarget.Slot
		elseif hoveredTarget.Kind == "Grid" then
			return "Grid", hoveredTarget.Uid
		end
	end

	-- 2) ЗАПАСНОЙ ПУТЬ — хит-тест средствами движка. Нужен на тач-экранах,
	--    где MouseEnter/MouseLeave не срабатывают вовсе.
	local mouse = UserInputService:GetMouseLocation()
	local ok, hits = pcall(function()
		return playerGui:GetGuiObjectsAtPosition(mouse.X, mouse.Y)
	 end)
	if ok and hits then
		local insidePanel = false
		for _, hit in hits do
			-- Поднимаемся по родителям: курсор стоит над Preview/CountLabel,
			-- а метка висит на самом слоте.
			local node = hit
			while node and node ~= playerGui do
				local dropKind = node:GetAttribute("DropKind")
				if dropKind == "Hotbar" then
					return "Hotbar", node:GetAttribute("DropSlot")
				elseif dropKind == "Cell" then
					return "Grid", node:GetAttribute("BackpackIndex")
				end
				if node == inventoryFrame then insidePanel = true end
				node = node.Parent
			end
		end
		if insidePanel then return "Grid", nil end
	end

	-- 3) Курсор в панели, но мимо ячейки — это всё равно "в инвентарь".
	if isOpen and inventoryFrame.Visible then
		return nil, nil
	end
	return nil, nil
end

local function completeDrag()
	if not drag then return end
	local kind, target = resolveDropTarget()

	if kind == "Hotbar" then
		if drag.Origin == "Hotbar" then
			-- Слот ↔ слот одним действием, а не двумя SetHotbar подряд:
			-- между двумя запросами прилетает Sync, и второй уже опирался
			-- бы на устаревшую картинку.
			if drag.OriginSlot ~= target then
				remote:FireServer("SwapHotbar", drag.OriginSlot, target)
			end
		elseif drag.StackIndex then
			remote:FireServer("SetHotbar", target, drag.StackIndex)
		end
	elseif kind == "Grid" then
		if drag.Origin == "Hotbar" then
			remote:FireServer("SetHotbar", drag.OriginSlot, nil) -- убрали из хотбара
		elseif target and drag.StackIndex and target ~= drag.StackIndex then
			remote:FireServer("ReorderBackpack", drag.StackIndex, target)
		end
	elseif drag.Origin == "Hotbar" then
		-- Бросили мимо всего: как в Satchel, предмет просто уходит из
		-- хотбара обратно в рюкзак — он никуда не пропадает.
		remote:FireServer("SetHotbar", drag.OriginSlot, nil)
	end

	endDrag()
end

--------------------------------------------------------------------------------
-- ПЕРЕНОС КЛИКАМИ ("взял — положил")
--
-- Перетаскивание удобно, но оно зависит от того, что движок правильно
-- отдаст отпускание кнопки над нужным слотом, — а именно это в Roblox и
-- подводит. Поэтому основной, всегда работающий способ теперь другой и
-- предельно простой: КЛИК берёт предмет "в руку курсора", ВТОРОЙ КЛИК по
-- слоту кладёт его туда. Ровно так устроены классические инвентари.
--
-- Здесь нет ни координат, ни хит-теста, ни GUI-инсета: оба клика приходят
-- как обычные события кнопок (.Activated) от тех самых слотов. Ломаться
-- нечему.
--------------------------------------------------------------------------------
local carried = nil -- { Uid, Origin = "Grid"|"Hotbar", OriginSlot }
local carriedGhost = nil

setCarried = function(value)
	carried = value
	if carriedGhost then
		carriedGhost:Destroy()
		carriedGhost = nil
	end
	if not value then
		dragLayer.Visible = false
		return
	end

	-- Призрак под курсором — единственная обратная связь "предмет у меня в
	-- руке". Без неё игрок не понимает, что первый клик что-то сделал.
	local ghost = makeCell()
	ghost.Name = "CarryGhost"
	ghost.AnchorPoint = Vector2.new(0.5, 0.5)
	ghost.BackgroundTransparency = 0.1
	ghost.ZIndex = 51
	local stack = stackByUid(value.Uid)
	applyPreview(ghost:FindFirstChild("Preview"), stack)
	local ghostName = ghost:FindFirstChild("ToolName")
	if ghostName then ghostName.Text = stack and stackDisplayName(stack) or "" end
	local ghostCount = ghost:FindFirstChild("CountLabel")
	if ghostCount then ghostCount.Text = stack and ("x" .. stack.Count) or "" end
	for _, d in ghost:GetDescendants() do
		if d:IsA("GuiObject") then d.ZIndex = 52 end
	end
	ghost.Parent = dragLayer
	carriedGhost = ghost
	dragLayer.Visible = true
end

-- Один клик по любому слоту. kind = "Hotbar"|"Grid".
handleSlotClick = function(kind, slotIndex, uid)
	-- НИЧЕГО НЕ НЕСЁМ: клик берёт предмет. Пустой слот брать нечего —
	-- тогда это обычный клик, и он просто берёт/убирает руду в руки.
	if not carried then
		if not uid then return end
		if kind == "Hotbar" then
			-- ЗДЕСЬ БЫЛА ДЫРА: клик по слоту хотбара ВСЕГДА означал "взять в
			-- руки", поэтому забрать предмет ИЗ хотбара кликами было нельзя
			-- вообще — только перетаскиванием. Половина переноса (хотбар →
			-- инвентарь) просто отсутствовала.
			--
			-- Решает контекст: инвентарь ОТКРЫТ — значит игрок раскладывает
			-- вещи, и клик берёт предмет для переноса. Инвентарь закрыт —
			-- значит он играет, и клик берёт руду в руки, как и раньше.
			if isOpen then
				setCarried({ Uid = uid, Origin = "Hotbar", OriginSlot = slotIndex })
			else
				toggleHotbarSlot(slotIndex)
			end
			return
		end
		setCarried({ Uid = uid, Origin = "Grid" })
		return
	end

	-- УЖЕ НЕСЁМ: этот клик — место назначения.
	if kind == "Hotbar" then
		if carried.Origin == "Hotbar" then
			if carried.OriginSlot ~= slotIndex then
				remote:FireServer("SwapHotbar", carried.OriginSlot, slotIndex)
			end
		else
			remote:FireServer("SetHotbar", slotIndex, carried.Uid)
		end
	else -- Grid
		if carried.Origin == "Hotbar" then
			remote:FireServer("SetHotbar", carried.OriginSlot, nil)
		elseif uid and uid ~= carried.Uid then
			remote:FireServer("ReorderBackpack", carried.Uid, uid)
		end
	end
	setCarried(nil)
end

local function beginDrag(sourceButton, info)
	if drag then endDrag() end

	-- Призрак строим заново, а не клонируем исходную кнопку: у слота
	-- хотбара своя вёрстка (значок клавиши, оверлей перезарядки), и в
	-- полёте всё это только мешало бы.
	local ghost = makeCell()
	ghost.Name = "DragGhost"
	ghost.AnchorPoint = Vector2.new(0.5, 0.5)
	ghost.BackgroundTransparency = 0.1
	ghost.ZIndex = 51
	local ghostStroke = ghost:FindFirstChild("Highlight")
	if ghostStroke then
		ghostStroke.Color = SLOT_BORDER_COLOR
		ghostStroke.Thickness = 2
	end

	local stack = stackByUid(info.StackIndex)
	applyPreview(ghost:FindFirstChild("Preview"), stack)
	local ghostName = ghost:FindFirstChild("ToolName")
	if ghostName then ghostName.Text = stack and stackDisplayName(stack) or "" end
	local ghostCount = ghost:FindFirstChild("CountLabel")
	if ghostCount then ghostCount.Text = stack and ("x" .. stack.Count) or "" end

	for _, descendant in ghost:GetDescendants() do
		if descendant:IsA("GuiObject") then descendant.ZIndex = 52 end
	end
	ghost.Parent = dragLayer
	dragLayer.Visible = true

	drag = {
		StackIndex = info.StackIndex,
		Origin = info.Origin,
		OriginSlot = info.OriginSlot,
		Ghost = ghost,
	}
	local position = pointerPosition()
	ghost.Position = UDim2.fromOffset(position.X, position.Y)
end

-- Общий обработчик "нажал на ячейку": сам решает, клик это или перетаскивание.
bindDragSource = function(button, buildInfo, onClick)
	button.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		local info = buildInfo()
		local startPosition = pointerPosition()
		local started = false
		local finished = false
		local moveConnection, endConnection

		local function finish(commit)
			if finished then return end
			finished = true
			if moveConnection then moveConnection:Disconnect() end
			if endConnection then endConnection:Disconnect() end
			if started then
				if commit then
					completeDrag()
				else
					endDrag()
				end
			elseif commit and onClick then
				onClick()
			end
		end

		moveConnection = UserInputService.InputChanged:Connect(function(moved)
			if moved.UserInputType ~= Enum.UserInputType.MouseMovement
				and moved.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			local position = pointerPosition()
			if not started then
				-- Порог в пикселях: без него любое дрожание мыши во время
				-- клика превращалось бы в перетаскивание, и обычный клик
				-- стал бы попросту невозможен на тачскрине.
				if (position - startPosition).Magnitude < DRAG_THRESHOLD then return end
				if not info.StackIndex then return end -- пустой слот тащить нечем
				started = true
				beginDrag(button, info)
			end
			if drag and drag.Ghost then
				drag.Ghost.Position = UDim2.fromOffset(position.X, position.Y)
			end
		end)

		endConnection = UserInputService.InputEnded:Connect(function(ended)
			if ended.UserInputType == input.UserInputType then
				finish(true)
			end
		end)
	end)
end

--------------------------------------------------------------------------------
-- ОТРИСОВКА СЕТКИ
--------------------------------------------------------------------------------
local function visibleBackpackIndices()
	local indices = {}
	local query = searchText:lower()

	-- Что уже лежит в хотбаре — в сетке НЕ показываем. Хотбар это та же
	-- сумка, просто быстрый доступ: положил стопку в слот — она сменила
	-- место, а не размножилась. Раньше она была видна в обоих местах
	-- одновременно, и выглядело это как дубликат предмета.
	local inHotbar = {}
	for slotIndex = 1, Config.Inventory.HotbarSlots do
		local uid = hotbarAt(slotIndex)
		if uid then inHotbar[uid] = true end
	end

	for index, stack in state.Backpack do
		if not inHotbar[stack.Uid]
			and (query == "" or stackDisplayName(stack):lower():find(query, 1, true)) then
			table.insert(indices, index)
		end
	end
	-- Порядок в сетке — это порядок В РЮКЗАКЕ, который игрок сам задаёт
	-- перетаскиванием. Пересортировывать здесь по редкости было бы прямым
	-- противоречием: игрок перетащил стопку, а она прыгнула обратно.
	table.sort(indices, function(a, b) return a < b end)
	return indices
end

renderGrid = function()
	-- Ячейки пересоздаются целиком, поэтому наведение на ячейку сетки
	-- становится недействительным: hoveredTarget указывал бы на уже
	-- уничтоженную ячейку, и бросок ушёл бы в несуществующий слот.
	-- Наведение на ХОТБАР не трогаем — его слоты переживают перерисовку.
	if hoveredTarget and hoveredTarget.Kind == "Grid" then
		hoveredTarget = nil
	end
	for _, child in gridFrame:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end

	local order = 0
	local query = searchText:lower()

	-- КИРКИ живут в той же сетке, а не в отдельной вкладке: в Satchel
	-- сетка — это просто "всё, что у тебя есть", и вкладка ради семи
	-- карточек добавила бы лишний клик на ровном месте. Карточка на
	-- каждый ОТКРЫТЫЙ тир (1..PickaxeMaxTier); вернуться на пройденный
	-- тир можно — это выбор стиля, не эксплойт (серверная проверка тира
	-- всё равно в InventoryService:EquipPickaxe).
	local showTools = currentFilter == "All" or currentFilter == "Tools"
	for tier = state.PickaxeMaxTier or 1, 1, -1 do
		local tierConfig = Config.PickaxeTiers[tier]
		local title = "pickaxe t" .. tier
		if showTools and tierConfig and (query == "" or title:find(query, 1, true)) then
			order += 1
			local cell = makeCell()
			cell.Name = "Pickaxe_" .. tier
			cell.LayoutOrder = order
			cell.Parent = gridFrame

			local equipped = tier == state.PickaxeTier
			local highlight = cell:FindFirstChild("Highlight")
			if highlight then
				highlight.Color = SLOT_EQUIP_COLOR
				highlight.Thickness = equipped and SLOT_EQUIP_THICKNESS or 0
			end
			local nameLabel = cell:FindFirstChild("ToolName")
			if nameLabel then nameLabel.Text = "T" .. tier end
			local countText = cell:FindFirstChild("CountLabel")
			if countText then countText.Text = equipped and "ON" or "" end
			setImagePreview(cell:FindFirstChild("Preview"), Config.Icons and Config.Icons.Pickaxe or nil)

			local capturedTier = tier
			cell.Activated:Connect(function()
				remote:FireServer("EquipPickaxe", capturedTier, nil)
			end)
		end
	end

	-- v9: СНАРЯЖЕНИЕ (не тратит слоты). То, что уже в хотбаре, не дублируем.
	local gearInHotbar = {}
	for slotIndex = 1, Config.Inventory.HotbarSlots do
		local uid = hotbarAt(slotIndex)
		if uid then gearInHotbar[uid] = true end
	end
	for _, gearStack in state.Gear or {} do
		if not gearInHotbar[gearStack.Uid]
			and (currentFilter == "All" or currentFilter == gearCategory(gearStack.Gear))
			and (query == "" or stackDisplayName(gearStack):lower():find(query, 1, true)) then
			order += 1
			local cell = makeCell()
			cell.Name = "Gear_" .. gearStack.Gear
			cell.LayoutOrder = order
			cell.Parent = gridFrame
			local highlight = cell:FindFirstChild("Highlight")
			if highlight then
				local held = (player:GetAttribute("HeldGear") or "") == gearStack.Gear
				highlight.Color = held and SLOT_EQUIP_COLOR or gearColor(gearStack.Gear)
				highlight.Thickness = held and SLOT_EQUIP_THICKNESS or 1
			end
			local nameLabel = cell:FindFirstChild("ToolName")
			if nameLabel then nameLabel.Text = stackDisplayName(gearStack) end
			local countText = cell:FindFirstChild("CountLabel")
			if countText then countText.Text = "x" .. tostring(gearStack.Count) end
			applyPreview(cell:FindFirstChild("Preview"), gearStack)
			local capturedUid = gearStack.Uid
			trackHover(cell, { Kind = "Grid", Uid = capturedUid })
			bindDragSource(cell, function()
				return { StackIndex = capturedUid, Origin = "Grid" }
			end, function()
				handleSlotClick("Grid", nil, capturedUid)
			end)
		end
	end

	-- РУДА
	for _, stackIndex in (currentFilter == "All" or currentFilter == "Ores") and visibleBackpackIndices() or {} do
		local stack = state.Backpack[stackIndex]
		local uid = stack.Uid
		local info = oreInfoFor(stack)
		order += 1
		local cell = makeCell()
		cell.Name = "Item_" .. tostring(stackIndex)
		cell.LayoutOrder = order
		cell:SetAttribute("BackpackIndex", uid)
		cell:SetAttribute("DropKind", "Cell") -- метка для resolveDropTarget
		for _, descendant in cell:GetDescendants() do
			if descendant:IsA("GuiObject") then
				descendant:SetAttribute("DropKind", "Cell")
				descendant:SetAttribute("BackpackIndex", stackIndex)
			end
		end
		cell.Parent = gridFrame

		local highlight = cell:FindFirstChild("Highlight")
		if highlight then
			if heldStackIndex == uid then
				highlight.Color = SLOT_EQUIP_COLOR
				highlight.Thickness = SLOT_EQUIP_THICKNESS
			else
				-- Тонкая рамка цветом редкости: то, что в Satchel несёт сам
				-- предмет, у нас несёт его редкость.
				-- v3 (Ж2): редкость по слоту руды в текущей пещере игрока.
				highlight.Color = rarityColor(info and ((Config.OreRarityFor and Config.OreRarityFor(stack.Ore, player:GetAttribute("MineTier"))) or info.Rarity))
				highlight.Thickness = 1
			end
		end
		local nameLabel = cell:FindFirstChild("ToolName")
		if nameLabel then nameLabel.Text = stackDisplayName(stack) end
		local countText = cell:FindFirstChild("CountLabel")
		if countText then countText.Text = "x" .. tostring(stack.Count) end
		applyPreview(cell:FindFirstChild("Preview"), stack)

		local capturedIndex = uid
		trackHover(cell, { Kind = "Grid", Uid = capturedIndex })
		bindDragSource(cell, function()
			return { StackIndex = capturedIndex, Origin = "Grid" }
		end, function()
			-- Клик по ячейке сетки — это ПЕРЕНОС ("взял / положил"). Взять
			-- руду В РУКИ можно слотом хотбара или клавишей 1..6; сетка
			-- нужна прежде всего для раскладки, и смешивать два разных
			-- действия на одном клике означало бы, что игрок никогда не
			-- уверен, что произойдёт.
			handleSlotClick("Grid", nil, capturedIndex)
		end)
	end

	updateCanvasSize()

	local slots = state.Slots == -1 and "∞" or tostring(state.Slots)
	countLabel.Text = ("%d/%s"):format(backpackCount(), slots)
end

refreshHotbarSlots()
bar.ChildAdded:Connect(function()
	task.defer(function()
		refreshHotbarSlots()
		renderHotbar()
	end)
end)
bar.ChildRemoved:Connect(function() task.defer(refreshHotbarSlots) end)

--------------------------------------------------------------------------------
-- КИРКА
--------------------------------------------------------------------------------
local function getPickaxeTool()
	local character = player.Character
	if not character then return nil end
	local backpack = player:FindFirstChild("Backpack")
	local function findIn(container)
		if not container then return nil end
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and (child.Name == "Pickaxe" or child.Name:match("^Pickaxe_Tier%d+$")) then
				return child
			end
		end
		return nil
	end
	return findIn(backpack) or findIn(character)
end

togglePickaxe = function()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local tool = getPickaxeTool()
	if not (humanoid and tool) then return end
	if tool.Parent == character then
		humanoid:UnequipTools()
	else
		humanoid:EquipTool(tool)
	end
end

if pickaxeSlot then
	pickaxeSlot.Activated:Connect(function()
		if player:GetAttribute("CarryingCart") == true then
			-- CustomCartUI's ClickCatcher handles shield activation here.
			return
		end
		clearHeld()
		renderHotbar()
		renderGrid()
		togglePickaxe()
	end)
end

--------------------------------------------------------------------------------
-- ОТКРЫТИЕ / ЗАКРЫТИЕ
--------------------------------------------------------------------------------
local function setOpen(open)
	if isOpen == open then return end
	isOpen = open
	if open then
		updateLayout()
		gui.Enabled = true
		remote:FireServer("Sync")
		inventoryFrame.BackgroundTransparency = 1
		TweenService:Create(inventoryFrame, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = BACKGROUND_FADE,
		}):Play()
	else
		endDrag()
		local tween = TweenService:Create(
			inventoryFrame,
			TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ BackgroundTransparency = 1 }
		)
		tween.Completed:Connect(function()
			if not isOpen then gui.Enabled = false end
		end)
		tween:Play()
	end
end

--------------------------------------------------------------------------------
-- ПРИЗРАК ПОД КУРСОРОМ + ОТМЕНА ПЕРЕНОСА
--------------------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
	local ghost = carriedGhost or (drag and drag.Ghost)
	if not ghost then return end
	local position = pointerPosition()
	ghost.Position = UDim2.fromOffset(position.X, position.Y)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	-- Правая кнопка и Escape кладут поднятый предмет обратно. Без явной
	-- отмены игрок, случайно взявший стопку, оказался бы заперт: любой
	-- следующий клик её куда-нибудь переложил бы.
	if input.UserInputType == Enum.UserInputType.MouseButton2
		or input.KeyCode == Enum.KeyCode.Escape then
		if carried then setCarried(nil) end
	end
end)

--------------------------------------------------------------------------------
-- КЛАВИАТУРА
--------------------------------------------------------------------------------
local DIGIT_KEYS = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
}

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or UserInputService:GetFocusedTextBox() then return end

	-- Backquote — ОДНА И ТА ЖЕ физическая клавиша и для `~`, и для русской
	-- `ё`, поэтому раскладка роли не играет и отдельной проверки не
	-- требует. DPadUp — тот же переключатель на геймпаде, как в Satchel.
	if input.KeyCode == Enum.KeyCode.Backquote or input.KeyCode == Enum.KeyCode.DPadUp then
		setOpen(not isOpen)
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape and isOpen then
		setOpen(false)
		return
	end

	if input.KeyCode == Config.Inventory.PickaxeKey then
		if player:GetAttribute("CarryingCart") == true then
			-- CustomCartUI owns the shield hotkey and its cooldown/paid extension.
			return
		end
		clearHeld() -- в руках может быть только что-то одно: руда ИЛИ кирка
		renderHotbar()
		renderGrid()
		togglePickaxe()
		return
	end

	-- ВЫБРОСИТЬ РУДУ (Backspace). Кусок улетает по дуге вперёд от игрока —
	-- сама дуга и приземление считаются на сервере тем же кодом, что и
	-- выброс из шахты, чтобы выброшенная руда вела себя ровно так же, как
	-- любая другая лежащая на земле (крутится, левитирует, подбирается).
	if input.KeyCode == Enum.KeyCode.Backspace then
		if heldStackIndex then
			remote:FireServer("DropHeld", heldStackIndex)
		end
		return
	end

	local slotIndex = DIGIT_KEYS[input.KeyCode]
	if slotIndex then
		toggleHotbarSlot(slotIndex)
	end
end)

--------------------------------------------------------------------------------
-- ПОИСК
--------------------------------------------------------------------------------
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	searchText = searchBox.Text or ""
	searchClear.Visible = searchText ~= ""
	renderGrid()
end)
searchClear.Activated:Connect(function()
	searchBox.Text = ""
end)

--------------------------------------------------------------------------------
-- ДАРЕНИЕ: зажать ЛКМ на игроке, держа руду в руках
--------------------------------------------------------------------------------
local giftHoldStart = nil
local giftTarget = nil

local function playerUnderMouse()
	local mouse = player:GetMouse()
	local target = mouse and mouse.Target
	local model = target and target:FindFirstAncestorOfClass("Model")
	local targetPlayer = model and Players:GetPlayerFromCharacter(model)
	if targetPlayer and targetPlayer ~= player then return targetPlayer end
	return nil
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if not heldStackIndex then return end
	local target = playerUnderMouse()
	if target then
		giftTarget = target
		giftHoldStart = os.clock()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	giftHoldStart = nil
	giftTarget = nil
end)

--------------------------------------------------------------------------------
-- ЦИКЛ: сдача руды в тележку и дарение
--------------------------------------------------------------------------------
local lastDepositAttempt = 0

RunService.Heartbeat:Connect(function()
	-- СДАЧА РУДЫ В ТЕЛЕЖКУ.
	--
	-- ЗДЕСЬ БЫЛ САМЫЙ ДОРОГОЙ БАГ ФАЙЛА. Прошлый код каждый кадр брал
	-- ПЕРВУЮ попавшуюся стопку рюкзака (next(state.Backpack)) и слал
	-- "DepositHeldOre" — безусловно: независимо от того, держит игрок
	-- что-нибудь в руках или нет, и нажимал ли он вообще хоть что-то. То
	-- есть рюкзак сам себя разгружал в тележку по четыре раза в секунду,
	-- и остановить это было нельзя никак. Сдаём ТОЛЬКО ТО, ЧТО РЕАЛЬНО В
	-- РУКАХ; приехали мы к тележке или нет — решает сервер (проверка
	-- расстояния в InventoryService:DepositHeldOre).
	-- ТЕПЕРЬ СЕРВЕР САМ переливает В ТЕЛЕЖКУ ВСЮ руду, как только игрок
	-- рядом (InventoryService:_depositOneToCart), а не только ту, что в
	-- руках. Слать отсюда запрос больше не нужно — он лишь дублировал бы.
	local _ = lastDepositAttempt

	if not (giftHoldStart and giftTarget and heldStackIndex) then return end
	if os.clock() - giftHoldStart >= Config.Inventory.GiftHoldSeconds then
		remote:FireServer("Gift", giftTarget, heldStackIndex)
		giftHoldStart = nil
		giftTarget = nil
		clearHeld()
	end
end)

--------------------------------------------------------------------------------
-- СИНХРОНИЗАЦИЯ С СЕРВЕРОМ
--------------------------------------------------------------------------------
local function animateDeposit(stack, targetPosition)
	if not (stack and typeof(targetPosition) == "Vector3") then return end
	local visual = buildOrePreview(stack)
	if not visual then return end
	for _, descendant in visual:GetDescendants() do
		if descendant:IsA("WeldConstraint") or descendant:IsA("Weld") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
		end
	end
	visual.Parent = workspace
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		visual:Destroy()
		return
	end
	local start = CFrame.new(hrp.Position + Vector3.new(0, 1.2, 0.8))
	visual:PivotTo(start)
	local finish = CFrame.new(targetPosition + Vector3.new(0, 1.4, 0))
	local startPosition, finishPosition = start.Position, finish.Position
	local arcHeight = math.clamp((finishPosition - startPosition).Magnitude * 0.28, 2, 6)
	local pivot = Instance.new("NumberValue")
	pivot.Value = 0
	pivot:GetPropertyChangedSignal("Value"):Connect(function()
		if not visual.Parent then return end
		local alpha = pivot.Value
		local eased = 1 - (1 - alpha) ^ 2
		local basePosition = startPosition:Lerp(finishPosition, eased)
		local arc = math.sin(alpha * math.pi) * arcHeight
		local spin = CFrame.Angles(math.rad(540) * alpha, math.rad(360) * alpha, 0)
		visual:PivotTo(CFrame.new(basePosition + Vector3.yAxis * arc) * spin)
	end)
	local tween = TweenService:Create(pivot, TweenInfo.new(0.48, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = 1 })
	tween.Completed:Connect(function()
		pivot:Destroy()
		visual:Destroy()
	end)
	tween:Play()
end

remote.OnClientEvent:Connect(function(command, payload, extra)
	if command == "Deposited" then
		animateDeposit(payload, extra)
		return
	end
	if command ~= "Sync" or typeof(payload) ~= "table" then return end
	state = payload
	state.Backpack = state.Backpack or {}
	state.Cart = state.Cart or { Items = {}, Capacity = 0 }
	state.Cart.Items = state.Cart.Items or {}
	state.Hotbar = state.Hotbar or {}
	state.Gear = state.Gear or {}
	-- Стопка могла кончиться (продали/подарили/сдали) — не держим в руках
	-- то, чего уже нет.
	if heldStackIndex and not stackByUid(heldStackIndex) then
		clearHeld()
	end
	-- Поднятая стопка могла кончиться (продали, подарили, сдали) — не
	-- оставляем в руке курсора ссылку на то, чего уже нет.
	if carried and carried.Uid and not stackByUid(carried.Uid) then
		setCarried(nil)
	end
	renderGrid()
	renderHotbar()
end)

-- v9: снаряжение в руке / телега / сервер сам убрал руду — перерисовать.
player:GetAttributeChangedSignal("HeldGear"):Connect(function()
	renderHotbar()
	if isOpen then renderGrid() end
end)
player:GetAttributeChangedSignal("HeldOreUid"):Connect(function()
	if player:GetAttribute("HeldOreUid") == nil and heldStackIndex ~= nil then
		heldStackIndex = nil
		renderHotbar()
		if isOpen then renderGrid() end
	end
end)

player.CharacterAdded:Connect(function()
	clearHeld()
	task.defer(function() remote:FireServer("Sync") end)
end)

remote:FireServer("Sync")
renderGrid()
renderHotbar()

--------------------------------------------------------------------------------
-- ВНЕШНЕЕ ОТКРЫТИЕ (кнопка-книга меню)
--------------------------------------------------------------------------------
task.spawn(function()
	local openRequest = ReplicatedStorage.Shared:WaitForChild("CollectionMenuOpenRequest", 10)
	if not openRequest then
		-- Не фатально: клавиша `~` работает независимо от этой шины.
		warn("[InventoryUI] CollectionMenuOpenRequest is missing — открытие из меню-книги недоступно.")
		return
	end
	openRequest.Event:Connect(function(target)
		if target == "Inventory" then setOpen(true) end
	end)
end)
