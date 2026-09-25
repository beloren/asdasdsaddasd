--------------------------------------------------------------------------------
-- CollectionMenu
-- Одна кнопка-книга (левый край экрана, там, где раньше была шестерёнка)
-- вместо трёх отдельных (магазин/скины/настройки) — открывает подменю
-- списком (тот же стиль, что и Store: FredokaOne, скруглённые белые
-- пилюли на цветной панели). Пункты SHOP/SKINS/SETTINGS дёргают уже
-- существующие панели через общий BindableEvent (см. CustomCartUI.client.lua
-- и SkinUI.client.lua — они его слушают и сами открывают свои панели).
-- Пункт MUTATIONS открывает книгу коллекции мутаций, которая целиком живёт
-- тут же (см. Config.Mutations/MutationBookService).
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local UiMotion = require(ReplicatedStorage.Shared.UiMotion)
local UiSfx = require(ReplicatedStorage.Shared.UiSfx)
local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)
local PlaceableFactory = require(ReplicatedStorage.Shared.PlaceableFactory)
local MutationVisuals = require(ReplicatedStorage.Shared.MutationVisuals)
local CollectionKey = require(ReplicatedStorage.Shared.CollectionKey)
local OreIncome = require(ReplicatedStorage.Shared.OreIncome)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local AmbientGlow = require(ReplicatedStorage.Shared.AmbientGlow)
local IconBounce = require(ReplicatedStorage.Shared.IconBounce)
-- Те же формулы, по которым сервер реально спавнит гоблина. Раньше карточка
-- моба считала статы сама, из голого конфига, без множителей из
-- GoblinService — и показывала ровно половину настоящего HP и ~53% урона.
local GoblinStats = require(ReplicatedStorage.Shared.GoblinStats)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mutationBookRemote = ReplicatedStorage.Shared:WaitForChild("MutationBookRequest")

local openRequest = ReplicatedStorage.Shared:FindFirstChild("CollectionMenuOpenRequest")
if not openRequest then
	openRequest = Instance.new("BindableEvent")
	openRequest.Name = "CollectionMenuOpenRequest"
	openRequest.Parent = ReplicatedStorage.Shared
end

local function imageUri(id)
	return id and id ~= 0 and ("rbxassetid://" .. tostring(id)) or ""
end

local function prepareBookVfx(source, bookButton)
	local container = Instance.new("Model")
	container.Name = "BookVFX"
	local screenOffset = source:GetAttribute("ScreenOffset")
	if typeof(screenOffset) ~= "Vector2" then screenOffset = Vector2.zero end
	local depth = source:GetAttribute("Depth")
	if typeof(depth) ~= "number" or depth <= 0 then depth = 12 end
	local referenceViewportHeight = source:GetAttribute("ReferenceViewportHeight")
	if typeof(referenceViewportHeight) ~= "number" or referenceViewportHeight <= 0 then referenceViewportHeight = 1080 end

	local clone
	local holder
	if source:IsA("ParticleEmitter") then
		holder = Instance.new("Part")
		holder.Name = "BookVFXHolder"
		holder.Transparency = 1
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanTouch = false
		holder.CanQuery = false
		holder.Size = Vector3.new(0.2, 0.2, 0.2)
		holder.Parent = container
		clone = source:Clone()
		clone.Parent = holder
	else
		clone = source:Clone()
		clone.Parent = container
	end
	if clone:IsA("ParticleEmitter") then
		clone.LockedToPart = true
	else
		for _, descendant in clone:GetDescendants() do
			if descendant:IsA("ParticleEmitter") then
				descendant.LockedToPart = true
			end
		end
	end

	local pivotTarget
	if clone:IsA("Model") then
		for _, descendant in clone:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanTouch = false
				descendant.CanQuery = false
			end
		end
		pivotTarget = function(cframe)
			clone:PivotTo(cframe)
		end
	elseif clone:IsA("BasePart") then
		clone.Anchored = true
		clone.CanCollide = false
		clone.CanTouch = false
		clone.CanQuery = false
		pivotTarget = function(cframe)
			clone.CFrame = cframe
		end
	else
		pivotTarget = function(cframe)
			holder.CFrame = cframe
		end
	end

	local connection
	connection = RunService.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		if not camera then return end
		if container.Parent ~= camera then container.Parent = camera end
		local vfxEnabled = player:GetAttribute("IntroActive") ~= true
		if clone:IsA("ParticleEmitter") then
			clone.Enabled = vfxEnabled
		else
			for _, descendant in clone:GetDescendants() do
				if descendant:IsA("ParticleEmitter")
					or descendant:IsA("Trail")
					or descendant:IsA("Beam") then
					descendant.Enabled = vfxEnabled
				end
			end
		end

		local viewportSize = camera.ViewportSize
		if viewportSize.X <= 0 or viewportSize.Y <= 0 then return end
		local buttonCenter = bookButton.AbsolutePosition + bookButton.AbsoluteSize / 2 + screenOffset
		local normalizedX = (buttonCenter.X / viewportSize.X - 0.5) * 2
		local normalizedY = (0.5 - buttonCenter.Y / viewportSize.Y) * 2
		local scaledDepth = depth * viewportSize.Y / referenceViewportHeight
		local halfHeight = scaledDepth * math.tan(math.rad(camera.FieldOfView) / 2)
		local worldOffset = Vector3.new(normalizedX * halfHeight * viewportSize.X / viewportSize.Y, normalizedY * halfHeight, -scaledDepth)
		pivotTarget(camera.CFrame * CFrame.new(worldOffset))
	end)

	bookButton.Destroying:Connect(function()
		connection:Disconnect()
		container:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Кнопка-книга
--------------------------------------------------------------------------------

-- Книга обязательна и собирается вручную в StarterGui/CollectionMenu/
-- BookButton. Не создаём никаких плейсхолдеров: ждём точную Studio-иерархию,
-- чтобы её размер, вид, поворот и позиция оставались только под её контролем.
-- v20: меню собирается билдером (Shared.UiBuilders.CollectionMenuUi →
-- StarterGui/CollectionMenu); нет в StarterGui — соберётся тем же билдером.
local gui = require(ReplicatedStorage.Shared.UiRegistry).Get("CollectionMenu")
gui.DisplayOrder = 30
local bookButton = gui:WaitForChild("BookButton")
assert(bookButton:IsA("GuiButton"), "StarterGui/CollectionMenu/BookButton должен быть ImageButton или TextButton")

local bookMobileScale = bookButton:FindFirstChild("MobileBookScale")
if not bookMobileScale then
	bookMobileScale = Instance.new("UIScale")
	bookMobileScale.Name = "MobileBookScale"
	bookMobileScale.Parent = bookButton
end
local function resizeBookButton()
	if not UserInputService.TouchEnabled then
		bookMobileScale.Scale = 1
		return
	end
	bookMobileScale.Scale = 1 -- v20.16: подгонка под экран — client/ResponsiveUi
	bookButton.AnchorPoint = Vector2.new(0, 0.5)
	-- ПО ПРЯМОМУ ЗАПРОСУ: "книжка на телефоне должна быть точно слева по
	-- центру, именно на телефоне, на ПК норм стоит". Раньше здесь стояло
	-- 0.7 по Y (низ экрана, а не центр) — именно это и уводило книгу вниз
	-- от центра ИМЕННО на мобиле, хотя на ПК она остаётся там, где её
	-- поставили в Studio (обычно центр). Теперь 0.5 — ровно по центру, как
	-- и на ПК. Заодно это гарантирует, что закреплённый квест (который
	-- всегда встаёт НИЖЕ книги, см. QuestUI.client.lua/positionPinnedTracker)
	-- окажется выше нижнего края экрана, а не будет вылезать за него.
	bookButton.Position = UDim2.new(0, 12, 0.5, 0)
end
resizeBookButton()

local bookVfxAsset = ReplicatedStorage:WaitForChild("Assets"):FindFirstChild("BookVFX")
if bookVfxAsset and (bookVfxAsset:IsA("ParticleEmitter") or bookVfxAsset:IsA("BasePart") or bookVfxAsset:IsA("Model")) then
	prepareBookVfx(bookVfxAsset, bookButton)
else
	local bookGlow = Instance.new("Frame")
	bookGlow.Name = "BookGlow"
	bookGlow.BackgroundTransparency = 1
	bookGlow.ZIndex = 0
	bookGlow.Parent = gui
	local function syncBookGlow()
		bookGlow.AnchorPoint = bookButton.AnchorPoint
		bookGlow.Position = bookButton.Position
		bookGlow.Size = bookButton.Size
		bookGlow.Rotation = bookButton.Rotation
	end
	syncBookGlow()
	bookButton:GetPropertyChangedSignal("AnchorPoint"):Connect(syncBookGlow)
	bookButton:GetPropertyChangedSignal("Position"):Connect(syncBookGlow)
	bookButton:GetPropertyChangedSignal("Size"):Connect(syncBookGlow)
	bookButton:GetPropertyChangedSignal("Rotation"):Connect(syncBookGlow)
	AmbientGlow.Apply(bookGlow)
end

local function setBookVfxEnabled(enabled)
	local camera = workspace.CurrentCamera
	local bookVfx = camera and camera:FindFirstChild("BookVFX")
	if bookVfx then
		for _, descendant in bookVfx:GetDescendants() do
			if descendant:IsA("ParticleEmitter")
				or descendant:IsA("Trail")
				or descendant:IsA("Beam") then
				descendant.Enabled = enabled
			end
		end
	end
	local bookGlow = gui:FindFirstChild("BookGlow")
	if bookGlow then
		bookGlow.Visible = enabled
	end
end

setBookVfxEnabled(player:GetAttribute("IntroActive") ~= true)
player:GetAttributeChangedSignal("IntroActive"):Connect(function()
	setBookVfxEnabled(player:GetAttribute("IntroActive") ~= true)
end)

--------------------------------------------------------------------------------
-- VFX позади книжки. Настоящий ассет `ReplicatedStorage/Assets/BookVFX`
-- клонируется в CurrentCamera и каждый кадр выравнивается по её экранной
-- позиции. Если ассета ещё нет, используется лёгкий UI-fallback из AmbientGlow.
--------------------------------------------------------------------------------
-- Сама книжка — плавная непрерывная "дыхательная" пульсация размера (см.
-- IconBounce.ApplyPulse), НЕ резкий прыжок, как у HUD-иконок — тут нужен
-- медленный, спокойный акцент, а не бодрый скачок.
IconBounce.ApplyPulse(bookButton)

--------------------------------------------------------------------------------
-- Подменю — вертикальный список белых пилюль на цветной панели (стиль
-- Store, см. tools/BuildAllUI.lua).
--------------------------------------------------------------------------------

local dimmer = gui:FindFirstChild("Dimmer")
local submenu = gui:FindFirstChild("Submenu")
if not (dimmer and dimmer:IsA("GuiButton") and submenu and submenu:IsA("GuiObject")) then
	warn("[CollectionMenu] Submenu не найден или неполон — запусти tools/BuildAllUI.lua. Использую runtime fallback.")
	if dimmer then dimmer:Destroy() end
	if submenu then submenu:Destroy() end
	dimmer = Instance.new("TextButton")
	dimmer.Name = "Dimmer"
	dimmer.Size = UDim2.fromScale(1, 1)
	dimmer.BackgroundColor3 = Color3.new(0, 0, 0)
	dimmer.BackgroundTransparency = 0.5
	dimmer.BorderSizePixel = 0
	dimmer.AutoButtonColor = false
	dimmer.Text = ""
	dimmer.Visible = false
	dimmer.ZIndex = 5
	dimmer.Parent = gui

	submenu = Instance.new("Frame")
	submenu.Name = "Submenu"
	submenu.AnchorPoint = Vector2.new(0.5, 0.5)
	submenu.Position = UDim2.fromScale(0.5, 0.5)
	submenu.Size = UDim2.fromOffset(360, 340)
	submenu.BackgroundColor3 = Color3.fromRGB(45, 140, 220)
	submenu.BorderSizePixel = 0
	submenu.Visible = false
	submenu.ZIndex = 6
	submenu.Parent = gui
end
dimmer.Visible = false
submenu.Visible = false

local submenuScale = submenu:FindFirstChild("MobileSubmenuScale") or Instance.new("UIScale")
submenuScale.Name = "MobileSubmenuScale"
submenuScale.Parent = submenu
local function resizeSubmenu()
	if not UserInputService.TouchEnabled then
		submenuScale.Scale = 1
		return
	end
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(390, 844)
	local _ = viewport
	submenuScale.Scale = 1 -- v20.16: подгонка под экран — client/ResponsiveUi
end
resizeSubmenu()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resizeSubmenu)
end
-- Без скругления (квадратные углы, как и весь остальной UI "книжки").

