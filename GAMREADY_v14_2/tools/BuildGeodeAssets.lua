-- Standalone Studio Command Bar builder for the geode system.
-- It only replaces geode-owned assets and StarterGui/GeodeUi.

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
local oldUi = StarterGui:FindFirstChild("GeodeUi")
if oldUi then oldUi:Destroy() end

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

local gui = Instance.new("ScreenGui")
gui.Name = "GeodeUi"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 28
gui.Enabled = false
gui.Parent = StarterGui
local dimmer = button("Dimmer", "", Color3.new(0, 0, 0))
dimmer.Size = UDim2.fromScale(1, 1)
dimmer.BackgroundTransparency = 0.35
dimmer.Parent = gui

local function inventoryPanel(name, titleText, gridName)
	local panel = Instance.new("Frame")
	panel.Name = name
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(720, 470)
	panel.BackgroundColor3 = Color3.fromRGB(30, 36, 49)
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Name = "ResponsiveScale"
	scale.Parent = panel
	local title = textLabel("Title", titleText)
	title.Position = UDim2.fromOffset(22, 14)
	title.Size = UDim2.new(1, -90, 0, 48)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel
	local close = button("CloseButton", "X", Color3.fromRGB(190, 65, 70))
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -14, 0, 14)
	close.Size = UDim2.fromOffset(42, 42)
	close.Parent = panel
	local grid = Instance.new("ScrollingFrame")
	grid.Name = gridName
	grid.Position = UDim2.fromOffset(20, 76)
	grid.Size = UDim2.new(1, -40, 1, -96)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 6
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.Parent = panel
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(185, 225)
	layout.CellPadding = UDim2.fromOffset(18, 18)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = grid
	return grid
end

local geodeGrid = inventoryPanel("VaultPanel", "GEODE STORAGE", "GeodeGrid")
local geodeTemplate = Instance.new("ImageButton")
geodeTemplate.Name = "GeodeCardTemplate"
geodeTemplate.BackgroundTransparency = 1
geodeTemplate.BorderSizePixel = 0
geodeTemplate.Visible = false
geodeTemplate.Parent = geodeGrid
local geodeName = textLabel("Name", "GEODE")
geodeName.Position = UDim2.fromOffset(5, 0)
geodeName.Size = UDim2.new(1, -10, 0, 26)
geodeName.Parent = geodeTemplate
local geodeBackground = Instance.new("ImageLabel")
geodeBackground.Name = "IconBackground"
geodeBackground.AnchorPoint = Vector2.new(0.5, 0)
geodeBackground.Position = UDim2.new(0.5, 0, 0, 28)
geodeBackground.Size = UDim2.fromOffset(170, 170)
geodeBackground.BackgroundColor3 = Color3.fromRGB(145, 155, 170)
geodeBackground.BorderSizePixel = 0
local slotBackgroundId = tonumber(Config.Geodes.Images.SlotBackground) or 0
geodeBackground.Image = slotBackgroundId ~= 0 and ("rbxassetid://" .. tostring(slotBackgroundId)) or ""
geodeBackground.ScaleType = Enum.ScaleType.Stretch
geodeBackground.Parent = geodeTemplate
local geodeIcon = Instance.new("ImageLabel")
geodeIcon.Name = "Icon"
geodeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
geodeIcon.Position = UDim2.fromScale(0.5, 0.5)
geodeIcon.Size = UDim2.fromScale(0.76, 0.76)
geodeIcon.BackgroundTransparency = 1
geodeIcon.ScaleType = Enum.ScaleType.Fit
geodeIcon.Parent = geodeBackground
local geodeCount = textLabel("Count", "x0")
geodeCount.Position = UDim2.new(0, 5, 1, -24)
geodeCount.Size = UDim2.new(1, -10, 0, 22)
geodeCount.TextColor3 = Color3.fromRGB(120, 255, 145)
geodeCount.Parent = geodeTemplate
local infoButton = button("InfoButton", "i", Color3.fromRGB(65, 85, 125))
infoButton.AnchorPoint = Vector2.new(1, 0)
infoButton.Position = UDim2.new(1, -8, 0, 34)
infoButton.Size = UDim2.fromOffset(26, 26)
infoButton.Parent = geodeTemplate
local dropInfo = Instance.new("Frame")
dropInfo.Name = "DropInfoPanel"
dropInfo.Position = UDim2.new(1, 12, 0, 76)
dropInfo.Size = UDim2.fromOffset(270, 380)
dropInfo.BackgroundColor3 = Color3.fromRGB(30, 36, 49)
dropInfo.BorderSizePixel = 0
dropInfo.Visible = false
dropInfo.Parent = geodeGrid.Parent
local infoTitle = textLabel("InfoTitle", "GEODE DROPS")
infoTitle.Position = UDim2.fromOffset(14, 12)
infoTitle.Size = UDim2.new(1, -28, 0, 34)
infoTitle.TextXAlignment = Enum.TextXAlignment.Left
infoTitle.Parent = dropInfo
local infoRarity = textLabel("InfoRarity", "RARITY")
infoRarity.Position = UDim2.fromOffset(14, 48)
infoRarity.Size = UDim2.new(1, -28, 0, 24)
infoRarity.TextXAlignment = Enum.TextXAlignment.Left
infoRarity.Parent = dropInfo
local chanceScroll = Instance.new("ScrollingFrame")
chanceScroll.Name = "ChanceScroll"
chanceScroll.Position = UDim2.fromOffset(14, 80)
chanceScroll.Size = UDim2.new(1, -28, 1, -150)
chanceScroll.BackgroundTransparency = 1
chanceScroll.BorderSizePixel = 0
chanceScroll.ScrollBarThickness = 5
chanceScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
chanceScroll.CanvasSize = UDim2.new()
chanceScroll.Parent = dropInfo
local infoChances = textLabel("InfoChances", "BASE DROP CHANCES")
infoChances.Size = UDim2.new(1, -8, 0, 0)
infoChances.AutomaticSize = Enum.AutomaticSize.Y
infoChances.TextXAlignment = Enum.TextXAlignment.Left
infoChances.TextYAlignment = Enum.TextYAlignment.Top
infoChances.TextSize = 14
infoChances.RichText = true
infoChances.Parent = chanceScroll
local crackButton = button("CrackButton", "CRACK GEODE", Color3.fromRGB(65, 155, 85))
crackButton.AnchorPoint = Vector2.new(0, 1)
crackButton.Position = UDim2.new(0, 14, 1, -12)
crackButton.Size = UDim2.new(1, -28, 0, 46)
crackButton.Active = false
crackButton.Parent = dropInfo

