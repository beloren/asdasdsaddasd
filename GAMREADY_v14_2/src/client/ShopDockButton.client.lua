--------------------------------------------------------------------------------
-- ShopDockButton (LocalScript) v20.20 — кнопка магазина 🛒 (v20.131: последней в ряду, с «!»)
-- топбара (там, где раньше была кнопка квестов; квесты теперь в меню).
-- Открывает тот же магазин (геймпассы, паки), что и пункт SHOP в меню —
-- через общую шину CollectionMenuOpenRequest("Shop").
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiKit = require(ReplicatedStorage.Shared.UiKit)

local openRequest = ReplicatedStorage.Shared:FindFirstChild("CollectionMenuOpenRequest")
if not openRequest then
	openRequest = Instance.new("BindableEvent")
	openRequest.Name = "CollectionMenuOpenRequest"
	openRequest.Parent = ReplicatedStorage.Shared
end

-- v20.21: кнопка собирается билдером (StarterGui/TopbarDock/Row/ShopDockButton,
-- иконка — ImageLabel "Icon"). Нет в StarterGui — собираем так же кодом.
local dockGui = require(ReplicatedStorage.Shared.UiRegistry).Get("TopbarDock")
local button = dockGui and dockGui:FindFirstChild("ShopDockButton", true)
if not button then
	button = UiKit.PlateButton(nil, "ShopDockButton", "Round", { Size = UDim2.fromOffset(44, 44) })
	UiKit.ThemeIcon(button, "Icon", "Shop", "🛒", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.62, 0.62),
		ZIndex = 2,
	})
end

-- v20.131: магазин - ПОСЛЕДНИЙ в ряду (самое заметное место) и с «!»
require(ReplicatedStorage.Shared.TopbarDock).Add(button, 100)

local badge = button:FindFirstChild("AttentionBadge")
if not badge then
	badge = Instance.new("TextLabel")
	badge.Name = "AttentionBadge"
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.new(1, -2, 0, 4)
	badge.Size = UDim2.fromScale(0.5, 0.5)
	badge.BackgroundColor3 = Color3.fromRGB(255, 70, 70)
	badge.Text = "!"
	badge.TextScaled = true
	badge.Font = Enum.Font.FredokaOne
	badge.TextColor3 = Color3.new(1, 1, 1)
	badge.ZIndex = 20
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = badge
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(60, 10, 10)
	stroke.Thickness = 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = badge
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.12, 0)
	pad.PaddingBottom = UDim.new(0.12, 0)
	pad.Parent = badge
	badge.Parent = button
end
-- лёгкое «подпрыгивание», чтобы глаз цеплялся
task.spawn(function()
	local TweenService = game:GetService("TweenService")
	local scale = badge:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = badge
	while badge.Parent do
		TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.25 }):Play()
		task.wait(0.25)
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
		task.wait(1.6)
	end
end)

button.Activated:Connect(function()
	openRequest:Fire("Shop")
end)

-- v20.131: НПС магазина геймпассов (GamepassNpcService) открывает то же окно
task.spawn(function()
	local npcEvent = ReplicatedStorage.Shared:WaitForChild("GamepassNpcEvent", 60)
	if not npcEvent then return end
	npcEvent.OnClientEvent:Connect(function(action)
		if action == "Open" then openRequest:Fire("Shop") end
	end)
end)
