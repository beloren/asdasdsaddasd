--------------------------------------------------------------------------------
-- BigNum
-- Число вида sign * mantissa * 10^exponent (mantissa всегда в [1,10), кроме
-- значения "0", у которого mantissa = 0, exponent = 0). Такое представление
-- не ограничено сверху точностью double (в отличие от Config.Economy.
-- MaxCurrency = 9e15, который стоит ровно на границе 2^53 — предела ТОЧНОГО
-- целого в double) — деньги могут расти сколь угодно долго, не переставая
-- расти на реально ощутимые игроком приращения.
--
--------------------------------------------------------------------------------
-- !!! ГЛАВНОЕ, ЧТО НУЖНО ЗНАТЬ ПЕРЕД ИСПОЛЬЗОВАНИЕМ !!!
--------------------------------------------------------------------------------
-- В СТАРОЙ версии этого файла в шапке было написано, что "любое выражение
-- вида `money < cost` продолжает работать, даже если один операнд — обычное
-- число". ЭТО БЫЛО НЕВЕРНО и являлось источником почти всех падений,
-- связанных с деньгами. Проверено запуском на настоящем Luau:
--
--   bignum <  number   → ОШИБКА "attempt to compare table < number"
--   number <  bignum   → ОШИБКА "attempt to compare number < table"
--   bignum <= number   → ОШИБКА
--   bignum >= number   → ОШИБКА
--   bignum == number   → МОЛЧА возвращает false (ещё хуже ошибки)
--   "текст" .. bignum  → ОШИБКА "attempt to concatenate string with table"
--
-- Причина: Luau (как и Lua 5.1) для операторов сравнения СНАЧАЛА требует,
-- чтобы ОБА операнда были одного типа, и только потом смотрит на
-- метаметод __lt/__le. Арифметика (__add/__sub/__mul/__div) — наоборот,
-- смешанные типы принимает нормально, поэтому `money + 500` работает.
--
-- ПРАВИЛО, КОТОРОЕ РЕШАЕТ ПРОБЛЕМУ РАЗ И НАВСЕГДА:
--   • Сравниваешь деньги — используй ЯВНЫЕ функции ниже:
--       BigNum.lt(a, b)   -- a <  b
--       BigNum.le(a, b)   -- a <= b
--       BigNum.gt(a, b)   -- a >  b
--       BigNum.ge(a, b)   -- a >= b
--       BigNum.eq(a, b)   -- a == b
--       BigNum.compare(a, b) -- -1 / 0 / 1
--     Они сами приводят ЛЮБУЮ смесь (BigNum / число / строка) к BigNum,
--     поэтому порядок и типы операндов не важны вообще.
--   • Нужно передать деньги во встроенную функцию, которая физически
--     требует number (math.floor/math.max/math.clamp, DataStore,
--     IntValue.Value) — вызывай :toNumber() с явным клэмпом.
--   • Печатаешь деньги в текст — NumberFormat.abbreviate/withSeparators
--     (они понимают и BigNum, и обычное число). Конкатенация `..` теперь
--     тоже работает (см. __concat ниже), но в format("%s") BigNum по-
--     прежнему передавать НЕЛЬЗЯ — только tostring(x) или NumberFormat.
--------------------------------------------------------------------------------

local BigNum = {}
BigNum.__index = BigNum

-- Практический потолок — НЕ технический лимит (BigNum спокойно считает и
-- дальше), а защита от кривых/абузных входных данных (NaN, дурной ProductId
-- с ценой 1e400 и т.п.). 1e300 недостижим ни при каком реалистичном темпе
-- прогрессии, так что для игрока это неотличимо от "без лимита".
local SAFETY_EXPONENT = 300

local function isBigNum(value)
	return type(value) == "table" and getmetatable(value) == BigNum
end
BigNum.is = isBigNum

