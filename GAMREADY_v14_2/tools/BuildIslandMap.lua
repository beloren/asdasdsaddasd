-- BuildIslandMap: строит карту-ОСТРОВ в стиле современных симуляторов
-- (Grow a Garden и т.п.): гладкий пластик, сочные мягкие цвета, ВСЁ ИЗ
-- КУБОВ (никаких клиньев, шаров и цилиндров). Вставь целиком в Command Bar
-- Studio и нажми Enter. Ctrl+Z откатывает всё одним шагом.
--
-- ЧТО СТРОИТСЯ (и что из этого читает код игры):
--   • Остров-городок в центре: БОЛЬШОЙ ПАВИЛЬОН ПРОДАЖИ РУДЫ прямо в центре
--     (SellZone SELL_ZONE x SELL_ZONE), отдельная ЛАВКА ТОРГОВЦА с маркерами
--     MerchantSpot / MerchantSpotLook (обе части - одна модель IsBank),
--     вход в шахту в скале с рельсами к рынку, копёр шахты с колесом, пара
--     домиков, вышка, хижина смотрителя островов (IslandKeeperMarker), табло
--     лайков (LikeGoalBoard), фонари.
--   • 8 коротких тропинок одинаковой длины - каждая упирается в берег с
--     причалом. Дальше ВОДА: базы игроков (Workspace.PlotOrigins) стоят уже
--     в море. Невидимые BridgeSpans/BridgeSpan<N> показывают, где ставить мост.
--   • «Испорченная земля» гоблинов (Workspace.GoblinCamp: Zone + Spawns +
--     Marker): тёмная земля с фиолетовыми трещинами, большие камни (у них
--     точки появления), мёртвые деревья, обелиск.
--   • 16 точек валунов (Workspace.RubbleBoulderSpawnPoints, атрибут Tier).
--   • Пляж ступеньками (песок -> мокрый песок -> мелководье -> море),
--     пальмы, ракушки, невидимая стена в море.
--
-- СТАРОЕ НЕ УДАЛЯЕТСЯ: прежние IslandMap / RetroMap / PlotOrigins /
-- GoblinCamp / RubbleBoulderSpawnPoints / Baseplate и модели с IsBank
-- переносятся в ServerStorage.OldMapBackup.
--
-- Размеры меняются в первых строках. BASE_SIZE - сторона квадрата твоей
-- базы (PlotTemplate) в стадах; от неё считаются расстояния.
local BASE_SIZE = 240        -- сторона базы игрока (под твой PlotTemplate)
local ROAD_LENGTH = 135      -- длина тропинки от города до берега
local WATER_GAP = 36         -- минимальный пролив между концом тропинки и краем базы (там твой мост)
local MIN_BASE_GAP = 20      -- минимум воды между соседними базами (углы не слипаются)
local PLOT_Y = 0.5           -- высота точки PlotOrigins (центр PlotPad толщиной 1)
local TOWN_RADIUS = 110      -- радиус городка
local GOBLIN_ANGLE = 22.5    -- направление лагеря гоблинов (между базами 1 и 2)
local GOBLIN_RADIUS = 186    -- расстояние лагеря от центра
local GOBLIN_SIZE = 80       -- сторона территории гоблинов (углы не должны задевать тропинки)
local SELL_ZONE = 44         -- сторона зоны продажи в центре города
local TREE_COUNT = 80
local SEED = 20260928

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ServerStorage = game:GetService("ServerStorage")
local recording = ChangeHistoryService:TryBeginRecording("BuildIslandMap")
local rng = Random.new(SEED)
local rad = math.rad

local ROAD_START = TOWN_RADIUS - 6
local ROAD_END = ROAD_START + ROAD_LENGTH
-- Остров кончается там же, где тропинки: базы стоят уже В ВОДЕ, через
-- пролив WATER_GAP (мост строишь сам).
local COAST = ROAD_END + 10 -- радиус берега (с лёгким «шумом»)
-- Круг баз: не ближе WATER_GAP к берегу и так, чтобы 8 квадратов BASE_SIZE
-- не задевали друг друга углами (внутренние углы соседей расходятся).
local BASE_RING = math.max(COAST + WATER_GAP + BASE_SIZE / 2,
	BASE_SIZE / 2 + (BASE_SIZE / 2 + MIN_BASE_GAP / 2) / math.tan(math.rad(22.5)))

--------------------------------------------------------------------------------
-- ПАЛИТРА (мягкие сочные цвета симуляторов)
--------------------------------------------------------------------------------
local C = {
	Grass1 = Color3.fromRGB(108, 196, 74),
	Grass2 = Color3.fromRGB(94, 180, 64),
	Grass3 = Color3.fromRGB(128, 206, 88),
	GrassEdge = Color3.fromRGB(150, 205, 95),
	Path = Color3.fromRGB(214, 170, 112),
	PathDark = Color3.fromRGB(186, 140, 90),
	PathEdge = Color3.fromRGB(232, 204, 150),
	Sand = Color3.fromRGB(246, 226, 168),
	SandWet = Color3.fromRGB(224, 200, 140),
	Shallow = Color3.fromRGB(96, 214, 232),
	Water = Color3.fromRGB(52, 160, 226),
	Deep = Color3.fromRGB(34, 118, 200),
	Dirt = Color3.fromRGB(150, 104, 66),
	Stone = Color3.fromRGB(150, 152, 164),
	StoneLight = Color3.fromRGB(190, 192, 202),
	StoneDark = Color3.fromRGB(96, 98, 112),
	Wood = Color3.fromRGB(176, 118, 70),
	WoodLight = Color3.fromRGB(210, 158, 104),
	WoodDark = Color3.fromRGB(120, 78, 48),
	White = Color3.fromRGB(250, 248, 240),
	Cream = Color3.fromRGB(252, 236, 200),
	Red = Color3.fromRGB(232, 84, 72),
	Blue = Color3.fromRGB(72, 146, 232),
	Yellow = Color3.fromRGB(255, 212, 72),
	Orange = Color3.fromRGB(255, 150, 60),
	Pink = Color3.fromRGB(255, 140, 180),
	Purple = Color3.fromRGB(160, 110, 230),
	Teal = Color3.fromRGB(70, 200, 180),
	Leaf1 = Color3.fromRGB(62, 150, 60),
	Leaf2 = Color3.fromRGB(92, 186, 70),
	Leaf3 = Color3.fromRGB(140, 214, 96),
	Crystal = Color3.fromRGB(90, 230, 255),
	Mud = Color3.fromRGB(116, 84, 58),
	MudDark = Color3.fromRGB(78, 58, 44),
	Coal = Color3.fromRGB(44, 44, 52),
}

