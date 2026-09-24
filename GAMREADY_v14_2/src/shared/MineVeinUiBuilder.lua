--------------------------------------------------------------------------------
-- MineVeinUiBuilder — собирает интерфейс мини-игры "РУДНАЯ ЖИЛА" (вариант A).
--
-- ОДИН источник правды для двух мест:
--   • tools/BuildAllUI.lua (Studio Command Bar) кладёт результат в
--     StarterGui — дальше вид правится мышкой, картинки подставляются в
--     ImageLabel'ы;
--   • MineExpeditionUI.client.lua строит то же самое сам, если в
--     StarterGui нет свежего MineArcUi (игра не ломается без билдера).
--
-- КАРТИНКИ. Всё, что имеет смысл заменить своим артом, — ImageLabel с
-- пустым Image и "запасным" видом из цветных плашек:
--   Vein/VeinImage              — сама жила (фон полосы);
--   Vein/GoodZoneTemplate       — кристальная зона (GOOD);
--   Vein/PerfectZoneTemplate    — самородок (PERFECT);
--   Vein/Pick                   — кирка-бегунок;
--   HitPips/Pip1..3             — кружки результатов ударов.
-- Клиент: если у ImageLabel задан Image — запасные дочерние плашки
-- (Pebbles/Shine/Gem*/Handle/Head) прячутся, фон делается прозрачным.
-- Зоны растягиваются по ширине, поэтому для них лучше ScaleType = Slice
-- (SliceCenter настраивается в Studio) или Stretch.
--
-- СТРУКТУРА:
--   ScreenGui "MineArcUi"
--   ├─ Frame "ModifierCard"   — крупная карточка модификатора захода
--   │    ├─ Title, Subtitle (TextLabel)
--   └─ Frame "Container"      — вся мини-игра, у низа экрана над хотбаром
--        ├─ UIScale "AutoScale"
--        ├─ Frame "ModifierTag" → Title
--        ├─ TextLabel "Verdict" (+ UIScale "Pop")
--        ├─ Frame "Vein"
--        │    ├─ ImageLabel "VeinImage" (+ Frame "Pebbles", "Cracks")
--        │    ├─ Frame "Zones"
--        │    ├─ ImageLabel "GoodZoneTemplate" (Visible = false)
--        │    ├─ ImageLabel "PerfectZoneTemplate" (Visible = false)
--        │    ├─ Frame "Marker"
--        │    ├─ ImageLabel "Pick" (+ Handle, Head)
--        │    └─ Frame "Flash"
--        ├─ Frame "HitPips" → Pip1..Pip3
--        ├─ TextLabel "LuckLabel"
--        └─ TextButton "TapButton" (на тач-устройствах)
--------------------------------------------------------------------------------

local UiKit = require(script.Parent.UiKit)
local Theme = UiKit.Theme

local Builder = {}

Builder.VERSION = 20 -- клиент пересобирает MineArcUi, если версия в StarterGui старее
Builder.VEIN_WIDTH = 540
Builder.VEIN_HEIGHT = 44

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0, 8)
	c.Parent = parent
	return c
end

local function stroke(parent, color, thickness, name)
	local s = Instance.new("UIStroke")
	s.Name = name or "UIStroke"
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

-- v20: текст — стиль темы (жирный курсив с обводкой).
local function label(name, text, size, color)
	return UiKit.Text(nil, name, text, {
		_Style = "Title",
		Size = size,
		TextColor3 = color or Color3.new(1, 1, 1),
	})
end

-- v20: все плашки запасного вида — ImageLabel (Image пустой = видна
-- заливка цветом; поставишь картинку — клиент спрячет запасной декор).
local function frame(name, props)
	local f = Instance.new("ImageLabel")
	f.Name = name
	f.Image = ""
	f.BorderSizePixel = 0
	for key, value in props do
		f[key] = value
	end
	return f
end

