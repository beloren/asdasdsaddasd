--------------------------------------------------------------------------------
-- AddIslandMarkers — вставляет в модели островов (ReplicatedStorage.Assets/
-- Island_Anvil, Island_Income, Island_Smelter) маркеры построек, которые
-- можно ТАСКАТЬ и КРУТИТЬ мышкой в Studio.
--
--   Island_Anvil   → StationMarker  (наковальня жеод)
--   Island_Income  → PodiumMarker   (подиум кристалла), SafeMarker (сейф)
--   Island_Smelter → StationMarker  (плавильня)
--
-- Маркер — модель: жёлтая плита 4×0.2×4 ("Plate") со стрелкой. СТРЕЛКА =
-- куда смотрит «лицо» постройки. Постройка встаёт по центру плиты на её
-- НИЖНЮЮ грань — положите плиту на землю острова. Выделяйте модель маркера
-- целиком и двигайте/крутите её. В игре маркер невидим (IslandService). Можно вместо поворота маркера положить
-- рядом деталь "<Имя>Look" — постройка будет смотреть на неё.
--
-- Уже существующие маркеры не трогаются. Без модели острова в Assets
-- (кодовый остров) позицию и поворот задают Config.Islands.Definitions.
-- <Id>.Stations (Offset, Yaw) — там же стартовые значения для маркеров.
--
-- Запуск: Studio → View → Command Bar (Edit Mode), вставить файл и Enter.
-- Чтобы увидеть остров: перетащите модель из Assets в Workspace, поправьте
-- маркеры, верните модель в ReplicatedStorage.Assets.
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local assets = ReplicatedStorage:FindFirstChild("Assets")
local COLOR = Color3.fromRGB(255, 210, 60)

local function findIsland(name)
	local direct = assets and assets:FindFirstChild(name)
	if direct then return direct end
	return workspace:FindFirstChild(name, true)
end

local function part(parent, name, size, cframe, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Маркер = МОДЕЛЬ: плита "Plate" (PrimaryPart) + стрелка из трёх планок.
-- Выделяете модель и двигаете/крутите целиком (Move/Rotate или Ctrl+R).
local function makeMarker(island, name, cframe)
	local marker = Instance.new("Model")
	marker.Name = name
	local plate = part(marker, "Plate", Vector3.new(4, 0.2, 4), cframe * CFrame.new(0, 0.1, 0), COLOR)
	plate.Transparency = 0.35
	marker.PrimaryPart = plate
	-- Стрелка лежит на плите и смотрит вперёд (-Z плиты) — туда будет
	-- смотреть «лицо» постройки.
	local red = Color3.fromRGB(255, 90, 60)
	part(marker, "ArrowShaft", Vector3.new(0.4, 0.2, 2.6), plate.CFrame * CFrame.new(0, 0.2, -0.3), red)
	part(marker, "ArrowLeft", Vector3.new(0.4, 0.2, 1.5), plate.CFrame * CFrame.new(-0.42, 0.2, -1.2) * CFrame.Angles(0, math.rad(-40), 0), red)
	part(marker, "ArrowRight", Vector3.new(0.4, 0.2, 1.5), plate.CFrame * CFrame.new(0.42, 0.2, -1.2) * CFrame.Angles(0, math.rad(40), 0), red)

	local label = Instance.new("BillboardGui")
	label.Name = "MarkerLabel"
	label.Size = UDim2.fromOffset(160, 30)
	label.StudsOffset = Vector3.new(0, 2.5, 0)
	label.AlwaysOnTop = true
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.GothamBold
	text.TextColor3 = COLOR
	text.TextStrokeTransparency = 0.3
	text.Text = name
	text.Parent = label
	label.Parent = plate

	marker.Parent = island
	return marker
end

local added = 0
for islandId, definition in Config.Islands.Definitions do
	local island = findIsland(definition.Model or ("Island_" .. islandId))
	if not (island and island:IsA("Model")) then
		print(("[AddIslandMarkers] %s: модели %s нет в Assets - место задаётся в Config.Islands.Definitions.%s.Stations"):format(islandId, definition.Model or "?", islandId))
		continue
	end
	local primary = island.PrimaryPart or island:FindFirstChildWhichIsA("BasePart", true)
	local boxCFrame, boxSize = island:GetBoundingBox()
	local rotation = primary and primary.CFrame.Rotation or CFrame.new()
	-- Центр верха острова (по габариту): плиту потом опустите на землю.
	local top = CFrame.new(boxCFrame.Position + Vector3.new(0, boxSize.Y / 2, 0)) * rotation
	for name, spec in definition.Stations or {} do
		if island:FindFirstChild(name, true) then
			print(("[AddIslandMarkers] %s/%s уже есть - не трогаю"):format(island.Name, name))
		else
			local offset = spec.Offset or Vector3.zero
			makeMarker(island, name, top * CFrame.new(offset) * CFrame.Angles(0, math.rad(spec.Yaw or 0), 0))
			added += 1
			print(("[AddIslandMarkers] %s/%s добавлен"):format(island.Name, name))
		end
	end
end
print(("[AddIslandMarkers] готово, добавлено маркеров: %d"):format(added))
