--------------------------------------------------------------------------------
-- TutorialUI — ДИАЛОГОВОЕ ОКНО ОБУЧЕНИЯ (см. Config.Tutorial, TutorialService).
--
-- ЧТО ЭТО. Единственная клиентская часть обучения. Ничего не решает и ничего
-- не считает: сервер присылает готовую карточку "что показать" через
-- RemoteEvent TutorialStateEvent, скрипт её рисует. Обратно уходит ровно
-- одно намерение — "Далее" или "Пропустить" (TutorialActionEvent).
--
-- ФОРМА (A+C по согласованному макету):
--   • РАЗВЁРНУТОЕ состояние — классическое диалоговое окно снизу экрана:
--     плашка с именем говорящего, портрет над рамкой, текст печатается
--     посимвольно, мигающая стрелка "дальше" в углу.
--   • СВЁРНУТОЕ состояние — та же рамка, ужатая в одну строку с текущим
--     заданием и счётчиком. Появляется, как только реплики кончились, и
--     держится всё время, пока игрок выполняет шаг.
-- То есть на экране всегда ровно ОДИН элемент обучения, а не карточка
-- плюс трекер плюс подсказка, как было в прежнем гайде.
--
-- ПОЧЕМУ ДВА ОТДЕЛЬНЫХ ФРЕЙМА, А НЕ ОДИН МОРФИРУЮЩИЙСЯ. Разная внутренняя
-- раскладка (портрет/имя/стрелка против одной строки с прогрессом) — при
-- морфинге пришлось бы твинить размеры и прозрачности десятка вложенных
-- элементов и ловить их рассинхрон на каждом переходе. Два фрейма с
-- перекрёстным появлением дают тот же визуальный эффект и не могут
-- застрять в промежуточном состоянии.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Localization = require(ReplicatedStorage.Shared.Localization)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function tr(text, args)
	if not text then return "" end
	local ok, translated = pcall(Localization.Translate, player.LocaleId, text, args)
	return ok and translated or text
end

--------------------------------------------------------------------------------
-- ОКНО СТРОИТСЯ БИЛДЕРОМ.
--
-- Готовый TutorialUi кладёт в StarterGui скрипт tools/BuildAllUI.lua
-- (входит в общую сборку tools/BuildAllUI.lua). Если билдер ни разу не
-- запускали, строим такой же на лету из ТОГО ЖЕ модуля — обучение обязано
-- работать даже на свежем месте, иначе новичок не увидит ничего и застрянет.
--------------------------------------------------------------------------------

local function isNarrow()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	return viewport.X < 700
end

local gui = require(ReplicatedStorage.Shared.UiRegistry).Get("TutorialUi")
gui.Enabled = false

-- Все элементы ищутся по контракту имён из TutorialUiBuilder. Падать при
-- отсутствии нельзя: лучше не показать портрет, чем уронить весь скрипт и
-- оставить игрока вообще без обучения.
local dialog = gui:WaitForChild("Dialog")
local nameplate = dialog:WaitForChild("Nameplate")
local speakerLabel = nameplate:WaitForChild("Speaker")
local portrait = dialog:WaitForChild("Portrait")
local body = dialog:WaitForChild("Body")
local continueArrow = dialog:WaitForChild("Continue")
if continueArrow:IsA("TextLabel") and continueArrow.Text ~= "" then -- старая сборка с символом ▼
	require(game:GetService("ReplicatedStorage").Shared.UiKit).GlyphToShape(continueArrow, "ChevronDown")
end
local advanceButton = dialog:WaitForChild("AdvanceArea")

local task_ = gui:WaitForChild("Task")
local taskTitle = task_:WaitForChild("Title")
local taskBody = task_:WaitForChild("Body")
local skipButton = task_:WaitForChild("Skip")
skipButton.Text = tr("SKIP TUTORIAL")

