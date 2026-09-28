-- BuildRetroMap: строит НОВУЮ КАРТУ в стиле ретро-Roblox (старые пластиковые
-- стады, яркие цвета, блочные формы, градиенты из партов). Вставь целиком в
-- Command Bar Studio и нажми Enter. Ctrl+Z откатывает всё одним шагом.
--
-- ЧТО СТРОИТСЯ (и что из этого читает код игры):
--   • Мини-город в центре: площадь с фонтаном-монументом (гигантский
--     кристалл + скрещённые кирки), РЫНОК ШАХТЁРОВ (модель с атрибутом
--     IsBank: Building + SellZone + MerchantSpot - там продают руду и стоит
--     торговец), 5 домиков, часовая башня, хижина смотрителя островов
--     (IslandKeeperMarker), табло лайков (LikeGoalBoard), фонари, заборчики.
--   • 8 баз игроков по кругу (Workspace.PlotOrigins: Plot1..Plot8 + PlotNLook,
--     лицом к городу) с огромным расстоянием между ними.
--   • 8 тропинок от города к каждой базе - ОДИНАКОВОЙ длины и формы.
--   • Территория гоблинов (Workspace.GoblinCamp: Zone + Spawns + Marker) -
--     частокол, шатры, костёр, тотем, вышка.
--   • 16 точек валунов (Workspace.RubbleBoulderSpawnPoints, атрибут Tier:
--     ближе к городу - слабые, дальше - сильные).
--   • Поле с градиентом травы, деревья, камни, цветы, горы по краю карты
--     и невидимая стена.
--
-- СТАРОЕ НЕ УДАЛЯЕТСЯ: прежние PlotOrigins / GoblinCamp /
-- RubbleBoulderSpawnPoints / Baseplate / RetroMap и модели с IsBank
-- переносятся в ServerStorage.OldMapBackup.
--
-- Размеры меняются в первых строках. BASE_SIZE - сторона квадрата твоей
-- базы (PlotTemplate) в стадах; от неё считаются расстояния.
local BASE_SIZE = 240        -- сторона базы игрока (под твой PlotTemplate)
local BASE_RING = 800        -- радиус круга баз (центр карты -> центр базы)
local PLOT_Y = 0.5           -- высота точки PlotOrigins (центр PlotPad толщиной 1)
local TOWN_RADIUS = 125      -- радиус города
local GOBLIN_ANGLE = 22.5    -- направление лагеря гоблинов (между базами 1 и 2)
local GOBLIN_RADIUS = 340    -- расстояние лагеря от центра
local GOBLIN_SIZE = 130      -- сторона территории гоблинов
local TREE_COUNT = 420
local SEED = 20260928

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ServerStorage = game:GetService("ServerStorage")
local recording = ChangeHistoryService:TryBeginRecording("BuildRetroMap")
local rng = Random.new(SEED)

local MAP_RADIUS = BASE_RING + BASE_SIZE * 0.75 + 190
local rad = math.rad

