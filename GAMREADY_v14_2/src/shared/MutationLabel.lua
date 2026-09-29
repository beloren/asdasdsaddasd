--------------------------------------------------------------------------------
-- MutationLabel (v20.43) — строка мутаций над рудой: каждая мутация своим
-- цветом (Config.Mutations[id].Color), через « + ». RichText.
--
--   MutationLabel.Rich("Frozen,Golden")  -> '<font color="#..">FROZEN</font> + ...'
--   MutationLabel.Rich(crystal)          -> по атрибуту Mutations у куска
-- Пусто/нет мутаций — nil.
--------------------------------------------------------------------------------
local Config = require(script.Parent.Config)

local MutationLabel = {}

local FALLBACK = Color3.fromRGB(255, 170, 70)

local function hex(color)
	return string.format("%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end

function MutationLabel.Ids(source)
	local raw = source
	if typeof(source) == "Instance" then raw = source:GetAttribute("Mutations") end
	if type(raw) ~= "string" or raw == "" then return {} end
	local ids = {}
	for _, id in string.split(raw, ",") do
		if id ~= "" then table.insert(ids, id) end
	end
	return ids
end

function MutationLabel.Rich(source)
	local parts = {}
	for _, id in MutationLabel.Ids(source) do
		local mutation = Config.Mutations[id]
		local name = ((mutation and mutation.DisplayName) or id):upper()
		local color = (mutation and typeof(mutation.Color) == "Color3") and mutation.Color or FALLBACK
		-- Слишком тёмные цвета (Void) осветляем, чтобы читалось на фоне.
		local _, _, v = color:ToHSV()
		if v < 0.55 then color = color:Lerp(Color3.new(1, 1, 1), 0.35) end
		table.insert(parts, ('<font color="#%s">%s</font>'):format(hex(color), name))
	end
	if #parts == 0 then return nil end
	return table.concat(parts, '<font color="#FFFFFF"> + </font>')
end

-- v20.93: ТАБЛИЧКИ НАД РУДОЙ СТОПКОЙ, без наложений. Снизу вверх:
-- PriceGui (имя/шанс/цена + строка мутаций) -> GiganticBadge -> CutsceneChance.
-- Каждая встаёт над ВЕРХНИМ краем предыдущей (по её реальной высоте), а не
-- на фиксированной высоте - раньше ценник с мутациями вырастал и залезал
-- на плашку GIGANTIC. Вызывать после любого изменения размеров.
local STACK = { "PriceGui", "GiganticBadge", "CutsceneChance" }
local GAP = 0.12
function MutationLabel.Stack(root)
	if not root then return end
	local top = nil
	for _, name in STACK do
		local gui = root:FindFirstChild(name)
		if gui and gui:IsA("BillboardGui") then
			local height = gui.Size.Y.Scale
			if top == nil then
				top = gui.StudsOffset.Y + height / 2
			else
				gui.StudsOffset = Vector3.new(gui.StudsOffset.X, top + GAP + height / 2, gui.StudsOffset.Z)
				top = top + GAP + height
			end
		end
	end
end

return MutationLabel