-- Кнопка "BUY GEODES" на самой панели хранилища + отдельная панель со
-- списком всех типов жеод для покупки за Robux (GeodeUI.client.lua ищет их
-- по этим именам — VaultPanel.BuyGeodesButton / BuyGeodesPanel.BuyGeodesGrid
-- .BuyGeodeCardTemplate; необязательный контракт, но раз уж собираем
-- билдером "настоящий" UI — добавляем сразу, чтобы фича не потерялась).
local vaultPanel = geodeGrid.Parent
local buyOpenButton = button("BuyGeodesButton", "BUY GEODES", Color3.fromRGB(65, 155, 85))
buyOpenButton.AnchorPoint = Vector2.new(1, 0)
buyOpenButton.Position = UDim2.new(1, -64, 0, 14)
buyOpenButton.Size = UDim2.fromOffset(140, 42)
buyOpenButton.Parent = vaultPanel

local buyGeodesGrid = inventoryPanel("BuyGeodesPanel", "BUY GEODES", "BuyGeodesGrid")
local buyGeodeTemplate = Instance.new("Frame")
buyGeodeTemplate.Name = "BuyGeodeCardTemplate"
buyGeodeTemplate.BackgroundTransparency = 1
buyGeodeTemplate.BorderSizePixel = 0
buyGeodeTemplate.Visible = false
buyGeodeTemplate.Parent = buyGeodesGrid
local buyName = textLabel("Name", "GEODE")
buyName.Position = UDim2.fromOffset(5, 0)
buyName.Size = UDim2.new(1, -10, 0, 26)
buyName.Parent = buyGeodeTemplate
local buyBackground = Instance.new("ImageLabel")
buyBackground.Name = "IconBackground"
buyBackground.AnchorPoint = Vector2.new(0.5, 0)
buyBackground.Position = UDim2.new(0.5, 0, 0, 28)
buyBackground.Size = UDim2.fromOffset(170, 130)
buyBackground.BackgroundColor3 = Color3.fromRGB(145, 155, 170)
buyBackground.BorderSizePixel = 0
buyBackground.Image = slotBackgroundId ~= 0 and ("rbxassetid://" .. tostring(slotBackgroundId)) or ""
buyBackground.ScaleType = Enum.ScaleType.Stretch
buyBackground.Parent = buyGeodeTemplate
local buyIcon = Instance.new("ImageLabel")
buyIcon.Name = "Icon"
buyIcon.AnchorPoint = Vector2.new(0.5, 0.5)
buyIcon.Position = UDim2.fromScale(0.5, 0.5)
buyIcon.Size = UDim2.fromScale(0.76, 0.76)
buyIcon.BackgroundTransparency = 1
buyIcon.ScaleType = Enum.ScaleType.Fit
buyIcon.Parent = buyBackground
local buyOwned = textLabel("Owned", "OWNED x0")
buyOwned.Position = UDim2.new(0, 5, 0, 160)
buyOwned.Size = UDim2.new(1, -10, 0, 20)
buyOwned.TextColor3 = Color3.fromRGB(120, 255, 145)
buyOwned.TextSize = 14
buyOwned.Parent = buyGeodeTemplate
local buyButton = button("BuyButton", "", Color3.fromRGB(65, 155, 85))
buyButton.Position = UDim2.new(0, 5, 1, -34)
buyButton.Size = UDim2.new(1, -10, 0, 30)
buyButton.Parent = buyGeodeTemplate
-- Подпись цены отдельным лейблом (не родным .Text кнопки) — просто чтобы
-- renderBuyGeodes мог менять текст через setButtonText одинаково с
-- остальным UI. Слева от кнопки ничего нет — вся ширина под текст.
local buyCaption = Instance.new("TextLabel")
buyCaption.Name = "Caption"
buyCaption.BackgroundTransparency = 1
buyCaption.Font = Enum.Font.Arcade
buyCaption.Text = "BUY -- R$0"
buyCaption.TextColor3 = Color3.new(1, 1, 1)
buyCaption.TextScaled = true
buyCaption.TextStrokeTransparency = 1
buyCaption.Position = UDim2.new(0, 2, 0, 2)
buyCaption.Size = UDim2.new(1, -4, 1, -4)
buyCaption.Parent = buyButton

