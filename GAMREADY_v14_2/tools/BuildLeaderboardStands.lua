-- BuildLeaderboardStands: СТЕНДЫ ТОПОВ (деньги / престиж / донат) для
-- LeaderboardService. Вставь целиком в Command Bar Studio и нажми Enter.
-- Стенды встают на землю туда, куда смотрит камера, лицом к камере.
--
-- ЧТО ПОЛУЧИШЬ: Workspace.LeaderboardStands с тремя моделями MoneyStand,
-- PrestigeStand, DonationStand. В каждой:
--   Board       - доска: сервер рисует топ-10 на её ПЕРЕДНЕЙ грани (Front);
--   Plate       - табличка «#1 ник · значение» (тоже передняя грань);
--   StatueSpot  - маркер: здесь встанет R6-риг игрока с 1-го места,
--                 смотрит туда же, куда перёд маркера (в игре невидим);
--   остальное   - декор (столбы, шапка, постамент) - меняй как хочешь.
-- v20.117: стенды деревянные, таблица на доске - тот же деревянный вид, что
-- рисует игра (Shared.LeaderboardBoardGui; сначала синхронизируй Rojo).
-- Сейчас на досках и табличке ПРИМЕР (LeaderboardGui / PlateGui), на
-- постаменте - R6-манекен StatuePreview: в игре сервер поставит на его
-- место R6-риг игрока с 1-го места (с одеждой и аксессуарами).
--
-- Двигай/крути/перекрашивай модели как нужно. Главное - не переименовывай
-- модели и детали Board / Plate / StatueSpot. Старые LeaderboardStands (в
-- т.ч. из BuildIslandMap) этот скрипт удаляет - остаются только новые.
-- Ctrl+Z откатывает.

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Players = game:GetService("Players")
local recording = ChangeHistoryService:TryBeginRecording("BuildLeaderboardStands")

local SPACING = 17 -- расстояние между стендами
local SPECS = {
	-- Названия и цвета как в игре (LeaderboardService SPECS).
	{ Name = "MoneyStand", Key = "Money", Title = "Top Money", Color = Color3.fromRGB(110, 240, 140), Sample = "$1.2B" },
	{ Name = "PrestigeStand", Key = "Rebirths", Title = "Top Prestige", Color = Color3.fromRGB(255, 95, 120), Sample = "42" },
	{ Name = "DonationStand", Key = "Donated", Title = "Top Robux Spent", Color = Color3.fromRGB(255, 214, 60), Sample = "R$ 5.0K" },
}

-- Убираем старые стенды.
for _, inst in workspace:GetDescendants() do
	if inst.Name == "LeaderboardStands" and inst.Parent then inst:Destroy() end
end

-- Точка на земле перед камерой.
local camera = workspace.CurrentCamera
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
local hit = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * 600, params)
local ground = hit and hit.Position or (camera.CFrame.Position + camera.CFrame.LookVector * 60)
local toCamera = Vector3.new(camera.CFrame.Position.X - ground.X, 0, camera.CFrame.Position.Z - ground.Z)
if toCamera.Magnitude < 0.1 then toCamera = Vector3.new(0, 0, 1) end
-- Перёд группы (-Z) смотрит на камеру.
local groupCF = CFrame.lookAt(ground, ground + toCamera.Unit)

local function box(parent, name, size, cf, color, props)
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


-- v20.117: ПРИМЕР ТАБЛИЦЫ - тем же модулем, что рисует сервер
-- (Shared.LeaderboardBoardGui): в Studio видно ровно то, что будет в игре.
local BoardGui = nil
do
	local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
	local module = shared and shared:FindFirstChild("LeaderboardBoardGui")
	if module then
		-- свежая копия папки: Command Bar кэширует модули после синхронизации Rojo
		local fresh = shared:Clone()
		local ok, result = pcall(require, fresh.LeaderboardBoardGui)
		if ok then BoardGui = result else warn("[BuildLeaderboardStands] LeaderboardBoardGui:", result) end
	else
		warn("[BuildLeaderboardStands] Нет ReplicatedStorage.Shared.LeaderboardBoardGui - сначала синхронизируй Rojo. Пример таблицы будет простым.")
	end
end

local function previewBoard(board, spec)
	if not BoardGui then return end
	local entries = {}
	for rank = 1, 10 do
		table.insert(entries, { Name = "Player" .. rank, Value = spec.Sample })
	end
	BoardGui.Board(board, { Key = spec.Key, Title = spec.Title, Color = spec.Color }, entries, {
		Format = function(_, value) return value end,
	})
end

local function previewPlate(plate, spec)
	if not BoardGui then return end
	BoardGui.Plate(plate, { Color = spec.Color }, "#1 Player1", spec.Sample)
end

