--------------------------------------------------------------------------------
-- LoadingScreen (ReplicatedFirst) v20.124 — ЗАГРУЗКА С ОБЛЁТОМ МИРА.
--
-- Катсцены больше нет (Config.Loading.Cutscene = false). При входе:
--   1) камера висит высоко над центром мира и медленно кружит, мир размыт
--      (BlurEffect), поверх - логотип, полоса загрузки, подсказки и
--      «Loading assets... N%» слева внизу;
--   2) грузится ВСЁ: ReplicatedStorage (модели, VFX, анимации ударов),
--      мир, интерфейс, звуки, освещение и все айди из Config (картинки,
--      звуки, анимации - как Animation). Порциями, у каждой порции свой
--      лимит времени - битый ассет не подвешивает загрузку;
--   3) SKIP (через Config.Loading.SkipAfterSeconds) - сразу к игроку;
--   4) конец загрузки - камера из текущей точки «как в GTA 5»: взлёт выше,
--      перелёт к игроку сверху, спуск за спину - и обычная камера.
-- Атрибуты: IntroActive = true на время загрузки (обучение, HUD, музыка
-- ждут), AssetsLoaded = true в конце. Всё в pcall и со страховкой по времени.
--------------------------------------------------------------------------------
local ContentProvider = game:GetService("ContentProvider")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
for _, child in playerGui:GetChildren() do
	if child.Name == "PreloadScreen" or child.Name == "LoadingScreen" then child:Destroy() end
end
player:SetAttribute("IntroActive", true)
player:SetAttribute("AssetsLoaded", false)

--------------------------------------------------------------------------------
-- ЭКРАН (мир виден сквозь размытие - фона нет)
--------------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LoadingScreen"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 1000
pcall(function() screenGui.ScreenInsets = Enum.ScreenInsets.None end)
screenGui.Parent = playerGui

local root = Instance.new("CanvasGroup")
root.Name = "Root"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = Color3.new(0, 0, 0)
root.BackgroundTransparency = 0 -- первые кадры, пока мир не прогрузился - тёмный экран
root.BorderSizePixel = 0
root.Parent = screenGui

local function stroke(parent, thickness, color)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color or Color3.fromRGB(20, 14, 10)
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = parent
	return s
