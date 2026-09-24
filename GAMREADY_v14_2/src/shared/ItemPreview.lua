--------------------------------------------------------------------------------
-- ItemPreview (v18) — 3D-превью любой награды во ViewportFrame.
-- Используют окно шансов (client/DropPreviewUI) и карточки открытия
-- (shared/RevealCards). Только клиент.
--
-- item: строка DropTables или результат открытия. Понимает Kind:
--   Crystal/Ore (OreId, Mutations) · Money · Essence (Mutation) · Heart ·
--   Skin (SkinId) · Charm (Charm) · PrestigePoint · Relic (RelicId) · Junk (OreId)
--
-- ItemPreview.Mount(viewport, item, opts) строит модель, камеру по габаритам
-- и (opts.Spin ~= false) медленно крутит её, пока viewport в дереве.
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)

local ItemPreview = {}

local function part(model, name, shape, size, color, material, cframe, transparency)
	local p = Instance.new("Part")
	p.Name = name
	if shape then p.Shape = shape end
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CFrame = cframe or CFrame.new()
	p.Transparency = transparency or 0
	p.Anchored = true
	p.CanCollide = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function money(tier)
	local model = Instance.new("Model")
	local gold = Color3.fromRGB(255, 200, 60)
	local count = tier == 3 and 7 or tier == 2 and 5 or 3
	for i = 1, count do
		part(model, "Coin", Enum.PartType.Cylinder, Vector3.new(0.22, 1.3, 1.3), gold, Enum.Material.Metal,
			CFrame.new(math.sin(i) * 0.08, i * 0.24, math.cos(i) * 0.08) * CFrame.Angles(0, 0, math.rad(90)))
	end
	if tier == 3 then
		part(model, "Bag", Enum.PartType.Ball, Vector3.new(1.6, 1.5, 1.6), Color3.fromRGB(150, 110, 60), Enum.Material.Fabric, CFrame.new(1.3, 0.8, 0))
		part(model, "Tie", Enum.PartType.Cylinder, Vector3.new(0.3, 0.6, 0.6), Color3.fromRGB(110, 75, 40), Enum.Material.Fabric, CFrame.new(1.3, 1.6, 0) * CFrame.Angles(0, 0, math.rad(90)))
		part(model, "Sign", nil, Vector3.new(0.6, 0.6, 0.05), gold, Enum.Material.Neon, CFrame.new(1.3, 0.85, -0.8))
	end
	part(model, "Shine", Enum.PartType.Ball, Vector3.new(0.25, 0.25, 0.25), Color3.new(1, 1, 1), Enum.Material.Neon, CFrame.new(-0.35, count * 0.24 + 0.2, -0.3))
	return model
end

local function vial(color)
	local model = Instance.new("Model")
	local glass = Color3.fromRGB(220, 240, 255)
	part(model, "Glass", Enum.PartType.Cylinder, Vector3.new(1.8, 0.95, 0.95), glass, Enum.Material.Glass, CFrame.Angles(0, 0, math.rad(90)), 0.5)
	part(model, "Liquid", Enum.PartType.Cylinder, Vector3.new(1.35, 0.8, 0.8), color, Enum.Material.Neon, CFrame.new(0, -0.18, 0) * CFrame.Angles(0, 0, math.rad(90)))
	part(model, "Cork", Enum.PartType.Cylinder, Vector3.new(0.35, 0.7, 0.7), Color3.fromRGB(150, 95, 55), Enum.Material.Wood, CFrame.new(0, 1.05, 0) * CFrame.Angles(0, 0, math.rad(90)))
	for i = 1, 3 do
		part(model, "Bubble", Enum.PartType.Ball, Vector3.one * (0.12 + i * 0.03), Color3.new(1, 1, 1), Enum.Material.Neon, CFrame.new((i - 2) * 0.18, -0.2 + i * 0.28, -0.3), 0.3)
	end
	return model
end

