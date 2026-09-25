--------------------------------------------------------------------------------
-- MineExpeditionUI (LocalScript) — РУДА v2, клиентская часть.
--
-- Три обязанности, все чисто визуальные/UX — вся честная проверка
-- (тайминг тычков по дуге, состав добытой руды, шансы) считается на
-- сервере (см. MineService.lua), этот скрипт ей не доверяет и не может
-- сам себе ничего начислить:
--   1. Диалог НПС (RemoteEvent "MineDialogRequest") — простая карточка
--      "GO TO MINE" (по прямому запросу — визуал ты поменяешь в билдере,
--      это функциональный каркас).
--   2. Мини-игра "дуга" (RemoteEvent "MineExpeditionState"/"MineArcHit") —
--      стрелка идёт пинг-понгом по треку, позиция считается ЛОКАЛЬНО от
--      момента получения раунда (чисто для картинки), клик шлёт токен
--      раунда на сервер, тот сам решает — попал или нет.
--   3. Камера — во время всей экспедиции переходит в Scriptable и летает
--      по CFrame'ам, которые присылает сервер (позиции игрока не знает
--      никто, кроме сервера, поэтому все координаты приходят оттуда).
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

local dialogRemote = ReplicatedStorage.Shared:WaitForChild("MineDialogRequest", 10)
local startRemote = ReplicatedStorage.Shared:WaitForChild("MineExpeditionStart", 10)
local stateRemote = ReplicatedStorage.Shared:WaitForChild("MineExpeditionState", 10)
local arcHitRemote = ReplicatedStorage.Shared:WaitForChild("MineArcHit", 10)
if not (dialogRemote and startRemote and stateRemote and arcHitRemote) then
	warn("[MineExpeditionUI] RemoteEvent'ы шахты не появились — фича не будет работать, остальная игра не пострадает.")
	return
end

local BASE_FOV = 70

local function UiSfxLazy(name)
	pcall(function() require(ReplicatedStorage.Shared.UiSfx).play(name) end)
end

--------------------------------------------------------------------------------
-- ДИАЛОГ ШАХТЁРА (v14.3) — в стиле Grow a Garden: реплика висит справа от
-- шахтёра, под ней варианты ответа. Вид — Shared/MinerDialogUiBuilder
-- (Studio-билдер tools/BuildAllUI.lua).
--------------------------------------------------------------------------------
local DialogBuilder = require(ReplicatedStorage.Shared.MinerDialogUiBuilder)

-- v20: StarterGui/MinerDialogUi (tools/BuildAllUI.lua); нет — соберётся билдером.
-- Раньше тут был одноразовый FindFirstChild: копия из StarterGui ещё не
-- успевала прийти, скрипт строил свою, и отредактированная в Studio версия
-- висела рядом никем не используемой.
local UiRegistry = require(ReplicatedStorage.Shared.UiRegistry)
local dialogGui = UiRegistry.Get("MinerDialogUi")
if dialogGui and (dialogGui:GetAttribute("MinerDialogVersion") or 0) < DialogBuilder.VERSION then
	dialogGui:Destroy()
	dialogGui = nil
end
if not dialogGui then
	dialogGui = DialogBuilder.Build()
	dialogGui.Parent = playerGui
end
dialogGui.Enabled = false

local dialogRoot = dialogGui:WaitForChild("Root")
local dialogPop = dialogRoot:FindFirstChild("Pop")
local dialogText = dialogRoot:FindFirstChild("Bubble"):FindFirstChild("Text")
local dialogChoices = dialogRoot:FindFirstChild("Choices")
local choiceTemplate = dialogChoices:FindFirstChild("ChoiceTemplate")
choiceTemplate.Visible = false

local dialogOpen = false
local dialogNpc = nil
local dialogInfo = {}
local typeToken = 0

