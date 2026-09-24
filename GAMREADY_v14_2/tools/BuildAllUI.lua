--------------------------------------------------------------------------------
-- BuildAllUI (v9) — ОДИН скрипт, который собирает ВЕСЬ UI игры: HUD,
-- инвентарь, магазины, квесты, награды, престиж, жеоды, банк, коллекцию,
-- мини-игры и т.д. Studio → View → Command Bar → вставить весь файл → Enter.
--
-- Внутри — ровно те же отдельные билдеры из tools/ (каждое окно со своим
-- стилем), запущенные по очереди. Каждый — в своей защищённой функции:
-- ошибка одного не останавливает остальные, в конце печатается отчёт.
--
-- ⚠ ФАЙЛ СГЕНЕРИРОВАН из отдельных tools/Build*.lua. Меняешь отдельный
-- билдер — перегенерируй (tools/_gen_build_all.py) или правь в обоих местах.
-- Карточка обучения (BuildTutorialObjectiveCard) убрана: обучение v7 рисует
-- своё диалоговое окно кодом (src/client/TutorialUI.client.lua), отдельный
-- шаблон в StarterGui ему не нужен.
--
-- Не входят (не UI): BuildCartSizeGuides, BuildGeodeAssets,
-- BuildNewAssetWorkspacePack, BuildSkinAssets, BuildRubbleBoulderSpawnPoints,
-- BuildLeaderboardBoards, BuildMobileLayoutEditor, HarvestMobileLayout,
-- FixDisabledUi, примеры скриптов.
--------------------------------------------------------------------------------
local __report = {}
local function __run(name, what, fn)
	local ok, err = pcall(fn)
	table.insert(__report, (ok and "✔ " or "✘ ") .. name .. " — " .. what .. (ok and "" or ("\n      " .. tostring(err))))
	task.wait() -- даём Studio «вдохнуть» между билдерами
end

-- ============================================================================
-- BuildUIAssets.lua — HUD, кнопки, базовые окна (Hud, HudGui, …)
-- ============================================================================
__run("BuildUIAssets.lua", "HUD, кнопки, базовые окна (Hud, HudGui, …)", function()
--------------------------------------------------------------------------------
-- BuildUIAssets — ОДНОРАЗОВЫЙ скрипт-сборщик (v3, с поддержкой картинок).
--
-- ЧТО ДЕЛАЕТ: строит РЕАЛЬНЫЕ Instance'ы основного UI игры прямо в
-- StarterGui — ровно то же самое, что сейчас на лету собирает кодовый
-- плейсхолдер в CustomCartUI.client.lua / HudService.lua, только один раз
-- и с текстом на английском (игра — на английском). StarterGui выбран
-- НАРОЧНО (не ReplicatedStorage/Assets): содержимое рендерится прямо во
-- вьюпорте Studio — можно строить/двигать/красить билдером интерфейсов и
-- сразу видеть результат, не запуская игру. Roblox сам клонирует
-- StarterGui каждому игроку в PlayerGui — коду ничего специально клонировать
-- не нужно, он просто находит уже готовое и подключает логику.
--
-- НОВОЕ В v3 — КАРТИНКИ БЕЗ РУЧНОЙ ВОЗНИ В STUDIO.
-- Раньше, чтобы поставить своей кнопке картинку вместо цвета, приходилось
-- вручную пересоздавать инстанс в Studio (Frame → ImageLabel), переносить
-- детей, копировать Position/Size и т.п. — легко ошибиться. Теперь вместо
-- этого просто впиши ID своих картинок в таблицу IMAGES чуть ниже (числа
-- из Asset Manager/Toolbox, без "rbxassetid://" — префикс скрипт добавит
-- сам) и запусти этот файл заново через Command Bar. Скрипт идемпотентен —
-- он сам сносит старые версии собранных ScreenGui и строит их заново,
-- уже сразу с нужными картинками, ни один инстанс руками трогать не надо.
-- Оставил 0 — элемент останется как сейчас, обычным цветным прямоугольником
-- (ничего не сломается, если картинки ещё нет).
--
-- СОБИРАЕТ игровые ScreenGui:
--   CartInteractionUi — промпт "Take Cart" + подсказка "Drop Cart"
--   Hud               — деньги + ребёрты
--   HotbarUi          — строится отдельным tools/BuildInventoryUI.lua
--   ActionButtons     — кнопка защиты (спавн тележки — физическая, в мире.
--                        Сама кнопка теперь тоже заменяемый ассет —
--                        "RespawnButton" в ReplicatedStorage/Assets, см.
--                        PlaceholderFactory.RespawnButton/CartService:
--                        SetupRespawnButton — и получает Style = Custom, тот
--                        же кастомный вид промпта, что у "взять тележку",
--                        DialogResponses ниже к нему отношения не имеет)
--   SettingsMenu      — шестерёнка: звук + промокоды
--   DialogResponses   — список ответов диалога NPC-продавца (Шахта/Тележка/Кирка)
--   RebirthDialogButtons — кнопки REBIRTH/CANCEL диалога крота
--
-- UI магазина собирается отдельным Command Bar-скриптом
-- BuildShopEntry.lua и BuildShopUi.lua (BuildGamepassQuickBar.lua удалён —
-- фичи "быстрых кнопок геймпассов" больше нет, см. CustomCartUI.client.lua).
-- Этот файл не создаёт, не удаляет и не изменяет их ScreenGui.
--
-- КАК ЗАПУСТИТЬ (нужно один раз, не часть игры):
--   1. Открой проект в Studio (через Rojo — как обычно).
--   2. Впиши ID своих картинок в таблицу IMAGES ниже (необязательно —
--      можно оставить всё 0 и получить прежний цветной вид).
--   3. Открой Command Bar (View → Command Bar).
--   4. Вставь ВЕСЬ этот файл целиком и нажми Enter.
--   5. Готово — в StarterGui появятся игровые ScreenGui, уже с картинками.
--      Разворачивай их в Explorer и редактируй дальше — Studio сразу
--      покажет результат во вьюпорте.
--   6. Захотел поменять картинку — поменяй число в IMAGES и запусти файл
--      заново. Скрипт сносит старые версии собранных ScreenGui и строит
--      заново с нуля — вручную ничего удалять не нужно.
--
-- ВАЖНО: ScreenGui.ResetOnSpawn у всех специально выставлен в false —
-- игра респавнит персонажей вручную (CharacterAutoLoads = false), и при
-- ResetOnSpawn = true (дефолт Roblox) Roblox уничтожал бы этот UI при
-- каждом респавне. Не меняй это свойство в Studio, если не уверен.
--
-- Этот файл НЕ часть рантайма — в default.project.json не подключён
-- специально, чтобы Rojo его не трогал. Один раз выполнил — можно забыть.
--------------------------------------------------------------------------------

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

Config.Icons = Config.Icons or {}

--------------------------------------------------------------------------------
-- ЗДЕСЬ МЕНЯЕШЬ КАРТИНКИ. Каждое число — ID картинки из твоего Asset
-- Manager/Toolbox (просто цифры, БЕЗ "rbxassetid://" — это скрипт допишет
-- сам). 0 = картинки нет, элемент остаётся обычным цветным прямоугольником,
-- как сейчас. Все картинки предполагаются ПРЯМОУГОЛЬНЫМИ — растягиваются
-- ровно на размер элемента (ScaleType.Stretch), обрезать/подгонять форму
-- самому не нужно.
--------------------------------------------------------------------------------
local IMAGES = {
	-- HUD (низ/верх экрана)
	MoneyPill = 0,          -- фон "за балансом" денег
	RebirthPill = 0,        -- фон "за балансом" ребёртов
	MoneyIcon = Config.Icons.Money or 0,          -- иконка 💰
	RebirthIcon = Config.Icons.Rebirth or 0,      -- иконка 🔄

	-- Подсказки у тележки
	CartPromptGui = 0,      -- фон подсказки "Take Cart"
	CartDropHintGui = 0,    -- фон подсказки "Drop Cart"
	TalkPromptGui = 0,      -- фон подсказки "Talk" у NPC (отдельный от "Take Cart" стиль)

	-- Хотбар кирки и кнопка щита (низ экрана)
	HotbarSlot = 0,         -- фон слота кирки
	HotbarIcon = Config.Icons.Pickaxe or 0,
	ProtectionButton = 0,   -- фон кнопки щита
	ProtectionIcon = Config.Icons.Protection or 0,

	-- Меню настроек (шестерёнка, слева по центру)
	GearButton = 0,         -- фон кнопки-шестерёнки
	GearIcon = Config.Icons.Settings or 0,
	CommonCloseButton = (Config.UI and Config.UI.CloseButtonImageId) or 0, -- общий крестик для всех окон
	SettingsCloseButton = 0, -- крестик закрытия панели настроек
	SoundToggle = 0,        -- переключатель звука Vkl/Off (код сам тонирует зелёным/красным)
	RedeemButton = 0,       -- кнопка "Claim" промокода
	SliderThumb = Config.Icons.SliderThumb or 0,

	-- Диалог продавца прокачки (справа на экране)
	DialogTemplate = 0,     -- фон одного пункта диалога (Mine/Cart/Pickaxe)
	DialogCloseButton = 0,  -- крестик закрытия диалога

	RebirthButton = 0,      -- фон кнопки REBIRTH в диалоге крота
	RebirthCancelButton = 0, -- фон кнопки CANCEL в диалоге крота
}

-- Превращает число ID в строку "rbxassetid://...", 0/nil → пустая строка
-- (значит "картинки нет"), та же логика, что и в CustomCartUI.client.lua.
local function imageUri(id)
	if not id or id == 0 then
		return ""
	end
	return "rbxassetid://" .. tostring(id)
end

-- Ставит картинку на ГОТОВЫЙ Image-элемент (ImageLabel/ImageButton), если ID
-- задан. Заодно прячет фоновую заливку и градиент — иначе твоя картинка
-- окажется перекрашена/затонирована декоративным градиентом, который имеет
-- смысл только для плейсхолдер-цвета. ID = 0 — ничего не трогает, элемент
-- остаётся ровно таким же цветным прямоугольником, как и раньше.
local function applyImage(instance, id)
	if not id or id == 0 then
		return
	end
	instance.Image = imageUri(id)
	instance.ScaleType = Enum.ScaleType.Stretch
	instance.BackgroundTransparency = 1
	local gradient = instance:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Enabled = false
	end
end

-- ВАЖНО: у ImageButton/ImageLabel НЕТ свойства .Text вообще (в отличие от
-- TextButton/TextLabel) — задать текст прямо на них нельзя, попытка кинет
-- ошибку "Text is not a valid member of ImageButton". Поэтому подпись у
-- кнопок-картинок — отдельный child TextLabel поверх (дети всегда рисуются
-- НАД содержимым родителя, так что подпись остаётся читаемой поверх любой
-- картинки). Используется для кнопок, у которых есть видимый текст
-- (CloseButton/SoundToggle/RedeemButton) — GearButton и Template такой
-- подписи не требуют, у них текст и так всегда был пустым.
local function addCaption(button, text, font)
	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.Size = UDim2.fromScale(1, 1)
	caption.BackgroundTransparency = 1
	caption.Font = font or Enum.Font.FredokaOne
	caption.TextScaled = true
	caption.TextColor3 = Color3.new(1, 1, 1)
	caption.Text = text
	caption.ZIndex = 2
	caption.Parent = button
	return caption
end

-- Ниже — общие мелкие хелперы скругления/обводки. Похожие локальные
-- addCorner/addStroke также есть внутри секции
-- SettingsMenu (см. do-блок дальше) — те локальные копии там и остались,
-- друг другу не мешают (обычное затенение имени в своей области видимости).

local ACCENT_COLOR = Color3.fromRGB(255, 200, 90)   -- Config.UI.AccentColor
local DROP_COLOR = Color3.fromRGB(90, 150, 220)
local TALK_COLOR = Color3.fromRGB(150, 100, 220) -- отдельный, фиолетовый — визуально НЕ путается с "Take Cart" (золото) или "Drop Cart" (синий)
local MONEY_COLOR = Color3.fromRGB(70, 195, 85)
local REBIRTH_COLOR = Color3.fromRGB(165, 90, 255)
local DARK_COLOR = Color3.fromRGB(20, 20, 25)

-- ВАЖНО: объявлены ПОСЛЕ DARK_COLOR специально — это самая обычная
-- Lua-ловушка с областью видимости: local, объявленный НИЖЕ по тексту
-- функции, внутри неё не виден (функция увидела бы глобальную DARK_COLOR,
-- то есть nil) — код должен идти строго после переменных, которые
-- использует как значение по умолчанию.
local function addCorner(inst, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0, 12)
	c.Parent = inst
	return c
end

local function addStroke(inst, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color or DARK_COLOR
	s.Thickness = thickness or 3
	s.Parent = inst
	return s
end

-- Общие строительные блоки — повторяют хелперы из CustomCartUI.client.lua/
-- HudService.lua дословно, просто здесь строят реальные Instance'ы разом.
-- Пилюли/слоты/кнопки теперь ImageLabel/ImageButton (не Frame/TextButton) —
-- визуально и по поведению ничем не отличаются от прежних, пока IMAGES = 0
-- (Image = "" ничего не рисует поверх фона), а как только пропишешь ID —
-- начинают показывать картинку. Клики (connectClick в CustomCartUI.client.lua)
-- одинаково работают что с TextButton/ImageButton, что с Frame/ImageLabel —
-- менять код не нужно.
--------------------------------------------------------------------------------

local function makePillFrame(name, color, width, height, position, imageId)
	local pill = Instance.new("ImageLabel")
	pill.Name = name
	pill.AnchorPoint = Vector2.new(0.5, 1)
	pill.Position = position
	pill.Size = UDim2.fromOffset(width, height)
	pill.BackgroundColor3 = color
	pill.BorderSizePixel = 0
	-- Иконка клавиши является дочерней, но рисуется отдельным квадратом
	-- снаружи слева от плашки.
	pill.ClipsDescendants = false
	pill.Visible = false -- показывается кодом по событиям

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = pill

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3.5
	stroke.Color = DARK_COLOR
	stroke.Parent = pill

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(175, 175, 175)),
	})
	gradient.Parent = pill

	applyImage(pill, imageId)

	return pill
end

local function makeKeyBadge(parent)
	local image = Instance.new("ImageLabel")
	image.Name = "PromptKeyImage"
	image.AnchorPoint = Vector2.new(1, 0.5)
	image.Position = UDim2.new(0, -8, 0.5, 0)
	local size = parent.Size.Y.Offset > 0 and parent.Size.Y.Offset or 46
	image.Size = UDim2.fromOffset(size, size)
	image.BackgroundTransparency = 1
	image.Image = "rbxassetid://126258714999257"
	image.ScaleType = Enum.ScaleType.Fit
	image.ZIndex = 2
	image.Parent = parent

	return image
end

local function makePillText(parent, text)
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.new(0, 50, 0.5, 0)
	label.Size = UDim2.new(1, -60, 1, -12)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = text
	label.ZIndex = 2
	label.Parent = parent

	local textStroke = Instance.new("UIStroke")
	textStroke.Thickness = 2.5
	textStroke.Color = DARK_COLOR
	textStroke.Parent = label

	return label
end

local function makeFillOverlay(pill)
	local fillOverlay = Instance.new("Frame")
	fillOverlay.Name = "FillOverlay"
	fillOverlay.AnchorPoint = Vector2.new(0, 0)
	fillOverlay.Position = UDim2.fromScale(0, 0)
	fillOverlay.Size = UDim2.new(0, 0, 1, 0)
	fillOverlay.BackgroundColor3 = DARK_COLOR
	fillOverlay.BackgroundTransparency = 0.55
	fillOverlay.BorderSizePixel = 0
	fillOverlay.ZIndex = 1
	fillOverlay.Parent = pill

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = fillOverlay

	return fillOverlay
end

