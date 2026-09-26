--------------------------------------------------------------------------------
-- PlaceableFactory — модели тотемов, декора и реликвий.
--
-- Сначала ищется своя модель в ReplicatedStorage.Assets.<Asset> (имя — в
-- Config.Placeables / Config.Relics). Нашлась — клонируется как есть, со
-- всеми ParticleEmitter/Attachment/Beam/Light внутри; пивот ставится в
-- центр НИЖНЕЙ грани, чтобы модель вставала на землю, а не утопала в ней.
-- Нет — строится плейсхолдер из деталей: он должен выглядеть прилично и
-- без анимаций.
--
-- Все детали: Anchored, CanCollide = false (декор не мешает ходить и не
-- ломает физику тележек), CanQuery = true (по ним работают промпты подбора).
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)
local PlaceableCatalog = require(script.Parent.PlaceableCatalog)

local PlaceableFactory = {}

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = true
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do p[key] = value end
	return p
end

local function sparkles(parent, color, rate, size)
	local attachment = Instance.new("Attachment")
	attachment.Name = "FxAttachment"
	attachment.Parent = parent
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Sparkles"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size or 0.35), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.8, 1.6)
	emitter.Rate = rate or 6
	emitter.Speed = NumberRange.new(0.6, 1.6)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 1.2, 0)
	emitter.Parent = attachment
	return emitter
end

local function light(parent, color, brightness, range)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness or 1.5
	l.Range = range or 10
	l.Shadows = false
	l.Parent = parent
	return l
end

-- Модель из деталей: первая деталь — Root (основание), от неё пивот.
local function assemble(name, root, parts)
	local model = Instance.new("Model")
	model.Name = name
	root.Name = "Root"
	root.Parent = model
	for _, p in parts do p.Parent = model end
	model.PrimaryPart = root
	local bottom = root.CFrame * CFrame.new(0, -root.Size.Y / 2, 0)
	model.WorldPivot = bottom
	return model
end

-- Своя модель из Assets: клон + пивот в центр нижней грани габарита.
local function fromAsset(assetName)
	if typeof(assetName) ~= "string" or assetName == "" then return nil end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local source = assets and assets:FindFirstChild(assetName)
	if not source then return nil end
	local clone = source:Clone()
	local model = clone
	if clone:IsA("BasePart") then
		model = Instance.new("Model")
		model.Name = assetName
		clone.Name = "Root"
		clone.Parent = model
		model.PrimaryPart = clone
	elseif not clone:IsA("Model") then
		clone:Destroy()
		return nil
	end
	model.PrimaryPart = model.PrimaryPart or model:FindFirstChild("Root", true) or model:FindFirstChildWhichIsA("BasePart", true)
	if not model.PrimaryPart then
		model:Destroy()
		return nil
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = true
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	local boxCFrame, boxSize = model:GetBoundingBox()
	local rotation = model.PrimaryPart.CFrame - model.PrimaryPart.CFrame.Position
	model.WorldPivot = CFrame.new(boxCFrame.Position - Vector3.new(0, boxSize.Y / 2, 0)) * rotation
	model:SetAttribute("CustomAsset", true)
	return model
end

--------------------------------------------------------------------------------
-- ТОТЕМ: каменная плита, ступенчатая колонна цвета эффекта, светящаяся
-- сфера цвета тира, руны-кольца. Чем выше тир, тем выше колонна.
--------------------------------------------------------------------------------
local function buildTotem(info)
	-- v20.43: тиров 3 (Early/Mid/Late) — размер/свет как у старых T2/T6/T10.
	local tier = ({ 2, 6, 10 })[info.Tier or 1] or 10
	local tierColor = info.TierColor or Color3.new(1, 1, 1)
	local base = part({ Size = Vector3.new(2.6, 0.5, 2.6), Material = Enum.Material.Slate, Color = Color3.fromRGB(80, 78, 84) })
	base.CFrame = CFrame.new(0, 0.25, 0)
	local parts = {}
	local height = 2.4 + tier * 0.12
	local column = part({ Size = Vector3.new(1.3, height, 1.3), Material = Enum.Material.Cobblestone, Color = info.Color:Lerp(Color3.fromRGB(60, 60, 60), 0.45) })
	column.CFrame = CFrame.new(0, 0.5 + height / 2, 0)
	table.insert(parts, column)
	for i = 1, 2 do
		local ring = part({ Size = Vector3.new(1.55, 0.18, 1.55), Material = Enum.Material.Neon, Color = info.Color })
		ring.CFrame = CFrame.new(0, 0.5 + height * (i == 1 and 0.3 or 0.72), 0)
		table.insert(parts, ring)
	end
	local cap = part({ Size = Vector3.new(1.8, 0.35, 1.8), Material = Enum.Material.Slate, Color = Color3.fromRGB(70, 68, 74) })
	cap.CFrame = CFrame.new(0, 0.5 + height + 0.175, 0)
	table.insert(parts, cap)
	local orb = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * (0.9 + tier * 0.04), Material = Enum.Material.Neon, Color = tierColor, CastShadow = false })
	orb.Name = "Orb"
	orb.CFrame = CFrame.new(0, 0.5 + height + 0.35 + orb.Size.Y / 2 + 0.15, 0)
	table.insert(parts, orb)
	light(orb, tierColor, 1.2 + tier * 0.15, 8 + tier)
	sparkles(orb, tierColor, 3 + tier, 0.25 + tier * 0.02)
	-- Эмблема эффекта спереди колонны.
	local plate = part({ Size = Vector3.new(0.8, 0.8, 0.1), Material = Enum.Material.Neon, Color = info.Color, CastShadow = false })
	plate.CFrame = CFrame.new(0, 0.5 + height * 0.5, -0.7)
	table.insert(parts, plate)
	return assemble("Totem", base, parts)