local function closeDialog(silent)
	if not dialogOpen then return end
	dialogOpen = false
	typeToken += 1
	if dialogPop then
		local out = TweenService:Create(dialogPop, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
		out:Play()
		out.Completed:Once(function()
			if not dialogOpen then dialogGui.Enabled = false end
		end)
	else
		dialogGui.Enabled = false
	end
	if not silent then dialogRemote:FireServer("Close") end
end

-- Печатная машинка: буквы появляются по одной, клик по облачку — сразу всё.
local function typeLine(text)
	typeToken += 1
	local myToken = typeToken
	dialogText.Text = text
	dialogText.MaxVisibleGraphemes = 0
	task.spawn(function()
		local total = utf8.len(dialogText.ContentText) or #text
		for i = 1, total do
			if typeToken ~= myToken then return end
			dialogText.MaxVisibleGraphemes = i
			task.wait(0.016)
		end
		dialogText.MaxVisibleGraphemes = -1
	end)
end

local function setChoices(list)
	for _, child in dialogChoices:GetChildren() do
		if child:IsA("GuiButton") and child ~= choiceTemplate then child:Destroy() end
	end
	for index, choice in list do
		local button = choiceTemplate:Clone()
		button.Name = "Choice" .. index
		button.LayoutOrder = index
		button.Visible = true
		button.BackgroundColor3 = DialogBuilder.CHOICE_COLORS[choice.Kind] or DialogBuilder.CHOICE_COLORS.Ask
		local label = button:FindFirstChild("Label")
		if label then label.Text = choice.Text end
		-- Кнопки выезжают по очереди.
		local scale = Instance.new("UIScale")
		scale.Scale = 0
		scale.Parent = button
		task.delay(0.05 * index, function()
			TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end)
		button.Parent = dialogChoices
		button.Activated:Connect(function()
			UiSfxLazy("DialogueChoice")
			choice.Action()
		end)
	end
end

local showMainPage -- объявлена заранее

local function startDig()
	closeDialog(true)
	startRemote:FireServer()
end

local function showInfoPage()
	local rarity = dialogInfo.Rarity or "Common"
	local color = Config.RarityColors[rarity] or Color3.new(1, 1, 1)
	local hex = ("#%02X%02X%02X"):format(color.R * 255, color.G * 255, color.B * 255)
	typeLine(("It's a <b>TIER %d</b> mine. One dig gives about <b>%d ore</b>, mostly <font color=\"%s\"><b>%s</b></font>. Hit the vein well and rarer stuff comes out!")
		:format(dialogInfo.Tier or 1, dialogInfo.Yield or 0, hex, rarity:upper()))
	setChoices({
		{ Kind = "Yes", Text = "⛏ Let's dig!", Action = startDig },
		{ Kind = "No", Text = "Maybe later", Action = function() closeDialog() end },
	})
end

showMainPage = function()
	if dialogInfo.Blocked then
		typeLine("Whoa, the entrance is <b>blocked</b>! Clear the rubble first, then we can dig.")
		setChoices({
			{ Kind = "Ask", Text = "Okay!", Action = function() closeDialog() end },
		})
		return
	end
	local lines = {
		"Hey partner! Ready to go <b>deep</b>? Grab your pick!",
		"The rocks are talking today... Wanna dig?",
		"Another trip down? I'll lead the way!",
	}
	typeLine(lines[math.random(1, #lines)])
	setChoices({
		{ Kind = "Yes", Text = "⛏ Let's dig!", Action = startDig },
		{ Kind = "Ask", Text = "What's down there?", Action = showInfoPage },
		{ Kind = "No", Text = "Maybe later", Action = function() closeDialog() end },
	})
end

local function openDialog(payload)
	payload = typeof(payload) == "table" and payload or {}
	dialogInfo = payload
	dialogNpc = payload.Npc
	local adornee = dialogNpc and (dialogNpc:FindFirstChild("Head") or dialogNpc.PrimaryPart or dialogNpc:FindFirstChildWhichIsA("BasePart", true))
	dialogGui.Adornee = adornee
	dialogGui.Enabled = true
	dialogOpen = true
	if dialogPop then
		dialogPop.Scale = 0.3
		TweenService:Create(dialogPop, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	showMainPage()
end

-- Клик по облачку — дописать реплику сразу.
local bubbleButton = Instance.new("TextButton")
bubbleButton.Name = "SkipTyping"
bubbleButton.BackgroundTransparency = 1
bubbleButton.Text = ""
bubbleButton.Size = UDim2.fromScale(1, 1)
bubbleButton.ZIndex = 1
bubbleButton.Parent = dialogRoot:FindFirstChild("Bubble")
bubbleButton.Activated:Connect(function()
	typeToken += 1
	dialogText.MaxVisibleGraphemes = -1
end)

-- Ушёл от шахтёра — диалог закрывается сам.
RunService.Heartbeat:Connect(function()
	if not dialogOpen then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local adornee = dialogGui.Adornee
	if not (root and adornee and adornee.Parent) or (root.Position - adornee.Position).Magnitude > 16 then
		closeDialog()
	end
end)

dialogRemote.OnClientEvent:Connect(function(action, payload)
	if action == "Open" then
		openDialog(payload)
	elseif action == "Close" then
		closeDialog(true)
	end
end)

--------------------------------------------------------------------------------
-- КАМЕРА
--------------------------------------------------------------------------------
local cameraActive = false
local cameraRestoreType = Enum.CameraType.Custom

local function beginCameraControl()
	if cameraActive then return end
	cameraActive = true
	cameraRestoreType = camera.CameraType
	camera.CameraType = Enum.CameraType.Scriptable
end

local function endCameraControl()
	if not cameraActive then return end
	cameraActive = false
	camera.CameraType = cameraRestoreType
end

-- entryCFrame — точка входа в шахту (см. MineService), backOffset/upOffset —
-- насколько камера отъезжает назад/вверх от неё (тот же принцип, что и
-- существующий "камера рывок при улучшении шахты" — playUpgradeRevealCamera
-- в CustomCartUI.client.lua, см. Scriptable + TweenService).
--
-- НАПРАВЛЕНИЕ (см. правку по фидбеку — камера была "в текстурках и под
-- землёй"): раньше считали "назад" как -LookVector маркера MineEntryPoint,
-- но у маркера на участке LookVector смотрит НАРУЖУ из шахты (в сторону
-- слайма), поэтому "назад от входа" — это +LookVector, а не -LookVector.
-- Если на каких-то тирах маркер развёрнут иначе и камера снова окажется не
-- с той стороны — поменяй CAMERA_BACK_SIGN на -1, больше трогать нечего.
local CAMERA_BACK_SIGN = 1

local function dollyTo(entryCFrame, backOffset, upOffset, seconds, lookAt)
	if not entryCFrame then return end
	beginCameraControl()
	local focus = lookAt or entryCFrame.Position
	local camPos = entryCFrame.Position + entryCFrame.LookVector * (CAMERA_BACK_SIGN * (backOffset or 20)) + Vector3.new(0, upOffset or 12, 0)
	local ok, target = pcall(CFrame.new, camPos, focus)
	if not ok then return end
	local tween = TweenService:Create(camera, TweenInfo.new(seconds or 1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = target })
	tween:Play()
end

-- МАРКЕРЫ КАМЕРЫ (по прямому запросу — "камера летает не так, как хочет
-- сейчас, а я буду спавнить маркеры с направлением куда она должна
-- смотреть при каждой ситуации"). Сервер присылает готовую пару Position/
-- LookAt (см. MineService.lua:cameraMarkerFor, PlotService:_buildMine —
-- билдер кладёт в модель шахты части "CameraMarkerN"/"CameraMarkerNLook").
-- Камера летит СЮДА, никакого расчёта по EntryCFrame/офсетам.
local function dollyToMarker(markerData, seconds)
	if not markerData then return false end
	beginCameraControl()
	local ok, target = pcall(CFrame.new, markerData.Position, markerData.LookAt)
	if not ok then return false end
	TweenService:Create(camera, TweenInfo.new(seconds or 1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = target }):Play()
	return true
end

-- Общая точка входа для ЛЮБОЙ стадии: если сервер прислал CameraMarker —
-- летим на него (билдер сам расставил, где стоять и куда смотреть);
-- иначе — старый расчётный долли (entryCFrame + офсеты), чтобы шахты, где
-- маркеры ещё не расставлены, не остались совсем без камеры.
-- КАМЕРА ПО ОСИ "ШАХТА → БАНК" (по прямому запросу — "вместо работы по
-- маркерам камеру тоже переделай").
--
-- Маркеры приходилось руками расставлять в каждой шахте, и там, где их
-- забыли, камера молча падала на старый расчётный долли. Теперь план
-- СЧИТАЕТСЯ: берём горизонтальное направление от шахты к банку и отходим
-- вдоль него на distance, поднимаясь на height. Один и тот же код даёт и
-- высокий обзорный план на разговоре с шахтёром, и низкий "киношный" на
-- выбросе руды — разница только в двух числах.
--
-- Возвращает true, если план удалось построить (есть и шахта, и банк).

--------------------------------------------------------------------------------
-- СИГНАЛ КАТСЦЕНЫ: прячет/возвращает HUD (см. client/CinematicHud.client.lua).
-- Создаём по принципу "найди или заведи" — какой из скриптов стартует
-- первым, не гарантировано, и оба должны получить ОДИН и тот же объект.
--------------------------------------------------------------------------------
local cinematicMode = ReplicatedStorage.Shared:FindFirstChild("CinematicMode")
if not cinematicMode then
	cinematicMode = Instance.new("BindableEvent")
	cinematicMode.Name = "CinematicMode"
	cinematicMode.Parent = ReplicatedStorage.Shared
end

local function dollyAlongBankAxis(minePosition, bankPosition, distance, height, aimHeight, seconds)
	if typeof(minePosition) ~= "Vector3" or typeof(bankPosition) ~= "Vector3" then
		return false
	end
	-- Только горизонтальная составляющая: банк может стоять выше или ниже
	-- шахты, и без обнуления Y высота камеры зависела бы от рельефа, а не
	-- от того, что мы here задали.
	local flat = (bankPosition - minePosition) * Vector3.new(1, 0, 1)
	if flat.Magnitude < 0.1 then return false end
	local direction = flat.Unit

	-- ЗДЕСЬ БЫЛА ПРИЧИНА "камера всё равно перетягивается на игрока".
	-- Старые dollyTo/dollyToMarker первым делом звали beginCameraControl()
	-- (он переводит камеру в Scriptable), а эта функция — новая — его не
	-- звала. Твин исправно двигал CFrame, но камера оставалась в режиме
	-- Custom, и штатный контроллер Roblox каждый кадр возвращал её на
	-- игрока. Выглядело как "камера не слушается".
	beginCameraControl()

	local eye = minePosition + direction * distance + Vector3.yAxis * height
	local aim = minePosition + Vector3.yAxis * (aimHeight or 0)
	TweenService:Create(
		camera,
		TweenInfo.new(seconds or 1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = CFrame.lookAt(eye, aim) }
	):Play()
	return true
end

local function dollyToStage(data, fallbackBackOffset, fallbackUpOffset, seconds, fallbackLookAt)
	if dollyToMarker(data.CameraMarker, seconds) then return end
	dollyTo(data.EntryCFrame, fallbackBackOffset, fallbackUpOffset, seconds, fallbackLookAt)
end

-- БАЗОВЫЙ FOV — то значение, к которому камера обязана возвращаться после
-- любой "пружинки". Держим его ОТДЕЛЬНОЙ переменной, а не читаем
-- camera.FieldOfView в момент удара: с накопительным наездом (см. ниже)
-- в камеру почти всегда играет какой-нибудь твин, и снимок живого
-- значения дал бы случайное число из середины анимации. Каждая такая
-- пружинка возвращала бы камеру не туда, откуда началась, и за три
-- попадания FOV уползал бы куда угодно.
local baseFov = BASE_FOV

local function fovTo(target, seconds)
	baseFov = target
	local tween = TweenService:Create(camera, TweenInfo.new(seconds or 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = target })
	tween:Play()
end

-- "Пружинка" FOV на попадание (см. ТЗ "фов игрока меняется будто
-- пружинит") — резкий наезд, потом плавный откат РОВНО к базовому FOV.
local function fovKick(kick, seconds)
	local target = baseFov
	local inTween = TweenService:Create(camera, TweenInfo.new((seconds or 0.22) * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = target + (kick or -6) })
	inTween:Play()
	inTween.Completed:Connect(function()
		-- Возвращаемся к АКТУАЛЬНОМУ baseFov, а не к захваченному выше:
		-- за время пружинки мог прийти следующий "Hit" и придвинуть
		-- камеру ещё ближе — откат не должен его отменять.
		TweenService:Create(camera, TweenInfo.new((seconds or 0.22) * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = baseFov }):Play()
	end)
end

--------------------------------------------------------------------------------
-- МИНИ-ИГРА "РУДНАЯ ЖИЛА" (вариант A)
--
-- Интерфейс собирает ReplicatedStorage.Shared.MineVeinUiBuilder (его же
-- зовёт Studio-билдер tools/BuildAllUI.lua). Здесь — только "оживление":
-- кирка бегает по жиле, зоны раунда приходят с сервера, реакция на удар
-- своя для PERFECT / GOOD / MISS (цвет, звук, вспышка, искры, тряска
-- камеры и интерфейса, каменные осколки из входа шахты), карточка и
-- плашка модификатора захода.
--
-- Позиция кирки считается той же функцией, что и на сервере
-- (Shared.MineVeinMath), поэтому то, что видит игрок, совпадает с тем, что
-- засчитает сервер. В момент нажатия клиент отправляет, сколько времени
-- прошло с начала раунда у НЕГО — сервер учитывает это в пределах лага.
--------------------------------------------------------------------------------
local UserInputService = game:GetService("UserInputService")
local VeinBuilder = require(ReplicatedStorage.Shared.MineVeinUiBuilder)
local MineVeinMath = require(ReplicatedStorage.Shared.MineVeinMath)
local UiSfx = require(ReplicatedStorage.Shared.UiSfx)

local tryVeinHit, stopArcVisual -- объявлены заранее (используются до определения)
local ui = nil -- ссылки на части интерфейса (см. ensureVeinUi)
local activeRoundToken = nil
local sentForToken = nil
local roundReceivedAt = 0
local roundSweepSeconds = 1
local roundMotion = "Linear"
local veinRenderConn = nil
local pickSwingUntil = 0
local cardToken = 0
-- v14.3: параметры режимов текущего раунда (см. MineVeinMath).
local roundFlips = nil     -- REVERSE: моменты разворота
local roundDual = false    -- DUAL PICKS: вторая кирка навстречу
local roundShrink = nil    -- SHRINKING VEIN: { Seconds, MinFrac }
local roundZones = nil     -- исходные зоны раунда
local zonePieces = {}      -- { { Piece, Index } } — для сжатия/гашения
local ghostToken = 0

local QUALITY_COLORS = {
	Perfect = Config.MineExpedition.VeinColors.Perfect,
	Good = Config.MineExpedition.VeinColors.Good,
	Miss = Config.MineExpedition.VeinColors.Miss,
}
local PIP_IDLE_COLOR = Color3.fromRGB(70, 66, 60)
local GHOST_COUNT = 4

-- У ImageLabel задана своя картинка → прячем запасные плашки внутри и
-- делаем фон прозрачным (иначе цветной прямоугольник торчал бы из-под арта).
local function adoptImage(imageLabel)
	if not (imageLabel and imageLabel:IsA("ImageLabel")) then return end
	if imageLabel.Image == "" then return end
	imageLabel.BackgroundTransparency = 1
	for _, child in imageLabel:GetChildren() do
		if child:IsA("GuiObject") then
			child.Visible = false
		elseif child:IsA("UIStroke") then
			child.Enabled = false
		end
	end
end

local function updateAutoScale()
	if not ui then return end
	local viewport = camera.ViewportSize
	-- Контейнер ~660 px в ширину с кнопкой; на узких экранах ужимаем.
	ui.AutoScale.Scale = math.clamp(viewport.X / 700, 0.55, 1)
end

local function ensureVeinUi()
	if ui and ui.Gui.Parent then return ui end

	local gui = UiRegistry.Get("MineArcUi")
	if gui and ((gui:GetAttribute("VeinUiVersion") or 0) < VeinBuilder.VERSION or not gui:FindFirstChild("Vein", true)) then
		warn("[MineExpeditionUI] StarterGui/MineArcUi устарел — собираю жилу кодом. Перезапусти tools/BuildAllUI.lua, чтобы править вид в Studio.")
		gui:Destroy()
		gui = nil
	end
	if not gui then
		gui = VeinBuilder.Build()
		gui.Parent = playerGui
	end
	gui.Enabled = false

	local container = gui:FindFirstChild("Container")
	local vein = container:FindFirstChild("Vein")
	ui = {
		Gui = gui,
		Container = container,
		AutoScale = container:FindFirstChild("AutoScale") or Instance.new("UIScale", container),
		Vein = vein,
		VeinImage = vein:FindFirstChild("VeinImage"),
		Zones = vein:FindFirstChild("Zones"),
		GoodTemplate = vein:FindFirstChild("GoodZoneTemplate"),
		PerfectTemplate = vein:FindFirstChild("PerfectZoneTemplate"),
		Marker = vein:FindFirstChild("Marker"),
		Pick = vein:FindFirstChild("Pick"),
		Flash = vein:FindFirstChild("Flash"),
		Verdict = container:FindFirstChild("Verdict"),
		Pips = container:FindFirstChild("HitPips"),
		Luck = container:FindFirstChild("LuckLabel"),
		Tap = container:FindFirstChild("TapButton"),
		Tag = container:FindFirstChild("ModifierTag"),
		Card = gui:FindFirstChild("ModifierCard"),
		VeinHome = vein.Position,
		Ghosts = {},
	}
	ui.VerdictPop = ui.Verdict and ui.Verdict:FindFirstChild("Pop")
	ui.CardPop = ui.Card and ui.Card:FindFirstChild("Pop")

	adoptImage(ui.VeinImage)
	adoptImage(ui.GoodTemplate)
	adoptImage(ui.PerfectTemplate)
	adoptImage(ui.Pick)
	if ui.Pips then
		for _, pip in ui.Pips:GetChildren() do adoptImage(pip) end
	end

	-- Шлейф кирки: полупрозрачные копии риски на прошлых позициях.
	for i = 1, GHOST_COUNT do
		local ghost = ui.Marker:Clone()
		ghost.Name = "Ghost" .. i
		ghost.ZIndex = ui.Marker.ZIndex - 1
		ghost.BackgroundTransparency = 0.45 + i * 0.12
		ghost.Parent = vein
		ui.Ghosts[i] = ghost
	end

	-- v14.3 DUAL PICKS: вторая кирка и риска — копии первой, окрашенные.
	ui.Pick2 = vein:FindFirstChild("Pick2")
	if not ui.Pick2 then
		ui.Pick2 = ui.Pick:Clone()
		ui.Pick2.Name = "Pick2"
		ui.Pick2.Parent = vein
		if ui.Pick2.Image ~= "" then
			ui.Pick2.ImageColor3 = Color3.fromRGB(255, 150, 215)
		else
			local head = ui.Pick2:FindFirstChild("Head")
			if head then head.BackgroundColor3 = Color3.fromRGB(255, 150, 215) end
		end
	end
	ui.Marker2 = vein:FindFirstChild("Marker2")
	if not ui.Marker2 then
		ui.Marker2 = ui.Marker:Clone()
		ui.Marker2.Name = "Marker2"
		ui.Marker2.BackgroundColor3 = Color3.fromRGB(255, 150, 215)
		ui.Marker2.Parent = vein
	end
	ui.Pick2.Visible = false
	ui.Marker2.Visible = false

	-- Кнопка — только на тач-устройствах; на ПК бьют кликом/пробелом.
	if ui.Tap then
		ui.Tap.Visible = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		ui.Tap.Activated:Connect(function()
			tryVeinHit()
		end)
	end

	updateAutoScale()
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateAutoScale)
	return ui
end

local function trackWidth()
	local width = ui.Vein.AbsoluteSize.X / math.max(ui.AutoScale.Scale, 0.01)
	if width <= 0 then width = ui.Vein:GetAttribute("TrackWidth") or VeinBuilder.VEIN_WIDTH end
	return width
end

-- Удар. Один раз на раунд (клик по кнопке и клик мышью по экрану иначе
-- отправили бы два удара).
tryVeinHit = function()
	local token = activeRoundToken
	if not token or sentForToken == token then return end
	sentForToken = token
	pickSwingUntil = os.clock() + 0.18
	arcHitRemote:FireServer(token, os.clock() - roundReceivedAt)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not activeRoundToken or gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Space
		or input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		tryVeinHit()
	end
end)

--------------------------------------------------------------------------------
-- ТРЯСКА КАМЕРЫ. Смещение снимается, только если камеру с прошлого кадра
-- никто не трогал (иначе твин долли уже выставил её заново и снимать нечего)
-- — поэтому тряска никогда не "уводит" камеру.
--------------------------------------------------------------------------------
local shake = { Amp = 0, Start = 0, Seconds = 0, Offset = CFrame.identity, Written = nil }

local function cameraShake(amplitude, seconds)
	if amplitude <= shake.Amp * math.max(0, 1 - (os.clock() - shake.Start) / math.max(shake.Seconds, 0.01)) then
		return
	end
	shake.Amp = amplitude
	shake.Start = os.clock()
	shake.Seconds = seconds
end

RunService:BindToRenderStep("MineVeinCameraShake", Enum.RenderPriority.Camera.Value + 2, function()
	local current = camera.CFrame
	local base = current
	if shake.Written and current == shake.Written then
		base = current * shake.Offset:Inverse()
	end
	local elapsed = os.clock() - shake.Start
	if shake.Amp > 0 and elapsed < shake.Seconds then
		local k = shake.Amp * (1 - elapsed / shake.Seconds)
		shake.Offset = CFrame.new(
			(math.random() * 2 - 1) * k,
			(math.random() * 2 - 1) * k,
			0
		) * CFrame.Angles(0, 0, (math.random() * 2 - 1) * k * 0.02)
		local written = base * shake.Offset
		camera.CFrame = written
		shake.Written = written
	elseif shake.Written then
		if current == shake.Written then
			camera.CFrame = base
		end
		shake.Written = nil
		shake.Offset = CFrame.identity
		shake.Amp = 0
	end
end)

--------------------------------------------------------------------------------
-- ИСКРЫ В ИНТЕРФЕЙСЕ (квадратики, летят из точки удара и падают)
--------------------------------------------------------------------------------
local function spawnUiSparks(xOffset, quality)
	local count = quality == "Perfect" and 22 or quality == "Good" and 12 or 6
	local colors = quality == "Perfect" and { QUALITY_COLORS.Perfect, Color3.new(1, 1, 1), Color3.fromRGB(255, 235, 150) }
		or quality == "Good" and { QUALITY_COLORS.Good, Color3.fromRGB(200, 250, 170) }
		or { Color3.fromRGB(120, 114, 106), Color3.fromRGB(90, 86, 80) }
	local veinPos = ui.Vein.Position
	local originX = veinPos.X.Offset - trackWidth() / 2 + xOffset
	local originY = veinPos.Y.Offset + 6
	local sparks = {}
	for i = 1, count do
		local size = math.random(4, quality == "Perfect" and 9 or 7)
		local spark = Instance.new("Frame")
		spark.BorderSizePixel = 0
		spark.AnchorPoint = Vector2.new(0.5, 0.5)
		spark.Size = UDim2.fromOffset(size, size)
		spark.BackgroundColor3 = colors[(i % #colors) + 1]
		spark.ZIndex = 18
		spark.Position = UDim2.fromOffset(originX, originY)
		spark.Parent = ui.Container
		local spread = quality == "Miss" and 60 or 200
		table.insert(sparks, {
			Frame = spark,
			X = originX, Y = originY,
			VX = (math.random() * 2 - 1) * spread,
			VY = quality == "Miss" and -math.random(20, 60) or -math.random(120, 300),
		})
	end
	local started = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - started
		for _, s in sparks do
			s.VY += 700 * dt
			s.X += s.VX * dt
			s.Y += s.VY * dt
			s.Frame.Position = UDim2.fromOffset(s.X, s.Y)
			s.Frame.BackgroundTransparency = math.clamp((t - 0.35) / 0.35, 0, 1)
		end
		if t > 0.7 then
			conn:Disconnect()
			for _, s in sparks do s.Frame:Destroy() end
		end
	end)
end

--------------------------------------------------------------------------------
-- КАМЕННЫЕ ОСКОЛКИ ИЗ ВХОДА ШАХТЫ (квадратные детали, с анимацией)
--------------------------------------------------------------------------------
local rockFolder = nil
local function spawnMineRocks(origin, mineSize, count, quality, mineCenter)
	if typeof(origin) ~= "Vector3" or not count or count <= 0 then return end
	-- v9: осколки летят ВОКРУГ ВСЕЙ шахты (по периметру её габаритов),
	-- наружу и вверх, только серые — без золотых/цветных.
	local center = typeof(mineCenter) == "CFrame" and mineCenter or nil
	if not (rockFolder and rockFolder.Parent) then
		rockFolder = Instance.new("Folder")
		rockFolder.Name = "MineHitRocks"
		rockFolder.Parent = workspace
	end
	local footprint = (typeof(mineSize) == "Vector3") and math.max(mineSize.X, mineSize.Z) or 12
	local sizeScale = math.clamp(footprint / 14, 0.7, 2.2)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { rockFolder, player.Character }
	-- Землю меряем от двери (как раньше): луч из центра шахты упирался в
	-- её собственную крышу.
	local hit = workspace:Raycast(origin + Vector3.new(0, 2, 0), Vector3.new(0, -80, 0), params)
	local groundY = hit and hit.Position.Y or (origin.Y - 3)

	-- Летят в основном в сторону камеры (их должно быть видно), веером.
	local toCamera = (camera.CFrame.Position - origin) * Vector3.new(1, 0, 1)
	toCamera = toCamera.Magnitude > 0.1 and toCamera.Unit or Vector3.xAxis
	local rocks = {}
	for i = 1, count do
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Slate
		part.Color = ({ Color3.fromRGB(128, 128, 132), Color3.fromRGB(98, 98, 104), Color3.fromRGB(150, 150, 156) })[(i % 3) + 1]
		local edge = (0.45 + math.random() * 0.75) * sizeScale
		part.Size = Vector3.new(edge * (0.8 + math.random() * 0.4), edge, edge * (0.8 + math.random() * 0.4))
		local dir, start
		if center and typeof(mineSize) == "Vector3" then
			-- Точка на периметре габаритов шахты (эллипс по X/Z), на
			-- случайной высоте нижних двух третей — «шахта трескается».
			local angle = (i / count) * math.pi * 2 + (math.random() - 0.5) * 0.6
			local localDir = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local halfX, halfZ = mineSize.X * 0.5, mineSize.Z * 0.5
			local offset = Vector3.new(localDir.X * halfX, 0, localDir.Z * halfZ)
			local worldOffset = center:VectorToWorldSpace(offset)
			local height = groundY + 0.5 + math.random() * mineSize.Y * 0.65
			start = Vector3.new(center.Position.X + worldOffset.X, height, center.Position.Z + worldOffset.Z)
			dir = center:VectorToWorldSpace(localDir)
		else
			local turn = (math.random() * 2 - 1) * math.rad(80)
			dir = CFrame.fromAxisAngle(Vector3.yAxis, turn):VectorToWorldSpace(toCamera)
			start = origin + dir * 1.5
		end
		part.CFrame = CFrame.new(start)
		part.Parent = rockFolder
		table.insert(rocks, {
			Part = part,
			Pos = start,
			Vel = dir * (10 + math.random() * 10) * math.sqrt(sizeScale) + Vector3.new(0, 12 + math.random() * 10, 0),
			Rot = CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6),
			Axis = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit,
			Spin = 6 + math.random() * 8,
			Size = part.Size,
			Bounced = false,
		})
	end
	local started = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		dt = math.min(dt, 1 / 20)
		local t = os.clock() - started
		local fade = math.clamp((t - 0.7) / 0.45, 0, 1)
		for _, r in rocks do
			r.Vel -= Vector3.new(0, 60 * dt, 0)
			r.Pos += r.Vel * dt
			local floorY = groundY + r.Size.Y * 0.5
			if r.Pos.Y < floorY then
				r.Pos = Vector3.new(r.Pos.X, floorY, r.Pos.Z)
				if not r.Bounced then
					r.Bounced = true
					r.Vel = Vector3.new(r.Vel.X * 0.55, -r.Vel.Y * 0.35, r.Vel.Z * 0.55)
					r.Spin *= 0.5
				else
					r.Vel = Vector3.new(r.Vel.X * 0.9, 0, r.Vel.Z * 0.9)
				end
			end
			r.Rot = CFrame.fromAxisAngle(r.Axis, r.Spin * dt) * r.Rot
			r.Part.Size = r.Size * (1 - fade * 0.95)
			r.Part.Transparency = fade * 0.5
			r.Part.CFrame = CFrame.new(r.Pos) * r.Rot
		end
		if t > 1.15 then
			conn:Disconnect()
			for _, r in rocks do r.Part:Destroy() end
		end
	end)
end

--------------------------------------------------------------------------------
-- ЗОНЫ, ПЛАШКИ, КАРТОЧКА
--------------------------------------------------------------------------------
local function clearZones()
	for _, child in ui.Zones:GetChildren() do
		child:Destroy()
	end
	table.clear(zonePieces)
end

-- v14.3: плавно гасит/зажигает зону целиком (фон, картинка, обводки).
local function fadeZone(piece, transparent, seconds)
	local info = TweenInfo.new(seconds or 0.25)
	for _, object in piece:GetDescendants() do
		if object:IsA("UIStroke") then
			TweenService:Create(object, info, { Transparency = transparent and 1 or 0 }):Play()
		elseif object:IsA("GuiObject") then
			local home = object:GetAttribute("HomeBg")
			if home == nil then home = object.BackgroundTransparency; object:SetAttribute("HomeBg", home) end
			TweenService:Create(object, info, { BackgroundTransparency = transparent and 1 or home }):Play()
		end
	end
	local home = piece:GetAttribute("HomeBg")
	if home == nil then home = piece.BackgroundTransparency; piece:SetAttribute("HomeBg", home) end
	local goals = { BackgroundTransparency = transparent and 1 or home }
	if piece:IsA("ImageLabel") then goals.ImageTransparency = transparent and 1 or 0 end
	TweenService:Create(piece, info, goals):Play()
end

local function drawVeinZones(zones)
	clearZones()
	if type(zones) ~= "table" then return end
	-- Сначала кристаллы, потом самородки — самородок лежит поверх.
	for _, pass in { "Good", "Perfect" } do
		for zoneIndex, zone in zones do
			if zone.Kind == pass then
				local template = pass == "Perfect" and ui.PerfectTemplate or ui.GoodTemplate
				local piece = template:Clone()
				piece.Name = "Zone_" .. pass
				piece.Visible = true
				piece.Position = UDim2.new(zone.Start, 0, 0.5, 0)
				local finalSize = UDim2.new(zone.Finish - zone.Start, 0, template.Size.Y.Scale, template.Size.Y.Offset)
				piece.Parent = ui.Zones
				table.insert(zonePieces, { Piece = piece, Index = zoneIndex })
				if roundShrink then
					-- Сжимающаяся жила: размер ведёт покадровое обновление.
					piece.Size = finalSize
				else
					piece.Size = UDim2.new(0, 0, finalSize.Y.Scale, finalSize.Y.Offset)
					-- Зона "вырастает" из жилы.
					TweenService:Create(piece, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = finalSize }):Play()
				end
				if pass == "Perfect" then
					local glow = piece:FindFirstChild("Glow")
					if glow and glow:IsA("UIStroke") and glow.Enabled then
						TweenService:Create(glow, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.85 }):Play()
					end
				end
			end
		end
	end
end

local function resetPips(hitsRequired)
	if not ui.Pips then return end
	local template = ui.Pips:FindFirstChild("Pip1")
	for i = 1, math.max(hitsRequired or 3, 1) do
		if not ui.Pips:FindFirstChild("Pip" .. i) and template then
			local extra = template:Clone()
			extra.Name = "Pip" .. i
			extra.Parent = ui.Pips
		end
	end
	for _, pip in ui.Pips:GetChildren() do
		local index = tonumber(pip.Name:match("^Pip(%d+)$"))
		if index then
			pip.Visible = index <= (hitsRequired or 3)
			if pip.Image == "" then
				pip.BackgroundColor3 = PIP_IDLE_COLOR
			else
				pip.ImageColor3 = Color3.fromRGB(110, 106, 100)
			end
			pip.Size = UDim2.fromOffset(16, 16)
		end
	end
end

local function markPip(index, quality)
	local pip = ui.Pips and ui.Pips:FindFirstChild("Pip" .. index)
	if not pip then return end
	local color = QUALITY_COLORS[quality] or QUALITY_COLORS.Miss
	if pip.Image == "" then
		pip.BackgroundColor3 = color
	else
		pip.ImageColor3 = color
	end
	pip.Size = UDim2.fromOffset(26, 26)
	TweenService:Create(pip, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(16, 16) }):Play()
end

local function setModifierLook(target, modifier)
	if not target then return end
	local title = target:FindFirstChild("Title")
	local subtitle = target:FindFirstChild("Subtitle")
	local rim = target:FindFirstChild("Rim")
	if title then
		title.Text = modifier.Title or ""
		title.TextColor3 = modifier.Color or title.TextColor3
	end
	if subtitle then subtitle.Text = modifier.Subtitle or "" end
	if rim and rim:IsA("UIStroke") then rim.Color = modifier.Color or rim.Color end
end

-- Крупная карточка модификатора в начале захода: выскакивает, держится,
-- уезжает. Дальше весь заход над жилой висит компактная плашка.
local function showModifierCard(modifier)
	ensureVeinUi()
	if not modifier then
		if ui.Tag then ui.Tag.Visible = false end
		if ui.Card then ui.Card.Visible = false end
		return
	end
	ui.Gui.Enabled = true
	setModifierLook(ui.Card, modifier)
	setModifierLook(ui.Tag, modifier)
	if not ui.Card then return end
	cardToken += 1
	local myToken = cardToken
	ui.Card.Visible = true
	if ui.CardPop then
		ui.CardPop.Scale = 0.2
		TweenService:Create(ui.CardPop, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	UiSfx.play("MineModifierReveal")
	task.delay(2.4, function()
		if cardToken ~= myToken or not ui.Card.Parent then return end
		if ui.CardPop then
			local out = TweenService:Create(ui.CardPop, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
			out:Play()
			out.Completed:Wait()
		end
		if cardToken == myToken then ui.Card.Visible = false end
	end)
end

--------------------------------------------------------------------------------
-- РАУНД
--------------------------------------------------------------------------------
local function placePick(elapsed)
	local width = trackWidth()
	local position = MineVeinMath.NeedlePosition(elapsed, roundSweepSeconds, roundMotion, roundFlips)
	local x = math.round(width * position)
	ui.Marker.Position = UDim2.new(0, x, 0.5, 0)
	ui.Pick.Position = UDim2.new(0, x, 0, 12)
	for i, ghost in ui.Ghosts do
		local past = MineVeinMath.NeedlePosition(math.max(0, elapsed - i * 0.022), roundSweepSeconds, roundMotion, roundFlips)
		ghost.Position = UDim2.new(0, math.round(width * past), 0.5, 0)
	end
	local swinging = os.clock() < pickSwingUntil
	-- Кирка покачивается на ходу; в момент удара резко "клюёт" вниз.
	if swinging then
		ui.Pick.Rotation = -28
	else
		ui.Pick.Rotation = math.sin(os.clock() * 11) * 7
	end
	-- v14.3 DUAL PICKS: вторая кирка зеркально, навстречу.
	if roundDual then
		local x2 = math.round(width * MineVeinMath.MirrorPosition(position))
		ui.Marker2.Position = UDim2.new(0, x2, 0.5, 0)
		ui.Pick2.Position = UDim2.new(0, x2, 0, 12)
		ui.Pick2.Rotation = swinging and 28 or -math.sin(os.clock() * 11) * 7
	end
	-- v14.3 SHRINKING VEIN: зоны сужаются к центру.
	if roundShrink and roundZones then
		local now = MineVeinMath.ZonesAt(roundZones, elapsed, roundShrink)
		for _, entry in zonePieces do
			local zone = now[entry.Index]
			if zone and entry.Piece.Parent then
				entry.Piece.Position = UDim2.new(zone.Start, 0, 0.5, 0)
				entry.Piece.Size = UDim2.new(zone.Finish - zone.Start, 0, entry.Piece.Size.Y.Scale, entry.Piece.Size.Y.Offset)
			end
		end
	end
end

local function startArcVisual(data)
	ensureVeinUi()
	ui.Gui.Enabled = true
	ui.Container.Visible = true
	activeRoundToken = data.Token
	sentForToken = nil
	roundReceivedAt = os.clock()
	roundSweepSeconds = data.SweepSeconds or 1.6
	roundMotion = data.Motion or "Linear"
	roundFlips = data.Flips
	roundDual = data.Dual == true
	roundShrink = data.Shrink
	roundZones = data.Zones
	ui.Pick2.Visible = roundDual
	ui.Marker2.Visible = roundDual

	if (data.RoundIndex or 1) == 1 then
		resetPips(data.HitsRequired)
		ui.Luck.Text = "LUCK +0%"
	end
	if ui.Tag then
		ui.Tag.Visible = data.Modifier ~= nil
		if data.Modifier then
			setModifierLook(ui.Tag, data.Modifier)
			-- MOMENTUM: на плашке — текущая серия.
			local title = ui.Tag:FindFirstChild("Title")
			if title and (data.Momentum or 0) > 0 then
				title.Text = ("%s ×%d"):format(data.Modifier.Title or "", data.Momentum + 1)
			end
		end
	end
	for _, ghost in ui.Ghosts do ghost.Visible = true end
	drawVeinZones(data.Zones)
	-- GHOST VEIN: зоны гаснут через GhostSeconds — бить по памяти.
	ghostToken += 1
	local ghostSeconds = data.Modifier and data.Modifier.GhostSeconds
	if ghostSeconds then
		local myGhost = ghostToken
		task.delay(ghostSeconds, function()
			if ghostToken ~= myGhost or activeRoundToken ~= data.Token then return end
			for _, entry in zonePieces do fadeZone(entry.Piece, true, 0.3) end
		end)
	end

	if veinRenderConn then veinRenderConn:Disconnect() end
	veinRenderConn = RunService.RenderStepped:Connect(function()
		if activeRoundToken ~= data.Token then return end
		placePick(os.clock() - roundReceivedAt)
	end)
end

stopArcVisual = function()
	activeRoundToken = nil
	sentForToken = nil
	if veinRenderConn then
		veinRenderConn:Disconnect()
		veinRenderConn = nil
	end
	cardToken += 1
	ghostToken += 1
	roundDual, roundShrink, roundFlips = false, nil, nil
	if ui then
		ui.Pick2.Visible = false
		ui.Marker2.Visible = false
		ui.Gui.Enabled = false
		if ui.Card then ui.Card.Visible = false end
		if ui.Tag then ui.Tag.Visible = false end
		clearZones()
	end
end

-- Реакция интерфейса на удар: PERFECT / GOOD / MISS заметно разные.
local function playHitFeedback(data)
	ensureVeinUi()
	local quality = data.Quality or "Good"
	local color = QUALITY_COLORS[quality] or QUALITY_COLORS.Good

	-- Кирка застывает там, где засчитан удар.
	activeRoundToken = nil
	pickSwingUntil = os.clock() + 0.22
	local width = trackWidth()
	local x = math.round(width * (data.Position or 0.5))
	ui.Marker.Position = UDim2.new(0, x, 0.5, 0)
	ui.Pick.Position = UDim2.new(0, x, 0, 12)
	ui.Pick.Rotation = -28
	for _, ghost in ui.Ghosts do ghost.Visible = false end
	-- v14.3 DUAL PICKS: засчитанная кирка — та, что попала лучше; вторая
	-- застывает на своём месте.
	if roundDual and data.OtherPosition then
		local x2 = math.round(width * data.OtherPosition)
		local primaryIsFirst = (data.PickIndex or 1) == 1
		local counted, other = ui.Pick, ui.Pick2
		if not primaryIsFirst then counted, other = ui.Pick2, ui.Pick end
		counted.Position = UDim2.new(0, x, 0, 12)
		counted.Rotation = -28
		other.Position = UDim2.new(0, x2, 0, 12)
		other.Rotation = 0
		ui.Marker2.Position = UDim2.new(0, x2, 0.5, 0)
	end
	-- GHOST VEIN: после удара зоны снова видны — видно, куда попал.
	ghostToken += 1
	for _, entry in zonePieces do fadeZone(entry.Piece, false, 0.15) end

	-- Вердикт.
	local verdict = ui.Verdict
	verdict.Text = quality == "Perfect" and "PERFECT!" or quality == "Good" and "GOOD" or "MISS"
	verdict.TextColor3 = color
	verdict.TextTransparency = 0
	local stroke = verdict:FindFirstChildOfClass("UIStroke")
	if stroke then stroke.Transparency = 0 end
	if ui.VerdictPop then
		ui.VerdictPop.Scale = quality == "Perfect" and 1.9 or quality == "Good" and 1.4 or 1.1
		TweenService:Create(ui.VerdictPop, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	task.delay(0.6, function()
		TweenService:Create(verdict, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
		if stroke then TweenService:Create(stroke, TweenInfo.new(0.25), { Transparency = 1 }):Play() end
	end)

	-- Вспышка жилы цветом результата.
	ui.Flash.BackgroundColor3 = color
	ui.Flash.BackgroundTransparency = quality == "Perfect" and 0.15 or quality == "Good" and 0.4 or 0.6
	TweenService:Create(ui.Flash, TweenInfo.new(quality == "Perfect" and 0.45 or 0.3), { BackgroundTransparency = 1 }):Play()

	-- Жила дёргается: PERFECT — подпрыгивает, MISS — трясётся "нет-нет".
	local home = ui.VeinHome
	task.spawn(function()
		local started = os.clock()
		local seconds = quality == "Miss" and 0.3 or 0.25
		while os.clock() - started < seconds do
			local k = 1 - (os.clock() - started) / seconds
			if quality == "Miss" then
				ui.Vein.Position = home + UDim2.fromOffset(math.sin((os.clock() - started) * 70) * 7 * k, 0)
			elseif quality == "Perfect" then
				ui.Vein.Position = home + UDim2.fromOffset((math.random() * 2 - 1) * 4 * k, -9 * k)
			else
				ui.Vein.Position = home + UDim2.fromOffset(0, -4 * k)
			end
			RunService.RenderStepped:Wait()
		end
		ui.Vein.Position = home
	end)

	spawnUiSparks(x, quality)
	markPip(data.RoundIndex or 1, quality)
	if data.LuckBonus then
		ui.Luck.Text = ("LUCK +%d%%"):format(math.floor(data.LuckBonus * 100 + 0.5))
		if (data.LuckGain or 0) > 0 then
			ui.Luck.TextColor3 = color
			TweenService:Create(ui.Luck, TweenInfo.new(0.5), { TextColor3 = Color3.fromRGB(250, 210, 90) }):Play()
		end
	end

	UiSfx.play(quality == "Perfect" and "MineHitPerfect" or quality == "Good" and "MineHitGood" or "MineHitMiss")
	cameraShake(quality == "Perfect" and 0.45 or quality == "Good" and 0.2 or 0.08, quality == "Perfect" and 0.35 or 0.25)
	spawnMineRocks(data.DoorPosition, data.MineSize, data.Rocks, quality, data.MineCenter)
end

--------------------------------------------------------------------------------
-- v14.4: КАРТОЧКА РЕДКОСТИ ШАХТЫ — НАСТОЯЩИЙ 3D-ОБЪЕКТ перед камерой.
--
-- Карточка живёт в мире (в workspace.CurrentCamera, видна только этому
-- игроку) на расстоянии Distance перед объективом и каждый кадр
-- пересчитывается от камеры — поэтому у неё честная перспектива, свет,
-- частицы, а надпись на ней наклоняется вместе с ней.
--
-- Полёт: вылетает снизу, наклонившись ВНИЗ → «застревает» в центре
-- (лёгкое покачивание + эффекты редкости) → улетает вверх, наклоняясь
-- ВВЕРХ. Эффекты по редкости — Config.MineExpedition.RarityCard.Effects.
--
-- Своя модель: ReplicatedStorage.Assets.MineRarityCards.<Rarity> (Model или
-- Part), лицевая сторона — грань Front главной детали. Нет модели —
-- плейсхолдер: объёмная плашка с рамкой и надписью.
--------------------------------------------------------------------------------
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local function cardPart(name, size, color, material, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function buildCardPlaceholder(rarity, color)
	local model = Instance.new("Model")
	model.Name = "RarityCardPlaceholder"
	local plate = cardPart("Plate", Vector3.new(6, 3.4, 0.5), color, Enum.Material.SmoothPlastic, model)
	local dark = color:Lerp(Color3.new(0, 0, 0), 0.55)
	-- Объёмная рамка из четырёх брусков + неоновый кант.
	local rimW = 0.32
	for _, spec in {
		{ Vector3.new(6 + rimW * 2, rimW, 0.8), Vector3.new(0, 1.7 + rimW / 2, 0) },
		{ Vector3.new(6 + rimW * 2, rimW, 0.8), Vector3.new(0, -1.7 - rimW / 2, 0) },
		{ Vector3.new(rimW, 3.4, 0.8), Vector3.new(3 + rimW / 2, 0, 0) },
		{ Vector3.new(rimW, 3.4, 0.8), Vector3.new(-3 - rimW / 2, 0, 0) },
	} do
		local rim = cardPart("Rim", spec[1], dark, Enum.Material.SmoothPlastic, model)
		rim.CFrame = plate.CFrame * CFrame.new(spec[2])
	end
	local glow = cardPart("Glow", Vector3.new(6.9, 4.3, 0.1), color, Enum.Material.Neon, model)
	glow.CFrame = plate.CFrame * CFrame.new(0, 0, 0.45)
	glow.Transparency = 0.25

	local surface = Instance.new("SurfaceGui")
	surface.Name = "Face"
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	surface.CanvasSize = Vector2.new(600, 340)
	surface.LightInfluence = 0
	surface.Parent = plate
	local gradient = Instance.new("Frame")
	gradient.Size = UDim2.fromScale(1, 1)
	gradient.BackgroundColor3 = Color3.new(1, 1, 1)
	gradient.BackgroundTransparency = 0.75
	gradient.BorderSizePixel = 0
	gradient.Parent = surface
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Transparency = NumberSequence.new(0, 1)
	g.Parent = gradient
	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Size = UDim2.fromScale(1, 0.24)
	sub.Position = UDim2.fromScale(0, 0.08)
	require(game:GetService("ReplicatedStorage").Shared.UiKit).StyleText(sub, "Heading") -- v20: шрифт темы
	sub.TextScaled = true
	sub.TextColor3 = Color3.new(1, 1, 1)
	sub.Text = "MINE RARITY"
	sub.Parent = surface
	local subStroke = Instance.new("UIStroke")
	subStroke.Thickness = 4
	subStroke.Color = dark
	subStroke.Parent = sub
	local label = sub:Clone()
	label.Size = UDim2.fromScale(0.9, 0.5)
	label.Position = UDim2.fromScale(0.05, 0.34)
	label.Text = rarity:upper()
	label.Parent = surface
	label:FindFirstChildOfClass("UIStroke").Thickness = 7
	model.PrimaryPart = plate
	return model
end

local function findCardAsset(rarity)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("MineRarityCards")
	local asset = folder and folder:FindFirstChild(rarity)
	if not asset then return nil end
	local copy = asset:Clone()
	if copy:IsA("BasePart") then
		local model = Instance.new("Model")
		model.Name = rarity
		copy.Parent = model
		model.PrimaryPart = copy
		copy = model
	end
	if not copy:IsA("Model") then copy:Destroy() return nil end
	if not copy.PrimaryPart then copy.PrimaryPart = copy:FindFirstChildWhichIsA("BasePart", true) end
	if not copy.PrimaryPart then copy:Destroy() return nil end
	for _, d in copy:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		elseif d:IsA("BaseScript") then
			d:Destroy()
		end
	end
	return copy
end

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARKLE
	e.Enabled = false
	e.LightEmission = 1
	e.LightInfluence = 0
	e.ZOffset = 1
	for key, value in props do e[key] = value end
	e.Parent = parent
	return e
end

local rarityFlashGui = nil
local function screenFlash(color, transparency)
	if not rarityFlashGui or not rarityFlashGui.Parent then
		rarityFlashGui = Instance.new("ScreenGui")
		rarityFlashGui.Name = "MineRarityFlash"
		rarityFlashGui.IgnoreGuiInset = true
		rarityFlashGui.ResetOnSpawn = false
		rarityFlashGui.DisplayOrder = 59
		rarityFlashGui.Parent = playerGui
	end
	local flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = transparency
	flash.BorderSizePixel = 0
	flash.Parent = rarityFlashGui
	local tween = TweenService:Create(flash, TweenInfo.new(0.45), { BackgroundTransparency = 1 })
	tween.Completed:Once(function() flash:Destroy() end)
	tween:Play()
end

local activeCard = nil

local function playRarityCard(data)
	local cfg = Config.MineExpedition.RarityCard or {}
	local rarity = data.Rarity or "Common"
	local color = data.Color or Config.RarityColors[rarity] or Color3.new(1, 1, 1)
	local fx = (cfg.Effects and cfg.Effects[rarity]) or {}
	if activeCard then activeCard:Destroy() end

	local model = findCardAsset(rarity) or buildCardPlaceholder(rarity, color)
	activeCard = model
	local primary = model.PrimaryPart
	model:PivotTo(CFrame.new())
	local pivotOffset = primary.CFrame:ToObjectSpace(model:GetPivot())
	local _, rawSize = model:GetBoundingBox()

	local distance = cfg.Distance or 10
	local function visible()
		local height = 2 * distance * math.tan(math.rad(camera.FieldOfView / 2))
		local viewport = camera.ViewportSize
		return height, height * (viewport.X / math.max(viewport.Y, 1))
	end
	local _, visibleW = visible()
	local cardW = (cfg.ScreenWidth or 0.36) * visibleW
	pcall(function() model:ScaleTo(cardW / math.max(rawSize.X, 0.1)) end)
	pivotOffset = primary.CFrame:ToObjectSpace(model:GetPivot())
	local _, size = model:GetBoundingBox()
	model.Parent = camera

	-- Точка эффектов — центр карточки, чуть перед лицевой гранью.
	local anchor = Instance.new("Attachment")
	anchor.Name = "FxAnchor"
	anchor.Position = Vector3.new(0, 0, -primary.Size.Z / 2 - 0.2)
	anchor.Parent = primary
	local scaleK = cardW / 6 -- размеры эффектов относительно карточки

	-- ПОЛОСКИ ЗА КАРТОЧКОЙ (v20.38) — у КАЖДОЙ редкости свой набор слоёв
	-- (Config.MineExpedition.RarityCard.Backdrops): невидимые плиты с Decal
	-- картинок UiTheme.Backdrops, крутятся с разной скоростью и направлением.
	local UiKit = require(ReplicatedStorage.Shared.UiKit)
	local rayLength = size.X * 2.2
	local layerColor = color:Lerp(Color3.new(1, 1, 1), 0.25)
	local function decalPlate(name, kind, side)
		local plate = cardPart(name, Vector3.new(side, side, 0.05), color, Enum.Material.SmoothPlastic, model)
		plate.Transparency = 1
		local decal = Instance.new("Decal")
		decal.Name = "Backdrop"
		decal.Face = Enum.NormalId.Front
		local resolved = UiKit.BackdropKind(kind)
		decal.Texture = UiKit.ImageUri(UiKit.Theme.Backdrops[resolved])
		decal.Color3 = (UiKit.Theme.BackdropKeepColor and UiKit.Theme.BackdropKeepColor[resolved]) and Color3.new(1, 1, 1) or layerColor
		decal.Transparency = 1
		decal.Parent = plate
		return plate, decal
	end
	local layers = {}
	local layerSpecs = (cfg.Backdrops and cfg.Backdrops[rarity]) or { { Kind = rarity, Spin = 0.9 } }
	for index, spec in layerSpecs do
		local plate, decal = decalPlate("RaysPlate" .. index, spec.Kind or rarity, rayLength * (spec.Scale or 1))
		table.insert(layers, { Plate = plate, Decal = decal, Spin = spec.Spin or 0.9, Depth = 0.6 + index * 0.04 })
	end
	-- Ударная волна (Uncommon+): полоски первого слоя расходятся и гаснут.
	local ring, ringDecal = nil, nil
	if fx.Ring then
		ring, ringDecal = decalPlate("Ring", layerSpecs[1] and layerSpecs[1].Kind or rarity, 1)
	end

	local inSeconds = cfg.InSeconds or 0.6
	local holdSeconds = (cfg.HoldSeconds or 1.45) + (fx.HoldExtra or 0)
	local outSeconds = cfg.OutSeconds or 0.5
	local tilt = math.rad(cfg.TiltDegrees or 24)
	local sway = math.rad(cfg.SwayDegrees or 7)
	local startVy, endVy = -1.7, 1.8
	local started = os.clock()
	local reachedCenter, burstAt = false, 0
	local rainbowHue = 0

	-- v17: плавные кривые. Вылет — с мягким перелётом (Back Out), уход —
	-- с коротким замахом вниз (Back In). Наклон считается от скорости,
	-- а не от позиции, и сглаживается — без рывков на стыках фаз.
	local function easeOutBack(a)
		local c1 = 1.25
		local c3 = c1 + 1
		return 1 + c3 * (a - 1) ^ 3 + c1 * (a - 1) ^ 2
	end
	local function easeInBack(a)
		local c1 = 1.4
		local c3 = c1 + 1
		return c3 * a ^ 3 - c1 * a ^ 2
	end
	local function smooth(a) a = math.clamp(a, 0, 1) return a * a * (3 - 2 * a) end
	local smoothTilt = math.clamp(startVy / 1.2, -1, 1) * tilt

	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		if activeCard ~= model then conn:Disconnect() return end
		local t = os.clock() - started
		local vy, bob, roll, yaw = 0, 0, 0, 0
		if t < inSeconds then
			local a = t / inSeconds
			vy = startVy * (1 - easeOutBack(a))
		elseif t < inSeconds + holdSeconds then
			vy = 0
			-- «Мотается» в центре: мягкое покачивание, крен и поворот.
			-- Амплитуда плавно нарастает и к концу стихает.
			local ht = t - inSeconds
			local envelope = smooth(ht / 0.35) * (1 - smooth((ht - (holdSeconds - 0.3)) / 0.3))
			bob = math.sin(ht * 4.2) * 0.05 * envelope
			roll = math.sin(ht * 3.1) * sway * envelope
			yaw = math.sin(ht * 2.3 + 0.8) * sway * 1.3 * envelope
			if not reachedCenter then
				reachedCenter = true
				burstAt = t
				UiSfx.play("MineModifierReveal")
				local burst = emitter(anchor, {
					Color = ColorSequence.new(color, Color3.new(1, 1, 1)),
					Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5 * scaleK), NumberSequenceKeypoint.new(1, 0) }),
					Speed = NumberRange.new(6 * scaleK, 14 * scaleK),
					Lifetime = NumberRange.new(0.35, 0.7),
					SpreadAngle = Vector2.new(180, 180),
					Drag = 4,
					Rotation = NumberRange.new(0, 360),
					RotSpeed = NumberRange.new(-200, 200),
				})
				burst:Emit(fx.Burst or 12)
				if fx.Stars then
					local stars = emitter(anchor, {
						Color = ColorSequence.new(Color3.new(1, 1, 1)),
						Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, 0.9 * scaleK), NumberSequenceKeypoint.new(1, 0) }),
						Speed = NumberRange.new(2 * scaleK, 5 * scaleK),
						Lifetime = NumberRange.new(0.6, 1),
						SpreadAngle = Vector2.new(180, 180),
					})
					stars:Emit(math.floor((fx.Burst or 12) / 4))
				end
				if (fx.Confetti or 0) > 0 then
					local confetti = emitter(anchor, {
						Texture = "rbxasset://textures/particles/sparkles_main.dds",
						Color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
							ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 220, 80)),
							ColorSequenceKeypoint.new(0.66, Color3.fromRGB(90, 220, 255)),
							ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 110, 255)),
						}),
						LightEmission = 0.4,
						Size = NumberSequence.new(0.28 * scaleK),
						Speed = NumberRange.new(10 * scaleK, 18 * scaleK),
						Lifetime = NumberRange.new(0.9, 1.4),
						SpreadAngle = Vector2.new(70, 70),
						Acceleration = Vector3.new(0, -14 * scaleK, 0),
						Rotation = NumberRange.new(0, 360),
						RotSpeed = NumberRange.new(-300, 300),
					})
					confetti:Emit(fx.Confetti)
				end
				if (fx.Shake or 0) > 0 then cameraShake(fx.Shake, 0.35) end
				if (fx.Flash or 0) > 0 then screenFlash(color, 1 - fx.Flash) end
			end
		else
			local a = math.clamp((t - inSeconds - holdSeconds) / outSeconds, 0, 1)
			vy = endVy * easeInBack(a) -- замах вниз и разгон вверх
		end

		local visibleH = visible()
		local camCF = camera.CFrame
		-- Наклон: снизу — вниз, сверху — вверх; сглажен, чтобы не дёргался
		-- на стыках фаз.
		local targetTilt = math.clamp(vy / 1.2, -1, 1) * tilt
		smoothTilt += (targetTilt - smoothTilt) * math.clamp(dt * 14, 0, 1)
		-- Лицом к камере (flip на 180°).
		local cardCF = camCF * CFrame.new(0, vy * visibleH / 2 + bob, -distance)
			* CFrame.Angles(0, math.pi + yaw, 0)
			* CFrame.Angles(smoothTilt + bob * 0.6, 0, roll)
		-- «Поп» при остановке в центре.
		local popScale = 1
		if reachedCenter then
			local since = t - burstAt
			if since < 0.25 then popScale = 1 + 0.12 * math.sin(since / 0.25 * math.pi) end
		end
		-- «Поп» — карточка на миг подаётся к камере (вдоль своего LookVector).
		local toward = distance * (1 - 1 / popScale)
		model:PivotTo(cardCF * CFrame.new(0, 0, -toward) * pivotOffset)

		-- Лучи и волна — только пока карточка в центре.
		local holding = reachedCenter and t < inSeconds + holdSeconds
		local fade = holding and math.clamp((t - burstAt) / 0.12, 0, 1) or 0
		for index, layer in layers do
			layer.Plate.CFrame = cardCF * CFrame.new(0, 0, layer.Depth) * CFrame.Angles(0, 0, t * layer.Spin)
			layer.Decal.Transparency = 1 - fade * (index == 1 and 0.9 or 0.6)
		end
		if ring then
			local since = reachedCenter and (t - burstAt) or 0
			local grow = math.clamp(since / 0.45, 0, 1)
			local diameter = size.X * (0.4 + grow * 2.4)
			ring.Size = Vector3.new(diameter, diameter, 0.05)
			ring.CFrame = cardCF * CFrame.new(0, 0, 0.3) * CFrame.Angles(0, 0, -t * 1.5)
			ringDecal.Transparency = reachedCenter and (0.2 + grow * 0.8) or 1
		end
		-- Mythic: рамка переливается радугой.
		if fx.Rainbow then
			rainbowHue = (rainbowHue + dt * 0.6) % 1
			local glow = model:FindFirstChild("Glow")
			if glow then glow.Color = Color3.fromHSV(rainbowHue, 0.7, 1) end
		end

		if t >= inSeconds + holdSeconds + outSeconds then
			conn:Disconnect()
			if activeCard == model then activeCard = nil end
			-- Частицам даём догореть.
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") then part.Transparency = 1 end
				if part:IsA("SurfaceGui") then part.Enabled = false end
				if part:IsA("Decal") then part.Transparency = 1 end
			end
			task.delay(1.5, function() model:Destroy() end)
		end
	end)
