--------------------------------------------------------------------------------
-- LoadingScreen (ReplicatedFirst) v20.120 — ЗАГРУЗОЧНЫЙ ЭКРАН ПЕРЕД КАТСЦЕНОЙ.
--
-- v20.121: КОРОТКАЯ загрузка - только то, что нужно катсцене (риг камеры,
-- сцена, логотип), до Config.Loading.CutsceneWaitSeconds; есть SKIP. Потом
-- AssetsLoaded → катсцена, а всё остальное (Assets, анимации, картинки,
-- декали, VFX, звуки, мир, айди из Config) грузится ПАРАЛЛЕЛЬНО с ней.
--
-- Отказоустойчивость: любая ошибка логируется, AssetsLoaded выставляется
-- всё равно, общий потолок - Config.Loading.MaxSeconds (по умолчанию 60).
--------------------------------------------------------------------------------
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
for _, child in playerGui:GetChildren() do
	if child.Name == "PreloadScreen" or child.Name == "LoadingScreen" then child:Destroy() end
end

--------------------------------------------------------------------------------
-- ЭКРАН
--------------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LoadingScreen"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 1000
screenGui.ScreenInsets = Enum.ScreenInsets.None
screenGui.ClipToDeviceSafeArea = false
screenGui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.FullscreenExtension
screenGui.Parent = playerGui

local staleScreenConnection = playerGui.ChildAdded:Connect(function(child)
	if child ~= screenGui and (child.Name == "PreloadScreen" or child.Name == "LoadingScreen") then child:Destroy() end
end)

local background = Instance.new("CanvasGroup")
background.Name = "Background"
background.AnchorPoint = Vector2.new(0.5, 0.5)
background.Position = UDim2.fromScale(0.5, 0.5)
background.Size = UDim2.new(1, 400, 1, 400)
background.BackgroundColor3 = Color3.fromRGB(10, 8, 18)
background.BorderSizePixel = 0
background.Parent = screenGui

local gradient = Instance.new("UIGradient")
gradient.Rotation = 90
gradient.Color = ColorSequence.new(Color3.fromRGB(30, 22, 52), Color3.fromRGB(6, 5, 12))
gradient.Parent = background

local center = Instance.new("Frame")
center.Name = "Center"
center.AnchorPoint = Vector2.new(0.5, 0.5)
center.Position = UDim2.fromScale(0.5, 0.5)
center.Size = UDim2.fromOffset(460, 220)
center.BackgroundTransparency = 1
center.Parent = background
local centerLimit = Instance.new("UISizeConstraint")
centerLimit.MaxSize = Vector2.new(460, 220)
centerLimit.Parent = center
local centerScale = Instance.new("UIScale")
centerScale.Parent = center

local logo = Instance.new("ImageLabel")
logo.Name = "Logo"
logo.AnchorPoint = Vector2.new(0.5, 0)
logo.Position = UDim2.fromScale(0.5, 0)
logo.Size = UDim2.fromOffset(110, 110)
logo.BackgroundTransparency = 1
logo.ScaleType = Enum.ScaleType.Fit
logo.Parent = center

local title = Instance.new("TextLabel")
title.Name = "Title"
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.new(0.5, 0, 0, 116)
title.Size = UDim2.new(1, 0, 0, 34)
title.BackgroundTransparency = 1
title.Font = Enum.Font.FredokaOne
title.TextScaled = true
title.TextColor3 = Color3.new(1, 1, 1)
title.Text = "LOADING..."
title.Parent = center
local titleStroke = Instance.new("UIStroke")
titleStroke.Thickness = 3
titleStroke.Color = Color3.fromRGB(20, 10, 30)
titleStroke.Parent = title

local barBack = Instance.new("Frame")
barBack.Name = "Bar"
barBack.AnchorPoint = Vector2.new(0.5, 0)
barBack.Position = UDim2.new(0.5, 0, 0, 160)
barBack.Size = UDim2.new(1, -20, 0, 26)
barBack.BackgroundColor3 = Color3.fromRGB(30, 26, 44)
barBack.BorderSizePixel = 0
barBack.Parent = center
Instance.new("UICorner", barBack).CornerRadius = UDim.new(1, 0)
local barStroke = Instance.new("UIStroke")
barStroke.Thickness = 3
barStroke.Color = Color3.fromRGB(10, 8, 18)
barStroke.Parent = barBack
local barFill = Instance.new("Frame")
barFill.Name = "Fill"
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = Color3.fromRGB(255, 205, 70)
barFill.BorderSizePixel = 0
barFill.Parent = barBack
Instance.new("UICorner", barFill).CornerRadius = UDim.new(1, 0)
local fillGradient = Instance.new("UIGradient")
fillGradient.Rotation = 90
fillGradient.Color = ColorSequence.new(Color3.fromRGB(255, 235, 140), Color3.fromRGB(255, 160, 40))
fillGradient.Parent = barFill

