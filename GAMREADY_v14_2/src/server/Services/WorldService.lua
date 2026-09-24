--------------------------------------------------------------------------------
-- WorldService
-- Статичный мир: банк. По умолчанию банк ставится в геометрическом
-- центре карты (дорога от любой шахты до него максимально длинная и
-- опасная) — но это можно переопределить: отметь СВОЮ модель банка где
-- угодно в workspace атрибутом "IsBank" = true, и код возьмёт именно её,
-- не трогая её позицию (см. Start ниже).
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)

local WorldService = {}

local sellZone = nil
local bankModel = nil

function WorldService:Init(_services)
end

function WorldService:Start()
	-- Банк — либо СВОЯ модель, отмеченная атрибутом "IsBank" = true где
	-- угодно в workspace (билдер сам решает, где и как её построить —
	-- код её не трогает, не клонирует и не двигает, использует как есть),
	-- либо дефолтный плейсхолдер в геометрическом центре карты, если такой
	-- отметки нигде нет.
	local customBank = nil
	for _, instance in workspace:GetDescendants() do
		if instance:IsA("Model") and instance:GetAttribute("IsBank") then
			customBank = instance
			break
		end
	end

	if customBank then
		bankModel = customBank
	else
		bankModel = PlaceholderFactory.Bank()
		bankModel:PivotTo(CFrame.new(0, 8, 0))
		bankModel.Parent = workspace
	end

	sellZone = bankModel:FindFirstChild("SellZone", true)
	assert(sellZone, "У модели банка обязан быть Part 'SellZone'")

	-- Запасной нейтральный спавн (основной — на участке игрока). Invisible/
	-- без коллизии — та же причина, что и у персонального спавна в
	-- PlotService: чисто функциональная точка, а не физическая площадка.
	local fallbackSpawn = Instance.new("SpawnLocation")
	fallbackSpawn.Name = "FallbackSpawn"
	fallbackSpawn.Size = Vector3.new(8, 1, 8)
	fallbackSpawn.Position = Vector3.new(0, 0.5, 45)
	fallbackSpawn.Anchored = true
	fallbackSpawn.Neutral = true
	fallbackSpawn.Duration = 0
	fallbackSpawn.Enabled = false
	fallbackSpawn.Transparency = 1
	fallbackSpawn.CanCollide = false
	fallbackSpawn.Parent = workspace
end

function WorldService:GetSellZone()
	return sellZone
end

-- Верх банка. "Building" может быть и Part, и Model (в своей модели
-- банка) — раньше для Model здесь падало обращение к .Position, а без
-- "Building" возвращалась мировая точка (0, 20, 0): продажа уводила руду в
-- центр карты. Теперь запасной вариант — габариты всей модели банка.
function WorldService:GetBankTopPosition()
	local building = bankModel and bankModel:FindFirstChild("Building", true)
	if building and building:IsA("BasePart") then
		return building.Position + Vector3.new(0, building.Size.Y / 2 + 2, 0)
	elseif building and building:IsA("Model") then
		local cf, size = building:GetBoundingBox()
		return cf.Position + Vector3.new(0, size.Y / 2 + 2, 0)
	elseif bankModel then
		local cf, size = bankModel:GetBoundingBox()
		return cf.Position + Vector3.new(0, size.Y / 2, 0)
	end
	return sellZone and (sellZone.Position + Vector3.new(0, 8, 0)) or Vector3.new(0, 20, 0)
end

local function instancePosition(instance)
	if instance:IsA("BasePart") then
		return instance.Position
	elseif instance:IsA("Model") then
		return instance:GetPivot().Position
	elseif instance:IsA("Attachment") then
		return instance.WorldPosition
	end
	local part = instance:FindFirstChildWhichIsA("BasePart", true)
	return part and part.Position or nil
end

-- КУДА УЛЕТАЕТ ПРОДАННАЯ РУДА — в сам банк. Маркер "SellTarget" в модели
-- банка (необязательный: поставь Part туда, где руда должна исчезать —
-- в окно кассы, в дверь), иначе — середина здания "Building" на уровне
-- чуть ниже крыши, иначе верх банка.
function WorldService:GetBankTargetPosition()
	local marker = bankModel and bankModel:FindFirstChild("SellTarget", true)
	local position = marker and instancePosition(marker)
	if position then return position end
	local building = bankModel and bankModel:FindFirstChild("Building", true)
	if building and building:IsA("BasePart") then
		return building.Position + Vector3.new(0, building.Size.Y * 0.15, 0)
	elseif building and building:IsA("Model") then
		local cf, size = building:GetBoundingBox()
		return cf.Position + Vector3.new(0, size.Y * 0.15, 0)
	end
	-- Нет здания — в середину зоны продажи на высоте человеческого роста:
	-- руда хотя бы летит туда, где игрок её продаёт.
	if sellZone then
		return sellZone.Position + Vector3.new(0, 5, 0)
	end
	return self:GetBankTopPosition()
end

function WorldService:GetBankModel()
	return bankModel
end

return WorldService