end
-- v20.125: шрифты как в HUD (UiTheme: SourceSansPro, жирный курсив)
local HUD_FAMILY = "rbxasset://fonts/families/SourceSansPro.json"
local FONT_HEADING = Font.new(HUD_FAMILY, Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
local FONT_BODY = Font.new(HUD_FAMILY, Enum.FontWeight.Bold, Enum.FontStyle.Italic)

local logo = Instance.new("ImageLabel")
logo.Name = "Logo"
logo.AnchorPoint = Vector2.new(0.5, 0.5)
logo.Position = UDim2.fromScale(0.5, 0.42)
logo.Size = UDim2.fromScale(0.5, 0.42)
logo.BackgroundTransparency = 1
logo.ScaleType = Enum.ScaleType.Fit
logo.Parent = root
local logoScale = Instance.new("UIScale")
logoScale.Parent = logo

local barBack = Instance.new("ImageLabel")
barBack.Name = "Bar"
barBack.AnchorPoint = Vector2.new(0.5, 0.5)
barBack.Position = UDim2.fromScale(0.5, 0.775)
barBack.Size = UDim2.fromScale(0.6, 0.055)
barBack.BackgroundColor3 = Color3.fromRGB(170, 22, 28)
barBack.Image = ""
barBack.BorderSizePixel = 0
barBack.Parent = root
Instance.new("UICorner", barBack).CornerRadius = UDim.new(0, 8)
stroke(barBack, 3, Color3.fromRGB(60, 8, 10))
local barFill = Instance.new("ImageLabel")
barFill.Name = "Fill"
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = Color3.fromRGB(40, 165, 50)
barFill.Image = ""
barFill.BorderSizePixel = 0
barFill.Parent = barBack
Instance.new("UICorner", barFill).CornerRadius = UDim.new(0, 8)
local fillGradient = Instance.new("UIGradient")
fillGradient.Rotation = 90
fillGradient.Color = ColorSequence.new(Color3.fromRGB(110, 230, 110), Color3.fromRGB(30, 140, 40))
fillGradient.Parent = barFill

local tip = Instance.new("TextLabel")
tip.Name = "Tip"
tip.AnchorPoint = Vector2.new(0.5, 0.5)
tip.Position = UDim2.fromScale(0.5, 0.9)
tip.Size = UDim2.fromScale(0.7, 0.045)
tip.BackgroundTransparency = 1
tip.FontFace = FONT_BODY
tip.TextScaled = true
tip.TextColor3 = Color3.new(1, 1, 1)
tip.Text = ""
tip.Parent = root
stroke(tip, 2)

local status = Instance.new("TextLabel")
status.Name = "Status"
status.AnchorPoint = Vector2.new(0, 1)
status.Position = UDim2.new(0, 14, 1, -10)
status.Size = UDim2.fromScale(0.32, 0.042)
status.BackgroundTransparency = 1
status.FontFace = FONT_HEADING
status.TextScaled = true
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextColor3 = Color3.new(1, 1, 1)
status.Text = "Loading..."
status.Parent = root
stroke(status, 2)

local skipButton = Instance.new("TextButton")
skipButton.Name = "Skip"
skipButton.AnchorPoint = Vector2.new(1, 1)
skipButton.Position = UDim2.new(1, -18, 1, -14)
skipButton.Size = UDim2.fromOffset(150, 52)
skipButton.BackgroundColor3 = Color3.fromRGB(235, 160, 40)
skipButton.FontFace = FONT_HEADING
skipButton.TextScaled = true
skipButton.TextColor3 = Color3.new(1, 1, 1)
skipButton.Text = "SKIP >"
skipButton.Visible = false
skipButton.Parent = root
Instance.new("UICorner", skipButton).CornerRadius = UDim.new(0, 12)
local skipStroke = stroke(skipButton, 3)
skipStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
local skipPad = Instance.new("UIPadding")
skipPad.PaddingTop, skipPad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
skipPad.Parent = skipButton
local skipped = false
skipButton.Activated:Connect(function() skipped = true end)

--------------------------------------------------------------------------------
-- ПРЯЧЕМ ОСТАЛЬНОЙ ИНТЕРФЕЙС, ПОКА ГРУЗИМ (вернём в конце)
--------------------------------------------------------------------------------
-- v20.128: ПОМНИМ НАМЕРЕНИЯ СКРИПТОВ. Экран, который скрипт включил во
-- время загрузки, вернётся; экран, который был включён с самого начала,
-- вернётся, если это не окно, которое его скрипт сам выключает при старте
-- (иначе такое окно открылось бы само после загрузки). Управление на
-- телефоне (TouchGui/ControlGui) не трогаем никогда.
local KEEP_DISABLED = {
	TutorialUi = true, PerkUi = true, MerchantUi = true, IslandUi = true, GeodeUi = true,
	DropPreviewUi = true, DecorStorageUi = true, CartInventoryUi = true, SatchelInventory = true,
	SettingsMenu = true, ShopEntry = true, SkinEntry = true, RebirthDialogButtons = true,
	MinerDialogUi = true, MineArcUi = true, UpgradeShopUi = true, InventoryUi = true,
	-- v20.146: полноэкранные деревья никогда не включаются сами после загрузки
	UpgradeTreeUi = true, IslandTreeUi = true,
}
local CONTROL_GUIS = { TouchGui = true, ControlGui = true }
local tracked = {} -- [gui] = { Initial = bool, Wanted = bool, Connection }
local function suppress(gui)
	if gui == screenGui or not gui:IsA("ScreenGui") or CONTROL_GUIS[gui.Name] or tracked[gui] then return end
	local entry = { Initial = gui.Enabled, Wanted = false }
	tracked[gui] = entry
	entry.Connection = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if gui.Enabled then
			entry.Wanted = true -- скрипт включил экран во время загрузки
			gui.Enabled = false
		end
	end)
	gui.Enabled = false
