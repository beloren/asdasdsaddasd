--------------------------------------------------------------------------------
-- MutationRoll
-- ЕДИНСТВЕННОЕ место, где решается "какие мутации выпали". Раньше эта логика
-- была продублирована в CrystalService:rollMutations (руда из шахты) и
-- RockService:rollMutations (кристаллы с валунов), причём вторая копия даже не
-- считала множитель — просто возвращала список. Любая новая мутация или
-- правило неизбежно расходились бы между ними.
--
-- Здесь же живут три вещи, которых раньше не было вовсе:
--   • ВЗАИМОИСКЛЮЧАЮЩИЕ ГРУППЫ (Config.Mutations.ExclusiveGroups) — из одной
--     группы может выпасть максимум одна мутация. Нужно для размеров: руда не
--     может быть одновременно гигантской и крошечной, а без группы результат
--     зависел бы от того, какой визуал применился последним.
--   • УДАЧА от ребёртов и тира шахты (Config.Mutations.LuckBonus) — поднимает
--     шанс только у мутаций с флагом ScalesWithLuck, то есть у редких.
--   • ФАКТИЧЕСКИЙ шанс (EffectiveChance) — именно его надо показывать игроку
--     в чат-объявлении. Базовое число из конфига перестало быть правдой в тот
--     момент, когда шансы стали зависеть от прогресса, а раскрытие реальных
--     вероятностей — требование Roblox к Random Item Generator'ам.
--------------------------------------------------------------------------------

local Config = require(script.Parent.Config)

local MutationRoll = {}

-- Насколько подняты шансы редких мутаций у конкретного игрока. 0 = новичок
-- без ребёртов на первом тире шахты, ровно базовые шансы из конфига.
function MutationRoll.LuckFor(rebirths, mineTier)
	local cfg = Config.Mutations.LuckBonus
	if not cfg then return 0 end
	local luck = (tonumber(rebirths) or 0) * (cfg.PerRebirth or 0)
		+ math.max(0, (tonumber(mineTier) or 1) - 1) * (cfg.PerMineTier or 0)
	return math.clamp(luck, 0, cfg.MaxTotal or math.huge)
end

-- Фактический шанс мутации для игрока с такой удачей. Прибавка
-- ОТНОСИТЕЛЬНАЯ: luck = 0.5 означает "шанс в полтора раза выше базового", а
-- не "+50 процентных пунктов" — иначе Celestial с его 0.3% скакнул бы до
-- 50.3% и стал бы обычным делом.
--
-- weatherMultiplier — ДОПОЛНИТЕЛЬНЫЙ множитель от текущего погодного ивента
-- (см. Config.WeatherEvents/WeatherService.lua), если эта мутация сейчас
-- усилена (например, Celestial во время "Nightfall"). Необязательный
-- параметр — старые вызовы без него работают как прежде.
-- v20.66: ДВУХЭТАПНЫЙ БРОСОК (см. Config.Mutations.Roll).
local function rollCfg()
	return Config.Mutations.Roll or { BaseChance = 0.06, ExtraChance = 0.08, MaxMutations = 3, MaxChance = 0.5 }
end

-- Вес мутации в выборе «какая». Удача от прогресса (только ScalesWithLuck)
-- и погода делают редкую мутацию ВЕРОЯТНЕЕ среди выпавших.
local function weightOf(info, luck, weatherMultiplier)
	local weight = tonumber(info.Weight) or tonumber(info.Chance) or 0
	if info.ScalesWithLuck then weight *= 1 + (tonumber(luck) or 0) end
	weatherMultiplier = tonumber(weatherMultiplier)
	if weatherMultiplier and weatherMultiplier > 1 then weight *= weatherMultiplier end
	return weight
end

-- Шанс, что руда вообще мутирует. potionMultiplier - зелье/перк/пасс.
function MutationRoll.AnyChance(potionMultiplier)
	local cfg = rollCfg()
	return math.clamp(cfg.BaseChance * (tonumber(potionMultiplier) or 1), 0, cfg.MaxChance or 0.5)
end

-- Фактический шанс получить ИМЕННО эту мутацию на куске руды: шанс мутации
-- вообще × её доля среди весов. Это число и показывается игроку (1/N).
function MutationRoll.EffectiveChance(mutationId, luck, weatherMultiplier, potionMultiplier)
	local info = Config.Mutations[mutationId]
	if not info then return 0 end
	local total = 0
	for _, id in Config.Mutations.Order do
		local other = Config.Mutations[id]
		if other then total += weightOf(other, luck, id == mutationId and weatherMultiplier or nil) end
	end
	if total <= 0 then return 0 end
	return MutationRoll.AnyChance(potionMultiplier) * weightOf(info, luck, weatherMultiplier) / total
end

