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

local button = Instance.new("ImageButton")
button.Name = "ShopDockButton"
button.AutoButtonColor = false
button.Image = UiKit.ImageUri(UiKit.Theme.Icons.Shop)
button.ScaleType = Enum.ScaleType.Fit
local emoji = UiKit.Text(button, "Icon", "🛒", { _Stroke = 0, Visible = button.Image == "" })
emoji.FontFace = Font.fromEnum(Enum.Font.GothamBold)

require(ReplicatedStorage.Shared.TopbarDock).Add(button, 1)

button.Activated:Connect(function()
	openRequest:Fire("Shop")
end)
