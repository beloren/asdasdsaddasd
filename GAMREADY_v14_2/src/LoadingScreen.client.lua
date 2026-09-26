local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- ЗАГРУЗОЧНЫЙ ЭКРАН УБРАН ПО ЗАПРОСУ ("убери загрузку в самом начале с
-- зелёной полосой, катсцена будет самая первая при заходе в игру").
--
-- Что именно убрано: логотип по центру, полоса прогресса с зелёным
-- градиентом и вся её анимация. Что ОСТАЛОСЬ и почему это нельзя было
-- удалить вместе с картинкой:
--
--  1) Предзагрузка ассетов (ContentProvider:PreloadAsync ниже). Без неё
--     катсцена стартует на непрогруженных текстурах и звуках.
--  2) Атрибут AssetsLoaded. По нему катсцена и ЗАПУСКАЕТСЯ
--     (см. MoonAnimationTest.client.lua) — снеси этот скрипт целиком, и
--     катсцены не будет вообще.
--  3) Чёрная заливка на весь экран. Чёрный слой самой катсцены создаётся
--     ПРОЗРАЧНЫМ (BlackLayer.BackgroundTransparency = 1), так что без этой
--     заливки игрок несколько секунд смотрел бы на игровой мир ДО начала
--     катсцены — ровно то, чего просили избежать.
--
-- Итог для игрока: заходит → чернота → сразу катсцена. Никакой "загрузки"
-- с полосой он больше не видит.
-- MAX_PRELOAD_TIME убран: предзагрузка больше не блокирует запуск и ждать
-- её завершения не нужно (см. Config.Loading и комментарий у PreloadAsync
-- ниже). Оставлять константу, которая больше ни на что не влияет, вреднее,
-- чем удалить: следующий читатель решит, что лимит всё ещё работает.

ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
-- ReplicatedFirst is the only owner of the loading UI. Remove stale loading
-- screens left in StarterGui by older versions before drawing this one.
for _, child in playerGui:GetChildren() do
	if child.Name == "PreloadScreen" or child.Name == "LoadingScreen" then
		child:Destroy()
	end
end

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
	if child ~= screenGui and (child.Name == "PreloadScreen" or child.Name == "LoadingScreen") then
		child:Destroy()
	end
end)

local background = Instance.new("CanvasGroup")
background.Name = "Background"
background.AnchorPoint = Vector2.new(0.5, 0.5)
background.Position = UDim2.fromScale(0.5, 0.5)
background.Size = UDim2.fromScale(1, 1)
background.BackgroundColor3 = Color3.new(0, 0, 0)
background.BorderSizePixel = 0
background.Parent = screenGui

local blackOverscan = Instance.new("Frame")
blackOverscan.Name = "BlackOverscan"
blackOverscan.AnchorPoint = Vector2.new(0.5, 0.5)
blackOverscan.Position = UDim2.fromScale(0.5, 0.5)
blackOverscan.Size = UDim2.new(1, 400, 1, 400)
blackOverscan.BackgroundColor3 = Color3.new(0, 0, 0)
blackOverscan.BorderSizePixel = 0
blackOverscan.Parent = background

-- Ключи, суффикс которых однозначно указывает на "голое число = айди ассета"
-- (см. Config.lua: CloseButtonImageId, HintImageId, OwnedImageId, TrailTextureId и т.п.)
local RAW_ID_KEY_SUFFIXES = {
	"ImageId",
	"IconId",
	"TextureId",
	"MeshId",
	"SoundId",
	"AnimationId",
}

-- Таблицы, ВСЕ числовые поля которых — голые айди картинок, независимо от
-- имени поля (см. Config.Icons = { Pickaxe = 0, FlyingCoin = 93607959812195, ... }
-- и Config.Cards.CoverIcons = { Mine = 0, Cart = 0, ... } — поля называются по
-- названию ветки, а не заканчиваются на "Id").
local RAW_ID_PARENT_TABLES = {
	Icons = true,
	CoverIcons = true,
}