local function makeHudPill(parent, order, color, icon, imageId, iconImageId)
	local pill = Instance.new("ImageLabel")
	pill.Name = "Pill_" .. order
	pill.Size = UDim2.fromOffset(220, 62)
	pill.BackgroundColor3 = color
	pill.BorderSizePixel = 0
	pill.LayoutOrder = order
	pill.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = pill

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3.5
	stroke.Color = DARK_COLOR
	stroke.Parent = pill

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(175, 175, 175)),
	})
	gradient.Parent = pill

	applyImage(pill, imageId)

	local iconLabel = Instance.new("ImageLabel")
	iconLabel.Image = imageUri(iconImageId)
	iconLabel.ScaleType = Enum.ScaleType.Fit
	iconLabel.BackgroundTransparency = 1
	iconLabel.Name = "Icon"
	iconLabel.Size = UDim2.fromOffset(44, 44)
	iconLabel.Position = UDim2.new(0, 8, 0.5, 0)
	iconLabel.AnchorPoint = Vector2.new(0, 0.5)
	iconLabel.Parent = pill

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Name = "Value"
	valueLabel.Size = UDim2.new(1, -64, 1, -12)
	valueLabel.Position = UDim2.new(0, 56, 0.5, 0)
	valueLabel.AnchorPoint = Vector2.new(0, 0.5)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Font = Enum.Font.FredokaOne
	valueLabel.TextScaled = false
	valueLabel.TextSize = 28
	valueLabel.TextXAlignment = Enum.TextXAlignment.Left
	valueLabel.TextColor3 = Color3.new(1, 1, 1)
	valueLabel.Parent = pill

	local textStroke = Instance.new("UIStroke")
	textStroke.Thickness = 2.5
	textStroke.Color = DARK_COLOR
	textStroke.Parent = valueLabel

	return pill
end

-- Слот хотбара/кнопки действия: иконка + место под заливку отката + текст.
local function makeActionSlot(name, position, size, emoji, strokeColor, imageId, iconImageId)
	local slot = Instance.new("ImageLabel")
	slot.Name = name
	slot.AnchorPoint = Vector2.new(0.5, 1)
	slot.Position = position
	slot.Size = size
	slot.BackgroundColor3 = Color3.fromRGB(30, 28, 35)
	slot.BorderSizePixel = 0
	slot.ClipsDescendants = true

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = slot

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = strokeColor
	stroke.Parent = slot

	applyImage(slot, imageId)

	local icon = Instance.new("ImageLabel")
	icon.Image = imageUri(iconImageId)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.BackgroundTransparency = 1
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.62, 0.62)
	icon.ZIndex = 2
	icon.Parent = slot

	-- Заливка отката — старт пустая (см. CustomCartUI.client.lua: доступно = не красное)
	local overlay = Instance.new("Frame")
	overlay.Name = "CooldownOverlay"
	overlay.AnchorPoint = Vector2.new(0, 1)
	overlay.Position = UDim2.new(0, 0, 1, 0)
	overlay.Size = UDim2.new(1, 0, 0, 0)
	overlay.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
	overlay.BackgroundTransparency = 0.1
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 3
	overlay.Parent = slot
	local overlayCorner = Instance.new("UICorner")
	overlayCorner.CornerRadius = UDim.new(0, 12)
	overlayCorner.Parent = overlay

	local text = Instance.new("TextLabel")
	text.Name = "CooldownText"
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.fromScale(0.5, 0.5)
	text.Size = UDim2.fromScale(0.8, 0.5)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeColor3 = DARK_COLOR
	text.TextStrokeTransparency = 0
	text.Visible = false
	text.ZIndex = 4
	text.Parent = slot

	return slot
end

local generatedGuis = {}
local function freshScreenGui(name, displayOrder)
	local existing = StarterGui:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false -- ОБЯЗАТЕЛЬНО: ручной респавн персонажей, см. шапку файла
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = displayOrder
	gui.Parent = StarterGui
	table.insert(generatedGuis, gui)
	return gui
end

--------------------------------------------------------------------------------
-- Сборка
--------------------------------------------------------------------------------

-- Загрузочный экран теперь создаётся ранним LocalScript в ReplicatedFirst.
-- Удаляем старый StarterGui-ассет, чтобы он больше не клонировался игроку.
local legacyPreloadScreen = StarterGui:FindFirstChild("PreloadScreen")
if legacyPreloadScreen then
	legacyPreloadScreen:Destroy()
end

-- 1) CartInteractionUi — "Take Cart" prompt + "Drop Cart" hint
do
	local screenGui = freshScreenGui("CartInteractionUi", 5)
	local commonPosition = UDim2.new(0.5, 0, 1, -140)

	local promptPill = makePillFrame("CartPromptGui", ACCENT_COLOR, 190, 46, commonPosition, IMAGES.CartPromptGui)
	makeFillOverlay(promptPill)
	makeKeyBadge(promptPill)
	makePillText(promptPill, "") -- текст подставляется кодом на лету (ObjectText/ActionText промпта)
	promptPill.Parent = screenGui

	local dropPill = makePillFrame("CartDropHintGui", DROP_COLOR, 220, 40, commonPosition, IMAGES.CartDropHintGui)
	makeFillOverlay(dropPill)
	makeKeyBadge(dropPill)
	makePillText(dropPill, "Drop Cart")
	dropPill.Parent = screenGui

	-- Отдельный, визуально не спутать с "Take Cart"/"Drop Cart" — свой
	-- цвет (фиолетовый). Показывается ТОЛЬКО для ProximityPrompt с
	-- атрибутом PromptKind == "Talk" (см. RebirthService/UpgradeService/
	-- ShopNpcService — они выставляют Style = Custom + этот атрибут) —
	-- НЕ переиспользует внешний вид "Take Cart", у диалоговых NPC теперь
	-- свой собственный кастомный промпт.
	local talkPill = makePillFrame("TalkPromptGui", TALK_COLOR, 190, 46, commonPosition, IMAGES.TalkPromptGui)
	makeFillOverlay(talkPill) -- нужен для RebirthNPC (у него HoldDuration = 0.6, не мгновенный клик, как у остальных двух)
	makeKeyBadge(talkPill)
	makePillText(talkPill, "") -- текст подставляется кодом на лету (ObjectText/ActionText промпта)
	talkPill.Parent = screenGui

	-- FillCartOffer ("моментальное заполнение тележки за Robux") УБРАНО
	-- ЦЕЛИКОМ по прямому запросу — этой фичи в игре больше нет. Новая
	-- механика добычи (НПС-экспедиция, см. MineService.lua) не имеет
	-- состояния "тележка стоит и постепенно наполняется", на котором
	-- строилась эта кнопка, так что она и функционально была бы не у
	-- места, даже если бы её оставили. См. src/client/CustomCartUI.client
	-- .lua — функция setupInstantFillUi, которая её обслуживала, тоже
	-- удалена целиком.
end

-- 2) Hud — портрет игрока (круглый ViewportFrame, живой персонаж
-- клонируется и крутится клиентским скриптом — см.
-- src/client/PlayerPortraitHud.client.lua) + плашка баланса + плашка
-- престижа (см. ТЗ/референс — круглый портрет слева, тёмная плашка
-- баланса и поменьше плашка "PRESTIGE: N" под ней). ЗАМЕНА старой
-- версии (два одинаковых денежных/ребёрт-пилюль в столбик).
do
	local screenGui = freshScreenGui("Hud", 10)

	-- Перенесено в левый нижний угол (было — левый верхний) по прямому
	-- запросу.
	local container = Instance.new("Frame")
	container.Name = "HudGui"
	container.AnchorPoint = Vector2.new(0, 1)
	container.Position = UDim2.new(0, 16, 1, -16)
	container.Size = UDim2.fromOffset(300, 110)
	container.BackgroundTransparency = 1
	container.Parent = screenGui

	-- ПОРТРЕТ — живой 3D-рендер персонажа (по прямому запросу — лицом к
	-- камере, по центру, плавно покачивается влево-вправо, не целиком
	-- крутится). Билдер тут кладёт только рамку/фон, содержимое (клон
	-- персонажа + камера + покачивание) заполняет клиентский скрипт (см.
	-- PlayerPortraitHud.client.lua).
	local portrait = Instance.new("ViewportFrame")
	portrait.Name = "Portrait"
	portrait.AnchorPoint = Vector2.new(0, 0.5)
	portrait.Position = UDim2.new(0, 0, 0.5, 0)
	portrait.Size = UDim2.fromOffset(92, 92)
	portrait.BackgroundColor3 = Color3.fromRGB(235, 215, 180)
	portrait.BorderSizePixel = 0
	portrait.ClipsDescendants = true -- обязательно для круглого кропа через UICorner ниже
	portrait.Parent = container
	addCorner(portrait, UDim.new(1, 0))
	addStroke(portrait, Color3.fromRGB(150, 95, 40), 4)

	-- РАМКА ПОРТРЕТА — отдельный ImageLabel ПОВЕРХ вьюпорта (по прямому
	-- запросу "чтобы я тоже мог заменить"). Пустой Image = видно рамку,
	-- нарисованную кодом (UIStroke выше); подставьте свой ассет кольца —
	-- и он ляжет сверху, ничего больше править не нужно.
	--
	-- Именно ПОВЕРХ, а не фоном: ViewportFrame рисует 3D-содержимое над
	-- своим фоном, поэтому кольцо-фон было бы не видно.
	local portraitFrame = Instance.new("ImageLabel")
	portraitFrame.Name = "PortraitFrame"
	portraitFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	portraitFrame.Position = UDim2.fromScale(0.5, 0.5)
	portraitFrame.Size = UDim2.new(1, 18, 1, 18) -- чуть больше портрета: кольцо обрамляет его снаружи
	portraitFrame.BackgroundTransparency = 1
	portraitFrame.Image = "" -- ← сюда свой ассет рамки
	portraitFrame.ScaleType = Enum.ScaleType.Fit
	portraitFrame.ZIndex = 5
	portraitFrame.Parent = portrait

	-- BalanceBar — тёмная вытянутая плашка справа от портрета (было:
	-- MoneyPill из makeHudPill, тот же контракт имён — HudService.lua
	-- трогать не пришлось).
	local balanceBar = Instance.new("Frame")
	balanceBar.Name = "MoneyPill"
	balanceBar.AnchorPoint = Vector2.new(0, 0.5)
	balanceBar.Position = UDim2.new(0, 80, 0.5, -16)
	balanceBar.Size = UDim2.fromOffset(216, 46)
	balanceBar.BackgroundColor3 = Color3.fromRGB(35, 38, 46)
	balanceBar.BorderSizePixel = 0
	balanceBar.Parent = container
	addCorner(balanceBar, UDim.new(0, 10))
	addStroke(balanceBar, Color3.fromRGB(150, 95, 40), 3)

	-- Подложка плашки баланса своим ассетом. Лежит ПОЗАДИ текста (ZIndex 0)
	-- и растянута на всю плашку; когда Image задан, клиент/вы можете
	-- убрать BackgroundTransparency у самой плашки.
	local balanceSkin = Instance.new("ImageLabel")
	balanceSkin.Name = "Skin"
	balanceSkin.Size = UDim2.fromScale(1, 1)
	balanceSkin.BackgroundTransparency = 1
	balanceSkin.Image = "" -- ← сюда свой ассет плашки
	balanceSkin.ScaleType = Enum.ScaleType.Slice
	balanceSkin.SliceCenter = Rect.new(12, 12, 20, 20) -- 9-slice: плашка тянется по ширине без искажения углов
	balanceSkin.ZIndex = 0
	balanceSkin.Parent = balanceBar

	local balanceLabel = Instance.new("TextLabel")
	balanceLabel.Name = "Value"
	balanceLabel.Size = UDim2.new(1, -20, 1, 0)
	balanceLabel.Position = UDim2.fromOffset(14, 0)
	balanceLabel.BackgroundTransparency = 1
	balanceLabel.Font = Enum.Font.FredokaOne
	balanceLabel.TextColor3 = Color3.fromRGB(255, 230, 180)
	balanceLabel.TextXAlignment = Enum.TextXAlignment.Left
	balanceLabel.TextYAlignment = Enum.TextYAlignment.Center
	balanceLabel.Text = "$0"
	balanceLabel.TextScaled = false
	balanceLabel.TextSize = 26
	balanceLabel.Parent = balanceBar

	-- RebirthBar — плашка поменьше под балансом, "PRESTIGE: N" (было:
	-- RebirthPill из makeHudPill, тот же контракт имён).
	local rebirthBar = Instance.new("Frame")
	rebirthBar.Name = "RebirthPill"
	rebirthBar.AnchorPoint = Vector2.new(0, 0.5)
	-- По референсу плашка престижа сидит ПОД баланcом и заходит левым
	-- краем под портрет, а не стоит отдельным блоком в стороне.
	rebirthBar.Position = UDim2.new(0, 74, 0.5, 34)
	rebirthBar.Size = UDim2.fromOffset(160, 28)
	rebirthBar.BackgroundColor3 = Color3.fromRGB(120, 70, 25)
	rebirthBar.BorderSizePixel = 0
	rebirthBar.Parent = container
	addCorner(rebirthBar, UDim.new(0, 8))
	addStroke(rebirthBar, Color3.fromRGB(150, 95, 40), 2)

	local rebirthSkin = Instance.new("ImageLabel")
	rebirthSkin.Name = "Skin"
	rebirthSkin.Size = UDim2.fromScale(1, 1)
	rebirthSkin.BackgroundTransparency = 1
	rebirthSkin.Image = "" -- ← сюда свой ассет плашки престижа
	rebirthSkin.ScaleType = Enum.ScaleType.Slice
	rebirthSkin.SliceCenter = Rect.new(10, 10, 18, 18)
	rebirthSkin.ZIndex = 0
	rebirthSkin.Parent = rebirthBar

	local rebirthLabel = Instance.new("TextLabel")
	rebirthLabel.Name = "Value"
	rebirthLabel.Size = UDim2.new(1, -16, 1, 0)
	rebirthLabel.Position = UDim2.fromOffset(10, 0)
	rebirthLabel.BackgroundTransparency = 1
	rebirthLabel.Font = Enum.Font.FredokaOne
	rebirthLabel.TextColor3 = Color3.new(1, 1, 1)
	rebirthLabel.TextXAlignment = Enum.TextXAlignment.Left
	rebirthLabel.TextYAlignment = Enum.TextYAlignment.Center
	rebirthLabel.Text = "PRESTIGE: 0"
	rebirthLabel.TextScaled = false
	rebirthLabel.TextSize = 18
	rebirthLabel.Parent = rebirthBar
end

-- Щит использует центральный PickaxeSlot в HotbarUi.
local oldActionButtons = StarterGui:FindFirstChild("ActionButtons")
if oldActionButtons then oldActionButtons:Destroy() end