end

--------------------------------------------------------------------------------
-- ДЕКОР
--------------------------------------------------------------------------------
local DECOR_BUILDERS = {}

DECOR_BUILDERS.IronLantern = function()
	local base = part({ Size = Vector3.new(1.4, 0.3, 1.4), Material = Enum.Material.Metal, Color = Color3.fromRGB(45, 45, 50) })
	base.CFrame = CFrame.new(0, 0.15, 0)
	local post = part({ Size = Vector3.new(0.3, 4.2, 0.3), Material = Enum.Material.Metal, Color = Color3.fromRGB(40, 40, 44) })
	post.CFrame = CFrame.new(0, 2.4, 0)
	local cage = part({ Size = Vector3.new(0.95, 1.1, 0.95), Material = Enum.Material.Glass, Transparency = 0.35, Color = Color3.fromRGB(255, 210, 140) })
	cage.CFrame = CFrame.new(0, 5.05, 0)
	local flame = part({ Size = Vector3.new(0.45, 0.6, 0.45), Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 170, 60), CastShadow = false })
	flame.CFrame = CFrame.new(0, 5.0, 0)
	local roof = part({ Size = Vector3.new(1.25, 0.25, 1.25), Material = Enum.Material.Metal, Color = Color3.fromRGB(35, 35, 38) })
	roof.CFrame = CFrame.new(0, 5.72, 0)
	light(flame, Color3.fromRGB(255, 180, 90), 2, 16)
	return assemble("IronLantern", base, { post, cage, flame, roof })
end

DECOR_BUILDERS.CrystalLantern = function()
	local base = part({ Size = Vector3.new(1.6, 0.8, 1.6), Material = Enum.Material.Slate, Color = Color3.fromRGB(70, 70, 80) })
	base.CFrame = CFrame.new(0, 0.4, 0)
	local stem = part({ Size = Vector3.new(0.6, 1.4, 0.6), Material = Enum.Material.Slate, Color = Color3.fromRGB(60, 60, 70) })
	stem.CFrame = CFrame.new(0, 1.5, 0)
	local crystal = part({ Size = Vector3.new(0.8, 1.8, 0.8), Material = Enum.Material.Neon, Color = Color3.fromRGB(110, 220, 255), CastShadow = false })
	crystal.CFrame = CFrame.new(0, 3.1, 0) * CFrame.Angles(0, math.rad(45), math.rad(8))
	local shard = part({ Size = Vector3.new(0.4, 1, 0.4), Material = Enum.Material.Neon, Color = Color3.fromRGB(160, 235, 255), CastShadow = false })
	shard.CFrame = CFrame.new(0.35, 2.6, 0.1) * CFrame.Angles(0, 0, math.rad(-25))
	light(crystal, Color3.fromRGB(120, 220, 255), 2, 14)
	sparkles(crystal, Color3.fromRGB(170, 240, 255), 3, 0.2)
	return assemble("CrystalLantern", base, { stem, crystal, shard })
end

