--------------------------------------------------------------------------------
-- MineVeinMath — ОБЩАЯ математика мини-игры "рудная жила" для сервера и
-- клиента. Позиция кирки на жиле считается по одной и той же формуле в
-- обоих местах, поэтому по сети её не гоняют каждый кадр: сервер шлёт
-- только параметры раунда, клиент рисует, сервер проверяет попадание той
-- же функцией.
--
-- v14.3 — режимы:
--   flips  — моменты (сек от начала раунда), когда кирка РАЗВОРАЧИВАЕТСЯ
--            (режим «Разворот»);
--   dual   — вторая кирка идёт зеркально навстречу первой (1 - позиция);
--            засчитывается ЛУЧШАЯ из двух (режим «Две кирки»);
--   shrink — { Seconds, MinFrac }: зоны сужаются к центру со временем
--            (режим «Сжимающаяся жила»).
--------------------------------------------------------------------------------

local MineVeinMath = {}

-- Пинг-понг 0 → 1 → 0 за 2·sweepSeconds. Функция чётная и периодическая,
-- поэтому «время назад» (см. VirtualTime) даёт ровное движение обратно.
local function pingpong(elapsed, sweepSeconds)
	if sweepSeconds <= 0 then return 0 end
	local t = (elapsed / sweepSeconds) % 2
	if t <= 1 then return t end
	return 2 - t
end

-- «Виртуальное» время с учётом разворотов: после каждого flip время идёт
-- в обратную сторону — кирка плавно едет назад без скачка.
function MineVeinMath.VirtualTime(elapsed, flips)
	if type(flips) ~= "table" or #flips == 0 then return elapsed end
	local virtual, direction, last = 0, 1, 0
	for _, flipAt in flips do
		if flipAt >= elapsed then break end
		virtual += direction * (flipAt - last)
		direction = -direction
		last = flipAt
	end
	return virtual + direction * (elapsed - last)
end

-- motion:
--   "Linear" — равномерно (обычный режим);
--   "Eased"  — медленно у краёв, быстро в середине ("Unstable Rock").
function MineVeinMath.NeedlePosition(elapsed, sweepSeconds, motion, flips)
	local u = pingpong(MineVeinMath.VirtualTime(math.max(0, elapsed), flips), sweepSeconds)
	if motion == "Eased" then
		return (1 - math.cos(math.pi * u)) / 2
	end
	return u
end

-- Позиция второй кирки (режим «Две кирки»): зеркально, навстречу.
function MineVeinMath.MirrorPosition(position)
	return 1 - position
end

-- Зоны в момент elapsed: для режима «Сжимающаяся жила» каждая зона
-- сужается к своему центру. Без shrink возвращает исходный список.
function MineVeinMath.ZonesAt(zones, elapsed, shrink)
	if type(shrink) ~= "table" or not zones then return zones end
	local seconds = math.max(0.1, tonumber(shrink.Seconds) or 3)
	local minFrac = math.clamp(tonumber(shrink.MinFrac) or 0.35, 0.05, 1)
	local factor = math.max(minFrac, 1 - (math.max(0, elapsed) / seconds) * (1 - minFrac))
	local result = table.create(#zones)
	for index, zone in zones do
		local center = (zone.Start + zone.Finish) / 2
		local half = (zone.Finish - zone.Start) / 2 * factor
		result[index] = { Kind = zone.Kind, Color = zone.Color, Start = center - half, Finish = center + half }
	end
	return result
end

-- Какая зона под позицией. Perfect проверяется ПЕРВЫМ — он лежит внутри
-- Good. Ничего не нашли — промах (nil).
function MineVeinMath.ZoneAt(zones, position, tolerance)
	tolerance = tolerance or 0
	local best = nil
	for _, zone in zones do
		if position >= zone.Start - tolerance and position <= zone.Finish + tolerance then
			if zone.Kind == "Perfect" then
				return zone
			end
			best = best or zone
		end
	end
	return best
end

local RANK = { Perfect = 3, Good = 2 }
function MineVeinMath.Rank(zone)
	return zone and RANK[zone.Kind] or 0
end

return MineVeinMath
