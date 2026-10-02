--------------------------------------------------------------------------------
-- BuildRubbleBoulderSpawnPoints (v20.132) — ТОЧКИ ДИКИХ ВАЛУНОВ (вне баз).
-- Запуск: вставь в Command Bar Studio и нажми Enter.
--
-- Добавляет точки в workspace.RubbleBoulderSpawnPoints (папку создаёт, если
-- её нет). Твои уже расставленные точки НЕ удаляются - скрипт только
-- докладывает новые до TARGET_COUNT штук, кольцами вокруг банка, ставя их на
-- землю. Дальше двигай/копируй/удаляй их мышкой как хочешь.
--
-- ПРАВИЛА (RockService):
--   • сколько точек - столько и валунов (Config.Boulders.MaxActive = 0);
--   • тир каждого валуна СЛУЧАЙНЫЙ при каждом появлении (Config.Boulders.
--     RandomTierWeights) - атрибут Tier у точки не нужен;
--   • в игре точки невидимы (видны только в Studio).
--------------------------------------------------------------------------------

local TARGET_COUNT = 36
local RINGS = { { Radius = 75, Count = 12 }, { Radius = 115, Count = 12 }, { Radius = 155, Count = 12 } }

local function findBankPosition()
	for _, instance in workspace:GetDescendants() do
		if instance:IsA("Model") and instance:GetAttribute("IsBank") then
			return instance:GetPivot().Position
		end
	end
	local merchant = workspace:FindFirstChild("BankMerchant")
	if merchant and merchant:IsA("Model") then return merchant:GetPivot().Position end
	return Vector3.new(0, 0, 0)
end

local center = findBankPosition()
local folder = workspace:FindFirstChild("RubbleBoulderSpawnPoints")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "RubbleBoulderSpawnPoints"
	folder.Parent = workspace
end

local existing = {}
for _, child in folder:GetChildren() do
	if child:IsA("BasePart") then table.insert(existing, child) end
end

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = { folder }

local added = 0
local index = #existing
for ringIndex, ring in RINGS do
	for i = 1, ring.Count do
		if index >= TARGET_COUNT then break end
		local angle = (i - 1) / ring.Count * math.pi * 2 + ringIndex * 0.35
		local flat = center + Vector3.new(math.cos(angle) * ring.Radius, 0, math.sin(angle) * ring.Radius)
		-- не ставим вплотную к уже существующей точке
		local tooClose = false
		for _, part in existing do
			if (Vector3.new(part.Position.X, 0, part.Position.Z) - Vector3.new(flat.X, 0, flat.Z)).Magnitude < 14 then
				tooClose = true
				break
			end
		end
		if not tooClose then
			local hit = workspace:Raycast(flat + Vector3.new(0, 200, 0), Vector3.new(0, -400, 0), params)
			local y = hit and hit.Position.Y or center.Y
			index += 1
			local point = Instance.new("Part")
			point.Name = ("BoulderSpawn_%02d"):format(index)
			point.Size = Vector3.new(4, 1, 4)
			point.CFrame = CFrame.new(flat.X, y + 0.5, flat.Z)
			point.Anchored = true
			point.CanCollide = false
			point.CanTouch = false
			point.CanQuery = false
			point.Transparency = 0.3
			point.Material = Enum.Material.Neon
			point.Color = Color3.fromRGB(255, 170, 60)
			point:SetAttribute("MapMarker", true)
			point.Parent = folder
			table.insert(existing, point)
			added += 1
		end
	end
end
print(("[BuildRubbleBoulderSpawnPoints] добавлено точек: %d, всего: %d (сколько точек - столько валунов)"):format(added, #existing))