DECOR_BUILDERS.OreBarrel = function()
	local body = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.2, 1.8, 1.8), Material = Enum.Material.WoodPlanks, Color = Color3.fromRGB(125, 80, 45) })
	body.CFrame = CFrame.new(0, 1.1, 0) * CFrame.Angles(0, 0, math.rad(90))
	local parts = {}
	for _, y in { 0.35, 1.85 } do
		local hoop = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.15, 1.9, 1.9), Material = Enum.Material.Metal, Color = Color3.fromRGB(60, 60, 65) })
		hoop.CFrame = CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90))
		table.insert(parts, hoop)
	end
	local colors = { Color3.fromRGB(255, 190, 60), Color3.fromRGB(110, 220, 255), Color3.fromRGB(220, 90, 255), Color3.fromRGB(120, 255, 140) }
	for i = 1, 5 do
		local chunk = part({ Size = Vector3.one * (0.45 + (i % 3) * 0.12), Material = Enum.Material.Neon, Color = colors[(i % #colors) + 1], CastShadow = false })
		local angle = i * 1.3
		chunk.CFrame = CFrame.new(math.cos(angle) * 0.45, 2.35 + (i % 2) * 0.15, math.sin(angle) * 0.45) * CFrame.Angles(angle, angle * 2, 0)
		table.insert(parts, chunk)
	end
	-- Невидимое основание (Root), чтобы пивот был у земли.
	local root = part({ Size = Vector3.new(1.8, 0.1, 1.8), Transparency = 1, CastShadow = false })
	root.CFrame = CFrame.new(0, 0.05, 0)
	table.insert(parts, body)
	return assemble("OreBarrel", root, parts)
end

DECOR_BUILDERS.CrystalCluster = function()
	local base = part({ Size = Vector3.new(2.6, 0.6, 2.4), Material = Enum.Material.Rock, Color = Color3.fromRGB(85, 80, 95) })
	base.CFrame = CFrame.new(0, 0.3, 0)
	local parts = {}
	local specs = {
		{ 0, 2.2, 0, 0.9, 3.2, 0, 0 }, { 0.7, 1.4, 0.3, 0.6, 2, 0, -25 }, { -0.7, 1.3, 0.2, 0.55, 1.8, 0, 22 },
		{ 0.2, 1.1, -0.7, 0.5, 1.5, -24, 0 }, { -0.3, 1.0, 0.75, 0.45, 1.3, 26, 0 },
	}
	for i, s in specs do
		local c = part({ Size = Vector3.new(s[4], s[5], s[4]), Material = Enum.Material.Neon, Color = Color3.fromRGB(190, 110, 255):Lerp(Color3.fromRGB(110, 200, 255), i / #specs), CastShadow = false })
		c.CFrame = CFrame.new(s[1], s[2], s[3]) * CFrame.Angles(math.rad(s[6]), math.rad(45 + i * 20), math.rad(s[7]))
		table.insert(parts, c)
	end
	light(parts[1], Color3.fromRGB(180, 130, 255), 2.2, 14)
	sparkles(parts[1], Color3.fromRGB(220, 180, 255), 4, 0.25)
	return assemble("CrystalCluster", base, parts)
end

local function pedestal(height, color, material)
	local base = part({ Size = Vector3.new(2.4, 0.4, 2.4), Material = material or Enum.Material.Marble, Color = color or Color3.fromRGB(215, 210, 200) })
	base.CFrame = CFrame.new(0, 0.2, 0)
	local column = part({ Size = Vector3.new(1.8, height, 1.8), Material = material or Enum.Material.Marble, Color = (color or Color3.fromRGB(215, 210, 200)):Lerp(Color3.new(1, 1, 1), 0.08) })
	column.CFrame = CFrame.new(0, 0.4 + height / 2, 0)
	local top = part({ Size = Vector3.new(2.2, 0.3, 2.2), Material = material or Enum.Material.Marble, Color = color or Color3.fromRGB(215, 210, 200) })
	top.CFrame = CFrame.new(0, 0.4 + height + 0.15, 0)
	return base, { column, top }, 0.4 + height + 0.3
end

DECOR_BUILDERS.MinerStatue = function()
	local stone = Color3.fromRGB(150, 148, 142)
	local base, parts, topY = pedestal(1, Color3.fromRGB(120, 118, 112), Enum.Material.Slate)
	local function add(size, cf, color, material)
		local p = part({ Size = size, Material = material or Enum.Material.Slate, Color = color or stone })
		p.CFrame = CFrame.new(0, topY, 0) * cf
		table.insert(parts, p)
		return p
	end
	add(Vector3.new(0.55, 1.3, 0.6), CFrame.new(-0.32, 0.65, 0))
	add(Vector3.new(0.55, 1.3, 0.6), CFrame.new(0.32, 0.65, 0))
	add(Vector3.new(1.3, 1.4, 0.7), CFrame.new(0, 2.0, 0))
	add(Vector3.new(0.45, 1.3, 0.5), CFrame.new(-0.9, 2.0, 0))
	add(Vector3.new(0.45, 1.3, 0.5), CFrame.new(0.9, 2.1, -0.2) * CFrame.Angles(math.rad(-50), 0, 0))
	add(Vector3.new(0.9, 0.9, 0.9), CFrame.new(0, 3.15, 0))
	add(Vector3.new(1.05, 0.35, 1.05), CFrame.new(0, 3.65, 0), Color3.fromRGB(200, 170, 60), Enum.Material.Metal)
	local lamp = add(Vector3.new(0.3, 0.3, 0.1), CFrame.new(0, 3.65, -0.55), Color3.fromRGB(255, 230, 150), Enum.Material.Neon)
	light(lamp, Color3.fromRGB(255, 220, 150), 1, 8)
	add(Vector3.new(0.18, 2.2, 0.18), CFrame.new(0.9, 3.0, -0.9) * CFrame.Angles(math.rad(-50), 0, 0), Color3.fromRGB(110, 80, 50), Enum.Material.Wood)
	add(Vector3.new(1.4, 0.25, 0.25), CFrame.new(0.9, 3.8, -1.55) * CFrame.Angles(math.rad(-50), 0, 0), Color3.fromRGB(90, 90, 95), Enum.Material.Metal)
	return assemble("MinerStatue", base, parts)
end

DECOR_BUILDERS.MoleStatue = function()
	local gold = Color3.fromRGB(255, 195, 60)
	local base, parts, topY = pedestal(1.2, Color3.fromRGB(40, 38, 44), Enum.Material.Marble)
	local function add(shape, size, cf, color, material)
		local p = part({ Shape = shape, Size = size, Material = material or Enum.Material.Foil, Color = color or gold })
		p.CFrame = CFrame.new(0, topY, 0) * cf
		table.insert(parts, p)
		return p
	end
	local body = add(Enum.PartType.Ball, Vector3.one * 2.2, CFrame.new(0, 1.1, 0))
	add(Enum.PartType.Ball, Vector3.one * 1.5, CFrame.new(0, 2.3, -0.45))
	add(Enum.PartType.Ball, Vector3.one * 0.45, CFrame.new(0, 2.2, -1.2), Color3.fromRGB(255, 120, 150), Enum.Material.SmoothPlastic)
	add(Enum.PartType.Ball, Vector3.one * 0.18, CFrame.new(-0.32, 2.55, -1.08), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic)
	add(Enum.PartType.Ball, Vector3.one * 0.18, CFrame.new(0.32, 2.55, -1.08), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic)
	add(Enum.PartType.Block, Vector3.new(0.7, 0.25, 0.5), CFrame.new(-0.85, 0.35, -0.8) * CFrame.Angles(0, math.rad(20), 0))
	add(Enum.PartType.Block, Vector3.new(0.7, 0.25, 0.5), CFrame.new(0.85, 0.35, -0.8) * CFrame.Angles(0, math.rad(-20), 0))
	add(Enum.PartType.Block, Vector3.new(1.3, 0.4, 1.3), CFrame.new(0, 3.1, -0.45), Color3.fromRGB(255, 225, 90), Enum.Material.Metal)
	light(body, gold, 1.3, 12)
	sparkles(body, Color3.fromRGB(255, 230, 120), 3, 0.3)
	return assemble("MoleStatue", base, parts)
end

DECOR_BUILDERS.PlushMole = function()
	local fur = Color3.fromRGB(120, 85, 65)
	local root = part({ Size = Vector3.new(2, 0.1, 2), Transparency = 1, CastShadow = false })
	root.CFrame = CFrame.new(0, 0.05, 0)
	local parts = {}
	local function add(shape, size, cf, color, material)
		local p = part({ Shape = shape, Size = size, Material = material or Enum.Material.Fabric, Color = color or fur })
		p.CFrame = cf
		table.insert(parts, p)
		return p
	end
	add(Enum.PartType.Ball, Vector3.one * 2.4, CFrame.new(0, 1.2, 0))
	add(Enum.PartType.Ball, Vector3.one * 1.7, CFrame.new(0, 2.55, -0.25))
	add(Enum.PartType.Ball, Vector3.new(1.2, 0.9, 1.2), CFrame.new(0, 1.1, -0.95), Color3.fromRGB(215, 180, 150))
	add(Enum.PartType.Ball, Vector3.one * 0.55, CFrame.new(0, 2.4, -1.1), Color3.fromRGB(255, 140, 170), Enum.Material.SmoothPlastic)
	add(Enum.PartType.Ball, Vector3.one * 0.22, CFrame.new(-0.38, 2.8, -0.98), Color3.new(0.05, 0.05, 0.05), Enum.Material.SmoothPlastic)
	add(Enum.PartType.Ball, Vector3.one * 0.22, CFrame.new(0.38, 2.8, -0.98), Color3.new(0.05, 0.05, 0.05), Enum.Material.SmoothPlastic)
	add(Enum.PartType.Ball, Vector3.one * 0.3, CFrame.new(-0.55, 2.55, -0.9), Color3.fromRGB(255, 160, 170))
	add(Enum.PartType.Ball, Vector3.one * 0.3, CFrame.new(0.55, 2.55, -0.9), Color3.fromRGB(255, 160, 170))
	add(Enum.PartType.Ball, Vector3.new(0.8, 0.5, 0.9), CFrame.new(-1.05, 1.5, -0.6), Color3.fromRGB(235, 190, 170))
	add(Enum.PartType.Ball, Vector3.new(0.8, 0.5, 0.9), CFrame.new(1.05, 1.5, -0.6), Color3.fromRGB(235, 190, 170))
	add(Enum.PartType.Ball, Vector3.new(0.9, 0.5, 1.1), CFrame.new(-0.6, 0.25, -0.7), Color3.fromRGB(235, 190, 170))
	add(Enum.PartType.Ball, Vector3.new(0.9, 0.5, 1.1), CFrame.new(0.6, 0.25, -0.7), Color3.fromRGB(235, 190, 170))
	-- Бантик — маленькая деталь, из-за которой игрушка читается как игрушка.
	add(Enum.PartType.Block, Vector3.new(0.9, 0.35, 0.2), CFrame.new(0, 1.85, -0.95), Color3.fromRGB(230, 60, 80), Enum.Material.SmoothPlastic)
	return assemble("PlushMole", root, parts)
end

--------------------------------------------------------------------------------
-- v20.22: РАСТЕНИЯ, СКАМЕЙКА, СУНДУК-ХРАНИЛИЩЕ, БАНКА ДЛЯ РУДЫ.
-- «Лицо» у всех — сторона -Z (как у плюшевого крота): туда смотрит сидящий
-- на скамейке, туда открывается крышка сундука.
--------------------------------------------------------------------------------
-- Cylinder в Roblox лежит вдоль X; стоячий — поворот на 90° вокруг Z.
local function builderKit()
	local parts = {}
	local function add(props, cf)
		local p = part(props)
		p.CFrame = cf
		table.insert(parts, p)
		return p
	end
	return parts, add
end

-- Цветок: стебель, два листа и головка.
local function flower(add, position, height, headColor, headShape)
	local stem = Color3.fromRGB(70, 150, 60)
	add({ Size = Vector3.new(0.12, height, 0.12), Material = Enum.Material.Grass, Color = stem }, CFrame.new(position + Vector3.new(0, height / 2, 0)))
	add({ Size = Vector3.new(0.45, 0.06, 0.2), Material = Enum.Material.Grass, Color = stem }, CFrame.new(position + Vector3.new(0.18, height * 0.35, 0)) * CFrame.Angles(0, 0, math.rad(25)))
	add({ Size = Vector3.new(0.45, 0.06, 0.2), Material = Enum.Material.Grass, Color = stem }, CFrame.new(position + Vector3.new(-0.18, height * 0.55, 0)) * CFrame.Angles(0, 0, math.rad(-25)))
	add({ Shape = headShape or Enum.PartType.Ball, Size = Vector3.new(0.42, 0.55, 0.42), Material = Enum.Material.SmoothPlastic, Color = headColor }, CFrame.new(position + Vector3.new(0, height + 0.2, 0)))
end

DECOR_BUILDERS.Flowers1 = function()
	-- Грядка тюльпанов: холмик земли и шесть цветков разных цветов.
	local parts, add = builderKit()
	local root = part({ Size = Vector3.new(2.6, 0.1, 2.6), Transparency = 1, CastShadow = false })
	root.CFrame = CFrame.new(0, 0.05, 0)
	add({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.35, 2.6, 2.6), Material = Enum.Material.Ground, Color = Color3.fromRGB(105, 72, 45) }, CFrame.new(0, 0.17, 0) * CFrame.Angles(0, 0, math.rad(90)))
	local colors = { Color3.fromRGB(235, 60, 80), Color3.fromRGB(255, 150, 190), Color3.fromRGB(255, 210, 60), Color3.fromRGB(235, 60, 80), Color3.fromRGB(200, 110, 255), Color3.fromRGB(255, 255, 240) }
	for i, color in colors do
		local angle = i / #colors * math.pi * 2
		local radius = i % 2 == 0 and 0.75 or 0.4
		flower(add, Vector3.new(math.cos(angle) * radius, 0.3, math.sin(angle) * radius), 0.9 + (i % 3) * 0.2, color)
	end
	return assemble("Flowers1", root, parts)
end

DECOR_BUILDERS.Flowers2 = function()
	-- Подсолнухи в глиняном горшке: три высоких стебля с жёлтыми «тарелками».
	local parts, add = builderKit()
	local terracotta = Color3.fromRGB(190, 100, 60)
	local root = part({ Size = Vector3.new(1.8, 0.1, 1.8), Transparency = 1, CastShadow = false })
	root.CFrame = CFrame.new(0, 0.05, 0)
	add({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.3, 1.6, 1.6), Material = Enum.Material.Brick, Color = terracotta }, CFrame.new(0, 0.65, 0) * CFrame.Angles(0, 0, math.rad(90)))
	add({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, 1.85, 1.85), Material = Enum.Material.Brick, Color = terracotta:Lerp(Color3.new(1, 1, 1), 0.1) }, CFrame.new(0, 1.35, 0) * CFrame.Angles(0, 0, math.rad(90)))
	add({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 1.5, 1.5), Material = Enum.Material.Ground, Color = Color3.fromRGB(80, 55, 35) }, CFrame.new(0, 1.44, 0) * CFrame.Angles(0, 0, math.rad(90)))
	for i, spec in { { -0.35, 2.4, -0.1, 12 }, { 0.35, 2.0, 0.15, -10 }, { 0, 2.8, 0.3, 4 } } do
		local x, height, z, tilt = spec[1], spec[2], spec[3], spec[4]
		local base = Vector3.new(x, 1.45, z)
		add({ Size = Vector3.new(0.14, height, 0.14), Material = Enum.Material.Grass, Color = Color3.fromRGB(80, 150, 55) }, CFrame.new(base + Vector3.new(0, height / 2, 0)))
		add({ Size = Vector3.new(0.55, 0.06, 0.3), Material = Enum.Material.Grass, Color = Color3.fromRGB(80, 150, 55) }, CFrame.new(base + Vector3.new(0.22, height * 0.45, 0)) * CFrame.Angles(0, 0, math.rad(20)))
		local head = CFrame.new(base + Vector3.new(0, height + 0.1, 0)) * CFrame.Angles(math.rad(-70 + tilt), 0, 0)
		add({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 1.1 - i * 0.05, 1.1 - i * 0.05), Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(255, 205, 40) }, head * CFrame.Angles(0, math.rad(90), 0))
		add({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.16, 0.5, 0.5), Material = Enum.Material.Fabric, Color = Color3.fromRGB(95, 60, 30) }, head * CFrame.new(0, 0, -0.04) * CFrame.Angles(0, math.rad(90), 0))
	end
	return assemble("Flowers2", root, parts)
end

-- Куст из шаров листвы. berries — сколько ягод рассыпать сверху.
local function bush(name, specs, leaf, berries, berryColor)
	local parts, add = builderKit()
	local root = part({ Size = Vector3.new(2.6, 0.1, 2.6), Transparency = 1, CastShadow = false })
	root.CFrame = CFrame.new(0, 0.05, 0)
	local top = 0
	for i, s in specs do
		add({ Shape = Enum.PartType.Ball, Size = Vector3.one * s[4], Material = Enum.Material.Grass, Color = leaf:Lerp(Color3.new(0, 0, 0), (i % 3) * 0.06) }, CFrame.new(s[1], s[2], s[3]))
		top = math.max(top, s[2] + s[4] / 2)
	end
	for i = 1, berries or 0 do
		local angle = i * 2.4
		local y = 0.8 + (i % 4) * 0.35
		local r = 1.05 - math.abs(y - 1.2) * 0.25
		add({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.24, Material = Enum.Material.SmoothPlastic, Color = berryColor, CastShadow = false }, CFrame.new(math.cos(angle) * r, y, math.sin(angle) * r))
	end
	return assemble(name, root, parts)
end

DECOR_BUILDERS.Bush1 = function()
	return bush("Bush1", {
		{ 0, 1.0, 0, 2.0 }, { 0.7, 0.75, 0.2, 1.5 }, { -0.7, 0.7, -0.1, 1.4 }, { 0.1, 0.7, 0.75, 1.3 }, { -0.1, 0.8, -0.7, 1.3 }, { 0, 1.7, 0, 1.2 },
	}, Color3.fromRGB(85, 165, 70))
end

DECOR_BUILDERS.Bush2 = function()
	return bush("Bush2", {
		{ 0, 1.2, 0, 2.3 }, { 0.85, 0.85, 0.2, 1.7 }, { -0.85, 0.85, -0.1, 1.7 }, { 0.15, 0.85, 0.9, 1.5 }, { -0.1, 0.9, -0.85, 1.5 }, { 0.2, 2.0, 0.1, 1.4 }, { -0.4, 1.8, 0.3, 1.1 },
	}, Color3.fromRGB(50, 120, 60), 12, Color3.fromRGB(220, 40, 70))
end

DECOR_BUILDERS.Bench = function()
	-- Деревянная скамейка на чугунных ножках. Внутри — настоящий Seat "Seat":
	-- на него сажает промпт SIT (сам по касанию не садит: CanTouch = false).
	local parts, add = builderKit()
	local wood = Color3.fromRGB(150, 100, 55)
	local iron = Color3.fromRGB(45, 45, 50)
	local root = part({ Size = Vector3.new(5, 0.1, 1.8), Transparency = 1, CastShadow = false })
	root.CFrame = CFrame.new(0, 0.05, 0)
	for _, x in { -2.1, 2.1 } do
		add({ Size = Vector3.new(0.25, 1.5, 1.5), Material = Enum.Material.Metal, Color = iron }, CFrame.new(x, 0.75, 0))
		add({ Size = Vector3.new(0.25, 1.9, 0.25), Material = Enum.Material.Metal, Color = iron }, CFrame.new(x, 2.1, 0.75) * CFrame.Angles(math.rad(-10), 0, 0))
		add({ Size = Vector3.new(0.3, 0.2, 1.4), Material = Enum.Material.Metal, Color = iron }, CFrame.new(x, 2.05, 0.05))
	end
	for i, z in { -0.5, 0, 0.5 } do
		add({ Size = Vector3.new(4.9, 0.18, 0.44), Material = Enum.Material.WoodPlanks, Color = wood:Lerp(Color3.new(0, 0, 0), (i % 2) * 0.08) }, CFrame.new(0, 1.55, z))
	end
	for i, y in { 2.2, 2.75 } do
		add({ Size = Vector3.new(4.9, 0.4, 0.14), Material = Enum.Material.WoodPlanks, Color = wood:Lerp(Color3.new(0, 0, 0), (i % 2) * 0.08) }, CFrame.new(0, y, 0.72 + (y - 1.6) * 0.18) * CFrame.Angles(math.rad(-10), 0, 0))
	end
	local seat = Instance.new("Seat")
	seat.Name = "Seat"
	seat.Size = Vector3.new(4.4, 0.2, 1.4)
	seat.CFrame = CFrame.new(0, 1.6, 0)
	seat.Transparency = 1
	seat.Anchored = true
	seat.CanCollide = false
	seat.CanTouch = false
	seat.CanQuery = false
	seat.CastShadow = false
	table.insert(parts, seat)
	return assemble("Bench", root, parts)
end

DECOR_BUILDERS.StorageChest = function()
	-- Окованный деревянный сундук с золотым замком, из-под крышки — свет руды.
	local parts, add = builderKit()
	local wood = Color3.fromRGB(120, 75, 40)
	local iron = Color3.fromRGB(60, 60, 68)
	local gold = Color3.fromRGB(255, 200, 70)
	local root = add({ Size = Vector3.new(3.4, 1.7, 2.2), Material = Enum.Material.WoodPlanks, Color = wood }, CFrame.new(0, 0.85, 0))
	table.remove(parts, 1)
	add({ Size = Vector3.new(3.5, 0.7, 2.3), Material = Enum.Material.WoodPlanks, Color = wood:Lerp(Color3.new(1, 1, 1), 0.06) }, CFrame.new(0, 2.05, 0))
	add({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.5, 1.2, 2.3), Material = Enum.Material.WoodPlanks, Color = wood:Lerp(Color3.new(1, 1, 1), 0.06) }, CFrame.new(0, 2.3, 0))
	for _, x in { -1.3, 0, 1.3 } do
		add({ Size = Vector3.new(0.22, 1.75, 2.28), Material = Enum.Material.Metal, Color = iron }, CFrame.new(x, 0.87, 0))
		add({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.24, 1.26, 2.36), Material = Enum.Material.Metal, Color = iron }, CFrame.new(x, 2.3, 0))
	end
	add({ Size = Vector3.new(0.6, 0.7, 0.2), Material = Enum.Material.Metal, Color = gold }, CFrame.new(0, 1.75, -1.2))
	local glow = add({ Size = Vector3.new(3.1, 0.08, 1.9), Material = Enum.Material.Neon, Color = Color3.fromRGB(120, 220, 255), CastShadow = false }, CFrame.new(0, 1.72, 0))
	light(glow, Color3.fromRGB(140, 220, 255), 0.8, 7)
	return assemble("StorageChest", root, parts)
