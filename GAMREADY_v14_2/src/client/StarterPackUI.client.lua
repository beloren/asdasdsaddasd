--------------------------------------------------------------------------------
-- StarterPackUI
-- Баннер "STARTER KIT" (радужная надпись + отсчёт до конца окна предложения)
-- поверх StarterGui/StarterPackOffer (см. tools/BuildStarterPackUI.lua).
-- Показывается ТОЛЬКО новым игрокам (см. FirstJoinedAt в DataService),
-- ТОЛЬКО пока не истекло Config.DevProducts.StarterPack.OfferWindowSeconds
-- и ТОЛЬКО пока пак ещё не куплен (StarterPackClaimed).
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Config = require(ReplicatedStorage.Shared.Config)
local UiSfx = require(ReplicatedStorage.Shared.UiSfx)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local STARTER_PACK_ICON_IMAGE = "rbxassetid://100116175987177"
local HOVER_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CLICK_TWEEN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PANEL_IN_TWEEN = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PANEL_OUT_TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local pack = Config.DevProducts.StarterPack
if not pack then
	warn("[StarterPackUI] Config.DevProducts.StarterPack не настроен.")
	return
end

-- v20: вид собирается билдером (Shared.UiBuilders.StarterPackUi →
-- StarterGui/StarterPackOffer); нет в StarterGui — соберётся тем же билдером.
local gui = require(ReplicatedStorage.Shared.UiRegistry).Get("StarterPackOffer")
if not gui then
	warn("[StarterPackUI] StarterPackOffer не найден. Запусти tools/BuildAllUI.lua.")
	return
end

local banner = gui:FindFirstChild("Banner", true)
local rainbowTitle = gui:FindFirstChild("RainbowTitle", true)
local countdownLabel = gui:FindFirstChild("Countdown", true)
local dimmer = gui:FindFirstChild("Dimmer", true)
local details = gui:FindFirstChild("Details", true)
local closeButton = details and details:FindFirstChild("CloseButton", true)
local buyButton = details and details:FindFirstChild("BuyButton", true)

-- v10: зачёркнутая «стоит» цена рядом с реальной (Config.DevProducts.StarterPack).
do
	local starterPack = Config.DevProducts.StarterPack or {}
	local buyLabel = buyButton and (buyButton:FindFirstChild("Caption") or (buyButton:IsA("TextButton") and buyButton))
	if buyLabel and starterPack.PriceRobux then
		buyLabel.RichText = true
		if starterPack.WorthRobux and starterPack.WorthRobux > starterPack.PriceRobux then
			buyLabel.Text = ("<s>R$ %d</s>  BUY FOR R$ %d"):format(starterPack.WorthRobux, starterPack.PriceRobux)
		else
			buyLabel.Text = ("BUY FOR R$ %d"):format(starterPack.PriceRobux)
		end
	end
end

local function setVisible(instance, visible)
	if instance and instance:IsA("GuiObject") then
		instance.Visible = visible
	end
end

-- Иконка баннера — из билдера (её можно заменить в Studio). Пустая —
-- ставим стандартную картинку стартового набора.
local bannerIcon = banner and banner:FindFirstChild("Icon")
if bannerIcon and bannerIcon:IsA("ImageLabel") and bannerIcon.Image == "" then
	bannerIcon.Image = STARTER_PACK_ICON_IMAGE
end

-- Тот же приём, что и у остальных панелей проекта (CollectionMenu/
-- GeodeUI/DailyReward) — ResponsiveScale подстраивается под ViewportSize,
-- чтобы панель не вылезала за экран на телефонах/маленьких окнах.
local responsiveScale = details and details:FindFirstChild("ResponsiveScale")
local panelScale = details and details:FindFirstChild("StarterPackOpenScale")
if details and not panelScale then
	panelScale = Instance.new("UIScale")
	panelScale.Name = "StarterPackOpenScale"
	panelScale.Scale = 1
	panelScale.Parent = details
