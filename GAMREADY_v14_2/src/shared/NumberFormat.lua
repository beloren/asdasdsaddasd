--------------------------------------------------------------------------------
-- NumberFormat
-- 12345 → "12.3K", 4500000 → "4.5M" — как в популярных симуляторах.
--
-- Принимает И обычные Lua-числа, И BigNum (см. Shared.BigNum) — деньги
-- игрока (DataService:GetMoney/GetRebirthCost) теперь BigNum, потому что
-- обычный double точно хранит целые только до 2^53 (Config.Economy.
-- MaxCurrency = 9e15 раньше стоял ровно на этой границе). Остальные вызовы
-- (цены в магазине, доход геод и т.п.) как были обычными числами, так и
-- остались — функция сама определяет, что ей передали.
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BigNum = require(ReplicatedStorage.Shared.BigNum)

local NumberFormat = {}

local SUFFIXES = {
	{ 1e18, "QI" },
	{ 1e15, "QA" },
	{ 1e12, "T" },
	{ 1e9, "B" },
	{ 1e6, "M" },
	{ 1e3, "K" },
}

function NumberFormat.abbreviate(value)
	if BigNum.is(value) then
		return value:abbreviate()
	end
	value = tonumber(value) or 0
	if value ~= value then return "0" end
	if value == math.huge then return "MAX" end
	if value == -math.huge then return "-MAX" end
	local sign = value < 0 and "-" or ""
	value = math.abs(value)
	for _, entry in SUFFIXES do
		local threshold, suffix = entry[1], entry[2]
		if value >= threshold then
			local short = value / threshold
			if short >= 100 then
				return sign .. ("%d%s"):format(math.floor(short), suffix)
			end
			short = math.floor(short * 10) / 10
			local formatted = short == math.floor(short) and ("%d"):format(short) or ("%.1f"):format(short)
			return sign .. formatted .. suffix
		end
	end
	return sign .. ("%.0f"):format(value)
end

-- v14.3: ДОХОД В СЕКУНДУ. Вся экономика по-прежнему хранит ставки в $/мин
-- (IncomePerMinute и т.п.) — эта функция только ПЕРЕВОДИТ их для экрана:
-- делит на 60 и красиво округляет. Мелкие ставки показываются с одной
-- десятой ("0.5", "2.3"), чтобы не превращаться в "0"; крупные — как
-- обычно, сокращением ("1.2K", "4.5M").
function NumberFormat.perSecond(perMinute)
	local value
	if BigNum.is(perMinute) then
		value = tonumber(perMinute:toNumber()) or 0
	else
		value = tonumber(perMinute) or 0
	end
	value = value / 60
	if value ~= value or value <= 0 then return "0" end
	if value < 10 then
		local short = math.floor(value * 10) / 10
		if short <= 0 then return "0.1" end
		return short == math.floor(short) and ("%d"):format(short) or ("%.1f"):format(short)
	end
	return NumberFormat.abbreviate(math.floor(value))
end

-- 1234567 → "1.234.567" — точки-разделители тысяч/миллионов и т.п. (см.
-- запрос "сделать точки при диалоге с нпс... для простого восприятия").
-- В отличие от abbreviate (которое СОКРАЩАЕТ до K/M/B и теряет точность),
-- эта функция сохраняет ПОЛНОЕ число — то, что нужно в диалогах с НПС,
-- где игрок должен видеть точную цену, а не примерную.
function NumberFormat.withSeparators(value)
	if BigNum.is(value) then
		return value:withSeparators()
	end
	value = math.floor(tonumber(value) or 0)
	local negative = value < 0
	local digits = ("%.0f"):format(math.abs(value))
	local grouped = digits:reverse():gsub("(%d%d%d)", "%1."):reverse()
	grouped = grouped:gsub("^%.", "") -- убираем случайную точку в самом начале, если длина кратна 3
	return (negative and "-" or "") .. grouped
end

return NumberFormat