-- ПРОПУСК В ДВА ТАПА. Кнопка маленькая и стоит у нижнего края — на
-- телефоне в неё легко попасть случайно, а пропуск необратим. Первый тап
-- только меняет надпись; второй в течение SKIP_CONFIRM_SECONDS пропускает.
local SKIP_CONFIRM_SECONDS = 3
local skipArmedToken = 0
local skipArmed = false
local skipStepIndex = nil
local function resetSkipConfirm()
	skipArmed = false
	skipArmedToken += 1
	skipButton.Text = tr("SKIP TUTORIAL")
end


--------------------------------------------------------------------------------
-- СТРЕЛКА И ТРОПИНКА К ЦЕЛИ.
--
-- Цель приходит от сервера ГОТОВЫМ Instance (см. TutorialService:_resolveTarget)
-- — здесь не ищется ничего по имени. Именно клиентский поиск по миру и был
-- в прежнем гайде главным источником "задание есть, а стрелка ведёт в
-- пустоту": любое переименование объекта на базе ломало его молча.
--------------------------------------------------------------------------------
local worldArrowAnchor = Instance.new("Part")
worldArrowAnchor.Name = "TutorialArrowAnchor"
worldArrowAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
worldArrowAnchor.Transparency = 1
worldArrowAnchor.Anchored = true
worldArrowAnchor.CanCollide = false
worldArrowAnchor.CanQuery = false
worldArrowAnchor.CanTouch = false
worldArrowAnchor.Parent = workspace

local worldArrow = Instance.new("BillboardGui")
worldArrow.Name = "TutorialWorldArrow"
worldArrow.Size = UDim2.fromScale(2.4, 2.4)
worldArrow.AlwaysOnTop = true
worldArrow.Enabled = false
worldArrow.Adornee = worldArrowAnchor
worldArrow.Parent = worldArrowAnchor

local worldArrowLabel = Instance.new("TextLabel")
worldArrowLabel.Size = UDim2.fromScale(1, 1)
worldArrowLabel.BackgroundTransparency = 1
require(game:GetService("ReplicatedStorage").Shared.UiKit).StyleText(worldArrowLabel, "Heading") -- v20: шрифт темы
worldArrowLabel.TextColor3 = Config.Tutorial.TrailColor
worldArrowLabel.TextScaled = true
worldArrowLabel.Text = ""
worldArrowLabel.Parent = worldArrow
-- v20.9: стрелка — фигура (символа ▼ в шрифтах Roblox нет → «квадратик»).
require(game:GetService("ReplicatedStorage").Shared.UiKit).GlyphToShape(worldArrowLabel, "ChevronDown")

local trailGroundAnchor = Instance.new("Part")
trailGroundAnchor.Name = "TutorialTrailGroundAnchor"
trailGroundAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
trailGroundAnchor.Transparency = 1
trailGroundAnchor.Anchored = true
trailGroundAnchor.CanCollide = false
trailGroundAnchor.CanQuery = false
trailGroundAnchor.CanTouch = false
trailGroundAnchor.Parent = workspace

local trailEnd = Instance.new("Attachment")
trailEnd.Name = "TutorialTrailEnd"
trailEnd.Parent = trailGroundAnchor

local trailBeam = Instance.new("Beam")
trailBeam.Name = "TutorialTrail"
trailBeam.Width0 = Config.Tutorial.TrailWidth
trailBeam.Width1 = Config.Tutorial.TrailWidth
trailBeam.FaceCamera = true
trailBeam.Color = ColorSequence.new(Config.Tutorial.TrailColor)
trailBeam.Attachment1 = trailEnd
trailBeam.Enabled = false
if (Config.Tutorial.TrailTextureId or 0) ~= 0 then
	trailBeam.Texture = "rbxassetid://" .. Config.Tutorial.TrailTextureId
	trailBeam.TextureMode = Enum.TextureMode.Wrap
	trailBeam.TextureLength = Config.Tutorial.TrailTextureLength
	trailBeam.TextureSpeed = Config.Tutorial.TrailScrollSpeed
end
trailBeam.Parent = trailGroundAnchor