end
local dimmerBaseTransparency = dimmer and dimmer:IsA("GuiObject") and dimmer.BackgroundTransparency or 0.35
local detailsBasePosition = details and details:IsA("GuiObject") and details.Position or nil
local bannerBasePosition = banner and banner:IsA("GuiObject") and banner.Position or nil
local bannerScale = banner and banner:FindFirstChild("StarterPackBannerScale")
if banner and banner:IsA("GuiObject") and not bannerScale then
	bannerScale = Instance.new("UIScale")
	bannerScale.Name = "StarterPackBannerScale"
	bannerScale.Parent = banner
end

player:SetAttribute("StarterPackOfferActive", false)

local trackedJumpButton
local jumpButtonConnections = {}

local function findBalanceBounds()
	for _, name in { "MoneyPill", "MoneyLabel", "Balance", "BalanceFrame" } do
		local candidate = playerGui:FindFirstChild(name, true)
		if candidate and candidate:IsA("GuiObject") and candidate.Visible then
			return candidate.AbsolutePosition, candidate.AbsoluteSize
		end
	end
	return nil
end

local function updateBannerLayout()
	if not (banner and banner:IsA("GuiObject")) then return end
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(800, 600)
	local mobile = UserInputService.TouchEnabled or viewport.X < 700
	banner.AnchorPoint = Vector2.new(1, 1)
	local jumpButton = mobile and playerGui:FindFirstChild("JumpButton", true) or nil
	if jumpButton ~= trackedJumpButton then
		for _, connection in jumpButtonConnections do connection:Disconnect() end
		jumpButtonConnections = {}
		trackedJumpButton = jumpButton
		if jumpButton and jumpButton:IsA("GuiObject") then
			for _, property in { "AbsolutePosition", "AbsoluteSize", "Visible" } do
				table.insert(jumpButtonConnections, jumpButton:GetPropertyChangedSignal(property):Connect(updateBannerLayout))
			end
		end
	end
	if jumpButton and jumpButton:IsA("GuiObject") and jumpButton.Visible then
		-- Prefer the space above JumpButton, but move below it if that space
		-- intersects the balance HUD in the top-right corner.
		local bannerHeight = math.max(1, banner.AbsoluteSize.Y)
		local jumpTop = jumpButton.AbsolutePosition.Y
		local jumpBottom = jumpTop + jumpButton.AbsoluteSize.Y
		local aboveTop = jumpTop - 14 - bannerHeight
		local balancePosition, balanceSize = findBalanceBounds()
		local overlapsBalance = balancePosition
			and aboveTop < balancePosition.Y + balanceSize.Y + 8
			and aboveTop + bannerHeight > balancePosition.Y - 8
		local belowTop = jumpBottom + 14
		local useBelow = overlapsBalance and belowTop + bannerHeight <= viewport.Y - 8
		local top = useBelow and belowTop or aboveTop
		banner.Position = UDim2.fromOffset(viewport.X - 14, math.max(8, top + bannerHeight))
	else
		banner.Position = mobile and UDim2.new(1, -14, 1, -14) or UDim2.new(1, -20, 1, -20)
	end
	bannerBasePosition = banner.Position
	if bannerScale then
		bannerScale.Scale = mobile and math.clamp(viewport.X / 520, 0.58, 0.74) or 1
	end
end

updateBannerLayout()
playerGui.DescendantAdded:Connect(function(descendant)
	if descendant.Name == "JumpButton" or descendant.Name == "TouchGui" then
		task.defer(updateBannerLayout)
	end
end)

local function tween(object, info, goal)
	if not object then return nil end
	local created = TweenService:Create(object, info, goal)
	created:Play()
	return created
end

local function setPanelOpen(open)
	if not (details and details:IsA("GuiObject")) then return end
	if open then
		setVisible(details, true)
		if detailsBasePosition then
			details.Position = detailsBasePosition + UDim2.fromOffset(0, 18)
		end
		if panelScale then panelScale.Scale = 0.92 end
		tween(details, PANEL_IN_TWEEN, { Position = detailsBasePosition or details.Position })
		tween(panelScale, PANEL_IN_TWEEN, { Scale = 1 })
	else
		tween(details, PANEL_OUT_TWEEN, { Position = detailsBasePosition and (detailsBasePosition + UDim2.fromOffset(0, 12)) or details.Position })
		local closing = tween(panelScale, PANEL_OUT_TWEEN, { Scale = 0.94 })
		if closing then
			closing.Completed:Connect(function()
				setVisible(details, false)
				if panelScale then panelScale.Scale = 1 end
				if detailsBasePosition then details.Position = detailsBasePosition end
			end)
		else
			setVisible(details, false)
		end
	end