function Builder.Build()
	local W, H = Builder.VEIN_WIDTH, Builder.VEIN_HEIGHT

	local gui = UiKit.Screen("MineArcUi", { DisplayOrder = 45, Enabled = false })
	gui:SetAttribute("VeinUiVersion", Builder.VERSION)

	----------------------------------------------------------------------------
	-- КАРТОЧКА МОДИФИКАТОРА (по центру экрана, появляется в начале захода)
	----------------------------------------------------------------------------
	local card = UiKit.Card(nil, "ModifierCard", Theme.Accents.Gold, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(440, 104),
		Visible = false,
	})
	card:FindFirstChild("SkinStroke").Name = "Rim"
	local cardScale = Instance.new("UIScale")
	cardScale.Name = "Pop"
	cardScale.Parent = card
	local cardTitle = label("Title", "GOLDEN VEIN", UDim2.new(1, -24, 0, 50), Theme.Accents.Gold.Main)
	cardTitle.Position = UDim2.fromOffset(12, 10)
	cardTitle.Parent = card
	local cardSub = label("Subtitle", "Perfect hits give x2.5 luck", UDim2.new(1, -24, 0, 26), Color3.fromRGB(235, 230, 220))
	cardSub.Position = UDim2.fromOffset(12, 64)
	cardSub.Parent = card
	card.Parent = gui

	----------------------------------------------------------------------------
	-- КОНТЕЙНЕР МИНИ-ИГРЫ — у низа экрана, чуть выше хотбара (хотбар:
	-- низ -14, высота 60 → его верх в 74 px от низа экрана).
	----------------------------------------------------------------------------
	local container = frame("Container", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -84),
		Size = UDim2.fromOffset(600, 150),
		BackgroundTransparency = 1,
	})
	local autoScale = Instance.new("UIScale")
	autoScale.Name = "AutoScale"
	autoScale.Parent = container
	container.Parent = gui

	-- Компактная плашка модификатора над жилой (живёт весь заход).
	local tag = UiKit.Plate(nil, "ModifierTag", "Pill", {
		_Accent = Theme.Accents.Gold,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(300, 0),
		Size = UDim2.fromOffset(230, 24),
		Visible = false,
	})
	tag:FindFirstChild("SkinStroke").Name = "Rim"
	local tagTitle = label("Title", "GOLDEN VEIN", UDim2.new(1, -16, 1, -6), Color3.fromRGB(255, 205, 70))
	tagTitle.AnchorPoint = Vector2.new(0.5, 0.5)
	tagTitle.Position = UDim2.fromScale(0.5, 0.5)
	tagTitle.Parent = tag
	tag.Parent = container

	-- Вердикт удара: PERFECT! / GOOD / MISS.
	local verdict = label("Verdict", "", UDim2.fromOffset(260, 34))
	verdict.AnchorPoint = Vector2.new(0.5, 0.5)
	verdict.Position = UDim2.fromOffset(300, 44)
	verdict.ZIndex = 20
	verdict.TextTransparency = 1
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Parent = verdict
	verdict.Parent = container

	----------------------------------------------------------------------------
	-- ЖИЛА
	----------------------------------------------------------------------------
	local vein = frame("Vein", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(300, 74),
		Size = UDim2.fromOffset(W, H),
		BackgroundTransparency = 1,
	})
	vein:SetAttribute("TrackWidth", W)
	vein.Parent = container

	local veinImage = Instance.new("ImageLabel")
	veinImage.Name = "VeinImage"
	veinImage.Size = UDim2.fromScale(1, 1)
	veinImage.BackgroundColor3 = Color3.fromRGB(34, 31, 28)
	veinImage.BorderSizePixel = 0
	veinImage.Image = ""
	veinImage.ScaleType = Enum.ScaleType.Stretch
	veinImage.ZIndex = 2
	corner(veinImage, UDim.new(0, 12))
	stroke(veinImage, Color3.fromRGB(92, 86, 78), 3, "Rim")
	veinImage.Parent = vein

	-- Запасной декор: камешки по кромке жилы и тонкие трещины внутри.
	local pebbles = frame("Pebbles", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1 })
	pebbles.Parent = veinImage
	local rng = Random.new(7)
	local pebbleColors = { Color3.fromRGB(96, 90, 84), Color3.fromRGB(78, 73, 68), Color3.fromRGB(110, 102, 92) }
	for i = 1, 22 do
		for _, top in { true, false } do
			local size = rng:NextInteger(9, 16)
			local p = frame("Pebble", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new((i - 0.5) / 22 + rng:NextNumber(-0.01, 0.01), 0, top and 0 or 1, top and -2 or 2),
				Size = UDim2.fromOffset(size, math.floor(size * 0.8)),
				BackgroundColor3 = pebbleColors[rng:NextInteger(1, #pebbleColors)],
				ZIndex = 1,
			})
			corner(p, UDim.new(0, 3))
			p.Parent = pebbles
		end
	end
	local cracks = frame("Cracks", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3 })
	cracks.Parent = veinImage
	for i = 1, 7 do
		local c = frame("Crack", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0.04 + (i - 1) * 0.135, 0, rng:NextNumber(0.3, 0.7), 0),
			Size = UDim2.fromOffset(rng:NextInteger(26, 48), 2),
			BackgroundColor3 = Color3.fromRGB(70, 66, 60),
			ZIndex = 3,
		})
		c.Parent = cracks
	end

	local zones = frame("Zones", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 4 })
	zones.Parent = vein

	-- GOOD — кристальная зона.
	local good = Instance.new("ImageLabel")
	good.Name = "GoodZoneTemplate"
	good.Visible = false
	good.AnchorPoint = Vector2.new(0, 0.5)
	good.Position = UDim2.fromScale(0, 0.5)
	good.Size = UDim2.new(0.2, 0, 1, -10)
	good.BackgroundColor3 = Color3.fromRGB(64, 150, 58)
	good.BorderSizePixel = 0
	good.Image = ""
	good.ScaleType = Enum.ScaleType.Stretch
	good.ZIndex = 5
	corner(good, UDim.new(0, 8))
	local goodShine = frame("Shine", {
		Position = UDim2.new(0, 4, 0, 3),
		Size = UDim2.new(1, -8, 0.28, 0),
		BackgroundColor3 = Color3.fromRGB(160, 225, 120),
		BackgroundTransparency = 0.35,
		ZIndex = 6,
	})
	corner(goodShine, UDim.new(0, 4))
	goodShine.Parent = good
	for index, x in { 0.2, 0.5, 0.8 } do
		local gem = frame("Gem" .. index, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, 0.6),
			Size = UDim2.fromOffset(9, 9),
			BackgroundColor3 = Color3.fromRGB(190, 240, 150),
			ZIndex = 6,
		})
		corner(gem, UDim.new(0, 2))
		gem.Parent = good
	end
	good.Parent = vein

	-- PERFECT — самородок: выше жилы, золотой, с белой обводкой.
	local perfect = Instance.new("ImageLabel")
	perfect.Name = "PerfectZoneTemplate"
	perfect.Visible = false
	perfect.AnchorPoint = Vector2.new(0, 0.5)
	perfect.Position = UDim2.fromScale(0, 0.5)
	perfect.Size = UDim2.new(0.05, 0, 1, 8)
	perfect.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
	perfect.BorderSizePixel = 0
	perfect.Image = ""
	perfect.ScaleType = Enum.ScaleType.Stretch
	perfect.ZIndex = 7
	corner(perfect, UDim.new(0, 6))
	stroke(perfect, Color3.fromRGB(255, 250, 225), 2, "Glow")
	local perfectShine = frame("Shine", {
		Position = UDim2.new(0, 3, 0, 3),
		Size = UDim2.new(1, -6, 0.3, 0),
		BackgroundColor3 = Color3.fromRGB(255, 240, 180),
		BackgroundTransparency = 0.2,
		ZIndex = 8,
	})
	corner(perfectShine, UDim.new(0, 3))
	perfectShine.Parent = perfect
	perfect.Parent = vein

	-- Точная риска — куда именно придётся удар.
	local marker = frame("Marker", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(0, 4, 1, 10),
		BackgroundColor3 = Color3.fromRGB(255, 250, 235),
		ZIndex = 10,
	})
	corner(marker, UDim.new(0, 2))
	marker.Parent = vein

	-- Кирка-бегунок над жилой.
	local pick = Instance.new("ImageLabel")
	pick.Name = "Pick"
	pick.AnchorPoint = Vector2.new(0.5, 1)
	pick.Position = UDim2.new(0, 0, 0, 12)
	pick.Size = UDim2.fromOffset(46, 58)
	pick.BackgroundTransparency = 1
	pick.Image = ""
	pick.ScaleType = Enum.ScaleType.Fit
	pick.ZIndex = 11
	local handle = frame("Handle", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(0, 6, 1, -6),
		BackgroundColor3 = Color3.fromRGB(128, 84, 46),
		ZIndex = 11,
	})
	corner(handle, UDim.new(0, 3))
	handle.Parent = pick
	local head = frame("Head", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 2),
		Size = UDim2.new(1, -2, 0, 10),
		BackgroundColor3 = Color3.fromRGB(206, 204, 196),
		ZIndex = 12,
	})
	corner(head, UDim.new(0, 5))
	stroke(head, Color3.fromRGB(60, 58, 54), 1.5, "Edge")
	head.Parent = pick
	pick.Parent = vein

	local flash = frame("Flash", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		ZIndex = 15,
	})
	corner(flash, UDim.new(0, 12))
	flash.Parent = vein

	----------------------------------------------------------------------------
	-- РЕЗУЛЬТАТЫ УДАРОВ + УДАЧА
	----------------------------------------------------------------------------
	local pips = frame("HitPips", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(300, 128),
		Size = UDim2.fromOffset(90, 18),
		BackgroundTransparency = 1,
	})
	local pipLayout = Instance.new("UIListLayout")
	pipLayout.FillDirection = Enum.FillDirection.Horizontal
	pipLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	pipLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	pipLayout.Padding = UDim.new(0, 10)
	pipLayout.SortOrder = Enum.SortOrder.Name
	pipLayout.Parent = pips
	for i = 1, 3 do
		local pip = Instance.new("ImageLabel")
		pip.Name = "Pip" .. i
		pip.Size = UDim2.fromOffset(16, 16)
		pip.BackgroundColor3 = Color3.fromRGB(70, 66, 60)
		pip.BorderSizePixel = 0
		pip.Image = ""
		corner(pip, UDim.new(1, 0))
		stroke(pip, Color3.fromRGB(30, 26, 22), 2, "Edge")
		pip.Parent = pips
	end
	pips.Parent = container

	local luck = label("LuckLabel", "LUCK +0%", UDim2.fromOffset(130, 20), Color3.fromRGB(250, 210, 90))
	luck.AnchorPoint = Vector2.new(1, 0)
	luck.Position = UDim2.fromOffset(300 + W / 2, 127)
	luck.TextXAlignment = Enum.TextXAlignment.Right
	luck.Parent = container

	-- Кнопка удара — только для тача (клиент прячет её на ПК: там бьют
	-- кликом в любом месте экрана или пробелом).
	local tap = UiKit.TextButton(nil, "TapButton", "HIT", {
		_Style = "Title",
		_StrokeColor = Theme.Skins.Button_Yellow.TextStroke,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(300 + W / 2 + 10, 74 + H / 2),
		Size = UDim2.fromOffset(64, 48),
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Skins.Button_Yellow.Color,
		ZIndex = 12,
	})
	UiKit.Stroke(tap, Theme.Skins.Button_Yellow.StrokeColor, 1.5, 0, "SkinStroke")
	tap.Parent = container

	return gui
end

return Builder
