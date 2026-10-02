--------------------------------------------------------------------------------
-- CinematicHud (LocalScript) — прячет ИГРОВОЙ интерфейс на время катсцен.
--
-- ЗАЧЕМ. Во время катсцены шахты, мини-игры, раскола жеоды и улучшений
-- камера показывает сцену, а поверх неё продолжал висеть весь HUD: хотбар,
-- портрет, квесты, баффы, подсказки. Кадр переставал читаться.
--
-- КАК. Каждый верхнеуровневый элемент уезжает к БЛИЖАЙШЕМУ к нему краю
-- экрана и возвращается на место, когда катсцена кончилась. Именно к
-- ближайшему, а не всё в одну сторону: хотбар снизу уходит вниз, портрет
-- слева — влево, панель баффов справа — вправо. Так это читается как
-- "интерфейс убрался", а не как "интерфейс уехал куда-то".
--
-- ПОЧЕМУ НЕ ПРОСТО Enabled = false. Мгновенное исчезновение выглядит как
-- баг/лаг, а не как приём. Плюс исходную позицию всё равно надо где-то
-- помнить, чтобы вернуть — а раз помним, то и анимация почти бесплатна.
--
-- КАК ПОЛЬЗОВАТЬСЯ ИЗ ДРУГИХ СКРИПТОВ:
--   local ReplicatedStorage = game:GetService("ReplicatedStorage")
--   local cinematic = ReplicatedStorage.Shared:FindFirstChild("CinematicMode")
--   cinematic:Fire(true)   -- спрятать HUD
--   cinematic:Fire(false)  -- вернуть
--
-- Вызовы СЧИТАЮТСЯ (Fire(true) дважды требует двух Fire(false)): катсцены
-- могут накладываться, и первая же закончившаяся не должна возвращать HUD
-- поверх второй, ещё идущей.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ScreenGui, которые НЕ прячем: это либо сама катсцена, либо то, что
-- обязано быть видно поверх неё (затемнения, переходы, модальные окна).
-- Прятать их означало бы спрятать то, ради чего HUD и убирается.
local KEEP_VISIBLE = {
	-- v20.130: УПРАВЛЕНИЕ И ЭКРАНЫ ROBLOX НЕ ТРОГАЕМ НИКОГДА (джойстик пропадал)
	TouchGui = true,
	ControlGui = true,
	Freecam = true,
	Chat = true,
	BubbleChat = true,
	PlayerList = true,
	LoadingScreen = true,
	TutorialCursor = true,
	MineArcUi = true,          -- мини-игра шахты
	MineDialogUi = true,       -- реплики шахтёра
	GeodeUi = true,            -- окно жеоды и раскол
	IntroTransition = true,    -- переходы/затемнения
	ReturnScreenUi = true,
	SettingsMenu = true,
	InteractiveTutorial = true,
	ZavtrackDialog = true,
	RebirthDialogButtons = true,
	DamageNumber = true,       -- мировые числа, не HUD
	MoneyGainFx = true,
	GeodeDropNotifications = true,
	WeatherLightning = true,   -- полноэкранный эффект молнии, часть картинки
	InventoryDragOverlay = true,
	IslandLabels = true,       -- мировые подписи над островами (IslandUI), не HUD
	RevealCards = true,        -- v20: карточки открытия наград
	TutorialUi = true,         -- v20: реплики обучения
	-- v20.114: экраны, которые сами появляются ВО ВРЕМЯ катсцен
	RarityReel = true,         -- лента редкостей шахты
	MineRarityFlash = true,
	BoulderHitVignette = true,
	CoinShowerFx = true,
	TutorialSpotlight = true,
	BoulderGameUi = true,
	MiningRhythmUi = true,
	MinerDialogUi = true,
}