end

DECOR_BUILDERS.OreJar = function()
	-- Стеклянная банка на деревянной подставке с медной крышкой. Невидимая
	-- деталь "OreSpot" — центр, где крутится руда.
	local parts, add = builderKit()
	local root = add({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.35, 2.3, 2.3), Material = Enum.Material.Wood, Color = Color3.fromRGB(110, 70, 40) }, CFrame.new(0, 0.175, 0) * CFrame.Angles(0, 0, math.rad(90)))
	table.remove(parts, 1)
	add({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.3, 1.9, 1.9), Material = Enum.Material.Glass, Color = Color3.fromRGB(210, 235, 255), Transparency = 0.65, CastShadow = false }, CFrame.new(0, 1.5, 0) * CFrame.Angles(0, 0, math.rad(90)))
	add({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 1.6, 1.6), Material = Enum.Material.Glass, Color = Color3.fromRGB(210, 235, 255), Transparency = 0.55, CastShadow = false }, CFrame.new(0, 2.8, 0) * CFrame.Angles(0, 0, math.rad(90)))
	add({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 1.75, 1.75), Material = Enum.Material.Metal, Color = Color3.fromRGB(190, 120, 70) }, CFrame.new(0, 3.05, 0) * CFrame.Angles(0, 0, math.rad(90)))
	add({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.4, Material = Enum.Material.Metal, Color = Color3.fromRGB(210, 150, 90) }, CFrame.new(0, 3.3, 0))
	add({ Size = Vector3.new(0.3, 0.3, 0.3), Transparency = 1, CastShadow = false, CanQuery = false }, CFrame.new(0, 1.5, 0)).Name = "OreSpot"
	return assemble("OreJar", root, parts)
