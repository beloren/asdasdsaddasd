--------------------------------------------------------------------------------
-- MineService — РУДА v2 (см. Config.MineExpedition в Config.lua и оба
-- сообщения ТЗ "переписать систему механики сбора руды").
--
-- Старая механика ("подъехал тележкой к шахте — руда сыплется сама, пока
-- стоишь") полностью убрана (см. Config.MiningRhythm.Enabled = false —
-- старый код ритм-мини-игры оставлен в файлах, но больше не подключается).
-- Новый цикл на игрока:
--   1. Подходишь к MinerNPC слева от шахты → диалог → "GO TO MINE".
--   2. НПС и КЛОН игрока заходят внутрь по очереди (см. buildActorClone/
--      moveModel); сам игрок стоит невидимым на месте разговора, камера
--      отъезжает и поднимается (см. Config.MineExpedition.CameraBackOffset/
--      CameraUpOffset — клиент считает саму камеру, см. MineExpeditionUI
--      .client.lua, сервер только присылает целевые CFrame/тайминги).
--   3. Мини-игра "дуга": HitsRequired (по ТЗ — 3) успешных тычки (см.
--      _runArcMinigame/_onArcHit). Стрелка идёт по дуге пинг-понгом,
--      позиция считается ОБЕИМИ сторонами детерминированно от времени
--      начала раунда — сеть не гоняет позицию каждый кадр, только токен
--      раунда и сам факт клика (тот же приём честности, что был у старой
--      ритм-мини-игры). Каждое попадание — FOV-пружинка + шахта "дышит"
--      + дверь шахты (MineDoor) обновляет цвет (см. _pulseMineDoor).
--   4. На последнем попадании — выброс руды (см. _ejectOre): считается
--      тир/количество (Config.MineTiers[tier].OreYield), роллится состав
--      пачки (Config.RollOreForTier — 4 руды тира с весами 60/30/8/2),
--      самая редкая руда летит первой и в центр, остальные — парой затем
--      волнами (см. Config.MineExpedition.WaveSize). Дверь получает
--      финальный цвет по редкости (Config.MineDoorRarityColor) и включает
--      свои VFX_<Rarity>-attachment'ы, см. _applyDoorRarity.
--      Руда приземляется в workspace.MineGroundOre чёрной: спойлерится
--      САМА руда (её части временно становятся чёрным неоном, см.
--      applySpoilerLook), а над ней висят анимированные "???" (см.
--      attachMysteryGui + client/OreMysteryFX.client.lua). Через
--      паузу раскрывается (снимается Shell + показывается PriceGui с
--      честным шансом "1/N", см. CrystalService.attachPriceGui).
--      Подбирается НАЕЗДОМ тележки — см. новый Heartbeat-подборщик в
--      CartService.lua (папка/атрибуты тот же контракт: GroundOreOwner,
--      Landed).
--   5. НПС и игрок выходят, камера возвращается игроку (см. _finishExpedition).
--
-- Все переходы состояний ведёт СЕРВЕР — клиент только рисует UI/камеру по
-- присылаемым RemoteEvent'ам (RemoteEvent "MineExpeditionState") и
-- подтверждает тычки по дуге через "MineArcHit" (с честной серверной
-- проверкой тайминга, сервер НИКОГДА не верит позиции стрелки от клиента).
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldUi = require(ReplicatedStorage.Shared.WorldUi) -- v20: стили мировых надписей (StarterGui/WorldUiTemplates)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)
local CrystalUtil = require(ReplicatedStorage.Shared.CrystalUtil)
local Sfx = require(ReplicatedStorage.Shared.Sfx)
local MineVeinMath = require(ReplicatedStorage.Shared.MineVeinMath)

local MineService = {}

-- Объявлены заранее: определены ниже (раздел мини-игры), а используются
-- уже в _beginExpedition, который стоит в файле выше.
local pickVeinModifier
local publicModifier
local Services = nil

local npcRecords = {} -- [player] = { Npc, Prompt, IsCustom, WatchdogToken }
local expeditions = {} -- [player] = { Token, Plot, Cart, Tier, Hits, PendingRound, OriginCFrame, OriginWalkSpeed }

-- ПОЗИЦИЯ БАНКА — ось, вдоль которой теперь отходит камера (см.
-- Config.MineExpedition.UseBankAxisCamera). Отдаём клиенту в payload
-- каждой стадии: клиент сам банк не ищет, чтобы у него и у сервера не
-- разъехалось представление о том, где он.
local function bankPosition()
	if Services.WorldService and Services.WorldService.GetBankTargetPosition then
		local ok, position = pcall(function()
			return Services.WorldService:GetBankTargetPosition()
		end)
		if ok and typeof(position) == "Vector3" then return position end
	end
	return nil
end

-- Точка самой шахты, от которой отмеряется отход камеры.
local function minePosition(plot)
	if plot.MineDoorPart and plot.MineDoorPart:IsA("BasePart") then
		return plot.MineDoorPart.Position
	end
	return plot.MineEntryCFrame and plot.MineEntryCFrame.Position or nil
end

-- v14.3: ОСЬ КАМЕРЫ И ВЫЛЕТА. Если в PlotTemplate есть MineFacingMarker
-- (см. PlotService:_buildMine → plot.MineFacingDir), камера мини-игры,
-- камера вылета и сама куча руды встают на ось «куда смотрит шахта».
-- Клиенту по-прежнему уходит поле BankPosition — просто теперь это точка
-- далеко перед шахтой, и все старые расчёты «вдоль оси к банку» сами
-- становятся расчётами «вдоль взгляда шахты». Нет маркера — банк, как было.
local function axisTarget(plot)
	if plot and plot.MineFacingDir then
		local origin = minePosition(plot)
		if origin then return origin + plot.MineFacingDir * 1000 end
	end
	return bankPosition()
end

--------------------------------------------------------------------------------
-- КАТСЦЕНА С ДУБЛЁРОМ
--
-- Раньше в шахту заезжал САМ игрок: его замораживали и ручным Lerp'ом
-- тащили ко входу (_freezeAndGlide), а камера летела следом внутрь. Из-за
-- этого его приходилось потом возвращать обратно, и любой сбой посреди
-- катсцены оставлял человека стоять у шахты.
--
-- Теперь настоящий персонаж НЕ ДВИГАЕТСЯ ВООБЩЕ. Он просто становится
-- невидимым и стоит там, где нажал на разговор, а в шахту заходит его
-- КЛОН. Поэтому "вернуть игрока на место" не требуется как задача — он с
-- места и не уходил, что бы ни случилось с катсценой по дороге.
--------------------------------------------------------------------------------

-- Универсальное "иди туда" для любой модели (шахтёр, клон): pivot едет
-- Lerp'ом по кадрам. Токен в атрибуте обрывает предыдущее движение той же
-- модели, если пришло новое — иначе два Lerp'а тянули бы её в разные
-- стороны одновременно.
local function moveModel(model, targetCFrame, seconds)
	if not (model and model.Parent and targetCFrame) then return end
	local startCFrame = model:GetPivot()
	local token = HttpService:GenerateGUID(false)
	model:SetAttribute("_MoveToken", token)
	local steps = math.max(6, math.floor(seconds * 30))
	task.spawn(function()
		for i = 1, steps do
			if model:GetAttribute("_MoveToken") ~= token or not model.Parent then return end
			model:PivotTo(startCFrame:Lerp(targetCFrame, i / steps))
			task.wait(seconds / steps)
		end
	end)
end

-- Видимость всей модели разом. Исходная прозрачность каждой детали
-- запоминается В АТРИБУТЕ САМОЙ ДЕТАЛИ: так восстановление не зависит от
-- того, жива ли ещё корутина, которая её спрятала, и переживает даже
-- аварийный обрыв катсцены.
local function setModelVisible(model, visible)
	if not (model and model.Parent) then return end
	for _, d in model:GetDescendants() do
		local isPart = d:IsA("BasePart")
		local isSurface = d:IsA("Decal") or d:IsA("Texture")
		if isPart or isSurface then
			if visible then
				local saved = d:GetAttribute("_MineHidden")
				if saved ~= nil then
					d.Transparency = saved
					d:SetAttribute("_MineHidden", nil)
				end
			elseif d:GetAttribute("_MineHidden") == nil then
				d:SetAttribute("_MineHidden", d.Transparency)
				d.Transparency = 1
			end
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Иначе над невидимым игроком продолжало бы висеть его имя и
		-- полоска здоровья персонажа, которого "нет".
		humanoid.NameDisplayDistance = visible and 100 or 0
		humanoid.HealthDisplayDistance = visible and 100 or 0
	end
end

-- Клон-дублёр. Снимается с ЖИВОГО персонажа до того, как оригинал
-- спрятали, поэтому несёт всю его внешность: одежду, аксессуары, цвета.
--
-- v14.3: клон ХОДИТ С АНИМАЦИЕЙ. Заякорен только HumanoidRootPart (его
-- двигает PivotTo), остальные части держатся суставами — поэтому
-- Animator может шевелить руками и ногами. Анимации ходьбы/стойки берём из
-- штатного Animate-скрипта персонажа (у каждого игрока свои), до того как
-- скрипт удалён.
local function buildActorClone(character)
	if not character then return nil end
	local wasArchivable = character.Archivable
	character.Archivable = true -- персонажи по умолчанию не клонируются
	local ok, clone = pcall(function() return character:Clone() end)
	character.Archivable = wasArchivable
	if not ok or not clone then return nil end

	local animate = clone:FindFirstChild("Animate")
	local function animId(folderName)
		local folder = animate and animate:FindFirstChild(folderName)
		local anim = folder and folder:FindFirstChildWhichIsA("Animation")
		return anim and anim.AnimationId or nil
	end
	local walkId, idleId = animId("walk"), animId("idle")

	local root = clone:FindFirstChild("HumanoidRootPart")
	for _, d in clone:GetDescendants() do
		if d:IsA("BaseScript") then
			-- Скрипты персонажа (Animate и прочее) в дублёре не нужны и
			-- только мешают: он двигается PivotTo, а не физикой.
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = (d == root) or root == nil
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		pcall(function() humanoid.EvaluateStateMachine = false end)
		local cfg = Config.MineExpedition
		local override = humanoid.RigType == Enum.HumanoidRigType.R15 and cfg.ActorWalkAnimationR15 or cfg.ActorWalkAnimationR6
		if tonumber(override) and override ~= 0 then walkId = "rbxassetid://" .. tostring(override) end
		clone:SetAttribute("_WalkAnim", walkId or "")
		clone:SetAttribute("_IdleAnim", idleId or "")
	end
	clone.Name = "MineActor"
	clone.Parent = workspace
	return clone
end

-- Проиграть анимацию по id на модели с Humanoid/AnimationController.
-- Возвращает трек (или nil). Ошибки глушим — это чистый визуал.
local function playAnim(model, animationId, looped)
	if not (model and model.Parent) or typeof(animationId) ~= "string" or animationId == "" then return nil end
	local ok, track = pcall(function()
		local host = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChildOfClass("AnimationController")
		if not host then return nil end
		local animator = host:FindFirstChildOfClass("Animator") or Instance.new("Animator", host)
		local anim = Instance.new("Animation")
		anim.AnimationId = animationId
		local loaded = animator:LoadAnimation(anim)
		loaded.Looped = looped ~= false
		loaded:Play(0.15)
		return loaded
	end)
	return ok and track or nil
end

