--------------------------------------------------------------------------------
-- DataService
-- Профили игроков. Хранит МИНИМУМ: Money + прогресс 3 НЕЗАВИСИМЫХ веток
-- прокачки (Mine/Cart/Pickaxe). Тир каждой ветки = 1 + число купленных
-- в ней шагов — прямое хранимое число, без вывода из общей цепочки.
--------------------------------------------------------------------------------

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local BadgeService = game:GetService("BadgeService")

local Config = require(ReplicatedStorage.Shared.Config)
local CollectionKey = require(ReplicatedStorage.Shared.CollectionKey)
local Localization = require(ReplicatedStorage.Shared.Localization)
local Sfx = require(ReplicatedStorage.Shared.Sfx)
local BigNum = require(ReplicatedStorage.Shared.BigNum)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)

-- Практический потолок денег — НЕ 2^53 (как был Config.Economy.MaxCurrency
-- для старого double-хранилища), а условная "бесконечность" в BigNum-
-- представлении: 1e300. Реальным лимитом прогрессии он не является ни при
-- каком мыслимом темпе игры, это чисто защита от кривых входных чисел.
local MONEY_SAFETY_CAP = BigNum.new(10):powInt(300)

local DataService = {}

local Services = nil
local store = nil
local receiptStore = nil
local profiles = {} -- [player] = { Data, SessionId, Saving, Closing, MemoryOnly, PendingReceiptSaves }

function DataService:AwardBadge(player, badgeId)
	badgeId = tonumber(badgeId) or 0
	if not player or not player.Parent or badgeId <= 0 then return end
	task.spawn(function()
		local ok, hasBadge = pcall(function()
			return BadgeService:UserHasBadgeAsync(player.UserId, badgeId)
		end)
		if not ok or hasBadge or not player.Parent then return end
		local awarded, err = pcall(function()
			BadgeService:AwardBadge(player.UserId, badgeId)
		end)
		if not awarded then warn("[DataService] Badge award failed:", badgeId, err) end
	end)
end

local CHAIN_CONFIG = { Mine = Config.MineChain, Cart = Config.CartChain, Pickaxe = Config.PickaxeChain }

local DEFAULT_DATA = {
	Money = BigNum.new(0):toData(), -- {s=0,m=0,e=0} — см. reconcile() ниже: старые сейвы (Money простым числом) конвертируются в этот формат ДО общего цикла сверки типов, иначе он бы сбросил деньги в 0 как "поле неверного типа"
	EconomyVersion = Config.Economy.Version,
	-- v8: престиж-перки, снаряжение (динамит/сундуки), поставленные сундуки.
	PrestigePoints = 0,
	Perks = {},
	PerksMigrated = false, -- старым профилям заполнится false → PrestigeService переведёт ребёрты в очки (у новых Rebirths = 0)
	Gear = {},
	PlacedChests = {},
	-- v12: КУПЛЕНА ЛИ ВООБЩЕ ПЕРВАЯ ТЕЛЕЖКА. Тир тележки по-прежнему
	-- 1 + CartIndex, но сам факт владения теперь отдельный: у нового игрока
	-- тележки НЕТ, первая покупается у НПС прокачки за 0 (см.
	-- UpgradeService — ветка Cart, и CartService:UnlockFirstCart).
	-- Старым профилям (которые играли до этой версии и тележку уже имели)
	-- флаг проставляется автоматически, см. CartService:SetupPlayer.
	CartUnlocked = false,
	MineIndex = 0,    -- сколько шагов Config.MineChain куплено (тир = 1 + индекс)
	CartIndex = 0,    -- сколько шагов Config.CartChain куплено
	PickaxeIndex = 0, -- сколько шагов Config.PickaxeChain куплено
	Rebirths = 0,     -- каждый ребёрт даёт постоянный множитель цены кристаллов
	CartDamage = 0,   -- суммарный фактически нанесённый урон по тележкам
	PlayTimeSeconds = 0, -- суммарное время в игре между всеми сессиями
	RedeemedCodes = {}, -- уже использованные промокоды (Config.PromoCodes) — каждый разово
	TutorialVersion = 0,
	-- ОБУЧЕНИЕ v7 (см. Config.Tutorial/TutorialService). Номер шага живёт в
	-- профиле, а не на клиенте: прошлый гайд держал его в локальной
	-- переменной LocalScript'а и честно начинал заново после каждого
	-- перезахода/вылета — на шестом шаге это означало потерю всего
	-- пройденного.
	TutorialStep = 1,
	-- ПОЧИНЕНА ЛИ ШАХТА. Отдельный флаг, а не "тир 0": Config.MineTiers —
	-- массив с 1, и нулевой индекс уронил бы всё, что читает
	-- Config.MineTiers[tier] (см. подробный разбор в Config.Mine.Broken).
	-- Поднимается починкой у торговца (нулевой шаг ветки шахты).
	--
	-- В DEFAULT_DATA поля НАМЕРЕННО НЕТ. reconcile() заполняет пропуски
	-- дефолтами ДО миграции в LoadProfile, и с дефолтом false миграция
	-- `if data.MineRepaired == nil` не срабатывала никогда: у каждого
	-- старого игрока шахта оказывалась сломанной. Значение ставит сама
	-- миграция — false новичку, true профилю с прогрессом.
	SeenHints = {}, -- [hintKey] = true — контекстные подсказки (щит/PvP/rebirth), каждая показывается один раз за аккаунт
	Username = "",
	DisplayName = "",
	UserId = 0,
	SchemaVersion = 3,
	LastSeenAt = 0,
	ProcessedReceipts = {}, -- последние PurchaseId; постоянные tombstone лежат в отдельном DataStore
	ProcessedReceiptOrder = {},
	PaidProtectionEndsAt = 0,
	StarterPackClaimed = false, -- см. Config.DevProducts.StarterPack — перманентно даёт бонус ExtraPouch/SpeedBoost без реальной покупки этих пассов (MonetizationService подмешивает флаг в ownership-кэш)
	FirstJoinedAt = 0, -- unix-время СОЗДАНИЯ профиля (не каждого захода!) — 0 у всех, чьё сохранение старше этого поля; используется StarterPackUI.client.lua, чтобы не показывать баннер старым игрокам
	PendingCartFills = {}, -- [PurchaseId] = { ProductId, Tier, MaxCrystals, CreatedAt }
	Geodes = (function()
		local counts = {}
		for geodeType in Config.Geodes.Types do counts[geodeType] = 0 end
		return counts
	end)(), -- один счётчик на КАЖДЫЙ тип из Config.Geodes.Types, автоматически
	-- ИНВЕНТАРЬ v1 (см. Config.Inventory). Backpack — массив стопок
	-- { Ore = "Iron", Variant = 2, Mutations = "Frozen", Count = 5, Value = 1234 }.
	-- Hotbar — [slotIndex] = индекс стопки в Backpack (или nil).
	-- OwnedPickaxes — [tier] = true, какие тиры кирок открыты (можно
	-- переключаться между ними, см. InventoryService:EquipPickaxe).
	-- EquippedPickaxeTier/EquippedPickaxeSkin — что сейчас в руках.
	Backpack = {},
	Hotbar = {},
	OwnedPickaxes = {},
	EquippedPickaxeTier = 0, -- 0 = "текущий тир прокачки", см. InventoryService:GetEquippedPickaxeTier
	EquippedPickaxeSkin = "Default",
	GeodeCollection = {}, -- [oreId] = { Copies, Level }
	InstalledGeodeOre = "",
	GeodeSafeBalance = 0,
	GeodeLastCalculatedAt = 0,
	GeodeOpenPity = 0,
	GeodeHearts = 0,     -- v18: сердца жеоды (след. жеода даёт 3 награды)
	ChestSkinPity = 0,   -- v18: сундуков Epic/Legendary подряд без скина
	GeodeSpawnPity = 0,
	FirstGeodeOreGranted = false,
	GeodeEvacuations = {}, -- [transactionId] = timestamp; idempotency for bank retries
	GeodeEvacuationOrder = {},
	StarterQuestProgress = {},
	DailyQuestDate = "",
	DailyQuests = {},
	WeeklyQuestPoints = 0,
	WeeklyQuestWeek = "",
	LastDailyClaimDate = "",
	DailyRewardStreak = 0,
	DailyRewardClaimed = false,
	DailyRewardEligible = true,
	DailyMiningBoostEndsAt = 0,
	-- Какой именно множитель выдали при последнем клейме буста (см. фикс
	-- ниже в QuestService:GetMiningBoostMultiplier). Раньше множитель НЕ
	-- сохранялся — функция просто сканировала Config.Quests.DailyRewards в
	-- поисках ПЕРВОЙ записи с Kind=="MiningBoost" и всегда возвращала ЕЁ
	-- множитель, независимо от того, какой буст был реально заклеймлен.
	-- Пока в таблице был только один MiningBoost-день, это давало верный
	-- результат случайно; как только появился второй с другим числом —
	-- стало бы неверно для одного из двух. Теперь множитель фиксируется
	-- в момент клейма и не зависит от того, что сейчас лежит в конфиге.
	DailyMiningBoostMultiplier = 1,
	DailyCartColorUnlocked = false,
	-- Подсказки про вторичные механики (см. Config.Tips и QuestService:
	-- _scheduleTips) — НЕ часть основного гайда, показываются с задержкой
	-- уже ПОСЛЕ его прохождения.
	TutorialCompletedAt = 0, -- Unix-время завершения основного гайда; 0 = ещё не проходил
	TipsShown = {}, -- [Config.Tips[i].Id] = true, каждая подсказка ровно один раз за профиль
	LikeRewardClaimed = false, -- см. LikeRewardService — одноразовая награда за лайк игры
	GroupRewardClaimed = false, -- см. GroupRewardService — одноразовая награда за лайк+вступление в группу
	-- [tier .. "_" .. mutationId] = true — какие комбинации руда/мутация уже
	-- находил игрок (см. MutationBookService) — просто найдено/не найдено,
	-- без счётчика повторов.
	MutationsFound = {},
	MobsFound = {},
	OwnedSkins = {},
	EquippedSkins = { Pickaxe = "", Cart = "", Ore = "" },
	SkinStarterGranted = false,
	DeveloperTestGrantVersion = 0,
	-- НАСЛЕДИЕ СЛАЙМА (слайм удалён, его место занял торговец банка).
	-- Накопленное кормление больше не растёт, но не выбрасывается: из него
	-- один раз считается замороженный бонус к продаже (см.
	-- GetLegacySellBonus / Config.Merchant.LegacySlime).
	SlimeFedValue = 0,
	-- Какие one-time подсказки при АКТИВАЦИИ квеста уже показаны (см.
	-- Config.Quests.Starter[].OnActivateTip / QuestService.
	-- _maybeShowQuestActivationTip) — [questId] = true. Отдельно от
	-- Config.Tips (те — по таймеру после тутора, эти — привязаны к
	-- моменту, когда конкретный квест реально становится активным).
	ShownQuestTips = {},
	-- ОСТРОВА (см. Config.Islands / IslandService). Islands — [id] = true.
	-- SmelterLevel — 0, пока острова плавильни нет. SmelterSlots — массив
	-- { Ore, Variant, Mutations, Value, StartedAt, Duration } (время — os.time,
	-- поэтому плавка идёт и пока игрок офлайн). IslandsMigrated — разовая
	-- выдача островов старым игрокам уже выполнена.
	Islands = {},
	SmelterLevel = 0,
	SmelterSlots = {},
	IslandsMigrated = false,
	-- v9/v10: книга коллекции по руде, заряды микротранзакций, ежедневный
	-- бесплатный динамит (Demolition Expert).
	OreBook = {},
	OreBookMigrated = false,
	MineRushCharges = 0,
	PerfectStrikes = 0,
	DemolitionDailyAt = 0,
	-- v14: база. Тотемы/декор/реликвии лежат в data.Gear (обычный инвентарь);
	-- здесь — то, что поставлено на участке (позиция ОТНОСИТЕЛЬНО участка),
	-- и метаданные реликвий (глобальный серийник, кто нашёл).
	PlacedDecor = {},
	Relics = {},
	-- v20: книга трофеев — какие реликвии игрок КОГДА-ЛИБО находил (даже
	-- если потом продал): [RelicId] = { Count, BestSerial, FirstAt }.
	RelicsFound = {},
	BaseUidCounter = 0,
}

