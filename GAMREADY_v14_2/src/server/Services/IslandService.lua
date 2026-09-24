--------------------------------------------------------------------------------
-- IslandService — ОСТРОВА ПРОГРЕССИИ (см. Config.Islands).
--
-- Что делает:
--   • НПС Island Keeper в центре мира (у банка или по маркеру
--     workspace.IslandKeeperMarker). Промпт открывает окно покупок
--     (client/IslandUI.client.lua).
--   • За каждым участком — до трёх островов. Купленный остров выезжает
--     из-под земли (сервер двигает модель, клиент владельца дополнительно
--     показывает катсцену). Уже купленные при заходе строятся сразу.
--       Anvil   → на нём стоит наковальня жеод  (GeodeService:BuildBuilding)
--       Income  → подиум кристалла и сейф       (PassiveIncomeService:BuildStructures)
--       Smelter → плавильня (вся логика — в этом файле)
--   • Плавильня: игрок держит руду из хотбара (атрибут HeldOreUid) и жмёт
--     промпт/кликает по печи → один кусок уходит в печь, через 3–5 минут
--     (os.time — идёт и офлайн) получается слиток той же руды с теми же
--     мутациями и ценой × Config.Islands.Smelter.ValueMultiplier.
--     Число одновременных слотов растёт с уровнем плавильни.
--   • Гейты: Owns(player, id) читают GeodeService (открытие жеод),
--     PassiveIncomeService (установка кристалла/сейф), RebirthService.
--
-- Данные профиля: Islands, SmelterLevel, SmelterSlots, IslandsMigrated
-- (см. DEFAULT_DATA в DataService).
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldUi = require(ReplicatedStorage.Shared.WorldUi) -- v20: стили мировых надписей (StarterGui/WorldUiTemplates)
local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)
local BigNum = require(ReplicatedStorage.Shared.BigNum)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)

local IslandService = {}

local Services = nil
local remote = nil
local keeperNpc = nil
local keeperPrompt = nil
local states = {}      -- [player] = { Plot, Models = {[id] = Model}, Rising = {[id]=true}, Smelter = {...}, Connections = {} }
local lastRequest = {} -- [player] = os.clock()
local busy = {}        -- [player] = true, пока идёт покупка

local ISLANDS = Config.Islands or { Enabled = false, Order = {}, Definitions = {}, Smelter = { Levels = {} } }
local SMELT = ISLANDS.Smelter

-- Позиция руды в цепочке — от неё зависит время плавки (простая руда
-- плавится быстрее редкой, см. Config.Islands.Smelter.MinSeconds/MaxSeconds).
local oreIndex = {}
for index, info in Config.OreChain do
	oreIndex[info.Key] = index
