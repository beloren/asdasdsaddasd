--------------------------------------------------------------------------------
-- CompassUI (v20.125) — КОМПАС-ТЕЛЕПОРТ: кнопка слева под MENU, по нажатию -
-- обычное окно-меню с карточками мест (Town / Ore Merchant, свой плот, свои
-- острова). Клик по карточке - телепорт (сервер: CompassService, откат
-- Config.Compass.Cooldown). Карты больше нет.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local cfg = Config.Compass or {}
if cfg.Enabled == false then return end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage.Shared:WaitForChild("CompassRequest", 30)
if not remote then return end
local TutorialTarget = require(ReplicatedStorage.Shared.TutorialTarget)
local UiKit = require(ReplicatedStorage.Shared.UiKit)

local function sfx(name)
	pcall(function() require(ReplicatedStorage.Shared.UiSfx).play(name) end)
end
local function isPhone()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local gui = Instance.new("ScreenGui")
gui.Name = "CompassUi"
gui.ResetOnSpawn = false
gui.DisplayOrder = 96
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)
gui.Parent = playerGui

--------------------------------------------------------------------------------
-- КНОПКА (под книгой MENU)
--------------------------------------------------------------------------------
local button = Instance.new("ImageButton")
button.Name = "CompassButton"
button.AutoButtonColor = false
button.BackgroundColor3 = Color3.fromRGB(35, 30, 55)
button.BackgroundTransparency = 0.15
button.Image = (tonumber(cfg.ButtonImageId) or 0) > 0 and ("rbxassetid://" .. cfg.ButtonImageId) or ""
button.Parent = gui
Instance.new("UICorner", button).CornerRadius = UDim.new(1, 0)
local buttonStroke = Instance.new("UIStroke")
buttonStroke.Thickness = 3
buttonStroke.Color = Color3.fromRGB(255, 215, 90)
buttonStroke.Parent = button
local buttonEmoji = Instance.new("TextLabel")
buttonEmoji.BackgroundTransparency = 1
buttonEmoji.Size = UDim2.fromScale(0.8, 0.8)
buttonEmoji.Position = UDim2.fromScale(0.1, 0.08)
buttonEmoji.Text = "🧭"
buttonEmoji.TextScaled = true
buttonEmoji.Visible = button.Image == ""
buttonEmoji.Parent = button
local buttonLabel = UiKit.Text(button, "Label", "TRAVEL", {
	_Style = "Heading",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 1, -2),
	Size = UDim2.new(1.5, 0, 0, 18),
})
buttonLabel.TextScaled = true
TutorialTarget.Mark(button, "Compass")

local function placeButton()
	if isPhone() then
		button.Size = UDim2.fromOffset(46, 46)
		button.Position = UDim2.new(0, 24, 0.5, 34)
	else
		button.Size = UDim2.fromOffset(58, 58)
		button.Position = UDim2.new(0, 34, 0.5, 26)
	end
end
placeButton()

--------------------------------------------------------------------------------
-- ОКНО-МЕНЮ С КАРТОЧКАМИ МЕСТ
--------------------------------------------------------------------------------
local dimmer = UiKit.Dimmer(gui, { ZIndex = 10 })
local panel, parts = UiKit.Window(gui, "Panel", {
	Title = "TELEPORT",
	Accent = "Gold",
	Size = UDim2.fromOffset(640, 430),
	Position = UDim2.fromScale(0.5, 0.5),
	Scroll = true,
	ZIndex = 11,
})
panel.Visible = false
local panelScale = UiKit.Scale(panel, "ResponsiveScale", 1)
local body = parts.Body
local grid = UiKit.Grid(body, UDim2.fromOffset(180, 170), UDim2.fromOffset(14, 14))
grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
pcall(function() body.AutomaticCanvasSize = Enum.AutomaticSize.Y end)
pcall(function() body.CanvasSize = UDim2.new() end)

local cooldownLabel = UiKit.Text(panel, "Cooldown", "", {
	_Style = "Body",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 1, 6),
	Size = UDim2.new(1, 0, 0, 26),
	TextColor3 = Color3.fromRGB(255, 220, 120),
})
cooldownLabel.TextScaled = true

local fade = Instance.new("Frame")
fade.Name = "Fade"
fade.BackgroundColor3 = Color3.new(0, 0, 0)
fade.BackgroundTransparency = 1
fade.Size = UDim2.fromScale(1, 1)
fade.ZIndex = 50
fade.Visible = false
fade.Parent = gui

local function layout()
	local camera = workspace.CurrentCamera
	local view = camera and camera.ViewportSize or Vector2.new(1280, 720)
	panelScale.Scale = math.clamp(math.min((view.X - 30) / 640, (view.Y - 90) / 430), 0.45, 1)
end
layout()

local ACCENTS = { Center = "Gold", Raft = "Green" }
local SUBTITLES = { Center = "In front of the Ore Merchant", Raft = "Your base" }

