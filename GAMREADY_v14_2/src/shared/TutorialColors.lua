--------------------------------------------------------------------------------
-- TutorialColors (v20.174) — ЦВЕТНЫЕ КЛЮЧЕВЫЕ СЛОВА в текстах обучения.
-- Красит уже ПЕРЕВЕДЁННЫЙ текст (английский и русский), поэтому переводы
-- реплик не ломаются. Список слов и цветов - Config.Tutorial.Keywords.
-- Текст внутри уже стоящих тегов (<font ...>) не трогается.
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local TutorialColors = {}

local function hexOf(color)
	return ("#%02X%02X%02X"):format(math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end

local compiled = nil
local function compile()
	if compiled then return compiled end
	compiled = {}
	for _, group in (Config.Tutorial and Config.Tutorial.Keywords) or {} do
		local hex = typeof(group.Color) == "Color3" and hexOf(group.Color) or tostring(group.Color or "#FFFFFF")
		for _, word in group.Words or {} do
			table.insert(compiled, { Word = word, Hex = hex, Ascii = not word:find("[\128-\255]") })
		end
	end
	-- длинные слова первыми: «backpack» раньше «pack»
	table.sort(compiled, function(a, b) return #a.Word > #b.Word end)
	return compiled
end

local function escapePattern(s)
	return (s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

-- одно слово в куске текста без тегов; уже покрашенные места пропускаем
local function paintSegment(segment)
	local marks = {}
	local lower = segment:lower()
	-- суммы денег «$150», «$1.5K» - зелёным
	local moneyHex = Config.Tutorial and Config.Tutorial.MoneyColor and hexOf(Config.Tutorial.MoneyColor) or "#6CFF7E"
	local startMoney = 1
	while true do
		local s, e = segment:find("%$[%d%.,]+[KMBTkmbt]?", startMoney)
		if not s then break end
		table.insert(marks, { s, e, moneyHex })
		startMoney = e + 1
	end
	for _, entry in compile() do
		local needle = entry.Word:lower()
		local pattern = entry.Ascii and ("%f[%w]" .. escapePattern(needle) .. "%f[%W]") or escapePattern(needle)
		local start = 1
		while true do
			local s, e = lower:find(pattern, start)
			if not s then break end
			local free = true
			for _, m in marks do
				if s <= m[2] and e >= m[1] then free = false break end
			end
			if free then table.insert(marks, { s, e, entry.Hex }) end
			start = e + 1
		end
	end
	if #marks == 0 then return segment end
	table.sort(marks, function(a, b) return a[1] < b[1] end)
	local out, pos = {}, 1
	for _, m in marks do
		table.insert(out, segment:sub(pos, m[1] - 1))
		table.insert(out, ('<font color="%s">%s</font>'):format(m[3], segment:sub(m[1], m[2])))
		pos = m[2] + 1
	end
	table.insert(out, segment:sub(pos))
	return table.concat(out)
end

function TutorialColors.Paint(text)
	if type(text) ~= "string" or text == "" then return text end
	if Config.Tutorial and Config.Tutorial.ColorKeywords == false then return text end
	-- не трогаем содержимое тегов и текст внутри уже покрашенных <font>
	local out = {}
	local depth = 0
	local pos = 1
	while pos <= #text do
		local s, e = text:find("<[^>]*>", pos)
		local chunk = text:sub(pos, (s or #text + 1) - 1)
		if chunk ~= "" then
			table.insert(out, depth > 0 and chunk or paintSegment(chunk))
		end
		if not s then break end
		local tag = text:sub(s, e)
		if tag:match("^<font") then depth += 1 elseif tag:match("^</font") then depth = math.max(0, depth - 1) end
		table.insert(out, tag)
		pos = e + 1
	end
	return table.concat(out)
end

return TutorialColors