local submenuClose = submenu:FindFirstChild("CloseButton", true)
local list = submenu:FindFirstChild("List", true)
if not (submenuClose and submenuClose:IsA("GuiButton")) then
	submenuClose = Instance.new("TextButton")
	submenuClose.Name = "CloseButton"
	submenuClose.AnchorPoint = Vector2.new(1, 0)
	submenuClose.Position = UDim2.new(1, -10, 0, 10)
	submenuClose.Size = UDim2.fromOffset(30, 30)
	submenuClose.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
	require(game:GetService("ReplicatedStorage").Shared.UiKit).StyleText(submenuClose, "Number") -- v20: шрифт темы
	submenuClose.TextScaled = true
	submenuClose.TextColor3 = Color3.new(1, 1, 1)
	submenuClose.Text = "X"
	submenuClose.ZIndex = 7
	submenuClose.Parent = submenu
end
if not (list and list:IsA("GuiObject")) then
	list = Instance.new("Frame")
	list.Name = "List"
	list.Position = UDim2.fromOffset(20, 20)
	list.Size = UDim2.new(1, -40, 1, -40)
	list.BackgroundTransparency = 1
	list.ZIndex = 6
	list.Parent = submenu
end
if not list:FindFirstChildOfClass("UIListLayout") then
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 10)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list
end

local mutationBookPanel -- объявлена ниже, нужна форвардом для пункта MUTATIONS

local function closeSubmenu()
	dimmer.Visible = false
	UiMotion.Close(submenu)
end

local function openSubmenu()
	UiSfx.play("UiMenuOpen")
	dimmer.Visible = true
	submenu.Visible = true
	UiMotion.Open(submenu)
end

local ITEMS = {
	{ Key = "Inventory", Label = "INVENTORY", Icon = "InventoryMenuIconId" },
	{ Key = "Shop", Label = "SHOP", Icon = "ShopMenuIconId" },
	{ Key = "Skins", Label = "SKINS", Icon = "SkinsMenuIconId" },
	{ Key = "Settings", Label = "SETTINGS", Icon = "SettingsMenuIconId" },
	{ Key = "Mutations", Label = "MUTATIONS", Icon = "MutationsMenuIconId" },
}