local function heart()
	local model = Instance.new("Model")
	local pink = Color3.fromRGB(255, 80, 160)
	part(model, "L", Enum.PartType.Ball, Vector3.one * 1.2, pink, Enum.Material.Neon, CFrame.new(-0.42, 0.3, 0))
	part(model, "R", Enum.PartType.Ball, Vector3.one * 1.2, pink, Enum.Material.Neon, CFrame.new(0.42, 0.3, 0))
	part(model, "Point", nil, Vector3.new(1.2, 1.2, 0.9), pink, Enum.Material.Neon, CFrame.new(0, -0.25, 0) * CFrame.Angles(0, 0, math.rad(45)))
	part(model, "Shell", Enum.PartType.Ball, Vector3.one * 2.6, Color3.fromRGB(200, 160, 255), Enum.Material.Glass, CFrame.new(0, 0.1, 0), 0.75)
	return model
end

local function amulet(color)
	local model = Instance.new("Model")
	local gold = Color3.fromRGB(255, 196, 60)
	part(model, "Disc", Enum.PartType.Cylinder, Vector3.new(0.25, 1.6, 1.6), gold, Enum.Material.Metal, CFrame.Angles(0, math.rad(90), 0))
	part(model, "Rim", Enum.PartType.Cylinder, Vector3.new(0.3, 1.25, 1.25), Color3.fromRGB(200, 140, 30), Enum.Material.Metal, CFrame.Angles(0, math.rad(90), 0))
	part(model, "Gem", Enum.PartType.Ball, Vector3.one * 0.8, color, Enum.Material.Neon, CFrame.new(0, 0, -0.2))
	part(model, "Loop", Enum.PartType.Cylinder, Vector3.new(0.12, 0.45, 0.45), gold, Enum.Material.Metal, CFrame.new(0, 0.95, 0) * CFrame.Angles(0, math.rad(90), 0))
	return model
end

local function star()
	local model = Instance.new("Model")
	local gold = Color3.fromRGB(255, 215, 80)
	for i = 0, 4 do
		part(model, "Ray", Enum.PartType.Wedge, Vector3.new(0.3, 1.1, 0.6), gold, Enum.Material.Neon,
			CFrame.Angles(0, 0, math.rad(i * 72)) * CFrame.new(0, 0.7, 0) * CFrame.Angles(math.rad(-90), 0, 0))
	end
	part(model, "Core", Enum.PartType.Ball, Vector3.one * 0.9, gold, Enum.Material.Neon, CFrame.new())
	return model
end

local function fromAsset(assetName)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local source = assets and assetName and assets:FindFirstChild(assetName)
	if not source then return nil end
	local clone = source:Clone()
	if clone:IsA("BasePart") then
		local model = Instance.new("Model")
		clone.Parent = model
		clone = model
	elseif clone:IsA("Tool") then
		local model = Instance.new("Model")
		for _, child in clone:GetChildren() do child.Parent = model end
		clone:Destroy()
		clone = model
	end
	if not clone:IsA("Model") then clone:Destroy() return nil end
	return clone
end

