-- Studio Command Bar builder for the new skin and geode 3D assets.
-- Creates an editable preview pack in Workspace and never touches
-- ReplicatedStorage/Assets. Move the pack's CHILDREN, not the pack folder,
-- directly into ReplicatedStorage/Assets after replacing the placeholders.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Selection = game:GetService("Selection")

local Config = require(ReplicatedStorage.Shared.Config)
local PACK_NAME = "NEW_ASSETS_MOVE_CHILDREN_TO_ASSETS"

assert(
	Config.Geodes and Config.Geodes.Order and Config.Geodes.Types and Config.Geodes.Ores,
	"[BuildNewAssetWorkspacePack] Config.Geodes is unavailable. Stop Play Test, wait for Rojo sync, restart Studio, and run the builder again."
)
assert(
	Config.Skins and Config.Skins.Definitions,
	"[BuildNewAssetWorkspacePack] Config.Skins.Definitions is unavailable. Stop Play Test, wait for Rojo sync, restart Studio, and run the builder again."
)
assert(
	not workspace:FindFirstChild(PACK_NAME),
	"[BuildNewAssetWorkspacePack] Workspace already contains " .. PACK_NAME .. ". Rename or remove it only after saving your work."
)

local pack = Instance.new("Folder")
pack.Name = PACK_NAME
pack:SetAttribute("Destination", "ReplicatedStorage/Assets")
pack.Parent = workspace

local camera = workspace.CurrentCamera
local origin = camera and (camera.CFrame.Position + camera.CFrame.LookVector * 45) or Vector3.new(0, 10, 0)
origin = Vector3.new(math.round(origin.X), math.round(origin.Y), math.round(origin.Z))

local createdCount = 0

local function part(name, size, color, material, transparency)
	local item = Instance.new("Part")
	item.Name = name
	item.Size = size
	item.Color = color
	item.Material = material or Enum.Material.SmoothPlastic
	item.Transparency = transparency or 0
	item.Anchored = true
	item.CanCollide = false
	item.CanTouch = false
	item.TopSurface = Enum.SurfaceType.Smooth
	item.BottomSurface = Enum.SurfaceType.Smooth
	return item
end

local function addAsset(asset)
	asset.Parent = pack
	createdCount += 1
	return asset
end

local function place(asset, offset)
	local target = CFrame.new(origin + offset)
	if asset:IsA("Model") then
		asset:PivotTo(target)
	elseif asset:IsA("BasePart") then
		asset.CFrame = target
	end
end

