-- Standalone Studio Command Bar builder for the geode system.
-- It only replaces geode-owned assets and StarterGui/GeodeUi (v20: GeodeUi — через UiRegistry).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Assets = ReplicatedStorage:WaitForChild("Assets")
local Config = require(ReplicatedStorage.Shared.Config)

assert(
	Config.Geodes and Config.Geodes.Ores and Config.Geodes.Types,
	"[BuildGeodeAssets] Config.Geodes отсутствует в Studio. Останови Play Test, дождись синхронизации Rojo и перезапусти Studio, чтобы сбросить кэш require(Config), затем запусти билдер снова."
)

local OWNED_ASSETS = {
	"GeodeBuilding", "GeodePodium", "GeodeSafe", "GeodeResultTemplates",
	"GeodeCartVFX",
}
for geodeType in Config.Geodes.Types do
	table.insert(OWNED_ASSETS, "Geode_" .. geodeType)
	table.insert(OWNED_ASSETS, "GeodeVFX_" .. geodeType)
end
for oreId in Config.Geodes.Ores do table.insert(OWNED_ASSETS, "CollectionOre_" .. oreId) end
for _, name in OWNED_ASSETS do
	local old = Assets:FindFirstChild(name)
	if old then old:Destroy() end
end

local cartVfx = Instance.new("Part")
cartVfx.Name = "GeodeCartVFX"
cartVfx.Size = Vector3.new(0.5, 0.5, 0.5)
cartVfx.Transparency = 1
cartVfx.Anchored = true
cartVfx.CanCollide = false
local cartBurst = Instance.new("ParticleEmitter")
cartBurst.Name = "GeodeCartBurst"
cartBurst.Color = ColorSequence.new(Color3.fromRGB(95, 210, 255), Color3.fromRGB(255, 255, 255))
cartBurst.LightEmission = 1
cartBurst.Lifetime = NumberRange.new(0.55, 1.1)
cartBurst.Speed = NumberRange.new(4, 9)
cartBurst.SpreadAngle = Vector2.new(180, 180)
cartBurst.Rate = 0
cartBurst.Size = NumberSequence.new(0.8, 0)
cartBurst.Parent = cartVfx
cartVfx.Parent = Assets

local function part(name, size, color, material)
	local item = Instance.new("Part")
	item.Name = name
	item.Size = size
	item.Color = color
	item.Material = material or Enum.Material.SmoothPlastic
	item.Anchored = true
	item.TopSurface = Enum.SurfaceType.Smooth
	item.BottomSurface = Enum.SurfaceType.Smooth
	return item
end

local building = Instance.new("Model")
building.Name = "GeodeBuilding"
local buildingRoot = part("Root", Vector3.new(10, 5, 7), Color3.fromRGB(42, 48, 62), Enum.Material.Metal)
buildingRoot.Parent = building
building.PrimaryPart = buildingRoot
local crusher = part("Crusher", Vector3.new(3.5, 2.5, 2.5), Color3.fromRGB(95, 135, 175), Enum.Material.Metal)
crusher.CFrame = CFrame.new(0, 0, -4)
crusher.Parent = building
building.Parent = Assets

local podium = part("GeodePodium", Vector3.new(6, 1.5, 6), Color3.fromRGB(75, 70, 100), Enum.Material.Marble)
podium.Parent = Assets
local safe = part("GeodeSafe", Vector3.new(4, 4, 3), Color3.fromRGB(45, 55, 65), Enum.Material.Metal)
safe.Parent = Assets

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

statusGui(buildingRoot, "UNAVAILABLE", Color3.fromRGB(255, 85, 85), 4)
statusGui(podium, "NO ORE INSTALLED", Color3.new(1, 1, 1), 5)
statusGui(safe, "$0", Color3.fromRGB(255, 220, 90), 3.5)

for geodeType, info in Config.Geodes.Types do
	local geode = part("Geode_" .. geodeType, Vector3.new(1.65, 1.65, 1.65), info.Color, Enum.Material.Slate)
	geode.Anchored = false
	local light = Instance.new("PointLight")
	light.Color = info.Color
	light.Brightness = 1.5
	light.Range = 8
	light.Parent = geode
	geode.Parent = Assets
	local vfx = Instance.new("Attachment")
	vfx.Name = "GeodeVFX_" .. geodeType
	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new(info.Color)
	particles.Rate = 8
	particles.Lifetime = NumberRange.new(0.5, 1)
	particles.Speed = NumberRange.new(0.5, 1.5)
	particles.Parent = vfx
	vfx.Parent = geode
end

for oreId, info in Config.Geodes.Ores do
	local ore = part("CollectionOre_" .. oreId, Vector3.new(2.3, 3.6, 2.3), info.Color, Enum.Material.Neon)
	ore.CanCollide = false
	ore.Parent = Assets
end

local templates = Instance.new("Folder")
templates.Name = "GeodeResultTemplates"
templates.Parent = Assets
for rarity, color in {
	Common = Color3.fromRGB(150, 155, 165), Uncommon = Color3.fromRGB(75, 195, 105),
	Rare = Color3.fromRGB(70, 135, 245), Epic = Color3.fromRGB(170, 85, 235), Legendary = Color3.fromRGB(245, 190, 55),
	Mythic = Color3.fromRGB(235, 45, 95),
} do
	local frame = Instance.new("Frame")
	frame.Name = rarity
	frame.BackgroundColor3 = color
	frame.Size = UDim2.fromOffset(240, 320)
	frame.Parent = templates
end

local function button(name, text, color)
	local item = Instance.new("TextButton")
	item.Name = name
	item.Text = text
	item.Font = Enum.Font.Arcade
	item.TextScaled = true
	item.TextColor3 = Color3.new(1, 1, 1)
	item.TextStrokeTransparency = 1
	item.BackgroundColor3 = color
	item.BorderSizePixel = 0
	return item
end

local function textLabel(name, text)
	local item = Instance.new("TextLabel")
	item.Name = name
	item.BackgroundTransparency = 1
	item.Font = Enum.Font.Arcade
	item.Text = text or ""
	item.TextColor3 = Color3.new(1, 1, 1)
	item.TextScaled = true
	item.TextWrapped = true
	item.TextStrokeTransparency = 1
	return item
end

-- v20: окно жеод собирает общий билдер (Shared.GeodeUiBuilder через
-- UiRegistry) — тот же, что и tools/BuildAllUI.lua, в едином стиле UiKit.
local UiRegistry = require(game:GetService("ReplicatedStorage").Shared.UiRegistry)
for _, line in UiRegistry.BuildAll(StarterGui, { GeodeUi = true }) do print("[BuildGeodeAssets] " .. line) end

print("[BuildGeodeAssets] Geode world assets and StarterGui/GeodeUi created (incl. BUY GEODES button/panel). Only geode-owned targets were replaced.")