-- 5) SettingsMenu — gear icon (left-center) + panel (audio, promo codes)
--    Стиль совпадает с магазином: синяя шапка и тёмные карточки,
--    строки-переключатели с зелёной/красной пилюлей On/Off. Всё это —
--    обычные Instance'ы, полностью редактируемые в Studio после сборки:
--    цвета, размеры, текст — трогайте что угодно, скрипт (connectClick в
--    CustomCartUI.client.lua) сам подхватит любые правки по именам.
do
	local screenGui = freshScreenGui("SettingsMenu", 20)

	local THEME = {
		panel = Color3.fromRGB(35, 33, 42),
		panelStroke = Color3.fromRGB(20, 20, 25),
		header = Color3.fromRGB(60, 110, 200),
		headerStroke = Color3.fromRGB(35, 70, 145),
		row = Color3.fromRGB(55, 52, 68),
		rowStroke = Color3.fromRGB(20, 20, 25),
		on = Color3.fromRGB(70, 195, 85),
		subtitle = Color3.fromRGB(190, 200, 225),
		input = Color3.fromRGB(45, 43, 55),
	}

	local function addCorner(inst, radius)
		local c = Instance.new("UICorner")
		c.CornerRadius = radius or UDim.new(0, 10)
		c.Parent = inst
		return c
	end

	local function addStroke(inst, color, thickness)
		local s = Instance.new("UIStroke")
		s.Color = color
		s.Thickness = thickness or 2
		s.Parent = inst
		return s
	end

	-- Шестерёнка (кружок слева по центру — открывает/закрывает панель)
	local gearButton = Instance.new("ImageButton")
	gearButton.Name = "GearButton"
	gearButton.AnchorPoint = Vector2.new(0, 0.5)
	gearButton.Position = UDim2.new(0, 14, 0.5, -26)
	gearButton.Size = UDim2.fromOffset(44, 44)
	gearButton.BackgroundColor3 = Color3.fromRGB(30, 28, 35)
	gearButton.BorderSizePixel = 0
	gearButton.AutoButtonColor = false
	gearButton.Parent = screenGui
	addCorner(gearButton, UDim.new(0.5, 0))
	addStroke(gearButton, Color3.fromRGB(220, 220, 220), 2)
	if IMAGES.GearButton ~= 0 then
		gearButton.Image = imageUri(IMAGES.GearButton)
		gearButton.ScaleType = Enum.ScaleType.Stretch
		gearButton.BackgroundTransparency = 1
	end

	local gearIcon = Instance.new("ImageLabel")
	gearIcon.Image = imageUri(IMAGES.GearIcon)
	gearIcon.ScaleType = Enum.ScaleType.Fit
	gearIcon.Name = "Icon"
	gearIcon.BackgroundTransparency = 1
	gearIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	gearIcon.Position = UDim2.fromScale(0.5, 0.5)
	gearIcon.Size = UDim2.fromScale(0.65, 0.65)
	gearIcon.Parent = gearButton

	-- Тёмная карточка настроек по центру экрана
	local panel = Instance.new("ImageLabel")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(400, 520)
	panel.BackgroundColor3 = THEME.panel
	panel.BorderSizePixel = 0
	panel.ClipsDescendants = true
	panel.Visible = false
	panel.Parent = screenGui
	addCorner(panel, UDim.new(0, 14))
	addStroke(panel, THEME.panelStroke, 3)

	-- Синяя шапка, как у магазина
	local header = Instance.new("ImageLabel")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 56)
	header.BackgroundColor3 = THEME.header
	header.BorderSizePixel = 0
	header.ZIndex = 2
	header.Parent = panel

	local headerBottom = Instance.new("Frame")
	headerBottom.BackgroundColor3 = THEME.headerStroke
	headerBottom.BorderSizePixel = 0
	headerBottom.Size = UDim2.new(1, 0, 0, 3)
	headerBottom.Position = UDim2.new(0, 0, 1, -3)
	headerBottom.ZIndex = 2
	headerBottom.Parent = header

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 14, 0, 0)
	title.Size = UDim2.new(1, -60, 1, 0)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Text = "Settings"
	title.ZIndex = 3
	title.Parent = header

	local closeButton = Instance.new("ImageButton")
	closeButton.Name = "CloseButton"
	closeButton.AnchorPoint = Vector2.new(1, 0.5)
	closeButton.Position = UDim2.new(1, -8, 0.5, 0)
	closeButton.Size = UDim2.fromOffset(26, 26)
	closeButton.BackgroundColor3 = Color3.fromRGB(190, 70, 70)
	closeButton.AutoButtonColor = false
	closeButton.ZIndex = 3
	closeButton.Parent = header
	addCorner(closeButton, UDim.new(0, 6))
	addCaption(closeButton, "X")
	local closeImageId = IMAGES.SettingsCloseButton ~= 0 and IMAGES.SettingsCloseButton or IMAGES.CommonCloseButton
	applyImage(closeButton, closeImageId)
	if closeImageId ~= 0 then
		closeButton.ScaleType = Enum.ScaleType.Fit
		closeButton.Caption.Visible = false
	end

	-- Тело панели со строками настроек
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.new(0, 10, 0, 66)
	body.Size = UDim2.new(1, -20, 1, -76)
	body.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = body

	local function buildToggleRow(name, label, subtitle, order)
		local row = Instance.new("Frame")
		row.Name = name
		row.BackgroundColor3 = THEME.row
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, 58)
		row.LayoutOrder = order
		row.Parent = body
		addCorner(row, UDim.new(0, 10))
		addStroke(row, THEME.rowStroke, 2)

		local rowTitle = Instance.new("TextLabel")
		rowTitle.BackgroundTransparency = 1
		rowTitle.Position = UDim2.new(0, 12, 0, 6)
		rowTitle.Size = UDim2.new(1, -100, 0, 22)
		rowTitle.Font = Enum.Font.FredokaOne
		rowTitle.TextScaled = true
		rowTitle.TextXAlignment = Enum.TextXAlignment.Left
		rowTitle.TextColor3 = Color3.new(1, 1, 1)
		rowTitle.Text = label
		rowTitle.Parent = row

		local rowSubtitle = Instance.new("TextLabel")
		rowSubtitle.BackgroundTransparency = 1
		rowSubtitle.Position = UDim2.new(0, 12, 0, 30)
		rowSubtitle.Size = UDim2.new(1, -100, 0, 20)
		rowSubtitle.Font = Enum.Font.FredokaOne
		rowSubtitle.TextScaled = true
		rowSubtitle.TextXAlignment = Enum.TextXAlignment.Left
		rowSubtitle.TextColor3 = THEME.subtitle
		rowSubtitle.Text = subtitle
		rowSubtitle.Parent = row

		local toggle = Instance.new("ImageButton")
		toggle.Name = name .. "Toggle"
		toggle.AnchorPoint = Vector2.new(1, 0.5)
		toggle.Position = UDim2.new(1, -12, 0.5, 0)
		toggle.Size = UDim2.fromOffset(64, 30)
		toggle.BackgroundColor3 = THEME.on
		toggle.AutoButtonColor = false
		toggle.Parent = row
		addCorner(toggle, UDim.new(0.5, 0))
		addCaption(toggle, "On")
		if IMAGES.SoundToggle ~= 0 then
			-- ImageColor3 — тонирует зелёным/красным саму картинку (см.
			-- CustomCartUI.client.lua: paintToggle) — картинка тут задумана
			-- НЕЙТРАЛЬНОЙ (бело-серой), код сам красит её по состоянию звука.
			toggle.Image = imageUri(IMAGES.SoundToggle)
			toggle.ScaleType = Enum.ScaleType.Stretch
			toggle.BackgroundTransparency = 1
			toggle.ImageColor3 = THEME.on
		end

		return row, toggle
	end

	local _, soundToggle = buildToggleRow("Audio", "Audio", "Toggle your audio", 1)
	soundToggle.Name = "SoundToggle"

	local function buildSliderRow(name, labelText, order)
		local row = Instance.new("Frame")
		row.Name = name .. "Row"
		row.Size = UDim2.new(1, 0, 0, 50)
		row.BackgroundColor3 = THEME.row
		row.BorderSizePixel = 0
		row.LayoutOrder = order
		row.Parent = body

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Position = UDim2.fromOffset(12, 4)
		label.Size = UDim2.new(1, -70, 0, 20)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextSize = 16
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Text = labelText
		label.Parent = row

		local value = Instance.new("TextLabel")
		value.Name = "Value"
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.new(1, -12, 0, 4)
		value.Size = UDim2.fromOffset(48, 20)
		value.BackgroundTransparency = 1
		value.Font = Enum.Font.GothamBold
		value.TextSize = 14
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.TextColor3 = THEME.subtitle
		value.Text = "100%"
		value.Parent = row

		local track = Instance.new("Frame")
		track.Name = "Track"
		track.Position = UDim2.new(0, 12, 1, -17)
		track.Size = UDim2.new(1, -24, 0, 8)
		track.BackgroundColor3 = THEME.input
		track.BorderSizePixel = 0
		track.Active = true
		track.Parent = row

		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundColor3 = THEME.on
		fill.BorderSizePixel = 0
		fill.Parent = track

		local thumb = Instance.new("ImageButton")
		thumb.Name = "Thumb"
		thumb.AnchorPoint = Vector2.new(0.5, 0.5)
		thumb.Position = UDim2.fromScale(1, 0.5)
		thumb.Size = UDim2.fromOffset(20, 20)
		thumb.BackgroundColor3 = Color3.new(1, 1, 1)
		thumb.BorderSizePixel = 0
		thumb.AutoButtonColor = false
		thumb.Image = imageUri(IMAGES.SliderThumb)
		thumb.ScaleType = Enum.ScaleType.Fit
		thumb.Parent = track
	end

	buildSliderRow("SfxSlider", "WORLD SOUNDS", 2)
	buildSliderRow("MusicSlider", "MUSIC", 3)
	buildSliderRow("UiSlider", "UI SOUNDS", 4)
	buildSliderRow("EffectsSlider", "VISUAL EFFECTS", 5)

	-- Строка редима промокодов
	local redeemRow = Instance.new("Frame")
	redeemRow.Name = "RedeemRow"
	redeemRow.BackgroundColor3 = THEME.row
	redeemRow.BorderSizePixel = 0
	redeemRow.Size = UDim2.new(1, 0, 0, 110)
	redeemRow.LayoutOrder = 6
	redeemRow.Parent = body
	addCorner(redeemRow, UDim.new(0, 10))
	addStroke(redeemRow, THEME.rowStroke, 2)

	local redeemTitle = Instance.new("TextLabel")
	redeemTitle.BackgroundTransparency = 1
	redeemTitle.Position = UDim2.new(0, 12, 0, 6)
	redeemTitle.Size = UDim2.new(1, -24, 0, 22)
	redeemTitle.Font = Enum.Font.FredokaOne
	redeemTitle.TextScaled = true
	redeemTitle.TextXAlignment = Enum.TextXAlignment.Left
	redeemTitle.TextColor3 = Color3.new(1, 1, 1)
	redeemTitle.Text = "Redeem Codes"
	redeemTitle.Parent = redeemRow

	local redeemSubtitle = Instance.new("TextLabel")
	redeemSubtitle.BackgroundTransparency = 1
	redeemSubtitle.Position = UDim2.new(0, 12, 0, 30)
	redeemSubtitle.Size = UDim2.new(1, -24, 0, 18)
	redeemSubtitle.Font = Enum.Font.FredokaOne
	redeemSubtitle.TextScaled = true
	redeemSubtitle.TextXAlignment = Enum.TextXAlignment.Left
	redeemSubtitle.TextColor3 = THEME.subtitle
	redeemSubtitle.Text = "Look for codes on developer's socials!"
	redeemSubtitle.Parent = redeemRow

	local codeInput = Instance.new("TextBox")
	codeInput.Name = "CodeInput"
	codeInput.Position = UDim2.new(0, 12, 0, 54)
	codeInput.Size = UDim2.new(1, -100, 0, 32)
	codeInput.BackgroundColor3 = THEME.input
	codeInput.Font = Enum.Font.FredokaOne
	codeInput.TextScaled = true
	codeInput.TextColor3 = Color3.new(1, 1, 1)
	codeInput.PlaceholderText = "Type code here.."
	codeInput.ClearTextOnFocus = false
	codeInput.Text = ""
	codeInput.Parent = redeemRow
	addCorner(codeInput, UDim.new(0, 8))

	local redeemButton = Instance.new("ImageButton")
	redeemButton.Name = "RedeemButton"
	redeemButton.AnchorPoint = Vector2.new(1, 0)
	redeemButton.Position = UDim2.new(1, -12, 0, 54)
	redeemButton.Size = UDim2.fromOffset(76, 32)
	redeemButton.BackgroundColor3 = THEME.on
	redeemButton.AutoButtonColor = false
	redeemButton.Parent = redeemRow
	addCorner(redeemButton, UDim.new(0, 8))
	addCaption(redeemButton, "Claim")
	applyImage(redeemButton, IMAGES.RedeemButton)

	local resultText = Instance.new("TextLabel")
	resultText.Name = "ResultText"
	resultText.BackgroundTransparency = 1
	resultText.Position = UDim2.new(0, 12, 0, 88)
	resultText.Size = UDim2.new(1, -24, 0, 18)
	resultText.Font = Enum.Font.FredokaOne
	resultText.TextScaled = true
	resultText.TextColor3 = Color3.fromRGB(255, 220, 150)
	resultText.Text = ""
	resultText.ZIndex = 2
	resultText.Parent = redeemRow
end

--------------------------------------------------------------------------------
-- 6) RebirthDialogButtons — заменяемые кнопки диалога крота.
--------------------------------------------------------------------------------
do
	local screenGui = freshScreenGui("RebirthDialogButtons", 15)
	screenGui.Enabled = false

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -140)
	panel.Size = UDim2.fromOffset(320, 60)
	panel.BackgroundTransparency = 1
	panel.Parent = screenGui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 16)
	layout.Parent = panel

	local function makeRebirthButton(name, text, color, imageId)
		local button = Instance.new("ImageButton")
		button.Name = name
		button.Size = UDim2.fromOffset(150, 52)
		button.BackgroundColor3 = color
		button.BorderSizePixel = 0
		button.AutoButtonColor = true
		button.Parent = panel
		addCorner(button, UDim.new(0, 12))
		addStroke(button, DARK_COLOR, 2)
		applyImage(button, imageId)
		addCaption(button, text, Enum.Font.Arcade)
		return button
	end

	makeRebirthButton("RebirthButton", "PRESTIGE", Color3.fromRGB(70, 170, 90), IMAGES.RebirthButton)
	makeRebirthButton("CancelButton", "CANCEL", Color3.fromRGB(150, 60, 60), IMAGES.RebirthCancelButton)
end

for _, gui in generatedGuis do
	for _, descendant in gui:GetDescendants() do
		if descendant:IsA("UICorner") or descendant:IsA("UIStroke") then
			descendant:Destroy()
		elseif descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
			descendant.TextStrokeTransparency = 1
		end
	end
end

print("[BuildUIAssets] Done: CartInteractionUi, Hud, SettingsMenu, and RebirthDialogButtons created in StarterGui (English text). Notification UI is built separately by tools/BuildNotificationUI.lua. Shop UI was not changed.")
end)

-- ============================================================================
-- BuildInventoryUI.lua — инвентарь и хотбар (HotbarUi)
-- ============================================================================
__run("BuildInventoryUI.lua", "инвентарь и хотбар (HotbarUi)", function()
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
end)

-- ============================================================================
-- BuildNotificationUI.lua — уведомления / тосты — ToastUiBuilder
-- ============================================================================
__run("BuildNotificationUI.lua", "уведомления / тосты — ToastUiBuilder", function()
--------------------------------------------------------------------------------
-- BuildNotificationUI — Studio Command Bar: собирает StarterGui/Toast —
-- уведомления в стиле Grow a Garden (v14.3: компактные карточки сверху по
-- центру, на экране максимум две, очередь ускоряется, дубли склеиваются).
--
-- Сама сборка живёт в ReplicatedStorage.Shared.ToastUiBuilder (тот же
-- модуль использует клиент, если в StarterGui нет свежей версии), поэтому
-- вид в Studio и в игре всегда совпадает.
--
-- КАК ИСПОЛЬЗОВАТЬ:
--   1. Синхронизировать проект (Rojo), чтобы модуль был в Shared.
--   2. Вставить этот файл целиком в Command Bar и выполнить.
--   3. Править вид мышкой: Toast/Stack/Panel — шаблон одной карточки.
--      Размер карточки клиент берёт из шаблона. Свою подложку — в
--      Panel/Skin.Image (ScaleType = Slice). Шаблон должен остаться
--      Visible = false — клиент его клонирует.
--   Позиция стопки на экране — Toast/Stack.Position.
--------------------------------------------------------------------------------
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:FindFirstChild("Shared")
local module = shared and shared:FindFirstChild("ToastUiBuilder")
assert(module, "[BuildNotificationUI] Нет ReplicatedStorage.Shared.ToastUiBuilder — сначала синхронизируй проект (Rojo).")

local Builder = require(module)

local existing = StarterGui:FindFirstChild("Toast")
if existing then existing:Destroy() end

local gui = Builder.Build()
gui.Parent = StarterGui

print(("[BuildNotificationUI] Готово: StarterGui/Toast (версия %d). Шаблон карточки — Toast/Stack/Panel."):format(Builder.VERSION))
end)

-- ============================================================================
-- BuildShopUi.lua — магазин за Robux (ShopUi)
-- ============================================================================
__run("BuildShopUi.lua", "магазин за Robux (ShopUi)", function()
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
end)

-- ============================================================================
-- BuildQuestUI.lua — квесты (QuestUi)
-- ============================================================================
__run("BuildQuestUI.lua", "квесты (QuestUi)", function()
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
end)

-- ============================================================================
-- BuildTutorialUI.lua — диалоговое окно обучения (TutorialUi)
-- ============================================================================
__run("BuildTutorialUI.lua", "диалоговое окно обучения (TutorialUi)", function()
--------------------------------------------------------------------------------
-- BuildTutorialUI — ДИАЛОГОВОЕ ОКНО ОБУЧЕНИЯ (см. Config.Tutorial).
--
-- Собирает StarterGui/TutorialUi: рамку с плашкой имени, портретом и
-- посимвольно печатающимся текстом, плюс свёрнутую плашку-задание, в
-- которую окно превращается на время выполнения шага.
--
-- САМА ГЕОМЕТРИЯ ЛЕЖИТ НЕ ЗДЕСЬ, а в src/shared/TutorialUiBuilder.lua.
-- Причина: если этот билдер ни разу не запускали, обучение обязано
-- работать всё равно — иначе новичок на свежем месте не увидит ничего и
-- застрянет на первом шаге. Поэтому то же построение вызывает и
-- src/client/TutorialUI.client.lua, когда не находит готовый TutorialUi в
-- PlayerGui. Одна функция, две точки вызова — копиям разъехаться негде.
--
-- Что даёт запуск билдера по сравнению со сборкой на лету: окно можно
-- открыть в Studio и подвинуть/перекрасить руками, как остальной
-- интерфейс. Клиент уважает то, что лежит в StarterGui, и строит своё
-- только при отсутствии.
--
-- ЗАПУСК: Rojo-синк → Command Bar в Studio → вставить файл целиком → Enter.
-- Безопасно перезапускается, но пересоздаёт StarterGui/TutorialUi с нуля,
-- вместе с ручными правками.
--------------------------------------------------------------------------------

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local existing = StarterGui:FindFirstChild("TutorialUi")
if existing then existing:Destroy() end

local TutorialUiBuilder = require(ReplicatedStorage.Shared.TutorialUiBuilder)

-- narrow = false: в StarterGui кладём настольный вариант. Клиент сам
-- пересчитает размеры под узкий экран при запуске и при смене размера окна
-- (см. подписку на ViewportSize в TutorialUI.client.lua), так что отдельная
-- мобильная сборка здесь не нужна.
local gui = TutorialUiBuilder.Build(false)
gui.Parent = StarterGui

print("[BuildTutorialUI] TutorialUi собран (диалоговое окно обучения v7).")
end)