local function lerpColors(list, t)
	t = math.clamp(t, 0, 1)
	if #list == 1 then return list[1] end
	local scaled = t * (#list - 1)
	local index = math.min(#list - 1, math.floor(scaled) + 1)
	return list[index]:Lerp(list[index + 1], scaled - (index - 1))
end

--------------------------------------------------------------------------------
-- СТАРЫЕ ОБЪЕКТЫ -> ServerStorage.OldMapBackup
--------------------------------------------------------------------------------
local backup = ServerStorage:FindFirstChild("OldMapBackup") or Instance.new("Folder")
backup.Name = "OldMapBackup"
backup.Parent = ServerStorage
for _, name in { "IslandMap", "RetroMap", "PlotOrigins", "GoblinCamp", "RubbleBoulderSpawnPoints", "Baseplate", "LikeGoalBoard", "IslandKeeperMarker", "IslandKeeperMarkerLook" } do
	local old = workspace:FindFirstChild(name)
	if old then old.Parent = backup end
end
for _, inst in workspace:GetDescendants() do
	if inst:IsA("Model") and inst:GetAttribute("IsBank") and inst.Parent then inst.Parent = backup end
end

local map = Instance.new("Model")
map.Name = "IslandMap"
map.Parent = workspace
local function folder(name, parent)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent or map
	return f
end
local groundF = folder("Ground")
local shoreF = folder("Shore")
local roadsF = folder("Roads")
local townF = folder("Town")
local natureF = folder("Nature")
local basesF = folder("Landings")

--------------------------------------------------------------------------------
-- КУБЫ
--------------------------------------------------------------------------------
-- ПАУЗЫ: в Studio у Command Bar есть лимит времени выполнения - без пауз
-- скрипт обрывался на середине (и, например, не успевал построить лагерь
-- гоблинов). Каждые 200 деталей даём Studio «вздохнуть».
local built = 0
local function breathe()
	built += 1
	if built % 200 == 0 and task and task.wait then task.wait() end
end

-- Каждая часть карты строится отдельно: если одна упадёт с ошибкой,
-- остальные всё равно построятся, а ошибка будет в Output.
local function section(name, fn)
	local ok, err = pcall(fn)
	if ok then
		print(("[BuildIslandMap] %s - ok (%d деталей)"):format(name, built))
	else
		warn(("[BuildIslandMap] %s - ОШИБКА: %s"):format(name, tostring(err)))
	end
end

local function box(parent, name, size, cf, color, props)
	breathe()
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props or {} do p[k] = v end
	p.Parent = parent
	return p
end

local function glow(p, range)
	p.Material = Enum.Material.Neon
	if range then
		local l = Instance.new("PointLight")
		l.Color = p.Color
		l.Range = range
		l.Brightness = 1.3
		l.Parent = p
	end
	return p
end

local function marker(parent, name, size, cf, color)
	return box(parent, name, size, cf, color or C.Yellow, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
end

-- Столбик-градиент из кубов (снизу вверх), taper - сужение к верху.
local function stack(parent, name, baseCF, width, depth, height, colors, steps, taper)
	local layer = height / steps
	for i = 1, steps do
		local t = (i - 1) / math.max(1, steps - 1)
		local k = 1 - (taper or 0) * t
		box(parent, name, Vector3.new(width * k, layer, depth * k), baseCF * CFrame.new(0, layer * (i - 0.5), 0), lerpColors(colors, t))
	end
end

local function sign(parent, name, text, size, cf, bg, fg)
	local board = box(parent, name, size, cf, bg or C.Wood)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
		label.TextScaled = true
		label.TextColor3 = fg or C.White
		label.Text = text
		label.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Color = Color3.fromRGB(40, 30, 20)
		stroke.Parent = label
	end
	return board
end

local function polar(angleDeg, radius, y)
	local a = rad(angleDeg)
	return Vector3.new(math.sin(a) * radius, y or 0, -math.cos(a) * radius)
end

-- Берег чуть «гуляет» (сумма синусов) - остров не идеально круглый.
local function coastAt(angleDeg)
	local a = rad(angleDeg)
	-- У тропинок (каждые 45°) берег ровный - тропинка упирается прямо в воду.
	local nearRoad = math.abs(((angleDeg + 22.5) % 45) - 22.5) / 22.5 -- 0 у тропинки, 1 между
	local wobble = math.sin(a * 3 + 0.7) * 9 + math.sin(a * 7 + 2.1) * 5 + math.sin(a * 13) * 3
	return COAST + wobble * nearRoad + 14 * nearRoad
end

--------------------------------------------------------------------------------
-- РАСКЛАДКА
--------------------------------------------------------------------------------
local baseAngles, basePositions = {}, {}
for i = 1, 8 do
	baseAngles[i] = (i - 1) * 45
	basePositions[i] = polar(baseAngles[i], BASE_RING)
end
local goblinCenter = polar(GOBLIN_ANGLE, GOBLIN_RADIUS)

-- Одна форма тропинки на все 8 (повёрнутая копия) - длина одинаковая.
local roadShape = {}
do
	local d = ROAD_START
	while d <= ROAD_END do
		local fade = math.sin(math.clamp((d - ROAD_START) / ROAD_LENGTH, 0, 1) * math.pi)
		table.insert(roadShape, { D = d, Side = math.sin(d / 42) * 10 * fade })
		d += 16
	end
	table.insert(roadShape, { D = ROAD_END + 12, Side = 0 })
end
local function roadPoint(angleDeg, entry)
	local forward = polar(angleDeg, 1)
	local right = Vector3.new(-forward.Z, 0, forward.X)
	return forward * entry.D + right * entry.Side
end

-- Валуны: в секторах между дорогами - ближние (у города) и дальние (у берега).
local boulderSpots = {}
for k = 0, 7 do
	local angle = 22.5 + k * 45
	local isGoblinSector = math.abs(((angle - GOBLIN_ANGLE + 180) % 360) - 180) < 10
	if not isGoblinSector then
		table.insert(boulderSpots, { Pos = polar(angle + (k % 2 == 0 and -5 or 5), TOWN_RADIUS + 38) })
		table.insert(boulderSpots, { Pos = polar(angle, coastAt(angle) - 38) })
	end
end
-- Сектор гоблинов занят лагерем - его 2 точки уходят в противоположные сектора.
for _, k in { 4, 6 } do
	table.insert(boulderSpots, { Pos = polar(22.5 + k * 45 + 12, (TOWN_RADIUS + coastAt(22.5 + k * 45)) / 2 + 4) })
end
table.sort(boulderSpots, function(a, b) return a.Pos.Magnitude < b.Pos.Magnitude end)
for index, spot in boulderSpots do
	spot.Tier = index <= 8 and (((index - 1) % 4) + 1) or (((index - 9) % 5) + 5)
end

local function distanceToRoad(pos)
	local best = math.huge
	for i = 1, 8 do
		local dir = polar(baseAngles[i], 1)
		local along = pos:Dot(dir)
		if along > ROAD_START - 16 and along < ROAD_END + 16 then
			best = math.min(best, (pos - dir * along).Magnitude)
		end
	end
	return best
end

local function flatAngle(pos)
	return math.deg(math.atan2(pos.X, -pos.Z)) % 360
end

local function blocked(pos, margin)
	margin = margin or 0
	local flat = Vector3.new(pos.X, 0, pos.Z)
	if flat.Magnitude < TOWN_RADIUS + 20 + margin then return true end
	if flat.Magnitude > coastAt(flatAngle(flat)) - 40 then return true end
	for i = 1, 8 do
		local rel = CFrame.lookAt(basePositions[i], Vector3.zero):PointToObjectSpace(flat)
		if math.abs(rel.X) < BASE_SIZE / 2 + 40 + margin and math.abs(rel.Z) < BASE_SIZE / 2 + 40 + margin then return true end
	end
	if distanceToRoad(flat) < 24 + margin then return true end
	if (flat - goblinCenter).Magnitude < GOBLIN_SIZE * 0.78 + margin then return true end
	for _, spot in boulderSpots do
		if (flat - spot.Pos).Magnitude < 22 + margin then return true end
	end
	return false
end

--------------------------------------------------------------------------------
-- 1) ОСТРОВ: трава, берег ступеньками, пляж, мелководье, море
--------------------------------------------------------------------------------
do
	-- Трава внутри: крупные кубы с лёгкой «шахматкой» и градиентом к краю.
	local tile = 64
	local n = math.ceil(COAST / tile) + 1
	for x = -n, n do
		for z = -n, n do
			local c = Vector3.new(x * tile, 0, z * tile)
			local farthest = c.Magnitude + tile * 0.72
			if farthest < coastAt(flatAngle(c)) - 34 then
				local color = lerpColors({ C.Grass3, C.Grass1, C.Grass2 }, c.Magnitude / COAST)
				if (x + z) % 2 == 0 then color = color:Lerp(C.Leaf1, 0.06) end
				box(groundF, "Grass", Vector3.new(tile, 6, tile), CFrame.new(c + Vector3.new(0, -3, 0)), color)
			end
		end
	end
	-- Кольцо у берега: сетка кубов 16 стад, тип - по расстоянию до берега.
	local cell = 16
	local m = math.ceil((COAST + 140) / cell)
	for x = -m, m do
		for z = -m, m do
			local c = Vector3.new(x * cell, 0, z * cell)
			local r = c.Magnitude
			local coast = coastAt(flatAngle(c))
			local d = r - coast -- <0 - суша, >0 - вода
			-- Внутренняя граница кольца: там, где кончаются крупные плиты.
			local innerTile = Vector3.new(math.round(x * cell / tile) * tile, 0, math.round(z * cell / tile) * tile)
			local coveredByTile = (innerTile.Magnitude + tile * 0.72 < coastAt(flatAngle(innerTile)) - 34)
				and math.abs(innerTile.X - c.X) <= tile / 2 and math.abs(innerTile.Z - c.Z) <= tile / 2
			if d < 120 and not coveredByTile then
				local color, top
				if d < -26 then
					color, top = C.Grass1:Lerp(C.GrassEdge, math.clamp((d + 60) / 34, 0, 1)), 0
				elseif d < -8 then
					color, top = C.Sand, -0.8
				elseif d < 6 then
					color, top = C.SandWet, -1.6
				elseif d < 40 then
					color, top = C.Shallow:Lerp(C.Water, (d - 6) / 34), -3
				else
					color, top = C.Water:Lerp(C.Deep, math.clamp((d - 40) / 80, 0, 1)), -3.4
				end
				local props = nil
				if d >= 6 then props = { Transparency = 0.15, Material = Enum.Material.Glass } end
				box(shoreF, d >= 6 and "Water" or "Shore", Vector3.new(cell, 6, cell), CFrame.new(c + Vector3.new(0, top - 3, 0)), color, props)
			end
		end
	end
	-- Открытое море (большие кубы за кольцом) + песчаное дно под водой.
	local seaTile = 512
	local seaN = math.ceil((COAST + 900) / seaTile)
	for x = -seaN, seaN do
		for z = -seaN, seaN do
			local c = Vector3.new(x * seaTile, 0, z * seaTile)
			if c.Magnitude > COAST - seaTile * 0.2 then
				box(shoreF, "Sea", Vector3.new(seaTile, 4, seaTile), CFrame.new(c + Vector3.new(0, -5.6, 0)), C.Deep, { Transparency = 0.1, Material = Enum.Material.Glass })
			end
		end
	end
	-- Невидимая стена в море, чтобы не уплыть за край.
	local walls = 48
	local wallR = COAST + 150
	for i = 0, walls - 1 do
		local angle = (i + 0.5) / walls * 360
		local length = 2 * math.pi * wallR / walls + 6
		box(shoreF, "BoundaryWall", Vector3.new(length, 200, 4), CFrame.lookAt(polar(angle, wallR, 96), Vector3.new(0, 96, 0)), C.White, {
			Transparency = 1, CanQuery = false, CanTouch = false,
		})
	end
end

--------------------------------------------------------------------------------
-- 2) ТРОПИНКИ: песочная середина + светлые края, фонари, указатели
--------------------------------------------------------------------------------
for i = 1, 8 do
	local angle = baseAngles[i]
	local road = folder("Road" .. i, roadsF)
	local forward = polar(angle, 1)
	local right = Vector3.new(-forward.Z, 0, forward.X)
	for s = 1, #roadShape - 1 do
		local a = roadPoint(angle, roadShape[s])
		local b = roadPoint(angle, roadShape[s + 1])
		local length = (b - a).Magnitude + 2
		local cf = CFrame.lookAt((a + b) / 2, b)
		box(road, "PathEdge", Vector3.new(20, 0.4, length), cf * CFrame.new(0, 0.2, 0), C.PathEdge)
		box(road, "Path", Vector3.new(14, 0.4, length), cf * CFrame.new(0, 0.4, 0), (s % 2 == 0) and C.Path or C.Path:Lerp(C.PathDark, 0.25))
	end
	local entry = roadPoint(angle, roadShape[2])
	local post = entry + right * 14
	box(road, "SignPost", Vector3.new(1.2, 8, 1.2), CFrame.new(post + Vector3.new(0, 4, 0)), C.WoodDark)
	sign(road, "BaseSign", "BASE " .. i, Vector3.new(8, 3, 0.8), CFrame.lookAt(post + Vector3.new(0, 7.5, 0), post + Vector3.new(0, 7.5, 0) + right), C.Wood, C.Yellow)
	for s = 5, #roadShape - 2, 6 do
		local p = roadPoint(angle, roadShape[s])
		local side = (s // 6) % 2 == 0 and 13 or -13
		local at = p + right * side
		box(road, "LampPost", Vector3.new(1, 9, 1), CFrame.new(at + Vector3.new(0, 4.5, 0)), C.WoodDark)
		box(road, "LampTop", Vector3.new(2.6, 0.6, 2.6), CFrame.new(at + Vector3.new(0, 10.8, 0)), C.WoodDark)
		glow(box(road, "Lamp", Vector3.new(1.8, 1.8, 1.8), CFrame.new(at + Vector3.new(0, 9.8, 0)), C.Yellow), 18)
	end
end

--------------------------------------------------------------------------------
-- 3) БАЗЫ В ВОДЕ: PlotOrigins + причал у конца тропинки + место под мост
--------------------------------------------------------------------------------
local origins = Instance.new("Folder")
origins.Name = "PlotOrigins"
origins.Parent = workspace
local bridges = folder("BridgeSpans", basesF)
for i = 1, 8 do
	local pos = basePositions[i]
	local origin = marker(origins, "Plot" .. i, Vector3.new(4, 1, 4), CFrame.lookAt(pos + Vector3.new(0, PLOT_Y, 0), Vector3.new(0, PLOT_Y, 0)), C.Red)
	origin.Transparency = 0.5
	local look = marker(origins, "Plot" .. i .. "Look", Vector3.new(2, 2, 2), CFrame.new(Vector3.new(0, PLOT_Y, 0):Lerp(pos + Vector3.new(0, PLOT_Y, 0), 0.9)), C.Yellow)
	look.Transparency = 0.5
	-- Причал: деревянный настил на краю берега, где кончается тропинка.
	local forward = polar(baseAngles[i], 1)
	local landing = CFrame.lookAt(forward * (COAST - 2), forward * (COAST + 10))
	box(basesF, "Landing", Vector3.new(18, 0.8, 10), landing * CFrame.new(0, 0.4, 0), C.WoodLight)
	for _, x in { -8, 8 } do
		box(basesF, "LandingPost", Vector3.new(1.4, 7, 1.4), landing * CFrame.new(x, 0.5, -4.4), C.WoodDark)
		glow(box(basesF, "LandingLamp", Vector3.new(1.4, 1.4, 1.4), landing * CFrame.new(x, 4.4, -4.4), C.Yellow), 14)
	end
	-- МЕСТО ПОД МОСТ (невидимое): от края причала до края базы. Выдели
	-- BridgeSpan<N> в Explorer - увидишь рамку, по ней и ставь свой мост.
	local from = forward * (COAST + 3)
	local to = forward * (BASE_RING - BASE_SIZE / 2)
	local span = marker(bridges, "BridgeSpan" .. i, Vector3.new(14, 1, (to - from).Magnitude), CFrame.lookAt((from + to) / 2, to), C.Orange)
	span:SetAttribute("BaseIndex", i)
end

--------------------------------------------------------------------------------
-- 4) ПОЛУШАХТЁРСКИЙ ГОРОДОК
--------------------------------------------------------------------------------
local function gapCFrame(k, radius)
	local p = polar(22.5 + k * 45, radius, 0.5)
	return CFrame.lookAt(p, Vector3.new(0, 0.5, 0)) -- лицом к площади
