--------------------------------------------------------------------------------
-- DropTables (v18) — ЕДИНАЯ таблица шансов для жеод и сундуков.
--
-- Один и тот же модуль:
--   • сервер (GeodeService / GearService) — роллит награду по этим строкам;
--   • клиент (DropPreviewUI) — рисует окно шансов с предпросмотром.
-- Поэтому то, что игрок видит в окне, ровно то, что считает сервер
-- (требование Roblox к Random Item Generator'ам).
--
-- Строка: { Id, Kind, Title, Rarity, Chance (0..1, на ОДНУ награду), ... }
--   Kind = "Crystal" (OreId) | "Money" (Amount или Carts) | "Essence" (Mutation)
--        | "Heart" | "Skin" (SkinId) | "Charm" (Charm) | "PrestigePoint"
--------------------------------------------------------------------------------
local Config = require(script.Parent.Config)

local DropTables = {}

local mutationIndex = {}
for index, id in Config.Mutations.Order do mutationIndex[id] = index end

-- Редкость мутации по её месту в Config.Mutations.Order (от частых к редким).
function DropTables.MutationRarity(mutationId)
	local index = mutationIndex[mutationId] or 1
	if index <= 3 then return "Uncommon" end
	if index <= 7 then return "Rare" end
	if index <= 11 then return "Epic" end
	if index <= 15 then return "Legendary" end
	return "Mythic"
end

function DropTables.EssenceKey(mutationId)
	return "Essence_" .. tostring(mutationId)
end

function DropTables.EssenceMutation(key)
	if typeof(key) ~= "string" then return nil end
	local id = key:match("^Essence_(%a+)$")
	return id and Config.Mutations[id] and id or nil
end

-- Все ключи эссенций (для инвентаря), от редких к частым.
function DropTables.AllEssenceKeys()
	local list = {}
	for index = #Config.Mutations.Order, 1, -1 do
		table.insert(list, DropTables.EssenceKey(Config.Mutations.Order[index]))
	end
	return list
end

--------------------------------------------------------------------------------
-- ЖЕОДЫ
--------------------------------------------------------------------------------
local geodeCache = {}

function DropTables.Geode(geodeType)
	if geodeCache[geodeType] then return geodeCache[geodeType] end
	local info = Config.Geodes.Types[geodeType]
	if not info then return nil end
	local drops = Config.Geodes.Drops
	local rows = {}

	local ores = info.Ores or {}
	for _, oreId in ores do
		local ore = Config.Geodes.Ores[oreId]
		if ore then
			table.insert(rows, {
				Id = "Crystal_" .. oreId, Kind = "Crystal", OreId = oreId,
				Title = ore.DisplayName, Rarity = ore.Rarity or "Common",
				Chance = drops.Crystal / math.max(1, #ores),
				Description = "A crystal for your Income Podium. Duplicates level it up.",
			})
		end
	end

	local moneyRarity = { "Uncommon", "Rare", "Legendary" }
	for index, amount in info.Money or {} do
		table.insert(rows, {
			Id = "Money_" .. index, Kind = "Money", Amount = amount, Index = index,
			Title = index == 3 and "Jackpot" or "Cash",
			Rarity = moneyRarity[index] or "Uncommon",
			Chance = drops.Money * (Config.Geodes.MoneySplit[index] or 0),
			Description = "Money, straight to your balance.",
		})
	end

	local pool = Config.Geodes.Essence.ByGeode[geodeType] or {}
	local total = 0
	for _, pair in pool do total += pair[2] end
	for _, pair in pool do
		local mutation = Config.Mutations[pair[1]]
		if mutation then
			table.insert(rows, {
				Id = "Essence_" .. pair[1], Kind = "Essence", Mutation = pair[1],
				Title = (mutation.DisplayName or pair[1]) .. " Essence",
				Rarity = DropTables.MutationRarity(pair[1]),
				Chance = drops.Essence * pair[2] / math.max(1, total),
				Description = ("Apply to your podium crystal: it becomes %s (x%s income)."):format(
					mutation.DisplayName or pair[1], tostring(mutation.Multiplier or 1)),
			})
		end
	end

	local heart = Config.Geodes.Heart
	table.insert(rows, {
		Id = "Heart", Kind = "Heart", Title = heart.DisplayName, Rarity = "Mythic",
		Chance = drops.Heart,
		Description = ("Your next geode gives %d rewards at once!"):format(heart.Rewards),
	})

	-- v17: мусор (Config.Junk) роллится первым — остальные доли честно
	-- ужимаются на его шанс.
	local junkChance = (Config.Junk and Config.Junk.Enabled and Config.Junk.Chance and tonumber(Config.Junk.Chance.Geode)) or 0
	if junkChance > 0 then
		for _, row in rows do row.Chance *= (1 - junkChance) end
		table.insert(rows, {
			Id = "Junk", Kind = "Junk", Title = "Junk", Rarity = "Common", Chance = junkChance,
			Description = "Rock, cola can, dog bone, rubber duck… worth almost nothing.",
		})
	end

	local tableInfo = {
		Source = "Geode", Id = geodeType, Title = info.DisplayName, Color = info.Color,
		Rarity = info.Rarity, Rolls = 1, Rows = rows,
	}
	geodeCache[geodeType] = tableInfo
	return tableInfo
end

--------------------------------------------------------------------------------
-- СУНДУКИ
--------------------------------------------------------------------------------
-- Пул скинов сундука. isAvailable(skinId) — необязательный фильтр (сервер
-- передаёт проверку наличия ассета).
function DropTables.ChestSkinPool(rarity, isAvailable)
	local pool = {}
	for skinId, definition in Config.Skins.Definitions do
		if definition.Chests and definition.Chests[rarity]
			and Config.Skins.EnabledKinds[definition.Kind] == true
			and (not isAvailable or isAvailable(skinId)) then
			table.insert(pool, skinId)
		end
	end
	table.sort(pool)
	return pool
end

local chestCache = {}

function DropTables.Chest(rarity, isAvailable)
	if not isAvailable and chestCache[rarity] then return chestCache[rarity] end
	local info = Config.Chests.Types[rarity]
	if not info then return nil end
	local total = 0
	for _, row in info.Loot do total += row.Weight end
	local rows = {}
	for _, lootRow in info.Loot do
		local share = lootRow.Weight / math.max(1e-9, total)
		if lootRow.Kind == "Money" then
			table.insert(rows, {
				Id = "Money", Kind = "Money", Carts = lootRow.Carts, Title = "Cash", Rarity = "Uncommon",
				Chance = share, Description = ("%s–%s full carts of cash."):format(tostring(lootRow.Carts[1]), tostring(lootRow.Carts[2])),
			})
		elseif lootRow.Kind == "Skin" then
			local pool = DropTables.ChestSkinPool(rarity, isAvailable)
			local weights, sum = {}, 0
			for _, skinId in pool do
				local w = Config.Chests.SkinRarityWeights[Config.Skins.Definitions[skinId].Rarity] or 10
				weights[skinId] = w
				sum += w
			end
			for _, skinId in pool do
				local definition = Config.Skins.Definitions[skinId]
				table.insert(rows, {
					Id = "Skin_" .. skinId, Kind = "Skin", SkinId = skinId,
					Title = definition.DisplayName, Rarity = definition.Rarity,
					Chance = share * weights[skinId] / math.max(1e-9, sum),
					Description = "Pickaxe skin — only from chests.",
				})
			end
		elseif lootRow.Kind == "Charm" then
			local weights = Config.Charms.Weights[rarity] or {}
			local sum = 0
			for _, key in Config.Charms.Order do sum += weights[key] or 0 end
			for _, key in Config.Charms.Order do
				local charm = Config.Potions.Types[key]
				local w = weights[key] or 0
				if charm and w > 0 then
					local buff = Config.Buffs[charm.Buff] or {}
					table.insert(rows, {
						Id = key, Kind = "Charm", Charm = key, Title = charm.DisplayName,
						Rarity = charm.Rarity or "Rare", Chance = share * w / math.max(1e-9, sum),
						Description = buff.Description or "",
					})
				end
			end
		elseif lootRow.Kind == "PrestigePoint" then
			table.insert(rows, {
				Id = "PrestigePoint", Kind = "PrestigePoint", Title = "Prestige Point", Rarity = "Legendary",
				Chance = share, Description = "Spend it on permanent perks.",
			})
		end
	end
	local pity = Config.Chests.SkinPity
	local tableInfo = {
		Source = "Chest", Id = rarity, Title = info.DisplayName, Color = info.Color,
		Rarity = rarity == "Common" and "Common" or rarity, Rolls = info.Rolls, Rows = rows,
		PityEvery = (pity and pity.Rarities[rarity]) and pity.Every or nil,
	}
	if not isAvailable then chestCache[rarity] = tableInfo end
	return tableInfo
end

--------------------------------------------------------------------------------
-- РОЛЛ
--------------------------------------------------------------------------------
-- filter(row) -> bool — необязательно (например, только скины для гарантии).
function DropTables.Pick(rows, filter, rng)
	local total = 0
	for _, row in rows do
		if not filter or filter(row) then total += row.Chance end
	end
	if total <= 0 then return nil end
	local roll = (rng and rng:NextNumber() or math.random()) * total
	local last = nil
	for _, row in rows do
		if not filter or filter(row) then
			roll -= row.Chance
			last = row
			if roll <= 0 then return row end
		end
	end
	return last
end

-- «1 из N» / проценты для подписи.
function DropTables.ChanceText(chance)
	chance = tonumber(chance) or 0
	if chance <= 0 then return "—" end
	local percent = chance * 100
	if percent >= 10 then return ("%.1f%%"):format(percent) end
	if percent >= 1 then return ("%.2f%%"):format(percent) end
	return ("%.3f%%"):format(percent)
end

function DropTables.OneIn(chance)
	chance = tonumber(chance) or 0
	if chance <= 0 then return "" end
	return ("1 in %d"):format(math.max(1, math.floor(1 / chance + 0.5)))
end

return DropTables
