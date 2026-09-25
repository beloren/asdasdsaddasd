--------------------------------------------------------------------------------
-- MerchantService — ТОРГОВЕЦ БАНКА И БИРЖА РУДЫ (заменили слайма).
--
-- Один торговец на сервер, стоит в зоне банка постоянно. Раз в
-- Config.Merchant.CycleSeconds ОДНОВРЕМЕННО:
--   • КУРС — новый общий множитель цены продажи всей руды (GetMarketMultiplier);
--   • СТОК — что и сколько лежит в лавке в этом цикле.
--
-- ЧТО ВИДИТ КЛИЕНТ:
--   workspace-атрибуты (общие для всех, без отдельного трафика):
--     MarketMultiplier   — текущий курс (число)
--     MarketBucket       — Id корзины курса ("Crash".."Jackpot")
--     MerchantRestockAt  — время следующего цикла (workspace:GetServerTimeNow())
--     MerchantCycle      — номер цикла
--   RemoteEvent  Shared.MerchantState   — личный снимок лавки (цены по тирам
--                                         игрока, остаток его личного стока,
--                                         его зелья) + команда "Open";
--   RemoteFunction Shared.MerchantRequest — Buy / GetState.
--
-- Зелья — снаряжение (Config.Potions, GearService): купленное ложится в
-- инвентарь, пьётся кликом с зельем в руке.
--
-- СТОК ЛИЧНЫЙ. Глобально катается только "сколько штук положено в этом
-- цикле", а покупки считаются на игрока: двое игроков не отнимают друг у
-- друга товар (как в Grow a Garden). Личный RESTOCK (dev product) заменяет
-- игроку сток текущего цикла новым броском и обнуляет его покупки.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local BigNum = require(ReplicatedStorage.Shared.BigNum)
local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)
local PlaceableCatalog = require(ReplicatedStorage.Shared.PlaceableCatalog)

local MerchantService = {}

local Services = nil
local CFG = Config.Merchant

local stateRemote = nil
local requestRemote = nil

local cycle = 0
local nextRestockAt = 0
local marketMultiplier = 1
local marketBucketId = "Normal"
local globalStock = {} -- [itemId] = сколько штук положено в этом цикле

-- [player] = { Cycle = n, Stock = {…} | nil (личный реролл), Bought = { [itemId] = n }, Busy = bool }
local personal = {}

-- v14: товары лавки = статичные (CFG.Items, вкладка SHOP) + ПРЕДЛОЖЕНИЯ
-- ЦИКЛА (cycleOffers): тотемы/декор для вкладки BASE и лимитированная
-- кирка. Предложения катаются заново каждый цикл, поэтому itemById
-- пересобирается в _newCycle.
local staticById = {}
for _, item in CFG.Items do
	item.Tab = item.Tab or "Shop"
	staticById[item.Id] = item
end
local itemById = table.clone(staticById)
local cycleOffers = {}
local limitedLastCycle = {} -- [skinId] = цикл, когда лимитка была в стоке

--------------------------------------------------------------------------------
-- БИРЖА
--------------------------------------------------------------------------------
local function rollMarket(rng)
	local buckets = CFG.Market.Buckets
	local noRepeat = CFG.Market.NoRepeat or {}
	local total = 0
	for _, bucket in buckets do
		if not (noRepeat[bucket.Id] and bucket.Id == marketBucketId) then
			total += bucket.Weight
		end
	end
	local pick = rng:NextNumber() * total
	local chosen = buckets[1]
	for _, bucket in buckets do
		if not (noRepeat[bucket.Id] and bucket.Id == marketBucketId) then
			pick -= bucket.Weight
			if pick <= 0 then
				chosen = bucket
				break
			end
		end
	end
	local step = CFG.Market.Step or 0.05
	local value = chosen.Min + rng:NextNumber() * (chosen.Max - chosen.Min)
	value = math.floor(value / step + 0.5) * step
	return math.clamp(value, chosen.Min, chosen.Max), chosen
end

local function rollStock(rng)
	local stock = {}
	for _, item in CFG.Items do
		if rng:NextNumber() <= (item.Chance or 1) then
			stock[item.Id] = rng:NextInteger(item.Stock[1], item.Stock[2])
		else
			stock[item.Id] = 0
		end
	end
	for _, offer in cycleOffers do
		if rng:NextNumber() <= (offer.Chance or 1) then
			stock[offer.Id] = rng:NextInteger(offer.Stock[1], offer.Stock[2])
		else
			stock[offer.Id] = 0 -- v20.27: мебель не в стоке — видна, но не купить
		end
	end
	return stock
end

