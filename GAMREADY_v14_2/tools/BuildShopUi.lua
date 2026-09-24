--------------------------------------------------------------------------------
-- Standalone Command Bar builder for StarterGui/ShopUi.
-- Rerunning this script destroys and rebuilds only the ShopUi ScreenGui.
--
-- ПЕРЕДЕЛАНО С НУЛЯ (по прямому запросу — "магазин надо целиком переделать,
-- чтобы не было вкладок, а просто геймпассы категориями которые можно
-- листать ниже", + приложенный референс "Prospector's Shop" + отдельный
-- стайл-гайд на весь Roblox UI игры, см. сообщение целиком):
--   • БЫЛО: вкладки (Passes/Deals) + пагинация (Prev/Next, 6 карточек на
--     страницу).
--   • СТАЛО: ОДНА вертикально прокручиваемая страница — каждая категория
--     (Config.Shop.Tabs) это отдельная СЕКЦИЯ с заголовком, внутри неё все
--     товары этой категории сеткой (UIGridLayout, сам переносит строки),
--     без ограничения "N карточек на экран" — сколько товаров, столько и
--     карточек, секция просто растягивается по высоте.
--
-- СТИЛЬ (см. присланный стайл-гайд целиком): тёмные полупрозрачные панели,
-- ПРЯМОУГОЛЬНЫЕ формы (скругление 0–4px, не большие пилюли), тонкие рамки
-- вместо теней, цвет = функция (жёлтый — кнопка/действие/награда, зелёный —
-- прогресс/успех, красный — закрытие/отмена, синий — заголовки/рамки/общая
-- информация, фиолетовый/золотой — ТОЛЬКО редкость предмета). Фиолетовый
-- заголовок/лента — это конкретно брендинг ИЗ РЕФЕРЕНСА "Prospector's
-- Shop" (сознательное исключение, не нарушение правила: это "особая",
-- узнаваемая вывеska магазина, а не рядовой текст).
--------------------------------------------------------------------------------

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

Config.Shop = Config.Shop or {}
Config.Shop.Tabs = Config.Shop.Tabs or { "Passes", "Deals" }
Config.Icons = Config.Icons or {}

local IMAGES = {
	CommonCloseButton = Config.UI and Config.UI.CloseButtonImageId or 0,
	ShopPanelBg = 0,
	ShopHeaderBg = 0,
	ShopHeaderIcon = 0,
	ShopCloseButton = 0,
	PriceButtonBg = 0,
	RobuxIcon = Config.Icons.Robux or 0,
}

-- Показывается ТОЛЬКО на заголовке секции (косметика) — ключ категории в
-- Config.Shop.Items/PreferredTab остаётся "Deals" как и был, трогать его
-- везде по кодовой базе (RebirthService/UpgradeService/NotifyService) —
-- лишний риск ради надписи. См. референс "Prospector's Shop" — там эта
-- категория называется "Products".
-- Подписи и градиенты секций живут в Config (см. Config.Shop
-- .TabDisplayNames/.TabGradients) — чтобы добавить категорию, достаточно
-- дописать её туда, здесь ничего менять не нужно.
local TAB_DISPLAY_NAMES = Config.Shop.TabDisplayNames or {}
local TAB_GRADIENTS = Config.Shop.TabGradients or {}

local function imageUri(id)
	return id and id ~= 0 and ("rbxassetid://" .. tostring(id)) or ""
end

local function applyImage(instance, id)
	if not id or id == 0 then
		return
	end
	instance.Image = imageUri(id)
	instance.ScaleType = Enum.ScaleType.Stretch
	instance.BackgroundTransparency = 1
end

local function addCorner(inst, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0, 4) -- 0–4px по стайл-гайду — НЕ большие скругления
	c.Parent = inst
	return c
end

