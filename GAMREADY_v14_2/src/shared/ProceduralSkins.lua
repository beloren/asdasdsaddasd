--------------------------------------------------------------------------------
-- ProceduralSkins (v18) — простые модели скинов «Пиратский клад», пока в
-- ReplicatedStorage.Assets нет своих. Сервер при старте (SkinService:Init)
-- кладёт собранный Tool в Assets под AssetName скина, поэтому дальше весь
-- код игры (кирка в руке, превью в SkinUI, окно шансов, карточки) видит его
-- как обычный ассет. Положишь свою модель с тем же именем — возьмётся она.
--
-- Формат: Tool с прямым BasePart "Handle" (вертикальная рукоять вдоль Y,
-- навершие сверху), остальные детали приварены WeldConstraint'ами.
--------------------------------------------------------------------------------
local ProceduralSkins = {}

local WOOD = Color3.fromRGB(110, 72, 40)
local DARK_WOOD = Color3.fromRGB(70, 44, 26)
local GOLD = Color3.fromRGB(255, 196, 60)
local IRON = Color3.fromRGB(80, 84, 92)
local BONE = Color3.fromRGB(236, 228, 205)

local function newTool(skinId)
	local tool = Instance.new("Tool")
	tool.Name = "Skin_Pickaxe_" .. skinId
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.Grip = CFrame.new(0, -1, 0)
	return tool
end

local function part(tool, name, shape, size, color, material, cframe, props)
	local p = Instance.new("Part")
	p.Name = name
	if shape then p.Shape = shape end
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CFrame = cframe or CFrame.new()
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props or {} do p[key] = value end
	p.Parent = tool
	return p
end

local function handle(tool, color, material, length)
	return part(tool, "Handle", nil, Vector3.new(0.32, length or 3, 0.32), color, material or Enum.Material.Wood, CFrame.new())
end

local function weldAll(tool)
	local h = tool:FindFirstChild("Handle")
	for _, child in tool:GetChildren() do
		if child:IsA("BasePart") and child ~= h then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = h
			weld.Part1 = child
			weld.Parent = child
		end
	end
end

local function glow(p, color, range)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range or 6
	light.Brightness = 1.2
	light.Parent = p
end

local builders = {}

builders.RustyShovel = function(tool)
	handle(tool, WOOD, Enum.Material.Wood, 3)
	part(tool, "Grip", nil, Vector3.new(0.9, 0.18, 0.18), DARK_WOOD, Enum.Material.Wood, CFrame.new(0, -1.45, 0))
	part(tool, "Collar", Enum.PartType.Cylinder, Vector3.new(0.3, 0.42, 0.42), Color3.fromRGB(120, 70, 40), Enum.Material.CorrodedMetal, CFrame.new(0, 1.55, 0) * CFrame.Angles(0, 0, math.rad(90)))
	part(tool, "Blade", nil, Vector3.new(1.1, 1.2, 0.14), Color3.fromRGB(150, 85, 45), Enum.Material.CorrodedMetal, CFrame.new(0, 2.25, 0))
	part(tool, "Tip", Enum.PartType.Wedge, Vector3.new(0.14, 0.4, 1.1), Color3.fromRGB(150, 85, 45), Enum.Material.CorrodedMetal, CFrame.new(0, 3.05, 0) * CFrame.Angles(0, math.rad(90), 0))
end

builders.BonePick = function(tool)
	handle(tool, BONE, Enum.Material.SmoothPlastic, 3)
	for _, y in { -1.45, 1.4 } do
		part(tool, "Knob", Enum.PartType.Ball, Vector3.new(0.5, 0.5, 0.5), BONE, nil, CFrame.new(0, y, 0))
	end
	part(tool, "Head", Enum.PartType.Cylinder, Vector3.new(2.4, 0.32, 0.32), BONE, nil, CFrame.new(0, 1.55, 0))
	for _, x in { -1.25, 1.25 } do
		for _, z in { -0.16, 0.16 } do
			part(tool, "End", Enum.PartType.Ball, Vector3.new(0.42, 0.42, 0.42), BONE, nil, CFrame.new(x, 1.55, z))
		end
	end
	part(tool, "Skull", Enum.PartType.Ball, Vector3.new(0.7, 0.7, 0.7), BONE, nil, CFrame.new(0, 1.9, 0))
	part(tool, "EyeL", Enum.PartType.Ball, Vector3.new(0.16, 0.16, 0.16), Color3.fromRGB(20, 20, 20), nil, CFrame.new(-0.13, 1.95, -0.3))
	part(tool, "EyeR", Enum.PartType.Ball, Vector3.new(0.16, 0.16, 0.16), Color3.fromRGB(20, 20, 20), nil, CFrame.new(0.13, 1.95, -0.3))
