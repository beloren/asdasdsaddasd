--------------------------------------------------------------------------------
-- GoblinStats
-- ЕДИНСТВЕННОЕ место, где считаются фактические HP и урон гоблина.
--
-- Зачем модуль: раньше формулы жили в двух местах и разошлись.
--   • GoblinService:createR6Placeholder умножал HP на 2, а урон — на 1.25
--     (кроме Golden) и ещё на Config.Goblins.DamageMultiplier (1.5).
--   • CollectionMenu.client.lua (энциклопедия) считал голое
--     Health + tier*HealthPerTier и Damage + tier*DamagePerTier.
-- В итоге книга показывала РОВНО ПОЛОВИНУ настоящего HP и ~53% настоящего
-- урона. Теперь оба зовут отсюда, и разойтись физически не могут.
--------------------------------------------------------------------------------

local Config = require(script.Parent.Config)

local GoblinStats = {}

-- Множитель HP, применяемый ко ВСЕМ гоблинам при спавне.
GoblinStats.HealthMultiplier = 2

-- Урон обычных типов дополнительно домножается на это; Golden — нет
-- (у него собственный, уже повышенный Damage/DamagePerTier в конфиге).
GoblinStats.NormalDamageBonus = 1.25

-- Золотой страж валуна получает ещё один x2 к HP поверх общего
-- (см. GoblinService:SpawnEliteForBoulder).
GoblinStats.EliteHealthMultiplier = 2

function GoblinStats.Health(mobId, tier, elite)
	local definition = Config.Goblins.Types[mobId]
	if not definition then return 0 end
	local health = (definition.Health + tier * definition.HealthPerTier) * GoblinStats.HealthMultiplier
	if elite then health *= GoblinStats.EliteHealthMultiplier end
	return health
end

function GoblinStats.Damage(mobId, tier)
	local definition = Config.Goblins.Types[mobId]
	if not definition then return 0 end
	local base = definition.Damage + tier * definition.DamagePerTier
	local typeBonus = mobId == "Golden" and 1 or GoblinStats.NormalDamageBonus
	return base * typeBonus * (Config.Goblins.DamageMultiplier or 1)
end

-- Фактическое замедление шахты этим типом на этом тире — та же формула,
-- что в GoblinService:_applyTypeSlowdown. Книга раньше печатала голый
-- definition.Slowdown, то есть значение, верное только на MinMineTier.
function GoblinStats.Slowdown(mobId, tier)
	local definition = Config.Goblins.Types[mobId]
	if not definition then return 0 end
	-- Objective = "Guard" (золотой страж) вообще не вызывает
	-- _applyTypeSlowdown — он не трогает шахту, только дерётся.
	if definition.Objective == "Guard" then return 0 end
	return math.clamp(
		definition.Slowdown + (tier - definition.MinMineTier) * 0.015,
		Config.Goblins.SlowdownMin,
		Config.Goblins.SlowdownMax
	)
end

-- Что реально отбирает этот тип — для строки TARGET в энциклопедии.
-- Раньше выражение схлопывало "Guard" в ветку "ORE IN YOUR CART", хотя
-- страж не ворует ничего.
function GoblinStats.TargetText(mobId)
	local definition = Config.Goblins.Types[mobId]
	if not definition then return "" end
	if definition.Objective == "Guard" then return "NOTHING - IT GUARDS THE BOULDER" end
	if definition.Objective == "Mine" then return "YOUR MINE" end
	return definition.CanStealCart and "YOUR ENTIRE CART" or "ORE IN YOUR CART"
end

return GoblinStats