end
for _, gui in playerGui:GetChildren() do suppress(gui) end
local suppressConnection = playerGui.ChildAdded:Connect(suppress)
-- и интерфейс Roblox (чат, список игроков, рюкзак, эмоции, здоровье)
local StarterGui = game:GetService("StarterGui")
local CORE_TYPES = { Enum.CoreGuiType.Chat, Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.EmotesMenu, Enum.CoreGuiType.Health }
local coreWas = {}
for _, kind in CORE_TYPES do
	local ok, enabled = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, kind)
	coreWas[kind] = ok and enabled
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, kind, false)
end
local function restoreGuis()
	suppressConnection:Disconnect()
	for gui, entry in tracked do
		entry.Connection:Disconnect()
		local restore = entry.Wanted or (entry.Initial and not KEEP_DISABLED[gui.Name])
		if restore and gui.Parent and gui:GetAttribute("FocusHidden") ~= true then gui.Enabled = true end
	end
	table.clear(tracked)
	-- v20.127: рюкзак и список игроков Roblox НЕ возвращаем - их отключает сама
	-- игра (CustomCartUI: свой хотбар со слотом кирки). Раньше загрузка
	-- включала стандартный рюкзак обратно, и кирка стала обычным слотом.
	for kind, enabled in coreWas do
		if enabled and kind ~= Enum.CoreGuiType.Backpack and kind ~= Enum.CoreGuiType.PlayerList then
			pcall(StarterGui.SetCoreGuiEnabled, StarterGui, kind, true)
		end
	end
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false)
	-- v20.138: список игроков (TAB) после загрузки - включён
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList, true)
end

--------------------------------------------------------------------------------
-- КАМЕРА: облёт над центром мира + размытие
--------------------------------------------------------------------------------
local blur = Instance.new("BlurEffect")
blur.Name = "LoadingBlur"
blur.Size = 18
blur.Parent = Lighting

local loadingCfg = {}
local soundsCfg = {}
-- v20.129: звук перелёта камеры (Config.Sounds.LoadingWhoosh)
local function playWhoosh(pitch)
	local entry = soundsCfg.LoadingWhoosh
	if not (entry and typeof(entry.Id) == "string" and entry.Id ~= "") then return end
	local sound = Instance.new("Sound")
	sound.SoundId = entry.Id
	sound.Volume = entry.Volume or 0.5
	sound.PlaybackSpeed = (entry.Pitch or 1) * (pitch or 1)
	sound.Parent = game:GetService("SoundService")
	sound:Play()
	game:GetService("Debris"):AddItem(sound, 5)
end
local orbitCenter = Vector3.new(0, 0, 0)
local orbitAngle = math.random() * math.pi * 2
local orbiting = true

-- v20.125: центр мира = ГОРОД С МАГАЗИНАМИ - середина между торговцем
-- руды (BankMerchant) и хранителем островов (IslandKeeper); нет их -
-- маркер CompassCenterMarker / зона продажи / точка спавна.
local function positionOf(instance)
	if not instance then return nil end
	if instance:IsA("BasePart") then return instance.Position end
	if instance:IsA("Model") then
		local ok, pivot = pcall(instance.GetPivot, instance)
		return ok and pivot.Position or nil
	end
	if instance:IsA("Folder") then
		local inner = instance:FindFirstChildWhichIsA("Model") or instance:FindFirstChildWhichIsA("BasePart")
		return positionOf(inner)
	end
	return nil
end

