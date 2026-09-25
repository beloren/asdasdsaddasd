--------------------------------------------------------------------------------
-- UiTheme — ЕДИНЫЙ СТИЛЬ ВСЕГО ИНТЕРФЕЙСА (v20).
--
-- Здесь лежит всё, из чего собирается вид игры: шрифты, цвета, акценты окон
-- и КАРТИНКИ ПОДЛОЖЕК. Все билдеры (ReplicatedStorage.Shared.UiBuilders.*)
-- строят интерфейс только через UiKit, а UiKit берёт вид отсюда. Поменял
-- что-то здесь → запустил tools/BuildAllUI.lua (пересобрать всё) или
-- tools/ApplyUiSkins.lua (только перекрасить/поставить картинки, НЕ трогая
-- твои ручные правки позиций) — и весь UI игры поменялся разом.
--
-- СТИЛЬ: как в Prospecting / Fisch — тёмные полупрозрачные прямоугольные
-- панели, тонкая цветная рамка (у каждого окна свой акцент), отдельная
-- полоса заголовка с закладкой-ленточкой слева и красным «X» справа,
-- крупный жирный курсив с тёмной обводкой, зелёные кнопки покупки,
-- карточки с рамкой цвета редкости.
--
-- КАРТИНКИ (Skins). Каждая подложка в игре — ImageLabel/ImageButton с
-- атрибутом UiSkin = "<ключ>". Пока Image у скина пустой, элемент рисуется
-- цветом (Color/Transparency/Stroke ниже). Впиши rbxassetid — и ВСЕ такие
-- элементы во всех окнах покажут твою картинку (9-slice по Slice, если он
-- задан, иначе Stretch). Можно писать число (123456) или строку
-- "rbxassetid://123456".
--   • Tint = true — картинка тонируется цветом акцента/редкости
--     (удобно: одна белая рамка карточки → зелёная/синяя/фиолетовая).
--   • У отдельного элемента можно поставить свою картинку прямо в Studio
--     и атрибут UiSkinLocked = true — ApplyUiSkins его не тронет.
--------------------------------------------------------------------------------

local Theme = {}

Theme.VERSION = 20

--------------------------------------------------------------------------------
-- ШРИФТЫ — жирный курсив, как на референсах. Стиль → FontFace.
--------------------------------------------------------------------------------
local FAMILY = "rbxasset://fonts/families/SourceSansPro.json"
Theme.Fonts = {
	Title = Font.new(FAMILY, Enum.FontWeight.Heavy, Enum.FontStyle.Italic),   -- заголовки окон, «Welcome Back!»
	Heading = Font.new(FAMILY, Enum.FontWeight.Bold, Enum.FontStyle.Italic),  -- названия секций, карточек, кнопки
	Body = Font.new(FAMILY, Enum.FontWeight.SemiBold, Enum.FontStyle.Italic), -- обычный текст, описания
	Small = Font.new(FAMILY, Enum.FontWeight.SemiBold, Enum.FontStyle.Italic),-- подписи, прогресс «0/20»
	Number = Font.new(FAMILY, Enum.FontWeight.Heavy, Enum.FontStyle.Italic),  -- цены, деньги, счётчики
	Plain = Font.new(FAMILY, Enum.FontWeight.SemiBold, Enum.FontStyle.Normal),-- ввод текста
	-- v20.3: засечный шрифт — имена NPC над головой и трекер квестов слева
	-- (референс «Ice Man» / «Sensei Moro Final»).
	Serif = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal),
	SerifBody = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
	-- v20.8: бывший «Fredoka» — теперь тот же жирный курсив, что и деньги
	-- (оставлен как псевдоним, чтобы старые ссылки не ломались).
	Fredoka = Font.new(FAMILY, Enum.FontWeight.Heavy, Enum.FontStyle.Italic),
	-- v20.6: курсивные варианты для подсказок (трекер квестов слева).
	SerifItalic = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold, Enum.FontStyle.Italic),
	SerifBodyItalic = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Regular, Enum.FontStyle.Italic),
}

