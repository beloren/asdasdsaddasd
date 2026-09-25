--------------------------------------------------------------------------------
-- PlacementGhost (LocalScript) — УСТАНОВКА ТОТЕМОВ/ДЕКОРА/РЕЛИКВИЙ ИЗ РУКИ (v14.1).
--
-- Взял предмет из инвентаря/хотбара (атрибут HeldGear = "Totem_…",
-- "Decor_…" или "Relic:…") — за курсором (на телефоне за касанием) ездит
-- полупрозрачный призрак. Зелёный — можно, красный — нельзя (только земля
-- своего участка, любая поверхность, смотрящая вверх — shared/GroundCheck,
-- та же проверка, что на сервере).
--   ПК:      ЛКМ — поставить, R — повернуть.
--   Телефон: тап — куда, кнопки ↻ и ✔.
-- Убрать из руки — тем же слотом хотбара, как любое снаряжение.
-- v20.9: сундуки (HeldGear = "Chest_…") тоже с призраком: стоят на полу
-- участка, по умолчанию смотрят на игрока, R — повернуть.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Localization = require(ReplicatedStorage.Shared.Localization)
local PlaceableFactory = require(ReplicatedStorage.Shared.PlaceableFactory)
local PlaceableCatalog = require(ReplicatedStorage.Shared.PlaceableCatalog)
local GroundCheck = require(ReplicatedStorage.Shared.GroundCheck)

local CFG = Config.Placeables
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage.Shared:WaitForChild("GearRequest", 30)
if not remote then return end

local function tr(text)
	local ok, result = pcall(Localization.Translate, player.LocaleId, text)
	return ok and result or text
end

local function isChest(key)
	local rarity = typeof(key) == "string" and key:match("^Chest_(%a+)$")
	return rarity ~= nil and Config.Chests and Config.Chests.Types[rarity] ~= nil
end

local function isPlaceable(key)
	return typeof(key) == "string" and (PlaceableCatalog.Info(key) ~= nil or key:match("^Relic:") ~= nil or isChest(key))
end

--------------------------------------------------------------------------------
-- UI: подсказка + кнопки для телефона
--------------------------------------------------------------------------------
-- v20: вид — Shared.UiBuilders.PlacementUi (StarterGui/PlacementUi → GhostHud).
local placementUi = require(ReplicatedStorage.Shared.UiRegistry).Get("PlacementUi")
local ghostHud = placementUi:WaitForChild("GhostHud")
local hintPill = ghostHud:WaitForChild("Hint")
local hint = hintPill:WaitForChild("Text")
-- v20.24: верхняя плашка-подсказка скрыта — то же самое уже пишет подсказка
-- предмета над хотбаром (GearUi/AimHint). Плашка всплывает только на ошибку.
hintPill.Visible = false
local hintToken = 0
local function flashHint(text)
	hintToken += 1
	local token = hintToken
	hint.Text = text
	hintPill.Visible = true
	task.delay(1.5, function()
		if hintToken == token then hintPill.Visible = false end
	end)
end
local mobileBar = ghostHud:WaitForChild("MobileBar")
local rotateButton = mobileBar:WaitForChild("Rotate")
local placeButton = mobileBar:WaitForChild("Place")

--------------------------------------------------------------------------------
-- ПРИЗРАК
--------------------------------------------------------------------------------
local ghost, highlight = nil, nil
local ghostKey = nil
local yaw = 0
local valid = false
local targetCFrame = nil
local lastTouch = nil
local cachedPad = nil

local function myPad()
	if cachedPad and cachedPad.Parent and cachedPad:GetAttribute("OwnerUserId") == player.UserId then return cachedPad end
	cachedPad = nil
	for _, instance in workspace:GetDescendants() do
		if instance:IsA("BasePart") and instance:GetAttribute("OwnerUserId") == player.UserId
			and instance.Size.X > 20 and instance.Size.Z > 20
		then
			cachedPad = instance
			break
		end
	end
	return cachedPad
end

local function destroyGhost()
	if ghost then ghost:Destroy() end
	ghost, highlight, ghostKey, targetCFrame = nil, nil, nil, nil
	ghostHud.Visible = false
end

local function buildGhost(key)
	destroyGhost()
	local model
	if isChest(key) then
		model = PlaceableFactory.BuildChest((key:gsub("^Chest_", "")))
	elseif key:match("^Relic:") then
		local relicId = key:match("^Relic:([%w]+):")
		model = relicId and PlaceableFactory.BuildRelic(relicId)
	else
		model = PlaceableFactory.BuildItem(key)
	end
	if not model then return end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanQuery = false
			d.CanCollide = false
			d.CanTouch = false
			d.CastShadow = false
			d.Transparency = math.max(d.Transparency, 0.45)
		elseif d:IsA("ProximityPrompt") or d:IsA("BillboardGui") then
			d:Destroy()
		end
	end
	highlight = Instance.new("Highlight")
	highlight.FillTransparency = 0.6
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = model
	model.Parent = workspace.CurrentCamera
	ghost, ghostKey = model, key
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	mobileBar.Visible = touchOnly
	hintPill.Visible = false
	yaw = 0
	ghostHud.Visible = true