local SLIDE_SECONDS = 0.35
local EASING_OUT = TweenInfo.new(SLIDE_SECONDS, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local EASING_IN = TweenInfo.new(SLIDE_SECONDS, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

local hiddenElements = {} -- [GuiObject] = оригинальный UDim2
local dynamicKeep = {}    -- v20.118: [имя ScreenGui] = счётчик - временно не прячем (HudFocus)
local depth = 0

local function viewportSize()
	local camera = workspace.CurrentCamera
	return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

-- Куда именно уводить элемент: считаем расстояние от его центра до каждого
-- из четырёх краёв и выбираем минимальное.
local function offscreenPositionFor(element)
	local viewport = viewportSize()
	local position = element.AbsolutePosition
	local size = element.AbsoluteSize
	local centre = position + size / 2

	local distances = {
		{ edge = "Left", value = centre.X },
		{ edge = "Right", value = viewport.X - centre.X },
		{ edge = "Top", value = centre.Y },
		{ edge = "Bottom", value = viewport.Y - centre.Y },
	}
	table.sort(distances, function(a, b) return a.value < b.value end)
	local nearest = distances[1].edge

	local current = element.Position
	-- Сдвигаем на габарит элемента плюс запас: элемент должен уйти ЦЕЛИКОМ,
	-- иначе у края останется торчать полоска.
	local marginX = size.X + 40
	local marginY = size.Y + 40

	if nearest == "Left" then
		return current - UDim2.fromOffset(marginX, 0)
	elseif nearest == "Right" then
		return current + UDim2.fromOffset(marginX, 0)
	elseif nearest == "Top" then
		return current - UDim2.fromOffset(0, marginY)
	end
	return current + UDim2.fromOffset(0, marginY)
end

local function hudElements()
	local list = {}
	for _, gui in playerGui:GetChildren() do
		if gui:IsA("ScreenGui") and gui.Enabled and not KEEP_VISIBLE[gui.Name] and not dynamicKeep[gui.Name] and gui:GetAttribute("CinematicKeep") ~= true then
			for _, child in gui:GetChildren() do
				-- Только верхнеуровневые видимые элементы: двигать вложенные
				-- бессмысленно, они уедут вместе с родителем.
				if child:IsA("GuiObject") and child.Visible then
					table.insert(list, child)
				end
			end
		end
	end
	return list
end

local function hideHud()
	for _, element in hudElements() do
		if hiddenElements[element] == nil then
			-- Запоминаем ДО первого сдвига. Если катсцена наложится на
			-- катсцену, второй заход не должен запомнить уже уехавшую
			-- позицию как "исходную" — иначе HUD никогда не вернётся.
			-- v20.128: элемент мог быть посреди уезжания под окном (ScreenFocus) -
			-- настоящий дом в атрибуте FocusHome
			local focusHome = element:GetAttribute("FocusHome")
			hiddenElements[element] = typeof(focusHome) == "UDim2" and focusHome or element.Position
			element:SetAttribute("CinematicHome", hiddenElements[element])
			TweenService:Create(element, EASING_OUT, {
				Position = offscreenPositionFor(element),
			}):Play()
		end
	end
end

local function showHud()
	for element, originalPosition in hiddenElements do
		element:SetAttribute("CinematicHome", nil)
		-- под открытым окном (ScreenFocus) экран выключен - домой вернёт ScreenFocus
		if element.Parent and typeof(element:GetAttribute("FocusHome")) == "UDim2" then
			-- ничего: ScreenFocus сам привезёт элемент домой при закрытии окна
		elseif element.Parent then
			-- Телефонная раскладка (UiLayout) могла сменить позицию, пока HUD
			-- был спрятан, — возвращаем туда.
			local layoutPosition = element:GetAttribute("LayoutPosition")
			local target = typeof(layoutPosition) == "UDim2" and layoutPosition or originalPosition
			TweenService:Create(element, EASING_IN, { Position = target }):Play()
		end
	end
	hiddenElements = {}
end

-- v20.114: ВСЁ UI НА ВРЕМЯ КАТСЦЕНЫ. Пока катсцена идёт, раз в 0.25 с
-- досдвигаем то, что появилось уже после её начала (уведомления, компас,
-- новые панели), и прячем интерфейс Roblox (чат, список игроков, рюкзак,
-- эмоции) - Config.UI.CinematicHideCoreGui. После катсцены всё как было.
local StarterGui = game:GetService("StarterGui")
local okConfig, Config = pcall(require, ReplicatedStorage.Shared.Config)
local HIDE_CORE = not (okConfig and Config.UI and Config.UI.CinematicHideCoreGui == false)
local CORE_TYPES = { Enum.CoreGuiType.Chat, Enum.CoreGuiType.EmotesMenu, Enum.CoreGuiType.Health }
local coreWasEnabled = nil

local function hideCore()
	if not HIDE_CORE or coreWasEnabled then return end
	coreWasEnabled = {}
	for _, kind in CORE_TYPES do
		local ok, enabled = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, kind)
		coreWasEnabled[kind] = ok and enabled
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, kind, false)
	end