end

-- Площадь: каменные плиты двух тонов (круг из кубов) + бордюр из кубов.
do
	local cell = 10
	local r = TOWN_RADIUS - 8
	for x = -math.ceil(r / cell), math.ceil(r / cell) do
		for z = -math.ceil(r / cell), math.ceil(r / cell) do
			local c = Vector3.new(x * cell, 0, z * cell)
			if c.Magnitude <= r then
				local color = ((x + z) % 2 == 0) and C.StoneLight or C.Stone:Lerp(C.StoneLight, 0.5)
				box(townF, "Plaza", Vector3.new(cell, 0.5, cell), CFrame.new(c + Vector3.new(0, 0.25, 0)), color)
			end
		end
	end
	-- Заборчик из кубиков по краю городка, проходы под 8 тропинок.
	local segments = 56
	for s = 0, segments - 1 do
		local angle = s * 360 / segments
		local nearRoad = false
		for i = 1, 8 do
			if math.abs(((angle - baseAngles[i] + 180) % 360) - 180) < 8 then nearRoad = true end
		end
		-- у входа в шахту (скала) забор не нужен
		if math.abs(((angle - (22.5 + 4 * 45) + 180) % 360) - 180) < 12 then nearRoad = true end
		if not nearRoad then
			local cf = CFrame.lookAt(polar(angle, TOWN_RADIUS), Vector3.zero)
			local length = 2 * math.pi * TOWN_RADIUS / segments + 0.4
			box(townF, "FenceRail", Vector3.new(length, 0.8, 0.8), cf * CFrame.new(0, 2.4, 0), C.WoodLight)
			box(townF, "FencePost", Vector3.new(1.4, 3.4, 1.4), cf * CFrame.new(length / 2, 1.7, 0), C.Wood)
		end
	end
