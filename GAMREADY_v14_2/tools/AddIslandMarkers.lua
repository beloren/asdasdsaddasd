--------------------------------------------------------------------------------
-- AddIslandMarkers — вставляет в модели островов (ReplicatedStorage.Assets/
-- Island_Anvil, Island_Income, Island_Smelter) маркеры построек, которые
-- можно ТАСКАТЬ и КРУТИТЬ мышкой в Studio.
--
--   Island_Anvil   → AnvilMarker   + AnvilMarkerLook   (наковальня жеод)
--   Island_Income  → PodiumMarker  + PodiumMarkerLook  (подиум кристалла)
--                    SafeMarker    + SafeMarkerLook    (сейф)
--   Island_Smelter → SmelterMarker + SmelterMarkerLook (плавильня)
--
-- <Имя>Look - красный кубик: постройка поворачивается ЛИЦОМ К НЕМУ (главнее,
-- чем стрелка на плите). Двигай кубик вокруг плиты - постройка развернётся.
-- Старый маркер StationMarker скрипт сам переименует в новое имя.
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

-- Кубик направления "<Имя>Look" - в 6 стадах перед плитой (по стрелке).
local function makeLook(island, name, markerCFrame)
	local look = part(island, name .. "Look", Vector3.new(1, 1, 1), markerCFrame * CFrame.new(0, 0.6, -6), Color3.fromRGB(255, 70, 70))
	look.Transparency = 0.2
	local label = Instance.new("BillboardGui")
	label.Name = "MarkerLabel"
	label.Size = UDim2.fromOffset(170, 26)
	label.StudsOffset = Vector3.new(0, 1.4, 0)
	label.AlwaysOnTop = true
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.GothamBold
	text.TextColor3 = Color3.fromRGB(255, 120, 100)
	text.TextStrokeTransparency = 0.3
	text.Text = name .. "Look"
	text.Parent = label
	label.Parent = look
	return look
end

local function markerCFrameOf(marker)
	local root = marker:IsA("Model") and (marker.PrimaryPart or marker:FindFirstChild("Plate") or marker:FindFirstChildWhichIsA("BasePart")) or marker
	return root and root:IsA("BasePart") and root.CFrame or nil
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
		-- старое имя (у наковальни и плавильни) -> новое
		local old = island:FindFirstChild("StationMarker", true)
		if old and not island:FindFirstChild(name, true) and (name == "AnvilMarker" or name == "SmelterMarker") then
			old.Name = name
			local oldLook = island:FindFirstChild("StationMarkerLook", true)
			if oldLook then oldLook.Name = name .. "Look" end
			print(("[AddIslandMarkers] %s: StationMarker переименован в %s"):format(island.Name, name))
		end
		local marker = island:FindFirstChild(name, true)
		if marker then
			print(("[AddIslandMarkers] %s/%s уже есть - не трогаю"):format(island.Name, name))
		else
			local offset = spec.Offset or Vector3.zero
			marker = makeMarker(island, name, top * CFrame.new(offset) * CFrame.Angles(0, math.rad(spec.Yaw or 0), 0))
			added += 1
			print(("[AddIslandMarkers] %s/%s добавлен"):format(island.Name, name))
		end
		if not island:FindFirstChild(name .. "Look", true) then
			local cf = markerCFrameOf(marker)
			if cf then
				makeLook(island, name, cf)
				added += 1
				print(("[AddIslandMarkers] %s/%sLook добавлен"):format(island.Name, name))
			end
		end
	end
end
print(("[AddIslandMarkers] готово, добавлено маркеров: %d"):format(added))
