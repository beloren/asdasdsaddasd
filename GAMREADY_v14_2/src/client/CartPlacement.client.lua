--------------------------------------------------------------------------------
-- CartPlacement (LocalScript) — ЗЕЛЁНЫЙ/КРАСНЫЙ ПРЕДПРОСМОТР ПОСТАНОВКИ
-- ТЕЛЕЖКИ ИЗ УПАКОВКИ (v12).
--
-- Включается САМ, как только игрок берёт упаковку в руки: сервер ставит на
-- него атрибут HeldCartPackage (см. GearService:Equip), клиент это видит и
-- начинает рисовать призрак тележки там, куда игрок целится.
--
-- ЧТО ЗДЕСЬ ЕСТЬ И ЧЕГО ЗДЕСЬ НЕТ.
--   • ЕСТЬ: призрак (полупрозрачная копия настоящей модели Cart_TierN),
--     подсветка зелёным/красным, подпись-причина отказа, клик/тап =
--     отправить точку на сервер.
--   • НЕТ: никакой власти над игрой. Клиент НЕ создаёт тележку и не решает,
--     можно ли поставить — он присылает серверу ТОЛЬКО точку прицела, а тот
--     проверяет всё заново тем же самым общим модулем (Shared.CartPlacement),
--     которым посчитано превью. Поэтому \"зелёное\" у игрока и \"можно\" у
--     сервера — это буквально один и тот же код, но подделать постановку
--     нельзя.
--
-- ЛИЦОМ К ИГРОКУ. Призрак каждый кадр разворачивается передом к персонажу
-- (CartPlacement.PlacementCFrame) — то есть игрок заранее видит не абстрактный
-- прямоугольник, а тележку ровно в той позе, в которой она встанет, и может
-- обойти место кругом, чтобы выбрать сторону.
--
-- ПРИЗРАК — ЭТО НАСТОЯЩАЯ МОДЕЛЬ. Не коробка-заглушка: клонируется тот же
-- Cart_TierN, который построит сервер (через PlaceholderFactory), со снятой
-- физикой, лучами и интерфейсами. Любая кастомная модель, положенная в
-- Assets, появится в превью сама, без правок кода.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)
local CartPlacement = require(ReplicatedStorage.Shared.CartPlacement)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local placeRemote = ReplicatedStorage.Shared:WaitForChild("PlaceCartRequest", 30)
if not placeRemote then
	warn("[CartPlacement] PlaceCartRequest не появился - постановка тележки отключена на клиенте.")
	return
end

local settings = Config.CartPackage or {}

--------------------------------------------------------------------------------
-- ПОДСКАЗКА НА ЭКРАНЕ
--
-- Одна строка внизу: \"PLACE YOUR CART\" зелёным или причина отказа красным.
-- Отдельный ScreenGui с низким DisplayOrder — чтобы не перехватывать нажатия
-- у магазина/инвентаря (Frame и TextLabel кликов не ловят, но слой всё равно
-- держим ниже панелей).
--------------------------------------------------------------------------------
-- v20: вид — Shared.UiBuilders.PlacementUi (StarterGui/PlacementUi → CartHud).
local placementUi = require(ReplicatedStorage.Shared.UiRegistry).Get("PlacementUi")
local cartHud = placementUi:WaitForChild("CartHud")
local hintPlate = cartHud:WaitForChild("Hint")
local hint = hintPlate:WaitForChild("Text")

--------------------------------------------------------------------------------
-- ПРИЗРАК
--------------------------------------------------------------------------------
local ghost = nil        -- Model
local ghostRoot = nil    -- BasePart
local ghostTier = nil    -- для какого тира построен (пересобираем при апгрейде)
local ghostHighlight = nil
local lastValidCFrame = nil
local lastOk = false

local function destroyGhost()
	if ghost then ghost:Destroy() end
	ghost, ghostRoot, ghostTier, ghostHighlight = nil, nil, nil, nil
	lastValidCFrame, lastOk = nil, false
end

local function buildGhost(tier)
	destroyGhost()
	local ok, model = pcall(PlaceholderFactory.Cart, tier)
	if not ok or not model then return false end
	local root = model:FindFirstChild("Root") or model.PrimaryPart
	if not root then
		model:Destroy()
		return false
	end
	model.PrimaryPart = root
	model.Name = "CartPlacementGhost"

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			-- Призрак не участвует ни в физике, ни в лучах: иначе он ловил
			-- бы собственный прицельный рейкаст и всегда мешал бы сам себе.
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
			descendant.Transparency = math.clamp(tonumber(settings.PreviewTransparency) or 0.55, 0, 1)
			descendant.CastShadow = false
		elseif descendant:IsA("BillboardGui") or descendant:IsA("SurfaceGui")
			or descendant:IsA("ProximityPrompt") or descendant:IsA("Script")
			or descendant:IsA("LocalScript") or descendant:IsA("ParticleEmitter") then
			-- Ценник, комбо, промпт \"GRAB CART\" и пыль спринта у призрака
			-- не нужны — он не тележка, он намерение.
			descendant:Destroy()
		end
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "PlacementHighlight"
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillTransparency = math.clamp(tonumber(settings.PreviewFillTransparency) or 0.7, 0, 1)
	highlight.OutlineTransparency = 0
	highlight.Adornee = model
	highlight.Parent = model

	model.Parent = workspace
	ghost, ghostRoot, ghostHighlight, ghostTier = model, root, highlight, tier
	return true