local function addStroke(inst, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 1 -- тонкие рамки, не тяжёлые тени — по стайл-гайду
	s.Parent = inst
	return s
end

local function addCaption(button, text)
	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.Size = UDim2.fromScale(1, 1)
	caption.BackgroundTransparency = 1
	caption.Font = Enum.Font.FredokaOne
	caption.TextScaled = true
	caption.TextColor3 = Color3.new(1, 1, 1)
	caption.Text = text
	caption.ZIndex = 2
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = caption
	caption.Parent = button
	return caption
end

local existing = StarterGui:FindFirstChild("ShopUi")
if existing and existing:IsA("ScreenGui") then
	existing:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ShopUi"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 25
screenGui.Parent = StarterGui

--------------------------------------------------------------------------------
-- ЦВЕТА — функциональные, по стайл-гайду.
--------------------------------------------------------------------------------
local PANEL_COLOR = Color3.fromRGB(18, 17, 23)
local SECTION_HEADER_COLOR = Color3.fromRGB(110, 175, 255) -- синий — заголовки/общая информация
local FRAME_COLOR = Color3.fromRGB(70, 75, 90) -- нейтральная тонкая рамка карточек по умолчанию
local ACTION_COLOR = Color3.fromRGB(230, 185, 60) -- жёлтый — кнопки/цена/действие
local CLOSE_COLOR = Color3.fromRGB(220, 70, 70) -- красный — закрытие/отмена
local RARITY_COLOR = { GamePass = Color3.fromRGB(175, 110, 235), DevProduct = Color3.fromRGB(220, 175, 70) } -- фиолетовый/золотой — ТОЛЬКО редкость/тип товара, не общее украшение

local dimmer = Instance.new("TextButton")
dimmer.Name = "Dimmer"
dimmer.Size = UDim2.fromScale(1, 1)
dimmer.BackgroundColor3 = Color3.new(0, 0, 0)
dimmer.BackgroundTransparency = 0.45
dimmer.Text = ""
dimmer.AutoButtonColor = false
dimmer.Visible = false
dimmer.ZIndex = 1
dimmer.Parent = screenGui

local panel = Instance.new("ImageLabel")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(760, 560)
panel.BackgroundColor3 = PANEL_COLOR
panel.BackgroundTransparency = 0.1 -- слегка полупрозрачная — по стайл-гайду "через панель слегка виден игровой мир"
panel.BorderSizePixel = 0
panel.Visible = false
panel.ZIndex = 2
panel.Parent = screenGui
applyImage(panel, IMAGES.ShopPanelBg)
addCorner(panel, UDim.new(0, 4))
addStroke(panel, Color3.fromRGB(150, 100, 210), 1) -- тонкая фиолетовая рамка — брендинг "Prospector's Shop"

--------------------------------------------------------------------------------
-- ШАПКА
--------------------------------------------------------------------------------
local header = Instance.new("ImageLabel")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 56)
header.BackgroundColor3 = Color3.fromRGB(12, 11, 16)
header.BorderSizePixel = 0
header.ZIndex = 3
header.Parent = panel
applyImage(header, IMAGES.ShopHeaderBg)
addCorner(header, UDim.new(0, 4))

local headerPatch = Instance.new("Frame")
headerPatch.Name = "CornerPatch"
headerPatch.AnchorPoint = Vector2.new(0, 1)
headerPatch.Position = UDim2.new(0, 0, 1, 0)
headerPatch.Size = UDim2.new(1, 0, 0, 16)
headerPatch.BackgroundColor3 = header.BackgroundColor3
headerPatch.BorderSizePixel = 0
headerPatch.ZIndex = 3
headerPatch.Parent = header

local title = Instance.new("TextLabel")
title.Name = "Title"
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.new(0.5, 0, 0.5, 0)
title.Size = UDim2.new(0, 320, 0.7, 0)
title.BackgroundTransparency = 1
title.Font = Enum.Font.FredokaOne
title.TextScaled = true
title.TextXAlignment = Enum.TextXAlignment.Center
title.TextColor3 = Color3.new(1, 1, 1)
title.TextStrokeTransparency = 0.4
title.TextStrokeColor3 = Color3.fromRGB(40, 10, 60)
title.Text = "Prospector's Shop"
title.ZIndex = 4
title.Parent = header
local titleGradient = Instance.new("UIGradient")
titleGradient.Rotation = 90
titleGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(225, 190, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(165, 100, 235)),
})
titleGradient.Parent = title

