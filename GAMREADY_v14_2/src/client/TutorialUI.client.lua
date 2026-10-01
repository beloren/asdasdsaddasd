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
-- v20.110: персонаж слева + табличка справа (элементы могут лежать в Board).
local function find(name)
	return dialog:FindFirstChild(name, true) or dialog:WaitForChild(name, 5)
end
local nameplate = find("Nameplate")
local speakerLabel = nameplate:FindFirstChild("Speaker", true)
local portrait = find("Portrait")
local body = find("Body")
local continueArrow = find("Continue")
local characterImage = dialog:FindFirstChild("Character")
local boardImage = dialog:FindFirstChild("Board")
local function imageUri(id)
	id = tonumber(id) or 0
	return id > 0 and ("rbxassetid://" .. id) or nil
end
-- Картинки из Config (если в Studio не поставили свои).
if characterImage and characterImage.Image == "" then
	characterImage.Image = imageUri(Config.Tutorial.CharacterImageId) or imageUri(Config.Tutorial.PortraitImageId) or ""
end
if boardImage and boardImage.Image == "" and imageUri(Config.Tutorial.BoardImageId) then
	boardImage.Image = imageUri(Config.Tutorial.BoardImageId)
	boardImage.BackgroundTransparency = 1
	local outline = boardImage:FindFirstChild("Outline")
	if outline then outline.Enabled = false end
end
local pointer = gui:FindFirstChild("Pointer")
if pointer and pointer.Image == "" and imageUri(Config.Tutorial.PointerImageId) then
	pointer.Image = imageUri(Config.Tutorial.PointerImageId)
	local fb = pointer:FindFirstChild("Fallback")
	if fb then fb.Visible = false end
end
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
	portrait.Visible = false -- v20.110: вместо портрета - персонаж слева (Character)

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
	if not skipArmed then skipButton.Text = tr(payload.SkipText or "SKIP TUTORIAL") end -- v20.110: в главах - SKIP
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
		dialog.Size = narrow and UDim2.new(0.96, 0, 0, 150) or UDim2.new(0, 760, 0, 170)
		task_.Size = narrow and UDim2.new(0.88, 0, 0, 52) or UDim2.new(0.30, 0, 0, 52)
		if characterImage then characterImage.Size = narrow and UDim2.new(0, 120, 1, 40) or UDim2.new(0, 190, 1, 70) end
		if boardImage then boardImage.Size = narrow and UDim2.new(1, -112, 1, 0) or UDim2.new(1, -176, 1, 0) end
	end)
end

--------------------------------------------------------------------------------
-- v20.110: ЗАТЕМНЕНИЕ + УКАЗАТЕЛЬ + НАПОМИНАНИЯ.
--   • Шаг может назвать цели интерфейса (payload.UiTargets, см.
--     Shared.TutorialTarget). Если такая кнопка сейчас на экране - всё
--     вокруг неё темнеет (клики мимо не проходят), вокруг пульсирует рамка,
--     указатель «тапает» в неё.
--   • Иначе указатель показывает на цель в мире (payload.Target), а если
--     она за краем экрана - стоит у края и смотрит в её сторону.
--   • Игрок долго ничего не делает - задание мигает, указатель растёт,
--     звучит подсказка (Config.Tutorial.NudgeSeconds).
--------------------------------------------------------------------------------
local GuiService = game:GetService("GuiService")
local TutorialTarget = require(ReplicatedStorage.Shared.TutorialTarget)

local spot = Instance.new("ScreenGui")
spot.Name = "TutorialSpotlight"
spot.IgnoreGuiInset = true
spot.ResetOnSpawn = false
spot.DisplayOrder = 1150
spot.Enabled = false
spot.Parent = playerGui
local shades = {}
for _, name in { "Top", "Bottom", "Left", "Right" } do
	local frame = Instance.new("TextButton") -- кнопка = клики мимо цели не проходят
	frame.Name = name
	frame.Text = ""
	frame.AutoButtonColor = false
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 0.45
	frame.BorderSizePixel = 0
	frame.Parent = spot
	shades[name] = frame
end
local ring = Instance.new("Frame")
ring.Name = "Ring"
ring.BackgroundTransparency = 1
ring.Parent = spot
local ringStroke = Instance.new("UIStroke")
ringStroke.Thickness = 4
ringStroke.Color = Config.Tutorial.SpotlightColor or Color3.fromRGB(255, 215, 60)
ringStroke.Parent = ring
Instance.new("UICorner", ring).CornerRadius = UDim.new(0, 12)