local crystalGrid = inventoryPanel("PodiumPanel", "CRYSTAL COLLECTION", "CrystalGrid")
local crystalTemplate = Instance.new("ImageButton")
crystalTemplate.Name = "CrystalCardTemplate"
crystalTemplate.BackgroundTransparency = 1
crystalTemplate.BorderSizePixel = 0
crystalTemplate.Visible = false
crystalTemplate.Parent = crystalGrid
local crystalName = textLabel("Name", "CRYSTAL")
crystalName.Position = UDim2.fromOffset(5, 0)
crystalName.Size = UDim2.new(1, -10, 0, 26)
crystalName.Parent = crystalTemplate
local crystalBackground = Instance.new("ImageLabel")
crystalBackground.Name = "IconBackground"
crystalBackground.AnchorPoint = Vector2.new(0.5, 0)
crystalBackground.Position = UDim2.new(0.5, 0, 0, 28)
crystalBackground.Size = UDim2.fromOffset(170, 170)
crystalBackground.BackgroundColor3 = Color3.fromRGB(150, 155, 165)
crystalBackground.BorderSizePixel = 0
crystalBackground.Image = slotBackgroundId ~= 0 and ("rbxassetid://" .. tostring(slotBackgroundId)) or ""
crystalBackground.ScaleType = Enum.ScaleType.Stretch
crystalBackground.Parent = crystalTemplate
local crystalIcon = Instance.new("ImageLabel")
crystalIcon.Name = "Icon"
crystalIcon.AnchorPoint = Vector2.new(0.5, 0.5)
crystalIcon.Position = UDim2.fromScale(0.5, 0.5)
crystalIcon.Size = UDim2.fromScale(0.76, 0.76)
crystalIcon.BackgroundTransparency = 1
crystalIcon.ScaleType = Enum.ScaleType.Fit
crystalIcon.Parent = crystalBackground
local income = textLabel("Income", "$0/SEC")
income.Position = UDim2.new(0, 5, 1, -24)
income.Size = UDim2.new(1, -10, 0, 22)
income.TextColor3 = Color3.fromRGB(100, 255, 130)
income.Parent = crystalTemplate
local installed = textLabel("Installed", "INSTALLED")
installed.AnchorPoint = Vector2.new(1, 0)
installed.Position = UDim2.new(1, -8, 0, 34)
installed.Size = UDim2.fromOffset(90, 20)
installed.TextColor3 = Color3.fromRGB(100, 255, 130)
installed.TextXAlignment = Enum.TextXAlignment.Right
installed.Visible = false
installed.Parent = crystalTemplate