end

local dimmerAnimationToken = 0
local function animateDimmer(open)
	if not (dimmer and dimmer:IsA("GuiObject")) then return end
	dimmerAnimationToken += 1
	local token = dimmerAnimationToken
	if open then
		dimmer.BackgroundTransparency = 1
		setVisible(dimmer, true)
		tween(dimmer, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = dimmerBaseTransparency })
	else
		setVisible(dimmer, false)
		local closing = tween(dimmer, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 })
		if closing then
			closing.Completed:Connect(function()
				if token ~= dimmerAnimationToken then return end
				dimmer.BackgroundTransparency = dimmerBaseTransparency
			end)
		else
			dimmer.BackgroundTransparency = dimmerBaseTransparency
		end
	end
end

local function buttonScale(button)
	if not (button and button:IsA("GuiButton")) then return nil end
	local scale = button:FindFirstChild("StarterPackButtonScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "StarterPackButtonScale"
		scale.Parent = button
	end
	return scale
end

local function animateButton(button)
	if button and button:GetAttribute("StarterPackAnimated") == true then return end
	local scale = buttonScale(button)
	if not scale then return end
	button:SetAttribute("StarterPackAnimated", true)
	button.MouseEnter:Connect(function() tween(scale, HOVER_TWEEN, { Scale = 1.04 }) end)
	button.MouseLeave:Connect(function() tween(scale, HOVER_TWEEN, { Scale = 1 }) end)
	button.MouseButton1Down:Connect(function() tween(scale, CLICK_TWEEN, { Scale = 0.96 }) end)
	button.Activated:Connect(function()
		UiSfx.play("UiButtonClick")
		tween(scale, HOVER_TWEEN, { Scale = 1.04 })
	end)
end

local function animateStarterPackButtons(root)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("GuiButton") and descendant ~= dimmer then
			animateButton(descendant)
		end
	end
end

animateStarterPackButtons(gui)
gui.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("GuiButton") and descendant ~= dimmer then
		animateButton(descendant)
	end
end)

local function resizeDetails()
	if not responsiveScale then return end
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(800, 600)
	if details and details.Size.X.Offset > 0 and details.Size.Y.Offset > 0 then
		responsiveScale.Scale = math.min(1, (viewport.X - 40) / details.Size.X.Offset, (viewport.Y - 40) / details.Size.Y.Offset)
	end
end
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resizeDetails)
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateBannerLayout)
end
resizeDetails()

local rainbowToken = 0
local countdownToken = 0
local floatToken = 0
local forceCountdownStartedAt = nil
local purchaseBlocked = false

-- Радуга — та же идея, что и у RainbowSwap-мутации на кристаллах
-- (см. Shared/MutationVisuals.lua): цвет непрерывно бежит по кругу через HSV.
local function startRainbow(token)
	if not (banner and banner:IsA("GuiObject") and rainbowTitle and rainbowTitle:IsA("TextLabel")) then return end
	task.spawn(function()
		local hue = 0
		while rainbowToken == token and banner.Visible do
			hue = (hue + 0.01) % 1
			rainbowTitle.TextColor3 = Color3.fromHSV(hue, 0.85, 1)
			task.wait(0.03)
		end
	end)
end

local function formatCountdown(secondsLeft)
	secondsLeft = math.max(0, math.floor(secondsLeft))
	local minutes = math.floor(secondsLeft / 60)
	local seconds = secondsLeft % 60
	return ("%d:%02d"):format(minutes, seconds)
end

