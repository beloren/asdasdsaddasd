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