-- ============================================================================
-- BuildDailyRewardUI.lua — ежедневные награды
-- ============================================================================
__run("BuildDailyRewardUI.lua", "ежедневные награды", function()
-- Standalone Studio builder. Replaces only StarterGui/DailyRewardUi.

local StarterGui = game:GetService("StarterGui")
-- ЕДИНЫЙ СТИЛЬ С МАГАЗИНОМ (по прямому запросу — "дейлиревардс переделай
-- под стилистику шопа"): та же тёмная полупрозрачная панель, то же
-- скругление 0-4px, та же тёмная шапка с лентой-закладкой слева и красным
-- X справа, те же цветные тонкие обводки карточек. См.
-- tools/BuildShopUi.lua — палитра держится в паре с ним.
local COLORS = {
	Panel = Color3.fromRGB(18, 17, 23),
	Header = Color3.fromRGB(12, 11, 16),
	Card = Color3.fromRGB(30, 28, 38),
	CardStroke = Color3.fromRGB(70, 75, 90),
	Locked = Color3.fromRGB(38, 36, 46),
	Yellow = Color3.fromRGB(230, 185, 60), -- жёлтый = действие/награда (стайл-гайд)
	Green = Color3.fromRGB(80, 200, 90),   -- зелёный = готово/забрано
	Close = Color3.fromRGB(220, 70, 70),   -- красный = закрыть
	Ribbon = Color3.fromRGB(190, 130, 245),
	White = Color3.fromRGB(245, 247, 255),
}

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
-- Placeholder-текст на будущее для Studio-превью (реальный текст на клиенте
-- всегда переписывается из Config.Quests.DailyRewards[day].Text — см.
-- DailyRewardUI.client.lua:render). Держим синхронно с конфигом просто
-- для удобства, чтобы то, что видно в Studio до запуска игры, не вводило
-- в заблуждение.
local REWARDS = { "$75K", "$350K", "1.75x MINING\n45 MIN", "$2M", "2.5x MINING\n1 HOUR", "$400M", "GOLD\nSKIN" }

local function label(name, text, size, position, textSize)
	local item = Instance.new("TextLabel")
	item.Name = name
	item.Size = size
	item.Position = position
	item.BackgroundTransparency = 1
	item.Font = Enum.Font.Arcade
	item.Text = text
	item.TextColor3 = COLORS.White
	item.TextSize = textSize
	item.TextStrokeTransparency = 1
	item.TextWrapped = true
	return item
end

local function rewardCard(day, size, position, parent)
	local card = Instance.new("ImageButton")
	card.Name = "Day" .. day
	card.Size = size
	card.Position = position
	card.BackgroundColor3 = COLORS.Card
	card.BorderSizePixel = 0
	card.AutoButtonColor = false
	card.Image = ""
	card.Parent = parent
	addCorner(card, UDim.new(0, 4))
	-- День 7 — финальная награда, выделяется зелёной обводкой (как
	-- выделенная колонка на референсе), остальные нейтральные.
	addStroke(card, day == 7 and COLORS.Green or COLORS.CardStroke, day == 7 and 2 or 1)
	local dayLabel = label("Day", "DAY " .. day, UDim2.new(1, -12, 0, 28), UDim2.fromOffset(6, 7), 16)
	dayLabel.TextColor3 = COLORS.Yellow
	dayLabel.Parent = card
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = day == 7 and UDim2.fromOffset(75, 36) or UDim2.new(0.5, 0, 0, 36)
	icon.Size = day == 7 and UDim2.fromOffset(60, 44) or UDim2.fromOffset(64, 50)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = card
	local reward = label(
		"Reward", REWARDS[day],
		day == 7 and UDim2.fromOffset(330, 40) or UDim2.new(1, -10, 0, 42),
		day == 7 and UDim2.fromOffset(120, 24) or UDim2.fromOffset(5, 88), 13
	)
	-- БОЛЬШИЕ ЯРКИЕ ОБВЕДЁННЫЕ буквы — та же логика, что и в fallback-версии
	-- на клиенте (DailyRewardUI.client.lua): TextScaled сам подбирает
	-- размер под содержимое (короткие "$2M" — крупно, двухстрочные бусты —
	-- не вылезают за край), клиент только красит TextColor3 по типу
	-- награды (Money/MiningBoost/Skin), саму эту "жирность" не переопределяет.
	reward.TextScaled = true
	reward.Font = Enum.Font.GothamBlack
	reward.TextStrokeTransparency = 0.35
	reward.TextStrokeColor3 = Color3.fromRGB(10, 12, 18)
	local rewardSizeLimit = Instance.new("UITextSizeConstraint")
	rewardSizeLimit.MaxTextSize = day == 7 and 30 or 22
	rewardSizeLimit.MinTextSize = 10
	rewardSizeLimit.Parent = reward
	reward.Parent = card
	local status = label(
		"Status", "LOCKED",
		day == 7 and UDim2.fromOffset(330, 20) or UDim2.new(1, -12, 0, 18),
		day == 7 and UDim2.fromOffset(120, 66) or UDim2.new(0, 6, 1, -20), 11
	)
	status.TextColor3 = Color3.fromRGB(170, 178, 198)
	status.Parent = card
end

local existing = StarterGui:FindFirstChild("DailyRewardUi")
if existing then existing:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "DailyRewardUi"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
gui.DisplayOrder = 500
gui.Parent = StarterGui

local dimmer = Instance.new("Frame")
dimmer.Name = "Dimmer"
dimmer.Size = UDim2.fromScale(1, 1)
dimmer.BackgroundColor3 = Color3.fromRGB(12, 15, 22)
dimmer.BackgroundTransparency = 0.28
dimmer.BorderSizePixel = 0
dimmer.Visible = false
dimmer.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(560, 590)
panel.BackgroundColor3 = COLORS.Panel
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
local scale = Instance.new("UIScale")
scale.Name = "ResponsiveScale"
scale.Parent = panel

local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 64)
header.BackgroundColor3 = COLORS.Header
header.BorderSizePixel = 0
header.Parent = panel
addCorner(panel, UDim.new(0, 4))
addStroke(panel, Color3.fromRGB(150, 100, 210), 1)
addCorner(header, UDim.new(0, 4))

-- Лента-закладка слева в шапке — тот же элемент, что в магазине/квестах,
-- ради единого стиля всех окон.
local ribbon = Instance.new("Frame")
ribbon.Name = "RibbonIcon"
ribbon.AnchorPoint = Vector2.new(0, 0)
ribbon.Position = UDim2.fromOffset(14, 0)
ribbon.Size = UDim2.fromOffset(24, 38)
ribbon.BackgroundColor3 = COLORS.Ribbon
ribbon.BorderSizePixel = 0
ribbon.ZIndex = 4
ribbon.Parent = header
for _, xOffset in { -1, 1 } do
	local notch = Instance.new("Frame")
	notch.AnchorPoint = Vector2.new(0.5, 0)
	notch.Position = UDim2.new(0.5, xOffset * 6, 1, -6)
	notch.Size = UDim2.fromOffset(9, 9)
	notch.Rotation = 45
	notch.BackgroundColor3 = COLORS.Header
	notch.BorderSizePixel = 0
	notch.ZIndex = 5
	notch.Parent = ribbon
end

label("Title", "DAILY REWARD", UDim2.new(1, -90, 1, 0), UDim2.fromOffset(24, 0), 27).Parent = header
local close = Instance.new("TextButton")
close.Name = "CloseButton"
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -14, 0, 14)
close.Size = UDim2.fromOffset(42, 38)
close.BackgroundColor3 = Color3.new(0, 0, 0)
close.BackgroundTransparency = 1
close.TextColor3 = COLORS.Close
close.BorderSizePixel = 0
close.Font = Enum.Font.Arcade
close.Text = "X"
close.TextColor3 = COLORS.White
close.TextSize = 18
close.TextStrokeTransparency = 1
close.Parent = header

for day = 1, 6 do
	local column = (day - 1) % 3
	local row = math.floor((day - 1) / 3)
	rewardCard(day, UDim2.fromOffset(150, 150), UDim2.fromOffset(35 + column * 170, 76 + row * 164), panel)
end
rewardCard(7, UDim2.fromOffset(490, 94), UDim2.fromOffset(35, 405), panel)

local claim = Instance.new("TextButton")
claim.Name = "ClaimButton"
claim.Position = UDim2.fromOffset(35, 520)
claim.Size = UDim2.fromOffset(490, 48)
claim.BackgroundColor3 = COLORS.Yellow
claim.BorderSizePixel = 0
claim.Font = Enum.Font.Arcade
claim.Text = "CLAIM TODAY'S REWARD"
claim.TextColor3 = COLORS.White
claim.TextSize = 15
claim.TextStrokeTransparency = 1
claim.Active = false
claim.Parent = panel

print("[BuildDailyRewardUI] StarterGui/DailyRewardUi created. Replace each DayN/Icon image in Studio.")
end)

-- ============================================================================
-- BuildGroupRewardUI.lua — награда за группу
-- ============================================================================
__run("BuildGroupRewardUI.lua", "награда за группу", function()
--------------------------------------------------------------------------------
-- УСТАРЕЛО — оставлено, чтобы не ломать привычку и старые заметки.
--
-- Вёрстка обоих окон-подарков (GroupRewardUi и второго) собрана в ОДНОМ файле
-- tools/BuildRewardPopups.lua. Раньше здесь и в соседнем билдере лежало по
-- 240 строк, отличавшихся ровно пятью значениями — любая правка вёрстки
-- требовала одинакового ручного повтора в двух местах, и рано или поздно
-- они расходились.
--
-- Все настройки (какой скин выдавать, жеоды, тексты, цвета, размер карточки,
-- картинки подарка) вынесены в Config.GroupReward и Config.GroupReward.Ui —
-- их можно менять, вообще не открывая .lua.
--
-- Этот файл просто запускает общий билдер, чтобы старая команда продолжала
-- работать. Собираются СРАЗУ ОБА окна — это дешево и гарантирует, что они
-- не разъедутся между собой.
--------------------------------------------------------------------------------

warn("[BuildGroupRewardUI] Этот билдер объединён с соседним. Запускаю tools/BuildRewardPopups.lua — он соберёт оба окна-подарка.")
require(script.Parent.BuildRewardPopups)
end)

-- ============================================================================
-- BuildLikeRewardUI.lua — награда за лайк
-- ============================================================================
__run("BuildLikeRewardUI.lua", "награда за лайк", function()
--------------------------------------------------------------------------------
-- УСТАРЕЛО — оставлено, чтобы не ломать привычку и старые заметки.
--
-- Вёрстка обоих окон-подарков (LikeRewardUi и второго) собрана в ОДНОМ файле
-- tools/BuildRewardPopups.lua. Раньше здесь и в соседнем билдере лежало по
-- 240 строк, отличавшихся ровно пятью значениями — любая правка вёрстки
-- требовала одинакового ручного повтора в двух местах, и рано или поздно
-- они расходились.
--
-- Все настройки (какой скин выдавать, жеоды, тексты, цвета, размер карточки,
-- картинки подарка) вынесены в Config.LikeReward и Config.LikeReward.Ui —
-- их можно менять, вообще не открывая .lua.
--
-- Этот файл просто запускает общий билдер, чтобы старая команда продолжала
-- работать. Собираются СРАЗУ ОБА окна — это дешево и гарантирует, что они
-- не разъедутся между собой.
--------------------------------------------------------------------------------

warn("[BuildLikeRewardUI] Этот билдер объединён с соседним. Запускаю tools/BuildRewardPopups.lua — он соберёт оба окна-подарка.")
require(script.Parent.BuildRewardPopups)
end)

-- ============================================================================
-- BuildStarterPackUI.lua — стартовый пак
-- ============================================================================
__run("BuildStarterPackUI.lua", "стартовый пак", function()
--------------------------------------------------------------------------------
-- Standalone Studio builder for StarterGui/StarterPackOffer — баннер с
-- радужной надписью "STARTER KIT" + отсчётом (см. Config.DevProducts.
-- StarterPack.OfferWindowSeconds) и экран "что внутри" с ценой и кнопкой
-- покупки. Вся анимация (радуга/отсчёт) и логика показа — в
-- src/client/StarterPackUI.client.lua, здесь только статичная разметка.
-- Rerunning this script destroys and rebuilds only this exact ScreenGui.
--------------------------------------------------------------------------------

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

Config.DevProducts = Config.DevProducts or {}
local pack = Config.DevProducts.StarterPack or { PriceRobux = 99, Contents = {} }
local STARTER_PACK_ICON_IMAGE = "rbxassetid://100116175987177"

local COLORS = {
	Panel = Color3.fromRGB(29, 34, 47),
	Header = Color3.fromRGB(55, 91, 166),
	Row = Color3.fromRGB(40, 46, 62),
	White = Color3.fromRGB(245, 247, 255),
	Green = Color3.fromRGB(80, 195, 90),
	Banner = Color3.fromRGB(24, 27, 38),
}

local function label(name, text, size, position, textSize)
	local item = Instance.new("TextLabel")
	item.Name = name
	item.Size = size
	item.Position = position
	item.BackgroundTransparency = 1
	item.Font = Enum.Font.Arcade
	item.Text = text
	item.TextColor3 = COLORS.White
	item.TextSize = textSize
	item.TextStrokeTransparency = 1
	item.TextWrapped = true
	return item
end

local existing = StarterGui:FindFirstChild("StarterPackOffer")
if existing then existing:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "StarterPackOffer"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
gui.DisplayOrder = 400
gui.Parent = StarterGui

--------------------------------------------------------------------------------
-- БАННЕР — плашка справа по центру. Enabled/Visible полностью
-- решает клиент (см. StarterPackUI.client.lua): новый ли игрок, в окне ли
-- ещё OfferWindowSeconds, не куплен ли пак уже.
--------------------------------------------------------------------------------
local banner = Instance.new("ImageButton")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(1, 1)
banner.Position = UDim2.new(1, -20, 1, -20)
banner.Size = UDim2.fromOffset(286, 86)
banner.BackgroundColor3 = COLORS.Banner
banner.BorderSizePixel = 0
banner.AutoButtonColor = false
banner.Image = ""
banner.ZIndex = 10
banner.Visible = false
banner.Parent = gui

local bannerIcon = Instance.new("ImageLabel")
bannerIcon.Name = "Icon"
bannerIcon.AnchorPoint = Vector2.new(0, 0.5)
bannerIcon.Position = UDim2.fromOffset(10, 43)
bannerIcon.Size = UDim2.fromOffset(66, 66)
bannerIcon.BackgroundTransparency = 1
bannerIcon.ScaleType = Enum.ScaleType.Fit
bannerIcon.Image = STARTER_PACK_ICON_IMAGE
bannerIcon.ZIndex = 11
bannerIcon.Parent = banner

-- Цвет здесь ЛЮБОЙ (StarterPackUI.client.lua перекрашивает его в цикле HSV
-- каждый кадр, пока баннер виден) — TextColor3 ниже просто стартовое значение.
local rainbowTitle = label("RainbowTitle", "STARTER KIT", UDim2.new(1, -88, 0, 28), UDim2.fromOffset(84, 7), 20)
rainbowTitle.TextColor3 = Color3.fromRGB(255, 90, 90)
rainbowTitle.ZIndex = 11
rainbowTitle.Parent = banner

local countdown = label("Countdown", "10:00", UDim2.new(1, -88, 0, 24), UDim2.fromOffset(84, 39), 18)
countdown.TextColor3 = Color3.fromRGB(220, 225, 235)
countdown.ZIndex = 11
countdown.Parent = banner

--------------------------------------------------------------------------------
-- ЭКРАН "ЧТО ВНУТРИ" — открывается кликом по баннеру.
--------------------------------------------------------------------------------
local dimmer = Instance.new("TextButton")
dimmer.Name = "Dimmer"
dimmer.Size = UDim2.fromScale(1, 1)
dimmer.BackgroundColor3 = Color3.fromRGB(12, 15, 22)
dimmer.BackgroundTransparency = 0.35
dimmer.BorderSizePixel = 0
dimmer.AutoButtonColor = false
dimmer.Text = ""
dimmer.Visible = false
dimmer.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "Details"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
local rowCount = math.max(1, #pack.Contents)
panel.Size = UDim2.fromOffset(420, 168 + rowCount * 36)
panel.BackgroundColor3 = COLORS.Panel
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
local scale = Instance.new("UIScale")
scale.Name = "ResponsiveScale"
scale.Parent = panel

local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 56)
header.BackgroundColor3 = COLORS.Header
header.BorderSizePixel = 0
header.Parent = panel
local title = label("Title", "STARTER KIT", UDim2.new(1, -60, 1, 0), UDim2.fromOffset(20, 0), 24)
title.Parent = header
local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -12, 0, 10)
closeButton.Size = UDim2.fromOffset(38, 36)
closeButton.BackgroundColor3 = Color3.fromRGB(190, 65, 70)
closeButton.BorderSizePixel = 0
closeButton.Font = Enum.Font.Arcade
closeButton.Text = "X"
closeButton.TextColor3 = COLORS.White
closeButton.TextSize = 18
closeButton.TextStrokeTransparency = 1
closeButton.Parent = header