--------------------------------------------------------------------------------
-- ПАЛИТРА (классические BrickColor-цвета старого Roblox)
--------------------------------------------------------------------------------
local C = {
	Grass1 = Color3.fromRGB(75, 151, 75),    -- Bright green
	Grass2 = Color3.fromRGB(90, 160, 70),
	Grass3 = Color3.fromRGB(120, 144, 76),   -- Olive-ish к краю
	Dirt = Color3.fromRGB(160, 110, 70),
	DirtLight = Color3.fromRGB(204, 142, 105),
	Sand = Color3.fromRGB(215, 197, 154),    -- Brick yellow
	Stone = Color3.fromRGB(163, 162, 165),   -- Medium stone grey
	StoneDark = Color3.fromRGB(99, 95, 98),  -- Dark stone grey
	White = Color3.fromRGB(242, 243, 243),
	Red = Color3.fromRGB(196, 40, 28),       -- Bright red
	Blue = Color3.fromRGB(13, 105, 172),     -- Bright blue
	Yellow = Color3.fromRGB(245, 205, 48),   -- Bright yellow
	Orange = Color3.fromRGB(218, 133, 65),   -- Bright orange
	Wood = Color3.fromRGB(124, 92, 70),      -- Brown
	WoodDark = Color3.fromRGB(86, 66, 54),
	Leaf1 = Color3.fromRGB(39, 70, 45),      -- Earth green
	Leaf2 = Color3.fromRGB(75, 151, 75),
	Leaf3 = Color3.fromRGB(161, 196, 140),
	Water1 = Color3.fromRGB(13, 105, 172),
	Water2 = Color3.fromRGB(128, 187, 219),
	Crystal = Color3.fromRGB(0, 255, 255),
	Snow = Color3.fromRGB(248, 248, 248),
	Mud = Color3.fromRGB(98, 71, 50),
	MudDark = Color3.fromRGB(60, 45, 35),
	Purple = Color3.fromRGB(107, 50, 124),
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
for _, name in { "RetroMap", "PlotOrigins", "GoblinCamp", "RubbleBoulderSpawnPoints", "Baseplate", "LikeGoalBoard", "IslandKeeperMarker", "IslandKeeperMarkerLook" } do
	local old = workspace:FindFirstChild(name)
	if old then old.Parent = backup end
end
for _, inst in workspace:GetDescendants() do
	if inst:IsA("Model") and inst:GetAttribute("IsBank") and inst.Parent then inst.Parent = backup end
end

local map = Instance.new("Model")
map.Name = "RetroMap"
map.Parent = workspace
local function folder(name, parent)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent or map
	return f
end
local groundF = folder("Ground")
local roadsF = folder("Roads")
local townF = folder("Town")
local natureF = folder("Nature")
local mountainsF = folder("Mountains")
local basesF = folder("BaseClearings")

--------------------------------------------------------------------------------
-- ДЕТАЛИ
--------------------------------------------------------------------------------
local function studs(p)
	p.Material = Enum.Material.Plastic
	p.TopSurface = Enum.SurfaceType.Studs
	p.BottomSurface = Enum.SurfaceType.Inlet
	return p
end

local function box(parent, name, size, cf, color, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	studs(p)
	for k, v in props or {} do p[k] = v end
	p.Parent = parent
	return p
end

local function wedge(parent, name, size, cf, color)
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	studs(p)
	p.Parent = parent
	return p
end

local function cylinder(parent, name, height, diameter, cf, color, props)
	-- Цилиндр в Roblox лежит вдоль X - ставим его «на попа».
	return box(parent, name, Vector3.new(height, diameter, diameter), cf * CFrame.Angles(0, 0, rad(90)), color, props)
end

local function ball(parent, name, d, cf, color)
	return box(parent, name, Vector3.new(d, d, d), cf, color, { Shape = Enum.PartType.Ball })
end

local function neon(p, light, range)
	p.Material = Enum.Material.Neon
	if light then
		local l = Instance.new("PointLight")
		l.Color = p.Color
		l.Range = range or 14
		l.Brightness = 1.4
		l.Parent = p
	end
	return p
end

-- Башенка-градиент: steps слоёв снизу вверх, цвет по палитре, сужение taper.
local function gradientStack(parent, name, baseCF, width, depth, height, colors, steps, taper)
	local layer = height / steps
	for i = 1, steps do
		local t = (i - 1) / math.max(1, steps - 1)
		local k = 1 - (taper or 0) * t
		box(parent, name .. i, Vector3.new(width * k, layer, depth * k),
			baseCF * CFrame.new(0, layer * (i - 0.5), 0), lerpColors(colors, t))
	end
end

-- Табличка с текстом (SurfaceGui, ретро-шрифт).
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
		label.FontFace = Font.fromEnum(Enum.Font.Arcade)
		label.TextScaled = true
		label.TextColor3 = fg or C.White
		label.TextStrokeTransparency = 0
		label.Text = text
		label.Parent = gui
	end
	return board
end

local function marker(parent, name, size, cf, color)
	return box(parent, name, size, cf, color or C.Yellow, {
		Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false,
		Material = Enum.Material.SmoothPlastic, TopSurface = Enum.SurfaceType.Smooth, BottomSurface = Enum.SurfaceType.Smooth,
	})
end

local function polar(angleDeg, radius, y)
	local a = rad(angleDeg)
	return Vector3.new(math.sin(a) * radius, y or 0, -math.cos(a) * radius)
end

--------------------------------------------------------------------------------
-- РАСКЛАДКА: базы, дороги, валуны, лагерь
--------------------------------------------------------------------------------
local baseAngles, basePositions = {}, {}
for i = 1, 8 do
	baseAngles[i] = (i - 1) * 45
	basePositions[i] = polar(baseAngles[i], BASE_RING)
end
local goblinCenter = polar(GOBLIN_ANGLE, GOBLIN_RADIUS)

-- Одна форма дороги на все 8 (повёрнутая копия) - поэтому длина одинаковая.
local ROAD_START = TOWN_RADIUS - 8
local ROAD_END = BASE_RING - BASE_SIZE / 2 - 24
local roadShape = {}
do
	local step = 22
	local d = ROAD_START
	while d <= ROAD_END do
		-- лёгкое петляние, затухающее к концам (въезд в город и базу прямой)
		local fade = math.sin(math.clamp((d - ROAD_START) / (ROAD_END - ROAD_START), 0, 1) * math.pi)
		table.insert(roadShape, { D = d, Side = math.sin(d / 55) * 16 * fade })
		d += step
	end
	table.insert(roadShape, { D = ROAD_END + 10, Side = 0 })
end
local function roadPoint(angleDeg, entry)
	local forward = polar(angleDeg, 1)
	local right = Vector3.new(-forward.Z, 0, forward.X)
	return forward * entry.D + right * entry.Side
end

-- Точки валунов: в секторах между дорогами. Ближние (слабые) и дальние (сильные).
local boulderSpots = {}
for k = 0, 7 do
	local angle = 22.5 + k * 45
	if k ~= 0 or math.abs(((angle - GOBLIN_ANGLE + 180) % 360) - 180) > 10 then
		table.insert(boulderSpots, { Pos = polar(angle - 6, 250), Tier = 0 })
		table.insert(boulderSpots, { Pos = polar(angle + 7, 540), Tier = 0 })
	else
		table.insert(boulderSpots, { Pos = polar(angle - 12, 600), Tier = 0 })
		table.insert(boulderSpots, { Pos = polar(angle + 12, 620), Tier = 0 })
	end
end
table.sort(boulderSpots, function(a, b) return a.Pos.Magnitude < b.Pos.Magnitude end)
for index, spot in boulderSpots do
	-- 16 точек: ближние 8 -> тиры 1-4, дальние 8 -> 5-9.
	spot.Tier = index <= 8 and (((index - 1) % 4) + 1) or (((index - 9) % 5) + 5)
end

local function distanceToRoad(pos)
	local best = math.huge
	for i = 1, 8 do
		local dir = polar(baseAngles[i], 1)
		local along = pos:Dot(dir)
		if along > ROAD_START - 20 and along < ROAD_END + 20 then
			local perp = (pos - dir * along).Magnitude
			best = math.min(best, perp)
		end
	end
	return best
end

local function blocked(pos, margin)
	margin = margin or 0
	local flat = Vector3.new(pos.X, 0, pos.Z)
	if flat.Magnitude < TOWN_RADIUS + 25 + margin then return true end
	if flat.Magnitude > MAP_RADIUS - 70 then return true end
	for i = 1, 8 do
		if (flat - basePositions[i]).Magnitude < BASE_SIZE * 0.78 + margin then return true end
	end
	if distanceToRoad(flat) < 34 + margin then return true end
	if (flat - goblinCenter).Magnitude < GOBLIN_SIZE * 0.8 + margin then return true end
	for _, spot in boulderSpots do
		if (flat - spot.Pos).Magnitude < 22 + margin then return true end
	end
	return false
end

--------------------------------------------------------------------------------
-- 1) ЗЕМЛЯ: плиты с радиальным градиентом травы
--------------------------------------------------------------------------------
do
	local tile = 128
	local n = math.ceil(MAP_RADIUS / tile) + 1
	for x = -n, n do
		for z = -n, n do
			local center = Vector3.new(x * tile, 0, z * tile)
			if center.Magnitude <= MAP_RADIUS + tile then
				local t = center.Magnitude / MAP_RADIUS
				local color = lerpColors({ C.Grass2, C.Grass1, C.Grass3 }, t)
				-- лёгкая «шахматка» - ретро-вид и видно масштаб
				if (x + z) % 2 == 0 then color = color:Lerp(Color3.new(0, 0, 0), 0.05) end
				box(groundF, "Grass", Vector3.new(tile, 4, tile), CFrame.new(center + Vector3.new(0, -2, 0)), color)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- 2) ДОРОГИ: земляная середина + светлые края-градиент + камушки
