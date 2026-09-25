--------------------------------------------------------------------------------
-- ResponsiveUi (LocalScript) v20.16 — ОДНА система подгонки интерфейса под
-- устройство: версия для ПК и версия для телефона (см. shared/UiLayout и
-- Config.UiLayout).
--
-- Для каждого нашего ScreenGui:
--   • раскладка профиля (Config.UiLayout.Overrides) — позиции/направления;
--   • каждому верхнему элементу — UIScale = анимация × подгонка:
--       подгонка — база профиля (HUD на телефоне мельче) и «целиком на
--       экране»; анимация — то, что пишут скрипты окон (Pop/PanelScale/…):
--       их значение перехватывается и домножается, поэтому открывающие
--       анимации работают как раньше, а окно всё равно влезает.
-- Раньше каждый скрипт подгонял свои окна сам (DeviceScale, MobileScale,
-- AutoScale, ResponsiveScale…) и они спорили друг с другом — теперь только здесь.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UiLayout = require(ReplicatedStorage.Shared.UiLayout)
local UiRegistry = require(ReplicatedStorage.Shared.UiRegistry)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Экраны Roblox (сенсорное управление, чат и т.п.) не трогаем никогда.
local ROBLOX_SCREENS = { TouchGui = true, Freecam = true, Chat = true, BubbleChat = true, ControlGui = true, PlayerList = true }

local profile = UiLayout.Profile()
playerGui:SetAttribute("UiProfile", profile)

local entries = setmetatable({}, { __mode = "k" }) -- [element] = { Scale, Anim, Fit, LastWrite }

local function isOurs(gui)
	if not gui:IsA("ScreenGui") or ROBLOX_SCREENS[gui.Name] then return false end
	return UiRegistry.Entry(gui.Name) ~= nil or gui:GetAttribute("UiKitVersion") ~= nil or gui:GetAttribute("BuilderVersion") ~= nil
		or gui:GetAttribute("ResponsiveUi") == true
end

local function write(entry)
	local value = entry.Anim * entry.Fit
	if math.abs(entry.Scale.Scale - value) > 1e-4 then
		entry.LastWrite = value
		entry.Scale.Scale = value
	else
		entry.LastWrite = entry.Scale.Scale
	end
end

local function entryFor(element)
	local entry = entries[element]
	if entry and entry.Scale.Parent == element then return entry end
	local scale = element:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "ResponsiveScale"
		scale.Parent = element
	end
	entry = { Scale = scale, Anim = scale.Scale, Fit = 1, LastWrite = scale.Scale }
	entries[element] = entry
	-- Перехват: скрипт окна написал своё значение (анимация открытия и т.п.)
	-- → запоминаем его как «анимацию» и сразу домножаем на подгонку.
	scale:GetPropertyChangedSignal("Scale"):Connect(function()
		if math.abs(scale.Scale - entry.LastWrite) < 1e-4 then return end
		entry.Anim = entry.Fit > 0 and scale.Scale or 1
		write(entry)
	end)
	return entry
end

local function measuredNatural(element, entry)
	-- AutomaticSize: реальный размер без нашего масштаба.
	if element.AutomaticSize == Enum.AutomaticSize.None then return nil end
	local s = math.max(entry and entry.Scale.Scale or 1, 0.01)
	return element.AbsoluteSize / s
end

local function processScreen(gui)
	if not isOurs(gui) then return end
	UiLayout.ApplyOverrides(gui, profile)
	local bounds = gui.AbsoluteSize
	if bounds.X < 2 or bounds.Y < 2 then
		local camera = workspace.CurrentCamera
		bounds = camera and camera.ViewportSize or Vector2.new(1280, 720)
	end
	for _, element in gui:GetChildren() do
		if UiLayout.Manageable(gui.Name, element) then
			local entry = entryFor(element)
			local fit = UiLayout.FitScale(element, profile, bounds, measuredNatural(element, entry))
			if math.abs(fit - entry.Fit) > 0.005 then
				entry.Fit = fit
				write(entry)
			end
		end
	end
end

local function processAll()
	local newProfile = UiLayout.Profile()
	if newProfile ~= profile then
		profile = newProfile
		playerGui:SetAttribute("UiProfile", profile)
	end
	for _, gui in playerGui:GetChildren() do
		local ok, err = pcall(processScreen, gui)
		if not ok then warn("[ResponsiveUi] " .. gui.Name .. ": " .. tostring(err)) end
	end
end

-- Проходы: сразу, при смене размера экрана, при появлении экранов и
-- элементов (отложенно, пачкой) и страховочно раз в 1.5 сек.
local dirty = true
local function markDirty() dirty = true end

local function watchScreen(gui)
	if not gui:IsA("ScreenGui") then return end
	gui.ChildAdded:Connect(markDirty)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(markDirty)
	markDirty()
end
for _, gui in playerGui:GetChildren() do watchScreen(gui) end
playerGui.ChildAdded:Connect(watchScreen)

local function bindCamera()
	local camera = workspace.CurrentCamera
	if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(markDirty) end
	markDirty()
end
bindCamera()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)

local sinceFull = 0
RunService.Heartbeat:Connect(function(dt)
	sinceFull += dt
	if dirty or sinceFull >= 1.5 then
		dirty = false
		sinceFull = 0
		processAll()
	end
end)