end

builders.AnchorPick = function(tool)
	handle(tool, IRON, Enum.Material.Metal, 3.2)
	part(tool, "Ring", Enum.PartType.Cylinder, Vector3.new(0.18, 0.8, 0.8), IRON, Enum.Material.Metal, CFrame.new(0, -1.75, 0))
	part(tool, "Stock", nil, Vector3.new(1.4, 0.22, 0.22), IRON, Enum.Material.Metal, CFrame.new(0, 1.2, 0))
	for _, side in { -1, 1 } do
		part(tool, "Arm", nil, Vector3.new(1.1, 0.3, 0.3), IRON, Enum.Material.Metal, CFrame.new(side * 0.5, 1.75, 0) * CFrame.Angles(0, 0, math.rad(side * -25)))
		part(tool, "Fluke", Enum.PartType.Wedge, Vector3.new(0.3, 0.55, 0.5), Color3.fromRGB(110, 115, 125), Enum.Material.Metal, CFrame.new(side * 1.05, 2.05, 0) * CFrame.Angles(0, math.rad(side * 90), 0))
	end
	part(tool, "Crown", Enum.PartType.Ball, Vector3.new(0.5, 0.5, 0.5), IRON, Enum.Material.Metal, CFrame.new(0, 1.6, 0))
end

builders.PirateHook = function(tool)
	handle(tool, WOOD, Enum.Material.Wood, 2.8)
	part(tool, "Wrap", nil, Vector3.new(0.38, 0.9, 0.38), Color3.fromRGB(170, 30, 40), Enum.Material.Fabric, CFrame.new(0, -0.9, 0))
	part(tool, "Cuff", Enum.PartType.Cylinder, Vector3.new(0.4, 0.7, 0.7), Color3.fromRGB(60, 40, 25), Enum.Material.Leather, CFrame.new(0, 1.4, 0) * CFrame.Angles(0, 0, math.rad(90)))
	local silver = Color3.fromRGB(200, 205, 215)
	part(tool, "Shank", nil, Vector3.new(0.16, 0.9, 0.16), silver, Enum.Material.Metal, CFrame.new(0, 2.1, 0))
	part(tool, "Bend1", nil, Vector3.new(0.16, 0.5, 0.16), silver, Enum.Material.Metal, CFrame.new(0.2, 2.62, 0) * CFrame.Angles(0, 0, math.rad(-50)))
	part(tool, "Bend2", nil, Vector3.new(0.16, 0.55, 0.16), silver, Enum.Material.Metal, CFrame.new(0.52, 2.55, 0) * CFrame.Angles(0, 0, math.rad(-140)))
	part(tool, "Point", Enum.PartType.Wedge, Vector3.new(0.16, 0.35, 0.18), silver, Enum.Material.Metal, CFrame.new(0.66, 2.25, 0) * CFrame.Angles(0, 0, math.rad(180)))
end

builders.KrakenTentacle = function(tool)
	local purple = Color3.fromRGB(125, 50, 150)
	local h = handle(tool, purple, Enum.Material.SmoothPlastic, 1.6)
	h.CFrame = CFrame.new(0, -0.7, 0)
	local y, size, x = 0.2, 0.5, 0
	for i = 1, 8 do
		x = math.sin(i * 0.7) * 0.25
		part(tool, "Segment", Enum.PartType.Ball, Vector3.one * size, purple, nil, CFrame.new(x, y, 0))
		part(tool, "Sucker", Enum.PartType.Ball, Vector3.one * (size * 0.35), Color3.fromRGB(255, 150, 190), nil, CFrame.new(x, y, -size * 0.38))
		y += size * 0.62
		size *= 0.9
	end
	part(tool, "Tip", Enum.PartType.Ball, Vector3.one * 0.2, Color3.fromRGB(255, 150, 190), Enum.Material.Neon, CFrame.new(x, y, 0))