end

--------------------------------------------------------------------------------
-- РЕЛИКВИЯ: постамент + сам трофей с эмиттерами и светом.
--------------------------------------------------------------------------------
local RELIC_BUILDERS = {}

RELIC_BUILDERS.GoldenPickaxeTrophy = function(info)
	local p1 = part({ Size = Vector3.new(0.25, 2.6, 0.25), Material = Enum.Material.Foil, Color = info.Color })
	p1.CFrame = CFrame.new(0, 1.3, 0) * CFrame.Angles(0, 0, math.rad(20))
	local head = part({ Size = Vector3.new(2, 0.35, 0.35), Material = Enum.Material.Foil, Color = info.Color })
	head.CFrame = CFrame.new(-0.45, 2.5, 0) * CFrame.Angles(0, 0, math.rad(20))
	return { p1, head }, p1
end

RELIC_BUILDERS.CrownedMoleSkull = function(info)
	local skull = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.5, Material = Enum.Material.Marble, Color = info.Color })
	skull.CFrame = CFrame.new(0, 0.9, 0)
	local snout = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.8, 0.6, 0.9), Material = Enum.Material.Marble, Color = info.Color })
	snout.CFrame = CFrame.new(0, 0.7, -0.7)
	local eyeL = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.32, Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 60, 60), CastShadow = false })
	eyeL.CFrame = CFrame.new(-0.3, 1.05, -0.62)
	local eyeR = eyeL:Clone()
	eyeR.CFrame = CFrame.new(0.3, 1.05, -0.62)
	local crown = part({ Size = Vector3.new(1.2, 0.45, 1.2), Material = Enum.Material.Foil, Color = Color3.fromRGB(255, 200, 60) })
	crown.CFrame = CFrame.new(0, 1.75, 0)
	local parts = { skull, snout, eyeL, eyeR, crown }
	for i = 0, 3 do
		local spike = part({ Size = Vector3.new(0.22, 0.45, 0.22), Material = Enum.Material.Foil, Color = Color3.fromRGB(255, 210, 70) })
		spike.CFrame = CFrame.new(math.cos(i * math.pi / 2) * 0.5, 2.1, math.sin(i * math.pi / 2) * 0.5) * CFrame.Angles(0, math.rad(45), 0)
		table.insert(parts, spike)
	end
	return parts, skull