end

local function snap(value)
	local step = CFG.GridStep or 0.5
	return math.floor(value / step + 0.5) * step
end

local function ignoreList()
	local list = { ghost, workspace:FindFirstChild("MineGroundOre") }
	for _, other in Players:GetPlayers() do
		if other.Character then table.insert(list, other.Character) end
	end
	return list
end

RunService.RenderStepped:Connect(function()
	if not ghost then return end
	local camera = workspace.CurrentCamera
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (camera and hrp) then return end
	local screenPoint
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		screenPoint = lastTouch or Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y * 0.6)
	else
		screenPoint = UserInputService:GetMouseLocation()
	end
	local ray = camera:ViewportPointToRay(screenPoint.X, screenPoint.Y)
	local ignore = ignoreList()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 250, params)
	if not hit then return end
	-- v14.4: ЛЮБАЯ ПОВЕРХНОСТЬ. Пологая — стоим вертикально по сетке;
	-- стена/крутой склон — прилипаем по нормали (без сетки).
	local normal = hit.Normal
	local position = hit.Position
	if GroundCheck.IsUpright(normal) then
		position = Vector3.new(snap(position.X), position.Y, snap(position.Z))
	end
	local pad = myPad()
	local onSurface, surfacePosition, surfaceNormal = GroundCheck.Surface(position, normal, ignore)
	if onSurface then
		position, normal = surfacePosition, surfaceNormal
	end
	if isChest(ghostKey) then
		-- Сундук: как на сервере (GearService:_placeChest) — на полу участка,
		-- лицом к игроку (+ поворот R), не ближе 2 стадов к краю, до 30 стадов.
		local ok = false
		local cf
		if pad then
			local flat = Vector3.new(hit.Position.X, 0, hit.Position.Z)
			local look = Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - flat
			local facing = look.Magnitude > 0.1 and CFrame.lookAt(Vector3.zero, look) or CFrame.new()
			local rotation = facing * CFrame.Angles(0, math.rad(yaw), 0)
			local _, size = ghost:GetBoundingBox()
			local floorY = pad.Position.Y + pad.Size.Y / 2
			ghost:PivotTo(CFrame.new(hit.Position.X, floorY + size.Y / 2, hit.Position.Z) * rotation)
			cf = CFrame.new(hit.Position.X, floorY, hit.Position.Z) * rotation
			local localPoint = pad.CFrame:PointToObjectSpace(hit.Position)
			ok = math.abs(localPoint.X) <= pad.Size.X / 2 - 2 and math.abs(localPoint.Z) <= pad.Size.Z / 2 - 2
				and (hrp.Position - hit.Position).Magnitude <= 30
		end
		targetCFrame = cf
		valid = ok
		local color = ok and Color3.fromRGB(80, 255, 120) or Color3.fromRGB(255, 70, 70)
		highlight.FillColor = color
		highlight.OutlineColor = color
		return
	end
	local cf = CFrame.new(position) * GroundCheck.Orientation(normal, yaw)
	ghost:PivotTo(cf)
	targetCFrame = cf
	local ok = onSurface and pad ~= nil and (hrp.Position - position).Magnitude <= (CFG.PlaceRange or 60)
		and GroundCheck.InPlot(pad, position)
	valid = ok
	local color = ok and Color3.fromRGB(80, 255, 120) or Color3.fromRGB(255, 70, 70)
	highlight.FillColor = color
	highlight.OutlineColor = color
end)

local function confirm()
	if not (ghost and targetCFrame) then return end
	if not valid then
		flashHint(tr("Only inside your own base!"))
		return
	end
	remote:FireServer("Use", nil, targetCFrame)
end

local function rotate()
	yaw = (yaw + (CFG.RotateStep or 45)) % 360
end

rotateButton.Activated:Connect(rotate)
placeButton.Activated:Connect(confirm)

UserInputService.InputBegan:Connect(function(input, processed)
	if not ghost then return end
	if input.UserInputType == Enum.UserInputType.Touch then
		if not processed then lastTouch = Vector2.new(input.Position.X, input.Position.Y) end
		return
	end
	if processed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		confirm()
	elseif input.KeyCode == Enum.KeyCode.R then
		rotate()
	end
end)
UserInputService.InputChanged:Connect(function(input, processed)
	if ghost and input.UserInputType == Enum.UserInputType.Touch and not processed then
		lastTouch = Vector2.new(input.Position.X, input.Position.Y)
	end
end)

local function refresh()
	local key = player:GetAttribute("HeldGear") or ""
	if isPlaceable(key) then
		if key ~= ghostKey then buildGhost(key) end
	else
		destroyGhost()
	end
end
player:GetAttributeChangedSignal("HeldGear"):Connect(refresh)
player.CharacterRemoving:Connect(destroyGhost)
refresh()