local destinations = {}
local cooldownUntil = 0
local teleport -- forward

local function card(dest, order)
	local accent = ACCENTS[dest.Id] or "Blue"
	local c = UiKit.CardButton(body, "Place_" .. dest.Id, accent, { LayoutOrder = order, ZIndex = 12 })
	local icon = UiKit.Text(c, "Icon", dest.Icon or "📍", {
		_Style = "Heading",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.new(1, -20, 0, 62),
		ZIndex = 13,
	})
	icon.TextScaled = true
	local name = UiKit.Text(c, "PlaceName", (dest.Name or dest.Id):upper(), {
		_Style = "Heading",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 78),
		Size = UDim2.new(1, -16, 0, 30),
		ZIndex = 13,
	})
	name.TextScaled = true
	local sub = UiKit.Text(c, "Subtitle", SUBTITLES[dest.Id] or "Your island", {
		_Style = "Body",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 110),
		Size = UDim2.new(1, -16, 0, 18),
		TextColor3 = Color3.fromRGB(210, 210, 225),
		ZIndex = 13,
	})
	sub.TextScaled = true
	local go = UiKit.Button(c, "Go", "GO", "Green", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -24, 0, 30),
		ZIndex = 13,
	})
	go.Active = false -- нажатие ловит вся карточка
	c.Activated:Connect(function() teleport(dest.Id) end)
	TutorialTarget.Mark(c, "Compass:" .. dest.Id)
	c:SetAttribute("WorldPos", dest.Position) -- обучение выбирает место ближе к цели
	return c
end

local function rebuild()
	for _, child in body:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	for order, dest in destinations do card(dest, order) end
end

local function refreshInfo()
	local ok, info = pcall(function() return remote:InvokeServer("Info") end)
	if ok and type(info) == "table" then
		destinations = info.Destinations or {}
		cooldownUntil = os.clock() + (tonumber(info.CooldownLeft) or 0)
		rebuild()
	end
end

local function setOpen(open)
	if open then
		layout()
		dimmer.Visible = true
		panel.Visible = true
		local base = panelScale.Scale
		panelScale.Scale = base * 0.7
		TweenService:Create(panelScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = base }):Play()
		sfx("UiMenuOpen")
		task.spawn(refreshInfo)
		local tutorialRemote = ReplicatedStorage.Shared:FindFirstChild("TutorialActionEvent")
		if tutorialRemote then tutorialRemote:FireServer("UiFlag", "CompassOpened") end
	else
		if not panel.Visible then return end
		sfx("UiMenuClose")
		dimmer.Visible = false
		panel.Visible = false
	end
end

local busy = false
teleport = function(destId)
	if busy then return end
	local left = cooldownUntil - os.clock()
	if left > 0 then
		sfx("UiError")
		cooldownLabel.Text = ("Wait %ds"):format(math.ceil(left))
		return
	end
	busy = true
	fade.Visible = true
	local inTween = TweenService:Create(fade, TweenInfo.new(0.18), { BackgroundTransparency = 0 })
	inTween:Play()
	inTween.Completed:Wait()
	local ok, result, extra = pcall(function() return remote:InvokeServer("Teleport", destId) end)
	if ok and result == true then
		sfx("UiConfirm")
		cooldownUntil = os.clock() + (tonumber(extra) or cfg.Cooldown or 5)
		setOpen(false)
	else
		sfx("UiError")
		cooldownLabel.Text = tostring(ok and extra or "Try again")
	end
	local outTween = TweenService:Create(fade, TweenInfo.new(0.3), { BackgroundTransparency = 1 })
	outTween:Play()
	outTween.Completed:Wait()
	fade.Visible = false
	busy = false
end

button.Activated:Connect(function()
	sfx("UiButtonClick")
	setOpen(not panel.Visible)
end)
if parts.CloseButton then parts.CloseButton.Activated:Connect(function() setOpen(false) end) end
dimmer.Activated:Connect(function() setOpen(false) end)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.M then setOpen(not panel.Visible) end
	if input.KeyCode == Enum.KeyCode.Escape and panel.Visible then setOpen(false) end
end)

-- отсчёт отката на кнопке и в окне
RunService.RenderStepped:Connect(function()
	local left = cooldownUntil - os.clock()
	if left > 0 then
		button.BackgroundColor3 = Color3.fromRGB(70, 60, 80)
		buttonLabel.Text = ("%d"):format(math.ceil(left))
	else
		button.BackgroundColor3 = Color3.fromRGB(35, 30, 55)
		buttonLabel.Text = "TRAVEL"
	end
	if panel.Visible then
		cooldownLabel.Text = left > 0 and ("Teleport ready in %ds"):format(math.ceil(left)) or "Pick a place to teleport"
	end
end)

local camera = workspace.CurrentCamera
if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(function() placeButton(); layout() end) end