local function startBannerFloat(token)
	if not (banner and banner:IsA("GuiObject") and bannerBasePosition) then return end
	task.spawn(function()
		local up = true
		while floatToken == token and banner.Visible do
			local y = up and -4 or 4
			up = not up
			local move = tween(banner, TweenInfo.new(1.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Position = bannerBasePosition + UDim2.fromOffset(0, y),
			})
			if move then move.Completed:Wait() else task.wait(1.35) end
		end
		if banner and banner.Parent and bannerBasePosition then banner.Position = bannerBasePosition end
	end)
end

local function hideOffer()
	player:SetAttribute("StarterPackOfferActive", false)
	rainbowToken += 1
	countdownToken += 1
	floatToken += 1
	gui.Enabled = false
	setVisible(banner, false)
	setVisible(dimmer, false)
	setVisible(details, false)
	if banner and bannerBasePosition then banner.Position = bannerBasePosition end
end

local function closeDetails()
	animateDimmer(false)
	setPanelOpen(false)
end

local function openDetails()
	if purchaseBlocked or player:GetAttribute("StarterPackClaimed") ~= false then
		hideOffer()
		return
	end
	gui.Enabled = true
	player:SetAttribute("StarterPackOfferActive", true)
	animateDimmer(true)
	setPanelOpen(true)
end

-- Config.Debug.ForceStarterPackOffer — см. комментарий в Config.lua: обходит
-- все проверки, чтобы баннер можно было увидеть на уже игравшем аккаунте.
--
-- ОБЪЯВЛЕНА ЗДЕСЬ, А НЕ НИЖЕ, СПЕЦИАЛЬНО: startCountdown читает forceOffer, и
-- пока `local forceOffer` стояла ПОСЛЕ неё, имя внутри функции резолвилось
-- не в этот local, а в ГЛОБАЛ — то есть всегда в nil. Дебажный режим из-за
-- этого не работал: ветка "просто крутим таймер" не срабатывала, и отсчёт
-- сразу проваливался в hideOffer(), пряча баннер.
-- ТОЛЬКО В STUDIO. Флаг Config.Debug.ForceStarterPackOffer обходит ВСЕ
-- обычные условия показа баннера (новый ли игрок, не истекло ли окно), и он
-- уже однажды уехал в прод включённым — в результате «срочное предложение с
-- таймером» висело у игроков, которые играют месяцами. Проверка на Studio
-- делает такую утечку невозможной в принципе: даже если флаг снова оставят
-- в true и опубликуют, живые игроки этого не увидят.
--
-- На условие «пак уже куплен» это не влияет никак — оно проверяется отдельно
-- и ПЕРВЫМ (см. tryShowOffer/startCountdown ниже), forceOffer его не
-- обходит ни в Studio, ни где-либо ещё: купившему баннер не показывается
-- никогда.
local RunService = game:GetService("RunService")
local forceOffer = RunService:IsStudio()
	and Config.Debug and Config.Debug.ForceStarterPackOffer == true

-- Отсчёт — считается от FirstJoinedAt (unix-время создания профиля, см.
-- DataService), а не от момента, когда клиентский скрипт запустился: если
-- игрок перезашёл в игру спустя 3 минуты после первого захода, окно уже
-- должно быть на 7 минутах, а не начинаться заново с 10:00.
local function startCountdown(token)
	if not (countdownLabel and countdownLabel:IsA("TextLabel")) then return end
	task.spawn(function()
		while countdownToken == token do
			local firstJoinedAt = tonumber(player:GetAttribute("FirstJoinedAt")) or 0
			if purchaseBlocked or player:GetAttribute("StarterPackClaimed") ~= false then
				hideOffer()
				return
			end
			if forceOffer then
				forceCountdownStartedAt = forceCountdownStartedAt or os.time()
				local remaining = pack.OfferWindowSeconds - (os.time() - forceCountdownStartedAt)
				if remaining <= 0 then
					hideOffer()
					return
				end
				countdownLabel.Text = formatCountdown(remaining)
				task.wait(1)
				continue
			end
			if firstJoinedAt <= 0 then
				hideOffer()
				return
			end
			local remaining = pack.OfferWindowSeconds - (os.time() - firstJoinedAt)
			if remaining <= 0 then
				hideOffer()
				return
			end
			countdownLabel.Text = formatCountdown(remaining)
			task.wait(1)
		end
	end)