end

RELIC_BUILDERS.DragonEggFossil = function(info)
	local egg = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(1.5, 2.1, 1.5), Material = Enum.Material.Slate, Color = Color3.fromRGB(70, 45, 40) })
	egg.CFrame = CFrame.new(0, 1.1, 0)
	local parts = { egg }
	for i = 1, 4 do
		local vein = part({ Size = Vector3.new(0.12, 1.4, 0.12), Material = Enum.Material.Neon, Color = info.Color, CastShadow = false })
		vein.CFrame = CFrame.new(0, 1.1, 0) * CFrame.Angles(0, math.rad(i * 90), 0) * CFrame.new(0, 0, -0.74) * CFrame.Angles(0, 0, math.rad(i * 17))
		table.insert(parts, vein)
	end
	return parts, egg
end

RELIC_BUILDERS.HeartOfTheMountain = function(info)
	local core = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.4, Material = Enum.Material.Neon, Color = info.Color, CastShadow = false })
	core.CFrame = CFrame.new(0, 1.3, 0)
	local shell = part({ Size = Vector3.new(1.3, 1.3, 1.3), Material = Enum.Material.Glass, Transparency = 0.45, Color = Color3.fromRGB(255, 180, 220) })
	shell.CFrame = CFrame.new(0, 1.3, 0) * CFrame.Angles(math.rad(45), math.rad(45), 0)
	local parts = { core, shell }
	for i = 1, 3 do
		local shard = part({ Size = Vector3.new(0.3, 0.9, 0.3), Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 120, 200), CastShadow = false })
		shard.CFrame = CFrame.new(0, 1.3, 0) * CFrame.Angles(0, math.rad(i * 120), 0) * CFrame.new(0, 0, -1.1) * CFrame.Angles(math.rad(20), 0, 0)
		table.insert(parts, shard)
	end
	return parts, core
