--------------------------------------------------------------------------------
-- BuildCartSizeGuides — ОДНОРАЗОВЫЙ скрипт-ориентир.
--
-- ЧТО ДЕЛАЕТ: ставит в Workspace ряд из 8 размеченных партов — по одному
-- на каждый тир тележки (Config.CartTiers). Каждый показывает:
--   • "Floor" — минимальный пол под сетку слотов кристаллов (ОДИН И ТОТ ЖЕ
--     размер для ВСЕХ тиров — сетка Config.CartSlots не меняется, растёт
--     только высота стопки груза, не площадь).
--   • "StackHeight" — полупрозрачный столб той высоты, на которую
--     поднимется груз при ПОЛНОЙ тележке этого тира (кристаллы кладутся
--     слоями вверх, слой = Config.CartSlots.Cell студов).
--   • Табличка над ними с точными цифрами (пол, высота, capacity).
--
-- Модель Cart_TierN (см. README, таблица ассетов) должна иметь Root не
-- меньше размера "Floor" — остальное (форма бортов, декор, высота стенок)
-- на твой вкус, главное чтобы кристаллы физически помещались и были видны.
--
-- КАК ЗАПУСТИТЬ: Command Bar в Studio → вставить весь файл → Enter.
-- Идемпотентен: старая версия (Folder "CartSizeGuides" в Workspace) перед
-- пересборкой сносится. Когда домоделируешь — просто удали Folder руками,
-- скрипт не часть игры (в default.project.json не подключён).
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local slots = Config.CartSlots
local floorX = slots.Cols * slots.Cell -- одинаково для ВСЕХ тиров
local floorZ = slots.Rows * slots.Cell
local perLayer = slots.Cols * slots.Rows

local SPACING = 14 -- студов между тирами по X, чтобы не перекрывались
local BASE_CFRAME = CFrame.new(0, 5, 0) -- где встанет тир 1; двигай на глаз под свою карту

local existing = workspace:FindFirstChild("CartSizeGuides")
if existing then
	existing:Destroy()
end

local folder = Instance.new("Folder")
folder.Name = "CartSizeGuides"
folder.Parent = workspace

for tier, tierInfo in Config.CartTiers do
	local layers = math.ceil(tierInfo.Capacity / perLayer)
	local stackHeight = layers * slots.Cell
	local origin = BASE_CFRAME * CFrame.new((tier - 1) * SPACING, 0, 0)

	-- Пол — минимальный размер Root, чтобы сетка слотов физически влезла.
	local floor = Instance.new("Part")
	floor.Name = ("Tier%d_Floor"):format(tier)
	floor.Anchored = true
	floor.CanCollide = false
	floor.Material = Enum.Material.Neon
	floor.Color = Color3.fromHSV((tier - 1) / 8, 0.6, 1)
	floor.Transparency = 0.4
	floor.Size = Vector3.new(floorX, 0.2, floorZ)
	floor.CFrame = origin
	floor.Parent = folder

	-- Столб высоты — во столько поднимется груз при ПОЛНОЙ тележке этого тира.
	local stack = Instance.new("Part")
	stack.Name = ("Tier%d_StackHeight"):format(tier)
	stack.Anchored = true
	stack.CanCollide = false
	stack.Material = Enum.Material.ForceField
	stack.Color = floor.Color
	stack.Transparency = 0.75
	stack.Size = Vector3.new(floorX, stackHeight, floorZ)
	stack.CFrame = origin * CFrame.new(0, 0.1 + stackHeight / 2, 0)
	stack.Parent = folder

	-- Табличка с точными цифрами
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(6, 0, 1.6, 0)
	billboard.StudsOffset = Vector3.new(0, stackHeight + 2.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = floor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Text = ("Тир %d\nПол: %.1f x %.1f studs\nГруз до: %.1f studs (%d шт.)")
		:format(tier, floorX, floorZ, stackHeight, tierInfo.Capacity)
	label.Parent = billboard
end

print(("[BuildCartSizeGuides] Готово: 8 ориентиров в Workspace/CartSizeGuides. Пол одинаковый для всех тиров (%.1f x %.1f studs) — растёт только высота груза."):format(floorX, floorZ))
