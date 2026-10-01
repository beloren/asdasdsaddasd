--------------------------------------------------------------------------------
-- CompassUI (v20.110) — КОМПАС: кнопка слева под MENU, по нажатию - круглая
-- мини-карта мира сверху. Метки: центр (торговцы), свой плот, свои острова,
-- другие плоты, ты сам (стрелка по взгляду камеры). Клик по метке или по
-- кнопке под картой - телепорт (сервер: CompassService, откат Config.Compass).
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
local okKit, UiKit = pcall(require, ReplicatedStorage.Shared.UiKit)

local function sfx(name)
	pcall(function() require(ReplicatedStorage.Shared.UiSfx).play(name) end)
end
local function style(label, kind)
	if okKit then pcall(UiKit.StyleText, label, kind or "Heading") end
end
local function stroke(parent, thickness, color)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 2
	s.Color = color or Color3.fromRGB(15, 12, 25)
	s.Parent = parent
	return s
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

-- КНОПКА (под книгой MENU, чуть правее)
local button = Instance.new("ImageButton")
button.Name = "CompassButton"
button.AutoButtonColor = false
button.BackgroundColor3 = Color3.fromRGB(35, 30, 55)
button.BackgroundTransparency = 0.15
button.AnchorPoint = Vector2.new(0, 0)
button.Image = (tonumber(cfg.ButtonImageId) or 0) > 0 and ("rbxassetid://" .. cfg.ButtonImageId) or ""
button.Parent = gui
Instance.new("UICorner", button).CornerRadius = UDim.new(1, 0)
stroke(button, 3, Color3.fromRGB(255, 215, 90))
local buttonEmoji = Instance.new("TextLabel")
buttonEmoji.BackgroundTransparency = 1
buttonEmoji.Size = UDim2.fromScale(0.8, 0.8)
buttonEmoji.Position = UDim2.fromScale(0.1, 0.08)
buttonEmoji.Text = "🧭"
buttonEmoji.TextScaled = true
buttonEmoji.Visible = button.Image == ""
buttonEmoji.Parent = button
local buttonLabel = Instance.new("TextLabel")
buttonLabel.BackgroundTransparency = 1
buttonLabel.AnchorPoint = Vector2.new(0.5, 0)
buttonLabel.Position = UDim2.new(0.5, 0, 1, -2)
buttonLabel.Size = UDim2.new(1.4, 0, 0, 18)
buttonLabel.Text = "MAP"
buttonLabel.TextScaled = true
buttonLabel.TextColor3 = Color3.new(1, 1, 1)
style(buttonLabel)
stroke(buttonLabel, 2)
buttonLabel.Parent = button
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

-- ОКНО КАРТЫ
local dim = Instance.new("TextButton")
dim.Name = "Dim"
dim.Text = ""
dim.AutoButtonColor = false
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 0.5
dim.Size = UDim2.fromScale(1, 1)
dim.Visible = false
dim.ZIndex = 10
dim.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.48)
panel.BackgroundTransparency = 1
panel.Visible = false
panel.ZIndex = 11
panel.Parent = gui
local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

local map = Instance.new("ImageLabel")
map.Name = "Map"
map.AnchorPoint = Vector2.new(0.5, 0)
map.Position = UDim2.new(0.5, 0, 0, 0)
map.BackgroundColor3 = Color3.fromRGB(40, 90, 130)
map.ScaleType = Enum.ScaleType.Crop
map.Image = (tonumber(cfg.MapImageId) or 0) > 0 and ("rbxassetid://" .. cfg.MapImageId) or ""
map.ClipsDescendants = true
map.ZIndex = 12
map.Parent = panel
Instance.new("UICorner", map).CornerRadius = UDim.new(1, 0)
stroke(map, 6, Color3.fromRGB(255, 215, 90))
local water = Instance.new("UIGradient")
water.Color = ColorSequence.new(Color3.fromRGB(90, 170, 220), Color3.fromRGB(30, 80, 140))
water.Rotation = 90
water.Enabled = map.Image == ""
water.Parent = map

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.AnchorPoint = Vector2.new(0.5, 1)
title.Position = UDim2.new(0.5, 0, 0, -4)
title.Size = UDim2.new(1, 0, 0, 34)
title.Text = "🧭 WORLD MAP"
title.TextScaled = true
title.TextColor3 = Color3.new(1, 1, 1)
title.ZIndex = 13
style(title)
stroke(title, 3)
title.Parent = panel

local closeButton = Instance.new("TextButton")
closeButton.Name = "Close"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, 6, 0, -6)
closeButton.Size = UDim2.fromOffset(44, 44)
closeButton.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
closeButton.Text = "X"
closeButton.TextScaled = true
closeButton.TextColor3 = Color3.new(1, 1, 1)
closeButton.ZIndex = 20
style(closeButton)
Instance.new("UICorner", closeButton).CornerRadius = UDim.new(1, 0)
stroke(closeButton, 3)
closeButton.Parent = panel