end

local function paintGhost(ok)
	if not ghostHighlight then return end
	local color = ok and (settings.PreviewOkColor or Color3.fromRGB(70, 255, 120))
		or (settings.PreviewBadColor or Color3.fromRGB(255, 70, 70))
	ghostHighlight.FillColor = color
	ghostHighlight.OutlineColor = color
end

--------------------------------------------------------------------------------
-- СОСТОЯНИЕ
--------------------------------------------------------------------------------
local function heldPackageTier()
	local tier = tonumber(player:GetAttribute("HeldCartPackage"))
	if not tier or tier < 1 then return nil end
	return math.floor(tier)
end

-- Куда целится игрок. На мыши — положение курсора, на тапе — центр экрана
-- (пальцем игрок уже водит камерой, отдельного курсора у него нет).
local function aimScreenPoint()
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	if UserInputService.MouseEnabled then
		local mouse = UserInputService:GetMouseLocation()
		return Vector2.new(mouse.X, mouse.Y)
	end
	return camera.ViewportSize * 0.5
end

local function ignoreList()
	local list = { ghost }
	for _, plr in Players:GetPlayers() do
		if plr.Character then table.insert(list, plr.Character) end
	end
	-- Собственная упаковка над головой — тоже не препятствие.
	local carried = workspace:FindFirstChild("HeldCartPackageVisual_" .. player.UserId)
	if carried then table.insert(list, carried) end
	return list
end

RunService.RenderStepped:Connect(function()
	local tier = heldPackageTier()
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if not (tier and hrp and humanoid and humanoid.Health > 0) then
		if ghost then destroyGhost() end
		if cartHud.Visible then cartHud.Visible = false end
		return
	end

	-- Тир поменялся (купил апгрейд, пока держал упаковку) — пересобираем
	-- призрак, чтобы он показывал ту тележку, которая реально встанет.
	if not ghost or ghostTier ~= tier then
		if not buildGhost(tier) then return end
	end

	local screenPoint = aimScreenPoint()
	if not screenPoint then return end
	local aim = CartPlacement.AimPoint(workspace.CurrentCamera, screenPoint, ignoreList())
	if not aim then return end

	local ok, reason, placement = CartPlacement.Validate({
		Position = aim,
		PlayerPosition = hrp.Position,
		Model = ghost,
		Root = ghostRoot,
		Pad = nil, -- участок проверяет сервер; на клиенте его границ может не быть
		IgnoreList = ignoreList(),
	})

	lastOk = ok
	lastValidCFrame = placement

	if placement then
		ghost:PivotTo(placement)
	else
		-- Места нет (бездна, слишком далеко, стена) — призрак всё равно
		-- показываем красным, чтобы игрок видел, ЧТО он ставит и куда
		-- целится. Приподнимаем на половину корпуса, иначе красная тележка
		-- наполовину утоплена в геометрию и читается плохо.
		local _, rootToBottom = CartPlacement.MeasureModel(ghost, ghostRoot)
		local fallbackFacing = CartPlacement.PlacementCFrame(
			aim + Vector3.new(0, rootToBottom, 0),
			hrp.Position,
			CartPlacement.FacingAngle(ghost, ghostRoot)
		)
		ghost:PivotTo(fallbackFacing)
	end
	paintGhost(ok)

	cartHud.Visible = true
	hint.Text = ok and "TAP TO PLACE YOUR CART" or string.upper(reason or "CAN'T PLACE HERE")
	hint.TextColor3 = ok and (settings.PreviewOkColor or Color3.fromRGB(70, 255, 120))
		or (settings.PreviewBadColor or Color3.fromRGB(255, 70, 70))
	local hintStroke = hintPlate:FindFirstChild("SkinStroke")
	if hintStroke then hintStroke.Color = hint.TextColor3 end
end)

--------------------------------------------------------------------------------
-- ВВОД
--
-- processed — нажатие уже съел интерфейс (кнопка магазина, слот инвентаря):
-- ставить по нему тележку нельзя, иначе любой клик по UI с упаковкой в руках
-- ронял бы тележку за спиной.
--------------------------------------------------------------------------------
local function tryPlace()
	if not heldPackageTier() then return end
	if not (lastOk and lastValidCFrame) then return end
	-- Серверу уходит ТОЛЬКО точка: всё остальное (поворот, посадка на землю,
	-- проверки) он считает сам — см. CartService:PlaceCartFromPackage.
	placeRemote:FireServer(lastValidCFrame.Position)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		tryPlace()
	end
end)

player.CharacterRemoving:Connect(destroyGhost)
