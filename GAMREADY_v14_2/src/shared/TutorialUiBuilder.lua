--------------------------------------------------------------------------------
-- TutorialUiBuilder — ПОСТРОЕНИЕ ОКНА ОБУЧЕНИЯ (см. Config.Tutorial).
--
-- ЗАЧЕМ ОТДЕЛЬНЫЙ МОДУЛЬ. Интерфейс в этом проекте собирается скриптами из
-- tools/, а не рисуется руками в Studio, — окно обучения теперь живёт по
-- тем же правилам. Но у него есть особенность: если билдер ни разу не
-- запускали, обучение обязано работать всё равно (новичок, попавший на
-- сервер без собранного UI, иначе просто не увидит ничего и застрянет).
--
-- Поэтому построение вынесено СЮДА, а вызывают его двое:
--   • tools/BuildAllUI.lua — кладёт готовый TutorialUi в StarterGui;
--   • src/client/TutorialUI.client.lua — если в PlayerGui его не оказалось,
--     строит себе такой же на лету.
-- Одна функция, две точки вызова: разъехаться копиям физически негде.
--
-- КОНТРАКТ ИМЁН (по ним клиент находит элементы; переименование молча
-- сломает показ):
--   Dialog → Nameplate/Speaker, Portrait, Body, Continue, AdvanceArea
--   Task   → Title, Body, Skip
--------------------------------------------------------------------------------

local UiKit = require(script.Parent.UiKit)
local Theme = UiKit.Theme

local TutorialUiBuilder = {}
TutorialUiBuilder.VERSION = 22