-- Приводит (sign, mantissa>=0, exponent) к канонической форме: mantissa в
-- [1,10) либо (0,0) для нуля. Также глушит NaN/inf, которые иначе тихо
-- проросли бы через всю дальнейшую арифметику.
--
-- Нормализация идёт через log10 одним шагом, а не циклом деления на 10:
-- у старой версии на входе вроде 1e300 крутилось 300 итераций подряд, и
-- это при том, что normalize вызывается на КАЖДОЕ сложение денег.
local function normalize(sign, m, e)
	if m ~= m then -- NaN где-то выше по цепочке
		return 0, 0, 0
	end
	if m == math.huge then
		-- Переполнение double при умножении мантисс — отдаём безопасный
		-- потолок, но СО ЗНАКОМ (старая версия здесь теряла знак и
		-- превращала минус-бесконечность в +1e300).
		return (sign < 0 and -1 or 1), 1, SAFETY_EXPONENT
	end
	if m <= 0 then
		return 0, 0, 0
	end
	if sign == 0 then
		return 0, 0, 0
	end
	if m < 1 or m >= 10 then
		local shift = math.floor(math.log10(m))
		if shift ~= 0 and shift == shift and math.abs(shift) ~= math.huge then
			m /= 10 ^ shift
			e += shift
		end
		-- log10 на границах (0.9999999, 9.9999999) может промахнуться на
		-- единицу из-за округления double — добираем вручную, но это уже
		-- максимум одна-две итерации, а не триста.
		while m >= 10 do
			m /= 10
			e += 1
		end
		while m < 1 do
			m *= 10
			e -= 1
		end
	end
	if e > SAFETY_EXPONENT then
		return (sign < 0 and -1 or 1), 1, SAFETY_EXPONENT
	end
	if e < -SAFETY_EXPONENT then
		return 0, 0, 0 -- меньше 1e-300 — для денег это ноль
	end
	return (sign < 0 and -1 or 1), m, e
end

local function newRaw(s, m, e)
	return setmetatable({ s = s, m = m, e = e }, BigNum)
end

-- Из обычного Lua-числа ИЛИ уже готового BigNum (в этом случае возвращается
-- как есть — экземпляры BigNum никогда не мутируются на месте, так что
-- шарить ссылку безопасно). Понимает и сериализованную форму {s=,m=,e=},
-- чтобы случайно переданные "сырые" данные из профиля не превращались в 0.
function BigNum.new(value)
	if isBigNum(value) then
		return value
	end
	if type(value) == "table" then
		-- Плоская таблица из профиля/DataStore — тот же формат, что отдаёт
		-- toData(). Раньше сюда попадал tonumber(table) = nil → деньги
		-- молча становились нулём.
		return BigNum.fromData(value)
	end
	value = tonumber(value) or 0
	if value ~= value or value == math.huge or value == -math.huge then
		value = 0
	end
	local sign = value < 0 and -1 or (value > 0 and 1 or 0)
	local s, m, e = normalize(sign, math.abs(value), 0)
	return newRaw(s, m, e)
end

-- Сериализация для сохранения в ProfileService/DataStore — обычная плоская
-- таблица без метатаблицы (JSON-совместимая).
function BigNum:toData()
	return { s = self.s, m = self.m, e = self.e }
end

function BigNum.fromData(data)
	if isBigNum(data) then
		return data
	end
	if type(data) ~= "table" then
		-- Старый формат (обычное число) — миграция должна была перехватить
		-- это раньше, но не роняем сервер, если всё же долетело.
		return BigNum.new(data)
	end
	local s = tonumber(data.s) or 0
	local m = math.abs(tonumber(data.m) or 0)
	local e = math.floor(tonumber(data.e) or 0)
	if m ~= m or e ~= e then -- битые данные в сейве
		return newRaw(0, 0, 0)
	end
	return newRaw(normalize(s, m, e))
end

function BigNum:isZero()
	return self.s == 0
end

function BigNum:isNegative()
	return self.s < 0
end

function BigNum:isPositive()
	return self.s > 0
end

