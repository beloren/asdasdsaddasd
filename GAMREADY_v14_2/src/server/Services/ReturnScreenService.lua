--------------------------------------------------------------------------------
-- ReturnScreenService
--
-- Отвечает за ДВЕ связанные вещи, которые для игрока являются одним событием
-- «пока меня не было»:
--
--   1) ОФЛАЙН-ШАХТА. v20.9: по умолчанию (Config.OfflineCart.Mode = "Money")
--      игрок просто получает немного денег за время отсутствия — см.
--      GrantOfflineMoney. Старая схема ниже («Ore»): тележка на парковке участка встречает игрока уже
--      наполненной рудой — ровно настолько, насколько успела бы её набить
--      шахта за время отсутствия (на пониженной скорости, см.
--      Config.OfflineCart).
--
--   2) ЭКРАН ВОЗВРАЩЕНИЯ. Один экран со всеми офлайн-итогами сразу: руда в
--      тележке, накопленное в сейфе, состояние стрика. Раньше это были
--      разрозненные всплывашки в разное время, которые игрок не связывал
--      между собой.
--
-- ГЛАВНОЕ ЭКОНОМИЧЕСКОЕ РЕШЕНИЕ, которое стоит понимать, прежде чем что-то
-- здесь менять: офлайн даёт РУДУ, А НЕ ДЕНЬГИ.
--
-- Деньги игрок всё равно зарабатывает сам — руду нужно довезти до банка и не
-- потерять её по дороге в PvP, а комбо-множитель тележки считается только при
-- реальной доставке (см. CartService.comboMultiplier). Поэтому эта механика
-- физически не может работать вторым сейфом: она выдаёт сырьё, а не результат,
-- и её потолок — вместимость одной тележки, то есть 1.4-4.3 минуты игры
-- (Capacity × SpawnInterval). Для сравнения: один ребёрт стоит 17-110 полных
-- тележек. Сдвинуть баланс этим невозможно даже теоретически.
--
-- Если захочется сделать щедрее — поднимай Config.OfflineCart.Rate, а НЕ
-- потолок: потолок и есть то, что защищает экономику.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local ReturnScreenService = {}
local Services
local remote

-- Накопитель на игрока: разные сервисы досылают сюда свои строки в разное
-- время (сейф — из PassiveIncomeService во время настройки участка, руда —
-- отсюда же после спавна тележки), а показываем всё ОДНИМ пакетом в конце.
local pending = {}

-- v12: [player] = { Amount, MineTier } — офлайн-руда, посчитанная на заходе,
-- но ещё не выданная: тележки в этот момент не существует (она лежит
-- упаковкой). Высыпается в неё сразу после постановки.
local pendingOfflineFill = {}
local offlineFx = {} -- [player] = офлайн-деньги, ждущие «прилёта» монет по COLLECT

function ReturnScreenService:Init(services)
	Services = services
	remote = ReplicatedStorage.Shared:FindFirstChild("ReturnScreenEvent")
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = "ReturnScreenEvent"
		remote.Parent = ReplicatedStorage.Shared
	end
	-- v20.31: игрок нажал COLLECT на экране возвращения — офлайн-деньги (уже
	-- на счёте) «прилетают» обычной процедурой, как при сборе в банке:
	-- 3D-монетки у игрока (BankService:SpawnCoinBurst) + «+$X» (MoneyGainEvent).
	remote.OnServerEvent:Connect(function(player, action)
		if action ~= "Collected" then return end
		local amount = offlineFx[player]
		offlineFx[player] = nil
		if not (amount and amount > 0) then return end
		if Services.BankService and Services.BankService.SpawnCoinBurst then
			pcall(Services.BankService.SpawnCoinBurst, Services.BankService, player, nil, 6)
		end
		local moneyGain = ReplicatedStorage.Shared:FindFirstChild("MoneyGainEvent")
		if moneyGain then moneyGain:FireClient(player, amount) end
	end)
	Players.PlayerRemoving:Connect(function(player) offlineFx[player] = nil end)
end

local function bucket(player)
	local entry = pending[player]
	if not entry then
		entry = { Safe = 0, CartOre = 0, CartValue = 0, OfflineMoney = 0 }
		pending[player] = entry
	end
	return entry
end

-- Вызывается из PassiveIncomeService:SetupPlot после Accrue.
function ReturnScreenService:ReportSafe(player, amount)
	amount = tonumber(amount) or 0
	if amount <= 0 then return end
	bucket(player).Safe += amount
end