end

-- КОПЁР ШАХТЫ (деревянная башня с колесом из кубов) над стволом рядом с
-- входом в шахту, светящиеся кристаллы - ориентир, виден издалека.
do
	local model = Instance.new("Model")
	model.Name = "MineHeadframe"
	model.Parent = townF
	local base = gapCFrame(5, 84)
	-- Ствол шахты: тёмный квадрат в каменной обвязке.
	box(model, "ShaftRim", Vector3.new(18, 1.4, 18), base * CFrame.new(0, 0.7, 0), C.StoneDark)
	box(model, "Shaft", Vector3.new(12, 1.5, 12), base * CFrame.new(0, 0.8, 0), C.Coal)
	-- Четыре ноги копра, сходятся к верху.
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			for level = 0, 5 do
				local k = 1 - level * 0.09
				box(model, "Leg", Vector3.new(1.8, 5, 1.8), base * CFrame.new(sx * 7 * k, 2.5 + level * 5, sz * 7 * k), level % 2 == 0 and C.Wood or C.WoodLight)
			end
		end
	end
	-- Поперечины.
	for level = 1, 5, 2 do
		local k = 1 - level * 0.09
		for _, rot in { 0, 90 } do
			box(model, "Brace", Vector3.new(14 * k + 1.8, 1, 1), base * CFrame.Angles(0, rad(rot), 0) * CFrame.new(0, level * 5 + 2.5, 7 * k), C.WoodDark)
			box(model, "Brace", Vector3.new(14 * k + 1.8, 1, 1), base * CFrame.Angles(0, rad(rot), 0) * CFrame.new(0, level * 5 + 2.5, -7 * k), C.WoodDark)
		end
	end
	box(model, "TopDeck", Vector3.new(12, 1.4, 12), base * CFrame.new(0, 31, 0), C.WoodDark)
	-- Колесо: кольцо из кубов + спицы.
	local wheel = base * CFrame.new(0, 37, 0)
	for s = 0, 15 do
		local a = s / 16 * math.pi * 2
		box(model, "WheelRim", Vector3.new(2.2, 2.2, 1.2), wheel * CFrame.new(math.cos(a) * 6, math.sin(a) * 6, 0) * CFrame.Angles(0, 0, a), C.Red)
	end
	for s = 0, 3 do
		box(model, "WheelSpoke", Vector3.new(12, 0.8, 0.8), wheel * CFrame.Angles(0, 0, s * math.pi / 4), C.StoneDark)
	end
	box(model, "WheelHub", Vector3.new(2.4, 2.4, 2.4), wheel, C.Yellow)
	-- Светящиеся кристаллы у ствола.
	for i, spec in ipairs({ { 9, 6, 5 }, { -9, 7, -4 }, { 7, 5, -9 }, { -8, 6, 8 } }) do
		local cf = base * CFrame.new(spec[1], 0, spec[3]) * CFrame.Angles(rad(12), rad(i * 40), rad(-10))
		for layer = 1, 3 do
			local s = 3.6 - layer * 0.8
			local part = box(model, "Crystal", Vector3.new(s, spec[2] / 3, s), cf * CFrame.new(0, spec[2] / 3 * (layer - 0.5), 0), lerpColors({ C.Blue, C.Crystal, C.White }, (layer - 1) / 2))
			if layer == 3 then glow(part, 18) end
		end
	end
	sign(model, "TownSign", "MINER TOWN", Vector3.new(18, 4, 1), base * CFrame.new(0, 34, 6.5), C.Wood, C.Yellow)
end

-- Рельсы из кубов от центра к входу в шахту (скала между дорогами 5 и 6).
local function rails(parent, from, to)
	local length = (to - from).Magnitude
	local cf = CFrame.lookAt((from + to) / 2, to)
	for _, x in { -1.6, 1.6 } do
		box(parent, "Rail", Vector3.new(0.5, 0.5, length), cf * CFrame.new(x, 0.9, 0), C.StoneDark)
	end
	for z = -length / 2 + 1, length / 2 - 1, 3 do
		box(parent, "Sleeper", Vector3.new(5, 0.4, 1), cf * CFrame.new(0, 0.6, z), C.WoodDark)
	end
end

