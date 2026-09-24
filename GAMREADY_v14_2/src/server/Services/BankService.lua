--------------------------------------------------------------------------------
-- BankService
-- Тележка в руках игрока въезжает в золотую зону → кристаллы по одному
-- улетают в банк, деньги идут ТЕКУЩЕМУ ДЕРЖАТЕЛЮ (угнал — забрал добычу).
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config)
local Sfx = require(ReplicatedStorage.Shared.Sfx)
local CrystalUtil = require(ReplicatedStorage.Shared.CrystalUtil)
local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)

local BankService = {}

local Services = nil
local sellingHands = {} -- [userId] = true, пока идёт распродажа руды из рук (см. Start/_sellHands)
local sellingBackpack = {} -- [userId] = true, пока идёт распродажа руды из рюкзака (см. Start/_sellBackpack)
local depositingRubbleCrystal = {} -- [userId] = true while the one-slot crystal is being saved
local moneyGainRemote = nil
local pendingMoneyFx = {} -- [player] = accumulated payout during a short sale burst

local coinFxRemote = nil
local sellFxRemote = nil

--------------------------------------------------------------------------------
-- МОНЕТКИ И ПОЛЁТ РУДЫ — ТЕПЕРЬ НА КЛИЕНТЕ (client/SellFx.client.lua).
--
-- Раньше монетки были серверными Part'ами, которые сервер двигал каждый
-- кадр через task.wait(): каждый шаг реплицировался всем игрокам — отсюда
-- рывки у получателя и лишний трафик у остальных. Сервер теперь только
-- говорит "откуда и сколько", а физику, дугу, блеск и магнит к игроку
-- считает клиент — плавно, на своей частоте кадров.
--
--   CoinBurstFx (игроку)  — (origin: Vector3?, weight: number)
--   SellFx (всем)         — полёт проданной руды в банк, см. _sell/_sellBackpack
--------------------------------------------------------------------------------
local function spawnCoinBurst(player, sourcePosition, weight)
	if not (player and player.Parent and coinFxRemote) then return end
	coinFxRemote:FireClient(player, sourcePosition, weight or 1)
end

local function fireSellFx(payload)
	if sellFxRemote then sellFxRemote:FireAllClients(payload) end
end

-- Множитель биржи торговца, зафиксированный на старте продажи (как и комбо
-- тележки): курс может смениться посреди распродажи большой тележки, и
-- без фиксации её хвост уходил бы по другой цене.
-- Описание проданного куска для клиента: тип руды (чтобы построить ту же
-- модель) и где он лежал. Для старых кристаллов без типа — цвет и размер.
local function oreFxPayload(crystal, root, holder, payout, market, index, target)
	local rootColor, rootSize = nil, nil
	if root and root:IsA("BasePart") then
		rootColor, rootSize = root.Color, root.Size
	end
	return {
		Kind = "Ore",
		Holder = holder.UserId,
		From = root and root.Position or target,
		To = target,
		Ore = crystal:GetAttribute("CrystalOre"),
		Variant = crystal:GetAttribute("CrystalVariant"),
		Smelted = crystal:GetAttribute("Smelted") == true,
		Color = rootColor,
		Size = rootSize,
		Payout = payout,
		Market = market,
		Index = index,
	}
end

local function marketAtStart()
	return Services.MerchantService and Services.MerchantService:GetMarketMultiplier() or 1
end

local function legacyBonus(player)
	return Services.DataService.GetLegacySellBonus and Services.DataService:GetLegacySellBonus(player) or 0
end

local function queueMoneyFx(player, amount)
	-- v17: доход от продажи показывает счётчик над торговцем (SellFx) —
	-- дублировать его экранной надписью не нужно.
	if Config.Bank.ScreenMoneyPopupOnSell ~= true then return end
	if not (player and player.Parent and moneyGainRemote) then return end
	local pending = pendingMoneyFx[player]
	if pending then
		pending.Amount += amount
		return
	end
	pending = { Amount = amount }
	pendingMoneyFx[player] = pending
	task.delay(0.25, function()
		if pendingMoneyFx[player] ~= pending then return end
		pendingMoneyFx[player] = nil
		if player.Parent then
			moneyGainRemote:FireClient(player, pending.Amount)
		end
	end)