-- Толщина тёмной обводки текста по стилю.
Theme.TextStroke = {
	Serif = 1.6,
	SerifBody = 1.2,
	Fredoka = 2,
	SerifItalic = 1.6,
	SerifBodyItalic = 1.2,
	Title = 2.5,
	Heading = 1.8,
	Body = 1.4,
	Small = 1.2,
	Number = 2,
	Plain = 0,
}

--------------------------------------------------------------------------------
-- ЦВЕТА
--------------------------------------------------------------------------------
Theme.Colors = {
	Text = Color3.fromRGB(255, 255, 255),
	SubText = Color3.fromRGB(205, 205, 215),
	MutedText = Color3.fromRGB(150, 150, 160),
	TextStroke = Color3.fromRGB(12, 10, 16),
	Money = Color3.fromRGB(255, 225, 90),
	Positive = Color3.fromRGB(150, 255, 110),
	Negative = Color3.fromRGB(255, 70, 70),
	Close = Color3.fromRGB(255, 38, 38),
	Shards = Color3.fromRGB(235, 150, 255),
	Exp = Color3.fromRGB(150, 220, 255),
	Dimmer = Color3.fromRGB(0, 0, 0),
}

-- Акценты окон: Main — рамка/лента, Light — верх градиента заголовка,
-- Dark — низ градиента / тень.
local function accent(main, light, dark)
	return { Main = main, Light = light, Dark = dark }
end
Theme.Accents = {
	Purple = accent(Color3.fromRGB(190, 130, 255), Color3.fromRGB(235, 205, 255), Color3.fromRGB(150, 85, 235)), -- магазин
	Blue = accent(Color3.fromRGB(70, 165, 255), Color3.fromRGB(150, 225, 255), Color3.fromRGB(45, 130, 235)),    -- квесты, инфо
	Peach = accent(Color3.fromRGB(255, 196, 140), Color3.fromRGB(255, 232, 200), Color3.fromRGB(240, 160, 100)), -- крафт, инвентарь
	Gold = accent(Color3.fromRGB(255, 205, 70), Color3.fromRGB(255, 245, 160), Color3.fromRGB(240, 170, 30)),    -- награды, деньги
	Green = accent(Color3.fromRGB(120, 230, 90), Color3.fromRGB(205, 255, 170), Color3.fromRGB(70, 185, 50)),    -- прогресс, успех
	Red = accent(Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 170, 160), Color3.fromRGB(215, 40, 40)),       -- бой, опасность
	Pink = accent(Color3.fromRGB(255, 120, 210), Color3.fromRGB(255, 200, 240), Color3.fromRGB(230, 70, 180)),   -- жеоды, кристаллы
	Teal = accent(Color3.fromRGB(70, 225, 200), Color3.fromRGB(175, 255, 240), Color3.fromRGB(35, 180, 165)),    -- острова, путешествия
	Orange = accent(Color3.fromRGB(255, 150, 60), Color3.fromRGB(255, 210, 150), Color3.fromRGB(235, 110, 30)),  -- престиж, торговец
	Grey = accent(Color3.fromRGB(170, 170, 180), Color3.fromRGB(235, 235, 240), Color3.fromRGB(120, 120, 130)),  -- нейтральное
}
Theme.DefaultAccent = "Blue"

-- Цвета редкостей (рамки карточек, подписи).
Theme.Rarity = {
	Common = Color3.fromRGB(215, 215, 215),
	Uncommon = Color3.fromRGB(110, 235, 80),
	Rare = Color3.fromRGB(70, 150, 255),
	Epic = Color3.fromRGB(185, 100, 255),
	Legendary = Color3.fromRGB(255, 190, 40),
	Mythic = Color3.fromRGB(255, 70, 110),
	Exotic = Color3.fromRGB(80, 255, 230),
	Secret = Color3.fromRGB(40, 40, 40),
}