local ribbonIcon = Instance.new("ImageLabel")
ribbonIcon.Name = "BasketIcon"
ribbonIcon.AnchorPoint = Vector2.new(0, 0.5)
ribbonIcon.Position = UDim2.new(0, 14, 0.5, 0)
ribbonIcon.Size = UDim2.fromOffset(24, 38)
ribbonIcon.BackgroundColor3 = Color3.fromRGB(190, 130, 245)
ribbonIcon.BorderSizePixel = 0
ribbonIcon.Image = imageUri(IMAGES.ShopHeaderIcon)
ribbonIcon.ScaleType = Enum.ScaleType.Fit
ribbonIcon.ZIndex = 4
ribbonIcon.Parent = header
for _, xOffset in { -1, 1 } do
	local notch = Instance.new("Frame")
	notch.AnchorPoint = Vector2.new(0.5, 0)
	notch.Position = UDim2.new(0.5, xOffset * 6.5, 1, -6)
	notch.Size = UDim2.fromOffset(10, 10)
	notch.Rotation = 45
	notch.BackgroundColor3 = header.BackgroundColor3
	notch.BorderSizePixel = 0
	notch.ZIndex = 5
	notch.Parent = ribbonIcon
end

local closeButton = Instance.new("ImageButton")
closeButton.Name = "CloseButton"
closeButton.AnchorPoint = Vector2.new(1, 0.5)
closeButton.Position = UDim2.new(1, -12, 0.5, 0)
closeButton.Size = UDim2.fromOffset(30, 30)
closeButton.BackgroundTransparency = 1
closeButton.AutoButtonColor = false
closeButton.ZIndex = 4
closeButton.Parent = header
local closeCaption = addCaption(closeButton, "X")
closeCaption.TextColor3 = CLOSE_COLOR
closeCaption.Font = Enum.Font.GothamBlack
local closeImageId = IMAGES.ShopCloseButton ~= 0 and IMAGES.ShopCloseButton or IMAGES.CommonCloseButton
applyImage(closeButton, closeImageId)
if closeImageId ~= 0 then
	closeButton.ScaleType = Enum.ScaleType.Fit
	closeButton.Caption.Visible = false
end

--------------------------------------------------------------------------------
-- ТЕЛО — ОДНА вертикально прокручиваемая колонка секций (без вкладок).
--------------------------------------------------------------------------------
local body = Instance.new("ScrollingFrame")
body.Name = "Body"
body.Position = UDim2.new(0, 16, 0, 66)
body.Size = UDim2.new(1, -32, 1, -82)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 6
body.ScrollBarImageColor3 = Color3.fromRGB(150, 100, 210)
body.CanvasSize = UDim2.new(0, 0, 0, 0)
body.AutomaticCanvasSize = Enum.AutomaticSize.Y
body.ZIndex = 2
body.Parent = panel

local bodyLayout = Instance.new("UIListLayout")
bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
-- Промежуток между отделами был 18 px, и вместе с подложкой (которая
-- ещё и на 12 px выше содержимого) отделы визуально разъезжались. 6 px
-- достаточно, чтобы границу было видно, и меню перестаёт выглядеть
-- разорванным на куски.
bodyLayout.Padding = UDim.new(0, 6)
bodyLayout.Parent = body

-- КАРТОЧКА-ШАБЛОН — Visible = false, никогда не показывается сама по
-- себе. Клиент (CustomCartUI.client.lua/renderShop) клонирует её В КАЖДУЮ
-- секцию под каждый товар — ровно тот же приём, что и у QuestRowTemplate
-- в tools/BuildQuestUI.lua. Раньше билдер строил 6 ПУСТЫХ слотов НА
-- ВКЛАДКУ заранее (под пагинацию) — без пагинации в этом больше нет
-- смысла: карточек ровно столько, сколько реальных товаров.
local cardTemplate = Instance.new("ImageLabel")
cardTemplate.Name = "CardTemplate"
cardTemplate.Size = UDim2.fromOffset(216, 148)
cardTemplate.BackgroundColor3 = Color3.fromRGB(30, 28, 38)
cardTemplate.BorderSizePixel = 0
cardTemplate.Visible = false
cardTemplate.ZIndex = 2
cardTemplate.Parent = screenGui
addCorner(cardTemplate, UDim.new(0, 4))
local cardStroke = addStroke(cardTemplate, FRAME_COLOR, 1)
cardStroke.Name = "AccentStroke"

