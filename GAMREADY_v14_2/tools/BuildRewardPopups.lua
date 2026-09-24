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
