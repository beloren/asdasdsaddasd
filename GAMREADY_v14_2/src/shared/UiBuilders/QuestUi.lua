--------------------------------------------------------------------------------
-- QuestUi — окно квестов + трекер закреплённого квеста (стиль «Quests»
-- из референса: синий акцент, секции с линией, полосы прогресса, кнопка Track).
-- Клиент: QuestUI.client.lua — клонирует шаблоны из папки Templates.
--
-- СТРУКТУРА (имена — контракт):
--   ScreenGui "QuestUi"
--   ├─ ImageButton "QuestToggleButton" [Round] → "Emoji", ImageLabel "Badge"
--   ├─ Frame "QuestTracker" (UIListLayout; клиент кладёт сюда клон TrackerRow)
--   ├─ TextButton "Dimmer"
--   ├─ ImageLabel "QuestModal" (окно) → TitleBar(Title, Ribbon, CloseButton)
--   │    └─ Frame → Body → Frame "Tabs" (StoryTab/DailyTab/WeeklyTab), ScrollingFrame "List"
--   └─ Folder "Templates"
--        ├─ ImageButton "TrackerRow" (без подложки) → Header(Icon, Title, Caret, Line), Why,
--        │    Objective(Bullet, Text); скрытые Progress/Cycle/Bar — для совместимости
--        ├─ Frame "SectionTitle" → Label, Line
--        ├─ ImageLabel "QuestCard" [Inset] → Title, Progress, Description, Why,
--        │     Bar(Fill), Frame "Chips", Points, Blocked, ImageButton "TrackButton"(Caption)
--        ├─ ImageLabel "DoneCard" [Inset] → Title
--        ├─ ImageLabel "ChestCard" [Inset] → Title, Status
--        ├─ Frame "WeeklyBar" → Bar(Fill), Label
--        ├─ TextLabel "Chip"
--        └─ TextLabel "Info"
--------------------------------------------------------------------------------
local Shared = script.Parent.Parent
local UiKit = require(Shared.UiKit)
local Theme = UiKit.Theme

local Builder = {}

