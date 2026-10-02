--------------------------------------------------------------------------------
-- HudCurrencyFx (v20.135) — АНИМАЦИЯ НАЧИСЛЕНИЯ ВАЛЮТЫ В HUD.
-- Сервер шлёт CurrencyFx:
--   "Money", amount     - счётчик денег подпрыгивает, рядом всплывает «+$X»
--                         (если уже летят монетки CoinShower - только прыжок);
--   "Prestige", amount  - очко престижа (иконка UiTheme.Icons.Prestige)
--                         появляется в центре экрана, раскрывается с искрами и
--                         по дуге падает в счётчик престижа HUD; число в HUD
--                         увеличивается в момент приземления.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UiKit = require(ReplicatedStorage.Shared.UiKit)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local Theme = UiKit.Theme

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CurrencyFx", 60)
if not remote then return end

local function sfx(name)
	pcall(function() require(ReplicatedStorage.Shared.UiSfx).play(name) end)
end

local layer = Instance.new("ScreenGui")
layer.Name = "HudCurrencyFx"
layer.IgnoreGuiInset = true
layer.ResetOnSpawn = false
layer.DisplayOrder = 960
layer:SetAttribute("UiKitVersion", 20)
layer.Parent = playerGui

local function hud()
	return playerGui:FindFirstChild("Hud")
end

local function pillParts(name)
	local gui = hud()
	local pill = gui and gui:FindFirstChild(name, true)
	if not pill then return nil end
	local value = pill:FindFirstChild("Value", true)
	local icon = pill:FindFirstChild("Icon", true)
	return pill, value, icon
end

-- центр элемента в координатах нашего слоя (IgnoreGuiInset = true)
local function screenCenter(guiObject)
	local center = guiObject.AbsolutePosition + guiObject.AbsoluteSize / 2
	local owner = guiObject:FindFirstAncestorWhichIsA("ScreenGui")
	if owner and not owner.IgnoreGuiInset then
		center += Vector2.new(0, game:GetService("GuiService"):GetGuiInset().Y)
	end
	return center
end

-- прыжок элемента: свой UIScale, если у него ещё нет чужого (Roblox
-- применяет только один UIScale)
local function bump(target, strength)
	if not (target and target:IsA("GuiObject")) then return end
	local scale = target:FindFirstChild("CurrencyBump")
	if not scale then
		if target:FindFirstChildOfClass("UIScale") then
			scale = target:FindFirstChildOfClass("UIScale")
		else
			scale = Instance.new("UIScale")
			scale.Name = "CurrencyBump"
			scale.Parent = target
		end
	end
	if scale.Name ~= "CurrencyBump" then return end
	scale.Scale = 1 + (strength or 0.22)
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	if target:IsA("TextLabel") then
		local base = target:GetAttribute("CurrencyBaseRotation")
		if base == nil then
			base = target.Rotation
			target:SetAttribute("CurrencyBaseRotation", base)
		end
		target.Rotation = base + (math.random() < 0.5 and -6 or 6)
		TweenService:Create(target, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = base }):Play()
	end
end

-- «+X» рядом со счётчиком: всплывает, едет вверх и тает
local function popText(text, color, anchor)
	local label = Instance.new("TextLabel")
	label.Name = "CurrencyPop"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.fromOffset(anchor.X, anchor.Y)
	label.Size = UDim2.fromOffset(240, 40)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	UiKit.StyleText(label, "Number")
	label.TextScaled = true
	label.TextColor3 = color
	label.ZIndex = 6
	label.Parent = layer
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = label
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(label, TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = label.Position - UDim2.fromOffset(0, 34) }):Play()
	task.delay(0.9, function()
		TweenService:Create(label, TweenInfo.new(0.45), { TextTransparency = 1 }):Play()
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then TweenService:Create(stroke, TweenInfo.new(0.45), { Transparency = 1 }):Play() end
		task.delay(0.5, function() label:Destroy() end)
	end)
	return label
end

--------------------------------------------------------------------------------
-- ДЕНЬГИ
--------------------------------------------------------------------------------
local moneyPop, moneyPopAmount, moneyPopUntil = nil, 0, 0
local function onMoney(amount)
	amount = tonumber(amount) or 0
	if amount <= 0 then return end
	local pill, value, icon = pillParts("MoneyPill")
	if not pill or not pill.Visible then return end
	bump(value or pill, 0.25)
	bump(icon, 0.3)
	-- монетки CoinShower уже показывают «+$X» - второй не нужен
	local shower = playerGui:FindFirstChild("CoinShowerFx")
	if shower and #shower:GetChildren() > 0 then return end
	local target = value or pill
	local anchor = screenCenter(target) + Vector2.new(target.AbsoluteSize.X / 2 + 8, 0)
	local now = os.clock()
	if moneyPop and moneyPop.Parent and now < moneyPopUntil then
		-- несколько начислений подряд - одна надпись, сумма растёт
		moneyPopAmount += amount
		moneyPop.Text = "+$" .. NumberFormat.abbreviate(moneyPopAmount)
		bump(moneyPop, 0.15)
	else
		moneyPopAmount = amount
		moneyPop = popText("+$" .. NumberFormat.abbreviate(amount), Color3.fromRGB(150, 255, 130), anchor)
	end
	moneyPopUntil = now + 0.7
end

