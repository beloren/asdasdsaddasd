--------------------------------------------------------------------------------
-- MonetizationService
-- Единая точка правды по Game Pass'ам и Developer Product'ам (Config.
-- GamePasses/Config.DevProducts).
--
--   • Владение каждым Game Pass проверяется ОДИН РАЗ при входе игрока
--     (UserOwnsGamePassAsync, обёрнут в pcall) и кэшируется на весь сеанс —
--     остальные сервисы читают уже готовый кэш через API ниже, не дёргая
--     Roblox API повторно на каждый чих (продажу, удар, спавн кристалла).
--   • Кэш обновляется "живьём", если пасс куплен ПРЯМО ВО ВРЕМЯ сессии
--     (MarketplaceService.PromptGamePassPurchaseFinished) — не нужно
--     перезаходить, чтобы почувствовать эффект.
--   • ЕДИНСТВЕННЫЙ MarketplaceService.ProcessReceipt на всю игру — раньше
--     жил в CombatService (только продление щита), теперь весь диспетчер
--     Developer Product'ов (включая новые Money Pack'и) собран здесь. Если
--     появится ещё один платный расходник — обрабатывай его ТОЖЕ тут, а не
--     заводи второй ProcessReceipt: он один на игру, второй просто
--     перезапишет первый и что-то перестанет засчитываться.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local BigNum = require(ReplicatedStorage.Shared.BigNum)
-- Тот же практический потолок, что MONEY_SAFETY_CAP в DataService.lua (там
-- он локальный для модуля, поэтому не импортируется, а дублируется — это
-- просто защита от кривых чисел, не реальный игровой лимит).
local MONEY_SAFETY_CAP = BigNum.new(10):powInt(300)

-- Та же подстраховка от рассинхрона Config.lua, что и в BuildUIAssets.lua/
-- CustomCartUI.client.lua — ProcessReceipt ниже перебирает Config.Shop.Items.
Config.Shop = Config.Shop or {}
Config.Shop.Items = Config.Shop.Items or {}
Config.CashPasses = Config.CashPasses or { "DoubleCash" }

local MonetizationService = {}

local function devProductsMicro()
	return Config.DevProducts.Micro or {}
end

local Services = nil

-- [userId] = { GoldenShield=bool, ..., SpeedBoost=bool, FastMining=bool }
local ownership = {}
local unresolvedOwnership = {}
local deliveringCartFills = {}
local appliedCartFills = {} -- [player][PurchaseId] = cart, grant уже выдан; осталось сохранить consumption
local friendsOnServer = {} -- [userId] = сколько ДРУГИХ игроков на этом сервере — Roblox-друзья этого игрока
local referralGeneration = 0

local function checkPass(userId, passId)
	if not passId or passId == 0 then
		return true, false -- пасс ещё не создан (Id-плейсхолдер)
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(userId, passId)
	end)
	return ok, ok and owns == true or nil
end

-- Атрибуты на самом Player'е ("Owns_GoldenShield" и т.п.) — простейший
-- способ довести владение геймпассом до клиента БЕЗ отдельного
-- RemoteFunction/RemoteEvent: атрибуты реплицируются сами, клиент просто
-- слушает GetAttributeChangedSignal (см. GamepassQuickBar в
-- CustomCartUI.client.lua — подсвечивает купленные пассы золотым).
-- v10: старые (снятые с продажи) пассы → новые (Config.GamePasses[*].GrantsTo).
local function applyLegacyGrants(data)
	for key, passInfo in Config.GamePasses do
		if passInfo.Legacy and data[key] == true then
			for _, target in passInfo.GrantsTo or {} do
				data[target] = true
			end
		end
	end
end

local function syncOwnershipAttributes(player)
	local data = ownership[player.UserId]
	if not data then
		return
	end
	for key, owned in data do
		player:SetAttribute("Owns_" .. key, owned)
	end
end

local function applyEntitlement(player, key)
	if key == "RocketPickaxe" and Services.SkinService then
		-- v10: пасс выдаёт СКИН турбо-кирки (надевается в меню скинов).
		pcall(Services.SkinService.GrantSkin, Services.SkinService, player, Config.RocketPickaxe.SkinId)
	elseif key == "CartGuard" and Services.CombatService then
		Services.CombatService:RefreshShieldVisual(player)
		if Services.CartService then Services.CartService:RefreshShieldVisual(player) end
	elseif key == "ExtraPouch" and Services.HandCarryService then
		Services.HandCarryService:RefreshCapacity(player)
	end
end

local function loadOwnership(player)
	local userId = player.UserId
	local data = ownership[userId] or {}
	ownership[userId] = data
	player:SetAttribute("PassEntitlementsReady", false)
	for key in Config.GamePasses do
		if data[key] == nil then data[key] = false end
	end

	-- Starter Pack is profile-backed, so entitlement loading must not race
	-- ahead of DataService:LoadProfile.
	while player.Parent and not Services.DataService:IsProfileReady(player) do
		task.wait(0.1)
	end
	if not player.Parent or ownership[userId] ~= data then return end

	local passes = Config.GamePasses
	-- StarterPack даёт бессрочный бонус ExtraPouch/SpeedBoost БЕЗ реальной
	-- покупки этих пассов (см. Config.DevProducts.StarterPack) — подмешиваем
	-- сохранённый флаг сюда же, а не проверяем его отдельно в GetPouchBonus/
	-- GetSpeedMultiplier, иначе он бы слетал при каждом пересчёте (loadOwnership
	-- вызывается заново на респауне и т.п., полностью перезаписывая ownership[...]).
	local starterPackClaimed = Services.DataService:HasClaimedStarterPack(player)
	do -- v10: заряды микротранзакций — клиенту (кнопки/подсказки)
		local profileData = Services.DataService:GetGeodeData(player)
		if profileData then
			player:SetAttribute("MineRushCharges", tonumber(profileData.MineRushCharges) or 0)
			player:SetAttribute("PerfectStrikes", tonumber(profileData.PerfectStrikes) or 0)
		end
	end
	local unresolved = {}
	unresolvedOwnership[userId] = unresolved
	for key, passInfo in passes do
		local success, owns
		for attempt = 1, 3 do
			success, owns = checkPass(userId, passInfo.Id)
			if success then break end
			task.wait(attempt)
		end
		-- Never overwrite a purchase event that arrived while this request yielded.
		if success and owns then data[key] = true end
		if not success and data[key] ~= true then unresolved[key] = true end
	end
	if starterPackClaimed then
		data.ExtraPouch = true
	end
	applyLegacyGrants(data)
	if not player.Parent or ownership[userId] ~= data then return end
	syncOwnershipAttributes(player)
	local ready = next(unresolved) == nil
	player:SetAttribute("PassEntitlementsReady", ready)
	if not ready then
		if Services.NotifyService then Services.NotifyService:Show(player, "Purchase bonuses could not be verified yet. Paid actions will retry shortly.", { Icon = "Pending" }) end
		task.spawn(function()
			while player.Parent == Players and ownership[userId] == data and next(unresolved) ~= nil do
				task.wait(10)
				for key in unresolved do
					local success, owns = checkPass(userId, passes[key].Id)
					if success then
						unresolved[key] = nil
						if owns and data[key] ~= true then
							data[key] = true
							applyLegacyGrants(data)
							applyEntitlement(player, key)
						end
					end
				end
				if player.Parent == Players and ownership[userId] == data then
					syncOwnershipAttributes(player)
					player:SetAttribute("PassEntitlementsReady", next(unresolved) == nil)
				end
			end
		end)
	end

	-- Проверка владения асинхронная и может закончиться уже после первичной
	-- настройки персонажа/UI. Сразу пересчитываем эффекты, которым нужен push,
	-- а не только чтение кэша при следующем игровом действии.
	for key, owned in data do if owned then applyEntitlement(player, key) end end
