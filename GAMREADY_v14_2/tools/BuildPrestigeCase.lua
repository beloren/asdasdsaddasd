--------------------------------------------------------------------------------
-- BuildPrestigeCase — создаёт модель сундука престижа (та же, что заглушка
-- в игре: PrestigeService buildPlaceholderCase), чтобы доработать её в Studio.
-- Studio → View → Command Bar → вставить файл → Enter.
--
-- Модель появляется в Workspace перед камерой и сразу выделяется.
-- Доработал - перетащи её в ReplicatedStorage/Assets с именем "PrestigeCase"
-- (Config.Prestige.CaseModelName) - игра возьмёт её на всех базах.
-- Где стоит на базе - маркер PrestigeCaseMarker (+ PrestigeCaseMarkerLook)
-- в ReplicatedStorage/Assets/PlotTemplate.
-- PrimaryPart = Body: промпт VIEW PERKS вешается на неё.
--------------------------------------------------------------------------------
local Selection = game:GetService("Selection")

local camera = workspace.CurrentCamera
local spot = camera and (camera.CFrame.Position + camera.CFrame.LookVector * 12) or Vector3.new(0, 5, 0)
local base = CFrame.new(spot)

local model = Instance.new("Model")
model.Name = "PrestigeCase"

local body = Instance.new("Part")
body.Name = "Body"
body.Size = Vector3.new(3.2, 2.2, 1.1)
body.Color = Color3.fromRGB(110, 70, 40)
body.Material = Enum.Material.Leather
body.Anchored = true
body.CanCollide = true
body.CFrame = base
body.Parent = model

local trim = Instance.new("Part")
trim.Name = "Trim"
trim.Size = Vector3.new(3.3, 0.25, 1.15)
trim.Color = Color3.fromRGB(255, 200, 70)
trim.Material = Enum.Material.Metal
trim.Anchored = true
trim.CanCollide = false
trim.CFrame = base * CFrame.new(0, 0.3, 0)
trim.Parent = model

local handle = Instance.new("Part")
handle.Name = "Handle"
handle.Size = Vector3.new(1.2, 0.3, 0.3)
handle.Color = Color3.fromRGB(60, 40, 25)
handle.Anchored = true
handle.CanCollide = false
handle.CFrame = base * CFrame.new(0, 1.25, 0)
handle.Parent = model

model.PrimaryPart = body
model.Parent = workspace
Selection:Set({ model })
print("[BuildPrestigeCase] Модель PrestigeCase создана в Workspace и выделена. Доработай и перенеси в ReplicatedStorage/Assets.")