--------------------------------------------------------------------------------
for i = 1, 8 do
	local angle = baseAngles[i]
	local road = folder("Road" .. i, roadsF)
	for s = 1, #roadShape - 1 do
		local a = roadPoint(angle, roadShape[s])
		local b = roadPoint(angle, roadShape[s + 1])
		local mid = (a + b) / 2
		local length = (b - a).Magnitude + 3
		local cf = CFrame.lookAt(mid, b) -- Z вдоль дороги
		box(road, "RoadEdge", Vector3.new(26, 0.3, length), cf * CFrame.new(0, 0.15, 0), C.Sand)
		box(road, "RoadMid", Vector3.new(20, 0.3, length), cf * CFrame.new(0, 0.3, 0), C.DirtLight)
		box(road, "RoadCore", Vector3.new(13, 0.3, length), cf * CFrame.new(0, 0.45, 0), C.Dirt)
		if s % 3 == 0 then
			local side = (s % 2 == 0) and 15 or -15
			box(road, "Pebble", Vector3.new(2, 1, 2), cf * CFrame.new(side, 0.5, 0) * CFrame.Angles(0, rng:NextNumber() * 3, 0), C.Stone)
		end
	end
	-- Указатель у въезда в город.
	local entry = roadPoint(angle, roadShape[2])
	local forward = polar(angle, 1)
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local post = entry + right * 18
	box(road, "SignPost", Vector3.new(1, 9, 1), CFrame.new(post + Vector3.new(0, 4.5, 0)), C.WoodDark)
	sign(road, "BaseSign", "BASE " .. i .. "  >>", Vector3.new(9, 3, 0.6),
		CFrame.lookAt(post + Vector3.new(0, 8, 0), post + Vector3.new(0, 8, 0) + right), C.Wood, C.Yellow)
	-- Фонари вдоль дороги (каждые ~150 стад), по очереди с разных сторон.
	local lampEvery = 7
	for s = lampEvery, #roadShape - 2, lampEvery do
		local p = roadPoint(angle, roadShape[s])
		local side = (s // lampEvery) % 2 == 0 and 17 or -17
		local at = p + right * side
		box(road, "LampPole", Vector3.new(1, 12, 1), CFrame.new(at + Vector3.new(0, 6, 0)), C.StoneDark)
		neon(box(road, "LampLight", Vector3.new(2.4, 2.4, 2.4), CFrame.new(at + Vector3.new(0, 13, 0)), C.Yellow), true, 22)
	end
end

--------------------------------------------------------------------------------
-- 3) БАЗЫ: PlotOrigins + поляны-градиенты под базами
--------------------------------------------------------------------------------
local origins = Instance.new("Folder")
origins.Name = "PlotOrigins"
origins.Parent = workspace
for i = 1, 8 do
	local pos = basePositions[i]
	local cf = CFrame.lookAt(pos, Vector3.new(0, 0, 0)) -- лицом к городу
	-- Поляна: три вложенных квадрата-ступеньки (градиент к центру).
	local ring = { C.Grass1:Lerp(C.Sand, 0.25), C.Grass1:Lerp(C.Sand, 0.5), C.Sand:Lerp(C.White, 0.15) }
	for step = 1, 3 do
		local side = BASE_SIZE + 60 - (step - 1) * 24
		box(basesF, "Clearing" .. i, Vector3.new(side, 0.2, side), cf * CFrame.new(0, 0.1 * step, 0), ring[step])
	end
	-- Флажки по углам поляны.
	for _, corner in { Vector3.new(1, 0, 1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, -1) } do
		local at = cf * CFrame.new(corner * (BASE_SIZE / 2 + 26))
		box(basesF, "FlagPole", Vector3.new(0.8, 14, 0.8), at * CFrame.new(0, 7, 0), C.White)
		box(basesF, "Flag", Vector3.new(0.3, 3, 5), at * CFrame.new(0, 12.5, 2.6), i % 2 == 0 and C.Red or C.Blue)
	end
	local origin = marker(origins, "Plot" .. i, Vector3.new(4, 1, 4), CFrame.lookAt(pos + Vector3.new(0, PLOT_Y, 0), Vector3.new(0, PLOT_Y, 0)), C.Red)
	origin.Transparency = 0.5
	local look = marker(origins, "Plot" .. i .. "Look", Vector3.new(2, 2, 2), CFrame.new(Vector3.new(0, PLOT_Y, 0):Lerp(pos + Vector3.new(0, PLOT_Y, 0), 0.9)), C.Yellow)
	look.Transparency = 0.5
end