--------------------------------------------------------------------------------
-- ОЧКО ПРЕСТИЖА
--------------------------------------------------------------------------------
local function prestigeIcon(size)
	local image = UiKit.ImageUri(Theme.Icons and Theme.Icons.Prestige)
	local icon = Instance.new("ImageLabel")
	icon.Name = "PrestigePoint"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Size = UDim2.fromOffset(size, size)
	icon.Image = image ~= "" and image or "rbxassetid://115386518245112"
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 8
	icon.Parent = layer
	return icon
end

local function sparkle(at, color)
	for i = 1, 10 do
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.BorderSizePixel = 0
		dot.BackgroundColor3 = color
		dot.Size = UDim2.fromOffset(8, 8)
		dot.Rotation = 45
		dot.Position = UDim2.fromOffset(at.X, at.Y)
		dot.ZIndex = 7
		dot.Parent = layer
		local angle = (i / 10) * math.pi * 2 + math.random() * 0.4
		local dist = 70 + math.random() * 60
		local to = at + Vector2.new(math.cos(angle), math.sin(angle)) * dist
		TweenService:Create(dot, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(to.X, to.Y), Size = UDim2.fromOffset(2, 2), BackgroundTransparency = 1, Rotation = 225,
		}):Play()
		task.delay(0.6, function() dot:Destroy() end)
	end
end

local prestigeQueue = 0
local function onPrestige(amount)
	amount = math.max(1, math.floor(tonumber(amount) or 1))
	local pill, value, iconTarget = pillParts("RebirthPill")
	local prefix = pill and pill:GetAttribute("Prefix")
	if typeof(prefix) ~= "string" then prefix = "PRESTIGE: " end
	-- число в HUD растёт, когда очко долетит
	local points = tonumber(player:GetAttribute("PrestigePoints")) or 0
	prestigeQueue += amount
	if value then value.Text = prefix .. NumberFormat.abbreviate(math.max(0, points - prestigeQueue)) end

	local camera = workspace.CurrentCamera
	local view = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local center = Vector2.new(view.X / 2, view.Y * 0.45)
	local size = math.clamp(view.Y * 0.16, 70, 130)
	local icon = prestigeIcon(size)
	icon.Position = UDim2.fromOffset(center.X, center.Y)
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = icon
	local caption = Instance.new("TextLabel")
	caption.BackgroundTransparency = 1
	caption.AnchorPoint = Vector2.new(0.5, 0)
	caption.Position = UDim2.fromOffset(center.X, center.Y + size * 0.6)
	caption.Size = UDim2.fromOffset(360, 40)
	caption.Text = ("+%d PRESTIGE POINT%s"):format(amount, amount > 1 and "S" or "")
	UiKit.StyleText(caption, "Title")
	caption.TextScaled = true
	caption.TextColor3 = Color3.fromRGB(255, 150, 215)
	caption.TextTransparency = 1
	caption.ZIndex = 8
	caption.Parent = layer

	sfx("PerkUnlock")
	TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(caption, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
	sparkle(center, Color3.fromRGB(255, 190, 235))
	-- покачивание, пока висит
	local started = os.clock()
	local wobble = RunService.RenderStepped:Connect(function()
		icon.Rotation = math.sin((os.clock() - started) * 6) * 8
	end)
	task.wait(1.1)
	wobble:Disconnect()
	TweenService:Create(caption, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
	local cstroke = caption:FindFirstChildOfClass("UIStroke")
	if cstroke then TweenService:Create(cstroke, TweenInfo.new(0.25), { Transparency = 1 }):Play() end
	task.delay(0.3, function() caption:Destroy() end)

	-- дуга в счётчик HUD
	local targetObject = (iconTarget and iconTarget.AbsoluteSize.X > 2 and iconTarget) or value or pill
	local target = targetObject and screenCenter(targetObject) or Vector2.new(view.X * 0.12, 40)
	local control = (center + target) / 2 + Vector2.new(0, -view.Y * 0.18)
	local duration = 0.75
	local began = os.clock()
	while icon.Parent do
		local t = math.clamp((os.clock() - began) / duration, 0, 1)
		local e = t * t * (3 - 2 * t)
		local p = center:Lerp(control, e):Lerp(control:Lerp(target, e), e)
		icon.Position = UDim2.fromOffset(p.X, p.Y)
		scale.Scale = 1 - 0.7 * e
		icon.Rotation = e * 360
		if t >= 1 then break end
		RunService.RenderStepped:Wait()
	end
	icon:Destroy()
	prestigeQueue = math.max(0, prestigeQueue - amount)
	points = tonumber(player:GetAttribute("PrestigePoints")) or points
	if value then value.Text = prefix .. NumberFormat.abbreviate(math.max(0, points - prestigeQueue)) end
	sparkle(target, Color3.fromRGB(255, 190, 235))
	sfx("RewardCrystal")
	bump(value or pill, 0.35)
	bump(iconTarget, 0.4)
	if value then
		popText("+" .. amount, Color3.fromRGB(255, 150, 215), screenCenter(value) + Vector2.new(value.AbsoluteSize.X / 2 + 8, 0))
	end
end

remote.OnClientEvent:Connect(function(kind, amount)
	if kind == "Money" then
		onMoney(amount)
	elseif kind == "Prestige" then
		task.spawn(onPrestige, amount)
	end
end)