local trailStart = nil
local function attachTrailToCharacter(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	if trailStart then trailStart:Destroy() end
	trailStart = Instance.new("Attachment")
	trailStart.Name = "TutorialTrailStart"
	trailStart.Position = Vector3.new(0, -2.2, 0) -- у земли, а не на уровне груди: иначе дорожка уходит по диагонали в воздух
	trailStart.Parent = root
	trailBeam.Attachment0 = trailStart
end
if player.Character then attachTrailToCharacter(player.Character) end
player.CharacterAdded:Connect(attachTrailToCharacter)

--------------------------------------------------------------------------------
-- СОСТОЯНИЕ
--------------------------------------------------------------------------------
local current = nil        -- последняя карточка от сервера
local currentTarget = nil  -- Instance цели
local typingToken = 0
local canAdvance = false

local stateRemote = ReplicatedStorage.Shared:WaitForChild("TutorialStateEvent")
local actionRemote = ReplicatedStorage.Shared:WaitForChild("TutorialActionEvent")
local hintRemote = ReplicatedStorage.Shared:WaitForChild("TutorialHintEvent")

-- Посимвольная печать через MaxVisibleGraphemes. Токен нужен, чтобы
-- предыдущая реплика не продолжала дописываться поверх новой, если сервер
-- прислал следующую карточку до конца анимации.
--
-- ПОЧЕМУ НЕ string.sub. Он режет по БАЙТАМ, а кириллица в UTF-8 — два
-- байта на букву: на каждом втором кадре строка обрывалась посреди
-- символа и на экране мигали «�», а печать шла вдвое медленнее, чем
-- задано в TypewriterCharDelay. MaxVisibleGraphemes считает видимые
-- символы и заодно не двигает перенос строк во время печати.
local function typeText(label, text, onDone)
	typingToken += 1
	local myToken = typingToken
	label.Text = text
	label.MaxVisibleGraphemes = 0
	local total = utf8.len(text) or #text
	local delayPerChar = Config.Tutorial.TypewriterCharDelay or 0.022
	task.spawn(function()
		for index = 1, total do
			if myToken ~= typingToken then return end
			label.MaxVisibleGraphemes = index
			task.wait(delayPerChar)
		end
		if myToken ~= typingToken then return end
		label.MaxVisibleGraphemes = -1
		if onDone then onDone() end
	end)
end

local function finishTyping()
	-- Тап во время печати не пролистывает реплику, а дописывает её целиком.
	-- Иначе игрок, привыкший тапать быстро, проскакивал бы текст, ни разу
	-- его не увидев.
	if not current or not current.Text then return false end
	-- Сравниваем и подставляем ПЕРЕВЕДЁННУЮ строку: body печатается уже
	-- переведённой, и сверка с исходным английским текстом означала бы,
	-- что тап всегда считается "печать не закончена" и реплика никогда
	-- не пролистывается.
	local full = tr(current.Text)
	if body.Text == full and body.MaxVisibleGraphemes == -1 then return false end
	typingToken += 1
	body.Text = full
	body.MaxVisibleGraphemes = -1
	canAdvance = true
	continueArrow.Visible = true
	return true
end

--------------------------------------------------------------------------------
-- ВОРОТА ПОКАЗА.
--
-- Сервер шлёт первую карточку в момент выдачи участка — а игрок в эту
-- секунду ещё смотрит загрузочный экран и вступительную катсцену
-- (атрибуты AssetsLoaded/IntroActive, см. MoonAnimationTest.client.lua).
-- Без этих ворот окно открывалось ПОД катсценой: посимвольная печать
-- проигрывалась вхолостую, игрок её не видел, а когда катсцена кончалась —
-- обнаруживал уже дописанный текст или пустой экран. Со стороны это
-- выглядело как "туториал появляется с большой задержкой".
--
-- Теперь карточка придерживается и разыгрывается заново, когда игрок
-- реально смотрит на экран.
--------------------------------------------------------------------------------
local pendingPayload = nil

local function gateOpen()
	return player:GetAttribute("AssetsLoaded") ~= false
		and player:GetAttribute("IntroActive") ~= true
		-- ВО ВРЕМЯ ЭКСПЕДИЦИИ обучение молчит целиком. Игрок в этот момент
		-- внутри мини-игры со своей камерой и своим интерфейсом, а стрелка
		-- обучения указывала на вход в шахту — то есть на место, где он уже
		-- стоит, поверх прицела мини-игры.
		and player:GetAttribute("MineExpeditionActive") ~= true
end

--------------------------------------------------------------------------------
-- АНИМАЦИИ.
--
-- Окно не должно возникать и пропадать мгновенно: резкая подмена читается
-- как "мигнуло", и игрок не успевает понять, что сменилось — реплика,
-- задание или шаг целиком. Все переходы идут через выезд снизу с лёгким
-- масштабом, а выполнение шага дополнительно подсвечивается вспышкой
-- рамки — это единственный момент, когда обучение говорит "получилось".
--------------------------------------------------------------------------------
local ANIM_IN = TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local ANIM_OUT = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

-- v20.41: окно стоит НАД ХОТБАРОМ, а не поверх него (на телефоне плашка
-- закрывала ячейки, и нельзя было взять предмет).
local function aboveHotbarOffset()
	local playerGui = player:FindFirstChild("PlayerGui")
	local hotbarGui = playerGui and playerGui:FindFirstChild("HotbarUi")
	local bar = hotbarGui and hotbarGui:FindFirstChild("Bar")
	local camera = workspace.CurrentCamera
	if not (bar and bar:IsA("GuiObject") and hotbarGui.Enabled and bar.Visible and camera) or bar.AbsoluteSize.Y < 2 then
		return -28
	end
	local inset = hotbarGui.IgnoreGuiInset and 0 or game:GetService("GuiService"):GetGuiInset().Y
	local barTop = bar.AbsolutePosition.Y + inset
	return -math.max(28, math.floor(camera.ViewportSize.Y - barTop + 8))
end

local function restingPosition(frame)
	return UDim2.new(frame.Position.X.Scale, frame.Position.X.Offset, 1, aboveHotbarOffset())
end

local function slideIn(frame)
	if frame.Visible and frame:GetAttribute("_Shown") == true then return end
	frame:SetAttribute("_Shown", true)
	local rest = restingPosition(frame)
	frame.Position = UDim2.new(rest.X.Scale, rest.X.Offset, 1, 90)
	frame.Visible = true
	TweenService:Create(frame, ANIM_IN, { Position = rest }):Play()
end

local function slideOut(frame)
	if not frame.Visible then return end
	frame:SetAttribute("_Shown", false)
	local rest = restingPosition(frame)
	local tween = TweenService:Create(frame, ANIM_OUT, {
		Position = UDim2.new(rest.X.Scale, rest.X.Offset, 1, 90),
	})
	tween:Play()
	tween.Completed:Connect(function()
		-- Прячем, только если за время ухода окно не показали снова —
		-- иначе быстрая смена реплик гасила бы уже приехавшее окно.
		if frame:GetAttribute("_Shown") ~= true then frame.Visible = false end
	end)
end

-- Короткая золотая вспышка рамки: шаг закрыт.
local function flashFrame(frame)
	local outline = frame:FindFirstChild("Outline") or frame:FindFirstChildWhichIsA("UIStroke")
	if not outline then return end
	local original = outline.Color
	outline.Color = Color3.fromRGB(255, 255, 255)
	outline.Thickness = 4
	TweenService:Create(outline, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Color = original,
		Thickness = 2,
	}):Play()