end

local function restoreCore()
	if not coreWasEnabled then return end
	for kind, enabled in coreWasEnabled do
		-- v20.130: рюкзак и список игроков игра выключает сама - не возвращаем
		if enabled and kind ~= Enum.CoreGuiType.Backpack and kind ~= Enum.CoreGuiType.PlayerList then
			pcall(StarterGui.SetCoreGuiEnabled, StarterGui, kind, true)
		end
	end
	coreWasEnabled = nil
end

-- v20.130: ВЛАДЕЛЬЦЫ ВМЕСТО СЧЁТЧИКА. Раньше Fire(true)/Fire(false)
-- считались счётчиком: лишний Fire(true) (повторный пакет «Minigame»,
-- ошибка, выход посреди сцены) навсегда оставлял HUD за краем экрана - у
-- игроков пропадали все кнопки. Теперь у каждой катсцены своё имя:
--   CinematicMode:Fire(true, "Mine") / Fire(false, "Mine")
-- повторный Fire(true) того же имени ничего не добавляет; у каждого
-- владельца лимит MAX_OWNER_SECONDS - потом HUD возвращается сам.
local MAX_OWNER_SECONDS = 120
local cameraHoldName, cameraHoldSince = nil, 0
local scriptableSince = nil
local owners = {} -- [имя] = { Since, NoCore, Focus, Keep }

local function anyOwner(filter)
	for _, info in owners do
		if filter == nil or filter(info) then return true end
	end
	return false
end

local function refresh()
	local active = next(owners) ~= nil
	-- закреплённые экраны (HudFocus keep) - объединение по всем фокус-владельцам
	table.clear(dynamicKeep)
	for _, info in owners do
		for _, name in info.Keep or {} do dynamicKeep[name] = true end
	end
	-- если хоть один НЕ фокусный владелец - keep фокуса не действует
	if anyOwner(function(info) return not info.Focus end) then table.clear(dynamicKeep) end
	if active then
		depth = 1
		-- экраны, которые больше не надо прятать (стали keep) - вернуть
		for element, originalPosition in hiddenElements do
			local gui = element:FindFirstAncestorWhichIsA("ScreenGui")
			if gui and dynamicKeep[gui.Name] then
				hiddenElements[element] = nil
				element:SetAttribute("CinematicHome", nil)
				TweenService:Create(element, EASING_IN, { Position = originalPosition }):Play()
			end
		end
		pcall(hideHud)
		if anyOwner(function(info) return not info.NoCore end) then hideCore() else restoreCore() end
	else
		depth = 0
		showHud()
		restoreCore()
	end
	playerGui:SetAttribute("CinematicActive", anyOwner(function(info) return not info.Focus end))
end

local function setOwner(name, active, info)
	name = tostring(name or "Default")
	if active then
		local existing = owners[name]
		owners[name] = info or {}
		owners[name].Since = existing and existing.Since or os.clock()
	else
		owners[name] = nil
	end
	refresh()
end