local percent = Instance.new("TextLabel")
percent.Name = "Percent"
percent.AnchorPoint = Vector2.new(0.5, 0)
percent.Position = UDim2.new(0.5, 0, 0, 192)
percent.Size = UDim2.new(1, 0, 0, 24)
percent.BackgroundTransparency = 1
percent.Font = Enum.Font.GothamBold
percent.TextScaled = true
percent.TextColor3 = Color3.fromRGB(200, 190, 230)
percent.Text = "0%"
percent.Parent = center

local function fitScale()
	local camera = workspace.CurrentCamera
	local view = camera and camera.ViewportSize or Vector2.new(1280, 720)
	centerScale.Scale = math.clamp(math.min(view.X / 520, view.Y / 320), 0.55, 1.2)
end
fitScale()

local shown, target = 0, 0
local stage = "LOADING..."
local renderConnection = RunService.RenderStepped:Connect(function(dt)
	shown += (target - shown) * math.min(1, dt * 6)
	barFill.Size = UDim2.fromScale(math.clamp(shown, 0, 1), 1)
	percent.Text = ("%d%%"):format(math.floor(math.clamp(shown, 0, 1) * 100 + 0.5))
	local dots = string.rep(".", math.floor(os.clock() * 2) % 4)
	title.Text = stage .. dots
	logo.Rotation = math.sin(os.clock() * 2) * 4
	fitScale()
end)

--------------------------------------------------------------------------------
-- ЧТО ГРУЗИМ
--------------------------------------------------------------------------------
local CONTENT_CLASSES = {
	Decal = true, Texture = true, MeshPart = true, SpecialMesh = true, Sound = true, Animation = true,
	ImageLabel = true, ImageButton = true, ParticleEmitter = true, Beam = true, Trail = true,
	SurfaceAppearance = true, Sky = true, ShirtGraphic = true, Shirt = true, Pants = true,
	FileMesh = true, CharacterMesh = true, VideoFrame = true,
}

local RAW_ID_KEY_SUFFIXES = { "ImageId", "IconId", "TextureId", "MeshId", "SoundId", "AnimationId", "Image", "Icon" }
local RAW_ID_PARENT_TABLES = { Icons = true, CoverIcons = true, Images = true, NpcIdleAnimations = true }

