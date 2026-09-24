--------------------------------------------------------------------------------
-- BuildQuestUI — ОКНО КВЕСТОВ (v2, стиль общий с престижем и магазином).
--
-- ЧТО ИЗМЕНИЛОСЬ И ЗАЧЕМ. Прошлая версия была нарисована в собственной
-- палитре — синий акцент (90,170,255), серо-чёрная панель (20,20,26),
-- шрифт Arcade — и выглядела как элемент из другой игры рядом с окном
-- престижа, деревом перков и магазином улучшений, которые все собраны в
-- одной схеме: тёмно-индиговая панель, золотая вкладка-заголовок,
-- FredokaOne. Здесь ровно та же схема и те же токены, что в
-- src/shared/PrestigeUiBuilder.lua.
--
-- КОНТРАКТ ИМЁН НЕ ТРОНУТ. QuestUI.client.lua ищет элементы по именам
-- (QuestToggleButton/Badge, Dimmer, QuestModal → Background, Title,
-- CloseButton, SectionLabel, List → QuestRowTemplate, PinnedTracker), а
-- строка внутри шаблона обязана содержать Icon, PinButton → Checkmark,
-- Body → Title / Description / ProgressBarBackground → ProgressBarFill /
-- Progress / Reward. Переименование любого из них молча сломает
-- заполнение строки — менялось только оформление.
--
-- ДИНАМИЧЕСКИЙ ТЕКСТ ОСТАЁТСЯ TextLabel (заголовок, описание, прогресс,
-- награда), всё остальное — ImageLabel/Frame. RichText = true обязателен у
-- описания: подсветка чисел идёт тегами <font color=...> (см.
-- highlightQuestText в клиенте), без него они печатались бы как есть.
--
-- ЗАПУСК: Rojo-синк → Command Bar в Studio → вставить файл целиком → Enter.
-- Безопасно перезапускается, но пересоздаёт StarterGui/QuestUi с нуля.
--------------------------------------------------------------------------------

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local existing = StarterGui:FindFirstChild("QuestUi")
if existing then existing:Destroy() end

--------------------------------------------------------------------------------
-- ТОКЕНЫ — один в один с PrestigeUiBuilder. Держим их здесь копией, а не
-- require'им оттуда, намеренно: файл запускается из Command Bar как
-- самостоятельный скрипт и обязан работать, даже если shared-модули в этот
-- момент ещё не синхронизированы Rojo.
--------------------------------------------------------------------------------
local INK = Color3.fromRGB(10, 8, 24)
local NIGHT = Color3.fromRGB(30, 22, 64)
local NIGHT_DEEP = Color3.fromRGB(18, 13, 42)
local ROW_BG = Color3.fromRGB(24, 18, 54)
local GOLD = Color3.fromRGB(255, 200, 70)
local GOLD_TEXT = Color3.fromRGB(255, 220, 110)
local GREEN = Color3.fromRGB(70, 195, 100)
local MUTED = Color3.fromRGB(168, 162, 200)

local function corner(parent, radius)
	local item = Instance.new("UICorner")
	item.CornerRadius = UDim.new(0, radius or 12)
	item.Parent = parent
	return item
end

local function stroke(parent, thickness, color, contextual)
	local item = Instance.new("UIStroke")
	item.Name = "Outline"
	item.Thickness = thickness or 2
	item.Color = color or GOLD
	item.ApplyStrokeMode = contextual and Enum.ApplyStrokeMode.Contextual or Enum.ApplyStrokeMode.Border
	item.Parent = parent
	return item
end

local function label(name, text, size, position, textSize, options)
	options = options or {}
	local item = Instance.new("TextLabel")
	item.Name = name
	item.Size = size
	item.Position = position
	item.BackgroundTransparency = 1
	item.Font = options.Font or Enum.Font.FredokaOne
	item.Text = text
	item.TextColor3 = options.Color or Color3.new(1, 1, 1)
	item.TextSize = textSize
	item.TextWrapped = options.Wrapped ~= false
	item.TextXAlignment = options.Align or Enum.TextXAlignment.Left
	item.RichText = options.RichText == true
	if options.Stroke ~= false then stroke(item, 2, INK, true) end
	return item
end

local gui = Instance.new("ScreenGui")
gui.Name = "QuestUi"
gui.ResetOnSpawn = false -- респавн в игре ручной (CharacterAutoLoads = false); с true окно умирало бы на каждой смерти
gui.IgnoreGuiInset = false
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
gui.DisplayOrder = 24
gui.Parent = StarterGui

