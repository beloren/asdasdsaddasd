--------------------------------------------------------------------------------
-- Main (единственный Script в проекте)
-- Точка входа. Собирает сервисы, задаёт порядок инициализации
-- и оркестрирует жизненный цикл игрока. Вся логика — в ModuleScript-сервисах.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Localization = require(ReplicatedStorage.Shared.Localization)
local Config = require(ReplicatedStorage.Shared.Config)
local Services = {}

local servicesFolder = script.Parent:WaitForChild("Services")

local cutsceneFinished = ReplicatedStorage.Shared:FindFirstChild("CutsceneFinished")
if not cutsceneFinished then
	cutsceneFinished = Instance.new("RemoteEvent")
	cutsceneFinished.Name = "CutsceneFinished"
	cutsceneFinished.Parent = ReplicatedStorage.Shared
end
pcall(function()
	cutsceneFinished.Sandboxed = true
end)

-- УСТАРЕВШИЕ КЛИЕНТСКИЕ СКРИПТЫ СЛАЙМА. Слайм заменён торговцем банка, но
-- Rojo не всегда удаляет из места файлы, убранные из проекта, — старые
-- SlimeHud/BankSlimeCelebration оставались в StarterPlayerScripts и падали
-- на Config.Slime (которого больше нет). Удаляем до входа игроков: скрипты
-- копируются в PlayerScripts только при подключении.
do
	local StarterPlayer = game:GetService("StarterPlayer")
	local StarterGui = game:GetService("StarterGui")
	local legacyNames = { SlimeHud = true, BankSlimeCelebration = true }
	for _, container in { StarterPlayer:FindFirstChild("StarterPlayerScripts"), StarterPlayer:FindFirstChild("StarterCharacterScripts"), StarterGui } do
		for _, instance in container and container:GetDescendants() or {} do
			if legacyNames[instance.Name] and instance:IsA("LuaSourceContainer") then
				warn("[Main] Удалён устаревший скрипт слайма:", instance:GetFullName())
				instance:Destroy()
			end
		end
	end
	local legacyService = servicesFolder:FindFirstChild("SlimeService")
	if legacyService then
		warn("[Main] Удалён устаревший SlimeService")
		legacyService:Destroy()
	end
end

for _, module in servicesFolder:GetChildren() do
	if module:IsA("ModuleScript") then
		Services[module.Name] = require(module)
	end
end