end

local lastStepIndex = nil

-- v20.41: АВТО-ЛИСТАНИЕ (Config.Tutorial.AutoAdvanceSeconds). Отсчёт идёт
-- только пока реплика дописана и реально видна: катсцена (IntroActive,
-- CinematicActive), загрузка и мини-игра его ставят на паузу.
local advance
local autoToken = 0
local function startAutoAdvance()
	autoToken += 1
	local token = autoToken
	local total = tonumber(Config.Tutorial.AutoAdvanceSeconds) or 0
	if total <= 0 then return end
	task.spawn(function()
		local waited = 0
		while token == autoToken do
			local dt = task.wait(0.1)
			local playerGui = player:FindFirstChild("PlayerGui")
			local cinematic = playerGui and playerGui:GetAttribute("CinematicActive") == true
			if dialog.Visible and gateOpen() and not cinematic then
				waited += dt
				if waited >= total then
					if token == autoToken and advance then advance() end
					return
				end
			end
		end
	end)
end

local function showDialog(payload)
	if not gateOpen() then pendingPayload = payload; return end
	pendingPayload = nil
	autoToken += 1 -- новая реплика: старый авто-отсчёт больше не действует
	gui.Enabled = true
	slideOut(task_)
	slideIn(dialog)
	canAdvance = false
	continueArrow.Visible = false

	-- Переводим ЗДЕСЬ, а не на сервере: Localization выбирает язык по
	-- LocaleId конкретного игрока, а сервер рассылает одну и ту же карточку.
	speakerLabel.Text = tr(payload.Speaker or "???")
	-- На узком экране текст растянут почти на всю ширину окна — портрет
	-- поверх него закрывал бы конец строки. Раньше здесь стояло
	-- безусловное Visible = true, и на телефоне портрет наезжал на текст.
	if (payload.Portrait or 0) ~= 0 then
		portrait.Image = "rbxassetid://" .. tostring(payload.Portrait)
	end
	portrait.Visible = (payload.Portrait or 0) ~= 0 and not isNarrow()
	body.Size = isNarrow() and UDim2.new(1, -32, 1, -42) or UDim2.new(1, -104, 1, -42)

	typeText(body, tr(payload.Text or ""), function()
		task.wait(Config.Tutorial.AdvanceGuardSeconds or 0.25)
		canAdvance = true
		continueArrow.Visible = true
		startAutoAdvance()
	end)