end

local function isInZone(zone, position)
	local relative = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(relative.X) <= half.X + 2
		and math.abs(relative.Z) <= half.Z + 2
		and math.abs(relative.Y) <= 15
end

-- Куда улетает проданная руда: В САМ БАНК (WorldService:GetBankTargetPosition —
-- маркер SellTarget или середина здания). Раньше целью был маркер слайма.
local function sellTargetPosition(_zone)
	return Services.WorldService:GetBankTargetPosition()
end

--------------------------------------------------------------------------------
-- УДАЛЕНО (обучение v7): recordTutorialOreSold.
--
-- Эта функция ДОПЛАЧИВАЛА новичку недостающую сумму до цены первого
-- апгрейда шахты прямо в момент первой продажи. В прежнем гайде это было
-- вынужденной заплаткой: авто-добыча давала руду копейками, и без доплаты
-- игрок не мог перейти к шагу «улучши шахту».
--
-- Теперь копить в прологе не на что вообще: и починка шахты, и первая
-- тележка бесплатны (см. Config.Mine.Broken.RepairCostDuringTutorial), а
-- продажа стоит последним шагом — как демонстрация цикла, а не как способ
-- наскрести на следующий шаг.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- ПРОДАЖА РУДЫ ИЗ РЮКЗАКА (см. Config.Bank.InventorySellEnabled).
--
-- Отличия от продажи тележкой, все намеренные:
--   • НЕТ комбо-множителя рейса (Config.Cart.ComboThresholds, до x120) —
--     именно он и делает тележку смыслом игры;
--   • НЕТ кормления слайма банка: слайм растёт от рейсов, а не от того,
--     сколько раз игрок сбегал пешком;
--   • объём ограничен рюкзаком, а до первой тележки — стартовыми пятью
--     ячейками (см. InventoryService:GetSlotCount).
-- Множители за Robux (DoubleCash, рефералы) применяются как обычно: они
-- куплены игроком и не должны молча отключаться на части продаж.
--------------------------------------------------------------------------------
function BankService:_sellBackpack(player, zone)
	local targetPosition = sellTargetPosition(zone)
	local soldCount = 0
	local market = marketAtStart()
	while player.Parent do
		if player:GetAttribute("EconomyTransactionLocked") == true then task.wait(0.1); continue end
		if Services.MonetizationService and not Services.MonetizationService:IsEntitlementsReady(player) then
			Services.NotifyService:Show(player, "Purchase bonuses are still loading. Try selling again shortly.", { Icon = "Pending" })
			break
		end
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp or not isInZone(zone, hrp.Position) then break end

		-- Всегда берём ПЕРВУЮ стопку и ровно по одному куску: так продажа
		-- читается как процесс (монетки капают), а выход из зоны в любой
		-- момент оставляет остаток в рюкзаке нетронутым.
		local removed = Services.InventoryService:RemoveAt(player, 1, 1)
		if not removed then break end

		local payout = math.floor((tonumber(removed.Value) or 0) * market * (1 + legacyBonus(player)) + 0.5)
		fireSellFx({
			Kind = "Ore", Holder = player.UserId, From = hrp.Position + Vector3.new(0, 1.2, 0), To = targetPosition,
			Ore = removed.Ore, Variant = removed.Variant, Smelted = removed.Smelted,
			Payout = payout, Market = market, Index = soldCount,
		})
		if payout > 0 then
			if Services.MonetizationService then
				payout = math.floor(payout
					* Services.MonetizationService:GetCashMultiplier(player)
					* Services.MonetizationService:GetReferralMultiplier(player) + 0.5)
			end
			payout = math.min(payout, Config.Economy.MaxCurrency)
			Services.DataService:AddMoney(player, payout, targetPosition)
			Services.QuestService:RecordMetric(player, "MoneyEarned", payout)
			queueMoneyFx(player, payout)
		end
		Services.QuestService:RecordMetric(player, "OreSold", 1)
		soldCount += 1
		Sfx.play("Sell", hrp)
		task.wait(Config.Bank.InventorySellDelay or 0.12)
	end

	if soldCount > 0 then
		Services.InventoryService:Sync(player)
		-- Шаг обучения «отнеси руду в центр» закрывается по ФАКТУ первой
		-- продажи, а не по сумме: сумма зависит от того, сколько руды
		-- выпало с валунов, и привязывать к ней шаг значило бы иногда
		-- требовать второй заход без объяснения причины.
		if Services.TutorialService then
			pcall(function() Services.TutorialService:Count(player, "OreSoldFromBag", 1) end)
		end
	end