end
local ORE_COUNT = math.max(1, #Config.OreChain)

--------------------------------------------------------------------------------
-- ДАННЫЕ
--------------------------------------------------------------------------------
local function profileOf(player)
	return Services.DataService:GetGeodeData(player)
end

local function ensureFields(data)
	if typeof(data.Islands) ~= "table" then data.Islands = {} end
	if typeof(data.SmelterSlots) ~= "table" then data.SmelterSlots = {} end
	data.SmelterLevel = math.max(0, math.floor(tonumber(data.SmelterLevel) or 0))
end

function IslandService:Owns(player, islandId)
	if not ISLANDS.Enabled then return true end
	local data = profileOf(player)
	return data ~= nil and typeof(data.Islands) == "table" and data.Islands[islandId] == true
end

function IslandService:CountOwned(player)
	local count = 0
	for _, id in ISLANDS.Order do
		if self:Owns(player, id) then count += 1 end
	end
	return count
end

function IslandService:HasRebirthIslands(player)
	if not ISLANDS.Enabled then return true end
	for _, id in ISLANDS.RebirthRequires or {} do
		if not self:Owns(player, id) then return false end
	end
	return true
end

function IslandService:RebirthRequirementLabel()
	if not ISLANDS.Enabled or #(ISLANDS.RebirthRequires or {}) == 0 then return nil end
	return ("Unlock %d islands at the Island Keeper"):format(#ISLANDS.RebirthRequires)
end

-- v10: пасс Fast Smelter — помечаем профиль владельца (weak-таблица),
-- т.к. smelterLevelInfo получает только data.
local fastSmelterData = setmetatable({}, { __mode = "k" })

local function smelterLevelInfo(data)
	local level = math.clamp(data.SmelterLevel, 1, math.max(1, #SMELT.Levels))
	local info = SMELT.Levels[level] or { Slots = 1, SpeedMultiplier = 1 }
	if fastSmelterData[data] then
		local pass = Config.GamePasses.FastSmelter
		info = table.clone(info)
		info.Slots = (info.Slots or 1) + (pass.BonusSlots or 1)
		info.SpeedMultiplier = (info.SpeedMultiplier or 1) * (pass.SpeedMultiplier or 0.5)
	end
	return info, level
end

local function markFastSmelter(player, data)
	if data then
		fastSmelterData[data] = (Services and Services.MonetizationService
			and Services.MonetizationService:HasPass(player, "FastSmelter")) or nil
	end
end

local function smeltDuration(oreKey, data)
	local index = oreIndex[oreKey] or 1
	local alpha = ORE_COUNT > 1 and (index - 1) / (ORE_COUNT - 1) or 0
	alpha = alpha ^ math.max(0.1, tonumber(SMELT.TimeCurve) or 1)
	local base = SMELT.MinSeconds + (SMELT.MaxSeconds - SMELT.MinSeconds) * alpha
	local info = smelterLevelInfo(data)
	return math.max(10, math.floor(base * (info.SpeedMultiplier or 1) + 0.5))
end

local function formatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

local function oreName(oreKey)
	local info = Config.OreByKey[oreKey]
	return info and info.DisplayName or tostring(oreKey)
end

-- РАЗОВАЯ ВЫДАЧА СТАРЫМ ИГРОКАМ (см. Config.Islands.GrandfatherExistingPlayers).
-- Новый профиль к этому моменту ещё ни разу не открывал жеоды — ему ничего
-- не выдаётся, флаг просто ставится, чтобы проверка больше не повторялась.
local function migrate(player, data)
	ensureFields(data)
	if data.IslandsMigrated == true then return end
	data.IslandsMigrated = true
	if not ISLANDS.GrandfatherExistingPlayers then return end
	local usedGeodes = data.FirstGeodeOreGranted == true
		or (data.InstalledGeodeOre or "") ~= ""
		or (tonumber(data.TutorialCompletedAt) or 0) > 0
		or next(data.GeodeCollection or {}) ~= nil
	if usedGeodes then
		data.Islands.Anvil = true
		data.Islands.Income = true
	end
	if (tonumber(data.Rebirths) or 0) > 0 then
		for _, id in ISLANDS.Order do data.Islands[id] = true end
	end
	if data.Islands.Smelter then data.SmelterLevel = math.max(1, data.SmelterLevel) end
	if usedGeodes or (tonumber(data.Rebirths) or 0) > 0 then
		print(("[IslandService] %s: старый профиль — выданы острова, которыми он уже пользовался"):format(player.Name))
	end
end

local function syncAttributes(player)
	local data = profileOf(player)
	if not data then return end
	for _, id in ISLANDS.Order do
		player:SetAttribute("IslandOwned_" .. id, data.Islands[id] == true)
	end
	player:SetAttribute("SmelterLevel", data.SmelterLevel)
end

--------------------------------------------------------------------------------
-- ГЕОМЕТРИЯ
--------------------------------------------------------------------------------
local function newPart(props)
	local part = Instance.new("Part")
	if props.Shape then part.Shape = props.Shape end
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		if key ~= "Shape" then part[key] = value end
	end
	return part
end

-- Точка острова относительно участка: маркер из PlotTemplate (имя —
-- Config.Islands.Definitions[id].PlotMarker, читает PlotService), иначе —
-- ряд позади участка (-Z участка смотрит на банк, "позади" — это +Z).
-- Для своего макета сюда встаёт его PrimaryPart, для плейсхолдера — центр
-- верхней площадки.
local function islandTopCFrame(plot, islandId)
	local marker = plot.IslandCFrames and plot.IslandCFrames[islandId]
	if marker then return marker end
	local pad = plot.Pad
	local index = table.find(ISLANDS.Order, islandId) or 1
	local count = #ISLANDS.Order
	local x = (index - (count + 1) / 2) * ISLANDS.Spacing
	local z = pad.Size.Z / 2 + ISLANDS.BehindDistance + ISLANDS.Radius
	-- Поворот участка без наклона, только по вертикальной оси.
	local look = pad.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 0.01 then flatLook = Vector3.new(0, 0, -1) end
	local position = (pad.CFrame * CFrame.new(x, pad.Size.Y / 2, z)).Position
	return CFrame.lookAt(position, position + flatLook.Unit)
end

local function buildPlaceholderIsland(islandId, topCFrame, definition)
	local radius = ISLANDS.Radius
	local model = Instance.new("Model")
	model.Name = "Island_" .. islandId

	-- Невидимая горизонтальная площадка — PrimaryPart и "земля" для построек
	-- (цилиндр для этого не годится: у повёрнутого цилиндра Size.Y — это
	-- диаметр, и placeOnPlot поставил бы постройку в воздух).
	local surface = newPart({
		Name = "Surface",
		Size = Vector3.new(radius * 2, 1, radius * 2),
		CFrame = topCFrame * CFrame.new(0, -0.5, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = model,
	})
	model.PrimaryPart = surface

	local vertical = CFrame.Angles(0, 0, math.rad(90))
	newPart({
		Name = "Grass", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, radius * 2, radius * 2),
		CFrame = topCFrame * CFrame.new(0, -1, 0) * vertical,
		Material = Enum.Material.Grass, Color = Color3.fromRGB(96, 158, 72),
		Parent = model,
	})
	newPart({
		Name = "Trim", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, radius * 2 + 0.8, radius * 2 + 0.8),
		CFrame = topCFrame * CFrame.new(0, -2.2, 0) * vertical,
		Material = Enum.Material.SmoothPlastic, Color = definition.Color or Color3.fromRGB(200, 200, 200),
		Parent = model,
	})
	local layers = { { -5, 6, 0 }, { -10, 5, 3 }, { -14.5, 4, 6 } }
	for i, layer in layers do
		newPart({
			Name = "Rock" .. i, Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(layer[2], radius * 2 - layer[3], radius * 2 - layer[3]),
			CFrame = topCFrame * CFrame.new(0, layer[1], 0) * vertical,
			Material = Enum.Material.Slate, Color = Color3.fromRGB(112 - i * 8, 102 - i * 8, 92 - i * 8),
			Parent = model,
		})
	end
	-- Камни по краю — чтобы площадка не выглядела идеальной шайбой.
	local random = Random.new(#islandId * 7919)
	for i = 1, 9 do
		local angle = (i / 9) * math.pi * 2 + random:NextNumber(-0.2, 0.2)
		local size = random:NextNumber(1.4, 2.6)
		newPart({
			Name = "EdgeRock",
			Size = Vector3.new(size, size * 0.8, size * 1.1),
			CFrame = topCFrame * CFrame.new(math.cos(angle) * (radius - 0.6), -0.4, math.sin(angle) * (radius - 0.6))
				* CFrame.Angles(random:NextNumber(0, 1), random:NextNumber(0, 6), random:NextNumber(0, 1)),
			Material = Enum.Material.Rock, Color = Color3.fromRGB(125, 118, 108),
			CanCollide = false,
			Parent = model,
		})
	end
	return model
end

-- Ставит модель так, чтобы её низ (по видимым габаритам) лёг на topY.
local function snapBottomTo(model, topY)
	local ok, cf, size = pcall(function() return model:GetBoundingBox() end)
	if not ok then return end
	local halfHeight = math.abs(cf.RightVector.Y) * size.X / 2
		+ math.abs(cf.UpVector.Y) * size.Y / 2
		+ math.abs(cf.LookVector.Y) * size.Z / 2
	local bottom = cf.Position.Y - halfHeight
	model:PivotTo(model:GetPivot() + Vector3.new(0, topY - bottom, 0))
end

-- ТОЧКА ПОСТРОЙКИ НА ОСТРОВЕ. Маркер — деталь внутри модели острова
-- (например "StationMarker"), лежащая НА поверхности: постройка встаёт
-- на её НИЖНЮЮ грань, по центру маркера. Поворот — по маркеру (только
-- вокруг вертикали, без наклона) или по детали "<Имя>Look", если она
-- есть: постройка смотрит "лицом" на неё. Маркеры после чтения
-- становятся невидимыми и неосязаемыми.
-- Возвращает CFrame точки на поверхности (Y = низ маркера) или fallback.
local function stationCFrame(model, name, fallback)
	local marker = model:FindFirstChild(name, true)
	if not (marker and marker:IsA("BasePart")) then return fallback end
	local cf = marker.CFrame
	local half = marker.Size / 2
	local drop = math.abs(cf.RightVector.Y) * half.X + math.abs(cf.UpVector.Y) * half.Y + math.abs(cf.LookVector.Y) * half.Z
	local ground = Vector3.new(cf.Position.X, cf.Position.Y - drop, cf.Position.Z)
	local look = cf.LookVector
	local lookTarget = model:FindFirstChild(name .. "Look", true)
	if lookTarget and lookTarget:IsA("BasePart") then
		look = lookTarget.Position - marker.Position
		lookTarget.Transparency = 1
		lookTarget.CanCollide = false
		lookTarget.CanQuery = false
		lookTarget.CanTouch = false
	end
	look = Vector3.new(look.X, 0, look.Z)
	if look.Magnitude < 0.01 then look = Vector3.new(0, 0, -1) end
	marker.Transparency = 1
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	return CFrame.lookAt(ground, ground + look.Unit)
end

-- Невидимая "земля" для PassiveIncomeService.placeOnPlot: верхняя грань
-- ровно на высоте точки постройки.
local function groundRef(parent, name, cframe)
	return newPart({
		Name = name,
		Size = Vector3.new(4, 0.2, 4),
		CFrame = cframe * CFrame.new(0, -0.1, 0),
		Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false,
		Parent = parent,
	})
end

-- Верх острова по габаритам (для запасных точек, если маркеров нет).
local function topCenterOf(model, yawCFrame)
	local cf, size = model:GetBoundingBox()
	local top = Vector3.new(cf.Position.X, cf.Position.Y + size.Y / 2, cf.Position.Z)
	return CFrame.new(top) * yawCFrame.Rotation
end

--------------------------------------------------------------------------------
-- ПЛАВИЛЬНЯ — модель и табло
--------------------------------------------------------------------------------
-- ВНЕШНИЙ ВИД ПЛАВИЛЬНИ ПО УРОВНЯМ (плейсхолдер). Каждый уровень — своя
-- модель: глиняная печь → кирпичная → железная кузня → магмовая литейня.
-- Свой ассет на уровень — Assets/Smelter_Level<N> (или общий Assets/Smelter).
-- Chimneys: { x, z, ширина, высота } относительно центра.
local SMELTER_STYLES = {
	{
		Base = Vector3.new(5.6, 0.8, 5.6), BaseMat = Enum.Material.Cobblestone, BaseColor = Color3.fromRGB(110, 100, 92),
		Body = Vector3.new(4.4, 4, 4.4), BodyMat = Enum.Material.Sand, BodyColor = Color3.fromRGB(170, 112, 76),
		Top = Vector3.new(4.8, 0.6, 4.8), TopColor = Color3.fromRGB(140, 92, 64),
		Chimneys = { { 1.1, 1.1, 1.2, 2.6 } }, ChimneyColor = Color3.fromRGB(150, 98, 70), ChimneyMat = Enum.Material.Sand,
		Mouth = Vector2.new(2, 1.5),
	},
	{
		Base = Vector3.new(6.5, 1, 6.5), BaseMat = Enum.Material.Cobblestone, BaseColor = Color3.fromRGB(95, 90, 88),
		Body = Vector3.new(5.2, 5, 5.2), BodyMat = Enum.Material.Brick, BodyColor = Color3.fromRGB(120, 62, 45),
		Top = Vector3.new(5.8, 0.8, 5.8), TopColor = Color3.fromRGB(70, 66, 64),
		Chimneys = { { 1.4, 1.4, 1.6, 4 } }, ChimneyColor = Color3.fromRGB(95, 52, 40), ChimneyMat = Enum.Material.Brick,
		Mouth = Vector2.new(2.8, 2),
		Trim = { Mat = Enum.Material.Slate, Color = Color3.fromRGB(80, 76, 72), Heights = { 0.25 } },
	},
	{
		Base = Vector3.new(7.4, 1.1, 7.4), BaseMat = Enum.Material.DiamondPlate, BaseColor = Color3.fromRGB(90, 94, 100),
		Body = Vector3.new(6, 5.8, 6), BodyMat = Enum.Material.Metal, BodyColor = Color3.fromRGB(72, 75, 82),
		Top = Vector3.new(6.6, 0.9, 6.6), TopColor = Color3.fromRGB(55, 57, 62),
		Chimneys = { { 1.8, 1.8, 1.7, 4.6 }, { -1.8, 1.8, 1.4, 3.6 } }, ChimneyColor = Color3.fromRGB(60, 62, 68), ChimneyMat = Enum.Material.Metal,
		Mouth = Vector2.new(3.4, 2.4),
		Trim = { Mat = Enum.Material.DiamondPlate, Color = Color3.fromRGB(120, 124, 132), Heights = { 0.2, 0.75 } },
		Vents = Color3.fromRGB(255, 140, 50),
	},
	{
		Base = Vector3.new(8.4, 1.2, 8.4), BaseMat = Enum.Material.Basalt, BaseColor = Color3.fromRGB(45, 40, 42),
		Body = Vector3.new(6.8, 6.6, 6.8), BodyMat = Enum.Material.Basalt, BodyColor = Color3.fromRGB(38, 33, 36),
		Top = Vector3.new(7.6, 1, 7.6), TopColor = Color3.fromRGB(30, 26, 28),
		Chimneys = { { 2.1, 2.1, 1.8, 5.6 }, { -2.1, 2.1, 1.6, 4.6 }, { 0, -2.3, 1.3, 3.4 } }, ChimneyColor = Color3.fromRGB(34, 30, 32), ChimneyMat = Enum.Material.Basalt,
		Mouth = Vector2.new(4, 2.8),
		Trim = { Mat = Enum.Material.Foil, Color = Color3.fromRGB(255, 190, 60), Heights = { 0.15, 0.55, 0.95 } },
		Vents = Color3.fromRGB(255, 90, 30),
		Glow = true,
	},
}

local function buildPlaceholderSmelter(stationCFrame, level)
	local style = SMELTER_STYLES[math.clamp(level or 1, 1, #SMELTER_STYLES)]
	local model = Instance.new("Model")
	model.Name = "Smelter"
	local baseH, bodyH, topH = style.Base.Y, style.Body.Y, style.Top.Y
	local root = newPart({
		Name = "Root", Size = style.Base,
		CFrame = stationCFrame * CFrame.new(0, baseH / 2, 0),
		Material = style.BaseMat, Color = style.BaseColor,
		Parent = model,
	})
	model.PrimaryPart = root
	newPart({
		Name = "Body", Size = style.Body,
		CFrame = stationCFrame * CFrame.new(0, baseH + bodyH / 2, 0),
		Material = style.BodyMat, Color = style.BodyColor,
		Parent = model,
	})
	newPart({
		Name = "Top", Size = style.Top,
		CFrame = stationCFrame * CFrame.new(0, baseH + bodyH + topH / 2, 0),
		Material = Enum.Material.Slate, Color = style.TopColor,
		Parent = model,
	})
	if style.Trim then
		for index, height in style.Trim.Heights do
			newPart({
				Name = "Trim" .. index,
				Size = Vector3.new(style.Body.X + 0.3, 0.35, style.Body.Z + 0.3),
				CFrame = stationCFrame * CFrame.new(0, baseH + bodyH * height, 0),
				Material = style.Trim.Mat, Color = style.Trim.Color,
				CanCollide = false,
				Parent = model,
			})
		end
	end
	local firstChimney
	for index, chimney in style.Chimneys do
		local part = newPart({
			Name = index == 1 and "Chimney" or ("Chimney" .. index),
			Size = Vector3.new(chimney[3], chimney[4], chimney[3]),
			CFrame = stationCFrame * CFrame.new(chimney[1], baseH + bodyH + topH + chimney[4] / 2, chimney[2]),
			Material = style.ChimneyMat, Color = style.ChimneyColor,
			Parent = model,
		})
		firstChimney = firstChimney or part
	end
	-- "Mouth" — невидимая точка: к ней крепится промпт, в неё летит руда и
	-- из неё вылетают слитки. Видимое устье — в двух состояниях ниже.
	local mouthCFrame = stationCFrame * CFrame.new(0, baseH + 0.5 + style.Mouth.Y / 2, -(style.Body.Z / 2 + 0.05))
	local mouth = newPart({
		Name = "Mouth", Size = Vector3.new(style.Mouth.X, style.Mouth.Y, 0.3),
		CFrame = mouthCFrame,
		Transparency = 1,
		CanCollide = false,
		Parent = model,
	})
	-- ДВА СОСТОЯНИЯ (тот же контракт, что у своего ассета): furnace_inactive —
	-- тёмное холодное устье, furnace_active — раскалённое, со светом и огнём.
	local inactiveModel = Instance.new("Model")
	inactiveModel.Name = "furnace_inactive"
	inactiveModel.Parent = model
	newPart({
		Name = "MouthCold", Size = Vector3.new(style.Mouth.X, style.Mouth.Y, 0.3),
		CFrame = mouthCFrame,
		Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(28, 24, 24),
		CanCollide = false,
		Parent = inactiveModel,
	})
	local activeModel = Instance.new("Model")
	activeModel.Name = "furnace_active"
	activeModel.Parent = model
	local glow = newPart({
		Name = "MouthGlow", Size = Vector3.new(style.Mouth.X, style.Mouth.Y, 0.3),
		CFrame = mouthCFrame,
		Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 120, 40),
		CanCollide = false,
		Parent = activeModel,
	})
	local flameAttachment = Instance.new("Attachment")
	flameAttachment.Name = "Flame"
	flameAttachment.Position = Vector3.new(0, -style.Mouth.Y * 0.3, -0.4)
	flameAttachment.Parent = glow
	local flame = Instance.new("ParticleEmitter")
	flame.Name = "FurnaceFlame"
	flame.Texture = "rbxasset://textures/particles/fire_main.dds"
	flame.Color = ColorSequence.new(Color3.fromRGB(255, 170, 60), Color3.fromRGB(255, 70, 20))
	flame.LightEmission = 1
	flame.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, style.Mouth.X * 0.35), NumberSequenceKeypoint.new(1, 0) })
	flame.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	flame.Lifetime = NumberRange.new(0.4, 0.7)
	flame.Speed = NumberRange.new(1, 2.5)
	flame.Acceleration = Vector3.new(0, 4, 0)
	flame.Rate = 14
	flame.Parent = flameAttachment
	if style.Vents then
		for _, side in { -1, 1 } do
			for row = 1, 2 do
				newPart({
					Name = "Vent",
					Size = Vector3.new(0.2, 0.35, style.Body.Z * 0.5),
					CFrame = stationCFrame * CFrame.new(side * (style.Body.X / 2 + 0.05), baseH + bodyH * (0.35 + row * 0.18), 0),
					Material = Enum.Material.Neon, Color = style.Vents,
					CanCollide = false,
					Parent = model,
				})
			end
		end
	end
	if style.Glow then
		-- Магмовые трещины по основанию.
		for i = 1, 4 do
			local angle = i * math.pi / 2
			newPart({
				Name = "MagmaCrack",
				Size = Vector3.new(0.35, 0.1, style.Base.X * 0.35),
				CFrame = stationCFrame * CFrame.Angles(0, angle, 0) * CFrame.new(style.Base.X * 0.38, baseH + 0.02, 0),
				Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 80, 20),
				CanCollide = false,
				Parent = model,
			})
		end
	end
	local light = Instance.new("PointLight")
	light.Name = "FireLight"
	light.Color = Color3.fromRGB(255, 140, 60)
	light.Range = 10 + level * 2
	light.Brightness = 2.5
	light.Parent = glow
	-- Плейсхолдер "плавится" целиком (см. client/FurnaceFX), а не только
	-- устье — у своего ассета анимируется модель furnace_active.
	model:SetAttribute("SquashTarget", "")
	local smokeAttachment = Instance.new("Attachment")
	smokeAttachment.Name = "SmokePoint"
	smokeAttachment.Position = Vector3.new(0, firstChimney.Size.Y / 2 + 0.1, 0)
	smokeAttachment.Parent = firstChimney
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smoke"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(90, 90, 95))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 3) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(1.5, 2.5)
	smoke.Speed = NumberRange.new(2, 4)
	smoke.Rate = 4 + level * 2
	smoke.Enabled = false
	smoke.Parent = smokeAttachment
	return model
end

-- СОСТОЯНИЯ ПЕЧИ furnace_active / furnace_inactive — две модели внутри
-- модели печи (своего ассета или плейсхолдера). Видна ровно одна:
-- детали другой прозрачны и неосязаемы, эмиттеры и свет выключены.
-- Исходные значения запоминаются атрибутами при первой подготовке.
local function prepareStateModel(stateModel)
	if not stateModel then return end
	for _, descendant in stateModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant:SetAttribute("BaseTransparency", descendant.Transparency)
			descendant:SetAttribute("BaseCanCollide", descendant.CanCollide)
		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Light") or descendant:IsA("Beam") or descendant:IsA("Trail") or descendant:IsA("Fire") or descendant:IsA("Smoke") or descendant:IsA("Sparkles") then
			descendant:SetAttribute("BaseEnabled", descendant.Enabled)
		end
	end
end

local function setStateVisible(stateModel, visible)
	if not stateModel then return end
	for _, descendant in stateModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Transparency = visible and (descendant:GetAttribute("BaseTransparency") or 0) or 1
			descendant.CanCollide = visible and (descendant:GetAttribute("BaseCanCollide") == true) or false
		elseif descendant:GetAttribute("BaseEnabled") ~= nil then
			descendant.Enabled = visible and descendant:GetAttribute("BaseEnabled") == true
		end
	end
end

local function setFurnaceActive(smelter, active)
	if smelter.IsActive == active then return end
	smelter.IsActive = active
	setStateVisible(smelter.ActiveModel, active)
	setStateVisible(smelter.InactiveModel, not active)
	-- Клиенты (FurnaceFX) по этому атрибуту включают анимацию "плавления".
	smelter.Model:SetAttribute("FurnaceActive", active)
end

local function buildSmelterBoard(anchor)
	local gui = Instance.new("BillboardGui")
	gui.Name = "SmelterBoard"
	gui.Size = UDim2.fromOffset(320, 84)
	gui.StudsOffset = Vector3.new(0, 7.5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 55
	gui.LightInfluence = 0
	gui.Adornee = anchor
	gui.Parent = anchor
	local title = WorldUi.Text(nil, "Text", "Heading")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0.55, 0)
	title.BackgroundTransparency = 1
	title.TextScaled = true
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Text = "SMELTER"
	title.Parent = gui
	local sub = WorldUi.Text(nil, "Text", "Body")
	sub.Name = "Sub"
	sub.Position = UDim2.fromScale(0, 0.58)
	sub.Size = UDim2.new(1, 0, 0.4, 0)
	sub.BackgroundTransparency = 1
	sub.TextScaled = true
	sub.RichText = true
	sub.TextColor3 = Color3.fromRGB(230, 230, 235)
	sub.Text = ""
	sub.Parent = gui
	return gui, title, sub
end

-- Сколько секунд после "плевка" над печью горит ReadyText.
local READY_BANNER_SECONDS = 6

function IslandService:_updateSmelter(player)
	markFastSmelter(player, Services.DataService:GetGeodeData(player))
	local state = states[player]
	local smelter = state and state.Smelter
	local data = profileOf(player)
	if not (smelter and data and smelter.Model.Parent) then return end
	ensureFields(data)

	-- v9: готовое НЕ вылетает само — ждёт клика по печи (InteractSmelter).
	local info = smelterLevelInfo(data)
	local now = os.time()
	local slots = data.SmelterSlots
	local soonest, soonestOre = nil, nil
	local readyCount = 0
	for _, slot in slots do
		local left = (slot.StartedAt or 0) + (slot.Duration or 0) - now
		if left > 0 and (not soonest or left < soonest) then
			soonest, soonestOre = left, slot.Ore
		elseif left <= 0 then
			readyCount += 1
			if not slot.Notified then
				slot.Notified = true
				Services.NotifyService:Show(player, ("%s ingot is ready — click the smelter!"):format(oreName(slot.Ore)), { Icon = "Reward" })
			end
		end
	end
	smelter.Model:SetAttribute("IngotsReady", readyCount)
	smelter.WasSeeded = true

	local used = #slots
	-- При одном слоте счётчик "1/1" ничего не сообщает — не показываем.
	local capacitySuffix = info.Slots > 1 and ("  •  %d/%d"):format(used, info.Slots) or ""
	local multiplierText = ("x%s"):format(tostring(SMELT.ValueMultiplier))
	local recentlyEjected = os.clock() - (smelter.LastEjectAt or 0) < READY_BANNER_SECONDS
	if readyCount > 0 then
		smelter.Title.Text = SMELT.ReadyText
		smelter.Title.TextColor3 = Color3.fromRGB(110, 255, 140)
		smelter.Sub.Text = readyCount == 1 and "<font color=\"#FFD84A\">CLICK</font> to collect" or ("<font color=\"#FFD84A\">CLICK</font> to collect %d ingots"):format(readyCount)
	elseif recentlyEjected then
		smelter.Title.Text = SMELT.ReadyText
		smelter.Title.TextColor3 = Color3.fromRGB(110, 255, 140)
		smelter.Sub.Text = ("<font color=\"#FFD84A\">%s INGOT</font>"):format(oreName(smelter.LastEjectOre):upper())
	elseif soonest then
		smelter.Title.Text = "SMELTING..."
		smelter.Title.TextColor3 = Color3.fromRGB(255, 160, 70)
		smelter.Sub.Text = ("%s — <font color=\"#FFD84A\">%s</font>%s"):format(oreName(soonestOre):upper(), formatTime(soonest), capacitySuffix)
	else
		smelter.Title.Text = "SMELTER"
		smelter.Title.TextColor3 = Color3.new(1, 1, 1)
		smelter.Sub.Text = ("Ore → ingot <font color=\"#FFD84A\">%s</font>%s"):format(multiplierText, capacitySuffix)
	end

	-- Текст промпта зависит и от печи, и от того, что игрок держит.
	local held = player:GetAttribute("HeldOre")
	local heldSmelted = player:GetAttribute("HeldOreSmelted") == true
	if readyCount > 0 then
		smelter.Prompt.ActionText = "COLLECT"
	elseif used >= info.Slots then
		smelter.Prompt.ActionText = info.Slots > 1 and "SMELTER FULL" or "SMELTER BUSY"
	elseif held and not heldSmelted then
		smelter.Prompt.ActionText = "SMELT " .. oreName(held):upper()
	else
		smelter.Prompt.ActionText = "SMELT ORE"
	end

	-- Пока внутри что-то плавится — состояние furnace_active (и анимация
	-- "плавления" на клиентах), иначе — furnace_inactive.
	local burning = used > 0
	setFurnaceActive(smelter, burning)
	if smelter.Smoke then smelter.Smoke.Enabled = burning end
end

-- ВЫПЛЁВЫВАНИЕ ГОТОВЫХ СЛИТКОВ. Готовый слот сразу уходит из данных, а
-- слиток вылетает из устья по дуге с трейлом (MineService:EjectToGround —
-- та же анимация, что у руды из шахты) и ложится на остров. Подбирает
-- только владелец — ногами или тележкой. Пока слиток лежит на земле, он
-- числится в state.PendingIngots: если игрок выйдет, не подобрав его,
-- слиток вернётся в печь готовым (CleanupPlayer) и вылетит при следующем
-- заходе — ничего не теряется.
function IslandService:_ejectReady(player)
	local state = states[player]
	local smelter = state and state.Smelter
	local data = profileOf(player)
	if not (smelter and data) then return 0 end
	local now = os.time()
	local ready = {}
	local index = 1
	while index <= #data.SmelterSlots do
		local slot = data.SmelterSlots[index]
		if (slot.StartedAt or 0) + (slot.Duration or 0) <= now then
			table.insert(ready, table.remove(data.SmelterSlots, index))
		else
			index += 1
		end
	end
	if #ready == 0 then return 0 end
	smelter.LastEjectAt = os.clock()
	smelter.LastEjectOre = ready[#ready].Ore
	-- Клиенты (FurnaceFX) по смене счётчика играют "плевок" печи.
	smelter.Model:SetAttribute("SpitCount", (tonumber(smelter.Model:GetAttribute("SpitCount")) or 0) + 1)
	for i, slot in ready do
		task.delay((i - 1) * 0.35 + 0.15, function()
			self:_spitIngot(player, slot)
		end)
	end
	return #ready
end

local function restoreReadySlot(data, slot)
	table.insert(data.SmelterSlots, {
		Ore = slot.Ore,
		Variant = slot.Variant or 1,
		Mutations = slot.Mutations,
		Value = slot.Value,
		Gigantic = slot.Gigantic, Tier = slot.Tier, Chance = slot.Chance,
		Notified = true,
		StartedAt = 0,
		Duration = 0,
	})
end

function IslandService:_spitIngot(player, slot)
	local state = states[player]
	local smelter = state and state.Smelter
	local data = profileOf(player)
	if not data then return end
	if not (smelter and player.Parent and Services.MineService and Services.MineService.EjectToGround) then
		restoreReadySlot(data, slot)
		return
	end
	local value = math.floor((tonumber(slot.Value) or 0) * (SMELT.ValueMultiplier or 20) + 0.5)
	-- Слиток — та же руда с теми же мутациями; модель — Assets/Ingot_<Руда>
	-- (см. PlaceholderFactory.OreIngot), цена уже умножена.
	local ok, crystal = pcall(function()
		return Services.CrystalService:CreateFromStack({
			Ore = slot.Ore,
			Variant = slot.Variant or 1,
			Mutations = slot.Mutations,
			Value = value,
			Count = 1,
			Smelted = true,
			Gigantic = slot.Gigantic, Tier = slot.Tier, Chance = slot.Chance,
		})
	end)
	if not (ok and crystal) then
		warn("[IslandService] Слиток не создан, возвращаю в печь:", crystal)
		restoreReadySlot(data, slot)
		return
	end
	local mouth = smelter.Mouth or smelter.Root
	local forward = smelter.Station and smelter.Station.LookVector or -mouth.CFrame.LookVector
	forward = Vector3.new(forward.X, 0, forward.Z)
	forward = forward.Magnitude > 0.01 and forward.Unit or Vector3.new(0, 0, -1)
	local side = Vector3.new(-forward.Z, 0, forward.X)
	local from = mouth.Position + forward * 0.8
	local landXZ = from + forward * (4 + math.random() * 3) + side * ((math.random() - 0.5) * 5)
	if not Services.MineService:EjectToGround(player, crystal, from, landXZ, 0.75, 6) then
		crystal:Destroy()
		restoreReadySlot(data, slot)
		return
	end
	-- Слиток "висит" за печью, пока лежит в MineGroundOre. Ушёл оттуда
	-- (подобран в рюкзак/тележку, уничтожен) — больше не наш.
	state.PendingIngots[crystal] = slot
	local groundFolder = crystal.Parent
	local connection
	connection = crystal.AncestryChanged:Connect(function()
		if crystal.Parent ~= groundFolder then
			if states[player] then states[player].PendingIngots[crystal] = nil end
			connection:Disconnect()
		end
	end)
end

function IslandService:_flyOreIntoSmelter(player, removed, mouthPart)
	local info = Config.OreByKey[removed.Ore]
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (info and hrp and mouthPart) then return end
	local ok, visual = pcall(PlaceholderFactory.OreCrystal, info, Config.OreVariants[removed.Variant or 1])
	if not ok or not visual then return end
	for _, part in (visual:IsA("BasePart") and { visual } or visual:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	local from = hrp.Position + Vector3.new(0, 1.5, 0)
	local to = mouthPart.Position
	visual:PivotTo(CFrame.new(from))
	visual.Parent = workspace
	task.spawn(function()
		local started = os.clock()
		local duration = 0.45
		while visual.Parent do
			local t = math.clamp((os.clock() - started) / duration, 0, 1)
			local pos = from:Lerp(to, t) + Vector3.new(0, math.sin(t * math.pi) * 3, 0)
			visual:PivotTo(CFrame.new(pos) * CFrame.Angles(t * 6, t * 4, 0))
			if t >= 1 then break end
			RunService.Heartbeat:Wait()
		end
		if visual.Parent then visual:Destroy() end
	end)
end

function IslandService:InteractSmelter(player)
	markFastSmelter(player, Services.DataService:GetGeodeData(player))
	local state = states[player]
	local smelter = state and state.Smelter
	local data = profileOf(player)
	if not (smelter and data) or state.Rising.Smelter then return end
	if player:GetAttribute("EconomyTransactionLocked") == true then return end
	local now = os.clock()
	if now - (smelter.LastUse or 0) < 0.35 then return end
	smelter.LastUse = now

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local anchor = smelter.Mouth or smelter.Root
	if not (hrp and anchor) or (hrp.Position - anchor.Position).Magnitude > (SMELT.PromptDistance or 10) + 8 then return end
	ensureFields(data)
	local info = smelterLevelInfo(data)
	local inventory = Services.InventoryService

	-- 1) v9: готовые слитки вылетают ТОЛЬКО по клику — и этот клик на них и уходит.
	if self:_ejectReady(player) > 0 then
		self:_updateSmelter(player)
		return
	end

	-- 2) Кладём руду из рук.
	local uid = player:GetAttribute("HeldOreUid")
	local stack = typeof(uid) == "string" and inventory:GetStackByUid(player, uid) or nil
	if not stack then
		Services.NotifyService:Show(player, "Hold an ore from your hotbar, then press the smelter", { Icon = "Ore" })
		return
	end
	if stack.Smelted then
		Services.NotifyService:Show(player, "Ingots can only be smelted once!", { Icon = "Error" })
		return
	end
	if not Config.OreByKey[stack.Ore] then return end
	if Config.IsJunk and Config.IsJunk(stack.Ore) then
		Services.NotifyService:Show(player, "That's junk! The smelter only takes ore.", { Icon = "Error" })
		return
	end
	if #data.SmelterSlots >= info.Slots then
		local canUpgrade = (data.SmelterLevel < #SMELT.Levels)
		Services.NotifyService:Show(player, info.Slots == 1
			and "The smelter takes one ore at a time. Wait for the ingot!"
			or canUpgrade
			and ("Smelter is full (%d/%d). Upgrade it at the Island Keeper!"):format(#data.SmelterSlots, info.Slots)
			or ("Smelter is full (%d/%d). Wait for an ingot."):format(#data.SmelterSlots, info.Slots), { Icon = "Error" })
		return
	end
	local removed = inventory:TakeOneByUid(player, uid)
	if not removed then return end
	local duration = smeltDuration(removed.Ore, data)
	table.insert(data.SmelterSlots, {
		Ore = removed.Ore,
		Variant = removed.Variant or 1,
		Mutations = removed.Mutations,
		Value = tonumber(removed.Value) or 0,
		Gigantic = removed.Gigantic, Tier = removed.Tier, Chance = removed.Chance,
		StartedAt = os.time(),
		Duration = duration,
	})
	self:_flyOreIntoSmelter(player, removed, anchor)
	Services.NotifyService:Show(player, ("SMELTING %s — ready in %s"):format(oreName(removed.Ore):upper(), formatTime(duration)), { Icon = "Ore" })
	self:_updateSmelter(player)
end

function IslandService:_buildSmelter(player, islandModel, stationCFrame)
	local data = profileOf(player)
	local _, level = smelterLevelInfo(data or { SmelterLevel = 1 })
	local model = PlaceholderFactory.Smelter(level)
	if model then
		model:PivotTo(stationCFrame)
	else
		model = buildPlaceholderSmelter(stationCFrame, level)
	end
	-- Метки для клиента (катсцена улучшения печи ищет СВОЮ печь по ним).
	model:SetAttribute("IsSmelter", true)
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("SmelterLevel", level)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then part.Anchored = true end
	end
	snapBottomTo(model, stationCFrame.Position.Y)
	model.Parent = islandModel

	local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	local mouth = model:FindFirstChild("Mouth", true)
	if not (mouth and mouth:IsA("BasePart")) then mouth = nil end
	local body = model:FindFirstChild("Body", true)
	local boardAnchor = (body and body:IsA("BasePart")) and body or root

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SmelterPrompt"
	prompt.ObjectText = "Smelter"
	prompt.ActionText = "SMELT ORE"
	prompt.HoldDuration = 0
	prompt.ClickablePrompt = true
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = SMELT.PromptDistance or 10
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute("PromptKind", "Talk")
	prompt:SetAttribute("OwnerUserId", player.UserId)
	prompt.Parent = mouth or root
	prompt.Triggered:Connect(function(triggerer)
		if triggerer == player then self:InteractSmelter(player) end
	end)

	-- "Нажать на печь рудой" — клик мышкой/тап прямо по модели тоже работает.
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = (SMELT.PromptDistance or 10) + 6
	click.Parent = boardAnchor
	click.MouseClick:Connect(function(clicker)
		if clicker == player then self:InteractSmelter(player) end
	end)

	local board, title, sub = buildSmelterBoard(boardAnchor)
	local smokeEmitter = model:FindFirstChild("Smoke", true)
	local light = model:FindFirstChild("FireLight", true)
	local activeModel = model:FindFirstChild("furnace_active", true)
	local inactiveModel = model:FindFirstChild("furnace_inactive", true)
	prepareStateModel(activeModel)
	prepareStateModel(inactiveModel)
	if model:GetAttribute("SquashTarget") == nil then
		-- Свой ассет: "плавится" именно активная модель, если она есть.
		model:SetAttribute("SquashTarget", activeModel and "furnace_active" or "")
	end
	states[player].Smelter = {
		Model = model,
		Root = root,
		Mouth = mouth,
		Prompt = prompt,
		Board = board,
		Title = title,
		Sub = sub,
		Smoke = smokeEmitter and smokeEmitter:IsA("ParticleEmitter") and smokeEmitter or nil,
		Light = light and light:IsA("PointLight") and light or nil,
		Notified = {},
		WasSeeded = false,
		Station = stationCFrame,
		ActiveModel = activeModel,
		InactiveModel = inactiveModel,
		IsActive = nil,
		LastEjectAt = 0,
		LastEjectOre = nil,
	}
	self:_updateSmelter(player)
end

-- Улучшение печи — новая модель уровня на том же месте. Старая удаляется
-- в тот же кадр; клиент владельца заранее снял с неё слепок и сам
-- проигрывает катсцену "старая сжимается → новая вырастает" (IslandUI).
function IslandService:_rebuildSmelter(player)
	local state = states[player]
	local smelter = state and state.Smelter
	if not smelter then return end
	local island = smelter.Model.Parent
	local station = smelter.Station
	local notified = smelter.Notified
	smelter.Model:Destroy()
	state.Smelter = nil
	self:_buildSmelter(player, island, station)
	if state.Smelter then
		state.Smelter.Notified = notified
		state.Smelter.WasSeeded = true
		state.Smelter.LastEjectAt = smelter.LastEjectAt or 0
		state.Smelter.LastEjectOre = smelter.LastEjectOre
	end
end

--------------------------------------------------------------------------------
-- ПОСТРОЙКА / ПОДЪЁМ ОСТРОВА
--------------------------------------------------------------------------------
function IslandService:_buildIsland(player, islandId, animate)
	local state = states[player]
	if not state or state.Models[islandId] then return end
	local plot = state.Plot
	if not (plot and plot.Content and plot.Content.Parent) then return end
	local definition = ISLANDS.Definitions[islandId] or {}
	local anchorCFrame = islandTopCFrame(plot, islandId)

	-- СВОЙ МАКЕТ ОСТРОВА (Assets/<definition.Model>, по умолчанию
	-- "Island_<Id>"): его PrimaryPart ставится РОВНО в маркер участка —
	-- и позицией, и поворотом. Мосты, декор и всё прочее — внутри макета,
	-- код их не трогает. Нет макета — строим плейсхолдер (верх площадки
	-- = маркер/точка по умолчанию).
	local model = PlaceholderFactory.Island(definition.Model or ("Island_" .. islandId))
	local fallbackTop
	if model then
		local primary = model.PrimaryPart
		model:PivotTo(anchorCFrame * primary.CFrame:ToObjectSpace(model:GetPivot()))
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then part.Anchored = true end
		end
		fallbackTop = topCenterOf(model, anchorCFrame)
	else
		model = buildPlaceholderIsland(islandId, anchorCFrame, definition)
		fallbackTop = anchorCFrame
	end
	model.Name = "Island_" .. islandId
	model:SetAttribute("IslandId", islandId)
	model:SetAttribute("OwnerUserId", player.UserId)
	model.Parent = plot.Content
	state.Models[islandId] = model

	-- Постройки — детьми модели острова, чтобы ехали вместе с ним.
	if islandId == "Anvil" then
		local station = stationCFrame(model, "StationMarker", fallbackTop)
		local building = Services.GeodeService:BuildBuilding(player, station, model)
		if building then snapBottomTo(building, station.Position.Y) end
	elseif islandId == "Income" then
		local right = fallbackTop.RightVector
		local podiumCFrame = stationCFrame(model, "PodiumMarker", fallbackTop - right * 3.8)
		local safeCFrame = stationCFrame(model, "SafeMarker", fallbackTop + right * 4.2)
		local podiumGround = groundRef(model, "PodiumGround", podiumCFrame)
		local safeGround = groundRef(model, "SafeGround", safeCFrame)
		Services.PassiveIncomeService:BuildStructures(player, podiumCFrame, safeCFrame, podiumGround, model, safeGround)
	elseif islandId == "Smelter" then
		local station = stationCFrame(model, "StationMarker", fallbackTop)
		self:_buildSmelter(player, model, station)
	end

	if animate then
		self:_rise(player, islandId, model)
	end
end

function IslandService:_rise(player, islandId, model)
	local state = states[player]
	state.Rising[islandId] = true
	local duration = ISLANDS.RiseSeconds or 3
	local finalPivot = model:GetPivot()
	local boxCFrame, boxSize = model:GetBoundingBox()
	-- Остров обязан уйти под землю ЦЕЛИКОМ, какой бы высоты ни был макет.
	local depth = math.max(ISLANDS.RiseDepth or 16, boxSize.Y + 2)
	local pad = state.Plot and state.Plot.Pad
	local groundY = pad and (pad.Position.Y + pad.Size.Y / 2) or (boxCFrame.Position.Y - boxSize.Y / 2)

	-- Промпты острова молчат, пока он едет.
	local prompts = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("ProximityPrompt") and descendant.Enabled then
			descendant.Enabled = false
			table.insert(prompts, descendant)
		end
	end
	if islandId == "Income" then
		Services.PassiveIncomeService:SetSuspended(player, true)
		Services.PassiveIncomeService:ResetOreModel(player)
	end
	model:PivotTo(finalPivot - Vector3.new(0, depth, 0))

	-- Пыль из земли по площади острова.
	local dust = newPart({
		Name = "IslandRiseDust",
		Size = Vector3.new(math.max(4, boxSize.X), 0.2, math.max(4, boxSize.Z)),
		CFrame = CFrame.new(boxCFrame.Position.X, groundY, boxCFrame.Position.Z),
		Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false,
		Parent = workspace,
	})
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(165, 140, 110))
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(1, 1.8)
	emitter.Speed = NumberRange.new(4, 9)
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.Rate = 60
	emitter.Parent = dust

	-- Клиент владельца покажет катсцену (камера + тряска + осколки).
	if remote then
		local focus = Vector3.new(boxCFrame.Position.X, groundY, boxCFrame.Position.Z)
		remote:FireClient(player, "Rise", islandId, focus, duration, math.max(boxSize.X, boxSize.Z) / 2)
	end

	task.spawn(function()
		local started = os.clock()
		while model.Parent do
			local t = math.clamp((os.clock() - started) / duration, 0, 1)
			-- EaseOutBack: чуть переезжает вверх и садится на место.
			local c1, c3 = 1.2, 2.2
			local eased = 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
			-- Мелкая дрожь, затухающая к концу — "продирается сквозь землю".
			local shake = (1 - t) * 0.25
			local jitter = Vector3.new((math.random() - 0.5) * shake, 0, (math.random() - 0.5) * shake)
			model:PivotTo(finalPivot + Vector3.new(0, -depth * (1 - eased), 0) + jitter)
			if t >= 1 then break end
			if t > 0.75 then emitter.Rate = 15 end
			RunService.Heartbeat:Wait()
		end
		if model.Parent then model:PivotTo(finalPivot) end
		emitter.Enabled = false
		task.delay(2, function() if dust.Parent then dust:Destroy() end end)
		for _, prompt in prompts do
			if prompt.Parent then prompt.Enabled = true end
		end
		if states[player] then states[player].Rising[islandId] = nil end
		if islandId == "Income" and player.Parent then
			Services.PassiveIncomeService:SetSuspended(player, false)
			Services.PassiveIncomeService:ResetOreModel(player)
			Services.PassiveIncomeService:UpdateDisplay(player)
		end
	end)
end

--------------------------------------------------------------------------------
-- ПОКУПКИ У НПС
--------------------------------------------------------------------------------
local function costText(cost)
	return "$" .. NumberFormat.abbreviate(cost)
end

function IslandService:BuildState(player)
	local data = profileOf(player)
	if not data then return nil end
	ensureFields(data)
	local money = Services.DataService:GetMoney(player)
	local islands = {}
	for _, id in ISLANDS.Order do
		local definition = ISLANDS.Definitions[id] or {}
		local requires = definition.Requires
		local requiresMet = not requires or data.Islands[requires] == true
		table.insert(islands, {
			Id = id,
			DisplayName = definition.DisplayName or id,
			Description = definition.Description or "",
			Icon = definition.Icon or "",
			Color = definition.Color or Color3.new(1, 1, 1),
			CostText = costText(definition.Cost or 0),
			Owned = data.Islands[id] == true,
			RequiresMet = requiresMet,
			RequiresName = requires and (ISLANDS.Definitions[requires] and ISLANDS.Definitions[requires].DisplayName or requires) or nil,
			CanAfford = not BigNum.lt(money, definition.Cost or 0),
			Perks = definition.Perks or {},
		})
	end
	local smelter = nil
	if data.Islands.Smelter == true then
		local info, level = smelterLevelInfo(data)
		local nextInfo = SMELT.Levels[level + 1]
		local levels = {}
		for index, entry in SMELT.Levels do
			levels[index] = { Slots = entry.Slots, Name = entry.Name or ("Level " .. index) }
		end
		smelter = {
			Level = level,
			MaxLevel = #SMELT.Levels,
			Levels = levels,
			Name = info.Name or ("Level " .. level),
			NextName = nextInfo and (nextInfo.Name or ("Level " .. (level + 1))) or nil,
			Slots = info.Slots,
			NextSlots = nextInfo and nextInfo.Slots or nil,
			NextSpeed = nextInfo and nextInfo.SpeedMultiplier or nil,
			NextCostText = nextInfo and costText(nextInfo.Cost or 0) or nil,
			CanAfford = nextInfo and not BigNum.lt(money, nextInfo.Cost or 0) or false,
			Multiplier = SMELT.ValueMultiplier,
		}
	end
	return {
		Islands = islands,
		Smelter = smelter,
		RebirthUnlocked = self:HasRebirthIslands(player),
		KeeperName = ISLANDS.KeeperName,
	}
end

function IslandService:SendState(player, command)
	if remote and player.Parent then
		remote:FireClient(player, command or "State", self:BuildState(player))
	end
end

local function nearKeeper(player)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local root = keeperNpc and keeperNpc.PrimaryPart
	return hrp and root and (hrp.Position - root.Position).Magnitude <= (ISLANDS.KeeperPromptDistance or 12) + 25
end

local function charge(player, cost)
	if player:GetAttribute("EconomyTransactionLocked") == true then
		return false, "Saving another reward, try again"
	end
	if BigNum.lt(Services.DataService:GetMoney(player), cost) then
		return false, "Not enough money"
	end
	Services.DataService:AddMoney(player, -cost)
	return true
end

local function saveSoon(player)
	task.spawn(function()
		pcall(function() Services.DataService:SaveProfile(player) end)
	end)
end

function IslandService:TryBuy(player, islandId)
	local definition = ISLANDS.Definitions[islandId]
	local data = profileOf(player)
	if not (definition and data and states[player]) then return false, "Unavailable" end
	ensureFields(data)
	if data.Islands[islandId] then return false, "Already unlocked" end
	if definition.Requires and not data.Islands[definition.Requires] then
		local need = ISLANDS.Definitions[definition.Requires]
		return false, ("Unlock the %s first"):format(need and need.DisplayName or definition.Requires)
	end
	local ok, reason = charge(player, definition.Cost or 0)
	if not ok then return false, reason end

	data.Islands[islandId] = true
	if islandId == "Smelter" then data.SmelterLevel = math.max(1, data.SmelterLevel) end
	syncAttributes(player)
	saveSoon(player)
	local built, err = pcall(function() self:_buildIsland(player, islandId, true) end)
	if not built then warn("[IslandService] Постройка острова упала:", err) end
	Services.NotifyService:Show(player, ("%s UNLOCKED! Look behind your base."):format((definition.DisplayName or islandId):upper()), { Icon = "Reward", Duration = 5 })
	if Services.QuestService and Services.QuestService._refreshDerived then
		pcall(function() Services.QuestService:_refreshDerived(player) end)
	end
	if Services.TutorialService then
		pcall(function() Services.TutorialService:ShowHint(player, "FirstIsland") end)
	end
	return true
end

function IslandService:TryUpgradeSmelter(player)
	local data = profileOf(player)
	if not (data and states[player]) then return false, "Unavailable" end
	ensureFields(data)
	if not data.Islands.Smelter then return false, "Unlock the Smelter Island first" end
	if states[player].Rising.Smelter or not states[player].Smelter then return false, "Wait for the island to finish rising" end
	local _, level = smelterLevelInfo(data)
	local nextInfo = SMELT.Levels[level + 1]
	if not nextInfo then return false, "Smelter is already max level" end
	local ok, reason = charge(player, nextInfo.Cost or 0)
	if not ok then return false, reason end
	data.SmelterLevel = level + 1
	syncAttributes(player)
	saveSoon(player)
	local rebuilt, err = pcall(function() self:_rebuildSmelter(player) end)
	if not rebuilt then warn("[IslandService] Пересборка печи упала:", err) end
	if remote then remote:FireClient(player, "SmelterUpgraded", level + 1) end
	Services.NotifyService:Show(player, ("%s — SMELTS %d ORE AT ONCE"):format((nextInfo.Name or "SMELTER UPGRADED"):upper(), nextInfo.Slots), { Icon = "Reward" })
	return true
end

--------------------------------------------------------------------------------
-- НПС В ЦЕНТРЕ МИРА
--------------------------------------------------------------------------------
local function groundYAt(position, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	local hit = workspace:Raycast(position + Vector3.new(0, 60, 0), Vector3.new(0, -200, 0), params)
	return hit and hit.Position.Y or nil
end

function IslandService:_spawnKeeper()
	local folder = Instance.new("Folder")
	folder.Name = "IslandKeeper"
	folder.Parent = workspace

	local bankPosition = Vector3.zero
	local sellZone = Services.WorldService and Services.WorldService.GetSellZone and Services.WorldService:GetSellZone()
	if sellZone then
		bankPosition = sellZone:IsA("BasePart") and sellZone.Position or sellZone:GetPivot().Position
	end

	local cframe
	local marker = workspace:FindFirstChild("IslandKeeperMarker", true)
	if marker and marker:IsA("BasePart") then
		cframe = marker.CFrame
		local look = workspace:FindFirstChild("IslandKeeperMarkerLook", true)
		if look and look:IsA("BasePart") then
			cframe = CFrame.lookAt(marker.Position, Vector3.new(look.Position.X, marker.Position.Y, look.Position.Z))
			look.Transparency = 1
			look.CanCollide = false
		end
		marker.Transparency = 1
		marker.CanCollide = false
	else
		local position = bankPosition + (ISLANDS.KeeperOffset or Vector3.new(-30, 0, 0))
		local away = Vector3.new(position.X - bankPosition.X, 0, position.Z - bankPosition.Z)
		if away.Magnitude < 0.1 then away = Vector3.new(-1, 0, 0) end
		cframe = CFrame.lookAt(position, position + away.Unit)
	end

	local npc, isCustom = PlaceholderFactory.IslandKeeperNPC()
	local primary = npc.PrimaryPart
	local facing = npc:FindFirstChild("FacingPoint", true)
	local correction = 0
	if facing and facing:IsA("BasePart") then
		local offset = primary.CFrame:PointToObjectSpace(facing.Position)
		correction = -math.atan2(offset.X, offset.Z)
	end
	npc:PivotTo(cframe * CFrame.Angles(0, correction, 0))
	npc.Parent = folder
	if not isCustom then
		for _, part in npc:GetDescendants() do
			if part:IsA("BasePart") then part.Anchored = true; part.CanCollide = false end
		end
		pcall(PlaceholderFactory.ShiftNpcHats, npc, -2.2)
	end
	local groundY = groundYAt(cframe.Position, { npc, marker })
	if groundY then
		local boxCFrame, size = npc:GetBoundingBox()
		npc:PivotTo(npc:GetPivot() + Vector3.new(0, groundY - (boxCFrame.Position.Y - size.Y / 2), 0))
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "IslandKeeperPrompt"
	prompt.ObjectText = ISLANDS.KeeperName or "Island Keeper"
	prompt.ActionText = "TRAVEL"
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = ISLANDS.KeeperPromptDistance or 12
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute("PromptKind", "Talk")
	prompt.Parent = primary
	prompt.Triggered:Connect(function(player)
		if player:GetAttribute("UpgradeInProgress") == true then return end
		if not states[player] then return end
		self:SendState(player, "Open")
	end)
	keeperNpc = npc
	keeperPrompt = prompt
end

--------------------------------------------------------------------------------
-- ЖИЗНЕННЫЙ ЦИКЛ
--------------------------------------------------------------------------------
function IslandService:Init(services)
	Services = services
	remote = ReplicatedStorage.Shared:FindFirstChild("IslandRequest")
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = "IslandRequest"
		remote.Parent = ReplicatedStorage.Shared
	end
	remote.OnServerEvent:Connect(function(player, action, value)
		if typeof(action) ~= "string" then return end
		local now = os.clock()
		if now - (lastRequest[player] or 0) < 0.2 then return end
		lastRequest[player] = now
		if action == "RequestState" then
			self:SendState(player)
		elseif action == "Buy" or action == "UpgradeSmelter" then
			if busy[player] then return end
			if not nearKeeper(player) then
				remote:FireClient(player, "Result", false, "Come closer to the Island Keeper")
				return
			end
			busy[player] = true
			local ok, result, reason = pcall(function()
				if action == "Buy" then
					if typeof(value) ~= "string" then return false, "Unavailable" end
					return self:TryBuy(player, value)
				end
				return self:TryUpgradeSmelter(player)
			end)
			busy[player] = nil
			if not ok then
				warn("[IslandService] Покупка упала:", result)
				result, reason = false, "Something went wrong"
			end
			remote:FireClient(player, "Result", result == true, reason, action, value)
			self:SendState(player)
		end
	end)
end

function IslandService:Start()
	if not ISLANDS.Enabled then return end
	local ok, err = pcall(function() self:_spawnKeeper() end)
	if not ok then warn("[IslandService] НПС островов не создан:", err) end

	-- Табло плавилен — раз в секунду (таймеры и готовность).
	task.spawn(function()
		while true do
			task.wait(1)
			for player in states do
				pcall(function() self:_updateSmelter(player) end)
			end
		end
	end)
end

function IslandService:SetupPlot(player, plot)
	local data = profileOf(player)
	if not data then return end
	migrate(player, data)
	states[player] = { Plot = plot, Models = {}, Rising = {}, Smelter = nil, Connections = {}, PendingIngots = {} }
	syncAttributes(player)
	if not ISLANDS.Enabled then return end
	for _, id in ISLANDS.Order do
		if data.Islands[id] then
			local ok, err = pcall(function() self:_buildIsland(player, id, false) end)
			if not ok then warn(("[IslandService] Остров %s для %s не построен: %s"):format(id, player.Name, tostring(err))) end
		end
	end
	-- Смена руды в руках меняет текст промпта плавильни.
	for _, attribute in { "HeldOre", "HeldOreSmelted" } do
		table.insert(states[player].Connections, player:GetAttributeChangedSignal(attribute):Connect(function()
			pcall(function() self:_updateSmelter(player) end)
		end))
	end
end

-- Ребёрт сжигает руду в инвентаре — и в печи тоже (см. RebirthService).
function IslandService:OnRebirth(player)
	local data = profileOf(player)
	if not data then return end
	data.SmelterSlots = {}
	local state = states[player]
	if state then
		for crystal in state.PendingIngots do
			if crystal.Parent then crystal:Destroy() end
		end
		table.clear(state.PendingIngots)
	end
	self:_updateSmelter(player)
end

function IslandService:CleanupPlayer(player)
	local state = states[player]
	if state then
		for _, connection in state.Connections do connection:Disconnect() end
		-- Неподобранные слитки возвращаются в печь готовыми — профиль
		-- сохраняется ПОСЛЕ этой уборки (DataService:UnloadProfile последний).
		local data = profileOf(player)
		for crystal, slot in state.PendingIngots do
			if data then restoreReadySlot(data, slot) end
			if crystal.Parent then crystal:Destroy() end
		end
		table.clear(state.PendingIngots)
	end
	states[player] = nil
	lastRequest[player] = nil
	busy[player] = nil
end

return IslandService