local function deepCopy(source)
	local copy = {}
	for key, value in source do
		copy[key] = typeof(value) == "table" and deepCopy(value) or value
	end
	return copy
end

local function profileKey(player)
	return "profile_" .. player.UserId
end

local function receiptKey(purchaseId)
	return "purchase_" .. tostring(purchaseId)
end

local function reconcile(data, player)
	-- МИГРАЦИЯ ФОРМАТА ДЕНЕГ: до этого коммита Money хранился обычным
	-- Lua-числом. DEFAULT_DATA.Money теперь таблица {s,m,e} (BigNum) — если
	-- сделать это ПОСЛЕ общего цикла сверки типов ниже, он увидит
	-- "number вместо table" и решит, что поле битое, СБРОСИВ деньги игрока
	-- в 0. Поэтому конвертируем старый формат в новый здесь, ДО цикла.
	if typeof(data.Money) == "number" then
		data.Money = BigNum.new(data.Money):toData()
	elseif typeof(data.Money) ~= "table" then
		data.Money = BigNum.new(0):toData()
	end

	local loadedEconomyVersion = math.max(1, math.floor(tonumber(data.EconomyVersion) or 1))
	for key, value in DEFAULT_DATA do
		if data[key] == nil then
			data[key] = typeof(value) == "table" and deepCopy(value) or value
		elseif typeof(data[key]) ~= typeof(value) then
			if typeof(value) == "number" and tonumber(data[key]) then
				data[key] = tonumber(data[key])
			else
				warn(("[DataService] Профиль %s: поле %s имело неверный тип (%s вместо %s) — сброшено к дефолту"):format(
					player.Name, key, typeof(data[key]), typeof(value)
				))
				data[key] = typeof(value) == "table" and deepCopy(value) or value
			end
		end
	end
	if loadedEconomyVersion < Config.Economy.Version then
		-- Миграции по шагам: v1→v2 (x LegacyMoneyScale), v2→v3 (x LegacyMoneyScaleV3 +
		-- обрезка веток под новые цепочки: 8 пещер вместо 9 тиров).
		local scale = 1
		if loadedEconomyVersion < 2 then scale *= Config.Economy.LegacyMoneyScale or 1 end
		if loadedEconomyVersion < 3 then
			scale *= Config.Economy.LegacyMoneyScaleV3 or 1
			for kind, chain in CHAIN_CONFIG do
				local field = kind .. "Index"
				data[field] = math.clamp(math.floor(tonumber(data[field]) or 0), 0, #chain)
			end
			if tonumber(data.SlimeFedValue) then
				data.SlimeFedValue = math.max(0, math.floor(data.SlimeFedValue * (Config.Economy.LegacyMoneyScaleV3 or 1)))
			end
			data.GeodeSafeCapRateWatermark = 0
		end
		data.Money = (BigNum.fromData(data.Money) * scale):clamp(BigNum.new(0), MONEY_SAFETY_CAP):toData()
		data.GeodeSafeBalance = math.min(Config.Economy.MaxCurrency, math.max(0, (tonumber(data.GeodeSafeBalance) or 0) * scale))
		data.EconomyVersion = Config.Economy.Version
		print(("[DataService] Профиль %s переведён на экономику v%d (денежные остатки x%s)"):format(player.Name, Config.Economy.Version, tostring(scale)))
	end
	data.Username = player.Name
	data.DisplayName = player.DisplayName
	data.UserId = player.UserId
	data.SchemaVersion = 3

	--------------------------------------------------------------------------
	-- СКОЛЬКО ИГРОКА НЕ БЫЛО. Считается ИМЕННО ЗДЕСЬ и никак иначе: строкой
	-- ниже LastSeenAt перезаписывается текущим временем, и прежнее значение
	-- после этого уже не восстановить.
	--
	-- LastSeenAt обновляется не только при выходе, но и на каждом автосейве
	-- (Config.Data.AutosaveInterval, 120 сек) — и это ПРАВИЛЬНО для нашей
	-- задачи: при падении сервера профиль остаётся с временем последнего
	-- удачного сохранения, а не с моментом выхода, поэтому крашнувшийся
	-- игрок не получает офлайн-награду за время, которое он на самом деле
	-- провёл в игре.
	--
	-- Поле транзиентное (в DEFAULT_DATA его нет и в DataStore оно не
	-- уходит) — это факт о ТЕКУЩЕЙ сессии, а не сохраняемый прогресс.
	local previousSeenAt = tonumber(data.LastSeenAt) or 0
	local nowSeconds = os.time()
	local offline = 0
	if previousSeenAt > 0 and nowSeconds > previousSeenAt then
		offline = nowSeconds - previousSeenAt
	end
	data.LastSeenAt = nowSeconds
	player:SetAttribute("OfflineSeconds", offline)
	data.PlayTimeSeconds = math.max(0, math.floor(tonumber(data.PlayTimeSeconds) or 0))
	for geodeType in Config.Geodes.Types do
		data.Geodes[geodeType] = math.max(0, math.floor(tonumber(data.Geodes[geodeType]) or 0))
	end
	for key, entry in data.GeodeCollection do
		-- КЛЮЧ ЗДЕСЬ — НЕ ГОЛЫЙ oreId. Мутировавшая руда лежит под составным
		-- ключом вида "Quartz#Rusty" (см. CollectionKey), и проверка
		-- Config.Geodes.Ores[key] на нём НЕ СРАБОТАЛА БЫ — эта чистка молча
		-- стёрла бы игроку все мутировавшие ячейки при первой же загрузке
		-- профиля. Проверяем базовую руду.
		if not Config.Geodes.Ores[CollectionKey.BaseOre(key)] or typeof(entry) ~= "table" then
			data.GeodeCollection[key] = nil
		else
			entry.Copies = math.max(1, math.floor(tonumber(entry.Copies) or 1))
			entry.Level = math.clamp(math.floor(tonumber(entry.Level) or 1), 1, Config.Geodes.MaxOreLevel)
		end
	end
	for mobId, found in data.MobsFound do
		if not Config.Goblins.Types[mobId] or found ~= true then data.MobsFound[mobId] = nil end
	end
	if data.InstalledGeodeOre ~= "" and not data.GeodeCollection[data.InstalledGeodeOre] then
		data.InstalledGeodeOre = ""
	end
	for skinId, owned in data.OwnedSkins do
		if not Config.Skins.Definitions[skinId] or owned ~= true then data.OwnedSkins[skinId] = nil end
	end
	for _, kind in { "Pickaxe", "Cart", "Ore" } do
		local skinId = typeof(data.EquippedSkins[kind]) == "string" and data.EquippedSkins[kind] or ""
		local definition = Config.Skins.Definitions[skinId]
		if skinId ~= "" and (not definition or definition.Kind ~= kind or data.OwnedSkins[skinId] ~= true) then skinId = "" end
		data.EquippedSkins[kind] = skinId
	end
	return data
end

local function activeProfile(player)
	local profile = profiles[player]
	if not profile or profile.Closing or profile.Invalid then
		return nil
	end
	return profile
end

local function syncLeaderstats(player, data)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end
	local money = leaderstats:FindFirstChild("Money")
	-- ПЕРЕИМЕНОВАНО "Rebirths" -> "Prestige" (по прямому запросу). Имя этого
	-- IntValue внутри leaderstats — это ЗАГОЛОВОК КОЛОНКИ в стандартном
	-- списке игроков Roblox (Tab) и ключ, под которым значение попадает в
	-- сохранённые борды. Весь остальной текст игры давно говорит "Prestige"
	-- (Localization.lua, UpgradeService, LeaderboardService), и только эта
	-- колонка продолжала показывать старое слово.
	local rebirths = leaderstats:FindFirstChild("Prestige")
	local cartDamage = leaderstats:FindFirstChild("Cart Damage")
	if money then money.Value = NumberFormat.abbreviate(BigNum.fromData(data.Money)) end
	if rebirths then rebirths.Value = data.Rebirths end
	if cartDamage then cartDamage.Value = math.floor(data.CartDamage) end
end

--------------------------------------------------------------------------------

function DataService:Init(_services)
	Services = _services
	local ok, result = pcall(function()
		return {
			Profile = DataStoreService:GetDataStore(Config.Data.StoreName),
			Receipts = DataStoreService:GetDataStore(Config.Data.ReceiptStoreName),
		}
	end)
	if ok then
		store = result.Profile
		receiptStore = result.Receipts
	else
		warn("[DataService] DataStore недоступен (Studio без API-доступа?). Работаем в памяти:", result)
	end

	-- Промокоды (меню настроек, src/client) — сервер сам проверяет валидность
	-- и повторное использование, клиенту нечего подделывать. Ответ (успех/
	-- причина отказа) шлём обратно тем же RemoteEvent.
	--
	-- lastRedeemAttempt — защита от спама: эксплойт мог бы дёргать этот
	-- RemoteEvent тысячи раз в секунду (само по себе не даёт ничего
	-- украсть — RedeemCode всё равно проверяет всё по-честному, — но
	-- зря грузит сервер строковыми операциями на каждый вызов).
	local lastRedeemAttempt = {}
	local redeemRemote = Instance.new("RemoteEvent")
	redeemRemote.Name = "RedeemCodeRequest"
	redeemRemote.Parent = ReplicatedStorage.Shared
	redeemRemote.OnServerEvent:Connect(function(player, code)
		if typeof(code) ~= "string" or #code > 32 then
			return -- не строка или подозрительно длинная — настоящие промокоды короткие
		end
		local now = os.clock()
		local last = lastRedeemAttempt[player.UserId]
		if last and now - last < 0.5 then
			return -- не чаще двух попыток в секунду — не наказываем игрока молча, просто игнорируем лишнее
		end
		lastRedeemAttempt[player.UserId] = now
		local result, reward = self:RedeemCode(player, code)
		redeemRemote:FireClient(player, result, reward)
	end)

	local tutorialRemote = Instance.new("RemoteEvent")
	tutorialRemote.Name = "CompleteTutorialRequest"
	tutorialRemote.Parent = ReplicatedStorage.Shared

	-- Клиент слушает этот ивент, чтобы проиграть анимацию "монетки летят в
	-- баланс" и показать бейдж — см. CustomCartUI.client.lua.
	local tutorialRewardRemote = Instance.new("RemoteEvent")
	tutorialRewardRemote.Name = "TutorialRewardEvent"
	tutorialRewardRemote.Parent = ReplicatedStorage.Shared

	--------------------------------------------------------------------------
	-- ЗАВЕРШЕНИЕ ОБУЧЕНИЯ БОЛЬШЕ НЕ ИДЁТ ЧЕРЕЗ КЛИЕНТА.
	--
	-- Здесь висел обработчик, принимавший от клиента "я прошёл гайд" и
	-- выдававший за это награду. Проверить это сервер толком не мог:
	-- единственным условием был атрибут TutorialOreInstalled, а режим
	-- "Skip" не проверял вообще ничего. В обучении v7 состояние ведёт
	-- TutorialService — он же выдаёт награду и поднимает TutorialVersion,
	-- и клиенту тут решать нечего.
	--
	-- Сам RemoteEvent оставлен живым намеренно: на него может быть
	-- подписан клиентский код, которого мы здесь не видим (и старые
	-- клиенты в момент раскатки). Теперь он делает ровно одно безопасное
	-- действие — приводит NeedsTutorial и панель квестов в соответствие с
	-- уже сохранённым профилем, ничего не начисляя.
	--------------------------------------------------------------------------
	tutorialRemote.OnServerEvent:Connect(function(player)
		local profile = activeProfile(player)
		if not profile then return end
		if profile.Data.TutorialVersion >= Config.Tutorial.Version then
			player:SetAttribute("NeedsTutorial", false)
			if Services.CombatService then Services.CombatService:FinishTutorialProtection(player) end
			if Services.QuestService then Services.QuestService:SendState(player) end
		end
	end)
end

function DataService:Start()
	-- Автосейв
	task.spawn(function()
		while true do
			task.wait(Config.Data.AutosaveInterval)
			for player, profile in profiles do
				if not profile.Closing then
					task.spawn(function()
						local ok, reason = self:SaveProfile(player)
						local leaseUnsafe = reason == "DataStoreError"
							and os.time() + Config.Data.AutosaveInterval >= (profile.LeaseExpiresAt or 0)
						if not ok and (reason == "LockLost" or leaseUnsafe) and player.Parent then
							profile.Invalid = true
							local message = reason == "LockLost"
								and "Your data session was opened elsewhere. Please rejoin."
								or "Data saving is temporarily unavailable. Please rejoin safely."
							player:Kick(Localization.Translate(player.LocaleId, message))
						end
					end)
				end
			end
		end
	end)

	game:BindToClose(function()
		local remaining = 0
		local completed = Instance.new("BindableEvent")
		for player, profile in profiles do
			if not profile.Closing then
				remaining += 1
				task.spawn(function()
					self:UnloadProfile(player)
					remaining -= 1
					completed:Fire()
				end)
			end
		end
		while remaining > 0 do
			completed.Event:Wait()
		end
		completed:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- ЖИЗНЕННЫЙ ЦИКЛ ПРОФИЛЯ
--------------------------------------------------------------------------------

function DataService:LoadProfile(player)
	if profiles[player] then
		return false, "AlreadyLoaded"
	end
	local sessionId = (game.JobId ~= "" and game.JobId or "studio") .. ":" .. HttpService:GenerateGUID(false)
	local data
	local memoryOnly = false
	if not store then
		if not RunService:IsStudio() then
			return false, "DataStoreUnavailable"
		end
		local fresh = deepCopy(DEFAULT_DATA)
		fresh.FirstJoinedAt = os.time()
		data = reconcile(fresh, player)
		profiles[player] = { Data = data, SessionId = sessionId, MemoryOnly = true, PendingReceiptSaves = {} }
	else
		local lastReason = "DataStoreError"
		for attempt = 1, Config.Data.SaveRetries do
			local outcome
			local studioLockedSnapshot
			local ok, result = pcall(function()
				return store:UpdateAsync(profileKey(player), function(stored)
					outcome = nil
					if stored ~= nil and typeof(stored) ~= "table" then
						outcome = "CorruptProfile"
						return nil
					end
					local candidate = deepCopy(stored or DEFAULT_DATA)
					if not stored then
						candidate.FirstJoinedAt = os.time() -- ровно здесь и определяется "новый игрок", см. StarterPackClaimed/FirstJoinedAt в DEFAULT_DATA
					end
					local now = os.time()
					local foreignLock = typeof(candidate._SessionId) == "string"
						and candidate._SessionId ~= sessionId
						and (tonumber(candidate._SessionExpiresAt) or 0) > now
					if foreignLock then
						if RunService:IsStudio() then
							studioLockedSnapshot = candidate
							outcome = "StudioMemoryOnly"
						else
							outcome = "Locked"
						end
						return nil
					end
					reconcile(candidate, player)
					candidate._SessionId = sessionId
					candidate._SessionExpiresAt = now + Config.Data.SessionLockTimeout
					outcome = "Acquired"
					return candidate
				end)
			end)
			if ok and outcome == "Acquired" and typeof(result) == "table" then
				data = result
				break
			end
			if ok and outcome == "StudioMemoryOnly" and typeof(studioLockedSnapshot) == "table" then
				data = reconcile(studioLockedSnapshot, player)
				memoryOnly = true
				warn("[DataService] Профиль занят другим сервером; Studio использует снимок только в памяти и не будет его сохранять")
				break
			end
			if outcome == "CorruptProfile" then
				return false, outcome
			end
			lastReason = outcome == "Locked" and "Locked" or "DataStoreError"
			if attempt < Config.Data.SaveRetries then
				task.wait(Config.Data.SaveRetryDelay * attempt)
			end
		end
		if not data then
			if RunService:IsStudio() and lastReason == "DataStoreError" then
				warn("[DataService] DataStore API недоступен в Studio — профиль работает только в памяти")
				local fresh = deepCopy(DEFAULT_DATA)
				fresh.FirstJoinedAt = os.time()
				data = reconcile(fresh, player)
				profiles[player] = { Data = data, SessionId = sessionId, MemoryOnly = true, PendingReceiptSaves = {} }
			else
				return false, lastReason
			end
		elseif memoryOnly then
			profiles[player] = { Data = data, SessionId = sessionId, MemoryOnly = true, PendingReceiptSaves = {} }
		else
			profiles[player] = { Data = data, SessionId = sessionId, LeaseExpiresAt = data._SessionExpiresAt, PendingReceiptSaves = {} }
		end
	end

	if not player.Parent then
		self:UnloadProfile(player)
		return false, "PlayerLeft"
	end
	-- ВЕТЕРАНЫ НЕ ПРОХОДЯТ ПРОЛОГ ЗАНОВО. Поднятие Config.Tutorial.Version
	-- до 7 без этой проверки отправляло КАЖДОГО старого игрока в пролог
	-- для новичка — а вместе с ним включались все гейты обучения:
	-- заглушенные тосты, закрытые дейлики, выключенные волны гоблинов,
	-- заблокированное открытие жеод и подиум. Профиль с реальным
	-- прогрессом получает обучение засчитанным — без награды и бейджа.
	if data.TutorialVersion < Config.Tutorial.Version then
		local veteran = (tonumber(data.TutorialVersion) or 0) > 0
			or (tonumber(data.Rebirths) or 0) > 0
			or (tonumber(data.PickaxeIndex) or 0) > 0
			or (tonumber(data.CartIndex) or 0) > 0
			or (tonumber(data.MineIndex) or 0) > 1
		if veteran then
			data.TutorialVersion = Config.Tutorial.Version
			data.TutorialCompletedAt = tonumber(data.TutorialCompletedAt) or os.time()
			data.TutorialStep = 1
		end
	end
	player:SetAttribute("NeedsTutorial", data.TutorialVersion < Config.Tutorial.Version)

	-- МИГРАЦИЯ ПОД ОБУЧЕНИЕ v7.
	--
	-- Поля MineRepaired в старых сейвах нет, и без этой строки КАЖДЫЙ
	-- действующий игрок зашёл бы в мёртвую шахту: экспедиция заблокирована,
	-- модель чёрная, а починить её можно только покупкой первого шага
	-- Config.MineChain — который у него давно куплен, то есть повторить его
	-- уже нельзя. Поэтому любой профиль с признаками прогресса (куплен хоть
	-- один апгрейд шахты, есть престиж, пройден прежний гайд или уже была
	-- тележка) считается владеющим рабочей шахтой.
	local hasMineProgress = (tonumber(data.MineIndex) or 0) > 0
		or (tonumber(data.Rebirths) or 0) > 0
		or (tonumber(data.TutorialVersion) or 0) > 0
		or data.CartUnlocked == true
	if data.MineRepaired == nil then
		data.MineRepaired = hasMineProgress
	end
	-- ПОВТОРНЫЙ ПРОГОН ДЛЯ УЖЕ ИСПОРЧЕННЫХ СЕЙВОВ. Пока MineRepaired лежал
	-- в DEFAULT_DATA, миграция выше не срабатывала, и в сейвы успело
	-- записаться false у игроков с прогрессом. Один раз на профиль
	-- чиним их по тем же признакам.
	if data.MineRepairedFixV1 ~= true then
		data.MineRepairedFixV1 = true
		if data.MineRepaired ~= true and hasMineProgress then
			data.MineRepaired = true
		end
	end
	player:SetAttribute("MineRepaired", data.MineRepaired == true)
	if player:GetAttribute("NeedsTutorial") and Services.CombatService then
		-- Новичок ещё не прошёл гайд — временная защита на время его
		-- прохождения и первых апгрейдов (см. Config.Protection.NewbieDuration).
		-- Использует ту же инфраструктуру Protected/ProtectionEndsAtUnix, что
		-- и обычный щит-кнопка — таймер над головой рисует клиент сам.
		Services.CombatService:GrantTutorialProtection(player, Config.Protection.NewbieDuration)
	end

	-- Минимальный UI: деньги через стандартный leaderboard
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local money = Instance.new("StringValue") -- НЕ IntValue/NumberValue: Money теперь BigNum (см. Shared.BigNum) и физически не помещается ни в 32-битный int, ни (после десятков ребёртов) точно в double — храним готовую отформатированную строку ("1.23Qa")
	money.Name = "Money"
	money.Value = NumberFormat.abbreviate(BigNum.fromData(data.Money))
	money.Parent = leaderstats
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Prestige" -- см. комментарий в syncLeaderstats выше
	rebirths.Value = data.Rebirths
	rebirths.Parent = leaderstats
	local cartDamage = Instance.new("IntValue")
	cartDamage.Name = "Cart Damage"
	cartDamage.Value = math.floor(data.CartDamage)
	cartDamage.Parent = leaderstats
	leaderstats.Parent = player

	-- Для клиентского баннера "стартовый пак" (StarterPackUI.client.lua) —
	-- сколько бы раз ни пересчитывались другие атрибуты, эти два выставляем
	-- один раз здесь: FirstJoinedAt не меняется всю жизнь профиля, а
	-- StarterPackClaimed дальше обновляет только сама покупка (см.
	-- MonetizationService).
	player:SetAttribute("FirstJoinedAt", tonumber(data.FirstJoinedAt) or 0)
	player:SetAttribute("StarterPackClaimed", data.StarterPackClaimed == true)
	return true
end

function DataService:SaveProfile(player, release)
	local profile = profiles[player]
	if not profile then
		return false, "NoProfile"
	end
	if profile.MemoryOnly then
		return true
	end
	while profile.Saving do
		task.wait()
		if profile.Invalid then
			return false, "LockLost"
		end
	end
	profile.Saving = true
	local snapshot = deepCopy(profile.Data)
	snapshot.Username = player.Name
	snapshot.DisplayName = player.DisplayName
	snapshot.UserId = player.UserId
	snapshot.SchemaVersion = 3
	snapshot.LastSeenAt = os.time()
	local failureReason = "DataStoreError"
	for attempt = 1, Config.Data.SaveRetries do
		local outcome
		local ok = pcall(function()
			store:UpdateAsync(profileKey(player), function(current)
				outcome = nil
				if typeof(current) ~= "table" or current._SessionId ~= profile.SessionId then
					outcome = "LockLost"
					return nil
				end
				if release then
					snapshot._SessionId = nil
					snapshot._SessionExpiresAt = nil
				else
					snapshot._SessionId = profile.SessionId
					snapshot._SessionExpiresAt = os.time() + Config.Data.SessionLockTimeout
				end
				outcome = "Saved"
				return snapshot
			end)
		end)
		if ok and outcome == "Saved" then
			profile.Data.Username = snapshot.Username
			profile.Data.DisplayName = snapshot.DisplayName
			profile.Data.LastSeenAt = snapshot.LastSeenAt
			if release then
				profile.LeaseExpiresAt = nil
			else
				profile.LeaseExpiresAt = snapshot._SessionExpiresAt
			end
			profile.Saving = false
			return true
		end
		if outcome == "LockLost" then
			profile.Invalid = true
			failureReason = "LockLost"
			break
		end
		if attempt < Config.Data.SaveRetries then
			task.wait(Config.Data.SaveRetryDelay * attempt)
		end
	end
	profile.Saving = false
	warn("[DataService] Не удалось сохранить профиль", player.Name)
	return false, failureReason
end

function DataService:UnloadProfile(player)
	local profile = profiles[player]
	if not profile or profile.Closing then
		return
	end
	profile.Closing = true
	self:SaveProfile(player, true)
	profiles[player] = nil
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function DataService:IsProfileReady(player)
	return activeProfile(player) ~= nil
end

function DataService:GetGeodeData(player)
	local profile = activeProfile(player)
	return profile and profile.Data or nil
end

function DataService:IsTutorialRequired(player)
	local profile = activeProfile(player)
	return profile ~= nil and profile.Data.TutorialVersion < Config.Tutorial.Version
end

-- Used for bank evacuation: mutation is rolled back if the immediate durable
-- save fails, so a geode never disappears from the cart without a reward.
function DataService:AddGeodesAndSave(player, counts, transactionId)
	local profile = activeProfile(player)
	if not profile or typeof(transactionId) ~= "string" or transactionId == "" then return false, "Invalid" end
	if profile.Data.GeodeEvacuations[transactionId] then
		local saved = self:SaveProfile(player) == true
		return saved, saved and "Committed" or "Pending" -- retry an ambiguous/pending durable save
	end
	for geodeType, amount in counts do
		if Config.Geodes.Types[geodeType] and typeof(amount) == "number" and amount > 0 then
			profile.Data.Geodes[geodeType] = (profile.Data.Geodes[geodeType] or 0) + math.floor(amount)
		end
	end
	profile.Data.GeodeEvacuations[transactionId] = os.time()
	table.insert(profile.Data.GeodeEvacuationOrder, transactionId)
	while #profile.Data.GeodeEvacuationOrder > 100 do
		local oldId = table.remove(profile.Data.GeodeEvacuationOrder, 1)
		profile.Data.GeodeEvacuations[oldId] = nil
	end
	if self:SaveProfile(player) then
		return true, "Committed"
	end
	-- Keep the mutation and transaction marker in memory. The caller may
	-- restore physical cargo; retrying this same id only retries persistence
	-- and can never increment the counters twice.
	return false, "Pending"
end

local function readReceiptTombstone(purchaseId)
	if not receiptStore then
		return false, nil
	end
	for attempt = 1, Config.Data.SaveRetries do
		local ok, result = pcall(function()
			return receiptStore:GetAsync(receiptKey(purchaseId))
		end)
		if ok then
			return true, result
		end
		if attempt < Config.Data.SaveRetries then
			task.wait(Config.Data.SaveRetryDelay * attempt)
		end
	end
	return false, nil
end

local function writeReceiptTombstone(receiptInfo)
	if not receiptStore then
		return false
	end
	for attempt = 1, Config.Data.SaveRetries do
		local ok, result = pcall(function()
			return receiptStore:UpdateAsync(receiptKey(receiptInfo.PurchaseId), function(existing)
				if existing then
					return existing
				end
				return {
					PlayerId = receiptInfo.PlayerId,
					ProductId = receiptInfo.ProductId,
					GrantedAt = os.time(),
				}
			end)
		end)
		if ok and typeof(result) == "table" and result.PlayerId == receiptInfo.PlayerId and result.ProductId == receiptInfo.ProductId then
			return true
		end
		if attempt < Config.Data.SaveRetries then
			task.wait(Config.Data.SaveRetryDelay * attempt)
		end
	end
	return false
end

-- Единственная точка durable-обработки Developer Product. grant(data) не
-- должен yield; возвращает true только после успешной выдачи/записи награды.
-- Профильный журнал связывает выдачу с сохранением, отдельный DataStore
-- tombstone не даёт старому PurchaseId повториться после очистки кэша.
function DataService:ProcessDeveloperProduct(player, receiptInfo, grant)
	local purchaseId = tostring(receiptInfo.PurchaseId or "")
	if purchaseId == "" or typeof(receiptInfo.ProductId) ~= "number" or typeof(grant) ~= "function" then
		return "Retry"
	end
	local initialProfile = activeProfile(player)
	if initialProfile and initialProfile.MemoryOnly and RunService:IsStudio() then
		local existing = initialProfile.Data.ProcessedReceipts[purchaseId]
		if existing then return "AlreadyCommitted" end
		local ok, granted = pcall(grant, initialProfile.Data)
		if not ok or granted ~= true then return "Retry" end
		initialProfile.Data.ProcessedReceipts[purchaseId] = { ProductId = receiptInfo.ProductId, GrantedAt = os.time(), Tombstoned = true }
		syncLeaderstats(player, initialProfile.Data)
		return "Committed"
	end

	local tombstoneOk, tombstone = readReceiptTombstone(purchaseId)
	if not tombstoneOk then
		return "Retry"
	end
	if tombstone then
		if typeof(tombstone) ~= "table" then
			warn("[DataService] Corrupt receipt tombstone", purchaseId)
			return "Retry"
		end
		if tombstone.PlayerId ~= receiptInfo.PlayerId or tombstone.ProductId ~= receiptInfo.ProductId then
			warn(("[DataService] Receipt collision %s: stored player/product %s/%s, got %s/%s"):format(
				purchaseId, tostring(tombstone.PlayerId), tostring(tombstone.ProductId), tostring(receiptInfo.PlayerId), tostring(receiptInfo.ProductId)
			))
			return "Retry"
		end
		return "AlreadyCommitted"
	end

	local profile = activeProfile(player)
	if not profile or profile.MemoryOnly then
		return "NotReady"
	end
	profile.ReceiptBusy = profile.ReceiptBusy or {}
	while profile.ReceiptBusy[purchaseId] do
		task.wait()
		profile = activeProfile(player)
		if not profile then
			return "NotReady"
		end
	end
	profile.ReceiptBusy[purchaseId] = true

	local function finish(result)
		if profile and profile.ReceiptBusy then
			profile.ReceiptBusy[purchaseId] = nil
		end
		return result
	end

	local existing = profile.Data.ProcessedReceipts[purchaseId]
	if existing then
		if typeof(existing) ~= "table" or existing.ProductId ~= receiptInfo.ProductId then
			warn("[DataService] ProductId mismatch in profile receipt", purchaseId)
			return finish("Retry")
		end
		if writeReceiptTombstone(receiptInfo) then
			profile.PendingReceiptSaves[purchaseId] = nil
			existing.Tombstoned = true
			self:SaveProfile(player) -- сохраняем статус, чтобы запись можно было безопасно очистить
			return finish("AlreadyCommitted")
		end
		return finish("Retry")
	end

	local ok, granted = pcall(grant, profile.Data)
	if not ok or granted ~= true then
		if not ok then
			warn("[DataService] Developer Product grant failed", purchaseId, granted)
		end
		return finish("Retry")
	end

	profile.Data.ProcessedReceipts[purchaseId] = {
		ProductId = receiptInfo.ProductId,
		GrantedAt = os.time(),
		Tombstoned = false,
	}
	table.insert(profile.Data.ProcessedReceiptOrder, purchaseId)
	while #profile.Data.ProcessedReceiptOrder > Config.Data.ReceiptHistoryLimit do
		local removableIndex
		for index, oldId in profile.Data.ProcessedReceiptOrder do
			local oldReceipt = profile.Data.ProcessedReceipts[oldId]
			if oldReceipt and oldReceipt.Tombstoned == true then
				removableIndex = index
				break
			end
		end
		if not removableIndex then break end
		local oldId = table.remove(profile.Data.ProcessedReceiptOrder, removableIndex)
		profile.Data.ProcessedReceipts[oldId] = nil
	end
	profile.PendingReceiptSaves[purchaseId] = true

	local saved = self:SaveProfile(player)
	if not saved then
		return finish("Retry") -- marker остаётся в памяти; retry не вызовет grant повторно
	end
	syncLeaderstats(player, profile.Data)
	if not writeReceiptTombstone(receiptInfo) then
		return finish("Retry") -- профильный marker не даст повторную выдачу
	end
	profile.Data.ProcessedReceipts[purchaseId].Tombstoned = true
	profile.PendingReceiptSaves[purchaseId] = nil
	self:SaveProfile(player) -- tombstone уже durable; фиксируем безопасный для pruning marker
	return finish("Committed")
end

function DataService:GetPaidProtectionEndsAt(player)
	local profile = profiles[player]
	return profile and tonumber(profile.Data.PaidProtectionEndsAt) or 0
end

function DataService:HasClaimedStarterPack(player)
	local profile = profiles[player]
	return profile ~= nil and profile.Data.StarterPackClaimed == true
end

-- Помечает пак забранным — идемпотентно, повторный вызов ничего не портит.
-- НЕ сохраняет профиль сам — вызывающий (MonetizationService, в момент
-- обработки покупки) и так сохраняет через ProcessDeveloperProduct.
function DataService:MarkStarterPackClaimed(player)
	local profile = profiles[player]
	if profile then
		profile.Data.StarterPackClaimed = true
	end
end

function DataService:ClearPaidProtection(player)
	local profile = activeProfile(player)
	if not profile then return false end
	profile.Data.PaidProtectionEndsAt = 0
	return self:SaveProfile(player) == true
end

function DataService:GetPendingCartFills(player)
	local profile = activeProfile(player)
	return profile and profile.Data.PendingCartFills or {}
end

function DataService:CompletePendingCartFill(player, purchaseId)
	local profile = activeProfile(player)
	local entitlement = profile and profile.Data.PendingCartFills[purchaseId]
	if not entitlement then
		return false
	end
	profile.Data.PendingCartFills[purchaseId] = nil
	local saved = self:SaveProfile(player)
	if not saved then
		profile.Data.PendingCartFills[purchaseId] = entitlement
		return false
	end
	return true
end

-- Возвращает BigNum (см. Shared.BigNum), а НЕ обычное число.
--
-- ВНИМАНИЕ: здесь раньше стоял комментарий, утверждавший, что "весь код
-- вида `GetMoney(player) < cost` продолжает работать благодаря
-- метаметодам". ЭТО НЕВЕРНО и было источником падений: Luau требует
-- одинакового ТИПА обоих операндов ДО того, как посмотрит на __lt/__le,
-- поэтому `bigNumMoney < 5000` падает с "attempt to compare table <
-- number", а `bigNumMoney == 5000` молча возвращает false.
--
-- ПРАВИЛЬНО сравнивать деньги так (работает с любой смесью типов):
--     if BigNum.lt(Services.DataService:GetMoney(player), cost) then ...
--     if BigNum.ge(money, step.Cost) then ...
-- Перед math.floor/math.max/DataStore — :toNumberClamped().
-- Для вывода в текст — NumberFormat.abbreviate/withSeparators.
function DataService:GetMoney(player)
	local profile = profiles[player]
	if not profile then return BigNum.new(0) end
	return BigNum.fromData(profile.Data.Money)
end

local pendingCoinBurst = {} -- [player] = true — дебаунс монеток, см. AddMoney ниже

-- amount — обычное число ЛИБО BigNum. Раньше принималось только number,
-- а BigNum молча отбрасывался (`typeof(amount) ~= "number"` → return false),
-- то есть начисление крупной награды тихо не происходило вообще. Теперь
-- принимается и то, и другое, а в дальнейшую логику (порог для монеток,
-- знак суммы) уходит уже нормализованный BigNum.
function DataService:AddMoney(player, amount, coinOrigin, suppressCoinBurst)
	local profile = activeProfile(player)
	if not profile then
		return false
	end
	if BigNum.is(amount) then
		-- уже BigNum — ничего не проверяем, невалидные значения BigNum
		-- ловит у себя внутри (NaN/inf нормализуются в 0)
	elseif typeof(amount) == "number" then
		if amount ~= amount or math.abs(amount) == math.huge then
			return false
		end
	else
		return false
	end
	local delta = BigNum.new(amount)
	amount = delta -- дальше по функции используется только знак, см. ниже
	local updatedMoney = (BigNum.fromData(profile.Data.Money) + delta):clamp(BigNum.new(0), MONEY_SAFETY_CAP)
	profile.Data.Money = updatedMoney:toData()

	local leaderstats = player:FindFirstChild("leaderstats")
	local money = leaderstats and leaderstats:FindFirstChild("Money")
	if money then
		money.Value = NumberFormat.abbreviate(updatedMoney)
	end

	-- 3D-монетки с зелёным трейлом (см. BankService:SpawnCoinBurst) — от
	-- ЛЮБОГО источника денег (продажа, сейф, квесты, ребёрт, дейли-награда
	-- и т.д.), потому что AddMoney — единственная функция, через которую
	-- деньги вообще начисляются. Дебаунс на 0.25с на игрока, чтобы не
	-- заспамить пачкой монеток при продаже сразу многих кусков руды подряд
	-- (та же пауза, что раньше жила только внутри BankService).
	-- coinOrigin — необязательно, ОТКУДА физически вылетают монетки (касса
	-- банка при продаже, сейф при сборе дохода) — без него падают у ног
	-- игрока (квесты/ребёрт/дейли-награда, там нет физического источника).
	-- suppressCoinBurst — для источников денег, у которых УЖЕ ЕСТЬ свой
	-- собственный визуал награды (например, сундук гоблина сам показывает
	-- монетку, вылетающую из сундука, когда тот открывается) — без этого
	-- флага монетка вылетала сразу через 0.25с после смерти гоблина, то
	-- есть ЗАДОЛГО до того, как сундук вообще открывается на экране
	-- (~3 секунды тряски), и выглядело так, будто награда выпала раньше
	-- самого сундука.
	-- `amount > 0` здесь НЕЛЬЗЯ: amount теперь BigNum, а Luau не сравнивает
	-- table с number (см. шапку Shared/BigNum.lua). isPositive() — та же
	-- проверка, но без падения.
	if not suppressCoinBurst and delta:isPositive() and player.Parent and Services.BankService and not pendingCoinBurst[player] then
		-- Weight — сколько начислений пришло в окне дебаунса: клиент по нему
		-- решает, сколько монет высыпать (одна продажа — горстка, целая
		-- тележка — дождь).
		pendingCoinBurst[player] = { Origin = coinOrigin, Weight = 1 }
		task.delay(0.25, function()
			local pending = pendingCoinBurst[player]
			pendingCoinBurst[player] = nil
			if player.Parent then
				Services.BankService:SpawnCoinBurst(player, pending and pending.Origin, pending and pending.Weight or 1)
			end
		end)
	elseif pendingCoinBurst[player] and delta:isPositive() then
		pendingCoinBurst[player].Weight += 1
		-- Догоняющий вызов знает источник, а первый в окне — нет:
		-- берём этот, монетки не должны сыпаться "ниоткуда".
		if coinOrigin and not pendingCoinBurst[player].Origin then
			pendingCoinBurst[player].Origin = coinOrigin
		end
	end
	return true
end

-- Контекстные подсказки (щит/PvP/выпавшая руда/rebirth, см. CombatService/
-- CartService/UpgradeService) — каждая должна показаться ИГРОКУ РОВНО ОДИН
-- РАЗ за аккаунт. Возвращает true только при первом вызове с данным ключом —
-- вызывающий код сам решает, показывать ли NotifyService:Show в этом случае.
function DataService:MarkHintSeen(player, hintKey)
	local profile = activeProfile(player)
	if not profile then
		return false
	end
	profile.Data.SeenHints = profile.Data.SeenHints or {}
	if profile.Data.SeenHints[hintKey] then
		return false
	end
	profile.Data.SeenHints[hintKey] = true
	return true
end

function DataService:MarkHintSeenAndSave(player, hintKey)
	local profile = activeProfile(player)
	if not profile then return false end
	profile.Data.SeenHints = profile.Data.SeenHints or {}
	if profile.Data.SeenHints[hintKey] then return false end
	profile.Data.SeenHints[hintKey] = true
	if not self:SaveProfile(player) then
		profile.Data.SeenHints[hintKey] = nil
		return false
	end
	return true
end

function DataService:ClearHintSeenAndSave(player, hintKey)
	local profile = activeProfile(player)
	if not profile or not profile.Data.SeenHints or not profile.Data.SeenHints[hintKey] then return false end
	profile.Data.SeenHints[hintKey] = nil
	if not self:SaveProfile(player) then
		profile.Data.SeenHints[hintKey] = true
		return false
	end
	return true
end

function DataService:GetCartDamage(player)
	local profile = profiles[player]
	return profile and tonumber(profile.Data.CartDamage) or 0
end

function DataService:GetPlayTime(player)
	local profile = profiles[player]
	return profile and math.max(0, tonumber(profile.Data.PlayTimeSeconds) or 0) or 0
end

function DataService:AddPlayTime(player, seconds)
	local profile = activeProfile(player)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	if not profile or seconds <= 0 then return false end
	profile.Data.PlayTimeSeconds = math.max(0, (tonumber(profile.Data.PlayTimeSeconds) or 0) + seconds)
	return true
end

function DataService:AddCartDamage(player, amount)
	local profile = activeProfile(player)
	if not profile or typeof(amount) ~= "number" or amount <= 0 then
		return false
	end
	profile.Data.CartDamage = math.max(0, (tonumber(profile.Data.CartDamage) or 0) + amount)
	local leaderstats = player:FindFirstChild("leaderstats")
	local value = leaderstats and leaderstats:FindFirstChild("Cart Damage")
	if value then
		value.Value = math.floor(profile.Data.CartDamage)
	end
	return true
end

-- Промокод (Discord/меню настроек, см. Config.PromoCodes). Возвращает
-- строку-результат ("Ok" / "AlreadyRedeemed" / "Invalid") + числовую
-- награду в деньгах (0, если результат не "Ok") — клиент сам решает,
-- как это показать игроку, текст не наше дело на сервере.
function DataService:RedeemCode(player, code)
	local profile = activeProfile(player)
	if not profile then
		return "Invalid", 0
	end
	local normalized = code:upper():gsub("%s+", "")
	local reward = Config.PromoCodes[normalized]
	if not reward then
		for configuredCode, configuredReward in Config.PromoCodes do
			if tostring(configuredCode):upper():gsub("%s+", "") == normalized then
				reward = configuredReward
				break
			end
		end
	end
	if not reward then
		return "Invalid", 0
	end
	local expiresAt = reward.ExpiresAt
	if typeof(expiresAt) == "string" then
		local year, month, day = expiresAt:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
		if year then
			local ok, dateTime = pcall(DateTime.fromUniversalTime, tonumber(year), tonumber(month), tonumber(day), 23, 59, 59)
			expiresAt = ok and dateTime.UnixTimestamp or 0
		else
			expiresAt = 0
		end
	end
	if reward.Enabled == false or (typeof(expiresAt) == "number" and os.time() > expiresAt) then
		return "Expired", 0
	end
	if table.find(profile.Data.RedeemedCodes, normalized) then
		return "AlreadyRedeemed", 0
	end
	-- v16: код с табло лайков открывается только по достижении цели.
	if reward.RequiresLikes and (tonumber(Config.LikeGoals and Config.LikeGoals.CurrentLikes) or 0) < reward.RequiresLikes then
		return "Invalid", 0
	end
	table.insert(profile.Data.RedeemedCodes, normalized)
	if reward.Money and reward.Money > 0 then
		self:AddMoney(player, reward.Money)
	end
	if reward.Chest and Services and Services.GearService then
		pcall(Services.GearService.GrantChest, Services.GearService, player, reward.Chest, 1)
	end
	return "Ok", reward.Money or 0
end

-- index (0-based, сколько шагов куплено) → тир (1-based).
function DataService:GetBranchIndex(player, kind)
	local profile = profiles[player]
	if not profile then
		return 0
	end
	return profile.Data[kind .. "Index"] or 0
end

function DataService:GetBranchTier(player, kind)
	return 1 + self:GetBranchIndex(player, kind)
end

-- ФИКС "ПРОГРЕССИЯ СЛИШКОМ БЫСТРАЯ / x2-x4 ДЕНЬГИ ПОЗВОЛЯЮТ КУПИТЬ НЕСКОЛЬКО
-- ТИРОВ ЗА ОДИН ЗАХОД": раньше Cost из Config.MineChain/CartChain/
-- PickaxeChain/Config.Rebirth шёл в UI/списание НАПРЯМУЮ, БЕЗ поправки на то,
-- сколько игрок реально зарабатывает за то же самое действие (кусок руды).
-- Кто-то с пассом x2/x4/x6/x8 Cash копит нужную сумму В РАЗЫ быстрее того же
-- игрока без пассов — при статичных ценах это означает "купить сразу
-- несколько тиров за один заход", а не "прогрессировать быстрее, но всё
-- ещё по одному шагу за раз".
--
-- ЭФФЕКТИВНАЯ ЦЕНА = базовая цена × ProgressionSlowdown (общее замедление
-- прогрессии, см. запрос "прогрессию сделать дольше") × claw-back часть
-- денежного множителя игрока (ProgressionMultiplierClawback — какая доля
-- бонуса x2/x4/etc "отбирается" ростом цены, а не отдаётся бесплатно).
-- ClawbackShare = 0 → множитель денег не трогает цены вообще (как было).
-- ClawbackShare = 1 → множитель денег полностью компенсируется ростом цены
-- (x2 денег = x2 цена, эффективно НЕ ускоряет прогрессию вообще).
-- Значение из Config — где-то посередине: бонус всё ещё чувствуется, но не
-- обнуляет саму идею тиров/прогрессии.
--------------------------------------------------------------------------------
-- Кто-то с пассом x2/x4/x6/x8 Cash копит нужную сумму В РАЗЫ быстрее того же
-- игрока без пассов — раньше здесь был "clawback": цены апгрейдов/ребёртов
-- дополнительно росли в зависимости от денежного множителя игрока, чтобы
-- частично компенсировать/забрать обратно эффект от x2/x4 денег (см.
-- историю — Config.Economy.ProgressionClawbackSteps). По прямому запросу
-- ("искусственное замедление прогрессии в зависимости от дохода — убрать")
-- механика полностью убрана: денежный множитель игрока теперь ВООБЩЕ не
-- влияет на цены — x2/x4/x6/x8 Cash дают чистое ускорение без скрытого
-- "налога" в виде подорожавших апгрейдов. ProgressionSlowdown ниже
-- НЕТРОНУТ — это отдельный, не завязанный на доход игрока рычаг (плоское
-- замедление одинаковое для всех, не наказывает конкретно за покупку
-- cash-пассов), запрос был именно про доходозависимую часть.
--------------------------------------------------------------------------------
local function effectiveCost(player, baseCost)
	local slowdown = Config.Economy and Config.Economy.ProgressionSlowdown or 1
	if BigNum.is(baseCost) then
		-- Цена ребёрта (GetRebirthCost) — растёт без реального потолка, так
		-- что уже не всегда влезает в double, отсюда BigNum на входе.
		return (baseCost * slowdown):floor()
	end
	return math.floor(baseCost * slowdown + 0.5)
end

function DataService:GetBranchMaxTier(kind)
	return 1 + #CHAIN_CONFIG[kind]
end

-- Потолок тира от числа ребёртов (НЕ физический максимум цепочки) — см.
-- Config.Rebirth. 0 ребёртов → BaseTierCap; каждый следующий поднимает
-- потолок, пока не упрётся в MaxTierCap (= реальная длина цепочек).
function DataService:GetTierCap(player)
	local cfg = Config.Rebirth
	return math.min(cfg.BaseTierCap + self:GetRebirths(player) * cfg.TierCapPerRebirth, cfg.MaxTierCap)
end

-- v3: потолок КОНКРЕТНОЙ ветки. Кап ребёрта действует только на ветки из
-- Config.TierCappedBranches (пещера); перки — до конца своей цепочки.
function DataService:GetBranchCap(player, kind)
	if Config.TierCappedBranches and not Config.TierCappedBranches[kind] then
		return self:GetBranchMaxTier(kind)
	end
	return math.min(self:GetTierCap(player), self:GetBranchMaxTier(kind))
end

-- Следующий шаг ветки (nil, если ветка уже на максимуме ЛИБО упёрлась в
-- текущий тир-кап от числа ребёртов — за новым потолком нужно к НПС ребёрта).
-- ОТОБРАЖАЕМЫЙ ТИР ШАХТЫ.
--
-- Внутренний тир сломанной шахты — 1 (Config.MineTiers начинается с
-- единицы, нулевого элемента там нет и быть не может, см. Config.Mine.Broken).
-- Но игроку она показывается как ТИР 0: это модель первого тира с
-- содранными текстурами и чёрным неоном, то есть «шахта, которой ещё
-- нет». Первая покупка в ветке — починка — переводит её в честный тир 1.
function DataService:GetDisplayTier(player, kind)
	if kind == "Mine" and player:GetAttribute("MineRepaired") == false then
		return 0
	end
	return self:GetBranchTier(player, kind)
end

function DataService:GetNextBranchStep(player, kind)
	-- ПОЧИНКА — НУЛЕВОЙ ШАГ ВЕТКИ ШАХТЫ. Не берётся из Config.MineChain и
	-- не двигает MineIndex: после неё следующим шагом станет обычный
	-- MineChain[1] (тир 2), как будто починки в цепочке и не было.
	if kind == "Mine" and player:GetAttribute("MineRepaired") == false then
		return {
			Tier = 1,
			-- Во время обучения починка бесплатна (см. Config.Mine.Broken):
			-- пролог больше не заставляет копить, он про механики.
			Cost = player:GetAttribute("NeedsTutorial") == true
				and (Config.Mine.Broken.RepairCostDuringTutorial or 0)
				or effectiveCost(player, Config.Mine.Broken.RepairCost),
			Repair = true,
		}
	end
	local nextTier = self:GetBranchTier(player, kind) + 1
	if nextTier > self:GetBranchCap(player, kind) then
		return nil
	end
	local step = CHAIN_CONFIG[kind][self:GetBranchIndex(player, kind) + 1]
	if not step then
		return nil
	end
	-- Копия, а НЕ правка CHAIN_CONFIG на месте — та же самая таблица
	-- используется ДЛЯ ВСЕХ игроков (общий Config), т.к. эффективная цена
	-- у каждого своя (зависит от его денежного множителя).
	return { Tier = step.Tier, Cost = effectiveCost(player, step.Cost) }
end

function DataService:IncrementBranch(player, kind)
	local profile = activeProfile(player)
	if not profile then
		return false
	end
	local field = kind .. "Index"
	local nextTier = self:GetBranchTier(player, kind) + 1
	if profile.Data[field] < #CHAIN_CONFIG[kind] and nextTier <= self:GetBranchCap(player, kind) then
		profile.Data[field] += 1
		return true
	end
	return false
end

-- Денежная стоимость СЛЕДУЮЩЕГО ребёрта — растёт геометрически, отдельно
-- от того, что уже потрачено на прокачку до текущего потолка (тот прогресс
-- всё равно сгорает при ребёрте).
-- Цена ребёрта растёт В ДВА ЭТАПА (см. подробный комментарий у
-- Config.Rebirth.LateCostGrowth):
--   1) пока каждый ребёрт ещё поднимает тир-кап — крутой CostGrowth (×10),
--      он ровно поспевает за примерно десятикратным ростом дохода с
--      каждого нового тира руды;
--   2) после того как кап упёрся в MaxTierCap — гораздо более пологий
--      LateCostGrowth, потому что доход дальше растёт только линейно от
--      MultiplierPerRebirth. Без этого разделения цена уходила в отрыв от
--      дохода и ребёрт становился недостижим в принципе.
function DataService:GetRebirthCostForNumber(player, rebirthNumber)
	-- v4: престиж — фиксированная цена по номеру (Config.Prestige.CostBase/Growth/Max).
	local prestige = Config.Prestige
	if prestige and prestige.Enabled and prestige.CostBase then
		local done = math.max(0, math.floor(tonumber(rebirthNumber) or 1) - 1)
		local value = BigNum.new(prestige.CostBase) * BigNum.new(prestige.CostGrowth or 1):powInt(done)
		value = value:floor():clamp(nil, BigNum.new(prestige.CostMax or 1e15))
		return effectiveCost(player, value):clamp(nil, MONEY_SAFETY_CAP)
	end
	local cfg = Config.Rebirth
	local exponent = math.max(0, math.floor(tonumber(rebirthNumber) or 1) - 1)

	-- Сколько ребёртов реально поднимают потолок тира (обычно 5).
	local perRebirth = math.max(0, tonumber(cfg.TierCapPerRebirth) or 0)
	local cappedSteps = math.huge
	if perRebirth > 0 then
		cappedSteps = math.max(0, math.ceil(((tonumber(cfg.MaxTierCap) or 0) - (tonumber(cfg.BaseTierCap) or 0)) / perRebirth))
	end

	local steepSteps = math.min(exponent, cappedSteps)
	local lateSteps = math.max(0, exponent - steepSteps)

	local base = BigNum.new(cfg.CostBase) * BigNum.new(cfg.CostGrowth):powInt(steepSteps)
	if lateSteps > 0 then
		local lateGrowth = tonumber(cfg.LateCostGrowth) or tonumber(cfg.CostGrowth) or 1
		base = base * BigNum.new(lateGrowth):powInt(lateSteps)
	end
	base = base:clamp(nil, MONEY_SAFETY_CAP)

	return effectiveCost(player, base):clamp(nil, MONEY_SAFETY_CAP)