-- Вход в шахту: скала-горка из кубов (градиент камня), тёмный проём, балки.
do
	local model = Instance.new("Model")
	model.Name = "MineEntrance"
	model.Parent = townF
	local cf = gapCFrame(4, 82)
	for layer = 1, 5 do
		local k = 1 - (layer - 1) * 0.17
		for part = -2, 2 do
			local w = (10 + rng:NextNumber() * 4) * k
			box(model, "Rock", Vector3.new(w, 5, w), cf * CFrame.new(part * 7 * k, 2.5 + (layer - 1) * 5, 6 + math.abs(part) * 2) * CFrame.Angles(0, rad(rng:NextNumber() * 20 - 10), 0),
				lerpColors({ C.StoneDark, C.Stone, C.StoneLight }, (layer - 1) / 4))
		end
	end
	box(model, "Opening", Vector3.new(9, 9, 2), cf * CFrame.new(0, 4.5, -0.6), C.Coal)
	for _, x in { -5.2, 5.2 } do box(model, "Beam", Vector3.new(1.6, 10, 1.6), cf * CFrame.new(x, 5, -1.4), C.Wood) end
	box(model, "BeamTop", Vector3.new(12, 1.6, 1.8), cf * CFrame.new(0, 10.4, -1.4), C.Wood)
	sign(model, "MineSign", "MINE", Vector3.new(7, 2.4, 0.6), cf * CFrame.new(0, 12.4, -1.8), C.WoodDark, C.Yellow)
	glow(box(model, "Lantern", Vector3.new(1.4, 1.8, 1.4), cf * CFrame.new(-5.2, 8, -2.8), C.Orange), 16)
	glow(box(model, "Lantern", Vector3.new(1.4, 1.8, 1.4), cf * CFrame.new(5.2, 8, -2.8), C.Orange), 16)
	-- Рельсы от шахты до края рынка в центре.
	rails(model, (cf * CFrame.new(0, -0.5, -1)).Position, (cf.Position - Vector3.new(0, 0.5, 0)).Unit * (SELL_ZONE / 2 + 10))
	-- Вагонетка с рудой.
	local cart = cf * CFrame.new(0, 1.4, -14)
	box(model, "Cart", Vector3.new(4.4, 2.6, 6), cart * CFrame.new(0, 1.3, 0), C.StoneDark)
	box(model, "CartInner", Vector3.new(3.6, 0.4, 5.2), cart * CFrame.new(0, 2.5, 0), C.Coal)
	for o = 1, 4 do
		glow(box(model, "Ore", Vector3.new(1.3, 1.3, 1.3), cart * CFrame.new(o % 2 == 0 and 0.8 or -0.8, 3.1, -2 + o) * CFrame.Angles(rad(o * 25), rad(o * 40), 0), ({ C.Crystal, C.Yellow, C.Pink, C.Orange })[o]))
	end
end

-- Домик из кубов: стены-градиент, ступенчатая крыша, окна, дверь, труба.
local function house(cf, w, d, h, wall, roof, name)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = townF
	stack(model, "Wall", cf, w, d, h, { wall:Lerp(Color3.new(0, 0, 0), 0.12), wall, wall:Lerp(C.White, 0.12) }, 3, 0)
	box(model, "Base", Vector3.new(w + 1, 1, d + 1), cf * CFrame.new(0, 0.5, 0), C.StoneDark)
	-- Крыша ступеньками (5 кубов всё уже и уже).
	for step = 1, 5 do
		local depth = (d + 3) * (1 - (step - 1) * 0.2)
		box(model, "Roof", Vector3.new(w + 3, 1.3, depth), cf * CFrame.new(0, h + 0.65 + (step - 1) * 1.3, 0), roof:Lerp(Color3.new(0, 0, 0), (step - 1) * 0.04))
	end
	box(model, "Door", Vector3.new(4, 6.4, 0.6), cf * CFrame.new(0, 3.2, -d / 2 - 0.3), C.WoodDark)
	box(model, "DoorKnob", Vector3.new(0.6, 0.6, 0.6), cf * CFrame.new(1.2, 3.2, -d / 2 - 0.7), C.Yellow)
	for _, x in { -w / 2 + 3.4, w / 2 - 3.4 } do
		glow(box(model, "Window", Vector3.new(3.2, 3.2, 0.5), cf * CFrame.new(x, h * 0.55, -d / 2 - 0.25), C.Cream))
		box(model, "Sill", Vector3.new(4.2, 0.6, 1.2), cf * CFrame.new(x, h * 0.55 - 2, -d / 2 - 0.6), C.White)
		box(model, "Flowers", Vector3.new(3.6, 0.8, 0.8), cf * CFrame.new(x, h * 0.55 - 1.4, -d / 2 - 0.7), x > 0 and C.Pink or C.Yellow)
	end
	box(model, "Chimney", Vector3.new(2.4, 4, 2.4), cf * CFrame.new(w / 3, h + 4.5, d / 5), C.Red:Lerp(C.StoneDark, 0.35))
	box(model, "Step", Vector3.new(6, 0.6, 2.4), cf * CFrame.new(0, 0.3, -d / 2 - 1.4), C.StoneLight)
	return model
end