local function buildTemplates(gui)
	local templates = Instance.new("Folder")
	templates.Name = "Templates"
	templates.Parent = gui

	-- ТРЕКЕР (v20.3, референс «Sensei Moro Final»): без подложки. Ромб-значок,
	-- засечный заголовок, тонкая линия с «^» (свернуть), описание и строки
	-- целей «◇ - Get X: 0/3». Строка растёт по высоте сама (AutomaticSize).
	local row = Instance.new("ImageButton")
	row.Name = "TrackerRow"
	row.AutoButtonColor = false
	row.BackgroundTransparency = 1
	row.Image = ""
	row.Size = UDim2.new(1, 0, 0, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.Parent = templates
	UiKit.List(row, { Padding = UDim.new(0, 2) })

	local header = UiKit.Group(row, "Header", { Size = UDim2.new(1, 0, 0, 42), LayoutOrder = 1 })
	UiKit.ThemeIcon(header, "Icon", "QuestDiamond", "◈", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(30, 30),
		ImageColor3 = Theme.Accents.Gold.Main,
	})
	local diamond = header.Icon:FindFirstChild("Emoji")
	if diamond then
		diamond.TextColor3 = Theme.Accents.Gold.Main
		diamond.FontFace = Theme.Fonts.Number
	end
	-- Заголовок квеста («Treasure Time») — крупнее всего остального текста трекера.
	local title = UiKit.Text(header, "Title", "Quest", {
		_Style = "Number",
		_Stroke = 2.5,
		Position = UDim2.fromOffset(38, 0),
		Size = UDim2.new(1, -62, 1, -4),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	title.TextScaled = false
	title.TextSize = 32
	UiKit.Text(header, "Caret", "^", {
		_Style = "Heading",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 2),
		Size = UDim2.fromOffset(20, 20),
		TextColor3 = Theme.Colors.SubText,
	})
	local line = UiKit.Group(header, "Line", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 34, 1, 0),
		Size = UDim2.new(1, -34, 0, 2),
		BackgroundTransparency = 0.45,
		BackgroundColor3 = Color3.fromRGB(235, 225, 200),
	})
	UiKit.Gradient(line, Color3.new(1, 1, 1), Color3.new(1, 1, 1), 0, "Fade").Transparency = UiKit.NSeq(0, 0.85)

	local desc = UiKit.Text(row, "Why", "Find the rarest ores to the forge!", {
		_Style = "Heading",
		Size = UDim2.new(1, 0, 0, 24),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 2,
	})
	desc.TextScaled = false
	desc.TextSize = 22

	-- Строка цели: «◇ - Get Fireite: 0/3». Progress — число справа в той же строке.
	local objective = UiKit.Group(row, "Objective", { Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 3 })
	UiKit.Text(objective, "Bullet", "◇", {
		_Style = "Heading",
		Position = UDim2.fromOffset(4, 0),
		Size = UDim2.fromOffset(22, 28),
	})
	local objText = UiKit.Text(objective, "Text", "- Get Fireite:", {
		_Style = "Heading",
		Position = UDim2.fromOffset(28, 0),
		Size = UDim2.new(1, -28, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	objText.TextScaled = false
	objText.TextSize = 22
	-- Контракт клиента: Title/Progress/Why/Cycle/Bar — оставлены (Progress и
	-- Cycle теперь просто подписи, Bar скрыт: на референсе полоски нет).
	local progress = UiKit.Text(row, "Progress", "0/1", { _Style = "Heading", Visible = false, Size = UDim2.fromOffset(0, 0) })
	progress.LayoutOrder = 9
	UiKit.Text(row, "Cycle", "", { _Style = "Heading", Visible = false, Size = UDim2.fromOffset(0, 0), LayoutOrder = 10 })
	local _, fill = UiKit.Bar(row, "Bar", "Gold", { Size = UDim2.fromOffset(0, 0), Visible = false })
	fill.Visible = false
	UiKit.Group(row, "Gap", { Size = UDim2.new(1, 0, 0, 8), LayoutOrder = 20 })

	-- Заголовок секции окна («Daily Quests (23h 59m)»).
	local section = UiKit.SectionHeader(templates, "SectionTitle", "Daily Quests", "Blue", { _Layout = "Left", _Height = 30 })
	section.Size = UDim2.new(1, -8, 0, 30)

	-- Карточка активного квеста.
	local card = UiKit.Plate(templates, "QuestCard", "Inset", { Size = UDim2.new(1, -8, 0, 132) })
	UiKit.Padding(card, 0, 12, 8, 8)
	UiKit.Text(card, "Title", "Daily Quest: Play with a friend", {
		_Style = "Heading",
		Size = UDim2.new(1, -110, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
	})
	UiKit.Text(card, "Progress", "0/20", {
		_Style = "Number",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(110, 24),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Colors.Positive,
		ZIndex = 2,
	})
	UiKit.Plate(card, "TitleLine", "Divider", {
		_Accent = Color3.new(1, 1, 1),
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 2),
		ZIndex = 2,
	})
	UiKit.Text(card, "Description", "Play with a friend for 20 minutes", {
		_Style = "Body",
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
	})
	UiKit.Text(card, "Why", "💡 Why", {
		_Style = "Small",
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(1, -70, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Colors.SubText,
		ZIndex = 2,
	})
	UiKit.Text(card, "Points", "+10 ⭐", {
		_Style = "Heading",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 54),
		Size = UDim2.fromOffset(70, 16),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Accents.Purple.Light,
		Visible = false,
		ZIndex = 2,
	})
	UiKit.Text(card, "Blocked", "Needs 2+ players on the server", {
		_Style = "Small",
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(1, -70, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 150, 110),
		Visible = false,
		ZIndex = 3,
	})
	UiKit.Bar(card, "Bar", "Blue", { Position = UDim2.fromOffset(0, 74), Size = UDim2.new(1, 0, 0, 8), ZIndex = 2 })
	local chips = UiKit.Group(card, "Chips", {
		Position = UDim2.fromOffset(0, 90),
		Size = UDim2.new(1, -96, 0, 22),
		ZIndex = 2,
	})
	UiKit.List(chips, { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), VerticalAlignment = Enum.VerticalAlignment.Center })
	UiKit.Button(card, "TrackButton", "Track", "Track", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 88),
		Size = UDim2.fromOffset(88, 26),
		ZIndex = 3,
	})

	-- Выполненный квест (одна строка).
	local done = UiKit.Plate(templates, "DoneCard", "Inset", { Size = UDim2.new(1, -8, 0, 40), BackgroundTransparency = 0.7 })
	UiKit.Padding(done, 0, 12, 6, 6)
	UiKit.Text(done, "Title", "✔ Quest", {
		_Style = "Heading",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Colors.MutedText,
		ZIndex = 2,
	})

	-- Недельный сундук.
	local chest = UiKit.Plate(templates, "ChestCard", "Inset", { Size = UDim2.new(1, -8, 0, 46) })
	UiKit.Padding(chest, 0, 12, 8, 8)
	UiKit.Text(chest, "Title", "🎁 Chest", {
		_Style = "Heading",
		Size = UDim2.fromScale(0.6, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
	})
	UiKit.Text(chest, "Status", "0/10 ⭐", {
		_Style = "Number",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.4, 1),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Colors.SubText,
		ZIndex = 2,
	})

	local weekly = UiKit.Group(templates, "WeeklyBar", { Size = UDim2.new(1, -8, 0, 22) })
	UiKit.Bar(weekly, "Bar", "Purple", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 14) })

	-- Фишка награды: «$5,000», «1,000 EXP», «60 💎».
	UiKit.Text(templates, "Chip", "$5,000", {
		_Style = "Heading",
		Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		TextScaled = false,
		TextSize = 17,
		TextColor3 = Theme.Colors.Money,
		ZIndex = 2,
	})

	UiKit.Text(templates, "Info", "Info", {
		_Style = "Body",
		Size = UDim2.new(1, -8, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Colors.SubText,
	})
end

function Builder.Build()
	local gui = UiKit.Screen("QuestUi", {
		DisplayOrder = 1200,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	})

	local toggle = UiKit.PlateButton(gui, "QuestToggleButton", "Round", { Size = UDim2.fromOffset(44, 44) })
	UiKit.Text(toggle, "Emoji", "📜", {
		_Stroke = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.6, 0.6),
		ZIndex = 2,
	}).FontFace = Font.fromEnum(Enum.Font.GothamBold)
	UiKit.Badge(toggle, "Badge", "", { Size = UDim2.fromOffset(12, 12), Position = UDim2.new(1, -4, 0, 4), Visible = false })

	-- Трекер слева над портретом: строки растут ВВЕРХ от нижнего края.
	local tracker = UiKit.Group(gui, "QuestTracker", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -140),
		Size = UDim2.fromOffset(380, 300),
	})
	UiKit.List(tracker, { Padding = UDim.new(0, 4), VerticalAlignment = Enum.VerticalAlignment.Bottom })

	UiKit.Dimmer(gui, { Size = UDim2.new(1, 0, 1, 80), Position = UDim2.fromOffset(0, -60), ZIndex = 10 })

	local modal, parts = UiKit.Window(gui, "QuestModal", {
		Title = "Quests",
		Accent = "Blue",
		Size = UDim2.fromOffset(640, 480),
		Position = UDim2.fromScale(0.5, 0.52),
		ZIndex = 11,
	})
	local body = parts.Body
	UiKit.Tabs(body, "Tabs", {
		{ Name = "StoryTab", Text = "Story" },
		{ Name = "DailyTab", Text = "Daily" },
		{ Name = "WeeklyTab", Text = "Weekly" },
	}, "Blue", { Size = UDim2.new(1, 0, 0, 42) })
	local list = UiKit.Scroll(body, "List", {
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 1, -50),
	})
	UiKit.List(list, { Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center })
	UiKit.Padding(list, 4, 0, 6, 10)
	gui:SetAttribute("UiKitVersion", 24) -- v20.8: трекер шрифтом денег, крупный заголовок
	modal:SetAttribute("BaseWidth", 640)
	modal:SetAttribute("BaseHeight", 480)

	buildTemplates(gui)
	UiKit.HideTemplates(gui) -- шаблоны выключены с рождения
	return gui
end

return Builder