-- Обратно в обычное Lua-число. Безопасно для сравнительно небольших сумм
-- (тиры прокачки, цены в магазине) — для АСТРОНОМИЧЕСКИХ величин (сами
-- деньги игрока после десятков ребёртов) даёт лишь приближение, что и
-- ожидаемо: ту точность, что теряет double, BigNum хранит только пока
-- число остаётся в BigNum-форме.
function BigNum:toNumber()
	if self.s == 0 then return 0 end
	if self.e > 308 then
		return self.s > 0 and math.huge or -math.huge
	end
	local value = self.s * self.m * (10 ^ self.e)
	if value ~= value then return 0 end
	return value
end

-- То же самое, но ГАРАНТИРОВАННО конечное число в заданных границах —
-- ровно то, что нужно перед math.floor/DataStore/IntValue.Value, где
-- math.huge или NaN уронили бы вызов.
function BigNum:toNumberClamped(minValue, maxValue)
	minValue = minValue or -9007199254740992 -- -2^53
	maxValue = maxValue or 9007199254740992  --  2^53, предел точного целого в double
	local value = self:toNumber()
	if value ~= value then return 0 end
	if value < minValue then return minValue end
	if value > maxValue then return maxValue end
	return value
end

-- a + b (мантисса bM приводится к порядку aE перед сложением)
local function combine(aS, aM, aE, bS, bM, bE)
	if aS == 0 then return bS, bM, bE end
	if bS == 0 then return aS, aM, aE end
	if aE < bE then
		aS, aM, aE, bS, bM, bE = bS, bM, bE, aS, aM, aE
	end
	local diff = aE - bE
	if diff > 17 then
		-- bM меньше на 17+ порядков — на арифметике double неотличимо от 0
		return aS, aM, aE
	end
	local bShifted = bM / (10 ^ diff)
	local total = aS * aM + bS * bShifted
	local sign = total < 0 and -1 or (total > 0 and 1 or 0)
	return normalize(sign, math.abs(total), aE)
end

function BigNum.__add(a, b)
	a, b = BigNum.new(a), BigNum.new(b)
	return newRaw(combine(a.s, a.m, a.e, b.s, b.m, b.e))
end

function BigNum.__sub(a, b)
	a, b = BigNum.new(a), BigNum.new(b)
	return newRaw(combine(a.s, a.m, a.e, -b.s, b.m, b.e))
end

function BigNum.__unm(a)
	a = BigNum.new(a)
	return newRaw(-a.s, a.m, a.e)
end

function BigNum.__mul(a, b)
	a, b = BigNum.new(a), BigNum.new(b)
	if a.s == 0 or b.s == 0 then return newRaw(0, 0, 0) end
	return newRaw(normalize(a.s * b.s, a.m * b.m, a.e + b.e))
end

function BigNum.__div(a, b)
	a, b = BigNum.new(a), BigNum.new(b)
	if b.s == 0 then
		return newRaw(0, 0, 0) -- защита от деления на 0 — в игровой экономике это всегда баг где-то выше, а не повод падать
	end
	if a.s == 0 then return newRaw(0, 0, 0) end
	return newRaw(normalize(a.s * b.s, a.m / b.m, a.e - b.e))
end

--------------------------------------------------------------------------------
-- СРАВНЕНИЯ
--
-- Метаметоды __lt/__le/__eq ОСТАВЛЕНЫ — они корректно работают, когда ОБА
-- операнда уже BigNum (`money < cost`, где оба из DataService). Но Luau не
-- позволяет им сработать для смешанной пары table/number, поэтому основной,
-- рекомендуемый способ — статические BigNum.lt/le/gt/ge/eq/compare ниже:
-- они принимают что угодно с любой стороны и никогда не падают.
--------------------------------------------------------------------------------

local EPSILON = 1e-12
local function compareMagnitude(aM, aE, bM, bE)
	if aE ~= bE then
		return aE < bE and -1 or 1
	end
	if math.abs(aM - bM) < EPSILON then
		return 0
	end
	return aM < bM and -1 or 1