--------------------------------------------------------------------------------
-- 1) КНОПКА В ТОПБАРЕ
--
-- Position — ЗАГОТОВКА: клиент переставляет кнопку по формуле «сразу после
-- иконок Roblox» (см. positionToggleButton). Подвинешь её в Studio сам —
-- код это уважит и трогать не станет.
--------------------------------------------------------------------------------
local toggleButton = Instance.new("ImageButton")
toggleButton.Name = "QuestToggleButton"
toggleButton.Position = UDim2.fromOffset(0, 0)
toggleButton.Size = UDim2.fromOffset(36, 36)
toggleButton.BackgroundColor3 = NIGHT
toggleButton.Image = "" -- своя иконка свитка сюда, необязательно
toggleButton.Parent = gui
corner(toggleButton, 18)
stroke(toggleButton, 2, GOLD)

local toggleIcon = Instance.new("ImageLabel")
toggleIcon.Name = "Icon"
toggleIcon.AnchorPoint = Vector2.new(0.5, 0.5)
toggleIcon.Position = UDim2.fromScale(0.5, 0.5)
toggleIcon.Size = UDim2.fromScale(0.6, 0.6)
toggleIcon.BackgroundTransparency = 1
toggleIcon.Image = ""
toggleIcon.ScaleType = Enum.ScaleType.Fit
toggleIcon.Parent = toggleButton

-- Точка «есть новое» — как уведомление у иконки чата в Roblox.
local toggleBadge = Instance.new("ImageLabel")
toggleBadge.Name = "Badge"
toggleBadge.AnchorPoint = Vector2.new(1, 0)
toggleBadge.Position = UDim2.new(1, 4, 0, -4)
toggleBadge.Size = UDim2.fromOffset(14, 14)
toggleBadge.BackgroundColor3 = GOLD
toggleBadge.Image = ""
toggleBadge.Visible = false
toggleBadge.Parent = toggleButton
corner(toggleBadge, 7)

--------------------------------------------------------------------------------
-- 2) ОКНО СПИСКА
--------------------------------------------------------------------------------
local MODAL_WIDTH, MODAL_HEIGHT = 460, 560

-- Затемнение — ОТДЕЛЬНЫЙ элемент вне modal, чтобы окно можно было
-- анимировать (scale/fade) независимо от фона.
local dimmer = Instance.new("ImageButton") -- кнопка, а не Frame: клик мимо окна закрывает его
dimmer.Name = "Dimmer"
dimmer.Size = UDim2.fromScale(1, 1)
dimmer.BackgroundColor3 = Color3.new(0, 0, 0)
dimmer.BackgroundTransparency = 1
dimmer.Image = ""
dimmer.AutoButtonColor = false
dimmer.Visible = false
dimmer.ZIndex = 1
dimmer.Parent = gui

local modal = Instance.new("Frame")
modal.Name = "QuestModal"
modal.AnchorPoint = Vector2.new(0.5, 0.5)
modal.Position = UDim2.fromScale(0.5, 0.5)
modal.Size = UDim2.fromOffset(MODAL_WIDTH, MODAL_HEIGHT)
modal.BackgroundTransparency = 1
modal.Visible = false
modal.ZIndex = 2
modal.Parent = gui

local modalBackground = Instance.new("ImageLabel")
modalBackground.Name = "Background"
modalBackground.Size = UDim2.fromScale(1, 1)
modalBackground.BackgroundColor3 = NIGHT_DEEP
modalBackground.BackgroundTransparency = 0.02
modalBackground.BorderSizePixel = 0
modalBackground.Image = ""
modalBackground.ZIndex = 2
modalBackground.Parent = modal
corner(modalBackground, 16)
stroke(modalBackground, 3, GOLD)

-- ЗОЛОТАЯ ВКЛАДКА-ЗАГОЛОВОК — тот же элемент, что и «⭐ PRESTIGE» в окне
-- престижа: выступает над верхним краем панели.
local tab = Instance.new("Frame")
tab.Name = "Tab"
tab.AnchorPoint = Vector2.new(0.5, 1)
tab.Position = UDim2.new(0.5, 0, 0, 6)
tab.Size = UDim2.fromOffset(196, 42)
tab.BackgroundColor3 = GOLD
tab.BorderSizePixel = 0
tab.ZIndex = 4
tab.Parent = modal
corner(tab, 12)
stroke(tab, 3, INK)

local titleLabel = label("Title", "QUESTS", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 24, {
	Color = INK,
	Align = Enum.TextXAlignment.Center,
	Stroke = false,
})
titleLabel.ZIndex = 5
titleLabel.Parent = tab

local closeButton = Instance.new("ImageButton")
closeButton.Name = "CloseButton"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -10, 0, 10)
closeButton.Size = UDim2.fromOffset(34, 34)
closeButton.BackgroundColor3 = NIGHT
closeButton.Image = ""
closeButton.ZIndex = 5
closeButton.Parent = modal
corner(closeButton, 17)
stroke(closeButton, 2, GOLD)

