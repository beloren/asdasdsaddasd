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
	{ Name = "MoneyStand", Title = "TOP MONEY", Color = Color3.fromRGB(255, 211, 75), Sample = "$1.2B" },
	{ Name = "PrestigeStand", Title = "TOP PRESTIGE", Color = Color3.fromRGB(105, 225, 255), Sample = "42" },
	{ Name = "DonationStand", Title = "TOP DONATION", Color = Color3.fromRGB(255, 120, 200), Sample = "R$ 5.0K" },
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

local function text(parent, name, value, color, props)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	label.TextScaled = true
	label.Text = value
	label.TextColor3 = color
	for k, v in props or {} do label[k] = v end
	label.Parent = parent
	return label
end

-- Пример таблицы (в игре сервер нарисует свою с настоящими данными).
local function previewBoard(board, spec)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LeaderboardGui"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(700, 900)
	gui.LightInfluence = 0
	gui.Parent = board
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	text(bg, "Title", spec.Title, Color3.fromRGB(20, 22, 26), {
		Size = UDim2.new(1, 0, 0, 110), BackgroundTransparency = 0, BackgroundColor3 = spec.Color, BorderSizePixel = 0,
	})
	for rank = 1, 10 do
		local row = Instance.new("Frame")
		row.Position = UDim2.new(0, 20, 0, 125 + (rank - 1) * 73)
		row.Size = UDim2.new(1, -40, 0, 62)
		row.BackgroundColor3 = rank % 2 == 1 and Color3.fromRGB(31, 34, 43) or Color3.fromRGB(25, 28, 36)
		row.BorderSizePixel = 0
		row.Parent = bg
		text(row, "Rank", "#" .. rank, rank <= 3 and spec.Color or Color3.fromRGB(185, 190, 200), { Size = UDim2.new(0, 70, 1, 0) })
		text(row, "Name", "Player" .. rank, Color3.new(1, 1, 1), {
			Position = UDim2.new(0, 75, 0, 0), Size = UDim2.new(1, -255, 1, 0), TextXAlignment = Enum.TextXAlignment.Left,
		})
		text(row, "Value", spec.Sample, spec.Color, {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 175, 1, 0), TextXAlignment = Enum.TextXAlignment.Right,
		})
	end
end

local function previewPlate(plate, spec)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "PlateGui"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(460, 140)
	gui.LightInfluence = 0
	gui.Parent = plate
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	frame.BorderSizePixel = 0
	frame.Parent = gui
	text(frame, "NameText", "#1 Player1", Color3.new(1, 1, 1), { Size = UDim2.fromScale(1, 0.58) })
	text(frame, "ValueText", spec.Sample, spec.Color, { Position = UDim2.fromScale(0, 0.58), Size = UDim2.fromScale(1, 0.42) })
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
	local wood, woodDark = Color3.fromRGB(40, 32, 26), Color3.fromRGB(120, 78, 48)
	for _, x in { -7, 7 } do
		box(stand, "Post", Vector3.new(1.2, 25, 1.2), cf * CFrame.new(x, 12.5, 0.4), woodDark)
	end
	local board = box(stand, "Board", Vector3.new(13, 16, 0.8), cf * CFrame.new(0, 16, 0), wood)
	box(stand, "Header", Vector3.new(15.4, 1.6, 1.4), cf * CFrame.new(0, 24.8, 0.2), spec.Color)
	box(stand, "PedestalBase", Vector3.new(6.4, 1, 6.4), cf * CFrame.new(0, 0.5, -7), Color3.fromRGB(96, 98, 112))
	box(stand, "Pedestal", Vector3.new(5, 2, 5), cf * CFrame.new(0, 2, -7), Color3.fromRGB(150, 152, 164))
	box(stand, "PedestalTop", Vector3.new(5.6, 0.5, 5.6), cf * CFrame.new(0, 3.25, -7), spec.Color)
	local plate = box(stand, "Plate", Vector3.new(4.4, 1.4, 0.2), cf * CFrame.new(0, 2, -9.6), Color3.fromRGB(30, 30, 36))
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