-- РЫНОК ШАХТЁРОВ (банк) - ОДНА модель с IsBank (код ищет в ней Building,
-- SellZone и MerchantSpot):
--   • в центре города - большой павильон продажи: SellZone SELL_ZONE x
--     SELL_ZONE под крышей на столбах (Building - крыша, над ней вылетает
--     проданная руда);
--   • отдельная ЛАВКА ТОРГОВЦА между дорогами 3 и 4, в ней маркер
--     MerchantSpot (там стоит торговец) и MerchantSpotLook (куда смотрит).
section("Market + merchant", function()
	local market = Instance.new("Model")
	market.Name = "MinersMarket"
	market:SetAttribute("IsBank", true)
	market.Parent = townF

	-- ПАВИЛЬОН ПРОДАЖИ.
	local center = CFrame.new(0, 0.5, 0)
	local half = SELL_ZONE / 2
	box(market, "SellFloor", Vector3.new(SELL_ZONE + 8, 0.4, SELL_ZONE + 8), center * CFrame.new(0, 0.2, 0), C.WoodLight)
	box(market, "SellZone", Vector3.new(SELL_ZONE, 0.6, SELL_ZONE), center * CFrame.new(0, 0.5, 0), C.Yellow, { Transparency = 0.45, CanCollide = false, Material = Enum.Material.Neon })
	for _, spec in { { Vector3.new(SELL_ZONE + 2, 1, 1), Vector3.new(0, 0.6, half) }, { Vector3.new(SELL_ZONE + 2, 1, 1), Vector3.new(0, 0.6, -half) },
		{ Vector3.new(1, 1, SELL_ZONE + 2), Vector3.new(half, 0.6, 0) }, { Vector3.new(1, 1, SELL_ZONE + 2), Vector3.new(-half, 0.6, 0) } } do
		glow(box(market, "SellZoneEdge", spec[1], center * CFrame.new(spec[2]), C.Orange))
	end
	-- БЕЗ КРЫШИ (высокие тележки). Низкие столбики с фонарями по углам и
	-- таблички SELL ORE на высоких шестах СНАРУЖИ зоны - над зоной ничего нет.
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			local corner = center * CFrame.new(x * (half + 2.5), 0, z * (half + 2.5))
			stack(market, "Post", corner, 2.4, 2.4, 5, { C.WoodDark, C.Wood }, 2, 0)
			glow(box(market, "PostLamp", Vector3.new(1.8, 1.8, 1.8), corner * CFrame.new(0, 6, 0), C.Yellow), 18)
		end
	end
	for side = 0, 3 do
		local sideCF = center * CFrame.Angles(0, rad(side * 90), 0)
		local at = sideCF * CFrame.new(half * 0.55, 0, -(half + 5))
		box(market, "SignPole", Vector3.new(1.2, 14, 1.2), at * CFrame.new(0, 7, 0), C.WoodDark)
		sign(market, "SellSign", "SELL ORE", Vector3.new(12, 3.4, 0.8), at * CFrame.new(0, 12.5, 0), C.Yellow, C.Red)
		-- Полосатый бортик вдоль края пола (низкий, не мешает заезду).
		for s2 = 0, 10 do
			box(market, "Curb", Vector3.new((SELL_ZONE + 8) / 11, 0.2, 1), sideCF * CFrame.new(-(SELL_ZONE + 8) / 2 + (s2 + 0.5) * (SELL_ZONE + 8) / 11, 0.5, -(SELL_ZONE + 8) / 2 + 0.5), s2 % 2 == 0 and C.Red or C.White)
		end
	end
	-- Building - НЕВИДИМАЯ точка над центром зоны: туда вылетает проданная
	-- руда (WorldService:GetBankTopPosition). Ничего не загораживает.
	local building = box(market, "Building", Vector3.new(4, 4, 4), center * CFrame.new(0, 16, 0), C.Yellow, {
		Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false,
	})
	-- Весы и кучи руды по углам зоны (декор, не мешают проходу).
	for i, o in ipairs({ Vector3.new(-half + 3, 0, -half + 3), Vector3.new(half - 3, 0, half - 3) }) do
		box(market, "Scale", Vector3.new(4, 3, 4), center * CFrame.new(o + Vector3.new(0, 1.5, 0)), C.StoneDark)
		glow(box(market, "ScaleOre", Vector3.new(2, 2, 2), center * CFrame.new(o + Vector3.new(0, 4, 0)) * CFrame.Angles(rad(20), rad(i * 30), 0), i == 1 and C.Crystal or C.Yellow), 12)
	end
	market.PrimaryPart = building

	-- ЛАВКА ТОРГОВЦА.
	local shop = Instance.new("Model")
	shop.Name = "MerchantShop"
	shop.Parent = market
	local cf = gapCFrame(2, 76)
	box(shop, "ShopFloor", Vector3.new(24, 0.6, 18), cf * CFrame.new(0, 0.3, 2), C.WoodLight)
	stack(shop, "BackWall", cf * CFrame.new(0, 0, 10), 24, 2, 12, { C.Purple:Lerp(Color3.new(0, 0, 0), 0.2), C.Purple }, 2, 0)
	for _, x in { -11, 11 } do
		stack(shop, "SideWall", cf * CFrame.new(x, 0, 4), 2, 12, 12, { C.Purple:Lerp(Color3.new(0, 0, 0), 0.2), C.Purple }, 2, 0)
	end
	for step = 1, 4 do
		box(shop, "ShopRoof", Vector3.new(27, 1.3, 21 - (step - 1) * 4.6), cf * CFrame.new(0, 12.65 + (step - 1) * 1.3, 2.5), (step % 2 == 1) and C.Purple:Lerp(C.White, 0.2) or C.Yellow)
	end
	-- Прилавок (торговец стоит ЗА ним, игрок подходит спереди).
	box(shop, "Counter", Vector3.new(16, 3.4, 3), cf * CFrame.new(0, 1.7, -4), C.Wood)
	box(shop, "CounterTop", Vector3.new(17, 0.6, 3.6), cf * CFrame.new(0, 3.7, -4), C.WoodLight)
	for o = 1, 4 do
		glow(box(shop, "Potion", Vector3.new(1, 1.6, 1), cf * CFrame.new(-6 + o * 2.4, 4.8, -4), ({ C.Pink, C.Crystal, C.Yellow, C.Leaf3 })[o]))
	end
	for o = 1, 3 do
		box(shop, "Shelf", Vector3.new(18, 0.6, 1.6), cf * CFrame.new(0, 3 + o * 2.4, 8.4), C.WoodDark)
		for q = 1, 5 do
			box(shop, "ShelfItem", Vector3.new(1.4, 1.4, 1.2), cf * CFrame.new(-7 + q * 2.8, 3.9 + o * 2.4, 8.4), ({ C.Red, C.Blue, C.Yellow, C.Teal, C.Orange })[(q + o) % 5 + 1])
		end
	end
	sign(shop, "ShopSign", "MERCHANT", Vector3.new(16, 3.4, 0.8), cf * CFrame.new(0, 11, -6.2), C.Purple, C.Yellow)
	for _, x in { -9, 9 } do glow(box(shop, "ShopLamp", Vector3.new(1.4, 1.8, 1.4), cf * CFrame.new(x, 9, -6.4), C.Yellow), 16) end
	marker(shop, "MerchantSpot", Vector3.new(2, 1, 2), cf * CFrame.new(0, 0.7, 1.5))
	marker(shop, "MerchantSpotLook", Vector3.new(1, 1, 1), cf * CFrame.new(0, 0.7, -12))
end)

-- Домики и мастерские.
house(gapCFrame(3, 78), 18, 14, 10, C.Cream, C.Red, "HouseRed")
house(gapCFrame(6, 78), 16, 13, 9, C.WoodLight, C.Leaf1, "HouseGreen")
house(gapCFrame(7, 80), 18, 14, 10, C.White, C.Orange, "HouseOrange")

-- Башня-вышка шахтёров (ориентир) - между дорогами 2 и 3.
do
	local cf = gapCFrame(1, 80)
	local model = Instance.new("Model")
	model.Name = "Watchtower"
	model.Parent = townF
	stack(model, "Tower", cf, 10, 10, 28, { C.StoneDark, C.Stone, C.StoneLight }, 5, 0.1)
	for step = 1, 4 do box(model, "Roof", Vector3.new(12 - step * 2.2, 1.6, 12 - step * 2.2), cf * CFrame.new(0, 28 + step * 1.6, 0), C.Red) end
	glow(box(model, "Beacon", Vector3.new(2, 2, 2), cf * CFrame.new(0, 36.4, 0), C.Yellow), 30)
	glow(box(model, "Window", Vector3.new(3, 3, 0.5), cf * CFrame.new(0, 22, -4.9), C.Cream))
end

-- Хижина смотрителя островов (IslandKeeperMarker) - между дорогами 1 и 2.
do
	local cf = gapCFrame(0, 78)
	house(cf, 14, 12, 9, C.WoodLight, C.Teal, "IslandKeeperHut")
	local spot = cf * CFrame.new(0, 0.5, -10)
	marker(workspace, "IslandKeeperMarker", Vector3.new(2, 1, 2), spot)
	marker(workspace, "IslandKeeperMarkerLook", Vector3.new(1, 1, 1), CFrame.new(Vector3.new(0, spot.Position.Y, 0)))
	sign(townF, "IslandSign", "ISLANDS", Vector3.new(8, 2.4, 0.6), cf * CFrame.new(0, 12, -6.6), C.Teal, C.White)
end

-- Табло лайков - у площади, лицом к центру.
do
	local pos = polar(202.5, SELL_ZONE / 2 + 26, 8)
	local cf = CFrame.lookAt(pos, Vector3.new(0, 8, 0))
	box(workspace, "LikeGoalBoard", Vector3.new(14, 9, 1), cf, C.WoodDark)
	for _, x in { -6, 6 } do box(townF, "BoardLeg", Vector3.new(1, 4, 1), cf * CFrame.new(x, -6.5, 0), C.Wood) end
end

-- Фонари по кругу площади.
for s = 0, 15 do
	local angle = s * 22.5 + 11.25
	local at = polar(angle, TOWN_RADIUS - 16)
	box(townF, "LampPost", Vector3.new(1, 8, 1), CFrame.new(at + Vector3.new(0, 4.5, 0)), C.WoodDark)
	box(townF, "LampTop", Vector3.new(2.4, 0.6, 2.4), CFrame.new(at + Vector3.new(0, 9.8, 0)), C.WoodDark)
	glow(box(townF, "Lamp", Vector3.new(1.6, 1.6, 1.6), CFrame.new(at + Vector3.new(0, 8.9, 0)), C.Yellow), 16)
end