end

local function showTask(payload)
	if not gateOpen() then pendingPayload = payload; return end
	pendingPayload = nil
	gui.Enabled = true
	slideOut(dialog)
	slideIn(task_)
	-- Смена шага — повод отметить прогресс вспышкой; смена прогресса
	-- внутри одного шага (1/2 → 2/2) её не вызывает, иначе бы мигало.
	if lastStepIndex ~= nil and payload.StepIndex ~= lastStepIndex then
		flashFrame(task_)
	end
	lastStepIndex = payload.StepIndex
	canAdvance = false

	taskTitle.Text = tr(payload.Short or "")
	local text = tr(payload.Task or "")
	if payload.ShowProgress then
		text = ("%s  (%d/%d)"):format(text, payload.Progress or 0, payload.ProgressTarget or 1)
	end
	taskBody.Text = text
	skipButton.Visible = payload.CanSkip ~= false
	-- Сервер переотправляет плашку каждые 2 сек (живая цель стрелки) —
	-- сбрасываем "взведённый" пропуск только при смене шага, иначе
	-- второй тап мог попасть уже в сброшенную кнопку.
	if payload.StepIndex ~= skipStepIndex then
		skipStepIndex = payload.StepIndex
		resetSkipConfirm()
	end
end

local function hideAll()
	slideOut(dialog)
	slideOut(task_)
	gui.Enabled = false
	worldArrow.Enabled = false
	trailBeam.Enabled = false
	currentTarget = nil
end