-- Пункт SETTINGS убран вместе с окном настроек (Config.UI.
-- SettingsMenuEnabled = false): кнопка, которая ничего не открывает, хуже,
-- чем её отсутствие. Уже собранную в Studio строку тоже удаляем.
if Config.UI.SettingsMenuEnabled == false then
	for index = #ITEMS, 1, -1 do
		if ITEMS[index].Key == "Settings" then
			table.remove(ITEMS, index)
		end
	end
	local studioSettingsRow = list:FindFirstChild("SettingsRow")
	if studioSettingsRow then
		studioSettingsRow:Destroy()
	end
end

for order, item in ITEMS do
	local row = list:FindFirstChild(item.Key .. "Row")
	if not (row and row:IsA("GuiButton")) then
		row = Instance.new("TextButton")
		row.Name = item.Key .. "Row"
		row.LayoutOrder = order
		row.Size = UDim2.new(1, 0, 0, 56)
		row.BackgroundColor3 = Color3.new(1, 1, 1)
		row.AutoButtonColor = false
		row.Text = ""
		row.ZIndex = 6
		row.Parent = list

		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 12, 0.5, 0)
		icon.Size = UDim2.fromOffset(36, 36)
		icon.BackgroundColor3 = Color3.fromRGB(220, 220, 230)
		icon.BorderSizePixel = 0
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Image = imageUri(Config.UI[item.Icon])
		icon.ZIndex = 7
		icon.Parent = row

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.AnchorPoint = Vector2.new(0, 0.5)
		label.Position = UDim2.new(0, 60, 0.5, 0)
		label.Size = UDim2.new(1, -72, 1, -12)
		label.BackgroundTransparency = 1
		require(game:GetService("ReplicatedStorage").Shared.UiKit).StyleText(label, "Number") -- v20: шрифт темы
		label.TextScaled = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = Color3.fromRGB(60, 60, 70)
		label.Text = item.Label
		label.ZIndex = 7
		label.Parent = row
	end

	row.Activated:Connect(function()
		UiSfx.play()
		closeSubmenu()
		if item.Key == "Mutations" then
			if mutationBookPanel then
				mutationBookPanel.Visible = true
				UiMotion.Open(mutationBookPanel)
				dimmer.Visible = true
			end
		else
			openRequest:Fire(item.Key)
		end
	end)
end

bookButton.Activated:Connect(function()
	local ok, err = pcall(function()
		if submenu.Visible then
			closeSubmenu()
		else
			openSubmenu()
		end
	end)
	if not ok then
		warn("[CollectionMenu] Ошибка при клике на BookButton: " .. tostring(err))
	end
end)
submenuClose.Activated:Connect(closeSubmenu)
dimmer.Activated:Connect(function()
	if submenu.Visible then
		closeSubmenu()
	elseif not (mutationBookPanel and mutationBookPanel.Visible) then
		return
	end
end)

--------------------------------------------------------------------------------
-- Книга мутаций — "найдено/не найдено" по каждой паре тир руды × мутация
-- (просто галочка, без счётчика повторов — см. Config.Mutations). Если в
-- StarterGui уже есть свой "MutationBookPanel" (см.
-- tools/BuildAllUI.lua) — используем его контейнер (Title/
-- CloseButton/Scroller) как есть, свободно редактируемый в Studio; сама
-- сетка тир×мутация всё равно генерируется кодом (она из Config.Mutations,
-- вручную раскладывать 48 ячеек в Studio было бы мучением).
--------------------------------------------------------------------------------


-- v9: книга строится CollectionBookUiBuilder («музей кристаллов»). Нет
-- панели или она старой версии (прежняя «деревянная» из билдера) — ставим новую.
local CollectionBookUiBuilder = require(ReplicatedStorage.Shared.CollectionBookUiBuilder)
local panel = gui:FindFirstChild("MutationBookPanel") or gui:WaitForChild("MutationBookPanel", 3)
if not panel or (tonumber(panel:GetAttribute("BuilderVersion")) or 0) < CollectionBookUiBuilder.VERSION then
	panel = CollectionBookUiBuilder.Install(gui)
end
mutationBookPanel = panel
panel.ZIndex = 6
-- Sibling mode keeps the whole book subtree above the full-screen dimmer,
-- while the dimmer still blocks clicks outside the book.
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local bookClose = panel:FindFirstChild("CloseButton", true)
local tabMutations = panel:WaitForChild("Sidebar"):WaitForChild("TabOreMutations")
local tabMobs = panel.Sidebar:WaitForChild("TabMobs")

-- Новый билдер создаёт кнопку заранее. Клонирование оставлено только как
-- fallback для старого place, где BuildMutationBookCrystalsTab ещё не запускали.
local tabCrystals = panel.Sidebar:FindFirstChild("TabCrystals")
if not tabCrystals then
	tabCrystals = tabMobs:Clone()
	tabCrystals.Name = "TabCrystals"
	tabCrystals.LayoutOrder = (tonumber(tabMobs.LayoutOrder) or 0) + 1
	tabCrystals.Parent = panel.Sidebar
end
do
	-- Подпись может лежать как на самой кнопке, так и в дочернем TextLabel —
	-- зависит от того, как собран макет. Поддерживаем оба варианта.
	if tabCrystals:IsA("TextButton") or tabCrystals:IsA("TextLabel") then
		tabCrystals.Text = "CRYSTALS"
	end
	for _, descendant in tabCrystals:GetDescendants() do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
			descendant.Text = "CRYSTALS"
		end
	end
end
-- v20: вкладка ТРОФЕЕВ (реликвии). Старый макет без кнопки — клон мобов.
local tabTrophies = panel.Sidebar:FindFirstChild("TabTrophies")
if not tabTrophies then
	tabTrophies = tabMobs:Clone()
	tabTrophies.Name = "TabTrophies"
	tabTrophies.LayoutOrder = (tonumber(tabCrystals.LayoutOrder) or 0) + 1
	tabTrophies.Parent = panel.Sidebar
	for _, descendant in tabTrophies:GetDescendants() do
		if descendant:IsA("TextLabel") then descendant.Text = "🏆" end
	end
end
local leftPage = panel:FindFirstChild("LeftPage", true)
local pageTitle = leftPage:WaitForChild("PageTitle")
local bookScroller = leftPage:WaitForChild("Scroller")
-- ОТСТУП ПОД ОБВОДКУ КАРТОЧЕК. Scroller обрезает всё, что выходит за его
-- границы, а UIStroke у ячейки рисуется СНАРУЖИ её прямоугольника — поэтому у
-- крайних карточек рамка срезалась с той стороны, где ячейка прилегала к краю
-- прокрутки. Несколько пикселей поля решают это, не трогая саму сетку.
do
	local scrollerPadding = bookScroller:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding")
	scrollerPadding.PaddingTop = UDim.new(0, 4)
	scrollerPadding.PaddingBottom = UDim.new(0, 4)
	scrollerPadding.PaddingLeft = UDim.new(0, 4)
	scrollerPadding.PaddingRight = UDim.new(0, 4)
	scrollerPadding.Parent = bookScroller