local list = Instance.new("Frame")
list.Name = "Places"
list.AnchorPoint = Vector2.new(0.5, 0)
list.BackgroundTransparency = 1
list.ZIndex = 12
list.Parent = panel
local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Horizontal
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.Wraps = true
listLayout.Padding = UDim.new(0, 8)
listLayout.Parent = list

local cooldownLabel = Instance.new("TextLabel")
cooldownLabel.BackgroundTransparency = 1
cooldownLabel.AnchorPoint = Vector2.new(0.5, 0)
cooldownLabel.Size = UDim2.new(1, 0, 0, 24)
cooldownLabel.Text = ""
cooldownLabel.TextScaled = true
cooldownLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
cooldownLabel.ZIndex = 13
style(cooldownLabel)
stroke(cooldownLabel, 2)
cooldownLabel.Parent = panel

local fade = Instance.new("Frame")
fade.Name = "Fade"
fade.BackgroundColor3 = Color3.new(0, 0, 0)
fade.BackgroundTransparency = 1
fade.Size = UDim2.fromScale(1, 1)
fade.ZIndex = 50
fade.Visible = false
fade.Parent = gui

local function layout()
	local size = isPhone() and (cfg.MapSizePhone or 290) or (cfg.MapSizePC or 440)
	local camera = workspace.CurrentCamera
	local view = camera and camera.ViewportSize or Vector2.new(1280, 720)
	size = math.min(size, view.Y - 220, view.X - 40)
	panel.Size = UDim2.fromOffset(size, size + 120)
	map.Size = UDim2.fromOffset(size, size)
	list.Position = UDim2.new(0.5, 0, 0, size + 10)
	list.Size = UDim2.new(1, 80, 0, 90)
	cooldownLabel.Position = UDim2.new(0.5, 0, 0, size + 104)
end
layout()

--------------------------------------------------------------------------------
-- ГРАНИЦЫ КАРТЫ (мир → картинка)
--------------------------------------------------------------------------------
local destinations = {}
local cooldownUntil = 0
local bounds = nil -- { MinX, MinZ, MaxX, MaxZ }

local function computeBounds()
	local minPart = workspace:FindFirstChild("CompassMapMin", true)
	local maxPart = workspace:FindFirstChild("CompassMapMax", true)
	if minPart and maxPart and minPart:IsA("BasePart") and maxPart:IsA("BasePart") then
		return {
			MinX = math.min(minPart.Position.X, maxPart.Position.X), MinZ = math.min(minPart.Position.Z, maxPart.Position.Z),
			MaxX = math.max(minPart.Position.X, maxPart.Position.X), MaxZ = math.max(minPart.Position.Z, maxPart.Position.Z),
		}
	end
	local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
	local function add(p)
		minX, minZ = math.min(minX, p.X), math.min(minZ, p.Z)
		maxX, maxZ = math.max(maxX, p.X), math.max(maxZ, p.Z)
	end
	for _, dest in destinations do add(dest.Position) end
	local plots = workspace:FindFirstChild("Plots")
	for _, pad in plots and plots:GetChildren() or {} do
		local ok, cf = pcall(function() return pad:IsA("Model") and pad:GetPivot() or pad.CFrame end)
		if ok and cf then add(cf.Position) end
	end
	if minX == math.huge then return nil end
	-- квадрат с запасом
	local cx, cz = (minX + maxX) / 2, (minZ + maxZ) / 2
	local half = math.max(maxX - minX, maxZ - minZ) / 2 + 60
	return { MinX = cx - half, MinZ = cz - half, MaxX = cx + half, MaxZ = cz + half }
end

local function toMap(position)
	if not bounds then return UDim2.fromScale(0.5, 0.5) end
	local u = (position.X - bounds.MinX) / math.max(1, bounds.MaxX - bounds.MinX)
	local v = (position.Z - bounds.MinZ) / math.max(1, bounds.MaxZ - bounds.MinZ)
	return UDim2.fromScale(math.clamp(u, 0.03, 0.97), math.clamp(v, 0.03, 0.97))
end

--------------------------------------------------------------------------------
-- МЕТКИ И КНОПКИ
--------------------------------------------------------------------------------
local markers = Instance.new("Folder")
markers.Name = "Markers"
markers.Parent = map

local selfArrow = Instance.new("TextLabel")
selfArrow.Name = "You"
selfArrow.AnchorPoint = Vector2.new(0.5, 0.5)
selfArrow.Size = UDim2.fromOffset(26, 26)
selfArrow.BackgroundTransparency = 1
selfArrow.Text = "▲"
selfArrow.TextScaled = true
selfArrow.TextColor3 = Color3.fromRGB(255, 240, 80)
selfArrow.ZIndex = 18
selfArrow.Parent = map
if okKit and UiKit.GlyphToShape then pcall(UiKit.GlyphToShape, selfArrow, "ChevronUp") end -- без «квадратика» вместо ▲

local teleport -- forward

