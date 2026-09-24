--------------------------------------------------------------------------------
-- SocialHud (LocalScript) v16 — маленькая кнопка 🎁 для наград «группа» и
-- «избранное». Видна, пока хоть что-то не забрано. Клик — два пункта:
-- 👥 группа (+10% навсегда + сундук) и ⭐ избранное. Сами окна —
-- GroupRewardUI / LikeRewardUI (открываются их BindableEvent'ами Preview*).
-- Никаких автопоказов: предложения в удачный момент шлёт SocialOfferService.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local groupPending = Config.GroupReward and Config.GroupReward.Enabled and (tonumber(Config.GroupReward.GroupId) or 0) ~= 0
local favoritePending = Config.LikeReward and Config.LikeReward.Enabled

local gui = Instance.new("ScreenGui")
gui.Name = "SocialHud"
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
gui.Parent = playerGui

local button = Instance.new("TextButton")
button.Name = "Gift"
button.Size = UDim2.fromOffset(56, 56)
button.Position = (Config.SocialOffers and Config.SocialOffers.HudPosition) or UDim2.new(0, 12, 0.36, 0)
button.BackgroundColor3 = Color3.fromRGB(255, 190, 60)
button.Text = "👥"
button.TextScaled = true
button.AutoButtonColor = false
button.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(1, 0)
corner.Parent = button
local stroke = Instance.new("UIStroke")
stroke.Thickness = 3
stroke.Color = Color3.fromRGB(20, 16, 30)
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
stroke.Parent = button
local dot = Instance.new("Frame")
dot.Size = UDim2.fromOffset(14, 14)
dot.Position = UDim2.new(1, -12, 0, -2)
dot.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
dot.Parent = button
local dotCorner = Instance.new("UICorner")
dotCorner.CornerRadius = UDim.new(1, 0)
dotCorner.Parent = dot
local scale = Instance.new("UIScale")
scale.Parent = button
-- v19.4: кнопка — в ряд со штатными кнопками Roblox в топбаре.
require(ReplicatedStorage.Shared.TopbarDock).Add(button, 3)

local menu = Instance.new("Frame")
menu.Name = "Menu"
menu.Visible = false
menu.BackgroundTransparency = 1
menu.Position = UDim2.new(0, 0, 1, 10) -- v19.4: меню открывается ВНИЗ от кнопки в топбаре
menu.Size = UDim2.fromOffset(210, 100)
menu.Parent = button
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.Parent = menu

local function menuButton(text, color, order, onClick)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 44)
	b.BackgroundColor3 = color
	b.Font = Enum.Font.FredokaOne
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	b.LayoutOrder = order
	b.Parent = menu
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = b
	local s = Instance.new("UIStroke")
	s.Thickness = 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = b
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 8)
	p.PaddingRight = UDim.new(0, 8)
	p.Parent = b
	b.Activated:Connect(function()
		menu.Visible = false
		onClick()
	end)
	return b
end

local function fire(name)
	local event = playerGui:FindFirstChild(name)
	if event and event:IsA("BindableEvent") then event:Fire() end
end

local bonus = math.floor(((Config.GroupReward and Config.GroupReward.IncomeBonus) or 0) * 100 + 0.5)
local groupButton = menuButton(("👥 GROUP: +%d%% CASH"):format(bonus), Color3.fromRGB(70, 130, 220), 1, function() fire("PreviewGroupReward") end)
local favoriteButton = menuButton("⭐ FAVORITE: FREE SKIN", Color3.fromRGB(220, 90, 120), 2, function() fire("PreviewLikeReward") end)

local function refresh()
	groupButton.Visible = groupPending == true
	favoriteButton.Visible = favoritePending == true
	button.Visible = groupPending == true or favoritePending == true
	if not button.Visible then menu.Visible = false end
end
refresh()

button.Activated:Connect(function()
	scale.Scale = 0.85
	TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	dot.Visible = false
	menu.Visible = not menu.Visible
end)

-- Слушаем те же State, что и окна наград.
task.spawn(function()
	local groupRemote = ReplicatedStorage.Shared:WaitForChild("GroupRewardRequest", 60)
	if groupRemote then
		groupRemote.OnClientEvent:Connect(function(action, payload)
			if action == "State" and type(payload) == "table" then
				groupPending = not (payload.Claimed and payload.Member)
				refresh()
			end
		end)
	end
end)
task.spawn(function()
	local likeRemote = ReplicatedStorage.Shared:WaitForChild("LikeRewardRequest", 60)
	if likeRemote then
		likeRemote.OnClientEvent:Connect(function(action, payload)
			if action == "State" and type(payload) == "table" then
				favoritePending = payload.Claimed ~= true
				refresh()
			end
		end)
	end
end)