end

-- Roblox-дружба симметрична, но API проверяется от лица КОНКРЕТНОГО игрока
-- (throttled HTTP-запрос под капотом) — оборачиваем в pcall, как и checkPass
-- выше, чтобы временный сбой сети не уронил весь пересчёт для всех.
local function isFriendWith(player, otherUserId)
	local ok, result = pcall(function() return player:IsFriendsWith(otherUserId) end)
	return ok and result == true
end

-- Пересчитывает "сколько друзей на сервере" для КАЖДОГО текущего игрока —
-- O(n²) от числа игроков, но сервер максимум Config.World.PlotCount человек
-- (сейчас 8), так что это максимум 56 дешёвых проверок, не проблема.
-- Вызывается при входе/выходе любого игрока (см. Start ниже) — дружба
-- за сессию не меняется сама по себе, поэтому чаще пересчитывать не нужно.
local function recomputeReferralGraph()
	referralGeneration += 1
	local generation = referralGeneration
	local players = Players:GetPlayers()
	local counts = {}
	for _, player in players do
		local count = 0
		for _, other in players do
			if player.Parent == Players and other.Parent == Players and other ~= player and isFriendWith(player, other.UserId) then
				count += 1
			end
		end
		counts[player] = count
	end
	if generation ~= referralGeneration then return end
	for player, count in counts do
		if player.Parent ~= Players then continue end
		friendsOnServer[player.UserId] = count
		player:SetAttribute("ReferralFriendsOnline", count)
		local cappedCount = math.min(count, Config.Referral.MaxFriends)
		player:SetAttribute("ReferralMultiplier", 1 + cappedCount * Config.Referral.MoneyMultiplierPerFriend)
	end
end

local function referralPromptMessage(player)
	local count = friendsOnServer[player.UserId] or 0
	if count <= 0 then
		return ("Invite friends for a money bonus! 1 friend online = x%.0f money."):format(1 + Config.Referral.MoneyMultiplierPerFriend)
	end
	local multiplier = MonetizationService:GetReferralMultiplier(player)
	return ("%d friend%s online -> x%.0f money! Invite more for an even bigger bonus."):format(count, count == 1 and "" or "s", multiplier)
end

-- Раз в Config.Referral.PromptInterval секунд ненавязчиво напоминает
-- пригласить друзей — обычный Toast (см. NotifyService), тот же, что и
-- "не хватает денег"/"открыт магазин", просто с кнопкой-действием
-- "Invite" (см. CustomCartUI.client.lua). Не показывается, если у игрока
-- уже максимум учитываемых друзей на сервере — рекламировать нечего.
local function startReferralReminders(player)
	task.spawn(function()
		while player.Parent do
			task.wait(Config.Referral.PromptInterval)
			if not player.Parent then
				break
			end
			local count = friendsOnServer[player.UserId] or 0
			if count < Config.Referral.MaxFriends and Services.NotifyService then
				Services.NotifyService:Show(player, referralPromptMessage(player), { ActionLabel = "Invite", Action = "Invite", Icon = "Social" })
			end
		end
	end)
end

local PASS_NOTIFY = {
	DoubleCash = { Icon = "Money", Effect = "Ore sells for x2 money." },
	DoubleLuck = { Icon = "Reward", Effect = "x2 mutation chance, rarer ore." },
	OreMagnet = { Icon = "Gift", Effect = "Ore flies to you from far away." },
	ExtraPouch = { Icon = "Gift", Effect = "+12 backpack slots." },
	GeodeMaster = { Icon = "Geode", Effect = "Open 3 or 5 geodes at once." },
	DemolitionExpert = { Icon = "Pickaxe", Effect = "Dynamite recharges 2x faster + free daily dynamite." },
	CartGuard = { Icon = "Shield", Effect = "Longer shield, shorter cooldown." },
	FastSmelter = { Icon = "Reward", Effect = "Smelter x2 faster, +1 slot." },
	RocketPickaxe = { Icon = "Pickaxe", Effect = "Press R: one hit knocks players flying!" },
	DoubleDrops = { Icon = "Geode", Effect = "Geodes give x2 rewards." },
}

local function passTitle(key)
	for _, item in Config.Shop.Items do
		if item.ProductType == "GamePass" and item.PassKey == key and item.Title then
			return item.Title
		end
	end
	return key
end

local function notifyPassPurchased(player, key)
	if not Services.NotifyService then return end
	local meta = PASS_NOTIFY[key] or { Icon = "Reward", Effect = "Bonus unlocked." }
	Services.NotifyService:Show(player, ("PURCHASED: %s\n%s"):format(passTitle(key), meta.Effect), {
		Icon = meta.Icon,
	})
end

--------------------------------------------------------------------------------
-- v20.4: FOREVER PACK (Config.Shop.ForeverPack) — цепочка «бесплатно →
-- пак → пак дороже», обновляется каждые RefreshHours. Состояние в профиле:
-- data.ForeverPack = { Window, Step } (Step — сколько звеньев уже взято в
-- текущем окне). Клиенту — атрибуты ForeverStep и ForeverRefreshAt.
--------------------------------------------------------------------------------
local function foreverWindow()
	local hours = (Config.Shop.ForeverPack and Config.Shop.ForeverPack.RefreshHours) or 4
	local period = math.max(60, hours * 3600)
	local index = math.floor(os.time() / period)
	return index, (index + 1) * period
end

local function foreverState(data)
	local window = foreverWindow()
	if type(data.ForeverPack) ~= "table" or data.ForeverPack.Window ~= window then
		data.ForeverPack = { Window = window, Step = 0 }
	end
	return data.ForeverPack
end

local function publishForever(player)
	local data = Services.DataService:GetGeodeData(player)
	if not data then return end
	local state = foreverState(data)
	local _, refreshAt = foreverWindow()
	player:SetAttribute("ForeverStep", state.Step)
	player:SetAttribute("ForeverRefreshAt", refreshAt)
end

-- Покупка пака: если это следующее звено цепочки — продвигаем её.
local function advanceForever(player, data, packKey)
	local cfg = Config.Shop.ForeverPack
	if not (cfg and data) then return end
	local state = foreverState(data)
	if cfg.Steps[state.Step + 1] == packKey then
		state.Step += 1
	end
	task.defer(publishForever, player)
end

