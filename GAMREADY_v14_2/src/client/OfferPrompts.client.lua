--------------------------------------------------------------------------------
-- OfferPrompts (LocalScript, v10) — КОНТЕКСТНЫЕ ПРЕДЛОЖЕНИЯ: маленький
-- «купон» с ценой появляется ровно в тот момент, когда товар нужен, и
-- покупается в одно касание (MarketplaceService). Вид — OfferUiBuilder.
--
--   🛡 Shield     — несёшь тележку, рядом чужой игрок, щита нет
--   🧍 Get Up     — лежишь в рагдолле
--   💢 Revenge    — тебя ограбили (сервер шлёт OfferEvent "Revenge")
--   ⛏ Mine Rush  — стоишь у своей шахты, зарядов нет
--   🎯 Perfect    — идёт мини-игра валуна
--
-- Товар с Id = 0 не показывается (Config.Offers.ShowWithoutId — для тестов).
-- Закрытый крестиком купон не всплывает Config.Offers.HideSeconds секунд.
--
-- Здесь же кнопка 🚀 ROCKET PICKAXE (видна владельцам пасса): клик или R —
-- включить/выключить; шторка показывает откат ракетного удара.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Builder = require(ReplicatedStorage.Shared.OfferUiBuilder)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local cfg = Config.Offers or {}
local micro = Config.DevProducts.Micro or {}

-- v20: StarterGui/OfferUi (tools/BuildAllUI.lua); нет — соберётся билдером.
local gui = require(ReplicatedStorage.Shared.UiRegistry).Get("OfferUi")
if not gui or (tonumber(gui:GetAttribute("BuilderVersion")) or 0) < Builder.VERSION then
	if gui then gui:Destroy() end
	gui = Builder.Build()
	gui.Parent = playerGui
end
local stack = gui:WaitForChild("Stack")
local template = stack:WaitForChild("OfferTemplate")
local autoScale = stack:FindFirstChild("AutoScale")
local rocketButton = gui:WaitForChild("RocketButton")

local function fitScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local _ = viewport
	if autoScale then autoScale.Scale = 1 end -- v20.16: подгонка под экран — client/ResponsiveUi
end
fitScale()
if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitScale) end

--------------------------------------------------------------------------------
-- КУПОНЫ
--------------------------------------------------------------------------------
local OFFERS = {
	Shield = { Order = 1, Icon = "🛡", Text = "Shield now", ProductId = Config.Protection.PaidProductId, Price = Config.Protection.PriceRobux },
	GetUp = { Order = 2, Icon = micro.GetUp and micro.GetUp.Icon, Text = "Get up now", Micro = "GetUp" },
	Revenge = { Order = 3, Icon = micro.Revenge and micro.Revenge.Icon, Text = "Get back", Micro = "Revenge" },
	MineRush = { Order = 4, Icon = micro.MineRush and micro.MineRush.Icon, Text = "x2 ore · 3 digs", Micro = "MineRush" },
	PerfectStrike = { Order = 5, Icon = micro.PerfectStrike and micro.PerfectStrike.Icon, Text = "PERFECT break", Micro = "PerfectStrike" },
}
for _, offer in OFFERS do
	if offer.Micro and micro[offer.Micro] then
		offer.ProductId = micro[offer.Micro].Id
		offer.Price = micro[offer.Micro].PriceRobux
	end
end

local shown = {}      -- [key] = button
local snoozed = {}    -- [key] = os.clock() до которого не показываем
local revengeInfo = nil -- { Value, ExpiresAt }

local function available(offer)
	return (offer.ProductId or 0) ~= 0 or cfg.ShowWithoutId == true
end

local function hideOffer(key)
	local button = shown[key]
	if not button then return end
	shown[key] = nil
	local pop = button:FindFirstChild("Pop")
	if pop then
		local tween = TweenService:Create(pop, TweenInfo.new(0.15), { Scale = 0 })
		tween:Play()
		tween.Completed:Connect(function() button:Destroy() end)
	else
		button:Destroy()
	end
end

local function showOffer(key, labelText)
	local offer = OFFERS[key]
	if not offer or not available(offer) then return end
	if (snoozed[key] or 0) > os.clock() then return end
	local button = shown[key]
	if not button then
		button = template:Clone()
		button.Name = "Offer_" .. key
		button.Visible = true
		button.LayoutOrder = offer.Order
		button.Icon.Text = offer.Icon or "✨"
		button.Price.Text.Text = "R$ " .. tostring(offer.Price or "?")
		button.Parent = stack
		shown[key] = button
		local pop = button:FindFirstChild("Pop")
		if pop then
			pop.Scale = 0
			TweenService:Create(pop, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		button.Activated:Connect(function()
			if (offer.ProductId or 0) == 0 then return end
			MarketplaceService:PromptProductPurchase(player, offer.ProductId)
		end)
		button.Close.Activated:Connect(function()
			snoozed[key] = os.clock() + (cfg.HideSeconds or 45)
			hideOffer(key)
		end)
	end
	button.Label.Text = labelText or offer.Text
end

local function setOffer(key, wanted, labelText)
	if wanted then showOffer(key, labelText) else hideOffer(key) end
end

-- Купил — купон уходит.
MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
	if userId ~= player.UserId or not purchased then return end
	for key, offer in OFFERS do
		if offer.ProductId == productId then
			if key == "Revenge" then revengeInfo = nil end
			hideOffer(key)
		end
	end
end)