--------------------------------------------------------------------------------
-- 5) ТЕРРИТОРИЯ ГОБЛИНОВ - «ИСПОРЧЕННАЯ ЗЕМЛЯ» (GoblinCamp: Zone + Spawns + Marker)
-- Тёмная больная земля с фиолетовыми светящимися трещинами, мёртвые
-- деревья и КРУПНЫЕ КАМНИ - гоблины появляются прямо у этих камней.
--------------------------------------------------------------------------------
section("Goblin land", function()
	local camp = Instance.new("Model")
	camp.Name = "GoblinCamp"
	camp.Parent = workspace
	local cf = CFrame.lookAt(goblinCenter, Vector3.zero) -- «вход» смотрит на город
	local deco = folder("Decor", camp)
	local Corrupt = {
		Edge = C.Grass1:Lerp(Color3.fromRGB(90, 70, 90), 0.55),
		Ground = Color3.fromRGB(74, 56, 78),
		Deep = Color3.fromRGB(46, 34, 54),
		Rock = Color3.fromRGB(70, 64, 84),
		RockDark = Color3.fromRGB(44, 40, 56),
		Glow = Color3.fromRGB(190, 70, 255),
		DeadWood = Color3.fromRGB(64, 50, 46),
	}
	local half = GOBLIN_SIZE / 2
	-- Земля: неровные пятна-кубы (крупные -> мелкие, светлее -> темнее к центру).
	for step = 1, 3 do
		local side = GOBLIN_SIZE + 4 - (step - 1) * 22
		box(deco, "CorruptGround", Vector3.new(side, 0.3, side), cf * CFrame.new(0, 0.15 + (step - 1) * 0.15, 0),
			lerpColors({ Corrupt.Edge, Corrupt.Ground, Corrupt.Deep }, (step - 1) / 2))
	end
	for _ = 1, 26 do -- «рваный» край: пятна гнили расползаются на траву
		local a = rng:NextNumber() * math.pi * 2
		local r = half - 2 + rng:NextNumber() * 4
		local sz = 5 + rng:NextNumber() * 5
		box(deco, "Blight", Vector3.new(sz, 0.3, sz * (0.6 + rng:NextNumber() * 0.6)), cf * CFrame.new(math.cos(a) * r, 0.12, math.sin(a) * r) * CFrame.Angles(0, rng:NextNumber() * 3, 0), Corrupt.Edge)
	end
	-- Светящиеся трещины (тонкие неоновые полосы, ломаные).
	for _ = 1, 14 do
		local at = cf * CFrame.new(rng:NextNumber() * GOBLIN_SIZE * 0.8 - GOBLIN_SIZE * 0.4, 0.62, rng:NextNumber() * GOBLIN_SIZE * 0.8 - GOBLIN_SIZE * 0.4)
		local yaw = rng:NextNumber() * math.pi
		for seg = 0, 2 do
			glow(box(deco, "Crack", Vector3.new(0.6, 0.2, 5 + rng:NextNumber() * 4), at * CFrame.Angles(0, yaw + seg * 0.5, 0) * CFrame.new(0, 0, seg * 4), Corrupt.Glow))
		end
	end
	-- Крупные камни: 6 скоплений по кругу - у каждого точка появления гоблинов.
	local spawns = folder("Spawns", camp)
	for i = 1, 6 do
		local a = (i - 1) / 6 * math.pi * 2 + 0.3
		local rockCF = cf * CFrame.new(math.cos(a) * half * 0.62, 0, math.sin(a) * half * 0.62)
		for piece = 1, 3 do
			local s = (piece == 1) and (9 + rng:NextNumber() * 4) or (4 + rng:NextNumber() * 3)
			local offset = piece == 1 and Vector3.zero or Vector3.new(rng:NextNumber() * 10 - 5, 0, rng:NextNumber() * 10 - 5)
			local rock = box(deco, "BigRock", Vector3.new(s, s * 0.8, s * 0.9), rockCF * CFrame.new(offset + Vector3.new(0, s * 0.35, 0)) * CFrame.Angles(rad(rng:NextNumber() * 16 - 8), rng:NextNumber() * 3, rad(rng:NextNumber() * 16 - 8)),
				piece == 1 and Corrupt.Rock or Corrupt.RockDark)
			if piece == 1 then
				-- светящиеся «жилы» на большом камне
				glow(box(deco, "RockVein", Vector3.new(s * 0.9, 0.4, 0.4), rock.CFrame * CFrame.new(0, s * 0.1, -s * 0.46), Corrupt.Glow), 12)
			end
		end
		-- Точка появления - у камня, со стороны центра лагеря.
		local inward = cf * CFrame.new(math.cos(a) * half * 0.38, 1, math.sin(a) * half * 0.38)
		marker(spawns, "Spawn" .. i, Vector3.new(2, 1, 2), inward, Color3.fromRGB(90, 220, 90))
	end
	-- Мёртвые деревья (кривые стволы из кубов).
	for _, o in { Vector3.new(-half + 10, 0, half - 10), Vector3.new(half - 10, 0, half - 12), Vector3.new(-half + 12, 0, -8), Vector3.new(half - 8, 0, 4) } do
		local tcf = cf * CFrame.new(o) * CFrame.Angles(0, rng:NextNumber() * 3, 0)
		for seg = 0, 3 do
			box(deco, "DeadTrunk", Vector3.new(1.8, 3, 1.8), tcf * CFrame.new(seg * 0.5, 1.5 + seg * 3, 0) * CFrame.Angles(0, 0, rad(-6 * seg)), Corrupt.DeadWood)
		end
		box(deco, "DeadBranch", Vector3.new(6, 1, 1), tcf * CFrame.new(2.4, 10.5, 0) * CFrame.Angles(0, 0, rad(30)), Corrupt.DeadWood)
		box(deco, "DeadBranch", Vector3.new(5, 1, 1), tcf * CFrame.new(-1.2, 9, 0) * CFrame.Angles(0, 0, rad(-35)), Corrupt.DeadWood)
	end
	-- Тотем-обелиск в центре: камень-градиент, светящийся глаз.
	stack(deco, "Obelisk", cf * CFrame.new(0, 0, 4), 5, 5, 18, { Corrupt.RockDark, Corrupt.Rock, Corrupt.Glow:Lerp(Corrupt.Rock, 0.5) }, 5, 0.3)
	glow(box(deco, "ObeliskEye", Vector3.new(2.4, 2.4, 2.4), cf * CFrame.new(0, 19.6, 4) * CFrame.Angles(rad(45), rad(45), 0), Corrupt.Glow), 30)
	-- Вход с табличкой (со стороны города) и ограда из острых камней по краю.
	local gate = cf * CFrame.new(0, 0, -half)
	for _, x in { -11, 11 } do
		stack(deco, "GateStone", gate * CFrame.new(x, 0, 0), 4, 4, 14, { Corrupt.RockDark, Corrupt.Rock }, 3, 0.35)
	end
	box(deco, "Skull", Vector3.new(4, 4, 4), gate * CFrame.new(0, 12, 0), C.White)
	glow(box(deco, "SkullEye", Vector3.new(0.9, 0.9, 0.4), gate * CFrame.new(-0.9, 12.4, -2.1), Corrupt.Glow), 10)
	glow(box(deco, "SkullEye", Vector3.new(0.9, 0.9, 0.4), gate * CFrame.new(0.9, 12.4, -2.1), Corrupt.Glow))
	box(deco, "SkullPost", Vector3.new(1, 10, 1), gate * CFrame.new(0, 5, 0), Corrupt.DeadWood)
	sign(deco, "GoblinSign", "GOBLIN LANDS", Vector3.new(12, 2.6, 0.6), gate * CFrame.new(0, 7, -1.2), Corrupt.Deep, Corrupt.Glow)
	for sideIndex = 0, 3 do
		local sideCF = cf * CFrame.Angles(0, rad(90 * sideIndex), 0)
		for x = -half, half, 7 do
			if not (sideIndex == 0 and math.abs(x) < 16) then
				local h = 3 + rng:NextNumber() * 4
				box(deco, "Spike", Vector3.new(2.6, h, 2.6), sideCF * CFrame.new(x + rng:NextNumber() * 2, h / 2, -half) * CFrame.Angles(rad(rng:NextNumber() * 20 - 10), rng:NextNumber() * 3, 0), Corrupt.RockDark)
			end
		end
	end
	local zone = marker(camp, "Zone", Vector3.new(GOBLIN_SIZE, 30, GOBLIN_SIZE), cf * CFrame.new(0, 13, 0), Color3.fromRGB(255, 70, 70))
	marker(camp, "Marker", Vector3.new(2, 2, 2), cf * CFrame.new(0, 1, -half + 14))
	camp.PrimaryPart = zone
end)

