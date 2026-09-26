--------------------------------------------------------------------------------
-- PlaceableCatalog — единый разбор ID предметов базы (тотемы и декор).
--
-- ФОРМАТ ID (строка, так и лежит в data.BaseItems / data.PlacedDecor):
--   Totem_<Type>_T<tier>              — Totem_Fortune_T1 … _T3 (v20.43: 3 тира)
--   Totem_Prism_T<tier>               — Prism на все мутации сразу
--   (старый формат Totem_Prism_<Mutation>_T<n> и тиры 4..10 — см. MigrateLegacyId)
--   Decor_<Id>                        — Decor_PlushMole
-- Реликвии здесь не участвуют: у каждой свой серийник, они хранятся
-- отдельными записями (data.Relics) и описаны в Config.Relics.
--
-- Один модуль и на сервере, и на клиенте — названия, иконки, цвета и сила
-- эффекта не могут разойтись между лавкой, инвентарём и расчётом баффа.
--------------------------------------------------------------------------------
local Config = require(script.Parent.Config)

local PlaceableCatalog = {}

local CFG = Config.Placeables
local cache = {}

local function tierRarity(tier)
	return CFG.TierRarity[math.clamp(tier, 1, #CFG.TierRarity)] or "Common"
end

local function roman(n)
	local numerals = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }
	return numerals[n] or tostring(n)
end

local function maxTier()
	return #(CFG.TierPrices or { 1 })
end

-- v20.43: название тира (Early / Mid / Late).
function PlaceableCatalog.TierName(tier)
	return (CFG.TierNames and CFG.TierNames[tier]) or roman(tier)
end

local function totemValue(def, tier)
	if def.Values then return def.Values[math.clamp(tier, 1, #def.Values)] or 0 end
	return (def.PerTier or 0) * tier
end

-- v20.43: старый ID (10 тиров, Prism на мутацию) → новый (3 тира).
-- Возвращает новый ID или nil, если ID не тотем старого формата.
local LEGACY_TIER = { 1, 1, 1, 2, 2, 2, 2, 3, 3, 3 }
function PlaceableCatalog.MigrateLegacyId(itemId)
	if typeof(itemId) ~= "string" or itemId:match("^Totem_Shrine_") then return nil end
	local _, prismTier = itemId:match("^Totem_Prism_([%a]+)_T(%d+)$")
	if prismTier then
		return ("Totem_Prism_T%d"):format(LEGACY_TIER[math.clamp(tonumber(prismTier), 1, 10)])
	end
	local totemType, tier = itemId:match("^Totem_([%a]+)_T(%d+)$")
	if totemType and CFG.TotemTypes[totemType] then
		return ("Totem_%s_T%d"):format(totemType, LEGACY_TIER[math.clamp(tonumber(tier), 1, 10)])
	end
	return nil
end
PlaceableCatalog.Roman = roman

function PlaceableCatalog.TotemId(totemType, tier, mutation)
	return ("Totem_%s_T%d"):format(totemType, tier)
end

-- v4: фиксированная цена тотема: TierPrices[тир] × PriceMult типа,
-- округлённая до двух значащих цифр.
function PlaceableCatalog.TotemPrice(totemType, tier)
	local def = CFG.TotemTypes[totemType]
	local base = CFG.TierPrices and CFG.TierPrices[math.clamp(tier, 1, #CFG.TierPrices)] or 0
	local value = base * (def and def.PriceMult or 1)
	if value < 100 then return math.floor(value + 0.5) end
	local step = 10 ^ (math.floor(math.log10(value)) - 1)
	return math.floor(value / step + 0.5) * step
end

-- v4: «свой» тир тотемов для пещеры (последний тир, чья TierHomeCave ≤ пещеры).
function PlaceableCatalog.TotemTierForCave(cave)
	cave = math.floor(tonumber(cave) or 1)
	local best = 1
	for tier, home in CFG.TierHomeCave or {} do
		if cave >= home and tier > best then best = tier end
	end
	return best
end

function PlaceableCatalog.DecorId(decorId)
	return "Decor_" .. decorId
end

-- Возвращает описание предмета или nil для битого/неизвестного ID.
-- { Id, Kind = "Totem"|"Decor", Type, Tier, Mutation, DisplayName, ShortName,
--   Icon, Color, Rarity, Effect, Value, Asset, Price }  (v4: Price — фиксированная цена в $)
function PlaceableCatalog.Info(itemId)
	if typeof(itemId) ~= "string" then return nil end
	local cached = cache[itemId]
	if cached ~= nil then return cached or nil end

	local info = nil
	local shrineId = itemId:match("^Totem_Shrine_([%a]+)$")
	local totemType, totemTier = itemId:match("^Totem_([%a]+)_T(%d+)$")
	local decorId = itemId:match("^Decor_([%w]+)$")

	local shrines = Config.Prestige and Config.Prestige.Shrines
	if shrineId then
		-- v4: святилище за очки престижа (Config.Prestige.Shrines).
		local def = shrines and shrines.Types[shrineId]
		if def then
			local mutation = def.Mutation and Config.Mutations[def.Mutation]
			local color = def.Color or (mutation and mutation.Color) or Color3.fromRGB(255, 215, 90)
			info = {
				Id = itemId, Kind = "Totem", Type = "Shrine", ShrineId = shrineId, Tier = 10,
				Mutation = def.Mutation, Every = def.Every,
				DisplayName = def.DisplayName, ShortName = def.DisplayName,
				Icon = def.Icon, Color = color, TierColor = color, Rarity = "Mythic",
				Effect = def.Kind == "Mutation" and "Shrine" or def.Kind, Value = def.Value or 0,
				Asset = def.Asset, Price = 0, PointsCost = def.Cost,
			}
		end
	elseif totemType then
		local tier = tonumber(totemTier)
		local def = CFG.TotemTypes[totemType]
		if def and tier and tier >= 1 and tier <= maxTier() then
			local tierName = PlaceableCatalog.TierName(tier)
			info = {
				Id = itemId, Kind = "Totem", Type = totemType, Tier = tier,
				-- Prism без Mutation = на все мутации из PrismMutations.
				Mutations = totemType == "Prism" and CFG.PrismMutations or nil,
				DisplayName = ("%s (%s)"):format(def.DisplayName, tierName),
				ShortName = ("%s %s"):format(totemType, tierName),
				Icon = def.Icon, Color = def.Color, TierColor = CFG.TierColors[tier],
				Rarity = tierRarity(tier), Effect = def.Effect, Value = totemValue(def, tier),
				Asset = def.Asset, Price = PlaceableCatalog.TotemPrice(totemType, tier),
			}
		end
	elseif decorId then
		local def = CFG.Decor[decorId]
		if def then
			info = {
				Id = itemId, Kind = "Decor", Type = decorId,
				DisplayName = def.DisplayName, ShortName = def.DisplayName,
				Icon = def.Icon, Color = Config.RarityColors[def.Rarity] or Color3.new(1, 1, 1),
				Rarity = def.Rarity, Asset = def.Asset, Price = def.Price or 0,
			}
		end
	end
	cache[itemId] = info or false
	return info
end

-- Человекочитаемое описание эффекта («+6% Luck», «Celestial chance x1.45»).
function PlaceableCatalog.EffectText(info)
	if not info or info.Kind ~= "Totem" then return "Decoration" end
	local percent = math.floor(info.Value * 100 + 0.5)
	if info.Effect == "Shrine" then
		local mutation = Config.Mutations[info.Mutation]
		return ("1 of every %d ore: guaranteed %s"):format(info.Every or 3, mutation and mutation.DisplayName or tostring(info.Mutation))
	end
	if info.Type == "Shrine" and info.Effect == "Luck" then
		return ("+%d%% Luck (permanent)"):format(percent)
	elseif info.Type == "Shrine" and info.Effect == "Income" then
		return ("+%d%% Sell Income (permanent)"):format(percent)
	end
	if info.Effect == "Luck" then
		return ("+%d%% Luck"):format(percent)
	elseif info.Effect == "Income" then
		return ("+%d%% Sell Income"):format(percent)
	elseif info.Effect == "BoulderRespawn" then
		return ("Base boulders respawn %d%% faster"):format(percent)
	elseif info.Effect == "Mutation" and not info.Mutation then
		return ("All mutations x%.1f"):format(1 + info.Value)
	elseif info.Effect == "Mutation" then
		local mutation = Config.Mutations[info.Mutation]
		return ("%s chance x%.2f"):format(mutation and mutation.DisplayName or tostring(info.Mutation), 1 + info.Value)
	end
	return ""
end

-- Цвет редкости с учётом «Secret» у реликвий.
function PlaceableCatalog.RarityColor(rarity)
	return Config.RarityColors[rarity]
		or (Config.Relics.RarityColors and Config.Relics.RarityColors[rarity])
		or Color3.new(1, 1, 1)
end

-- v4: ID святилища.
function PlaceableCatalog.ShrineId(shrineId)
	return "Totem_Shrine_" .. tostring(shrineId)
end

-- Все возможные тотемы (для лавки): список типов.
function PlaceableCatalog.AllTotemKinds()
	local kinds = {}
	for _, totemType in CFG.TotemOrder do
		table.insert(kinds, { Type = totemType })
	end
	return kinds
end

return PlaceableCatalog
