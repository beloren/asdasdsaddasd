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
--   • tools/BuildTutorialUI.lua — кладёт готовый TutorialUi в StarterGui;
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
TutorialUiBuilder.VERSION = 20

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

	-- ДИАЛОГ: тёмная полупрозрачная панель с золотой рамкой (как окна игры).
	local dialog = UiKit.Card(gui, "Dialog", "Gold", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -28),
		Size = narrow and UDim2.new(0.88, 0, 0, 118) or UDim2.new(0.40, 0, 0, 104),
		Visible = false,
	})
	dialog.BackgroundColor3 = Theme.Skins.Panel.Color
	dialog.BackgroundTransparency = 0.12

	-- Плашка имени выступает над рамкой.
	local nameplate = UiKit.Plate(dialog, "Nameplate", "TitleBar", {
		_Accent = "Gold",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 18, 0, 6),
		Size = UDim2.fromOffset(140, 30),
		ZIndex = 3,
	})
	UiKit.Text(nameplate, "Speaker", "???", {
		_Style = "Heading",
		Position = UDim2.fromOffset(8, 2),
		Size = UDim2.new(1, -16, 1, -4),
		TextColor3 = Theme.Accents.Gold.Light,
		ZIndex = 4,
	})

	UiKit.Icon(dialog, "Portrait", "", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(78, 78),
		Visible = false,
		ZIndex = 3,
	})

	local body = UiKit.Text(dialog, "Body", "", {
		_Style = "Body",
		Position = UDim2.fromOffset(20, 18),
		Size = narrow and UDim2.new(1, -32, 1, -42) or UDim2.new(1, -104, 1, -42),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		RichText = true,
		ZIndex = 2,
	})
	body.TextScaled = false
	body.TextSize = 18

	UiKit.Text(dialog, "Continue", "▼", {
		_Style = "Heading",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -8),
		Size = UDim2.fromOffset(28, 28),
		TextColor3 = Theme.Accents.Gold.Main,
		Visible = false,
		ZIndex = 3,
	})

	-- Тап в любое место окна продвигает диалог.
	local advance = Instance.new("TextButton")
	advance.Name = "AdvanceArea"
	advance.Size = UDim2.fromScale(1, 1)
	advance.BackgroundTransparency = 1
	advance.Text = ""
	advance.ZIndex = 5
	advance.Parent = dialog

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