end

-- -1 если a < b, 0 если равны, 1 если a > b. Принимает BigNum/число/строку
-- в любой комбинации — это ЕДИНСТВЕННАЯ функция сравнения, которую стоит
-- звать из игрового кода напрямую, остальные сделаны через неё.
function BigNum.compare(a, b)
	a, b = BigNum.new(a), BigNum.new(b)
	if a.s ~= b.s then
		return a.s < b.s and -1 or 1
	end
	if a.s == 0 then
		return 0
	end
	local mag = compareMagnitude(a.m, a.e, b.m, b.e)
	-- У отрицательных чисел бОльшая величина означает МЕНЬШЕЕ значение.
	return a.s > 0 and mag or -mag
end

function BigNum.lt(a, b) return BigNum.compare(a, b) < 0 end
function BigNum.le(a, b) return BigNum.compare(a, b) <= 0 end
function BigNum.gt(a, b) return BigNum.compare(a, b) > 0 end
function BigNum.ge(a, b) return BigNum.compare(a, b) >= 0 end
function BigNum.eq(a, b) return BigNum.compare(a, b) == 0 end

-- Метаметоды — работают только для пары BigNum/BigNum (см. блок выше).
function BigNum.__eq(a, b) return BigNum.compare(a, b) == 0 end
function BigNum.__lt(a, b) return BigNum.compare(a, b) < 0 end
function BigNum.__le(a, b) return BigNum.compare(a, b) <= 0 end

-- Целая неотрицательная степень: base:powInt(n) — используется для роста
-- цены ребёрта (CostGrowth^rebirths), где rebirths — обычное маленькое
-- целое, но при большом числе ребёртов сам результат уже не помещается в
-- double. Быстрое возведение в степень (log n умножений).
function BigNum:powInt(n)
	n = math.floor(tonumber(n) or 0)
	if n <= 0 then return BigNum.new(1) end
	local result = BigNum.new(1)
	local base = self
	while n > 0 do
		if n % 2 == 1 then
			result = result * base
		end
		n = math.floor(n / 2)
		if n > 0 then
			base = base * base
		end
	end
	return result
end

function BigNum:floor()
	if self.s < 0 then
		-- floor() отрицательных денег в игре не нужен (деньги никогда не
		-- бывают < 0) — не роняем сервер, просто возвращаем как есть.
		return self
	end
	if self.s == 0 then
		return self
	end
	if self.e >= 15 then
		return self -- на таких масштабах дробной части физически нет (double столько точности не хранит)
	end
	local whole = math.floor(self.m * (10 ^ self.e))
	return BigNum.new(whole)
end

function BigNum.max(a, b)
	a, b = BigNum.new(a), BigNum.new(b)
	return BigNum.compare(a, b) < 0 and b or a
end

function BigNum.min(a, b)
	a, b = BigNum.new(a), BigNum.new(b)
	return BigNum.compare(a, b) < 0 and a or b
end

-- Зажимает значение в [lo, hi].
function BigNum:clamp(lo, hi)
	local result = self
	if lo ~= nil then result = BigNum.max(result, lo) end
	if hi ~= nil then result = BigNum.min(result, hi) end
	return result
end

--------------------------------------------------------------------------------
-- Форматирование — общие суффиксы для NumberFormat.lua (K/M/B/T/Qa/Qi/... и
-- дальше уже научной нотацией, чтобы не заводить бесконечный список имён,
-- которых игрок всё равно не запомнит после квинтиллиона).
--------------------------------------------------------------------------------

local NAMED_SUFFIXES = {
	{ 3, "K" }, { 6, "M" }, { 9, "B" }, { 12, "T" },
	{ 15, "QA" }, { 18, "QI" }, { 21, "SX" }, { 24, "SP" },
	{ 27, "OC" }, { 30, "NO" }, { 33, "DC" },
	{ 36, "UDC" }, { 39, "DDC" }, { 42, "TDC" }, { 45, "QADC" },
	{ 48, "QIDC" }, { 51, "SXDC" }, { 54, "SPDC" }, { 57, "OCDC" },
	{ 60, "NODC" }, { 63, "VG" },
}