-- досдвигаем то, что появилось уже после начала катсцены; снимаем
-- «забытых» владельцев; гарантированно возвращаем всё, если владельцев нет.
task.spawn(function()
	while true do
		task.wait(0.25)
		local now = os.clock()
		local expired = false
		for name, info in owners do
			if now - (info.Since or now) > (info.MaxSeconds or MAX_OWNER_SECONDS) then
				warn(("[CinematicHud] «%s» держал HUD спрятанным дольше %d с - возвращаю"):format(name, info.MaxSeconds or MAX_OWNER_SECONDS))
				owners[name] = nil
				expired = true
			end
		end
		if expired then refresh() end
		-- v20.130: СТОРОЖ КАМЕРЫ. Камера в Scriptable дольше 4 с, а никто её
		-- не держит (нет катсцен, загрузки, шахты, окна престижа - атрибут
		-- PlayerGui.CameraHold) - возвращаем обычную камеру за игроком.
		-- CameraHold тоже не вечный: зависший атрибут (сцена упала) снимаем
		local hold = playerGui:GetAttribute("CameraHold")
		if hold ~= nil then
			if hold ~= cameraHoldName then cameraHoldName, cameraHoldSince = hold, now end
			if now - cameraHoldSince > (hold == "Prestige" and 900 or 120) then
				warn(("[CinematicHud] CameraHold «%s» завис - снимаю"):format(tostring(hold)))
				playerGui:SetAttribute("CameraHold", nil)
				cameraHoldName = nil
			end
		else
			cameraHoldName = nil
		end
		local camera = workspace.CurrentCamera
		local held = next(owners) ~= nil
			or player:GetAttribute("IntroActive") == true
			or player:GetAttribute("MineExpeditionActive") == true
			or playerGui:GetAttribute("CameraHold") ~= nil
		if camera and camera.CameraType == Enum.CameraType.Scriptable and not held then
			scriptableSince = scriptableSince or now
			if now - scriptableSince > 4 then
				scriptableSince = nil
				local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if humanoid then camera.CameraSubject = humanoid end
				camera.CameraType = Enum.CameraType.Custom
				warn("[CinematicHud] камера застряла в Scriptable - вернул обычную")
			end
		else
			scriptableSince = nil
		end
		if next(owners) then
			pcall(hideHud)
		else
			-- СТОРОЖ: владельцев нет, а что-то осталось за краем - вернуть
			if next(hiddenElements) then showHud() end
			for _, gui in playerGui:GetChildren() do
				if gui:IsA("ScreenGui") then
					for _, child in gui:GetChildren() do
						local home = child:IsA("GuiObject") and child:GetAttribute("CinematicHome")
						if typeof(home) == "UDim2" then
							child:SetAttribute("CinematicHome", nil)
							if typeof(child:GetAttribute("FocusHome")) ~= "UDim2" then
								TweenService:Create(child, EASING_IN, { Position = home }):Play()
							end
						end
					end
				end
			end
		end
	end
end)

-- Страховка: персонаж умер/переродился посреди катсцены - всё сбрасываем.
player.CharacterAdded:Connect(function()
	if next(owners) then
		table.clear(owners)
		refresh()
	end
end)

-- Создаём сигнал сами, а не ждём чужого: порядок запуска клиентских
-- скриптов не гарантирован, и ожидание могло бы не дождаться.
local signal = ReplicatedStorage.Shared:FindFirstChild("CinematicMode")
if not signal then
	signal = Instance.new("BindableEvent")
	signal.Name = "CinematicMode"
	signal.Parent = ReplicatedStorage.Shared
end
signal.Event:Connect(function(active, ownerName, maxSeconds)
	setOwner(ownerName or "Default", active == true, { MaxSeconds = tonumber(maxSeconds) })
end)

-- «ФОКУС» ДЛЯ ДИАЛОГОВ (обучение и т.п.): всё уезжает к краям, кроме
-- перечисленных экранов. Fire(true, {"HotbarUi"}, "Имя") / Fire(false, nil, "Имя").
-- Интерфейс Roblox не трогает.
local focus = ReplicatedStorage.Shared:FindFirstChild("HudFocus")
if not focus then
	focus = Instance.new("BindableEvent")
	focus.Name = "HudFocus"
	focus.Parent = ReplicatedStorage.Shared
end
focus.Event:Connect(function(active, keep, ownerName)
	setOwner("Focus:" .. tostring(ownerName or "Default"), active == true, {
		Focus = true, NoCore = true, Keep = type(keep) == "table" and keep or {}, MaxSeconds = 90,
	})
end)