--------------------------------------------------------------------------------
-- 6) ТОЧКИ ВАЛУНОВ (16 шт.) + каменистые пятна из кубов
--------------------------------------------------------------------------------
section("Boulder spots", function()
	local points = Instance.new("Folder")
	points.Name = "RubbleBoulderSpawnPoints"
	points.Parent = workspace
	for index, spot in boulderSpots do
		local p = marker(points, ("Point%02d"):format(index), Vector3.new(4, 1, 4), CFrame.new(spot.Pos + Vector3.new(0, 0.5, 0)), C.StoneDark)
		p:SetAttribute("Tier", spot.Tier)
		box(natureF, "RockPatch", Vector3.new(22, 0.3, 22), CFrame.new(spot.Pos + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, rad(index * 17), 0), C.Grass1:Lerp(C.Stone, 0.4))
		box(natureF, "RockPatch", Vector3.new(14, 0.3, 14), CFrame.new(spot.Pos + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, rad(index * 29), 0), C.Stone)
		for r = 1, 5 do
			local a = r / 5 * math.pi * 2 + rng:NextNumber()
			local s = 1.6 + rng:NextNumber() * 1.6
			box(natureF, "Pebble", Vector3.new(s, s * 0.8, s), CFrame.new(spot.Pos + Vector3.new(math.cos(a) * 11, s * 0.4, math.sin(a) * 11)) * CFrame.Angles(0, rng:NextNumber() * 3, 0), C.Stone:Lerp(C.StoneDark, rng:NextNumber()))
		end
	end
end)

--------------------------------------------------------------------------------
-- 7) ПРИРОДА: кубические деревья, кусты, цветы; у берега - пальмы и ракушки
--------------------------------------------------------------------------------
local function cubeTree(pos, scale)
	local cf = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber() * math.pi, 0)
	box(natureF, "Trunk", Vector3.new(2.4, 7, 2.4) * scale, cf * CFrame.new(0, 3.5 * scale, 0), C.Wood)
	box(natureF, "Leaves", Vector3.new(10, 5, 10) * scale, cf * CFrame.new(0, 9 * scale, 0), C.Leaf1)
	box(natureF, "Leaves", Vector3.new(8, 4, 8) * scale, cf * CFrame.new(0.6 * scale, 12.5 * scale, -0.4 * scale), C.Leaf2)
	box(natureF, "Leaves", Vector3.new(5, 3, 5) * scale, cf * CFrame.new(-0.4 * scale, 15 * scale, 0.5 * scale), C.Leaf3)
	if rng:NextNumber() < 0.3 then -- яблочки
		for _ = 1, 3 do
			box(natureF, "Fruit", Vector3.new(1, 1, 1) * scale, cf * CFrame.new((rng:NextNumber() * 8 - 4) * scale, (8 + rng:NextNumber() * 3) * scale, -5.2 * scale), C.Red)
		end
	end
end
local function palm(pos, scale)
	local lean = CFrame.Angles(rad(rng:NextNumber() * 14 - 7), rng:NextNumber() * math.pi * 2, rad(10))
	local cf = CFrame.new(pos) * lean
	for s = 0, 4 do
		box(natureF, "PalmTrunk", Vector3.new(1.8, 3, 1.8) * scale, cf * CFrame.new(0, (1.5 + s * 3) * scale, 0) * CFrame.Angles(0, rad(s * 12), 0), s % 2 == 0 and C.Wood or C.WoodLight)
	end
	local top = cf * CFrame.new(0, 16 * scale, 0)
	for leaf = 0, 4 do
		box(natureF, "PalmLeaf", Vector3.new(2.4, 0.6, 8) * scale, top * CFrame.Angles(0, leaf / 5 * math.pi * 2, 0) * CFrame.new(0, 0, -4 * scale) * CFrame.Angles(rad(-18), 0, 0), C.Leaf2)
	end
	box(natureF, "Coconut", Vector3.new(1.2, 1.2, 1.2) * scale, top * CFrame.new(0.6 * scale, -0.8 * scale, 0), C.WoodDark)
end

local planted = 0
local tries = 0
while planted < TREE_COUNT and tries < TREE_COUNT * 15 do
	tries += 1
	local a = rng:NextNumber() * math.pi * 2
	local r = math.sqrt(rng:NextNumber()) * COAST
	local pos = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
	if not blocked(pos, 4) then
		cubeTree(pos, 0.8 + rng:NextNumber() * 0.5)
		planted += 1
		if rng:NextNumber() < 0.4 then
			box(natureF, "Bush", Vector3.new(4, 2.6, 4), CFrame.new(pos + Vector3.new(rng:NextNumber() * 10 - 5, 1.3, rng:NextNumber() * 10 - 5)), C.Leaf2)
		end
	end
end
-- Цветочные полянки.
for _ = 1, 70 do
	local a = rng:NextNumber() * math.pi * 2
	local r = math.sqrt(rng:NextNumber()) * COAST
	local pos = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
	if not blocked(pos, 0) then
		for f = 1, 5 do
			local fp = pos + Vector3.new(rng:NextNumber() * 8 - 4, 0.6, rng:NextNumber() * 8 - 4)
			box(natureF, "Flower", Vector3.new(1.2, 1.2, 1.2), CFrame.new(fp), ({ C.Pink, C.Yellow, C.White, C.Purple, C.Red })[(f % 5) + 1])
		end
	end
end
-- Пляж: пальмы, ракушки, камни у воды.
for i = 0, 55 do
	local angle = i / 56 * 360 + rng:NextNumber() * 4
	local p = polar(angle, coastAt(angle) - 20 - rng:NextNumber() * 10, -0.8)
	do
		if i % 3 == 0 then
			palm(p, 0.9 + rng:NextNumber() * 0.4)
		elseif i % 3 == 1 then
			box(natureF, "Shell", Vector3.new(1.4, 0.6, 1.4), CFrame.new(p + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, rng:NextNumber() * 3, 0), ({ C.Pink, C.Cream, C.Orange })[rng:NextInteger(1, 3)])
		else
			local s = 3 + rng:NextNumber() * 3
			box(natureF, "BeachRock", Vector3.new(s, s * 0.7, s), CFrame.new(polar(angle, coastAt(angle) + 4, -1.6 + s * 0.3)) * CFrame.Angles(0, rng:NextNumber() * 3, 0), C.StoneLight)
		end
	end
end

--------------------------------------------------------------------------------
if recording then ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit) end
game:GetService("Selection"):Set({ map })
local parts = 0
for _, d in workspace:GetDescendants() do if d:IsA("BasePart") then parts += 1 end end
print(("[BuildIslandMap] Готово. Тропинки по %d стад, базы на радиусе %d (между соседними ~%d стад), берег ~%d. Точек валунов %d, деревьев %d. Деталей в Workspace: %d. Старое - в ServerStorage.OldMapBackup.")
	:format(ROAD_LENGTH, BASE_RING, math.floor(2 * BASE_RING * math.sin(math.pi / 8) - BASE_SIZE), COAST, #boulderSpots, planted, parts))
