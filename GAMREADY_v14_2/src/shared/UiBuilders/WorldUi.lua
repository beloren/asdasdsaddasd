--------------------------------------------------------------------------------
-- WorldUi (v20) — ШАБЛОНЫ МИРОВОГО ИНТЕРФЕЙСА: надписи над рудой, NPC,
-- тележкой, мобами, числа урона, таймеры и т.д.
--
-- Всё, что висит в мире (BillboardGui/SurfaceGui), серверные сервисы и
-- клиентские скрипты собирают через Shared.WorldUi из этих шаблонов:
-- поменяй шрифт/обводку/подложку здесь (StarterGui/WorldUiTemplates) —
-- поменяется у всех надписей в игре.
--
-- СТРУКТУРА (контракт):
--   ScreenGui "WorldUiTemplates" (Enabled=false — сам ничего не рисует)
--   ├─ Folder "TextStyles" — образцы TextLabel (FontFace + UIStroke "TextStroke"):
--   │    "Title", "Heading", "Number", "Money", "Body", "Small", "Glyph",
--   │    "NpcName", "NpcSub", "NpcArrow" (имена NPC), "Label", "LabelSub" (трофеи, тотемы)
--   ├─ Folder "Plates" — образцы подложек (ImageLabel со скином):
--   │    "Pill", "Card", "Dark", "Bar" (→ "Fill")
--   └─ Folder "Billboards" — готовые билборды:
--        "NpcDialog" → "name", "arrow", "dialog", "bonus"
--        "TitleSub"  → "Title", "Sub"
--        "HealthBar" → "Icon", "Title", "Bar" (→ "Fill"), "Value"
--        "Timer"     → "Plate" [Pill] → "Icon", "Text"
--        "Arrow"     → "Image", "Glyph"
--------------------------------------------------------------------------------
local UiKit = require(script.Parent.Parent.UiKit)
local Theme = UiKit.Theme

local Builder = {}
Builder.VERSION = 21

-- Стили мирового текста: шрифт темы + более толстая обводка (надписи
-- читаются поверх любого фона сцены).
Builder.TEXT_STYLES = {
	Title = { Font = "Title", Stroke = 3, Color = Theme.Colors.Text },
	Heading = { Font = "Heading", Stroke = 2.5, Color = Theme.Colors.Text },
	Number = { Font = "Number", Stroke = 2.5, Color = Theme.Colors.Text },
	Money = { Font = "Number", Stroke = 2.5, Color = Theme.Colors.Positive },
	Body = { Font = "Body", Stroke = 2, Color = Theme.Colors.Text },
	Small = { Font = "Small", Stroke = 1.5, Color = Theme.Colors.SubText },
	Glyph = { Font = "Title", Stroke = 3, Color = Theme.Accents.Gold.Main },
	-- v20.8: имена NPC (продавец, мэр престижа…) и подписи над трофеями и
	-- тотемами — тем же шрифтом, что и деньги в HUD (жирный курсив темы,
	-- стиль Fisch). Подписи трофеев/тотемов — TextScaled в рамке в пикселях.
	NpcName = { Font = "Number", Stroke = 2.5, Color = Color3.new(1, 1, 1) },
	NpcSub = { Font = "Heading", Stroke = 2, Color = Color3.fromRGB(225, 225, 230) },
	NpcArrow = { Font = "Heading", Stroke = 1.5, Color = Color3.fromRGB(210, 210, 215) },
	Label = { Font = "Number", Stroke = 2.5, Color = Color3.new(1, 1, 1) },
	LabelSub = { Font = "Heading", Stroke = 2, Color = Color3.fromRGB(230, 230, 235) },
}

local function textSample(parent, name, spec)
	local t = UiKit.Text(parent, name, name, {
		_Style = spec.Font,
		_Stroke = spec.Stroke,
		TextColor3 = spec.Color,
	})
	return t
end

local function billboard(parent, name, size)
	local b = Instance.new("BillboardGui")
	b.Name = name
	b.Size = size
	b.AlwaysOnTop = true
	b.LightInfluence = 0
	b.Enabled = false
	b.Parent = parent
	return b
end