local function skinAvailable(skinId)
	local definition = Config.Skins.Definitions[skinId]
	if not definition then return false end
	if Services and Services.SkinService and Services.SkinService.IsSkinAvailable then
		local ok, available = pcall(Services.SkinService.IsSkinAvailable, Services.SkinService, skinId)
		return ok and available == true
	end
	return true
end

-- Предложения цикла: тотемы и декор (BASE) + лимитированная кирка (SHOP).
local function rollOffers(rng)
	local offers = {}
	local base = CFG.BaseOffers
	local placeables = Config.Placeables
	if base and placeables then
		-- v4: для КАЖДОГО тира катаются TotemsPerTier разных тотемов; игрок
		-- видит только тиры своего диапазона (см. visibleFor). Так в лавке
		-- всегда есть товар «по карману», а цены при этом фиксированные.
		local kinds = PlaceableCatalog.AllTotemKinds()
		local used = {}
		for tier = 1, #(placeables.TierPrices or {}) do
			local picked = 0
			for _ = 1, 20 do
				if picked >= (placeables.TotemsPerTier or 2) then break end
				local kind = kinds[rng:NextInteger(1, #kinds)]
				local placeableId = PlaceableCatalog.TotemId(kind.Type, tier, kind.Mutation)
				local info = PlaceableCatalog.Info(placeableId)
				if info and not used[placeableId] then
					used[placeableId] = true
					picked += 1
					table.insert(offers, {
						Id = "P_" .. placeableId, Kind = "Placeable", PlaceableId = placeableId, Tab = "Base",
						Rarity = info.Rarity, DisplayName = info.DisplayName, Icon = info.Icon,
						Price = info.Price, Stock = base.TotemStock or { 1, 1 },
						SortTier = tier, TotemTier = tier,
					})
				end
			end
		end
		-- v20.27: МЕБЕЛЬ ПОКАЗЫВАЕТСЯ ВСЯ (Config.Placeables.DecorOrder), у
		-- каждой свой шанс оказаться в стоке этого цикла: StockChance у самой
		-- мебели или по весу DecorWeights (частая — почти всегда, редкая —
		-- изредка). Не выпала — строка видна, но затемнена и не покупается.
		local maxWeight = 0
		for _, decorId in placeables.DecorOrder do
			maxWeight = math.max(maxWeight, placeables.DecorWeights[decorId] or 1)
		end
		local minChance, maxChance = base.DecorMinChance or 0.12, base.DecorMaxChance or 0.8
		for index, decorId in placeables.DecorOrder do
			local placeableId = PlaceableCatalog.DecorId(decorId)
			local info = PlaceableCatalog.Info(placeableId)
			local def = placeables.Decor[decorId]
			if info and def and not used[placeableId] then
				used[placeableId] = true
				local weight = placeables.DecorWeights[decorId] or 1
				local chance = def.StockChance or math.clamp(minChance + (weight / math.max(maxWeight, 1)) * (maxChance - minChance), 0, 1)
				table.insert(offers, {
					Id = "P_" .. placeableId, Kind = "Placeable", PlaceableId = placeableId, Tab = "Base",
					Rarity = info.Rarity, DisplayName = info.DisplayName, Icon = info.Icon,
					Price = info.Price, Stock = base.DecorStock or { 1, 1 }, Chance = chance,
					SortTier = 0, DecorIndex = index,
				})
			end
		end
	end
	local limited = CFG.Limited
	if limited and limited.Enabled and rng:NextNumber() <= (limited.Chance or 1) then
		local function candidates(pool, respectCooldown)
			local list = {}
			for _, skinId in pool or {} do
				local last = limitedLastCycle[skinId]
				local cooled = not respectCooldown or not last or (cycle - last) >= (limited.CooldownCycles or 0)
				if cooled and skinAvailable(skinId) then table.insert(list, skinId) end
			end
			return list
		end
		local list = candidates(limited.Pool, true)
		if #list == 0 then list = candidates(limited.FallbackPool, true) end
		if #list > 0 then
			local skinId = list[rng:NextInteger(1, #list)]
			local definition = Config.Skins.Definitions[skinId]
			limitedLastCycle[skinId] = cycle
			table.insert(offers, {
				Id = "L_" .. skinId, Kind = "Skin", SkinId = skinId, Tab = "Shop", Limited = true,
				Rarity = definition.Rarity or "Epic", DisplayName = definition.DisplayName or skinId, Icon = "⛏",
				Price = (limited.PriceByRarity or {})[definition.Rarity] or 400000,
				Stock = { 1, 1 },
			})
		end
	end
	return offers
end

function MerchantService:GetMarketMultiplier()
	return marketMultiplier
end

-- Полный множитель продажи для игрока: курс биржи × замороженный бонус
-- слайма. Cash-пассы/рефералка/бафы считаются отдельно, как и раньше
-- (MonetizationService), — сюда не входят.
function MerchantService:GetSellMultiplier(player)
	local legacy = 0
	if player and Services.DataService.GetLegacySellBonus then
		legacy = Services.DataService:GetLegacySellBonus(player)
	end
	return marketMultiplier * (1 + legacy)
end

--------------------------------------------------------------------------------
-- ЛИЧНОЕ СОСТОЯНИЕ
--------------------------------------------------------------------------------
local function personalOf(player)
	local entry = personal[player]
	if not entry or entry.Cycle ~= cycle then
		entry = { Cycle = cycle, Stock = nil, Bought = {}, Busy = entry and entry.Busy or false }
		personal[player] = entry
	end
	return entry
end

local dailyDealId -- объявлена ниже (скидка дня всегда в стоке)
local function stockLeft(player, itemId)
	local entry = personalOf(player)
	local base = (entry.Stock or globalStock)[itemId] or 0
	if dailyDealId and itemId == dailyDealId() then
		base = math.max(base, (CFG.DailyDeal and CFG.DailyDeal.Stock) or 1)
	end
	return math.max(0, base - (entry.Bought[itemId] or 0))
end

--------------------------------------------------------------------------------
-- v20.28: ЖЕОДЫ, «???», СКИДКА ДНЯ
--------------------------------------------------------------------------------
-- Две значащие цифры: 12 345 → 12 000 (ценники читаются сразу).
local function niceRound(value)
	value = math.max(1, value)
	local magnitude = 10 ^ math.max(0, math.floor(math.log10(value)) - 1)
	return math.floor(value / magnitude + 0.5) * magnitude
end

local function incomePerMinute(player)
	local tiers = Services.DataService:GetTiers(player)
	local ok, value = pcall(Config.IncomePerMinute, tiers.Mine or 1, tiers.Cart or 1)
	return ok and tonumber(value) or 100
end

local function geodeTypeFor(player, offset)
	local order = Config.Geodes.Order or {}
	if #order == 0 then return nil end
	local cave = Services.DataService:GetTiers(player).Mine or 1
	return order[math.clamp(cave + (offset or 0), 1, #order)]
end

-- Скидка дня: один товар вкладки SHOP на сутки (UTC), одинаковый у всех.
dailyDealId = function()
	local deal = CFG.DailyDeal
	if not (deal and deal.Enabled) then return nil end
	local eligible = {}
	for _, item in CFG.Items do
		if (item.Tab or "Shop") == "Shop" and deal.Kinds[item.Kind] then table.insert(eligible, item.Id) end
	end
	if #eligible == 0 then return nil end
	local day = math.floor(os.time() / 86400)
	return eligible[Random.new(day * 7919):NextInteger(1, #eligible)]
end

local function basePrice(player, item)
	if item.PriceMinutes then
		return niceRound(incomePerMinute(player) * item.PriceMinutes)
	end
	return math.max(0, math.floor(tonumber(item.Price) or 0))
end

-- v4: цены фиксированные (item.Price); v20.28: жеоды и «???» — в минутах
-- дохода игрока, товар дня — со скидкой.
local function priceFor(player, item)
	local price = basePrice(player, item)
	if item.Id == dailyDealId() then
		price = niceRound(price * (1 - (CFG.DailyDeal.Discount or 0.3)))
	end
	return price
end

-- v4: тотемы показываются только своего диапазона: тиры [свой-1 … свой+1],
-- где «свой» — PlaceableCatalog.TotemTierForCave(пещера игрока).
local function visibleFor(player, item)
	if not item.TotemTier then return true end
	local cave = Services.DataService:GetTiers(player).Mine or 1
	local own = PlaceableCatalog.TotemTierForCave(cave)
	return math.abs(item.TotemTier - own) <= 1
end

-- Почему товар сейчас нельзя купить (кроме денег/стока) — или nil.
local function lockReason(player, item)
	if item.Kind == "Skin" then
		if Services.SkinService:OwnsSkin(player, item.SkinId) then return "OWNED" end
		if Services.SkinService.IsSkinAvailable and not Services.SkinService:IsSkinAvailable(item.SkinId) then
			return "SOON"
		end
	elseif item.Kind == "Potion" then
		local info = Config.Potions and Config.Potions.Types[item.Potion]
		if not info then return "SOON" end
		local data = Services.DataService:GetGeodeData(player)
		local have = data and data.Gear and tonumber(data.Gear[item.Potion]) or 0
		if have >= (Config.Potions.MaxStack or 99) then return "FULL" end
	elseif item.Kind == "Gear" then
		local info = Config.Dynamite.Types[item.Key]
		if not info then return "SOON" end
		local cave = Services.DataService:GetTiers(player).Mine or 1
		if cave < (info.UnlockCave or 1) then
			return ("CAVE %d"):format(info.UnlockCave)
		end
	end
	return nil
end

-- Всё, что клиенту нужно для отрисовки строки, — прямо в снимке: лавке
-- на клиенте больше не нужен Config.Merchant.Items (товары цикла меняются).
local function skinEffect(skinId)
	local buffs = Config.SkinBuffs and Config.SkinBuffs[skinId]
	if not buffs then return "Pickaxe skin" end
	local lines = {}
	for stat, value in buffs do
		local info = Config.SkinStats and Config.SkinStats[stat]
		table.insert(lines, { value, ("%s%d%% %s"):format(value >= 0 and "+" or "-", math.floor(math.abs(value) * 100 + 0.5), info and info.Label or stat) })
	end
	table.sort(lines, function(a, b) return a[1] > b[1] end)
	local out = {}
	for _, line in lines do table.insert(out, line[2]) end
	return table.concat(out, " · ")
end

local function describe(item, player)
	local name, icon, image, effect = item.DisplayName, item.Icon, nil, nil
	if item.Kind == "Geode" then
		local geodeType = geodeTypeFor(player, item.GeodeOffset)
		local info = geodeType and Config.Geodes.Types[geodeType]
		name = info and info.DisplayName or "Geode"
		effect = "Goes straight to your geode vault"
		return name, icon or "🪨", image, effect
	elseif item.Kind == "Mystery" then
		return "???", "❓", nil, "A random surprise: potion, geode, furniture, cash… or a rare pickaxe!"
	end
	if item.Kind == "Potion" then
		local potion = Config.Potions and Config.Potions.Types[item.Potion]
		if potion then name, icon = potion.DisplayName, potion.Icon end
		local seconds = potion and potion.Seconds
		effect = seconds and ("Lasts %d min"):format(math.max(1, math.floor(seconds / 60))) or nil
	elseif item.Kind == "Skin" then
		local definition = Config.Skins.Definitions[item.SkinId]
		local imageId = definition and definition.ImageId or 0
		if imageId and imageId ~= 0 then image = "rbxassetid://" .. tostring(imageId) end
		name = name or (definition and definition.DisplayName)
		-- v20.28: бонусы кирки прямо в строке (+роль).
		local role = Config.SkinRoles and Config.SkinRoles[item.SkinId]
		effect = (role and (role:upper() .. ": ") or "") .. skinEffect(item.SkinId)
		if item.Limited then effect = "LIMITED — gone after this restock. " .. effect end
	elseif item.Kind == "Placeable" then
		effect = PlaceableCatalog.EffectText(PlaceableCatalog.Info(item.PlaceableId))
	end
	return name or item.Id, icon or "?", image, effect
end

local function wishlistOf(player)
	local data = Services.DataService:GetGeodeData(player)
	if not data then return {} end
	if type(data.MerchantWishlist) ~= "table" then data.MerchantWishlist = {} end
	return data.MerchantWishlist
end

function MerchantService:BuildState(player)
	local items = {}
	local order = 0
	local deal = dailyDealId()
	local wishlist = wishlistOf(player)
	local function add(item)
		order += 1
		local name, icon, image, effect = describe(item, player)
		local left = stockLeft(player, item.Id)
		local isDeal = item.Id == deal
		local sortOrder = item.Limited and -100 or (item.SortTier and (order - item.SortTier * 20) or order)
		if isDeal then sortOrder = -90 end
		-- v20.27/28: не в стоке — в конец списка (виден, но затемнён).
		if left <= 0 then sortOrder += 500 end
		local rarity = item.Rarity
		if item.Kind == "Geode" then
			local geodeType = geodeTypeFor(player, item.GeodeOffset)
			rarity = geodeType and Config.Geodes.Types[geodeType] and Config.Geodes.Types[geodeType].Rarity or "Common"
		end
		table.insert(items, {
			Id = item.Id,
			Tab = item.Tab or "Shop",
			Kind = item.Kind,
			DisplayName = name,
			Icon = icon,
			Image = image,
			Effect = effect,
			Rarity = rarity,
			Limited = item.Limited == true,
			Order = sortOrder,
			Stock = left,
			Price = priceFor(player, item),
			Lock = lockReason(player, item),
			-- v20.28
			SkinId = item.SkinId,
			Buffs = item.SkinId and Config.SkinBuffs and Config.SkinBuffs[item.SkinId] or nil,
			Deal = isDeal and math.floor((CFG.DailyDeal.Discount or 0.3) * 100 + 0.5) or nil,
			OldPrice = isDeal and basePrice(player, item) or nil,
			Wished = wishlist[item.Id] == true,
		})
	end
	for _, offer in cycleOffers do
		if offer.Limited then add(offer) end
	end
	for _, item in CFG.Items do add(item) end
	for _, offer in cycleOffers do
		if not offer.Limited and visibleFor(player, offer) then add(offer) end
	end
	local data = Services.DataService:GetGeodeData(player)
	return {
		EquippedSkin = data and data.EquippedSkins and data.EquippedSkins.Pickaxe or "",
		Cycle = cycle,
		RestockAt = nextRestockAt,
		Market = marketMultiplier,
		Bucket = marketBucketId,
		Items = items,
	}
end

function MerchantService:SendState(player, command)
	if not (player and player.Parent) then return end
	if command == "Open" then player:SetAttribute("MerchantWishAlert", nil) end -- v20.28: открыл — «!» гаснет
	local ok, state = pcall(function() return self:BuildState(player) end)
	if ok then
		stateRemote:FireClient(player, command or "State", state)
	end
end

--------------------------------------------------------------------------------
-- ПОКУПКА
--------------------------------------------------------------------------------
local function grant(player, item)
	if item.Kind == "Potion" then
		-- Зелье — снаряжение: ложится в инвентарь рядом с динамитом, ячеек
		-- рюкзака не тратит, ставится в хотбар (GearService:AddGear).
		return Services.GearService:AddGear(player, item.Potion, 1) > 0
	elseif item.Kind == "Gear" then
		local data = Services.DataService:GetGeodeData(player)
		local have = data and data.Gear and tonumber(data.Gear[item.Key]) or 0
		if have + 1 > (Config.Dynamite.MaxStack or math.huge) then return false, "Bag full" end
		return Services.GearService:AddGear(player, item.Key, 1) > 0
	elseif item.Kind == "Skin" then
		return Services.SkinService:GrantSkin(player, item.SkinId) == true
	elseif item.Kind == "Placeable" then
		return Services.BaseDecorService and Services.BaseDecorService:GrantItem(player, item.PlaceableId, 1) == true
	elseif item.Kind == "Geode" then
		local geodeType = geodeTypeFor(player, item.GeodeOffset)
		return geodeType ~= nil and Services.GeodeService:AddGeodeDirectly(player, geodeType) == true
	elseif item.Kind == "Mystery" then
		return MerchantService._openMystery(player)
	end
	return false
end

-- v20.28: «???» — выдаёт случайную награду, возвращает true, nil, reveal
-- (карточка для клиента, формат RevealCards).
local function grantMoneyMinutes(player, minutes)
	local amount = niceRound(incomePerMinute(player) * (minutes or 10))
	Services.DataService:AddMoney(player, amount)
	return { Kind = "Money", Amount = amount, Rarity = "Rare" }
end

local function pickWeighted(rng, list, weightOf)
	local total = 0
	for _, entry in list do total += weightOf(entry) end
	local roll = rng:NextNumber() * total
	for _, entry in list do
		roll -= weightOf(entry)
		if roll <= 0 then return entry end
	end
	return list[#list]
end

function MerchantService._openMystery(player)
	local pool = (CFG.Mystery and CFG.Mystery.Pool) or {}
	if #pool == 0 then return true, nil, grantMoneyMinutes(player, 10) end
	local rng = Random.new()
	local pick = pickWeighted(rng, pool, function(entry) return entry.Weight or 1 end)
	if pick.Kind == "Potion" then
		local order = Config.Potions and Config.Potions.Order or {}
		local key = order[rng:NextInteger(1, math.max(#order, 1))]
		if key and Services.GearService:AddGear(player, key, 1) > 0 then
			local rarity = "Rare"
			for _, item in CFG.Items do
				if item.Potion == key then rarity = item.Rarity or rarity end
			end
			return true, nil, { Kind = "Charm", Charm = key, Rarity = rarity }
		end
	elseif pick.Kind == "Geode" then
		local geodeType = geodeTypeFor(player, pick.GeodeOffset)
		if geodeType and Services.GeodeService:AddGeodeDirectly(player, geodeType) == true then
			local info = Config.Geodes.Types[geodeType]
			return true, nil, { Kind = "Geode", Title = info.DisplayName, Text = info.DisplayName, Rarity = info.Rarity }
		end
	elseif pick.Kind == "Decor" then
		local placeables = Config.Placeables
		local decorId = pickWeighted(rng, placeables.DecorOrder, function(id) return placeables.DecorWeights[id] or 1 end)
		local placeableId = PlaceableCatalog.DecorId(decorId)
		local info = PlaceableCatalog.Info(placeableId)
		if info and Services.BaseDecorService and Services.BaseDecorService:GrantItem(player, placeableId, 1) == true then
			return true, nil, { Kind = "Decor", Title = info.DisplayName, Text = info.DisplayName, Rarity = info.Rarity }
		end
	elseif pick.Kind == "Skin" then
		local candidates = {}
		for _, skinId in pick.Skins or {} do
			if skinAvailable(skinId) and not Services.SkinService:OwnsSkin(player, skinId) then table.insert(candidates, skinId) end
		end
		if #candidates > 0 then
			local skinId = candidates[rng:NextInteger(1, #candidates)]
			if Services.SkinService:GrantSkin(player, skinId) == true then
				local definition = Config.Skins.Definitions[skinId]
				return true, nil, { Kind = "Skin", SkinId = skinId, Rarity = definition and definition.Rarity or "Epic", New = true }
			end
		end
		local fallback = pick.Fallback or { Minutes = 20 }
		return true, nil, grantMoneyMinutes(player, fallback.Minutes)
	elseif pick.Kind == "Money" then
		return true, nil, grantMoneyMinutes(player, pick.Minutes)
	end
	-- Что-то не выдалось (полный инвентарь, занята транзакция) — деньги.
	return true, nil, grantMoneyMinutes(player, 10)
end

function MerchantService:Buy(player, itemId)
	local item = itemById[itemId]
	if not item then return false, "Unknown item" end
	if not visibleFor(player, item) then return false, "Not available" end
	if player:GetAttribute("EconomyTransactionLocked") == true then return false, "Try again" end
	local entry = personalOf(player)
	if entry.Busy then return false, "Busy" end
	if stockLeft(player, itemId) <= 0 then return false, "NO STOCK" end
	local lock = lockReason(player, item)
	if lock then return false, lock end

	local cost = priceFor(player, item)
	if BigNum.lt(Services.DataService:GetMoney(player), cost) then
		return false, "Not enough money"
	end

	-- Busy: выдача скина сохраняет профиль (yield). Без блокировки второй
	-- запрос проскочил бы мимо проверки стока до того, как первый
	-- записал покупку.
	entry.Busy = true
	local purchaseCycle = cycle
	local ok, granted, reason, reveal = pcall(grant, player, item)
	entry.Busy = false
	if not ok or not granted then
		if not ok then warn("[MerchantService] покупка", itemId, granted) end
		return false, (ok and reason) or "Purchase failed"
	end
	Services.DataService:AddMoney(player, -cost)
	-- Цикл мог смениться, пока сохранялся профиль: покупку записываем в
	-- тот цикл, в котором её проверяли (personalOf пересоздаст запись).
	if personalOf(player).Cycle == purchaseCycle then
		entry.Bought[itemId] = (entry.Bought[itemId] or 0) + 1
	end
	if Services.QuestService and Services.QuestService.RecordMetric then
		pcall(function() Services.QuestService:RecordMetric(player, "MerchantBuys", 1) end)
	end
	self:SendState(player)
	return true, reveal
end

-- v20.28: «напомни мне» — звёздочка на товаре.
function MerchantService:ToggleWish(player, itemId)
	if not (CFG.Wishlist and CFG.Wishlist.Enabled) then return false end
	if not itemById[itemId] and not staticById[itemId] and not itemId:match("^P_") then return false end
	local wishlist = wishlistOf(player)
	if wishlist[itemId] then
		wishlist[itemId] = nil
	else
		local count = 0
		for _ in wishlist do count += 1 end
		if count >= (CFG.Wishlist.MaxWishes or 8) then return false, "Too many stars" end
		wishlist[itemId] = true
	end
	self:SendState(player)
	return true
end

-- Новый цикл: отмеченные товары в стоке — уведомление и «!» над торговцем.
function MerchantService:_notifyWishes(player)
	if not (CFG.Wishlist and CFG.Wishlist.Enabled) then return end
	local names = {}
	for itemId in wishlistOf(player) do
		local item = itemById[itemId]
		if item and visibleFor(player, item) and stockLeft(player, itemId) > 0 then
			table.insert(names, (describe(item, player)))
		end
	end
	if #names == 0 then return end
	player:SetAttribute("MerchantWishAlert", table.concat(names, ", "))
	if Services.NotifyService then
		Services.NotifyService:Show(player, ("⭐ IN STOCK at the Ore Merchant: %s!"):format(table.concat(names, ", ")), { Icon = "Quest", Duration = 7 })
	end
end

--------------------------------------------------------------------------------
-- ЛИЧНЫЙ RESTOCK (dev product MerchantRestock, см. MonetizationService)
--------------------------------------------------------------------------------
function MerchantService:PersonalRestock(player)
	local entry = personalOf(player)
	entry.Stock = rollStock(Random.new())
	entry.Bought = {}
	self:SendState(player, "Restocked")
end

--------------------------------------------------------------------------------
-- ЦИКЛ
--------------------------------------------------------------------------------
local function announceMarket(bucket)
	if not (bucket.Announce and Services.AnnounceService) then return end
	local arrow = marketMultiplier >= 1 and "📈" or "📉"
	local text = ("%s ORE PRICES %s: x%.2f for the next %d min!"):format(
		arrow, bucket.Label, marketMultiplier, math.floor(CFG.CycleSeconds / 60))
	pcall(function() Services.AnnounceService:Broadcast(text, bucket.Color) end)
end

-- Редкий товар в стоке — объявление всему серверу. Сток личный, но
-- цикл общий: "Void Pickaxe у торговца ещё 5 минут" — повод доехать.
function MerchantService:_announceRareStock()
	if not (CFG.AnnounceRarities and Services.AnnounceService) then return end
	for _, offer in cycleOffers do
		if offer.Limited and (globalStock[offer.Id] or 0) > 0 then
			local color = CFG.RarityColors[offer.Rarity] or Color3.new(1, 1, 1)
			pcall(function()
				Services.AnnounceService:Broadcast(("⏳ LIMITED %s is at the Ore Merchant — only this restock!"):format(offer.DisplayName), color)
			end)
		end
	end
	for _, item in CFG.Items do
		if CFG.AnnounceRarities[item.Rarity] and (globalStock[item.Id] or 0) > 0 then
			local name = item.DisplayName
				or (item.Potion and Config.Potions.Types[item.Potion] and Config.Potions.Types[item.Potion].DisplayName)
				or item.Id
			local color = CFG.RarityColors[item.Rarity]
			pcall(function()
				Services.AnnounceService:Broadcast(("⭐ %s %s is in the Ore Merchant's stock!"):format(item.Rarity:upper(), name), color)
			end)
		end
	end
end

function MerchantService:_newCycle()
	cycle += 1
	local rng = Random.new()
	local multiplier, bucket = rollMarket(rng)
	marketMultiplier = multiplier
	marketBucketId = bucket.Id
	cycleOffers = rollOffers(rng)
	itemById = table.clone(staticById)
	for _, offer in cycleOffers do itemById[offer.Id] = offer end
	globalStock = rollStock(rng)
	nextRestockAt = workspace:GetServerTimeNow() + CFG.CycleSeconds

	workspace:SetAttribute("MarketMultiplier", marketMultiplier)
	workspace:SetAttribute("MarketBucket", marketBucketId)
	workspace:SetAttribute("MerchantRestockAt", nextRestockAt)
	workspace:SetAttribute("MerchantCycle", cycle)

	announceMarket(bucket)
	self:_announceRareStock()
	-- Подписи стоимости на тележках считают курс — без пересчёта они
	-- показывали бы старую цифру до следующей добычи.
	if Services.CartService and Services.CartService.RefreshAllValueLabels then
		pcall(function() Services.CartService:RefreshAllValueLabels() end)
	end
	for _, player in Players:GetPlayers() do
		self:SendState(player, "Restocked")
		pcall(self._notifyWishes, self, player)
	end
end

--------------------------------------------------------------------------------
-- НПС
--------------------------------------------------------------------------------
local function findSpot(bankModel)
	if not bankModel then return nil end
	for _, name in { "MerchantSpot", "SlimeSpot" } do
		local marker = bankModel:FindFirstChild(name, true)
		if marker and marker:IsA("BasePart") then return marker.Position end
	end
	return nil
end

-- ОСТАТКИ СЛАЙМА в модели банка (своя модель из места, собранная ещё при
-- слайме): табличка "LEVEL N", модель слайма и т.п. Код их больше не
-- создаёт, но в сохранённом месте они могли остаться и висеть над кротом.
local function removeSlimeLeftovers(root)
	if not root then return end
	for _, descendant in root:GetDescendants() do
		if descendant.Parent and descendant.Name:lower():find("slime") then
			if descendant:IsA("BasePart") and descendant.Name == "SlimeSpot" then
				-- Маркер места — оставляем, по нему встаёт торговец.
				for _, child in descendant:GetChildren() do child:Destroy() end
			else
				descendant:Destroy()
			end
		end
	end
	for _, gui in root:GetDescendants() do
		if gui:IsA("BillboardGui") and gui.Name ~= "MerchantBoard" and gui.Parent then
			for _, label in gui:GetDescendants() do
				if label:IsA("TextLabel") and label.Text:upper():find("LEVEL") then
					gui:Destroy()
					break
				end
			end
		end
	end
end

function MerchantService:_spawnNpc()
	local zone = Services.WorldService:GetSellZone()
	if not zone then
		warn("[MerchantService] Нет SellZone — торговец не поставлен.")
		return
	end
	local bankModel = zone:FindFirstAncestorWhichIsA("Model")
	removeSlimeLeftovers(bankModel)
	-- v20.19: без маркера MerchantSpot — справа ЗА краем зоны продажи, а не
	-- внутри неё (к торговцу можно подойти, не продавая руду).
	local spot = findSpot(bankModel)
		or (zone.CFrame * CFrame.new(zone.Size.X / 2 + 6, zone.Size.Y / 2, 0)).Position
	local model = PlaceholderFactory.BankMerchant()
	model.Name = "BankMerchant"
	model:SetAttribute("BankMerchant", true)
	-- ЛИЦОМ НАРУЖУ, от здания банка к подъезжающим игрокам. Раньше
	-- (слайм) целью был центр зоны — а он под зданием, и торговец смотрел
	-- бы в стену. Пивот модели — у ног (см. PlaceholderFactory.BankMerchant).
	local building = bankModel and bankModel:FindFirstChild("Building", true)
	local center = building and building:IsA("BasePart") and building.Position or zone.Position
	local outward = Vector3.new(spot.X - center.X, 0, spot.Z - center.Z)
	if outward.Magnitude < 0.5 then outward = zone.CFrame.LookVector * Vector3.new(1, 0, 1) end
	model:PivotTo(CFrame.lookAt(spot, spot + outward.Unit))
	if CFG.ShowBoard == false then
		local board = model:FindFirstChild("MerchantBoard", true)
		if board then board:Destroy() end
	end
	removeSlimeLeftovers(model)
	model.Parent = workspace

	local anchor = model:FindFirstChild("PromptAnchor", true) or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart", true)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "MerchantPrompt"
	prompt.ActionText = "BUY"
	prompt.ObjectText = CFG.DisplayName
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = CFG.PromptDistance or 12
	prompt.RequiresLineOfSight = false
	-- Custom: рисуется на самом торговце (client/WorldPrompts.client.lua),
	-- как все промпты в игре; Talk — приоритет над соседними промптами.
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute("PromptKind", "Talk")
	prompt.Parent = anchor
	prompt.Triggered:Connect(function(player)
		self:SendState(player, "Open")
	end)
end

--------------------------------------------------------------------------------
-- ЖИЗНЕННЫЙ ЦИКЛ СЕРВИСА
--------------------------------------------------------------------------------
function MerchantService:Init(services)
	Services = services
	local shared = ReplicatedStorage.Shared
	stateRemote = shared:FindFirstChild("MerchantState") or Instance.new("RemoteEvent")
	stateRemote.Name = "MerchantState"
	stateRemote.Parent = shared
	requestRemote = shared:FindFirstChild("MerchantRequest") or Instance.new("RemoteFunction")
	requestRemote.Name = "MerchantRequest"
	requestRemote.Parent = shared

	requestRemote.OnServerInvoke = function(player, action, arg)
		if not CFG.Enabled then return false, "Disabled" end
		if action == "Buy" and typeof(arg) == "string" then
			return self:Buy(player, arg)

		elseif action == "Wish" and typeof(arg) == "string" then
			return self:ToggleWish(player, arg)

		elseif action == "GetState" then
			-- Открыл лавку — «!» над торговцем гаснет.
			player:SetAttribute("MerchantWishAlert", nil)
			return true, self:BuildState(player)
		end
		return false, "Bad request"
	end

	Players.PlayerRemoving:Connect(function(player)
		personal[player] = nil
	end)
end

function MerchantService:Start()
	if not CFG.Enabled then return end
	self:_newCycle()
	local ok, err = pcall(function() self:_spawnNpc() end)
	if not ok then warn("[MerchantService] Торговец не поставлен:", err) end
	task.spawn(function()
		while true do
			task.wait(0.5)
			if workspace:GetServerTimeNow() >= nextRestockAt then
				self:_newCycle()
			end
		end
	end)
end

function MerchantService:SetupPlayer(player)
	-- Перенос зелий из прежнего отдельного хранилища (data.Potions, по
	-- виду бафа) в снаряжение. Одноразово: после переноса поле удаляется.
	local data = Services.DataService:GetGeodeData(player)
	if data and type(data.Potions) == "table" then
		local byBuff = { Speed = "Potion_Speed", Money = "Potion_Money", Luck = "Potion_Luck", MutationPotion = "Potion_Mutation" }
		for buff, count in data.Potions do
			local key = byBuff[buff]
			if key and (tonumber(count) or 0) > 0 then
				pcall(function() Services.GearService:AddGear(player, key, math.floor(count)) end)
			end
		end
		data.Potions = nil
	end
	self:SendState(player)
end

return MerchantService