local function isRawAssetIdKey(key, parentKey)
	if typeof(key) ~= "string" then
		return false
	end
	if parentKey and RAW_ID_PARENT_TABLES[parentKey] then
		return true
	end
	for _, suffix in RAW_ID_KEY_SUFFIXES do
		if key:sub(-#suffix) == suffix then
			return true
		end
	end
	return false
end

local function collectConfigAssetIds(source, results, seen, parentKey)
	if typeof(source) ~= "table" or seen[source] then
		return
	end
	seen[source] = true
	for key, value in source do
		if typeof(value) == "string" and value:match("^rbxassetid://%d+$") and value ~= "rbxassetid://0" then
			table.insert(results, value)
		elseif typeof(value) == "number" and value ~= 0 and isRawAssetIdKey(key, parentKey) then
			table.insert(results, "rbxassetid://" .. tostring(value))
		elseif typeof(value) == "table" then
			collectConfigAssetIds(value, results, seen, typeof(key) == "string" and key or parentKey)
		end
	end
end

-- ОТКАЗОУСТОЙЧИВОСТЬ. Тело этого потока раньше не было обёрнуто ни во что:
-- ошибка на ЛЮБОЙ строке до `player:SetAttribute("AssetsLoaded", true)`
-- убивала поток молча, атрибут не выставлялся никогда, и катсцена
-- (MoonAnimationTest) ждала его вечно — уже отключив управление. Игрок
-- оставался стоять на месте без кнопок управления на телефоне, пока не
-- сделает ресет. Теперь любая ошибка логируется, а флаги выставляются в
-- любом случае, чтобы никто вниз по цепочке не завис.
local function finalize()
	pcall(function() player:SetAttribute("AssetsLoaded", true) end)
end

task.spawn(function()
	local ok, err = xpcall(function()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	local plotWaitStarted = os.clock()
	-- Было 5 секунд. Участок нужен не катсцене, а игре ПОСЛЕ неё — а она
	-- начнётся секунд на десять позже, к тому моменту атрибут давно придёт.
	-- Держать ради него чёрный экран нет причин.
	while player:GetAttribute("PlotIndex") == nil and os.clock() - plotWaitStarted < 1.5 do
		task.wait(0.05)
	end
	-- BillboardGui участка создаются сервером по очереди. Ждём, пока их число
	-- перестанет меняться, и только потом делаем снимок game:GetDescendants(),
	-- который ContentProvider загрузит вместе с картинками и шрифтами внутри.
	local billboardWaitStarted = os.clock()
	local stableSince = os.clock()
	local lastBillboardCount = -1
	repeat
		local billboardCount = 0
		for _, descendant in game:GetDescendants() do
			if descendant:IsA("BillboardGui") then billboardCount += 1 end
		end
		if billboardCount ~= lastBillboardCount then
			lastBillboardCount = billboardCount
			stableSince = os.clock()
		end
		task.wait(0.05)
	until os.clock() - stableSince >= 0.35 or os.clock() - billboardWaitStarted >= 1

	local assets = game:GetDescendants()
	local configModule = ReplicatedStorage:FindFirstChild("Shared")
	configModule = configModule and configModule:FindFirstChild("Config")
	if configModule then
		local ok, config = pcall(require, configModule)
		if ok then
			collectConfigAssetIds(config, assets, {})
		end
	end

	-- ПРЕДЗАГРУЗКА БОЛЬШЕ НЕ БЛОКИРУЕТ СТАРТ (см. Config.Loading).
	--
	-- Раньше здесь стоял цикл ожидания до MAX_PRELOAD_TIME (15 секунд), и
	-- всё это время игрок смотрел в чёрный экран, ничего не делая. Теперь
	-- PreloadAsync уходит в фоновый поток и спокойно доигрывает уже ВО ВРЕМЯ
	-- катсцены — то есть ровно тогда, когда игроку и так есть на что
	-- смотреть. Ждём только короткое окно CriticalWaitSeconds.
	--
	-- Почему это безопасно: ContentProvider не является обязательным
	-- условием отрисовки. Не успевший загрузиться ассет Roblox дорисует сам,
	-- как только тот придёт; худшее, что может случиться — первые кадры
	-- сцены с ещё не подгруженной текстурой. Это несопоставимо дешевле, чем
	-- 15 секунд черноты, которые игрок видит ГАРАНТИРОВАННО.
	task.spawn(function()
		local ok = pcall(function()
			ContentProvider:PreloadAsync(assets)
		end)
		if not ok then
			warn("[LoadingScreen] Some assets could not be preloaded; continuing startup.")
		end
	end)

	local criticalWait = 1.5
	local loadingConfig = configModule and select(2, pcall(require, configModule))
	if typeof(loadingConfig) == "table" and typeof(loadingConfig.Loading) == "table" then
		criticalWait = tonumber(loadingConfig.Loading.CriticalWaitSeconds) or criticalWait
	end
	task.wait(math.max(0, criticalWait))

	player:SetAttribute("AssetsLoaded", true)

	while player:GetAttribute("CutsceneStarted") ~= true
		and player:GetAttribute("IntroFailed") ~= true do
		task.wait(0.05)
	end

	local fade = TweenService:Create(background, TweenInfo.new(0.6), { GroupTransparency = 1 })
	fade:Play()
	fade.Completed:Wait()
	staleScreenConnection:Disconnect()
	screenGui:Destroy()
	end, debug.traceback)
	if not ok then
		warn("[LoadingScreen] Загрузочный экран упал; продолжаю запуск игры:\n" .. tostring(err))
		-- Обязательно снимаем экран и выставляем флаг, иначе игрок останется
		-- смотреть на застывшую заставку без управления.
		finalize()
		pcall(function() staleScreenConnection:Disconnect() end)
		pcall(function() screenGui:Destroy() end)
	end
end)

-- Страховка по времени, независимая от кода выше: даже если поток
-- где-то залип на WaitForChild/Wait (а не упал), флаг всё равно будет
-- выставлен, и катсцена с управлением не останутся заблокированными.
task.delay(30, function()
	if player:GetAttribute("AssetsLoaded") ~= true then
		warn("[LoadingScreen] AssetsLoaded не выставлен за 30 с - выставляю принудительно.")
		finalize()
		pcall(function() screenGui:Destroy() end)
	end
end)