local closeIcon = Instance.new("ImageLabel")
closeIcon.Name = "Icon"
closeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
closeIcon.Position = UDim2.fromScale(0.5, 0.5)
closeIcon.Size = UDim2.fromScale(0.5, 0.5)
closeIcon.BackgroundTransparency = 1
closeIcon.Image = ""
closeIcon.ZIndex = 6
closeIcon.Parent = closeButton
-- Крестик геометрией, а не текстовым символом: рендерится одинаково при
-- любом шрифте и локали (тот же приём, что и у галочки ниже).
for _, rotation in { 45, -45 } do
	local bar = Instance.new("Frame")
	bar.Name = "Stroke"
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.fromScale(0.5, 0.5)
	bar.Size = UDim2.fromOffset(16, 3)
	bar.Rotation = rotation
	bar.BackgroundColor3 = GOLD
	bar.BorderSizePixel = 0
	bar.ZIndex = 7
	bar.Parent = closeIcon
	corner(bar, 2)
end

local sectionLabel = label("SectionLabel", "MAIN QUESTS", UDim2.new(1, -32, 0, 22), UDim2.fromOffset(18, 48), 16, {
	Color = GOLD_TEXT,
})
sectionLabel.ZIndex = 4
sectionLabel.Parent = modal

local sectionUnderline = Instance.new("Frame")
sectionUnderline.Name = "Underline"
sectionUnderline.Position = UDim2.fromOffset(18, 72)
sectionUnderline.Size = UDim2.new(1, -36, 0, 2)
sectionUnderline.BackgroundColor3 = GOLD
sectionUnderline.BackgroundTransparency = 0.55
sectionUnderline.BorderSizePixel = 0
sectionUnderline.ZIndex = 4
sectionUnderline.Parent = modal

local list = Instance.new("ScrollingFrame")
list.Name = "List"
list.Position = UDim2.fromOffset(14, 84)
list.Size = UDim2.new(1, -28, 1, -98)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 5
list.ScrollBarImageColor3 = GOLD
list.CanvasSize = UDim2.new(0, 0, 0, 0)
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ZIndex = 4
list.Parent = modal

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 8)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = list