-- Манекен R6 на месте лидера (в игре его заменит риг игрока с 1-го места).
local function previewStatue(stand, spot)
	local rig
	pcall(function()
		rig = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R6)
	end)
	if not rig then
		-- запасной кубический манекен
		rig = Instance.new("Model")
		local function limb(name, size, offset)
			box(rig, name, size, CFrame.new(offset), Color3.fromRGB(163, 162, 165), {})
		end
		limb("Left Leg", Vector3.new(1, 2, 1), Vector3.new(-0.5, 1, 0))
		limb("Right Leg", Vector3.new(1, 2, 1), Vector3.new(0.5, 1, 0))
		limb("Torso", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0))
		limb("Left Arm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 3, 0))
		limb("Right Arm", Vector3.new(1, 2, 1), Vector3.new(1.5, 3, 0))
		limb("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 4.6, 0))
	end
	rig.Name = "StatuePreview"
	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid then humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end
	local look = spot.CFrame.LookVector
	rig:PivotTo(CFrame.lookAt(spot.Position, spot.Position + Vector3.new(look.X, 0, look.Z)))
	local boxCF, size = rig:GetBoundingBox()
	local topY = spot.Position.Y + spot.Size.Y / 2
	rig:PivotTo(rig:GetPivot() + Vector3.new(0, topY - (boxCF.Position.Y - size.Y / 2), 0))
	rig.Parent = stand
end

local folder = Instance.new("Model")
folder.Name = "LeaderboardStands"
folder.Parent = workspace

for index, spec in SPECS do
	local stand = Instance.new("Model")
	stand.Name = spec.Name
	stand.Parent = folder
	local cf = groupCF * CFrame.new((index - 2) * SPACING, 0, 0)
	-- v20.117: ДЕРЕВЯННЫЙ СТЕНД (столбы, рама из досок, крыша-козырёк).
	local woodDark, wood, plankColor = Color3.fromRGB(96, 56, 28), Color3.fromRGB(150, 92, 48), Color3.fromRGB(205, 136, 78)
	local woodProps = { Material = Enum.Material.WoodPlanks }
	for _, x in { -7.2, 7.2 } do
		box(stand, "Post", Vector3.new(1.3, 25, 1.3), cf * CFrame.new(x, 12.5, 0.4), woodDark, { Material = Enum.Material.Wood })
	end
	local board = box(stand, "Board", Vector3.new(13, 16, 0.8), cf * CFrame.new(0, 16, 0), wood, woodProps)
	-- рама вокруг доски
	box(stand, "FrameTop", Vector3.new(14.2, 0.8, 1.2), cf * CFrame.new(0, 24.3, 0.1), woodDark, woodProps)
	box(stand, "FrameBottom", Vector3.new(14.2, 0.8, 1.2), cf * CFrame.new(0, 7.7, 0.1), woodDark, woodProps)
	-- козырёк из двух скатов и конёк цвета категории
	box(stand, "RoofLeft", Vector3.new(8.4, 0.6, 3.2), cf * CFrame.new(-3.9, 26.2, 0.2) * CFrame.Angles(0, 0, math.rad(14)), plankColor, woodProps)
	box(stand, "RoofRight", Vector3.new(8.4, 0.6, 3.2), cf * CFrame.new(3.9, 26.2, 0.2) * CFrame.Angles(0, 0, math.rad(-14)), plankColor, woodProps)
	box(stand, "Header", Vector3.new(1.2, 1.2, 3.4), cf * CFrame.new(0, 27.2, 0.2), spec.Color)
	-- подпорка-доска под рамой
	box(stand, "Shelf", Vector3.new(14.2, 0.5, 2.2), cf * CFrame.new(0, 7.2, -0.4), plankColor, woodProps)
	box(stand, "PedestalBase", Vector3.new(6.4, 1, 6.4), cf * CFrame.new(0, 0.5, -7), Color3.fromRGB(96, 98, 112))
	box(stand, "Pedestal", Vector3.new(5, 2, 5), cf * CFrame.new(0, 2, -7), Color3.fromRGB(150, 152, 164))
	box(stand, "PedestalTop", Vector3.new(5.6, 0.5, 5.6), cf * CFrame.new(0, 3.25, -7), spec.Color)
	local plate = box(stand, "Plate", Vector3.new(4.4, 1.4, 0.2), cf * CFrame.new(0, 2, -9.6), woodDark, woodProps)
	local spot = box(stand, "StatueSpot", Vector3.new(2, 0.2, 2), cf * CFrame.new(0, 3.6, -7), Color3.new(1, 1, 1), {
		Transparency = 0.5, CanCollide = false, CanQuery = false, CanTouch = false,
	})
	spot:SetAttribute("MapMarker", true) -- в игре станет невидимым (WorldService)
	previewBoard(board, spec)
	previewPlate(plate, spec)
	previewStatue(stand, spot)
end

if recording then ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit) end
game:GetService("Selection"):Set({ folder })
print("[BuildLeaderboardStands] Готово: Workspace.LeaderboardStands (3 стенда) выделены - двигай и меняй как нужно.")