-- Строки списка — один в один по Config.DevProducts.StarterPack.Contents.
-- Правишь ТЕКСТ содержимого пака в Config.lua, а не здесь; перезапускаешь
-- этот билдер только если поменялось ЧИСЛО строк (иначе панель не той
-- высоты) или нужно поправить сам стиль строки.
local contentsFrame = Instance.new("Frame")
contentsFrame.Name = "Contents"
contentsFrame.Position = UDim2.fromOffset(20, 68)
contentsFrame.Size = UDim2.new(1, -40, 0, rowCount * 36)
contentsFrame.BackgroundTransparency = 1
contentsFrame.Parent = panel

for index, line in pack.Contents do
	local row = Instance.new("Frame")
	row.Name = "Row" .. index
	row.Position = UDim2.fromOffset(0, (index - 1) * 36)
	row.Size = UDim2.new(1, 0, 0, 32)
	row.BackgroundColor3 = COLORS.Row
	row.BorderSizePixel = 0
	row.Parent = contentsFrame

	local checkmark = label("Checkmark", "✔", UDim2.fromOffset(28, 32), UDim2.fromOffset(6, 0), 16)
	checkmark.TextColor3 = COLORS.Green
	checkmark.Parent = row

	local text = label("Text", line, UDim2.new(1, -44, 1, 0), UDim2.fromOffset(38, 0), 15)
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.Parent = row
end

local buyButton = Instance.new("TextButton")
buyButton.Name = "BuyButton"
buyButton.Position = UDim2.fromOffset(20, 88 + rowCount * 36)
buyButton.Size = UDim2.new(1, -40, 0, 48)
buyButton.BackgroundColor3 = COLORS.Green
buyButton.BorderSizePixel = 0
buyButton.Font = Enum.Font.Arcade
buyButton.Text = ("BUY FOR R$ %d"):format(pack.PriceRobux or 99)
buyButton.TextColor3 = Color3.fromRGB(20, 25, 20)
buyButton.TextSize = 18
buyButton.TextStrokeTransparency = 1
buyButton.Parent = panel

print("[BuildStarterPackUI] StarterGui/StarterPackOffer создан. Замени Banner/Icon и добавь иконки к строкам Contents в Studio при желании.")
end)

-- ============================================================================
-- BuildReturnScreenUI.lua — экран возвращения
-- ============================================================================
__run("BuildReturnScreenUI.lua", "экран возвращения", function()
-- Standalone Command Bar builder for StarterGui/ReturnScreenUi.
-- Rerunning destroys and rebuilds only ReturnScreenUi.
--
-- Раньше "экран возвращения" (src/client/ReturnScreenUI.client.lua) собирался
-- ПОЛНОСТЬЮ кодом в рантайме — единственный экран в проекте без авторской
-- версии в StarterGui, которую можно подвинуть/перекрасить в Studio, как это
-- уже сделано для Daily Reward / Group Reward / Like Reward и т.д.
--
-- Этот билдер кладёт готовую именованную иерархию в StarterGui/ReturnScreenUi.
-- Клиентский скрипт при старте её находит (playerGui клонирует StarterGui
-- автоматически) и просто подставляет текст/цвета/видимость строк — никакой
-- геометрии в коде клиента больше нет. Если билдер не запущен (например,
-- сразу после клонирования репозитория), клиент соберёт временный fallback
-- по тем же цветам, чтобы игра не сломалась, и напомнит запустить этот файл.
--
-- Контракт (что обязано существовать под этими именами — клиент проверяет их
-- при старте и откажется работать с внятным warn, если что-то не так):
--   ReturnScreenUi (ScreenGui)
--     Dimmer (Frame)
--     Panel (Frame)
--       Title (TextLabel)
--       AwaySubtitle (TextLabel)
--       RowCart (Frame) -> Icon, Label, Value (TextLabel)
--       RowSafe (Frame) -> Icon, Label, Value (TextLabel)
--       RowStreak (Frame) -> Icon, Label, Value (TextLabel)
--       HintLabel (TextLabel)
--       CollectButton (TextButton)

local StarterGui = game:GetService("StarterGui")

-- Та же палитра, что использовал прежний процедурный экран — правки цвета
-- теперь достаточно сделать здесь ИЛИ руками в Studio на готовых инстансах,
-- код клиента их не трогает.
local COLORS = {
	Dimmer = Color3.new(0, 0, 0),
	PanelBg = Color3.fromRGB(18, 22, 32),
	PanelStroke = Color3.fromRGB(90, 130, 200),
	RowBg = Color3.fromRGB(28, 33, 46),
	Title = Color3.fromRGB(255, 255, 255),
	Subtitle = Color3.fromRGB(138, 147, 166),
	Caption = Color3.fromRGB(196, 204, 220),
	ValueDefault = Color3.fromRGB(255, 255, 255),
	CartValue = Color3.fromRGB(120, 220, 255),
	SafeValue = Color3.fromRGB(95, 255, 130),
	StreakValue = Color3.fromRGB(255, 190, 70),
	Hint = Color3.fromRGB(138, 147, 166),
	ButtonBg = Color3.fromRGB(60, 150, 250),
	ButtonText = Color3.new(1, 1, 1),
}

local function corner(parent, radius)
	local instance = Instance.new("UICorner")
	instance.CornerRadius = UDim.new(0, radius)
	instance.Parent = parent
	return instance
end

local function stroke(parent, thickness, color, transparency)
	local instance = Instance.new("UIStroke")
	instance.Thickness = thickness
	instance.Color = color
	instance.Transparency = transparency or 0
	instance.Parent = parent
	return instance
end

-- Строка итога: иконка-эмодзи + подпись слева, значение справа — тот же
-- макет, что раньше строился в коде (buildRow), плюс имена Icon/Label/Value,
-- по которым клиент теперь их находит и заполняет данными с сервера.
-- valueColor "по умолчанию" сохраняется в атрибут RowDefaultValueColor —
-- клиент красит цифру в него, когда для строки нет отдельного акцентного
-- цвета (иначе используется тот, что уже стоит на самой строке).
local function row(name, order, emoji, caption, valueColor, parent)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, 0, 0, 46)
	frame.BackgroundColor3 = COLORS.RowBg
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.Visible = false -- клиент включает нужные строки по факту данных
	frame:SetAttribute("RowValueColor", valueColor)
	frame.Parent = parent
	corner(frame, 10)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = frame

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0, 34, 1, 0)
	icon.BackgroundTransparency = 1
	icon.Font = Enum.Font.GothamBold
	icon.Text = emoji
	icon.TextScaled = true
	icon.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Position = UDim2.new(0, 40, 0, 0)
	label.Size = UDim2.new(1, -40, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.Text = caption
	label.TextColor3 = COLORS.Caption
	label.TextSize = 15
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = frame

	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.Size = UDim2.fromScale(1, 1)
	value.BackgroundTransparency = 1
	value.Font = Enum.Font.GothamBold
	value.Text = ""
	value.TextColor3 = valueColor or COLORS.ValueDefault
	value.TextSize = 17
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.Parent = frame

	return frame
end

local existing = StarterGui:FindFirstChild("ReturnScreenUi")
if existing then existing:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "ReturnScreenUi"
-- Как и у остального UI проекта: респавн в игре ручной (CharacterAutoLoads =
-- false), дефолтный ResetOnSpawn = true уничтожил бы экран при респавне.
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 900

local dimmer = Instance.new("Frame")
dimmer.Name = "Dimmer"
dimmer.Size = UDim2.fromScale(1, 1)
dimmer.BackgroundColor3 = COLORS.Dimmer
dimmer.BackgroundTransparency = 1
dimmer.BorderSizePixel = 0
dimmer.Visible = false
dimmer.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
-- Size в Scale с ограничителем: на телефоне панель занимает почти всю
-- ширину, на мониторе не растягивается в простыню.
panel.Size = UDim2.new(0.86, 0, 0, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = COLORS.PanelBg
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
corner(panel, 16)
stroke(panel, 2, COLORS.PanelStroke, 0.35)

local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MaxSize = Vector2.new(420, math.huge)
sizeLimit.Parent = panel

local scale = Instance.new("UIScale")
scale.Name = "PanelScale"
scale.Scale = 0.9
scale.Parent = panel

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 18)
pad.PaddingBottom = UDim.new(0, 18)
pad.PaddingLeft = UDim.new(0, 18)
pad.PaddingRight = UDim.new(0, 18)
pad.Parent = panel

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 8)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.LayoutOrder = 0
title.Size = UDim2.new(1, 0, 0, 26)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.Text = "WHILE YOU WERE AWAY"
title.TextColor3 = COLORS.Title
title.TextSize = 20
title.Parent = panel

local subtitle = Instance.new("TextLabel")
subtitle.Name = "AwaySubtitle"
subtitle.LayoutOrder = 1
subtitle.Size = UDim2.new(1, 0, 0, 18)
subtitle.BackgroundTransparency = 1
subtitle.Font = Enum.Font.GothamMedium
subtitle.Text = "You were gone"
subtitle.TextColor3 = COLORS.Subtitle
subtitle.TextSize = 14
subtitle.Parent = panel

local spacer = Instance.new("Frame")
spacer.Name = "Spacer"
spacer.LayoutOrder = 2
spacer.Size = UDim2.new(1, 0, 0, 6)
spacer.BackgroundTransparency = 1
spacer.Parent = panel

-- Фиксированный набор из трёх строк (Cart / Safe / Streak), а не динамически
-- досоздаваемых — как Day1..Day7 в Daily Reward. UIListLayout сам убирает
-- зазор под невидимые строки, так что клиенту достаточно переключать
-- Row.Visible по факту, какие поля пришли в пакете с сервера.
row("RowCart", 3, "⛏️", "Mine kept working", COLORS.CartValue, panel)
row("RowSafe", 4, "🔐", "Safe accumulated", COLORS.SafeValue, panel)
row("RowStreak", 5, "🔥", "Streak", COLORS.StreakValue, panel)

local hint = Instance.new("TextLabel")
hint.Name = "HintLabel"
hint.LayoutOrder = 6
hint.Size = UDim2.new(1, 0, 0, 16)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.Gotham
hint.Text = "Your cart is loaded — deliver it to the bank"
hint.TextColor3 = COLORS.Hint
hint.TextSize = 12
hint.Visible = false
hint.Parent = panel

local button = Instance.new("TextButton")
button.Name = "CollectButton"
button.LayoutOrder = 7
button.Size = UDim2.new(1, 0, 0, 44)
button.BackgroundColor3 = COLORS.ButtonBg
button.BorderSizePixel = 0
button.Font = Enum.Font.GothamBold
button.Text = "COLLECT ALL"
button.TextColor3 = COLORS.ButtonText
button.TextSize = 17
button.AutoButtonColor = true
button.Parent = panel
corner(button, 10)

gui.Parent = StarterGui

print("[BuildReturnScreenUI] StarterGui/ReturnScreenUi created. Tweak colors/layout freely in Studio — the client script only fills text/visibility by name.")
end)

-- ============================================================================
-- BuildRebirthDialogUI.lua — окно престижа — PrestigeUiBuilder
-- ============================================================================
__run("BuildRebirthDialogUI.lua", "окно престижа — PrestigeUiBuilder", function()
--------------------------------------------------------------------------------
-- BuildRebirthDialogUI — Studio Command Bar: StarterGui/RebirthDialogButtons
-- (окно престижа у NPC: условия слева, что получишь справа).
-- Вид — Shared.PrestigeUiBuilder. Всё разом — tools/BuildAllUI.lua.
--------------------------------------------------------------------------------
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local module = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("PrestigeUiBuilder")
assert(module, "[BuildRebirthDialogUI] Нет Shared.PrestigeUiBuilder — сначала Rojo-синк.")
local existing = StarterGui:FindFirstChild("RebirthDialogButtons")
if existing then existing:Destroy() end
require(module).Build().Parent = StarterGui
print("[BuildRebirthDialogUI] Готово: StarterGui/RebirthDialogButtons.")
end)