local SPOT_PAD = 8
local function placeSpot(target)
	local inset = GuiService:GetGuiInset()
	local layer = target:FindFirstAncestorWhichIsA("LayerCollector")
	local offset = (layer and layer:IsA("ScreenGui") and not layer.IgnoreGuiInset) and inset or Vector2.zero
	local pos = target.AbsolutePosition + offset - Vector2.new(SPOT_PAD, SPOT_PAD)
	local size = target.AbsoluteSize + Vector2.new(SPOT_PAD * 2, SPOT_PAD * 2)
	local view = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	shades.Top.Position = UDim2.fromOffset(0, 0)
	shades.Top.Size = UDim2.fromOffset(view.X, math.max(0, pos.Y))
	shades.Bottom.Position = UDim2.fromOffset(0, pos.Y + size.Y)
	shades.Bottom.Size = UDim2.fromOffset(view.X, math.max(0, view.Y - pos.Y - size.Y))
	shades.Left.Position = UDim2.fromOffset(0, pos.Y)
	shades.Left.Size = UDim2.fromOffset(math.max(0, pos.X), size.Y)
	shades.Right.Position = UDim2.fromOffset(pos.X + size.X, pos.Y)
	shades.Right.Size = UDim2.fromOffset(math.max(0, view.X - pos.X - size.X), size.Y)
	ring.Position = UDim2.fromOffset(pos.X, pos.Y)
	ring.Size = UDim2.fromOffset(size.X, size.Y)
	ringStroke.Transparency = 0.15 + (math.sin(os.clock() * 6) + 1) * 0.25
	return pos + size * 0.5, size
end

local lastChangeAt = os.clock()
local lastSignature = nil
local nudgeBoost = 0
local uiTarget, uiCheckAt = nil, 0

local function pointerAt(screenPos, angle, tap)
	if not pointer then return end
	-- острие картинки - левый верхний угол: ставим его в точку
	local bob = math.abs(math.sin(os.clock() * (tap and 5 or 3))) * (tap and 14 or 10)
	local scale = 1 + nudgeBoost * 0.35
	pointer.Size = UDim2.fromOffset(64 * scale, 64 * scale)
	pointer.Rotation = angle or 0
	local dir = Vector2.new(math.cos(math.rad((angle or 0) + 45)), math.sin(math.rad((angle or 0) + 45)))
	local p = screenPos + dir * (6 + bob)
	local insetY = gui.IgnoreGuiInset and 0 or GuiService:GetGuiInset().Y
	pointer.Position = UDim2.fromOffset(p.X, p.Y - insetY)
	pointer.Visible = true
end

RunService.RenderStepped:Connect(function(dt)
	local active = gui.Enabled and current ~= nil and gateOpen() and current.Phase ~= "Hint"
	nudgeBoost = math.max(0, nudgeBoost - dt * 0.4)
	if not active then
		spot.Enabled = false
		if pointer then pointer.Visible = false end
		return
	end
	-- цель интерфейса (переискиваем 4 раза в секунду)
	if os.clock() >= uiCheckAt then
		uiCheckAt = os.clock() + 0.25
		uiTarget = current.UiTargets and TutorialTarget.Find(current.UiTargets) or nil
	end
	if uiTarget and uiTarget.Parent and TutorialTarget.Shown(uiTarget) then
		spot.Enabled = current.Phase == "Task" or current.Phase == "Lines"
		local center, size = placeSpot(uiTarget)
		pointerAt(center + Vector2.new(size.X * 0.15, size.Y * 0.15), 0, true)
		return
	end
	spot.Enabled = false
	-- цель в мире
	local position = targetPosition(currentTarget)
	local camera = workspace.CurrentCamera
	if not (position and camera) or current.Phase ~= "Task" then
		if pointer then pointer.Visible = false end
		return
	end
	local screen, onScreen = camera:WorldToViewportPoint(position + Vector3.new(0, 3.5, 0))
	local view = camera.ViewportSize
	if onScreen and screen.Z > 0 then
		pointerAt(Vector2.new(screen.X, screen.Y), 0, false)
	else
		-- за краем: стрелка у края, острие в сторону цели
		local center = view / 2
		local dir = Vector2.new(screen.X, screen.Y) - center
		if screen.Z < 0 then dir = -dir end
		if dir.Magnitude < 1 then dir = Vector2.new(0, -1) end
		dir = dir.Unit
		local margin = 70
		local scaleX = (view.X / 2 - margin) / math.max(0.001, math.abs(dir.X))
		local scaleY = (view.Y / 2 - margin) / math.max(0.001, math.abs(dir.Y))
		local edge = center + dir * math.min(scaleX, scaleY)
		-- картинка острием в левый верх (-135°), поворачиваем на цель
		local angle = math.deg(math.atan2(dir.Y, dir.X)) + 135
		pointerAt(edge, angle, false)
	end
end)

-- Напоминания: игрок застрял на задании.
task.spawn(function()
	local nudgeEvery = tonumber(Config.Tutorial.NudgeSeconds) or 18
	while true do
		task.wait(1)
		if current then
			local signature = tostring(current.StepIndex) .. "|" .. tostring(current.Phase) .. "|" .. tostring(current.Progress) .. "|" .. tostring(current.Chapter)
			if signature ~= lastSignature then
				lastSignature = signature
				lastChangeAt = os.clock()
			elseif current.Phase == "Task" and gateOpen() and os.clock() - lastChangeAt >= nudgeEvery then
				lastChangeAt = os.clock()
				nudgeBoost = 1
				if task_.Visible then flashFrame(task_) end
				pcall(function() require(ReplicatedStorage.Shared.UiSfx).play("UiHover") end)
			end
		end
	end
end)
