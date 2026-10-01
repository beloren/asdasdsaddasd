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

-- v20.126: весь вид - билдер UiBuilders.CompassUi (StarterGui/CompassUi,
-- правится в Studio). Здесь только логика.
local gui = require(ReplicatedStorage.Shared.UiRegistry).Get("CompassUi")
if not gui then return end
gui.Enabled = true

local button = gui:WaitForChild("CompassButton")
local buttonIcon = button:FindFirstChild("Icon")
local buttonLabel = button:WaitForChild("Label")
if buttonIcon and (tonumber(cfg.ButtonImageId) or 0) > 0 and buttonIcon.Image == "" then
	buttonIcon.Image = "rbxassetid://" .. cfg.ButtonImageId
end
if buttonIcon and buttonIcon:FindFirstChild("Emoji") then buttonIcon.Emoji.Visible = buttonIcon.Image == "" end
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

local dimmer = gui:WaitForChild("Dimmer")
local panel = gui:WaitForChild("Panel")
panel.Visible = false
dimmer.Visible = false
local panelScale = panel:FindFirstChild("ResponsiveScale") or UiKit.Scale(panel, "ResponsiveScale", 1)
local body = panel:WaitForChild("Places")
local cardTemplate = panel:WaitForChild("Templates"):WaitForChild("PlaceCardTemplate")
local closeButton = panel:FindFirstChild("CloseButton", true)
local cooldownLabel = panel:WaitForChild("Cooldown")
local fade = gui:WaitForChild("Fade")
local BASE_W = panel.Size.X.Offset > 0 and panel.Size.X.Offset or 640
local BASE_H = panel.Size.Y.Offset > 0 and panel.Size.Y.Offset or 430

local function layout()
	local camera = workspace.CurrentCamera
	local view = camera and camera.ViewportSize or Vector2.new(1280, 720)
	panelScale.Scale = math.clamp(math.min((view.X - 30) / BASE_W, (view.Y - 90) / BASE_H), 0.45, 1)
end
layout()

local ACCENTS = { Center = "Gold", Raft = "Green" }
local SUBTITLES = { Center = "In front of the Ore Merchant", Raft = "Your base" }

local destinations = {}
local cooldownUntil = 0
local teleport -- forward

local function card(dest, order)
	local c = cardTemplate:Clone()
	c.Name = "Place_" .. dest.Id
	c.LayoutOrder = order
	c.Visible = true
	-- рамка цветом места (вид карточки - из билдера, своё не перетираем)
	local skinStroke = c:FindFirstChild("SkinStroke")
	if skinStroke and c.Image == "" then skinStroke.Color = UiKit.Accent(ACCENTS[dest.Id] or "Blue").Main end
	local icon = c:FindFirstChild("Icon")
	local images = cfg.PlaceImages or {}
	local imageId = tonumber(images[dest.Id] or images[(dest.Id:match("^Island:(%w+)$") or "")]) or 0
	if icon then
		if imageId > 0 then icon.Image = "rbxassetid://" .. imageId end
		local emoji = icon:FindFirstChild("Emoji")
		if emoji then
			emoji.Text = dest.Icon or "📍"
			emoji.Visible = icon.Image == ""
		end
	end
	local name = c:FindFirstChild("PlaceName")
	if name then name.Text = (dest.Name or dest.Id):upper() end
	local sub = c:FindFirstChild("Subtitle")
	if sub then sub.Text = SUBTITLES[dest.Id] or "Your island" end
	local go = c:FindFirstChild("Go")
	if go then go.Active = false end -- нажатие ловит вся карточка
	c.Parent = body
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
if closeButton then closeButton.Activated:Connect(function() setOpen(false) end) end
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
