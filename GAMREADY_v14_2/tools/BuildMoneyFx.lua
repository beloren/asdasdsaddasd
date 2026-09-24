-- Standalone Studio builder for the replaceable flying-money image.
-- It replaces only ReplicatedStorage/Assets/MoneyFxTemplate.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Assets = ReplicatedStorage:WaitForChild("Assets")
local Config = require(ReplicatedStorage.Shared.Config)

local existing = Assets:FindFirstChild("MoneyFxTemplate")
if existing then existing:Destroy() end

local template = Instance.new("ImageLabel")
template.Name = "MoneyFxTemplate"
template.Size = UDim2.fromOffset(18, 18)
template.BackgroundColor3 = Color3.fromRGB(255, 215, 90)
template.BorderSizePixel = 0
template.Image = Config.Icons.FlyingCoin ~= 0 and ("rbxassetid://" .. tostring(Config.Icons.FlyingCoin)) or ""
template.BackgroundTransparency = template.Image == "" and 0 or 1
template.ScaleType = Enum.ScaleType.Fit
template.Visible = true
template.Parent = Assets

print("[BuildMoneyFx] Assets/MoneyFxTemplate created. Set its Image in Studio to replace flying coins.")