local offerRemote = ReplicatedStorage.Shared:WaitForChild("OfferEvent", 15)
if offerRemote then
	offerRemote.OnClientEvent:Connect(function(kind, payload)
		if kind == "Revenge" and type(payload) == "table" then
			revengeInfo = { Value = tonumber(payload.Value) or 0, ExpiresAt = tonumber(payload.ExpiresAt) or 0 }
			snoozed.Revenge = nil
		end
	end)
end

-- Своя шахта рядом?
local myMine = nil
local function findMyMine()
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("Model") and descendant:GetAttribute("PlotMine") == true then
			local plot = descendant.Parent and descendant.Parent.Parent
			local pad = plot and plot:FindFirstChild("PlotPad", true)
			if pad and pad:GetAttribute("OwnerUserId") == player.UserId then
				return descendant
			end
		end
	end
	return nil
end

local function enemyNearby(root)
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local otherRoot = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
			if otherRoot and (otherRoot.Position - root.Position).Magnitude <= (cfg.ShieldThreatRadius or 28) then
				return true
			end
		end
	end
	return false
end

local boulderUi = nil
local mineScan = 0
task.spawn(function()
	while true do
		task.wait(0.4)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local ragdolled = player:GetAttribute("Ragdolled") == true

		-- 🛡 щит: несёшь тележку, рядом чужой, щита нет.
		setOffer("Shield", root ~= nil and not ragdolled
			and player:GetAttribute("CarryingCart") == true
			and player:GetAttribute("Protected") ~= true
			and enemyNearby(root))

		-- 🧍 встать.
		setOffer("GetUp", ragdolled)

		-- 💢 вернуть украденное (после того как встал).
		local now = os.time()
		if revengeInfo and revengeInfo.ExpiresAt > now and revengeInfo.Value > 0 and not ragdolled then
			setOffer("Revenge", true, "Get back $" .. NumberFormat.abbreviate(revengeInfo.Value))
		else
			if revengeInfo and revengeInfo.ExpiresAt <= now then revengeInfo = nil end
			setOffer("Revenge", false)
		end

		-- ⛏ Mine Rush у своей шахты.
		mineScan -= 1
		if mineScan <= 0 or not (myMine and myMine.Parent) then
			mineScan = 12
			myMine = findMyMine()
		end
		local nearMine = false
		if root and myMine and myMine.Parent then
			local ok, pivot = pcall(myMine.GetPivot, myMine)
			nearMine = ok and (pivot.Position - root.Position).Magnitude <= (cfg.MineRushRadius or 26)
		end
		setOffer("MineRush", nearMine and not ragdolled and (tonumber(player:GetAttribute("MineRushCharges")) or 0) <= 0)

		-- 🎯 Perfect — пока открыта мини-игра валуна.
		boulderUi = boulderUi or playerGui:FindFirstChild("BoulderGameUi")
		local panel = boulderUi and boulderUi:FindFirstChild("Panel")
		setOffer("PerfectStrike", panel ~= nil and panel.Visible)
	end
end)

--------------------------------------------------------------------------------
-- 🚀 ТУРБО-КИРКА. Это СКИН (меню скинов), не кнопка: здесь только индикатор
-- отката ракетного удара, пока скин надет (атрибут RocketMode ставит сервер).
--------------------------------------------------------------------------------
local rocketCfg = Config.RocketPickaxe or {}
local rocketState = rocketButton:FindFirstChild("State")
local rocketShade = rocketButton:FindFirstChild("Cooldown")
local rocketGlow = rocketButton:FindFirstChild("Glow")
rocketButton.AutoButtonColor = false
rocketButton.Active = false

local function renderRocket()
	local on = player:GetAttribute("RocketMode") == true
	rocketButton.Visible = on
	rocketButton.BackgroundColor3 = Color3.fromRGB(230, 90, 40)
	if rocketGlow then rocketGlow.Transparency = 0 end
end
player:GetAttributeChangedSignal("RocketMode"):Connect(renderRocket)
renderRocket()

task.spawn(function()
	while true do
		task.wait(0.1)
		if rocketButton.Visible then
			local left = math.max(0, (tonumber(player:GetAttribute("RocketReadyAt")) or 0) - workspace:GetServerTimeNow())
			if rocketShade then
				rocketShade.Size = UDim2.fromScale(1, math.clamp(left / math.max(1, rocketCfg.Cooldown or 18), 0, 1))
			end
			if rocketState then
				rocketState.Text = left > 0 and (tostring(math.ceil(left)) .. "s") or "READY"
				rocketState.TextColor3 = left > 0 and Color3.fromRGB(230, 200, 200) or Color3.fromRGB(150, 255, 170)
			end
		end
	end
end)
