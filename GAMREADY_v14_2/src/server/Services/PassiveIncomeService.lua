local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)
local CollectionKey = require(ReplicatedStorage.Shared.CollectionKey)
local OreIncome = require(ReplicatedStorage.Shared.OreIncome)
local MutationVisuals = require(ReplicatedStorage.Shared.MutationVisuals)
local Sfx = require(ReplicatedStorage.Shared.Sfx)
local DropTables = require(ReplicatedStorage.Shared.DropTables)

local PassiveIncomeService = {}
local Services
local remote
local moneyGainRemote
local displays = {}
local lastInstallRequest = {}

-- Доход установленной на подиуме руды, $/мин.
--
-- ВСЯ ФОРМУЛА ПЕРЕЕХАЛА В src/shared/OreIncome.lua — там же и подробное
-- обоснование нового баланса. Здесь осталось только достать ключ ячейки и
-- уровень: доход теперь зависит ещё и от ТИРОВ САМОГО ИГРОКА (шахта задаёт
-- цену руды, тележка — вместимость), поэтому функции нужен player, а не
-- только его профиль.
local function incomePerMinute(player, data)
	local key = data.InstalledGeodeOre
	local entry = data.GeodeCollection[key]
	if not entry then return 0 end
	return OreIncome.PerMinuteForPlayer(player, key, entry.Level)
end

function PassiveIncomeService:Init(services)
	if not ReplicatedStorage.Shared:FindFirstChild("EssenceFx") then
		local fx = Instance.new("RemoteEvent")
		fx.Name = "EssenceFx"
		fx.Parent = ReplicatedStorage.Shared
	end
	Services = services
	remote = ReplicatedStorage.Shared:FindFirstChild("GeodeRequest")
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = "GeodeRequest"
		remote.Parent = ReplicatedStorage.Shared
	end
	moneyGainRemote = ReplicatedStorage.Shared:FindFirstChild("MoneyGainEvent") or Instance.new("RemoteEvent")
	moneyGainRemote.Name = "MoneyGainEvent"
	moneyGainRemote.Parent = ReplicatedStorage.Shared
	remote.OnServerEvent:Connect(function(player, action, value)
		if action == "InstallOre" then self:Install(player, value)
		elseif action == "RemoveOre" then self:Install(player, "")
		elseif action == "ExtractOre" then self:Extract(player, value)
		elseif action == "DeleteOre" then self:Delete(player, value)
		elseif action == "CollectSafe" then self:Collect(player) end
	end)
end

function PassiveIncomeService:Extract(player, oreId)
	-- КАЖДЫЙ отказ обязан закончиться SendState — клиент (GeodeUI,
	-- кнопка "TAKE IN HANDS") уменьшает счётчик копий и перерисовывает
	-- коллекцию СРАЗУ, не дожидаясь ответа сервера. Раньше половина веток
	-- здесь просто делала `return false` молча: сервер оставлял кристалл на
	-- месте, а в интерфейсе он пропадал — и расходился с реальностью до
	-- следующего случайного обновления. Install ниже так и сделан, тут
	-- просто забыли.
	local function reject()
		Services.GeodeService:SendState(player)
		return false
	end
	if typeof(oreId) ~= "string" or player:GetAttribute("CarryingCrystal") ~= "" then return reject() end
	local data = Services.DataService:GetGeodeData(player)
	local entry = data and data.GeodeCollection[oreId]
	if not entry or entry.Copies <= 0 or not Services.RockService then return reject() end
	if not Services.GeodeService:TryBeginTransaction(player) then return reject() end
	-- Снимок ДО изменений, чтобы откат возвращал ровно прежнее состояние
	-- (как это уже сделано в Delete ниже).
	local snapshot = { Copies = entry.Copies, Level = entry.Level, Installed = data.InstalledGeodeOre }
	entry.Copies -= 1
	if entry.Copies <= 0 then
		data.GeodeCollection[oreId] = nil
		if data.InstalledGeodeOre == oreId then data.InstalledGeodeOre = "" end
	else
		local level = 1
		for candidate, required in Config.Geodes.DuplicateCopiesPerLevel do
			if entry.Copies >= required then level = candidate else break end
		end
		entry.Level = math.min(level, Config.Geodes.MaxOreLevel)
	end
	-- В руки уходит БАЗОВАЯ руда плюс её мутации: ключ ячейки RockService не
	-- поймёт (он работает с oreId), а мутации нужны, чтобы взятый в руки
	-- кристалл выглядел так же, как лежал на подиуме, и вернулся в ту же
	-- ячейку при обратной сдаче.
	local extractedOreId, extractedMutations = CollectionKey.Parse(oreId)
	local ok = Services.RockService:CarryCrystal(
		player, extractedOreId,
		#extractedMutations > 0 and table.concat(extractedMutations, ",") or nil,
		true
	)
	if ok and Services.DataService:SaveProfile(player) then
		Services.GeodeService:EndTransaction(player)
		Services.GeodeService:SendState(player)
		return true
	end
	if ok then Services.RockService:CancelCarrying(player) end
	-- Откат по снимку. Раньше здесь стояла пара условий, которые при
	-- последней копии восстанавливали запись коллекции НОВОЙ таблицей, но
	-- проверяли счётчик по старой (у неё Copies уже 0) — из-за чего
	-- InstalledGeodeOre так и оставался пустым. То есть неудачная попытка
	-- "взять в руки" последнюю копию установленной руды молча снимала её с
	-- подиума и останавливала пассивный доход. Второе условие вдобавок
	-- могло установить на подиум руду, которой там до этого не было.
	data.GeodeCollection[oreId] = { Copies = snapshot.Copies, Level = snapshot.Level }
	data.InstalledGeodeOre = snapshot.Installed
	self:UpdateDisplay(player)
	Services.GeodeService:EndTransaction(player)
	Services.GeodeService:SendState(player)
	return false
end

-- Полностью удаляет запись из коллекции (ВСЕ копии сразу), а не убирает по
-- одной копии за нажатие — простое "удалить", без промежуточного состояния
-- "осталось ещё N копий", которое было не нужно и только путало.
function PassiveIncomeService:Delete(player, oreId)
	-- Как и в Extract: клиент удаляет карточку из коллекции сразу по нажатию
	-- "YES", поэтому любой отказ сервера обязан прислать корректирующий
	-- SendState — иначе кристалл продолжает существовать в данных, но игрок
	-- его больше не видит.
	local function reject()
		Services.GeodeService:SendState(player)
		return false
	end
	if typeof(oreId) ~= "string" then return reject() end
	local data = Services.DataService:GetGeodeData(player)
	local entry = data and data.GeodeCollection[oreId]
	if not entry or not Services.GeodeService:TryBeginTransaction(player) then return reject() end
	local snapshot = { Entry = entry, Installed = data.InstalledGeodeOre }
	data.GeodeCollection[oreId] = nil
	if data.InstalledGeodeOre == oreId then data.InstalledGeodeOre = "" end
	if Services.DataService:SaveProfile(player) then
		-- ВАЖНО: UpdateDisplay — то, что реально уничтожает/пересобирает
		-- физическую 3D-модель руды НА ПОДИУМЕ (см. Install ниже, он его
		-- уже вызывал). Без этого вызова данные корректно обнулялись
		-- (GeodeCollection/InstalledGeodeOre), а сама модель на подиуме
		-- продолжала висеть в мире как ни в чём не бывало — удалённый
		-- кристалл выглядел так, будто он никуда не делся.
		self:UpdateDisplay(player)
		Services.GeodeService:EndTransaction(player)
		Services.GeodeService:SendState(player)
		return true
	end
	data.GeodeCollection[oreId] = snapshot.Entry
	data.InstalledGeodeOre = snapshot.Installed
	self:UpdateDisplay(player)
	Services.GeodeService:EndTransaction(player)
	Services.GeodeService:SendState(player)
	return false