--------------------------------------------------------------------------------
-- 3) ШАБЛОН СТРОКИ КВЕСТА
--
-- Visible = false — сам никогда не показывается, клиент клонирует его на
-- каждый активный квест. Этот же шаблон используется и для закреплённой
-- плашки (PinnedTracker ниже), поэтому строка обязана читаться и внутри
-- окна, и поверх игрового экрана — отсюда контрастная подложка с обводкой,
-- а не полупрозрачный чёрный прямоугольник, как было раньше.
--------------------------------------------------------------------------------
local function buildQuestRow(parent, rowHeight, zIndex)
	local row = Instance.new("Frame")
	row.Name = "QuestRowTemplate"
	row.Size = UDim2.new(1, 0, 0, rowHeight)
	row.BackgroundTransparency = 1
	row.Visible = false
	row.ZIndex = zIndex
	row.Parent = parent

	local background = Instance.new("ImageLabel")
	background.Name = "Background"
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = ROW_BG
	background.BackgroundTransparency = 0.1
	background.BorderSizePixel = 0
	background.Image = ""
	background.ZIndex = zIndex
	background.Parent = row
	corner(background, 10)
	stroke(background, 2, Color3.fromRGB(58, 46, 104))

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 10, 0.5, 0)
	icon.Size = UDim2.fromOffset(30, 30)
	icon.BackgroundColor3 = GOLD
	icon.BorderSizePixel = 0
	icon.Image = (Config.Quests.IconId and Config.Quests.IconId ~= 0)
		and ("rbxassetid://" .. tostring(Config.Quests.IconId)) or ""
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = zIndex + 1
	icon.Parent = row
	corner(icon, 8)

	--------------------------------------------------------------------------
	-- ЧЕКБОКС «ЗАКРЕПИТЬ». Квадрат с галочкой, а не кружок, меняющий цвет:
	-- прошлый вариант переключался корректно, но на глаз это было
	-- невидно — отсюда и жалобы «повторное нажатие не открепляет».
	-- Галочка собрана из двух полосок, а не текстовым символом: часть
	-- шрифтов его не содержит, и он молча не рисовался.
	--------------------------------------------------------------------------
	local pinButton = Instance.new("ImageButton")
	pinButton.Name = "PinButton"
	pinButton.AnchorPoint = Vector2.new(1, 0.5)
	pinButton.Position = UDim2.new(1, -10, 0.5, 0)
	pinButton.Size = UDim2.fromOffset(28, 28)
	pinButton.BackgroundColor3 = NIGHT
	pinButton.Image = ""
	pinButton.Active = true
	pinButton.ZIndex = zIndex + 2
	pinButton.Parent = row
	corner(pinButton, 6)
	stroke(pinButton, 2, GOLD)

	local checkmark = Instance.new("Frame")
	checkmark.Name = "Checkmark"
	checkmark.Size = UDim2.fromScale(1, 1)
	checkmark.BackgroundTransparency = 1
	checkmark.Visible = false -- клиент включает при закреплении (см. fillRow)
	checkmark.ZIndex = zIndex + 3
	checkmark.Parent = pinButton
	for _, part in {
		{ Position = UDim2.fromScale(0.36, 0.58), Size = UDim2.fromOffset(8, 3), Rotation = 45 },
		{ Position = UDim2.fromScale(0.58, 0.44), Size = UDim2.fromOffset(14, 3), Rotation = -45 },
	} do
		local bar = Instance.new("Frame")
		bar.Name = "Stroke"
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = part.Position
		bar.Size = part.Size
		bar.Rotation = part.Rotation
		bar.BackgroundColor3 = GOLD
		bar.BorderSizePixel = 0
		bar.ZIndex = zIndex + 4
		bar.Parent = checkmark
		corner(bar, 2)
	end

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Position = UDim2.fromOffset(48, 6)
	body.Size = UDim2.new(1, -92, 0, rowHeight - 12)
	body.BackgroundTransparency = 1
	body.ZIndex = zIndex + 1
	body.Parent = row

	local title = label("Title", "QUEST", UDim2.new(1, 0, 0, 19), UDim2.fromOffset(0, 0), 16, {
		Color = Color3.new(1, 1, 1),
		Wrapped = false,
	})
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.ZIndex = zIndex + 2
	title.Parent = body

	local description = label("Description", "", UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 19), 13, {
		Font = Enum.Font.GothamMedium,
		Color = MUTED,
		RichText = true, -- подсветка чисел тегами <font color=...>, см. highlightQuestText
	})
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.ZIndex = zIndex + 2
	description.Parent = body

	local progressBackground = Instance.new("ImageLabel")
	progressBackground.Name = "ProgressBarBackground"
	progressBackground.Position = UDim2.new(0, 0, 1, -9)
	progressBackground.Size = UDim2.new(1, -78, 0, 7)
	progressBackground.BackgroundColor3 = INK
	progressBackground.BorderSizePixel = 0
	progressBackground.Image = ""
	progressBackground.ZIndex = zIndex + 2
	progressBackground.Parent = body
	corner(progressBackground, 4)

	local progressFill = Instance.new("ImageLabel")
	progressFill.Name = "ProgressBarFill"
	progressFill.Size = UDim2.fromScale(0, 1)
	progressFill.BackgroundColor3 = GREEN
	progressFill.BorderSizePixel = 0
	progressFill.Image = ""
	progressFill.ZIndex = zIndex + 3
	progressFill.Parent = progressBackground
	corner(progressFill, 4)

	local progressText = label("Progress", "0 / 1", UDim2.fromOffset(74, 15), UDim2.new(1, -74, 1, -16), 12, {
		Color = GREEN,
		Align = Enum.TextXAlignment.Right,
		Wrapped = false,
	})
	progressText.ZIndex = zIndex + 2
	progressText.Parent = body

	local rewardText = label("Reward", "$0", UDim2.fromOffset(84, 17), UDim2.new(0, 0, 1, -26), 15, {
		Color = GOLD_TEXT,
		Wrapped = false,
	})
	rewardText.ZIndex = zIndex + 2
	rewardText.Parent = body

	return row
end

buildQuestRow(list, 74, 5)

--------------------------------------------------------------------------------
-- 4) ЗАКРЕПЛЁННАЯ ПЛАШКА
--
-- Position — заготовка: клиент подставляет её под реальное положение
-- кнопки-книги (CollectionMenu.BookButton), где бы её ни передвинули.
-- Visible = false и это НЕ шаблон: клиент включает её сам, когда квест
-- закреплён.
--------------------------------------------------------------------------------
local pinnedTracker = buildQuestRow(gui, 74, 3)
pinnedTracker.Name = "PinnedTracker"
pinnedTracker.Size = UDim2.fromOffset(280, 74)
pinnedTracker.Position = UDim2.fromOffset(14, 400)
pinnedTracker.Visible = false

print("[BuildQuestUI] QuestUi пересобран в стиле престижа (золотая вкладка, индиговая панель).")