end

--------------------------------------------------------------------------------
-- ГЛАВНЫЙ ОБРАБОТЧИК СОСТОЯНИЙ ЭКСПЕДИЦИИ
--------------------------------------------------------------------------------
stateRemote.OnClientEvent:Connect(function(stage, data)
	data = data or {}
	if stage == "WalkIn" then
		ProximityPromptService.Enabled = false
		dollyToStage(data, 3, 5, math.max(0.4, (data.WalkSeconds or 2) * 0.6), data.EntryCFrame and data.EntryCFrame.Position)

	elseif stage == "Minigame" then
		cinematicMode:Fire(true) -- прячем HUD на всю катсцену
		-- РАЗГОВОР С ШАХТЁРОМ + МИНИ-ИГРА: камера отходит от шахты в
		-- сторону банка и ВВЕРХ, глядя на шахту сверху. Если банк почему-то
		-- не нашёлся (или ось отключена в конфиге), откатываемся на старый
		-- маркерный/расчётный долли — сцена не должна остаться без камеры.
		local cfg = Config.MineExpedition
		local placed = cfg.UseBankAxisCamera and dollyAlongBankAxis(
			data.MinePosition,
			data.BankPosition,
			cfg.CameraTalkDistance,
			cfg.CameraTalkHeight,
			cfg.CameraTalkAimHeight,
			cfg.CameraTalkSeconds
		)
		if not placed then
			dollyToStage(
				data,
				cfg.CameraBackOffset,
				cfg.CameraUpOffset,
				cfg.CameraDollySeconds,
				data.EntryCFrame and data.EntryCFrame.Position
			)
		end
		fovTo(data.FOV or cfg.CameraFOVMinigame, cfg.CameraDollySeconds)
		-- Модификатор захода — крупной карточкой, пока герои заходят внутрь.
		ensureVeinUi()
		ui.Container.Visible = false
		ui.Gui.Enabled = data.Modifier ~= nil
		showModifierCard(data.Modifier)

	elseif stage == "ArcRound" then
		startArcVisual(data)

	elseif stage == "Hit" then
		-- ПОРЯДОК ВАЖЕН: сначала двигаем базовый FOV (камера подъезжает
		-- ближе и там остаётся), потом бьём пружинкой — она отыграет
		-- назад уже к НОВОЙ, более близкой базе. Наоборот получилось бы
		-- "дёрнулись и уехали", а не "придвинулись рывком".
		if data.FOVBase then
			baseFov = data.FOVBase
			TweenService:Create(
				camera,
				TweenInfo.new(data.FOVBaseSeconds or 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ FieldOfView = data.FOVBase }
			):Play()
		end
		fovKick(data.FOVKick, data.FOVKickSeconds)
		playHitFeedback(data)
		if data.RoundIndex and data.HitsRequired and data.RoundIndex >= data.HitsRequired then
			task.delay(0.75, stopArcVisual)
		end

	elseif stage == "RarityCard" then
		stopArcVisual()
		playRarityCard(data)

	elseif stage == "Eject" then
		stopArcVisual()
		-- ШАХТА ЛОПНУЛА. Камера уходит ЕЩЁ дальше в сторону банка и
		-- ОПУСКАЕТСЯ почти на землю: руда летит из шахты прямо над ней, и
		-- низкий план даёт ей пройти через весь кадр. FOV тоже
		-- возвращается к обычному — после трёх наездов мини-игры кадр
		-- слишком узкий, чтобы вместить разлетающуюся пачку.
		local cfg = Config.MineExpedition
		-- FOV не просто возвращаем к обычному, а РАСШИРЯЕМ: после трёх
		-- наездов мини-игры кадр узкий, а сейчас в него должна поместиться
		-- вся разлетающаяся пачка.
		fovTo(BASE_FOV + (cfg.CameraEjectFOVWiden or 10), data.DiveSeconds or cfg.CameraDiveSeconds or 0.9)
		local placed = cfg.UseBankAxisCamera and dollyAlongBankAxis(
			data.MinePosition,
			data.BankPosition,
			cfg.CameraEjectDistance,
			cfg.CameraEjectHeight,
			cfg.CameraEjectAimHeight,
			data.DiveSeconds or cfg.CameraDiveSeconds
		)
		if not placed then
			if data.CameraMarker then
				dollyToMarker(data.CameraMarker, data.DiveSeconds or 0.9)
			elseif data.DropPosition then
				local dropPos = data.DropPosition
				local diveTarget = CFrame.new(dropPos + Vector3.new(0, 15, 12), dropPos)
				TweenService:Create(camera, TweenInfo.new(data.DiveSeconds or 0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = diveTarget }):Play()
			end
		end

	elseif stage == "WalkOut" then
		-- Если билдер положил маркер конкретно под "выход" — летим туда;
		-- иначе, как и раньше, камера просто остаётся на месте (общий
		-- план выброса руды), возврат в руки игрока — на "Done" ниже.
		if data.CameraMarker then
			dollyToMarker(data.CameraMarker, math.max(0.4, (data.WalkSeconds or 2) * 0.6))
		end

	elseif stage == "Done" then
		cinematicMode:Fire(false) -- катсцена кончилась — возвращаем HUD
		fovTo(BASE_FOV, 0.5)
		task.delay(0.5, function()
			endCameraControl()
			ProximityPromptService.Enabled = true
			stopArcVisual()
		end)
	elseif stage == "Cancelled" then
		stopArcVisual()
		endCameraControl()
		ProximityPromptService.Enabled = true
	end
end)