-- Явный порядок: зависимости инициализируются раньше зависящих.
local ORDER = {
	"DataService",
	"LeaderboardService",
	"NotifyService", -- всплывающие уведомления на экране — утилита без зависимостей, вызывается из многих других сервисов
	"AnnounceService", -- цветные системные сообщения в чат — тоже утилита без зависимостей
	"QuestService",
	-- ОБУЧЕНИЕ v7 (см. Config.Tutorial). ДО PlotService: тот спрашивает у
	-- него "починена ли шахта" прямо во время постройки участка
	-- (_buildMine → ApplyBrokenMineLook), то есть сервис обязан быть
	-- проинициализирован раньше. Сам он от остальных зависит только в
	-- рантайме, через Services.*, поэтому раннее место в списке безопасно.
	"TutorialService",
	"BuffService", -- временные баффы из жеод (см. ТЗ "х2 деньги/удача/скорость") — утилита без зависимостей, читается MonetizationService/CrystalService/CartService ниже
	"InventoryService", -- рюкзак/хотбар/кирки (см. Config.Inventory) — читает DataService/MonetizationService выше, CartService ниже дёргает его на подборе
	"MonetizationService", -- геймпассы/девпродукты — читают его CartService/HandCarryService/CrystalService/BankService/CombatService ниже
	"SkinService",
	"WorldService",
	"WeatherService", -- погодные ивенты (см. Config.WeatherEvents) — CrystalService/RockService ниже спрашивают у него текущие бусты мутаций
	"SwordNpcService",
	"CrystalService",
	"HandCarryService",
	"CartService",
	"GeodeService",
	"LikeRewardService", -- зависит от SkinService/GeodeService выше
	"GroupRewardService", -- та же зависимость
	"LikeGoalService", -- v16: табло целей по лайкам (ивенты читает MonetizationService в рантайме)
	"SocialOfferService", -- v16: мягкие предложения группы/избранного в удачный момент
	"MutationBookService", -- зависит от DataService выше
	"PassiveIncomeService",
	-- ДО PlotService намеренно: PassiveIncomeService:SetupPlot вызывается
	-- из PlotService:AssignPlot и уже там досылает сюда офлайн-доход сейфа,
	-- поэтому сервис обязан быть проинициализирован раньше.
	"ReturnScreenService",
	-- Острова прогрессии (см. Config.Islands) — ДО PlotService: тот зовёт
	-- IslandService:SetupPlot из AssignPlot. Сам сервис читает Geode/
	-- PassiveIncome/Inventory, они проинициализированы выше.
	"IslandService",
	"PlotService",
	"MineService",
	"GoblinService",
	"RockService",
	"BankService",
	-- Торговец банка и биржа руды (см. Config.Merchant) — ПОСЛЕ WorldService
	-- (ставится в зону банка в Start) и BankService (тот спрашивает у него
	-- курс на каждой продаже, но только в рантайме).
	"MerchantService",
	-- v14: тотемы/декор/реликвии на базе (к остальным сервисам — только в рантайме).
	"BaseDecorService",
	"UpgradeService",
	"ShopNpcService", -- НПС магазина (Robux) — как и UpgradeService, настраивается PlotService:AssignPlot на каждом участке
	"CombatService",
	"HudService",
	"RebirthService",
	"PrestigeService", -- v8: очки/перки престижа (остальные сервисы зовут его в рантайме)
	"GearService", -- v8: динамит и сундуки
}

for _, name in ORDER do
	assert(Services[name], "Отсутствует сервис: " .. name)
	Services[name]:Init(Services)
end