--------------------------------------------------------------------------------
-- 4) ГОРОД
--------------------------------------------------------------------------------
-- Площадь: круг из шахматных плит (два оттенка камня) + бордюр.
do
	local cell = 12
	local r = TOWN_RADIUS - 10
	for x = -math.ceil(r / cell), math.ceil(r / cell) do
		for z = -math.ceil(r / cell), math.ceil(r / cell) do
			local c = Vector3.new(x * cell, 0, z * cell)
			if c.Magnitude <= r then
				local t = c.Magnitude / r
				local color = ((x + z) % 2 == 0) and C.Stone or C.White:Lerp(C.Stone, 0.35)
				color = color:Lerp(C.Sand, t * 0.35)
				box(townF, "PlazaTile", Vector3.new(cell, 0.4, cell), CFrame.new(c + Vector3.new(0, 0.2, 0)), color)
			end
		end
	end
	-- Низкий заборчик по краю города, с проходами под 8 дорог.
	local segments = 64
	for s = 0, segments - 1 do
		local angle = s * 360 / segments
		local nearRoad = false
		for i = 1, 8 do
			if math.abs(((angle - baseAngles[i] + 180) % 360) - 180) < 8 then nearRoad = true end
		end
		if not nearRoad then
			local p = polar(angle, TOWN_RADIUS)
			local length = 2 * math.pi * TOWN_RADIUS / segments + 0.5
			local cf = CFrame.lookAt(p, Vector3.zero) -- X - по касательной к кругу
			box(townF, "Fence", Vector3.new(length, 1, 0.6), cf * CFrame.new(0, 2.5, 0), C.White)
			box(townF, "Fence", Vector3.new(length, 1, 0.6), cf * CFrame.new(0, 1.2, 0), C.White)
			box(townF, "FencePost", Vector3.new(1, 4, 1), cf * CFrame.new(length / 2, 2, 0), C.WoodDark)
		end
	end
end

-- ЦЕНТР: фонтан-монумент (чаши с водой-градиентом, гигантский кристалл,
-- скрещённые кирки) - видно с любой базы.
do
	local center = CFrame.new(0, 0.4, 0)
	cylinder(townF, "FountainBase", 1.6, 40, center * CFrame.new(0, 0.8, 0), C.StoneDark)
	cylinder(townF, "FountainRim", 2.4, 36, center * CFrame.new(0, 2.8, 0), C.Stone)
	neon(cylinder(townF, "FountainWater", 0.6, 32, center * CFrame.new(0, 3.9, 0), C.Water2))
	cylinder(townF, "FountainPillar", 8, 8, center * CFrame.new(0, 7, 0), C.White)
	cylinder(townF, "FountainBowl", 1.4, 18, center * CFrame.new(0, 11.4, 0), C.Stone)
	neon(cylinder(townF, "FountainWater2", 0.5, 15, center * CFrame.new(0, 12.3, 0), C.Water2))
	-- Кристалл: столбы-градиент от синего к бирюзовому неону.
	local crystalColors = { C.Water1, C.Crystal, C.White }
	for i, spec in ipairs({ { 0, 0, 6, 26, 0 }, { 4, 2, 3.5, 16, 18 }, { -4, -1, 3.5, 14, -20 }, { 1, -4, 3, 12, 12 }, { -2, 4, 3, 11, -14 } }) do
		local x, z, w, h, tilt = spec[1], spec[2], spec[3], spec[4], spec[5]
		local base = center * CFrame.new(x, 13, z) * CFrame.Angles(rad(tilt), rad(i * 37), rad(tilt * 0.6))
		for layer = 1, 4 do
			local t = (layer - 1) / 3
			local k = 1 - t * 0.55
			local part = box(townF, "Crystal", Vector3.new(w * k, h / 4, w * k), base * CFrame.new(0, h / 4 * (layer - 0.5), 0), lerpColors(crystalColors, t))
			part.Material = Enum.Material.Glass
			part.Transparency = 0.15
			if layer == 4 then neon(part, true, 30) end
		end
	end
	-- Скрещённые кирки у подножия кристалла.
	for _, yaw in { 45, -45 } do
		local cf = center * CFrame.new(0, 20, 0) * CFrame.Angles(0, rad(yaw), rad(35))
		box(townF, "PickHandle", Vector3.new(1.4, 22, 1.4), cf, C.Wood)
		local head = cf * CFrame.new(0, 11, 0)
		box(townF, "PickHead", Vector3.new(12, 2, 2), head, C.StoneDark)
		wedge(townF, "PickTip", Vector3.new(2, 2, 4), head * CFrame.new(7, 0, 0) * CFrame.Angles(0, rad(-90), 0), C.Stone)
		wedge(townF, "PickTip", Vector3.new(2, 2, 4), head * CFrame.new(-7, 0, 0) * CFrame.Angles(0, rad(90), 0), C.Stone)
	end
	sign(townF, "TownSign", "MINER TOWN", Vector3.new(24, 5, 1), center * CFrame.new(0, 6, 21), C.Red, C.Yellow)
end

-- Домик: стены-градиент, двускатная крыша, дверь, окна-неон, труба, клумба.
local function house(cf, w, d, h, wallColor, roofColor, name)
	local model = Instance.new("Model")
	model.Name = name or "House"
	model.Parent = townF
	gradientStack(model, "Wall", cf, w, d, h, { wallColor:Lerp(Color3.new(0, 0, 0), 0.25), wallColor, wallColor:Lerp(C.White, 0.2) }, 4, 0)
	-- Крыша: два клина.
	local roofH = h * 0.55
	-- У WedgePart высокий край сзади (+Z): половинка на +Z развёрнута к конику.
	wedge(model, "Roof", Vector3.new(w + 2, roofH, d / 2 + 1), cf * CFrame.new(0, h + roofH / 2, d / 4 + 0.5) * CFrame.Angles(0, rad(180), 0), roofColor)
	wedge(model, "Roof", Vector3.new(w + 2, roofH, d / 2 + 1), cf * CFrame.new(0, h + roofH / 2, -d / 4 - 0.5), roofColor)
	box(model, "RoofRidge", Vector3.new(w + 2.4, 0.8, 1.4), cf * CFrame.new(0, h + roofH, 0), roofColor:Lerp(Color3.new(0, 0, 0), 0.3))
	-- Дверь и окна на лицевой стороне (-Z).
	box(model, "Door", Vector3.new(4, 7, 0.4), cf * CFrame.new(0, 3.5, -d / 2 - 0.2), C.WoodDark)
	neon(box(model, "DoorKnob", Vector3.new(0.5, 0.5, 0.5), cf * CFrame.new(1.3, 3.5, -d / 2 - 0.5), C.Yellow))
	for _, x in { -w / 2 + 3.5, w / 2 - 3.5 } do
		local win = box(model, "Window", Vector3.new(3.4, 3.4, 0.4), cf * CFrame.new(x, h * 0.55, -d / 2 - 0.2), C.Yellow:Lerp(C.White, 0.4))
		neon(win)
		box(model, "WindowFrame", Vector3.new(4.2, 0.6, 0.6), cf * CFrame.new(x, h * 0.55 - 2, -d / 2 - 0.3), C.White)
		box(model, "FlowerBox", Vector3.new(4, 1, 1.2), cf * CFrame.new(x, h * 0.55 - 2.6, -d / 2 - 0.8), C.Wood)
		box(model, "Flowers", Vector3.new(3.6, 0.8, 0.8), cf * CFrame.new(x, h * 0.55 - 1.8, -d / 2 - 0.8), (x > 0) and C.Red or C.Yellow)
	end
	box(model, "Chimney", Vector3.new(2.4, roofH + 3, 2.4), cf * CFrame.new(w / 3, h + roofH / 2 + 1.5, d / 5), C.Red:Lerp(C.StoneDark, 0.3))
	box(model, "Step", Vector3.new(6, 0.6, 2.4), cf * CFrame.new(0, 0.3, -d / 2 - 1.4), C.Stone)
	return model
