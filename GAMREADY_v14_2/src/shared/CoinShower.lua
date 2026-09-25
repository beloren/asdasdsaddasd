--------------------------------------------------------------------------------
-- CoinShower (v20.27) — «пополнение» денег на экране: монетки вылетают из
-- точки (кнопка COLLECT и т.п.), разлетаются веером и по дуге влетают в
-- счётчик денег HUD (Hud/…/MoneyPill); счётчик подпрыгивает с каждой
-- монеткой, рядом всплывает «+$X». Только клиент.
--
--   CoinShower.Play(amount, fromScreenPosition?)   -- Vector2, по умолчанию центр
--
-- Монета — картинка UiTheme.Icons.Money (если задана) или нарисованный
-- золотой кружок со знаком «$».
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UiKit = require(ReplicatedStorage.Shared.UiKit)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local Theme = UiKit.Theme

local CoinShower = {}

local COIN_SIZE = 34
local GOLD = Color3.fromRGB(255, 205, 60)
local GOLD_DARK = Color3.fromRGB(190, 120, 20)

local function screenGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:FindFirstChild("CoinShowerFx")
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = "CoinShowerFx"
		gui.IgnoreGuiInset = true
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 950 -- над экраном возвращения
		gui:SetAttribute("UiKitVersion", 20)
		gui.Parent = playerGui
	end
	return gui
end

local function moneyPill()
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("Hud")
	local pill = hud and hud:FindFirstChild("MoneyPill", true)
	if pill and pill:IsA("GuiObject") and pill.AbsoluteSize.X > 0 then return pill end
	return nil
end

-- Центр элемента в координатах всего экрана (наш слой IgnoreGuiInset = true).
function CoinShower.ScreenCenter(guiObject)
	local center = guiObject.AbsolutePosition + guiObject.AbsoluteSize / 2
	local layer = guiObject:FindFirstAncestorWhichIsA("ScreenGui")
	if layer and not layer.IgnoreGuiInset then
		center += Vector2.new(0, game:GetService("GuiService"):GetGuiInset().Y)
	end
	return center
end

local function makeCoin(parent)
	local image = UiKit.ImageUri(Theme.Icons and Theme.Icons.Money)
	local coin
	if image ~= "" then
		coin = Instance.new("ImageLabel")
		coin.Image = image
		coin.BackgroundTransparency = 1
	else
		coin = Instance.new("Frame")
		coin.BackgroundColor3 = GOLD
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = coin
		local stroke = Instance.new("UIStroke")
		stroke.Color = GOLD_DARK
		stroke.Thickness = 2.5
		stroke.Parent = coin
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(Color3.fromRGB(255, 245, 170), GOLD)
		gradient.Rotation = 90
		gradient.Parent = coin
		local sign = Instance.new("TextLabel")
		sign.BackgroundTransparency = 1
		sign.Size = UDim2.fromScale(1, 1)
		sign.Text = "$"
		sign.TextScaled = true
		sign.TextColor3 = Color3.fromRGB(150, 90, 10)
		sign.FontFace = Theme.Fonts and Theme.Fonts.Number or Font.fromEnum(Enum.Font.GothamBlack)
		sign.Parent = coin
	end
	coin.Name = "Coin"
	coin.AnchorPoint = Vector2.new(0.5, 0.5)
	coin.Size = UDim2.fromOffset(COIN_SIZE, COIN_SIZE)
	coin.ZIndex = 5
	coin.Parent = parent
	return coin
end

local function bump(pill)
	local scale = pill:FindFirstChild("CoinShowerScale")
	if not scale then
		-- Свой UIScale нельзя вешать, если у плашки уже есть чужой (Roblox их
		-- не складывает) — тогда подпрыгивает иконка.
		local target = pill
		for _, child in pill:GetChildren() do
			if child:IsA("UIScale") then
				target = pill:FindFirstChild("Icon") or nil
				break
			end
		end
		if not target then return end
		scale = target:FindFirstChild("CoinShowerScale") or Instance.new("UIScale")
		scale.Name = "CoinShowerScale"
		scale.Parent = target
	end
	scale.Scale = 1.15
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function popLabel(gui, position, amount)
	local label = Instance.new("TextLabel")
	label.Name = "PlusMoney"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.fromOffset(position.X, position.Y)
	label.Size = UDim2.fromOffset(260, 44)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = "+$" .. NumberFormat.abbreviate(amount)
	UiKit.StyleText(label, "Number")
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(150, 255, 130)
	label.ZIndex = 6
	label.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = label
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(1.4, function()
		TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1, Position = label.Position - UDim2.fromOffset(0, 24) }):Play()
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then TweenService:Create(stroke, TweenInfo.new(0.5), { Transparency = 1 }):Play() end
		task.delay(0.6, function() label:Destroy() end)
	end)
end

function CoinShower.Play(amount, fromScreenPosition)
	amount = tonumber(amount) or 0
	if amount <= 0 then return end
	local gui = screenGui()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local from = fromScreenPosition or viewport / 2
	local pill = moneyPill()
	local target = pill and CoinShower.ScreenCenter(pill) or Vector2.new(viewport.X / 2, 40)

	-- Больше денег — больше монет (логарифмически), но не больше 24.
	local count = math.clamp(math.floor(6 + math.log10(amount + 1) * 2.5), 8, 24)
	local arrived = 0
	for i = 1, count do
		task.delay((i - 1) * 0.045, function()
			local coin = makeCoin(gui)
			local angle = math.random() * math.pi * 2
			local burst = from + Vector2.new(math.cos(angle), math.sin(angle) * 0.7) * (60 + math.random() * 110)
			coin.Position = UDim2.fromOffset(from.X, from.Y)
			coin.Rotation = math.random(-30, 30)
			local size = COIN_SIZE * (0.8 + math.random() * 0.4)
			coin.Size = UDim2.fromOffset(size * 0.3, size * 0.3)
			-- 1) выстрел веером
			TweenService:Create(coin, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.fromOffset(burst.X, burst.Y),
				Size = UDim2.fromOffset(size, size),
				Rotation = coin.Rotation + math.random(-90, 90),
			}):Play()
			task.wait(0.32 + math.random() * 0.12)
			-- 2) дуга в счётчик денег
			local start = burst
			local control = (start + target) / 2 + Vector2.new((math.random() - 0.5) * 160, -120 - math.random() * 80)
			local duration = 0.5 + math.random() * 0.15
			local began = os.clock()
			while coin.Parent do
				local t = math.clamp((os.clock() - began) / duration, 0, 1)
				local e = t * t * (3 - 2 * t)
				local p = start:Lerp(control, e):Lerp(control:Lerp(target, e), e)
				coin.Position = UDim2.fromOffset(p.X, p.Y)
				local s = size * (1 - 0.45 * e)
				coin.Size = UDim2.fromOffset(s, s)
				if t >= 1 then break end
				RunService.RenderStepped:Wait()
			end
			coin:Destroy()
			arrived += 1
			if pill then bump(pill) end
			if arrived == 1 then
				pcall(function() require(ReplicatedStorage.Shared.UiSfx).play("RewardMoney") end)
			end
			if arrived == count then
				popLabel(gui, target + Vector2.new((pill and pill.AbsoluteSize.X / 2 or 0) + 10, 0), amount)
			end
		end)
	end
end

return CoinShower