end
local rightPage = panel:FindFirstChild("RightPage", true)
local previewViewport = rightPage:WaitForChild("PreviewImage")
local previewCamera = previewViewport:FindFirstChildWhichIsA("Camera") or Instance.new("Camera")
previewCamera.Parent = previewViewport
previewViewport.CurrentCamera = previewCamera
local previewName = rightPage:WaitForChild("ItemNameLabel")
previewName.RichText = true
local previewNameGradient = previewName:FindFirstChild("RarityGradient") or Instance.new("UIGradient")
previewNameGradient.Name = "RarityGradient"
previewNameGradient.Enabled = false
previewNameGradient.Parent = previewName
local priceLabel = rightPage:WaitForChild("StatsRow"):WaitForChild("PriceLabel")
local chanceLabel = rightPage.StatsRow:WaitForChild("ChanceLabel")
local descriptionLabel = rightPage:WaitForChild("DescriptionLabel")
descriptionLabel.RichText = true
-- Обводка ЗДЕСЬ НЕ СТАВИТСЯ. Она была добавлена ради читаемости цветных
-- значений, но заодно легла и на серые подписи ("RARITY:", "SOURCE:" и
-- прочие) — на светлом фоне книги они от этого стали грязными и тяжёлыми.
-- Читаемость самих цветных значений решена точечно: тёмная обводка вешается
-- только на них, прямо в разметке RichText — тегом <stroke> вокруг каждого
-- <font> в строках описания ниже.
descriptionLabel.TextStrokeTransparency = 1
local templates = panel:WaitForChild("Templates")
local itemTemplate = templates:WaitForChild("ItemCell")
local lockedTemplate = templates:WaitForChild("LockedCell")
itemTemplate.Visible = false
lockedTemplate.Visible = false

local responsiveScale = panel:FindFirstChild("ResponsiveScale") or Instance.new("UIScale")
responsiveScale.Name = "ResponsiveScale"
responsiveScale.Parent = panel
local function resizeMutationBook()
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(900, 560)
	local _ = viewport
	responsiveScale.Scale = 1 -- v20.16: подгонка под экран — client/ResponsiveUi
end
resizeMutationBook()
if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resizeMutationBook) end

local state = { Mutations = {}, Mobs = {}, Crystals = {}, OreBook = {} }
local activeTab = "Mutations"

-- v9: счётчик «найдено / всего» (из билдера книги).
local progressChip = leftPage:FindFirstChild("ProgressChip")
local progressLabel = progressChip and progressChip:FindFirstChild("Text")

-- v9: руда → пещера, где она впервые встречается (для превью/подписи).
local ORE_CAVE = {}
for tier, tierInfo in Config.MineTiers do
	for _, ore in tierInfo.Ores or {} do
		if not ORE_CAVE[ore.Key] then ORE_CAVE[ore.Key] = tier end
	end
end

local previewObject
local previewToken = 0

local function colorHex(color)
	return ("#%02X%02X%02X"):format(math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255))
end

local rarityRank = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6 }
local function mutationRarity(chance)
	if chance <= 0.005 then return "Mythic" end
	if chance <= 0.015 then return "Legendary" end
	if chance <= 0.03 then return "Epic" end
	if chance <= 0.06 then return "Rare" end
	return "Uncommon"
end

local function setTitleGradient(rarity)
	local rank = rarityRank[rarity] or 1
	previewNameGradient.Enabled = rank >= 3
	if rank >= 5 then
		previewNameGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 100)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 225, 80)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(80, 220, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 100, 255)),
		})
	elseif rank == 4 then
		previewNameGradient.Color = ColorSequence.new(Color3.fromRGB(210, 110, 255), Color3.fromRGB(100, 180, 255))
	elseif rank == 3 then
		previewNameGradient.Color = ColorSequence.new(Color3.fromRGB(100, 180, 255), Color3.fromRGB(190, 235, 255))
	end
end

RunService.RenderStepped:Connect(function()
	if previewNameGradient.Enabled and panel.Visible then previewNameGradient.Rotation = (os.clock() * 55) % 360 end
end)

local previewNameDefaultColor = previewName.TextColor3
local function clearPreview()
	previewName.TextColor3 = previewNameDefaultColor
	previewToken += 1
	if previewObject then previewObject:Destroy(); previewObject = nil end
	previewViewport.Visible = false
	previewName.Visible = false
	rightPage.StatsRow.Visible = false
	descriptionLabel.Visible = false
end

local function revealPreviewDetails()
	previewViewport.Visible = true
	previewName.Visible = true
	rightPage.StatsRow.Visible = true
	descriptionLabel.Visible = true
end

local function prepareViewportObject(object)
	for _, descendant in object:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
		end
	end
	if object:IsA("BasePart") then object.Anchored = true; object.CanCollide = false end
	object.Parent = previewViewport
	if object:IsA("Model") then object:PivotTo(CFrame.identity) else object.CFrame = CFrame.identity end
	-- Камера наводится на ЦЕНТР ГАБАРИТОВ, а не в начало координат: PivotTo
	-- ставит в ноль ПИВОТ, а он у кристалла может быть в основании, а у
	-- персонажа — в середине корпуса. Из-за этого модель уезжала из кадра, и
	-- предпросмотр выглядел пустым.
	local center, size
	if object:IsA("Model") then
		local boundsCFrame, boundsSize = object:GetBoundingBox()
		center, size = boundsCFrame.Position, boundsSize
	else
		center, size = object.Position, object.Size
	end
	local radius = math.max(size.X, size.Y, size.Z) * 1.35 + 1
	-- Модели персонажей показываем КРУПНЕЕ примерно на 30%: гоблин вытянут по
	-- высоте, и подобранный под кристалл отступ оставлял вокруг него много
	-- пустого места. У руды отступ прежний.
	local isCharacter = object:IsA("Model") and object:FindFirstChildOfClass("Humanoid") ~= nil
	local isGoblinPreview = object.Name:match("^Goblin_") ~= nil or object.Name == "MobPreview"
	if isCharacter or isGoblinPreview then
		radius = radius * 0.7
	end
	previewCamera.CFrame = CFrame.lookAt(
		center + Vector3.new(radius * 0.75, radius * 0.45, radius * 0.75),
		center
	)
	previewObject = object
	previewToken += 1
	-- БОЛЬШАЯ ПАНЕЛЬ ПРЕДПРОСМОТРА КРУТИТСЯ — там модель показывают крупно и
	-- со всех сторон. Статичны только маленькие ячейки книги (см. ниже), где
	-- шестнадцать вертящихся кристаллов в ряду дёргали бы глаз.
	local token = previewToken
	task.spawn(function()
		while previewToken == token and object.Parent do
			local yRotation = os.clock() * 0.7 + (isGoblinPreview and math.pi or 0)
			local cf = CFrame.Angles(0, yRotation, 0)
			if object:IsA("Model") then object:PivotTo(cf) else object.CFrame = cf end
			task.wait(0.03)
		end
	end)
end

-- v9: превью записи книги по руде.
function showOreEntry(oreInfo, mutationId, cave)
	clearPreview()
	revealPreviewDetails()
	local mutation = mutationId and Config.Mutations[mutationId]
	local rarity = (Config.OreRarityFor and Config.OreRarityFor(oreInfo.Key, cave)) or oreInfo.Rarity or "Common"
	setTitleGradient(rarity)
	previewName.Text = mutation
		and ("<font color=\"%s\">%s</font> + <font color=\"%s\">%s</font>"):format(colorHex(oreInfo.Color), oreInfo.DisplayName, colorHex(mutation.Color), mutation.DisplayName)
		or ("<font color=\"%s\">%s</font>"):format(colorHex(oreInfo.Color), oreInfo.DisplayName)
	local price = math.floor((oreInfo.CrystalValue or 0) * (mutation and mutation.Multiplier or 1) + 0.5)
	priceLabel.Text = "$" .. NumberFormat.abbreviate(price)
	chanceLabel.Text = mutation and ("%.2f%%"):format(mutation.Chance * 100) or ""
	descriptionLabel.Text = ("<font color=\"%s\">%s</font>  ·  CAVE %d"):format(colorHex(Config.RarityColors[rarity] or Color3.new(1, 1, 1)), tostring(rarity):upper(), cave)
	local ok, model = pcall(PlaceholderFactory.OreCrystal, oreInfo, Config.OreVariants[1])
	if not ok then model = PlaceholderFactory.Crystal(cave) end
	if mutationId then MutationVisuals.Apply(model, mutationId) end
	prepareViewportObject(model)