local opening = Instance.new("Frame")
opening.Name = "OpeningOverlay"
opening.Size = UDim2.fromScale(1, 1)
opening.BackgroundColor3 = Color3.fromRGB(12, 15, 24)
opening.BackgroundTransparency = 1
opening.BorderSizePixel = 0
opening.Visible = false
opening.ZIndex = 20
opening.Parent = gui
local flash = Instance.new("Frame")
flash.Name = "Flash"
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = Color3.new(1, 1, 1)
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.ZIndex = 23
flash.Parent = opening
local egg = Instance.new("ImageLabel")
egg.Name = "EggImage"
egg.AnchorPoint = Vector2.new(0.5, 0.5)
egg.Position = UDim2.fromScale(0.5, 0.48)
egg.Size = UDim2.fromOffset(230, 230)
egg.BackgroundTransparency = 1
egg.ScaleType = Enum.ScaleType.Fit
egg.ZIndex = 21
egg.Parent = opening
-- Свечение-вспышка позади жеоды в момент раскола (Pet Sim-стиль). Без своей
-- текстуры (Config.Geodes.Images.CrackGlow = 0) рисуется мягкий цветной круг.
local crackGlow = Instance.new("ImageLabel")
crackGlow.Name = "CrackGlow"
crackGlow.AnchorPoint = Vector2.new(0.5, 0.5)
crackGlow.Position = UDim2.fromScale(0.5, 0.48)
crackGlow.Size = UDim2.fromOffset(0, 0)
crackGlow.BackgroundTransparency = 1
crackGlow.ImageTransparency = 1
crackGlow.ScaleType = Enum.ScaleType.Fit
crackGlow.ZIndex = 19
crackGlow.Visible = false
crackGlow.Parent = opening
local crackGlowCorner = Instance.new("UICorner")
crackGlowCorner.CornerRadius = UDim.new(1, 0)
crackGlowCorner.Parent = crackGlow
-- Две "половинки" жеоды, разлетающиеся в стороны при расколе — обрезанные
-- (ClipsDescendants) рамки с полной картинкой жеоды внутри, сдвинутой так,
-- чтобы была видна только своя половина (см. GeodeUI.client.lua).
local function makeHalf(name, side)
	local half = Instance.new("Frame")
	half.Name = name
	half.AnchorPoint = side == "Left" and Vector2.new(0, 0.5) or Vector2.new(1, 0.5)
	half.Position = UDim2.fromScale(0.5, 0.48)
	half.Size = UDim2.fromOffset(0, 0)
	half.BackgroundTransparency = 1
	half.ClipsDescendants = true
	half.ZIndex = 21
	half.Visible = false
	half.Parent = opening
	local image = Instance.new("ImageLabel")
	image.Name = "HalfImage"
	image.AnchorPoint = side == "Left" and Vector2.new(0, 0.5) or Vector2.new(1, 0.5)
	image.Position = side == "Left" and UDim2.fromScale(0, 0.5) or UDim2.fromScale(1, 0.5)
	image.Size = UDim2.fromOffset(230, 230)
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Fit
	image.Parent = half
	return half
end
makeHalf("LeftHalf", "Left")
makeHalf("RightHalf", "Right")
local silhouette = egg:Clone()
silhouette.Name = "DropSilhouette"
silhouette.Position = UDim2.fromScale(0.5, 0.4)
silhouette.Size = UDim2.fromOffset(270, 270)
silhouette.ImageColor3 = Color3.new(1, 1, 1)
silhouette.Visible = false
silhouette.ZIndex = 21
silhouette.Parent = opening
local resultImage = egg:Clone()
resultImage.Name = "ResultImage"
resultImage.Position = UDim2.fromScale(0.5, 0.4)
resultImage.Size = UDim2.fromOffset(250, 250)
resultImage.Visible = false
resultImage.ZIndex = 22
resultImage.Parent = opening
local resultOutline = Instance.new("UIStroke")
resultOutline.Name = "DropOutline"
resultOutline.Color = Color3.new(0, 0, 0)
resultOutline.Thickness = tonumber(Config.Geodes.DropOutlineThickness) or 4
resultOutline.Transparency = tonumber(Config.Geodes.DropOutlineTransparency) or 0
resultOutline.Parent = resultImage
local resultText = textLabel("ResultText", "")
resultText.AnchorPoint = Vector2.new(0.5, 0)
resultText.Position = UDim2.fromScale(0.5, 0.63)
resultText.Size = UDim2.new(0.75, 0, 0, 110)
resultText.TextStrokeColor3 = Color3.new(0, 0, 0)
resultText.TextStrokeTransparency = 0
resultText.Visible = false
resultText.ZIndex = 22
resultText.Parent = opening
local skip = button("SkipButton", "SKIP", Color3.fromRGB(65, 85, 125))
skip.AnchorPoint = Vector2.new(1, 1)
skip.Position = UDim2.new(1, -20, 1, -20)
skip.Size = UDim2.fromOffset(110, 42)
skip.Visible = false
skip.ZIndex = 24
skip.Parent = opening

print("[BuildGeodeAssets] Geode world assets and StarterGui/GeodeUi created (incl. BUY GEODES button/panel). Only geode-owned targets were replaced.")