local function statusGui(parent, text, color, offset)
	local gui = Instance.new("BillboardGui")
	gui.Name = "StatusGui"
	gui.Size = UDim2.fromOffset(280, 58)
	gui.StudsOffset = Vector3.new(0, offset, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 80
	gui.Parent = parent

	local label = Instance.new("TextLabel")
	label.Name = "Status"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Arcade
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.TextWrapped = true
	label.TextStrokeTransparency = 1
	label.Parent = gui
end

local skinPalette = {
	Skin_Pickaxe_BigWooden = { Color3.fromRGB(85, 45, 25), Color3.fromRGB(255, 95, 35) },
	Skin_Pickaxe_Crystal = { Color3.fromRGB(35, 65, 95), Color3.fromRGB(90, 225, 255) },
	Skin_Pickaxe_Love = { Color3.fromRGB(120, 170, 205), Color3.fromRGB(190, 245, 255) },
	Skin_Pickaxe_Radioactive = { Color3.fromRGB(45, 75, 38), Color3.fromRGB(125, 255, 80) },
	Skin_Pickaxe_VoidFixed = { Color3.fromRGB(28, 20, 42), Color3.fromRGB(185, 75, 255) },
	Skin_Cart_Miner = { Color3.fromRGB(75, 70, 62), Color3.fromRGB(255, 175, 55) },
	Skin_Cart_Royal = { Color3.fromRGB(65, 35, 105), Color3.fromRGB(255, 215, 70) },
	Skin_Cart_Industrial = { Color3.fromRGB(65, 75, 82), Color3.fromRGB(110, 225, 135) },
	Skin_Cart_Frost = { Color3.fromRGB(70, 130, 165), Color3.fromRGB(190, 245, 255) },
	Skin_Cart_Obsidian = { Color3.fromRGB(30, 28, 38), Color3.fromRGB(220, 80, 255) },
	Skin_Pickaxe_Amethyst = { Color3.fromRGB(90, 55, 20), Color3.fromRGB(255, 165, 60) },
	Skin_Cart_Amber = { Color3.fromRGB(90, 60, 30), Color3.fromRGB(255, 165, 60) },
	Skin_Pickaxe_CactusSword = { Color3.fromRGB(20, 70, 68), Color3.fromRGB(60, 220, 210) },
	Skin_Cart_Topaz = { Color3.fromRGB(25, 80, 78), Color3.fromRGB(60, 220, 210) },
	Skin_Pickaxe_Fish = { Color3.fromRGB(25, 70, 48), Color3.fromRGB(70, 220, 140) },
	Skin_Cart_Jade = { Color3.fromRGB(28, 78, 52), Color3.fromRGB(70, 220, 140) },
	Skin_Pickaxe_TungTungStick = { Color3.fromRGB(24, 20, 30), Color3.fromRGB(150, 100, 220) },
	Skin_Cart_Onyx = { Color3.fromRGB(26, 22, 34), Color3.fromRGB(150, 100, 220) },
	Skin_Pickaxe_BigMole = { Color3.fromRGB(70, 35, 70), Color3.fromRGB(255, 140, 220) },
	Skin_Cart_Aurora = { Color3.fromRGB(75, 40, 78), Color3.fromRGB(255, 140, 220) },
	Skin_Pickaxe_DevSword = { Color3.fromRGB(35, 15, 55), Color3.fromRGB(190, 90, 255) },
	Skin_Pickaxe_GoldSword = { Color3.fromRGB(120, 75, 15), Color3.fromRGB(255, 220, 70) },
	Skin_Pickaxe_GoldKunai = { Color3.fromRGB(95, 60, 15), Color3.fromRGB(255, 235, 90) },
	Skin_Cart_Nebula = { Color3.fromRGB(38, 18, 60), Color3.fromRGB(190, 90, 255) },
}

local rarityColor = {
	Common = Color3.fromRGB(145, 155, 170),
	Uncommon = Color3.fromRGB(75, 195, 105),
	Rare = Color3.fromRGB(70, 135, 245),
	Epic = Color3.fromRGB(170, 85, 235),
	Legendary = Color3.fromRGB(245, 190, 55),
	Mythic = Color3.fromRGB(235, 45, 95),
}

local function createPickaxeSkin(assetName, colors)
	local model = Instance.new("Model")
	model.Name = assetName

	local root = part("SkinRoot", Vector3.new(0.2, 0.2, 0.2), colors[1], nil, 1)
	root.Parent = model
	model.PrimaryPart = root
	local shaft = part("Shaft", Vector3.new(0.36, 3.8, 0.36), colors[1], Enum.Material.Wood)
	shaft.CFrame = CFrame.new(0, 1.5, 0)
	shaft.Parent = model
	local head = part("Head", Vector3.new(3.2, 0.5, 0.65), colors[2], Enum.Material.Neon)
	head.CFrame = CFrame.new(0, 3.25, 0)
	head.Parent = model
	return model
end

local function createCartSkin(assetName, colors)
	local model = Instance.new("Model")
	model.Name = assetName

	local root = part("SkinRoot", Vector3.new(0.2, 0.2, 0.2), colors[1], nil, 1)
	root.Parent = model
	model.PrimaryPart = root
	local body = part("Body", Vector3.new(7.5, 0.7, 5.5), colors[1], Enum.Material.Metal)
	body.CFrame = CFrame.new(0, 0.15, 0)
	body.Parent = model
	for _, z in { -2.6, 2.6 } do
		local trim = part("Trim", Vector3.new(7.8, 1.7, 0.35), colors[2], Enum.Material.Neon)
		trim.CFrame = CFrame.new(0, 1, z)
		trim.Parent = model
	end
	for _, x in { -3.6, 3.6 } do
		local trim = part("Trim", Vector3.new(0.35, 1.7, 5.3), colors[2], Enum.Material.Neon)
		trim.CFrame = CFrame.new(x, 1, 0)
		trim.Parent = model
	end
	return model
end

local skinDefinitions = {}
local seenAssetNames = {}
for skinId, definition in Config.Skins.Definitions do
	assert(definition.Kind == "Pickaxe" or definition.Kind == "Cart", "Unsupported skin Kind for " .. skinId)
	assert(type(definition.AssetName) == "string" and definition.AssetName ~= "", "Missing AssetName for " .. skinId)
	assert(not seenAssetNames[definition.AssetName], "Duplicate skin AssetName: " .. definition.AssetName)
	seenAssetNames[definition.AssetName] = true
	table.insert(skinDefinitions, definition)
end
table.sort(skinDefinitions, function(a, b)
	if a.Kind ~= b.Kind then return a.Kind == "Pickaxe" end
	return a.AssetName < b.AssetName
end)

local pickaxeIndex = 0
local cartIndex = 0
for _, definition in skinDefinitions do
	local fallback = rarityColor[definition.Rarity] or Color3.fromRGB(180, 180, 180)
	local colors = skinPalette[definition.AssetName] or { fallback, Color3.new(1, 1, 1) }
	local asset
	local offset
	if definition.Kind == "Pickaxe" then
		pickaxeIndex += 1
		asset = createPickaxeSkin(definition.AssetName, colors)
		offset = Vector3.new((pickaxeIndex - 6) * 6, 0, 0)
	else
		cartIndex += 1
		asset = createCartSkin(definition.AssetName, colors)
		offset = Vector3.new((cartIndex - 6) * 10, 0, 12)
	end
	addAsset(asset)
	place(asset, offset)
end

local geodeIndex = 0
for _, geodeType in Config.Geodes.Order do
	local info = assert(Config.Geodes.Types[geodeType], "Missing geode type: " .. geodeType)
	geodeIndex += 1
	local geode = part("Geode_" .. geodeType, Vector3.new(1.65, 1.65, 1.65), info.Color, Enum.Material.Slate)

	local light = Instance.new("PointLight")
	light.Color = info.Color
	light.Brightness = 1.5
	light.Range = 8
	light.Parent = geode

	local attachment = Instance.new("Attachment")
	attachment.Name = "GeodeVFX_" .. geodeType
	attachment.Parent = geode
	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new(info.Color)
	particles.Rate = 8
	particles.Lifetime = NumberRange.new(0.5, 1)
	particles.Speed = NumberRange.new(0.5, 1.5)
	particles.Parent = attachment

	addAsset(geode)
	place(geode, Vector3.new((geodeIndex - 4.5) * 6, 0, 24))
end

local oreIndex = 0
local seenOres = {}
for _, geodeType in Config.Geodes.Order do
	for _, oreId in Config.Geodes.Types[geodeType].Ores do
		assert(not seenOres[oreId], "Ore appears in more than one geode: " .. oreId)
		seenOres[oreId] = true
		local info = assert(Config.Geodes.Ores[oreId], "Missing ore definition: " .. oreId)
		oreIndex += 1
		local ore = part("CollectionOre_" .. oreId, Vector3.new(2.3, 3.6, 2.3), info.Color, Enum.Material.Neon)
		addAsset(ore)
		local column = (oreIndex - 1) % 8
		local row = math.floor((oreIndex - 1) / 8)
		place(ore, Vector3.new((column - 3.5) * 6, 0, 34 + row * 7))
	end
end
for oreId in Config.Geodes.Ores do
	assert(seenOres[oreId], "Ore is not assigned to a geode type: " .. oreId)
end

local building = Instance.new("Model")
building.Name = "GeodeBuilding"
local buildingRoot = part("Root", Vector3.new(10, 5, 7), Color3.fromRGB(42, 48, 62), Enum.Material.Metal)
buildingRoot.CanCollide = true
buildingRoot.Parent = building
building.PrimaryPart = buildingRoot
local crusher = part("Crusher", Vector3.new(3.5, 2.5, 2.5), Color3.fromRGB(95, 135, 175), Enum.Material.Metal)
crusher.CFrame = CFrame.new(0, 0, -4)
crusher.CanCollide = true
crusher.Parent = building
statusGui(buildingRoot, "UNAVAILABLE", Color3.fromRGB(255, 85, 85), 4)
addAsset(building)
place(building, Vector3.new(-18, 2.5, 60))

local podium = part("GeodePodium", Vector3.new(6, 1.5, 6), Color3.fromRGB(75, 70, 100), Enum.Material.Marble)
podium.CanCollide = true
statusGui(podium, "NO ORE INSTALLED", Color3.new(1, 1, 1), 5)
addAsset(podium)
place(podium, Vector3.new(-3, 0.75, 60))

local safe = part("GeodeSafe", Vector3.new(4, 4, 3), Color3.fromRGB(45, 55, 65), Enum.Material.Metal)
safe.CanCollide = true
statusGui(safe, "$0", Color3.fromRGB(255, 220, 90), 3.5)
addAsset(safe)
place(safe, Vector3.new(9, 2, 60))

local cartVfx = part("GeodeCartVFX", Vector3.new(0.5, 0.5, 0.5), Color3.new(1, 1, 1), nil, 1)
local cartBurst = Instance.new("ParticleEmitter")
cartBurst.Name = "GeodeCartBurst"
cartBurst:SetAttribute("EmitCount", 24)
cartBurst.Color = ColorSequence.new(Color3.fromRGB(95, 210, 255), Color3.fromRGB(255, 255, 255))
cartBurst.LightEmission = 1
cartBurst.Lifetime = NumberRange.new(0.55, 1.1)
cartBurst.Speed = NumberRange.new(4, 9)
cartBurst.SpreadAngle = Vector2.new(180, 180)
cartBurst.Rate = 0
cartBurst.Size = NumberSequence.new(0.8, 0)
cartBurst.Parent = cartVfx
addAsset(cartVfx)
place(cartVfx, Vector3.new(20, 2, 60))

local expectedCount = #skinDefinitions + #Config.Geodes.Order + oreIndex + 4
assert(createdCount == expectedCount, string.format("Created %d assets, expected %d", createdCount, expectedCount))
pack:SetAttribute("AssetCount", createdCount)
Selection:Set({ pack })

print(string.format(
	"[BuildNewAssetWorkspacePack] Created %d editable assets in Workspace/%s. Move all CHILDREN directly into ReplicatedStorage/Assets; do not move the wrapper folder.",
	createdCount,
	PACK_NAME
))
