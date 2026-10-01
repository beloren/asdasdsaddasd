--------------------------------------------------------------------------------
-- OreBoxModel (v20.109) — 3D-превью коробки руды (торговец, вкладка ORE):
-- деревянный ящик из стадов, сверху сидит сама руда. Своя модель:
-- ReplicatedStorage/Assets/OreBox (руда ставится на её верх).
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)
local OrePreview = require(script.Parent.OrePreview)

local OreBoxModel = {}

local function crate()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local custom = assets and assets:FindFirstChild("OreBox")
	if custom then
		local clone = custom:Clone()
		if clone:IsA("BasePart") then
			local wrap = Instance.new("Model")
			clone.Parent = wrap
			wrap.PrimaryPart = clone
			clone = wrap
		end
		return clone
	end
	local model = Instance.new("Model")
	model.Name = "OreBox"
	local box = Instance.new("Part")
	box.Name = "Crate"
	box.Size = Vector3.new(2.4, 1.6, 2.4)
	box.Color = Color3.fromRGB(150, 98, 52)
	box.Material = Enum.Material.WoodPlanks
	box.TopSurface = Enum.SurfaceType.Studs
	box.BottomSurface = Enum.SurfaceType.Inlet
	box.Anchored = true
	box.CanCollide = false
	box.CFrame = CFrame.new(0, 0.8, 0)
	box.Parent = model
	for _, x in { -1.25, 1.25 } do
		local band = Instance.new("Part")
		band.Name = "Band"
		band.Size = Vector3.new(0.12, 1.7, 2.5)
		band.Color = Color3.fromRGB(90, 58, 30)
		band.Material = Enum.Material.SmoothPlastic
		band.Anchored = true
		band.CanCollide = false
		band.CFrame = CFrame.new(x * 0.6, 0.8, 0)
		band.Parent = model
	end
	model.PrimaryPart = box
	return model
end

function OreBoxModel.Build(oreKey)
	if not (Config.OreByKey and Config.OreByKey[oreKey]) then return nil end
	local model = crate()
	local _, boxSize = model:GetBoundingBox()
	local top = model:GetPivot().Position.Y + boxSize.Y
	local template = OrePreview.Template({ Ore = oreKey, Variant = 2 })
	if template then
		local ore = template:Clone()
		local oreCf, oreSize
		if ore:IsA("Model") then
			oreCf, oreSize = ore:GetBoundingBox()
		else
			oreCf, oreSize = ore.CFrame, ore.Size
		end
		local scale = 1.6 / math.max(oreSize.X, oreSize.Y, oreSize.Z, 0.1)
		if ore:IsA("Model") then
			pcall(ore.ScaleTo, ore, ore:GetScale() * scale)
			oreCf, oreSize = ore:GetBoundingBox()
			ore:PivotTo(ore:GetPivot() + (Vector3.new(0, top + oreSize.Y / 2, 0) - oreCf.Position))
		else
			ore.Size *= scale
			ore.CFrame = CFrame.new(0, top + ore.Size.Y / 2, 0)
		end
		ore.Parent = model
	end
	return model
end

return OreBoxModel