end

local function tryShowOffer()
	if purchaseBlocked or player:GetAttribute("StarterPackClaimed") ~= false then
		hideOffer()
		return
	end
	-- Ничего постороннего поверх основного гайда — та же причина, что и в
	-- NotifyService:Show. Баннер сам себя перепроверит, как только
	-- NeedsTutorial станет false (см. подписку внизу файла), окно
	-- предложения (FirstJoinedAt+OfferWindowSeconds) при этом не сдвигается
	-- — просто баннер не рисуется поверх гайда, пока он не пройден.
	if player:GetAttribute("NeedsTutorial") == true then
		hideOffer()
		return
	end
	local firstJoinedAt = tonumber(player:GetAttribute("FirstJoinedAt")) or 0
	if not forceOffer then
		if firstJoinedAt <= 0 then
			return -- атрибут ещё не пришёл от сервера ИЛИ игрок не подходит (см. DataService)
		end
		local remaining = pack.OfferWindowSeconds - (os.time() - firstJoinedAt)
		if remaining <= 0 then
			return -- окно уже прошло — баннер не показываем вообще, даже на миг
		end
	end
	updateBannerLayout()
	gui.Enabled = true
	player:SetAttribute("StarterPackOfferActive", true)
	setVisible(banner, true)
	rainbowToken += 1
	startRainbow(rainbowToken)
	floatToken += 1
	startBannerFloat(floatToken)
	countdownToken += 1
	startCountdown(countdownToken)
end

if banner and banner:IsA("GuiButton") then
	banner.Activated:Connect(openDetails)
end
if closeButton and closeButton:IsA("GuiButton") then
	closeButton.Activated:Connect(closeDetails)
end
if dimmer and dimmer:IsA("GuiButton") then
	dimmer.Activated:Connect(closeDetails)
elseif dimmer and dimmer:IsA("GuiObject") then
	-- Поддержка уже созданного UI, где Dimmer был обычным Frame.
	dimmer.Active = true
	dimmer.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			closeDetails()
		end
	end)
end

if buyButton and buyButton:IsA("GuiButton") then
	buyButton.Activated:Connect(function()
		if purchaseBlocked or player:GetAttribute("StarterPackClaimed") ~= false then
			hideOffer()
			return
		end
		if not pack.Id or pack.Id == 0 then
			warn("[StarterPackUI] Developer Product стартового пака ещё не создан (Config.DevProducts.StarterPack.Id = 0, src/shared/Config.lua)")
			return
		end
		purchaseBlocked = true
		local ok, err = pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, pack.Id)
		if not ok then
			purchaseBlocked = false
			warn("[StarterPackUI] Failed to open purchase prompt:", err)
			tryShowOffer()
		end
	end)
end

MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
	if userId ~= player.UserId or productId ~= pack.Id then return end
	purchaseBlocked = purchased == true
	if purchaseBlocked then hideOffer() else tryShowOffer() end
end)

-- Как только сервер подтвердил покупку (см. MonetizationService), баннер и
-- экран "что внутри" исчезают НАВСЕГДА для этого игрока — сразу, без
-- ожидания следующего захода.
player:GetAttributeChangedSignal("StarterPackClaimed"):Connect(function()
	if player:GetAttribute("StarterPackClaimed") == true then
		purchaseBlocked = true
		hideOffer()
	else
		tryShowOffer()
	end
end)

-- FirstJoinedAt приходит от DataService не мгновенно на самом первом кадре —
-- слушаем изменение атрибута ТОЖЕ, а не только пробуем один раз сразу.
player:GetAttributeChangedSignal("FirstJoinedAt"):Connect(tryShowOffer)
-- Как только гайд пройден — баннер (если ещё актуален по времени/статусу
-- покупки) должен появиться СРАЗУ, а не ждать следующего случайного триггера.
player:GetAttributeChangedSignal("NeedsTutorial"):Connect(tryShowOffer)
tryShowOffer()