end

-- Здания стоят в промежутках между въездами дорог (углы 22.5 + 45k).
local function gapCFrame(k, radius)
	local angle = 22.5 + k * 45
	local p = polar(angle, radius, 0.4)
	return CFrame.lookAt(p, Vector3.new(0, 0.4, 0)) -- лицом к площади
end

-- РЫНОК ШАХТЁРОВ (банк). Код игры ищет модель с атрибутом IsBank:
-- Building (здание), SellZone (квадрат продажи), MerchantSpot (торговец).
do
	local cf = gapCFrame(2, 78)
	local market = Instance.new("Model")
	market.Name = "MinersMarket"
	market:SetAttribute("IsBank", true)
	market.Parent = townF
	local building = box(market, "Building", Vector3.new(34, 16, 20), cf * CFrame.new(0, 8, 8), C.Sand)
	gradientStack(market, "MarketWall", cf * CFrame.new(0, 0, 8), 34.4, 20.4, 5, { C.StoneDark, C.Stone }, 2, 0)
	-- Полосатый навес (красно-белый) на всю длину.
	for s = 0, 7 do
		wedge(market, "Awning", Vector3.new(34 / 8, 3, 7), cf * CFrame.new(-17 + 34 / 16 + s * 34 / 8, 13, -5.5), s % 2 == 0 and C.Red or C.White)
	end
	sign(market, "MarketSign", "MINER'S MARKET", Vector3.new(26, 4.5, 0.8), cf * CFrame.new(0, 19, -2.2), C.Blue, C.Yellow)
	-- Прилавки с кучками руды.
	for _, x in { -12, 0, 12 } do
		box(market, "Stall", Vector3.new(8, 3, 3), cf * CFrame.new(x, 1.5, -3.5), C.Wood)
		for o = 1, 3 do
			local color = ({ C.Crystal, C.Yellow, C.Red, C.Purple })[((x // 6) + o) % 4 + 1]
			neon(box(market, "OrePile", Vector3.new(1.4, 1.4, 1.4), cf * CFrame.new(x - 3 + o * 1.8, 3.7, -3.5) * CFrame.Angles(rad(o * 20), rad(o * 33), 0), color))
		end
	end
	-- Зона продажи: квадрат перед рынком (светится жёлтым), с рамкой.
	local ZONE = 24
	local zoneCF = cf * CFrame.new(0, 0.3, -6 - 4 - ZONE / 2)
	local zone = box(market, "SellZone", Vector3.new(ZONE, 0.6, ZONE), zoneCF, C.Yellow, {
		Transparency = 0.55, CanCollide = false, Material = Enum.Material.Neon,
		TopSurface = Enum.SurfaceType.Smooth, BottomSurface = Enum.SurfaceType.Smooth,
	})
	local _ = zone
	for _, spec in { { Vector3.new(ZONE + 1, 0.8, 0.8), Vector3.new(0, 0.2, ZONE / 2) }, { Vector3.new(ZONE + 1, 0.8, 0.8), Vector3.new(0, 0.2, -ZONE / 2) },
		{ Vector3.new(0.8, 0.8, ZONE + 1), Vector3.new(ZONE / 2, 0.2, 0) }, { Vector3.new(0.8, 0.8, ZONE + 1), Vector3.new(-ZONE / 2, 0.2, 0) } } do
		neon(box(market, "SellZoneEdge", spec[1], zoneCF * CFrame.new(spec[2]), C.Orange), false)
	end
	sign(market, "SellSign", "SELL ORE HERE", Vector3.new(14, 3, 0.6), zoneCF * CFrame.new(0, 7, ZONE / 2 + 0.5), C.Red, C.White)
	for _, x in { -ZONE / 2 - 1, ZONE / 2 + 1 } do
		box(market, "SignPost", Vector3.new(1, 8, 1), zoneCF * CFrame.new(x * 0.55, 4, ZONE / 2 + 0.5), C.WoodDark)
	end
	-- Торговец - справа за краем зоны продажи.
	marker(market, "MerchantSpot", Vector3.new(2, 1, 2), zoneCF * CFrame.new(ZONE / 2 + 8, 0.2, 0))
	box(market, "MerchantRug", Vector3.new(8, 0.2, 8), zoneCF * CFrame.new(ZONE / 2 + 8, 0, 0), C.Purple)
	market.PrimaryPart = building
end

-- Домики (в них «живут люди»), разные цвета и размеры.
house(gapCFrame(3, 84), 18, 14, 11, C.White, C.Red, "HouseRed")
house(gapCFrame(4, 88), 20, 16, 12, C.Sand, C.Blue, "HouseBlue")
house(gapCFrame(5, 84), 16, 14, 10, C.Orange:Lerp(C.White, 0.5), C.Leaf1, "HouseGreen")
house(gapCFrame(6, 88), 22, 16, 13, C.White, C.Purple, "HousePurple")
house(gapCFrame(7, 84), 18, 14, 11, C.Sand:Lerp(C.White, 0.4), C.Orange, "HouseOrange")

-- Часовая башня (ориентир) - между дорогами 2 и 3.
do
	local cf = gapCFrame(1, 86)
	local tower = Instance.new("Model")
	tower.Name = "ClockTower"
	tower.Parent = townF
	gradientStack(tower, "Tower", cf, 12, 12, 44, { C.StoneDark, C.Stone, C.White }, 8, 0.15)
	neon(box(tower, "ClockFace", Vector3.new(7, 7, 0.6), cf * CFrame.new(0, 36, -5.6), C.White), true, 25)
	box(tower, "HandHour", Vector3.new(0.6, 2.6, 0.4), cf * CFrame.new(0, 37, -6), C.StoneDark)
	box(tower, "HandMinute", Vector3.new(3.4, 0.5, 0.4), cf * CFrame.new(1.2, 36, -6), C.StoneDark)
	wedge(tower, "Spire", Vector3.new(11, 12, 5.5), cf * CFrame.new(0, 50, -2.75), C.Red)
	wedge(tower, "Spire", Vector3.new(11, 12, 5.5), cf * CFrame.new(0, 50, 2.75) * CFrame.Angles(0, rad(180), 0), C.Red)
	neon(ball(tower, "SpireLight", 2.4, cf * CFrame.new(0, 57, 0), C.Yellow), true, 30)
end

-- Хижина смотрителя островов (IslandKeeperMarker) - между дорогами 1 и 2.
do
	local cf = gapCFrame(0, 84)
	house(cf, 14, 12, 9, C.Wood:Lerp(C.Sand, 0.4), C.Water1, "IslandKeeperHut")
	local spot = cf * CFrame.new(0, 0.5, -11)
	marker(workspace, "IslandKeeperMarker", Vector3.new(2, 1, 2), spot)
	marker(workspace, "IslandKeeperMarkerLook", Vector3.new(1, 1, 1), CFrame.new(Vector3.new(0, spot.Position.Y, 0)))
	sign(townF, "IslandSign", "ISLANDS", Vector3.new(9, 2.4, 0.5), cf * CFrame.new(0, 12.5, -6.4), C.Water1, C.White)
end

-- Табло лайков (LikeGoalBoard): лицом к площади, у фонтана.
do
	local pos = polar(200, 44, 9)
	local board = box(workspace, "LikeGoalBoard", Vector3.new(16, 10, 1), CFrame.lookAt(pos, Vector3.new(0, 9, 0)), C.StoneDark)
	local _ = board
	for _, x in { -7, 7 } do
		box(townF, "BoardLeg", Vector3.new(1, 5, 1), CFrame.lookAt(pos, Vector3.new(0, 9, 0)) * CFrame.new(x, -7.5, 0), C.WoodDark)
	end
end

-- Фонари по кругу площади + лавочки.
for s = 0, 15 do
	local angle = s * 22.5 + 11.25
	local at = polar(angle, TOWN_RADIUS - 22)
	box(townF, "LampPole", Vector3.new(1, 10, 1), CFrame.new(at + Vector3.new(0, 5, 0)), C.StoneDark)
	neon(box(townF, "LampLight", Vector3.new(2.2, 2.2, 2.2), CFrame.new(at + Vector3.new(0, 11, 0)), C.Yellow:Lerp(C.White, 0.3)), true, 20)
	if s % 2 == 0 then
		local cf = CFrame.lookAt(polar(angle, TOWN_RADIUS - 32, 0.4), Vector3.new(0, 0.4, 0))
		box(townF, "BenchSeat", Vector3.new(6, 0.6, 2), cf * CFrame.new(0, 1.6, 0), C.Wood)
		box(townF, "BenchBack", Vector3.new(6, 2, 0.5), cf * CFrame.new(0, 2.8, 1), C.Wood)
		box(townF, "BenchLeg", Vector3.new(0.6, 1.4, 1.6), cf * CFrame.new(-2.5, 0.7, 0), C.StoneDark)
		box(townF, "BenchLeg", Vector3.new(0.6, 1.4, 1.6), cf * CFrame.new(2.5, 0.7, 0), C.StoneDark)
	end
end

--------------------------------------------------------------------------------
-- 5) ТЕРРИТОРИЯ ГОБЛИНОВ (GoblinCamp: Zone + Spawns + Marker)
--------------------------------------------------------------------------------
do
	local camp = Instance.new("Model")
	camp.Name = "GoblinCamp"
	camp.Parent = workspace
	local cf = CFrame.lookAt(goblinCenter, Vector3.zero) -- вход смотрит на город
	local deco = folder("Decor", camp)
	-- Земля лагеря: грязь-градиент (вложенные квадраты темнее к центру).
	for step = 1, 4 do
		local side = GOBLIN_SIZE + 30 - (step - 1) * 22
		box(deco, "Mud", Vector3.new(side, 0.2, side), cf * CFrame.new(0, 0.1 * step, 0),
			lerpColors({ C.Grass1:Lerp(C.Mud, 0.5), C.Mud, C.MudDark }, (step - 1) / 3))
	end
	-- Частокол по периметру, проход со стороны города.
	local half = GOBLIN_SIZE / 2
	local spacing = 3.2
	for sideIndex = 0, 3 do
		local sideCF = cf * CFrame.Angles(0, rad(90 * sideIndex), 0)
		for x = -half, half, spacing do
			local isGate = sideIndex == 0 and math.abs(x) < 12
			if not isGate then
				local h = 9 + rng:NextNumber() * 3
				local log = box(deco, "Palisade", Vector3.new(2.6, h, 2.6), sideCF * CFrame.new(x, h / 2, -half), C.WoodDark:Lerp(C.Wood, rng:NextNumber()))
				wedge(deco, "PalisadeTip", Vector3.new(2.6, 2, 1.3), log.CFrame * CFrame.new(0, h / 2 + 1, -0.65) * CFrame.Angles(0, rad(180), 0), C.Wood)
			end
		end
	end
	-- Ворота-арка с черепом.
	local gate = cf * CFrame.new(0, 0, -half)
	for _, x in { -13, 13 } do box(deco, "GatePost", Vector3.new(3, 18, 3), gate * CFrame.new(x, 9, 0), C.WoodDark) end
	box(deco, "GateBeam", Vector3.new(30, 2.4, 3), gate * CFrame.new(0, 17, 0), C.Wood)
	ball(deco, "Skull", 4, gate * CFrame.new(0, 20.5, 0), C.White)
	neon(box(deco, "SkullEyeL", Vector3.new(0.8, 0.8, 0.4), gate * CFrame.new(-0.8, 20.8, -1.9), C.Red), true, 10)
	neon(box(deco, "SkullEyeR", Vector3.new(0.8, 0.8, 0.4), gate * CFrame.new(0.8, 20.8, -1.9), C.Red))
	sign(deco, "GoblinSign", "GOBLIN LANDS", Vector3.new(16, 3, 0.6), gate * CFrame.new(0, 13.5, -1.8), C.MudDark, C.Red)
	-- Шатры по краям (не в центре - там гоблины бегают).
	for _, spec in { { -40, 40 }, { 40, 40 }, { -45, -10 }, { 45, -10 }, { 0, 48 } } do
		local tcf = cf * CFrame.new(spec[1], 0, spec[2]) * CFrame.Angles(0, rad(rng:NextNumber() * 360), 0)
		local color = ({ C.Leaf1, C.Mud, C.Purple, C.WoodDark })[rng:NextInteger(1, 4)]
		wedge(deco, "Tent", Vector3.new(12, 9, 7), tcf * CFrame.new(0, 4.5, 3.5) * CFrame.Angles(0, rad(180), 0), color)
		wedge(deco, "Tent", Vector3.new(12, 9, 7), tcf * CFrame.new(0, 4.5, -3.5), color:Lerp(Color3.new(0, 0, 0), 0.2))
	end
	-- Костёр в центре (огонь-градиент из неоновых кубиков) + брёвна.
	local fire = cf * CFrame.new(0, 0.4, 8)
	for a = 0, 5 do
		box(deco, "FireStone", Vector3.new(2, 1.4, 2), fire * CFrame.Angles(0, rad(a * 60), 0) * CFrame.new(4, 0.7, 0), C.StoneDark)
	end
	for layer, color in ipairs({ C.Red, C.Orange, C.Yellow }) do
		local s = 4 - layer
		local flame = neon(box(deco, "Flame", Vector3.new(s, s, s), fire * CFrame.new(0, layer * 1.3, 0) * CFrame.Angles(rad(layer * 20), rad(layer * 35), 0), color), layer == 1, 30)
		local _ = flame
	end
	local fx = Instance.new("Fire")
	fx.Heat = 8
	fx.Size = 6
	fx.Parent = deco:FindFirstChild("Flame")
	-- Тотем гоблинов (градиент зелёный -> тёмный) и сторожевая вышка.
	gradientStack(deco, "Totem", cf * CFrame.new(-30, 0, -20), 4, 4, 18, { C.MudDark, C.Leaf1, C.Grass1 }, 6, 0.2)
	neon(ball(deco, "TotemEye", 2, cf * CFrame.new(-30, 19, -20), C.Red), true, 14)
	local tower = cf * CFrame.new(38, 0, -38)
	for _, o in { Vector3.new(-3, 0, -3), Vector3.new(3, 0, -3), Vector3.new(-3, 0, 3), Vector3.new(3, 0, 3) } do
		box(deco, "TowerLeg", Vector3.new(1.2, 18, 1.2), tower * CFrame.new(o + Vector3.new(0, 9, 0)), C.WoodDark)
	end
	box(deco, "TowerFloor", Vector3.new(9, 1, 9), tower * CFrame.new(0, 18, 0), C.Wood)
	wedge(deco, "TowerRoof", Vector3.new(10, 4, 5), tower * CFrame.new(0, 23, -2.5), C.Mud)
	wedge(deco, "TowerRoof", Vector3.new(10, 4, 5), tower * CFrame.new(0, 23, 2.5) * CFrame.Angles(0, rad(180), 0), C.Mud)
	-- Факелы.
	for _, o in { Vector3.new(-half + 6, 0, -half + 6), Vector3.new(half - 6, 0, -half + 6), Vector3.new(-half + 6, 0, half - 6), Vector3.new(half - 6, 0, half - 6) } do
		box(deco, "TorchPole", Vector3.new(0.8, 7, 0.8), cf * CFrame.new(o + Vector3.new(0, 3.5, 0)), C.WoodDark)
		neon(box(deco, "TorchFlame", Vector3.new(1.4, 1.4, 1.4), cf * CFrame.new(o + Vector3.new(0, 7.6, 0)), C.Orange), true, 16)
	end

	-- То, что читает код (невидимое).
	local zone = marker(camp, "Zone", Vector3.new(GOBLIN_SIZE, 30, GOBLIN_SIZE), cf * CFrame.new(0, 13, 0), Color3.fromRGB(255, 70, 70))
	local spawns = folder("Spawns", camp)
	for i = 1, 6 do
		local a = (i - 1) / 6 * math.pi * 2
		marker(spawns, "Spawn" .. i, Vector3.new(2, 1, 2), cf * CFrame.new(math.cos(a) * GOBLIN_SIZE * 0.28, 1, math.sin(a) * GOBLIN_SIZE * 0.28 + 8), Color3.fromRGB(90, 220, 90))
	end
	marker(camp, "Marker", Vector3.new(2, 2, 2), cf * CFrame.new(0, 1, -half + 16))
	camp.PrimaryPart = zone
end

--------------------------------------------------------------------------------
-- 6) ТОЧКИ ВАЛУНОВ (RubbleBoulderSpawnPoints, 16 шт.) + каменистые пятна
--------------------------------------------------------------------------------
do
	local points = Instance.new("Folder")
	points.Name = "RubbleBoulderSpawnPoints"
	points.Parent = workspace
	for index, spot in boulderSpots do
		local p = marker(points, ("Point%02d"):format(index), Vector3.new(4, 1, 4), CFrame.new(spot.Pos + Vector3.new(0, 0.5, 0)), C.StoneDark)
		p:SetAttribute("Tier", spot.Tier)
		-- Каменистое пятно (градиент) и мелкие камушки вокруг - видно издалека.
		for step = 1, 3 do
			local d = 30 - (step - 1) * 8
			cylinder(natureF, "RockPatch", 0.2, d, CFrame.new(spot.Pos + Vector3.new(0, 0.1 * step, 0)),
				lerpColors({ C.Grass1:Lerp(C.Stone, 0.35), C.Stone, C.StoneDark }, (step - 1) / 2))
		end
		for r = 1, 6 do
			local a = r / 6 * math.pi * 2 + rng:NextNumber()
			local at = spot.Pos + Vector3.new(math.cos(a) * 13, 0.7, math.sin(a) * 13)
			box(natureF, "Pebble", Vector3.new(2 + rng:NextNumber() * 2, 1.4, 2 + rng:NextNumber() * 2), CFrame.new(at) * CFrame.Angles(0, rng:NextNumber() * 3, rad(rng:NextNumber() * 20)), C.Stone:Lerp(C.StoneDark, rng:NextNumber()))
		end
	end
end

--------------------------------------------------------------------------------
-- 7) ПРИРОДА: деревья (ёлки-ступеньки и «леденцы»), камни, цветы
--------------------------------------------------------------------------------
local function pine(pos, scale)
	local cf = CFrame.new(pos)
	box(natureF, "Trunk", Vector3.new(2, 6, 2) * scale, cf * CFrame.new(0, 3 * scale, 0), C.Wood)
	for layer = 1, 4 do
		local t = (layer - 1) / 3
		local w = (11 - layer * 2.2) * scale
		box(natureF, "Leaves", Vector3.new(w, 3 * scale, w), cf * CFrame.new(0, (5 + layer * 2.8) * scale, 0), lerpColors({ C.Leaf1, C.Leaf2, C.Leaf3 }, t))
	end