--------------------------------------------------------------------------------
-- СКРЫТИЕ ПРОЧЕГО UI НА ВРЕМЯ ОБУЧЕНИЯ.
--
-- Список приходит от сервера (см. TutorialService:_hiddenList) и намеренно
-- короткий. Прежний гайд прятал заметную часть интерфейса до восьмого шага,
-- а восьмой при части конфигураций пропускался — и игрок доигрывал сессию
-- вообще без журнала квестов.
--------------------------------------------------------------------------------
local hiddenNow = {}
local function applyHidden(names)
	local wanted = {}
	for _, name in names or {} do wanted[name] = true end
	-- Возвращаем всё, что пряталось раньше и больше не должно.
	for name in hiddenNow do
		if not wanted[name] then
			local screen = playerGui:FindFirstChild(name)
			if screen and screen:IsA("ScreenGui") then screen.Enabled = true end
		end
	end
	for name in wanted do
		local screen = playerGui:FindFirstChild(name)
		if screen and screen:IsA("ScreenGui") then screen.Enabled = false end
	end
	hiddenNow = wanted
end

--------------------------------------------------------------------------------
-- ПРИЁМ СОСТОЯНИЯ
--------------------------------------------------------------------------------
stateRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then return end

	if payload.Phase == "Reveal" then
		applyHidden(payload.Hidden)
		return
	end
	if payload.Phase == "Finished" then
		current = nil
		applyHidden({})
		hideAll()
		return
	end

	current = payload
	currentTarget = payload.Target

	if payload.Phase == "Lines" or payload.Phase == "Done" then
		showDialog(payload)
	else
		showTask(payload)
	end
end)

-- Контекстная подсказка (слой 2, Config.Tutorial.Hints) — то же окно, но
-- вне машины шагов: закрывается тапом и ничего не ждёт.
local hintActive = false
hintRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" or current then return end
	hintActive = true
	-- Phase = "Hint" ставится ДО showDialog: если окно сейчас закрыто
	-- (катсцена, экспедиция), payload уходит в pendingPayload, а
	-- flushPending без фазы рисовал его пустой плашкой задания.
	payload.Phase = "Hint"
	current = payload
	showDialog(payload)
end)

-- Сообщаем серверу, что подписка на OnClientEvent уже стоит и можно слать
-- состояние. Первый FireClient со стороны сервера уходит в момент выдачи
-- участка и вполне может опередить запуск этого LocalScript — потерянный
-- пакет Roblox не досылает, и обучение выглядело бы просто не включившимся.
-- Повторяем, пока состояние не придёт. Одного "Ready" мало: сервер создаёт
-- состояние игрока только после загрузки профиля и выдачи участка, и если
-- это заняло дольше, чем разовый повтор, обучение не появлялось вообще —
-- до первого случайного обновления прогресса.
task.spawn(function()
	for _ = 1, 20 do
		if current then return end
		actionRemote:FireServer("Ready")
		task.wait(1)
	end
end)

-- Катсцена кончилась / ассеты догрузились — разыгрываем придержанную
-- карточку заново, с самого начала печати.
local function flushPending()
	if not gateOpen() or not pendingPayload then return end
	local payload = pendingPayload
	pendingPayload = nil
	if payload.Phase == "Lines" or payload.Phase == "Done" or payload.Phase == "Hint" then
		showDialog(payload)
	else
		showTask(payload)
	end
end
player:GetAttributeChangedSignal("IntroActive"):Connect(flushPending)
player:GetAttributeChangedSignal("AssetsLoaded"):Connect(flushPending)
player:GetAttributeChangedSignal("MineExpeditionActive"):Connect(function()
	if player:GetAttribute("MineExpeditionActive") == true then
		-- Прячем немедленно: ждать следующей карточки от сервера нельзя,
		-- катсцена входа начинается прямо сейчас.
		pendingPayload = current
		hideAll()
	else
		flushPending()
	end
end)

function advance()
	autoToken += 1 -- ручное «Далее» отменяет авто-отсчёт этой реплики
	if finishTyping() then return end
	if not canAdvance then return end
	canAdvance = false
	if hintActive then
		hintActive = false
		current = nil
		hideAll()
		return
	end
	actionRemote:FireServer("Advance")
end

