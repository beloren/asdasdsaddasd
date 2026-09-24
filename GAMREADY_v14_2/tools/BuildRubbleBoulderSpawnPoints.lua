--------------------------------------------------------------------------------
-- BuildRubbleBoulderSpawnPoints — ОДНОРАЗОВЫЙ скрипт-сборщик.
-- Ставит 16 плейсхолдер-точек спавна валунов (workspace.RubbleBoulderSpawnPoints)
-- кольцом вокруг банка — временно, пока вы сами не расставите их по карте и
-- не сделаете модели (см. Boulder_Tier1..10 в PLACEHOLDERS_GUIDE.md).
--
-- Просто передвиньте/удалите/добавьте части внутри этой папки в Studio,
-- когда решите, где реально должны стоять валуны — код (RockService.lua)
-- сам подхватит любые BasePart внутри этой папки при следующем старте
-- сервера, их не обязательно оставлять ровно 16 и ровно кольцом.
--
-- Запускать через Command Bar (Studio): выделите этот скрипт и нажмите Run,
-- либо просто вставьте содержимое в Command Bar и выполните.
--------------------------------------------------------------------------------

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local POINT_COUNT = 16
local RADIUS = 70 -- студов от банка — достаточно далеко, чтобы не пересекаться с зоной продажи
local HEIGHT = 4 -- чуть приподнято над предполагаемым уровнем пола

-- Банк по умолчанию — геометрический центр карты (0, 8, 0), см.
-- WorldService.lua. Если у вас уже стоит своя модель банка с атрибутом
-- IsBank = true — точки строятся вокруг НЕЁ, а не вокруг (0,0,0).
local function findBankPosition()
	for _, instance in workspace:GetDescendants() do
		if instance:IsA("Model") and instance:GetAttribute("IsBank") then
			return instance:GetPivot().Position
		end
	end
	return Vector3.new(0, 0, 0)
end

local bankPosition = findBankPosition()

local existing = workspace:FindFirstChild("RubbleBoulderSpawnPoints")
if existing then
	existing:Destroy()
end

local folder = Instance.new("Folder")
folder.Name = "RubbleBoulderSpawnPoints"
folder.Parent = workspace

for index = 1, POINT_COUNT do
	local tier = ((index - 1) % 10) + 1 -- тот же цикл 1..10, что и фолбэк в RockService, если атрибут Tier не трогать
	local angle = (index - 1) / POINT_COUNT * math.pi * 2
	local position = bankPosition + Vector3.new(math.cos(angle) * RADIUS, HEIGHT, math.sin(angle) * RADIUS)

	local point = Instance.new("Part")
	point.Name = ("BoulderSpawn_%02d_Tier%d"):format(index, tier)
	point.Size = Vector3.new(4, 1, 4)
	point.CFrame = CFrame.new(position)
	point.Anchored = true
	point.CanCollide = false
	point.CanTouch = false
	point.CanQuery = false
	point.Transparency = 0.3
	point.Material = Enum.Material.Neon
	point.Color = (Config.MineTiers[tier] and Config.MineTiers[tier].Color) or Color3.fromRGB(200, 200, 200)
	point:SetAttribute("Tier", tier)
	point.Parent = folder

	local label = Instance.new("BillboardGui")
	label.Name = "TierLabel"
	label.Size = UDim2.fromOffset(80, 24)
	label.StudsOffset = Vector3.new(0, 2, 0)
	label.AlwaysOnTop = true
	label.Parent = point

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0
	text.Text = "T" .. tier
	text.Parent = label
end

print(("[BuildRubbleBoulderSpawnPoints] Done: %d placeholder points created in workspace.RubbleBoulderSpawnPoints around bank position %s. Move/replace them whenever you decide the real locations."):format(POINT_COUNT, tostring(bankPosition)))