end

function BankService:Init(services)
	Services = services
	local shared = ReplicatedStorage.Shared
	coinFxRemote = shared:FindFirstChild("CoinBurstFx") or Instance.new("RemoteEvent")
	coinFxRemote.Name = "CoinBurstFx"
	coinFxRemote.Parent = shared
	sellFxRemote = shared:FindFirstChild("SellFx") or Instance.new("RemoteEvent")
	sellFxRemote.Name = "SellFx"
	sellFxRemote.Parent = shared
	moneyGainRemote = ReplicatedStorage.Shared:FindFirstChild("MoneyGainEvent")
	if not moneyGainRemote then
		moneyGainRemote = Instance.new("RemoteEvent")
		moneyGainRemote.Name = "MoneyGainEvent"
		moneyGainRemote.Parent = ReplicatedStorage.Shared
	end

	-- КРИТИЧНО: обе эти таблицы индексируются по player.UserId, а не по
	-- самому объекту Player, и раньше НЕ чистились при выходе. Если игрок
	-- отключался ровно в момент продажи/депозита, его флаг оставался
	-- висеть — и при возвращении НА ТОТ ЖЕ СЕРВЕР (userId тот же) продажа
	-- руды из рук и сдача кристалла для него уже не запускались вообще,
	-- молча, до самого рестарта сервера.
	Players.PlayerRemoving:Connect(function(player)
		sellingHands[player.UserId] = nil
		sellingBackpack[player.UserId] = nil
		depositingRubbleCrystal[player.UserId] = nil
		pendingMoneyFx[player] = nil
	end)
end