end

function DataService:GetRebirthCost(player)
	-- v4: цена престижа фиксированная и зависит только от номера престижа
	-- (см. GetRebirthCostForNumber) — скип престижа за Robux и окно NPC
	-- считают одну и ту же сумму.
	return self:GetRebirthCostForNumber(player, self:GetRebirths(player) + 1)
end

function DataService:GetRebirths(player)
	local profile = profiles[player]
	return profile and profile.Data.Rebirths or 0
end

-- Постоянный множитель цены кристаллов: x1.0 → x1.5 → x2.0 → ...
function DataService:GetCrystalMultiplier(player)
	-- v8: цена руды = 1 + перк Money + бафф Money скина (Config.SkinBuffs).
	local bonus = self:GetRebirths(player) * Config.Rebirth.MultiplierPerRebirth
	if Services and Services.PrestigeService then
		local ok, stat = pcall(Services.PrestigeService.Stat, Services.PrestigeService, player, "Money")
		if ok and stat then bonus += stat end
	end
	return math.max(0.1, 1 + bonus)
end

-- Сброс ВСЕХ трёх веток за множитель. Вызывается RebirthService после всех проверок.
function DataService:DoRebirth(player)
	local profile = activeProfile(player)
	if not profile then
		return false
	end
	profile.Data.MineIndex = 0
	profile.Data.CartIndex = 0
	profile.Data.PickaxeIndex = 0
	profile.Data.Rebirths += 1
	if Config.Rebirth.ResetMoney then
		profile.Data.Money = BigNum.new(0):toData()
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local money = leaderstats:FindFirstChild("Money")
		if money then
			money.Value = NumberFormat.abbreviate(BigNum.fromData(profile.Data.Money))
		end
		local rebirths = leaderstats:FindFirstChild("Prestige")
		if rebirths then
			rebirths.Value = profile.Data.Rebirths
		end
	end
	return true
end

-- Текущие тиры всех трёх веток разом (удобно для остальных сервисов).
function DataService:GetTiers(player)
	return {
		Mine = self:GetBranchTier(player, "Mine"),
		Cart = self:GetBranchTier(player, "Cart"),
		Pickaxe = self:GetBranchTier(player, "Pickaxe"),
	}
end

-- ЗАМОРОЖЕННЫЙ БОНУС СЛАЙМА (доля: 0.03 = +3% к продаже). Слайм давал
-- +1% за уровень сверх первого; уровень считался из накопленного
-- кормления. Кормления больше нет, так что значение у игрока постоянное —
-- ровно то, что он успел накормить до замены слайма торговцем.
function DataService:GetLegacySellBonus(player)
	local profile = profiles[player]
	local fed = profile and tonumber(profile.Data.SlimeFedValue) or 0
	local cfg = Config.Merchant and Config.Merchant.LegacySlime
	if not cfg or fed <= 0 then return 0 end
	local level = 1
	for index, threshold in cfg.Thresholds do
		if fed >= threshold then level = index end
	end
	return (level - 1) * cfg.BonusPerLevel
end

return DataService