-- v20.38: НЕ ХВАТАЕТ ДЕНЕГ — ПОВТОРНЫЙ КЛИК. Первый отказ — обычное
-- «Not enough money». Если игрок жмёт ту же покупку ещё раз в течение
-- Config.MoneyPackOffer.RepeatSeconds — сразу открывается окно покупки
-- Money Pack'а, которого ХВАТИТ на недостающую сумму (самый дешёвый из
-- подходящих; если не хватит ни одного — самый крупный).
--   Services.MonetizationService:NotEnoughMoney(player, cost, "Upgrade:Mine")
local notEnoughState = setmetatable({}, { __mode = "k" })
function MonetizationService:PickMoneyPack(player, missing)
	local tiers = Services.DataService:GetTiers(player)
	local mult = Services.DataService:GetCrystalMultiplier(player)
	local offerCfg = Config.MoneyPackOffer or {}
	local best, largest = nil, nil
	for _, packKey in offerCfg.Packs or { "MoneyPackSmall", "MoneyPackMedium", "MoneyPackLarge" } do
		local pack = Config.DevProducts[packKey]
		if pack and (tonumber(pack.Id) or 0) > 0 then
			local amount = Config.MoneyPackAmount(pack, tiers.Mine, tiers.Cart, mult)
			if not largest or amount > largest.Amount then largest = { Key = packKey, Pack = pack, Amount = amount } end
			if not best and BigNum.ge(BigNum.new(amount), missing) then
				best = { Key = packKey, Pack = pack, Amount = amount }
			end
		end
	end
	return best or largest
end

function MonetizationService:NotEnoughMoney(player, cost, key)
	local offerCfg = Config.MoneyPackOffer or {}
	if offerCfg.Enabled == false or not player or not player.Parent then return end
	if player:GetAttribute("MineExpeditionActive") == true then return end
	local now = os.clock()
	local last = notEnoughState[player]
	key = tostring(key or "Any")
	local repeated = last and last.Key == key and now - last.At <= (offerCfg.RepeatSeconds or 6)
	if not repeated then
		notEnoughState[player] = { Key = key, At = now }
		return
	end
	-- Повтор засчитан — следующий повтор снова начнёт отсчёт с нуля, чтобы
	-- окно не всплывало на каждом клике подряд.
	notEnoughState[player] = nil
	if last.PromptedAt and now - last.PromptedAt < (offerCfg.CooldownSeconds or 20) then return end
	local ok, missing = pcall(function()
		return BigNum.new(cost) - BigNum.new(Services.DataService:GetMoney(player))
	end)
	if not ok then return end
	local offer = self:PickMoneyPack(player, missing)
	if not offer then return end
	notEnoughState[player] = { Key = "", At = 0, PromptedAt = now }
	pcall(function() MarketplaceService:PromptProductPurchase(player, offer.Pack.Id) end)
end

function MonetizationService:ClaimForeverFree(player)
	local cfg = Config.Shop.ForeverPack
	local data = Services.DataService:GetGeodeData(player)
	if not (cfg and data) or cfg.Steps[1] ~= "Free" then return false end
	local state = foreverState(data)
	if state.Step ~= 0 then return false end
	state.Step = 1
	local tiers = Services.DataService:GetTiers(player)
	local amount = Config.MoneyPackAmount({ Minutes = cfg.FreeMinutes or 3, Amount = 100 }, tiers.Mine, tiers.Cart, Services.DataService:GetCrystalMultiplier(player))
	Services.DataService:AddMoney(player, amount)
	publishForever(player)
	task.spawn(function() pcall(Services.DataService.SaveProfile, Services.DataService, player) end)
	return true
end

function MonetizationService:Init(services)
	Services = services
	self:InitOffers()
	local foreverRemote = Instance.new("RemoteEvent")
	foreverRemote.Name = "ShopForeverRequest"
	foreverRemote.Parent = ReplicatedStorage.Shared
	local lastClaim = {}
	foreverRemote.OnServerEvent:Connect(function(player, action)
		if action ~= "ClaimFree" then return end
		local now = os.clock()
		if lastClaim[player] and now - lastClaim[player] < 1 then return end
		lastClaim[player] = now
		self:ClaimForeverFree(player)
	end)
	-- Окно обновляется по часам — раз в минуту переиздаём атрибуты.
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in Players:GetPlayers() do pcall(publishForever, player) end
		end
	end)
end