-- ============================================================================
-- BuildRewardPopups.lua — всплывающие награды
-- ============================================================================
__run("BuildRewardPopups.lua", "всплывающие награды", function()
--------------------------------------------------------------------------------
-- BuildRewardPopups
--
-- ОДИН билдер на ВСЕ окна-подарки: награда за Favorite+лайк (LikeRewardUi) и
-- награда за лайк+вступление в группу (GroupRewardUi).
--
-- Запуск: вставить в Command Bar в Studio.
--   require(game.ServerScriptService.tools.BuildRewardPopups)
-- или просто открыть файл и выполнить его содержимое в Command Bar.
--
-- Пересборка уничтожает и создаёт заново ТОЛЬКО те ScreenGui, что перечислены
-- в POPUPS ниже. Остальной StarterGui не трогается.
--
--------------------------------------------------------------------------------
-- ЗАЧЕМ ОДИН ФАЙЛ ВМЕСТО ДВУХ
--
-- Раньше было два билдера — BuildLikeRewardUI.lua и BuildGroupRewardUI.lua, —
-- по 240 строк каждый, и отличались они РОВНО ПЯТЬЮ строками: два цвета
-- подарка, имя подписи, имя кнопки и текст на кнопке. Всё остальное было
-- посимвольной копией. На практике это означало, что любая правка вёрстки
-- (сдвинуть кнопку, поменять шрифт, добавить элемент) требовала одинаковой
-- ручной правки в двух местах, и рано или поздно они расходились.
--
-- Теперь вёрстка одна, а различия вынесены в Config.LikeReward.Ui и
-- Config.GroupReward.Ui — их можно править, вообще не открывая .lua-файлы.
--
--------------------------------------------------------------------------------
-- ЧТО МОЖНО МЕНЯТЬ И ГДЕ
--
--   • КАКОЙ СКИН ВЫДАЁТСЯ  → Config.LikeReward.SkinId / Config.GroupReward.SkinId
--     (любой ключ из Config.Skins.Definitions). Билдер ПРОВЕРЯЕТ, что такой
--     скин существует и что у него есть AssetName, и громко ругается, если
--     нет — раньше опечатка в SkinId обнаруживалась только когда живой игрок
--     нажимал CLAIM и не получал ничего.
--   • Жеоды за награду  → GeodeType / GeodeCount там же.
--   • Тексты, цвета, размер карточки → Config.*.Ui (см. комментарии там).
--   • Картинки подарка   → Config.*.Images (включая Images.Header —
--     баннер шапки карточки; как он тянется, задаёт Ui.HeaderScaleType).
--   • Когда показывать   → FirstShowDelay / RepeatDelay / MaxShowsPerSession.
--
-- ЧТО МЕНЯТЬ НЕЛЬЗЯ (контракт с клиентскими скриптами — они ищут по именам):
--   Dimmer, Gift, GiftHalfLeft, GiftHalfRight, Flash, Card, Header, Title,
--   CloseButton, IconRow, SkinIcon, GeodeIcon, Label (внутри иконок), Body,
--   LikeNote, и имя кнопки действия из Config.*.Ui.ActionButtonName.
--   Переименуешь — соответствующая часть окна просто перестанет работать.
--------------------------------------------------------------------------------

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

-- Список окон, которые собирает этот файл. Чтобы добавить третье окно-подарок,
-- достаточно дописать сюда ещё одну строку и создать соответствующий блок в
-- Config — трогать код вёрстки ниже не нужно.
local POPUPS = {
	{ Name = "LikeReward", Reward = Config.LikeReward },
	{ Name = "GroupReward", Reward = Config.GroupReward },
}

--------------------------------------------------------------------------------
-- Мелкие помощники.
--------------------------------------------------------------------------------

local function imageUri(id)
	return id and id ~= 0 and ("rbxassetid://" .. tostring(id)) or ""
end

local function applyImage(instance, id)
	if not id or id == 0 then return end
	instance.Image = imageUri(id)
	instance.ScaleType = Enum.ScaleType.Fit
	instance.BackgroundTransparency = 1
end

local function addCorner(instance, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function addStroke(instance, color, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Parent = instance
end

-- Значение из Config.*.Ui с запасным вариантом. Нужен, чтобы билдер не падал
-- на конфиге, собранном до появления блока Ui, и чтобы можно было спокойно
-- удалить любое поле из конфига, если оно устраивает по умолчанию.
local function ui(reward, key, fallback)
	local settings = reward.Ui
	local value = settings and settings[key]
	if value == nil then return fallback end
	return value
end

--------------------------------------------------------------------------------
-- ПРОВЕРКА НАГРАДЫ.
--
-- Смысл: поймать опечатку в конфиге ЗДЕСЬ, в Studio, где её видно сразу, а не
-- в проде через жалобу «нажал забрать, ничего не дали». Именно так и выглядел
-- реальный баг с наградой за группу: SkinId указывал на скин, который сервис
-- выдать не мог, и награда молча помечалась забранной.
--------------------------------------------------------------------------------
local function validateReward(name, reward)
	local problems = {}

	local skin = Config.Skins.Definitions[reward.SkinId]
	if not skin then
		table.insert(problems, ("SkinId = %q — такого ключа нет в Config.Skins.Definitions"):format(tostring(reward.SkinId)))
	elseif not skin.AssetName or skin.AssetName == "" then
		table.insert(problems, ("скин %s не имеет AssetName — выдать его нельзя"):format(tostring(reward.SkinId)))
	else
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		if assets and not assets:FindFirstChild(skin.AssetName) then
			table.insert(problems, ("в ReplicatedStorage/Assets нет модели %q (нужна для скина %s)"):format(
				tostring(skin.AssetName), tostring(reward.SkinId)))
		end
	end

	if not Config.Geodes.Types[reward.GeodeType] then
		table.insert(problems, ("GeodeType = %q — такого типа нет в Config.Geodes.Types"):format(tostring(reward.GeodeType)))
	end

	if name == "GroupReward" and (tonumber(reward.GroupId) or 0) <= 0 then
		table.insert(problems, "GroupId = 0 — кнопка вступления в группу работать не будет")
	end

	for _, problem in problems do
		warn(("[BuildRewardPopups] Config.%s: %s"):format(name, problem))
	end
	if #problems == 0 then
		local skinName = skin and skin.DisplayName or "?"
		print(("[BuildRewardPopups] Config.%s: награда — %s (%s) + %d x %s жеода."):format(
			name, tostring(reward.SkinId), skinName, reward.GeodeCount or 0, tostring(reward.GeodeType)))
	end
end

--------------------------------------------------------------------------------
-- СБОРКА ОДНОГО ОКНА.
--------------------------------------------------------------------------------
local function build(name, reward)
	validateReward(name, reward)

	local guiName = ui(reward, "ScreenGuiName", name .. "Ui")
	local font = ui(reward, "Font", Enum.Font.FredokaOne)
	local cardWidth = ui(reward, "CardWidth", 400)
	local cardHeight = ui(reward, "CardHeight", 370)
	local giftSize = ui(reward, "GiftSize", 170)

	local existing = StarterGui:FindFirstChild(guiName)
	if existing then existing:Destroy() end

	local gui = Instance.new("ScreenGui")
	gui.Name = guiName
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = ui(reward, "DisplayOrder", 40)
	gui.Enabled = false
	gui.Parent = StarterGui

	local dimmer = Instance.new("Frame")
	dimmer.Name = "Dimmer"
	dimmer.Size = UDim2.fromScale(1, 1)
	dimmer.BackgroundColor3 = Color3.new(0, 0, 0)
	dimmer.BackgroundTransparency = 0.45
	dimmer.BorderSizePixel = 0
	-- ZIndex 1 — строго НИЖЕ карточки (2) и подарка (3). Затемнение,
	-- оказавшееся на одном уровне с карточкой, перехватывает нажатия по
	-- крестику: именно этот класс ошибки уже ловили в меню жеод.
	dimmer.ZIndex = 1
	dimmer.Parent = gui

	local gift = Instance.new("ImageLabel")
	gift.Name = "Gift"
	gift.AnchorPoint = Vector2.new(0.5, 0.5)
	gift.Position = UDim2.fromScale(0.5, 0.45)
	--------------------------------------------------------------------------
	-- ПОЧЕМУ РЕАЛЬНЫЙ РАЗМЕР, А НЕ НОЛЬ.
	--
	-- Раньше билдер ставил подарку и карточке Size = (0, 0) и
	-- Visible = false — «размер задаст анимация в клиенте». Формально
	-- верно: showPopup при каждом показе сам выставляет и размер, и
	-- позицию, и видимость, так что на игру это никак не влияло.
	--
	-- Но в Studio это делало ассет НЕРЕДАКТИРУЕМЫМ: включаешь Enabled у
	-- ScreenGui — и видишь только затемнение, потому что всё остальное
	-- невидимо и имеет нулевой размер. Выглядит ровно как «билдер собрал
	-- окно неправильно, оно не появляется / оно не по центру».
	--
	-- Теперь всё строится в НАСТОЯЩЕМ размере и на своём месте. В игре
	-- ничего не меняется (клиент всё равно переприсваивает эти поля перед
	-- анимацией), зато ассет можно нормально открыть и править глазами.
	--------------------------------------------------------------------------
	gift.Size = UDim2.fromOffset(giftSize, giftSize)
	gift.BackgroundColor3 = ui(reward, "GiftColor", Color3.fromRGB(210, 60, 90))
	gift.BorderSizePixel = 0
	-- Подарок скрыт, а карточка показана: при включении Enabled в Studio
	-- сразу видно ГЛАВНОЕ — саму карточку с наградой, которую и хочется
	-- править. Чтобы посмотреть коробку подарка, поставь здесь Visible
	-- вручную в Studio (в игре это состояние всё равно перезадаётся).
	gift.Visible = false
	gift.ZIndex = 3
	gift.Parent = gui
	applyImage(gift, reward.Images and reward.Images.GiftClosed)
	addCorner(gift, 14)

	local function makeHalf(halfName, anchorX, imageId)
		local half = Instance.new("ImageLabel")
		half.Name = halfName
		half.AnchorPoint = Vector2.new(anchorX, 0.5)
		half.Position = UDim2.fromScale(0.5, 0.45)
		-- Половинки — ровно половина ширины подарка и его полная высота,
		-- чтобы «разлом» сходился без щели при любом GiftSize.
		half.Size = UDim2.fromOffset(giftSize / 2, giftSize)
		half.BackgroundColor3 = ui(reward, "GiftHalfColor", Color3.fromRGB(180, 45, 75))
		half.BorderSizePixel = 0
		half.Visible = false
		half.ZIndex = 3
		half.Parent = gui
		applyImage(half, imageId)
	end
	makeHalf("GiftHalfLeft", 1, reward.Images and reward.Images.GiftHalfLeft)
	makeHalf("GiftHalfRight", 0, reward.Images and reward.Images.GiftHalfRight)

	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 4
	flash.Parent = gui

	local card = Instance.new("ImageLabel")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.45)
	-- Настоящий размер и Visible = true — см. подробный комментарий у gift
	-- выше. В игре анимация всё равно начинает с нуля и раскрывает карточку
	-- до этих же CardWidth x CardHeight.
	card.Size = UDim2.fromOffset(cardWidth, cardHeight)
	card.BackgroundColor3 = ui(reward, "PanelColor", Color3.fromRGB(35, 33, 42))
	card.BorderSizePixel = 0
	card.Visible = true
	card.ClipsDescendants = true
	card.ZIndex = 2
	card.Parent = gui
	applyImage(card, reward.Images and reward.Images.CardBackground)
	addCorner(card, 14)
	addStroke(card, ui(reward, "StrokeColor", Color3.fromRGB(20, 20, 25)), 2)
	-- UIScale на карточке — тот самый, который клиент использует, чтобы
	-- ужать окно под узкий экран телефона. Создаём его СРАЗУ здесь, а не
	-- ждём, пока клиент добавит свой в рантайме: иначе в Studio его нет, и
	-- проверить, как карточка ляжет на мобильном разрешении, невозможно.
	local cardUiScale = Instance.new("UIScale")
	cardUiScale.Scale = 1
	cardUiScale.Parent = card

	-- Целевой размер кладём атрибутами: клиент читает их для анимации
	-- раскрытия и для расчёта UIScale под экран телефона. Так размер
	-- карточки задаётся ТОЛЬКО в конфиге и нигде не дублируется.
	card:SetAttribute("CardWidth", cardWidth)
	card:SetAttribute("CardHeight", cardHeight)

	--------------------------------------------------------------------------
	-- ШАПКА — ImageLabel, А НЕ Frame (по прямому запросу).
	--
	-- Frame умеет только сплошную заливку. ImageLabel умеет и её (пока
	-- картинка не задана — ведёт себя ровно как раньше, красится в
	-- Ui.HeaderColor), и нарисованный баннер с рамкой и узором.
	--
	-- Клиентские скрипты шапку не трогают вообще — они ищут Title и
	-- CloseButton, а те лежат ВНУТРИ неё, — поэтому смена класса ничего не
	-- ломает. Проверено по обоим файлам.
	--------------------------------------------------------------------------
	local header = Instance.new("ImageLabel")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 54)
	header.BackgroundColor3 = ui(reward, "HeaderColor", Color3.fromRGB(60, 110, 200))
	header.BorderSizePixel = 0
	header.Image = ""
	header.ZIndex = 3
	header.Parent = card

	local headerImageId = reward.Images and reward.Images.Header
	if headerImageId and headerImageId ~= 0 then
		header.Image = imageUri(headerImageId)
		-- Картинка есть — заливку убираем, иначе цвет проступал бы сквозь
		-- прозрачные места баннера.
		header.BackgroundTransparency = 1

		local scaleTypeName = ui(reward, "HeaderScaleType", "Stretch")
		if scaleTypeName == "Slice" then
			-- 9-slice: углы баннера не тянутся, растягивается только
			-- середина. Единственный режим, при котором рамка на шапке
			-- любой ширины выглядит одинаково аккуратно.
			header.ScaleType = Enum.ScaleType.Slice
			header.SliceCenter = ui(reward, "HeaderSliceCenter", Rect.new(24, 24, 24, 24))
		elseif scaleTypeName == "Fit" then
			header.ScaleType = Enum.ScaleType.Fit
		else
			-- Stretch — поведение по умолчанию у ImageLabel: картинка
			-- растягивается на весь прямоугольник шапки.
			header.ScaleType = Enum.ScaleType.Stretch
			if scaleTypeName ~= "Stretch" then
				-- Опечатку в конфиге лучше назвать вслух: молчаливый
				-- откат к Stretch выглядит как «9-slice не работает».
				warn(("[BuildRewardPopups] Config.%s.Ui.HeaderScaleType = %q — допустимы только \"Stretch\", \"Slice\", \"Fit\". Использую Stretch."):format(
					name, tostring(scaleTypeName)))
			end
		end
	end

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0, 0.5)
	title.Position = UDim2.new(0, 18, 0.5, 0)
	title.Size = UDim2.new(1, -72, 0, 32)
	title.BackgroundTransparency = 1
	title.Font = font
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	-- Цвет заголовка отдельной настройкой: на нарисованном светлом баннере
	-- белый текст читаться не будет.
	title.TextColor3 = ui(reward, "TitleColor", Color3.new(1, 1, 1))
	title.Text = reward.Title or ""
	title.ZIndex = 4
	title.Parent = header

	local close = Instance.new("TextButton")
	close.Name = "CloseButton"
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, -11, 0.5, 0)
	close.Size = UDim2.fromOffset(34, 34)
	close.BackgroundColor3 = ui(reward, "CloseColor", Color3.fromRGB(220, 70, 70))
	close.Font = font
	close.TextScaled = true
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Text = "X"
	close.AutoButtonColor = false
	-- Крестик выше всего внутри карточки — чтобы никакая декоративная
	-- деталь, добавленная позже, не смогла перекрыть нажатие.
	close.ZIndex = 10
	close.Parent = header
	addCorner(close, 17)

	local iconRow = Instance.new("Frame")
	iconRow.Name = "IconRow"
	iconRow.AnchorPoint = Vector2.new(0.5, 0)
	iconRow.Position = UDim2.new(0.5, 0, 0, 66)
	iconRow.Size = UDim2.new(1, -40, 0, 94)
	iconRow.BackgroundTransparency = 1
	iconRow.ZIndex = 3
	iconRow.Parent = card
	local iconLayout = Instance.new("UIListLayout")
	iconLayout.FillDirection = Enum.FillDirection.Horizontal
	iconLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	iconLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	iconLayout.Padding = UDim.new(0, 18)
	iconLayout.Parent = iconRow

	-- Внутрь SkinIcon клиент кладёт ViewportFrame с 3D-моделью скина, а в
	-- Label — его название. Оба берутся из Config.*.SkinId в рантайме,
	-- поэтому здесь только пустые «рамки» правильных имён.
	local function makeRewardIcon(iconName)
		local icon = Instance.new("ImageLabel")
		icon.Name = iconName
		icon.Size = UDim2.fromOffset(92, 92)
		icon.BackgroundColor3 = ui(reward, "TileColor", Color3.fromRGB(55, 52, 68))
		icon.BorderSizePixel = 0
		icon.ScaleType = Enum.ScaleType.Fit
		icon.ZIndex = 3
		icon.Parent = iconRow
		addCorner(icon, 12)
		addStroke(icon, Color3.fromRGB(80, 76, 96), 1.5)
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.new(0.5, 0, 1, -4)
		label.Size = UDim2.new(1, -8, 0, 18)
		label.BackgroundTransparency = 1
		label.Font = font
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0
		label.ZIndex = 4
		label.Parent = icon
	end
	makeRewardIcon("SkinIcon")
	makeRewardIcon("GeodeIcon")

	local body = Instance.new("TextLabel")
	body.Name = "Body"
	body.AnchorPoint = Vector2.new(0.5, 0)
	body.Position = UDim2.new(0.5, 0, 0, 172)
	body.Size = UDim2.new(1, -40, 0, 70)
	body.BackgroundColor3 = ui(reward, "SurfaceColor", Color3.fromRGB(45, 43, 55))
	body.BorderSizePixel = 0
	body.Font = font
	body.TextSize = 17
	body.TextWrapped = true
	body.TextColor3 = ui(reward, "BodyTextColor", Color3.fromRGB(225, 225, 230))
	body.Text = reward.Body or ""
	body.ZIndex = 3
	body.Parent = card
	addCorner(body, 8)

	local note = Instance.new("TextLabel")
	note.Name = "LikeNote"
	note.AnchorPoint = Vector2.new(0.5, 0)
	note.Position = UDim2.new(0.5, 0, 0, 256)
	note.Size = UDim2.new(1, -40, 0, 24)
	note.BackgroundTransparency = 1
	note.Font = font
	note.TextSize = 16
	note.TextColor3 = ui(reward, "NoteTextColor", Color3.fromRGB(140, 195, 255))
	note.Text = ui(reward, "NoteText", "LIKE THE GAME TO SUPPORT US")
	note.ZIndex = 3
	note.Parent = card

	local action = Instance.new("TextButton")
	action.Name = ui(reward, "ActionButtonName", "ActionButton")
	action.AnchorPoint = Vector2.new(0.5, 0)
	action.Position = UDim2.new(0.5, 0, 0, 298)
	action.Size = UDim2.new(1, -40, 0, 50)
	action.BackgroundColor3 = ui(reward, "ActionColor", Color3.fromRGB(255, 190, 60))
	action.Font = font
	action.TextScaled = true
	action.TextColor3 = ui(reward, "ActionTextColor", Color3.fromRGB(40, 30, 10))
	action.Text = ui(reward, "ActionButtonText", "CLAIM")
	action.AutoButtonColor = false
	action.ZIndex = 3
	action.Parent = card
	addCorner(action, 10)

	print(("[BuildRewardPopups] %s собран: карточка %d x %d, подарок %d, кнопка %q. Включи Enabled у ScreenGui, чтобы увидеть и поправить окно прямо в Studio."):format(
		guiName, cardWidth, cardHeight, giftSize, action.Name))
end

for _, popup in POPUPS do
	if popup.Reward then
		build(popup.Name, popup.Reward)
	else
		warn(("[BuildRewardPopups] В Config нет блока %s — окно пропущено."):format(popup.Name))
	end