local function marker(dest)
	local m = Instance.new("TextButton")
	m.Name = "Marker_" .. dest.Id
	m.AnchorPoint = Vector2.new(0.5, 0.5)
	m.Position = toMap(dest.Position)
	m.Size = UDim2.fromOffset(40, 40)
	m.BackgroundColor3 = dest.Id == "Raft" and Color3.fromRGB(80, 200, 110) or (dest.Id == "Center" and Color3.fromRGB(255, 190, 60) or Color3.fromRGB(120, 170, 255))
	m.Text = dest.Icon or "•"
	m.TextScaled = true
	m.ZIndex = 16
	Instance.new("UICorner", m).CornerRadius = UDim.new(1, 0)
	stroke(m, 3)
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.Position = UDim2.new(0.5, 0, 1, 0)
	name.Size = UDim2.fromOffset(110, 18)
	name.Text = dest.Name or dest.Id
	name.TextScaled = true
	name.TextColor3 = Color3.new(1, 1, 1)
	name.ZIndex = 17
	style(name)
	stroke(name, 2)
	name.Parent = m
	m.Parent = markers
	m.Activated:Connect(function() teleport(dest.Id) end)
	TutorialTarget.Mark(m, "CompassMarker:" .. dest.Id)
	return m
end

local function placeButtonFor(dest)
	local b = Instance.new("TextButton")
	b.Name = "Go_" .. dest.Id
	b.Size = UDim2.fromOffset(isPhone() and 120 or 150, 40)
	b.BackgroundColor3 = dest.Id == "Raft" and Color3.fromRGB(70, 180, 95) or (dest.Id == "Center" and Color3.fromRGB(230, 160, 40) or Color3.fromRGB(90, 140, 230))
	b.Text = ("%s %s"):format(dest.Icon or "", (dest.Name or dest.Id):upper())
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.ZIndex = 13
	style(b)
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)
	stroke(b, 3)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 6), UDim.new(0, 6)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 4), UDim.new(0, 4)
	pad.Parent = b
	b.Parent = list
	b.Activated:Connect(function() teleport(dest.Id) end)
	TutorialTarget.Mark(b, "Compass:" .. dest.Id)
	return b
end

local function rebuild()
	for _, child in markers:GetChildren() do child:Destroy() end
	for _, child in list:GetChildren() do
		if child:IsA("GuiButton") then child:Destroy() end
	end
	bounds = computeBounds()
	-- другие плоты - точки
	local plots = workspace:FindFirstChild("Plots")
	for _, pad in plots and plots:GetChildren() or {} do
		local ok, cf = pcall(function() return pad:IsA("Model") and pad:GetPivot() or pad.CFrame end)
		if ok and cf then
			local dot = Instance.new("Frame")
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Position = toMap(cf.Position)
			dot.Size = UDim2.fromOffset(14, 14)
			dot.BackgroundColor3 = Color3.fromRGB(150, 110, 70)
			dot.ZIndex = 14
			Instance.new("UICorner", dot).CornerRadius = UDim.new(0, 3)
			stroke(dot, 2)
			dot.Parent = markers
		end
	end
	for _, dest in destinations do
		marker(dest)
		placeButtonFor(dest)
	end
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
		refreshInfo()
		layout()
		dim.Visible = true
		panel.Visible = true
		panelScale.Scale = 0.6
		TweenService:Create(panelScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		sfx("UiMenuOpen")
		local tutorialRemote = ReplicatedStorage.Shared:FindFirstChild("TutorialActionEvent")
		if tutorialRemote then tutorialRemote:FireServer("UiFlag", "CompassOpened") end
	else
		if not panel.Visible then return end
		sfx("UiMenuClose")
		dim.Visible = false
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
closeButton.Activated:Connect(function() setOpen(false) end)
dim.Activated:Connect(function() setOpen(false) end)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.M then setOpen(not panel.Visible) end
	if input.KeyCode == Enum.KeyCode.Escape and panel.Visible then setOpen(false) end
end)

-- живая стрелка игрока и отсчёт отката
RunService.RenderStepped:Connect(function()
	local left = cooldownUntil - os.clock()
	if left > 0 then
		button.BackgroundColor3 = Color3.fromRGB(70, 60, 80)
		buttonLabel.Text = ("%d"):format(math.ceil(left))
	else
		button.BackgroundColor3 = Color3.fromRGB(35, 30, 55)
		buttonLabel.Text = "MAP"
	end
	if not panel.Visible then return end
	cooldownLabel.Text = left > 0 and ("Teleport ready in %ds"):format(math.ceil(left)) or "Tap a place to teleport"
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if hrp and bounds then
		selfArrow.Visible = true
		selfArrow.Position = toMap(hrp.Position)
		local look = camera and camera.CFrame.LookVector or hrp.CFrame.LookVector
		selfArrow.Rotation = math.deg(math.atan2(look.X, -look.Z))
	else
		selfArrow.Visible = false
	end
end)

local camera = workspace.CurrentCamera
if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(function() placeButton(); layout() end) end