end

builders.SkeletonKey = function(tool)
	handle(tool, GOLD, Enum.Material.Metal, 3)
	part(tool, "Bow", Enum.PartType.Cylinder, Vector3.new(0.22, 1.1, 1.1), GOLD, Enum.Material.Metal, CFrame.new(0, -1.9, 0) * CFrame.Angles(0, math.rad(90), 0))
	part(tool, "BowHole", Enum.PartType.Cylinder, Vector3.new(0.26, 0.55, 0.55), Color3.fromRGB(30, 20, 10), Enum.Material.SmoothPlastic, CFrame.new(0, -1.9, 0) * CFrame.Angles(0, math.rad(90), 0))
	part(tool, "Skull", Enum.PartType.Ball, Vector3.new(0.5, 0.5, 0.5), BONE, nil, CFrame.new(0, -1.35, 0))
	part(tool, "Bit1", nil, Vector3.new(0.7, 0.22, 0.2), GOLD, Enum.Material.Metal, CFrame.new(0.35, 1.3, 0))
	part(tool, "Bit2", nil, Vector3.new(0.5, 0.22, 0.2), GOLD, Enum.Material.Metal, CFrame.new(0.25, 0.95, 0))
	part(tool, "Bit3", nil, Vector3.new(0.22, 0.5, 0.2), GOLD, Enum.Material.Metal, CFrame.new(0.6, 1.1, 0))
	part(tool, "Gem", Enum.PartType.Ball, Vector3.new(0.3, 0.3, 0.3), Color3.fromRGB(80, 255, 150), Enum.Material.Neon, CFrame.new(0, -1.9, 0))
end

builders.GoldenTrident = function(tool)
	handle(tool, GOLD, Enum.Material.Metal, 3.4)
	part(tool, "Cross", nil, Vector3.new(1.3, 0.22, 0.22), GOLD, Enum.Material.Metal, CFrame.new(0, 1.7, 0))
	for _, x in { -0.55, 0, 0.55 } do
		local length = x == 0 and 1.1 or 0.8
		part(tool, "Prong", nil, Vector3.new(0.16, length, 0.16), GOLD, Enum.Material.Metal, CFrame.new(x, 1.8 + length / 2, 0))
		part(tool, "Barb", Enum.PartType.Wedge, Vector3.new(0.18, 0.35, 0.3), GOLD, Enum.Material.Metal, CFrame.new(x, 1.95 + length, 0))
	end
	local gem = part(tool, "Gem", Enum.PartType.Ball, Vector3.new(0.34, 0.34, 0.34), Color3.fromRGB(70, 200, 255), Enum.Material.Neon, CFrame.new(0, 1.7, -0.12))
	glow(gem, Color3.fromRGB(70, 200, 255), 5)
end

builders.DoubloonAxe = function(tool)
	handle(tool, DARK_WOOD, Enum.Material.Wood, 3)
	part(tool, "Band", Enum.PartType.Cylinder, Vector3.new(0.2, 0.38, 0.38), GOLD, Enum.Material.Metal, CFrame.new(0, -1.1, 0) * CFrame.Angles(0, 0, math.rad(90)))
	part(tool, "Coin", Enum.PartType.Cylinder, Vector3.new(0.2, 1.7, 1.7), GOLD, Enum.Material.Metal, CFrame.new(0.75, 1.2, 0) * CFrame.Angles(0, math.rad(90), 0))
	part(tool, "CoinRim", Enum.PartType.Cylinder, Vector3.new(0.24, 1.35, 1.35), Color3.fromRGB(225, 160, 30), Enum.Material.Metal, CFrame.new(0.75, 1.2, 0) * CFrame.Angles(0, math.rad(90), 0))
	part(tool, "Back", nil, Vector3.new(0.5, 0.5, 0.3), GOLD, Enum.Material.Metal, CFrame.new(-0.3, 1.2, 0))
	local gem = part(tool, "Gem", Enum.PartType.Ball, Vector3.new(0.35, 0.35, 0.35), Color3.fromRGB(255, 60, 70), Enum.Material.Neon, CFrame.new(0.75, 1.2, -0.15))
	glow(gem, Color3.fromRGB(255, 80, 80), 4)