--------------------------------------------------------------------------------
-- ОФЛАЙН-ЗАПОЛНЕНИЕ ТЕЛЕЖКИ
--
-- Вызывается из Main СРАЗУ ПОСЛЕ CartService:SpawnCartFor — тележка к этому
-- моменту уже стоит на своей парковке (plot.CartSpawnCFrame), пустая. Мы её
-- не создаём и не двигаем, только наполняем: место спавна, физика, ХП и всё
-- остальное остаются ровно теми же, что и у обычной тележки.
--------------------------------------------------------------------------------
-- v20.9: офлайн-доход деньгами. Доля активного дохода в минуту за время
-- отсутствия (Config.OfflineCart.MoneyRate, потолок MaxMoneySeconds).
function ReturnScreenService:GrantOfflineMoney(player)
	local cfg = Config.OfflineCart
	local offline = tonumber(player:GetAttribute("OfflineSeconds")) or 0
	if offline < (tonumber(cfg.MinOfflineSeconds) or 0) then return end
	if not Services.CartService:IsCartUnlocked(player) then return end -- ещё не начал играть по-настоящему
	offline = math.min(offline, tonumber(cfg.MaxMoneySeconds) or offline)
	local tiers = Services.DataService:GetTiers(player)
	local perMinute = Config.IncomePerMinute(tiers.Mine, tiers.Cart)
	local ok, multiplier = pcall(Services.DataService.GetCrystalMultiplier, Services.DataService, player)
	local money = math.floor(perMinute * (offline / 60) * (tonumber(cfg.MoneyRate) or 0) * (ok and tonumber(multiplier) or 1))
	if money <= 0 then return end
	if Services.DataService:AddMoney(player, money, nil, true) == false then return end
	bucket(player).OfflineMoney += money
end

