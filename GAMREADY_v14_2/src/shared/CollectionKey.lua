--------------------------------------------------------------------------------
-- CollectionKey
-- Ключ ячейки коллекции. Раньше это был просто oreId ("Quartz"), и любые две
-- добытые руды одного вида складывались в одну ячейку независимо от мутаций:
-- обычный Quartz и Rusty Quartz были неотличимы, а мутация влияла только на
-- множитель дохода этой общей ячейки.
--
-- Теперь мутировавшая руда — ОТДЕЛЬНАЯ ячейка со своей иконкой, своим уровнем
-- и своим доходом:
--     "Quartz"              — обычный
--     "Quartz#Rusty"        — ржавый
--     "Quartz#Rusty,Frozen" — ржавый и замороженный одновременно
--
-- ФОРМАТ СОВМЕСТИМ СО СТАРЫМИ СОХРАНЕНИЯМИ: ключ без символа "#" — это ровно
-- то, что лежало в профилях раньше, и читается как немутировавшая руда. Ничего
-- мигрировать не нужно.
--
-- ПОРЯДОК МУТАЦИЙ В КЛЮЧЕ КАНОНИЧЕН — всегда по Config.Mutations.Order. Иначе
-- "Frozen,Rusty" и "Rusty,Frozen" стали бы двумя разными ячейками для одной и
-- той же руды, и игрок видел бы дубликаты.
--------------------------------------------------------------------------------

local Config = require(script.Parent.Config)

local CollectionKey = {}

local SEPARATOR = "#"

-- Позиция мутации в Config.Mutations.Order — по ней сортируем.
local orderIndex = {}
for index, mutationId in Config.Mutations.Order do
	orderIndex[mutationId] = index
end

-- Приводит произвольный список/строку мутаций к каноническому виду:
-- отбрасывает неизвестные, убирает дубликаты, сортирует по Order.
function CollectionKey.Canonical(mutations)
	local list = {}
	local seen = {}

	local function push(mutationId)
		if Config.Mutations[mutationId] and not seen[mutationId] then
			seen[mutationId] = true
			table.insert(list, mutationId)
		end
	end

	if typeof(mutations) == "string" then
		for mutationId in string.gmatch(mutations, "[^,]+") do push(mutationId) end
	elseif typeof(mutations) == "table" then
		for _, mutationId in mutations do push(mutationId) end
	end

	table.sort(list, function(a, b)
		return (orderIndex[a] or math.huge) < (orderIndex[b] or math.huge)
	end)
	return list
end

-- oreId + мутации -> ключ ячейки.
function CollectionKey.Make(oreId, mutations)
	local list = CollectionKey.Canonical(mutations)
	if #list == 0 then
		return oreId -- ровно старый формат
	end
	return oreId .. SEPARATOR .. table.concat(list, ",")
end

-- Ключ -> oreId, список мутаций.
function CollectionKey.Parse(key)
	if typeof(key) ~= "string" or key == "" then return nil, {} end
	local separatorAt = string.find(key, SEPARATOR, 1, true)
	if not separatorAt then
		return key, {}
	end
	local oreId = string.sub(key, 1, separatorAt - 1)
	local rest = string.sub(key, separatorAt + 1)
	return oreId, CollectionKey.Canonical(rest)
end

-- Только базовая руда — для обращений к Config.Geodes.Ores и к
-- PlaceholderFactory.CollectionOre, которые про мутации ничего не знают.
function CollectionKey.BaseOre(key)
	local oreId = CollectionKey.Parse(key)
	return oreId
end

-- Множитель мутаций, зашитый в ключ. Считается ИЗ КЛЮЧА, а не хранится
-- отдельным полем: одно поле рано или поздно рассинхронизировалось бы с
-- ключом, а так источник истины ровно один.
function CollectionKey.Multiplier(key)
	local _, mutations = CollectionKey.Parse(key)
	local multiplier = 1
	for _, mutationId in mutations do
		local info = Config.Mutations[mutationId]
		if info then multiplier *= info.Multiplier end
	end
	return multiplier
end

-- Отображаемое имя ячейки: "RUSTY QUARTZ", "RUSTY FROZEN QUARTZ".
function CollectionKey.DisplayName(key)
	local oreId, mutations = CollectionKey.Parse(key)
	local ore = Config.Geodes.Ores[oreId]
	local base = ore and ore.DisplayName or tostring(oreId)
	if #mutations == 0 then return base end
	local names = {}
	for _, mutationId in mutations do
		table.insert(names, Config.Mutations[mutationId].DisplayName)
	end
	return table.concat(names, " ") .. " " .. base
end

return CollectionKey