end

local function showMutation(tier, mutationId)
	clearPreview()
	revealPreviewDetails()
	local mutation = Config.Mutations[mutationId]
	local tierInfo = Config.MineTiers[tier]
	if not (mutation and tierInfo) then
		warn("[CollectionMenu] Missing mutation data", tostring(tier), tostring(mutationId))
		descriptionLabel.Text = "Mutation data unavailable"
		return
	end
	local mutationRarityName = mutationRarity(mutation.Chance)
	local displayRarity = (rarityRank[mutationRarityName] or 1) > (rarityRank[tierInfo.Rarity] or 1) and mutationRarityName or tierInfo.Rarity
	setTitleGradient(displayRarity)
	previewName.Text = ("<font color=\"%s\">%s</font> + <font color=\"%s\">%s</font>"):format(
		colorHex(tierInfo.Color), tierInfo.DisplayName, colorHex(mutation.Color), mutation.DisplayName
	)
	local actualPrice = math.floor(tierInfo.CrystalValue * mutation.Multiplier + 0.5)
	priceLabel.Text = "VALUE: $" .. NumberFormat.abbreviate(actualPrice)
	chanceLabel.Text = ("CHANCE: %.2f%%"):format(mutation.Chance * 100)
	descriptionLabel.Text = ("%s\nRARITY: <stroke color=\"rgb(0,0,0)\" joins=\"round\" thickness=\"1\"><font color=\"%s\">%s + %s</font></stroke>\nPRICE: <stroke color=\"rgb(0,0,0)\" joins=\"round\" thickness=\"1\"><font color=\"#55E879\">$%s</font></stroke>\nFOUND IN: <stroke color=\"rgb(0,0,0)\" joins=\"round\" thickness=\"1\"><font color=\"#69EB82\">TIER %d MINE</font></stroke>"):format(
		tostring(tierInfo.Description or ""), colorHex(Config.RarityColors[displayRarity] or Color3.new(1, 1, 1)), tostring(tierInfo.Rarity or "UNKNOWN"), tostring(mutationRarityName or "UNKNOWN"),
		NumberFormat.abbreviate(actualPrice), tier
	)
	local ore = PlaceholderFactory.Crystal(tier)
	MutationVisuals.Apply(ore, mutationId)
	prepareViewportObject(ore)
end

-- РЕАЛЬНАЯ МОДЕЛЬ ГОБЛИНА, а не кубики. Раньше эта функция всегда собирала
-- заглушку из шести деталей, поэтому энциклопедия показывала одну и ту же
-- фигурку для всех пяти типов, даже когда в ReplicatedStorage/Assets уже
-- лежали настоящие модели.
--
-- Имена ассетов те же, что использует сервер (см. findGoblinAssetWithSkins в
-- GoblinService): Goblin_Warrior, Goblin_King и так далее, плюс варианты
-- внешности с суффиксом _1.._3. Для энциклопедии всегда берём ПЕРВЫЙ
-- доступный вариант, а не случайный — карточка одного и того же моба не
-- должна меняться при каждом открытии.
local function findGoblinAssetForBook(goblinType)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then return nil end
	local base = "Goblin_" .. goblinType
	for _, name in { base, base .. "_1", base .. "_2", base .. "_3" } do
		local asset = assets:FindFirstChild(name)
		if asset and asset:IsA("Model") then return asset:Clone() end
	end
	return nil
end

local function makeMobPreview(definition, goblinType)
	local custom = goblinType and findGoblinAssetForBook(goblinType)
	if custom then return custom end

	-- Запасная фигурка из деталей — на случай, если своей модели ещё нет.
	local model = Instance.new("Model")
	model.Name = "MobPreview"
	local color = definition.Color or Color3.fromRGB(90, 180, 70)
	for _, partInfo in {
		{"Torso", Vector3.new(2, 2, 1), color, Vector3.new(0, 0, 0)},
		{"Head", Vector3.new(2, 1, 1), color:Lerp(Color3.new(1, 1, 1), 0.15), Vector3.new(0, 1.5, 0)},
		{"LeftArm", Vector3.new(0.7, 2, 0.7), color, Vector3.new(-1.35, 0, 0)},
		{"RightArm", Vector3.new(0.7, 2, 0.7), color, Vector3.new(1.35, 0, 0)},
		{"LeftLeg", Vector3.new(0.8, 1.8, 0.8), color:Lerp(Color3.new(0, 0, 0), 0.25), Vector3.new(-0.5, -1.9, 0)},
		{"RightLeg", Vector3.new(0.8, 1.8, 0.8), color:Lerp(Color3.new(0, 0, 0), 0.25), Vector3.new(0.5, -1.9, 0)},
	} do
		local part = Instance.new("Part")
		part.Name, part.Size, part.Color, part.Position = partInfo[1], partInfo[2], partInfo[3], partInfo[4]
		part.Parent = model
	end
	return model
end

local function showMob(mobId)
	clearPreview()
	revealPreviewDetails()
	local definition = Config.Goblins.Types[mobId]
	previewNameGradient.Enabled = false
	previewName.Text = definition.DisplayName
	rightPage.StatsRow.Visible = false
	-- У золотого стража MinMineTier/MaxMineTier = 11 — это не настоящий
	-- диапазон добычи, а служебные числа, которыми его выкидывают из пула
	-- обычных волн (см. chooseGoblinType). Реальный тир ему задаёт валун,
	-- то есть 1..MaxTierCap — по нему и считаем диапазон статов, иначе
	-- книга покажет силу несуществующего 11-го тира.
	local isGolden = mobId == "Golden"
	local statTierMin = isGolden and 1 or definition.MinMineTier
	local statTierMax = isGolden and Config.Rebirth.MaxTierCap or definition.MaxMineTier
	local minHp = GoblinStats.Health(mobId, statTierMin, isGolden)
	local maxHp = GoblinStats.Health(mobId, statTierMax, isGolden)
	local minDamage = GoblinStats.Damage(mobId, statTierMin)
	local maxDamage = GoblinStats.Damage(mobId, statTierMax)
	local target = GoblinStats.TargetText(mobId)
	-- Замедление растёт вместе с тиром (см. GoblinService:_applyTypeSlowdown),
	-- а раньше здесь печаталось голое definition.Slowdown — значение, верное
	-- только на самом первом тире появления. У стража оно вообще не
	-- применяется: ветка Objective = "Guard" не вызывает _applyTypeSlowdown.
	local slowMin = GoblinStats.Slowdown(mobId, statTierMin)
	local slowMax = GoblinStats.Slowdown(mobId, statTierMax)
	local debuff
	if slowMax <= 0 then
		debuff = "NONE - IT ONLY FIGHTS"
	elseif math.abs(slowMax - slowMin) < 0.005 then
		debuff = ("SLOWS MINE BY %.0f%% FOR %d SEC"):format(slowMax * 100, definition.SlowdownDuration)
	else
		debuff = ("SLOWS MINE BY %.0f-%.0f%% FOR %d SEC"):format(slowMin * 100, slowMax * 100, definition.SlowdownDuration)
	end
	-- "Золотой" не приходит с шахты (у него нет реального диапазона тиров
	-- добычи — MinMineTier/MaxMineTier = 11 существуют только чтобы обычные
	-- волны его не выбирали, см. Config.lua), поэтому для него отдельная
	-- строка появления/диапазона вместо бессмысленного "TIER 11 MINE".
	local appearsLine, tiersLine
	if mobId == "Golden" then
		appearsLine = "BREAKING A GOLDEN BOULDER"
		tiersLine = "ANY (SCALES WITH BOULDER TIER)"
	else
		appearsLine = ("TIER %d MINE"):format(definition.MinMineTier)
		tiersLine = ("%d-%d"):format(definition.MinMineTier, definition.MaxMineTier)
	end
	descriptionLabel.Text = ("DEBUFF: <stroke color=\"rgb(0,0,0)\" joins=\"round\" thickness=\"1\"><font color=\"#FF6969\">%s</font></stroke>\nHP: <stroke color=\"rgb(0,0,0)\" joins=\"round\" thickness=\"1\"><font color=\"#69EB82\">%d-%d</font></stroke>\nFIRST APPEARS: <stroke color=\"rgb(0,0,0)\" joins=\"round\" thickness=\"1\"><font color=\"#7FD4FF\">%s</font></stroke>\nTARGET: <stroke color=\"rgb(0,0,0)\" joins=\"round\" thickness=\"1\"><font color=\"#FF9E69\">%s</font></stroke>\nDAMAGE: <stroke color=\"rgb(0,0,0)\" joins=\"round\" thickness=\"1\"><font color=\"#FF6969\">%.0f-%.0f</font></stroke>\nMINE TIERS: <stroke color=\"rgb(0,0,0)\" joins=\"round\" thickness=\"1\"><font color=\"#69EB82\">%s</font></stroke>"):format(
		debuff, minHp, maxHp, appearsLine, target, minDamage, maxDamage, tiersLine
	)
	prepareViewportObject(makeMobPreview(definition, mobId))