function BankService:Start()
	task.spawn(function()
		while true do
			task.wait(0.15)
			local zone = Services.WorldService:GetSellZone()
			if not zone then
				continue
			end
			for _, data in Services.CartService:GetAllCarts() do
				if not data.Selling
					and data.HolderUserId ~= nil
					and (not Players:GetPlayerByUserId(data.HolderUserId) or Players:GetPlayerByUserId(data.HolderUserId):GetAttribute("EconomyTransactionLocked") ~= true)
					and (#data.Crystals > 0 or Services.CartService:GetGeodeCount(data) > 0)
					and isInZone(zone, data.Root.Position)
				then
					data.Selling = true
					task.spawn(function()
						self:_sell(data, zone)
					end)
				end
			end

			-- Руда в руках (см. HandCarryService) продаётся в той же зоне,
			-- но привязана к позиции ИГРОКА, а не тележки — своего Root у неё нет.
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				local playerInZone = hrp and isInZone(zone, hrp.Position)
				-- Украденная жеода на спине (см. CrystalService:_flyToBack — нет
				-- тележки, зачислена в хранилище напрямую) визуально "сдаётся",
				-- как только игрок физически доходит до банка — не привязано к
				-- продаже руды/тележки, само хранилище уже давно пополнено,
				-- тут только уборка декорации.
				if playerInZone and Services.CrystalService then
					Services.CrystalService:ClearStolenGeodeVisuals(player)
				end
				if playerInZone and Services.RockService and Services.RockService:GetCarrying(player)
					and not depositingRubbleCrystal[player.UserId]
					and player:GetAttribute("EconomyTransactionLocked") ~= true
				then
					depositingRubbleCrystal[player.UserId] = true
					task.spawn(function()
						-- pcall ОБЯЗАТЕЛЕН: без него любая ошибка внутри
						-- DepositCarrying оставляла флаг навсегда true, и
						-- игрок до конца сессии больше не мог сдать ни
						-- одного кристалла в банк.
						local ok, err = pcall(function()
							Services.RockService:DepositCarrying(player)
						end)
						depositingRubbleCrystal[player.UserId] = nil
						if not ok then
							warn("[BankService] DepositCarrying упал:", err)
						end
					end)
				end
				-- ПРОДАЖА РУДЫ ИЗ РЮКЗАКА (см. Config.Bank.InventorySellEnabled).
				-- Единственный способ получить деньги до первой тележки —
				-- и, как следствие, единственное, что делает первые два
				-- шага обучения проходимыми. Комбо-множитель рейса тут не
				-- начисляется никогда, поэтому тележка остаётся строго
				-- выгоднее и после того, как станет доступна.
				if Config.Bank.InventorySellEnabled == true
					and playerInZone
					and not sellingBackpack[player.UserId]
					and player:GetAttribute("EconomyTransactionLocked") ~= true
					and Services.InventoryService
					and Services.InventoryService:CountItems(player) > 0
				then
					sellingBackpack[player.UserId] = true
					task.spawn(function()
						-- pcall обязателен по той же причине, что и у
						-- соседних флагов: ошибка в середине цикла
						-- оставила бы флаг взведённым навсегда, и игрок
						-- до конца сессии не смог бы продать ничего.
						local ok, err = pcall(function()
							self:_sellBackpack(player, zone)
						end)
						sellingBackpack[player.UserId] = nil
						if not ok then warn("[BankService] _sellBackpack упал:", err) end
					end)
				end
				-- ПРОДАЖА ИЗ РУК ВЫКЛЮЧЕНА (по прямому запросу — руду можно
				-- продавать ТОЛЬКО тележкой). Руда в руках теперь сама
				-- переливается в свою тележку (InventoryService:_depositOneToCart).
				if Config.Bank.HandSellEnabled ~= true then
					continue
				end
				if sellingHands[player.UserId] or player:GetAttribute("EconomyTransactionLocked") == true or not Services.HandCarryService:HasOre(player) then
					continue
				end
				if playerInZone then
					sellingHands[player.UserId] = true
					task.spawn(function()
						-- Тот же случай, что и с depositingRubbleCrystal
						-- выше: _sellHands сбрасывает флаг в своей
						-- последней строке, но до неё надо ещё дойти —
						-- ошибка в середине цикла продажи оставляла флаг
						-- навсегда и полностью ломала продажу руды из рук.
						local ok, err = pcall(function()
							self:_sellHands(player, zone)
						end)
						sellingHands[player.UserId] = nil
						if not ok then
							warn("[BankService] _sellHands упал:", err)
						end
					end)
				end
			end
		end
	end)
end

-- Продажа руды из рук: как и тележка, по одному кусочку с задержкой и той
-- же анимацией полёта в банк, но БЕЗ комбо-множителя тележки (см.
-- Config.HandCarry) — руки безопаснее в PvP, но сознательно менее выгодны
-- при продаже СВОЕЙ переполненной руды, чем гружёная тележка. ЗАТО ворованный
-- кусок (см. HandCarryService:SellOne — возвращает stolen отдельным флагом)
-- продаётся с бонусом Config.HandCarry.StolenOreMultiplier — успешная кража
-- должна окупать риск PvP, а не обесцениваться до голой базовой цены куска.
function BankService:_sellHands(player, zone)
	local soldCount = 0
	local targetPosition = sellTargetPosition(zone)
	while player.Parent do
		if player:GetAttribute("EconomyTransactionLocked") == true then task.wait(0.1); continue end
		if Services.MonetizationService and not Services.MonetizationService:IsEntitlementsReady(player) then
			Services.NotifyService:Show(player, "Purchase bonuses are still loading. Try selling again shortly.", { Icon = "Pending" })
			break
		end
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp or not isInZone(zone, hrp.Position) then
			break
		end
		local payout, tier, stolen = Services.HandCarryService:SellOne(player)
		if not payout then
			break -- стеш опустел
		end
		if stolen then
			payout = math.floor(payout * (Config.HandCarry.StolenOreMultiplier or 1) + 0.5)
		end
		payout = math.floor(payout * marketAtStart() * (1 + legacyBonus(player)) + 0.5)
		if Services.MonetizationService then
			payout = math.floor(payout * Services.MonetizationService:GetCashMultiplier(player) * Services.MonetizationService:GetReferralMultiplier(player) + 0.5) -- независимые x2/x4/x6/x8 складываются по номиналу, друзья на сервере умножают результат отдельно
		end
		payout = math.min(payout, Config.Economy.MaxCurrency)
		Services.DataService:AddMoney(player, payout, targetPosition)
		Services.QuestService:RecordMetric(player, "MoneyEarned", payout)
		Services.QuestService:RecordMetric(player, "OreSold", 1)
		if Services.TutorialService then
			pcall(function() Services.TutorialService:Count(player, "OreSoldFromBag", 1) end)
		end
		soldCount += 1
		queueMoneyFx(player, payout)
		Sfx.play("Sell", hrp)

		-- Визуал: в стеше рук нет физического объекта (см. HandCarryService —
		-- подобранное сразу схлопывается в число), поэтому для анимации
		-- временно создаём такой же плейсхолдер-кристалл прямо у спины игрока
		-- и растворяем его в банке — та же анимация, что и у тележки (см. _sell).
		fireSellFx({
			Kind = "Ore", Holder = player.UserId, From = hrp.Position + Vector3.new(0, 1.6, 0), To = targetPosition,
			Tier = tier or 1, Payout = payout, Index = soldCount,
		})

		local delay = Config.Bank.SellDelayPerCrystal * (Config.Bank.SellAcceleration ^ math.max(0, soldCount - 1))
		task.wait(math.max(Config.Bank.SellMinimumDelay, delay))
	end
	sellingHands[player.UserId] = nil
end

function BankService:_sell(data, zone)
	-- Множитель ФИКСИРУЕТСЯ на момент захода в зону — иначе таял бы
	-- на глазах с каждым проданным кристаллом.
	local multiplier = Services.CartService:GetComboMultiplier(data)
	local initialCrystalCount = #data.Crystals
	local beganAt70Percent = data.Capacity > 0 and initialCrystalCount >= data.Capacity * 0.70
	local soldCount = 0
	local targetPosition = sellTargetPosition(zone)
	local market = marketAtStart()
	local lastHolder = nil
	local initialHolder = Players:GetPlayerByUserId(data.HolderUserId)
	if initialHolder and Services.CartService:GetGeodeCount(data) > 0 then
		lastHolder = initialHolder
		Services.GeodeService:EvacuateCart(initialHolder, data)
	end

	while data.Model.Parent
		and data.HolderUserId ~= nil
		and #data.Crystals > 0
		and isInZone(zone, data.Root.Position)
	do
		local holder = Players:GetPlayerByUserId(data.HolderUserId)
		if not holder then
			break
		end
		lastHolder = holder
		if holder:GetAttribute("EconomyTransactionLocked") == true then task.wait(0.1); continue end
		if Services.MonetizationService and not Services.MonetizationService:IsEntitlementsReady(holder) then
			Services.NotifyService:Show(holder, "Purchase bonuses are still loading. Try selling again shortly.", { Icon = "Pending" })
			break
		end

		local crystal = Services.CartService:RemoveCrystals(data, 1)[1]
		if not crystal then
			break
		end
		holder:SetAttribute("MiningCartFill", #data.Crystals)

		local baseValue = crystal:GetAttribute("CrystalValue") or 1
		local payout = math.floor(baseValue * multiplier + 0.5)
		if Services.MonetizationService then
			payout = math.floor(payout * Services.MonetizationService:GetCashMultiplier(holder) * Services.MonetizationService:GetReferralMultiplier(holder) + 0.5) -- сумма cash-пассов; платят ТЕКУЩЕМУ держателю; друзья на сервере умножают отдельно
		end
		-- Биржа торговца (курс на момент въезда) × замороженный бонус слайма.
		payout = math.floor(payout * market * (1 + legacyBonus(holder)) + 0.5)
		payout = math.min(payout, Config.Economy.MaxCurrency)
		Services.DataService:AddMoney(holder, payout, targetPosition)
		Services.QuestService:RecordMetric(holder, "MoneyEarned", payout)
		Services.QuestService:RecordMetric(holder, "OreSold", 1)
		queueMoneyFx(holder, payout)
		Sfx.play("Sell", data.Root)
		soldCount = soldCount + 1


		-- Визуал: сервер кристалл СРАЗУ удаляет и сообщает клиентам только
		-- "что и откуда". Копию для полёта строит каждый клиент сам
		-- (SellFx.client.lua). Раньше клиент двигал серверный объект, а
		-- сервер продолжал держать его у себя в тележке: позиция дёргалась
		-- между двумя владельцами, и кусок улетал "неизвестно куда".
		local root = CrystalUtil.GetRoot(crystal)
		fireSellFx(oreFxPayload(crystal, root, holder, payout, market, soldCount, targetPosition))
		crystal:Destroy()

		local delay = Config.Bank.SellDelayPerCrystal * (Config.Bank.SellAcceleration ^ math.max(0, soldCount - 1))
		task.wait(math.max(Config.Bank.SellMinimumDelay, delay))
	end
	data.Selling = false

	-- ВСЯ тележка распродана ЦЕЛИКОМ (не просто выехала из зоны/держатель
	-- пропал на середине распродажи) — торжественный момент: звук + VFX над
	-- местом продажи (см. _celebrateFullSale).
	if soldCount > 0 and #data.Crystals == 0 and lastHolder then
		Sfx.play("CartBanked", data.Root)
		Services.QuestService:RecordMetric(lastHolder, "CartSales", 1)
		if multiplier >= (Config.Cart.QuestHighComboMultiplier or 4) then Services.QuestService:RecordMetric(lastHolder, "X4Sales", 1) end
		if beganAt70Percent then Services.QuestService:RecordMetric(lastHolder, "Cart70Sales", 1) end
		if initialCrystalCount >= data.Capacity then
			Services.QuestService:RecordMetric(lastHolder, "FullCartNoLoss", 1)
		end
		-- Финальный шаг обучения — ЛЮБАЯ продажа тележкой, а не строго
		-- полной. Прежний гайд требовал именно полную, и это стабильно
		-- вешало новичков: набить тележку под завязку на первой пещере —
		-- несколько заходов в шахту подряд, а задание при этом выглядело
		-- выполнимым с первой ходки.
		if Services.TutorialService then
			pcall(function() Services.TutorialService:Count(lastHolder, "CartSold", 1) end)
		end
		self:_celebrateFullSale(data)
	end
end

-- Звук + VFX-плейсхолдер над местом продажи (см. PlaceholderFactory.BankSellVFX,
-- заменяется своим без изменения кода). Крутящихся монеток-плейсхолдеров
-- больше нет — убраны целиком по просьбе (визуально мешали/были не нужны).
function BankService:_celebrateFullSale(data)
	Sfx.play("CartSoldOut", data.Root)

	local vfxAsset, _vfxRoot = PlaceholderFactory.BankSellVFX()
	local vfxCFrame = data.Root.CFrame * CFrame.new(0, Config.BankSellVfx.HeightOffset, 0)
	if vfxAsset:IsA("Model") then
		vfxAsset:PivotTo(vfxCFrame)
	else
		vfxAsset.CFrame = vfxCFrame
		vfxAsset.Anchored = true
	end
	vfxAsset.Parent = workspace
	Debris:AddItem(vfxAsset, Config.BankSellVfx.Duration)
end

-- Публичная обёртка — чтобы этой же 3D-монеткой мог пользоваться не только
-- BankService (см. PassiveIncomeService:Collect — сбор денег из сейфа тоже
-- заслуживает ту же обратную связь, что и продажа руды). sourcePosition —
-- необязательно, откуда физически "вылетают" монетки (касса банка, сейф);
-- без него падают у ног игрока, как раньше.
function BankService:SpawnCoinBurst(player, sourcePosition, weight)
	spawnCoinBurst(player, sourcePosition, weight)
end

return BankService
