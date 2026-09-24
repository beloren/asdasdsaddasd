--------------------------------------------------------------------------------
-- OrePreviewHud
-- Наведение (ПК) или тап (телефон) на кусок руды, лежащий В ТЕЛЕЖКЕ —
-- своей или чужой, без разницы (например, перед тем как её ограбить) —
-- показывает карточку: тир, цена, мутация (если есть), плюс подсветка
-- самой руды в цвет тира (см. Config.MineTiers[tier].Color).
--
-- Сервер не создаёт ClickDetector на каждую часть руды: клиент сам делает
-- raycast от мыши/тапа. Это сохраняет tap-превью на телефоне и не плодит
-- тысячи интерактивных инстансов при полных тележках на большом сервере.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Config = require(ReplicatedStorage.Shared.Config)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "OrePreviewHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = playerGui

-- Подсветка руды — один переиспользуемый Highlight, Adornee переключается
-- на текущий превьюшный кусок руды (или снимается, когда превью закрыто).
local highlight = Instance.new("Highlight")
highlight.Name = "OrePreviewHighlight"
highlight.FillTransparency = 0.75
highlight.OutlineTransparency = 0
highlight.DepthMode = Enum.HighlightDepthMode.Occluded
highlight.Parent = gui

-- Карточка — тот же чёрный + градиент стиль, что и у превью в книге
-- мутаций, только теперь как BillboardGui над самим куском руды в мире,
-- а не привязанная к 2D-книге.
local billboard = Instance.new("BillboardGui")
billboard.Name = "OrePreviewBillboard"
billboard.Size = UDim2.fromOffset(140, 150)
billboard.StudsOffset = Vector3.new(0, 2.6, 0)
billboard.AlwaysOnTop = true
billboard.Enabled = false
billboard.Parent = gui

local card = Instance.new("Frame")
card.Size = UDim2.fromScale(1, 1)
card.BackgroundTransparency = 1
card.BorderSizePixel = 0
card.Parent = billboard

-- 3D-превью САМОГО ЭТОГО куска руды (с уже применённой мутацией — не
-- перегенерированный заново "усреднённый" тир, а клон реального инстанса,
-- см. showPreview) — тот же приём, что и в книге мутаций, только тут
-- показываем настоящий предмет, а не типовой пример. Вьюпорт занимает
-- почти всю карточку сверху донизу (до цены) — сама руда внутри
-- увеличена (см. радиус камеры в showPreview), чтобы оказаться почти
-- вплотную над ценой. Никакого фона/обводки у самого вьюпорта — чёрная
-- обводка нужна ВОКРУГ РУДЫ, а не вокруг рамки вьюпорта, поэтому она
-- сделана как Highlight на 3D-клоне внутри (см. showPreview), а не UIStroke
-- здесь на 2D-фрейме.
local previewViewport = Instance.new("ViewportFrame")
previewViewport.Name = "Viewport"
previewViewport.Position = UDim2.fromOffset(4, 4)
previewViewport.Size = UDim2.new(1, -8, 1, -8)
previewViewport.BackgroundTransparency = 1
previewViewport.Parent = card
local previewCamera = Instance.new("Camera")
previewCamera.Parent = previewViewport
previewViewport.CurrentCamera = previewCamera

-- Без названия/тира руды — только цена и мутация (если есть), по центру,
-- в нижней части карточки.
local priceLabel = Instance.new("TextLabel")
priceLabel.Name = "Price"
priceLabel.AnchorPoint = Vector2.new(0.5, 1)
priceLabel.Position = UDim2.new(0.5, 0, 1, -30)
priceLabel.Size = UDim2.new(1, -16, 0, 26)
priceLabel.BackgroundTransparency = 1
priceLabel.Font = Enum.Font.Arcade
priceLabel.TextScaled = true
priceLabel.TextXAlignment = Enum.TextXAlignment.Center
priceLabel.TextColor3 = Color3.fromRGB(120, 255, 150)
priceLabel.TextStrokeTransparency = 0
priceLabel.ZIndex = 5
priceLabel.Parent = card