-- narrow = true для узкого экрана (телефон). Влияет только на стартовые
-- размеры; клиент пересчитывает их сам при смене размера окна.
function TutorialUiBuilder.Build(narrow)
	if narrow == nil then
		local ok, width = pcall(function() return workspace.CurrentCamera.ViewportSize.X end)
		narrow = ok and width > 0 and width < 700
	end

	local gui = UiKit.Screen("TutorialUi", { DisplayOrder = 1200 })
	gui.Enabled = false
	gui:SetAttribute("BuilderVersion", TutorialUiBuilder.VERSION)

	-- v20.110: ДИАЛОГ = ПЕРСОНАЖ СЛЕВА + ТАБЛИЧКА СПРАВА.
	--   Dialog (прозрачная рамка)
	--   ├─ ImageLabel "Character" - персонаж во весь рост (Config.Tutorial.CharacterImageId)
	--   └─ ImageLabel "Board"     - табличка-подложка (Config.Tutorial.BoardImageId)
	--        ├─ Nameplate/Speaker, Body, Continue, Portrait (скрыт)
	-- Картинки можно поменять прямо в Studio (StarterGui/TutorialUi).
	local dialog = UiKit.Group(gui, "Dialog", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -28),
		Size = narrow and UDim2.new(0.96, 0, 0, 150) or UDim2.new(0, 760, 0, 170),
		Visible = false,
	})

	local character = Instance.new("ImageLabel")
	character.Name = "Character"
	character.BackgroundTransparency = 1
	character.AnchorPoint = Vector2.new(0, 1)
	character.Position = UDim2.new(0, 0, 1, 0)
	character.Size = narrow and UDim2.new(0, 120, 1, 40) or UDim2.new(0, 190, 1, 70)
	character.ScaleType = Enum.ScaleType.Fit
	character.Image = ""
	character.ZIndex = 4
	character.Parent = dialog

	local board = Instance.new("ImageLabel")
	board.Name = "Board"
	board.AnchorPoint = Vector2.new(1, 1)
	board.Position = UDim2.new(1, 0, 1, 0)
	board.Size = narrow and UDim2.new(1, -112, 1, 0) or UDim2.new(1, -176, 1, 0)
	board.BackgroundColor3 = Theme.Skins.Panel.Color
	board.BackgroundTransparency = 0.08
	board.ScaleType = Enum.ScaleType.Slice
	board.SliceCenter = Rect.new(40, 40, 60, 60)
	board.Image = ""
	board.ZIndex = 2
	board.Parent = dialog
	UiKit.Corner(board, 16)
	UiKit.Stroke(board, Theme.Accents.Gold.Main, 3, 0, "Outline")

	-- Плашка имени выступает над табличкой.
	local nameplate = UiKit.Plate(board, "Nameplate", "TitleBar", {
		_Accent = "Gold",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 18, 0, 8),
		Size = UDim2.fromOffset(150, 32),
		ZIndex = 5,
	})
	UiKit.Text(nameplate, "Speaker", "???", {
		_Style = "Heading",
		Position = UDim2.fromOffset(8, 2),
		Size = UDim2.new(1, -16, 1, -4),
		TextColor3 = Theme.Accents.Gold.Light,
		ZIndex = 6,
	})

	-- Старый портрет (совместимость со старыми сборками) - скрыт.
	UiKit.Icon(board, "Portrait", "", {
		Size = UDim2.fromOffset(1, 1),
		Visible = false,
	})

	local body = UiKit.Text(board, "Body", "", {
		_Style = "Body",
		Position = UDim2.fromOffset(22, 22),
		Size = UDim2.new(1, -44, 1, -46),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		RichText = true,
		ZIndex = 4,
	})
	body.TextScaled = false
	body.TextSize = narrow and 17 or 20
	body.TextWrapped = true

	local continueArrow = UiKit.Text(board, "Continue", "", {
		_Style = "Heading",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -8),
		Size = UDim2.fromOffset(28, 28),
		TextColor3 = Theme.Accents.Gold.Main,
		Visible = false,
		ZIndex = 5,
	})
	UiKit.GlyphToShape(continueArrow, "ChevronDown")

	-- Тап в любое место окна продвигает диалог.
	local advance = Instance.new("TextButton")
	advance.Name = "AdvanceArea"
	advance.Size = UDim2.fromScale(1, 1)
	advance.BackgroundTransparency = 1
	advance.Text = ""
	advance.ZIndex = 8
	advance.Parent = dialog

	-- v20.110: УКАЗАТЕЛЬ. Замени картинку своим курсором (Image); острие
	-- картинки - в ЛЕВОМ ВЕРХНЕМ углу (как у курсора мыши).
	local pointer = Instance.new("ImageLabel")
	pointer.Name = "Pointer"
	pointer.BackgroundTransparency = 1
	pointer.AnchorPoint = Vector2.new(0, 0)
	pointer.Size = UDim2.fromOffset(64, 64)
	pointer.Image = ""
	pointer.Visible = false
	pointer.ZIndex = 20
	pointer.Parent = gui
	local fallback = Instance.new("TextLabel")
	fallback.Name = "Fallback"
	fallback.BackgroundTransparency = 1
	fallback.Size = UDim2.fromScale(1, 1)
	fallback.Text = "👆"
	fallback.Rotation = -30
	fallback.TextScaled = true
	fallback.ZIndex = 21
	fallback.Parent = pointer

	-- СВЁРНУТАЯ ПЛАШКА-ЗАДАНИЕ
	local task_ = UiKit.Card(gui, "Task", "Gold", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -28),
		Size = narrow and UDim2.new(0.88, 0, 0, 52) or UDim2.new(0.30, 0, 0, 52),
		Visible = false,
	})
	task_.BackgroundColor3 = Theme.Skins.Panel.Color
	task_.BackgroundTransparency = 0.12
	UiKit.Text(task_, "Title", "", {
		_Style = "Heading",
		Position = UDim2.fromOffset(14, 4),
		Size = UDim2.new(1, -28, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Accents.Gold.Light,
		ZIndex = 2,
	})
	local taskBody = UiKit.Text(task_, "Body", "", {
		_Style = "Body",
		Position = UDim2.fromOffset(14, 25),
		Size = UDim2.new(1, -28, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 2,
	})
	taskBody.TextScaled = false
	taskBody.TextSize = 16

	-- «Пропустить» — тихая текстовая кнопка под плашкой.
	UiKit.TextButton(task_, "Skip", "SKIP TUTORIAL", {
		_Style = "Body",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 6),
		Size = UDim2.fromOffset(170, 22),
		TextColor3 = Theme.Colors.SubText,
	})
	return gui
end

return TutorialUiBuilder