end

local function buildRelicPlaceholder(relicId, info)
	local builder = RELIC_BUILDERS[relicId]
	local objectParts, focus
	if builder then objectParts, focus = builder(info) end
	if not objectParts then
		local gem = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.4, Material = Enum.Material.Neon, Color = info.Color })
		gem.CFrame = CFrame.new(0, 1, 0)
		objectParts, focus = { gem }, gem
	end
	local model = Instance.new("Model")
	model.Name = "RelicObject"
	local root = part({ Size = Vector3.new(1.4, 0.1, 1.4), Transparency = 1, CastShadow = false })
	root.CFrame = CFrame.new(0, 0.05, 0)
	root.Name = "Root"
	root.Parent = model
	for _, p in objectParts do p.Parent = model end
	model.PrimaryPart = root
	model.WorldPivot = CFrame.new(0, 0, 0)
	light(focus, info.Color, 2.5, 16)
	sparkles(focus, info.Color, 8, 0.35)
	-- Второй слой — медленный «ореол», чтобы трофей светился даже днём.
	local halo = sparkles(focus, info.Color:Lerp(Color3.new(1, 1, 1), 0.4), 2, 0.9)
	halo.Name = "Halo"
	halo.Lifetime = NumberRange.new(1.5, 2.5)
	halo.Speed = NumberRange.new(0.1, 0.3)
	return model
end

