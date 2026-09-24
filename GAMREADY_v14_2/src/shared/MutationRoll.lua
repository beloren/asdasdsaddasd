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
function MutationRoll.EffectiveChance(mutationId, luck, weatherMultiplier)
	local info = Config.Mutations[mutationId]
	if not info then return 0 end
	local base = info.ScalesWithLuck and math.min(1, info.Chance * (1 + (tonumber(luck) or 0))) or info.Chance
	weatherMultiplier = tonumber(weatherMultiplier)
	if weatherMultiplier and weatherMultiplier > 1 then
		return math.min(1, base * weatherMultiplier)
	end
	return base
end

-- Возвращает: список ID (в порядке Config.Mutations.Order, то есть от частых
-- к редким) и произведение их Multiplier.
--
-- weatherBoosts — необязательная { [mutationId] = множитель } от активного
-- погодного ивента (см. Config.WeatherEvents) — усиленные мутации бросаются
-- с повышенным EffectiveChance на время ивента, механика ровно та же,
-- просто с более высоким шансом.
-- potionMultiplier — общий множитель шанса ВСЕХ мутаций (бафф "зелье
-- мутаций", см. Config.Buffs.MutationPotion). Он умножает шанс, а не
-- гарантирует мутацию: гарантия сделала бы мутации обыденностью и убила
-- бы их ценность. Погодный множитель действует отдельно и складывается с
-- ним умножением — оба это "во сколько раз чаще".
function MutationRoll.Roll(luck, weatherBoosts, potionMultiplier)
	luck = tonumber(luck) or 0
	potionMultiplier = tonumber(potionMultiplier) or 1
	local hits, multiplier = {}, 1
	local groupTaken = {}
	local groups = Config.Mutations.ExclusiveGroups or {}

	for _, mutationId in Config.Mutations.Order do
		local info = Config.Mutations[mutationId]
		if info then
			local group = groups[mutationId]
			-- Из взаимоисключающей группы берём первую же выпавшую и дальше
			-- эту группу не рассматриваем. Order идёт от частых к редким,
			-- поэтому "первая выпавшая" — это честный независимый бросок, а
			-- не скрытое предпочтение редкой.
			if not (group and groupTaken[group]) then
				local weatherMultiplier = weatherBoosts and weatherBoosts[mutationId]
				local chance = MutationRoll.EffectiveChance(mutationId, luck, weatherMultiplier) * potionMultiplier
				-- Потолок: даже с зельем мутация не должна стать
				-- гарантированной — иначе исчезает сам смысл броска.
				if math.random() < math.min(chance, 0.95) then
					table.insert(hits, mutationId)
					multiplier *= info.Multiplier
					if group then groupTaken[group] = true end
				end
			end
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