end

print("[BuildRewardPopups] Готово. Настройки — в Config.LikeReward.Ui / Config.GroupReward.Ui.")
end)

-- ============================================================================
-- BuildMoneyFx.lua — летящие деньги
-- ============================================================================
__run("BuildMoneyFx.lua", "летящие деньги", function()
-- Standalone Studio builder for the replaceable flying-money image.
-- It replaces only ReplicatedStorage/Assets/MoneyFxTemplate.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Assets = ReplicatedStorage:WaitForChild("Assets")
local Config = require(ReplicatedStorage.Shared.Config)

local existing = Assets:FindFirstChild("MoneyFxTemplate")
if existing then existing:Destroy() end

local template = Instance.new("ImageLabel")
template.Name = "MoneyFxTemplate"
template.Size = UDim2.fromOffset(18, 18)
template.BackgroundColor3 = Color3.fromRGB(255, 215, 90)
template.BorderSizePixel = 0
template.Image = Config.Icons.FlyingCoin ~= 0 and ("rbxassetid://" .. tostring(Config.Icons.FlyingCoin)) or ""
template.BackgroundTransparency = template.Image == "" and 0 or 1
template.ScaleType = Enum.ScaleType.Fit
template.Visible = true
template.Parent = Assets

print("[BuildMoneyFx] Assets/MoneyFxTemplate created. Set its Image in Studio to replace flying coins.")
end)

-- ============================================================================
-- BuildMobBillboardTemplates.lua — билборды мобов
-- ============================================================================
__run("BuildMobBillboardTemplates.lua", "билборды мобов", function()
--------------------------------------------------------------------------------
-- BuildMobBillboardTemplates
-- Запусти целиком через Studio Command Bar.
-- Создаёт редактируемые шаблоны экранных BillboardGui в StarterGui.
-- В игре GoblinBillboard.client.lua клонирует их и меняет только данные.
--------------------------------------------------------------------------------

local StarterGui = game:GetService("StarterGui")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local old = StarterGui:FindFirstChild("MobBillboardTemplates")
if old then old:Destroy() end

local templates = Instance.new("ScreenGui")
templates.Name = "MobBillboardTemplates"
templates.Enabled = false
templates.ResetOnSpawn = false
templates.IgnoreGuiInset = true
templates.DisplayOrder = 19
templates.Parent = StarterGui

local TEMPLATE_PIXELS = Vector2.new(200, 41)
local TEMPLATE_STUDS = Vector2.new(6, 1.23)

local function frame(parent, name, size, position)
	local object = Instance.new("Frame")
	object.Name = name
	object.Size = size
	object.Position = position or UDim2.fromScale(0, 0)
	object.BackgroundTransparency = 1
	object.BorderSizePixel = 0
	object.Parent = parent
	return object
end

local function text(parent, name, size, position, textSize)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.Position = position or UDim2.fromScale(0, 0)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 1
	label.AutomaticSize = Enum.AutomaticSize.None
	label.SizeConstraint = Enum.SizeConstraint.RelativeXY
	label.Text = ""
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.Arcade
	label.TextSize = textSize or 14
	label.TextScaled = false
	label.TextWrapped = false
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0
	label.Parent = parent
	return label
end

local function buildTemplate(name, boulder)
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.Size = UDim2.fromScale(TEMPLATE_STUDS.X, TEMPLATE_STUDS.Y)
	gui.SizeOffset = Vector2.new(0, 0.5)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 70
	gui.Enabled = false
	gui.Parent = templates

	if boulder then
		local icon = Instance.new("ImageLabel")
		icon.Name = "BoulderIcon"
		icon.Size = UDim2.fromOffset(38, 38)
		icon.Position = UDim2.fromOffset(1, 1)
		icon.BackgroundTransparency = 1
		icon.BorderSizePixel = 0
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Image = Config.Boulders.IconImage or ""
		icon.Parent = gui
		text(icon, "IconPlaceholder", UDim2.fromScale(1, 1), nil, 14).Text = "B"
	else
		local icon = Instance.new("ImageLabel")
		icon.Name = "GoblinIcon"
		icon.Size = UDim2.fromOffset(38, 38)
		icon.Position = UDim2.fromOffset(1, 1)
		icon.BackgroundTransparency = 1
		icon.BorderSizePixel = 0
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = gui
		text(icon, "IconPlaceholder", UDim2.fromScale(1, 1), nil, 14).Text = "G"
	end

	local info = frame(gui, "Info", UDim2.fromOffset(156, 38), UDim2.fromOffset(42, 1))
	local title = text(info, "Title", UDim2.new(1, -12, 0, 19), UDim2.fromOffset(6, 1), 14)
	title.RichText = true
	local healthBack = frame(info, "HealthBack", UDim2.new(1, -12, 0, 14), UDim2.new(0, 6, 1, -18))
	healthBack.BackgroundTransparency = 0.15
	healthBack.BackgroundColor3 = Color3.fromRGB(7, 8, 9)
	healthBack.ClipsDescendants = true
	local fill = frame(healthBack, "Fill", UDim2.fromScale(1, 1))
	fill.BackgroundTransparency = 0
	fill.BackgroundColor3 = Color3.fromRGB(104, 207, 80)
	text(healthBack, "Health", UDim2.fromScale(1, 1), nil, 14)

	-- BillboardGui Scale is measured in studs. Remove every pixel offset so the
	-- complete layout shrinks naturally with distance instead of staying huge.
	local function convertChildrenToScale(parent, parentPixels)
		for _, child in parent:GetChildren() do
			if child:IsA("GuiObject") then
				local oldSize = child.Size
				local oldPosition = child.Position
				local childPixels = Vector2.new(
					parentPixels.X * oldSize.X.Scale + oldSize.X.Offset,
					parentPixels.Y * oldSize.Y.Scale + oldSize.Y.Offset
				)
				child.Size = UDim2.fromScale(
					oldSize.X.Scale + oldSize.X.Offset / parentPixels.X,
					oldSize.Y.Scale + oldSize.Y.Offset / parentPixels.Y
				)
				child.Position = UDim2.fromScale(
					oldPosition.X.Scale + oldPosition.X.Offset / parentPixels.X,
					oldPosition.Y.Scale + oldPosition.Y.Offset / parentPixels.Y
				)
				if child:IsA("TextLabel") then
					local constraint = Instance.new("UITextSizeConstraint")
					constraint.MaxTextSize = child.TextSize
					constraint.MinTextSize = 1
					constraint.Parent = child
					child.TextScaled = true
				end
				convertChildrenToScale(child, childPixels)
			end
		end
	end
	convertChildrenToScale(gui, TEMPLATE_PIXELS)
end

buildTemplate("GoblinTemplate", false)
buildTemplate("BoulderTemplate", true)

print("MobBillboardTemplates created in StarterGui. Edit GoblinTemplate/BoulderTemplate in Studio.")
end)

-- ============================================================================
-- BuildRubbleCrystalUI.lua — UI кристаллов в завалах
-- ============================================================================
__run("BuildRubbleCrystalUI.lua", "UI кристаллов в завалах", function()
--------------------------------------------------------------------------------
-- BuildRubbleCrystalUI — ОДНОРАЗОВЫЙ скрипт-сборщик, строит карточку
-- переноски кристалла (StarterGui/RubbleCrystalHotbar/Slot).
--
-- ОТДЕЛЬНЫЙ файл от BuildUIAssets.lua специально — чтобы не трогать/не
-- пересобирать заново весь остальной UI (PickaxeHotbar, HUD и т.д.), когда
-- меняешь именно эту карточку. Визуально — ТОЧНАЯ копия конструкции слота
-- кирки (makeActionSlot из BuildUIAssets.lua: скруглённые углы, обводка,
-- иконка по центру), только высота чуть больше и иконка не фиксированная —
-- какой именно кристалл сейчас в руках, решает RubbleCrystalUI.client.lua
-- во время игры (Image меняется на лету по Config.Geodes.Ores[oreId].ImageId).
--
-- Запускать через Command Bar (Studio), как и остальные Build*.lua.
--------------------------------------------------------------------------------

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
Config.Icons = Config.Icons or {}

-- Фон слота (необязательно) — впиши ID своей картинки, если хочешь другой
-- фон вместо однотонного плейсхолдера. Сама иконка кристалла ставится не
-- отсюда — она полностью управляется рантайм-скриптом (см. шапку файла).
local CRYSTAL_SLOT_BACKGROUND_IMAGE_ID = 0

local DARK_COLOR = Color3.fromRGB(20, 20, 25)

local function imageUri(id)
	if not id or id == 0 then
		return ""
	end
	return "rbxassetid://" .. tostring(id)
end

local function applyImage(instance, id)
	if not id or id == 0 then
		return
	end
	instance.Image = imageUri(id)
	instance.ScaleType = Enum.ScaleType.Stretch
	instance.BackgroundTransparency = 1
	local gradient = instance:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Enabled = false
	end
end

-- Копия makeActionSlot из BuildUIAssets.lua (см. комментарий в шапке — не
-- импортируем оттуда специально, чтобы этот файл ничего не трогал в старом
-- билдере и работал полностью самостоятельно).
local function makeActionSlot(name, position, size, strokeColor, backgroundImageId)
	local slot = Instance.new("ImageLabel")
	slot.Name = name
	slot.AnchorPoint = Vector2.new(0.5, 1)
	slot.Position = position
	slot.Size = size
	slot.BackgroundColor3 = Color3.fromRGB(30, 28, 35)
	slot.BorderSizePixel = 0
	slot.ClipsDescendants = true

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = slot

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = strokeColor
	stroke.Parent = slot

	applyImage(slot, backgroundImageId)

	-- Иконка — пустая по умолчанию (Image = ""), рантайм-скрипт сам
	-- проставляет Config.Geodes.Ores[oreId].ImageId при каждой смене
	-- переносимого кристалла (см. RubbleCrystalUI.client.lua).
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Image = ""
	icon.ScaleType = Enum.ScaleType.Fit
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.62, 0.62)
	icon.ZIndex = 2
	icon.Parent = slot

	-- Плейсхолдер-буква, пока Icon.Image пуст (нет картинки под конкретный
	-- oreId ещё, или ImageId = 0) — чтобы слот не выглядел пустым провалом.
	-- Рантайм-скрипт сам прячет её, как только выставляет реальную картинку.
	local placeholder = Instance.new("TextLabel")
	placeholder.Name = "Placeholder"
	placeholder.BackgroundTransparency = 1
	placeholder.Size = UDim2.fromScale(1, 1)
	placeholder.Font = Enum.Font.FredokaOne
	placeholder.TextScaled = true
	placeholder.TextColor3 = Color3.fromRGB(230, 230, 235)
	placeholder.TextStrokeColor3 = DARK_COLOR
	placeholder.TextStrokeTransparency = 0
	placeholder.Text = "?"
	placeholder.ZIndex = 2
	placeholder.Parent = slot

	return slot
end

local existing = StarterGui:FindFirstChild("RubbleCrystalHotbar")
if existing then
	existing:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RubbleCrystalHotbar"
screenGui.ResetOnSpawn = false -- см. PickaxeHotbar — респавн ручной, ResetOnSpawn=true снёс бы этот UI
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 5 -- тот же слой, что и PickaxeHotbar — стоят рядом в одном ряду
screenGui.Parent = StarterGui

-- Позиция здесь — это позиция, когда карточка ВИДНА (она скрыта, пока руки
-- пустые). Симметрична runtime-сдвигу кирки в RubbleCrystalUI.client.lua
-- (PICKAXE_SHIFT_OFFSET = 38, та же цифра, только в другую сторону) — вместе
-- пара [кристалл][кирка] стоит ровно по центру экрана, а не смещена влево.
local slot = makeActionSlot(
	"Slot",
	UDim2.new(0.5, -38, 1, -20),
	UDim2.fromOffset(68, 74),
	Color3.fromRGB(120, 200, 255), -- голубоватая обводка — отличает от серой кирки на глаз
	CRYSTAL_SLOT_BACKGROUND_IMAGE_ID
)
slot.Visible = false -- по умолчанию скрыт — RubbleCrystalUI.client.lua включает, пока кристалл в руках
slot.Parent = screenGui

print("[BuildRubbleCrystalUI] Done: RubbleCrystalHotbar/Slot created in StarterGui, styled like PickaxeHotbar. Runtime icon/visibility handled by RubbleCrystalUI.client.lua.")
end)

-- ============================================================================
-- BuildCollectionMenu.lua — кнопка-книга и подменю (CollectionMenu)
-- ============================================================================
__run("BuildCollectionMenu.lua", "кнопка-книга и подменю (CollectionMenu)", function()
-- Standalone Command Bar builder for StarterGui/CollectionMenu.
-- Rebuilds BookButton, Dimmer and Submenu, but leaves MutationBookPanel intact.
--
-- ПОСЛЕ запуска: в Explorer найдёшь StarterGui → CollectionMenu → BookButton.
-- Дальше делай с ним что хочешь прямо в Studio:
--   • Своя иконка — вставь картинку в свойство Image (или просто задай
--     Config.UI.CollectionBookImageId в Config.lua, оба варианта работают).
--   • Своя позиция — перетащи мышкой в 2D-редакторе (или поменяй Position/
--     AnchorPoint в Properties). Игра подхватит её как есть и БОЛЬШЕ НЕ
--     БУДЕТ пересчитывать координаты сама — раз кнопка своя, её место
--     целиком на твоей стороне.
--   • Свой размер/поворот — тоже просто свойства (Size/Rotation), меняй
--     как обычный ImageButton.

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local function imageUri(id)
	return id and id ~= 0 and ("rbxassetid://" .. tostring(id)) or ""
end

local gui = StarterGui:FindFirstChild("CollectionMenu")
if not gui then
	gui = Instance.new("ScreenGui")
	gui.Name = "CollectionMenu"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 95 -- выше InteractiveTutorial (90), иначе карточка гайда перехватывает клики поверх кнопки во время обучения
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
		gui.ClipToDeviceSafeArea = true
	end)
	gui.Parent = StarterGui
end

local existingButton = gui:FindFirstChild("BookButton")
if existingButton then existingButton:Destroy() end
for _, name in { "Dimmer", "Submenu" } do
	local existing = gui:FindFirstChild(name)
	if existing then existing:Destroy() end
end

local bookButton = Instance.new("ImageButton")
bookButton.Name = "BookButton"
bookButton.AnchorPoint = Vector2.new(0, 0.5)
bookButton.Position = UDim2.new(0, 14, 0.5, -26) -- стартовая позиция — там же, где была шестерёнка настроек; дальше просто перетаскивай
bookButton.Size = UDim2.fromOffset(52, 52)
bookButton.Rotation = -14
bookButton.BackgroundTransparency = 1
bookButton.AutoButtonColor = false
bookButton.ScaleType = Enum.ScaleType.Fit
bookButton.Parent = gui

-- Плейсхолдер-вид, пока не вставишь свою картинку в Image — просто
-- коричневая книжка с закладкой, тот же стиль, что у остальных
-- плейсхолдеров проекта.
bookButton.BackgroundColor3 = Color3.fromRGB(150, 100, 55)
bookButton.BackgroundTransparency = 0
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = bookButton
local bookmark = Instance.new("Frame")
bookmark.Name = "BookmarkPlaceholder" -- удали этот Frame сам, если вставишь свою картинку в Image — он тут только чтобы плейсхолдер не выглядел пустым квадратом
bookmark.AnchorPoint = Vector2.new(0.5, 0)
bookmark.Position = UDim2.new(0.75, 0, 0, -6)
bookmark.Size = UDim2.fromOffset(10, 22)
bookmark.BackgroundColor3 = Color3.fromRGB(210, 60, 90)
bookmark.BorderSizePixel = 0
bookmark.ZIndex = 2
bookmark.Parent = bookButton

local dimmer = Instance.new("TextButton")
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

local submenu = Instance.new("ImageLabel")
submenu.Name = "Submenu"
submenu.AnchorPoint = Vector2.new(0.5, 0.5)
submenu.Position = UDim2.fromScale(0.5, 0.5)
submenu.Size = UDim2.fromOffset(360, 340)
submenu.BackgroundColor3 = Color3.fromRGB(45, 140, 220)
submenu.BorderSizePixel = 0
submenu.Image = "" -- Фоновая текстура всей панели: rbxassetid://ID
submenu.ScaleType = Enum.ScaleType.Stretch
submenu.Visible = false
submenu.ZIndex = 6
submenu.Parent = gui

local scale = Instance.new("UIScale")
scale.Name = "MobileSubmenuScale"
scale.Parent = submenu

