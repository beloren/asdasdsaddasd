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
local CORE_TYPES = { Enum.CoreGuiType.Chat, Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.EmotesMenu, Enum.CoreGuiType.Health }
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
		if enabled then pcall(StarterGui.SetCoreGuiEnabled, StarterGui, kind, true) end
	end
	coreWasEnabled = nil
end

task.spawn(function()
	while true do
		task.wait(0.25)
		if depth > 0 then pcall(hideHud) end
	end
end)

local realDepth = 0 -- v20.118: только настоящие катсцены (без HudFocus) - для атрибута CinematicActive
local function setCinematic(active, noCore, isFocus)
	if not isFocus then realDepth = math.max(0, realDepth + (active and 1 or -1)) end
	if active then
		depth += 1
		if depth == 1 then
			hideHud()
			if not noCore then hideCore() end
		end
	else
		depth = math.max(0, depth - 1)
		if depth == 0 then
			showHud()
			restoreCore()
		end
	end
	playerGui:SetAttribute("CinematicActive", realDepth > 0)
end

-- Страховка: если персонаж умер/переродился посреди катсцены, счётчик мог
-- остаться ненулевым, и HUD не вернулся бы никогда. Респавн сбрасывает всё.
player.CharacterAdded:Connect(function()
	if depth > 0 then
		depth = 0
		realDepth = 0
		table.clear(dynamicKeep)
		playerGui:SetAttribute("CinematicActive", false)
		showHud()
		restoreCore()
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
signal.Event:Connect(function(active)
	setCinematic(active == true)
end)

-- v20.118: «ФОКУС» ДЛЯ ДИАЛОГОВ (обучение и т.п.): всё уезжает к краям,
-- кроме перечисленных экранов (например хотбар). Fire(true, {"HotbarUi"}) /
-- Fire(false, {"HotbarUi"}) - тот же список при снятии. Интерфейс Roblox не трогает.
local focus = ReplicatedStorage.Shared:FindFirstChild("HudFocus")
if not focus then
	focus = Instance.new("BindableEvent")
	focus.Name = "HudFocus"
	focus.Parent = ReplicatedStorage.Shared
end
focus.Event:Connect(function(active, keep)
	keep = type(keep) == "table" and keep or {}
	if active == true then
		for _, name in keep do dynamicKeep[name] = (dynamicKeep[name] or 0) + 1 end
		setCinematic(true, true, true)
	else
		for _, name in keep do
			dynamicKeep[name] = (dynamicKeep[name] or 1) - 1
			if dynamicKeep[name] <= 0 then dynamicKeep[name] = nil end
		end
		setCinematic(false, nil, true)
	end
end)