function MonetizationService:Start()
	-- Один ProductId обязан означать ровно одну награду. Иначе порядок веток
	-- ProcessReceipt незаметно выдавал бы первый совпавший товар.
	local registeredProducts = {}
	local registeredPasses = {}
	local function registerProduct(id, name)
		if not id or id == 0 then
			return
		end
		assert(not registeredProducts[id], ("Duplicate Developer Product Id %d: %s and %s"):format(id, registeredProducts[id] or "?", name))
		registeredProducts[id] = name
	end
	for key, passInfo in Config.GamePasses do
		local id = tonumber(passInfo.Id) or 0
		if id ~= 0 then
			assert(not registeredPasses[id], ("Duplicate Game Pass Id %d: %s and %s"):format(id, registeredPasses[id] or "?", key))
			registeredPasses[id] = key
		end
	end
	registerProduct(Config.Protection.PaidProductId, "ProtectionExtension")
	registerProduct(Config.DevProducts.StarterPack and Config.DevProducts.StarterPack.Id, "StarterPack")
	for _, key in { "WeatherNight", "WeatherRain", "WeatherThunderstorm", "WeatherBloodMoon", "WeatherSolarEclipse" } do
		local product = Config.DevProducts[key]
		registerProduct(product and product.Id, key)
	end
	for name, pack in Config.DevProducts do
		if name ~= "CartFillByTier" and typeof(pack) == "table" and pack.Amount then
			registerProduct(pack.Id, name)
		end
	end
	for tier, fillProduct in Config.DevProducts.CartFillByTier or {} do
		registerProduct(fillProduct.Id, "CartFillTier" .. tier)
	end
	for rebirthNumber, skipProduct in Config.DevProducts.RebirthSkip or {} do
		registerProduct(skipProduct.Id, "RebirthSkip" .. rebirthNumber)
	end
	for geodeType, pack in Config.DevProducts.GeodePacks or {} do
		registerProduct(pack.Id, "GeodePack_" .. geodeType)
	end
	for microKey, micro in Config.DevProducts.Micro or {} do
		registerProduct(micro.Id, "Micro_" .. microKey)
	end
	for _, item in Config.Shop.Items do
		if item.ProductType == "DevProduct" and item.GrantMoney and item.GrantMoney > 0 then
			-- Geode shop cards reuse the ProductIds already registered above.
			-- Register only standalone money cards here so duplicate IDs remain
			-- an error for unrelated products, but not for mirrored shop entries.
			if not registeredProducts[item.ProductId] then
				registerProduct(item.ProductId, item.Id)
			end
		end
	end

	Players.PlayerAdded:Connect(function(player)
		task.delay(3, function() pcall(publishForever, player) end)
		task.spawn(loadOwnership, player)
		task.spawn(recomputeReferralGraph) -- новый игрок мог изменить чужие счётчики друзей тоже, не только свой
		startReferralReminders(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(loadOwnership, player)
		startReferralReminders(player)
	end
	task.spawn(recomputeReferralGraph)
	Players.PlayerRemoving:Connect(function(player)
		ownership[player.UserId] = nil
		unresolvedOwnership[player.UserId] = nil
		friendsOnServer[player.UserId] = nil
		task.delay(25, function()
			deliveringCartFills[player] = nil
			for _, cart in appliedCartFills[player] or {} do
				if cart then cart.PaidFillPendingSave = nil end
			end
			appliedCartFills[player] = nil
		end)
		task.defer(recomputeReferralGraph) -- после ухода игрок уже не в Players:GetPlayers(), пересчёт для остальных корректен
	end)

	-- Живое обновление кэша, если пасс куплен ПРЯМО СЕЙЧАС (не с нуля сессии) —
	-- иначе эффект применился бы только после перезахода.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
		if not wasPurchased or player.Parent ~= Players then
			return
		end
		local key
		for candidate, passInfo in Config.GamePasses do
			if passInfo.Id ~= 0 and passInfo.Id == passId then key = candidate; break end
		end
		if not key then return end
		local data = ownership[player.UserId] or {}
		ownership[player.UserId] = data
		local wasNew = data[key] ~= true
		data[key] = true
		local unresolved = unresolvedOwnership[player.UserId]
		if unresolved then
			unresolved[key] = nil
			if next(unresolved) == nil then player:SetAttribute("PassEntitlementsReady", true) end
		end
		applyEntitlement(player, key)
		syncOwnershipAttributes(player)
		if wasNew then
			notifyPassPurchased(player, key)
		end
	end)

	-- ПРОВЕРКА ЦЕЛОСТНОСТИ ВЛАДЕНИЯ (см. отчёт: "золотая обводка у тележки,
	-- а над игроком зелёный щит" и общая просьба "проверяй покупку
	-- геймпасса прежде чем выдавать преимущество"). Кэш в `ownership`
	-- обновляется живьём только по событию PromptGamePassPurchaseFinished
	-- — если по любой причине (лаг события, покупка не через наш UI,
	-- рассинхрон между визуалами) кэш и реальное владение разойдутся,
	-- раньше это никогда само не чинилось. Здесь — раз в
	-- ReconcileInterval секунд на каждого онлайн-игрока переспрашиваем
	-- Roblox НАПРЯМУЮ (тот же checkPass, что и при входе) и, если
	-- что-то изменилось по сравнению с кэшем, пересчитываем визуалы/
	-- эффекты ровно так же, как если бы игрок только что купил пасс.
	-- Не трогает DevProduct-покупки (они разовые и не имеют "состояния
	-- владения" — ProcessReceipt ниже это подтверждает атомарно).
	task.spawn(function()
		local RECONCILE_INTERVAL = 120 -- сек; недорого — раз в 2 минуты на игрока, не при каждом чихе
		while true do
			task.wait(RECONCILE_INTERVAL)
			for _, player in Players:GetPlayers() do
				local data = ownership[player.UserId]
				if data then
					local passes = Config.GamePasses
					local unresolved = unresolvedOwnership[player.UserId] or {}
					unresolvedOwnership[player.UserId] = unresolved
					for key, passInfo in passes do
						local ok, owns = checkPass(player.UserId, passInfo.Id)
						if ok then unresolved[key] = nil else unresolved[key] = true end
						if ok and owns and data[key] ~= true then
							data[key] = true
							applyLegacyGrants(data)
							applyEntitlement(player, key)
							syncOwnershipAttributes(player)
							notifyPassPurchased(player, key)
						end
					end
					player:SetAttribute("PassEntitlementsReady", next(unresolved) == nil)
				end
			end
		end
	end)

	-- ЕДИНСТВЕННЫЙ ProcessReceipt на всю игру (см. предупреждение в шапке файла).
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player then
			-- Игрок вышел, пока покупка обрабатывалась — Roblox повторит попытку
			-- позже сам (retry-механизм платформы), тут отдаём "не обработано".
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local function process(grant)
			local status = Services.DataService:ProcessDeveloperProduct(player, receiptInfo, grant)
			if status == "Committed" or status == "AlreadyCommitted" then
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		-- v10: МИКРОТРАНЗАКЦИИ (Config.DevProducts.Micro).
		for microKey, micro in devProductsMicro() do
			if (micro.Id or 0) ~= 0 and receiptInfo.ProductId == micro.Id then
				return self:_grantMicro(player, receiptInfo, microKey, micro, process)
			end
		end

		-- Продление щита (+80 сек, Config.Protection.PaidDuration) — та же
		-- покупка, что была раньше, просто обработка переехала сюда.
		-- v8: пропуск таймера сундука (Config.Chests.Types[*].SkipProductId).
		if Config.Chests and Services.GearService then
			for rarity, chestInfo in Config.Chests.Types do
				if (chestInfo.SkipProductId or 0) ~= 0 and receiptInfo.ProductId == chestInfo.SkipProductId then
					return process(function()
						return Services.GearService:SkipChestTimer(player, rarity)
					end)
				end
			end
		end

		if receiptInfo.ProductId == Config.Protection.PaidProductId then
			local status = Services.DataService:ProcessDeveloperProduct(player, receiptInfo, function(data)
				local runtimeRemaining = Services.CombatService:GetProtectionRemaining(player)
				local base = math.max(tonumber(data.PaidProtectionEndsAt) or 0, os.time() + runtimeRemaining, os.time())
				data.PaidProtectionEndsAt = base + Config.Protection.PaidDuration
				return true
			end)
			if status == "Committed" or status == "AlreadyCommitted" then
				Services.CombatService:SyncPaidProtection(player, Services.DataService:GetPaidProtectionEndsAt(player))
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		-- Money Pack'и (Config.DevProducts) — прямая выдача денег в профиль.
		local devProducts = Config.DevProducts
		for packKey, pack in { MoneyPackSmall = devProducts.MoneyPackSmall, MoneyPackMedium = devProducts.MoneyPackMedium, MoneyPackLarge = devProducts.MoneyPackLarge } do
			if receiptInfo.ProductId == pack.Id then
				-- v3: «N минут твоего дохода» — считаем по тирам игрока на момент покупки.
				local tiers = Services.DataService:GetTiers(player)
				local amount = Config.MoneyPackAmount(pack, tiers.Mine, tiers.Cart, Services.DataService:GetCrystalMultiplier(player))
				return process(function(data)
					data.Money = (BigNum.fromData(data.Money) + amount):clamp(BigNum.new(0), MONEY_SAFETY_CAP):toData()
					advanceForever(player, data, packKey) -- v20.4: звено Forever Pack
					return true
				end)
			end
		end

		-- СТАРТОВЫЙ ПАК (см. Config.DevProducts.StarterPack) — по прямому
		-- запросу переделан в чистый донат деньгами (было: деньги + скин +
		-- щит + перманентные ExtraPouch/SpeedBoost). Skin/ShieldSeconds
		-- ветки ниже остались НА МЕСТЕ намеренно — они уже были условными
		-- ("if pack.Skin and ...") и просто ничего не делают, раз этих
		-- полей больше нет в Config; так пак снова обрастёт бонусами сам,
		-- если их когда-нибудь вернут в конфиг, без правки этого файла.
		-- ПОГОДНЫЕ ИВЕНТЫ ЗА ROBUX (см. Config.DevProducts.Weather*) — сразу
		-- запускают ивент на весь сервер. Права админа тут не нужны — сама
		-- покупка и есть допуск (см. WeatherService:PurchaseTriggerEvent).
		-- В профиль игрока ничего не пишем (нечего терять при неудачном
		-- сохранении), поэтому не нужен весь путь через ProcessDeveloperProduct —
		-- сразу PurchaseGranted.
		for _, key in { "WeatherNight", "WeatherRain", "WeatherThunderstorm", "WeatherBloodMoon", "WeatherSolarEclipse" } do
			local product = devProducts[key]
			if product and product.Id ~= 0 and receiptInfo.ProductId == product.Id then
				-- pcall — ОБЯЗАТЕЛЕН. Любая ошибка внутри WeatherService
				-- (именно так и выглядел баг "купил погоду, ничего не
				-- произошло": applyEvent резолвился в nil, см. комментарий
				-- в WeatherService.lua) вылетала ПРЯМО ОТСЮДА, из
				-- ProcessReceipt. Roblox трактует упавший ProcessReceipt
				-- как "не обработано" и повторяет попытку снова и снова —
				-- игрок остаётся без покупки и без внятного ответа.
				-- Теперь: сработало — подтверждаем чек; не сработало —
				-- честно возвращаем NotProcessedYet, чтобы платформа
				-- повторила попытку позже (или вернула деньги), и пишем
				-- предупреждение в лог.
				local ok, applied = pcall(function()
					return Services.WeatherService and Services.WeatherService:PurchaseTriggerEvent(product.EventId)
				end)
				if ok and applied then
					return Enum.ProductPurchaseDecision.PurchaseGranted
				end
				warn(("[MonetizationService] Погодный ивент %s (%s) не запустился для %s - чек НЕ подтверждён, платформа повторит попытку. Причина: %s"):format(
					tostring(key), tostring(product.EventId), player.Name,
					ok and "PurchaseTriggerEvent вернул false (нет такого EventId в Config.WeatherEvents.Events?)" or tostring(applied)
				))
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
		end

		if devProducts.StarterPack and devProducts.StarterPack.Id ~= 0 and receiptInfo.ProductId == devProducts.StarterPack.Id then
			local pack = devProducts.StarterPack
			local starterTiers = Services.DataService:GetTiers(player)
			local starterAmount = Config.MoneyPackAmount(pack, starterTiers.Mine, starterTiers.Cart, Services.DataService:GetCrystalMultiplier(player))
			local status = Services.DataService:ProcessDeveloperProduct(player, receiptInfo, function(data)
				if data.StarterPackClaimed == true then
					return true
				end
				data.Money = (BigNum.fromData(data.Money) + starterAmount):clamp(BigNum.new(0), MONEY_SAFETY_CAP):toData()
				data.StarterPackClaimed = true
				if pack.Skin and Config.Skins.Definitions[pack.Skin] then data.OwnedSkins[pack.Skin] = true end
				if pack.ShieldSeconds and pack.ShieldSeconds > 0 then
					local runtimeRemaining = Services.CombatService:GetProtectionRemaining(player)
					local base = math.max(tonumber(data.PaidProtectionEndsAt) or 0, os.time() + runtimeRemaining, os.time())
					data.PaidProtectionEndsAt = base + pack.ShieldSeconds
				end
				return true
			end)
			if status == "Committed" or status == "AlreadyCommitted" then
				player:SetAttribute("StarterPackClaimed", true)
				if Services.SkinService then Services.SkinService:SendState(player) end
				if Services.CombatService then Services.CombatService:SyncPaidProtection(player, Services.DataService:GetPaidProtectionEndsAt(player)) end
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		-- "Купить жеоду" (Config.DevProducts.GeodePacks) — по одной штуке
		-- нужного типа за покупку, ПОВТОРЯЕМО (обычный Developer Product, не
		-- Game Pass — см. комментарий в Config.lua про то, почему выбран
		-- именно этот тип продукта). Тот же durable-паттерн, что и у Money
		-- Pack'ов выше, только награда — не деньги, а +1 к data.Geodes[type].
		for geodeType, pack in devProducts.GeodePacks or {} do
			if pack.Id ~= 0 and receiptInfo.ProductId == pack.Id then
				local status = Services.DataService:ProcessDeveloperProduct(player, receiptInfo, function(data)
					data.Geodes[geodeType] = (tonumber(data.Geodes[geodeType]) or 0) + 1
					return true
				end)
				if status == "Committed" or status == "AlreadyCommitted" then
					-- Живой пуш игроку: обновляет статус здания хранилища и
					-- шлёт свежий GetState на клиент — если панель "GEODE
					-- STORAGE" открыта прямо сейчас, новая жеода появится в
					-- ней без переоткрытия (см. обработчик команды "State"
					-- в GeodeUI.client.lua).
					if Services.GeodeService then
						Services.GeodeService:UpdateBuilding(player)
						Services.GeodeService:SendState(player)
					end
					return Enum.ProductPurchaseDecision.PurchaseGranted
				end
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
		end

		-- "Открыть x3 / x5" НЕ здесь: это постоянные Game Pass'ы
		-- (Config.GamePasses.TripleGeodeOpen/FiveGeodeOpen), проверяются
		-- через MonetizationService:HasPass в GeodeService:OpenGeode
		-- напрямую, отдельного ProcessReceipt-шага не требуют.


		-- Моментальное заполнение — отдельный продукт для каждого тира.
		-- Количество берётся из серверного Config, клиент не сообщает ни тир,
		-- ни вместимость, поэтому подмена запроса не даёт более дорогой груз.
		for productTier, fillProduct in devProducts.CartFillByTier or {} do
			if fillProduct.Id ~= 0 and receiptInfo.ProductId == fillProduct.Id then
				local status = Services.DataService:ProcessDeveloperProduct(player, receiptInfo, function(data)
					data.PendingCartFills[tostring(receiptInfo.PurchaseId)] = {
						ProductId = receiptInfo.ProductId,
						Tier = productTier,
						MaxCrystals = fillProduct.MaxCrystals,
						CreatedAt = os.time(),
					}
					return true
				end)
				if status == "Committed" or status == "AlreadyCommitted" then
					task.defer(function() self:TryDeliverPendingCartFills(player) end)
					return Enum.ProductPurchaseDecision.PurchaseGranted
				end
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
		end

		-- "СКИП РЕБЁРТА" — доводит деньги игрока РОВНО до цены его ТЕКУЩЕГО
		-- ребёрта (BigNum.max — если денег уже больше цены, ничего не
		-- отнимаем и не портим; если меньше — доводим ровно до цены, без
		-- лишнего "довеска"), а затем сам пробует провести ребёрт. Если
		-- ветки ещё не прокачаны до тир-капа, ребёрт просто не сработает
		-- сейчас — деньги всё равно останутся зачисленными на будущее.
		-- BigNum, а не обычное вычитание/сложение — цена ребёрта растёт
		-- без реального потолка (см. DataService:GetRebirthCost) и рано
		-- или поздно перестаёт помещаться в double.
		for rebirthNumber, skipProduct in devProducts.RebirthSkip or {} do
			if skipProduct.Id ~= 0 and receiptInfo.ProductId == skipProduct.Id then
				local currentRebirthNumber = Services.DataService:GetRebirths(player) + 1
				local productCost = Services.DataService:GetRebirthCostForNumber(player, rebirthNumber)
				local status = Services.DataService:ProcessDeveloperProduct(player, receiptInfo, function(data)
					local money = BigNum.fromData(data.Money)
					if currentRebirthNumber == rebirthNumber then
						data.Money = BigNum.max(money, productCost):clamp(BigNum.new(0), MONEY_SAFETY_CAP):toData()
					else
						-- A historical SKU is worth only its own fixed tier cost; it
						-- can never top up a later, more expensive rebirth.
						data.Money = (money + productCost):clamp(BigNum.new(0), MONEY_SAFETY_CAP):toData()
					end
					return true
				end)
				if status == "Committed" or status == "AlreadyCommitted" then
					if Services.RebirthService and currentRebirthNumber == rebirthNumber then
						task.defer(function() Services.RebirthService:AttemptRebirthAfterPurchase(player) end)
					end
					return Enum.ProductPurchaseDecision.PurchaseGranted
				end
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
		end

		-- v4: СКИП ПРОКАЧКИ (Config.DevProducts.UpgradeSkip[ветка][тир]).
		-- Тот же принцип, что у скипа ребёрта: деньги доводятся до цены шага,
		-- затем апгрейд проводит обычная логика UpgradeService. Если шаг
		-- уже куплен — начисляется полная цена шага (покупка не сгорает).
		for kind, byTier in devProducts.UpgradeSkip or {} do
			for tier, skipProduct in byTier do
				if (skipProduct.Id or 0) ~= 0 and receiptInfo.ProductId == skipProduct.Id then
					local step = Services.DataService:GetNextBranchStep(player, kind)
					local matches = step ~= nil and step.Repair ~= true and step.Tier == tier
					local cost = matches and step.Cost or 0
					if not matches then
						for _, entry in Config[kind .. "Chain"] or {} do
							if entry.Tier == tier then cost = entry.Cost end
						end
					end
					local status = Services.DataService:ProcessDeveloperProduct(player, receiptInfo, function(data)
						local money = BigNum.fromData(data.Money)
						if matches then
							data.Money = BigNum.max(money, cost):clamp(BigNum.new(0), MONEY_SAFETY_CAP):toData()
						else
							data.Money = (money + cost):clamp(BigNum.new(0), MONEY_SAFETY_CAP):toData()
						end
						return true
					end)
					if status == "Committed" or status == "AlreadyCommitted" then
						if matches and Services.UpgradeService and Services.UpgradeService.BuyAfterSkip then
							task.defer(function() Services.UpgradeService:BuyAfterSkip(player, kind) end)
						end
						return Enum.ProductPurchaseDecision.PurchaseGranted
					end
					return Enum.ProductPurchaseDecision.NotProcessedYet
				end
			end
		end

		-- Карточки-заглушки магазина (Config.Shop.Items, ProductType =
		-- "DevProduct") — ОБЩИЙ путь выдачи: если у карточки задано
		-- GrantMoney (> 0), просто прибавляем эту сумму денег, ровно как
		-- Money Pack'ам выше. Так ЛЮБАЯ карточка-заглушка с реальным
		-- ProductId и заполненным GrantMoney начинает работать сама, без
		-- правки этого файла.
		--
		-- Если карточка должна давать что-то ДРУГОЕ (не деньги — например,
		-- скин, разовый бустер и т.п.) — GrantMoney оставь пустым/0 и
		-- допиши СВОЮ ветку прямо здесь по этому же образцу (сравнение с
		-- receiptInfo.ProductId → своя логика выдачи → return
		-- PurchaseGranted). Это ЕДИНСТВЕННОЕ место в проекте, где можно
		-- обрабатывать DevProduct-покупки — см. предупреждение в шапке файла.
		for _, item in Config.Shop.Items do
			if item.ProductType == "DevProduct" and item.ProductId ~= 0 and receiptInfo.ProductId == item.ProductId then
				if item.GrantMoney and item.GrantMoney > 0 then
					return process(function(data)
						data.Money = (BigNum.fromData(data.Money) + item.GrantMoney):clamp(BigNum.new(0), MONEY_SAFETY_CAP):toData()
						return true
					end)
				end
				-- Нашли карточку по ProductId, но не знаем, что именно ей
				-- выдавать (GrantMoney не задан) — ГРОМКО предупреждаем и
				-- НЕ подтверждаем покупку молча (это оставило бы игрока без
				-- денег И без товара). Roblox повторит попытку позже сам —
				-- у тебя есть время дописать сюда свою логику выдачи и
				-- переопубликовать игру, прежде чем ставить такую карточку
				-- в продажу по-настоящему.
				warn(("[MonetizationService] Куплен девпродукт %d (карточка \"%s\") без GrantMoney и без своей ветки выдачи в ProcessReceipt - покупка НЕ подтверждена. Допиши логику выдачи здесь или заполни GrantMoney в Config.Shop.Items."):format(receiptInfo.ProductId, item.Id))
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
		end

		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
end

function MonetizationService:TryDeliverPendingCartFills(player)
	if deliveringCartFills[player] or not Services.DataService:IsProfileReady(player) then
		return
	end
	local cart = Services.MineService:GetActiveCart(player)
	if not cart then
		return
	end
	deliveringCartFills[player] = true
	appliedCartFills[player] = appliedCartFills[player] or {}
	local deliveryOk, deliveryError = xpcall(function()
	for purchaseId, entitlement in Services.DataService:GetPendingCartFills(player) do
		-- Старый дешёвый ProductId не заполняет топовую тележку целиком:
		-- MaxCrystals навсегда зафиксирован купленным тиром продукта.
		local appliedCart = appliedCartFills[player][purchaseId]
		if appliedCart or Services.CartService:FillInstantly(player, cart, entitlement.MaxCrystals, entitlement.Tier) then
			appliedCart = appliedCart or cart
			appliedCart.PaidFillPendingSave = true
			appliedCartFills[player][purchaseId] = appliedCart
			if Services.DataService:CompletePendingCartFill(player, purchaseId) then
				appliedCart.PaidFillPendingSave = nil
				if appliedCartFills[player] then appliedCartFills[player][purchaseId] = nil end
			else
				task.spawn(function()
					while appliedCartFills[player] and appliedCartFills[player][purchaseId] do
						task.wait(5)
						if Services.DataService:CompletePendingCartFill(player, purchaseId) then
							appliedCart.PaidFillPendingSave = nil
							if appliedCartFills[player] then appliedCartFills[player][purchaseId] = nil end
							break
						end
					end
				end)
			end
			Services.MineService:RefreshActiveCart(player)
		end
		break -- после одного заполнения тележка обычно полна
	end
	end, debug.traceback)
	deliveringCartFills[player] = nil
	if not deliveryOk then warn("[MonetizationService] Pending cart fill delivery failed safely:", deliveryError) end
end

--------------------------------------------------------------------------------
-- API — читает уже закэшированное владение, ничего заново не запрашивает.
-- Если кэш ещё не успел загрузиться (первые доли секунды после входа —
-- loadOwnership асинхронный) — считается, что пасса нет, до следующего
-- обращения; сами эффекты не критичны по тайминугу (деньги/скорость/etc),
-- поэтому секундная задержка на входе безопасна.
--------------------------------------------------------------------------------

function MonetizationService:HasGoldenShield(player)
	return self:HasPass(player, "CartGuard") -- v10: золотой щит — у Cart Guard
end

function MonetizationService:HasPass(player, key)
	local data = player and ownership[player.UserId]
	return data ~= nil and data[key] == true

end

function MonetizationService:IsEntitlementsReady(player)
	return player:GetAttribute("PassEntitlementsReady") == true
end

-- Каждый денежный геймпасс сам даёт указанные 2x/4x/6x/8x. Владение
-- несколькими складывает их номиналы: 2x + 4x = 6x, все четыре = 20x.
function MonetizationService:GetCashMultiplier(player)
	local data = ownership[player.UserId]
	local multiplier = 0
	local highest = (Config.CashPassMode or "Highest") == "Highest"
	if data then
		for _, key in Config.CashPasses do
			if data[key] then
				local value = Config.GamePasses[key].Multiplier or 0
				-- v3: цепочка x2→x3→x5 — действует старший пасс, не сумма.
				multiplier = highest and math.max(multiplier, value) or (multiplier + value)
			end
		end
	end
	multiplier = math.max(1, multiplier)
	-- Временный бафф "х2 деньги" из жеод (см. BuffService) — умножает
	-- поверх геймпассов, как и было задумано ("+x2 на минуту/5 минут").
	if Services.BuffService then
		multiplier *= Services.BuffService:GetMultiplier(player, "Money")
	end
	-- v14: Ember-тотемы и выставленные реликвии — доход с продажи.
	if Services.BaseDecorService then
		multiplier *= 1 + Services.BaseDecorService:GetIncomeBonus(player)
	end
	-- v16: участник группы (Config.GroupReward.IncomeBonus).
	if player and player:GetAttribute("GroupMember") == true then
		multiplier *= 1 + (Config.GroupReward.IncomeBonus or 0)
	end
	-- v16: ивент с табло лайков (Config.LikeGoals, Event = "Money").
	if Services.LikeGoalService then
		multiplier *= Services.LikeGoalService:GetEventMultiplier("Money")
	end
	return multiplier
end

-- Друзья на сервере (см. Config.Referral/recomputeReferralGraph выше) —
-- НЕЗАВИСИМЫЙ множитель, умножается на GetCashMultiplier в BankService, а
-- не складывается с ним (платные пассы и бесплатные друзья — разные оси).
function MonetizationService:GetReferralMultiplier(player)
	local count = friendsOnServer[player.UserId] or 0
	if count <= 0 then
		return 1
	end
	count = math.min(count, Config.Referral.MaxFriends)
	return 1 + count * Config.Referral.MoneyMultiplierPerFriend
end

function MonetizationService:GetPouchBonus(player)
	local data = ownership[player.UserId]
	if data and data.ExtraPouch then
		return Config.GamePasses.ExtraPouch.BonusCapacity
	end
	return 0
end

function MonetizationService:GetMiningSpeedMultiplier(_player)
	return 1 -- v10: FastMining снят с продажи (владельцы получили Ore Magnet)
end

function MonetizationService:GetSpeedMultiplier(player)
	local multiplier = 1 -- v10: SpeedBoost снят с продажи
	if Services.BuffService then
		multiplier *= Services.BuffService:GetMultiplier(player, "Speed")
	end
	return multiplier
end

function MonetizationService:GetDamageMultiplier(player)
	local multiplier = 1 -- v10: DoubleDamage снят с продажи
	if Services.BuffService then
		multiplier *= Services.BuffService:GetMultiplier(player, "Damage")
	end
	return multiplier
end

function MonetizationService:GetHealthMultiplier(_player)
	return 1 -- v10: DoubleHealth снят с продажи
end

function MonetizationService:GetGeodeRewardCount(player)
	return self:HasPass(player, "DoubleDrops") and (Config.GamePasses.DoubleDrops.RewardCount or 2) or 1
end

--------------------------------------------------------------------------------
-- v10: УДАЧА — пасс 2x Luck, личное зелье, удача всего сервера.
-- Ore — добавка к наклону ролла руды (Config.RollOreForTier, зажим 0.6),
-- Mutation — множитель шанса мутаций. Серверная удача — у всех на сервере.
--------------------------------------------------------------------------------
local personalLuck = {} -- [player] = { Until, Ore, Mutation }
local serverLuck = { Until = 0, Ore = 0, Mutation = 1 }

function MonetizationService:GetLuckBoost(player)
	local ore, mutation = 0, 1
	if player and self:HasPass(player, "DoubleLuck") then
		ore += Config.GamePasses.DoubleLuck.OreLuck or 0
		mutation *= Config.GamePasses.DoubleLuck.MutationMultiplier or 2
	end
	local now = os.time()
	local potion = player and personalLuck[player]
	if potion and potion.Until > now then
		ore += potion.Ore
		mutation *= potion.Mutation
	end
	if serverLuck.Until > now then
		ore += serverLuck.Ore
		mutation *= serverLuck.Mutation
	end
	-- v16: ивент с табло лайков «x2 Luck» — как пасс 2x Luck.
	if Services.LikeGoalService then
		local eventMult = Services.LikeGoalService:GetEventMultiplier("Luck")
		if eventMult > 1 then
			ore += (Config.GamePasses.DoubleLuck.OreLuck or 0.2) * (eventMult - 1)
			mutation *= eventMult
		end
	end
	-- v14: Fortune-тотемы на базе. +100% удачи = сила пасса 2x Luck.
	if player and Services.BaseDecorService then
		local bonus = Services.BaseDecorService:GetLuckBonus(player)
		if bonus > 0 then
			ore += bonus * (Config.GamePasses.DoubleLuck.OreLuck or 0.2)
			mutation *= 1 + bonus
		end
	end
	return ore, mutation
end

function MonetizationService:GetPickupRadius(player)
	local base = Config.Inventory.PickupRadius
	if player and self:HasPass(player, "OreMagnet") then
		return math.max(base, Config.GamePasses.OreMagnet.PickupRadius or base)
	end
	return base
end

local function setServerLuck(mult, ore, seconds, buyer)
	local now = os.time()
	local stronger = mult >= serverLuck.Mutation or serverLuck.Until <= now
	if stronger then
		serverLuck.Mutation = mult
		serverLuck.Ore = ore
	end
	serverLuck.Until = math.max(serverLuck.Until, now) + seconds
	workspace:SetAttribute("ServerLuckUntil", serverLuck.Until)
	workspace:SetAttribute("ServerLuckMultiplier", serverLuck.Mutation)
	if Services.NotifyService then
		for _, other in Players:GetPlayers() do
			Services.NotifyService:Show(other, ("🌐 %s turned on SERVER LUCK x%d for everyone!"):format(buyer.DisplayName, mult), {
				Icon = "Reward", Duration = 5, TextColor = Color3.fromRGB(120, 255, 150),
			})
		end
	end
end

--------------------------------------------------------------------------------
-- v10: «ВЕРНУТЬ УКРАДЕННОЕ». CombatService/CartService сообщают, сколько
-- игрок потерял; клиент показывает предложение (OfferEvent "Revenge").
--------------------------------------------------------------------------------
local losses = {} -- [player] = { Value, At }
local offerRemote = nil

function MonetizationService:RecordLoss(victim, value)
	value = math.floor(tonumber(value) or 0)
	if not (victim and victim.Parent) or value <= 0 then return end
	local now = os.time()
	local entry = losses[victim]
	if entry and now - entry.At <= (Config.Offers.RevengeWindow or 90) then
		entry.Value += value
		entry.At = now
	else
		entry = { Value = value, At = now }
		losses[victim] = entry
	end
	local micro = Config.DevProducts.Micro and Config.DevProducts.Micro.Revenge
	if offerRemote and micro then
		offerRemote:FireClient(victim, "Revenge", {
			Value = math.floor(entry.Value * (Config.Offers.RevengeShare or 0.5)),
			ExpiresAt = now + (Config.Offers.RevengeWindow or 90),
		})
	end
end

--------------------------------------------------------------------------------
-- v10: ВЫДАЧА МИКРОТРАНЗАКЦИЙ. Всё, что меняет профиль, идёт через
-- process(grant) (идемпотентно по PurchaseId). Живые эффекты (встать,
-- удача, щит) применяются после подтверждения.
--------------------------------------------------------------------------------
function MonetizationService:_grantMicro(player, receiptInfo, key, micro, process)
	local granted = Enum.ProductPurchaseDecision.PurchaseGranted
	local notProcessed = Enum.ProductPurchaseDecision.NotProcessedYet
	local function notify(text)
		if Services.NotifyService then
			Services.NotifyService:Show(player, text, { Icon = "Reward", Duration = 3 })
		end
	end

	if key == "GetUp" then
		local result = process(function() return true end)
		if result == granted and Services.CombatService and Services.CombatService.EndRagdollNow then
			pcall(Services.CombatService.EndRagdollNow, Services.CombatService, player)
		end
		return result
	elseif key == "Revenge" then
		local entry = losses[player]
		local amount = entry and math.floor(entry.Value * (Config.Offers.RevengeShare or 0.5)) or 0
		local result = process(function(data)
			if amount > 0 then
				data.Money = (BigNum.fromData(data.Money) + amount):clamp(BigNum.new(0), MONEY_SAFETY_CAP):toData()
			end
			return true
		end)
		if result == granted then
			losses[player] = nil
			notify(("💢 Got back $%s!"):format(require(ReplicatedStorage.Shared.NumberFormat).abbreviate(amount)))
		end
		return result
	elseif micro.Gear then
		local result = process(function(data)
			data.Gear = data.Gear or {}
			data.Gear[micro.Gear] = (tonumber(data.Gear[micro.Gear]) or 0) + (micro.Count or 1)
			return true
		end)
		if result == granted and Services.GearService then
			Services.GearService:SendState(player)
			if Services.InventoryService and Services.InventoryService.OnGearChanged then
				pcall(Services.InventoryService.OnGearChanged, Services.InventoryService, player, micro.Gear, micro.Count or 1)
			end
			notify(("+%d %s"):format(micro.Count or 1, micro.Title))
		end
		return result
	elseif key == "MineRush" then
		local result = process(function(data)
			data.MineRushCharges = (tonumber(data.MineRushCharges) or 0) + (micro.Charges or 3)
			return true
		end)
		if result == granted then
			player:SetAttribute("MineRushCharges", (Services.DataService:GetGeodeData(player) or {}).MineRushCharges or 0)
			notify("⛏ Mine Rush! Next digs give x2 ore.")
		end
		return result
	elseif key == "PerfectStrike" then
		local result = process(function(data)
			data.PerfectStrikes = (tonumber(data.PerfectStrikes) or 0) + (micro.Charges or 1)
			return true
		end)
		if result == granted then
			player:SetAttribute("PerfectStrikes", (Services.DataService:GetGeodeData(player) or {}).PerfectStrikes or 0)
			local usedNow = Services.RockService and Services.RockService.ForcePerfect
				and select(2, pcall(Services.RockService.ForcePerfect, Services.RockService, player)) == true
			if not usedNow then notify("🎯 Your next boulder breaks PERFECT instantly!") end
		end
		return result
	elseif key == "MerchantRestock" then
		-- Личный перезаброс стока торговца банка (кнопка RESTOCK). Сам
		-- сток живёт в памяти MerchantService и привязан к циклу, в
		-- профиль писать нечего.
		local result = process(function()
			return true
		end)
		if result == granted and Services.MerchantService then
			Services.MerchantService:PersonalRestock(player)
			notify("🔄 The merchant restocked just for you!")
		end
		return result
	elseif key == "FillSafe" then
		-- v4: сейф сразу до потолка. Нет кристалла на подиуме — деньги
		-- FallbackMinutes активного дохода (покупка не должна сгореть).
		local passive = Services.PassiveIncomeService
		local room = passive and passive.GetSafeRoom and passive:GetSafeRoom(player) or nil
		local fallback = 0
		if not room or room <= 0 then
			local tiers = Services.DataService:GetTiers(player)
			fallback = math.floor((micro.FallbackMinutes or 30) * Config.IncomePerMinute(tiers.Mine, tiers.Cart)
				* (Config.Economy.RealIncomeFactor or 1) * Services.DataService:GetCrystalMultiplier(player))
		end
		local result = process(function(data)
			if room and room > 0 then
				data.GeodeSafeBalance = (tonumber(data.GeodeSafeBalance) or 0) + room
			else
				data.Money = (BigNum.fromData(data.Money) + math.max(1, fallback)):clamp(BigNum.new(0), MONEY_SAFETY_CAP):toData()
			end
			return true
		end)
		if result == granted then
			if room and room > 0 then
				if passive and passive.UpdateDisplay then pcall(passive.UpdateDisplay, passive, player) end
				notify("🏦 Your safe is FULL - go collect it!")
			else
				notify(("🏦 No crystal on the podium - got $%s instead!"):format(require(ReplicatedStorage.Shared.NumberFormat).abbreviate(fallback)))
			end
		end
		return result
	elseif key == "SmeltNow" then
		local result = process(function(data)
			for _, slot in data.SmelterSlots or {} do
				slot.StartedAt = os.time() - (slot.Duration or 0) - 1
			end
			return true
		end)
		if result == granted and Services.IslandService and Services.IslandService._updateSmelter then
			pcall(Services.IslandService._updateSmelter, Services.IslandService, player)
			notify("🔥 Smelting finished - click the smelter!")
		end
		return result
	end

	-- Эффекты по времени (без записи в профиль — как погода): подтверждаем
	-- сразу после применения. Сбой — NotProcessedYet, Roblox повторит.
	local ok = pcall(function()
		if key == "LuckPotion" then
			local now = os.time()
			local current = personalLuck[player]
			local startAt = (current and current.Until > now) and current.Until or now
			personalLuck[player] = { Until = startAt + micro.Seconds, Ore = micro.OreLuck or 0.15, Mutation = micro.MutationMultiplier or 2 }
			player:SetAttribute("LuckPotionUntil", personalLuck[player].Until)
			notify("🍀 Luck x2 for 15 minutes!")
		elseif key == "ServerLuck2" or key == "ServerLuck3" then
			setServerLuck(micro.MutationMultiplier or 2, micro.OreLuck or 0.1, micro.Seconds or 900, player)
		elseif key == "MoneyRush" then
			Services.BuffService:Grant(player, "Money", 1, micro.Seconds or 300, "MONEY x2")
			notify("💵 Money x2 for 5 minutes!")
		else
			error("unknown micro " .. tostring(key))
		end
	end)
	return ok and granted or notProcessed
end

function MonetizationService:InitOffers()
	offerRemote = Instance.new("RemoteEvent")
	offerRemote.Name = "OfferEvent"
	offerRemote.Parent = ReplicatedStorage.Shared
	Players.PlayerRemoving:Connect(function(player)
		losses[player] = nil
		personalLuck[player] = nil
	end)
end

return MonetizationService