local function findCenter()
	local shops = {}
	for _, name in { "BankMerchant", "IslandKeeper" } do
		local position = positionOf(workspace:FindFirstChild(name, true))
		if position then table.insert(shops, position) end
	end
	if #shops > 0 then
		local sum = Vector3.zero
		for _, position in shops do sum += position end
		return sum / #shops
	end
	for _, name in { "CompassCenterMarker", "SellZone", "Bank" } do
		local position = positionOf(workspace:FindFirstChild(name, true))
		if position then return position end
	end
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	return spawn and spawn.Position or Vector3.new(0, 0, 0)
end

local function orbitCFrame(angle)
	local height = tonumber(loadingCfg.OrbitHeight) or 110
	local radius = tonumber(loadingCfg.OrbitRadius) or 150
	local eye = orbitCenter + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
	return CFrame.lookAt(eye, orbitCenter)
end

local orbitConnection = RunService.RenderStepped:Connect(function(dt)
	local camera = workspace.CurrentCamera
	if not (camera and orbiting) then return end
	camera.CameraType = Enum.CameraType.Scriptable
	orbitAngle += dt * math.rad(tonumber(loadingCfg.OrbitDegreesPerSecond) or 6)
	camera.CFrame = orbitCFrame(orbitAngle)
end)

--------------------------------------------------------------------------------
-- ПРОГРЕСС И ПОДСКАЗКИ
--------------------------------------------------------------------------------
local shown, target = 0, 0
local stage = "Loading assets"
local tips = { "Rarer ore sells for more!", "Buy new ore at the Ore Merchant!", "Crystals earn money even offline!" }
local tipIndex, tipAt = 1, 0
local uiConnection = RunService.RenderStepped:Connect(function(dt)
	shown += (target - shown) * math.min(1, dt * 5)
	barFill.Size = UDim2.fromScale(math.clamp(shown, 0, 1), 1)
	status.Text = ("%s... %d%%"):format(stage, math.floor(math.clamp(shown, 0, 1) * 100 + 0.5))
	if orbiting then logoScale.Scale = 1 + math.sin(os.clock() * 2) * 0.025 end
	if os.clock() >= tipAt then
		tipAt = os.clock() + (tonumber(loadingCfg.TipSeconds) or 4)
		tipIndex = tipIndex % #tips + 1
		tip.Text = "[" .. tostring(tips[tipIndex]) .. "]"
	end
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
		local isAnim = (keyName and (keyName:find("Animation") or keyName:find("Anim"))) or parentKey == "NpcIdleAnimations"
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
				-- анимации (удары и т.п.) - как Animation, иначе ключевые кадры не подтянутся
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

local function collect(rootInstance, list, seen)
	if not rootInstance then return end
	for _, d in rootInstance:GetDescendants() do
		if CONTENT_CLASSES[d.ClassName] and not seen[d] then
			seen[d] = true
			table.insert(list, d)
		end
	end
end

-- Порция с лимитом времени: битый ассет не держит загрузку.
local function preloadBatch(batch, timeout)
	local finished = false
	task.spawn(function()
		pcall(ContentProvider.PreloadAsync, ContentProvider, batch)
		finished = true
	end)
	local started = os.clock()
	while not finished and not skipped and os.clock() - started < timeout do
		task.wait()
	end
end

--------------------------------------------------------------------------------
-- ПЕРЕХОД К ИГРОКУ «КАК В GTA 5»: взлёт → перелёт сверху → спуск за спину
--------------------------------------------------------------------------------
local function tweenCamera(camera, cframe, seconds, style, direction)
	local tween = TweenService:Create(camera, TweenInfo.new(seconds, style or Enum.EasingStyle.Sine, direction or Enum.EasingDirection.InOut), { CFrame = cframe })
	tween:Play()
	tween.Completed:Wait()
end

local function waitForCharacter(timeout)
	local started = os.clock()
	while os.clock() - started < timeout do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local head = character and character:FindFirstChild("Head")
		if hrp and head then return character, hrp, head end
		task.wait(0.1)
	end
	return nil
end

local function transitionToPlayer()
	local camera = workspace.CurrentCamera
	stage = "Loading player data"
	local character, hrp, head = waitForCharacter(tonumber(loadingCfg.CharacterWaitSeconds) or 30)
	orbiting = false
	-- v20.127: АНИМАЦИЯ УХОДА: SKIP и подсказка гаснут, полоса уезжает вниз,
	-- логотип «вспухает» и растворяется, затем гаснет весь слой
	skipButton.Visible = false
	local quick = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(tip, quick, { TextTransparency = 1 }):Play()
	TweenService:Create(status, quick, { TextTransparency = 1 }):Play()
	for _, item in { tip, status } do
		local textStroke = item:FindFirstChildOfClass("UIStroke")
		if textStroke then TweenService:Create(textStroke, quick, { Transparency = 1 }):Play() end
	end
	TweenService:Create(barBack, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Position = UDim2.fromScale(0.5, 1.2),
	}):Play()
	TweenService:Create(logoScale, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.12 }):Play()
	task.delay(0.18, function()
		TweenService:Create(logoScale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0.2 }):Play()
		TweenService:Create(logo, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { ImageTransparency = 1, Rotation = -8 }):Play()
	end)
	task.delay(0.55, function()
		TweenService:Create(root, TweenInfo.new(0.35), { GroupTransparency = 1 }):Play()
	end)
	if not (camera and character) then return end
	-- игрок мог ещё стоять не на месте - подождём, пока сервер поставит его на участок
	task.wait(0.3)
	local start = camera.CFrame
	local high = tonumber(loadingCfg.TransitionHeight) or 260
	local playerPos = hrp.Position
	local look = hrp.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	if look.Magnitude < 0.05 then look = Vector3.new(0, 0, -1) end
	look = look.Unit
	playWhoosh(1)
	-- 1) взлёт: из текущей точки вверх, взгляд вниз
	local upPos = Vector3.new(start.Position.X, math.max(start.Position.Y, playerPos.Y) + high, start.Position.Z)
	tweenCamera(camera, CFrame.lookAt(upPos, upPos - Vector3.new(0, 1, 0), look), 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	-- 2) перелёт над игроком (вид строго сверху)
	local overPos = Vector3.new(playerPos.X, upPos.Y, playerPos.Z)
	tweenCamera(camera, CFrame.lookAt(overPos, overPos - Vector3.new(0, 1, 0), look), 1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	-- 3) спуск: сначала ниже над игроком, потом за спину - обычный ракурс
	playerPos = hrp.Position
	local midPos = playerPos + Vector3.new(0, high * 0.25, 0)
	TweenService:Create(blur, TweenInfo.new(1.1), { Size = 0 }):Play()
	playWhoosh(1.25)
	tweenCamera(camera, CFrame.lookAt(midPos, playerPos, look), 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local focus = head.Position
	local eye = focus - look * 12 + Vector3.new(0, 4.5, 0)
	tweenCamera(camera, CFrame.lookAt(eye, focus), 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
end

local finishDone = false
local function finish()
	if finishDone then return end
	finishDone = true
	orbiting = false
	pcall(function() orbitConnection:Disconnect() end)
	pcall(function() uiConnection:Disconnect() end)
	local camera = workspace.CurrentCamera
	if camera then
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then camera.CameraSubject = humanoid end
		camera.CameraType = Enum.CameraType.Custom
	end
	pcall(function() blur:Destroy() end)
	pcall(restoreGuis)
	player:SetAttribute("AssetsLoaded", true)
	player:SetAttribute("IntroActive", false)
	pcall(function() screenGui:Destroy() end)
end

--------------------------------------------------------------------------------
-- ОСНОВНОЙ ПОТОК
--------------------------------------------------------------------------------
local finished = false
task.spawn(function()
	local ok, err = xpcall(function()
		if not game:IsLoaded() then game.Loaded:Wait() end
		local okConfig, Config = false, nil
		local shared = ReplicatedStorage:WaitForChild("Shared", 15)
		local configModule = shared and shared:WaitForChild("Config", 15)
		if configModule then okConfig, Config = pcall(require, configModule) end
		if okConfig and typeof(Config) == "table" and typeof(Config.Loading) == "table" then
			loadingCfg = Config.Loading
			soundsCfg = typeof(Config.Sounds) == "table" and Config.Sounds or {}
			if typeof(loadingCfg.Tips) == "table" and #loadingCfg.Tips > 0 then tips = loadingCfg.Tips end
		end
		local logoId = tonumber(loadingCfg.LogoImageId) or 113042882863397
		if logoId > 0 then logo.Image = "rbxassetid://" .. logoId end

		-- камера над центром мира; мир вокруг центра просим подгрузить
		-- торговцы ставятся сервером - чуть подождём их (не дольше 3 с)
		local centerWait = os.clock()
		while not workspace:FindFirstChild("BankMerchant", true) and os.clock() - centerWait < 3 do task.wait(0.1) end
		orbitCenter = findCenter()
		pcall(function() player:RequestStreamAroundAsync(orbitCenter, 10) end)
		TweenService:Create(root, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
		task.delay(tonumber(loadingCfg.SkipAfterSeconds) or 1, function() skipButton.Visible = true end)

		-- список всего, что грузим
		stage = "Loading assets"
		local list, seen, animations = {}, {}, {}
		collect(ReplicatedStorage, list, seen)
		collect(workspace, list, seen)
		collect(playerGui, list, seen)
		collect(game:GetService("StarterGui"), list, seen)
		collect(game:GetService("SoundService"), list, seen)
		collect(Lighting, list, seen)
		if okConfig then pcall(collectConfigAssetIds, Config, list, {}, nil, animations) end
		-- сначала то, что видно сразу и играет первым: анимации, VFX, звуки
		table.sort(list, function(a, b)
			local function rank(item)
				if typeof(item) ~= "Instance" then return 3 end
				if item:IsA("Animation") then return 0 end
				if item:IsA("ParticleEmitter") or item:IsA("Beam") or item:IsA("Trail") then return 1 end
				if item:IsA("Sound") then return 2 end
				return 3
			end
			return rank(a) < rank(b)
		end)

		local total = math.max(1, #list)
		local batchSize = tonumber(loadingCfg.BatchSize) or 60
		local batchTimeout = tonumber(loadingCfg.BatchTimeout) or 3
		local maxSeconds = tonumber(loadingCfg.MaxSeconds) or 25
		local started = os.clock()
		for index = 1, #list, batchSize do
			if skipped or os.clock() - started > maxSeconds then break end
			local batch = table.move(list, index, math.min(index + batchSize - 1, #list), 1, {})
			preloadBatch(batch, batchTimeout)
			target = math.min(index + batchSize - 1, #list) / total
		end
		target = 1
		task.wait(skipped and 0 or 0.25)
		skipButton.Visible = false
		-- недогруженное - в фоне, без экрана
		if skipped or os.clock() - started > maxSeconds then
			task.spawn(function()
				pcall(ContentProvider.PreloadAsync, ContentProvider, list)
				for _, animation in animations do animation:Destroy() end
			end)
		else
			for _, animation in animations do animation:Destroy() end
		end

		transitionToPlayer()
	end, debug.traceback)
	if not ok then
		warn("[LoadingScreen] Загрузка упала; продолжаю запуск игры:\n" .. tostring(err))
	end
	finished = true
	finish()
end)

-- Страховка: что бы ни случилось, через MaxSeconds + запас игра начнётся.
task.delay(75, function()
	if not finished then
		warn("[LoadingScreen] Загрузка не завершилась за 75 с - запускаю игру принудительно.")
		finished = true
		finish()
	end
end)