local header = Instance.new("ImageLabel")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 54)
header.BackgroundColor3 = Color3.fromRGB(35, 90, 165)
header.BorderSizePixel = 0
header.Image = "" -- Текстура шапки: rbxassetid://ID
header.ScaleType = Enum.ScaleType.Stretch
header.ZIndex = 7
header.Parent = submenu

local headerTitle = Instance.new("TextLabel")
headerTitle.Name = "Title"
headerTitle.Position = UDim2.fromOffset(16, 0)
headerTitle.Size = UDim2.new(1, -64, 1, 0)
headerTitle.BackgroundTransparency = 1
headerTitle.Font = Enum.Font.Arcade
headerTitle.Text = "COLLECTION MENU"
headerTitle.TextColor3 = Color3.new(1, 1, 1)
headerTitle.TextScaled = true
headerTitle.TextXAlignment = Enum.TextXAlignment.Left
headerTitle.TextStrokeTransparency = 0
headerTitle.ZIndex = 8
headerTitle.Parent = header

local close = Instance.new("TextButton")
close.Name = "CloseButton"
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -10, 0, 10)
close.Size = UDim2.fromOffset(30, 30)
close.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
close.BorderSizePixel = 0
close.Font = Enum.Font.Arcade
close.Text = "X"
close.TextColor3 = Color3.new(1, 1, 1)
close.TextScaled = true
close.ZIndex = 9
close.Parent = submenu

local list = Instance.new("Frame")
list.Name = "List"
list.Position = UDim2.fromOffset(20, 64)
list.Size = UDim2.new(1, -40, 1, -74)
list.BackgroundTransparency = 1
list.ZIndex = 6
list.Parent = submenu
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 10)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

local items = {
	{ Key = "Inventory", Label = "INVENTORY", Icon = "InventoryMenuIconId" },
	{ Key = "Shop", Label = "SHOP", Icon = "ShopMenuIconId" },
	{ Key = "Skins", Label = "SKINS", Icon = "SkinsMenuIconId" },
	{ Key = "Settings", Label = "SETTINGS", Icon = "SettingsMenuIconId" },
	{ Key = "Mutations", Label = "MUTATIONS", Icon = "MutationsMenuIconId" },
}
for order, item in items do
	local row = Instance.new("TextButton")
	row.Name = item.Key .. "Row"
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 56)
	row.BackgroundColor3 = Color3.new(1, 1, 1)
	row.BorderSizePixel = 0
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
	label.Font = Enum.Font.Arcade
	label.Text = item.Label
	label.TextColor3 = Color3.fromRGB(60, 60, 70)
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 7
	label.Parent = row
end

print("[BuildCollectionMenu] Done: editable Submenu created. Set Submenu.Image for the background and Submenu/Header.Image for the header.")
end)

-- ============================================================================
-- BuildMutationBookUI.lua — книга коллекции — CollectionBookUiBuilder
-- ============================================================================
__run("BuildMutationBookUI.lua", "книга коллекции — CollectionBookUiBuilder", function()
--------------------------------------------------------------------------------
-- BuildMutationBookUI — Studio Command Bar: ставит книгу коллекции
-- (MutationBookPanel) в StarterGui/CollectionMenu. Вид —
-- Shared.CollectionBookUiBuilder («музей кристаллов»). Кнопку-книгу и
-- подменю собирает tools/BuildCollectionMenu.lua. Всё разом — tools/BuildAllUI.lua.
--------------------------------------------------------------------------------
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local module = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("CollectionBookUiBuilder")
assert(module, "[BuildMutationBookUI] Нет Shared.CollectionBookUiBuilder — сначала Rojo-синк.")
local gui = StarterGui:FindFirstChild("CollectionMenu")
if not gui then
	gui = Instance.new("ScreenGui")
	gui.Name = "CollectionMenu"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 95
	gui.Parent = StarterGui
end
require(module).Install(gui)
print("[BuildMutationBookUI] Готово: StarterGui/CollectionMenu/MutationBookPanel.")
end)

-- ============================================================================
-- BuildPerkUI.lua — престиж — PerkUiBuilder
-- ============================================================================
__run("BuildPerkUI.lua", "престиж — PerkUiBuilder", function()
--------------------------------------------------------------------------------
-- BuildPerkUI — Studio Command Bar: собирает StarterGui/PerkUi (окно
-- чемоданчика перков престижа). Сборка — Shared.PerkUiBuilder.
--------------------------------------------------------------------------------
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local module = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("PerkUiBuilder")
assert(module, "[BuildPerkUI] Нет Shared.PerkUiBuilder — сначала Rojo-синк.")
local existing = StarterGui:FindFirstChild("PerkUi")
if existing then existing:Destroy() end
require(module).Build().Parent = StarterGui
print("[BuildPerkUI] Готово: StarterGui/PerkUi.")
end)

-- ============================================================================
-- BuildGeodeUI.lua — жеоды + подиум банка — GeodeUiBuilder / BankPodiumUiBuilder
-- ============================================================================
__run("BuildGeodeUI.lua", "жеоды + подиум банка — GeodeUiBuilder / BankPodiumUiBuilder", function()
--------------------------------------------------------------------------------
-- BuildGeodeUI — Studio Command Bar: собирает StarterGui/GeodeUi (хранилище
-- жеод, покупка, вскрытие, меню «сколько открыть» + подиум банка).
-- Вид: Shared.GeodeUiBuilder («аметистовая пещера») и
-- Shared.BankPodiumUiBuilder («изумрудный сейф»). Всё разом — tools/BuildAllUI.lua.
--------------------------------------------------------------------------------
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local module = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("GeodeUiBuilder")
assert(module, "[BuildGeodeUI] Нет Shared.GeodeUiBuilder — сначала Rojo-синк.")
local existing = StarterGui:FindFirstChild("GeodeUi")
if existing then existing:Destroy() end
require(module).Build().Parent = StarterGui
print("[BuildGeodeUI] Готово: StarterGui/GeodeUi.")
end)

-- ============================================================================
-- BuildBoulderGameUI.lua — мини-игра валуна — BoulderGameUiBuilder
-- ============================================================================
__run("BuildBoulderGameUI.lua", "мини-игра валуна — BoulderGameUiBuilder", function()
--------------------------------------------------------------------------------
-- BuildBoulderGameUI — Studio Command Bar: собирает StarterGui/BoulderGameUi
-- (мини-игра валунов). Сборка — в ReplicatedStorage.Shared.BoulderGameUiBuilder.
--   1. Rojo-синк. 2. Вставить файл в Command Bar и выполнить.
--   3. Править вид мышкой. Картинки: Panel/Track/TrackImage (полоса),
--      Panel/Track/Runner/RunnerImage (бегунок). Имена не менять.
--------------------------------------------------------------------------------
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local module = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("BoulderGameUiBuilder")
assert(module, "[BuildBoulderGameUI] Нет Shared.BoulderGameUiBuilder — сначала Rojo-синк.")
local existing = StarterGui:FindFirstChild("BoulderGameUi")
if existing then existing:Destroy() end
require(module).Build().Parent = StarterGui
print("[BuildBoulderGameUI] Готово: StarterGui/BoulderGameUi.")
end)

-- ============================================================================
-- BuildGearUI.lua — прицел и лут сундуков — GearUiBuilder
-- ============================================================================
__run("BuildGearUI.lua", "прицел и лут сундуков — GearUiBuilder", function()
--------------------------------------------------------------------------------
-- BuildGearUI — Studio Command Bar: собирает StarterGui/GearUi (панель
-- снаряжения: динамит/сундуки, подсказка прицела, окно лута, табличка
-- таймера сундука). Сборка — ReplicatedStorage.Shared.GearUiBuilder.
-- В SlotTemplate/Image можно поставить общую рамку; иконки предметов клиент
-- берёт из атрибутов GearUi: Icon_Dynamite, Icon_Chest_Common, … (rbxassetid).
--------------------------------------------------------------------------------
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local module = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("GearUiBuilder")
assert(module, "[BuildGearUI] Нет Shared.GearUiBuilder — сначала Rojo-синк.")
local existing = StarterGui:FindFirstChild("GearUi")
if existing then existing:Destroy() end
local gui = require(module).Build()
for _, key in { "Dynamite", "Chest_Common", "Chest_Rare", "Chest_Epic", "Chest_Legendary" } do
	gui:SetAttribute("Icon_" .. key, "")
end
gui.Parent = StarterGui
print("[BuildGearUI] Готово: StarterGui/GearUi.")
end)

-- ============================================================================
-- BuildSkinUIv3.lua — скины — SkinUiBuilder
-- ============================================================================
__run("BuildSkinUIv3.lua", "скины — SkinUiBuilder", function()
--------------------------------------------------------------------------------
-- BuildSkinUIv3 — Studio Command Bar: собирает НОВОЕ меню скинов
-- StarterGui/SkinUi (карточки → экран с баффами/дебаффами и EQUIP).
-- Заменяет старые BuildSkinUI*.lua. Сборка — Shared.SkinUiBuilder.
--------------------------------------------------------------------------------
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local module = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("SkinUiBuilder")
assert(module, "[BuildSkinUIv3] Нет Shared.SkinUiBuilder — сначала Rojo-синк.")
local existing = StarterGui:FindFirstChild("SkinUi")
if existing then existing:Destroy() end
require(module).Build().Parent = StarterGui
print("[BuildSkinUIv3] Готово: StarterGui/SkinUi (новое меню скинов).")
end)

-- ============================================================================
-- BuildCombatUI.lua — бой — CombatUiBuilder
-- ============================================================================
__run("BuildCombatUI.lua", "бой — CombatUiBuilder", function()
--------------------------------------------------------------------------------
-- BuildCombatUI — Studio Command Bar: собирает StarterGui/CombatUi —
-- интерфейс PvP v2: шкала оглушения над головой, значок WANTED,
-- комбо-счётчик атакующего и крупные надписи (KNOCKDOWN!/CLASH!).
--
-- Сама сборка живёт в ReplicatedStorage.Shared.CombatUiBuilder (тот же
-- модуль использует клиент, если в StarterGui нет свежей версии), поэтому
-- вид в Studio и в игре всегда совпадает.
--
-- КАК ИСПОЛЬЗОВАТЬ:
--   1. Синхронизировать проект (Rojo), чтобы модуль был в Shared.
--   2. Вставить этот файл целиком в Command Bar и выполнить.
--   3. Править вид мышкой в StarterGui/CombatUi:
--        StaggerTemplate/Bar/PipTemplate      — деление шкалы (Fill — заливка)
--        StaggerTemplate/State                — надпись "STUNNED!"
--        StaggerTemplate/Wanted               — значок награды
--        StaggerTemplate/Wanted/Icon          — поставь картинку мешка денег,
--                                               клиент сам её покажет
--        ComboCounter, Popup                  — экранные надписи
--   Имена объектов не переименовывай — по ним клиент находит элементы.
--   PipTemplate должен оставаться Visible = false — клиент его клонирует.
--   Если поднимешь Config.Stagger.UiVersion, клиент перестанет брать
--   устаревшую копию из StarterGui и соберёт свежую сам, пока не
--   перезапустишь этот билдер.
--------------------------------------------------------------------------------

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:FindFirstChild("Shared")
local module = shared and shared:FindFirstChild("CombatUiBuilder")
assert(module, "[BuildCombatUI] Нет ReplicatedStorage.Shared.CombatUiBuilder — сначала синхронизируй проект (Rojo).")

local Builder = require(module)

local existing = StarterGui:FindFirstChild("CombatUi")
if existing then
	existing:Destroy()
end

local gui = Builder.Build()
gui.Parent = StarterGui

print("[BuildCombatUI] Готово: StarterGui/CombatUi собран. Правь вид мышкой, имена не трогай.")
end)

-- ============================================================================
-- BuildMineArcUI.lua — мини-игра шахты — MineVeinUiBuilder
-- ============================================================================
__run("BuildMineArcUI.lua", "мини-игра шахты — MineVeinUiBuilder", function()
--------------------------------------------------------------------------------
-- BuildMineArcUI — Studio Command Bar: собирает StarterGui/MineArcUi —
-- интерфейс мини-игры "РУДНАЯ ЖИЛА" (вариант A).
--
-- Сама сборка живёт в ReplicatedStorage.Shared.MineVeinUiBuilder (тот же
-- модуль использует клиент, если в StarterGui нет свежей версии), поэтому
-- вид в Studio и в игре всегда совпадает.
--
-- КАК ИСПОЛЬЗОВАТЬ:
--   1. Синхронизировать проект (Rojo), чтобы модуль был в Shared.
--   2. Вставить этот файл целиком в Command Bar и выполнить.
--   3. Подставить свои картинки (ImageLabel с пустым Image):
--        Container/Vein/VeinImage            — рудная жила (фон полосы)
--        Container/Vein/GoodZoneTemplate     — кристальная зона (GOOD)
--        Container/Vein/PerfectZoneTemplate  — самородок (PERFECT)
--        Container/Vein/Pick                 — кирка-бегунок
--        Container/HitPips/Pip1..3           — кружки результатов
--      Как только у ImageLabel задан Image, клиент прячет его запасные
--      плашки (камешки, блики, рукоять) и делает фон прозрачным. Зоны
--      тянутся по ширине — для них удобнее ScaleType = Slice.
--   Шаблоны зон должны оставаться Visible = false — клиент их клонирует.
--------------------------------------------------------------------------------

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:FindFirstChild("Shared")
local module = shared and shared:FindFirstChild("MineVeinUiBuilder")
assert(module, "[BuildMineArcUI] Нет ReplicatedStorage.Shared.MineVeinUiBuilder — сначала синхронизируй проект (Rojo).")

local Builder = require(module)

local existing = StarterGui:FindFirstChild("MineArcUi")
if existing then
	existing:Destroy()
end

local gui = Builder.Build()
gui.Parent = StarterGui

print(("[BuildMineArcUI] Готово: StarterGui/MineArcUi (версия %d). Подставь картинки в ImageLabel'ы — см. шапку скрипта."):format(Builder.VERSION))
end)

-- ============================================================================
-- BuildMinerDialogUI.lua — диалог шахтёра — MinerDialogUiBuilder
-- ============================================================================
__run("BuildMinerDialogUI.lua", "диалог шахтёра — MinerDialogUiBuilder", function()
--------------------------------------------------------------------------------
-- BuildMinerDialogUI — Studio Command Bar: собирает StarterGui/MinerDialogUi —
-- диалог шахтёра в стиле Grow a Garden (реплика справа от шахтёра + ответы).
--
-- Сборка живёт в ReplicatedStorage.Shared.MinerDialogUiBuilder (тот же модуль
-- использует клиент, если в StarterGui нет свежей версии).
--
-- КАК ИСПОЛЬЗОВАТЬ:
--   1. Синхронизировать проект (Rojo).
--   2. Вставить этот файл целиком в Command Bar и выполнить.
--   3. Править вид мышкой. Choices/ChoiceTemplate — шаблон кнопки ответа,
--      должен остаться Visible = false. Сдвиг облачка от шахтёра —
--      MinerDialogUi.StudsOffset (X — вправо по экрану, Y — вверх).
--------------------------------------------------------------------------------
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:FindFirstChild("Shared")
local module = shared and shared:FindFirstChild("MinerDialogUiBuilder")
assert(module, "[BuildMinerDialogUI] Нет ReplicatedStorage.Shared.MinerDialogUiBuilder — сначала синхронизируй проект (Rojo).")

local Builder = require(module)
local existing = StarterGui:FindFirstChild("MinerDialogUi")
if existing then existing:Destroy() end
local gui = Builder.Build()
gui.Parent = StarterGui
print(("[BuildMinerDialogUI] Готово: StarterGui/MinerDialogUi (версия %d)."):format(Builder.VERSION))
end)

-- ============================================================================
-- BuildOfferUI.lua — купоны предложений и кнопка 🚀 — OfferUiBuilder
-- ============================================================================
__run("BuildOfferUI.lua", "купоны предложений и кнопка 🚀 — OfferUiBuilder", function()
--------------------------------------------------------------------------------
-- BuildOfferUI — Studio Command Bar: StarterGui/OfferUi (купоны контекстных
-- предложений + кнопка 🚀 Rocket Pickaxe). Вид — Shared.OfferUiBuilder.
-- Всё разом — tools/BuildAllUI.lua.
--------------------------------------------------------------------------------
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local module = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("OfferUiBuilder")
assert(module, "[BuildOfferUI] Нет Shared.OfferUiBuilder — сначала Rojo-синк.")
local existing = StarterGui:FindFirstChild("OfferUi")
if existing then existing:Destroy() end
require(module).Build().Parent = StarterGui
print("[BuildOfferUI] Готово: StarterGui/OfferUi.")
end)

print("[BuildAllUI] Готово:\n  " .. table.concat(__report, "\n  "))
