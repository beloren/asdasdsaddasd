-- Run this entire file once from Roblox Studio's Command Bar.
-- It creates a visible, editable Workspace/LeaderboardBoards model.
-- After editing, drag the model into ReplicatedStorage/Assets.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Selection = game:GetService("Selection")

local assets = ReplicatedStorage:FindFirstChild("Assets")
if not assets then
	assets = Instance.new("Folder")
	assets.Name = "Assets"
	assets.Parent = ReplicatedStorage
end

local existing = assets:FindFirstChild("LeaderboardBoards")
if existing then
	existing:Destroy()
end
local existingPreview = workspace:FindFirstChild("LeaderboardBoards")
if existingPreview then
	existingPreview:Destroy()
end

local model = Instance.new("Model")
model.Name = "LeaderboardBoards"

local function makePart(name, size, cframe, color, material, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent or model
	return part
end

local root = makePart(
	"Root",
	Vector3.new(27, 0.5, 3),
	CFrame.new(0, -0.75, 0),
	Color3.fromRGB(38, 41, 48),
	Enum.Material.Metal
)
root.Transparency = 0
root.CanCollide = true
root.CanQuery = true
model.PrimaryPart = root

local boardSpecs = {
	{
		Name = "MoneyBoard",
		DisplayName = "TOP MONEY",
		X = -8.5,
		Accent = Color3.fromRGB(255, 211, 75),
	},
	{
		Name = "RebirthBoard",
		DisplayName = "TOP PRESTIGE",
		X = 0,
		Accent = Color3.fromRGB(105, 225, 255),
	},
	{
		Name = "CartDamageBoard",
		DisplayName = "TOP CART DAMAGE",
		X = 8.5,
		Accent = Color3.fromRGB(255, 105, 105),
	},
}

for _, spec in boardSpecs do
	local group = Instance.new("Model")
	group.Name = spec.Name .. "Assembly"
	group.Parent = model

	-- LeaderboardService finds these three BaseParts by their exact names and
	-- creates the runtime SurfaceGui on their Front face.
	local board = makePart(
		spec.Name,
		Vector3.new(8, 10, 0.5),
		CFrame.new(spec.X, 5.5, 0),
		Color3.fromRGB(24, 26, 32),
		Enum.Material.SmoothPlastic,
		group
	)
	board.CanCollide = true
	board.CanQuery = true
	board:SetAttribute("DisplayName", spec.DisplayName)
	board:SetAttribute("SurfaceGuiFace", "Front")

	makePart(
		"TopTrim",
		Vector3.new(8.4, 0.35, 0.7),
		board.CFrame * CFrame.new(0, 5.15, 0),
		spec.Accent,
		Enum.Material.Neon,
		group
	)
	makePart(
		"BottomTrim",
		Vector3.new(8.4, 0.25, 0.7),
		board.CFrame * CFrame.new(0, -5.15, 0),
		spec.Accent,
		Enum.Material.Neon,
		group
	)
	makePart(
		"LeftPost",
		Vector3.new(0.3, 11, 0.7),
		board.CFrame * CFrame.new(-4.15, -0.35, 0),
		Color3.fromRGB(42, 45, 54),
		Enum.Material.Metal,
		group
	)
	makePart(
		"RightPost",
		Vector3.new(0.3, 11, 0.7),
		board.CFrame * CFrame.new(4.15, -0.35, 0),
		Color3.fromRGB(42, 45, 54),
		Enum.Material.Metal,
		group
	)
	makePart(
		"Stand",
		Vector3.new(0.65, 1, 0.65),
		board.CFrame * CFrame.new(0, -5.7, 0),
		Color3.fromRGB(55, 58, 68),
		Enum.Material.Metal,
		group
	)
end

model.Parent = workspace

local camera = workspace.CurrentCamera
if camera then
	local targetPosition = camera.CFrame.Position + camera.CFrame.LookVector * 35
	local uprightCameraPosition = Vector3.new(camera.CFrame.Position.X, targetPosition.Y, camera.CFrame.Position.Z)
	model:PivotTo(CFrame.lookAt(targetPosition, uprightCameraPosition))
end
Selection:Set({ model })

print("[BuildLeaderboardBoards] Created visible Workspace/LeaderboardBoards preview")
print("After editing, drag LeaderboardBoards into ReplicatedStorage/Assets.")
print("Required parts: MoneyBoard, RebirthBoard, CartDamageBoard. Keep Root as PrimaryPart.")
print("The Front face of each board must point toward the players.")