--------------------------------------------------------------------------------
-- СКИНЫ ПОДЛОЖЕК. Image = "" → рисуется цветом. Остальные поля — вид без
-- картинки (и рамка поверх картинки, если Stroke = true при заданном Image
-- не нужен — он автоматически выключается).
--   Slice — Rect 9-slice (центр) для картинки; nil = Stretch.
--   Corner — скругление (px), 0 = прямые углы как на референсах.
--   Gradient — {верх, низ} заливки (множители яркости поверх Color).
--------------------------------------------------------------------------------
local DARK = Color3.fromRGB(14, 14, 18)
Theme.Skins = {
	-- Окно целиком (тело под заголовком).
	Panel = { Image = "", Slice = Rect.new(16, 16, 48, 48), Color = DARK, Transparency = 0.3, StrokeThickness = 1.5, StrokeAccent = true, StrokeTransparency = 0.25, Corner = 0 },
	-- Полоса заголовка окна.
	TitleBar = { Image = "", Slice = Rect.new(16, 16, 48, 48), Color = Color3.fromRGB(10, 10, 14), Transparency = 0.2, StrokeThickness = 1.5, StrokeAccent = true, StrokeTransparency = 0.1, Corner = 0 },
	-- Закладка-ленточка слева на заголовке.
	Ribbon = { Image = "", Color = Color3.fromRGB(190, 130, 255), Transparency = 0, Tint = true, Corner = 0, FillAccent = true },
	-- Внутренние блоки: секции, строки списка, подложки под текст.
	Inset = { Image = "", Slice = Rect.new(12, 12, 36, 36), Color = Color3.fromRGB(8, 8, 10), Transparency = 0.45, StrokeThickness = 1, StrokeColor = Color3.fromRGB(70, 70, 80), StrokeTransparency = 0.4, Corner = 0 },
	-- Карточка товара/предмета/награды (рамка — цвет редкости или акцента).
	Card = { Image = "", Slice = Rect.new(12, 12, 36, 36), Color = Color3.fromRGB(30, 30, 34), Transparency = 0.08, StrokeThickness = 1.5, StrokeAccent = true, StrokeTransparency = 0, Corner = 0, Tint = false },
	-- Квадратная ячейка (хотбар, инвентарь, иконка награды).
	Slot = { Image = "", Slice = Rect.new(12, 12, 36, 36), Color = Color3.fromRGB(28, 28, 32), Transparency = 0.15, StrokeThickness = 1.5, StrokeColor = Color3.fromRGB(95, 95, 105), StrokeTransparency = 0.1, Corner = 0 },
	-- Круглая HUD-кнопка / значок.
	Round = { Image = "", Color = Color3.fromRGB(14, 14, 18), Transparency = 0.35, StrokeThickness = 1.5, StrokeColor = Color3.fromRGB(255, 255, 255), StrokeTransparency = 0.6, Corner = 999 },
	-- HUD-плашка (деньги, престиж, таймеры).
	Pill = { Image = "", Slice = Rect.new(12, 12, 36, 36), Color = Color3.fromRGB(12, 12, 16), Transparency = 0.35, StrokeThickness = 1.5, StrokeAccent = true, StrokeTransparency = 0.2, Corner = 0 },
	-- Всплывающая плашка (тосты, подсказки).
	Toast = { Image = "", Slice = Rect.new(12, 12, 36, 36), Color = Color3.fromRGB(12, 12, 16), Transparency = 0.2, StrokeThickness = 1.5, StrokeAccent = true, StrokeTransparency = 0, Corner = 0 },
	-- Поле ввода.
	Input = { Image = "", Slice = Rect.new(8, 8, 24, 24), Color = Color3.fromRGB(6, 6, 8), Transparency = 0.3, StrokeThickness = 1, StrokeColor = Color3.fromRGB(110, 110, 120), StrokeTransparency = 0.2, Corner = 0 },
	-- Полоса прогресса: дорожка и заливка.
	BarTrack = { Image = "", Slice = Rect.new(6, 6, 18, 18), Color = Color3.fromRGB(55, 55, 60), Transparency = 0.1, StrokeThickness = 1, StrokeColor = Color3.fromRGB(0, 0, 0), StrokeTransparency = 0.5, Corner = 0 },
	BarFill = { Image = "", Slice = Rect.new(6, 6, 18, 18), Color = Color3.fromRGB(120, 230, 90), Transparency = 0, Corner = 0, FillAccent = true, Tint = true, Gradient = { 1.15, 0.8 } },

	-- КНОПКИ. Button_<вариант>.
	Button_Green = { Image = "", Slice = Rect.new(12, 12, 36, 36), Color = Color3.fromRGB(110, 215, 60), Transparency = 0, StrokeThickness = 1.5, StrokeColor = Color3.fromRGB(215, 255, 170), StrokeTransparency = 0, Corner = 0, Gradient = { 1.2, 0.72 }, TextColor = Color3.fromRGB(255, 255, 255), TextStroke = Color3.fromRGB(20, 70, 10) },
	Button_Claim = { Image = "", Slice = Rect.new(12, 12, 36, 36), Color = Color3.fromRGB(28, 48, 32), Transparency = 0.05, StrokeThickness = 1.5, StrokeColor = Color3.fromRGB(150, 235, 120), StrokeTransparency = 0, Corner = 0, TextColor = Color3.fromRGB(180, 255, 140), TextStroke = Color3.fromRGB(10, 25, 10) },
	Button_Yellow = { Image = "", Slice = Rect.new(12, 12, 36, 36), Color = Color3.fromRGB(255, 205, 50), Transparency = 0, StrokeThickness = 1.5, StrokeColor = Color3.fromRGB(255, 245, 170), StrokeTransparency = 0, Corner = 0, Gradient = { 1.15, 0.78 }, TextColor = Color3.fromRGB(255, 255, 255), TextStroke = Color3.fromRGB(95, 60, 0) },
	Button_Track = { Image = "", Slice = Rect.new(12, 12, 36, 36), Color = Color3.fromRGB(40, 40, 42), Transparency = 0.05, StrokeThickness = 1.5, StrokeColor = Color3.fromRGB(255, 230, 90), StrokeTransparency = 0, Corner = 0, TextColor = Color3.fromRGB(255, 230, 90), TextStroke = Color3.fromRGB(20, 18, 5) },
	Button_Red = { Image = "", Slice = Rect.new(12, 12, 36, 36), Color = Color3.fromRGB(230, 60, 55), Transparency = 0, StrokeThickness = 1.5, StrokeColor = Color3.fromRGB(255, 180, 170), StrokeTransparency = 0, Corner = 0, Gradient = { 1.15, 0.75 }, TextColor = Color3.fromRGB(255, 255, 255), TextStroke = Color3.fromRGB(80, 10, 10) },
	Button_Blue = { Image = "", Slice = Rect.new(12, 12, 36, 36), Color = Color3.fromRGB(60, 150, 255), Transparency = 0, StrokeThickness = 1.5, StrokeColor = Color3.fromRGB(180, 225, 255), StrokeTransparency = 0, Corner = 0, Gradient = { 1.15, 0.75 }, TextColor = Color3.fromRGB(255, 255, 255), TextStroke = Color3.fromRGB(10, 40, 90) },
	Button_Purple = { Image = "", Slice = Rect.new(12, 12, 36, 36), Color = Color3.fromRGB(170, 95, 255), Transparency = 0, StrokeThickness = 1.5, StrokeColor = Color3.fromRGB(230, 200, 255), StrokeTransparency = 0, Corner = 0, Gradient = { 1.15, 0.75 }, TextColor = Color3.fromRGB(255, 255, 255), TextStroke = Color3.fromRGB(55, 15, 100) },
	Button_Dark = { Image = "", Slice = Rect.new(12, 12, 36, 36), Color = Color3.fromRGB(34, 34, 38), Transparency = 0.1, StrokeThickness = 1.5, StrokeColor = Color3.fromRGB(120, 120, 130), StrokeTransparency = 0.1, Corner = 0, TextColor = Color3.fromRGB(255, 255, 255), TextStroke = Color3.fromRGB(0, 0, 0) },
	-- Квадратная жёлтая кнопка «подарок» рядом с ценой.
	Button_Gift = { Image = "", Slice = Rect.new(8, 8, 24, 24), Color = Color3.fromRGB(255, 200, 40), Transparency = 0, StrokeThickness = 1.5, StrokeColor = Color3.fromRGB(255, 245, 170), StrokeTransparency = 0, Corner = 0, Gradient = { 1.15, 0.8 }, TextColor = Color3.fromRGB(255, 255, 255), TextStroke = Color3.fromRGB(95, 60, 0) },
	-- Вкладка (обычная / активная).
	Tab = { Image = "", Slice = Rect.new(8, 8, 24, 24), Color = Color3.fromRGB(10, 10, 12), Transparency = 0.35, StrokeThickness = 1, StrokeColor = Color3.fromRGB(80, 80, 90), StrokeTransparency = 0.3, Corner = 0, TextColor = Color3.fromRGB(200, 200, 205), TextStroke = Color3.fromRGB(0, 0, 0) },
	TabActive = { Image = "", Slice = Rect.new(8, 8, 24, 24), Color = Color3.fromRGB(24, 24, 28), Transparency = 0.1, StrokeThickness = 1, StrokeAccent = true, StrokeTransparency = 0, Corner = 0, TextColor = Color3.fromRGB(255, 255, 255), TextStroke = Color3.fromRGB(0, 0, 0) },
	-- Затемнение экрана под модальным окном.
	Dimmer = { Image = "", Color = Color3.fromRGB(0, 0, 0), Transparency = 0.5, Corner = 0 },
	-- Красная точка-уведомление / бейдж «NEW».
	Badge = { Image = "", Color = Color3.fromRGB(235, 45, 45), Transparency = 0, StrokeThickness = 1.5, StrokeColor = Color3.fromRGB(255, 255, 255), StrokeTransparency = 0, Corner = 999 },
	-- Разделитель-линия (под заголовком секции).
	Divider = { Image = "", Color = Color3.fromRGB(255, 255, 255), Transparency = 0, Corner = 0, FillAccent = true, Tint = true },
	-- Лучи/сияние за наградой.
	Glow = { Image = "", Color = Color3.fromRGB(255, 255, 255), Transparency = 1, Corner = 0, Tint = true },
}