end

function PassiveIncomeService:Start()
	-- Интервал был жёстко зашит как 10 сек. Теперь берётся из конфига
	-- (Config.Geodes.SafeTimerRefresh), потому что этот же тик рисует ЖИВОЙ
	-- обратный отсчёт на табличке сейфа: раз в 10 секунд таймер заметно
	-- «прыгает» через десяток секунд вместо того, чтобы идти.
	--
	-- Дороже это почти не стоит: Accrue — арифметика над числом в профиле,
	-- UpdateDisplay при неизменной руде только переписывает текст двух
	-- лейблов (пересборка модели руды на подиуме защищена проверками
	-- DisplayedOreId/DisplayedOreLevel и здесь не срабатывает).
	local interval = math.max(1, tonumber(Config.Geodes.SafeTimerRefresh) or 5)
	task.spawn(function()
		while true do
			task.wait(interval)
			for player in displays do
				local ok, err = pcall(function()
					if not Services.GeodeService:IsBusy(player) then
						self:Accrue(player)
						self:UpdateDisplay(player)
					end
				end)
				if not ok then
					warn("[PassiveIncomeService] Tick failed for", player.Name, ":", err)
				end
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- ПОТОЛОК СЕЙФА (см. развёрнутое обоснование в Config.Geodes.SafeCapPercentOfRebirth).
--
-- Возвращает потолок баланса сейфа В ОБЫЧНЫХ ЧИСЛАХ (не BigNum): сам
-- GeodeSafeBalance — это float в профиле, и приводить его к BigNum ради
-- одного сравнения смысла нет. Цена ребёрта при этом BigNum, потому что в
-- лейте она уже не влезает в double осмысленно — поэтому умножение делаем в
-- BigNum, и только потом опускаемся в число.
--
-- nil означает «потолка нет» — либо он выключен в конфиге (0/отрицательный),
-- либо цену ребёрта почему-то не удалось посчитать. Отсутствие потолка
-- безопаснее, чем случайный нулевой потолок: во втором случае сейф молча
-- перестал бы копить вообще.
--------------------------------------------------------------------------------
-- rate — доход в $/мин (см. incomePerMinute выше), нужен для целевого
-- времени заполнения. Необязательный: без него функция работает как раньше
-- (только защитный % от ребёрта) — это оставлено ради обратной
-- совместимости, если кто-то вызовет GetSafeCap без него из другого места.
function PassiveIncomeService:GetSafeCap(player, rate)
	-- Потолок №1: доход × 60 × целевые часы. Это то, что даёт игроку
	-- ПРЕДСКАЗУЕМОЕ "полный сейф через 5 часов" независимо от тира — см.
	-- Config.Geodes.SafeCapTargetHours.
	local targetHours = tonumber(Config.Geodes.SafeCapTargetHours) or 0
	local byTime
	if targetHours > 0 and rate and rate > 0 then
		byTime = rate * 60 * targetHours
	end

	-- Потолок №2: старый защитный % от цены следующего ребёрта — не даёт
	-- лейту одной выплатой перекрывать целый ребёрт (см. развёрнутое
	-- обоснование в Config.Geodes.SafeCapPercentOfRebirth).
	local byRebirth
	local share = tonumber(Config.Geodes.SafeCapPercentOfRebirth) or 0
	if share > 0 then
		local ok, cost = pcall(function()
			return Services.DataService:GetRebirthCost(player)
		end)
		if ok and cost ~= nil then
			if typeof(cost) == "table" and cost.toNumberClamped then
				byRebirth = (cost * share):toNumberClamped(0, Config.Economy.MaxCurrency)
			else
				byRebirth = (tonumber(cost) or 0) * share
			end
			if not byRebirth or byRebirth ~= byRebirth or byRebirth <= 0 then byRebirth = nil end -- NaN-guard
		end
	end

	-- ПОТОЛОК №3: «сколько это полных рейсов» (см.
	-- Config.Geodes.SafeCapTripEquivalent — там подробно, зачем он нужен
	-- в дополнение к двум предыдущим).
	--
	-- Считаем стоимость ОДНОГО полного рейса игрока прямо сейчас:
	-- вместимость его тележки × цена руды его шахты. Комбо-множитель
	-- намеренно НЕ учитываем — он зависит от того, как игрок реально возит
	-- груз, а нам нужна стабильная опорная величина (та же логика, что и в
	-- OreIncome.HalfCartValue, см. комментарий там).
	local byTrips
	local tripLimit = tonumber(Config.Geodes.SafeCapTripEquivalent) or 0
	if tripLimit > 0 then
		-- HalfCartValue — половина рейса, поэтому ×2 даёт полный.
		local fullTrip = OreIncome.HalfCartValue(
			player:GetAttribute("MineTier"),
			player:GetAttribute("CartTier")
		) * 2
		if fullTrip > 0 then
			byTrips = fullTrip * tripLimit
		end
	end

	-- Берём МЕНЬШИЙ из посчитавшихся потолков. Если ни один не посчитался
	-- (доход нулевой и % от ребёрта выключен/не посчитался) — потолка нет.
	local capped
	for _, candidate in { byTime, byRebirth, byTrips } do
		if candidate and candidate > 0 then
			capped = capped and math.min(capped, candidate) or candidate
		end
	end
	if not capped or capped <= 0 then return nil end
	return math.min(capped, Config.Economy.MaxCurrency)
end

-- v4: сколько ещё влезет в сейф до потолка (для продукта Fill the Safe).
-- nil — кристалла на подиуме нет или потолок не считается.
function PassiveIncomeService:GetSafeRoom(player)
	local data = Services.DataService:GetGeodeData(player)
	if not data then return nil end
	self:Accrue(player, true)
	local rate = incomePerMinute(player, data)
	if rate <= 0 then return nil end
	local watermarkRate = math.max(tonumber(data.GeodeSafeCapRateWatermark) or 0, rate)
	data.GeodeSafeCapRateWatermark = watermarkRate
	local cap = self:GetSafeCap(player, watermarkRate)
	if not cap then return nil end
	return math.max(0, math.floor(cap - (tonumber(data.GeodeSafeBalance) or 0)))
end

function PassiveIncomeService:Accrue(player, force)
	if not force and Services.GeodeService:IsBusy(player) then return 0 end
	local data = Services.DataService:GetGeodeData(player)
	if not data then return 0 end
	local now = os.time()
	local last = tonumber(data.GeodeLastCalculatedAt) or 0
	if last <= 0 or last > now then
		data.GeodeLastCalculatedAt = now
		return 0
	end
	local rate = incomePerMinute(player, data)
	local elapsed = math.min(now - last, Config.Geodes.OfflineCapSeconds)
	local before = data.GeodeSafeBalance
	if rate > 0 and elapsed > 0 then
		local grown = before + elapsed * rate / 60
		-- ПОТОЛОК СЧИТАЕТСЯ ПО "ПИКОВОЙ" СТАВКЕ ЭТОГО ЦИКЛА НАКОПЛЕНИЯ
		-- (GeodeSafeCapRateWatermark), А НЕ ПО ТЕКУЩЕЙ.
		--
		-- ЗАЧЕМ: потолок = ставка × 60 × SafeCapTargetHours (см. GetSafeCap).
		-- Если руду на подиуме на время сменили на более слабую (тест,
		-- случайный клик, временная нехватка кристалла нужного тира) —
		-- потолок, посчитанный по ТЕКУЩЕЙ ставке, мгновенно проседает НИЖЕ
		-- уже накопленного баланса. Сам баланс при этом не срезается (см.
		-- комментарий про "потолок применяется только вверх" ниже), но
		-- расти дальше он перестаёт — то есть сейф выглядит "уже полным",
		-- хотя игрок не добрал до суммы, которую честно обещал более
		-- сильный кристалл. watermark запоминает МАКСИМАЛЬНУЮ ставку,
		-- которая была на подиуме с момента последнего опустошения сейфа
		-- (см. сброс в Collect), и потолок считается по ней — понижение
		-- руды больше не может задним числом урезать уже идущий отсчёт.
		local watermarkRate = math.max(tonumber(data.GeodeSafeCapRateWatermark) or 0, rate)
		data.GeodeSafeCapRateWatermark = watermarkRate
		-- ПОТОЛОК ПРИМЕНЯЕТСЯ ТОЛЬКО ВВЕРХ. Если баланс УЖЕ выше потолка
		-- (игрок накопил до ребаланса, либо только что сделал ребёрт и цена
		-- следующего скакнула вниз относительно накопленного), мы его НЕ
		-- срезаем — отнимать у игрока уже начисленное нельзя, это худший
		-- вид «баланса». Просто перестаём добавлять сверху.
		local cap = self:GetSafeCap(player, watermarkRate)
		if cap and grown > cap then
			grown = math.max(before, cap)
		end
		data.GeodeSafeBalance = math.min(Config.Economy.MaxCurrency, grown)
	end
	data.GeodeLastCalculatedAt = now
	return data.GeodeSafeBalance - before
end

--------------------------------------------------------------------------------
-- Сколько секунд осталось до заполнения сейфа. Нужен и табличке на самом
-- сейфе, и экрану возвращения.
--   nil   — потолка нет либо руда на подиуме не установлена (копить нечем);
--   0     — уже полон, накопление остановлено.
--------------------------------------------------------------------------------
function PassiveIncomeService:SecondsUntilFull(player)
	local data = Services.DataService:GetGeodeData(player)
	if not data then return nil end
	local rate = incomePerMinute(player, data)
	if rate <= 0 then return nil end
	-- Потолок — по той же "пиковой" ставке цикла, что и в Accrue (см. там
	-- подробное обоснование), иначе табличка над сейфом и реальное
	-- накопление разошлись бы после смены руды на подиуме.
	local watermarkRate = math.max(tonumber(data.GeodeSafeCapRateWatermark) or 0, rate)
	local cap = self:GetSafeCap(player, watermarkRate)
	if not cap then return nil end
	local remaining = cap - (tonumber(data.GeodeSafeBalance) or 0)
	if remaining <= 0 then return 0 end
	-- А вот ВРЕМЯ ДОСЧИТЫВАНИЯ — по ТЕКУЩЕЙ ставке (сколько реально капает
	-- прямо сейчас), а не по watermark: иначе после понижения руды таймер
	-- занижал бы оставшееся время, обещая скорость, которой уже нет.
	return remaining / (rate / 60)
end

-- "5h 12m" / "12m 30s" / "45s" — компактный формат для таблички над сейфом.
function PassiveIncomeService:FormatDuration(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	if hours > 0 then return ("%dh %02dm"):format(hours, minutes) end
	if minutes > 0 then return ("%dm %02ds"):format(minutes, seconds % 60) end
	return ("%ds"):format(seconds)
end

function PassiveIncomeService:Install(player, oreId)
	if oreId ~= "" and Services.IslandService and not Services.IslandService:Owns(player, "Income") then
		Services.NotifyService:Show(player, "Unlock the Income Island at the Island Keeper to install crystals!", { Icon = "Quest" })
		Services.GeodeService:SendState(player, "PodiumState")
		return false
	end
	local data = Services.DataService:GetGeodeData(player)
	if not data or typeof(oreId) ~= "string" or (oreId ~= "" and not data.GeodeCollection[oreId]) then
		Services.GeodeService:SendState(player, "PodiumState")
		return false
	end
	-- Гейт прежнего гайда (ставить руду на подиум только после шага
	-- «открой жеоду») снят вместе с самим шагом — в обучении v7 его нет.
	local now = os.clock()
	local cooldown = math.max(0.1, tonumber(Config.Geodes.CrystalSwitchCooldown) or 0.6)
	if now - (lastInstallRequest[player] or 0) < cooldown then
		Services.GeodeService:SendState(player, "PodiumState")
		return false
	end
	lastInstallRequest[player] = now
	if data.InstalledGeodeOre == oreId then
		if oreId ~= "" and player:GetAttribute("NeedsTutorial") == true
			and player:GetAttribute("TutorialGeodeOpened") == true then
			player:SetAttribute("TutorialOreInstalled", true)
		end
		Services.GeodeService:SendState(player, "PodiumState")
		return true
	end
	if not Services.GeodeService:TryBeginTransaction(player) then
		Services.GeodeService:SendState(player, "PodiumState")
		return false
	end
	self:Accrue(player, true) -- old ore earns up to the exact replacement moment
	local previousOre = data.InstalledGeodeOre
	local previousTime = data.GeodeLastCalculatedAt
	data.InstalledGeodeOre = oreId
	data.GeodeLastCalculatedAt = os.time()
	if not Services.DataService:SaveProfile(player) then
		data.InstalledGeodeOre = previousOre
		data.GeodeLastCalculatedAt = previousTime
		Services.NotifyService:Show(player, "Podium change failed safely. Try again.", { Icon = "Error" })
		self:UpdateDisplay(player)
		Services.GeodeService:EndTransaction(player)
		Services.GeodeService:SendState(player, "PodiumState")
		return false
	end
	if oreId ~= "" then player:SetAttribute("TutorialOreInstalled", true) end
	self:UpdateDisplay(player)
	Services.GeodeService:EndTransaction(player)
	Services.GeodeService:SendState(player, "PodiumState")
	return true
end

function PassiveIncomeService:Collect(player)
	if Services.IslandService and not Services.IslandService:Owns(player, "Income") then return false end
	if not Services.GeodeService:TryBeginTransaction(player) then return false end
	local data = Services.DataService:GetGeodeData(player)
	if not data then Services.GeodeService:EndTransaction(player); return false end
	self:Accrue(player, true)
	local amount = math.floor(data.GeodeSafeBalance)
	if amount <= 0 then Services.GeodeService:EndTransaction(player); return false end

	-- БОНУС ЗА ПОЛНЫЙ СЕЙФ (см. Config.Geodes.SafeFullBonusMultiplier).
	-- Забор РОВНО когда сейф упёрся в потолок (а не в процессе накопления)
	-- получает надбавку — это и есть "через 5 часов много денег": разница
	-- между зайти на 10 минут пораньше и дождаться полного сейфа реальна и
	-- ощутима, а не просто одна и та же сумма в любой момент после потолка.
	--
	-- Потолок здесь считается ПО ТОЙ ЖЕ "пиковой" ставке (watermark), что и
	-- в Accrue/SecondsUntilFull, а НЕ по сырой текущей ставке — иначе если
	-- игрок сменил руду на более слабую прямо перед сбором, бонус мог бы не
	-- сработать (новый заниженный потолок "меньше" уже нако­пленного) или
	-- сработать неправильно относительно того, что реально капало.
	-- self:Accrue(player, true) выше уже обновил watermark на актуальный.
	local rate = incomePerMinute(player, data)
	local watermarkRate = math.max(tonumber(data.GeodeSafeCapRateWatermark) or 0, rate)
	local cap = self:GetSafeCap(player, watermarkRate)
	local isFull = cap and amount >= math.floor(cap)
	local bonusMultiplier = tonumber(Config.Geodes.SafeFullBonusMultiplier) or 1
	if isFull and bonusMultiplier > 1 then
		amount = math.floor(amount * bonusMultiplier)
	end

	local previousSafe = data.GeodeSafeBalance
	local previousWatermark = data.GeodeSafeCapRateWatermark
	data.GeodeSafeBalance -= math.min(previousSafe, amount)
	-- Новый цикл накопления начинается с чистого watermark'а — если сейф
	-- реально опустошили, прошлая "пиковая" ставка больше ни на что не
	-- влияет (иначе разово поставленный сильный кристалл держал бы потолок
	-- завышенным вечно, даже после того, как его давно сняли с подиума).
	data.GeodeSafeCapRateWatermark = 0
	-- Монетки вылетают ИЗ СЕЙФА (см. Config.CoinFx/BankService:SpawnCoinBurst),
	-- а не у ног игрока — реально оттуда только что забрали деньги.
	local display = displays[player]
	local safePosition = display and display.Safe and display.Safe.Parent and display.Safe:GetPivot().Position
	Services.DataService:AddMoney(player, amount, safePosition)
	if not Services.DataService:SaveProfile(player) then
		data.GeodeSafeBalance = previousSafe
		data.GeodeSafeCapRateWatermark = previousWatermark
		Services.DataService:AddMoney(player, -amount)
		Services.NotifyService:Show(player, "Safe collection failed safely. Try again.", { Icon = "Error" })
		Services.GeodeService:EndTransaction(player)
		return false
	end
	Services.GeodeService:EndTransaction(player)
	-- Отдельно от кнопки "GOT IT" в гайде (см. CustomCartUI.client.lua) —
	-- если игрок РЕАЛЬНО собрал деньги из сейфа, это тоже засчитывает шаг
	-- гайда, не только явный клик по кнопке.
	player:SetAttribute("TutorialSafeCollected", true)
	local display = displays[player]
	Sfx.play("SafeCollect", display and display.Safe)
	if Services.QuestService then Services.QuestService:RecordMetric(player, "SafeCollected", amount) end
	if moneyGainRemote then moneyGainRemote:FireClient(player, amount) end
	Services.NotifyService:Show(player, ("COLLECTED $%s FROM SAFE"):format(NumberFormat.abbreviate(amount)), { Icon = "Safe" })
	self:UpdateDisplay(player)
	Services.GeodeService:SendState(player)
	return true
end

local function billboard(part, offset, worldSized)
	local gui
	if part:IsA("BillboardGui") and part.Name == "StatusGui" then
		gui = part
	else
		for _, descendant in part:GetDescendants() do
			if descendant:IsA("BillboardGui") and descendant.Name == "StatusGui" then
				gui = descendant
				break
			end
		end
	end
	local label = gui and gui:FindFirstChildWhichIsA("TextLabel", true)
	local created = false
	if not (gui and gui:IsA("BillboardGui") and label) then
		created = true
		gui = Instance.new("BillboardGui")
		gui.Name = "StatusGui"
		local anchor = part:IsA("Model") and (part.PrimaryPart or part:FindFirstChild("Root", true)) or part
		gui.Parent = anchor or part
		label = Instance.new("TextLabel")
		label.Name = "Status"
		label.Size = UDim2.fromScale(1, 1)
		label.Parent = gui
	end
	-- Size — ВСЕГДА фиксированный (чистый Offset, БЕЗ доли Scale), даже
	-- если это уже существующий авторский StatusGui из ассета сейфа, а не
	-- только что созданный — по прямому запросу "не скейлилось в
	-- зависимости от расстояния камеры". UDim2 с долей Scale (например,
	-- {0.1, 0, 0.1, 0}) у BillboardGui.Size реально растёт/уменьшается
	-- вместе с расстоянием до камеры — это НЕ баг Roblox, а его штатное
	-- поведение для Scale-компонента, но именно такого поведения тут не
	-- нужно ни для одной надписи над сейфом. Шрифт/цвет/позицию у чужого
	-- ассета всё ещё не трогаем — форсируем именно и только Size.
	gui.Size = worldSized and UDim2.fromOffset(680, 264) or UDim2.fromOffset(280, 58)
	if created then
		local anchor = part:IsA("Model") and (part.PrimaryPart or part:FindFirstChild("Root", true)) or part
		gui.StudsOffset = Vector3.new(0, offset, 0)
		gui.AlwaysOnTop = true
		-- Сумма над СЕЙФОМ (worldSized=false) видна только вблизи — по
		-- прямому запросу снижено с 80 до 35 студов. Табличка на подиуме
		-- (worldSized=true, крупный мировой размер) не трогаем — запрос
		-- был именно про надпись над сейфом.
		gui.MaxDistance = worldSized and 80 or 35
		if anchor and anchor:IsA("BasePart") then gui.Adornee = anchor end
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextScaled = true
		label.TextWrapped = true
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextYAlignment = Enum.TextYAlignment.Center
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.TextStrokeTransparency = 0
		label.Font = Enum.Font.Arcade
	end
	return label, gui, created
end

local function rootPart(object)
	if object:IsA("BasePart") then return object end
	if object:IsA("Model") then
		local root = object.PrimaryPart or object:FindFirstChild("Root", true)
		if root and root:IsA("BasePart") then return root end
	end
	return object:FindFirstChildWhichIsA("BasePart", true)
end

local function bounds(object)
	if object:IsA("Model") then return object:GetBoundingBox() end
	return object.CFrame, object.Size
end

local function bottomY(object)
	local objectCFrame, objectSize = bounds(object)
	local halfHeight = math.abs(objectCFrame.RightVector.Y) * objectSize.X / 2
		+ math.abs(objectCFrame.UpVector.Y) * objectSize.Y / 2
		+ math.abs(objectCFrame.LookVector.Y) * objectSize.Z / 2
	return objectCFrame.Position.Y - halfHeight
end

local function moveY(object, amount)
	if object:IsA("Model") then
		object:PivotTo(object:GetPivot() + Vector3.new(0, amount, 0))
	else
		object.CFrame += Vector3.new(0, amount, 0)
	end
end

local function pivotRootTo(model, targetCFrame)
	local root = rootPart(model)
	if not root then
		model:PivotTo(targetCFrame)
		return
	end
	local rootToPivot = root.CFrame:ToObjectSpace(model:GetPivot())
	model:PivotTo(targetCFrame * rootToPivot)
end

local function placeOnPlot(object, targetCFrame, plotPad)
	if object:IsA("Model") then
		pivotRootTo(object, targetCFrame)
	else
		object.CFrame = targetCFrame
	end
	local boundsCFrame, boundsSize = bounds(object)
	local up = plotPad.CFrame.UpVector
	local halfHeight = math.abs(boundsCFrame.RightVector:Dot(up)) * boundsSize.X / 2
		+ math.abs(boundsCFrame.UpVector:Dot(up)) * boundsSize.Y / 2
		+ math.abs(boundsCFrame.LookVector:Dot(up)) * boundsSize.Z / 2
	local objectBottom = boundsCFrame.Position:Dot(up) - halfHeight
	local plotTop = plotPad.Position:Dot(up) + plotPad.Size.Y / 2
	local correction = up * (plotTop - objectBottom)
	if object:IsA("Model") then
		object:PivotTo(object:GetPivot() + correction)
	else
		object.CFrame += correction
	end
end

local function podiumTopCFrame(podium)
	local placement = podium:FindFirstChild("OrePlacement", true)
	if placement and placement:IsA("BasePart") then return placement.CFrame end
	local boundsCFrame, boundsSize = bounds(podium)
	local root = rootPart(podium)
	if not root then return boundsCFrame * CFrame.new(0, boundsSize.Y / 2, 0) end
	local up = root.CFrame.UpVector
	local topOffset = (boundsCFrame.Position - root.Position):Dot(up) + boundsSize.Y / 2
	return root.CFrame * CFrame.new(0, topOffset, 0)
end

local function setAnchored(object, anchored)
	if object:IsA("BasePart") then object.Anchored = anchored end
	for _, descendant in object:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = anchored
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
end

local function findPrompt(object, name)
	local prompt = object:FindFirstChild(name, true)
	return prompt and prompt:IsA("ProximityPrompt") and prompt or object:FindFirstChildWhichIsA("ProximityPrompt", true)
end

function PassiveIncomeService:SetupPlot(player, plot)
	local profile = Services.DataService:GetGeodeData(player)
	player:SetAttribute("TutorialOreInstalled", player:GetAttribute("NeedsTutorial") ~= true
		and profile and profile.InstalledGeodeOre ~= "" or false)
	-- ПОДИУМ И СЕЙФ ТЕПЕРЬ СТОЯТ НА ОСТРОВЕ ДОХОДА (см. Config.Islands /
	-- IslandService:BuildStructures). Офлайн-доход при этом считается как
	-- раньше — он зависит только от установленного кристалла.
	if Services.IslandService and Config.Islands and Config.Islands.Enabled then
		local earned = self:Accrue(player)
		if earned >= 1 and Services.ReturnScreenService then
			Services.ReturnScreenService:ReportSafe(player, earned)
		end
		return
	end
	self:BuildStructures(player, plot.GeodePodiumCFrame, plot.GeodeSafeCFrame, plot.Pad, plot.Content)
	local earned = self:Accrue(player)
	if earned >= 1 and Services.ReturnScreenService then
		Services.ReturnScreenService:ReportSafe(player, earned)
	end
	self:UpdateDisplay(player)
end

-- Строит подиум кристалла и сейф. groundPart — горизонтальная деталь, на
-- верхнюю грань которой их ставим (участок или площадка острова).
-- Возвращает podium, safe.
-- safeGroundPart — своя "земля" для сейфа (на острове подиум и сейф могут
-- стоять на разной высоте, у каждого свой маркер). Не задана — та же.
function PassiveIncomeService:BuildStructures(player, podiumCFrame, safeCFrame, groundPart, parent, safeGroundPart)
	local plot = { GeodePodiumCFrame = podiumCFrame, GeodeSafeCFrame = safeCFrame, Pad = groundPart, SafePad = safeGroundPart or groundPart, Content = parent }
	local podium = PlaceholderFactory.GeodePodium()
	local customPodium = podium ~= nil
	podium = podium or Instance.new("Part")
	podium.Name = "GeodePodium"
	if not customPodium then
		podium.Size = Vector3.new(6, 1.5, 6)
		podium.Color = Color3.fromRGB(75, 70, 100)
		podium.Material = Enum.Material.Marble
	end
	placeOnPlot(podium, plot.GeodePodiumCFrame, plot.Pad)
	setAnchored(podium, true)
	podium.Parent = plot.Content
	local podiumPrompt = findPrompt(podium, "PodiumPrompt") or Instance.new("ProximityPrompt")
	podiumPrompt.Name = "PodiumPrompt"
	podiumPrompt.ActionText = "CHOOSE ORE"
	podiumPrompt.ObjectText = "Income Podium"
	podiumPrompt.RequiresLineOfSight = false
	podiumPrompt.Style = Enum.ProximityPromptStyle.Custom
	podiumPrompt:SetAttribute("PromptKind", "Talk")
	podiumPrompt:SetAttribute("OwnerUserId", player.UserId)
	podiumPrompt.Parent = rootPart(podium) or podium
	-- Второе значение — сам BillboardGui, а не только его TextLabel: он нужен,
	-- чтобы гасить табличку целиком (см. Config.Geodes.ShowPodiumStatusLabel
	-- и UpdateDisplay ниже). Прятать один лишь TextLabel мало — остался бы
	-- пустой billboard, который всё так же перекрывает вид на кристалл.
	local podiumLabel, podiumLabelGui = billboard(podium, 7, true)
	local safe = PlaceholderFactory.GeodeSafe()
	local customSafe = safe ~= nil
	safe = safe or Instance.new("Part")
	safe.Name = "GeodeSafe"
	if not customSafe then
		safe.Size = Vector3.new(4, 4, 3)
		safe.Color = Color3.fromRGB(45, 55, 65)
		safe.Material = Enum.Material.Metal
	end
	placeOnPlot(safe, plot.GeodeSafeCFrame, plot.SafePad)
	setAnchored(safe, true)
	safe.Parent = plot.Content
	local safePrompt = findPrompt(safe, "SafePrompt") or Instance.new("ProximityPrompt")
	safePrompt.Name = "SafePrompt"
	safePrompt.ActionText = "COLLECT MONEY"
	safePrompt.ObjectText = "Income Safe"
	safePrompt.HoldDuration = 0 -- было Config.Geodes.SafeCollectHoldDuration (1.5 сек) — теперь мгновенный клик
	safePrompt.ClickablePrompt = true
	safePrompt.RequiresLineOfSight = false
	safePrompt.Style = Enum.ProximityPromptStyle.Custom
	safePrompt:SetAttribute("PromptKind", "Talk")
	safePrompt:SetAttribute("OwnerUserId", player.UserId)
	safePrompt.Parent = rootPart(safe) or safe

	-- ЕДИНЫЙ БИЛБОРД НАД СЕЙФОМ — по прямому запросу переделан с нуля.
	-- РЕАЛЬНАЯ ПРИЧИНА БАГА "вижу чужой доход даже на дистанции": старый
	-- код ПЕРЕИСПОЛЬЗОВАЛ уже существующий StatusGui/TimerGui, если такой
	-- был в модели сейфа (например, от более старой версии ассета) — а
	-- MaxDistance выставлялся ТОЛЬКО для новосозданного билборда (см.
	-- `if created then ... gui.MaxDistance = ... end` было раньше). У
	-- переиспользованного билборда MaxDistance просто никогда не
	-- проставлялся — виден с любой дистанции. Теперь СТАРЫЕ StatusGui/
	-- TimerGui, если есть, удаляются целиком, и билборд строится заново,
	-- всегда одинаково: две строки (сумма зелёным + FULL IN), близкая
	-- дистанция (30 стадов — "недалеко", по образцу коротких билбордов
	-- кристаллов), никакой лазейки для переиспользования чужой вёрстки.
	for _, name in { "StatusGui", "TimerGui" } do
		for _, descendant in safe:GetDescendants() do
			if descendant:IsA("BillboardGui") and descendant.Name == name then
				descendant:Destroy()
			end
		end
	end

	local safeAnchor = rootPart(safe) or safe
	local safeGui = Instance.new("BillboardGui")
	safeGui.Name = "SafeIncomeGui"
	safeGui.Size = UDim2.fromOffset(240, 64)
	safeGui.StudsOffset = Vector3.new(0, 4, 0)
	safeGui.AlwaysOnTop = true
	safeGui.MaxDistance = 30 -- "недалеко" — по прямому запросу, короткая дистанция как у билбордов кристаллов
	if safeAnchor and safeAnchor:IsA("BasePart") then safeGui.Adornee = safeAnchor end
	safeGui.Parent = safeAnchor or safe

	local safeLayout = Instance.new("UIListLayout")
	safeLayout.FillDirection = Enum.FillDirection.Vertical
	safeLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	safeLayout.SortOrder = Enum.SortOrder.LayoutOrder
	safeLayout.Parent = safeGui

	local safeLabel = Instance.new("TextLabel")
	safeLabel.Name = "Amount"
	safeLabel.LayoutOrder = 1
	safeLabel.Size = UDim2.new(1, 0, 0, 34)
	safeLabel.BackgroundTransparency = 1
	safeLabel.Font = Enum.Font.Arcade
	safeLabel.TextScaled = true
	safeLabel.TextWrapped = true
	safeLabel.TextColor3 = Color3.fromRGB(90, 255, 130) -- зелёный, по прямому запросу
	safeLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	safeLabel.TextStrokeTransparency = 0
	safeLabel.Text = "$0"
	safeLabel.Parent = safeGui

	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "Timer"
	timerLabel.LayoutOrder = 2
	timerLabel.Size = UDim2.new(1, 0, 0, 26)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Font = Enum.Font.Arcade
	timerLabel.TextScaled = true
	timerLabel.TextWrapped = true
	timerLabel.RichText = true
	timerLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	timerLabel.TextStrokeTransparency = 0
	timerLabel.Text = ""
	timerLabel.Parent = safeGui

	-- v18: ЭССЕНЦИИ МУТАЦИЙ. Второй промпт подиума (клавиша F) — показывается
	-- строкой под «Choose Ore» (WorldPrompts: SecondaryPrompt), включён, пока
	-- у игрока есть эссенция, которую можно нанести на установленный кристалл.
	local essencePrompt = Instance.new("ProximityPrompt")
	essencePrompt.Name = "EssencePrompt"
	essencePrompt.ActionText = "APPLY ESSENCE"
	essencePrompt.ObjectText = "Income Podium"
	essencePrompt.KeyboardKeyCode = Enum.KeyCode.F
	essencePrompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	essencePrompt.HoldDuration = 0.6
	essencePrompt.RequiresLineOfSight = false
	essencePrompt.Style = Enum.ProximityPromptStyle.Custom
	essencePrompt.Enabled = false
	essencePrompt:SetAttribute("SecondaryPrompt", true)
	essencePrompt:SetAttribute("OwnerUserId", player.UserId)
	essencePrompt.MaxActivationDistance = podiumPrompt.MaxActivationDistance
	essencePrompt.Parent = podiumPrompt.Parent
	essencePrompt.Triggered:Connect(function(triggerer)
		if triggerer == player then self:ApplyEssence(player) end
	end)

	displays[player] = { EssencePrompt = essencePrompt, Podium = podium, PodiumLabel = podiumLabel, PodiumLabelGui = podiumLabelGui, Safe = safe, SafeLabel = safeLabel, SafeTimerLabel = timerLabel, OreModel = nil, DisplayedOreId = nil, DisplayedOreLevel = nil, PodiumPrompt = podiumPrompt }
	podiumPrompt.Triggered:Connect(function(triggerer)
		if triggerer == player then Services.GeodeService:SendState(player, "OpenPodium", Services.GeodeService:GetState(player)) end
	end)
	safePrompt.Triggered:Connect(function(triggerer)
		if triggerer == player then self:Collect(player) end
	end)
	self:UpdateDisplay(player)
	return podium, safe
end

-- Модель руды на подиуме анимируется от ЗАПОМНЕННОЙ точки. Когда остров
-- едет из-под земли, её надо пересобрать уже на финальном месте.
function PassiveIncomeService:SetSuspended(player, suspended)
	local display = displays[player]
	if display then display.Suspended = suspended == true end
end

function PassiveIncomeService:ResetOreModel(player)
	local display = displays[player]
	if not display then return end
	display.OreAnimationToken = nil
	if display.OreModel then display.OreModel:Destroy(); display.OreModel = nil end
	if display.IncomeLabelGui then display.IncomeLabelGui:Destroy(); display.IncomeLabelGui = nil; display.IncomeLabelText = nil end
	display.DisplayedOreId = nil
	display.DisplayedOreLevel = nil
end

function PassiveIncomeService:UpdateDisplay(player)
	local display = displays[player]
	local data = Services.DataService:GetGeodeData(player)
	if not display or not data then return end
	task.defer(function() self:RefreshEssencePrompt(player) end) -- v18
	-- Остров дохода сейчас выезжает из-под земли (см. IslandService) —
	-- не пересобираем модель кристалла посреди движения.
	if display.Suspended then return end
	local rate = incomePerMinute(player, data)
	display.SafeLabel.Text = "$" .. NumberFormat.abbreviate(math.floor(data.GeodeSafeBalance))

	-- ТАЙМЕР ДО ЗАПОЛНЕНИЯ. Три состояния, у каждого свой смысл для игрока:
	--   • руда не установлена     — сейф в принципе не копит, зовём на подиум;
	--   • копит                   — сколько осталось до остановки накопления;
	--   • полон                   — накопление ОСТАНОВЛЕНО, каждая минута
	--                               простоя теперь буквально теряет деньги.
	-- Третье состояние и есть причина возвращаться в игру вовремя, поэтому
	-- оно красное и написано прямым текстом, а не намёком.
	if display.SafeTimerLabel then
		local label = display.SafeTimerLabel
		if rate <= 0 then
			label.Text = '<font color="#8A93A6">NO CRYSTAL ON PODIUM</font>'
		else
			local remaining = self:SecondsUntilFull(player)
			if remaining == nil then
				-- Потолок выключен в конфиге — таймеру нечего показывать,
				-- но доход есть: показываем хотя бы скорость.
				label.Text = ('<font color="#5FFF82">+$%s/SEC</font>'):format(NumberFormat.perSecond(rate))
			elseif remaining <= 0 then
				label.Text = '<font color="#FF6B6B">SAFE FULL — INCOME STOPPED</font>'
			else
				label.Text = ('<font color="#8A93A6">FULL IN</font> <font color="#FFD84A">%s</font>')
					:format(self:FormatDuration(remaining))
			end
		end
	end
	local oreId = data.InstalledGeodeOre
	local entry = data.GeodeCollection[oreId]
	if entry then
		local baseOreId, installedMutations = CollectionKey.Parse(oreId)
		local info = Config.Geodes.Ores[baseOreId]
		-- Подпись из ТРЁХ строк: название руды, доход, мутация. Третья строка
		-- появляется только у мутировавшего кристалла — у обычного подпись
		-- остаётся прежней двухстрочной, лишней пустой строки не будет.
		local mutationNames = {}
		for _, mutationId in installedMutations do
			table.insert(mutationNames, Config.Mutations[mutationId].DisplayName:upper())
		end
		MutationVisuals.StyleOverheadLabel(display.PodiumLabel, installedMutations, info.Color)
		local nameColor = info.Color:Lerp(Color3.new(1, 1, 1), 0.72)
		local nameHex = ("#%02X%02X%02X"):format(
			math.round(nameColor.R * 255),
			math.round(nameColor.G * 255),
			math.round(nameColor.B * 255)
		)
		display.PodiumLabel.Text = ('<font color="%s">%s</font>\n<font color="#5FFF82">$%s/SEC</font>'):format(
			nameHex,
			info.DisplayName,
			NumberFormat.perSecond(rate)
		) .. (#mutationNames > 0 and ("\n" .. MutationVisuals.ColoredNames(installedMutations)) or "")
		display.PodiumLabel.TextColor3 = Color3.new(1, 1, 1)
		-- ВТОРАЯ ТАБЛИЧКА НАД ПОДИУМОМ СКРЫТА, ПОКА КРИСТАЛЛ УСТАНОВЛЕН —
		-- по прямому запросу. Она дублировала то, что и так написано прямо
		-- над кристаллом ("$X/SEC", см. IncomeLabel ниже), плюс добавляла
		-- название и мутации — и всё это висело вторым слоем поверх самой
		-- модели. Текст выше по-прежнему формируется: он ничего не стоит,
		-- зато табличка мгновенно готова, если её включат обратно флагом
		-- Config.Geodes.ShowPodiumStatusLabel.
		if display.PodiumLabelGui then
			display.PodiumLabelGui.Enabled = Config.Geodes.ShowPodiumStatusLabel == true
		end
		if display.IncomeLabelText then
			display.IncomeLabelText.Text = ("$%s/SEC"):format(NumberFormat.perSecond(rate))
		end
		if display.DisplayedOreId ~= oreId or display.DisplayedOreLevel ~= entry.Level
			or not (display.OreModel and display.OreModel.Parent) then
			if display.OreModel then display.OreModel:Destroy() end
			display.OreAnimationToken = nil -- останавливает предыдущий цикл анимации ниже, если был
			local ore = PlaceholderFactory.CollectionOre(baseOreId)
			local placementCFrame = podiumTopCFrame(display.Podium)
			-- Preserve the exact orientation authored in ReplicatedStorage. Only
			-- move the asset's pivot to the podium; do not impose X/Z/Y corrections.
			local assetRotation = ore:GetPivot().Rotation
			local assetPlacement = CFrame.new(placementCFrame.Position) * assetRotation
			local baseCFrame
			local levitateHeight
			local bobHeight
			if ore:IsA("Model") then
				for _, descendant in ore:GetDescendants() do
					if descendant:IsA("BasePart") then descendant.Anchored = true; descendant.CanCollide = false end
				end
				ore:PivotTo(assetPlacement)
				local boundsCFrame, boundsSize = ore:GetBoundingBox()
				local bottom = bottomY(ore)
				baseCFrame = ore:GetPivot() + Vector3.new(0, placementCFrame.Position.Y - bottom, 0)
				levitateHeight = math.clamp(Config.Geodes.OreLevitateHeight * (boundsSize.Y / 3.6), 0.05, 0.25)
				bobHeight = math.min(Config.Geodes.OreBobHeight * (boundsSize.Y / 3.6), levitateHeight * 0.45)
			else
				ore.Anchored = true
				ore.CanCollide = false
				ore.CFrame = assetPlacement
				baseCFrame = ore.CFrame + Vector3.new(0, ore.Size.Y / 2, 0)
				levitateHeight = math.clamp(Config.Geodes.OreLevitateHeight * (ore.Size.Y / 3.6), 0.05, 0.25)
				bobHeight = math.min(Config.Geodes.OreBobHeight * (ore.Size.Y / 3.6), levitateHeight * 0.45)
			end
			-- Мутации применяются к модели на подиуме так же, как к руде в
			-- тележке: ржавый кристалл и на подиуме должен выглядеть ржавым.
			-- ДО установки Parent, чтобы игрок не увидел кадр с "чистой"
			-- моделью до перекраски.
			for _, mutationId in installedMutations do
				MutationVisuals.Apply(ore, mutationId, ore:IsA("Model") and ore.PrimaryPart or ore)
			end
			ore.Parent = display.Podium.Parent
			display.OreModel = ore
			display.DisplayedOreId = oreId
			display.DisplayedOreLevel = entry.Level

			-- Отдельная подпись "$X/SEC" ПРЯМО НАД кристаллом (не смешана
			-- с общей PodiumLabel, которая сидит над самим подиумом) — по
			-- прямому запросу: зелёным с чёрной обводкой, размер как у
			-- надписи над сейфом (280x58, см. billboard(safe, 3.5, false)
			-- выше). Пересобирается вместе с моделью руды и парентится
			-- НА НЕЁ — BillboardGui сам следует за Adornee каждый кадр,
			-- так что подпись "прилипает" к левитации/вращению кристалла
			-- бесплатно, без отдельной анимации.
			if display.IncomeLabelGui then
				display.IncomeLabelGui:Destroy()
				display.IncomeLabelGui = nil
				display.IncomeLabelText = nil
			end
			local incomeAnchor = ore:IsA("Model") and (ore.PrimaryPart or ore:FindFirstChildWhichIsA("BasePart", true)) or ore
			if incomeAnchor then
				local incomeGui = Instance.new("BillboardGui")
				incomeGui.Name = "IncomeLabel"
				incomeGui.Adornee = incomeAnchor
				incomeGui.Size = UDim2.fromOffset(280, 58)
				local clearance = (ore:IsA("Model") and (select(2, ore:GetBoundingBox())).Y or ore.Size.Y) * 0.5 + 1.4
				incomeGui.StudsOffset = Vector3.new(0, clearance, 0)
				incomeGui.AlwaysOnTop = true
				incomeGui.MaxDistance = 35 -- тот же радиус, что и у суммы над сейфом
				incomeGui.Parent = incomeAnchor

				local incomeLabelText = Instance.new("TextLabel")
				incomeLabelText.Name = "Income"
				incomeLabelText.Size = UDim2.fromScale(1, 1)
				incomeLabelText.BackgroundTransparency = 1
				incomeLabelText.Font = Enum.Font.Arcade
				incomeLabelText.TextScaled = true
				incomeLabelText.TextWrapped = true
				incomeLabelText.TextColor3 = Color3.fromRGB(90, 255, 130)
				incomeLabelText.TextStrokeColor3 = Color3.new(0, 0, 0)
				incomeLabelText.TextStrokeTransparency = 0
				incomeLabelText.Parent = incomeGui

				display.IncomeLabelGui = incomeGui
				display.IncomeLabelText = incomeLabelText
			end

			-- Левитация над "родной" точкой посадки + бесконечное вращение
			-- вокруг себя (Config.Geodes.OreLevitateHeight/OreBobHeight/
			-- OreBobSpeed/OreSpinSpeed) — вместо того, чтобы просто стоять
			-- неподвижно на подиуме. token останавливает цикл сам, как только
			-- модель заменят другой (следующая установка) или уничтожат.
			local token = {}
				display.OreAnimationToken = token
				task.spawn(function()
					local start = os.clock()
					while ore.Parent and display.OreAnimationToken == token do
						local elapsed = os.clock() - start
						local bob = math.sin(elapsed * Config.Geodes.OreBobSpeed) * bobHeight
						local spin = CFrame.Angles(0, elapsed * Config.Geodes.OreSpinSpeed, 0)
						local animatedCFrame = CFrame.new(baseCFrame.Position + Vector3.new(0, levitateHeight + bob, 0))
							* spin * (baseCFrame - baseCFrame.Position)
						ore:PivotTo(animatedCFrame)
						local targetBottom = placementCFrame.Position.Y + levitateHeight + bob
						moveY(ore, targetBottom - bottomY(ore))
						task.wait(0.03)
				end
			end)
		end
	else
		display.PodiumLabel.Text = "NO ORE INSTALLED"
		display.PodiumLabel.TextColor3 = Color3.new(1, 1, 1)
		-- На ПУСТОМ подиуме табличку возвращаем: скрывать было нечего и
		-- незачем — кристалла нет, значит нет и надписи "$X/SEC" над ним,
		-- и без этой подсказки подиум выглядел бы просто безымянной
		-- тумбой. Прятали её именно как ДУБЛЬ, а дублировать тут нечего.
		if display.PodiumLabelGui then
			display.PodiumLabelGui.Enabled = true
		end
		display.OreAnimationToken = nil
		if display.OreModel then display.OreModel:Destroy(); display.OreModel = nil end
		if display.IncomeLabelGui then display.IncomeLabelGui:Destroy(); display.IncomeLabelGui = nil; display.IncomeLabelText = nil end
		display.DisplayedOreId = nil
		display.DisplayedOreLevel = nil
	end
end

-- Вызывается GeodeService, пока клиент тапает жеоду (см. "SetCrackingPromptEnabled"
-- в GeodeService.lua) — подиум выбора руды стоит рядом с хранилищем жеод на
-- том же участке, и его точно так же можно случайно задеть посреди анимации
-- раскалывания, прислав "OpenPodium" и выдёргивая игрока из процесса.
function PassiveIncomeService:SetPodiumPromptEnabled(player, enabled)
	local display = displays[player]
	if display and display.PodiumPrompt then
		display.PodiumPrompt.Enabled = enabled
	end
	if display then display.PodiumPromptDisabled = not enabled end
	self:RefreshEssencePrompt(player)
end

--------------------------------------------------------------------------------
-- v18: ЭССЕНЦИИ МУТАЦИЙ (выпадают только из жеод, см. Config.Geodes.Essence)
--------------------------------------------------------------------------------
local function ownedEssences(data)
	local list = {}
	for _, key in DropTables.AllEssenceKeys() do -- от редких к частым
		local count = math.floor(tonumber(data.Gear and data.Gear[key]) or 0)
		if count > 0 then table.insert(list, { Key = key, Mutation = DropTables.EssenceMutation(key), Count = count }) end
	end
	return list
end

-- Какую эссенцию нанесём: ту, что в руке (если подходит), иначе самую
-- редкую из имеющихся, которой у кристалла ещё нет. nil + причина.
local function chooseEssence(player, data)
	local key = data.InstalledGeodeOre
	if not key or key == "" or not data.GeodeCollection[key] then return nil, "NoCrystal" end
	local _, mutations = CollectionKey.Parse(key)
	local has = {}
	for _, id in mutations do has[id] = true end
	local maxPer = (Config.Geodes.Essence and Config.Geodes.Essence.MaxPerCrystal) or 2
	if #mutations >= maxPer then return nil, "Full" end
	local owned = ownedEssences(data)
	if #owned == 0 then return nil, "NoEssence" end
	local held = player:GetAttribute("HeldGear") or ""
	local heldMutation = DropTables.EssenceMutation(held)
	for _, essence in owned do
		if essence.Mutation == heldMutation and not has[essence.Mutation] then return essence end
	end
	for _, essence in owned do
		local group = Config.Mutations.ExclusiveGroups and Config.Mutations.ExclusiveGroups[essence.Mutation]
		local clash = false
		if group then
			for id in has do
				if Config.Mutations.ExclusiveGroups[id] == group then clash = true end
			end
		end
		if not has[essence.Mutation] and not clash then return essence end
	end
	return nil, "AlreadyHas"
end

function PassiveIncomeService:RefreshEssencePrompt(player)
	local display = displays[player]
	local prompt = display and display.EssencePrompt
	if not (prompt and prompt.Parent) then return end
	local data = Services.DataService:GetGeodeData(player)
	local essence = data and chooseEssence(player, data)
	if essence and not display.PodiumPromptDisabled then
		local mutation = Config.Mutations[essence.Mutation]
		prompt.ActionText = ("Apply %s Essence"):format(mutation and mutation.DisplayName or essence.Mutation)
		prompt.Enabled = true
	else
		prompt.Enabled = false
	end
end

local lastEssenceApply = {}

function PassiveIncomeService:ApplyEssence(player)
	local now = os.clock()
	if lastEssenceApply[player] and now - lastEssenceApply[player] < 0.8 then return false end
	lastEssenceApply[player] = now
	local data = Services.DataService:GetGeodeData(player)
	if not data then return false end
	local essence, reason = chooseEssence(player, data)
	if not essence then
		local text = reason == "NoCrystal" and "Install a crystal on the podium first!"
			or reason == "Full" and ("This crystal already holds %d mutations."):format((Config.Geodes.Essence and Config.Geodes.Essence.MaxPerCrystal) or 2)
			or reason == "AlreadyHas" and "Your crystal already has these mutations."
			or "You have no essence. Find them in geodes!"
		Services.NotifyService:Show(player, text, { Icon = "Error" })
		self:RefreshEssencePrompt(player)
		return false
	end
	if not Services.GeodeService:TryBeginTransaction(player) then return false end
	self:Accrue(player, true) -- старый кристалл доначисляет до момента смены

	local oldKey = data.InstalledGeodeOre
	local oldEntry = data.GeodeCollection[oldKey]
	local oreId, mutations = CollectionKey.Parse(oldKey)
	table.insert(mutations, essence.Mutation)
	local newKey = CollectionKey.Make(oreId, mutations)
	local snapshot = {
		Old = { Copies = oldEntry.Copies, Level = oldEntry.Level },
		New = data.GeodeCollection[newKey] and { Copies = data.GeodeCollection[newKey].Copies, Level = data.GeodeCollection[newKey].Level } or nil,
		Installed = oldKey,
		Essence = data.Gear[essence.Key],
	}

	-- Весь кристалл (со всеми копиями и уровнем) превращается в мутировавший.
	local copiesTable = Config.Geodes.DuplicateCopiesPerLevel
	local maxCopies = copiesTable[#copiesTable]
	local target = data.GeodeCollection[newKey]
	if target then
		target.Copies = math.min(target.Copies + oldEntry.Copies, maxCopies)
		local level = 1
		for candidate, required in copiesTable do
			if target.Copies >= required then level = candidate else break end
		end
		target.Level = math.max(target.Level, math.min(level, Config.Geodes.MaxOreLevel))
	else
		data.GeodeCollection[newKey] = { Copies = oldEntry.Copies, Level = oldEntry.Level }
	end
	data.GeodeCollection[oldKey] = nil
	data.InstalledGeodeOre = newKey
	data.Gear[essence.Key] = math.max(0, (data.Gear[essence.Key] or 0) - 1)
	data.GeodeLastCalculatedAt = os.time()

	if not Services.DataService:SaveProfile(player) then
		data.GeodeCollection[oldKey] = { Copies = snapshot.Old.Copies, Level = snapshot.Old.Level }
		if snapshot.New then
			data.GeodeCollection[newKey] = { Copies = snapshot.New.Copies, Level = snapshot.New.Level }
		else
			data.GeodeCollection[newKey] = nil
		end
		data.InstalledGeodeOre = snapshot.Installed
		data.Gear[essence.Key] = snapshot.Essence
		Services.GeodeService:EndTransaction(player)
		Services.NotifyService:Show(player, "Essence failed safely. Try again.", { Icon = "Error" })
		return false
	end
	Services.GeodeService:EndTransaction(player)
	if Services.MutationBookService then
		pcall(Services.MutationBookService.RecordFound, Services.MutationBookService, player, 1, essence.Mutation)
	end
	-- Снаряжение: слот/хотбар/рука — через обычный путь.
	if (data.Gear[essence.Key] or 0) <= 0 and player:GetAttribute("HeldGear") == essence.Key then
		Services.GearService:Unequip(player)
	end
	pcall(Services.GearService.SendState, Services.GearService, player)
	if Services.InventoryService and Services.InventoryService.OnGearChanged then
		pcall(Services.InventoryService.OnGearChanged, Services.InventoryService, player, essence.Key, -1)
	end
	self:ResetOreModel(player) -- кристалл пересобирается уже с мутацией
	self:UpdateDisplay(player)
	Services.GeodeService:SendState(player, "PodiumState")
	self:RefreshEssencePrompt(player)
	local mutation = Config.Mutations[essence.Mutation]
	Services.NotifyService:Show(player, ("🧪 %s ESSENCE APPLIED! Crystal is now %s (x%s)"):format(
		(mutation and mutation.DisplayName or essence.Mutation):upper(), CollectionKey.DisplayName(newKey), tostring(mutation and mutation.Multiplier or 1)
	), { Icon = "Crystal", Duration = 3.5 })
	local display = displays[player]
	if display and display.Podium then
		pcall(Sfx.play, "GeodeReveal", display.Podium:IsA("BasePart") and display.Podium or display.Podium.PrimaryPart)
	end
	-- Клиенты рисуют вспышку на подиуме (client/EssenceFX).
	local fxRemote = ReplicatedStorage.Shared:FindFirstChild("EssenceFx")
	if fxRemote and display and display.Podium then
		fxRemote:FireAllClients(display.Podium, mutation and mutation.Color or Color3.fromRGB(200, 120, 255))
	end
	return true
end

function PassiveIncomeService:CleanupPlayer(player)
	lastInstallRequest[player] = nil
	lastEssenceApply[player] = nil
	displays[player] = nil
end

return PassiveIncomeService