end

builders.CursedCaptainBlade = function(tool)
	local black = Color3.fromRGB(25, 25, 30)
	local ghost = Color3.fromRGB(90, 255, 150)
	handle(tool, black, Enum.Material.Leather, 1.2).CFrame = CFrame.new(0, -1, 0)
	part(tool, "Pommel", Enum.PartType.Ball, Vector3.new(0.5, 0.5, 0.5), BONE, nil, CFrame.new(0, -1.7, 0))
	part(tool, "Guard", nil, Vector3.new(0.9, 0.18, 0.4), GOLD, Enum.Material.Metal, CFrame.new(0, -0.35, 0))
	part(tool, "GuardBow", nil, Vector3.new(0.14, 1.1, 0.14), GOLD, Enum.Material.Metal, CFrame.new(0.4, -0.9, 0))
	local blade = Color3.fromRGB(60, 70, 70)
	local y, angle = -0.2, 0
	for i = 1, 5 do
		local seg = part(tool, "Blade", nil, Vector3.new(0.36, 0.75, 0.08), blade, Enum.Material.Metal, CFrame.new(math.sin(angle) * 0.4, y + 0.37, 0) * CFrame.Angles(0, 0, -angle))
		part(tool, "Edge", nil, Vector3.new(0.06, 0.75, 0.09), ghost, Enum.Material.Neon, seg.CFrame * CFrame.new(0.2, 0, 0))
		y += 0.7
		angle += math.rad(7)
	end
	local fx = part(tool, "Ghost", nil, Vector3.new(0.2, 0.2, 0.2), ghost, Enum.Material.Neon, CFrame.new(0.3, 1.6, 0), { Transparency = 1 })
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(ghost)
	emitter.LightEmission = 0.8
	emitter.Transparency = NumberSequence.new(0.5, 1)
	emitter.Size = NumberSequence.new(0.6, 1.2)
	emitter.Lifetime = NumberRange.new(0.6, 1)
	emitter.Rate = 12
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.Parent = fx
	glow(fx, ghost, 6)
end

--------------------------------------------------------------------------------
-- v20.60: ОБЩИЕ ФОРМЫ для скинов без своего билдера. Берутся из
-- Config.Skins.Definitions[id]: Shape (Pickaxe/Sword/Axe/Club/Kunai/Hammer),
-- Colors = { цвет навершия, цвет рукояти }, Material, Rainbow.
--------------------------------------------------------------------------------
local RAINBOW = {
	Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 170, 60), Color3.fromRGB(255, 240, 80),
	Color3.fromRGB(90, 230, 110), Color3.fromRGB(80, 170, 255), Color3.fromRGB(190, 100, 255),
}

local shapes = {}

shapes.Pickaxe = function(tool, head, grip, material, rainbow)
	handle(tool, grip, Enum.Material.Wood, 3)
	part(tool, "Collar", nil, Vector3.new(0.5, 0.5, 0.5), head, material, CFrame.new(0, 1.45, 0))
	for _, side in { -1, 1 } do
		for i = 1, 3 do
			local color = rainbow and RAINBOW[(side < 0 and i or i + 3)] or head
			local size = Vector3.new(0.55, 0.42 - i * 0.07, 0.42 - i * 0.07)
			part(tool, "Blade", nil, size, color, material,
				CFrame.new(side * (0.2 + i * 0.42), 1.45 - i * 0.12, 0) * CFrame.Angles(0, 0, math.rad(side * -8 * i)))
		end
	end
end