end

-- v20: карточка трофея (реликвии) на правой странице.
local function showTrophy(relicId)
	clearPreview()
	revealPreviewDetails()
	local info = Config.Relics.Types[relicId]
	local color = (Config.Relics.RarityColors and Config.Relics.RarityColors[info.Rarity]) or Config.RarityColors[info.Rarity] or info.Color
	previewNameGradient.Enabled = false
	previewName.Text = ("%s %s"):format(info.Icon or "🏆", info.DisplayName)
	previewName.TextColor3 = color
	rightPage.StatsRow.Visible = true
	local count = tonumber(player:GetAttribute("RelicFound_" .. relicId)) or 0
	local best = tonumber(player:GetAttribute("RelicBest_" .. relicId)) or 0
	priceLabel.Text = ("+%d%% INCOME"):format(math.floor((info.IncomeBonus or 0) * 100 + 0.5))
	chanceLabel.Text = ("1 IN %s"):format(NumberFormat.abbreviate(math.floor(1 / math.max(info.Chance or 1e-9, 1e-9) + 0.5)))
	local hex = color:ToHex()
	local function value(text, valueColor)
		return ("<stroke color=\"rgb(0,0,0)\" joins=\"round\" thickness=\"1\"><font color=\"#%s\">%s</font></stroke>"):format(valueColor or hex, text)
	end
	descriptionLabel.Text = table.concat({
		"RARITY: " .. value(string.upper(info.Rarity or "")),
		"FOUND: " .. value(("%d TIME%s"):format(count, count == 1 and "" or "S"), "69EB82"),
		"BEST SERIAL: " .. value(best > 0 and ("#" .. best) or "-", "FFD75A"),
		"DROPS FROM: " .. value("BOULDERS & CHESTS", "7FD4FF"),
		"PLACE IT ON YOUR BASE FOR " .. value(("+%d%% INCOME"):format(math.floor((info.IncomeBonus or 0) * 100 + 0.5)), "69EB82"),
	}, "\n")
	local ok, model = pcall(PlaceableFactory.BuildRelic, relicId)
	if ok and model then prepareViewportObject(model) end
end

-- Порядок кристаллов в энциклопедии: сперва все жеодные по тирам жеод
-- (Stone -> Singularity, по три руды в каждой), потом все валунные по тирам
-- валуна. Строится один раз при загрузке.
local CRYSTAL_ENTRIES = {}
do
	for tier, geodeType in Config.Geodes.Order do
		local typeInfo = Config.Geodes.Types[geodeType]
		if typeInfo then
			for _, oreId in typeInfo.Ores do
				if Config.Geodes.Ores[oreId] then
					table.insert(CRYSTAL_ENTRIES, { OreId = oreId, Source = "Geode", GeodeType = geodeType, Tier = tier, Mutations = {} })
				end
			end
		end
	end
	local boulderOrder = { "Rubblegem", "Ironflake", "Coalheart", "Duskstone", "VerdantCore",
		"Emberite", "Frostvein", "Wyrmglass", "UmbralShard", "Titanheart" }
	for tier, oreId in boulderOrder do
		if Config.Geodes.Ores[oreId] then
			table.insert(CRYSTAL_ENTRIES, { OreId = oreId, Source = "Boulder", Tier = tier, Mutations = {} })
		end
	end
end