end
local function lollipop(pos, scale)
	local cf = CFrame.new(pos)
	box(natureF, "Trunk", Vector3.new(1.6, 8, 1.6) * scale, cf * CFrame.new(0, 4 * scale, 0), C.Wood)
	ball(natureF, "Crown", 9 * scale, cf * CFrame.new(0, 11 * scale, 0), C.Leaf2)
	ball(natureF, "CrownTop", 5.5 * scale, cf * CFrame.new(1 * scale, 14 * scale, -1 * scale), C.Leaf3)
end
local planted = 0
local attempts = 0
while planted < TREE_COUNT and attempts < TREE_COUNT * 12 do
	attempts += 1
	local a = rng:NextNumber() * math.pi * 2
	local r = math.sqrt(rng:NextNumber()) * (MAP_RADIUS - 60)
	local pos = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
	if not blocked(pos, 6) then
		local scale = 0.8 + rng:NextNumber() * 0.7
		if rng:NextNumber() < 0.55 then pine(pos, scale) else lollipop(pos, scale) end
		planted += 1
		-- рядом иногда кустик цветов
		if rng:NextNumber() < 0.35 then
			local fp = pos + Vector3.new(rng:NextNumber() * 8 - 4, 0.5, rng:NextNumber() * 8 - 4)
			box(natureF, "Flowers", Vector3.new(2, 1, 2), CFrame.new(fp), ({ C.Red, C.Yellow, C.White, C.Purple })[rng:NextInteger(1, 4)])
		end
	end
