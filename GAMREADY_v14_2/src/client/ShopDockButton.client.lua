--------------------------------------------------------------------------------
-- ShopDockButton (LocalScript) v20.20 — кнопка магазина 🛒 первой в ряду
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

require(ReplicatedStorage.Shared.TopbarDock).Add(button, 1)

button.Activated:Connect(function()
	openRequest:Fire("Shop")
end)
