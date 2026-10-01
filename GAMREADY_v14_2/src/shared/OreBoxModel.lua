--------------------------------------------------------------------------------
-- OreBoxModel (v20.109) — 3D-превью коробки руды (торговец, вкладка ORE):
-- деревянный ящик из стадов с рисунком руды на стенках (v20.114). Своя
-- модель: ReplicatedStorage/Assets/OreBox (рисунок - на её PrimaryPart).
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
		band.CFrame = CFrame.new(x * 0.86, 0.8, 0) -- v20.114: к краям, не закрывают рисунок
		band.Parent = model
	end
	model.PrimaryPart = box
	return model
end

-- v20.114: РИСУНОК РУДЫ НА КОРОБКЕ. Есть картинка (Config.MineRework.
-- OreBoxImages[ключ] или ImageId руды) - Decal на четырёх стенках;
-- нет - пиксельный самоцвет цвета руды из плоских брусков (виден и в 3D-
-- превью инвентаря, где SurfaceGui не рисуется).
local GEM = {
	"..###..",
	".#o###.",
	"#######",
	".#####.",
	"..###..",
	"...#...",
}

local function imageFor(oreKey)
	local cfg = Config.MineRework or {}
	local id = (cfg.OreBoxImages and cfg.OreBoxImages[oreKey]) or (Config.OreByKey[oreKey] and Config.OreByKey[oreKey].ImageId)
	id = tonumber(id) or 0
	return id > 0 and ("rbxassetid://" .. id) or nil
end

local function paintFace(model, crate, normal, ore)
	local size = crate.Size
	local depth = math.abs(normal.Z) > 0 and size.Z or size.X
	local faceWidth = math.abs(normal.Z) > 0 and size.X or size.Z
	local pixel = math.min(faceWidth * 0.62 / #GEM[1], size.Y * 0.8 / #GEM)
	local right = Vector3.new(-normal.Z, 0, normal.X)
	local base = crate.CFrame * CFrame.new(normal * (depth / 2 + 0.02))
	local color = ore.Color or Color3.fromRGB(200, 200, 200)
	for row, line in GEM do
		local colIndex = 1
		while colIndex <= #line do
			local ch = line:sub(colIndex, colIndex)
			if ch == "." then
				colIndex += 1
			else
				local runEnd = colIndex
				while runEnd < #line and line:sub(runEnd + 1, runEnd + 1) == ch do runEnd += 1 end
				local count = runEnd - colIndex + 1
				local part = Instance.new("Part")
				part.Name = "Art"
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.Material = Enum.Material.SmoothPlastic
				part.TopSurface = Enum.SurfaceType.Smooth
				part.BottomSurface = Enum.SurfaceType.Smooth
				local shade = row >= 4 and 0.25 or 0
				part.Color = ch == "o" and color:Lerp(Color3.new(1, 1, 1), 0.6) or color:Lerp(Color3.new(0, 0, 0), shade)
				local horizontal = math.abs(normal.Z) > 0
				part.Size = horizontal and Vector3.new(pixel * count, pixel, 0.05) or Vector3.new(0.05, pixel, pixel * count)
				local x = ((colIndex + runEnd) / 2 - (#line + 1) / 2) * pixel
				local y = ((#GEM + 1) / 2 - row) * pixel
				part.CFrame = CFrame.new(base.Position + right * x + Vector3.yAxis * y)
				part.Parent = model
				colIndex = runEnd + 1
			end
		end
	end
end

local function decorate(model, oreKey)
	local crate = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	local ore = Config.OreByKey[oreKey]
	if not (crate and ore) then return end
	local image = imageFor(oreKey)
	if image then
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
			local decal = Instance.new("Decal")
			decal.Name = "OreArt"
			decal.Face = face
			decal.Texture = image
			decal.Parent = crate
		end
		return
	end
	for _, normal in { Vector3.new(0, 0, -1), Vector3.new(0, 0, 1), Vector3.new(-1, 0, 0), Vector3.new(1, 0, 0) } do
		paintFace(model, crate, normal, ore)
	end
end

function OreBoxModel.Build(oreKey)
	if not (Config.OreByKey and Config.OreByKey[oreKey]) then return nil end
	local model = crate()
	pcall(decorate, model, oreKey)
	if not (Config.MineRework and Config.MineRework.OreBoxOreOnTop) then
		return model
	end
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