local function movePlayerToPlot(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local plot = Services.PlotService:GetPlot(player)
	if not root or not plot then
		return
	end

	if plot.PlayerSpawnLocation and plot.PlayerSpawnLocation.Parent then
		player.RespawnLocation = plot.PlayerSpawnLocation
	end
	local spawnCFrame = plot.PlayerSpawnCFrame or plot.Pad.CFrame
	character:PivotTo(spawnCFrame + Vector3.new(0, 3, 0))
	root.AssemblyLinearVelocity = Vector3.zero
end

local function playerIsOnOwnPlot(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local plot = Services.PlotService:GetPlot(player)
	if not (root and plot and plot.Pad) then return false end
	local localPosition = plot.Pad.CFrame:PointToObjectSpace(root.Position)
	local half = plot.Pad.Size / 2
	return math.abs(localPosition.X) <= half.X + 8
		and math.abs(localPosition.Z) <= half.Z + 8
		and localPosition.Y >= -8
		and localPosition.Y <= 80
end

local function verifyPlayerPlotSpawn(player)
	if player.Character and not playerIsOnOwnPlot(player) then
		movePlayerToPlot(player)
	end
end

local function queuePlotSpawnVerification(player)
	for _, delay in { 0, 0.15, 0.5, 1, 2, 4 } do
		task.delay(delay, function()
			if player.Parent and player:GetAttribute("CutsceneFinished") then
				verifyPlayerPlotSpawn(player)
			end
		end)
	end
end

cutsceneFinished.OnServerEvent:Connect(function(player)
	if player:GetAttribute("CutsceneFinished") then
		return
	end
	player:SetAttribute("CutsceneFinished", true)
	movePlayerToPlot(player)
	queuePlotSpawnVerification(player)
end)

--------------------------------------------------------------------------------
-- СЕРВЕРНЫЙ БЭКСТОП ДЛЯ КАТСЦЕНЫ.
--
-- До этого момента "конец катсцены" целиком зависел от клиента: он ОБЯЗАН
-- был сам вызвать cutsceneFinished:FireServer() (см. MoonAnimationTest.client.lua
-- — finishIntro/failIntro/сторожевой таймер). Если LocalScript интро вообще
-- не запустился (отключён другим скриптом, упал ДО подписки на событие,
-- эксплойтер вырубил клиентский код) или RemoteEvent потерялся — сервер
-- никогда не узнавал, что пора звать movePlayerToPlot, и игрок навсегда
-- оставался на TeleportPart (точка интро-камеры у банка), пересоздаваясь
-- там же при каждом респавне.
--
-- Этот таймер НЕ зависит от клиента вообще: спустя разумный запас времени
-- после захода сервер сам форсирует переход, если клиент так и не
-- отчитался. При штатной работе клиента он не успевает сработать —
-- cutsceneFinished.OnServerEvent выше уже выставит атрибут и отменит смысл
-- повторной работы (просто return, идемпотентно). CUTSCENE_SERVER_TIMEOUT
-- выбран с запасом над обычной длиной интро, но заметно меньше клиентского
-- ABSOLUTE_TIMEOUT (150с) — то есть это подстраховка "если клиент вообще не
-- ответил", а не гонка с его собственным сторожевым таймером.
local CUTSCENE_SERVER_TIMEOUT = 30
local function forceFinishCutsceneEventually(player)
	task.delay(CUTSCENE_SERVER_TIMEOUT, function()
		if not player.Parent then return end
		if player:GetAttribute("CutsceneFinished") then return end
		warn(("[Main] %s не подтвердил конец катсцены за %d с (клиентский скрипт не отчитался) - принудительно ставлю на участок."):format(player.Name, CUTSCENE_SERVER_TIMEOUT))
		player:SetAttribute("CutsceneFinished", true)
		movePlayerToPlot(player)
		queuePlotSpawnVerification(player)
	end)
end
for _, name in ORDER do
	local service = Services[name]
	if service.Start then
		service:Start()
	end
end

--------------------------------------------------------------------------------
-- ЖИЗНЕННЫЙ ЦИКЛ ИГРОКА
-- Спавним персонажа вручную ПОСЛЕ загрузки данных и выдачи участка.
--------------------------------------------------------------------------------

Players.CharacterAutoLoads = false

local function onPlayerAdded(player)
	local loaded, reason = Services.DataService:LoadProfile(player)
	if not loaded then
		if player.Parent and reason ~= "PlayerLeft" then
			local message = reason == "Locked"
				and "Your data is already loaded on another server. Please try again shortly."
				or "Your data could not be loaded safely. Please rejoin."
			player:Kick(Localization.Translate(player.LocaleId, message))
		end
		return
	end
	if not player.Parent then
		Services.DataService:UnloadProfile(player)
		return
	end
	Services.DataService:AwardBadge(player, Config.Badges and Config.Badges.JoinedGame)
	player:SetAttribute("CarryingCart", false)
	-- Стартуем бэкстоп-таймер сразу, как только известно, что игрок остаётся
	-- в игре — независимо от того, как пройдёт остальная настройка ниже
	-- (плот/тележка/катсцена). Если клиент за CUTSCENE_SERVER_TIMEOUT секунд
	-- так и не отчитается — сервер сам поставит игрока на участок.
	forceFinishCutsceneEventually(player)
	-- Раньше все пятнадцать вызовов ниже стояли в ОДНОМ xpcall, и любая
	-- ошибка в любом из них: (а) обрывала все оставшиеся шаги, (б) выгружала
	-- профиль, (в) кикала игрока с "Player setup failed safely".
	-- Это худший из возможных вариантов: одна некритичная ошибка (например,
	-- в косметике скина) выбрасывала игрока из игры целиком.
	--
	-- Теперь каждый шаг изолирован своим xpcall: упавший шаг логируется с
	-- полным трейсбеком и ПРОПУСКАЕТСЯ, остальные выполняются как обычно.
	-- Кика нет ни при каких обстоятельствах.
	local failedSteps = {}
	local function step(name, fn)
		local ok, err = xpcall(fn, debug.traceback)
		if not ok then
			table.insert(failedSteps, name)
			warn(("[Main] Шаг настройки '%s' упал для %s (игрок остаётся в игре):\n%s")
				:format(name, player.Name, tostring(err)))
		end
		return ok
	end

	step("LeaderboardService", function() Services.LeaderboardService:SetupPlayer(player) end)
	step("SkinService", function() Services.SkinService:SetupPlayer(player) end)

	-- Участок — единственный по-настоящему критичный шаг: без него игроку
	-- некуда спавниться, и почти всё остальное (тележка, шахта, гоблины)
	-- работает от него. Поэтому его результат проверяем отдельно, но
	-- по-прежнему БЕЗ кика.
	local plotOk = step("PlotService", function() Services.PlotService:AssignPlot(player) end)
	if plotOk and not Services.PlotService:GetPlot(player) then
		-- AssignPlot не бросает ошибку, когда свободных участков нет — он
		-- просто пишет warn и возвращает nil (см. PlotService:AssignPlot).
		-- Раньше это приводило к падению следующего же шага (SpawnCartFor на
		-- пустом участке) и, как следствие, к кику. Логируем явно.
		plotOk = false
		warn(("[Main] Игроку %s не достался участок (все %d заняты). Он останется в игре, но без базы.")
			:format(player.Name, Config.World.PlotCount))
		-- Без этого игрок без участка спавнился на СЛУЧАЙНОЙ ЧУЖОЙ БАЗЕ:
		-- RespawnLocation ему никто не назначил, а Roblox в этом случае
		-- выбирает любой Enabled+Neutral SpawnLocation в мире — то есть
		-- один из плотовых. И так после каждой смерти.
		local fallback = Services.PlotService:GetFallbackSpawn()
		if fallback and fallback.Parent then player.RespawnLocation = fallback end
	end

	if plotOk then
		-- v12: тележка БОЛЬШЕ НЕ СПАВНИТСЯ НА ЗАХОДЕ. Вместо этого сервис
		-- приводит игрока к инварианту владения: купил тележку — в рюкзаке
		-- лежит упаковка, из которой он сам её поставит, где захочет (см.
		-- CartService: SetupPlayer/_syncPackageInvariant). Старым профилям
		-- (играли до v12 и тележка у них была) флаг владения проставляется
		-- там же автоматически, покупать заново ничего не нужно.
		step("CartService", function() Services.CartService:SetupPlayer(player) end)
		-- Офлайн-руда теперь не может высыпаться прямо сейчас — тележки в
		-- мире ещё нет. Сервис считает её и придерживает до момента, когда
		-- игрок поставит тележку (см. ReturnScreenService:FillOfflineCart /
		-- ApplyPendingOfflineFill).
		step("OfflineCart", function() Services.ReturnScreenService:FillOfflineCart(player) end)
	else
		warn("[Main] Тележка не настроена: нет участка для", player.Name)
	end

	-- ПОСЛЕ участка и тележки: обучение резолвит цели шагов (шахтёр,
	-- торговец, валуны, банк) в реальные объекты на базе, а до AssignPlot
	-- их ещё не существует.
	step("TutorialService", function() Services.TutorialService:SetupPlayer(player) end)
	step("QuestService", function() Services.QuestService:SetupPlayer(player) end)
	step("MerchantService", function() Services.MerchantService:SetupPlayer(player) end)
	step("BaseDecorService", function() Services.BaseDecorService:SetupPlayer(player) end)
	step("WeatherService", function() Services.WeatherService:SyncPlayer(player) end)

	--------------------------------------------------------------------------
	-- "X ЗАШЁЛ НА СЕРВЕР" + ПЕРЕСБОРКА ДОСТУПНЫХ КВЕСТОВ.
	--
	-- Две вещи в одном месте, потому что это одно событие для игрока: часть
	-- квестов открывается только когда на сервере есть кто-то ещё (см.
	-- RequiresPlayers в Config.Quests и questBlockedByPlayerCount в
	-- QuestService). Без строки в чате новый квест появлялся бы у всех
	-- "сам собой", без объяснения. Со строкой это читается как причина и
	-- следствие — и заодно сообщает одиночке, что сервер ожил.
	--
	-- Порядок важен: сперва объявление (его должны увидеть УЖЕ игравшие),
	-- потом пересборка состояния квестов у всех, включая только что
	-- зашедшего.
	step("JoinAnnounce", function()
		local cfg = Config.JoinAnnounce
		if not (cfg and cfg.Enabled) then return end
		if #Players:GetPlayers() < (tonumber(cfg.MinPlayers) or 2) then return end
		Services.AnnounceService:Broadcast(nil, nil, {
			{ Text = player.DisplayName, Color = cfg.NameColor },
			{ Text = cfg.JoinSuffix, Color = cfg.TextColor },
		})
	end)
	step("QuestAvailability", function() Services.QuestService:RefreshAvailability() end)

	-- ПОСЛЕДНИМ шагом настройки: к этому моменту в накопителе уже лежат все
	-- офлайн-итоги (сейф — из PlotService выше, руда — из OfflineCart), и
	-- экран показывает их одним пакетом, а не четырьмя всплывашками подряд.
	step("ReturnScreen", function() Services.ReturnScreenService:Present(player) end)
	step("InventoryService", function() Services.InventoryService:SetupPlayer(player) end)
	step("CombatService", function() Services.CombatService:SetupPlayer(player) end)
	step("HandCarryService", function() Services.HandCarryService:SetupPlayer(player) end)
	step("LikeRewardService", function() Services.LikeRewardService:SetupPlayer(player) end)
	step("GroupRewardService", function() Services.GroupRewardService:SetupPlayer(player) end)
	step("SocialOfferService", function() Services.SocialOfferService:SetupPlayer(player) end)
	step("MutationBookService", function() Services.MutationBookService:SetupPlayer(player) end)
	step("MineService", function() Services.MineService:StartLoop(player) end)
	step("GoblinService", function() Services.GoblinService:SetupPlayer(player) end)
	step("RockService", function() Services.RockService:SetupPlayer(player) end)
	step("PrestigeService", function() Services.PrestigeService:SetupPlayer(player) end)
	step("GearService", function() Services.GearService:SetupPlayer(player) end)

	-- Ручной респавн (CharacterAutoLoads выключен)
	step("CharacterAdded", function()
	player.CharacterAdded:Connect(function(character)
		-- Remote players must keep their character model replicated even when
		-- StreamingEnabled unloads distant plot content. Without this, the owner
		-- still sees themselves locally while other clients see an empty plot.
		pcall(function()
			character.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		end)
		local humanoid = character:WaitForChild("Humanoid")
			local root = character:WaitForChild("HumanoidRootPart")
			if player:GetAttribute("CutsceneFinished") then
				movePlayerToPlot(player)
				-- Roblox/CoreScripts or a late-loaded spawn object can overwrite
				-- the placement after respawn, so verify it after physics too.
				queuePlotSpawnVerification(player)
			else
				local teleportPart = workspace:FindFirstChild("TeleportPart", true)
				if teleportPart and teleportPart:IsA("BasePart") then
					character:PivotTo(teleportPart.CFrame + Vector3.new(0, 3, 0))
					root.AssemblyLinearVelocity = Vector3.zero
				else
					warn("[Main] Workspace.TeleportPart was not found; keeping pre-cutscene spawn")
				end
			end
			humanoid.Died:Connect(function()
				task.delay(Players.RespawnTime, function()
				if player.Parent then player:LoadCharacterAsync() end
				end)
			end)
		end)
	end)

	-- LoadCharacter обязателен: CharacterAutoLoads выключен, и без него
	-- игрок навсегда останется без персонажа (чёрный экран). Если он упал —
	-- пробуем ещё раз через секунду, а не выкидываем игрока.
	if not step("LoadCharacter", function() player:LoadCharacterAsync() end) then
		task.delay(1, function()
			if player.Parent and not player.Character then
				local retryOk, retryErr = pcall(function() player:LoadCharacterAsync() end)
				if not retryOk then
					warn("[Main] Повторный LoadCharacter тоже упал для", player.Name, ":", retryErr)
				end
			end
		end)
	end

	step("HudService", function() Services.HudService:SetupPlayer(player) end)

	if #failedSteps > 0 then
		warn(("[Main] Настройка %s завершена с ошибками в шагах: %s. Игрок оставлен в игре.")
			:format(player.Name, table.concat(failedSteps, ", ")))
	end
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(onPlayerAdded, player)
end)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

-- ВАЖНО (исправление потери данных): раньше все вызовы ниже шли подряд,
-- БЕЗ pcall. Любая ошибка в ЛЮБОМ из них обрывала весь обработчик — и до
-- Services.DataService:UnloadProfile(player) в самом конце список просто не
-- доходил. Последствия у этого два, и оба тяжёлые:
--   1. Профиль не сохранялся — прогресс сессии терялся молча.
--   2. Сессионная блокировка в DataStore (см. DataService.LoadProfile,
--      _SessionId/_SessionExpiresAt) не снималась — игрок не мог зайти
--      обратно, пока не истечёт Config.Data.SessionLockTimeout, и видел
--      "Your data is already loaded on another server".
-- Теперь каждый шаг уборки изолирован: упавший шаг только пишет warn, а
-- уборка продолжается. UnloadProfile вынесен ОТДЕЛЬНО и вызывается всегда,
-- последним, что бы ни случилось выше.
Players.PlayerRemoving:Connect(function(player)
	local function step(name, callback)
		local ok, err = pcall(callback)
		if not ok then
			warn(("[Main] Уборка %s для %s упала (продолжаю остальные): %s"):format(name, player.Name, tostring(err)))
		end
	end

	step("LeaderboardService", function() Services.LeaderboardService:CleanupPlayer(player) end)
	step("ReturnScreenService", function() Services.ReturnScreenService:CleanupPlayer(player) end)
	step("MineService", function() Services.MineService:StopLoop(player) end)
	-- Состав сервера изменился в другую сторону: если игроков снова стало
	-- меньше, чем требует активный PvP/социальный квест, его нужно убрать с
	-- панели, а не оставлять висеть невыполнимым. Отложено на кадр, потому
	-- что в момент PlayerRemoving уходящий ещё числится в Players:GetPlayers()
	-- и счётчик был бы на единицу больше реального.
	step("QuestAvailability", function()
		task.defer(function()
			pcall(function() Services.QuestService:RefreshAvailability() end)
		end)
	end)
	step("CombatService", function() Services.CombatService:CleanupPlayer(player) end)
	step("HandCarryService", function() Services.HandCarryService:CleanupPlayer(player) end)
	step("CartService", function() Services.CartService:CleanupPlayer(player) end)
	step("UpgradeService", function() Services.UpgradeService:CleanupPlayer(player) end)
	step("ShopNpcService", function() Services.ShopNpcService:CleanupPlayer(player) end)
	step("SwordNpcService", function() Services.SwordNpcService:CleanupPlayer(player) end)
	step("RebirthService", function() Services.RebirthService:CleanupPlayer(player) end)
	step("QuestService", function() Services.QuestService:CleanupPlayer(player) end)
	step("SkinService", function() Services.SkinService:CleanupPlayer(player) end)
	step("GeodeService", function() Services.GeodeService:CleanupPlayer(player) end)
	step("RockService", function() Services.RockService:CleanupPlayer(player) end)
	step("PrestigeService", function() Services.PrestigeService:CleanupPlayer(player) end)
	step("GearService", function() Services.GearService:CleanupPlayer(player) end)
	step("PassiveIncomeService", function() Services.PassiveIncomeService:CleanupPlayer(player) end)
	step("IslandService", function() Services.IslandService:CleanupPlayer(player) end)
	step("PlotService", function() Services.PlotService:ReleasePlot(player) end)
	step("HudService", function() Services.HudService:CleanupPlayer(player) end)

	-- НЕ в pcall-обёртке step: это единственный шаг, ошибку которого важно
	-- увидеть целиком (он и сам внутри защищён ретраями, см. DataService).
	Services.DataService:UnloadProfile(player)
end)
