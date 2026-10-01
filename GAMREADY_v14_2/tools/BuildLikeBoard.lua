-- BuildLikeBoard (v20.122): ДЕРЕВЯННЫЙ СТЕНД ТАБЛО ЛАЙКОВ для LikeGoalService.
-- Вставь целиком в Command Bar Studio и нажми Enter (сначала синхронизируй Rojo).
-- Стенд встаёт на землю туда, куда смотрит камера, лицом к камере.
--
-- ЧТО ПОЛУЧИШЬ: Workspace.LikeGoalBoard (Model):
--   Board  - доска: сервер рисует табло на её ПЕРЕДНЕЙ грани (Front)
--            тем же Shared.LikeBoardGui, что и здесь;
--   остальное - декор (столбы, козырёк, полка) - меняй как хочешь.
-- Сейчас на доске ПРИМЕР: 6 лайков из 100 (Config.LikeGoals.CurrentLikes).
-- Не переименовывай модель LikeGoalBoard и деталь Board. Ctrl+Z откатывает.

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local recording = ChangeHistoryService:TryBeginRecording("BuildLikeBoard")

local WOOD = Color3.fromRGB(150, 92, 48)
local WOOD_DARK = Color3.fromRGB(96, 56, 28)
local ROOF = Color3.fromRGB(110, 210, 120)

for _, inst in workspace:GetDescendants() do
	if inst.Name == "LikeGoalBoard" and inst.Parent then inst:Destroy() end
end

local camera = workspace.CurrentCamera
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
local hit = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * 600, params)
local ground = hit and hit.Position or (camera.CFrame.Position + camera.CFrame.LookVector * 60)
local toCamera = Vector3.new(camera.CFrame.Position.X - ground.X, 0, camera.CFrame.Position.Z - ground.Z)
if toCamera.Magnitude < 0.1 then toCamera = Vector3.new(0, 0, 1) end
local baseCF = CFrame.lookAt(ground, ground + toCamera.Unit)

local model = Instance.new("Model")
model.Name = "LikeGoalBoard"

local function box(name, size, offset, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = baseCF * CFrame.new(offset)
	p.Color = color
	p.Material = Enum.Material.WoodPlanks
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local W, H = 16, 11.2 -- доска 1000x700 = 16x11.2 стада
local bottom = 3
box("PostLeft", Vector3.new(1.2, bottom + H + 1.5, 1.2), Vector3.new(-W / 2 - 0.6, (bottom + H + 1.5) / 2, 0), WOOD_DARK)
box("PostRight", Vector3.new(1.2, bottom + H + 1.5, 1.2), Vector3.new(W / 2 + 0.6, (bottom + H + 1.5) / 2, 0), WOOD_DARK)
local board = box("Board", Vector3.new(W, H, 0.6), Vector3.new(0, bottom + H / 2, 0), WOOD)
board.Material = Enum.Material.SmoothPlastic
box("Frame", Vector3.new(W + 2.4, 0.8, 1.2), Vector3.new(0, bottom - 0.4, 0), WOOD_DARK)
box("Shelf", Vector3.new(W + 1, 0.5, 2), Vector3.new(0, bottom - 1, -0.6), WOOD)
local roof = box("Roof", Vector3.new(W + 4, 0.8, 3.4), Vector3.new(0, bottom + H + 1.9, 0), ROOF)
roof.Material = Enum.Material.SmoothPlastic
box("RoofRidge", Vector3.new(W + 4.4, 0.5, 0.8), Vector3.new(0, bottom + H + 2.5, 0), WOOD_DARK)
model.PrimaryPart = board
model.Parent = workspace

-- Пример табло тем же модулем, что рисует сервер.
local shared = ReplicatedStorage:FindFirstChild("Shared")
if shared and shared:FindFirstChild("LikeBoardGui") then
	local fresh = shared:Clone() -- Command Bar кэширует модули после синхронизации Rojo
	local okConfig, Config = pcall(require, fresh.Config)
	local ok, LikeBoardGui = pcall(require, fresh.LikeBoardGui)
	if ok and okConfig then
		local goals = Config.LikeGoals or {}
		LikeBoardGui.Draw(board, goals, goals.CurrentLikes or 6)
	else
		warn("[BuildLikeBoard] Не удалось нарисовать пример:", ok and Config or LikeBoardGui)
	end
	fresh:Destroy()
else
	warn("[BuildLikeBoard] Нет ReplicatedStorage.Shared.LikeBoardGui - сначала синхронизируй Rojo.")
end

if recording then ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit) end
print("[BuildLikeBoard] Готово: Workspace.LikeGoalBoard (доска - Board, грань Front).")