function ItemPreview.Build(item)
	local kind = item and item.Kind
	local model
	if kind == "Crystal" or kind == "Ore" then
		local ok, ore = pcall(PlaceholderFactory.CollectionOre, item.OreId)
		if ok and ore then
			if ore:IsA("BasePart") then
				model = Instance.new("Model")
				ore.Parent = model
			else
				model = ore
			end
			if item.Mutations then
				local okMv, MutationVisuals = pcall(require, ReplicatedStorage.Shared.MutationVisuals)
				if okMv then
					for _, id in item.Mutations do
						pcall(MutationVisuals.Apply, model, id, model:FindFirstChildWhichIsA("BasePart", true))
					end
				end
			end
		end
	elseif kind == "Money" then
		model = money(item.Index or (item.Jackpot and 3) or 1)
	elseif kind == "Essence" then
		local mutation = Config.Mutations[item.Mutation]
		model = vial(mutation and mutation.Color or Color3.fromRGB(200, 120, 255))
	elseif kind == "Heart" then
		model = heart()
	elseif kind == "Skin" then
		local definition = Config.Skins.Definitions[item.SkinId]
		model = definition and fromAsset(definition.AssetName)
	elseif kind == "Charm" then
		local charm = Config.Potions.Types[item.Charm]
		model = amulet(charm and charm.Color or Color3.fromRGB(255, 200, 80))
	elseif kind == "PrestigePoint" then
		model = star()
	elseif kind == "Relic" then
		local relic = Config.Relics and Config.Relics.Types[item.RelicId]
		model = relic and fromAsset(relic.Asset)
		if not model then model = star() end
	elseif kind == "Junk" then
		local info = Config.JunkByKey and Config.JunkByKey[item.OreId]
		if info then
			local ok, junk = pcall(PlaceholderFactory.Junk, info)
			if ok and junk then
				if junk:IsA("BasePart") then
					model = Instance.new("Model")
					junk.Parent = model
				else
					model = junk
				end
			end
		else
			model = Instance.new("Model")
			part(model, "Rock", Enum.PartType.Ball, Vector3.new(1, 0.8, 0.9), Color3.fromRGB(125, 120, 115), Enum.Material.Slate)
			part(model, "Can", Enum.PartType.Cylinder, Vector3.new(0.9, 0.5, 0.5), Color3.fromRGB(200, 30, 40), Enum.Material.Metal, CFrame.new(0.8, 0.2, 0) * CFrame.Angles(0, 0, math.rad(80)))
		end
	end
	if not model then
		model = Instance.new("Model")
		part(model, "Box", nil, Vector3.one * 1.4, Config.RarityColors[item and item.Rarity or ""] or Color3.fromRGB(200, 200, 200), Enum.Material.Neon)
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		elseif d:IsA("Script") or d:IsA("LocalScript") or d:IsA("BillboardGui") or d:IsA("ProximityPrompt") then
			d:Destroy()
		end
	end
	return model
end

-- Вешает превью в viewport. opts: Spin (true), Tilt (градусы), Zoom (1).
-- Возвращает функцию очистки.
function ItemPreview.Mount(viewport, item, opts)
	opts = opts or {}
	for _, child in viewport:GetChildren() do
		if child:IsA("Model") or child:IsA("Camera") or child:IsA("WorldModel") then child:Destroy() end
	end
	local model = ItemPreview.Build(item)
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	model.Parent = world
	local ok, cf, size = pcall(function() return model:GetBoundingBox() end)
	if not ok then cf, size = CFrame.new(), Vector3.one end
	local center = cf.Position
	local radius = math.max(size.Magnitude / 2, 0.5)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	local distance = radius / math.tan(math.rad(20)) * (opts.Zoom or 1.05)
	local tilt = math.rad(opts.Tilt or 12)
	camera.CFrame = CFrame.lookAt(center + Vector3.new(0, math.sin(tilt) * distance, math.cos(tilt) * distance), center)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-0.5, -1, -0.7)
	viewport.Ambient = Color3.fromRGB(170, 170, 185)

	-- opts.Control = {} — внешнее управление: Paused (стоп авто-вращения),
	-- Angle (радианы; окно шансов крутит модель мышью через него).
	local connection
	local control = opts.Control or {}
	control.Angle = control.Angle or 0
	if opts.Spin ~= false or opts.Control then
		local base = model:GetPivot()
		local speed = opts.SpinSpeed or 0.9
		local offset = base.Position - center
		connection = RunService.RenderStepped:Connect(function(dt)
			if not model.Parent or not viewport:IsDescendantOf(game) then
				connection:Disconnect()
				return
			end
			if not viewport.Visible then return end
			if opts.Spin ~= false and not control.Paused then control.Angle += dt * speed end
			model:PivotTo(CFrame.new(center) * CFrame.Angles(0, control.Angle, 0) * CFrame.new(offset) * base.Rotation)
		end)
	end
	return function()
		if connection then connection:Disconnect() end
		world:Destroy()
		camera:Destroy()
	end
end

return ItemPreview