shapes.Sword = function(tool, head, grip, material, rainbow)
	handle(tool, grip, Enum.Material.Leather, 1.2)
	part(tool, "Pommel", Enum.PartType.Ball, Vector3.new(0.4, 0.4, 0.4), head, material, CFrame.new(0, -0.7, 0))
	part(tool, "Guard", nil, Vector3.new(1.3, 0.2, 0.34), grip, Enum.Material.Metal, CFrame.new(0, 0.65, 0))
	local segments = rainbow and #RAINBOW or 1
	local length = 2.6
	for i = 1, segments do
		local h = length / segments
		part(tool, "Blade", nil, Vector3.new(0.32, h, 0.1), rainbow and RAINBOW[i] or head, material,
			CFrame.new(0, 0.75 + h * (i - 0.5), 0))
	end
	part(tool, "Tip", Enum.PartType.Wedge, Vector3.new(0.1, 0.4, 0.32), rainbow and RAINBOW[#RAINBOW] or head, material,
		CFrame.new(0, 0.75 + length + 0.2, 0) * CFrame.Angles(0, math.rad(90), 0))
end

shapes.Axe = function(tool, head, grip, material)
	handle(tool, grip, Enum.Material.Wood, 3.2)
	part(tool, "Socket", nil, Vector3.new(0.45, 0.6, 0.45), grip, Enum.Material.Metal, CFrame.new(0, 1.4, 0))
	for _, side in { -1, 1 } do
		part(tool, "Blade", nil, Vector3.new(0.9, 1.1, 0.12), head, material, CFrame.new(side * 0.6, 1.4, 0))
		part(tool, "Edge", Enum.PartType.Wedge, Vector3.new(0.12, 1.1, 0.35), head, material,
			CFrame.new(side * 1.2, 1.4, 0) * CFrame.Angles(0, math.rad(side * -90), 0))
	end
end

shapes.Club = function(tool, head, grip, material)
	handle(tool, grip, Enum.Material.Wood, 2.4)
	part(tool, "Head", Enum.PartType.Cylinder, Vector3.new(1.6, 0.9, 0.9), head, material,
		CFrame.new(0, 1.9, 0) * CFrame.Angles(0, 0, math.rad(90)))
	part(tool, "Cap", Enum.PartType.Ball, Vector3.new(0.9, 0.9, 0.9), head, material, CFrame.new(0, 2.7, 0))
end

shapes.Kunai = function(tool, head, grip, material)
	handle(tool, grip, Enum.Material.Fabric, 1)
	part(tool, "Ring", Enum.PartType.Cylinder, Vector3.new(0.12, 0.5, 0.5), head, material, CFrame.new(0, -0.7, 0))
	part(tool, "Blade", nil, Vector3.new(0.4, 1, 0.1), head, material, CFrame.new(0, 1, 0))
	part(tool, "Tip", Enum.PartType.Wedge, Vector3.new(0.1, 0.6, 0.4), head, material,
		CFrame.new(0, 1.8, 0) * CFrame.Angles(0, math.rad(90), 0))
end

shapes.Hammer = function(tool, head, grip, material)
	handle(tool, grip, Enum.Material.Metal, 3)
	part(tool, "Head", nil, Vector3.new(2, 1, 1), grip, material, CFrame.new(0, 1.9, 0))
	for _, side in { -1, 1 } do
		part(tool, "Band", nil, Vector3.new(0.2, 1.08, 1.08), head, Enum.Material.Neon, CFrame.new(side * 0.7, 1.9, 0))
	end
end

local function definitionOf(skinId, definition)
	if definition then return definition end
	local ok, Config = pcall(function() return require(game:GetService("ReplicatedStorage").Shared.Config) end)
	return ok and Config.Skins.Definitions[skinId] or nil
end

function ProceduralSkins.Has(skinId, definition)
	if builders[skinId] then return true end
	definition = definitionOf(skinId, definition)
	return definition ~= nil and shapes[definition.Shape or ""] ~= nil
end

function ProceduralSkins.Build(skinId, definition)
	local tool = newTool(skinId)
	local builder = builders[skinId]
	if builder then
		builder(tool)
	else
		definition = definitionOf(skinId, definition)
		local shape = definition and shapes[definition.Shape or ""]
		if not shape then tool:Destroy(); return nil end
		local colors = definition.Colors or {}
		local head = colors[1] or Color3.fromRGB(200, 200, 210)
		local grip = colors[2] or WOOD
		local material = definition.Material or Enum.Material.SmoothPlastic
		shape(tool, head, grip, material, definition.Rainbow == true)
		if material == Enum.Material.Neon then
			local top = tool:FindFirstChild("Blade") or tool:FindFirstChild("Head")
			if top then glow(top, head, 7) end
		end
	end
	weldAll(tool)
	return tool
end

return ProceduralSkins