-- Возвращает "1.23Qa" / "4.56e70" и т.п. Числа меньше 1000 — просто целым
-- без суффикса (см. NumberFormat.abbreviate для обычных чисел).
function BigNum:abbreviate()
	if self.s == 0 then return "0" end
	local sign = self.s < 0 and "-" or ""
	if self.e < 3 then
		local value = self.m * (10 ^ self.e)
		return sign .. ("%.0f"):format(value)
	end
	for _, entry in NAMED_SUFFIXES do
		local exp, name = entry[1], entry[2]
		if self.e < exp + 3 then
			local shortValue = self.m * (10 ^ (self.e - exp))
			if shortValue >= 100 then
				return sign .. ("%d%s"):format(math.floor(shortValue), name)
			end
			shortValue = math.floor(shortValue * 10) / 10
			local formatted = shortValue == math.floor(shortValue) and ("%d"):format(shortValue) or ("%.1f"):format(shortValue)
			return sign .. formatted .. name
		end
	end
	-- Дальше именованных суффиксов не напаслись — научная нотация.
	return sign .. ("%.2fe%d"):format(self.m, self.e)
end

-- Полное число с точками-разделителями (для диалогов НПС, где нужна точная
-- цена) — но только пока это физически ЧЕСТНО.
--
-- ИСПРАВЛЕННЫЙ БАГ "после 17-го ребёрта везде одно и то же число".
-- Ниже стоит math.floor(self:toNumberClamped()), а toNumberClamped БЕЗ
-- аргументов зажимает результат в ±2^53 = 9007199254740992 (предел точного
-- целого в double). Порог перехода на аббревиатуру при этом стоял на e >= 21,
-- то есть на 10^21. В зазоре между 9.007e15 и 1e21 функция возвращала
-- КОНСТАНТУ "9.007.199.254.740.992" для ЛЮБОГО числа — цена 17-го ребёрта,
-- 18-го, 25-го выглядели совершенно одинаково, и игрок не понимал, сколько
-- вообще нужно накопить. Чуть ниже порога (примерно с 12-го ребёрта) вылезала
-- вторая часть той же проблемы: мусорные хвостовые цифры вида
-- "2.606.476.860.000.001" — двоичное округление double.
--
-- 15 — это НЕ округление "на глаз", а ровно та граница, где double перестаёт
-- точно представлять целые: числа с e <= 14 (то есть < 10^15) все меньше
-- 2^53 и печатаются посимвольно верно, а на e = 15 диапазон 1e15..1e16 уже
-- частично выходит за 2^53. Поэтому дальше отдаём abbreviate() — короткое,
-- но ЧЕСТНОЕ число, вместо длинной строки заведомо неверных цифр.
local EXACT_INTEGER_EXPONENT_LIMIT = 15

function BigNum:withSeparators()
	if self.e >= EXACT_INTEGER_EXPONENT_LIMIT then
		return self:abbreviate()
	end
	local value = math.floor(self:toNumberClamped())
	local negative = value < 0
	local digits = ("%.0f"):format(math.abs(value))
	local grouped = digits:reverse():gsub("(%d%d%d)", "%1."):reverse()
	grouped = grouped:gsub("^%.", "")
	return (negative and "-" or "") .. grouped
end

BigNum.__tostring = function(self)
	return self:abbreviate()
end

-- Без __concat выражение `"Цена: " .. cost` падало с "attempt to
-- concatenate string with table". Теперь работает с любой стороны.
BigNum.__concat = function(a, b)
	local left = isBigNum(a) and a:abbreviate() or tostring(a)
	local right = isBigNum(b) and b:abbreviate() or tostring(b)
	return left .. right
end

return BigNum