-- Выбор одной мутации по весам среди ещё не взятых (и не занятых групп).
local function pickOne(luck, weatherBoosts, taken, groupTaken)
	local groups = Config.Mutations.ExclusiveGroups or {}
	local pool, total = {}, 0
	for _, mutationId in Config.Mutations.Order do
		local info = Config.Mutations[mutationId]
		local group = groups[mutationId]
		if info and not taken[mutationId] and not (group and groupTaken[group]) and not info.EventOnly then
			local weight = weightOf(info, luck, weatherBoosts and weatherBoosts[mutationId])
			if weight > 0 then
				table.insert(pool, { Id = mutationId, Weight = weight })
				total += weight
			end
		end
	end
	if total <= 0 then return nil end
	local roll = math.random() * total
	for _, entry in pool do
		roll -= entry.Weight
		if roll <= 0 then return entry.Id end
	end
	return pool[#pool].Id
end

-- Возвращает: список ID (в порядке Config.Mutations.Order, от частых к
-- редким) и произведение их Multiplier. weatherBoosts - { [id] = множитель }
-- погоды/тотемов; potionMultiplier - множитель шанса мутации вообще.
function MutationRoll.Roll(luck, weatherBoosts, potionMultiplier)
	luck = tonumber(luck) or 0
	local cfg = rollCfg()
	local hits, multiplier = {}, 1
	if math.random() >= MutationRoll.AnyChance(potionMultiplier) then
		return hits, multiplier
	end
	local taken, groupTaken = {}, {}
	local groups = Config.Mutations.ExclusiveGroups or {}
	local function add(mutationId)
		taken[mutationId] = true
		local group = groups[mutationId]
		if group then groupTaken[group] = true end
	end
	local first = pickOne(luck, weatherBoosts, taken, groupTaken)
	if not first then return hits, multiplier end
	add(first)
	local count = 1
	while count < (cfg.MaxMutations or 3) and math.random() < (cfg.ExtraChance or 0) do
		local extra = pickOne(luck, weatherBoosts, taken, groupTaken)
		if not extra then break end
		add(extra)
		count += 1
	end
	for _, mutationId in Config.Mutations.Order do
		if taken[mutationId] then
			table.insert(hits, mutationId)
			multiplier *= Config.Mutations[mutationId].Multiplier
		end
	end
	return hits, multiplier
end

-- Дополняет уже брошенный набор ГАРАНТИРОВАННОЙ мутацией — используется
-- только самым редким погодным ивентом (Solar Eclipse, см.
-- Config.WeatherEvents.SolarEclipse.ForcedMutationChance): часть добытой
-- руды НАПРЯМУЮ получает Eclipsed, минуя обычный вероятностный бросок,
-- чтобы редчайший ивент ощущался кардинально иначе, а не просто как
-- "повышенный шанс попробовать угадать". Ничего не делает, если мутация
-- уже есть в списке (не задваиваем) или взаимоисключающая группа уже занята.
function MutationRoll.ForceInclude(hits, multiplier, mutationId)
	local info = Config.Mutations[mutationId]
	if not info then return hits, multiplier end
	for _, existing in hits do
		if existing == mutationId then return hits, multiplier end
	end
	local group = (Config.Mutations.ExclusiveGroups or {})[mutationId]
	if group then
		for _, existing in hits do
			if (Config.Mutations.ExclusiveGroups or {})[existing] == group then
				return hits, multiplier -- группа уже занята другой мутацией из этого броска
			end
		end
	end
	table.insert(hits, mutationId)
	return hits, multiplier * info.Multiplier
end

-- Произведение множителей уже известного набора мутаций (например,
-- восстановленного из атрибута "Mutations" при подборе упавшего кристалла).
function MutationRoll.MultiplierFor(mutationIds)
	local multiplier = 1
	for _, mutationId in mutationIds do
		local info = Config.Mutations[mutationId]
		if info then multiplier *= info.Multiplier end
	end
	return multiplier
end

-- Разбор строки-атрибута "Frozen,Molten" в список ID.
function MutationRoll.Parse(raw)
	local list = {}
	if typeof(raw) ~= "string" or raw == "" then return list end
	for mutationId in string.gmatch(raw, "[^,]+") do
		if Config.Mutations[mutationId] then table.insert(list, mutationId) end
	end
	return list
end

-- Совокупный шанс выпадения ИМЕННО такого набора — для честной строки
-- "(0.10% combined chance)" в объявлении. Считается по фактическим шансам
-- конкретного игрока, а не по базовым. weatherBoosts — см. Roll выше.
function MutationRoll.CombinedChance(mutationIds, luck, weatherBoosts)
	local chance = 1
	for _, mutationId in mutationIds do
		local weatherMultiplier = weatherBoosts and weatherBoosts[mutationId]
		chance *= MutationRoll.EffectiveChance(mutationId, luck, weatherMultiplier)
	end
	return chance
end

return MutationRoll