function ReturnScreenService:FillOfflineCart(player)
	local cfg = Config.OfflineCart
	if not (cfg and cfg.Enabled) then return end
	if (cfg.Mode or "Money") == "Money" then
		return self:GrantOfflineMoney(player)
	end

	local offline = tonumber(player:GetAttribute("OfflineSeconds")) or 0
	-- Порог отсечки. Без него перезаход раз в минуту был бы выгоднее игры:
	-- вышел-зашёл — и тележка снова полная.
	if offline < (tonumber(cfg.MinOfflineSeconds) or 0) then return end
	offline = math.min(offline, tonumber(cfg.MaxOfflineSeconds) or offline)

	local data = Services.CartService:GetOwnedCart(player)

	-- ТИР РУДЫ БЕРЁТСЯ ТЕКУЩИЙ, и его НЕ НУЖНО сохранять на выход.
	-- Тир шахты меняется только через покупку апгрейда или ребёрт, а и то и
	-- другое возможно исключительно внутри игры — пока игрок офлайн, он
	-- измениться не может. Если же игрок ребёртнулся и вышел, текущий (уже
	-- сброшенный) тир — это как раз правильный ответ, а сохранённый старый
	-- выдал бы ему руду, на которую он больше не имеет права.
	local mineTier = Services.DataService:GetTiers(player).Mine

	-- Сколько кристаллов шахта успела бы выдать. Формула ровно та же, что в
	-- MineService:StartLoop (интервал / (1 + тир × бонус)), умноженная на
	-- долю офлайн-скорости — чтобы офлайн и онлайн не разъезжались при
	-- будущих правках баланса шахты.
	local speedMultiplier = 1 + mineTier * Config.Mine.SpawnSpeedBonusPerTier
	local interval = Config.Mine.SpawnInterval / speedMultiplier
	local produced = math.floor(offline / interval * (tonumber(cfg.Rate) or 0))
	if produced <= 0 then return end

	-- v12: ТЕЛЕЖКИ НА ЗАХОДЕ БОЛЬШЕ НЕТ — она появляется только тогда, когда
	-- игрок сам поставит упаковку. Поэтому офлайн-руда здесь только
	-- СЧИТАЕТСЯ и придерживается: её высыплет в тележку
	-- ApplyPendingOfflineFill в момент постановки (зовётся из
	-- CartService:PlaceCartFromPackage). Экран возвращения при этом
	-- показывается как раньше, сразу: число кусков уже известно, а цена
	-- берётся оценочно по тиру пещеры (реальная цена с мутациями посчитается
	-- при выдаче и от оценки отличается незначительно).
	if not data then
		if not Services.CartService:IsCartUnlocked(player) then
			return -- тележка ещё вообще не куплена — офлайн-шахте некуда работать
		end
		local tierInfo = Config.CartTiers[Services.DataService:GetTiers(player).Cart]
		local roomInFutureCart = tierInfo
			and math.floor(tierInfo.Capacity * math.clamp(tonumber(cfg.MaxFillPercent) or 1, 0, 1))
			or 0
		local waitingAmount = math.min(produced, roomInFutureCart)
		if waitingAmount <= 0 then return end
		pendingOfflineFill[player] = { Amount = waitingAmount, MineTier = mineTier }
		local waitingEntry = bucket(player)
		waitingEntry.CartOre += waitingAmount
		waitingEntry.CartValue += math.floor(waitingAmount
			* ((Config.MineTiers[mineTier] and Config.MineTiers[mineTier].ExpectedValue) or 0))
		return
	end

	local capacity = math.floor(data.Capacity * math.clamp(tonumber(cfg.MaxFillPercent) or 1, 0, 1))
	local amount = math.min(produced, capacity - #data.Crystals)
	if amount <= 0 then return end

	-- Переиспользуем ровно тот же путь, которым наполняет тележку платный
	-- продукт CartFill: он уже умеет откатываться целиком при любой ошибке
	-- на середине и не оставляет полузаполненную тележку.
	local ok = Services.CartService:FillInstantly(player, data, amount, mineTier)
	if not ok then return end

	-- Стоимость считаем ПОСЛЕ заполнения и по реальному содержимому, а не по
	-- прикидке: у кусков могли выпасть мутации (CrystalService:Create роллит
	-- их на каждом), и множитель ребёртов тоже уже запечён в цену.
	local value = 0
	for _, crystal in data.Crystals do
		value += tonumber(crystal:GetAttribute("CrystalValue")) or 0
	end

	local entry = bucket(player)
	entry.CartOre += amount
	entry.CartValue += value
end

-- Высыпает придержанную офлайн-руду в ТОЛЬКО ЧТО ПОСТАВЛЕННУЮ тележку.
-- Зовётся из CartService:PlaceCartFromPackage. Если игрок за сессию ставил
-- тележку несколько раз, сработает только первый — запись потребляется.
function ReturnScreenService:ApplyPendingOfflineFill(player, data)
	local waiting = pendingOfflineFill[player]
	if not (waiting and data) then return false end
	pendingOfflineFill[player] = nil
	local amount = math.min(waiting.Amount, data.Capacity - #data.Crystals)
	if amount <= 0 then return false end
	return Services.CartService:FillInstantly(player, data, amount, waiting.MineTier) == true
end

--------------------------------------------------------------------------------
-- Показ экрана. Вызывается последним шагом настройки игрока в Main.
--------------------------------------------------------------------------------
function ReturnScreenService:Present(player)
	local cfg = Config.ReturnScreen
	if not (cfg and cfg.Enabled) then pending[player] = nil; return end

	local entry = pending[player]
	if not entry then return end
	pending[player] = nil

	local offline = tonumber(player:GetAttribute("OfflineSeconds")) or 0
	if offline < (tonumber(cfg.MinOfflineSeconds) or 0) then return end
	if entry.Safe <= 0 and entry.CartOre <= 0 and (entry.OfflineMoney or 0) <= 0 then return end

	local streak, streakDeadline
	local data = Services.DataService:GetGeodeData(player)
	if data then
		streak = tonumber(data.DailyRewardStreak) or 0
		if data.DailyRewardClaimed ~= true then
			streakDeadline = 0 -- награда доступна прямо сейчас
		else
			-- Тот же расчёт, что и в QuestService:ClaimDailyReward: серия
			-- держится до конца ЗАВТРАШНИХ суток UTC, а unix-эпоха выровнена
			-- по UTC-полуночи, поэтому хватает остатка от деления.
			streakDeadline = 2 * 86400 - (os.time() % 86400)
		end
	end

	if (entry.OfflineMoney or 0) > 0 then offlineFx[player] = entry.OfflineMoney end
	local payload = {
		OfflineSeconds = offline,
		Safe = entry.Safe,
		CartOre = entry.CartOre,
		CartValue = entry.CartValue,
		OfflineMoney = entry.OfflineMoney,
		Streak = streak,
		StreakSeconds = streakDeadline,
	}

	-- ЗАДЕРЖКА ОБЯЗАТЕЛЬНА. Клиентский слушатель живёт в конце очень
	-- большого LocalScript, а FireClient НЕ ставит сообщение в очередь для
	-- ещё не подписавшегося клиента — оно просто исчезает. Ровно на этом
	-- раньше молча терялся старый тост сейфа. Плюс экран не должен налезать
	-- на концовку катсцены.
	task.delay(tonumber(cfg.ShowDelay) or 2, function()
		if player.Parent and remote then
			remote:FireClient(player, payload)
		end
	end)
end

function ReturnScreenService:CleanupPlayer(player)
	pending[player] = nil
	pendingOfflineFill[player] = nil -- игрок ушёл, не поставив тележку — придержанная руда сгорает вместе с сессией
end

return ReturnScreenService
