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

local TutorialUiBuilder = {}

-- narrow = true для узкого экрана (телефон). Влияет только на стартовые
-- размеры; клиент пересчитывает их сам при смене размера окна.
function TutorialUiBuilder.Build(narrow)
	--------------------------------------------------------------------------------
	-- ПАЛИТРА — та же, что у окна престижа и магазина улучшений
	-- (см. PrestigeUiBuilder): тёмно-индиговая панель, золотой акцент. Обучение
	-- не должно выглядеть как элемент из другой игры.
	--------------------------------------------------------------------------------
	local INK = Color3.fromRGB(10, 8, 24)
	local NIGHT = Color3.fromRGB(30, 22, 64)
	local NIGHT_DEEP = Color3.fromRGB(18, 13, 42)
	local GOLD = Color3.fromRGB(255, 200, 70)
	local GOLD_TEXT = Color3.fromRGB(255, 220, 110)

	local function corner(parent, radius)
		local instance = Instance.new("UICorner")
		instance.CornerRadius = UDim.new(0, radius or 12)
		instance.Parent = parent
		return instance
	end

	local function stroke(parent, thickness, color)
		local instance = Instance.new("UIStroke")
		-- Имя нужно клиенту: по нему он находит обводку, чтобы мигнуть ей
		-- при закрытии шага (см. flashFrame в TutorialUI.client.lua).
		instance.Name = "Outline"
		instance.Thickness = thickness or 2
		instance.Color = color or GOLD
		instance.Parent = parent
		return instance
	end

	--------------------------------------------------------------------------------
	-- ПОСТРОЙКА
	--------------------------------------------------------------------------------
	local gui = Instance.new("ScreenGui")
	gui.Name = "TutorialUi"
	gui.ResetOnSpawn = false -- респавн в этой игре ручной; без false окно исчезло бы после первой смерти
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1200
	gui.Enabled = false
	-- Родитель задаёт вызывающий: билдер кладёт в StarterGui, клиент — в PlayerGui.

	-- Узкий экран = телефон/маленькое окно. Проверяем именно ШИРИНУ, а не
	-- UserInputService.TouchEnabled: последний true и на обычных ноутбуках с
	-- тачскрином, из-за чего раскладка ужималась на большом мониторе.
	local function isNarrow()
		local camera = workspace.CurrentCamera
		local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
		return viewport.X < 700
	end

	local dialog = Instance.new("Frame")
	dialog.Name = "Dialog"
	dialog.AnchorPoint = Vector2.new(0.5, 1)
	dialog.Position = UDim2.new(0.5, 0, 1, -28)
	dialog.Size = UDim2.new(0.40, 0, 0, 104)
	dialog.BackgroundColor3 = NIGHT_DEEP
	dialog.BackgroundTransparency = 0.08
	dialog.BorderSizePixel = 0
	dialog.Visible = false
	dialog.Parent = gui
	corner(dialog, 14)
	stroke(dialog, 3, GOLD)

	-- ПЛАШКА ИМЕНИ — отдельным прямоугольником, выступающим НАД рамкой (как на
	-- согласованном референсе). Вынесена наружу, а не внутрь: внутри она съела
	-- бы строку текста, а текста в реплике и так немного.
	local nameplate = Instance.new("Frame")
	nameplate.Name = "Nameplate"
	nameplate.AnchorPoint = Vector2.new(0, 1)
	nameplate.Position = UDim2.new(0, 18, 0, 2)
	nameplate.Size = UDim2.new(0, 124, 0, 28)
	nameplate.BackgroundColor3 = NIGHT
	nameplate.BorderSizePixel = 0
	nameplate.Parent = dialog
	corner(nameplate, 10)
	stroke(nameplate, 2, GOLD)

	local speakerLabel = Instance.new("TextLabel")
	speakerLabel.Name = "Speaker"
	speakerLabel.Size = UDim2.new(1, -16, 1, 0)
	speakerLabel.Position = UDim2.new(0, 8, 0, 0)
	speakerLabel.BackgroundTransparency = 1
	speakerLabel.Font = Enum.Font.FredokaOne
	speakerLabel.TextColor3 = GOLD_TEXT
	speakerLabel.TextScaled = true
	speakerLabel.TextXAlignment = Enum.TextXAlignment.Center
	speakerLabel.Text = "???"
	speakerLabel.Parent = nameplate

	-- ПОРТРЕТ — над рамкой справа, частично перекрывая её верхний край.
	local portrait = Instance.new("ImageLabel")
	portrait.Name = "Portrait"
	portrait.AnchorPoint = Vector2.new(1, 1)
	portrait.Position = UDim2.new(1, -14, 0, 14)
	portrait.Size = UDim2.fromOffset(78, 78)
	portrait.BackgroundTransparency = 1
	portrait.ScaleType = Enum.ScaleType.Fit
	portrait.Visible = false
	portrait.Parent = dialog

	local body = Instance.new("TextLabel")
	body.Name = "Body"
	body.Position = UDim2.new(0, 20, 0, 18)
	body.Size = UDim2.new(1, -104, 1, -42)
	body.BackgroundTransparency = 1
	body.Font = Enum.Font.GothamMedium
	body.TextColor3 = Color3.new(1, 1, 1)
	body.TextSize = 17
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.RichText = true
	body.Text = ""
	body.Parent = dialog

	local continueArrow = Instance.new("TextLabel")
	continueArrow.Name = "Continue"
	continueArrow.AnchorPoint = Vector2.new(1, 1)
	continueArrow.Position = UDim2.new(1, -16, 1, -8)
	continueArrow.Size = UDim2.fromOffset(28, 28)
	continueArrow.BackgroundTransparency = 1
	continueArrow.Font = Enum.Font.FredokaOne
	continueArrow.TextColor3 = GOLD
	continueArrow.TextScaled = true
	continueArrow.Text = "▼"
	continueArrow.Visible = false
	continueArrow.Parent = dialog

	-- Кликабельная подложка на всю рамку: по референсу окно продвигается тапом
	-- в любое место, а не по маленькой кнопке в углу (на телефоне в неё ещё и
	-- попасть надо).
	local advanceButton = Instance.new("TextButton")
	advanceButton.Name = "AdvanceArea"
	advanceButton.Size = UDim2.fromScale(1, 1)
	advanceButton.BackgroundTransparency = 1
	advanceButton.Text = ""
	advanceButton.Parent = dialog

	--------------------------------------------------------------------------------
	-- СВЁРНУТАЯ ПЛАШКА-ЗАДАНИЕ
	--------------------------------------------------------------------------------
	local task_ = Instance.new("Frame")
	task_.Name = "Task"
	task_.AnchorPoint = Vector2.new(0.5, 1)
	task_.Position = UDim2.new(0.5, 0, 1, -28)
	task_.Size = UDim2.new(0.30, 0, 0, 52)
	task_.BackgroundColor3 = NIGHT_DEEP
	task_.BackgroundTransparency = 0.12
	task_.BorderSizePixel = 0
	task_.Visible = false
	task_.Parent = gui
	corner(task_, 12)
	stroke(task_, 2, GOLD)

	local taskTitle = Instance.new("TextLabel")
	taskTitle.Name = "Title"
	taskTitle.Position = UDim2.new(0, 14, 0, 5)
	taskTitle.Size = UDim2.new(1, -28, 0, 18)
	taskTitle.BackgroundTransparency = 1
	taskTitle.Font = Enum.Font.FredokaOne
	taskTitle.TextColor3 = GOLD_TEXT
	taskTitle.TextSize = 15
	taskTitle.TextXAlignment = Enum.TextXAlignment.Left
	taskTitle.Text = ""
	taskTitle.Parent = task_

	local taskBody = Instance.new("TextLabel")
	taskBody.Name = "Body"
	taskBody.Position = UDim2.new(0, 14, 0, 24)
	taskBody.Size = UDim2.new(1, -28, 0, 22)
	taskBody.BackgroundTransparency = 1
	taskBody.Font = Enum.Font.GothamMedium
	taskBody.TextColor3 = Color3.fromRGB(226, 224, 240)
	taskBody.TextSize = 15
	taskBody.TextXAlignment = Enum.TextXAlignment.Left
	taskBody.TextTruncate = Enum.TextTruncate.AtEnd
	taskBody.Text = ""
	taskBody.Parent = task_

	local skipButton = Instance.new("TextButton")
	skipButton.Name = "Skip"
	skipButton.AnchorPoint = Vector2.new(0.5, 0)
	skipButton.Position = UDim2.new(0.5, 0, 1, 6)
	skipButton.Size = UDim2.fromOffset(150, 24)
	skipButton.BackgroundTransparency = 1
	skipButton.Font = Enum.Font.GothamMedium
	skipButton.TextColor3 = Color3.fromRGB(150, 146, 175)
	skipButton.TextSize = 13
	skipButton.Text = "SKIP TUTORIAL" -- клиент переводит через Localization при первом показе
	skipButton.Parent = task_
	return gui
end

return TutorialUiBuilder