-- Страница кристалла. Оформление то же, что у мутаций и мобов: заголовок с
-- градиентом по редкости, две строки статов сверху и разбор в описании.
local function showCrystal(entry)
	clearPreview()
	revealPreviewDetails()
	local info = Config.Geodes.Ores[entry.OreId]
	if not info then return end
	local collectionKey = entry.Key or CollectionKey.Make(entry.OreId, entry.Mutations)
	local mutations = entry.Mutations or {}
	local mutationMultiplier = CollectionKey.Multiplier(collectionKey)
	local mutationNames = {}
	for _, mutationId in mutations do
		local mutationInfo = Config.Mutations[mutationId]
		if mutationInfo then table.insert(mutationNames, mutationInfo.DisplayName) end
	end

	setTitleGradient(info.Rarity)
	previewName.Text = ("<font color=\"%s\">%s</font>"):format(colorHex(info.Color), CollectionKey.DisplayName(collectionKey))
	rightPage.StatsRow.Visible = true
	-- Считаем ТОЙ ЖЕ формулой, что и сервер (см. OreIncome.lua): доход
	-- зависит от тиров самого игрока, а info.IncomePerMinute — только
	-- плоская часть ставки. Раньше здесь была своя, третья по счёту копия
	-- расчёта, и она уже расходилась с сервером на множителе уровня.
	local income = OreIncome.PerMinuteForPlayer(player, collectionKey, entry.Level or 1)
	priceLabel.Text = "INCOME: $" .. NumberFormat.perSecond(income) .. "/SEC"

	-- ОТКУДА ПАДАЕТ И С КАКИМ ШАНСОМ.
		-- Жеода: сперва должна вообще выпасть руда (а не деньги или скин),
	-- потом из трёх руд этого типа равновероятно берётся одна.
	-- Валун: Config.Boulders.RewardOdds.Crystal за каждый разбитый валун
	-- своего тира.
	local sourceLine, chanceText
	if entry.Source == "Geode" then
		local cfg = Config.Geodes.Types[entry.GeodeType]
		-- v18: шанс — из shared/DropTables (то же, что роллит сервер).
		local perOre = 0
		local dropTable = require(ReplicatedStorage.Shared.DropTables).Geode(entry.GeodeType)
		for _, row in dropTable and dropTable.Rows or {} do
			if row.Kind == "Crystal" and row.OreId == entry.OreId then perOre = row.Chance end
		end
		chanceText = ("%.1f%%"):format(perOre * 100)
		sourceLine = ("%s (TIER %d MINE)"):format(cfg.DisplayName:upper(), entry.Tier)
	else
		chanceText = ("%.1f%%"):format((Config.Boulders.RewardOdds.Crystal or 0) * 100)
		sourceLine = ("TIER %d BOULDER"):format(entry.Tier)
	end
	if #mutations > 0 then
		local mutationChance = 1
		for _, mutationId in mutations do
			local mutationInfo = Config.Mutations[mutationId]
			if mutationInfo then mutationChance *= mutationInfo.Chance end
		end
		chanceText ..= " + " .. ("%.2f%% MUTATION"):format(mutationChance * 100)
	end
	chanceLabel.Text = "CHANCE: " .. chanceText

	-- Сколько даёт на максимальном уровне ячейки — руда усиливается копиями.
	local maxLevelIncome = income * (1 + (Config.Geodes.MaxOreLevel - 1) * Config.Geodes.IncomePerLevel)

	descriptionLabel.Text = ("SOURCE: <stroke color=\"rgb(0,0,0)\" joins=\"round\" thickness=\"1\"><font color=\"#FFD166\">%s</font></stroke>\nDROP CHANCE: <stroke color=\"rgb(0,0,0)\" joins=\"round\" thickness=\"1\"><font color=\"#9BE1FF\">%s</font></stroke>\nRARITY: <stroke color=\"rgb(0,0,0)\" joins=\"round\" thickness=\"1\"><font color=\"%s\">%s</font></stroke>\nMUTATIONS: <stroke color=\"rgb(0,0,0)\" joins=\"round\" thickness=\"1\"><font color=\"#D6A8FF\">%s</font></stroke>\nMULTIPLIER: <stroke color=\"rgb(0,0,0)\" joins=\"round\" thickness=\"1\"><font color=\"#FFD166\">x%.2f</font></stroke>\nINCOME: <stroke color=\"rgb(0,0,0)\" joins=\"round\" thickness=\"1\"><font color=\"#55E879\">$%s/SEC</font></stroke>\nAT LEVEL %d: <stroke color=\"rgb(0,0,0)\" joins=\"round\" thickness=\"1\"><font color=\"#55E879\">$%s/SEC</font></stroke>\nINSTALL IT ON THE PODIUM TO EARN WHILE AWAY.\nYOU CAN HAND IT TO ANOTHER PLAYER AS A GIFT.\nMUTATED COPIES ARE STORED AS SEPARATE SLOTS."):format(
		sourceLine,
		chanceText,
		colorHex(Config.RarityColors[info.Rarity] or Color3.new(1, 1, 1)), info.Rarity:upper(),
		#mutationNames > 0 and table.concat(mutationNames, " + ") or "NONE",
		mutationMultiplier,
		NumberFormat.perSecond(income),
		Config.Geodes.MaxOreLevel, NumberFormat.perSecond(maxLevelIncome)
	)

	local previewOre = PlaceholderFactory.CollectionOre(entry.OreId)
	for _, mutationId in mutations do
		MutationVisuals.Apply(previewOre, mutationId)
	end
	prepareViewportObject(previewOre)
end

local function clearGrid()
	-- Только ячейки: UIGridLayout и UIPadding прокрутки должны остаться
	-- (раньше отступ под обводку удалялся после первой же перерисовки).
	for _, child in bookScroller:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	bookScroller.CanvasPosition = Vector2.zero
	clearPreview()
end

-- Подпись ячейки — TextLabel "Caption" из шаблона ItemCell (билдер книги);
-- у старых шаблонов без неё создаётся на лету.
local function addCaption(cell, text)
	local label = cell:FindFirstChild("Caption")
	if not label then
		label = Instance.new("TextLabel")
		label.Name = "Caption"
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.new(0.5, 0, 1, -3)
		label.Size = UDim2.new(1, -6, 0, 0)
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.TextSize = 14
		label.TextWrapped = true
		label.BackgroundTransparency = 1
		require(game:GetService("ReplicatedStorage").Shared.UiKit).StyleText(label, "Heading") -- v20: шрифт темы
		label.TextColor3 = Color3.new(1, 1, 1)
		label.ZIndex = cell.ZIndex + 2
		label.Parent = cell
	end
	label.Text = text
end

-- Неподвижное превью модели прямо в ячейке списка. Нужно потому, что
-- рисованных иконок у мутаций и у новых руд нет и не будет: Config.Mutations
-- [id].IconId и ImageId валунных руд стоят в 0, и ячейка получала пустую
-- картинку. Показываем то же, что покажет большая панель справа, только без
-- вращения.
local function addCellPreview(cell, buildModel)
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "CellPreview"
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 0.42) -- чуть выше центра: снизу плашка с названием
	viewport.Size = UDim2.fromScale(0.86, 0.72)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(225, 225, 235)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.LightDirection = Vector3.new(-0.4, -1, -0.6)
	viewport.ZIndex = cell.ZIndex + 1
	viewport.Parent = cell

	local ok, err = pcall(function()
		local world = Instance.new("WorldModel")
		world.Parent = viewport

		local model = buildModel()
		if not model then error("нечего показывать") end
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then descendant.Anchored = true; descendant.CanCollide = false end
		end
		if model:IsA("BasePart") then model.Anchored = true; model.CanCollide = false end
		model.Parent = world
		if model:IsA("Model") and (model.Name:match("^Goblin_") or model.Name == "MobPreview") then
			model:PivotTo(model:GetPivot() * CFrame.Angles(0, math.pi, 0))
		end

		-- Камера смотрит в ЦЕНТР ГАБАРИТОВ, а не в начало координат: пивот у
		-- кристалла бывает в основании, у персонажа — в середине корпуса, и
		-- модель уезжала бы из кадра.
		local center, size
		if model:IsA("Model") then
			local boundsCFrame, boundsSize = model:GetBoundingBox()
			center, size = boundsCFrame.Position, boundsSize
		else
			center, size = model.Position, model.Size
		end
		local extent = math.max(size.X, size.Y, size.Z)
		local distance = math.max(2, extent * 1.6)
		local camera = Instance.new("Camera")
		camera.FieldOfView = 40
		camera.CFrame = CFrame.lookAt(center + Vector3.new(distance * 0.5, distance * 0.35, distance), center)
		camera.Parent = viewport
		viewport.CurrentCamera = camera
	end)
	if not ok then
		viewport:Destroy()
		warn("[CollectionMenu] Превью в ячейке не собралось:", err)
	end
end

-- buildModel необязателен: если он передан, ячейка показывает 3D-превью,
-- иначе — обычную картинку из image.
local function addEntry(order, unlocked, image, caption, callback, buildModel)
	local cell = (unlocked and itemTemplate or lockedTemplate):Clone()
	cell.Name = "Entry" .. order
	cell.LayoutOrder = order
	cell.Visible = true
	cell.Parent = bookScroller
	if unlocked then
		-- Для записей с 3D-моделью оставляем только живое превью, без
		-- дублирующей плоской иконки.
		local cellIcon = cell:FindFirstChild("Icon")
		if cellIcon and cellIcon:IsA("ImageLabel") then
			cellIcon.Image = buildModel and "" or image
		else
			cell.Image = buildModel and "" or image
		end
		if buildModel then addCellPreview(cell, buildModel) end
		addCaption(cell, caption)
		cell.Activated:Connect(function() UiSfx.play(); callback() end)
	end
end