-- Постамент реликвии (свой — Assets.RelicPedestal, пивот у земли; верх —
-- часть "Top" или верх габарита).
local function buildRelicPedestal()
	local custom = fromAsset("RelicPedestal")
	if custom then
		local topPart = custom:FindFirstChild("Top", true)
		local topY
		if topPart and topPart:IsA("BasePart") then
			topY = custom.WorldPivot:PointToObjectSpace(topPart.Position + Vector3.new(0, topPart.Size.Y / 2, 0)).Y
		else
			local _, size = custom:GetBoundingBox()
			topY = size.Y
		end
		return custom, topY
	end
	local base, parts, topY = pedestal(1.6, Color3.fromRGB(230, 225, 215), Enum.Material.Marble)
	local trim = part({ Size = Vector3.new(2.3, 0.12, 2.3), Material = Enum.Material.Foil, Color = Color3.fromRGB(255, 200, 70) })
	trim.CFrame = CFrame.new(0, topY - 0.02, 0)
	table.insert(parts, trim)
	return assemble("RelicPedestal", base, parts), topY
end

--------------------------------------------------------------------------------
-- ПУБЛИЧНОЕ API
--------------------------------------------------------------------------------

-- Тотем или декор по ID из PlaceableCatalog.
function PlaceableFactory.BuildItem(itemId)
	local info = PlaceableCatalog.Info(itemId)
	if not info then return nil end
	local model = fromAsset(info.Kind == "Totem" and (info.Asset .. "_T" .. info.Tier) or info.Asset)
		or (info.Kind == "Totem" and fromAsset(info.Asset))
		or nil
	if not model then
		if info.Kind == "Totem" then
			model = buildTotem(info)
		else
			local builder = DECOR_BUILDERS[info.Type]
			model = builder and builder() or nil
		end
	end
	if not model then return nil end
	model.Name = itemId
	-- v20.22: «рабочему» декору из своих моделей дорисовываем недостающее.
	local decorDef = info.Kind == "Decor" and Config.Placeables.Decor[info.Type]
	local fn = decorDef and decorDef.Function
	if fn == "Seat" or fn == "Jar" then
		local ok, boxCFrame, boxSize = pcall(function() return model:GetBoundingBox() end)
		if ok then
			if fn == "Seat" and not model:FindFirstChildWhichIsA("Seat", true) then
				-- Нет Seat в модели — невидимое сиденье на 45% высоты.
				local seat = Instance.new("Seat")
				seat.Name = "Seat"
				seat.Size = Vector3.new(math.max(1, boxSize.X * 0.8), 0.2, math.max(1, boxSize.Z * 0.6))
				seat.CFrame = model:GetPivot() * CFrame.new(0, boxSize.Y * 0.45, 0)
				seat.Transparency = 1
				seat.Anchored = true
				seat.CanCollide = false
				seat.CanTouch = false
				seat.CanQuery = false
				seat.Parent = model
			elseif fn == "Jar" and not model:FindFirstChild("OreSpot", true) then
				local spot = part({ Name = "OreSpot", Size = Vector3.one * 0.3, Transparency = 1, CastShadow = false, CanQuery = false })
				spot.CFrame = CFrame.new(boxCFrame.Position)
				spot.Parent = model
			end
		end
	end
	for _, seat in model:GetDescendants() do
		if seat:IsA("Seat") then
			seat.CanTouch = false -- садит только промпт SIT, не случайное касание
			seat.Disabled = false
		end
	end
	-- У своих моделей тотемов тоже подсвечиваем тир: лёгкий свет цвета тира.
	if info.Kind == "Totem" and model:GetAttribute("CustomAsset") and model.PrimaryPart then
		light(model.PrimaryPart, info.TierColor or Color3.new(1, 1, 1), 1, 8)
	end
	return model
end

-- Реликвия на постаменте. Возвращает модель, у которой пивот у земли.
function PlaceableFactory.BuildRelic(relicId)
	local info = Config.Relics.Types[relicId]
	if not info then return nil end
	local holder = Instance.new("Model")
	holder.Name = "Relic_" .. relicId
	local pedestalModel, topY = buildRelicPedestal()
	pedestalModel.Name = "Pedestal"
	pedestalModel:PivotTo(CFrame.new())
	pedestalModel.Parent = holder
	local object = fromAsset(info.Asset) or buildRelicPlaceholder(relicId, info)
	object.Name = "RelicObject"
	object:PivotTo(CFrame.new(0, topY, 0))
	object.Parent = holder
	holder.PrimaryPart = pedestalModel.PrimaryPart
	holder.WorldPivot = CFrame.new()
	return holder
end

-- v20.9: сундук (свой — ReplicatedStorage.Assets.Chests.<ModelName>, иначе
-- ящик с крышкой цвета редкости). Общий для сервера (GearService) и
-- призрака установки (PlacementGhost).
function PlaceableFactory.BuildChest(rarity)
	local info = Config.Chests.Types[rarity]
	local folder = ReplicatedStorage
	for _, name in Config.Chests.AssetFolderPath or {} do
		folder = folder and folder:FindFirstChild(name)
	end
	local asset = folder and info and folder:FindFirstChild(info.ModelName)
	if asset then
		local clone = asset:Clone()
		if clone:IsA("Model") and not clone.PrimaryPart then
			clone.PrimaryPart = clone:FindFirstChildWhichIsA("BasePart", true)
		end
		return clone
	end
	-- Заглушка: ящик с крышкой цвета редкости.
	local model = Instance.new("Model")
	model.Name = info and info.ModelName or "Chest"
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(3, 2, 2)
	body.Color = Color3.fromRGB(120, 80, 45)
	body.Material = Enum.Material.Wood
	body.Parent = model
	local lid = Instance.new("Part")
	lid.Name = "Lid"
	lid.Size = Vector3.new(3.1, 0.7, 2.1)
	lid.Color = info and info.Color or Color3.new(1, 1, 1)
	lid.Material = Enum.Material.Metal
	lid.CFrame = body.CFrame * CFrame.new(0, 1.35, 0)
	lid.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = lid
	weld.Parent = body
	model.PrimaryPart = body
	return model
end

return PlaceableFactory