local mutationLabel = Instance.new("TextLabel")
mutationLabel.Name = "Mutation"
mutationLabel.AnchorPoint = Vector2.new(0.5, 1)
mutationLabel.Position = UDim2.new(0.5, 0, 1, -4)
mutationLabel.Size = UDim2.new(1, -16, 0, 24)
mutationLabel.BackgroundTransparency = 1
mutationLabel.Font = Enum.Font.Arcade
mutationLabel.TextScaled = true
mutationLabel.TextXAlignment = Enum.TextXAlignment.Center
mutationLabel.TextColor3 = Color3.fromRGB(230, 230, 235)
mutationLabel.TextStrokeTransparency = 0
mutationLabel.Visible = false
mutationLabel.ZIndex = 5
mutationLabel.Parent = card

-- Кусок руды может быть и обычным Part, и Model (см. CrystalUtil.GetRoot).
-- Сервер больше не ставит ClickDetector на каждую часть: клиент сам делает
-- raycast от мыши/тапа и поднимается по родителям до инстанса с атрибутами.
local function findCrystalFromHit(instance)
	for _ = 1, 10 do
		if not instance then return nil end
		if instance:GetAttribute("CrystalValue") ~= nil then
			return instance
		end
		instance = instance.Parent
	end
	return nil
end

local function findAdornPart(crystalInstance)
	if crystalInstance:IsA("BasePart") then
		return crystalInstance
	end
	return crystalInstance.PrimaryPart or crystalInstance:FindFirstChildWhichIsA("BasePart", true)
end

local currentCrystal = nil
local currentPreviewClone = nil
local previewToken = 0

local function getBounds(instance)
	if instance:IsA("BasePart") then
		return instance.CFrame, instance.Size
	end
	return instance:GetBoundingBox()
end