local function renderBook()
	clearGrid()
	local mutStroke = tabMutations:FindFirstChild("SelectionStroke")
	local mobStroke = tabMobs:FindFirstChild("SelectionStroke")
	local crystalStroke = tabCrystals:FindFirstChild("SelectionStroke")
	mutStroke.Thickness = activeTab == "Mutations" and 5 or 2
	mobStroke.Thickness = activeTab == "Mobs" and 5 or 2
	if crystalStroke then crystalStroke.Thickness = activeTab == "Crystals" and 5 or 2 end
	local trophyStroke = tabTrophies:FindFirstChild("SelectionStroke")
	if trophyStroke then trophyStroke.Thickness = activeTab == "Trophies" and 5 or 2 end
	if progressChip then progressChip.Visible = activeTab == "Mutations" end
	if activeTab == "Mutations" then
		-- v9: КНИГА ПО РУДЕ. Строка = руда (сама руда + каждая мутация на
		-- ней). Каждая новая запись — маленькая награда (MutationBookService).
		pageTitle.Text = "ORES"
		local order, found, total = 0, 0, 0
		for _, oreInfo in Config.OreChain do
			local cave = ORE_CAVE[oreInfo.Key]
			if cave then
				local variants = { false }
				for _, mutationId in Config.Mutations.Order do table.insert(variants, mutationId) end
				for _, mutationId in variants do
					order += 1
					total += 1
					local key = mutationId and (oreInfo.Key .. "|" .. mutationId) or oreInfo.Key
					local unlocked = state.OreBook[key] == true
					if unlocked then found += 1 end
					local mutation = mutationId and Config.Mutations[mutationId]
					local caption = mutation and ("%s + %s"):format(oreInfo.DisplayName, mutation.DisplayName) or oreInfo.DisplayName
					addEntry(order, unlocked, mutation and imageUri(mutation.IconId) or imageUri(oreInfo.ImageId), caption, function()
						showOreEntry(oreInfo, mutationId or nil, cave)
					end, function()
						local variant = Config.OreVariants[1]
						local ok, model = pcall(PlaceholderFactory.OreCrystal, oreInfo, variant)
						if not ok then model = PlaceholderFactory.Crystal(cave) end
						if mutationId then MutationVisuals.Apply(model, mutationId) end
						return model
					end)
				end
			end
		end
		if progressLabel then progressLabel.Text = ("%d/%d"):format(found, total) end
	elseif activeTab == "Crystals" then
		pageTitle.Text = "CRYSTALS"
		local order = 0
		for _, baseEntry in CRYSTAL_ENTRIES do
			local variants = { baseEntry }
			local variantKeys = { [baseEntry.OreId] = true }
			for _, mutationId in Config.Mutations.Order do
				local key = CollectionKey.Make(baseEntry.OreId, { mutationId })
				variantKeys[key] = true
				table.insert(variants, {
					OreId = baseEntry.OreId,
					Source = baseEntry.Source,
					GeodeType = baseEntry.GeodeType,
					Tier = baseEntry.Tier,
					Mutations = { mutationId },
				})
			end
			-- Если игрок уже открыл комбинацию из нескольких мутаций, добавляем
			-- её отдельной карточкой тоже. Одиночные варианты выше отображаются
			-- заранее как закрытые слоты, по аналогии с книгой руды.
			for key in state.Crystals do
				local oreId, mutations = CollectionKey.Parse(key)
				if oreId == baseEntry.OreId and #mutations > 1 and not variantKeys[key] then
					variantKeys[key] = true
					table.insert(variants, {
						OreId = baseEntry.OreId,
						Source = baseEntry.Source,
						GeodeType = baseEntry.GeodeType,
						Tier = baseEntry.Tier,
						Mutations = mutations,
					})
				end
			end
			for _, entry in variants do
				order += 1
				local info = Config.Geodes.Ores[entry.OreId]
				local key = CollectionKey.Make(entry.OreId, entry.Mutations)
				entry.Key = key
				local unlocked = state.Crystals[key] == true
				addEntry(order, unlocked, imageUri(info.ImageId), CollectionKey.DisplayName(key), function()
					showCrystal(entry)
				end, function()
					local ore = PlaceholderFactory.CollectionOre(entry.OreId)
					for _, mutationId in entry.Mutations do
						MutationVisuals.Apply(ore, mutationId)
					end
					return ore
				end)
			end
		end
	elseif activeTab == "Trophies" then
		-- v20: ТРОФЕИ — реликвии с валунов и сундуков. Найденные (хоть раз,
		-- даже проданные) открыты, остальные — закрытые «???» ячейки.
		pageTitle.Text = "TROPHIES"
		for order, relicId in Config.Relics.Order do
			local info = Config.Relics.Types[relicId]
			local count = tonumber(player:GetAttribute("RelicFound_" .. relicId)) or 0
			local caption = count > 1 and ("%s x%d"):format(info.DisplayName, count) or info.DisplayName
			addEntry(order, count > 0, "", caption, function()
				showTrophy(relicId)
			end, function()
				return PlaceableFactory.BuildRelic(relicId)
			end)
		end
	else
		pageTitle.Text = "MOBS"
		for order, mobId in {"Warrior", "Thief", "Berserker", "King", "Golden"} do
			local definition = Config.Goblins.Types[mobId]
			addEntry(order, state.Mobs[mobId] == true, Config.Goblins.IconImage or "", definition.DisplayName, function()
				showMob(mobId)
			end, function()
				return makeMobPreview(definition, mobId)
			end)
		end
	end
end

tabMutations.Activated:Connect(function() activeTab = "Mutations"; renderBook() end)
tabMobs.Activated:Connect(function() activeTab = "Mobs"; renderBook() end)
tabCrystals.Activated:Connect(function() UiSfx.play(); activeTab = "Crystals"; renderBook() end)
tabTrophies.Activated:Connect(function() UiSfx.play(); activeTab = "Trophies"; renderBook() end)
for relicId in Config.Relics.Types do
	player:GetAttributeChangedSignal("RelicFound_" .. relicId):Connect(function()
		if activeTab == "Trophies" and panel.Visible then renderBook() end
	end)
end

-- КАКИЕ КРИСТАЛЛЫ УЖЕ НАЙДЕНЫ. Отдельного запроса на сервер не делаем:
-- состояние коллекции и так рассылается через GeodeRequest, и один ответ
-- сервера доходит до ВСЕХ слушателей этого ремоута на клиенте — GeodeUI уже
-- его запрашивает. Мы просто слушаем и достаём базовые руды из ключей ячеек
-- (ключ может быть составным, "Quartz#Rusty" — см. CollectionKey).
do
	local geodeRemote = ReplicatedStorage.Shared:FindFirstChild("GeodeRequest")
	if geodeRemote then
		geodeRemote.OnClientEvent:Connect(function(command, payload, newState)
			local statePayload = command == "State" and payload
				or command == "OpenResult" and newState
				or typeof(command) == "table" and command
			if not statePayload then return end
			if typeof(statePayload) ~= "table" or typeof(statePayload.Collection) ~= "table" then return end
			local found = {}
			for key in statePayload.Collection do
				local oreId = CollectionKey.BaseOre(key)
				if oreId and Config.Geodes.Ores[oreId] then found[key] = true end
			end
			state.Crystals = found
			if activeTab == "Crystals" then renderBook() end
		end)
		geodeRemote:FireServer("RequestState")
	end
end
bookClose.Activated:Connect(function()
	UiSfx.play()
	dimmer.Visible = false
	UiMotion.Close(panel)
	clearPreview()
end)

mutationBookRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then return end
	if payload.Mutations or payload.Mobs then
		state.Mutations = payload.Mutations or {}
		state.Mobs = payload.Mobs or {}
		state.OreBook = payload.OreBook or state.OreBook or {}
	else
		state.Mutations = payload -- backward-compatible state from an older server
	end
	renderBook()
end)
panel.Visible = false
clearPreview()
renderBook()
mutationBookRemote:FireServer("RequestState")