-- v14.3: ИДТИ ПО ТОЧКАМ. Модель едет по ломаной с постоянной скоростью и
-- плавно доворачивается по ходу движения (на поворотах не «щёлкает»).
-- Высота держится той, с которой модель стартовала: точки-маркеры могут
-- висеть на любой высоте, а ходят все по полу участка.
-- yawOffset — поправка «где у модели перёд» (для шахтёра — FacingPoint).
-- Возвращает время пути в секундах; onArrive зовётся по прибытии.
local function walkPath(model, points, yawOffset, onArrive)
	local cfg = Config.MineExpedition
	if not (model and model.Parent) or #points == 0 then
		if onArrive then task.defer(onArrive) end
		return 0
	end
	local speed = math.max(1, cfg.ActorWalkSpeed or 9)
	local turnSpeed = cfg.ActorTurnSpeed or 10
	local start = model:GetPivot()
	local y = start.Position.Y
	local path = { start.Position }
	for _, point in points do
		table.insert(path, Vector3.new(point.X, y, point.Z))
	end
	local lengths, total = {}, 0
	for i = 2, #path do
		lengths[i] = (path[i] - path[i - 1]).Magnitude
		total += lengths[i]
	end
	local token = HttpService:GenerateGUID(false)
	model:SetAttribute("_MoveToken", token)
	task.spawn(function()
		local travelled = 0
		local rotation = start.Rotation
		local last = os.clock()
		while true do
			RunService.Heartbeat:Wait()
			if model:GetAttribute("_MoveToken") ~= token or not model.Parent then return end
			local now = os.clock()
			local dt = math.min(now - last, 0.1)
			last = now
			travelled = math.min(total, travelled + speed * dt)
			-- Где мы на ломаной.
			local walked, position, heading = 0, path[#path], nil
			for i = 2, #path do
				local segment = lengths[i]
				if travelled <= walked + segment or i == #path then
					local alpha = segment > 0 and math.clamp((travelled - walked) / segment, 0, 1) or 1
					position = path[i - 1]:Lerp(path[i], alpha)
					local dir = (path[i] - path[i - 1]) * Vector3.new(1, 0, 1)
					heading = dir.Magnitude > 0.05 and dir.Unit or nil
					break
				end
				walked += segment
			end
			if heading then
				local target = CFrame.lookAt(Vector3.zero, heading) * CFrame.Angles(0, yawOffset or 0, 0)
				rotation = rotation:Lerp(target.Rotation, math.min(1, dt * turnSpeed))
			end
			model:PivotTo(CFrame.new(position) * rotation)
			if travelled >= total then break end
		end
		if onArrive then onArrive() end
	end)
	return total / speed
end

local pendingFillLoops = {} -- [player] = thread, см. StartLoop
local dialogRemote, startRemote, stateRemote, arcHitRemote
local groundOreFolder -- workspace.MineGroundOre — тот же контракт читает CartService (подбор наездом)

local WATCHDOG_TIMEOUT = 60 -- сек — с запасом больше самой долгой экспедиции, страховка от заглохшего промпта

--------------------------------------------------------------------------------
-- НПС: постановка/переезд/watchdog. Дословно тот же приём, что и в
-- ShopNpcService.lua (см. подробные комментарии там) — самодостаточная
-- копия, не общий модуль, чтобы каждый NPC-сервис оставался независимым.
--------------------------------------------------------------------------------
local function stabilizeNpc(npc, groundY, isCustom)
	if not isCustom then
		for _, descendant in npc:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
			end
		end
	end
	local cf, size = npc:GetBoundingBox()
	local bottomY = cf.Position.Y - size.Y / 2
	local correction = groundY - bottomY
	if math.abs(correction) > 1e-3 then
		npc:PivotTo(npc:GetPivot() + Vector3.new(0, correction, 0))
	end
end

local function facingCorrection(npc, primaryPart)
	local facingPoint = npc:FindFirstChild("FacingPoint", true)
	if not (facingPoint and facingPoint:IsA("BasePart")) then
		return 0
	end
	local localOffset = primaryPart.CFrame:PointToObjectSpace(facingPoint.Position)
	return -math.atan2(localOffset.X, localOffset.Z)
end

function MineService:RepositionNpc(player, plot)
	local record = npcRecords[player]
	if not record or not record.Npc or not record.Npc.Parent or not plot.MinerCFrame then
		return
	end
	local primaryPart = record.Npc.PrimaryPart
	if not primaryPart then return end
	local correction = facingCorrection(record.Npc, primaryPart)
	record.Npc:PivotTo(plot.MinerCFrame * CFrame.Angles(0, correction, 0))
	stabilizeNpc(record.Npc, plot.Pad.Position.Y + plot.Pad.Size.Y / 2, record.IsCustom)
end

function MineService:SetupPlot(player, plot)
	if not plot.MinerCFrame then
		return -- нет шахты/маркера ещё — участок в процессе постройки
	end
	local npc, isCustom = PlaceholderFactory.MinerNPC()
	local primaryPart = npc.PrimaryPart
	if not primaryPart then
		warn("[MineService] У MinerNPC нет PrimaryPart - позиционирование невозможно, НПС не поставлен.")
		npc:Destroy()
		return
	end
	local correction = facingCorrection(npc, primaryPart)
	npc:PivotTo(plot.MinerCFrame * CFrame.Angles(0, correction, 0))
	npc.Parent = plot.Content
	stabilizeNpc(npc, plot.Pad.Position.Y + plot.Pad.Size.Y / 2, isCustom)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = ""
	prompt.ActionText = "DIG"
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 10
	prompt.Style = Enum.ProximityPromptStyle.Custom -- свой вид рисует src/client — НЕ дефолтный серый Roblox
	prompt:SetAttribute("PromptKind", "Talk")
	prompt:SetAttribute("OwnerUserId", player.UserId)
	prompt.Parent = primaryPart

	npcRecords[player] = { Npc = npc, Prompt = prompt, IsCustom = isCustom, WatchdogToken = 0 }

	prompt.Triggered:Connect(function(triggerer)
		if triggerer ~= player then return end -- открывает диалог только владелец участка
		if expeditions[player] then return end -- уже в экспедиции — повторный клик игнорируем
		prompt.Enabled = false
		-- v14.3: диалог в стиле Grow a Garden висит справа от шахтёра —
		-- клиенту нужна сама модель и пара строк о шахте.
		local okTier, tiers = pcall(function() return Services.DataService:GetTiers(player) end)
		local tier = okTier and tiers and tiers.Mine or 1
		local tierInfo = Config.MineTiers[math.clamp(tier, 1, #Config.MineTiers)]
		local current = npcRecords[player]
		dialogRemote:FireClient(player, "Open", {
			Npc = current and current.Npc,
			Tier = tier,
			Yield = tierInfo and tierInfo.OreYield or 0,
			Rarity = Config.AverageRarityForTier(tier, 0),
			Blocked = Services.TutorialService and not Services.TutorialService:IsMineRepaired(player) or false,
		})
		local record = npcRecords[player]
		record.WatchdogToken += 1
		local myToken = record.WatchdogToken
		task.delay(WATCHDOG_TIMEOUT, function()
			local current = npcRecords[player]
			if current and current.WatchdogToken == myToken and current.Prompt and not expeditions[player] then
				current.Prompt.Enabled = true
			end
		end)
	end)

	player.CharacterAdded:Connect(function()
		local record = npcRecords[player]
		if record and record.Prompt and not expeditions[player] then
			record.WatchdogToken = (record.WatchdogToken or 0) + 1
			record.Prompt.Enabled = true
		end
	end)
end

-- Аварийное сворачивание катсцены. Вызывается со всех путей обрыва
-- (выход игрока, StopLoop, CleanupPlayer): без этого оборванная катсцена
-- оставила бы человека НЕВИДИМЫМ и обездвиженным, а его клон — стоять в
-- шахте навсегда. Ошибки глушим: это путь очистки, он обязан доработать
-- до конца, даже если половина ссылок уже мертва.
function MineService:_abortCutscene(player)
	local expedition = expeditions[player]
	if expedition then
		-- Вход обязан вернуться даже при обрыве, иначе шахта навсегда
		-- останется с подменённым мешем.
		pcall(function() self:_snapMineToBase(expedition.Plot) end)
		pcall(function() self:_restoreEntryMesh(expedition.Plot) end)
		-- Руда, успевшая вылететь до обрыва, осталась бы увеличенной и с
		-- CutsceneScaled навсегда — а такую подбор пропускает. Даём
		-- долететь уже запущенным кускам и сажаем всё к обычному размеру.
		local abortedFor = player
		task.delay((Config.MineExpedition.EjectFlightSeconds or 0.85) + 0.6, function()
			pcall(function() self:_shrinkGroundOre(abortedFor) end)
		end)
		pcall(function() self:_restoreControl(player, expedition) end)
	end
	local record = npcRecords[player]
	if record and record.Npc then
		pcall(function() setModelVisible(record.Npc, true) end)
		-- v14.3: шахтёр мог остаться посреди пути в шахту — возвращаем на место.
		if expedition and expedition.Plot then
			pcall(function()
				record.Npc:SetAttribute("_MoveToken", nil)
				self:RepositionNpc(player, expedition.Plot)
			end)
		end
	end
end

function MineService:CleanupPlayer(player)
	-- Страховка: если экспедиция оборвалась не через _finishExpedition
	-- (вылет, смерть, перезаход), флаг остался бы поднятым — и обучение
	-- молчало бы до конца сессии.
	player:SetAttribute("MineExpeditionActive", false)
	self:_abortCutscene(player)
	npcRecords[player] = nil -- сам инстанс уничтожает PlotService вместе с участком
	expeditions[player] = nil
end

--------------------------------------------------------------------------------
-- ИНИЦИАЛИЗАЦИЯ / RemoteEvent'ы
--------------------------------------------------------------------------------
function MineService:Init(services)
	Services = services

	dialogRemote = Instance.new("RemoteEvent")
	dialogRemote.Name = "MineDialogRequest"
	dialogRemote.Parent = ReplicatedStorage.Shared

	startRemote = Instance.new("RemoteEvent")
	startRemote.Name = "MineExpeditionStart"
	startRemote.Parent = ReplicatedStorage.Shared

	stateRemote = Instance.new("RemoteEvent")
	stateRemote.Name = "MineExpeditionState"
	stateRemote.Parent = ReplicatedStorage.Shared

	arcHitRemote = Instance.new("RemoteEvent")
	arcHitRemote.Name = "MineArcHit"
	arcHitRemote.Parent = ReplicatedStorage.Shared

	groundOreFolder = workspace:FindFirstChild("MineGroundOre")
	if not groundOreFolder then
		groundOreFolder = Instance.new("Folder")
		groundOreFolder.Name = "MineGroundOre"
		groundOreFolder.Parent = workspace
	end

	dialogRemote.OnServerEvent:Connect(function(player, action)
		if action == "Close" then
			local record = npcRecords[player]
			if record and record.Prompt and not expeditions[player] then
				record.Prompt.Enabled = true
				record.WatchdogToken = (record.WatchdogToken or 0) + 1
			end
		end
	end)

	startRemote.OnServerEvent:Connect(function(player)
		local ok, err = pcall(function() self:_beginExpedition(player) end)
		if not ok then warn("[MineService] _beginExpedition failed:", err) end
	end)

	arcHitRemote.OnServerEvent:Connect(function(player, token, clientElapsed)
		if typeof(token) ~= "string" then return end
		if typeof(clientElapsed) ~= "number" or clientElapsed ~= clientElapsed then
			clientElapsed = nil -- NaN/мусор — считаем по серверному времени
		end
		local ok, err = pcall(function() self:_onArcHit(player, token, clientElapsed) end)
		if not ok then warn("[MineService] _onArcHit failed:", err) end
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:CleanupPlayer(player)
	end)

	-- КРУТЯТСЯ НА МЕСТЕ, ПОКА ЛЕЖАТ (по прямому запросу — "надо сделать
	-- чтобы они крутились на месте когда выпали"). Один общий Heartbeat на
	-- всю папку — дешевле, чем отдельная корутина на каждый камень, и не
	-- требует ничего от CartService (тот просто подбирает уже готовый
	-- CFrame, вращение не мешает подбору по расстоянию). Останавливается
	-- само — как только кусок подобрали (CartService:AddCrystal меняет
	-- Parent/сваривает его к тележке), Landed-родитель уже не тот, цикл
	-- просто пропускает его на следующий же кадр.
	RunService.Heartbeat:Connect(function(dt)
		if not groundOreFolder then return end
		for _, crystal in groundOreFolder:GetChildren() do
			if crystal:GetAttribute("Landed") == true then
				local ok, root = pcall(CrystalUtil.GetRoot, crystal)
				if ok and root and root.Parent then
					local cfg = Config.MineExpedition
					local direction = crystal:GetAttribute("SpinAxis") or 1
					local speed = cfg.EjectSpinAfterLanding or 1.6

					-- ОДИН ПИСАТЕЛЬ НА ОДИН CFrame.
					--
					-- Руду "колбасило" именно потому, что в root.CFrame писали
					-- ДВА кода: этот цикл вращения и отдельная корутина
					-- левитации. Каждый кадр они по очереди затирали результат
					-- друг друга — кусок дёргался вверх-вниз и выглядел как
					-- лагающий. Теперь высота считается ЗДЕСЬ ЖЕ, и писатель
					-- остался ровно один.
					local spun = root.CFrame * CFrame.Angles(0, direction * speed * dt, 0)
					local groundY = crystal:GetAttribute("HoverGroundY")
					if groundY then
						local phase = (crystal:GetAttribute("HoverPhase") or 0) + dt
						crystal:SetAttribute("HoverPhase", phase)
						local bob = math.sin(phase / (cfg.OreHoverBobSeconds or 2.2) * math.pi * 2)
						local height = (cfg.OreHoverHeight or 1.6) + bob * (cfg.OreHoverBob or 0.35)
						spun = CFrame.new(spun.X, groundY + height, spun.Z) * spun.Rotation
					end
					root.CFrame = spun
				end
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- ШАГ 1→2: НАЧАЛО ЭКСПЕДИЦИИ
--------------------------------------------------------------------------------
-- По прямому запросу — можно отправляться в шахту даже с полной или
-- непустой тележкой (раньше требовалось свободное место). Ёмкость по-
-- прежнему проверяется ТАМ, где она реально важна — на подборе руды с
-- земли (см. новый Heartbeat-подборщик в CartService.lua): если тележка
-- полна, руда просто останется лежать на земле, ничего не потеряется и
-- не сломается.
local function findCartForExpedition(player)
	local cart = Services.CartService:GetHeldCart(player) or Services.CartService:GetOwnedCart(player)
	return cart
end

--------------------------------------------------------------------------------
-- МАРКЕРЫ КАМЕРЫ (по прямому запросу — "камера летает не так, как хочет
-- сейчас, а я буду спавнить маркеры с направлением куда она должна
-- смотреть при каждой ситуации"). См. подробный комментарий у их сбора в
-- PlotService:_buildMine (пары частей CameraMarkerN/CameraMarkerNLook
-- внутри модели шахты). Тут — только отдаёт клиенту готовые Position/
-- LookAt под нужную стадию, если билдер их расставил; если нет — nil, и
-- клиент сам решает, что делать (см. MineExpeditionUI.client.lua — там
-- оставлен старый расчётный долли как запасной вариант, чтобы шахты без
-- маркеров не остались без камеры вовсе).
--------------------------------------------------------------------------------
local function cameraMarkerFor(plot, stageName)
	local index = Config.MineExpedition.CameraMarkerForStage[stageName]
	return index and plot.CameraMarkers and plot.CameraMarkers[index]
end

function MineService:_moveNpc(player, targetCFrame, seconds)
	local record = npcRecords[player]
	if not record or not record.Npc or not record.Npc.Parent then return end
	local npc = record.Npc

	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if humanoid and tonumber(Config.MineExpedition.WalkAnimationId) and Config.MineExpedition.WalkAnimationId ~= 0 then
		local ok, track = pcall(function()
			local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
			local anim = Instance.new("Animation")
			anim.AnimationId = "rbxassetid://" .. tostring(Config.MineExpedition.WalkAnimationId)
			local loaded = animator:LoadAnimation(anim)
			loaded:Play()
			return loaded
		end)
		if ok and track then
			task.delay(seconds, function() pcall(function() track:Stop(0.2) end) end)
		end
	end

	-- Двигаем pivot вручную (Lerp по кадрам), а не Humanoid:MoveTo —
	-- плейсхолдер без Humanoid всё равно должен уметь "идти", а с
	-- настоящим ассетом это просто плавное перемещение под анимацию выше.
	-- Тот же moveModel, что водит и клона игрока.
	moveModel(npc, targetCFrame, seconds)
end

function MineService:_freezeAndGlide(player, targetCFrame, seconds)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and rootPart) then return end
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.AutoRotate = false

	local startCFrame = rootPart.CFrame
	local token = HttpService:GenerateGUID(false)
	player:SetAttribute("_MineGlideToken", token)
	local steps = math.max(6, math.floor(seconds * 30))
	task.spawn(function()
		for i = 1, steps do
			if player:GetAttribute("_MineGlideToken") ~= token or not rootPart.Parent then return end
			rootPart.CFrame = startCFrame:Lerp(targetCFrame, i / steps)
			task.wait(seconds / steps)
		end
	end)
end

function MineService:_restoreControl(player, expedition)
	local character = player.Character
	-- Снимаем невидимость и ставим персонажа точно в точку разговора. Он
	-- и так с неё не уходил, но за время катсцены его могло сдвинуть
	-- чем-то посторонним (толчок, платформа, респавн), а по ТЗ игрок
	-- обязан оказаться ровно там, где нажал на кнопку разговора.
	if character then
		setModelVisible(character, true)
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and expedition and expedition.OriginCFrame then
			root.CFrame = expedition.OriginCFrame
		end
	end
	-- Дублёр мог уцелеть, если катсцену оборвали на середине.
	if expedition and expedition.Actor then
		expedition.Actor:Destroy()
		expedition.Actor = nil
	end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = expedition.OriginWalkSpeed or 16
		humanoid.JumpPower = 50
		humanoid.AutoRotate = true
	end
	player:SetAttribute("_MineGlideToken", nil)
end

function MineService:_beginExpedition(player)
	if expeditions[player] then return end
	local record = npcRecords[player]
	if not record then return end
	local plot = Services.PlotService:GetPlot(player)
	if not plot or not plot.MineEntryCFrame then return end

	-- ШАХТА ЕЩЁ НЕ ПОЧИНЕНА (см. Config.Mine.Broken, TutorialService).
	-- Проверка стоит ПЕРЕД всем остальным: пока вход завален, внутрь не
	-- ведёт ни один путь — ни через диалог, ни через подделанный ремоут.
	if Services.TutorialService and not Services.TutorialService:IsMineRepaired(player) then
		if Services.NotifyService then
			Services.NotifyService:Show(player, "THE MINE IS BLOCKED - CLEAR THE RUBBLE FIRST", { Duration = 2.5 })
		end
		dialogRemote:FireClient(player, "Close")
		if record.Prompt then record.Prompt.Enabled = true end
		return
	end

	-- ТЕЛЕЖКА БОЛЬШЕ НЕ ОБЯЗАТЕЛЬНА.
	--
	-- Раньше её отсутствие полностью блокировало экспедицию — а по новому
	-- порядку обучения игрок чинит шахту и идёт копать ДО того, как
	-- получит первую тележку (см. Config.Tutorial.Steps: FirstExpedition
	-- стоит перед GetCart). Логика выброса руды к тележке и не привязана:
	-- руда падает на землю (см. _ejectOre), а оттуда её одинаково можно
	-- поднять ногами в рюкзак или собрать наездом тележки. Единственное,
	-- что делает cart, — принимает жеоды; там он уже проверен на nil.
	local cart = findCartForExpedition(player)

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and rootPart) then return end

	local tier = Services.DataService:GetTiers(player).Mine

	local expedition = {
		Token = HttpService:GenerateGUID(false),
		Plot = plot,
		Cart = cart,
		Tier = tier,
		Hits = 0,
		OriginCFrame = rootPart.CFrame,
		OriginWalkSpeed = humanoid.WalkSpeed,
	}
	expeditions[player] = expedition
	-- Флаг для клиентского UI: пока он поднят, обучение прячет своё окно и
	-- стрелку (см. TutorialUI.client.lua). Игрок внутри мини-игры со своей
	-- камерой, и указатель "иди в шахту" там указывал бы на место, где он
	-- уже стоит, поверх прицела.
	player:SetAttribute("MineExpeditionActive", true)

	dialogRemote:FireClient(player, "Close")
	if record.Prompt then record.Prompt.Enabled = false end

	local cfg = Config.MineExpedition

	-- 1) ДУБЛЁР. Снимаем клон с живого персонажа ДО того, как спрятать
	--    оригинал: иначе клон унаследовал бы невидимость.
	expedition.Actor = buildActorClone(character)
	if expedition.Actor then
		expedition.Actor:PivotTo(expedition.OriginCFrame)
	end

	-- 2) Настоящий игрок замирает НА МЕСТЕ и становится невидимым. Он
	--    никуда не идёт — значит, и возвращать его потом не придётся:
	--    по окончании катсцены он стоит ровно там, где нажал на разговор.
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.AutoRotate = false
	setModelVisible(character, false)

	-- 3) Камера СРАЗУ встаёт на верхнюю точку мини-игры. Залёта внутрь
	--    шахты больше нет — оттуда и показываем, как туда заходят.
	-- МОДИФИКАТОР ЗАХОДА (вариант 4) — один на весь заход, клиент
	-- показывает его карточкой сразу, пока шахтёр и дублёр заходят внутрь.
	expedition.Modifier = pickVeinModifier()
	-- v14.3: у режима может быть своё число ударов (FRENZY — 5).
	expedition.HitsRequired = (expedition.Modifier and expedition.Modifier.Hits) or cfg.HitsRequired
	expedition.Momentum = 0

	stateRemote:FireClient(player, "Minigame", {
		EntryCFrame = plot.MineEntryCFrame,
		CameraMarker = cameraMarkerFor(plot, "Minigame"),
		MinePosition = minePosition(plot),
		BankPosition = axisTarget(plot),
		FOV = cfg.CameraFOVMinigame,
		Modifier = publicModifier(expedition.Modifier),
	})

	-- ВХОД ЗДЕСЬ НЕ МЕНЯЕТСЯ (по прямому запросу — "меняться энтри должен
	-- только после того, как игрок пройдёт мини-игру"). Подмена делается
	-- один раз, в начале _ejectOre, по уже накопленной за мини-игру удаче.

	-- 4) v14.3: ЗАХОД ПО ТОЧКАМ. Оба постояли → шахтёр ведёт по пути
	--    (отошли, направо, прошли, направо, внутрь), клон идёт следом на
	--    ActorFollowGap. Дошёл до входа — «скрылся внутри».
	local idle = cfg.ActorIdleSeconds or 0.9
	local points = self:_minePath(plot)
	local speed = math.max(1, cfg.ActorWalkSpeed or 9)
	local followDelay = (cfg.ActorFollowGap or 3.2) / speed

	if expedition.Actor then
		expedition.ActorIdleTrack = playAnim(expedition.Actor, expedition.Actor:GetAttribute("_IdleAnim"), true)
	end

	local npcSeconds, actorSeconds = 0, 0
	local npcRecord = npcRecords[player]
	local npc = npcRecord and npcRecord.Npc
	if npc and npc.PrimaryPart then
		local startPos = npc:GetPivot().Position
		local total = 0
		local prev = startPos
		for _, point in points do
			total += ((point - prev) * Vector3.new(1, 0, 1)).Magnitude
			prev = point
		end
		npcSeconds = total / speed
	end
	if expedition.Actor then
		local total = 0
		local prev = expedition.Actor:GetPivot().Position
		for _, point in points do
			total += ((point - prev) * Vector3.new(1, 0, 1)).Magnitude
			prev = point
		end
		actorSeconds = total / speed
	end

	task.delay(idle, function()
		if expeditions[player] ~= expedition then return end
		local record = npcRecords[player]
		if not (record and record.Npc and record.Npc.PrimaryPart) then return end
		local walkTrack = nil
		if tonumber(cfg.WalkAnimationId) and cfg.WalkAnimationId ~= 0 then
			walkTrack = playAnim(record.Npc, "rbxassetid://" .. tostring(cfg.WalkAnimationId), true)
		end
		walkPath(record.Npc, points, facingCorrection(record.Npc, record.Npc.PrimaryPart), function()
			if walkTrack then pcall(function() walkTrack:Stop(0.1) end) end
			if expeditions[player] == expedition then setModelVisible(record.Npc, false) end
		end)
	end)

	task.delay(idle + followDelay, function()
		if expeditions[player] ~= expedition or not expedition.Actor then return end
		local actor = expedition.Actor
		if expedition.ActorIdleTrack then pcall(function() expedition.ActorIdleTrack:Stop(0.15) end) end
		local walkTrack = playAnim(actor, actor:GetAttribute("_WalkAnim"), true)
		walkPath(actor, points, 0, function()
			if walkTrack then pcall(function() walkTrack:Stop(0.1) end) end
			setModelVisible(actor, false)
		end)
	end)

	-- Мини-игра начинается, когда ОБА уже внутри.
	local insideAt = idle + math.max(npcSeconds, followDelay + actorSeconds) + 0.15
	task.delay(insideAt, function()
		if expeditions[player] ~= expedition then return end
		self:_startArcRound(player, expedition, 1)
	end)
end

-- v14.3: ТОЧКИ ПУТИ В ШАХТУ. MinePath1, MinePath2, … внутри модели шахты —
-- по порядку номеров; последней точкой всегда идёт сам вход (ENTRY).
-- Нет ни одной — путь считается сам: вперёд от шахты → направо → к точке
-- перед входом → внутрь (числа — Config.MineExpedition.PathAuto*).
function MineService:_minePath(plot)
	local cfg = Config.MineExpedition
	local points = {}
	local mine = plot.MineModel
	if mine then
		for index = 1, 30 do
			local marker = mine:FindFirstChild("MinePath" .. index, true)
			if not marker then break end
			if marker:IsA("BasePart") then
				marker.Transparency = 1
				marker.CanCollide = false
				marker.CanQuery = false
				table.insert(points, marker.Position)
			end
		end
	end
	local entry = plot.MineEntryCFrame.Position
	if #points == 0 then
		local forward = plot.MineFacingDir
		if not forward and mine then
			local look = mine:GetPivot().LookVector * Vector3.new(1, 0, 1)
			forward = look.Magnitude > 0.1 and look.Unit or nil
		end
		forward = forward or Vector3.zAxis
		local right = forward:Cross(Vector3.yAxis).Unit
		local from = plot.MinerCFrame and plot.MinerCFrame.Position or entry
		local p1 = from + forward * (cfg.PathAutoForward or 7)
		local p2 = p1 + right * (cfg.PathAutoSide or 7)
		local p3 = entry + forward * (cfg.PathAutoApproach or 5)
		points = { p1, p2, p3 }
	end
	table.insert(points, entry)
	return points
end

--------------------------------------------------------------------------------
-- ШАГ 3: МИНИ-ИГРА "РУДНАЯ ЖИЛА" (вариант A)
--
-- Кирка бегает по жиле туда-обратно. На жиле — кристальные зоны (GOOD) и
-- самородок внутри одной из них (PERFECT). Всё остальное — порода: удар
-- туда засчитывается как MISS и удачи не даёт вообще (по прямому запросу).
-- Раскладка своя на каждом ударе (Config.MineExpedition.VeinRounds —
-- "вариант 1"), модификатор захода (Modifiers — "вариант 4") её меняет.
--------------------------------------------------------------------------------

-- Выбор модификатора захода по весам; nil — обычный заход.
pickVeinModifier = function()
	local cfg = Config.MineExpedition
	local list = cfg.Modifiers
	if not list or #list == 0 or math.random() > (cfg.ModifierChance or 0) then
		return nil
	end
	local total = 0
	for _, modifier in list do total += modifier.Weight or 1 end
	local roll = math.random() * total
	for _, modifier in list do
		roll -= modifier.Weight or 1
		if roll <= 0 then return modifier end
	end
	return list[#list]
end

-- То, что уходит клиенту: только подпись и цвет, без чисел баланса.
publicModifier = function(modifier)
	if not modifier then return nil end
	return {
		Id = modifier.Id,
		Title = modifier.Title,
		Subtitle = modifier.Subtitle,
		Color = modifier.Color,
		Dual = modifier.Dual == true,
		GhostSeconds = modifier.GhostSeconds,
	}
end

-- Раскладка одного удара. Кристальные зоны ставятся в случайные места без
-- наложений (с зазором), самородок — внутри одной случайной из них.
local function buildVeinZones(roundIndex, modifier)
	local cfg = Config.MineExpedition
	local rounds = cfg.VeinRounds
	local round = rounds[math.clamp(roundIndex, 1, #rounds)]
	local goodMul = (modifier and modifier.GoodMul) or 1
	local perfectMul = (modifier and modifier.PerfectMul) or 1
	local colors = cfg.VeinColors
	local margin = cfg.VeinEdgeMargin or 0.04

	-- v14.3 JACKPOT: только один крошечный самородок, кристальных зон нет.
	if modifier and modifier.Jackpot then
		local width = modifier.JackpotWidth or 0.055
		local start = margin + math.random() * (1 - margin * 2 - width)
		return { { Kind = "Perfect", Start = start, Finish = start + width, Color = colors.Perfect } }, round
	end

	local widths = {}
	for _, width in round.Good do
		table.insert(widths, width * goodMul)
	end
	for _ = 1, (modifier and modifier.ExtraGood) or 0 do
		table.insert(widths, round.Good[#round.Good] * goodMul)
	end

	-- Если зоны суммарно не влезают — ужимаем все пропорционально.
	local gap = 0.04
	local usable = 1 - margin * 2
	local need = gap * (#widths - 1)
	for _, width in widths do need += width end
	if need > usable then
		local shrink = (usable - gap * (#widths - 1)) / (need - gap * (#widths - 1))
		for i, width in widths do widths[i] = width * shrink end
		need = usable
	end

	-- Случайно раскидываем свободное место между зонами: разбиваем "лишнее"
	-- пространство на (#widths + 1) случайных кусков.
	local free = usable - need
	local cuts = {}
	for i = 1, #widths + 1 do cuts[i] = math.random() end
	local cutSum = 0
	for _, cut in cuts do cutSum += cut end

	local zones = {}
	local cursor = margin
	local goodZones = {}
	for i, width in widths do
		cursor += free * (cuts[i] / cutSum)
		local zone = {
			Kind = "Good",
			Start = cursor,
			Finish = cursor + width,
			Color = colors.Good,
		}
		table.insert(zones, zone)
		table.insert(goodZones, zone)
		cursor += width + gap
	end

	-- Самородок — внутри одной кристальной зоны, не впритык к её краям.
	local host = goodZones[math.random(1, #goodZones)]
	local hostWidth = host.Finish - host.Start
	local perfectWidth = math.min(round.Perfect * perfectMul, hostWidth * 0.6)
	local slack = hostWidth - perfectWidth
	local offset = slack * (0.2 + math.random() * 0.6)
	table.insert(zones, {
		Kind = "Perfect",
		Start = host.Start + offset,
		Finish = host.Start + offset + perfectWidth,
		Color = colors.Perfect,
	})
	return zones, round
end

function MineService:_runArcMinigame(player, expedition)
	if expeditions[player] ~= expedition then return end
	-- РАЗГОВОР С ШАХТЁРОМ: камера отходит от шахты в сторону банка, вверх,
	-- и смотрит на шахту сверху. Дальше начинается мини-игра — план не
	-- меняется, только FOV подъезжает с каждым кликом.
	stateRemote:FireClient(player, "Minigame", {
		EntryCFrame = expedition.Plot.MineEntryCFrame,
		CameraMarker = cameraMarkerFor(expedition.Plot, "Minigame"),
		MinePosition = minePosition(expedition.Plot),
		BankPosition = axisTarget(expedition.Plot),
		FOV = Config.MineExpedition.CameraFOVMinigame,
	})
	self:_startArcRound(player, expedition, 1)
end

function MineService:_startArcRound(player, expedition, roundIndex)
	if expeditions[player] ~= expedition then return end
	local cfg = Config.MineExpedition
	local modifier = expedition.Modifier
	local zones, round = buildVeinZones(roundIndex, modifier)
	local sweep = cfg.SweepSeconds * ((modifier and modifier.SweepMul) or 1) / (round.Speed or 1)
	-- v14.3 MOMENTUM: каждый PERFECT подряд ускоряет кирку.
	if modifier and modifier.Momentum and (expedition.Momentum or 0) > 0 then
		sweep *= (modifier.MomentumSpeed or 0.85) ^ expedition.Momentum
	end
	local motion = (modifier and modifier.Motion) or "Linear"
	-- v14.3 REVERSE: случайные моменты разворота кирки.
	local flips = nil
	if modifier and modifier.Reverse then
		local r = modifier.Reverse
		flips = {}
		for _ = 1, r.Count or 2 do
			table.insert(flips, (r.Min or 0.5) + math.random() * ((r.Max or 2.5) - (r.Min or 0.5)))
		end
		table.sort(flips)
	end
	local shrink = modifier and modifier.Shrink or nil
	local dual = modifier and modifier.Dual == true or false
	local token = HttpService:GenerateGUID(false)
	expedition.PendingRound = {
		Token = token,
		RoundIndex = roundIndex,
		Zones = zones,
		StartClock = os.clock(),
		SweepSeconds = sweep,
		Motion = motion,
		Flips = flips,
		Shrink = shrink,
		Dual = dual,
	}
	stateRemote:FireClient(player, "ArcRound", {
		Token = token,
		Zones = zones, -- клиент рисует ИМЕННО эти зоны — увиденное совпадает с тем, что засчитает сервер
		SweepSeconds = sweep,
		Motion = motion,
		Flips = flips,
		Shrink = shrink,
		Dual = dual,
		Momentum = expedition.Momentum or 0,
		RoundIndex = roundIndex,
		HitsRequired = expedition.HitsRequired or cfg.HitsRequired,
		Modifier = publicModifier(modifier),
	})
	-- Не нажал за RoundTimeoutSeconds — выпускаем тот же удар заново.
	task.delay(cfg.RoundTimeoutSeconds, function()
		if expeditions[player] ~= expedition then return end
		local pending = expedition.PendingRound
		if pending and pending.Token == token then
			self:_startArcRound(player, expedition, roundIndex)
		end
	end)
end

-- НАКОПИТЕЛЬНОЕ РАСТЯЖЕНИЕ ШАХТЫ (по прямому запросу — "шахта
-- растягивается при каждом клике"). В отличие от _pulseMineDoor, который
-- пружинит и возвращается, этот масштаб ОСТАЁТСЯ: к третьему попаданию
-- шахта заметно раздута и читается как "сейчас лопнет".
--------------------------------------------------------------------------------
-- ВХОД ШАХТЫ: ПОДМЕНА МЕША ПО СРЕДНЕЙ РЕДКОСТИ
--
-- Модель шахты устроена так: Model → меши внутри, один из которых называется
-- "ENTRY" — это сам вход. На время мини-игры он подменяется на вариант из
-- ReplicatedStorage: entry_common / entry_uncommon / entry_rare / entry_epic /
-- entry_legendary / entry_mythic — по СРЕДНЕЙ редкости выпадения этой шахты
-- (см. Config.AverageRarityForTier). После катсцены возвращается исходный.
--
-- ВАЖНО: оригинал НЕ УНИЧТОЖАЕТСЯ, а убирается в сторону (Parent = nil) и
-- хранится в plot.EntryOriginal. Уничтожить и потом "собрать обратно" было
-- бы нельзя: авторский вход может нести на себе что угодно — декали,
-- партиклы, атрибуты, вложенные детали, — и воссоздать это из кода
-- невозможно. Заменяющий меш клонируется ЦЕЛИКОМ, со всем содержимым.
--------------------------------------------------------------------------------
local ENTRY_PART_NAME = "ENTRY"

-- Ищем вход по имени без учёта регистра: в моделях он встречается и как
-- "ENTRY", и как "Entry".
local function findEntryPart(mine)
	for _, descendant in mine:GetDescendants() do
		if descendant.Name:upper() == ENTRY_PART_NAME and descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function findEntryTemplate(rarity)
	local wanted = ("entry_%s"):format(rarity:lower())
	for _, child in ReplicatedStorage:GetDescendants() do
		-- Folder тоже принимаем: если ассеты сгруппированы простой папкой
		-- (несколько частей + партиклы без общей Model), а не оформлены как
		-- Model — они всё равно не должны отбрасываться поиском.
		if child.Name:lower() == wanted
			and (child:IsA("BasePart") or child:IsA("Model") or child:IsA("Folder")) then
			return child
		end
	end
	return nil
end

function MineService:_applyEntryMesh(plot, rarity)
	local mine = plot.MineModel
	if not mine then return end
	-- Уже подменён — второй раз не трогаем, иначе оригинал потеряется.
	if plot.EntryOriginal then return end

	local entry = findEntryPart(mine)
	if not entry then return end

	local template = findEntryTemplate(rarity)
	if not template then
		-- Нет ассета для этой редкости — оставляем как есть. Молча, потому
		-- что это нормальная ситуация: ассеты добавляются постепенно.
		return
	end

	-- СОХРАНЯЕМ ВСЁ СОДЕРЖИМОЕ ШАБЛОНА (по прямому запросу — партиклы,
	-- вложенные детали и всё остальное внутри entry_common и т.д.).
	--
	-- ПРИЧИНА №1: Instance:Clone() пропускает — молча, без ошибки — любого
	-- потомка с Archivable = false. Это единственный штатный способ в
	-- Roblox, которым часть содержимого клона может просто НЕ ПОЯВИТЬСЯ:
	-- сам шаблон клонируется, а часть его партиклов/деталей — нет. Флаг
	-- мог быть выставлен случайно (например, кем-то через плагин) и
	-- незаметен в Properties при беглом осмотре. Принудительно снимаем его
	-- со всего шаблона ПЕРЕД клонированием — на сам шаблон в
	-- ReplicatedStorage это не влияет, он используется только как
	-- источник для Clone() и никогда не показывается напрямую.
	if template.Archivable == false then template.Archivable = true end
	for _, descendant in template:GetDescendants() do
		if descendant.Archivable == false then descendant.Archivable = true end
	end

	local replacement = template:Clone()
	replacement.Name = ENTRY_PART_NAME .. "_Swapped"

	-- Folder → Model. Folder не умеет ни CFrame, ни PivotTo (у неё просто
	-- нет этих свойств/методов) — заворачиваем её содержимое в Model
	-- ОДИН РАЗ здесь, и дальше по функции Folder как тип вообще не
	-- встречается: весь код ниже уже умеет работать с Model.
	if replacement:IsA("Folder") then
		local wrapper = Instance.new("Model")
		for _, child in replacement:GetChildren() do
			child.Parent = wrapper
		end
		replacement:Destroy()
		replacement = wrapper
		replacement.Name = ENTRY_PART_NAME .. "_Swapped"
	end

	-- МЕШ (BasePart) С ПРИВЕШЕННЫМИ ДЕТАЛЯМИ ВНУТРИ — ТА САМАЯ ПРИЧИНА
	-- "не переносится", по вашему уточнению структуры entry_common.
	--
	-- entry_common — это САМ МЕШ (BasePart), а "Part" внутри него (со всеми
	-- партиклами) — просто РЕБЁНОК в иерархии, БЕЗ физической связи с
	-- мешем. В Roblox родитель-потомок между двумя BasePart НИЧЕГО не
	-- значит для позиции: перемещая CFrame меша (`replacement.CFrame =
	-- entry.CFrame` ниже), Roblox двигает ТОЛЬКО сам меш. "Part" остаётся
	-- ровно там, где он был в ReplicatedStorage, — то есть технически
	-- склонировался, но не переместился вместе с мешем. Только у Model
	-- PivotTo() двигает ВСЮ вложенную геометрию как единое жёсткое тело —
	-- это и есть механизм, который нужен здесь.
	--
	-- Заворачиваем меш (вместе со всем, что на нём висит) в Model и
	-- назначаем ЕЙ PrimaryPart = САМ МЕШ — именно он остаётся точкой
	-- отсчёта ("и на нём всё висит"), а "Part" и его партиклы, будучи
	-- потомками мема ВНУТРИ этой Model, поедут вместе с ним при PivotTo,
	-- сохранив свою позицию ОТНОСИТЕЛЬНО меша в точности такой, какой она
	-- была в ReplicatedStorage.
	if replacement:IsA("BasePart") then
		local hasNestedParts = false
		for _, descendant in replacement:GetDescendants() do
			if descendant:IsA("BasePart") then
				hasNestedParts = true
				break
			end
		end
		if hasNestedParts then
			local wrapper = Instance.new("Model")
			wrapper.Name = replacement.Name
			replacement.Parent = wrapper
			wrapper.PrimaryPart = replacement
			replacement = wrapper
		end
	end

	-- ПРИЧИНА №2: если шаблон — Model БЕЗ назначенного PrimaryPart,
	-- Model:PivotTo() позиционирует его по НЕЯВНОМУ дефолтному пивоту
	-- (центр bounding box, посчитанный Roblox самостоятельно). Внутренняя
	-- геометрия при этом не портится — части и партиклы двигаются как
	-- единое жёсткое тело, — но группа целиком может уехать так, что она
	-- окажется внутри стены шахты или за её пределами: технически всё
	-- склонировалось, но выглядит как "ничего нет". Даём шаблону
	-- ПРЕДСКАЗУЕМЫЙ PrimaryPart перед позиционированием, если автор его не
	-- назначил, — так итоговое место всегда совпадает с тем, что видно в
	-- Studio при выделении шаблона.
	if replacement:IsA("Model") and not replacement.PrimaryPart then
		replacement.PrimaryPart = replacement:FindFirstChildWhichIsA("BasePart", true)
	end

	-- Ставим ТОЧНО в положение старого входа. Для Model — по пивоту, для
	-- детали — по CFrame; иначе вход уехал бы относительно шахты.
	-- v9: ВХОД РЕДКОСТИ — РАЗМЕРОМ НАСТОЯЩЕГО ENTRY. Сравниваем
	-- габариты целиком (GetExtentsSize у модели, Size у детали) по самой
	-- длинной оси и ЗАЖИМАЕМ множитель (EntryScaleMin..Max) — раньше мелкая
	-- вложенная деталь могла дать множитель ×20 и огромный вход закрывал
	-- шахту (ломал мини-игру).
	do
		local want = math.max(entry.Size.X, entry.Size.Y, entry.Size.Z)
		local have = 0
		if replacement:IsA("Model") then
			local okSize, extents = pcall(function() return replacement:GetExtentsSize() end)
			if okSize and extents then have = math.max(extents.X, extents.Y, extents.Z) end
		else
			have = math.max(replacement.Size.X, replacement.Size.Y, replacement.Size.Z)
		end
		local cfgExp = Config.MineExpedition
		local factor = (have > 0.05) and math.clamp(want / have, cfgExp.EntryScaleMin or 0.75, cfgExp.EntryScaleMax or 1.5) or 1
		if math.abs(factor - 1) > 0.01 then
			if replacement:IsA("Model") then
				pcall(function() replacement:ScaleTo(replacement:GetScale() * factor) end)
			else
				replacement.Size = replacement.Size * factor
			end
		end
	end

	if replacement:IsA("Model") then
		replacement:PivotTo(entry.CFrame)
	else
		replacement.CFrame = entry.CFrame
	end
	replacement.Parent = mine

	-- ENTRY — ЦЕНТР ШАХТЫ (см. PlotService: mine.PrimaryPart = entry).
	-- Если PrimaryPart сейчас указывает на СТАРЫЙ вход, а мы через
	-- мгновение уберём его из модели (entry.Parent = nil), PrimaryPart
	-- станет указывать на деталь, которой в модели больше нет —
	-- Model:GetPivot()/ScaleTo() перестанут работать РОВНО на время
	-- катсцены, то есть именно тогда, когда рост/взрыв шахты и нужны
	-- сильнее всего. Переключаем ссылку на замену ДО удаления оригинала.
	local wasPrimaryPart = mine.PrimaryPart == entry
	if wasPrimaryPart then
		-- PrimaryPart обязан быть BasePart. Замена — Model (у неё внутри
		-- меш плюс, возможно, доп. детали) — берём её собственный
		-- PrimaryPart либо первую попавшуюся деталь внутри. Не нашли и
		-- там (совсем пустая Model — по сути сломанный ассет) — берём
		-- ЛЮБУЮ другую деталь шахты, лишь бы PrimaryPart не остался
		-- указывать в пустоту на всё время катсцены.
		local newPrimary = replacement:IsA("BasePart") and replacement
			or replacement:IsA("Model") and (replacement.PrimaryPart or replacement:FindFirstChildWhichIsA("BasePart", true))
			or nil
		if not newPrimary then
			for _, descendant in mine:GetDescendants() do
				if descendant ~= entry and descendant:IsA("BasePart") then
					newPrimary = descendant
					break
				end
			end
		end
		if newPrimary then mine.PrimaryPart = newPrimary end
	end

	-- Оригинал убираем в сторону, НЕ уничтожая (см. комментарий выше).
	plot.EntryOriginal = entry
	plot.EntrySwapped = replacement
	plot.EntryWasPrimaryPart = wasPrimaryPart
	-- Запоминаем, В КАКОЙ ИМЕННО модели случилась подмена: тир шахты
	-- может смениться (апгрейд) прямо во время катсцены, и тогда
	-- plot.MineModel на восстановлении будет указывать уже на ДРУГУЮ,
	-- новую модель — исходный вход в нового владельца пристёгивать
	-- нельзя, он от старой шахты.
	plot.EntrySwapMineModel = mine
	entry.Parent = nil
end

function MineService:_restoreEntryMesh(plot)
	-- Шахта СМЕНИЛАСЬ (апгрейд тира прямо во время катсцены) — вход от
	-- старой модели пристёгивать некуда и незачем, новая уже собрана
	-- заново с собственным авторским входом. Просто уничтожаем осиротевший
	-- оригинал и не трогаем PrimaryPart новой модели вообще.
	local sameMine = plot.MineModel and plot.MineModel == plot.EntrySwapMineModel
	plot.EntrySwapMineModel = nil

	if not sameMine then
		if plot.EntrySwapped and plot.EntrySwapped.Parent then plot.EntrySwapped:Destroy() end
		if plot.EntryOriginal then plot.EntryOriginal:Destroy() end
		plot.EntrySwapped = nil
		plot.EntryOriginal = nil
		plot.EntryWasPrimaryPart = nil
		return
	end

	-- Ссылку возвращаем ДО удаления замены — тот же порядок, что и при
	-- подмене: PrimaryPart не должен ни на кадр остаться указывающим в
	-- пустоту.
	if plot.EntryWasPrimaryPart and plot.EntryOriginal then
		plot.MineModel.PrimaryPart = plot.EntryOriginal
	end
	plot.EntryWasPrimaryPart = nil

	if plot.EntrySwapped then
		if plot.EntrySwapped.Parent then plot.EntrySwapped:Destroy() end
		plot.EntrySwapped = nil
	end
	if plot.EntryOriginal then
		plot.EntryOriginal.Parent = plot.MineModel
		plot.EntryOriginal = nil
	end
end

--------------------------------------------------------------------------------
-- МАСШТАБ ШАХТЫ: ОДИН АНИМАТОР НА МОДЕЛЬ
--
-- Раньше рост при ударах (_stretchMine) и "взрыв" (_burstMine) были ДВУМЯ
-- независимыми корутинами, и каждая сама дёргала mine:ScaleTo в цикле.
-- Стоило им наложиться (последний удар → через 0.25 с взрыв, а рост ещё
-- доигрывает), и два писателя затирали масштаб друг друга каждый кадр —
-- шахта дёргалась, а итоговый размер зависел от того, кто записал
-- последним. Добавить сверху ещё и "плевок" на каждую руду в такой схеме
-- было нельзя в принципе.
--
-- Теперь писатель ровно один: любая новая анимация ОТМЕНЯЕТ предыдущую
-- (токен) и стартует из того масштаба, где шахта реально стоит сейчас,
-- поэтому переходы между ростом, взрывом и плевками всегда непрерывные.
--
-- ОПОРА — ОСНОВАНИЕ ШАХТЫ, А НЕ ВХОД. Model:ScaleTo масштабирует вокруг
-- пивота (это ENTRY, он висит над землёй), и при раздуве нижняя часть
-- шахты уходила под землю, а при сжатии — отрывалась от неё. Здесь после
-- каждого ScaleTo модель сдвигается так, что неподвижной остаётся точка
-- "под входом на уровне низа шахты": по горизонтали шахта растёт от
-- входа (как и раньше), по вертикали — от земли вверх.
--
-- Время считается по os.clock(), а не числом шагов с task.wait(dt/steps):
-- task.wait не бывает короче кадра, и "0.18 с за 8 шагов" на деле длились
-- заметно дольше, отчего тайминги плевков разъезжались с полётом руды.
--------------------------------------------------------------------------------
local mineScaleStates = setmetatable({}, { __mode = "k" }) -- [Model] = { Token, Anchor }

local function mineBaseScale()
	return Config.MineExpedition.MineBaseScale or 1
end

local function getMineScaleState(mine)
	local state = mineScaleStates[mine]
	if not state then
		state = { Token = 0 }
		mineScaleStates[mine] = state
	end
	if not state.Anchor then
		-- Меряем ОДИН раз на модель, в покое (первая анимация всегда
		-- стартует из покоя). Дальше точка неподвижна по построению —
		-- каждый setMineScale сохраняет её на месте.
		local okPivot, pivot = pcall(function() return mine:GetPivot() end)
		local okBox, boxCFrame, boxSize = pcall(function() return mine:GetBoundingBox() end)
		if not (okPivot and okBox and pivot and boxCFrame and boxSize) then
			return nil
		end
		local bottomY = boxCFrame.Position.Y - boxSize.Y / 2
		state.Anchor = Vector3.new(pivot.Position.X, bottomY, pivot.Position.Z)
	end
	return state
end

-- Абсолютный масштаб s с неподвижной опорой. ScaleTo масштабирует вокруг
-- пивота P: x → P + (x − P)·k. После этого сдвигаем модель на
-- (A − P)·(1 − k): в сумме x → A + (x − A)·k — то есть масштаб вокруг A.
-- Формула не зависит от того, куда сейчас указывает PrimaryPart (при
-- подмене входа он меняется), поэтому её можно вызывать в любой момент.
local function setMineScale(mine, state, targetScale)
	local current = mine:GetScale()
	if current <= 0 or math.abs(current - targetScale) < 1e-4 then return end
	local k = targetScale / current
	local pivotBefore = mine:GetPivot().Position
	mine:ScaleTo(targetScale)
	local shift = (state.Anchor - pivotBefore) * (1 - k)
	mine:PivotTo(mine:GetPivot() + shift)
end

local function easeOutQuad(a) return 1 - (1 - a) * (1 - a) end
local function easeInOutQuad(a)
	if a < 0.5 then return 2 * a * a end
	return 1 - ((-2 * a + 2) ^ 2) / 2
end
local function easeOutBack(a)
	local c1, c3 = 1.4, 2.4
	return 1 + c3 * (a - 1) ^ 3 + c1 * (a - 1) ^ 2
end
local MINE_EASES = { OutQuad = easeOutQuad, InOutQuad = easeInOutQuad, OutBack = easeOutBack }
local EASE_NAMES = {}
for name, fn in MINE_EASES do EASE_NAMES[fn] = name end

-- keyframes: { { T = секунды от старта (накопительно), S = абсолютный
-- масштаб, Ease = функция }, ... }. Первый отрезок начинается с ТЕКУЩЕГО
-- масштаба модели. Возвращает токен (для проверки "моя ли ещё анимация").
-- ТРЯСКА. Смещение тряски хранится в state.ShakeOffset и ВСЕГДА снимается
-- перед масштабированием (иначе опорная точка "уехала" бы вместе с ним) и
-- при любой отмене анимации — шахта не может "застрять" сдвинутой.
local function clearMineShake(mine, state)
	local offset = state.ShakeOffset
	if offset then
		state.ShakeOffset = nil
		pcall(function() mine:PivotTo(mine:GetPivot() - offset) end)
	end
end

local function applyMineShake(mine, state, amplitude)
	if amplitude <= 0.001 then return end
	local offset = Vector3.new(
		(math.random() * 2 - 1) * amplitude,
		(math.random() * 2 - 1) * amplitude * 0.35,
		(math.random() * 2 - 1) * amplitude
	)
	state.ShakeOffset = offset
	pcall(function() mine:PivotTo(mine:GetPivot() + offset) end)
end

-- opts (необязательно): { Shake = амплитуда в стадах, ShakeSeconds = длительность }.
-- Тряска затухает линейно и идёт параллельно с масштабом.
-- v20.16: АНИМАЦИЯ ШАХТЫ — НА КЛИЕНТЕ. Раньше сервер каждый кадр делал
-- Model:ScaleTo всей шахты, и размеры/позиции ВСЕХ её деталей улетали по сети
-- каждый кадр — в момент выброса руды (взрыв + плевок на каждый кусок) это
-- давало пролаг как раз во время перелёта камеры. Теперь сервер пишет только
-- атрибут MineScaleAnim (ключи, тряска, серверное время старта), а
-- client/MineScaleFX проигрывает то же самое локально. Геометрия шахты на
-- сервере всё время в базовом масштабе.
local function encodeMineAnim(mine, token, keyframes, opts)
	local keys = {}
	for _, frame in keyframes do
		table.insert(keys, { T = frame.T, S = frame.S, E = EASE_NAMES[frame.Ease] or "OutQuad" })
	end
	local okScale, current = pcall(function() return mine:GetScale() end)
	return HttpService:JSONEncode({
		Seq = token,
		Start = workspace:GetServerTimeNow(),
		Current = okScale and current or mineBaseScale(),
		Keys = keys,
		Shake = opts and opts.Shake or 0,
		ShakeSeconds = opts and opts.ShakeSeconds or 0,
	})
end

function MineService:_animateMineScale(plot, keyframes, opts)
	local mine = plot and plot.MineModel
	if not (mine and mine.Parent) then return nil end
	local state = getMineScaleState(mine)
	if not state then return nil end
	state.Token += 1
	local token = state.Token
	clearMineShake(mine, state)
	if Config.MineExpedition.ClientMineScale ~= false then
		game:GetService("CollectionService"):AddTag(mine, "MineScaleAnimated")
		mine:SetAttribute("MineScaleAnim", encodeMineAnim(mine, token, keyframes, opts))
		return token
	end

	local okScale, startScale = pcall(function() return mine:GetScale() end)
	if not okScale then return nil end

	local shake = opts and opts.Shake or 0
	local shakeSeconds = opts and opts.ShakeSeconds or 0
	local lastT = keyframes[#keyframes] and keyframes[#keyframes].T or 0
	local total = math.max(lastT, shakeSeconds)

	task.spawn(function()
		local startedAt = os.clock()
		local from = startScale
		local prevT = 0
		local index = 1
		while true do
			if state.Token ~= token or not mine.Parent then return end
			local elapsed = os.clock() - startedAt
			clearMineShake(mine, state)

			-- Масштаб по ключам.
			local frame = keyframes[index]
			while frame and elapsed >= frame.T do
				from = frame.S
				prevT = frame.T
				index += 1
				frame = keyframes[index]
			end
			local value
			if frame then
				local span = frame.T - prevT
				local a = span > 0 and math.clamp((elapsed - prevT) / span, 0, 1) or 1
				value = from + (frame.S - from) * (frame.Ease or easeOutQuad)(a)
			else
				value = from
			end
			local ok, err = pcall(setMineScale, mine, state, math.max(0.05, value))
			if not ok then
				warn("[MineService] Mine scale animation failed:", err)
				return
			end

			-- Тряска поверх.
			if shake > 0 and elapsed < shakeSeconds then
				applyMineShake(mine, state, shake * (1 - elapsed / shakeSeconds) * value)
			end

			if elapsed >= total then break end
			RunService.Heartbeat:Wait()
		end
		clearMineShake(mine, state)
	end)
	return token
end

-- Мгновенно (без анимации) вернуть шахту к базовому масштабу и оборвать
-- любую идущую анимацию. Нужен перед подменой/возвратом входа: деталь,
-- добавленная в модель в раздутом состоянии, потом ужалась бы вместе с
-- моделью и навсегда осталась бы меньше положенного (и наоборот).
function MineService:_snapMineToBase(plot)
	local mine = plot and plot.MineModel
	if not (mine and mine.Parent) then return end
	local state = getMineScaleState(mine)
	if not state then return end
	state.Token += 1
	clearMineShake(mine, state)
	pcall(setMineScale, mine, state, mineBaseScale())
	if Config.MineExpedition.ClientMineScale ~= false then
		mine:SetAttribute("MineScaleAnim", HttpService:JSONEncode({ Seq = state.Token, Snap = true }))
	end
end

-- РЕАКЦИЯ ШАХТЫ НА УДАР — своя на каждый результат (по прямому запросу —
-- "при разной редкости разные анимации: тряска, увеличение и т.д.").
-- Рост КОПИТСЯ от удара к удару (к последнему шахта заметно раздута), а
-- поверх него:
--   PERFECT — большой подскок + сильная тряска;
--   GOOD    — обычный подскок + средняя тряска;
--   MISS    — шахта "съёживается" и мелко вздрагивает, потом встаёт в рост.
-- Числа — Config.MineExpedition.MineHitReaction. Каменные осколки из входа
-- рисует клиент (локальные детали — дешевле и плавнее).
function MineService:_stretchMine(plot, hitIndex, quality)
	local cfg = Config.MineExpedition
	local base = mineBaseScale()
	local target = base + (cfg.MineStretchPerHit or 0.09) * hitIndex
	local seconds = cfg.MineStretchSeconds or 0.18
	local reactions = cfg.MineHitReaction or {}
	local reaction = reactions[quality or "Good"] or reactions.Good or {}
	local opts = { Shake = reaction.Shake or 0, ShakeSeconds = reaction.ShakeSeconds or 0 }

	if quality == "Miss" then
		local mine = plot and plot.MineModel
		local okScale, current = pcall(function() return mine:GetScale() end)
		current = okScale and current or base
		local dip = current - base * (reaction.Dip or 0.06)
		self:_animateMineScale(plot, {
			{ T = 0.08, S = dip, Ease = easeOutQuad },
			{ T = 0.08 + seconds * 1.4, S = target, Ease = easeInOutQuad },
		}, opts)
		return
	end

	local overshoot = target + base * (reaction.Overshoot or 0.09)
	local up = quality == "Perfect" and 0.07 or 0.05
	self:_animateMineScale(plot, {
		{ T = up, S = overshoot, Ease = easeOutQuad },
		{ T = up + seconds * (quality == "Perfect" and 1.6 or 1), S = target, Ease = easeOutBack },
	}, opts)
end

-- ШАХТА "ЛОПАЕТСЯ" по завершении мини-игры: резкий раздув выше самого
-- раздутого состояния и упругое оседание обратно к базе.
function MineService:_burstMine(plot)
	local cfg = Config.MineExpedition
	local base = mineBaseScale()
	local burstTarget = base * (cfg.MineBurstScale or 1.5)
	local seconds = cfg.MineBurstSeconds or 0.45
	self:_animateMineScale(plot, {
		{ T = 0.07, S = burstTarget, Ease = easeOutQuad },
		{ T = 0.07 + seconds, S = base, Ease = easeOutBack },
	})
end

-- "ПЛЕВОК" НА КАЖДУЮ РУДУ (по прямому запросу — "шахта должна расширяться
-- после вылета каждой руды, а потом уменьшаться, будто выплёвывает").
--
-- Кривая подогнана под flyOre: руда ~0.12 с "приседает" в двери, и ровно
-- в эти 0.12 с шахта чуть поджимается (набирает воздух); в момент, когда
-- кусок отрывается от двери, шахта резко раздувается — это и есть
-- выплюнула; дальше упругий откат с лёгким недолётом и возврат ровно к
-- базе. Всё от MineBaseScale, поэтому постоянная прибавка +30% не теряется,
-- сколько бы плевков ни было подряд.
function MineService:_spitMine(plot)
	local cfg = Config.MineExpedition
	local base = mineBaseScale()
	local squash = cfg.MineSpitSquash or 0.94
	local peak = cfg.MineSpitScale or 1.2
	local seconds = cfg.MineSpitSeconds or 0.55
	-- Доли общей длительности: поджатие → выплюнула → откат → улеглась.
	self:_animateMineScale(plot, {
		{ T = seconds * 0.22, S = base * squash, Ease = easeInOutQuad },
		{ T = seconds * 0.38, S = base * peak, Ease = easeOutQuad },
		{ T = seconds * 0.78, S = base * (1 - (1 - squash) * 0.5), Ease = easeInOutQuad },
		{ T = seconds, S = base, Ease = easeOutQuad },
	})
end

function MineService:_pulseMineDoor(plot, color)
	-- v9: цветные эффекты внутри шахты выключены (DoorColorFX = false) —
	-- на клик остаются только серые 3D-осколки вокруг всей шахты (клиент).
	if Config.MineExpedition.DoorColorFX ~= true then return end
	local door = plot.MineDoorPart
	if door and door:IsA("BasePart") then
		door.Material = Enum.Material.Neon
		door.Color = color
	end
	-- РАЗДУВ ШАХТЫ ОТСЮДА УБРАН. Раньше этот метод сам делал ScaleTo до
	-- MineBulgeScale и через MineShakeSeconds возвращал масштаб к 1 —
	-- теперь масштабом заведует _stretchMine, который КОПИТ растяжение от
	-- клика к клику. Если бы оба писали в ScaleTo, возврат к 1 отсюда
	-- стирал бы всё накопленное растяжение через четверть секунды после
	-- каждого попадания, и шахта дёргалась бы вместо того, чтобы расти.
end

function MineService:_applyDoorRarity(plot, rarityKey)
	local door = plot.MineDoorPart
	if not door then return end
	local colorFx = Config.MineExpedition.DoorColorFX == true
	if colorFx then
		local color = Config.MineDoorRarityColor[rarityKey] or Config.MineDoorRarityColor.Common
		door.Material = Enum.Material.Neon
		door.Color = color
	end

	-- VFX по ТЗ: под MineDoor лежат attachment'ы/эмиттеры "VFX_<Rarity>"
	-- (Common/Uncommon/Rare/Epic/Legendary) — включаем те, что совпадают с
	-- выпавшей редкостью, выключаем остальные. Ищем и прямые дети, и
	-- вложенные (эмиттер внутри своего Attachment).
	for _, descendant in door:GetDescendants() do
		local name = descendant.Name
		local matchesTag = name:match("^VFX_(%a+)$")
		if matchesTag and (descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") or descendant:IsA("Trail") or descendant:IsA("Attachment")) then
			local matches = colorFx and matchesTag == rarityKey
			if descendant:IsA("Attachment") then
				for _, child in descendant:GetChildren() do
					if child:IsA("ParticleEmitter") or child:IsA("Beam") or child:IsA("Trail") then
						child.Enabled = matches
					end
				end
			else
				descendant.Enabled = matches
			end
		end
	end
end

function MineService:_onArcHit(player, token, clientElapsed)
	local expedition = expeditions[player]
	if not expedition then return end
	local pending = expedition.PendingRound
	if not pending or pending.Token ~= token then return end -- устаревшее/поддельное приглашение

	local cfg = Config.MineExpedition

	-- ГДЕ БЫЛА КИРКА В МОМЕНТ НАЖАТИЯ. Клиент присылает, сколько времени
	-- прошло у него с начала раунда; верим этому только в пределах окна
	-- лага (2·пинг + запас, не больше VeinLagMax), иначе берём серверное
	-- время. Так честный игрок с пингом не страдает, а подобрать "удобный"
	-- момент задним числом можно лишь в пределах пары кадров.
	local serverElapsed = os.clock() - pending.StartClock
	local elapsed = serverElapsed
	if clientElapsed then
		local okPing, ping = pcall(function() return player:GetNetworkPing() end)
		ping = (okPing and type(ping) == "number") and ping or 0.1
		local window = math.clamp(ping * 2 + (cfg.VeinLagGrace or 0.12), 0.05, cfg.VeinLagMax or 0.35)
		elapsed = math.clamp(clientElapsed, serverElapsed - window, serverElapsed + 0.03)
	end
	local position = MineVeinMath.NeedlePosition(elapsed, pending.SweepSeconds, pending.Motion, pending.Flips)
	local zonesNow = MineVeinMath.ZonesAt(pending.Zones, elapsed, pending.Shrink)
	local zone = MineVeinMath.ZoneAt(zonesNow, position, cfg.VeinHitTolerance or 0)
	-- v14.3 DUAL PICKS: вторая кирка идёт навстречу — берём ЛУЧШУЮ из двух.
	local pickIndex = 1
	local otherPosition = nil
	if pending.Dual then
		otherPosition = MineVeinMath.MirrorPosition(position)
		local other = MineVeinMath.ZoneAt(zonesNow, otherPosition, cfg.VeinHitTolerance or 0)
		if MineVeinMath.Rank(other) > MineVeinMath.Rank(zone) then
			zone, position, otherPosition, pickIndex = other, otherPosition, position, 2
		end
	end
	local quality = zone and zone.Kind or "Miss" -- "Perfect" / "Good" / "Miss"

	expedition.PendingRound = nil
	expedition.Hits += 1
	local hitIndex = expedition.Hits

	-- УДАЧА: самородок > кристаллы, промах — НОЛЬ (по прямому запросу).
	local modifier = expedition.Modifier
	local luckGain = (cfg.VeinLuck and cfg.VeinLuck[quality]) or 0
	if luckGain > 0 and modifier then
		luckGain *= modifier.LuckMul or 1
		if quality == "Perfect" then
			luckGain *= modifier.PerfectLuckMul or 1
		end
		-- v14.3 MOMENTUM: серия PERFECT увеличивает удачу удара.
		if modifier.Momentum then
			luckGain *= 1 + (modifier.MomentumLuck or 0.5) * (expedition.Momentum or 0)
		end
	end
	if modifier and modifier.Momentum then
		expedition.Momentum = quality == "Perfect" and (expedition.Momentum or 0) + 1 or 0
	end
	expedition.LuckBonus = (expedition.LuckBonus or 0) + luckGain
	expedition.HitResults = expedition.HitResults or {}
	expedition.HitResults[hitIndex] = quality

	local color = cfg.VeinColors[quality] or cfg.VeinColors.Miss
	self:_pulseMineDoor(expedition.Plot, color)
	-- Шахта реагирует по-разному на PERFECT / GOOD / MISS (рост + тряска).
	self:_stretchMine(expedition.Plot, hitIndex, quality)

	-- НАКОПИТЕЛЬНЫЙ НАЕЗД КАМЕРЫ (считает сервер, клиент только применяет).
	local zoom = math.max(
		(cfg.HitFOVZoomStep or -3.5) * hitIndex,
		cfg.HitFOVZoomMax or -14
	)
	local zoomedBase = (cfg.CameraFOVMinigame or 62) + zoom

	-- Для каменных осколков у клиента: откуда вылетают и какого размера шахта.
	local door = expedition.Plot.MineDoorPart
	local doorPosition = (door and door.Position) or minePosition(expedition.Plot)
	local mineSize, mineCenter = nil, nil
	local mine = expedition.Plot.MineModel
	if mine and mine.Parent then
		local okBox, boxCFrame, size = pcall(function() return mine:GetBoundingBox() end)
		if okBox then
			mineSize = size
			mineCenter = boxCFrame
		end
	end
	local reaction = cfg.MineHitReaction and cfg.MineHitReaction[quality] or {}

	stateRemote:FireClient(player, "Hit", {
		RoundIndex = hitIndex,
		HitsRequired = expedition.HitsRequired or cfg.HitsRequired,
		Quality = quality,
		PickIndex = pickIndex,
		OtherPosition = otherPosition,
		Momentum = expedition.Momentum,
		ZoneKind = quality, -- совместимость со старыми обработчиками
		ZoneColor = color,
		Position = position, -- где реально засчитан удар (клиент ставит туда вспышку)
		LuckGain = luckGain,
		LuckBonus = expedition.LuckBonus,
		FOVKick = (cfg.HitFOVKick or -6) * (quality == "Perfect" and 1.6 or quality == "Miss" and 0.4 or 1),
		FOVKickSeconds = cfg.HitFOVKickSeconds,
		FOVBase = zoomedBase,
		FOVBaseSeconds = cfg.HitFOVZoomSeconds,
		DoorPosition = doorPosition,
		MineSize = mineSize,
		MineCenter = mineCenter,
		Rocks = reaction.Rocks or 0,
	})

	if hitIndex >= (expedition.HitsRequired or cfg.HitsRequired) then
		task.delay(0.35, function()
			if expeditions[player] == expedition then
				-- v14.3: сначала пролетает карточка редкости шахты.
				self:_showRarityCard(player, expedition)
				if expeditions[player] ~= expedition then return end
				local ok, err = pcall(function() self:_ejectOre(player, expedition) end)
				if not ok then
					warn("[MineService] _ejectOre failed:", err)
					self:_finishExpedition(player, expedition)
				end
			end
		end)
	else
		task.delay((cfg.MineShakeSeconds or 0.3) + 0.35, function()
			if expeditions[player] == expedition then
				self:_startArcRound(player, expedition, hitIndex + 1)
			end
		end)
	end
end

-- v14.3: КАРТОЧКА РЕДКОСТИ ШАХТЫ. Та же редкость, по которой после
-- мини-игры подменяется вход (Config.AverageRarityForTier с учётом удачи).
-- Клиент рисует пролёт (MineExpeditionUI → RarityCard), сервер просто ждёт,
-- пока он доиграет, и только потом начинает вылет руды.
function MineService:_showRarityCard(player, expedition)
	local card = Config.MineExpedition.RarityCard or {}
	local rarity = Config.AverageRarityForTier(expedition.Tier, expedition.LuckBonus)
	stateRemote:FireClient(player, "RarityCard", {
		Rarity = rarity,
		Color = Config.RarityColors[rarity],
	})
	local extra = (card.Effects and card.Effects[rarity] and card.Effects[rarity].HoldExtra) or 0
	task.wait((card.InSeconds or 0.34) + (card.HoldSeconds or 0.42) + extra + (card.OutSeconds or 0.3) + 0.05)
end

--------------------------------------------------------------------------------
-- ШАГ 4: ВЫБРОС РУДЫ
--------------------------------------------------------------------------------

-- СПОЙЛЕР БЕЗ "ЧЁРНОГО ШАРИКА" (по прямому запросу).
--
-- Раньше вокруг летящей руды создавалась ОТДЕЛЬНАЯ чёрная сфера
-- SpoilerShell — из-за неё игрок видел не руду, а мяч, и вся анимация
-- squash/stretch самой руды была не видна вообще (шар её перекрывал).
-- Теперь спойлерится САМА руда: каждая её часть запоминает свой
-- Color/Material/Reflectance и временно становится ЧЁРНЫМ НЕОНОМ, а на
-- раскрытии получает прежний материал обратно (см. restoreSpoilerLook).
local SPOILER_COLOR = Color3.fromRGB(10, 10, 14)

local function spoilerParts(crystal)
	local parts = {}
	if crystal:IsA("BasePart") then
		table.insert(parts, crystal)
	else
		for _, descendant in crystal:GetDescendants() do
			if descendant:IsA("BasePart") then table.insert(parts, descendant) end
		end
	end
	return parts
end

local function applySpoilerLook(crystal)
	for _, part in spoilerParts(crystal) do
		-- Исходный вид храним В АТРИБУТАХ САМОЙ ЧАСТИ, а не в замыкании:
		-- если экспедиция оборвётся на полпути (игрок вышел, сервис
		-- перезапустился), восстановить вид сможет кто угодно, а не
		-- только та корутина, которая его испортила.
		if part:GetAttribute("SpoilerSaved") ~= true then
			part:SetAttribute("SpoilerSaved", true)
			part:SetAttribute("SpoilerColor", part.Color)
			part:SetAttribute("SpoilerMaterial", part.Material.Name)
			part:SetAttribute("SpoilerReflectance", part.Reflectance)
		end
		part.Color = SPOILER_COLOR
		part.Material = Enum.Material.Neon
		part.Reflectance = 0
	end
end

local function restoreSpoilerLook(crystal, seconds)
	for _, part in spoilerParts(crystal) do
		if part:GetAttribute("SpoilerSaved") == true then
			local color = part:GetAttribute("SpoilerColor") or Color3.new(1, 1, 1)
			local materialName = part:GetAttribute("SpoilerMaterial")
			local reflectance = part:GetAttribute("SpoilerReflectance") or 0
			-- Материал возвращаем СРАЗУ (Material не твинится в принципе),
			-- а цвет доезжает плавно — глаз читает это как "вспыхнуло и
			-- проявилось", без ступеньки между кадрами.
			local okMaterial, material = pcall(function() return Enum.Material[materialName] end)
			part.Material = (okMaterial and material) or Enum.Material.Neon
			part.Reflectance = reflectance
			TweenService:Create(
				part,
				TweenInfo.new(seconds or 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Color = color }
			):Play()
			part:SetAttribute("SpoilerSaved", nil)
			part:SetAttribute("SpoilerColor", nil)
			part:SetAttribute("SpoilerMaterial", nil)
			part:SetAttribute("SpoilerReflectance", nil)
		end
	end
end

-- Анимированные "???" над ещё не раскрытой рудой (по прямому запросу).
-- Сам БИЛБОРД ставит сервер (он же его и снимает), а ДВИЖЕНИЕ вопросиков
-- рисует клиент — см. src/client/OreMysteryFX.client.lua. Так анимация
-- идёт в 60 fps у каждого игрока и не стоит НИ ОДНОГО сетевого пакета:
-- сервер меняет только факт "билборд есть / билборда нет".
local function attachMysteryGui(crystal)
	local root = CrystalUtil.GetRoot(crystal)
	if not root then return nil end
	local gui = Instance.new("BillboardGui")
	gui.Name = "MysteryGui"
	gui.Size = UDim2.new(3.2, 0, 1.1, 0)
	gui.StudsOffset = Vector3.new(0, 2.2, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 100
	gui.Adornee = root
	gui.Parent = root

	-- ТРИ отдельных TextLabel, а не один со строкой "???" — только так
	-- клиент может гонять каждый вопросик со своей фазой (волна, разный
	-- масштаб, разный наклон). В одном TextLabel буквы двигаться не умеют.
	for i = 1, 3 do
		local mark = WorldUi.Text(nil, "Text", "Heading")
		mark.Name = "Mark" .. i
		mark.BackgroundTransparency = 1
		mark.Size = UDim2.fromScale(1 / 3, 1)
		mark.Position = UDim2.fromScale((i - 1) / 3, 0)
		mark.Text = "?"
		mark.TextScaled = true
		mark.TextColor3 = Color3.fromRGB(255, 255, 255)
		mark.Parent = gui
	end
	return gui
end

-- Настоящая высота пола под точкой приземления (по прямому запросу — "они
-- сто процентов должны появляться на земле", раньше landPos.Y бездумно
-- копировал plot.OreDropPosition.Y, а это исторически точка НАД тележкой,
-- см. PlotService — отсюда и баг "появляются наверху"). Рейкаст вниз по
-- полу/декорациям участка — надёжнее для любой геометрии площадки, чем
-- фиксированное число.
local function groundYAt(position, plot)
	local origin = Vector3.new(position.X, position.Y + 25, position.Z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local include = {}
	if plot.Pad then table.insert(include, plot.Pad) end
	if plot.Content then table.insert(include, plot.Content) end
	params.FilterDescendantsInstances = include
	local result = workspace:Raycast(origin, Vector3.new(0, -60, 0), params)
	if result then
		return result.Position.Y
	end
	return plot.Pad and (plot.Pad.Position.Y + plot.Pad.Size.Y / 2) or position.Y
end

-- АНИМАЦИЯ ВЫЛЕТА РУДЫ. Построена на классических принципах анимации
-- (Disney 12 principles / "game juice" — squash & stretch, anticipation,
-- arcs, slow in/out), а не на равномерном движении по синусоиде:
--   1. ANTICIPATION — перед вылетом камень на мгновение сжимается
--      (приседает) в сторону выброса. Глаз читает это как "набрал силу".
--   2. STRETCH В ПОЛЁТЕ — на быстрых участках (старт/падение) камень
--      вытягивается ВДОЛЬ направления движения и одновременно сужается
--      поперёк, СОХРАНЯЯ ОБЪЁМ (иначе это выглядит как надувание шарика,
--      а не как летящее тело с массой).
--   3. SQUARED ARC — вершина дуги достигается быстрее, чем середина
--      пути, и камень на ней слегка "зависает", после чего падает резче
--      (Ease-Out вверх, Ease-In вниз) — плоская парабола выглядит вяло.
--   4. SQUASH НА УДАРЕ — при касании земли камень сплющивается (шире и
--      ниже), потом отскакивает чуть выше нормы и возвращается в форму.
--   5. Трейл подчёркивает дугу движения (см. EjectTrail* в Config).
-- ЛЕВИТАЦИЯ. Кусок висит чуть выше земли и покачивается — так он читается
-- как добыча, виден поверх травы и не тонет в рельефе.
--
-- Здесь ТОЛЬКО включаем режим: саму высоту применяет общий Heartbeat
-- вращения (см. Init). Отдельная корутина, как было раньше, писала в тот
-- же root.CFrame параллельно с вращением, и два писателя рвали кусок на
-- части — его подбрасывало и дёргало.
local function startHover(crystal, groundY)
	crystal:SetAttribute("HoverGroundY", groundY)
	-- Приземление полностью доиграно — только теперь кусок можно
	-- подбирать (ногами/тележкой). Раньше хватало Landed, который ставится
	-- ДО фаз удара о землю: подбор стартовал, пока flyOre ещё менял
	-- размер и позицию, и два кода рвали кусок друг у друга.
	crystal:SetAttribute("PickupReady", true)
	-- Разная стартовая фаза: иначе вся куча качалась бы синхронно.
	crystal:SetAttribute("HoverPhase", math.random() * 10)
end

-- spitPop: true ТОЛЬКО для настоящего вылета из шахты (см. _ejectOre).
-- Ручной выброс игроком (Backspace, ThrowOreToGround) этот параметр не
-- передаёт: "шахта выплёвывает руду" — это буквально шахта, у брошенного
-- рукой куска источник совсем другой, натягивать на него ту же метафору
-- было бы уместно только совпадением, а не по смыслу запроса.
local function flyOre(crystal, fromPos, toPos, seconds, arcHeight, spitPop)
	local root = CrystalUtil.GetRoot(crystal)
	if not root then return end
	root.Anchored = true
	root.CanCollide = false

	local cfg = Config.MineExpedition
	local baseSize = root.Size

	local trail = Instance.new("Trail")
	local a0 = Instance.new("Attachment", root)
	a0.Position = Vector3.new(0, baseSize.Y / 2, 0)
	local a1 = Instance.new("Attachment", root)
	a1.Position = Vector3.new(0, -baseSize.Y / 2, 0)
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = cfg.EjectTrailLifetime or 0.4
	trail.WidthScale = NumberSequence.new(cfg.EjectTrailWidth or 0.6)
	local okColor, color = pcall(function() return root.Color end)
	trail.Color = ColorSequence.new(okColor and color or Color3.new(1, 1, 1))
	trail.Parent = root

	-- Кувырок по горизонтальной оси ("волейбольный мяч"), не юлой вокруг
	-- вертикали.
	local tumbleAxis = Vector3.new(math.random() * 2 - 1, 0, math.random() * 2 - 1)
	if tumbleAxis.Magnitude < 0.01 then tumbleAxis = Vector3.xAxis end
	tumbleAxis = tumbleAxis.Unit

	-- Объём-сохраняющая деформация: вытянули на factor вдоль оси движения
	-- → сузили на 1/sqrt(factor) по двум другим.
	local function stretchedSize(factor)
		local lateral = 1 / math.sqrt(factor)
		return Vector3.new(baseSize.X * lateral, baseSize.Y * factor, baseSize.Z * lateral)
	end

	-- ИСПРАВЛЕНИЕ ДЛЯ МЕШЕВЫХ РУД. Руда бывает и BasePart (плейсхолдер), и
	-- Model с мешем внутри (см. PlaceholderFactory.OreCrystal — "это всё
	-- будут меши в будущем"). Для Model менять root.Size БЕСПОЛЕЗНО:
	-- деформируется невидимый Root, а приваренный к нему меш остаётся
	-- прежнего размера — вся анимация squash/stretch просто не видна. У
	-- Model нет поосевого масштаба, поэтому там деформация читается через
	-- равномерный ScaleTo: чуть меньше на приседании, чуть больше на
	-- отскоке. Форма чуть другая, но движение наконец ВИДНО.
	local isModel = crystal:IsA("Model")
	local baseScale = 1
	if isModel then
		local okScale, scale = pcall(function() return crystal:GetScale() end)
		baseScale = (okScale and scale) or 1
	end
	-- "ПЛЕВОК" — ОБЩИЙ РАЗМЕР, А НЕ ФОРМА (по прямому запросу: "при
	-- каждом вылете руда должна становиться больше, а после плевка
	-- уменьшаться, будто шахта выплёвывает руду").
	--
	-- ЭТО ДРУГОЙ ЭФФЕКТ, чем squash/stretch выше. stretchedSize/applyShape
	-- меняют ФОРМУ с сохранением объёма (вытянули по одной оси — сузили по
	-- двум другим), поэтому "воздушный шар" из них не получится: общий
	-- размер визуально почти не меняется. Здесь нужен настоящий скачок
	-- ОБЩЕГО масштаба вверх и обратно вниз — множитель popScale
	-- перемножается с формой (applyShape), а не заменяет её: кусок
	-- одновременно и раздувается целиком, и продолжает деформироваться по
	-- скорости полёта.
	local popScale = 1
	local function applyShape(factor)
		if isModel then
			-- Сжимаем диапазон: 0.62..1.45 по одной оси ≈ 0.86..1.15
			-- равномерно — равномерный масштаб той же силы выглядел бы
			-- как "руда то приближается, то отдаляется".
			local okApply = pcall(function()
				crystal:ScaleTo(baseScale * popScale * (1 + (factor - 1) * 0.35))
			end)
			if not okApply then return end
		else
			local shaped = stretchedSize(factor)
			root.Size = Vector3.new(shaped.X * popScale, shaped.Y * popScale, shaped.Z * popScale)
		end
	end

	-- Разгоняет popScale от 1 → пик → обратно к 1 за EjectSpitPopSeconds,
	-- крутится ПАРАЛЛЕЛЬНО основной анимации (та трогает Size/ScaleTo сама
	-- по своему расписанию — применяем popScale внутри тех же вызовов
	-- applyShape, а не отдельными перезаписями Size, чтобы два источника
	-- правок не затирали друг друга, см. похожий баг с левитацией §18).
	local function startSpitPop()
		local peak = cfg.EjectSpitPopMultiplier or 1.35
		local seconds = cfg.EjectSpitPopSeconds or 0.3
		local popSteps = math.max(6, math.floor(seconds * 60))
		task.spawn(function()
			for i = 1, popSteps do
				if not root.Parent then return end
				local a = i / popSteps
				-- Резко вверх (первая треть), плавно вниз (остаток) — "выплюнули",
				-- а не "равномерно подышали".
				if a < 0.33 then
					popScale = 1 + (peak - 1) * (a / 0.33)
				else
					local fall = (a - 0.33) / 0.67
					popScale = peak - (peak - 1) * (fall * fall * (3 - 2 * fall)) -- smoothstep вниз
				end
				task.wait(seconds / popSteps)
			end
			popScale = 1
		end)
	end

	-- СТРАХОВКА. Если корутина полёта ниже оборвётся на ошибке (битый
	-- ассет руды и т.п.), кусок так и остался бы без PickupReady — то есть
	-- навсегда неподбираемым. Через заведомо большее время, чем длится весь
	-- полёт с приземлением, дожимаем флаги сами.
	task.delay(seconds + (cfg.LandingSquashSeconds or 0.26) + 1.5, function()
		if crystal.Parent and crystal.Parent.Name == "MineGroundOre"
			and crystal:GetAttribute("PickupReady") ~= true
			and crystal:GetAttribute("InventoryPickupInProgress") ~= true then
			crystal:SetAttribute("Landed", true)
			crystal:SetAttribute("PickupReady", true)
		end
	end)

	local steps = math.max(10, math.floor(seconds * 60))
	task.spawn(function()
		-- (1) ANTICIPATION — короткое приседание перед вылетом.
		local anticipationSeconds = math.min(0.12, seconds * 0.18)
		local anticipationSteps = math.max(2, math.floor(anticipationSeconds * 60))
		for i = 1, anticipationSteps do
			if not root.Parent then return end
			local a = i / anticipationSteps
			applyShape(1 - 0.25 * a) -- сжимается по вертикали, раздаётся вширь
			root.CFrame = CFrame.new(fromPos)
			task.wait(anticipationSeconds / anticipationSteps)
		end

		-- СПИТ — запускается ровно в момент выхода из шахты, на стыке
		-- приседания и полёта: именно здесь кусок "покидает" дверь, и
		-- раздутие должно начаться отсюда, а не раньше (иначе выглядело бы
		-- как "разбухло ещё внутри шахты") и не позже (иначе "вылетело, а
		-- потом почему-то распухло в воздухе").
		if spitPop then startSpitPop() end

		-- (2)+(3) ПОЛЁТ: "квадратная" дуга + stretch по скорости.
		local previousPos = fromPos
		for i = 1, steps do
			if not root.Parent then return end
			local linear = i / steps
			-- Горизонталь — slow in/out (smoothstep), чтобы камень
			-- вылетал резко и мягко "доезжал" до точки приземления.
			local horizontal = linear * linear * (3 - 2 * linear)
			-- Вертикаль — ВЕРШИНА РАНЬШЕ СЕРЕДИНЫ (pow < 1 на подъёме) +
			-- зависание на пике + резкое падение: тот самый "squared arc".
			local lift
            if linear < 0.45 then
				lift = math.sin((linear / 0.45) * (math.pi / 2)) -- быстрый подъём, плавное торможение к пику
			else
				local fall = (linear - 0.45) / 0.55
				lift = math.cos(fall * (math.pi / 2)) ^ 0.7 -- зависание, затем ускоряющееся падение
			end
			local pos = fromPos:Lerp(toPos, horizontal) + Vector3.new(0, lift * arcHeight, 0)

			-- Stretch пропорционален мгновенной скорости (расстояние за
			-- кадр), максимум +45% по длине.
			local speed = (pos - previousPos).Magnitude
			local stretch = math.clamp(1 + speed * 0.22, 1, 1.45)
			-- Для Model НЕ трогаем масштаб покадрово: ScaleTo пересобирает
			-- размеры всех частей модели, и 60 раз в секунду на каждый из
			-- десятка летящих кусков это заметная нагрузка на ровном месте.
			-- Модели получают деформацию только на приседании и на ударе,
			-- где она и читается.
			if not isModel then
				root.Size = stretchedSize(stretch)
			end
			previousPos = pos

			root.CFrame = CFrame.new(pos) * CFrame.fromAxisAngle(tumbleAxis, linear * math.pi * 4)
			task.wait(seconds / steps)
		end

		if not root.Parent then return end
		root.CFrame = CFrame.new(toPos)
		-- Коллизии у руды нет (по прямому запросу): лежащий кусок
		-- заанкорен и висит на ховере, толкать игроков/тележку ему незачем.
		root.CanCollide = false
		crystal:SetAttribute("Landed", true)
		crystal:SetAttribute("SpinAxis", math.random() < 0.5 and 1 or -1)
		task.delay((trail.Lifetime or 0.4) + 0.05, function()
			if trail.Parent then trail.Enabled = false end
		end)

		-- (4) SQUASH НА УДАРЕ → отскок → возврат в форму. Держим короткими
		-- (по рекомендации из исследования — деформация должна проходить
		-- за считанные кадры, иначе выглядит резиновой).
		-- ПЫЛЬ ОТ УДАРА. Без неё приземление читается как "камень
		-- телепортировался и задёргался": глазу нужен внешний признак
		-- контакта с землёй, а не только деформация самого тела.
		local dustAttachment = Instance.new("Attachment")
		dustAttachment.Name = "LandingDust"
		dustAttachment.Position = Vector3.new(0, -baseSize.Y / 2, 0)
		dustAttachment.Parent = root
		local dust = Instance.new("ParticleEmitter")
		dust.Name = "Dust"
		dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
		dust.Color = ColorSequence.new(Color3.fromRGB(170, 160, 150))
		dust.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		})
		dust.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(1, 2.4),
		})
		dust.Lifetime = NumberRange.new(0.3, 0.55)
		dust.Speed = NumberRange.new(4, 7)
		dust.SpreadAngle = Vector2.new(70, 70)
		dust.Drag = 6
		dust.Rate = 0
		dust.Rotation = NumberRange.new(-180, 180)
		dust.Parent = dustAttachment
		dust:Emit(14)
		Debris:AddItem(dustAttachment, 1.2)

		local impactSeconds = cfg.LandingSquashSeconds or 0.26
		-- ЧЕТЫРЕ фазы вместо трёх: добавлен затухающий ВТОРОЙ отскок.
		-- Один отскок читается как "пружина", два затухающих — как
		-- предмет с массой, который наконец улёгся.
		local phases = {
			{ Factor = 0.62, Portion = 0.24, Hop = 0.0 },  -- сплющился об землю
			{ Factor = 1.14, Portion = 0.28, Hop = 0.45 }, -- отскочил вытянувшись
			{ Factor = 0.88, Portion = 0.24, Hop = 0.12 }, -- второй, слабый отскок
			{ Factor = 1.0,  Portion = 0.24, Hop = 0.0 },  -- улёгся
		}
		local fromFactor = 1.2
		local fromHop = 0
		for _, phase in phases do
			local phaseSeconds = impactSeconds * phase.Portion
			local phaseSteps = math.max(2, math.floor(phaseSeconds * 60))
			for i = 1, phaseSteps do
				if not root.Parent then return end
				local a = i / phaseSteps
				applyShape(fromFactor + (phase.Factor - fromFactor) * a)
				-- Держим камень стоящим НА земле, а не "втопленным" в неё,
				-- пока меняется высота (Size растёт от центра в обе стороны),
				-- и подкидываем на Hop во время отскоков.
				local hop = fromHop + (phase.Hop - fromHop) * a
				root.CFrame = CFrame.new(toPos + Vector3.yAxis * hop)
				task.wait(phaseSeconds / phaseSteps)
			end
			fromFactor = phase.Factor
			fromHop = phase.Hop
		end
		if root.Parent then
			if isModel then
				pcall(function() crystal:ScaleTo(baseScale) end)
			else
				root.Size = baseSize
			end
			root.CFrame = CFrame.new(toPos)
			-- ЛЕВИТАЦИЯ ЗАПУСКАЕТСЯ ТОЛЬКО ЗДЕСЬ — когда приземление полностью
			-- отыграно. РАНЬШЕ она стартовала по флагу "Landed", который
			-- ставится ДО фаз удара: цикл левитации тянул кусок на высоту
			-- висения, а фазы удара в тот же момент возвращали его на землю.
			-- Два кода писали в один CFrame по 30-45 раз в секунду — руду и
			-- "колбасило": она подпрыгивала, падала обратно и дёргалась, как
			-- будто лагает.
			startHover(crystal, toPos.Y)
		end
	end)
end

-- ПО ПРЯМОМУ ЗАПРОСУ: первый (самый редкий, центральный) кусок из каждой
-- добычи ВСЕГДА получает постоянную пометку "GIGANTIC" — крупнее и с
-- отдельной надписью над обычным ценником, чтобы выделяться, независимо
-- от того, насколько редкая сама руда (даже уголь в тире 1 иногда будет
-- "гигантским" — это про ПОРЯДОК вылета, а не про везение).
-- v9: КРУПНЫЙ ШАНС «1/N» НА ВРЕМЯ КАТСЦЕНЫ (только шанс, без цены).
-- Появляется вместе с ценником (JustRevealed → Enabled), убирается в
-- _shrinkGroundOre.
local function attachCutsceneChance(crystal, priceGui)
	local chance = tonumber(crystal:GetAttribute("CrystalDisplayChance")) or tonumber(crystal:GetAttribute("CrystalChance")) or 0
	if chance <= 0 or not priceGui then return end
	local root = priceGui.Parent
	if not root then return end
	local oneInN = math.max(1, math.round(1 / chance))
	local rarity = crystal:GetAttribute("CrystalRarity")
	local color = (rarity and Config.RarityColors and Config.RarityColors[rarity]) or Color3.fromRGB(255, 225, 130)
	local gui = Instance.new("BillboardGui")
	gui.Name = "CutsceneChance"
	gui.Size = UDim2.new(4.2, 0, 1.6, 0)
	gui.StudsOffset = Vector3.new(0, 5, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 160
	gui.Enabled = priceGui.Enabled
	gui.Adornee = root
	gui.Parent = root
	local label = WorldUi.Text(nil, "Text", "Heading")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.Text = "1/" .. NumberFormat.abbreviate(oneInN)
	label.TextColor3 = color
	label.Parent = gui
	priceGui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if gui.Parent then gui.Enabled = priceGui.Enabled end
	end)
end

function MineService:_markAsGigantic(crystal)
	crystal:SetAttribute("Gigantic", true)
	local ok = pcall(function()
		if crystal:IsA("Model") then
			crystal:ScaleTo((crystal:GetScale() or 1) * 1.5)
		elseif crystal:IsA("BasePart") then
			crystal.Size = crystal.Size * 1.5
		end
	end)
	if not ok then
		warn("[MineService] Не удалось увеличить GIGANTIC-руду (ScaleTo) - метка всё равно проставлена.")
	end

	local priceGui = crystal:FindFirstChild("PriceGui", true)
	local root = priceGui and priceGui.Parent
	if not root then return end

	local badge = Instance.new("BillboardGui")
	badge.Name = "GiganticBadge"
	badge.Size = UDim2.new(4.4, 0, 0.6, 0)
	badge.StudsOffset = Vector3.new(0, 3.5, 0) -- выше обычного ценника (тот на 2.2, см. CrystalService.attachPriceGui)
	badge.AlwaysOnTop = true
	badge.Enabled = false -- включается вместе с ценником при раскрытии (см. MineService:_ejectOre — priceGui.Enabled = true в тот же момент)
	badge.Parent = root

	local label = WorldUi.Text(nil, "Text", "Heading")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 215, 60)
	label.Text = "GIGANTIC"
	label.Parent = badge

	-- Раскрывается СИНХРОННО с ценником (revealPiece только переключает
	-- priceGui.Enabled — подцепляем то же самое здесь, не дублируя логику
	-- показа): просто следим за ценником и копируем его Enabled.
	priceGui:GetPropertyChangedSignal("Enabled"):Connect(function()
		badge.Enabled = priceGui.Enabled
	end)
end

-- Масштаб куска руды, одинаково для Model и для BasePart-плейсхолдера.
-- Исходный размер запоминаем в атрибуте, чтобы уменьшение в конце
-- катсцены не зависело от того, кто и когда его увеличивал.
-- scale — ОТНОСИТЕЛЬНО собственного размера куска, запомненного при первом
-- вызове. Раньше для Model стоял абсолютный ScaleTo(scale): у Model-руды
-- уже есть свой масштаб (вариация I/II/III, пометка GIGANTIC ×1.5), и
-- "вернуть к 1" после катсцены стирало его — гигантская руда становилась
-- обычной, вариация III — размером с I.
local function scaleCrystal(crystal, scale)
	if crystal:IsA("Model") then
		local base = crystal:GetAttribute("BaseScale")
		if type(base) ~= "number" or base <= 0 then
			local ok, current = pcall(function() return crystal:GetScale() end)
			base = (ok and current and current > 0) and current or 1
			crystal:SetAttribute("BaseScale", base)
		end
		pcall(function() crystal:ScaleTo(base * scale) end)
		return
	end
	if not crystal:IsA("BasePart") then return end
	local base = crystal:GetAttribute("BaseSize")
	if typeof(base) ~= "Vector3" then
		base = crystal.Size
		crystal:SetAttribute("BaseSize", base)
	end
	crystal.Size = base * scale
end

-- ВЫБРОС РУДЫ ИГРОКОМ (Backspace). Отдельная публичная точка входа:
-- InventoryService снимает стопку из рюкзака и просит нас положить кусок
-- на землю. Дуга, приземление, вращение и левитация — тот же flyOre, что
-- и у выброса из шахты, поэтому выброшенный кусок ничем не отличается от
-- любого другого лежащего и подбирается так же.
function MineService:ThrowOreToGround(player, crystal)
	if not (player and crystal) then return false end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		crystal:Destroy()
		return false
	end
	if not groundOreFolder then
		groundOreFolder = workspace:FindFirstChild("MineGroundOre")
	end
	if not groundOreFolder then
		crystal:Destroy()
		return false
	end

	local cfg = Config.MineExpedition
	-- Якорим ВСЕ детали, а не только корень: flyOre анкорит root, но у
	-- модели остальные части могут быть свободными — они бы просто упали
	-- сквозь дугу полёта.
	for _, d in (crystal:IsA("Model") and crystal:GetDescendants() or { crystal }) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end

	crystal.Parent = groundOreFolder
	crystal:SetAttribute("GroundOreOwner", player.UserId)
	-- ВЫБРОШЕННУЮ РУДУ МОЖЕТ ПОДОБРАТЬ КТО УГОДНО (по прямому запросу).
	-- Обычная руда с шахты подбирается только владельцем участка; этот
	-- флаг снимает ограничение именно для выброшенных кусков, не трогая
	-- остальные.
	crystal:SetAttribute("PublicDrop", true)
	-- ЗАДЕРЖКА СОБСТВЕННОГО ПОДБОРА. Игрок стоит ровно там, откуда бросил,
	-- и без паузы кусок мгновенно всасывался бы обратно — выбросить руду
	-- было бы физически невозможно. Пауза именно ПЕРСОНАЛЬНАЯ: чужие
	-- игроки могут подобрать сразу, ждёт только тот, кто бросил.
	crystal:SetAttribute("DropOwnerUserId", player.UserId)
	crystal:SetAttribute("DropOwnerCooldownUntil", os.time() + (Config.MineExpedition.DropSelfPickupDelay or 3))
	crystal:SetAttribute("Landed", false)
	crystal:SetAttribute("SpinAxis", math.random(1, 2) == 1 and 1 or -1)

	-- Летит ВПЕРЁД от игрока и чуть в сторону, чтобы несколько брошенных
	-- подряд кусков не ложились друг в друга.
	local from = root.Position + Vector3.new(0, 2, 0)
	local forward = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	forward = forward.Magnitude > 0.1 and forward.Unit or Vector3.zAxis
	local side = forward:Cross(Vector3.yAxis) * ((math.random() - 0.5) * 4)
	local landXZ = root.Position + forward * (cfg.DropThrowDistance or 7) + side
	local plot = Services.PlotService and Services.PlotService:GetPlot(player)
	local landY = plot and groundYAt(landXZ, plot) or root.Position.Y - 2
	local to = Vector3.new(landXZ.X, landY, landXZ.Z)

	flyOre(crystal, from, to, cfg.DropThrowSeconds or 0.6, cfg.DropThrowArcHeight or 6)
	return true
end


-- ВЫПЛЁВЫВАНИЕ ГОТОВОГО КУСКА ИЗ ДРУГОГО ИСТОЧНИКА (плавильня на острове,
-- см. IslandService). Та же анимация, что у руды из шахты: приседание,
-- "плевок" с раздуванием, дуга с трейлом, удар о землю. Кусок ложится в
-- MineGroundOre и подбирается ТОЛЬКО владельцем (GroundOreOwner) — ногами
-- или тележкой, ровно как выброс шахты. landXZ — куда примерно упасть;
-- высота земли ищется лучом по участку (острова лежат внутри его Content).
function MineService:EjectToGround(player, crystal, fromPos, landXZ, seconds, arcHeight)
	if not (player and crystal) then return false end
	if not groundOreFolder then
		groundOreFolder = workspace:FindFirstChild("MineGroundOre")
	end
	if not groundOreFolder then
		return false
	end
	for _, d in (crystal:IsA("Model") and crystal:GetDescendants() or { crystal }) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
	crystal.Parent = groundOreFolder
	crystal:SetAttribute("GroundOreOwner", player.UserId)
	crystal:SetAttribute("Landed", false)
	crystal:SetAttribute("SpinAxis", math.random(1, 2) == 1 and 1 or -1)
	local plot = Services.PlotService and Services.PlotService:GetPlot(player)
	local landY = plot and groundYAt(landXZ, plot) or landXZ.Y
	flyOre(crystal, fromPos, Vector3.new(landXZ.X, landY, landXZ.Z), seconds or 0.75, arcHeight or 7, true)
	return true
end

-- Короткая тряска в момент раскрытия — кусок "вздрагивает", прежде чем
-- показать, чем он оказался.
local function shakeCrystal(crystal)
	local cfg = Config.MineExpedition
	local okRoot, root = pcall(CrystalUtil.GetRoot, crystal)
	if not okRoot or not root then return end
	task.spawn(function()
		local seconds = cfg.RevealShakeSeconds or 0.35
		local amplitude = cfg.RevealShakeStuds or 0.22
		local steps = math.max(3, math.floor(seconds * 45))
		for i = 1, steps do
			if not root.Parent then return end
			-- Амплитуда затухает к концу, иначе тряска обрывается на полпути.
			local decay = 1 - i / steps
			local offset = Vector3.new(
				(math.random() - 0.5) * 2 * amplitude * decay,
				(math.random() - 0.5) * 2 * amplitude * decay,
				(math.random() - 0.5) * 2 * amplitude * decay
			)
			crystal:SetAttribute("ShakeOffset", offset)
			task.wait(seconds / steps)
		end
		crystal:SetAttribute("ShakeOffset", nil)
	end)
end

function MineService:_ejectOre(player, expedition)
	if expeditions[player] ~= expedition then return end
	local plot = expedition.Plot
	local cart = expedition.Cart
	local tier = expedition.Tier
	local tierInfo = Config.MineTiers[math.clamp(tier, 1, #Config.MineTiers)]
	local yieldCount = tierInfo.OreYield
	-- v10: ⛏ MINE RUSH (микротранзакция) — x2 руды за раскопку, пока есть заряды.
	local profile = Services.DataService:GetGeodeData(player)
	if profile and (tonumber(profile.MineRushCharges) or 0) > 0 then
		profile.MineRushCharges -= 1
		player:SetAttribute("MineRushCharges", profile.MineRushCharges)
		yieldCount *= 2
	end
	-- v18: амулет DOUBLE HAUL из сундука — x2 руды, пока действует.
	if Services.BuffService and Services.BuffService:GetBonus(player, "DoubleHaul") > 0 then
		yieldCount *= 2
	end
	-- v10: 🚀 ракетная кирка — вполовину меньше руды.
	if Services.CombatService and Services.CombatService.IsRocketActive and Services.CombatService:IsRocketActive(player) then
		yieldCount = math.max(1, math.floor(yieldCount * (Config.RocketPickaxe.MineYieldMultiplier or 0.5)))
	end
	local cfg = Config.MineExpedition

	-- РУДА ВЫЛЕТАЕТ ИЗ ENTRY (по прямому запросу). plot.MineEntryCFrame
	-- теперь берётся из детали ENTRY в первую очередь (см. PlotService:
	-- _buildMine — она приоритетнее и абстрактного маркера, и дефолта от
	-- Zone), поэтому здесь достаточно ссылки на неё. plot.MineDoorPart —
	-- ОТДЕЛЬНАЯ, необязательная деталь (VFX неонового свечения двери, см.
	-- _pulseMineDoor/_applyDoorRarity); если билдер такую деталь положил,
	-- она может стоять не там же, где вход, и тогда именно её позиция
	-- побеждает — считаем это осознанным выбором builder'а, а не
	-- дефолтом.
	local doorPos = (plot.MineDoorPart and plot.MineDoorPart.Position) or plot.MineEntryCFrame.Position
	-- РУДА ПАДАЕТ У ВЫХОДА ИЗ ШАХТЫ, НО НЕ ВПРИТЫК (по прямому запросу).
	-- Раньше центр кучи был у точки спавна игрока (+10 к банку) — далеко от
	-- шахты. Теперь каждая руда ложится в секторе ПЕРЕД дверью: на
	-- расстоянии от EjectLandMinDistance до EjectLandMaxDistance от неё и
	-- не дальше EjectLandSpreadDegrees в стороны от направления "наружу".
	-- Минимальная дистанция не даёт руде упасть в саму дверь или за неё.
	--
	-- "Наружу" = среднее между направлениями на центр участка и на банк:
	-- центр участка гарантирует, что это открытое место перед шахтой, а
	-- банк — что куча лежит на стороне камеры выброса (она стоит на оси
	-- шахта → банк) и не прячется за шахтой.
	local bank = axisTarget(plot)
	local flatMask = Vector3.new(1, 0, 1)
	local function flatDir(target)
		if typeof(target) ~= "Vector3" then return nil end
		local d = (target - doorPos) * flatMask
		return d.Magnitude > 0.5 and d.Unit or nil
	end
	local toPlot = flatDir((plot.PlayerSpawnCFrame and plot.PlayerSpawnCFrame.Position) or plot.OreDropPosition)
	local toBank = flatDir(bank)
	local outward
	if toPlot and toBank and (toPlot + toBank).Magnitude > 0.2 then
		outward = (toPlot + toBank).Unit
	else
		outward = toBank or toPlot
	end
	-- v14.3: шахта смотрит на MineFacingMarker — руда летит туда же.
	if plot.MineFacingDir then
		outward = plot.MineFacingDir
	end
	if not outward then
		local look = plot.MineEntryCFrame.LookVector * flatMask
		outward = look.Magnitude > 0.1 and look.Unit or Vector3.xAxis
	end
	local landMin = cfg.EjectLandMinDistance or 10
	local landMax = math.max(landMin + 1, cfg.EjectLandMaxDistance or 22)
	local landSpread = math.rad(cfg.EjectLandSpreadDegrees or 55)
	local doorGround = Vector3.new(doorPos.X, doorPos.Y, doorPos.Z)
	-- Центр кучи — для камеры-фолбэка и спавна жеод.
	local dropCenter = doorGround + outward * ((landMin + landMax) / 2)

	-- РУДА ПАДАЕТ ПРЯМО ПЕРЕД КАМЕРОЙ (по прямому запросу — "почти
	-- буквально перед ней"). Камера выброса стоит на оси шахта → банк:
	-- eye = minePosition + dir·CameraEjectDistance + up·CameraEjectHeight
	-- (см. dollyAlongBankAxis в MineExpeditionUI). Считаем ту же точку
	-- ТЕМИ ЖЕ данными (minePosition/bankPosition, те же числа из Config),
	-- что шлём клиенту, поэтому сервер и камера совпадают без обмена по
	-- сети. Руда ложится в EjectLandCameraGap стадах перед объективом,
	-- с небольшим разбросом вбок и в глубину — вся куча в кадре, крупно.
	-- Если камера по оси не строится (ось выключена / банка нет), остаётся
	-- сектор у выхода шахты, посчитанный выше.
	local cameraFront = nil
	local mineAt = minePosition(plot)
	if cfg.EjectLandInFrontOfCamera ~= false and cfg.UseBankAxisCamera and mineAt and typeof(bank) == "Vector3" then
		local axis = (bank - mineAt) * flatMask
		if axis.Magnitude > 0.1 then
			axis = axis.Unit
			local gap = cfg.EjectLandCameraGap or 16
			-- v9: площадь кучи растёт с числом кусков — каждому нужен свой
			-- «пятачок» EjectLandMinGap, чтобы ярлыки шансов не слипались.
			local pieceGap = cfg.EjectLandMinGap or 4.5
			local neededArea = yieldCount * pieceGap * pieceGap * 1.35
			local spreadSide = math.clamp(math.sqrt(neededArea / 2), cfg.EjectLandCameraSpreadSide or 7, cfg.EjectLandMaxSpreadSide or 16)
			local spreadDepth = math.clamp(neededArea / (4 * spreadSide), cfg.EjectLandCameraSpreadDepth or 4, cfg.EjectLandMaxSpreadDepth or 9)
			local extraDepth = math.max(0, spreadDepth - (cfg.EjectLandCameraSpreadDepth or 4))
			local distanceFromMine = math.max(landMin, (cfg.CameraEjectDistance or 62) - gap - extraDepth)
			cameraFront = {
				Center = mineAt * flatMask + Vector3.yAxis * mineAt.Y + axis * distanceFromMine,
				Axis = axis,
				Side = Vector3.yAxis:Cross(axis).Unit,
				SpreadSide = spreadSide,
				SpreadDepth = spreadDepth,
			}
			dropCenter = cameraFront.Center
		end
	end
	dropCenter = Vector3.new(dropCenter.X, groundYAt(dropCenter, plot), dropCenter.Z)

	-- МИНИ-ИГРА ПРОЙДЕНА — только теперь меняется вход шахты, по редкости с
	-- учётом ВСЕЙ накопленной удачи. Перед подменой шахту мгновенно
	-- возвращаем к базовому масштабу: деталь, вставленная в раздутую
	-- модель, после оседания ужалась бы вместе с ней и осталась бы меньше
	-- положенного. Скачок в один кадр тут же перекрывает взрыв ниже.
	self:_snapMineToBase(plot)
	local okEntry, entryErr = pcall(function()
		self:_restoreEntryMesh(plot)
		self:_applyEntryMesh(plot, Config.AverageRarityForTier(tier, expedition.LuckBonus))
	end)
	if not okEntry then
		warn("[MineService] Entry swap failed:", entryErr)
	end

	-- ШАХТА ЛОПАЕТСЯ, камера уходит ЕЩЁ дальше в сторону банка и
	-- опускается почти на землю — руда полетит прямо над ней.
	self:_burstMine(plot)
	stateRemote:FireClient(player, "Eject", {
		DropPosition = dropCenter,
		CameraMarker = cameraMarkerFor(plot, "Eject"),
		MinePosition = minePosition(plot),
		BankPosition = axisTarget(plot),
		DiveSeconds = cfg.CameraDiveSeconds,
	})

	-- РОЛЛ ПАЧКИ. Сначала честный шанс жеоды на каждый "слот" (сохраняет
	-- старую пити/тутор-систему GeodeService без изменений — жеоды по-
	-- прежнему летят СРАЗУ в тележку, это отдельная, не переделываемая
	-- сейчас механика), иначе — руда через Config.RollOreForTier.
	local rolled = {} -- { {Crystal=, OreInfo=}, ... }
	for _ = 1, yieldCount do
		local wentToGeode = false
		if cart and Services.GeodeService then
			local ok, spawned = pcall(function()
				return Services.GeodeService:TrySpawnForMine(player, cart, tier, dropCenter, false)
			end)
			wentToGeode = ok and spawned == true
		end
		if not wentToGeode then
			local crystal = Services.CrystalService:Create(tier, player, expedition.LuckBonus)
			local oreInfo = Config.OreByKey[crystal:GetAttribute("CrystalOre")] or tierInfo
			table.insert(rolled, { Crystal = crystal, OreInfo = oreInfo })
		end
	end

	if #rolled == 0 then
		-- Всё ушло в жеоды (статистически почти невозможно, но не должно
		-- подвесить сцену) — просто выходим из шахты чуть погодя.
		task.delay(0.4, function()
			if expeditions[player] == expedition then self:_finishExpedition(player, expedition) end
		end)
		return
	end

	-- Самая редкая руда — первая/центральная (см. ТЗ). Index — позиция в
	-- Config.OreChain (18 руд подряд, чем правее — тем реже/дороже),
	-- этого достаточно, чтобы сравнить "какая руда редчей".
	table.sort(rolled, function(a, b) return a.OreInfo.Index > b.OreInfo.Index end)
	-- v3 (Ж2): редкость — по слоту руды в ЭТОЙ пещере, а не статическая.
	self:_applyDoorRarity(plot, rolled[1].Crystal:GetAttribute("CrystalRarity") or Config.OreRarityFor(rolled[1].OreInfo.Key, tier))
	self:_markAsGigantic(rolled[1].Crystal)

	local groundOwnerId = player.UserId

	-- v9: СЛУЧАЙНЫЙ РАЗБРОС С МИНИМАЛЬНОЙ ДИСТАНЦИЕЙ. Каждая новая точка
	-- выбирается из нескольких случайных кандидатов так, чтобы до уже занятых
	-- было не меньше EjectLandMinGap (по глубине кадра дистанция «весит»
	-- меньше — ярлыки, стоящие друг за другом, на экране перекрываются).
	local usedLand = {}
	local minGap = cfg.EjectLandMinGap or 4.5
	local depthWeight = cfg.EjectLandDepthWeight or 0.7
	local function spacing(a, b)
		local d = (a - b) * flatMask
		if cameraFront then
			local side = d:Dot(cameraFront.Side)
			local depth = d:Dot(cameraFront.Axis) * depthWeight
			return math.sqrt(side * side + depth * depth)
		end
		return d.Magnitude
	end
	local function pickLand(sample)
		local best, bestScore = nil, -1
		for _ = 1, 40 do
			local candidate = sample()
			local nearest = math.huge
			for _, used in usedLand do
				nearest = math.min(nearest, spacing(candidate, used))
			end
			if nearest >= minGap then
				best = candidate
				break
			end
			if nearest > bestScore then
				best, bestScore = candidate, nearest
			end
		end
		table.insert(usedLand, best)
		return best
	end

	-- Физически выбрасывает ОДИН кусок руды — заспойлеренный (чёрный),
	-- летит по дуге, приземляется. Возвращает crystal/shell, чтобы позже
	-- (см. revealPiece) его раскрыть.
	local function ejectPiece(entry)
		local crystal = entry.Crystal
		if not expeditions[player] then
			if crystal.Parent then crystal:Destroy() end -- экспедиция отменена — не оставляем висящий кусок
			return nil
		end
		crystal.Parent = groundOreFolder
		crystal:SetAttribute("GroundOreOwner", groundOwnerId)
		crystal:SetAttribute("Landed", false)
		-- v14.3: руда из шахты — подбирается только вблизи и только после
		-- того, как игрок сам сдвинулся с места выхода (см. InventoryService).
		crystal:SetAttribute("MineDrop", true)
		-- КРУПНЕЕ НА ВРЕМЯ КАТСЦЕНЫ: камера стоит далеко, и кусок обычного
		-- размера был бы в кадре парой пикселей. Уменьшится обратно, когда
		-- катсцена кончится (см. _finishExpedition).
		scaleCrystal(crystal, cfg.CutsceneOreScale or 2.6)
		crystal:SetAttribute("CutsceneScaled", true)
		applySpoilerLook(crystal)
		local mystery = attachMysteryGui(crystal)

		-- КРИТИЧНЫЙ ФИКС. Ценник НИКТО не выключал: BillboardGui создаётся
		-- с Enabled = true и стоит с AlwaysOnTop, поэтому название руды,
		-- шанс "1/N" и цена были видны СКВОЗЬ чёрную скорлупу всё время
		-- полёта — спойлер не работал вообще, а revealPiece "раскрывал"
		-- уже показанное. Гасим ценник на время полёта; заодно начинает
		-- работать GiganticBadge, который подписан на смену этого самого
		-- Enabled (см. _markAsGigantic) и раньше не срабатывал никогда,
		-- потому что значение не менялось.
		local priceGui = crystal:FindFirstChild("PriceGui", true)
		if priceGui then priceGui.Enabled = false end
		attachCutsceneChance(crystal, priceGui)

		-- Точка в секторе перед дверью (см. расчёт outward выше). sqrt —
		-- равномерная плотность по площади, иначе куча жалась бы к ближнему краю.
		local landXZ = pickLand(function()
			if cameraFront then
				-- Прямо перед объективом: вбок ±SpreadSide, в глубину ±SpreadDepth.
				return cameraFront.Center
					+ cameraFront.Side * ((math.random() * 2 - 1) * cameraFront.SpreadSide)
					+ cameraFront.Axis * ((math.random() * 2 - 1) * cameraFront.SpreadDepth)
			end
			local turn = (math.random() * 2 - 1) * landSpread
			local dir = CFrame.fromAxisAngle(Vector3.yAxis, turn):VectorToWorldSpace(outward)
			local distance = math.sqrt(landMin * landMin + math.random() * (landMax * landMax - landMin * landMin))
			return doorGround + dir * distance
		end)
		local landPos = Vector3.new(landXZ.X, groundYAt(landXZ, plot), landXZ.Z)
		-- ПЛЕВОК ДЕЛАЕТ ШАХТА, А НЕ РУДА. Раньше здесь раздувалась сама руда
		-- (spitPop), а шахта стояла неподвижно — это и выглядело "не так".
		-- Теперь шахта поджимается, пока кусок приседает в двери, и резко
		-- раздувается ровно в момент вылета (кривая подогнана под flyOre).
		self:_spitMine(plot)
		flyOre(crystal, Vector3.new(doorPos.X, doorPos.Y, doorPos.Z), landPos, cfg.EjectFlightSeconds, cfg.EjectArcHeight, cfg.EjectOreSpitPop == true)
		return { Crystal = crystal, Mystery = mystery }
	end

	-- Раскрывает ОДИН уже выброшенный кусок (снимает чёрную "скорлупу" +
	-- показывает билборд шанса). По прямому запросу редкость каждого
	-- куска проявляется только тогда, когда вылетает СЛЕДУЮЩИЙ — см. цикл
	-- ниже, а не по фиксированной задержке после своего же приземления.
	local function revealPiece(released)
		if not released then return end
		local crystal = released.Crystal
		if not (crystal and crystal.Parent) then return end

		-- Настоящий цвет читаем ДО восстановления: restoreSpoilerLook
		-- стирает сохранённые атрибуты, а вспышке ниже нужен именно
		-- родной цвет руды, а не чёрный, который ещё держится на part.Color
		-- первые кадры твина.
		local okRoot, root = pcall(CrystalUtil.GetRoot, crystal)
		local trueColor = okRoot and root and root:GetAttribute("SpoilerColor") or nil

		-- 0) Кусок вздрагивает, прежде чем показать, чем он оказался.
		shakeCrystal(crystal)

		-- 1) Руда получает НАЗАД свой материал и цвет (чёрный неон → родной).
		restoreSpoilerLook(crystal, cfg.RevealTweenSeconds)

		-- 2) "???" схлопываются, на их месте появляется настоящая надпись.
		--    Атрибут Revealed — сигнал клиенту проиграть схлопывание; сам
		--    объект убираем ЧУТЬ ПОЗЖЕ, иначе анимация не успеет пройти.
		local mystery = released.Mystery
		if mystery and mystery.Parent then
			mystery:SetAttribute("Revealed", true)
			Debris:AddItem(mystery, 0.4)
		end

		-- 3) Ценник (имя + шанс 1/N + цена) включается ровно в этот момент,
		--    вместе с ним — GiganticBadge, если кусок был помечен.
		local priceGui = crystal:FindFirstChild("PriceGui", true)
		if priceGui then
			-- НАДПИСЬ МЕРЦАЛА ДВАЖДЫ. Здесь стояло priceGui.Enabled = true —
			-- надпись появлялась МГНОВЕННО и без анимации (появление №1), а
			-- затем клиент, заметив JustRevealed своим опросом раз в
			-- полсекунды, сжимал её в точку и проигрывал "поп" (появление
			-- №2). Отсюда и "один раз просто так, другой с анимацией".
			--
			-- Теперь сервер только ставит МЕТКУ, а включает надпись сам
			-- клиент — одновременно с анимацией, одним появлением.
			priceGui:SetAttribute("JustRevealed", true)

			-- Страховка: если по какой-то причине клиент метку не
			-- отработал, через пару секунд показываем надпись как есть.
			-- Лучше без анимации, чем совсем без цены.
			task.delay(2, function()
				if priceGui.Parent and priceGui:GetAttribute("JustRevealed") == true then
					priceGui:SetAttribute("JustRevealed", nil)
					priceGui.Enabled = true
				end
			end)
		end

		-- 4) Короткая вспышка света на раскрытии — читается как "оно
		--    зажглось", и одновременно подсвечивает настоящий цвет руды.
		if okRoot and root then
			local flash = Instance.new("PointLight")
			flash.Name = "RevealFlash"
			flash.Brightness = 4
			flash.Range = 10
			flash.Color = trueColor or root.Color
			flash.Parent = root
			TweenService:Create(flash, TweenInfo.new(cfg.RevealTweenSeconds + 0.2), { Brightness = 0, Range = 0 }):Play()
			Debris:AddItem(flash, cfg.RevealTweenSeconds + 0.3)
		end
	end

	-- ОЧЕРЁДНОСТЬ (см. ТЗ): 1 центральная руда → пара сбоку → дальше
	-- волнами по WaveSize штук. Собираем именно ТАК, батчами — дальше идём
	-- по ним последовательно одной корутиной (см. ниже), а не десятком
	-- параллельных task.delay с накопленными смещениями — по прямому
	-- запросу таймингов ("по таймингам беда") тут нужна предсказуемая,
	-- ЛИНЕЙНАЯ очередь, а не куча независимо тикающих таймеров.
	local batches = { { rolled[1] } }
	local index = 2
	local pair = {}
	for _ = 1, 2 do
		if rolled[index] then
			table.insert(pair, rolled[index])
			index += 1
		end
	end
	if #pair > 0 then table.insert(batches, pair) end
	while rolled[index] do
		local wave = {}
		for _ = 1, cfg.WaveSize do
			if rolled[index] then
				table.insert(wave, rolled[index])
				index += 1
			end
		end
		table.insert(batches, wave)
	end

	-- ГЛАВНАЯ ПОСЛЕДОВАТЕЛЬНОСТЬ: выбрасываем батч N → ждём
	-- BatchGapSeconds (по ТЗ — "две секунды ожидание") → ОДНОВременно
	-- раскрываем батч N (редкость проявляется, когда вылетает следующий)
	-- И выбрасываем батч N+1 → и так далее. Последний батч раскрывается
	-- сам, без "следующего", через небольшую паузу после приземления.
	task.spawn(function()
		-- Сначала даём шахте доиграть "взрыв": первый плевок оборвал бы его
		-- (у масштаба один писатель, новая анимация отменяет старую).
		task.wait((cfg.MineBurstSeconds or 0.45) + 0.1)

		-- Руды внутри одного батча вылетают НЕ разом, а друг за другом с
		-- шагом MineSpitStaggerSeconds — иначе три руды давали бы один
		-- общий плевок, а по запросу шахта выплёвывает КАЖДУЮ руду.
		local stagger = cfg.MineSpitStaggerSeconds or 0.5
		local pending = nil -- предыдущий батч, ещё не раскрытый — {released1, released2, ...}
		for batchIndex, batch in batches do
			if expeditions[player] ~= expedition then return end
			local released = {}
			local batchStartedAt = os.clock()
			for pieceIndex, entry in batch do
				if pieceIndex > 1 then
					task.wait(stagger)
					if expeditions[player] ~= expedition then
						if entry.Crystal and entry.Crystal.Parent then entry.Crystal:Destroy() end
						continue
					end
				end
				local releasedPiece = ejectPiece(entry)
				if releasedPiece then table.insert(released, releasedPiece) end
				-- Предыдущий батч раскрывается вместе с ПЕРВОЙ рудой
				-- следующего — как и раньше ("редкость проявляется, когда
				-- вылетает следующая").
				if pieceIndex == 1 and pending then
					for _, pendingPiece in pending do
						revealPiece(pendingPiece)
					end
					pending = nil
				end
			end
			pending = released
			if batches[batchIndex + 1] then
				-- Пауза считается от НАЧАЛА батча, чтобы разнос руд внутри
				-- батча не растягивал общий ритм катсцены.
				local left = cfg.BatchGapSeconds - (os.clock() - batchStartedAt)
				task.wait(math.max(stagger, left))
			end
		end
		-- Последний батч — раскрываем сам, дав ему долететь и немного
		-- отлежаться на земле, раз следующего батча, который бы его
		-- раскрыл, больше нет.
		task.wait(cfg.EjectFlightSeconds + cfg.RevealDelaySeconds)
		if pending then
			for _, releasedPiece in pending do
				revealPiece(releasedPiece)
			end
		end
		task.wait(cfg.RevealTweenSeconds + 0.4)
		if expeditions[player] == expedition then
			self:_finishExpedition(player, expedition)
		end
	end)
end

--------------------------------------------------------------------------------
-- ШАГ 5: ВЫХОД
--------------------------------------------------------------------------------
-- Плавно возвращает всю лежащую руду этого игрока к нормальному размеру
-- после катсцены. Масштаб гоним шагами: ScaleTo/Size не твинятся.
function MineService:_shrinkGroundOre(player)
	local cfg = Config.MineExpedition
	local folder = workspace:FindFirstChild("MineGroundOre")
	if not folder then return end
	local from = cfg.CutsceneOreScale or 2.6
	local seconds = cfg.CutsceneOreShrinkSeconds or 0.5

	local pieces = {}
	for _, crystal in folder:GetChildren() do
		if crystal:GetAttribute("GroundOreOwner") == player.UserId
			and crystal:GetAttribute("CutsceneScaled") == true then
			crystal:SetAttribute("CutsceneScaled", nil)
			-- v9: крупный шанс нужен только в катсцене.
			local bigChance = crystal:FindFirstChild("CutsceneChance", true)
			if bigChance then bigChance:Destroy() end
			-- Пока садится к обычному размеру — не подбирается (см.
			-- InventoryService/CartService): иначе усадка и полёт в рюкзак
			-- писали бы размер одновременно.
			crystal:SetAttribute("ShrinkingBack", true)
			table.insert(pieces, crystal)
		end
	end
	if #pieces == 0 then return end

	task.spawn(function()
		local startedAt = os.clock()
		while true do
			local alpha = math.clamp((os.clock() - startedAt) / seconds, 0, 1)
			local scale = from + (1 - from) * alpha
			for _, crystal in pieces do
				if crystal.Parent then scaleCrystal(crystal, scale) end
			end
			if alpha >= 1 then break end
			task.wait()
		end
		for _, crystal in pieces do
			if crystal.Parent then
				scaleCrystal(crystal, 1)
				crystal:SetAttribute("ShrinkingBack", nil)
			end
		end
	end)
end

function MineService:_finishExpedition(player, expedition)
	if expeditions[player] ~= expedition then return end
	player:SetAttribute("MineExpeditionActive", false)
	-- Шаг обучения «сходи в шахту» закрывается ЗДЕСЬ, а не на третьем
	-- попадании по дуге: пока идёт катсцена выхода, игрок не управляет
	-- персонажем, и показывать ему следующее задание раньше времени
	-- значило бы выдать цель, к которой он физически не может двинуться.
	if Services.TutorialService then
		pcall(function() Services.TutorialService:Count(player, "ExpeditionsDone", 1) end)
	end
	local plot = expedition.Plot

	local cfg = Config.MineExpedition

	-- Вход возвращается к авторскому мешу: подменённый жил только на
	-- время катсцены. Масштаб — строго базовый в момент возврата (иначе
	-- авторский ENTRY встанет в модель другого размера).
	self:_snapMineToBase(plot)
	self:_restoreEntryMesh(plot)
	-- КАТСЦЕНА КОНЧИЛАСЬ — руда садится обратно к нормальному размеру.
	self:_shrinkGroundOre(player)

	-- v14.4: ВЫХОД — ЗЕРКАЛО ЗАХОДА. Оба появляются в середине ENTRY и
	-- идут ТЕМ ЖЕ путём в обратную сторону: шахтёр первым — на своё место,
	-- клон следом — ровно туда, где невидимо стоял настоящий игрок. Там
	-- клон исчезает, а игрок проявляется — подмены не видно.
	local forward = self:_minePath(plot) -- …, MinePathN, середина ENTRY
	local entryPos = forward[#forward]
	local back = {}
	for index = #forward - 1, 1, -1 do
		table.insert(back, forward[index])
	end
	local speed = math.max(1, cfg.ActorWalkSpeed or 9)
	local followDelay = (cfg.ActorFollowGap or 3.2) / speed

	local function pathSeconds(from, points)
		local total, prev = 0, from
		for _, point in points do
			total += ((point - prev) * Vector3.new(1, 0, 1)).Magnitude
			prev = point
		end
		return total / speed
	end
	local function faceFirst(from, points)
		local dir = ((points[1] or from) - from) * Vector3.new(1, 0, 1)
		return dir.Magnitude > 0.05 and CFrame.lookAt(Vector3.zero, dir.Unit) or CFrame.identity
	end

	-- Шахтёр выходит первым.
	local record = npcRecords[player]
	local npcSeconds = 0
	if record and record.Npc and record.Npc.PrimaryPart and plot.MinerCFrame then
		local npc = record.Npc
		local npcPoints = table.clone(back)
		table.insert(npcPoints, plot.MinerCFrame.Position)
		local start = Vector3.new(entryPos.X, npc:GetPivot().Position.Y, entryPos.Z)
		local correction = facingCorrection(npc, npc.PrimaryPart)
		npc:SetAttribute("_MoveToken", nil)
		npc:PivotTo(CFrame.new(start) * faceFirst(start, npcPoints) * CFrame.Angles(0, correction, 0))
		setModelVisible(npc, true)
		local walkTrack = nil
		if tonumber(cfg.WalkAnimationId) and cfg.WalkAnimationId ~= 0 then
			walkTrack = playAnim(npc, "rbxassetid://" .. tostring(cfg.WalkAnimationId), true)
		end
		npcSeconds = walkPath(npc, npcPoints, correction, function()
			if walkTrack then pcall(function() walkTrack:Stop(0.1) end) end
			self:RepositionNpc(player, plot)
		end)
	end

	-- Клон — следом, к точке, где стоит настоящий игрок.
	local actorSeconds = 0
	local actor = expedition.Actor
	if actor and actor.Parent and expedition.OriginCFrame then
		local actorPoints = table.clone(back)
		table.insert(actorPoints, expedition.OriginCFrame.Position)
		local start = Vector3.new(entryPos.X, expedition.OriginCFrame.Position.Y, entryPos.Z)
		actorSeconds = pathSeconds(start, actorPoints)
		task.delay(followDelay, function()
			if not actor.Parent then return end
			actor:PivotTo(CFrame.new(start) * faceFirst(start, actorPoints))
			setModelVisible(actor, true)
			local walkTrack = playAnim(actor, actor:GetAttribute("_WalkAnim"), true)
			walkPath(actor, actorPoints, 0, function()
				if walkTrack then pcall(function() walkTrack:Stop(0.1) end) end
				if actor.Parent then actor:PivotTo(expedition.OriginCFrame) end
			end)
		end)
	end

	local doneAt = math.max(npcSeconds, (actorSeconds > 0) and (followDelay + actorSeconds) or 0) + 0.15
	task.delay(doneAt, function()
		if expedition.Actor then
			expedition.Actor:Destroy()
			expedition.Actor = nil
		end
		-- Пока игрок отсюда не отошёл, руда из шахты к нему не летит
		-- (см. InventoryService, подбор).
		if expedition.OriginCFrame then
			player:SetAttribute("MineExitPos", expedition.OriginCFrame.Position)
		end
		self:_restoreControl(player, expedition)
		stateRemote:FireClient(player, "Done", {})
		if expeditions[player] == expedition then
			expeditions[player] = nil
		end
		local current = npcRecords[player]
		if current and current.Prompt then current.Prompt.Enabled = true end
		if current and current.Npc then setModelVisible(current.Npc, true) end
	end)
end

--------------------------------------------------------------------------------
-- СОВМЕСТИМОСТЬ СО СТАРЫМ ВЫЗЫВАЮЩИМ КОДОМ
--
-- Main.server.lua дёргает StartLoop/StopLoop на споне/выходе персонажа —
-- имена оставлены как есть, чтобы не трогать Main.server.lua. Смысл
-- поменялся: постоянного авто-тика добычи больше нет (см. шапку файла),
-- StartLoop теперь просто заводит лёгкий фоновый таймер для доставки уже
-- КУПЛЕННЫХ Robux-заполнений тележки (раньше это дёргалось из тика
-- добычи). MonetizationService:TryDeliverPendingCartFills всё ещё
-- вызывает GetActiveCart/RefreshActiveCart — см. их новый (упрощённый)
-- смысл ниже.
--------------------------------------------------------------------------------
function MineService:StartLoop(player)
	if pendingFillLoops[player] then return end
	pendingFillLoops[player] = task.spawn(function()
		while player.Parent do
			task.wait(3)
			local ok, err = pcall(function()
				Services.MonetizationService:TryDeliverPendingCartFills(player)
			end)
			if not ok then warn("[MineService] Pending fill delivery failed:", err) end
			-- Атрибуты MineActive/MiningCartTier/MiningCartFill/
			-- MiningCartCapacity/TutorialCartLoad раньше обновлялись КАЖДЫЙ
			-- тик старого авто-цикла добычи (см. setMiningState в v1).
			-- Держим их живыми и здесь — от них зависит HUD-подсказка
			-- "залить тележку за Robux" и часть клиентского UI в
			-- CustomCartUI.client.lua (см. grep по этим именам).
			-- ВАЖНО/TODO: сама механика туториала ("первая тележка = гайд,
			-- гарантированная геода на N-й капле, авто-финансирование при
			-- достижении RequiredCartLoad") была ЗАШИТА ВНУТРЬ старого
			-- бесконечного тика (см. Config.Tutorial, DataService:
			-- GetNextBranchStep(player, "Mine")) — она НЕ перенесена 1:1
			-- в новую экспедицию и требует отдельного прохода поверх
			-- MineService:_ejectOre (гарантированная геода уже частично
			-- работает через GeodeService:TrySpawnForMine forceTutorialGeode,
			-- но авто-финансирование первого апгрейда — ещё нет).
			local ok2, err2 = pcall(function()
				local cart = Services.CartService:GetHeldCart(player) or Services.CartService:GetOwnedCart(player)
				local active = cart ~= nil and #cart.Crystals < cart.Capacity
				player:SetAttribute("MineActive", active)
				if cart then
					player:SetAttribute("MiningCartTier", cart.Tier)
					player:SetAttribute("MiningCartFill", #cart.Crystals)
					player:SetAttribute("MiningCartCapacity", cart.Capacity)
					local geodeCount = Services.CartService.GetGeodeCount and Services.CartService:GetGeodeCount(cart) or 0
					player:SetAttribute("TutorialCartLoad", #cart.Crystals + geodeCount)
				end
			end)
			if not ok2 then warn("[MineService] Attribute sync failed:", err2) end
		end
	end)
end

function MineService:StopLoop(player)
	local thread = pendingFillLoops[player]
	if thread then
		pendingFillLoops[player] = nil
		pcall(task.cancel, thread)
	end
	self:_abortCutscene(player)
	expeditions[player] = nil
	if player.Parent then
		player:SetAttribute("_MineGlideToken", nil)
	end
end

-- Раньше означало "тележка сейчас стоит в зоне шахты и в неё капает
-- руда". Авто-капели больше нет — MonetizationService использует эту
-- функцию только чтобы понять, В КАКУЮ тележку доставить уже купленное
-- Robux-заполнение, для этого достаточно "любая тележка игрока с местом".
function MineService:GetActiveCart(player)
	local cart = Services.CartService:GetHeldCart(player) or Services.CartService:GetOwnedCart(player)
	if cart and #cart.Crystals < cart.Capacity then
		return cart
	end
	return nil
end

function MineService:RefreshActiveCart(player)
	-- Пустая функция ради обратной совместимости (см. MonetizationService
	-- :TryDeliverPendingCartFills) — v2 ничего не обязано пересчитывать
	-- здесь, GetActiveCart каждый раз считает состояние заново.
end

return MineService