end
for _ = 1, 90 do
	local a = rng:NextNumber() * math.pi * 2
	local r = math.sqrt(rng:NextNumber()) * (MAP_RADIUS - 60)
	local pos = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
	if not blocked(pos, 2) then
		local s = 3 + rng:NextNumber() * 5
		box(natureF, "Rock", Vector3.new(s, s * 0.7, s * 0.9), CFrame.new(pos + Vector3.new(0, s * 0.3, 0)) * CFrame.Angles(rad(rng:NextNumber() * 20), rng:NextNumber() * 6, rad(rng:NextNumber() * 20)), C.Stone:Lerp(C.StoneDark, rng:NextNumber() * 0.6))
	end
end

--------------------------------------------------------------------------------
-- 8) ГОРЫ ПО КРАЮ (ступенчатые, градиент трава -> камень -> снег) + стена
--------------------------------------------------------------------------------
do
	local count = math.floor(2 * math.pi * MAP_RADIUS / 60)
	for i = 0, count - 1 do
		local angle = i / count * 360 + rng:NextNumber() * 2
		local p = polar(angle, MAP_RADIUS - 10 + rng:NextNumber() * 30)
		local w = 70 + rng:NextNumber() * 40
		local h = 55 + rng:NextNumber() * 70
		local cf = CFrame.lookAt(p, Vector3.zero)
		gradientStack(mountainsF, "Mountain", cf, w, w * 0.8, h, { C.Grass1, C.Grass3, C.Stone, C.StoneDark, C.Snow }, 6, 0.8)
	end
	-- Невидимая стена по кругу, чтобы не уйти за горы.
	local walls = 48
	for i = 0, walls - 1 do
		local angle = (i + 0.5) / walls * 360
		local p = polar(angle, MAP_RADIUS + 40, 120)
		local length = 2 * math.pi * (MAP_RADIUS + 40) / walls + 4
		box(mountainsF, "BoundaryWall", Vector3.new(length, 240, 4), CFrame.lookAt(p, Vector3.new(0, 120, 0)), C.White, {
			Transparency = 1, CanQuery = false, CanTouch = false,
		})
	end
end

--------------------------------------------------------------------------------
if recording then ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit) end
game:GetService("Selection"):Set({ map })
local parts = 0
for _, d in workspace:GetDescendants() do if d:IsA("BasePart") then parts += 1 end end
print(("[BuildRetroMap] Готово. Радиус карты %d, базы на радиусе %d (между соседними ~%d стад), дорог 8 по %d стад, точек валунов %d, деревьев %d. Деталей в Workspace: %d. Старое - в ServerStorage.OldMapBackup.")
	:format(MAP_RADIUS, BASE_RING, math.floor(2 * BASE_RING * math.sin(math.pi / 8) - BASE_SIZE), ROAD_END - ROAD_START, #boulderSpots, planted, parts))