local function isRawAssetIdKey(key, parentKey)
	if parentKey and RAW_ID_PARENT_TABLES[parentKey] then return true end
	if typeof(key) ~= "string" then return false end
	for _, suffix in RAW_ID_KEY_SUFFIXES do
		if key:sub(-#suffix) == suffix then return true end
	end
	return false
end

local function collectConfigAssetIds(source, results, seen, parentKey, animations)
	if typeof(source) ~= "table" or seen[source] then return end
	seen[source] = true
	for key, value in source do
		local keyName = typeof(key) == "string" and key or nil
		local isAnim = (keyName and keyName:find("Animation")) or parentKey == "NpcIdleAnimations"
		local id = nil
		if typeof(value) == "string" and value:match("^rbxassetid://%d+$") and value ~= "rbxassetid://0" then
			id = value
		elseif typeof(value) == "number" and value > 0 and value == math.floor(value) and isRawAssetIdKey(key, parentKey) then
			id = "rbxassetid://" .. tostring(value)
		elseif typeof(value) == "table" then
			collectConfigAssetIds(value, results, seen, keyName or parentKey, animations)
		end
		if id then
			if isAnim then
				-- анимации грузим как Animation (иначе ключевые кадры не подтянутся)
				local animation = Instance.new("Animation")
				animation.AnimationId = id
				table.insert(animations, animation)
				table.insert(results, animation)
			else
				table.insert(results, id)
			end
		end
	end
end

local function collect(root, list, seen)
	if not root then return end
	for _, d in root:GetDescendants() do
		if CONTENT_CLASSES[d.ClassName] and not seen[d] then
			seen[d] = true
			table.insert(list, d)
		end
	end
end

local function finalize()
	pcall(function() player:SetAttribute("AssetsLoaded", true) end)
end

local function closeScreen()
	local fade = TweenService:Create(background, TweenInfo.new(0.6), { GroupTransparency = 1 })
	fade:Play()
	fade.Completed:Wait()
	pcall(function() renderConnection:Disconnect() end)
	pcall(function() staleScreenConnection:Disconnect() end)
	screenGui:Destroy()
end

-- v20.121: SKIP на загрузке - сразу к катсцене (догрузится по ходу).
local skipButton = Instance.new("TextButton")
skipButton.Name = "Skip"
skipButton.AnchorPoint = Vector2.new(1, 1)
skipButton.Position = UDim2.new(1, -24, 1, -24)
skipButton.Size = UDim2.fromOffset(120, 44)
skipButton.BackgroundTransparency = 1
skipButton.Font = Enum.Font.GothamBold
skipButton.TextScaled = true
skipButton.TextColor3 = Color3.new(1, 1, 1)
skipButton.TextStrokeTransparency = 0
skipButton.Text = "SKIP"
skipButton.Visible = false
skipButton.ZIndex = 5
skipButton.Parent = screenGui
local skipped = false
skipButton.MouseButton1Click:Connect(function() skipped = true end)

local function backgroundPreload(Config)
	-- всё остальное - параллельно с катсценой, без экрана
	task.spawn(function()
		local list, seen, animations = {}, {}, {}
		collect(ReplicatedStorage, list, seen)
		collect(workspace, list, seen)
		collect(playerGui, list, seen)
		collect(game:GetService("StarterGui"), list, seen)
		collect(game:GetService("SoundService"), list, seen)
		collect(game:GetService("Lighting"), list, seen)
		if Config then pcall(collectConfigAssetIds, Config, list, {}, nil, animations) end
		for index = 1, #list, 60 do
			local batch = table.move(list, index, math.min(index + 59, #list), 1, {})
			pcall(ContentProvider.PreloadAsync, ContentProvider, batch)
			task.wait(0.03)
		end
		for _, animation in animations do animation:Destroy() end
	end)
end

task.spawn(function()
	local ok, err = xpcall(function()
		if not game:IsLoaded() then game.Loaded:Wait() end
		local configModule = ReplicatedStorage:WaitForChild("Shared", 20)
		configModule = configModule and configModule:WaitForChild("Config", 20)
		local okConfig, Config = false, nil
		if configModule then okConfig, Config = pcall(require, configModule) end
		local loading = (okConfig and typeof(Config) == "table" and Config.Loading) or {}
		local logoId = tonumber(loading.LogoImageId) or 113042882863397
		if logoId > 0 then logo.Image = "rbxassetid://" .. logoId end
		task.delay(tonumber(loading.SkipAfterSeconds) or 2, function() skipButton.Visible = true end)

		-- 1) КОРОТКО: только то, что нужно катсцене - риг камеры и сцена
		stage = "LOADING"
		local waitMax = tonumber(loading.CutsceneWaitSeconds) or 8
		local started = os.clock()
		local rig, saves
		while os.clock() - started < waitMax and not skipped do
			rig = workspace:FindFirstChild("HumanoidCameraRig")
			saves = ReplicatedStorage:FindFirstChild("MoonAnimator2Saves")
			if rig and rig:FindFirstChild("Torso") and saves and saves:FindFirstChild("scene") then break end
			target = math.min(0.5, (os.clock() - started) / waitMax * 0.5)
			task.wait(0.1)
		end
		target = 0.55
		if not skipped then
			local list, seen = {}, {}
			if rig then collect(rig, list, seen) end
			if saves then collect(saves, list, seen) end
			table.insert(list, logo)
			local total, done = math.max(1, #list), 0
			for index = 1, #list, 30 do
				if skipped then break end
				local batch = table.move(list, index, math.min(index + 29, #list), 1, {})
				pcall(ContentProvider.PreloadAsync, ContentProvider, batch)
				done += #batch
				target = 0.55 + 0.45 * done / total
			end
		end
		target = 1
		task.wait(0.2)

		-- 2) катсцена стартует, остальное грузится параллельно
		player:SetAttribute("AssetsLoaded", true)
		backgroundPreload(okConfig and Config or nil)
		skipButton.Visible = false
		local waitStart = os.clock()
		while player:GetAttribute("CutsceneStarted") ~= true
			and player:GetAttribute("IntroFailed") ~= true
			and os.clock() - waitStart < 25 do
			task.wait(0.05)
		end
		closeScreen()
	end, debug.traceback)
	if not ok then
		warn("[LoadingScreen] Загрузочный экран упал; продолжаю запуск игры:\n" .. tostring(err))
		finalize()
		pcall(function() renderConnection:Disconnect() end)
		pcall(function() staleScreenConnection:Disconnect() end)
		pcall(function() screenGui:Destroy() end)
	end
end)

-- Страховка: что бы ни случилось, флаг выставится и экран уйдёт.
task.delay(40, function()
	if player:GetAttribute("AssetsLoaded") ~= true then
		warn("[LoadingScreen] AssetsLoaded не выставлен за 40 с - выставляю принудительно.")
		finalize()
		pcall(function() screenGui:Destroy() end)
	end
end)
