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

local function isPlaceable(key)
	return typeof(key) == "string" and (PlaceableCatalog.Info(key) ~= nil or key:match("^Relic:") ~= nil)
end

--------------------------------------------------------------------------------
-- UI: подсказка + кнопки для телефона
--------------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "PlacementGhostUi"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 26
gui.Enabled = false
gui.Parent = playerGui

local hint = Instance.new("TextLabel")
hint.AnchorPoint = Vector2.new(0.5, 0)
hint.Position = UDim2.new(0.5, 0, 0, 70)
hint.Size = UDim2.fromOffset(640, 30)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.FredokaOne
hint.TextScaled = true
hint.TextColor3 = Color3.fromRGB(255, 240, 180)
hint.Parent = gui
Instance.new("UIStroke", hint).Thickness = 2

local mobileBar = Instance.new("Frame")
mobileBar.AnchorPoint = Vector2.new(1, 1)
mobileBar.Position = UDim2.new(1, -20, 1, -150)
mobileBar.Size = UDim2.fromOffset(200, 64)
mobileBar.BackgroundTransparency = 1
mobileBar.Parent = gui
local barLayout = Instance.new("UIListLayout")
barLayout.FillDirection = Enum.FillDirection.Horizontal
barLayout.Padding = UDim.new(0, 10)
barLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
barLayout.Parent = mobileBar

local function roundButton(text, color)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(62, 62)
	b.BackgroundColor3 = color
	b.Text = text
	b.TextScaled = true
	b.Font = Enum.Font.FredokaOne
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Parent = mobileBar
	Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
	local s = Instance.new("UIStroke")
	s.Thickness = 3
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = b
	return b
end
local rotateButton = roundButton("↻", Color3.fromRGB(60, 130, 230))
local placeButton = roundButton("✔", Color3.fromRGB(60, 190, 80))

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
	gui.Enabled = false
end

local function buildGhost(key)
	destroyGhost()
	local model
	if key:match("^Relic:") then
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
	hint.Text = touchOnly and tr("Tap a spot on your base, then ✔") or tr("Click a spot on your base to place • R rotate")
	gui.Enabled = true
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
		hint.Text = tr("Only inside your own base!")
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