function Builder.Build()
	local gui = UiKit.Screen("WorldUiTemplates", {})
	gui.Enabled = false
	gui:SetAttribute("UiKitVersion", Builder.VERSION)

	local styles = Instance.new("Folder")
	styles.Name = "TextStyles"
	styles.Parent = gui
	for name, spec in Builder.TEXT_STYLES do
		textSample(styles, name, spec)
	end

	local plates = Instance.new("Folder")
	plates.Name = "Plates"
	plates.Parent = gui
	UiKit.Plate(plates, "Pill", "Pill", { _Accent = "Grey" })
	UiKit.Card(plates, "Card", "Grey", {})
	UiKit.Plate(plates, "Dark", "Toast", { _Accent = "Grey" })
	UiKit.Bar(plates, "Bar", "Green", { Size = UDim2.new(1, 0, 0, 8) })

	local boards = Instance.new("Folder")
	boards.Name = "Billboards"
	boards.Parent = gui

	-- Имя NPC + стрелка + реплика (продавцы, мэр престижа).
	local npc = billboard(boards, "NpcDialog", UDim2.fromOffset(300, 120))
	UiKit.Text(npc, "name", "NPC", { _Style = "Title", _Stroke = 3, Size = UDim2.fromScale(1, 0.4), TextColor3 = Theme.Accents.Gold.Light })
	local npcArrow = UiKit.Text(npc, "arrow", "", { _Style = "Title", _Stroke = 3, Position = UDim2.fromScale(0, 0.4), Size = UDim2.fromScale(1, 0.25) })
	UiKit.GlyphToShape(npcArrow, "ChevronDown") -- v20.9: фигура вместо ▼
	UiKit.Text(npc, "dialog", "", { _Style = "Heading", _Stroke = 3, Size = UDim2.fromScale(1, 1), Visible = false })
	UiKit.Text(npc, "bonus", "", { _Style = "Number", _Stroke = 3, Position = UDim2.fromScale(0, 0.7), Size = UDim2.fromScale(1, 0.3), TextColor3 = Theme.Colors.Positive, Visible = false })

	-- Заголовок + подпись (печь, острова, постройки).
	local titleSub = billboard(boards, "TitleSub", UDim2.fromOffset(320, 84))
	UiKit.Text(titleSub, "Title", "TITLE", { _Style = "Title", _Stroke = 3, Size = UDim2.fromScale(1, 0.55) })
	UiKit.Text(titleSub, "Sub", "", { _Style = "Heading", _Stroke = 2, Position = UDim2.fromScale(0, 0.58), Size = UDim2.fromScale(1, 0.4), TextColor3 = Theme.Colors.SubText })

	-- Полоска здоровья моба/валуна.
	local health = billboard(boards, "HealthBar", UDim2.fromOffset(200, 44))
	UiKit.Icon(health, "Icon", "", { Position = UDim2.fromOffset(1, 1), Size = UDim2.fromOffset(38, 38) })
	UiKit.Text(health, "Title", "MOB", {
		_Style = "Heading",
		Position = UDim2.fromOffset(42, 0),
		Size = UDim2.new(1, -44, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	UiKit.Bar(health, "Bar", "Red", {
		Position = UDim2.fromOffset(42, 22),
		Size = UDim2.new(1, -44, 0, 12),
	})
	UiKit.Text(health, "Value", "100", {
		_Style = "Small",
		Position = UDim2.fromOffset(42, 22),
		Size = UDim2.new(1, -44, 0, 12),
		ZIndex = 4,
	})

	-- Таймер/значок на подложке-пилюле.
	local timer = billboard(boards, "Timer", UDim2.fromOffset(150, 34))
	local pill = UiKit.Plate(timer, "Plate", "Pill", { _Accent = "Gold" })
	UiKit.Text(pill, "Icon", "🛡", {
		_Stroke = 0,
		Position = UDim2.fromOffset(4, 3),
		Size = UDim2.new(0, 26, 1, -6),
		ZIndex = 2,
	}).FontFace = Font.fromEnum(Enum.Font.GothamBold)
	UiKit.Text(pill, "Text", "0:30", {
		_Style = "Number",
		Position = UDim2.fromOffset(32, 3),
		Size = UDim2.new(1, -38, 1, -6),
		ZIndex = 2,
	})

	-- Стрелка-указатель (к банку, к цели).
	local arrow = billboard(boards, "Arrow", UDim2.fromOffset(60, 60))
	UiKit.Icon(arrow, "Image", "", { ZIndex = 2 })
	local glyph = UiKit.Text(arrow, "Glyph", "", { _Style = "Title", _Stroke = 3, TextColor3 = Theme.Accents.Gold.Main })
	UiKit.GlyphToShape(glyph, "ChevronDown")
	return gui
end

return Builder