--------------------------------------------------------------------------------
-- ИКОНКИ (не подложки): крестик закрытия, галочка, Robux, валюты.
-- Пусто = текст/эмодзи вместо картинки.
--------------------------------------------------------------------------------
Theme.Icons = {
	Close = "",      -- картинка красного X; пусто = текст «X»
	Check = "",      -- галочка «получено»
	Robux = "",      -- значок Robux на ценах
	Money = "",      -- 💰
	Prestige = "",   -- ⭐ престиж в HUD
	PortraitFrame = "", -- кольцо поверх портрета в HUD
	Shards = "",     -- 💎
	Exp = "",        -- EXP
	Gift = "",       -- 🎁 на кнопке подарка
	Lock = "",       -- 🔒
	Shop = "",       -- кнопки HUD
	Quests = "",
	Settings = "",
	Inventory = "",
	Skins = "",
	Rewards = "",
	Social = "",
	Book = "",
	QuestDiamond = "", -- золотой ромб у квеста в трекере; пусто = «◈»
	Rocket = "",     -- 🚀 кнопка ракетной кирки (пасс)
}

-- Размеры по умолчанию.
Theme.Metrics = {
	TitleBarHeight = 54,
	TitleTextSize = 38,
	Padding = 12,
	Gap = 8,
	RibbonWidth = 34,
	RibbonHeight = 64,
	CloseSize = 40,
	ScrollBar = 6,
}

return Theme