local function showPreview(crystalInstance)
	local adornPart = crystalInstance and findAdornPart(crystalInstance)
	if not (crystalInstance and adornPart) then return end
	if currentCrystal == crystalInstance and billboard.Enabled then return end

	currentCrystal = crystalInstance
	previewToken += 1
	local token = previewToken

	local isGeode = crystalInstance:GetAttribute("IsGeode") == true
	local geodeType = crystalInstance:GetAttribute("GeodeType")
	local geodeInfo = isGeode and geodeType and Config.Geodes.Types[geodeType]
	local tier = crystalInstance:GetAttribute("CrystalTier") or 1
	local value = crystalInstance:GetAttribute("CrystalValue") or 0
	local mutationsRaw = crystalInstance:GetAttribute("Mutations")
	local tierInfo = Config.MineTiers[tier]
	local tierColor = (geodeInfo and geodeInfo.Color) or (tierInfo and tierInfo.Color) or Color3.fromRGB(255, 220, 90)

	priceLabel.Text = isGeode and (geodeInfo and geodeInfo.DisplayName or geodeType or "GEODE")
		or "$" .. NumberFormat.withSeparators(value)
	priceLabel.TextColor3 = tierColor

	mutationLabel.Visible = false
	if not isGeode and mutationsRaw and mutationsRaw ~= "" then
		local names = {}
		for id in mutationsRaw:gmatch("[^,]+") do
			local info = Config.Mutations[id]
			if info then table.insert(names, info.DisplayName) end
		end
		if #names > 0 then
			mutationLabel.Text = "\u{2728} " .. table.concat(names, " + ")
			mutationLabel.Visible = true
		end
	end

	billboard.Adornee = adornPart
	billboard.Enabled = true
	highlight.Adornee = crystalInstance
	highlight.FillColor = tierColor
	highlight.OutlineColor = tierColor

	-- Клон РЕАЛЬНОГО куска руды (со всеми уже применёнными визуальными
	-- эффектами мутации — не перегенерированный "усреднённый" тир, как в
	-- книге мутаций, а точно этот самый предмет) — во вьюпорт, без физики/
	-- скриптов/детекторов. Уничтожаем только сам клон (не вьюпорт целиком
	-- через ClearAllChildren) — иначе унесло бы и previewCamera с ним.
	if currentPreviewClone then
		currentPreviewClone:Destroy()
		currentPreviewClone = nil
	end
	local clone = crystalInstance:Clone()
	local parts = clone:GetDescendants()
	if clone:IsA("BasePart") then table.insert(parts, clone) end
	for _, descendant in parts do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		elseif descendant:IsA("Weld")
			or descendant:IsA("WeldConstraint")
			or descendant:IsA("BillboardGui")
			or descendant:IsA("Script")
			or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
	clone:PivotTo(CFrame.new(0, 0, 0))
	clone.Parent = previewViewport
	currentPreviewClone = clone

	-- Чёрная обводка ВОКРУГ САМОЙ РУДЫ (3D-модели внутри вьюпорта), а не
	-- вокруг рамки вьюпорта — обычный UIStroke тут не подходит (это 2D-
	-- эффект для GuiObject), нужен именно Highlight на 3D-объекте.
	-- Парентим внутрь клона — уничтожается вместе с ним автоматически.
	local outlineHighlight = Instance.new("Highlight")
	outlineHighlight.Name = "OutlineHighlight"
	outlineHighlight.FillTransparency = 1 -- никакой заливки — только контур
	outlineHighlight.OutlineTransparency = 0
	outlineHighlight.OutlineColor = Color3.new(0, 0, 0)
	outlineHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	outlineHighlight.Adornee = clone
	outlineHighlight.Parent = clone

	local _, boundsSize = getBounds(clone)
	local radius = math.max(boundsSize.X, boundsSize.Y, boundsSize.Z) * 0.85 + 0.6 -- было *1.15+1.2 — камера ближе, руда крупнее в кадре
	previewCamera.CFrame = CFrame.new(Vector3.new(radius * 0.7, radius * 0.5, radius * 0.7), Vector3.new(0, 0, 0))

	task.spawn(function()
		local start = os.clock()
		while previewToken == token and clone.Parent do
			clone:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, (os.clock() - start) * 0.8, 0))
			task.wait(0.03)
		end
	end)
end

local function hidePreview(crystalInstance)
	if crystalInstance and currentCrystal ~= crystalInstance then return end
	currentCrystal = nil
	previewToken += 1
	billboard.Enabled = false
	highlight.Adornee = nil
	if currentPreviewClone then
		currentPreviewClone:Destroy()
		currentPreviewClone = nil
	end
end

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = true

local function raycastCrystal(screenPosition)
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	local ray = camera:ViewportPointToRay(screenPosition.X, screenPosition.Y)
	local character = Players.LocalPlayer.Character
	raycastParams.FilterDescendantsInstances = character and { character } or {}
	local result = workspace:Raycast(ray.Origin, ray.Direction * 500, raycastParams)
	local crystal = result and findCrystalFromHit(result.Instance) or nil
	if not crystal then return nil end
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local adornPart = findAdornPart(crystal)
	if root and adornPart and (root.Position - adornPart.Position).Magnitude > (Config.Cart.OrePreviewMaxDistance or 24) then
		return nil
	end
	return crystal
end

RunService.RenderStepped:Connect(function()
	if not UserInputService.MouseEnabled then return end
	local mouseLocation = UserInputService:GetMouseLocation()
	local crystal = raycastCrystal(mouseLocation)
	if crystal then
		showPreview(crystal)
	elseif currentCrystal then
		hidePreview()
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.Touch then return end
	local crystal = raycastCrystal(input.Position)
	if crystal then
		if currentCrystal == crystal and billboard.Enabled then
			hidePreview(crystal)
		else
			showPreview(crystal)
		end
	elseif currentCrystal then
		hidePreview()
	end
end)