advanceButton.Activated:Connect(advance)
skipButton.Activated:Connect(function()
	if not skipArmed then
		skipArmed = true
		skipArmedToken += 1
		local myToken = skipArmedToken
		skipButton.Text = tr("TAP AGAIN TO SKIP")
		task.delay(SKIP_CONFIRM_SECONDS, function()
			if myToken == skipArmedToken then resetSkipConfirm() end
		end)
		return
	end
	resetSkipConfirm()
	actionRemote:FireServer("Skip")
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not dialog.Visible then return end
	-- Игнорируем ввод, пока игрок печатает в поле (промокоды в настройках).
	if UserInputService:GetFocusedTextBox() then return end
	-- Enter, а не E/Space: E — клавиша ProximityPrompt (торговец, валуны,
	-- тележка), и одно нажатие одновременно открывало магазин и
	-- пролистывало реплику; Space заставлял персонажа прыгать. Мышь и тап
	-- по окну работают как раньше (AdvanceArea).
	if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
		advance()
	end
end)

--------------------------------------------------------------------------------
-- ОТРИСОВКА СТРЕЛКИ
--------------------------------------------------------------------------------
local function targetPosition(instance)
	if not instance or not instance.Parent then return nil end
	if instance:IsA("BasePart") then
		return instance.Position + Vector3.new(0, instance.Size.Y * 0.5, 0)
	elseif instance:IsA("Model") then
		local ok, cframe, size = pcall(function()
			local c, s = instance:GetBoundingBox()
			return c, s
		end)
		if ok and cframe then
			return cframe.Position + Vector3.new(0, (size and size.Y or 2) * 0.5, 0)
		end
		local pivot = instance:GetPivot()
		return pivot.Position
	end
	return nil
end

RunService.RenderStepped:Connect(function()
	if not gui.Enabled or not current then
		worldArrow.Enabled = false
		trailBeam.Enabled = false
		return
	end
	local position = targetPosition(currentTarget)
	if not position then
		worldArrow.Enabled = false
		trailBeam.Enabled = false
		return
	end
	worldArrowAnchor.Position = position + Vector3.new(0, 2.5 + math.sin(os.clock() * 4) * 0.45, 0)
	worldArrow.Enabled = true
	-- Конец дорожки держим у земли (без покачивания, в отличие от стрелки):
	-- иначе линия уходит по диагонали вверх и теряется на глаз.
	trailGroundAnchor.Position = Vector3.new(position.X, position.Y - 2, position.Z)
	if not trailStart and player.Character then attachTrailToCharacter(player.Character) end
	trailBeam.Enabled = trailStart ~= nil
end)

-- v20.41: хотбар может сдвинуться (поворот телефона, подгонка масштаба) —
-- раз в секунду подтягиваем показанные окна к его верхнему краю.
task.spawn(function()
	while true do
		task.wait(1)
		for _, frame in { dialog, task_ } do
			if frame.Visible and frame:GetAttribute("_Shown") == true then
				local rest = restingPosition(frame)
				if math.abs(frame.Position.Y.Offset - rest.Y.Offset) > 2 and math.abs(frame.Position.Y.Offset - rest.Y.Offset) < 400 then
					TweenService:Create(frame, ANIM_OUT, { Position = rest }):Play()
				end
			end
		end
	end
end)

-- Раскладка под узкий экран пересчитывается на смену размера окна, а не
-- один раз при запуске: игрок может развернуть окно или повернуть телефон.
local camera = workspace.CurrentCamera
if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		local narrow = isNarrow()
		dialog.Size = narrow and UDim2.new(0.88, 0, 0, 118) or UDim2.new(0.40, 0, 0, 104)
		task_.Size = narrow and UDim2.new(0.88, 0, 0, 52) or UDim2.new(0.30, 0, 0, 52)
		-- Портрет возвращается при повороте обратно в широкий режим —
		-- раньше, спрятавшись однажды, он пропадал до следующей реплики.
		portrait.Visible = portrait.Image ~= "" and dialog.Visible and not narrow
		body.Size = narrow and UDim2.new(1, -32, 1, -42) or UDim2.new(1, -104, 1, -42)
	end)
end
