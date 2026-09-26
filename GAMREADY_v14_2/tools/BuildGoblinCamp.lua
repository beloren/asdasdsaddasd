-- BuildGoblinCamp: создаёт Workspace/GoblinCamp (Zone + Spawns + Marker) для
-- лагеря гоблинов (GoblinCampService). Вставь целиком в Command Bar Studio и
-- нажми Enter. Лагерь ставится на землю в точке, куда смотрит камера.
-- Уже есть GoblinCamp: недостающие части добавятся, свои не тронутся.
-- Размер лагеря и число точек появления меняются в первых строках.
local SIZE_X, SIZE_Z, HEIGHT = 90, 90, 30 -- размер зоны в стадах
local SPAWN_COUNT = 6                     -- сколько точек появления (по кругу)
local SPAWN_RADIUS = 0.3                  -- радиус круга (доля от размера зоны)

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local recording = ChangeHistoryService:TryBeginRecording("BuildGoblinCamp")

local camera = workspace.CurrentCamera
local camp = workspace:FindFirstChild("GoblinCamp")
local center
local zone = camp and camp:FindFirstChild("Zone")
if zone and zone:IsA("BasePart") then
	center = zone.Position - Vector3.new(0, zone.Size.Y / 2, 0)
else
	-- Точка на земле, куда смотрит камера (до 1000 стадов).
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { camp }
	local hit = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * 1000, params)
	center = hit and hit.Position or (camera.CFrame.Position + camera.CFrame.LookVector * 60)
end

if not camp then
	camp = Instance.new("Model")
	camp.Name = "GoblinCamp"
	camp.Parent = workspace
end

local function helperPart(name, size, cframe, color, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Locked = false
	part.Material = Enum.Material.ForceField
	part.Color = color
	part.Transparency = 1 -- в игре не видно; выдели в Explorer, чтобы увидеть рамку
	part.Parent = parent
	return part
end

-- Zone: коробка лагеря. Низ чуть ниже земли, верх на HEIGHT выше.
if not (zone and zone:IsA("BasePart")) then
	zone = helperPart("Zone", Vector3.new(SIZE_X, HEIGHT, SIZE_Z),
		CFrame.new(center + Vector3.new(0, HEIGHT / 2 - 2, 0)), Color3.fromRGB(255, 70, 70), camp)
	local box = Instance.new("SelectionBox")
	box.Name = "ZoneOutline"
	box.Adornee = zone
	box.Color3 = Color3.fromRGB(255, 90, 60)
	box.LineThickness = 0.15
	box.Visible = false -- включи Visible, чтобы видеть рамку в Studio
	box.Parent = zone
end

-- Spawns: точки появления по кругу внутри зоны, на земле.
local spawns = camp:FindFirstChild("Spawns")
if not spawns then
	spawns = Instance.new("Folder")
	spawns.Name = "Spawns"
	spawns.Parent = camp
end
if #spawns:GetChildren() == 0 then
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { camp }
	local radius = math.min(SIZE_X, SIZE_Z) * SPAWN_RADIUS
	for i = 1, SPAWN_COUNT do
		local angle = (i - 1) / SPAWN_COUNT * math.pi * 2
		local flat = zone.Position + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local hit = workspace:Raycast(flat + Vector3.new(0, HEIGHT, 0), Vector3.new(0, -HEIGHT * 3, 0), params)
		local ground = hit and hit.Position or Vector3.new(flat.X, center.Y, flat.Z)
		helperPart("Spawn" .. i, Vector3.new(2, 1, 2), CFrame.new(ground + Vector3.new(0, 0.5, 0)), Color3.fromRGB(90, 220, 90), spawns)
	end
end

-- Marker: над ним висит табличка лагеря (таймер волны, дроп).
if not camp:FindFirstChild("Marker") then
	helperPart("Marker", Vector3.new(2, 2, 2), CFrame.new(zone.Position.X, center.Y + 1, zone.Position.Z), Color3.fromRGB(255, 210, 60), camp)
end

camp.PrimaryPart = zone
if recording then ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit) end
game:GetService("Selection"):Set({ camp })
print(("[BuildGoblinCamp] Готово: Workspace.GoblinCamp в %s, зона %dx%d, точек появления: %d. Двигай модель целиком или отдельные Spawn-ы; зона не должна пересекаться с базами игроков.")
	:format(tostring(Vector3.new(math.floor(center.X), math.floor(center.Y), math.floor(center.Z))), SIZE_X, SIZE_Z, #spawns:GetChildren()))