local placeholderIcon = Instance.new("ImageLabel")
placeholderIcon.Name = "PlaceholderIcon"
placeholderIcon.AnchorPoint = Vector2.new(0.5, 0)
placeholderIcon.Position = UDim2.new(0.5, 0, 0, 8)
placeholderIcon.Size = UDim2.new(1, -16, 0.5, 0)
placeholderIcon.BackgroundColor3 = Color3.fromRGB(14, 13, 18)
placeholderIcon.BackgroundTransparency = 0.1
placeholderIcon.Image = ""
placeholderIcon.ScaleType = Enum.ScaleType.Fit
placeholderIcon.ZIndex = 2
placeholderIcon.Parent = cardTemplate
addCorner(placeholderIcon, UDim.new(0, 4))

local badge = Instance.new("TextLabel")
badge.Name = "Badge"
badge.AnchorPoint = Vector2.new(0, 0)
badge.Position = UDim2.new(0, 4, 0, 4)
badge.Size = UDim2.fromOffset(48, 18)
badge.BackgroundColor3 = CLOSE_COLOR
badge.Font = Enum.Font.FredokaOne
badge.TextScaled = true
badge.TextColor3 = Color3.new(1, 1, 1)
badge.Text = "NEW"
badge.Visible = false
badge.ZIndex = 3
badge.Parent = cardTemplate
addCorner(badge, UDim.new(0, 3))

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.AnchorPoint = Vector2.new(0.5, 0)
titleLabel.Position = UDim2.new(0.5, 0, 0.56, 0)
titleLabel.Size = UDim2.new(1, -10, 0.2, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.FredokaOne
titleLabel.TextScaled = true
titleLabel.TextColor3 = Color3.new(1, 1, 1)
titleLabel.Text = ""
titleLabel.ZIndex = 2
titleLabel.Parent = cardTemplate

local priceButton = Instance.new("ImageButton")
priceButton.Name = "PriceButton"
priceButton.AnchorPoint = Vector2.new(0.5, 1)
priceButton.Position = UDim2.new(0.5, 0, 1, -6)
priceButton.Size = UDim2.new(1, -16, 0.22, 0)
priceButton.BackgroundColor3 = ACTION_COLOR -- жёлтый — действие/покупка, по стайл-гайду (было зелёным)
priceButton.AutoButtonColor = false
priceButton.ZIndex = 2
priceButton.Parent = cardTemplate
addCorner(priceButton, UDim.new(0, 4))
applyImage(priceButton, IMAGES.PriceButtonBg)
local priceCaption = addCaption(priceButton, "")
priceCaption.TextColor3 = Color3.fromRGB(35, 28, 10)
priceCaption.ZIndex = 3
priceCaption.Position = UDim2.new(0, 28, 0, 0)
priceCaption.Size = UDim2.new(1, -34, 1, 0)

local robuxIcon = Instance.new("ImageLabel")
robuxIcon.Name = "RobuxIcon"
robuxIcon.AnchorPoint = Vector2.new(0, 0.5)
robuxIcon.Position = UDim2.new(0, 8, 0.5, 0)
robuxIcon.Size = UDim2.fromOffset(18, 18)
robuxIcon.BackgroundTransparency = 1
robuxIcon.Image = imageUri(IMAGES.RobuxIcon)
robuxIcon.ScaleType = Enum.ScaleType.Fit
robuxIcon.ZIndex = 3
robuxIcon.Parent = priceButton

--------------------------------------------------------------------------------
-- СЕКЦИИ — одна на каждую категорию (Config.Shop.Tabs), пустая сетка
-- карточек внутри (клиент наполняет клонами CardTemplate). Порядок сверху
-- вниз = порядок Config.Shop.Tabs.
--------------------------------------------------------------------------------
for i, tabName in Config.Shop.Tabs do
	local section = Instance.new("Frame")
	section.Name = "Section_" .. tabName
	section.LayoutOrder = i
	section.Size = UDim2.new(1, 0, 0, 0)
	section.AutomaticSize = Enum.AutomaticSize.Y
	section.BackgroundTransparency = 1
	section.Parent = body

	local sectionLayout = Instance.new("UIListLayout")
	sectionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	sectionLayout.Padding = UDim.new(0, 4)
	sectionLayout.Parent = section

	-- ГРАДИЕНТНАЯ ПОДЛОЖКА СЕКЦИИ (по прямому запросу — у каждой панели
	-- свой цвет). Лежит ПОЗАДИ содержимого (ZIndex 0) и растягивается по
	-- высоте вместе с секцией, потому что сама секция AutomaticSize.Y.
	local gradientInfo = TAB_GRADIENTS[tabName]
	if gradientInfo then
		local backdrop = Instance.new("Frame")
		backdrop.Name = "Backdrop"
		backdrop.AnchorPoint = Vector2.new(0.5, 0)
		backdrop.Position = UDim2.new(0.5, 0, 0, 0)
		backdrop.Size = UDim2.new(1, 12, 1, 4) -- было (1,16,1,12): лишняя высота подложки и создавала ощущение большого разрыва
		backdrop.BackgroundColor3 = Color3.new(1, 1, 1)
		backdrop.BackgroundTransparency = 0.55
		backdrop.BorderSizePixel = 0
		backdrop.ZIndex = 0
		backdrop.Parent = section
		addCorner(backdrop, UDim.new(0, 4))
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Color = ColorSequence.new(gradientInfo.From, gradientInfo.To)
		gradient.Parent = backdrop
	end

	local sectionHeader = Instance.new("TextLabel")
	sectionHeader.Name = "SectionHeader"
	sectionHeader.LayoutOrder = 1
	sectionHeader.Size = UDim2.new(1, 0, 0, 22)
	sectionHeader.BackgroundTransparency = 1
	sectionHeader.Font = Enum.Font.FredokaOne
	sectionHeader.TextScaled = true
	sectionHeader.TextXAlignment = Enum.TextXAlignment.Left
	sectionHeader.TextColor3 = gradientInfo and gradientInfo.From:Lerp(Color3.new(1, 1, 1), 0.55) or SECTION_HEADER_COLOR
	sectionHeader.TextStrokeTransparency = 0.5
	sectionHeader.Text = TAB_DISPLAY_NAMES[tabName] or tabName
	sectionHeader.Parent = section

	local sectionUnderline = Instance.new("Frame")
	sectionUnderline.Name = "Underline"
	sectionUnderline.LayoutOrder = 2
	sectionUnderline.Size = UDim2.new(1, 0, 0, 1)
	sectionUnderline.BackgroundColor3 = gradientInfo and gradientInfo.From:Lerp(Color3.new(1, 1, 1), 0.4) or SECTION_HEADER_COLOR
	sectionUnderline.BackgroundTransparency = 0.5
	sectionUnderline.BorderSizePixel = 0
	sectionUnderline.Parent = section

	-- "Cards_<Tab>" — имя контракта СОХРАНЕНО от старой версии специально:
	-- клиентский код ищет контейнер именно по этому имени, менять не
	-- нужно, поменялось только то, ЧТО внутри (сетка без фиксированных
	-- слотов вместо CardSlot1..6).
	local cardsContainer = Instance.new("Frame")
	cardsContainer.Name = "Cards_" .. tabName
	cardsContainer.LayoutOrder = 3
	cardsContainer.Size = UDim2.new(1, 0, 0, 0)
	cardsContainer.AutomaticSize = Enum.AutomaticSize.Y
	cardsContainer.BackgroundTransparency = 1
	cardsContainer.Parent = section

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(216, 148)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = cardsContainer
end

print("[BuildShopUi] Done: ShopUi (sectioned, no tabs) created in StarterGui.")
