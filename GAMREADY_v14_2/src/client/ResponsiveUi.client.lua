--------------------------------------------------------------------------------
-- ResponsiveUi (LocalScript) v20.18 — ТЕЛЕФОННАЯ ВЕРСИЯ ИНТЕРФЕЙСА.
--
-- Работает ТОЛЬКО на телефоне (профиль "Phone", см. shared/UiLayout). На ПК и
-- планшете не делает ничего — интерфейс ровно такой, как его собрали.
--
-- На телефоне:
--   1) раскладка Config.UiLayout.Overrides.Phone — позиции/направления;
--   2) масштаб «влезает целиком + HUD компактнее» — ТОЛЬКО для верхних
--      элементов, у которых НЕТ своего UIScale (свои UIScale у окон и кнопок
--      ведут их собственные скрипты: анимации, наведение, подгонка). Мы
--      создаём один UIScale "PhoneFitScale" и пишем в него только сами —
--      без подписок на изменения, поэтому ни с кем не спорим.
-- v20.16 перехватывала чужие UIScale — это давало «Exponential deferred
-- event growth», дёрганье и пропажу HUD. Убрано полностью.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UiLayout = require(ReplicatedStorage.Shared.UiLayout)
local UiRegistry = require(ReplicatedStorage.Shared.UiRegistry)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local OWN_SCALE = "PhoneFitScale"
local ROBLOX_SCREENS = { TouchGui = true, Freecam = true, Chat = true, BubbleChat = true, ControlGui = true, PlayerList = true }

local function isOurs(gui)
	if not gui:IsA("ScreenGui") or ROBLOX_SCREENS[gui.Name] then return false end
	return UiRegistry.Entry(gui.Name) ~= nil or gui:GetAttribute("UiKitVersion") ~= nil or gui:GetAttribute("BuilderVersion") ~= nil
end

-- Наш UIScale у элемента, если других UIScale у него нет. Появился чужой —
-- свой убираем (два UIScale на одном объекте Roblox не складывает).
local function ownScaleFor(element, create)
	local ours, foreign = nil, false
	for _, child in element:GetChildren() do
		if child:IsA("UIScale") then
			if child.Name == OWN_SCALE then ours = child else foreign = true end
		end
	end
	if foreign then
		if ours then ours:Destroy() end
		return nil
	end
	if not ours and create then
		ours = Instance.new("UIScale")
		ours.Name = OWN_SCALE
		ours.Parent = element
	end
	return ours
end

local function clearScreen(gui)
	for _, element in gui:GetChildren() do
		local ours = element:FindFirstChild(OWN_SCALE)
		if ours then ours:Destroy() end
	end
end

local function processScreen(gui, profile)
	if not isOurs(gui) then return end
	if profile ~= "Phone" then
		clearScreen(gui)
		return
	end
	-- Во время катсцены HUD уведён за экран (CinematicHud) — раскладку
	-- применим, когда он вернётся.
	if playerGui:GetAttribute("CinematicActive") ~= true then
		UiLayout.ApplyOverrides(gui, profile)
	end
	local bounds = gui.AbsoluteSize
	if bounds.X < 2 or bounds.Y < 2 then
		local camera = workspace.CurrentCamera
		bounds = camera and camera.ViewportSize or Vector2.new(844, 390)
	end
	for _, element in gui:GetChildren() do
		if UiLayout.Manageable(gui.Name, element) and not element:IsA("GuiButton") then
			local scale = ownScaleFor(element, true)
			if scale then
				local fit = UiLayout.FitScale(element, profile, bounds)
				if math.abs(scale.Scale - fit) > 0.005 then
					scale.Scale = fit
				end
			end
		end
	end
end

local function processAll()
	local profile = UiLayout.Profile()
	playerGui:SetAttribute("UiProfile", profile)
	for _, gui in playerGui:GetChildren() do
		local ok, err = pcall(processScreen, gui, profile)
		if not ok then warn("[ResponsiveUi] " .. gui.Name .. ": " .. tostring(err)) end
	end
end

local dirty = true
local function markDirty() dirty = true end
playerGui.ChildAdded:Connect(markDirty)
local function bindCamera()
	local camera = workspace.CurrentCamera
	if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(markDirty) end
	markDirty()
end
bindCamera()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)

-- Проход по флагу и страховочно раз в 2 сек (элементы экранов появляются
-- постепенно). Никаких подписок на UIScale — только наши записи.
local sinceFull = 0
RunService.Heartbeat:Connect(function(dt)
	sinceFull += dt
	if dirty or sinceFull >= 2 then
		dirty = false
		sinceFull = 0
		processAll()
	end
end)
