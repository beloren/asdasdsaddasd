--------------------------------------------------------------------------------
-- CustomCartUI (LocalScript)
-- ЕДИНСТВЕННЫЙ клиентский скрипт в проекте — существует ради трёх вещей:
--   1) Кастомный вид ProximityPrompt "Взять тележку" (Style = Custom
--      выставлен сервером в CartService, здесь только рисуем UI).
--   2) Пока тележка в руках, обычного промпта нет вообще (сервер его
--      выключает) — вместо него статичная подсказка на экране + клавиша E,
--      без мигания при ходьбе.
--   3) Кастомный хотбар кирки снизу экрана (вместо дефолтного Backpack) —
--      иконка + визуальный откат кулдауна.
-- Никакой игровой логики здесь нет: отпускание тележки и взмах киркой
-- подтверждает СЕРВЕР, клиент только просит/показывает.
--
-- UI НЕ СОЗДАЁТСЯ КОДОМ. Он лежит готовым в StarterGui (собран билдером
-- в Studio), Roblox сам клонирует его в PlayerGui — скрипт лишь находит
-- части по именам и подключает логику. Если готового ассета нет — строит
-- кодовый плейсхолдер сам (см. контракты у каждого блока ниже).
--------------------------------------------------------------------------------

local MarketplaceService = game:GetService("MarketplaceService")
local SocialService = game:GetService("SocialService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local LocalizationService = game:GetService("LocalizationService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local UiMotion = require(ReplicatedStorage.Shared.UiMotion)
local SoundVariation = require(ReplicatedStorage.Shared.SoundVariation)
local Localization = require(ReplicatedStorage.Shared.Localization)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)
local MutationVisuals = require(ReplicatedStorage.Shared.MutationVisuals)

-- ЗАЩИТА ОТ РАССИНХРОНА КОНФИГА (см. подробный комментарий в
-- tools/BuildAllUI.lua) — этот скрипт работает постоянно в игре, а не
-- один раз, так что подстраховка здесь ещё важнее: старый/неполный
-- Config.Shop не должен ронять весь клиентский UI.
Config.Shop = Config.Shop or {}
Config.Shop.CardsPerPage = Config.Shop.CardsPerPage or 6
Config.Shop.Tabs = Config.Shop.Tabs or { "Passes", "Deals" }
Config.Shop.Items = Config.Shop.Items or {}
Config.Shop.HintShowDuration = Config.Shop.HintShowDuration or 8
Config.Shop.HintHideDuration = Config.Shop.HintHideDuration or 55
Config.DevProducts = Config.DevProducts or {}
Config.DevProducts.CartFillByTier = Config.DevProducts.CartFillByTier or {}
Config.Referral = Config.Referral or {}
Config.Referral.MoneyMultiplierPerFriend = Config.Referral.MoneyMultiplierPerFriend or 1
Config.Referral.MaxFriends = Config.Referral.MaxFriends or 3
-- Config.QuickBar.* защитные дефолты УБРАНЫ отсюда — фичи "быстрых кнопок
-- геймпассов" (GamepassQuickBar) в игре больше нет целиком, по прямому
-- запросу. Сам Config.QuickBar (таблица) в Config.lua НЕ удалён — его всё
-- ещё частично читает tools/BuildAllUI.lua (HintImageId для значка на
-- кнопке магазина), это отдельное, не связанное использование.

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local localeId = LocalizationService.RobloxLocaleId
local translatorOk, playerTranslator = pcall(
	LocalizationService.GetTranslatorForPlayerAsync,
	LocalizationService,
	player
)
if translatorOk and playerTranslator and playerTranslator.LocaleId ~= "" then
	-- LocaleId Translator'а учитывает выбранный игроком Experience Language,
	-- тогда как RobloxLocaleId относится к языку самого приложения Roblox.
	localeId = playerTranslator.LocaleId
end
playerGui:SetAttribute("ActiveLocaleId", Localization.Normalize(localeId))
local function tr(source, args)
	return Localization.Translate(localeId, source, args)
end
Localization.Bind(playerGui, localeId)
task.defer(function()
	Localization.Bind(workspace, localeId)
end)
local activateProtection = nil
local playUiClick = nil


-- Окна билдера рассчитаны на desktop-размеры. На узком экране уменьшаем
-- только крупные панели, а основные touch-кнопки слегка увеличиваем.
local LARGE_UI = {
	SettingsMenu = true,
	ShopUi = true,
	UpgradeShopCards = true,
}

local function applyAdditionalMobileScale(target)
	if not (UserInputService.TouchEnabled and target and target:IsA("GuiObject")) then return end
	local scale = target:FindFirstChild("AdditionalMobileScale") or Instance.new("UIScale")
	scale.Name = "AdditionalMobileScale"
	scale.Scale = 0.75
	scale.Parent = target
end

-- Настройки и магазин находятся в разных ScreenGui, поэтому выравниваем их
-- одной схемой здесь. Это также исправляет позицию в уже собранных Studio-ассетах.
local function applyLeftCornerButtonLayout(gui)
	local button
	local row
	if gui.Name == "SettingsMenu" then
		button = gui:FindFirstChild("GearButton", true)
		row = 0
	elseif gui.Name == "CollectionMenu" then
		-- BookButton собирается прямо в StarterGui/CollectionMenu и владеет
		-- своей позицией в Studio. Этот общий раскладчик не должен её сдвигать.
		return
	end
	if not (button and button:IsA("GuiObject")) then
		return
	end
	applyAdditionalMobileScale(button)

	local buttonSize = math.max(button.Size.Y.Offset, button.AbsoluteSize.Y, 44)
	local edgeInset = UserInputService.TouchEnabled and 12 or 14
	local gap = 8
	if UserInputService.TouchEnabled then
		buttonSize = math.max(buttonSize, 48)
		-- Offset-кнопки доводим до удобной touch-зоны, но Scale-размеры из
		-- кастомного Studio UI не переводим в пиксели и никогда не уменьшаем.
		if button.Size.X.Scale == 0 and button.Size.Y.Scale == 0 then
			local width = math.max(button.Size.X.Offset, 48)
			local height = math.max(button.Size.Y.Offset, 48)
			button.Size = UDim2.fromOffset(width, height)
			buttonSize = math.max(buttonSize, height)
		end
		button.AnchorPoint = Vector2.new(0, 0.5)
		button.Position = UDim2.new(0, edgeInset, 0.5, ({ -21, 37, 95 })[row + 1])
		return
	end
	local centerOffset = (buttonSize + gap) / 2
	button.AnchorPoint = Vector2.new(0, 0.5)
	button.Position = UDim2.new(0, edgeInset, 0.5, row == 0 and -centerOffset or row == 1 and centerOffset or centerOffset + buttonSize + gap)
end

local function applyDeviceScale(gui)
	if not gui:IsA("ScreenGui") then
		return
	end
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
		gui.ClipToDeviceSafeArea = true
	end)
	applyLeftCornerButtonLayout(gui)
	local viewport = workspace.CurrentCamera.ViewportSize
	local target = gui:FindFirstChild("Panel", true) or gui:FindFirstChild("Responses", true) or gui:FindFirstChild("Bar", true)
	if gui.Name == "SettingsMenu" and UserInputService.TouchEnabled then
		if not target then
			return
		end
		local baseWidth = target:GetAttribute("MobileBaseWidth")
		local baseHeight = target:GetAttribute("MobileBaseHeight")
		if not baseWidth or not baseHeight then
			baseWidth = target.Size.X.Offset > 0 and target.Size.X.Offset or target.AbsoluteSize.X
			baseHeight = target.Size.Y.Offset > 0 and target.Size.Y.Offset or target.AbsoluteSize.Y
			baseWidth = baseWidth > 0 and baseWidth or 320
			baseHeight = baseHeight > 0 and baseHeight or 430
			target:SetAttribute("MobileBaseWidth", baseWidth)
			target:SetAttribute("MobileBaseHeight", baseHeight)
		end
		local scale = target:FindFirstChild("DeviceScale")
		if not scale then
			scale = Instance.new("UIScale")
			scale.Name = "DeviceScale"
			scale.Parent = target
		end
		scale.Scale = math.min(0.7, (viewport.X - 24) / baseWidth, (viewport.Y - 48) / baseHeight)
	elseif LARGE_UI[gui.Name] then
		local oldScale = gui:FindFirstChild("DeviceScale")
		if oldScale then
			oldScale:Destroy()
		end
		if not target then
			return
		end
		local scale = target:FindFirstChild("DeviceScale")
		if not scale then
			scale = Instance.new("UIScale")
			scale.Name = "DeviceScale"
			scale.Parent = target
		end
		scale.Scale = math.min(1, viewport.X / 820, viewport.Y / 540)
	elseif gui.Name == "CartInteractionUi" and UserInputService.TouchEnabled then
		local promptScale = (viewport.X < 350 and 0.95 or 1.08) * 0.95 -- v20.18: было ×0.75 — подсказки были мелкими
		for _, name in { "CartPromptGui", "CartDropHintGui", "TalkPromptGui" } do
			local frame = gui:FindFirstChild(name, true)
			if frame then
				local scale = frame:FindFirstChild("MobileScale")
				if not scale then
					scale = Instance.new("UIScale")
					scale.Name = "MobileScale"
					scale.Parent = frame
				end
				scale.Scale = promptScale
				frame.Position = UDim2.new(0.5, 45, 1, -20)
			end
		end
		local fillOffer = gui:FindFirstChild("FillCartOffer", true)
		if fillOffer then
			local scale = fillOffer:FindFirstChild("MobileScale") or Instance.new("UIScale")
			scale.Name = "MobileScale"
			scale.Scale = (viewport.X < 500 and 0.82 or 1) * 0.75
			scale.Parent = fillOffer
			fillOffer.AnchorPoint = Vector2.new(1, 0.5)
			fillOffer.Position = UDim2.new(1, -12, 0.5, 0)
		end
	elseif gui.Name == "Hud" and UserInputService.TouchEnabled then
		local container = gui:FindFirstChild("HudGui", true)
		if container then
			local scale = container:FindFirstChild("MobileScale")
			if not scale then
				scale = Instance.new("UIScale")
				scale.Name = "MobileScale"
				scale.Parent = container
			end
			scale.Scale = 0.79

			-- ФИКС "ДЕНЬГИ/РЕБИРТХИ ДОЛЖНЫ БЫТЬ ТОЧНО СПРАВА СВЕРХУ": раньше
			-- позиция HudGui на телефоне была ЦЕЛИКОМ тем, что задал
			-- билдер в Studio-ассете под десктоп — на некоторых
			-- соотношениях сторон экрана это визуально съезжало не в
			-- угол. Явно фиксируем якорь и позицию в правый верхний угол
			-- каждый раз, когда применяется мобильный масштаб — не
			-- полагаемся на то, что уже стоит в ассете.
			if container:IsA("GuiObject") then
				container.AnchorPoint = Vector2.new(1, 0)
				container.Position = UDim2.new(1, -2, 0, 10)
			end
		end
	end
end
local function refreshDeviceScales()
	for _, gui in playerGui:GetChildren() do
		applyDeviceScale(gui)
	end
end
playerGui.ChildAdded:Connect(function(child)
	task.defer(applyDeviceScale, child)
end)
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshDeviceScales)
refreshDeviceScales()

-- JumpPower временно становится нулевым во время кулдауна тележки. На
-- некоторых мобильных версиях PlayerModule из-за этого прячет JumpButton и
-- не возвращает его после восстановления силы прыжка. Следим именно за
-- штатной кнопкой, не создавая поверх неё второй конкурирующий контрол.
if UserInputService.TouchEnabled then
	local trackedJumpButtons = {}
	local restoringJumpButton = false
	local function preserveJumpButton(instance)
		if instance.Name ~= "JumpButton" or not instance:IsA("GuiObject") or trackedJumpButtons[instance] then return end
		trackedJumpButtons[instance] = true
		instance.Visible = true
		instance:GetPropertyChangedSignal("Visible"):Connect(function()
			if instance.Parent and not instance.Visible and not restoringJumpButton then
				restoringJumpButton = true
				task.defer(function()
					if instance.Parent then instance.Visible = true end
					restoringJumpButton = false
				end)
			end
		end)
	end
	for _, descendant in playerGui:GetDescendants() do
		preserveJumpButton(descendant)
	end
	playerGui.DescendantAdded:Connect(preserveJumpButton)
end

local function refreshMobileInteractionLayout()
	if not UserInputService.TouchEnabled then
		return
	end
	local interactionGui = playerGui:FindFirstChild("CartInteractionUi")
	local interactionVisible = false
	if interactionGui then
		for _, name in { "CartPromptGui", "CartDropHintGui", "TalkPromptGui" } do
			local frame = interactionGui:FindFirstChild(name, true)
			if frame then
				if frame:GetAttribute("MobileReleaseCrystal") == true then
					-- RELEASE переносимого кристалла должен находиться выше пары
					-- [кристалл][кирка], а не перекрывать её touch-target'ом.
					frame.AnchorPoint = Vector2.new(0.5, 1)
					frame.Position = UDim2.new(0.5, 0, 1, -112)
					frame.Size = UDim2.fromOffset(150, 38)
				else
					frame.Position = UDim2.new(0.5, 45, 1, -20)
					local baseSize = frame:GetAttribute("MobileBaseSize")
					if typeof(baseSize) == "Vector2" then
						frame.Size = UDim2.fromOffset(baseSize.X, baseSize.Y)
					end
				end
				interactionVisible = interactionVisible or frame.Visible
			end
		end
	end

	local actionX = interactionVisible and (workspace.CurrentCamera.ViewportSize.X < 350 and -105 or -115) or 0
	local hotbarGui = playerGui:FindFirstChild("PickaxeHotbar")
	local hotbarSlot = hotbarGui and hotbarGui:FindFirstChild("Slot", true)
	if hotbarSlot then
		applyAdditionalMobileScale(hotbarSlot)
		hotbarSlot.Position = UDim2.new(0.5, actionX, 1, -20)
	end
	local actionGui = playerGui:FindFirstChild("ActionButtons")
	local protectionButton = actionGui and actionGui:FindFirstChild("ProtectionButton", true)
	if protectionButton then
		applyAdditionalMobileScale(protectionButton)
		protectionButton.Position = UDim2.new(0.5, actionX, 1, -20)
	end
end

-- ФИКС "КНОПКИ ТО СНИЗУ ТО СВЕРХУ" НА ТЕЛЕФОНЕ: раньше позиция
-- CartPromptGui/CartDropHintGui/TalkPromptGui пересчитывалась ТОЛЬКО из
-- пары конкретных мест кода (см. refreshActivePrompt/refreshDropHint
-- ниже) — если один из этих трёх фреймов становился видимым каким-то
-- ДРУГИМ путём (или просто раньше, чем успевал отработать код, который
-- зовёт refresh), он на мгновение показывался в своей "заводской"
-- позиции из StarterGui-ассета (какой её сделал tools/BuildAllUI.lua
-- под десктоп), а не в мобильной. Слушаем Visible НАПРЯМУЮ у каждого
-- фрейма — теперь позиция гарантированно пересчитывается КАЖДЫЙ раз,
-- когда фрейм показывается/прячется, независимо от того, откуда пришло
-- изменение.
if UserInputService.TouchEnabled then
	task.spawn(function()
		local interactionGui = playerGui:WaitForChild("CartInteractionUi", 5)
		if not interactionGui then
			return
		end
		for _, name in { "CartPromptGui", "CartDropHintGui", "TalkPromptGui" } do
			local frame = interactionGui:FindFirstChild(name, true)
			if frame then
				frame:GetPropertyChangedSignal("Visible"):Connect(refreshMobileInteractionLayout)
			end
		end
		refreshMobileInteractionLayout()
	end)
end

-- Метка создаётся локально, поэтому надпись своей базы не видят остальные.
task.spawn(function()
	local plots = workspace:WaitForChild("Plots", 5)
	if not plots then
		return
	end
	local function markPlot(instance)
		if not instance:IsA("Model") then
			return false
		end
		local pad = instance.PrimaryPart or instance:FindFirstChild("PlotPad", true)
		local plotIndex = player:GetAttribute("PlotIndex")
		local isOwnPlot = pad and (pad:GetAttribute("OwnerUserId") == player.UserId
			or (plotIndex and instance.Name == "PlotPad_" .. tostring(plotIndex)))
		if not isOwnPlot then
			return false
		end
		if pad:FindFirstChild("OwnBaseMarker") then
			return true
		end
		local marker = Instance.new("BillboardGui")
		marker.Name = "OwnBaseMarker"
		-- РАЗМЕР — по прямому запросу больше НЕ в Offset (пикселях).
		--
		-- ПРИЧИНА: BillboardGui.Size в Offset — известный, много раз
		-- описанный на девфоруме баг: с какого-то расстояния такой
		-- билборд начинает не уменьшаться, а РАСТИ ("keeps growing the
		-- farther away the camera gets" — ровно то, на что жаловались).
		-- Scale-компонента UDim2 у BillboardGui — это РАЗМЕР В СТАДАХ
		-- (не проценты, как у обычного GuiObject), и она уменьшается с
		-- расстоянием НОРМАЛЬНО, по правилам перспективы, без этого бага.
		--
		-- Раз в 0.2с (см. updateMarkerScale ниже) размер в стадах
		-- пересчитывается ПРОПОРЦИОНАЛЬНО расстоянию до камеры — это
		-- специально КОМПЕНСИРУЕТ обычное уменьшение от перспективы, так
		-- что итоговый видимый размер на экране остаётся ПОСТОЯННЫМ что
		-- вблизи, что издалека, вместо того чтобы расти.
		marker.Size = UDim2.fromScale(0, 0) -- пересчитывается сразу же ниже, это просто безопасное значение по умолчанию
		-- ПОДНЯТО СИЛЬНО ВЫШЕ по прямому запросу (было 30).
		marker.StudsOffset = Vector3.new(0, 52, 0)
		marker.AlwaysOnTop = true
		marker.LightInfluence = 0
		marker.MaxDistance = 500
		marker.Adornee = pad
		marker.Parent = pad

		-- РЕФЕРЕНСНАЯ ТОЧКА КАЛИБРОВКИ: "на расстоянии REFERENCE_DISTANCE
		-- студов от камеры билборд должен быть REFERENCE_WIDTH на
		-- REFERENCE_HEIGHT студов в мире" — эти два числа и есть то, что
		-- стоит покрутить, если итоговый видимый размер покажется
		-- слишком крупным/мелким. 30 студов — то же расстояние, на
		-- котором уже держится проверка видимости чуть ниже (свои 35).
		local REFERENCE_DISTANCE = 30
		local REFERENCE_WIDTH = 9.6
		local REFERENCE_HEIGHT = 8.0
		local function updateMarkerScale()
			local camera = workspace.CurrentCamera
			if not (camera and marker.Parent) then return end
			local distance = (camera.CFrame.Position - pad.Position).Magnitude
			-- studSize ∝ distance — компенсирует обычное перспективное
			-- уменьшение (apparent ∝ studSize / distance), давая на
			-- выходе постоянный видимый размер вместо уменьшающегося
			-- ИЛИ (в баг-версии на Offset) неожиданно растущего.
			local factor = math.max(distance, 1) / REFERENCE_DISTANCE
			marker.Size = UDim2.fromScale(REFERENCE_WIDTH * factor, REFERENCE_HEIGHT * factor)
		end
		updateMarkerScale()

		-- АВАТАРКА ИГРОКА — по референсу (круглая иконка с цветной
		-- обводкой + ник под ней, тот же стиль, что и подписи над
		-- грядками в Grow a Garden). Раньше здесь был статичный текст
		-- "YOUR BASE" — теперь ник владельца и его портрет, что сразу
		-- узнаваемо на любом участке, не только на своём.
		--
		-- Size ниже — В ПРОЦЕНТАХ (Scale) от canvas'а marker, а НЕ в
		-- пикселях: canvas теперь сам меняет реальный размер в стадах
		-- каждые 0.2с (см. updateMarkerScale выше), и дочерние элементы
		-- обязаны быть в Scale, чтобы схлопываться/расти вместе с ним, а
		-- не оставаться прежнего абсолютного пиксельного размера.
		--
		-- Canvas НЕ квадратный (REFERENCE_WIDTH ≠ REFERENCE_HEIGHT), а
		-- аватарке нужен настоящий круг — просто взять одинаковые X/Y
		-- в Scale дало бы ЭЛЛИПС (одинаковая ДОЛЯ разных по факту сторон
		-- canvas — это разные абсолютные пиксели). Ширина по Scale
		-- пересчитана с поправкой на соотношение сторон canvas
		-- (REFERENCE_HEIGHT / REFERENCE_WIDTH), чтобы в итоговых пикселях
		-- получался именно круг, а не сплюснутый овал.
		local avatarHeightScale = 0.65
		local avatarWidthScale = avatarHeightScale * (REFERENCE_HEIGHT / REFERENCE_WIDTH)
		local avatar = Instance.new("ImageLabel")
		avatar.Name = "Avatar"
		avatar.AnchorPoint = Vector2.new(0.5, 0)
		avatar.Position = UDim2.fromScale(0.5, 0.03)
		avatar.Size = UDim2.fromScale(avatarWidthScale, avatarHeightScale)
		avatar.BackgroundColor3 = Color3.fromRGB(120, 75, 45) -- видно как плейсхолдер, пока не подгрузился настоящий портрет
		avatar.Image = ""
		avatar.ScaleType = Enum.ScaleType.Fit
		avatar.Parent = marker
		local avatarCorner = Instance.new("UICorner")
		avatarCorner.CornerRadius = UDim.new(1, 0) -- квадрат → идеальный круг (Size.X == Size.Y выше)
		avatarCorner.Parent = avatar
		local avatarRing = Instance.new("UIStroke")
		avatarRing.Name = "Ring"
		avatarRing.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		avatarRing.Thickness = 4
		avatarRing.Color = Color3.fromRGB(120, 220, 90) -- зелёная обводка, как на референсе
		avatarRing.Parent = avatar

		-- Портрет игрока — единственный НЕ-плейсхолдерный ресурс здесь:
		-- GetUserThumbnailAsync — обычный, официальный способ получить
		-- настоящую аватарку любого игрока по UserId. Не блокирует показ
		-- надписи с ником — она появляется сразу, картинка донагружается
		-- следом, когда будет готова.
		task.spawn(function()
			local ok, content = pcall(function()
				local thumb, isReady = Players:GetUserThumbnailAsync(
					player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100
				)
				return isReady and thumb or nil
			end)
			if ok and content and avatar.Parent then
				avatar.Image = content
				avatar.BackgroundTransparency = 1 -- плейсхолдер-цвет больше не нужен под настоящим фото
			end
		end)

		local label = Instance.new("TextLabel")
		label.Name = "NameLabel"
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.fromScale(0.5, 0.68)
		label.Size = UDim2.fromScale(1, 0.32)
		label.BackgroundTransparency = 1
		require(game:GetService("ReplicatedStorage").Shared.UiKit).StyleText(label, "Number") -- v20: шрифт темы
		label.TextSize = 22
		label.TextColor3 = Color3.fromRGB(255, 225, 90)
		-- "<ник>'s Base" — по формату референса ("...'s Garden"), просто
		-- со словом этой игры ("Base"), а не позаимствованным из другой.
		label.Text = ("%s's Base"):format(player.DisplayName ~= "" and player.DisplayName or player.Name)
		label.TextScaled = true
		label.Parent = marker
		local boldStroke = Instance.new("UIStroke")
		boldStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		boldStroke.Thickness = 1.5
		boldStroke.Color = Color3.fromRGB(20, 20, 25)
		boldStroke.Parent = label
		task.spawn(function()
			while marker.Parent and player.Parent do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root then
					local horizontalOffset = Vector3.new(root.Position.X - pad.Position.X, 0, root.Position.Z - pad.Position.Z)
					marker.Enabled = horizontalOffset.Magnitude > 35
				else
					marker.Enabled = true
				end
				updateMarkerScale()
				task.wait(0.2)
			end
		end)
		return true
	end
	while player.Parent do
		for _, plot in plots:GetChildren() do
			if markPlot(plot) then
				return
			end
		end
		task.wait(0.5)
	end
end)

--------------------------------------------------------------------------------
-- "ЛЮБОЙ ПРОКСИМИТИ-ПРОМПТ СЕЙЧАС ПОКАЗАН?" — общий трекер, используется
-- туториалом ниже (карточка уходит к верху экрана, пока показан промпт —
-- см. showInteractiveTutorial/updateCardDock). Не привязан к конкретному
-- виду промпта (тележка, NPC, сейф, жеода...) — считает ЛЮБОЙ.
--
-- Не переиспользует более позднюю систему activePrompt/shownPrompts (см.
-- ниже по файлу, "1) Кастомный промпт") напрямую, потому что та объявлена
-- ПОСЛЕ этого места — в Lua локальная переменная видна только коду,
-- написанному текстуально ниже её объявления. Здесь свой независимый
-- счётчик на тех же самых событиях ProximityPromptService.
--
-- Считаем ЛЮБОЙ показанный промпт (не только Style = Custom): если игрок
-- видит хоть какую-то подсказку взаимодействия, карточка гайда всё равно
-- не должна лезть поверх неё, даже если это дефолтный серый Roblox-промпт.
local shownPromptCount = 0
local promptVisibilityListeners = {}
local function notifyPromptVisibilityListeners()
	local visible = shownPromptCount > 0
	for _, listener in promptVisibilityListeners do
		task.spawn(listener, visible)
	end
end
ProximityPromptService.PromptShown:Connect(function()
	shownPromptCount += 1
	if shownPromptCount == 1 then notifyPromptVisibilityListeners() end
end)
ProximityPromptService.PromptHidden:Connect(function()
	shownPromptCount = math.max(0, shownPromptCount - 1)
	if shownPromptCount == 0 then notifyPromptVisibilityListeners() end
end)

--------------------------------------------------------------------------------
-- "ЛЮБОЕ ДРУГОЕ ГУИ СЕЙЧАС ОТКРЫТО?" — по прямому запросу докинг карточки
-- к верху экрана должен срабатывать не только на проксимити-промпты
-- (см. shownPromptCount выше), но и на любое модальное окно/панель:
-- магазин, апгрейд-карты, диалог NPC, дневная награда, коллекция и т.д.
--
-- Список повторяет тот же реестр "модальных панелей", которым уже
-- пользуется ModalDimmerGuard.client.lua для своей задачи (гашение
-- зависшего диммера) — это единственное существующее в проекте место,
-- где явно перечислены все модальные окна игры по именам, поэтому он и
-- берётся как источник истины, плюс несколько экранов, которых там нет
-- (диалог с NPC, карточки апгрейда, настройки, окно ребёрта, финальный
-- экран возврата — они не участвуют в диммере, но это тоже "открытое
-- гуи" в смысле этого запроса).
--
-- НЕ включены сюда: постоянно видимый HUD/хотбар/квест-плашка (они не
-- "открываются" игроком, а всегда на экране) и мировые billboard-пузыри
-- диалога (ZavtrackDialog у меча-NPC) — это не полноэкранная панель, а
-- маленькая надпись прямо над головой NPC.
local MODAL_GUI_NAMES = {
	CollectionMenu = { "Submenu", "MutationBookPanel" },
	DailyRewardUi = { "Panel" },
	-- OpeningOverlay ДОБАВЛЕН. Раньше его тут не было, и это была настоящая
	-- дыра: во время анимации вскрытия жеоды все остальные панели GeodeUi
	-- скрыты, то есть anyModalGuiVisible() возвращал false — и карточка
	-- гайда со своей кнопкой уезжала обратно НАВЕРХ, на DisplayOrder 1100,
	-- прямо поверх шапки меню с крестиком. Именно на этом шаге («открой
	-- жеоду») игроки и жаловались, что окно не закрывается.
	GeodeUi = { "VaultPanel", "PodiumPanel", "BuyGeodesPanel", "OpenCountMenu", "OpeningOverlay" },
	GroupRewardUi = { "Gift", "GiftHalfLeft", "GiftHalfRight", "Card" },
	LikeRewardUi = { "Gift", "GiftHalfLeft", "GiftHalfRight", "Card" },
	ShopUi = { "Panel" },
	SkinUi = { "Panel" },
	PerkUi = { "Panel" }, -- v8: чемоданчик перков престижа
	StarterPackOffer = { "Details" },
	UpgradeShopCards = { "Panel", "UpgradePanel", "Cards" },
	UpgradeShopUi = { "Panel" },
	MerchantUi = { "Panel" },
	IslandUi = { "Panel" },
	DropPreviewUi = { "Panel" },
	InventoryUi = { "Panel" },
	SettingsMenu = { "Panel" },
	ReturnScreenUi = { "Panel" },
	RebirthDialogButtons = { "Panel" },
	QuestUi = { "QuestModal" },
}

-- Дёшево: фиксированный маленький список имён, FindFirstChild по каждому.
-- Не событийная система (в отличие от промптов выше) — у стольких разных
-- скриптов, независимо открывающих свои панели, нет единой точки, откуда
-- можно было бы подписаться на "Visible изменился" всех разом без риска
-- пропустить одну из них. Опрашивается тем же циклом 0.2с, что и
-- refreshObjective ниже (см. вызов updateCardDock() в нём) — второй
-- отдельный цикл был бы лишним.
local function anyModalGuiVisible()
	for guiName, modalNames in MODAL_GUI_NAMES do
		local modalGui = playerGui:FindFirstChild(guiName)
		if modalGui and (not modalGui:IsA("ScreenGui") or modalGui.Enabled) then
			for _, name in modalNames do
				local modal = modalGui:FindFirstChild(name, true)
				if modal and modal:IsA("GuiObject") and modal.Visible then
					return true
				end
			end
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- ОБУЧЕНИЕ ПЕРЕЕХАЛО ОТСЮДА (v7).
--
-- Здесь жила функция showInteractiveTutorial — двенадцатишаговая машина
-- состояний на ~1560 строк, целиком клиентская. Её больше нет: шаги стали
-- данными (Config.Tutorial.Steps), состояние ведёт сервер
-- (TutorialService), а рисует диалоговое окно отдельный LocalScript
-- src/client/TutorialUI.client.lua.
--
-- ПОЧЕМУ ПЕРЕПИСАЛИ, А НЕ ПОЧИНИЛИ. К моменту переделки гайд расходился с
-- игрой на трёх шагах из первых трёх: он ждал атрибут CarryingCart (с v12
-- у новичка вместо тележки упаковка), проверял MineActive как "тележка
-- стоит в зоне шахты" (в новом MineService это значит просто "есть тележка
-- со свободным местом") и отсчитывал капли авто-добычи, которой больше не
-- существует (руда добывается экспедицией). Плюс прогресс хранился в
-- локальной переменной и обнулялся при каждом перезаходе.
--
-- Вспомогательные части, которые гайд использовал и которые НУЖНЫ
-- остальному файлу (anyModalGuiVisible, updateCardDock, playUiClick),
-- остались на своих местах выше и ниже — удалён только сам туториал.
--------------------------------------------------------------------------------

-- Ждём RemoteEvent'ы АСИНХРОННО отдельными корутинами, чтобы блокирующий
-- WaitForChild не задерживал подписку на события промпта/хотбара.
local dropRemote = nil
task.spawn(function()
	dropRemote = ReplicatedStorage.Shared:WaitForChild("DropCartRequest")
end)

--------------------------------------------------------------------------------
-- НАСТРОЙКИ — шестерёнка в углу экрана, не завязана на режим (кирка/
-- тележка) — видна всегда. Звук — локально через SoundGroup "SFX"
-- (Sfx.lua создаёт её на сервере, здесь просто крутим Volume у себя,
-- сервер и другие игроки ничего не замечают). Промокоды — сервер сам
-- проверяет валидность/повторное использование (DataService:RedeemCode).
--
-- КОНТРАКТ (StarterGui/SettingsMenu) — необязателен, есть плейсхолдер:
--   ScreenGui "SettingsMenu"
--   ├─ GuiObject "GearButton" (TextButton/ImageButton ИЛИ Frame/ImageLabel) → Icon
--   └─ Frame "Panel" (скрыт по умолчанию, открывается кликом по шестерёнке)
--       ├─ GuiObject "SoundToggle"
--       ├─ TextBox "CodeInput"
--       ├─ GuiObject "RedeemButton"
--       ├─ TextLabel "ResultText"
--       └─ GuiObject "CloseButton" (необязателен)
--
-- ВАЖНО: кликабельные элементы (GearButton/CloseButton/SoundToggle/
-- RedeemButton) МОГУТ быть либо настоящими TextButton/ImageButton (тогда
-- используется штатный MouseButton1Click), ЛИБО простым Frame/ImageLabel
-- (тогда клик ловится вручную через InputBegan). Раньше контракт
-- документировал GearButton как Frame, а код при этом жёстко требовал
-- gearButton.MouseButton1Click — у Frame такого события нет, поэтому если
-- шестерёнку в Studio собрали как Frame (как и написано в контракте),
-- скрипт падал с ошибкой ДО подключения клика — и панель настроек вообще
-- переставала открываться. connectClick() ниже — исправление этого бага:
-- работает с любым из двух вариантов и не роняет весь скрипт при ошибке.
--------------------------------------------------------------------------------

local SoundService = game:GetService("SoundService")
local uiSoundGroup = SoundService:FindFirstChild("UI")
if not uiSoundGroup then
	uiSoundGroup = Instance.new("SoundGroup")
	uiSoundGroup.Name = "UI"
	uiSoundGroup.Parent = SoundService
end
local musicSoundGroup = SoundService:FindFirstChild("Music")
if not musicSoundGroup then
	musicSoundGroup = Instance.new("SoundGroup")
	musicSoundGroup.Name = "Music"
	musicSoundGroup.Parent = SoundService
end
local musicUserVolume = 1
local musicIntroMultiplier = 1
local function applyMusicVolume()
	musicSoundGroup.Volume = Config.Music.Volume * musicUserVolume * musicIntroMultiplier
end
local function updateMusicIntroMultiplier()
	musicIntroMultiplier = (player:GetAttribute("AssetsLoaded") ~= true
		or player:GetAttribute("IntroActive") == true) and 0.35 or 1
	applyMusicVolume()
end
updateMusicIntroMultiplier()
player:GetAttributeChangedSignal("AssetsLoaded"):Connect(updateMusicIntroMultiplier)
player:GetAttributeChangedSignal("IntroActive"):Connect(updateMusicIntroMultiplier)

-- Единая точка "звук клика по ЛЮБОЙ кнопке в игре" — клиентский, без 3D-
-- позиционирования (не нужно, это UI, а не мир), но через тот же SoundGroup
-- "SFX" (Sfx.lua создаёт её на сервере) — общая громкость с остальными
-- звуками игры. sfxGroup подхватывается лениво (WaitForChild ассинхронно
-- ниже в SettingsMenu уже делает то же самое) — если группа ещё не успела
-- реплицироваться в момент самого первого клика, звук просто тихо не
-- сыграет один раз, ничего не ломая.
local uiSfxGroup = nil
task.spawn(function()
	uiSfxGroup = SoundService:WaitForChild("SFX", 5)
end)

playUiClick = function(soundName)
	local entry = Config.Sounds[soundName or "UiButtonClick"]
	if not entry then
		return
	end
	local soundId = SoundVariation.Select(soundName or "UiButtonClick", entry)
	if not soundId then return end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = entry.Volume or 0.5
	sound.SoundGroup = uiSoundGroup
	sound.Parent = SoundService
	sound:Play()
	game:GetService("Debris"):AddItem(sound, 6)
end

-- Звук "разговора" NPC (Config.Sounds.DialogueTypewriter) — ОДИН
-- Sound-инстанс на ВЕСЬ диалог целиком (не на каждую печатающуюся строку —
-- typeText вызывается по несколько раз за один разговор: сперва
-- приветствие, потом ещё раз на текст каждого выбранного пункта меню, и
-- играть заново на каждый такой вызов означало бы снова копить кашу из
-- наложенных друг на друга запусков). Зациклен (Looped = true) — если
-- реплика длиннее одного проигрывания файла, звук просто крутится по
-- кругу сам, ничего перезапускать не нужно. Останавливается и уничтожается
-- ЦЕЛИКОМ строго при закрытии диалога (см. closeDialog/closeNpcDialog),
-- не раньше.
-- ИСПРАВЛЕНИЕ БАГА "ЗВУК ДИАЛОГА ИГРАЕТ ВЕЧНО ПОСЛЕ СМЕРТИ".
--
-- ЧТО БЫЛО. Звук зациклен (Looped) и живёт в SoundService — то есть НЕ
-- уничтожается при респавне персонажа (в отличие от всего, что лежит
-- внутри Character). Остановить его мог только closeDialog. А сторож
-- дистанции, который и должен закрывать диалог, при смерти игрока
-- натыкался на отсутствующий HumanoidRootPart и делал `return` — то есть
-- МОЛЧА ВЫХОДИЛ, вместо того чтобы закрыть диалог. Персонаж умер, диалог
-- формально остался открытым навсегда, и "голос" NPC гудел до конца
-- сессии, накладываясь на новый при следующем разговоре.
--
-- ЧТО СТАЛО. Два независимых уровня защиты:
--   1. Каждый созданный звук регистрируется в activeTalkingSounds. Смерть
--      или респавн глушат ВСЕ такие звуки разом — даже если какой-то
--      диалог по недосмотру забыл про свой closeDialog.
--   2. Диалоги регистрируют свои закрывашки (registerDialogCloser), и те
--      вызываются на смерти — чтобы закрылось и само окно/подсветка NPC,
--      а не только звук.
local activeTalkingSounds = {} -- [Sound] = true, пока играет
local dialogClosers = {}       -- список closeDialog-функций всех диалогов

local function startTalkingSound()
	local entry = Config.Sounds.DialogueTypewriter
	if not entry or entry.Id == "rbxassetid://0" then
		return nil -- звук ещё не задан — ничего не создаём и не падаем
	end
	local sound = Instance.new("Sound")
	sound.SoundId = entry.Id
	sound.Volume = entry.Volume or 0.5
	sound.Looped = true
	sound.SoundGroup = uiSoundGroup
	sound.Parent = SoundService
	sound:Play()
	activeTalkingSounds[sound] = true
	return sound
end

local function stopTalkingSound(sound)
	if sound then
		activeTalkingSounds[sound] = nil
		sound:Stop()
		sound:Destroy()
	end
end

local function stopAllTalkingSounds()
	for sound in activeTalkingSounds do
		activeTalkingSounds[sound] = nil
		pcall(function()
			sound:Stop()
			sound:Destroy()
		end)
	end
end

local function registerDialogCloser(closer)
	table.insert(dialogClosers, closer)
end

-- Закрывает все открытые диалоги и глушит их звуки. pcall на каждой
-- закрывашке — один сбойный диалог не должен помешать закрыть остальные
-- и (главное) выключить звук.
local function closeAllDialogs()
	for _, closer in dialogClosers do
		pcall(closer)
	end
	stopAllTalkingSounds()
end

-- Смерть и респавн — два РАЗНЫХ момента, и нужны оба: Died срабатывает
-- сразу (звук глохнет мгновенно, а не через несколько секунд ожидания
-- респавна), CharacterAdded ловит случаи, когда Died по какой-то причине
-- не пришёл (телепорт, ResetOnSpawn, смена персонажа).
local function watchCharacterForDialogReset(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid.Died:Connect(closeAllDialogs)
	end
end

if player.Character then
	task.spawn(watchCharacterForDialogReset, player.Character)
end
player.CharacterAdded:Connect(function(character)
	closeAllDialogs()
	task.spawn(watchCharacterForDialogReset, character)
end)

-- Подключает "клик" к любому GuiObject: если это настоящая кнопка — обычный
-- MouseButton1Click, если просто Frame/ImageLabel — эмулируем через
-- InputBegan (мышь + тач). pcall — чтобы ошибка на одном элементе не убила
-- остальную инициализацию скрипта (как было раньше).
-- Какой звук играть при клике по элементу интерфейса.
--
-- РАНЬШЕ здесь была маршрутизация ПО ИМЕНИ кнопки: имя содержит "close" /
-- "cancel" / "back" — играем UiMenuClose, "tab" / "category" — UiTabSwitch,
-- "claim" / "confirm" / "buy" / "collect" / "equip" — UiConfirm, "open" /
-- "menu" / "shop" / "settings" / "book" — UiMenuOpen, и только всё
-- остальное — UiButtonClick. Из-за этого клики по интерфейсу звучали
-- ПЯТЬЮ разными звуками, и замена одного лишь UiButtonClick исправляла
-- меньшинство кнопок — большинство продолжало играть старые звуки.
--
-- ТЕПЕРЬ любой клик по любому элементу — один и тот же UiButtonClick.
-- Интерфейс должен звучать одинаково, иначе воспринимается как склейка из
-- нескольких разных игр.
--
-- Явно переданный soundName по-прежнему уважается — он нужен для НЕ-кликов
-- (например, "TutorialStepComplete" — это дзынь завершения шага гайда, а не
-- звук нажатия).
local function resolveUiSound(_instance, soundName)
	if soundName then return soundName end
	return "UiButtonClick"
end

local function connectClick(instance, callback, soundName)
	if not instance then
		return
	end
	local ok, err = pcall(function()
		if instance:IsA("GuiButton") then
			instance.MouseButton1Click:Connect(function()
				playUiClick(resolveUiSound(instance, soundName))
				callback()
			end)
		else
			instance.Active = true
			instance.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch then
					playUiClick(resolveUiSound(instance, soundName))
					callback()
				end
			end)
		end
	end)
	if not ok then
		warn("[CustomCartUI] не удалось подключить клик к", instance:GetFullName(), ":", err)
	end
end

-- v20: окно настроек собирается билдером (Shared.UiBuilders.SettingsUi →
-- StarterGui/SettingsMenu). Нет в StarterGui — соберётся тем же билдером.
local settingsGui = require(ReplicatedStorage.Shared.UiRegistry).Get("SettingsMenu")
settingsGui.ResetOnSpawn = false
settingsGui.IgnoreGuiInset = true
settingsGui.DisplayOrder = 40 -- поверх книжки, квестов и остальных игровых UI

local gearButton = settingsGui:FindFirstChild("GearButton", true)
local settingsPanel = settingsGui:FindFirstChild("Panel", true)
local soundToggle = settingsGui:FindFirstChild("SoundToggle", true)
local codeInput = settingsGui:FindFirstChild("CodeInput", true)
local redeemButton = settingsGui:FindFirstChild("RedeemButton", true)
local resultText = settingsGui:FindFirstChild("ResultText", true)
local closeButton = settingsGui:FindFirstChild("CloseButton", true) -- необязателен, клика по шестерёнке достаточно

-- Строки ползунков собирает билдер; нет строки — ползунок просто не работает.
local function ensureSlider(name)
	return settingsPanel:FindFirstChild(name .. "Row", true)
end

local sfxSlider = ensureSlider("SfxSlider", "WORLD SOUNDS", 2)
local musicSlider = ensureSlider("MusicSlider", "MUSIC", 3)
local uiSlider = ensureSlider("UiSlider", "UI SOUNDS", 4)
local effectsSlider = ensureSlider("EffectsSlider", "VISUAL EFFECTS", 5)

connectClick(gearButton, function()
	if settingsPanel.Visible then
		UiMotion.Close(settingsPanel)
	else
		UiMotion.Open(settingsPanel)
	end
end)
-- Кнопка-шестерёнка сама по себе больше не показывается — теперь
-- открывается из общего меню-книги (см. CollectionMenu.client.lua,
-- слушает CollectionMenuOpenRequest и дёргает settingsPanel напрямую).
-- Сам gearButton оставлен нетронутым технически (клик по нему всё ещё
-- работал бы), просто скрыт с экрана.
gearButton.Visible = false

local collectionMenuOpenRequest = ReplicatedStorage.Shared:FindFirstChild("CollectionMenuOpenRequest")
if not collectionMenuOpenRequest then
	collectionMenuOpenRequest = Instance.new("BindableEvent")
	collectionMenuOpenRequest.Name = "CollectionMenuOpenRequest"
	collectionMenuOpenRequest.Parent = ReplicatedStorage.Shared
end
collectionMenuOpenRequest.Event:Connect(function(target)
	if target == "Settings" and Config.UI.SettingsMenuEnabled ~= false then
		UiMotion.Open(settingsPanel)
	end
end)

-- НАСТРОЙКИ УБРАНЫ С ЭКРАНА (по прямому запросу — "удали GearButton,
-- SettingsMenu с экрана, панель не надо"). Сам объект НЕ уничтожаем: ниже
-- по файлу на его детей (слайдеры, промокод, ResultText) завязан код, и
-- Destroy уронил бы весь скрипт. Вместо этого ScreenGui выключен целиком
-- и держится выключенным — что бы ни пыталось включить его обратно.
if Config.UI.SettingsMenuEnabled == false then
	gearButton.Visible = false
	settingsPanel.Visible = false
	settingsGui.Enabled = false
	settingsGui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if settingsGui.Enabled then
			settingsGui.Enabled = false
		end
	end)
	settingsPanel:GetPropertyChangedSignal("Visible"):Connect(function()
		if settingsPanel.Visible then
			settingsPanel.Visible = false
		end
	end)
end
connectClick(closeButton, function()
	UiMotion.Close(settingsPanel)
end)

local function bindSlider(row, initialValue, onChanged)
	if not row then
		return function() end
	end
	local track = row:FindFirstChild("Track")
	local fill = track and track:FindFirstChild("Fill")
	local thumb = track and track:FindFirstChild("Thumb")
	local valueLabel = row:FindFirstChild("Value")
	if not (track and fill and thumb and valueLabel) then
		return function() end
	end
	local current = initialValue
	local dragging = false
	local hitArea = row:FindFirstChild("SliderHitArea")
	if not hitArea then
		hitArea = Instance.new("TextButton")
		hitArea.Name = "SliderHitArea"
		hitArea.Position = UDim2.new(0, 4, 0, 20)
		hitArea.Size = UDim2.new(1, -8, 0, 30)
		hitArea.BackgroundTransparency = 1
		hitArea.Text = ""
		hitArea.AutoButtonColor = false
		hitArea.ZIndex = math.max(track.ZIndex, thumb.ZIndex) + 5
		hitArea.Parent = row
	end
	local function setValue(value)
		current = math.clamp(value, 0, 1)
		fill.Size = UDim2.fromScale(current, 1)
		thumb.Position = UDim2.fromScale(current, 0.5)
		valueLabel.Text = ("%d%%"):format(math.floor(current * 100 + 0.5))
		onChanged(current)
	end
	local function setFromX(x)
		if track.AbsoluteSize.X > 0 then
			setValue((x - track.AbsolutePosition.X) / track.AbsoluteSize.X)
		end
	end
	local function begin(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end
	hitArea.InputBegan:Connect(begin)
	UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			setFromX(UserInputService:GetMouseLocation().X)
		elseif input.UserInputType == Enum.UserInputType.Touch then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	setValue(initialValue)
	return setValue
end

local sfxVolume = 1
local uiVolume = 1
local audioMuted = false
local particleBaseRates = setmetatable({}, { __mode = "k" })
local effectBaseEnabled = setmetatable({}, { __mode = "k" })
local lightBaseBrightness = setmetatable({}, { __mode = "k" })
local effectsQuality = 1

local function applyEffectInstance(instance)
	if instance:IsA("ParticleEmitter") then
		particleBaseRates[instance] = particleBaseRates[instance] or instance.Rate
		instance.Rate = particleBaseRates[instance] * effectsQuality
	elseif instance:IsA("PostEffect") or instance:IsA("Trail") or instance:IsA("Beam") then
		if effectBaseEnabled[instance] == nil then
			effectBaseEnabled[instance] = instance.Enabled
		end
		instance.Enabled = effectBaseEnabled[instance] and effectsQuality > 0.05
	elseif instance:IsA("Light") then
		lightBaseBrightness[instance] = lightBaseBrightness[instance] or instance.Brightness
		instance.Brightness = lightBaseBrightness[instance] * effectsQuality
	end
end

local function applyEffectsQuality(value)
	effectsQuality = value
	for _, instance in workspace:GetDescendants() do
		applyEffectInstance(instance)
	end
	for _, instance in game:GetService("Lighting"):GetDescendants() do
		applyEffectInstance(instance)
	end
end
-- ПРОИЗВОДИТЕЛЬНОСТЬ. Тоже глобальный слушатель на весь Workspace: раньше
-- applyEffectInstance вызывался на КАЖДЫЙ созданный в мире инстанс и делал
-- до четырёх :IsA() подряд. При этом effectsQuality по умолчанию равен 1, а
-- при единице вся функция сводится к holostoy записи того же значения
-- обратно (Rate = base * 1, Brightness = base * 1) — то есть у 99% игроков,
-- которые ползунок графики вообще не трогали, это была чистая трата кадра
-- на каждый кристалл, звук, партикл и гоблина в мире. С ростом числа
-- игроков растёт и частота этих событий — отсюда просадка FPS именно в
-- мультиплеере.
--
-- Выходим сразу, пока качество на максимуме. Корректность не страдает:
-- когда игрок реально двигает ползунок, applyEffectsQuality заново
-- проходит по всему Workspace и Lighting, а дальше уже effectsQuality < 1 и
-- этот обработчик снова начинает обрабатывать новые инстансы.
local function onEffectInstanceAdded(instance)
	if effectsQuality >= 0.999 then return end
	applyEffectInstance(instance)
end
workspace.DescendantAdded:Connect(onEffectInstanceAdded)
game:GetService("Lighting").DescendantAdded:Connect(onEffectInstanceAdded)

bindSlider(musicSlider, 1, function(value)
	musicUserVolume = value
	applyMusicVolume()
end)
bindSlider(uiSlider, 1, function(value)
	uiVolume = value
	uiSoundGroup.Volume = audioMuted and 0 or uiVolume
end)
local previousEffectsQuality = 1
bindSlider(effectsSlider, 1, function(value)
	if value < previousEffectsQuality and value < 0.99 then
		resultText.TextColor3 = Color3.fromRGB(255, 190, 90)
		resultText.Text = "Rejoin to fully restore graphics after lowering effects."
	end
	previousEffectsQuality = value
	applyEffectsQuality(value)
end)

-- Звук — чисто локальная настройка, серверу/другим игрокам не сообщаем.
task.spawn(function()
	local sfxGroup = SoundService:WaitForChild("SFX", 5)
	if not sfxGroup then
		return
	end

	-- Красим SoundToggle в зелёный/красный по состоянию — работает и для
	-- обычной цветной кнопки (BackgroundColor3), и для картинки
	-- (ImageButton/ImageLabel, см. PLACEHOLDERS_GUIDE.md — "UI: замена
	-- кнопок и фонов на изображения"): для картинки красим ImageColor3
	-- (тонирует саму текстуру), а не фон под ней.
	-- ВАЖНО: SoundToggle в собранном BuildUIAssets.lua v3 — ВСЕГДА ImageButton
	-- (даже без своей картинки, см. таблицу IMAGES там же), поэтому проверка
	-- "по классу" здесь не годится — она была бы истинной всегда. Смотрим,
	-- реально ли поставлена картинка (.Image непустой): есть — тонируем её
	-- через ImageColor3, нет — красим BackgroundColor3, как раньше.
	local function paintToggle(instance, color)
		if instance:GetAttribute("UiSkin") then
			-- Кнопка темы: включено — зелёная, выключено — красная.
			require(ReplicatedStorage.Shared.UiKit).ApplySkin(instance, audioMuted and "Button_Red" or "Button_Green")
			return
		end
		if (instance:IsA("ImageButton") or instance:IsA("ImageLabel")) and instance.Image ~= "" then
			instance.ImageColor3 = color
		else
			instance.BackgroundColor3 = color
		end
	end

	-- Текст "On"/"Off": у ImageButton/ImageLabel своего .Text вообще нет
	-- (BuildUIAssets.lua v3 кладёт подпись отдельным child TextLabel
	-- "Caption" поверх картинки) — используем его, если есть. Для старых
	-- ручных SettingsMenu (обычный TextButton, без Caption) — пишем прямо
	-- на сам инстанс, как раньше.
	local function setToggleText(instance, text)
		local caption = instance:FindFirstChild("Caption")
		if caption then
			caption.Text = text
		elseif instance:IsA("TextButton") or instance:IsA("TextLabel") then
			instance.Text = text
		end
	end

	bindSlider(sfxSlider, 1, function(value)
		sfxVolume = value
		sfxGroup.Volume = audioMuted and 0 or sfxVolume
	end)
	connectClick(soundToggle, function()
		audioMuted = not audioMuted
		sfxGroup.Volume = audioMuted and 0 or sfxVolume
		uiSoundGroup.Volume = audioMuted and 0 or uiVolume
		setToggleText(soundToggle, audioMuted and "Off" or "On")
		paintToggle(soundToggle, audioMuted and Color3.fromRGB(190, 70, 70) or Color3.fromRGB(80, 195, 90))
	end)
end)

-- Промокоды — сервер проверяет валидность/повторное использование сам,
-- клиенту нечего подделывать. Ответ (успех/причина отказа) прилетает
-- обратно тем же RemoteEvent.
task.spawn(function()
	local redeemRemote = ReplicatedStorage.Shared:WaitForChild("RedeemCodeRequest")

	local function trySubmit()
		local code = codeInput.Text
		if code == "" then
			return
		end
		redeemRemote:FireServer(code)
	end

	connectClick(redeemButton, trySubmit)
	codeInput.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			trySubmit()
		end
	end)

	redeemRemote.OnClientEvent:Connect(function(result, reward)
		if result == "Ok" then
			playUiClick("UiSuccess")
			resultText.TextColor3 = Color3.fromRGB(120, 255, 150)
			resultText.Text = tr("Success! +${amount}", { amount = reward })
			codeInput.Text = ""
		elseif result == "AlreadyRedeemed" then
			resultText.TextColor3 = Color3.fromRGB(255, 190, 90)
			resultText.Text = "Already redeemed."
		elseif result == "Expired" then
			resultText.TextColor3 = Color3.fromRGB(255, 150, 90)
			resultText.Text = "This code has expired."
		else
			playUiClick("UiError")
			resultText.TextColor3 = Color3.fromRGB(255, 100, 100)
			resultText.Text = "Invalid code."
		end
	end)
end)

--------------------------------------------------------------------------------
-- 0) ХОТБАР КИРКИ — единственный слот снизу экрана (в игре только один
--    инструмент, полноценный инвентарь не нужен). Прячем дефолтный
--    Backpack Roblox (там кирка показывалась бы текстовым названием),
--    рисуем свой: иконка (тонируется по тиру) + тёмная заливка "стекает"
--    сверху вниз по мере отката кулдауна + число секунд до готовности —
--    ровно то, что нужно, чтобы было понятно, как работает откат.
--
-- КОНТРАКТ (StarterGui/PickaxeHotbar) — необязателен, есть кодовый
-- плейсхолдер на любую нехватку частей:
--   ScreenGui "PickaxeHotbar"
--   └─ Frame "Slot" → ImageLabel ИЛИ TextLabel "Icon"
--                      (необязательно: Frame "CooldownOverlay",
--                       TextLabel "CooldownText", UIStroke — тонируется по тиру)
--------------------------------------------------------------------------------

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)
-- НАТИВНЫЙ ЛИДЕРБОРД ROBLOX ("$0" / "$0" с монеткой / "Q 0") — по прямому
-- запросу убран целиком. Это стандартное окно Roblox для leaderstats
-- (Money/Rebirths/Cart Damage, см. DataService.lua) — сам движок рисует
-- иконки под распознанные названия статов, это его штатное поведение, не
-- наш код. ВАЖНО: это убирает ВЕСЬ список игроков целиком (в том числе
-- список по Tab с никами других игроков на сервере), не только иконки —
-- если нужно оставить сам список, но убрать конкретно иконки/статы,
-- скажи отдельно, для этого нужен другой подход (переименовать
-- leaderstats так, чтобы Roblox не подставлял иконку).
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)

-- Config.Icons.Pickaxe — чистое число (ID картинки) или 0/пусто, если
-- ассета ещё нет. Собираем "rbxassetid://..." сами — вставлять строку
-- с префиксом руками не нужно.
local function resolveIconAsset(id)
	if not id or id == 0 or id == "" or id == "0" then
		return nil
	end
	local text = tostring(id)
	if text:match("^rbxassetid://") then
		return text
	end
	return "rbxassetid://" .. text
end

-- Готовый ассет из StarterGui — ищем части по контракту, чего не хватает —
-- достраиваем поверх, а не отбрасываем целиком (уважаем авторский дизайн).
local function findHotbarAsset()
	local gui = playerGui:WaitForChild("HotbarUi", 10)
	local slot = gui and gui:FindFirstChild("PickaxeSlot", true)
	assert(gui and slot, "StarterGui/HotbarUi/PickaxeSlot is required. Run tools/BuildAllUI.lua.")
	return gui, slot
end

-- НОВЫЙ ХОТБАР ЗАМЕНЯЕТ СТАРЫЙ. Если в игре есть StarterGui/HotbarUi (см.
-- tools/BuildAllUI.lua + src/client/InventoryUI.client.lua), то
-- старый одиночный слот кирки больше не показывается: он висел бы вторым
-- баром поверх нового и, что хуже, перехватывал бы клавишу "1" под кирку —
-- а в новом хотбаре "1" это первый слот РУДЫ (кирка теперь на F).
--
-- ВАЖНО: здесь НЕЛЬЗЯ делать голый `return` — этот файл огромный, и выход
-- из него на этом месте убил бы ВСЁ, что объявлено ниже (кулдауны, кнопки
-- респавна/защиты, магазин, тосты и т.д.), а не только хотбар. Поэтому
-- старый хотбар именно ПРЯЧЕТСЯ, а обработчик клавиш ниже сам сверяется с
-- legacyHotbarDisabled и не трогает ввод, отданный новому хотбару.
local legacyHotbarDisabled = true
local legacy = playerGui:FindFirstChild("PickaxeHotbar")
if legacy then legacy:Destroy() end
local hotbarGui, hotbarSlot = findHotbarAsset()
hotbarGui.ResetOnSpawn = false
hotbarGui.IgnoreGuiInset = true
hotbarGui.Enabled = true
hotbarGui.DisplayOrder = 5

local tierStroke = hotbarSlot:FindFirstChildWhichIsA("UIStroke")

local cooldownOverlay = hotbarSlot:FindFirstChild("CooldownOverlay", true)
if cooldownOverlay and not (cooldownOverlay:IsA("GuiObject")) then cooldownOverlay = nil end
-- Заливка "стекает" сверху вниз: заякорена снизу, растёт/сжимается по высоте —
-- при полном кулдауне закрывает всю иконку, к концу открывает её снизу вверх.
if cooldownOverlay then
	cooldownOverlay.AnchorPoint = Vector2.new(0, 1)
	cooldownOverlay.Position = UDim2.new(0, 0, 1, 0)
	cooldownOverlay.Size = UDim2.new(1, 0, 0, 0)
end

local cooldownText = hotbarSlot:FindFirstChild("CooldownText", true)
if cooldownText then cooldownText.Visible = false end

local function applyTierStrokeColor()
	local tier = player:GetAttribute("PickaxeTier")
	local tierConfig = tier and Config.PickaxeTiers[tier]
	if not tierConfig then
		return
	end
	if tierStroke then
		tierStroke.Color = tierConfig.VfxColor
	end
end

local function refreshHotbarVisibility()
	hotbarGui.Enabled = player:GetAttribute("HasPickaxe") ~= false
end

applyTierStrokeColor()
refreshHotbarVisibility()
player:GetAttributeChangedSignal("PickaxeTier"):Connect(applyTierStrokeColor)
player:GetAttributeChangedSignal("HasPickaxe"):Connect(refreshHotbarVisibility)
player:GetAttributeChangedSignal("CarryingCart"):Connect(refreshHotbarVisibility)

-- Общая фабрика "отката с заливкой" — у каждого экземпляра свой токен
-- (отменяет предыдущий отсчёт, если новый пришёл раньше, чем истёк старый,
-- например кулдаун стал короче после апгрейда). Используется и для кирки,
-- и для кнопок ниже (респавн тележки, защита) — одна и та же визуальная логика.
local function makeCooldownController(overlay, text)
	local token = 0
	return function(duration)
		if not duration or duration <= 0 then
			return
		end
		token += 1
		local myToken = token

		if overlay then
			overlay.Size = UDim2.new(1, 0, 1, 0)
			TweenService:Create(
				overlay,
				TweenInfo.new(duration, Enum.EasingStyle.Linear),
				{ Size = UDim2.new(1, 0, 0, 0) }
			):Play()
		end
		if text then
			text.Visible = true
		end

		local start = os.clock()
		task.spawn(function()
			while token == myToken do
				local remaining = duration - (os.clock() - start)
				if remaining <= 0 then
					break
				end
				if text then
					text.Text = ("%.1f"):format(remaining)
				end
				task.wait(0.1)
			end
			if token == myToken and text then
				text.Visible = false
			end
		end)
	end
end

local playPickaxeCooldown = makeCooldownController(cooldownOverlay, cooldownText)

task.spawn(function()
	local swungRemote = ReplicatedStorage.Shared:WaitForChild("PickaxeSwungEvent")
	swungRemote.OnClientEvent:Connect(function()
		local tier = player:GetAttribute("PickaxeTier")
		local tierConfig = tier and Config.PickaxeTiers[tier]
		if tierConfig then
			playPickaxeCooldown(tierConfig.Cooldown)
		end
	end)
end)

-- ПЕРЕКЛЮЧЕНИЕ ЭКИПИРОВКИ (клавиша "1" и клик по слоту): дефолтный Backpack
-- Roblox выключен выше — вместе с ним отключается и вся штатная система
-- экипировки (хоткеи/клик), это не баг, а задокументированное поведение
-- SetCoreGuiEnabled(Backpack, false) (см. форум разработчиков Roblox).
-- Сервер выдаёт кирку в Backpack, но стандартный Backpack UI скрыт. Поэтому
-- "1"/F/клик по слоту явно экипирует или убирает её через
-- Humanoid:UnequipTools()/EquipTool().
local function getPickaxeTool()
	local character = player.Character
	if not character then
		return nil
	end
	local backpack = player:FindFirstChild("Backpack")
	return (backpack and backpack:FindFirstChild("Pickaxe")) or character:FindFirstChild("Pickaxe")
end

local function toggleEquip()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local tool = getPickaxeTool()
	if not humanoid or not tool then
		return
	end
	if tool.Parent == character then
		humanoid:UnequipTools()
	else
		humanoid:EquipTool(tool)
	end
end

-- Прозрачная кнопка поверх слота — ловит клик независимо от того, Frame
-- слот или уже кастомный GuiButton у готового StarterGui-ассета.
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or UserInputService:GetFocusedTextBox() then
		return
	end
	if input.KeyCode == Enum.KeyCode.F then
		-- F всегда остаётся доступной для защиты. Старый early-return
		-- отключал её вместе с удалённым PickaxeHotbar.
		if player:GetAttribute("CarryingCart") == true and activateProtection then
			activateProtection()
		elseif player:GetAttribute("CarryingCart") ~= true and not legacyHotbarDisabled then
			toggleEquip()
		end
	end
end)

--------------------------------------------------------------------------------
-- КНОПКА ЗАЩИТЫ: бесплатно на кулдауне, платное продление сверху.
-- Видна ТОЛЬКО пока игрок тащит тележку — пока в руках кирка (обычный
-- "боевой" режим), щит не нужен и не показывается, ровно как хотбар кирки
-- прячется, пока тащишь тележку — экран переключается между двумя
-- режимами, а не показывает всё сразу.
--
-- Кнопка "Заспавить тележку" — теперь ФИЗИЧЕСКАЯ, стоит в мире у парковки
-- (см. CartService:SetupRespawnButton/PlotService) — здесь её больше нет.
--
-- КОНТРАКТ (StarterGui/ActionButtons) — необязателен, есть плейсхолдер:
--   ScreenGui "ActionButtons"
--   └─ Frame "ProtectionButton" → TextLabel/ImageLabel "Icon"
--                                  (необязательно: Frame "CooldownOverlay",
--                                   TextLabel "CooldownText", UIStroke)
--------------------------------------------------------------------------------

-- (v20: заглушка ActionButtons удалена — щит живёт в слоте F хотбара, HotbarUi.)

-- WaitForChild, а не FindFirstChild. Это единственное место в файле, где
-- Studio-овский GUI брался без ожидания (все остальные — WaitForChild с
-- таймаутом 5, см. CartInteractionUi, SettingsMenu, ShopUi и прочие).
-- Разница принципиальная: скрипт лежит в StarterPlayerScripts и стартует
-- РАНЬШЕ, чем StarterGui успевает отреплицироваться в PlayerGui. На быстрой
-- машине успевало, на медленной — нет, и тогда FindFirstChild возвращал nil:
-- код собирал плейсхолдер, а следом приходил настоящий ActionButtons, и в
-- PlayerGui оказывалось ДВА одноимённых GUI. Ссылка оставалась на один, а
-- видел игрок другой — щит и не появлялся.
-- Щит использует уже существующий центральный слот F хотбара. Старый
-- ActionButtons удаляем, чтобы внизу экрана не появлялась вторая кнопка.
local oldActionGui = playerGui:FindFirstChild("ActionButtons")
if oldActionGui then oldActionGui:Destroy() end
local actionGui = playerGui:WaitForChild("HotbarUi", 5)
local protectionSlot = actionGui and actionGui:FindFirstChild("PickaxeSlot", true)
if not protectionSlot then
	warn("[CustomCartUI] HotbarUi/PickaxeSlot не найден — щит не подключён к хотбару.")
	return
end
actionGui.ResetOnSpawn = false
actionGui.IgnoreGuiInset = true

local protectionPreview = protectionSlot:FindFirstChild("Preview", true)
local pickaxePreviewImage = resolveIconAsset(Config.Icons and Config.Icons.Pickaxe)
	 or (protectionPreview and protectionPreview:IsA("ImageLabel") and protectionPreview.Image or "")
local protectionPreviewImage = resolveIconAsset(Config.Icons and Config.Icons.Protection) or ""
local function refreshProtectionSlotIcon()
	local carrying = player:GetAttribute("CarryingCart") == true
		or player:GetAttribute("CartCarrying") == true
	if protectionPreview and protectionPreview:IsA("ImageLabel") then
		protectionPreview.Image = carrying and protectionPreviewImage or pickaxePreviewImage
	end
	local key = protectionSlot:FindFirstChild("KeyBadge", true)
	if key then key.Text = carrying and "S" or "F" end
	local label = protectionSlot:FindFirstChild("ShieldLabel", true)
	if label then label.Visible = carrying end
	local count = protectionSlot:FindFirstChild("CountLabel", true)
	if count and carrying then count.Text = "SHIELD" end
end
refreshProtectionSlotIcon()
player:GetAttributeChangedSignal("CarryingCart"):Connect(refreshProtectionSlotIcon)

-- Полоса отката — красная, но НЕ с самого начала (когда кнопка доступна,
-- красного вообще не видно — это и путало: "доступно" выглядело так же,
-- как "занято"). Нажал → полоса СРАЗУ становится полностью красной →
-- убывает по мере отката → снова пусто, когда можно нажимать. Дополнительно
-- — число секунд, но ТОЛЬКО когда остаётся меньше showCountdownBelow.
local function setupFillBar(slot, color, showCountdownBelow)
	local bar = slot:FindFirstChild("CooldownOverlay", true) -- то же имя контракта, что и раньше
	if not bar then
		bar = Instance.new("Frame")
		bar.Name = "CooldownOverlay"
		bar.BorderSizePixel = 0
		bar.ZIndex = 3
		bar.Parent = slot

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = bar
	end
	bar.BackgroundColor3 = color
	bar.BackgroundTransparency = 0.1
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.new(0, 0, 1, 0)
	bar.Size = UDim2.new(1, 0, 0, 0) -- стартуем ПУСТЫМИ — доступно, красного не видно

	local text = slot:FindFirstChild("CooldownText", true)
	if not text then
		text = Instance.new("TextLabel")
		text.Name = "CooldownText"
		text.AnchorPoint = Vector2.new(0.5, 0.5)
		text.Position = UDim2.fromScale(0.5, 0.5)
		text.Size = UDim2.fromScale(0.8, 0.5)
		text.BackgroundTransparency = 1
		require(game:GetService("ReplicatedStorage").Shared.UiKit).StyleText(text, "Heading") -- v20: шрифт темы
		text.TextScaled = true
		text.TextColor3 = Color3.new(1, 1, 1)
		text.ZIndex = 4
		text.Parent = slot
	end
	text.Visible = false

	local activeTween = nil
	return function(duration)
		if not duration or duration <= 0 then
			return
		end
		if activeTween then
			activeTween:Cancel() -- иначе два твина одновременно тянут один и тот же Size — дёргается
		end
		bar.Size = UDim2.new(1, 0, 1, 0) -- сразу полностью красная — только что нажал, занято
		local myTween = TweenService:Create(
			bar,
			TweenInfo.new(duration, Enum.EasingStyle.Linear),
			{ Size = UDim2.new(1, 0, 0, 0) } -- убывает до пустого — снова можно нажимать
		)
		activeTween = myTween
		myTween:Play()

		local start = os.clock()
		task.spawn(function()
			while activeTween == myTween do
				local remaining = duration - (os.clock() - start)
				if remaining <= 0 then
					break
				end
				if remaining <= showCountdownBelow then
					text.Visible = true
					text.Text = ("%.0f"):format(remaining)
				end
				task.wait(0.2)
			end
			if activeTween == myTween then
				text.Visible = false
			end
		end)
	end
end

local function addClickCatcher(slot)
	local button = Instance.new("TextButton")
	button.Name = "ClickCatcher"
	button.BackgroundTransparency = 1
	button.Text = ""
	button.Size = UDim2.fromScale(1, 1)
	button.ZIndex = 5
	button.Parent = slot
	return button
end

local ACTION_BAR_COLOR = Color3.fromRGB(220, 60, 60) -- красная — сразу понятно "занято/недоступно/ждём"
local COUNTDOWN_THRESHOLD = 30 -- секунд — раньше этого числа отсчёт скрыт, показана только полоса

-- Всплывающая надпись над кнопкой — "ещё не готово", когда жмут раньше
-- времени. Отдельно от полосы/цифр — это разовая реакция на клик, а не
-- постоянно видимое состояние.
local function buildWarningLabel(slot)
	local label = Instance.new("TextLabel")
	label.Name = "WarningLabel"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 0, -6)
	label.Size = UDim2.new(3.2, 0, 0.7, 0)
	label.BackgroundTransparency = 1
	require(game:GetService("ReplicatedStorage").Shared.UiKit).StyleText(label, "Heading") -- v20: шрифт темы
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 90, 90)
	label.Visible = false
	label.ZIndex = 10
	label.Parent = slot
	return label
end

local function showWarning(label, text)
	label.Text = text
	label.Visible = true
	local myText = text
	task.delay(1.5, function()
		if label.Text == myText then -- никто не успел показать новое предупреждение поверх
			label.Visible = false
		end
	end)
end

-- Защита — бесплатно на кулдауне; пока кулдаун активен, клик пытается
-- купить платное продление (если Config.Protection.PaidProductId настроен).
-- Зелёная обводка — пока щит РЕАЛЬНО активен (атрибут Protected), это
-- отдельная от отката кнопки индикация ("щит горит прямо сейчас" против
-- "когда будет доступна следующая бесплатная активация").
local playProtectionCooldown = setupFillBar(protectionSlot, ACTION_BAR_COLOR, COUNTDOWN_THRESHOLD)
local protectionClickCatcher = addClickCatcher(protectionSlot)
local protectionStroke = protectionSlot:FindFirstChildWhichIsA("UIStroke")
local protectionWarning = buildWarningLabel(protectionSlot)

-- Подсказка по щиту — при наведении объясняет механику словами, а не только
-- цветом обводки: что щит вообще защищает от атак (см. CombatService —
-- защищённого нельзя даже выбрать целью), что бесплатная активация уходит на
-- кулдаун, и что её можно продлить платно/навсегда (Golden Shield).
local protectionTooltip = Instance.new("Frame")
protectionTooltip.Name = "ProtectionTooltip"
protectionTooltip.AnchorPoint = Vector2.new(0.5, 1)
protectionTooltip.Position = UDim2.new(0.5, 0, 0, -8)
protectionTooltip.Size = UDim2.fromOffset(230, 100)
protectionTooltip.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
protectionTooltip.BackgroundTransparency = 0.08
protectionTooltip.BorderSizePixel = 0
protectionTooltip.Visible = false
protectionTooltip.ZIndex = 10
protectionTooltip.Parent = protectionSlot

local protectionTooltipCorner = Instance.new("UICorner")
protectionTooltipCorner.CornerRadius = UDim.new(0, 8)
protectionTooltipCorner.Parent = protectionTooltip

local protectionTooltipStroke = Instance.new("UIStroke")
protectionTooltipStroke.Color = Config.Protection.Color
protectionTooltipStroke.Thickness = 1.5
protectionTooltipStroke.Parent = protectionTooltip

local protectionTooltipText = Instance.new("TextLabel")
protectionTooltipText.Name = "Text"
protectionTooltipText.BackgroundTransparency = 1
protectionTooltipText.Position = UDim2.fromOffset(8, 6)
protectionTooltipText.Size = UDim2.new(1, -16, 1, -12)
require(game:GetService("ReplicatedStorage").Shared.UiKit).StyleText(protectionTooltipText, "Number") -- v20: шрифт темы
protectionTooltipText.TextColor3 = Color3.new(1, 1, 1)
protectionTooltipText.TextSize = 14
protectionTooltipText.TextWrapped = true
protectionTooltipText.TextXAlignment = Enum.TextXAlignment.Left
protectionTooltipText.TextYAlignment = Enum.TextYAlignment.Top
protectionTooltipText.ZIndex = 11
protectionTooltipText.Text = "SHIELD\nWhile active, other players can't attack you or steal your ore.\nFree activation, then a cooldown.\nExtend it longer with a paid boost or the Golden Shield pass."
protectionTooltipText.Parent = protectionTooltip

protectionClickCatcher.MouseEnter:Connect(function()
	protectionTooltip.Visible = true
end)
protectionClickCatcher.MouseLeave:Connect(function()
	protectionTooltip.Visible = false
end)

local function refreshProtectionGlow()
	if not protectionStroke then
		return
	end
	if player:GetAttribute("Protected") then
		protectionStroke.Color = Config.Protection.Color
		protectionStroke.Thickness = 4
	else
		protectionStroke.Color = Color3.fromRGB(90, 90, 100)
		protectionStroke.Thickness = 3
	end
end
refreshProtectionGlow()
player:GetAttributeChangedSignal("Protected"):Connect(refreshProtectionGlow)

task.spawn(function()
	local freeProtectionRemote = ReplicatedStorage.Shared:WaitForChild("ActivateFreeProtectionRequest")
	local paidProtectionRemote = ReplicatedStorage.Shared:WaitForChild("BuyProtectionExtensionRequest")
	local onCooldown = false

	activateProtection = function()
		playUiClick()
		if onCooldown then
			if Config.Protection.PaidProductId ~= 0 then
				paidProtectionRemote:FireServer()
			else
				showWarning(protectionWarning, "Not ready yet!")
			end
		else
			freeProtectionRemote:FireServer()
		end
	end
	protectionClickCatcher.MouseButton1Click:Connect(activateProtection)

	freeProtectionRemote.OnClientEvent:Connect(function()
		onCooldown = true
		playProtectionCooldown(Config.Protection.FreeCooldown)
		task.delay(Config.Protection.FreeCooldown, function()
			onCooldown = false
		end)
	end)
end)

--------------------------------------------------------------------------------
-- МАГАЗИН ПРОКАЧКИ У NPC — диалог в стиле Fisch/Grow a Garden (см. присланный
-- референс DialogModule): NPC говорит текстом над своей головой (посимвольная
-- печать), а варианты ответа — отдельным пронумерованным списком на экране,
-- выбираются кликом ИЛИ клавишами 1/2/3. Сервер (UpgradeService) решает
-- вообще всё: клиент только просит открыть/купить и рисует то, что сервер
-- прислал — ничего не считает и не проверяет сам.
--
-- КОНТРАКТ NPC (Model "UpgradeShopNPC", ReplicatedStorage/Assets) — модель
-- обязана иметь PrimaryPart (на неё вешается ProximityPrompt, см.
-- UpgradeService:SetupPlot) и BillboardGui "gui" ГДЕ УГОДНО внутри модели
-- (не обязательно на конкретной части вроде "Head" — просто именованный
-- потомок, найдётся рекурсивно), а внутри неё → TextLabel "name"/"arrow"/
-- "dialog" (см. PlaceholderFactory.UpgradeShopNPC — там же и UIStroke на
-- каждом). Всё остальное содержимое модели (сколько частей, как называются)
-- никак не проверяется и не используется — работает с моделью как есть.
--
-- Старый DialogResponses удалён. Используется только UpgradeShopCards,
-- собранный builder'ом.
--------------------------------------------------------------------------------

local KIND_LABELS = { Mine = "MINE", Cart = "CART", Pickaxe = "PICKAXE" }
-- Порядок карточек — синхронизирован с tools/BuildAllUI.lua
-- ("шахта по середине, тележка справа, кирка слева" по прямому запросу).
-- Индексы 1/2/3 (клавиши-шорткаты и KIND_ORDER[index] ниже) теперь тоже
-- считают слева направо в НОВОМ порядке — это ожидаемо, карточки физически
-- переставлены, а не только перекрашены.
local KIND_ORDER = { "Pickaxe", "Mine", "Cart" }

-- true, если tools/BuildAllUI.lua был запущен и ScreenGui
-- "UpgradeShopCards" реально собран в StarterGui — выставляется следующим
-- IIFE ниже. Старый список строк (DialogResponses, дальше по файлу) читает
-- этот флаг и, если он true, просто ничего не делает — сам, целиком, не
-- удалён, остаётся рабочим запасным вариантом.
local upgradeShopCardsActive = false

-- MaxVisibleGraphemes раскрывает только видимые буквы, оставляя полный
-- RichText в Text валидным на каждом кадре. Если собирать строку через sub,
-- незакрытый <font> временно показывается игроку как служебная разметка.
local function typeText(label, full, charDelay)
	label.RichText = true
	label.Text = full
	label.MaxVisibleGraphemes = 0

	local visibleText = full:gsub("<[^>]+>", "")
	local graphemeCount = 0
	for _ in utf8.graphemes(visibleText) do
		graphemeCount += 1
	end
	for i = 1, graphemeCount do
		label.MaxVisibleGraphemes = i
		task.wait(charDelay)
	end
	label.MaxVisibleGraphemes = -1
end

-- Разрешение экрана меняется — TextSize у BillboardGui-лейблов (name/arrow/
-- dialog над головой NPC) не тянется через TextScaled так же надёжно, как
-- обычный экранный UI, поэтому пересчитываем TextSize вручную от реального
-- размера экрана относительно референсного 1920×1080 — ровно как в
-- присланном скрипте, просто подключено ОДИН раз на весь список текущих
-- лейблов (обновляется на каждое открытие диалога), а не заново на каждый.
local currentScaledLabels = {}
local function refreshResolutionScale()
	local referenceResolution = Vector2.new(1920, 1080)
	local referenceTextSize = 30
	local size = workspace.CurrentCamera.ViewportSize
	local scaleFactor = math.min(size.X / referenceResolution.X, size.Y / referenceResolution.Y)
	local textSize = math.max(9, referenceTextSize * scaleFactor)
	for _, label in currentScaledLabels do
		if label then
			label.TextSize = textSize * (label:GetAttribute("TextScaleMultiplier") or 1)
		end
	end
end
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshResolutionScale)

--------------------------------------------------------------------------------
-- КАМЕРА ПРИ УСПЕШНОЙ ПРОКАЧКЕ.
--
-- Общая для ОБОИХ видов диалога продавца (карточки/список, см. IIFE ниже) —
-- определена здесь один раз, каждый вызывает playUpgradeRevealCamera(kind,
-- closeMenu) на успешный BuyResult (closeMenu — своя closeDialog).
--
-- ПОСЛЕДОВАТЕЛЬНОСТЬ:
--   1. Меню плавно закрывается (closeMenu).
--   2. Камера "вылетает" от игрока (CameraType.Scriptable) на широкий план.
--   3. Камера едет и наводится на прокачанный объект (шахта/тележка/кирка).
--   4. Объект "выезжает из-под земли": временный клон растёт от почти-нуля
--      до полного размера и поднимается с высоты чуть ниже пола, с
--      мультяшным перелётом-отскоком (EasingStyle.Back) на приземлении +
--      камера-шейк + плейсхолдер VFX (пыль/искры/вспышка света). Настоящий
--      объект на это время скрыт ЛОКАЛЬНО (LocalTransparencyModifier — не
--      трогает то, что видят другие игроки), затем показывается обратно.
--      У кирки (Tool в руке персонажа) роста нет — её скейлить небезопасно
--      (сломает Grip/анимацию держания), просто крупный план + VFX.
--   5. Камера возвращается игроку, управление восстанавливается.
--
-- СКИП ПРИ СПАМЕ: если игрок покупает снова, пока катсцена ещё играет,
-- skipActiveCinematic() мгновенно возвращает камеру в исходный режим и
-- инвалидирует cinematicToken — все шаги предыдущего прогона проверяют его
-- через stillActive() перед каждым task.wait/Tween и тихо останавливаются,
-- не доигрывая. Никакой очереди — только "последняя прокачка выигрывает".
--------------------------------------------------------------------------------
local playUpgradeRevealCamera
local captureUpgradeBeforeSnapshot
local cancelPendingUpgradeReveal
-- Всё ниже — в отдельной функции (а НЕ голом do...end и НЕ прямо в теле
-- скрипта). Причина: этот LocalScript огромный, и всё, что не обёрнуто в
-- IIFE/функцию, живёт в ОДНОМ общем чанке верхнего уровня — у него общий
-- на всех бюджет в 200 локальных регистров (жёсткий лимит Luau).
-- ВАЖНО, уточнение задним числом: голый `do...end` этот бюджет НЕ
-- освобождает понадёжнее функции — освобождение регистров при выходе из
-- do-блока — это оптимизация компилятора (-O1/-O2), а Studio в Play-режиме
-- компилирует с -O0, где регистры do-блока НЕ переиспользуются (проверено
-- локально: luau-compile -O0 падает на первом же большом do-блоке после
-- этого места, -O1/-O2 — нет). Только настоящая функция гарантированно
-- получает свежий регистровый файл — используем её и здесь.
local function setupUpgradeRevealCinematic()
	-- Слепки "до покупки" для катсцены шага 3 (см. playUpgradeRevealCamera
	-- ниже) — [kind] = клон модели, снятый В МОМЕНТ КЛИКА "Купить", ДО того
	-- как сервер успеет заменить объект на новый. captureUpgradeBeforeSnapshot
	-- вызывается из обработчиков кнопки покупки (обе версии диалога, ниже по
	-- файлу), playUpgradeRevealCamera потребляет и уничтожает клон сама.
	local pendingBeforeModels = {}

	-- ФИКС "СНАЧАЛА ВИДНО УЖЕ УЛУЧШЕННОЕ, ПОТОМ ОНО ОТКАТЫВАЕТСЯ ДО СТАРОГО":
	-- сервер меняет реальную модель на новую СИНХРОННО, ДО отправки
	-- "BuyResult" (см. UpgradeService:_tryBuy) — новая модель реплицируется
	-- игроку зачастую БЫСТРЕЕ, чем долетает сам RemoteEvent, то есть новый
	-- тир на кадр-другой появляется в мире ЕЩЁ ДО того, как катсцена вообще
	-- стартует (она запускается по BuyResult и прячет модель только через
	-- ~0.55 сек полёта камеры — см. setModelLocalVisible ниже). Эти две
	-- таблицы прячут новую модель ЛОКАЛЬНО (LocalTransparencyModifier — не
	-- влияет на других игроков) в момент её появления в мире, а не когда до
	-- неё доберётся катсцена.
	local hideOnAppearConnections = {} -- [kind] = Connection, слушает появление новой модели
	local pendingHiddenModels = {} -- [kind] = уже спрятанная новая модель, ждёт катсцену

	-- ФИКС "СТАРАЯ ШАХТА ПРОПАДАЕТ В САМОМ НАЧАЛЕ КАТСЦЕНЫ". Сервер удаляет
	-- старую шахту почти сразу после клика, новую мы тут же прячем, а
	-- слепок старой раньше появлялся в мире только на шаге 3 — после ~1 сек
	-- полёта камеры. Всё это время на участке было ПУСТО. Теперь слепок
	-- встаёт на место настоящей модели в тот же кадр, когда та исчезает
	-- ("дублёр"), и катсцена потом просто продолжает работать с ним.
	local standInConnections = {} -- [kind] = Connection на исчезновение настоящей старой модели
	local function showStandIn(kind)
		local clone = pendingBeforeModels[kind]
		if clone and clone.Parent == nil then
			clone.Parent = workspace
		end
	end
	local function dropStandIn(kind, destroyClone)
		if standInConnections[kind] then
			standInConnections[kind]:Disconnect()
			standInConnections[kind] = nil
		end
		if destroyClone and pendingBeforeModels[kind] then
			pendingBeforeModels[kind]:Destroy()
			pendingBeforeModels[kind] = nil
		end
	end

	local cinematicToken = 0
	local cinematicActive = false
	local cinematicRestoreCameraType = Enum.CameraType.Custom

	-- БЛОКИРОВКА ProximityPrompt НА ВРЕМЯ КАТСЦЕНЫ (по прямому запросу).
	-- Во время пролёта камеры игрок не видит своего персонажа и не понимает,
	-- рядом с чем он стоит, а промпты продолжали ловить "E" — можно было
	-- случайно схватить тележку, открыть диалог продавца заново или
	-- собрать сейф вслепую, прямо посреди сцены.
	-- ProximityPromptService.Enabled — клиентское свойство, гасит ВСЕ
	-- промпты разом и мгновенно; ничего перебирать вручную не нужно.
	-- cinematicPromptsRestore хранит состояние ДО катсцены — если промпты
	-- были выключены не нами (например, диалогом продавца), мы не включим
	-- их обратно "за компанию".
	local cinematicPromptsRestore = nil
	local function setCinematicPromptsBlocked(blocked)
		if blocked then
			if cinematicPromptsRestore == nil then
				cinematicPromptsRestore = ProximityPromptService.Enabled
			end
			ProximityPromptService.Enabled = false
		elseif cinematicPromptsRestore ~= nil then
			ProximityPromptService.Enabled = cinematicPromptsRestore
			cinematicPromptsRestore = nil
		end
	end

	-- УЧЁТ ЛОКАЛЬНО СПРЯТАННЫХ МОДЕЛЕЙ (ФИКС "МОДЕЛИ БАГАЮТСЯ ПРИ БЫСТРОЙ
	-- ПРОКАЧКЕ"). Катсцена прячет настоящую модель через
	-- setModelLocalVisible(model, false) и показывает вместо неё временный
	-- клон. Если в этот момент прилетала ВТОРАЯ покупка, skipActiveCinematic
	-- просто обрывал сцену по токену — и настоящая модель ОСТАВАЛАСЬ
	-- НЕВИДИМОЙ навсегда, а временные клоны (beforeClone/newClone) висели в
	-- workspace. Внешне это и есть "шахта/тележка пропала" и "их стало две".
	-- Теперь всё, что сцена спрятала или создала, регистрируется здесь, и
	-- skipActiveCinematic возвращает мир в исходное состояние независимо от
	-- того, на каком шаге её оборвали.
	local cinematicHiddenModels = {}  -- [Model] = true, локально спрятана катсценой
	local cinematicTempClones = {}    -- [Instance] = true, временные клоны сцены

	-- Тот же приём поиска своего участка/тележки, что и в showInteractiveTutorial
	-- (см. ownPlotContent/ownCart там) — здесь отдельная копия, потому что тот
	-- код приватный внутри своей функции.
	local function findOwnPlotContent()
		local plots = workspace:FindFirstChild("Plots")
		local plotIndex = player:GetAttribute("PlotIndex")
		local plot = plots and plotIndex and plots:FindFirstChild("PlotPad_" .. tostring(plotIndex))
		local pad = plot and (plot.PrimaryPart or plot:FindFirstChild("PlotPad", true))
	return pad and pad:FindFirstChild("Content_" .. player.Name)
	end

	local function findOwnCart()
	local namedCart = workspace:FindFirstChild("Cart_" .. player.Name)
	if namedCart and namedCart:IsA("Model") and namedCart:GetAttribute("OwnerUserId") == player.UserId then
		return namedCart
	end
	return nil
	end

	-- Возвращает (модель_для_роста_или_nil, часть_для_фокуса_камеры). У Mine/Cart
	-- это реальная модель в мире — она же ростёт из-под земли. У Pickaxe модель
	-- не растёт (это заэкипированный Tool), только показывается крупным планом.
	-- ЭТО И БЫЛ БАГ "КАМЕРА ПОКАЗЫВАЕТ ШАХТЁРА, И ШАХТЁР МЕНЯЕТСЯ". Модель
	-- шахты искали по имени "^Mine", а под этот шаблон подходят и
	-- "MinerNPC" (шахтёр), и "MineActor" (дублёр катсцены) — они лежат в
	-- той же папке участка. Кто попался первым, того камера и снимала, его
	-- же прятала, клонировала, сжимала и "выращивала заново". Теперь шахта
	-- узнаётся по атрибуту PlotMine (ставит PlotService) или по точному
	-- имени Mine / Mine_TierN.
	local function isPlotMine(child)
		if not child:IsA("Model") then return false end
		if child:GetAttribute("PlotMine") == true then return true end
		return child.Name == "Mine" or child.Name:match("^Mine_Tier%d+$") ~= nil
	end

	local function resolveRevealAnchor(kind)
	if kind == "Mine" then
		local content = findOwnPlotContent()
		local mine
		if content then
			for _, child in content:GetChildren() do
				if isPlotMine(child) then
					mine = child
					break
				end
			end
		end
		local part = mine and (mine.PrimaryPart or mine:FindFirstChildWhichIsA("BasePart", true))
		return (mine and part) and mine or nil, part
	elseif kind == "Cart" then
		local cart = findOwnCart()
		local part = cart and (cart.PrimaryPart or cart:FindFirstChildWhichIsA("BasePart", true))
		return (cart and part) and cart or nil, part
	elseif kind == "Pickaxe" then
		local character = player.Character
		local tool = character and character:FindFirstChildOfClass("Tool")
		local handle = tool and tool:FindFirstChild("Handle")
		return nil, handle or (character and character:FindFirstChild("RightHand"))
	end
	return nil, nil
	end

	-- v17: ПРЯЧЕМ МОДЕЛЬ ЦЕЛИКОМ, А НЕ ТОЛЬКО ДЕТАЛИ.
	-- Раньше LocalTransparencyModifier ставился только BasePart'ам, и только
	-- тем, что уже были в модели в момент вызова. Поэтому у новой шахты
	-- «проступали» поверх дублёра старой: частицы, лучи, свет, огонь,
	-- Highlight, SurfaceGui/BillboardGui, декали — и все детали, которые
	-- доезжали репликацией/стримингом ПОЗЖЕ. Теперь прячется всё видимое,
	-- а пока модель спрятана, любой новый потомок прячется сразу же
	-- (DescendantAdded). Исходный Enabled хранится в атрибуте потомка —
	-- его несут и клоны, так что клон новой модели восстанавливается честно.
	local CINE_HIDE_ATTR = "_CineHiddenEnabled"
	local TOGGLE_CLASSES = { "ParticleEmitter", "Beam", "Trail", "Light", "Fire", "Smoke", "Sparkles", "Highlight", "SurfaceGui", "BillboardGui" }
	local function isToggleable(d)
		for _, className in TOGGLE_CLASSES do
			if d:IsA(className) then return true end
		end
		return false
	end
	local function hideVisual(d)
		if d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = 1
		elseif isToggleable(d) then
			if d:GetAttribute(CINE_HIDE_ATTR) == nil then
				d:SetAttribute(CINE_HIDE_ATTR, d.Enabled == true)
			end
			d.Enabled = false
			if d:IsA("ParticleEmitter") then pcall(function() d:Clear() end) end
		end
	end
	local function showVisual(d)
		if d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = 0
		elseif isToggleable(d) then
			local was = d:GetAttribute(CINE_HIDE_ATTR)
			if was ~= nil then
				d.Enabled = was
				d:SetAttribute(CINE_HIDE_ATTR, nil)
			end
		end
	end
	-- Вернуть видимость всем потомкам (и самой модели) — в т.ч. у клона.
	local function restoreAllVisuals(root)
		if not root then return end
		showVisual(root)
		for _, d in root:GetDescendants() do showVisual(d) end
	end
	local hiddenWatchers = {} -- [Model] = Connection на DescendantAdded

	local function setModelLocalVisible(model, visible)
	if not model then return end
	if hiddenWatchers[model] then
		hiddenWatchers[model]:Disconnect()
		hiddenWatchers[model] = nil
	end
	if visible then
		restoreAllVisuals(model)
	else
		for _, descendant in model:GetDescendants() do hideVisual(descendant) end
		hiddenWatchers[model] = model.DescendantAdded:Connect(function(descendant)
			hideVisual(descendant)
		end)
	end
	-- Регистрируем/снимаем с учёта (см. cinematicHiddenModels выше). Без
	-- этого прерванная катсцена не знала, что именно она успела спрятать,
	-- и модель оставалась невидимой навсегда.
	cinematicHiddenModels[model] = (not visible) or nil
	end

	-- Снимает "слепок" ТЕКУЩЕЙ (пока ещё старой) модели Mine/Cart — ИМЕННО
	-- сейчас, до того как сервер её заменит. Вызывается из обработчиков
	-- кнопки "Купить" НИЖЕ ПО ФАЙЛУ, ДО отправки FireServer("Buy", kind).
	-- Кирку не трогаем — это Tool в руке игрока, а не отдельная модель на
	-- участке, менять там физически нечего.
	captureUpgradeBeforeSnapshot = function(kind)
		if kind ~= "Mine" and kind ~= "Cart" and kind ~= "Pickaxe" then return end

		-- PICKAXE — ОТДЕЛЬНАЯ ВЕТКА. Это КРИТИЧНЫЙ ФИКС: resolveRevealAnchor
		-- ("Pickaxe") честно возвращает nil ПЕРВЫМ значением (там нет
		-- отдельной "модели в мире", как у Mine/Cart — только Tool,
		-- надетый на персонажа), и весь остальной код этой функции ниже
		-- (клонирование "model", слежение за Model в workspace/участке)
		-- рассчитан именно на модель. Раньше это означало: даже после
		-- снятия ограничения по kind выше, функция ВСЁ РАВНО тихо
		-- проваливалась на "if not model then return end" — снимок так и
		-- не строился, а значит и прятать новый инструмент было нечем.
		-- Именно поэтому после апгрейда кирки (например, "фиолетовый меч")
		-- анимации не было ВООБЩЕ — не подождало, не забаговало, а
		-- структурно не могло сработать.
		if kind == "Pickaxe" then
			local character = player.Character
			local tool = character and character:FindFirstChildOfClass("Tool")
			if not tool then return end
			local existing = pendingBeforeModels[kind]
			if existing then existing:Destroy() end
			local clone = tool:Clone()
			for _, descendant in clone:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Anchored = true
					descendant.CanCollide = false
					descendant.CanQuery = false
					descendant.CanTouch = false
				elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
					descendant:Destroy()
				end
			end
			clone.Parent = nil
			pendingBeforeModels[kind] = clone

			if hideOnAppearConnections[kind] then
				hideOnAppearConnections[kind]:Disconnect()
				hideOnAppearConnections[kind] = nil
			end
			if pendingHiddenModels[kind] and pendingHiddenModels[kind].Parent then
				setModelLocalVisible(pendingHiddenModels[kind], true)
			end
			pendingHiddenModels[kind] = nil

			-- Следим за ПЕРСОНАЖЕМ (не workspace/участком) — новый
			-- инструмент реплицируется именно туда, когда сервер выдаёт
			-- обновлённую кирку взамен старой.
			if character then
				hideOnAppearConnections[kind] = character.ChildAdded:Connect(function(child)
					if not child:IsA("Tool") then return end
					setModelLocalVisible(child, false)
					pendingHiddenModels[kind] = child
					if hideOnAppearConnections[kind] then
						hideOnAppearConnections[kind]:Disconnect()
						hideOnAppearConnections[kind] = nil
					end
				end)
			end
			return
		end

		local model = (resolveRevealAnchor(kind))
		if not model then return end
		dropStandIn(kind, true) -- предыдущий недоигранный слепок (например, покупка не удалась) — не копим утечки
		local clone = model:Clone()
		for _, descendant in clone:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.CanTouch = false
				-- Настоящая модель могла быть спрятана ПРОШЛОЙ катсценой
				-- (быстрая повторная покупка) — клон унаследовал бы
				-- невидимость, и дублёр оказался бы прозрачным.
				descendant.LocalTransparencyModifier = 0
			elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
				descendant:Destroy()
			end
		end
		restoreAllVisuals(clone) -- v17: клон не должен унаследовать «спрятанность»
		clone.Parent = nil -- держим в памяти, не в workspace, пока катсцена его не запросит
		pendingBeforeModels[kind] = clone

		-- Дублёр шахты: как только настоящая старая шахта уйдёт из мира,
		-- слепок встаёт на её место. Только для шахты — тележку игрок может
		-- в этот момент везти, и неподвижный дублёр на старом месте был бы
		-- ошибкой.
		if kind == "Mine" then
			standInConnections[kind] = model.AncestryChanged:Connect(function(_, parent)
				if parent == nil or not model:IsDescendantOf(workspace) then
					showStandIn(kind)
				end
			end)
		end

		-- Спрятать НОВУЮ модель СРАЗУ, как только она реплицируется в мир —
		-- не дожидаясь, пока катсцена (playUpgradeRevealCamera) сама до неё
		-- доберётся. Предыдущий незавершённый watcher/спрятанная модель
		-- (например, прошлая покупка сорвалась) — сначала возвращаем.
		if hideOnAppearConnections[kind] then
			hideOnAppearConnections[kind]:Disconnect()
			hideOnAppearConnections[kind] = nil
		end
		if pendingHiddenModels[kind] and pendingHiddenModels[kind].Parent then
			setModelLocalVisible(pendingHiddenModels[kind], true)
		end
		pendingHiddenModels[kind] = nil

		local watchRoot = kind == "Mine" and findOwnPlotContent() or workspace
		if watchRoot then
			hideOnAppearConnections[kind] = watchRoot.ChildAdded:Connect(function(child)
				if not child:IsA("Model") then return end
				local isMatch = kind == "Mine"
					and isPlotMine(child)
					or (kind == "Cart" and child.Name == "Cart_" .. player.Name and child:GetAttribute("OwnerUserId") == player.UserId)
				if not isMatch then return end
				setModelLocalVisible(child, false)
				pendingHiddenModels[kind] = child
				-- Подстраховка к AncestryChanged выше: новая уже здесь —
				-- значит, старой точно больше нет, дублёр обязан стоять.
				if kind == "Mine" then showStandIn(kind) end
				if hideOnAppearConnections[kind] then
					hideOnAppearConnections[kind]:Disconnect()
					hideOnAppearConnections[kind] = nil
				end
			end)
		end
	end

	-- Отменяет ожидание новой модели и возвращает видимость, если покупка
	-- не удалась (BuyResult ok=false) — иначе спрятанная модель (если
	-- сервер всё же успел её создать до отказа) осталась бы невидимой
	-- навсегда, а неиспользованный watcher — висел бы до следующей покупки.
	cancelPendingUpgradeReveal = function(kind)
		-- Покупка не прошла — настоящая старая модель на месте, дублёр не нужен.
		dropStandIn(kind, true)
		if hideOnAppearConnections[kind] then
			hideOnAppearConnections[kind]:Disconnect()
			hideOnAppearConnections[kind] = nil
		end
		if pendingHiddenModels[kind] and pendingHiddenModels[kind].Parent then
			setModelLocalVisible(pendingHiddenModels[kind], true)
		end
		pendingHiddenModels[kind] = nil
	end

	-- ГОРИЗОНТАЛЬНОЕ НАПРАВЛЕНИЕ КАМЕРЫ ОТ ОБЪЕКТА "К БАНКУ" (или НАОБОРОТ).
	--
	-- ЗАЧЕМ. Раньше камера смотрела с фиксированного диагонального угла
	-- (+X,+Z) от объекта независимо от того, как участок реально повёрнут в
	-- мире — на части плотов это утыкало обзор в стену/соседнюю постройку.
	-- Банк у каждого игрока один и тот же (SellZone в мире), поэтому его
	-- направление от объекта — надёжный, ОДИНАКОВЫЙ для всех ориентир,
	-- который почти гарантированно открытый (между плотами и банком всегда
	-- есть проход, иначе игрок не смог бы туда дойти с тележкой).
	--
	-- Mine — камера ставится СО СТОРОНЫ БАНКА (между объектом и банком),
	-- Cart — ровно наоборот, разворот на 180°: тележка обычно стоит носом
	-- к шахте/от банка, и вид с "банковской" стороны почти всегда упирался
	-- бы в саму тележку или зону погрузки.
	local function bankDirectionFrom(focusPos)
		local sellZone = workspace:FindFirstChild("SellZone", true)
		local bankPos = sellZone and (
			sellZone:IsA("BasePart") and sellZone.Position
			or (sellZone:IsA("Model") and sellZone:GetPivot().Position)
		)
		if not bankPos then
			return Vector3.new(1, 0, 0) -- банк не нашли — произвольное, но стабильное направление
		end
		local delta = bankPos - focusPos
		delta = Vector3.new(delta.X, 0, delta.Z)
		if delta.Magnitude < 0.5 then
			return Vector3.new(1, 0, 0)
		end
		return delta.Unit
	end

	-- ПЛЕЙСХОЛДЕР-VFX: пыль + искры + вспышка света в момент "приземления".
	-- Заменить на авторский эффект позже — сам вызов и точка привязки не
	-- изменятся, только содержимое этой функции.
	local function spawnPlaceholderBurst(cframe)
	local anchor = Instance.new("Part")
	anchor.Name = "UpgradeRevealVFX"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = cframe
	anchor.Parent = workspace

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 240, 180)
	light.Range = 18
	light.Brightness = 6
	light.Parent = anchor
	TweenService:Create(light, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Brightness = 0 }):Play()

	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(220, 200, 160))
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 3),
	})
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Lifetime = NumberRange.new(0.5, 0.9)
	dust.Speed = NumberRange.new(6, 10)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Rate = 0
	dust.Parent = anchor
	dust:Emit(24)

	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 235, 150))
	sparkle.Size = NumberSequence.new(0.6)
	sparkle.Lifetime = NumberRange.new(0.4, 0.7)
	sparkle.Speed = NumberRange.new(4, 8)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Rate = 0
	sparkle.Parent = anchor
	sparkle:Emit(16)

	task.delay(2, function()
		if anchor.Parent then anchor:Destroy() end
	end)
	end

	-- ГАБАРИТЫ ПО ВИДИМЫМ ДЕТАЛЯМ. GetBoundingBox учитывает и невидимые
	-- служебные части шахты (Zone парковки, маркеры камеры, точки входа),
	-- из-за них кадр уезжал в сторону. Считаем AABB в мировых осях только
	-- по тому, что игрок реально видит. Возвращает центр, размер, низ (Y).
	local function visibleBounds(model)
		if not model then return nil end
		local minV, maxV
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part.Transparency < 0.95 then
				local half = part.Size / 2
				local cf = part.CFrame
				for _, sx in { -1, 1 } do
					for _, sy in { -1, 1 } do
						for _, sz in { -1, 1 } do
							local corner = cf:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
							if minV then
								minV = minV:Min(corner)
								maxV = maxV:Max(corner)
							else
								minV, maxV = corner, corner
							end
						end
					end
				end
			end
		end
		if not minV then
			local ok, cf, size = pcall(function() return model:GetBoundingBox() end)
			if not ok then return nil end
			return cf.Position, size, cf.Position.Y - size.Y / 2
		end
		return (minV + maxV) / 2, maxV - minV, minV.Y
	end

	-- Масштаб модели ОТНОСИТЕЛЬНО её собственного (baseScale — масштаб,
	-- который был у клона изначально) с неподвижной точкой anchor. Раньше
	-- клоны шахты масштабировались АБСОЛЮТНО (ScaleTo(1)) — а шахта в мире
	-- стоит в MineBaseScale (1.3), то есть клон на старте катсцены
	-- внезапно становился на 30% меньше настоящей. И сжималась она к
	-- пивоту (двери), а не к земле.
	local function scaleModelAbout(model, baseScale, factor, anchor)
		local current = model:GetScale()
		local target = baseScale * math.max(factor, 0.02)
		if current <= 0 or math.abs(current - target) < 1e-4 then return end
		local k = target / current
		local pivotBefore = model:GetPivot().Position
		model:ScaleTo(target)
		model:PivotTo(model:GetPivot() + (anchor - pivotBefore) * (1 - k))
	end

	-- КАМЕННЫЕ ОСКОЛКИ ВО ВСЕ СТОРОНЫ (по прямому запросу). Чисто
	-- локальные детали: вылетают из основания шахты по кругу, летят по
	-- дуге с вращением, один раз отскакивают от земли, затем сжимаются и
	-- исчезают. Размер и дальность — от размеров шахты, чтобы на большой
	-- модели осколки не выглядели крошками. Папка регистрируется в
	-- cinematicTempClones — при обрыве катсцены её уберёт skipActiveCinematic.
	local function spawnRockDebris(center, groundY, footprint, height)
		local folder = Instance.new("Folder")
		folder.Name = "UpgradeRockDebris"
		folder.Parent = workspace
		cinematicTempClones[folder] = true

		local sizeScale = math.clamp(footprint / 14, 0.8, 2.6)
		local count = math.clamp(math.floor(12 + footprint * 0.5), 14, 26)
		local palette = {
			Color3.fromRGB(112, 104, 96), Color3.fromRGB(88, 82, 76),
			Color3.fromRGB(128, 116, 100), Color3.fromRGB(96, 90, 86),
		}
		local rocks = {}
		for i = 1, count do
			local part = Instance.new("Part")
			part.Name = "Rock"
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Material = (i % 3 == 0) and Enum.Material.Rock or Enum.Material.Slate
			part.Color = palette[(i % #palette) + 1]
			local size = Vector3.new(
				0.7 + math.random() * 1.1,
				0.6 + math.random() * 0.9,
				0.7 + math.random() * 1.1
			) * sizeScale
			part.Size = size
			local angle = (i / count) * math.pi * 2 + (math.random() - 0.5) * 0.5
			local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local start = Vector3.new(center.X, groundY + height * (0.15 + math.random() * 0.35), center.Z)
				+ dir * footprint * 0.3
			local speed = (16 + math.random() * 14) * math.sqrt(sizeScale)
			local rise = (14 + math.random() * 12) * math.sqrt(sizeScale)
			local spinAxis = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
			if spinAxis.Magnitude < 0.05 then spinAxis = Vector3.yAxis end
			part.CFrame = CFrame.new(start) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
			part.Parent = folder
			table.insert(rocks, {
				Part = part,
				Position = start,
				Velocity = dir * speed + Vector3.new(0, rise, 0),
				Rotation = part.CFrame - part.CFrame.Position,
				SpinAxis = spinAxis.Unit,
				SpinSpeed = 6 + math.random() * 10,
				BaseSize = size,
				Bounced = false,
			})
		end

		local gravity = 70
		local lifetime = 1.25
		local fadeFrom = 0.8
		local startedAt = os.clock()
		local connection
		connection = RunService.Heartbeat:Connect(function(dt)
			dt = math.min(dt, 1 / 20)
			local elapsed = os.clock() - startedAt
			if elapsed >= lifetime or not folder.Parent then
				connection:Disconnect()
				cinematicTempClones[folder] = nil
				if folder.Parent then folder:Destroy() end
				return
			end
			local fade = elapsed > fadeFrom and math.clamp((elapsed - fadeFrom) / (lifetime - fadeFrom), 0, 1) or 0
			for _, rock in rocks do
				rock.Velocity -= Vector3.new(0, gravity * dt, 0)
				rock.Position += rock.Velocity * dt
				local floorY = groundY + rock.BaseSize.Y * 0.5
				if rock.Position.Y < floorY then
					rock.Position = Vector3.new(rock.Position.X, floorY, rock.Position.Z)
					if not rock.Bounced then
						-- Один упругий отскок, дальше катится и гаснет.
						rock.Bounced = true
						rock.Velocity = Vector3.new(rock.Velocity.X * 0.55, -rock.Velocity.Y * 0.35, rock.Velocity.Z * 0.55)
						rock.SpinSpeed *= 0.6
					else
						rock.Velocity = Vector3.new(rock.Velocity.X * 0.9, 0, rock.Velocity.Z * 0.9)
					end
				end
				rock.Rotation = CFrame.fromAxisAngle(rock.SpinAxis, rock.SpinSpeed * dt) * rock.Rotation
				rock.Part.Size = rock.BaseSize * (1 - fade * 0.95)
				rock.Part.Transparency = fade * 0.6
				rock.Part.CFrame = CFrame.new(rock.Position) * rock.Rotation
			end
		end)
	end

	-- Мгновенно обрывает текущую катсцену (если играет) — используется и спам-
	-- защитой в начале playUpgradeRevealCamera, и (при желании) извне.
	local function skipActiveCinematic()
	if not cinematicActive then return end
	cinematicActive = false
	cinematicToken += 1
	workspace.CurrentCamera.CameraType = cinematicRestoreCameraType
	-- Промпты обратно — иначе прерванная катсцена оставила бы игрока
	-- вообще без "E" до конца сессии.
	setCinematicPromptsBlocked(false)
	-- ВОЗВРАТ МИРА В ПОРЯДОК (см. cinematicHiddenModels/cinematicTempClones
	-- выше). Именно этого шага раньше не было — оборванная сцена оставляла
	-- за собой невидимые настоящие модели и живые временные клоны.
	for model in cinematicHiddenModels do
		if model.Parent then
			setModelLocalVisible(model, true)
		end
		cinematicHiddenModels[model] = nil
	end
	for clone in cinematicTempClones do
		if clone.Parent then clone:Destroy() end
		cinematicTempClones[clone] = nil
	end
	end

	playUpgradeRevealCamera = function(kind, closeMenu)
	skipActiveCinematic() -- спам-клики: обрываем предыдущую катсцену без доигрывания

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if not (hrp and camera) then return end

	-- v12: ТЕЛЕЖКИ МОЖЕТ НЕ БЫТЬ В МИРЕ ВООБЩЕ — она лежит упаковкой в
	-- рюкзаке, пока игрок её не поставит. Показывать в этом случае нечего:
	-- выходим сразу, не тратя полторы секунды на ожидание репликации модели
	-- (цикл ниже). Игрок вместо катсцены получает уведомление "новая
	-- упаковка" от сервера, а сама тележка нового тира соберётся в момент
	-- постановки. Если тележка СТОИТ (или её несут) — всё как раньше:
	-- камера летит к ней и показывает уже улучшенную.
	if kind == "Cart" and player:GetAttribute("CartDeployed") ~= true then
		if closeMenu then closeMenu() end
		cancelPendingUpgradeReveal(kind)
		return
	end

	local revealModel, focusPart = resolveRevealAnchor(kind)

	-- ФИКС "КАМЕРА ИНОГДА НЕ НАВОДИТСЯ НА ТО, ЧТО УЛУЧШАЕТСЯ": BuyResult и
	-- репликация самой новой модели Mine/Cart идут РАЗНЫМИ путями (RemoteEvent
	-- vs обычная репликация Instance) — сервер отправляет BuyResult СРАЗУ
	-- после смены модели, но нет гарантии, что сама модель к этому моменту
	-- уже успела реплицироваться клиенту. Раньше resolveRevealAnchor не
	-- находил её вовремя, focusPart оставался nil, и катсцена молча
	-- пропускалась целиком (ниже — "нечего показать"), из-за чего казалось,
	-- что камера "не наводится". Даём модели до 1.5 сек, чтобы доехать.
	if not focusPart and (kind == "Mine" or kind == "Cart" or kind == "Pickaxe") then
		local deadline = os.clock() + 1.5
		while not focusPart and os.clock() < deadline do
			task.wait(0.05)
			revealModel, focusPart = resolveRevealAnchor(kind)
		end
	end

	-- Модель уже спрятана watcher'ом из captureUpgradeBeforeSnapshot (если
	-- он успел сработать) — катсцена теперь сама владеет её видимостью,
	-- снимаем с учёта, чтобы cancelPendingUpgradeReveal её не трогала.
	if hideOnAppearConnections[kind] then
		hideOnAppearConnections[kind]:Disconnect()
		hideOnAppearConnections[kind] = nil
	end
	if pendingHiddenModels[kind] then
		-- Подстраховка: resolveRevealAnchor не нашёл то же самое (не должно
		-- случаться — критерии поиска идентичны watcher'у), но раз модель
		-- уже спрятана, а катсцена её не заберёт — возвращаем видимость,
		-- чтобы она не осталась невидимой навсегда.
		if revealModel ~= pendingHiddenModels[kind] and pendingHiddenModels[kind].Parent then
			setModelLocalVisible(pendingHiddenModels[kind], true)
		end
		pendingHiddenModels[kind] = nil
	end

	-- Слежение за исчезновением старой шахты НЕ снимаем: если её удаление
	-- реплицируется позже старта сцены, дублёр всё равно встанет вовремя.
	-- Шаг 3 ниже сам забирает клон из pendingBeforeModels, после этого
	-- showStandIn ничего не делает.

	if not focusPart then
		-- Нечего показать — тихо пропускаем, но дублёр старой шахты не
		-- должен остаться стоять в мире навсегда.
		dropStandIn(kind, true)
		if revealModel then setModelLocalVisible(revealModel, true) end
		return
	end

	if closeMenu then closeMenu() end

	cinematicToken += 1
	local token = cinematicToken
	cinematicActive = true
	cinematicRestoreCameraType = camera.CameraType
	local startCFrame = camera.CFrame
	camera.CameraType = Enum.CameraType.Scriptable
	-- Гасим ВСЕ ProximityPrompt на время сцены (см. setCinematicPromptsBlocked
	-- выше) — по прямому запросу "во время катсцены улучшения нельзя было
	-- открывать проксимитипромпт (на е)".
	setCinematicPromptsBlocked(true)

	local function stillActive()
		return cinematicActive and cinematicToken == token
	end

	task.spawn(function()
		local ok, err = xpcall(function()
			-- Геометрия финального кадра считается ЗАРАНЕЕ (раньше — только
			-- перед шагом 2) — план сбоку-СВЕРХУ, ЗАМЕТНО выше самого
			-- объекта (чтобы не утыкаться в шахту/землю на крупных
			-- моделях), а горизонтальное направление — от банка (для
			-- шахты) или строго напротив (для тележки, разворот 180°),
			-- вместо фиксированного угла — так обзор почти гарантированно
			-- не упирается в стену/соседнюю постройку участка.
			local focusPos = focusPart.Position
			local objectHeight, objectRadius = 6, 6
			if revealModel then
				local boundsOk, _, boundsSize = pcall(function() return revealModel:GetBoundingBox() end)
				if boundsOk and boundsSize then
					objectHeight = boundsSize.Y
					objectRadius = math.max(boundsSize.X, boundsSize.Z)
				end
			end
			local camHeight = math.max(objectHeight * 1.8, 20) -- "сильно выше" по прямому запросу
			local camDistance = math.max(objectRadius * 1.2, 12)
			local focusLookAt = focusPos + Vector3.new(0, objectHeight * 0.35, 0)
			local horizontalDir
			if kind == "Mine" then
				horizontalDir = bankDirectionFrom(focusPos) -- со стороны банка
			elseif kind == "Cart" then
				horizontalDir = -bankDirectionFrom(focusPos) -- 180° от банка
			else
				-- Кирка — не про "сторону банка" (объект буквально в руке
				-- игрока), нужен просто ракурс сбоку от игрока, а не в его
				-- собственную спину/тело.
				local side = hrp.CFrame.RightVector
				side = Vector3.new(side.X, 0, side.Z)
				horizontalDir = side.Magnitude > 0.1 and side.Unit or Vector3.new(1, 0, 0)
			end
			local focusCamCFrame = CFrame.new(focusPos + horizontalDir * camDistance + Vector3.new(0, camHeight, 0), focusLookAt)

			-- ШАХТА — ВСЯ МОДЕЛЬ В КАДРЕ (по прямому запросу). Кадр строится
			-- по объединённым габаритам СТАРОЙ и НОВОЙ шахты (видимые детали),
			-- дистанция — чтобы описанная сфера целиком влезала в FOV 55 с
			-- небольшим запасом; ракурс со стороны банка, чуть сверху.
			local mineFrame = nil
			if kind == "Mine" and revealModel then
				local newCenter, newSize, newBottom = visibleBounds(revealModel)
				local oldCenter, oldSize, oldBottom = visibleBounds(pendingBeforeModels[kind])
				if newCenter then
					local minV = newCenter - newSize / 2
					local maxV = newCenter + newSize / 2
					if oldCenter then
						minV = minV:Min(oldCenter - oldSize / 2)
						maxV = maxV:Max(oldCenter + oldSize / 2)
					end
					local center = (minV + maxV) / 2
					local size = maxV - minV
					local radius = math.max(size.Magnitude / 2, 6)
					local halfFov = math.rad(55 / 2)
					local distance = radius / math.sin(halfFov) * 1.12
					local elevation = math.rad(22)
					local dir = bankDirectionFrom(center)
					local eye = center + dir * (math.cos(elevation) * distance) + Vector3.new(0, math.sin(elevation) * distance, 0)
					focusCamCFrame = CFrame.new(eye, center)
					focusLookAt = center
					horizontalDir = dir
					camDistance = distance * math.cos(elevation)
					camHeight = distance * math.sin(elevation)
					focusPos = center
					mineFrame = {
						NewCenter = newCenter, NewSize = newSize, NewBottom = newBottom,
						OldCenter = oldCenter, OldSize = oldSize, OldBottom = oldBottom,
					}
				end
			end

			-- ПОДМЕНА ДЕЛАЕТСЯ ДО ПОЛЁТА КАМЕРЫ.
			--
			-- Сервер заменяет модель синхронно, ещё до отправки BuyResult,
			-- а перелёт камеры (отъезд + наводка) занимает почти секунду.
			-- Раньше новая модель пряталась только ПОСЛЕ прилёта — и игрок
			-- успевал увидеть последовательность "новая → старая → новая":
			-- всю дорогу камера летела к уже обновлённой шахте, и лишь в
			-- кадре прибытия её подменяли на слепок старой.
			--
			-- Теперь прячем новую и ставим слепок старой ПЕРВЫМ делом, так
			-- что во время всего перелёта в кадре стоит ровно та шахта,
			-- которая была до покупки, — а меняется она уже в катсцене.
			local preSwapped = false
			if kind == "Mine" and revealModel and mineFrame then
				local beforeClone = pendingBeforeModels[kind]
				if beforeClone then
					setModelLocalVisible(revealModel, false)
					beforeClone.Parent = workspace
					cinematicTempClones[beforeClone] = true
					preSwapped = true
				end
			end

			-- 1) "Вылет" — широкий отъездной план, но УЖЕ по той же линии
			-- подлёта, что и финальный кадр (дальше и выше той же точки),
			-- а не позади игрока в сторону, куда он случайно стоял лицом.
			-- РАНЬШЕ это было двумя несвязанными направлениями: сначала
			-- камера уезжала "в спину игроку", потом на шаге 2 резко
			-- разворачивалась на объект — и это читалось как "сначала
			-- долго крутится, только потом летит". Теперь весь перелёт —
			-- одна плавная дуга к одной и той же точке с самого начала.
			local pullBackCFrame = CFrame.new(
				focusPos + horizontalDir * (camDistance * 1.8) + Vector3.new(0, camHeight * 1.6, 0),
				focusLookAt
			)
			local flyOut = TweenService:Create(camera, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				CFrame = pullBackCFrame,
				FieldOfView = 80,
			})
			flyOut:Play()
			flyOut.Completed:Wait()
			if not stillActive() then return end

			-- 2) Наводимся на объект — финальный кадр (см. focusCamCFrame
			-- выше) НЕ ИЗМЕНИЛСЯ, по прямому запросу — трогали только
			-- заход в катсцену, не место, куда она в итоге приезжает.
			local flyIn = TweenService:Create(camera, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
				CFrame = focusCamCFrame,
				FieldOfView = 55,
			})
			flyIn:Play()
			flyIn.Completed:Wait()
			if not stillActive() then return end

			-- 3) "СТАРАЯ ТРЯСЁТСЯ, ПОТОМ УМЕНЬШАЕТСЯ, НА ЕЁ МЕСТЕ ПОЯВЛЯЕТСЯ
			-- НОВАЯ С VFX ВОКРУГ" — по прямому запросу, взамен прежнего
			-- "выезда из-под земли".
			--
			-- ВАЖНЫЙ НЮАНС: к этому моменту сервер УЖЕ заменил объект в мире
			-- на новый (UpgradeService:_tryBuy вызывает SetMineTier/
			-- UpgradeOwnedCart СИНХРОННО, до отправки BuyResult) — то есть
			-- самой "старой" модели физически больше не существует, когда
			-- играет эта катсцена. Поэтому её слепок снимается ЗАРАНЕЕ, в
			-- момент клика "Купить" (см. captureUpgradeBeforeSnapshot,
			-- вызывается из обработчиков кнопки покупки НИЖЕ по файлу,
			-- ДО FireServer("Buy", ...)) и складывается в pendingBeforeModels
			-- — здесь мы просто забираем этот заранее сохранённый клон.
			local finalPivot = revealModel and revealModel:GetPivot() or CFrame.new(focusPart.Position)
			local groundCFrame = CFrame.new(finalPivot.Position.X, finalPivot.Position.Y, finalPivot.Position.Z)
			if kind == "Mine" and revealModel and mineFrame then
				-- ШАХТА: старая → резко сжимается → сразу вырастает новая,
				-- во все стороны разлетаются каменные осколки и исчезают.
				-- Шахтёр в сцене не участвует вообще (см. isPlotMine).
				-- Если подмена уже сделана выше (до полёта камеры) —
				-- повторять её не нужно, слепок уже в мире.
				if not preSwapped then
					setModelLocalVisible(revealModel, false)
				end

				local beforeClone = pendingBeforeModels[kind]
				pendingBeforeModels[kind] = nil
				if beforeClone then
					-- Старая шахта остаётся РОВНО там, где стояла (клон
					-- снят в момент клика и хранит свои мировые позиции).
					if not preSwapped then
						beforeClone.Parent = workspace
						cinematicTempClones[beforeClone] = true
					end
					local oldBase = beforeClone:GetScale()
					local oldAnchor = Vector3.new(mineFrame.OldCenter.X, mineFrame.OldBottom, mineFrame.OldCenter.Z)

					-- Показываем старую — игрок должен успеть её увидеть.
					task.wait(0.25)
					if stillActive() and beforeClone.Parent then
						-- 1) Нарастающая тряска старой шахты + лёгкая дрожь
						-- камеры: "что-то сейчас произойдёт".
						local basePivot = beforeClone:GetPivot()
						local rumbleStart = os.clock()
						local rumbleDuration = 0.42
						while stillActive() and beforeClone.Parent do
							local a = math.clamp((os.clock() - rumbleStart) / rumbleDuration, 0, 1)
							local amplitude = 0.06 + a * 0.32
							beforeClone:PivotTo(basePivot + Vector3.new(
								(math.random() - 0.5) * amplitude * 2,
								(math.random() - 0.5) * amplitude * 0.5,
								(math.random() - 0.5) * amplitude * 2
							))
							camera.CFrame = focusCamCFrame + Vector3.new((math.random() - 0.5) * a * 0.3, (math.random() - 0.5) * a * 0.3, 0)
							if a >= 1 then break end
							RunService.Heartbeat:Wait()
						end
						if beforeClone.Parent then beforeClone:PivotTo(basePivot) end
						camera.CFrame = focusCamCFrame
					end
					if stillActive() and beforeClone.Parent then
						-- 2) Замах: чуть "вздувается" (читается как давление
						-- изнутри), 3) и резко схлопывается в основание.
						local swellStart = os.clock()
						local swellDuration = 0.1
						while stillActive() and beforeClone.Parent do
							local a = math.clamp((os.clock() - swellStart) / swellDuration, 0, 1)
							pcall(scaleModelAbout, beforeClone, oldBase, 1 + math.sin(a * math.pi / 2) * 0.06, oldAnchor)
							if a >= 1 then break end
							RunService.Heartbeat:Wait()
						end
						local startedAt = os.clock()
						local duration = 0.18
						while stillActive() and beforeClone.Parent do
							local a = math.clamp((os.clock() - startedAt) / duration, 0, 1)
							pcall(scaleModelAbout, beforeClone, oldBase, 1.06 - a * a * 1.04, oldAnchor)
							if a >= 1 then break end
							RunService.Heartbeat:Wait()
						end
					end
					cinematicTempClones[beforeClone] = nil
					if beforeClone.Parent then beforeClone:Destroy() end
				end
				if not stillActive() then
					setModelLocalVisible(revealModel, true)
					return
				end

				-- Новая вырастает СРАЗУ, из того же основания, с перелётом.
				local newClone = revealModel:Clone()
				for _, descendant in newClone:GetDescendants() do
					if descendant:IsA("BasePart") then
						descendant.Anchored = true
						descendant.CanCollide = false
						descendant.CanQuery = false
						descendant.CanTouch = false
						descendant.LocalTransparencyModifier = 0
					elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
						descendant:Destroy()
					end
				end
				-- v17: клон целиком видим (частицы/свет/GUI — как у оригинала).
				restoreAllVisuals(newClone)
				newClone.Parent = workspace
				cinematicTempClones[newClone] = true
				local newBase = newClone:GetScale()
				local newAnchor = Vector3.new(mineFrame.NewCenter.X, mineFrame.NewBottom, mineFrame.NewCenter.Z)
				pcall(scaleModelAbout, newClone, newBase, 0.02, newAnchor)

				local footprint = math.max(mineFrame.NewSize.X, mineFrame.NewSize.Z)
				spawnRockDebris(mineFrame.NewCenter, mineFrame.NewBottom, footprint, mineFrame.NewSize.Y)
				spawnPlaceholderBurst(CFrame.new(newAnchor))

				local growStart = os.clock()
				local growDuration = 0.42
				while stillActive() and newClone.Parent do
					local a = math.clamp((os.clock() - growStart) / growDuration, 0, 1)
					-- EaseOutBack: вырастает чуть больше и садится в размер.
					local c1, c3 = 1.6, 2.6
					local eased = 1 + c3 * (a - 1) ^ 3 + c1 * (a - 1) ^ 2
					pcall(scaleModelAbout, newClone, newBase, math.max(0.02, eased), newAnchor)
					if a >= 1 then break end
					RunService.Heartbeat:Wait()
				end
				cinematicTempClones[newClone] = nil
				if newClone.Parent then newClone:Destroy() end
				setModelLocalVisible(revealModel, true)
			elseif revealModel then
				setModelLocalVisible(revealModel, false)

				local beforeClone = pendingBeforeModels[kind]
				pendingBeforeModels[kind] = nil
				if beforeClone then
					beforeClone:PivotTo(finalPivot)
					beforeClone.Parent = workspace
					cinematicTempClones[beforeClone] = true -- см. skipActiveCinematic: клон должен исчезнуть даже при обрыве сцены
					pcall(function() beforeClone:ScaleTo(1) end)

					-- Тряска: несколько кадров случайного смещения вокруг
					-- исходного места, затухающих к концу — читается как
					-- "тряхнуло перед тем, как пропасть", а не просто дрожь.
					local shakeDuration = 0.35
					local shakeElapsed = 0
					while stillActive() and shakeElapsed < shakeDuration and beforeClone.Parent do
						local dt = task.wait(1 / 30)
						shakeElapsed += dt
						local shakeAlpha = 1 - shakeElapsed / shakeDuration
						local jitter = Vector3.new(math.random() - 0.5, (math.random() - 0.5) * 0.5, math.random() - 0.5) * 0.35 * shakeAlpha
						beforeClone:PivotTo(finalPivot + jitter)
					end
					if beforeClone.Parent then beforeClone:PivotTo(finalPivot) end

					if stillActive() and beforeClone.Parent then
						-- Уменьшение: старая модель схлопывается в точку и
						-- пропадает (EasingDirection.In — ускоряющееся
						-- сжатие, читается как "уменьшается", а не тает).
						local shrink = Instance.new("NumberValue")
						shrink.Value = 1
						local shrinkChanged
						shrinkChanged = shrink.Changed:Connect(function(alpha)
							if not beforeClone.Parent then return end
							pcall(function() beforeClone:ScaleTo(math.max(alpha, 0.02)) end)
						end)
						local shrinkTween = TweenService:Create(shrink, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = 0.02 })
						shrinkTween:Play()
						shrinkTween.Completed:Wait()
						if shrinkChanged then shrinkChanged:Disconnect() end
						shrink:Destroy()
					end
					cinematicTempClones[beforeClone] = nil
					if beforeClone.Parent then beforeClone:Destroy() end
				end
				if not stillActive() then
					setModelLocalVisible(revealModel, true)
					return
				end

				-- "На её месте появляется новая — с VFX вокруг". Как и
				-- раньше, растим НЕ саму настоящую модель (рискованно —
				-- она уже часть игровой логики: зона детекта тележки у
				-- шахты и т.п.), а временный клон; настоящую показываем
				-- только когда клон уже отыграл и удалён. Подъём из-под
				-- земли убран по прямому запросу — теперь просто рост на
				-- месте.
				local newClone = revealModel:Clone()
				for _, descendant in newClone:GetDescendants() do
					if descendant:IsA("BasePart") then
						descendant.Anchored = true
						descendant.CanCollide = false
						descendant.CanQuery = false
						descendant.CanTouch = false
					elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
						descendant:Destroy()
					end
				end
				restoreAllVisuals(newClone) -- v17
				newClone.Parent = workspace
				cinematicTempClones[newClone] = true -- см. skipActiveCinematic
				newClone:PivotTo(finalPivot)
				pcall(function() newClone:ScaleTo(0.05) end)

				spawnPlaceholderBurst(groundCFrame) -- VFX вокруг — ровно в момент начала появления

				local growth = Instance.new("NumberValue")
				growth.Value = 0.05
				local growthChanged
				growthChanged = growth.Changed:Connect(function(alpha)
					if not newClone.Parent then return end
					pcall(function() newClone:ScaleTo(math.clamp(alpha, 0.05, 1.15)) end)
				end)
				local growTween = TweenService:Create(growth, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Value = 1 })
				growTween:Play()
				growTween.Completed:Wait()
				if growthChanged then growthChanged:Disconnect() end
				growth:Destroy()
				cinematicTempClones[newClone] = nil
				if newClone.Parent then newClone:Destroy() end
				setModelLocalVisible(revealModel, true)
			else
				task.wait(0.35) -- кирка: нет отдельной модели для смены, просто держим план
				spawnPlaceholderBurst(groundCFrame)
			end
			if not stillActive() then return end

			-- 4) Camera shake — короткий, затухающий, ровно в момент "приземления".
			local shakeDuration = 0.18
			local shakeElapsed = 0
			local shakeConn
			shakeConn = RunService.Heartbeat:Connect(function(dt)
				if not stillActive() then
					if shakeConn then shakeConn:Disconnect() end
					return
				end
				shakeElapsed += dt
				local shakeAlpha = math.clamp(1 - shakeElapsed / shakeDuration, 0, 1)
				local offset = Vector3.new((math.random() - 0.5) * 0.4 * shakeAlpha, (math.random() - 0.5) * 0.4 * shakeAlpha, 0)
				camera.CFrame = focusCamCFrame + offset
			end)
			task.wait(shakeDuration)
			if shakeConn then shakeConn:Disconnect() end
			if not stillActive() then return end

			task.wait(0.35) -- держим финальный кадр, чтобы объект успели рассмотреть

			-- 5) Возвращаем камеру игроку.
			local restoreTween = TweenService:Create(camera, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				CFrame = startCFrame,
				FieldOfView = 70,
			})
			restoreTween:Play()
			restoreTween.Completed:Wait()
			if cinematicToken == token then
				cinematicActive = false
				camera.CameraType = cinematicRestoreCameraType
				setCinematicPromptsBlocked(false) -- сцена доиграла штатно — возвращаем "E"
			end
		end, debug.traceback)

		-- СЕТКА БЕЗОПАСНОСТИ. Раньше вся последовательность выше не была
		-- ничем защищена: любая ошибка посреди неё (например, Model:ScaleTo
		-- падает на моделях с необычным содержимым — Terrain/незаанкоренные
		-- части/etc.) молча убивала корутину ДО финального шага 5, и камера
		-- НАВСЕГДА оставалась в CameraType.Scriptable, замороженная там, где
		-- сцена оборвалась. Игроку это выглядело как "всё перестало
		-- работать" — по факту переставала обновляться и сама камера, и
		-- любой UI/прицеливание, которые от неё зависят. Этот блок
		-- гарантирует восстановление ВСЕГДА, даже при ошибке; если сцена уже
		-- штатно восстановила камеру сама (успешный путь) или её кто-то
		-- скипнул новой покупкой (token уже другой) — здесь просто no-op.
		if not ok then
			warn("[CustomCartUI] Катсцена апгрейда (" .. tostring(kind) .. ") упала, восстанавливаю камеру принудительно:", err)
		end
		if cinematicToken == token and cinematicActive then
			cinematicActive = false
			pcall(function() camera.CameraType = cinematicRestoreCameraType end)
		end
		-- Промпты возвращаем БЕЗУСЛОВНО, вне зависимости от токена: даже
		-- если сцену уже перебила новая покупка, оставить игрока без "E"
		-- нельзя ни при каком стечении обстоятельств.
		pcall(function() setCinematicPromptsBlocked(false) end)
	end)
	end -- playUpgradeRevealCamera
end -- function setupUpgradeRevealCinematic (см. комментарий у "local playUpgradeRevealCamera" выше)
setupUpgradeRevealCinematic()

-- ОТКАТ ПОКУПКИ ПРОКАЧКИ НА КЛИЕНТЕ (см. Config.UpgradeShop.PurchaseCooldownSeconds
-- и UpgradeService — там же объяснено, почему откат вообще появился).
--
-- Сервер и так авторитетно отказывает в покупке во время отката, но
-- отправлять запрос, заведомо обречённый на отказ, — плохой опыт: игрок
-- жмёт карточку, слышит звук отказа и не понимает, что произошло. Здесь
-- мы просто НЕ ОТПРАВЛЯЕМ такой запрос и показываем, сколько осталось.
-- Атрибут UpgradeCooldownEndsAt выставляет сервер (os.time() конца
-- отката), поэтому подделать его клиент не может — а если бы и подделал,
-- дальше стоит та же проверка на сервере.
local function upgradeCooldownRemaining()
	local endsAt = tonumber(player:GetAttribute("UpgradeCooldownEndsAt")) or 0
	if endsAt <= 0 then return 0 end
	return math.max(0, endsAt - os.time())
end

--------------------------------------------------------------------------------
-- ОБРАТНЫЙ ОТСЧЁТ НА КНОПКАХ ПОКУПКИ.
--
-- Пока идёт откат, кнопка должна выглядеть неактивной и честно говорить,
-- сколько осталось ждать — иначе игрок жмёт по зелёной кнопке, слышит звук
-- отказа и не понимает, сломалось что-то или так задумано.
--
-- ОДИН общий цикл на весь клиент, а не по таймеру в каждом диалоге. Версий
-- окна прокачки две (новые карточки UpgradeShopCards и старый список
-- DialogResponses), плюс окно может открываться и закрываться много раз за
-- сессию — заводить отдельный цикл в каждом означало бы плодить их пачками
-- и следить за остановкой каждого.
--
-- Слушатели вызываются ТОЛЬКО когда изменилось целое число секунд, а не
-- каждый тик: перерисовывать одинаковый текст 5 раз в секунду незачем.
local upgradeCooldownListeners = {}
local lastBroadcastCooldown = -1

local function addUpgradeCooldownListener(listener)
	table.insert(upgradeCooldownListeners, listener)
	-- Сразу отдаём текущее состояние: окно могли открыть в СЕРЕДИНЕ отката,
	-- и без этого вызова кнопка до следующей смены секунды выглядела бы
	-- активной, хотя покупка уже отклоняется.
	listener(upgradeCooldownRemaining())
	return function()
		for index, entry in upgradeCooldownListeners do
			if entry == listener then
				table.remove(upgradeCooldownListeners, index)
				break
			end
		end
	end
end

task.spawn(function()
	while true do
		task.wait(0.2)
		local remaining = upgradeCooldownRemaining()
		if remaining ~= lastBroadcastCooldown then
			lastBroadcastCooldown = remaining
			for _, listener in upgradeCooldownListeners do
				-- pcall: сбойный слушатель (например, у уничтоженного
				-- окна) не должен ронять цикл и вместе с ним отсчёт во
				-- всех остальных окнах.
				pcall(listener, remaining)
			end
		end
	end
end)

-- Единая точка отправки покупки: гарантирует, что снимок "до" и сам
-- запрос всегда идут парой и только когда откат уже прошёл. Раньше эти
-- две строки были продублированы в ЧЕТЫРЁХ местах (две версии диалога ×
-- клик и цифровая клавиша), и добавлять проверку в каждое по отдельности
-- означало бы гарантированно где-нибудь её забыть.
-- ВНИМАНИЕ: shopRemoteEvent передаётся ПАРАМЕТРОМ, а не берётся из
-- замыкания. Это не стилистика: сам ремоут объявлен как ЛОКАЛЬНЫЙ внутри
-- каждого из двух блоков диалога НИЖЕ по файлу, а эта функция живёт выше
-- них. Обращение к имени shopRemoteEvent отсюда резолвилось бы в
-- ГЛОБАЛЬНОЕ (то есть в nil) и падало бы на первой же покупке — ровно тот
-- же класс ошибки, что чинился в WeatherService:PurchaseTriggerEvent.
local function requestUpgradePurchase(shopRemoteEvent, kind)
	local remaining = upgradeCooldownRemaining()
	if remaining > 0 then
		-- Звук отказа вместо тишины: игрок должен понять, что нажатие
		-- ЗАРЕГИСТРИРОВАНО, но сейчас идёт откат, а не что кнопка сломана.
		if playUiClick then playUiClick("UiError") end
		return false
	end
	captureUpgradeBeforeSnapshot(kind)
	shopRemoteEvent:FireServer("Buy", kind)
	return true
end

--------------------------------------------------------------------------------
	-- Единственный вид диалога продавца прокачки — карточки из builder'а.
--------------------------------------------------------------------------------
;(function()
	-- МАГАЗИН УЛУЧШЕНИЙ v3 — по образцу окна Island Keeper (IslandUI.client.lua):
	-- вертикальные карточки веток → клик → экран «было → станет», цена,
	-- BUY и ◀ BACK. Окно строится кодом, билдер tools/BuildUpgradeShopCards
	-- больше не нужен (его старый ScreenGui, если он есть в StarterGui,
	-- принудительно выключается ниже). Сервер и протокол не менялись:
	-- "Open"/"Status"/"BuyResult" от сервера, "Buy"/"Open"/"Close" к нему.
	local shopRemoteEvent = ReplicatedStorage.Shared:WaitForChild("UpgradeShopRequest")
	upgradeShopCardsActive = true

	-- v10: одна большая ветка слева (шахта) + квадратные карточки справа.
	local SHOP_ORDER = { "Mine", "Cart", "Pickaxe", "Supplies", "Soon1", "Soon2", "Soon3" }
	local MAIN_KIND = "Mine"
	local SOON_KINDS = { Soon1 = true, Soon2 = true, Soon3 = true }
	local CARD_W, CARD_H = 130, 212
	local MAIN_CARD_W, MAIN_CARD_H = 210, 300   -- v10: главная ветка (шахта)
	local SMALL_CARD_W, SMALL_CARD_H = 140, 144 -- v10: квадратные карточки справа

	local COLORS = {
		Panel = Color3.fromRGB(22, 26, 40),
		Outline = Color3.fromRGB(12, 14, 22),
		Frame = Color3.fromRGB(255, 190, 70),
		TabA = Color3.fromRGB(235, 140, 40),
		TabB = Color3.fromRGB(255, 205, 90),
		Text = Color3.fromRGB(245, 245, 250),
		Muted = Color3.fromRGB(170, 176, 196),
		Buy = Color3.fromRGB(70, 200, 95),
		Poor = Color3.fromRGB(215, 120, 45),
		Grey = Color3.fromRGB(95, 98, 110),
		Gold = Color3.fromRGB(255, 212, 80),
		Close = Color3.fromRGB(225, 50, 55),
		Back = Color3.fromRGB(55, 140, 255),
		Up = Color3.fromRGB(110, 255, 150),
	}
	local KIND_VIEW = {
		Mine = { Title = "CAVE", Icon = "⛰", Color = Color3.fromRGB(120, 170, 255) },
		Cart = { Title = "CART", Icon = "🛒", Color = Color3.fromRGB(95, 215, 130) },
		Pickaxe = { Title = "PICKAXE", Icon = "⛏", Color = Color3.fromRGB(255, 150, 70) },
		Supplies = { Title = "DYNAMITE", Icon = "🧨", Color = Color3.fromRGB(225, 70, 40) },
		Soon1 = { Title = "COMING SOON", Icon = "", Color = Color3.fromRGB(26, 28, 36) },
		Soon2 = { Title = "COMING SOON", Icon = "", Color = Color3.fromRGB(26, 28, 36) },
		Soon3 = { Title = "COMING SOON", Icon = "", Color = Color3.fromRGB(26, 28, 36) },
	}
	-- v10: ДИНАМИТ — одна категория, три вида внутри (Config.Dynamite.Types).
	local SUPPLY_KEY = { Supplies = true }
	local selectedSupply = "Dynamite"
	local function supplyLockedCave(dynamiteKey)
		local info = Config.Dynamite.Types[dynamiteKey]
		local cave = tonumber(player:GetAttribute("MineTier")) or 1
		if info and cave < (info.UnlockCave or 1) then return info.UnlockCave end
		return nil
	end
	-- v8: вкладка снаряжения — динамит (GearService, событие GearRequest).
	local gearRemote = ReplicatedStorage.Shared:WaitForChild("GearRequest", 10)
	local gearStates = {}
	for _, dynamiteKey in Config.Dynamite.Order do
		gearStates[dynamiteKey] = { Count = 0, Price = 0, Max = Config.Dynamite.MaxStack or 50 }
	end

	-- v20: окно собирается билдером (Shared.UiBuilders.UpgradeShopUi →
	-- StarterGui/UpgradeShopUi), здесь только логика.
	local ShopBuilder = require(ReplicatedStorage.Shared.UiBuilders.UpgradeShopUi)
	local UiRegistry = require(ReplicatedStorage.Shared.UiRegistry)
	local UiKit = require(ReplicatedStorage.Shared.UiKit)
	local PANEL_SIZE = ShopBuilder.PANEL_SIZE

	-- Старые экраны прошлых версий — выключаем, чтобы два окна не открывались разом.
	local function disableLegacy(child)
		if (child.Name == "UpgradeShopCards" or child.Name == "UpgradeShopV3") and child:IsA("ScreenGui") then
			child.Enabled = false
		end
	end
	for _, child in playerGui:GetChildren() do disableLegacy(child) end
	playerGui.ChildAdded:Connect(disableLegacy)

	local gui = UiRegistry.Get("UpgradeShopUi")
	gui.ResetOnSpawn = false
	gui.Enabled = false
	local panel = gui:WaitForChild("Panel")
	panel.Visible = false
	local panelScale = panel:FindFirstChild("PanelScale") or Instance.new("UIScale")
	panelScale.Name = "PanelScale"
	panelScale.Parent = panel
	local subtitle = panel:FindFirstChild("Subtitle", true)
	local closeButton = panel:FindFirstChild("Close", true) or panel:FindFirstChild("CloseButton", true)
	local toast = panel:FindFirstChild("Toast", true)
	local content = panel:FindFirstChild("Content", true)
	local templates = gui:WaitForChild("Templates")

	-- Перекраска кнопки в вариант темы (Green/Yellow/Dark/Blue/Red).
	local function paintButton(button, variant)
		UiKit.ApplySkin(button, "Button_" .. variant)
		local skin = UiKit.Theme.Skins["Button_" .. variant]
		local caption = button:FindFirstChild("Caption")
		if caption and skin then
			caption.TextColor3 = skin.TextColor or Color3.new(1, 1, 1)
			local textStroke = caption:FindFirstChild("TextStroke")
			if textStroke and skin.TextStroke then textStroke.Color = skin.TextStroke end
		end
	end
	local function variantFor(color)
		if color == COLORS.Buy then return "Green" end
		if color == COLORS.Poor or color == COLORS.Gold then return "Yellow" end
		if color == COLORS.Back then return "Blue" end
		if color == COLORS.Close then return "Red" end
		return "Dark"
	end

	-- КАРТОЧКА — клон шаблона Templates/Card.
	local function makeCard(parent, width, height)
		local card = templates:WaitForChild("Card"):Clone()
		card.Visible = true
		card.Size = UDim2.fromOffset(width, height)
		card.Parent = parent
		local scale = card:FindFirstChild("HoverScale") or Instance.new("UIScale")
		scale.Parent = card
		local chip = card:FindFirstChild("Chip")
		return {
			Card = card, Rim = card:FindFirstChild("SkinStroke"), Scale = scale,
			Icon = card:FindFirstChild("Icon"), Title = card:FindFirstChild("Title"), Level = card:FindFirstChild("Level"),
			Hint = card:FindFirstChild("Hint"), ChipText = chip and chip:FindFirstChild("Text"), Lock = card:FindFirstChild("Lock"),
			Shine = card:FindFirstChild("Shine"),
		}
	end
	-- Цвет рамки карточки = цвет ветки; тусклая — у недоступных.
	local function paintCard(visual, color, dim)
		if visual.Rim then visual.Rim.Color = color end
		visual.Card:SetAttribute("UiAccent", color)
		if visual.Card.Image ~= "" then
			visual.Card.ImageColor3 = dim and Color3.fromRGB(150, 150, 150) or Color3.new(1, 1, 1)
		end
		visual.Title.TextColor3 = dim and COLORS.Muted or color:Lerp(Color3.new(1, 1, 1), 0.45)
	end
	local function statLine(parent, text, order)
		local line = templates:WaitForChild("StatLine"):Clone()
		line.Visible = true
		line.Text = text
		line.LayoutOrder = order
		line.Parent = parent
		return line
	end
	local latestStatuses = {}
	local selectedKind = nil
	local dialogOpen = false
	local pendingBuy = false

	local function money(value)
		return "$" .. NumberFormat.abbreviate(value)
	end
	local function highlightCost(cost)
		return ("<font color=\"#FFD75A\">$%s</font>"):format(NumberFormat.abbreviate(cost))
	end

	-- Что показывает карточка в сетке: уровень, короткий итог следующего шага.
	local function cardHint(kind, status)
		local nextTier = status.NextTier
		if not nextTier then return "" end
		-- v12: первая тележка. Сервер отдаёт такой статус с Unlock = true и
		-- ценой 0 (UpgradeService:_branchStatus) — это не апгрейд, а выдача
		-- УПАКОВКИ, из которой игрок поставит тележку сам, где захочет.
		if status.Unlock then
			local first = Config.CartTiers[nextTier]
			return first and tr("Free! Holds {a} ore", { a = first.Capacity }) or tr("Free!")
		end
		-- ПОЧИНКА ШАХТЫ. Сервер отдаёт статус с Repair = true (см.
		-- UpgradeService:_branchStatus): это не апгрейд тира, а перевод
		-- шахты из "тира 0" (модель без текстур, чёрный неон) в рабочий
		-- тир 1. Цепочка Config.MineChain при этом не тратится.
		if status.Repair then
			return tr("Reopen the mine and start digging")
		end
		if kind == "Mine" then
			local nextCave = Config.MineTiers[nextTier]
			local newOre = nextCave and nextCave.Ores[#nextCave.Ores]
			return newOre and tr("New ore: {name}", { name = newOre.DisplayName }) or ""
		elseif kind == "Cart" then
			local cur, nxt = Config.CartTiers[status.Tier], Config.CartTiers[nextTier]
			return (cur and nxt) and tr("Space {a} → {b}", { a = cur.Capacity, b = nxt.Capacity }) or ""
		else
			local cur, nxt = Config.PickaxeTiers[status.Tier], Config.PickaxeTiers[nextTier]
			return (cur and nxt) and tr("Damage {a} → {b}", { a = cur.Damage, b = nxt.Damage }) or ""
		end
	end

	local function applyCard(visual, kind, status)
		local view = KIND_VIEW[kind]
		visual.Icon.Text = view.Icon
		visual.Title.Text = tr(view.Title)
		visual.Lock.Visible = false
		visual.Shine.Visible = true
		visual.Icon.TextTransparency = 0
		visual.Title.TextColor3 = COLORS.Text
		visual.Level.TextColor3 = COLORS.Gold
		if SOON_KINDS[kind] then
			-- v10: пустые чёрные карточки-заглушки под будущие ветки.
			paintCard(visual, Color3.fromRGB(85, 85, 95), true)
			visual.Shine.Visible = false
			visual.Icon.Text = "❔"
			visual.Icon.TextTransparency = 0.45
			visual.Title.Text = tr("COMING SOON")
			visual.Title.TextColor3 = COLORS.Muted
			visual.Level.Text = ""
			visual.Hint.Text = ""
			visual.ChipText.Text = ""
			return
		end
		if SUPPLY_KEY[kind] then
			local total = 0
			for _, dynamiteKey in Config.Dynamite.Order do
				total += (gearStates[dynamiteKey] or {}).Count or 0
			end
			paintCard(visual, view.Color, false)
			visual.Level.Text = "x" .. tostring(total)
			visual.Hint.Text = tr("Small · Medium · Mega")
			visual.ChipText.Text = '<font color="#FFE27A">' .. money((gearStates.Dynamite or {}).Price or 0) .. "</font>"
			return
		end
		if not status then
			paintCard(visual, COLORS.Grey, true)
			visual.ChipText.Text = "..."
			visual.Level.Text = ""
			visual.Hint.Text = ""
			return
		end
		local maxTier = 1 + #(kind == "Mine" and Config.MineChain or kind == "Cart" and Config.CartChain or Config.PickaxeChain)
		visual.Level.Text = tr("LV {tier}/{max}", { tier = status.Tier, max = maxTier })
		visual.Hint.Text = cardHint(kind, status)
		if status.State == "Maxed" then
			paintCard(visual, COLORS.Grey, true)
			visual.Icon.TextTransparency = 0.35
			visual.Shine.Visible = false
			visual.ChipText.Text = '<font color="#9CFFB4">✅ ' .. tr("MAX") .. "</font>"
		elseif status.State == "NeedRebirth" then
			paintCard(visual, COLORS.Grey, true)
			visual.Icon.TextTransparency = 0.6
			visual.Title.TextColor3 = COLORS.Muted
			visual.Lock.Visible = true
			visual.Hint.Text = tr("Cave {cap} is the limit for now", { cap = status.Cap or status.Tier })
			visual.ChipText.Text = '<font color="#8CD2FF">' .. tr("PRESTIGE") .. "</font>"
		elseif status.Repair then
			paintCard(visual, view.Color, false)
			visual.ChipText.Text = ((status.Cost or 0) <= 0)
				and ('<font color="#9CFFB4">' .. tr("FREE REPAIR") .. "</font>")
				or ('<font color="#FFC846">' .. tr("REPAIR") .. "</font>")
		elseif status.Unlock then
			-- v12: бесплатная первая тележка — ценник "$0" выглядел бы как
			-- ошибка, поэтому на карточке прямым текстом написано, что она
			-- бесплатная.
			paintCard(visual, view.Color, false)
			visual.ChipText.Text = '<font color="#9CFFB4">' .. tr("GET IT FREE") .. "</font>"
		else
			paintCard(visual, view.Color, false)
			visual.ChipText.Text = status.CanAfford
				and ('<font color="#FFE27A">' .. money(status.Cost) .. "</font>")
				or ('<font color="#FF9E6A">' .. money(status.Cost) .. "</font>")
		end
	end

	-- ЭКРАН 1: СЕТКА (слева большая карточка шахты, справа сетка квадратных).
	local gridView = content:WaitForChild("GridView")
	local row = gridView:WaitForChild("CardRow")
	local sideGrid = row:WaitForChild("SideGrid")
	local gridHint = gridView:WaitForChild("GridHint")
	local gridFooter = gridView:WaitForChild("GridFooter")
	gridHint.Visible = true

	-- ЭКРАН 2: ВЫБРАННАЯ ВЕТКА
	local detailView = content:WaitForChild("DetailView")
	detailView.Visible = false
	local backButton = detailView:WaitForChild("Back")
	local previewHolder = detailView:WaitForChild("PreviewHolder")
	local preview = makeCard(previewHolder, previewHolder.Size.X.Offset > 0 and previewHolder.Size.X.Offset or 150, previewHolder.Size.Y.Offset > 0 and previewHolder.Size.Y.Offset or 226)
	preview.Card.Active = false
	local info = detailView:WaitForChild("Info")
	local detailTitle = info:WaitForChild("DetailTitle")
	local detailDesc = info:WaitForChild("DetailDesc")
	local statsHeader = info:WaitForChild("StatsHeader")
	local statsList = info:WaitForChild("StatsList")
	local priceLabel = detailView:WaitForChild("PriceLabel")
	-- v9: цена показывается ТОЛЬКО на кнопке — отдельная строка скрыта.
	priceLabel.Visible = false
	local actionButton = detailView:WaitForChild("Action")
	local actionText = actionButton:WaitForChild("Caption")
	-- v8: вторая кнопка — только во вкладке SUPPLIES («BUY x5») и для скипа.
	local actionButton2 = detailView:WaitForChild("Action2")
	local actionText2 = actionButton2:WaitForChild("Caption")
	local actionBaseSize, actionBasePosition = actionButton.Size, actionButton.Position
	actionButton2.Visible = false

	-- Строки «было → станет» по ветке. Оценки — до бонусов ребёрта/пассов.
	local function statRows(kind, tier, nextTier)
		local rows = {}
		local function add(name, before, after)
			table.insert(rows, { Name = name, Before = before, After = after })
		end
		local cartTier = tonumber(player:GetAttribute("CartTier")) or 1
		local mineTier = tonumber(player:GetAttribute("MineTier")) or 1
		if kind == "Mine" then
			local cur, nxt = Config.MineTiers[tier], nextTier and Config.MineTiers[nextTier]
			add(tr("Cave"), tier, nextTier)
			add(tr("Ore per dig"), cur and cur.OreYield, nxt and nxt.OreYield)
			add(tr("Avg ore price"), cur and money(cur.ExpectedValue), nxt and money(nxt.ExpectedValue))
			add(tr("Full cart"), money(Config.CartValue(tier, cartTier)), nxt and money(Config.CartValue(nextTier, cartTier)))
			if nxt then
				local newOre = nxt.Ores[#nxt.Ores]
				add(tr("New ore"), nil, newOre and newOre.DisplayName)
			end
		elseif kind == "Cart" then
			local cur, nxt = Config.CartTiers[tier], nextTier and Config.CartTiers[nextTier]
			add(tr("Cargo space"), cur and cur.Capacity, nxt and nxt.Capacity)
			add(tr("Cart health"), cur and cur.MaxHealth, nxt and nxt.MaxHealth)
			add(tr("Full cart"), money(Config.CartValue(mineTier, tier)), nxt and money(Config.CartValue(mineTier, nextTier)))
		else
			local cur, nxt = Config.PickaxeTiers[tier], nextTier and Config.PickaxeTiers[nextTier]
			local hands = Config.HandCarry and Config.HandCarry.CapacityByPickaxeTier or {}
			add(tr("Damage"), cur and cur.Damage, nxt and nxt.Damage)
			add(tr("Ore knocked per hit"), cur and (math.floor(cur.KnockoutPercent * 100) .. "%"), nxt and (math.floor(nxt.KnockoutPercent * 100) .. "%"))
			add(tr("Ore in hands"), hands[tier], nextTier and hands[nextTier])
			add(tr("Boulders up to tier"), tier + 2, nextTier and (nextTier + 2))
		end
		return rows
	end

	local function descFor(kind)
		local descriptions = Config.UpgradeShop and Config.UpgradeShop.Cards and Config.UpgradeShop.Cards.Descriptions or {}
		return tr(descriptions[kind] or "")
	end

	local lastActionColor = COLORS.Buy
	local function setAction(text, color, enabled)
		actionText.Text = text
		lastActionColor = color
		paintButton(actionButton, variantFor(color))
		actionButton.Active = enabled
	end

	-- v10: ДИНАМИТ — одна категория, внутри три вида. Сверху ряд вкладок
	-- SMALL / MEDIUM / MEGA (закрытые — «🔒 CAVE N»), ниже статы выбранного
	-- и две кнопки покупки x1 / x5.
	-- v10: ДИНАМИТ — одна категория, внутри три вида: вкладки SMALL / MEDIUM / MEGA.
	local supplyTabs = detailView:WaitForChild("SupplyTabs")
	supplyTabs.Visible = false

	local renderSupplies
	local supplyTabButtons = {}
	for index, dynamiteKey in Config.Dynamite.Order do
		local info = Config.Dynamite.Types[dynamiteKey]
		local tabButton = templates:WaitForChild("SupplyTab"):Clone()
		tabButton.Name = "Tab_" .. dynamiteKey
		tabButton.Visible = true
		tabButton.Size = UDim2.new(1 / #Config.Dynamite.Order, -6, 1, 0)
		tabButton.BackgroundColor3 = info.Color
		tabButton.Parent = supplyTabs
		local tabText = tabButton:WaitForChild("Caption")
		tabText.Text = info.ShortName or info.DisplayName
		tabButton.LayoutOrder = index
		supplyTabButtons[dynamiteKey] = { Button = tabButton, Text = tabText, Info = info }
		tabButton.Activated:Connect(function()
			selectedSupply = dynamiteKey
			playUiClick()
			renderSupplies()
		end)
	end

	renderSupplies = function()
		local dynamiteKey = selectedSupply
		local info = Config.Dynamite.Types[dynamiteKey]
		local gearState = gearStates[dynamiteKey]
		supplyTabs.Visible = true
		for key, entry in supplyTabButtons do
			local locked = supplyLockedCave(key)
			local active = key == dynamiteKey
			entry.Button.BackgroundColor3 = locked and COLORS.Grey or entry.Info.Color
			entry.Text.Text = locked and ("🔒 " .. tostring(locked)) or (entry.Info.ShortName or entry.Info.DisplayName)
			entry.Text.TextColor3 = active and Color3.new(1, 1, 1) or COLORS.Muted
			local stroke = entry.Button:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = active and Color3.fromRGB(255, 225, 130) or Color3.fromRGB(12, 14, 22)
				stroke.Thickness = active and 3 or 2
			end
		end

		applyCard(preview, "Supplies", nil)
		preview.Icon.Text = info.Icon
		preview.Title.Text = tr(info.DisplayName)
		preview.Level.Text = "x" .. tostring(gearState.Count)
		detailTitle.Text = tr(info.DisplayName):upper()
		detailTitle.TextColor3 = info.Color:Lerp(Color3.new(1, 1, 1), 0.35)
		detailDesc.Text = tr("Breaks boulders. Knocks players down.")
		statsHeader.Text = ""
		for _, child in statsList:GetChildren() do
			if child:IsA("TextLabel") then child:Destroy() end
		end
		local rows = {
			tr("In bag: {n}/{max}", { n = gearState.Count, max = gearState.Max }),
			"💥 " .. tr("Radius {n}", { n = info.Radius }),
			"😵 " .. tr("Knockdown {n}s", { n = info.RagdollSeconds }),
			"⏱ " .. tr("Cooldown {n}s", { n = info.Cooldown }),
		}
		for index, line in rows do
			statLine(statsList, line, index)
		end
		priceLabel.Text = highlightCost(gearState.Price)
		local full = gearState.Count >= gearState.Max
		local lockedCave = supplyLockedCave(dynamiteKey)
		-- Две кнопки рядом: BUY x1 слева, BUY x5 справа.
		actionButton.Size = UDim2.new(0.5, -122, 0, 50)
		actionButton.Position = UDim2.new(0.5, 110, 1, -6)
		actionButton2.Visible = lockedCave == nil
		if lockedCave then
			setAction("🔒 " .. tr("CAVE {n}", { n = lockedCave }), COLORS.Grey, false)
			return
		end
		setAction(full and tr("BAG FULL") or ("x1 · " .. money(gearState.Price)), full and COLORS.Grey or COLORS.Buy, not full)
		actionText2.Text = "x5 · " .. money((gearState.Price or 0) * 5)
		local canFive = gearState.Count + 5 <= gearState.Max
		paintButton(actionButton2, canFive and "Green" or "Dark")
		actionButton2.Active = canFive
	end

	local function renderDetail()
		local kind = selectedKind
		if not kind then return end
		if SUPPLY_KEY[kind] then
			renderSupplies()
			return
		end
		supplyTabs.Visible = false
		if SOON_KINDS[kind] then
			-- Заглушка: ничего не продаём, просто рассказываем, что будет.
			applyCard(preview, kind, nil)
			detailTitle.Text = tr("COMING SOON")
			detailTitle.TextColor3 = COLORS.Muted
			detailDesc.Text = tr("A new upgrade branch will live here.")
			statsHeader.Text = ""
			for _, child in statsList:GetChildren() do
				if child:IsA("TextLabel") then child:Destroy() end
			end
			actionButton2.Visible = false
			actionButton.Size = actionBaseSize
			actionButton.Position = actionBasePosition
			setAction(tr("SOON"), COLORS.Grey, false)
			return
		end
		actionButton2.Visible = false
		actionButton.Size = actionBaseSize
		actionButton.Position = actionBasePosition
		local status = latestStatuses[kind]
		applyCard(preview, kind, status)
		local view = KIND_VIEW[kind]
		detailTitle.Text = tr(view.Title)
		detailTitle.TextColor3 = view.Color:Lerp(Color3.new(1, 1, 1), 0.35)
		detailDesc.Text = descFor(kind)
		for _, child in statsList:GetChildren() do
			if child:IsA("TextLabel") then child:Destroy() end
		end
		if not status then
			statsHeader.Text = ""
			priceLabel.Text = ""
			setAction("...", COLORS.Grey, false)
			return
		end
		local nextTier = status.State == "Buyable" and status.NextTier or nil
		statsHeader.Text = "" -- v9: меньше текста — строки «было → станет» говорят сами
		for index, rowInfo in statRows(kind, status.Tier, nextTier) do
			local before = rowInfo.Before ~= nil and tostring(rowInfo.Before) or nil
			local after = rowInfo.After ~= nil and tostring(rowInfo.After) or nil
			local text
			if before and after then
				text = ('%s: <font color="#C8CCDA">%s</font>  →  <font color="#6CFF9A">%s</font>'):format(rowInfo.Name, before, after)
			elseif after then
				text = ('<font color="#6CFF9A">✅</font> %s: <font color="#6CFF9A">%s</font>'):format(rowInfo.Name, after)
			elseif before then
				text = ('%s: <font color="#C8CCDA">%s</font>'):format(rowInfo.Name, before)
			end
			if text then
				statLine(statsList, text, index)
			end
		end

		local cooldown = upgradeCooldownRemaining()
		if status.State == "Maxed" then
			priceLabel.Text = '<font color="#9CFFB4">' .. tr("MAX") .. "</font>"
			setAction(tr("MAX LEVEL"), COLORS.Grey, false)
		elseif status.State == "NeedRebirth" then
			priceLabel.Text = ""
			setAction(tr("NEED PRESTIGE"), COLORS.Grey, false)
		elseif cooldown > 0 then
			priceLabel.Text = highlightCost(status.Cost)
			setAction(tr("WAIT {seconds}s", { seconds = cooldown }), COLORS.Grey, false)
		elseif status.Repair then
			-- Во время обучения починка бесплатна — ценник "$0" выглядел бы
			-- как ошибка (тот же приём, что у бесплатной первой тележки).
			if (status.Cost or 0) <= 0 then
				priceLabel.Text = '<font color="#9CFFB4">' .. tr("FREE") .. "</font>"
				setAction("⛏ " .. tr("REPAIR THE MINE"), COLORS.Buy, true)
			else
				priceLabel.Text = highlightCost(status.Cost)
				setAction("⛏ " .. tr("REPAIR THE MINE"), COLORS.Buy, status.CanAfford)
			end
		elseif status.Unlock then
			-- v12: первая тележка бесплатная и выдаётся УПАКОВКОЙ — кнопка
			-- говорит именно это, а не "улучшить за $0".
			priceLabel.Text = '<font color="#9CFFB4">' .. tr("FREE") .. "</font>"
			setAction("📦 " .. tr("GET YOUR CART"), COLORS.Buy, true)
		else
			priceLabel.Text = highlightCost(status.Cost)
			-- v9: цена прямо на кнопке, без дубля строкой ниже.
			setAction("⬆ " .. money(status.Cost), status.CanAfford and COLORS.Buy or COLORS.Poor, true)
			-- v4: денег не хватает — рядом кнопка скипа за Robux.
			if not status.CanAfford and status.SkipProductId then
				actionButton.Size = UDim2.new(0.5, -122, 0, 50)
				actionButton.Position = UDim2.new(0.5, 110, 1, -6)
				actionButton2.Visible = true
				actionButton2.Active = true
				paintButton(actionButton2, "Yellow")
				actionText2.Text = ("⚡ SKIP R$%d"):format(status.SkipRobux or 0)
			end
		end
		if pendingBuy then setAction("...", lastActionColor, false) end
	end

	local gridCards = {}
	local function showDetail(kind)
		selectedKind = kind
		playUiClick()
		gridView.Visible = false
		detailView.Visible = true
		detailView.Position = UDim2.fromOffset(40, 0)
		renderDetail()
		TweenService:Create(detailView, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(),
		}):Play()
	end
	local function showGrid(animated)
		selectedKind = nil
		detailView.Visible = false
		gridView.Visible = true
		if animated then
			gridView.Position = UDim2.fromOffset(-40, 0)
			TweenService:Create(gridView, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.new(),
			}):Play()
		else
			gridView.Position = UDim2.new()
		end
	end

	for order, kind in SHOP_ORDER do
		local isMain = kind == MAIN_KIND
		local visual = makeCard(isMain and row or sideGrid,
			isMain and MAIN_CARD_W or SMALL_CARD_W,
			isMain and MAIN_CARD_H or SMALL_CARD_H)
		visual.Card.Name = "Card_" .. kind
		visual.Card.LayoutOrder = order
		if isMain then
			visual.Card.AnchorPoint = Vector2.new(0, 0.5)
			visual.Card.Position = UDim2.new(0, 0, 0.5, 0)
		end
		visual.Card.MouseEnter:Connect(function() TweenService:Create(visual.Scale, TweenInfo.new(0.12), { Scale = 1.06 }):Play() end)
		visual.Card.MouseLeave:Connect(function() TweenService:Create(visual.Scale, TweenInfo.new(0.12), { Scale = 1 }):Play() end)
		visual.Card.Activated:Connect(function()
			if dialogOpen then showDetail(kind) end
		end)
		gridCards[kind] = visual
		applyCard(visual, kind, nil)
	end

	local function renderAll()
		for kind, visual in gridCards do
			applyCard(visual, kind, latestStatuses[kind])
		end
		local mine = latestStatuses.Mine
		if mine and mine.State == "NeedRebirth" then
			gridFooter.Text = ('<font color="#8CD2FF">%s</font>'):format(tr("Cave limit reached — talk to the Prestige Mayor to go deeper!"))
		else
			gridFooter.Text = ('<font color="#FFD75A">%s</font>'):format(tr("The CAVE unlocks new ore. Cart and pickaxe are boosts."))
		end
		subtitle.Text = tr("Everything resets on prestige")
		if detailView.Visible then renderDetail() end
	end

	local function applyStatus(statuses)
		for kind, status in statuses or {} do
			latestStatuses[kind] = status
		end
		renderAll()
	end
	addUpgradeCooldownListener(function()
		if dialogOpen and detailView.Visible then renderDetail() end
	end)

	local toastToken = 0
	local function showToast(text, good)
		toastToken += 1
		local token = toastToken
		toast.Text = text
		toast.TextColor3 = good and Color3.fromRGB(120, 255, 160) or Color3.fromRGB(255, 120, 120)
		toast.TextTransparency = 0
		task.delay(2.2, function()
			if toastToken == token then
				TweenService:Create(toast, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			end
		end)
	end

	local function fitScale()
		local camera = workspace.CurrentCamera
		local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
		panelScale.Scale = math.min(1.15, (viewport.X - 40) / PANEL_SIZE.X, (viewport.Y - 80) / PANEL_SIZE.Y)
	end

	local currentNpc = nil
	local talkingSound = nil
	local npcPosition = nil
	local npcGui, npcName, npcArrow, npcDialog
	local distanceCheckConnection = nil
	local bobConnection = nil
	local pollToken = 0

	local function closeDialog()
		if not dialogOpen then
			return
		end
		dialogOpen = false
		pendingBuy = false
		pollToken += 1
		playUiClick("UiMenuClose")
		local tween = TweenService:Create(panelScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = panelScale.Scale * 0.85 })
		tween:Play()
		task.delay(0.15, function()
			if not dialogOpen then
				panel.Visible = false
				gui.Enabled = false
			end
		end)
		if distanceCheckConnection then
			distanceCheckConnection:Disconnect()
			distanceCheckConnection = nil
		end
		if bobConnection then
			bobConnection:Disconnect()
			bobConnection = nil
		end
		if npcGui then
			if npcName then npcName.Visible = true end
			if npcArrow then npcArrow.Visible = true end
			if npcDialog then npcDialog.Visible = false end
		end
		if currentNpc then
			currentNpc:SetAttribute("Talking", false)
			currentNpc = nil
		end
		stopTalkingSound(talkingSound)
		talkingSound = nil
		shopRemoteEvent:FireServer("Close")
		TweenService:Create(workspace.CurrentCamera, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { FieldOfView = 70 }):Play()
	end
	registerDialogCloser(closeDialog)

	local function openDialog(npc)
		local npcRoot = npc and npc.PrimaryPart
		npcGui = npc and npc:FindFirstChild("gui", true)
		npcName = npcGui and npcGui:FindFirstChild("name", true)
		npcArrow = npcGui and npcGui:FindFirstChild("arrow", true)
		npcDialog = npcGui and npcGui:FindFirstChild("dialog", true)
		npcPosition = npcRoot and npcRoot.Position or nil

		currentNpc = npc
		if npc then npc:SetAttribute("Talking", true) end
		talkingSound = startTalkingSound()
		dialogOpen = true
		if npcDialog then npcDialog.Visible = true end
		if npcName then npcName.Visible = false end
		if npcArrow then npcArrow.Visible = false end
		if npcName or npcDialog then
			currentScaledLabels = { npcName, npcArrow, npcDialog }
			refreshResolutionScale()
		end

		showGrid(false)
		if gearRemote then gearRemote:FireServer("GetState") end
		renderAll()
		fitScale()
		local target = panelScale.Scale
		panelScale.Scale = target * 0.85
		panel.Visible = true
		gui.Enabled = true
		playUiClick("UiMenuOpen")
		TweenService:Create(panelScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
		TweenService:Create(workspace.CurrentCamera, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { FieldOfView = 65 }):Play()
		if npcDialog then
			task.spawn(function()
				typeText(npcDialog, tr("Welcome! What would you like to upgrade?"), Config.UpgradeShop.TypewriterCharDelay)
			end)
		end

		-- Пока окно открыто — раз в 2 сек освежаем статусы (деньги меняются).
		pollToken += 1
		local myToken = pollToken
		task.spawn(function()
			while dialogOpen and pollToken == myToken do
				task.wait(2)
				if dialogOpen and pollToken == myToken then
					shopRemoteEvent:FireServer("Open")
				end
			end
		end)

		if distanceCheckConnection then distanceCheckConnection:Disconnect() end
		distanceCheckConnection = RunService.Heartbeat:Connect(function()
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if not hrp then
				closeDialog()
				return
			end
			if npcPosition and (hrp.Position - npcPosition).Magnitude > Config.UpgradeShop.DialogRange then
				closeDialog()
			end
		end)
		if bobConnection then bobConnection:Disconnect() end
		local frameCount = 0
		bobConnection = RunService.Heartbeat:Connect(function()
			frameCount += 1
			if not (dialogOpen and npcGui) then return end
			if npcDialog and npcDialog.Visible then
				npcGui.StudsOffset = Vector3.new(0, math.sin(frameCount / 8) / 5 + 1.55, 0)
			else
				npcGui.StudsOffset = Vector3.new(0, math.sin(frameCount / 25) / 6 + 1.55, 0)
			end
		end)
	end

	backButton.Activated:Connect(function()
		playUiClick("UiCancel")
		showGrid(true)
	end)
	closeButton.Activated:Connect(closeDialog)
	actionButton2.Activated:Connect(function()
		if dialogOpen and SUPPLY_KEY[selectedKind] and actionButton2.Active and gearRemote then
			playUiClick()
			gearRemote:FireServer("BuyDynamite", 5, selectedSupply)
			return
		end
		-- v4: скип прокачки за Robux (Config.DevProducts.UpgradeSkip).
		local status = dialogOpen and selectedKind and latestStatuses[selectedKind]
		if status and status.SkipProductId and actionButton2.Active then
			playUiClick()
			pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, status.SkipProductId)
		end
	end)
	if gearRemote then
		gearRemote.OnClientEvent:Connect(function(command, payload)
			if type(payload) ~= "table" then return end
			if command == "BuyResult" then
				if payload.Ok then
					showToast(tr("Bought!"), true)
				elseif payload.Reason then
					showToast(tr(payload.Reason), false)
				end
				return
			end
			if payload.Gear then
				for _, dynamiteKey in Config.Dynamite.Order do
					local gearState = gearStates[dynamiteKey]
					gearState.Count = math.floor(tonumber(payload.Gear[dynamiteKey]) or 0)
					gearState.Price = tonumber(payload.DynamitePrices and payload.DynamitePrices[dynamiteKey]) or gearState.Price
				end
				if dialogOpen then renderAll() end
			end
		end)
	end
	actionButton.Activated:Connect(function()
		if dialogOpen and SUPPLY_KEY[selectedKind] then
			if actionButton.Active and gearRemote then
				playUiClick()
				gearRemote:FireServer("BuyDynamite", 1, selectedSupply)
			else
				playUiClick("UiError")
			end
			return
		end
		if not (dialogOpen and selectedKind) or not actionButton.Active or pendingBuy then
			playUiClick("UiError")
			return
		end
		if requestUpgradePurchase(shopRemoteEvent, selectedKind) then
			pendingBuy = true
			renderDetail()
			task.delay(3, function()
				if pendingBuy then
					pendingBuy = false
					if dialogOpen then renderDetail() end
				end
			end)
		end
	end)

	local numberKeys = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }
	UserInputService.InputBegan:Connect(function(input, processed)
		if not dialogOpen then return end
		if input.KeyCode == Enum.KeyCode.Escape then
			closeDialog()
			return
		end
		if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		if input.KeyCode == Enum.KeyCode.Backspace and detailView.Visible then
			showGrid(true)
			return
		end
		local index = table.find(numberKeys, input.KeyCode)
		if index and SHOP_ORDER[index] then
			showDetail(SHOP_ORDER[index])
		end
	end)
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		if dialogOpen then fitScale() end
	end)

	shopRemoteEvent.OnClientEvent:Connect(function(action, a, b, c)
		if action == "Open" then
			openDialog(a)
		elseif action == "Status" then
			applyStatus(a)
		elseif action == "BuyResult" then
			local kind, ok, reason = a, b, c
			pendingBuy = false
			if ok then
				playUpgradeRevealCamera(kind, closeDialog)
			else
				cancelPendingUpgradeReveal(kind)
				if reason then showToast(tr(reason), false) end
				if dialogOpen then renderDetail() end
			end
		end
	end)
end)()

;(function()
	local shopRemoteEvent = ReplicatedStorage.Shared:WaitForChild("UpgradeShopRequest")

-- Старый строковый список удалён, оставлен только пустой compatibility scope
-- для сохранения структуры большого LocalScript.
	if false then
	local responsesGui = playerGui:WaitForChild("DialogResponses", 5)
	local responsesFrame = responsesGui and responsesGui:FindFirstChild("Responses", true)
	local responseTemplate = responsesFrame and responsesFrame:FindFirstChild("Template", true)
	local responsesValid = responseTemplate and responseTemplate:FindFirstChild("Text", true)
	if not responsesValid then
		warn("[CustomCartUI] StarterGui/DialogResponses не найден или неполон (нужны Responses/Template/Text) — запусти tools/BuildAllUI.lua. Диалог с продавцом прокачки не будет работать.")
		return
	end
	responsesGui.ResetOnSpawn = false
	responsesGui.DisplayOrder = 15

	responsesFrame.Visible = false -- скрыт целиком, пока диалог не открыт (см. openDialog/closeDialog)
	local template = responseTemplate
	template.Visible = false

	-- Три постоянных пункта (не растущий список 1..9, как в референсе, —
	-- у нас всегда ровно три ветки) — клонируем шаблон один раз на каждую
	-- и дальше просто переиспользуем/обновляем текст.
	local optionButtons = {}
	local optionTexts = {}
	for i, kind in KIND_ORDER do
		local option = template:Clone()
		option.Name = kind .. "Option"
		option.LayoutOrder = i
		option.Visible = false
		option.Parent = responsesFrame
		optionButtons[kind] = option
		optionTexts[kind] = option:FindFirstChild("Text", true)

		-- ФИКС "ТЕГИ ПОКАЗЫВАЮТСЯ КАК ТЕКСТ, А НЕ ЦВЕТОМ": не полагаемся
		-- на то, что живой ассет в StarterGui уже пересобран через
		-- обновлённый tools/BuildAllUI.lua (RichText мог остаться
		-- false на старом инстансе, собранном до этого фикса) — выставляем
		-- явно здесь же, в коде, при каждом клонировании. Работает
		-- одинаково и со старым, и с новым ассетом, перезапускать билдер
		-- ради одного этого не обязательно.
		if optionTexts[kind] then
			optionTexts[kind].RichText = true
		end

		-- Иконка слева — из Config.UpgradeShop.Icons по имени ветки. 0/nil —
		-- просто оставляем пустое место (билдер ещё не подставил свою
		-- картинку), без ошибок и предупреждений.
		local icon = option:FindFirstChild("Icon", true)
		local iconId = Config.UpgradeShop.Icons and Config.UpgradeShop.Icons[kind]
		if icon and iconId and iconId ~= 0 then
			icon.Image = "rbxassetid://" .. iconId
		end
	end

	-- Цена сокращена до K/M/B/T через NumberFormat.abbreviate и выделена
	-- жёлтым прямо внутри строки через RichText.
	local function highlightCost(cost)
		return ("<font color=\"#FFD75A\">$%s</font>"):format(NumberFormat.abbreviate(cost))
	end

	local function rowTextAndColor(status)
		local label = tr(KIND_LABELS[status.Kind])
		local num = table.find(KIND_ORDER, status.Kind)
		if status.State == "Maxed" then
			return tr("upgrade.max", { number = num, branch = label, tier = status.Tier }), Color3.fromRGB(255, 215, 90)
		elseif status.State == "NeedRebirth" then
			return tr("upgrade.needRebirth", { number = num, branch = label, tier = status.Cap }), Color3.fromRGB(140, 210, 255)
		elseif status.State == "Buyable" then
			if status.Repair then
				return ("%d. %s — <font color=\"#FFC846\">REPAIR</font> %s"):format(num or 1, label, highlightCost(status.Cost)), Color3.new(1, 1, 1)
			end
			if status.Unlock then
				-- v12: бесплатная первая тележка в списковом варианте диалога.
				return ("%d. %s — <font color=\"#9CFFB4\">FREE</font>"):format(num or 2, label), Color3.new(1, 1, 1)
			end
			if status.Blocked then
				return tr("upgrade.blocked", { number = num, branch = label, tier = status.NextTier, cost = highlightCost(status.Cost) }),
					Color3.fromRGB(180, 180, 190)
			end
			return tr("upgrade.buy", { number = num, branch = label, tier = status.NextTier, cost = highlightCost(status.Cost) }), Color3.new(1, 1, 1)
		end
		return tr("upgrade.wait", { number = num, branch = label }), Color3.fromRGB(180, 180, 190)
	end

	-- См. одноимённый блок в версии с карточками выше — та же задача:
	-- помнить последние статусы, чтобы обратный отсчёт мог перерисовать
	-- строки сам, без обращения к серверу.
	local latestStatuses = {}

	local function refreshOptionRows()
		local cooldown = upgradeCooldownRemaining()
		for kind, text in optionTexts do
			local status = latestStatuses[kind]
			if status then
				local newText, color = rowTextAndColor(status)
				if cooldown > 0 then
					-- Строку не заменяем целиком, а ДОПИСЫВАЕМ ожидание:
					-- в старом списке в строке лежит и номер пункта, и
					-- название ветки, и цена — потерять их на пять секунд
					-- было бы хуже, чем просто пригасить строку.
					newText = newText .. (" <font color=\"#FF9A5A\">(%s)</font>"):format(
						tr("WAIT {seconds}s", { seconds = cooldown })
					)
					color = Color3.fromRGB(150, 150, 160)
				end
				text.Text = newText
				text.TextColor3 = color
			end
		end
	end

	local function applyStatus(statuses)
		for kind in optionTexts do
			if statuses[kind] then latestStatuses[kind] = statuses[kind] end
		end
		refreshOptionRows()
	end

	addUpgradeCooldownListener(refreshOptionRows)

	local function showBuyWarning(kind, reason)
		local text = optionTexts[kind]
		if not text then
			return
		end
		local before = text.Text
		local beforeColor = text.TextColor3
		local flashed = before .. "  (" .. tr(reason) .. ")"
		text.Text = flashed
		text.TextColor3 = Color3.fromRGB(255, 110, 110)
		task.delay(1.6, function()
			if text.Text == flashed then -- никто не успел обновить поверх (например, новый Status)
				text.Text = before
				text.TextColor3 = beforeColor
			end
		end)
	end

	local dialogOpen = false
	local currentNpc = nil -- см. openDialog/closeDialog — атрибут "Talking" на этой модели, для синхронизации анимаций (см. Union-скрипт в самой модели NPC)
	local talkingSound = nil -- см. startTalkingSound/stopTalkingSound — один зацикленный звук на весь диалог
	local npcPosition = nil
	local npcGui, npcName, npcArrow, npcDialog
	local distanceCheckConnection = nil
	local bobConnection = nil

	local function hideOptions()
		for _, option in optionButtons do
			option.Visible = false
		end
	end

	-- Раньше карточки появлялись по одной, печатая текст посимвольно — по
	-- просьбе теперь появляются сразу все и сразу с полным текстом.
	local revealToken = 0
	local function revealOptions()
		revealToken += 1
		local myToken = revealToken
		for _, kind in KIND_ORDER do
			if revealToken ~= myToken or not dialogOpen then
				return -- диалог закрыли или переоткрыли — не наша очередь
			end
			local option = optionButtons[kind]
			local text = optionTexts[kind]
			if option and text then
				option.Visible = true
				text.Text = tr(text.Text)
			end
		end
	end

	local function closeDialog()
		if not dialogOpen then
			return
		end
		dialogOpen = false
		revealToken += 1 -- отменяет незавершённый revealOptions, если диалог закрыли посреди печати
		hideOptions()
		responsesFrame.Visible = false -- прячет и сам крестик — раньше висел вечно, т.к. это сосед пунктов, а не один из них
		if distanceCheckConnection then
			distanceCheckConnection:Disconnect()
			distanceCheckConnection = nil
		end
		if bobConnection then
			bobConnection:Disconnect()
			bobConnection = nil
		end
		if npcGui then
			npcName.Visible = true
			if npcArrow then
				npcArrow.Visible = true
			end
			npcDialog.Visible = false
		end
		if currentNpc then
			currentNpc:SetAttribute("Talking", false) -- см. Union-скрипт в модели NPC — переключает анимацию обратно на "простой"
			currentNpc = nil
		end
		stopTalkingSound(talkingSound)
		talkingSound = nil
		shopRemoteEvent:FireServer("Close") -- сообщает серверу — снова включить ProximityPrompt (см. UpgradeService.lua, выключает его на время разговора)
		TweenService:Create(workspace.CurrentCamera, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { FieldOfView = 70 }):Play()
	end

	registerDialogCloser(closeDialog) -- см. closeAllDialogs: диалог обязан закрыться при смерти игрока
	local function openDialog(npc)
		local npcRoot = npc.PrimaryPart
		npcGui = npc:FindFirstChild("gui", true)
		if not (npcRoot and npcGui) then
			warn("[CustomCartUI] У UpgradeShopNPC нет PrimaryPart и/или BillboardGui \"gui\" где-нибудь внутри модели — не могу показать диалог")
			shopRemoteEvent:FireServer("Close") -- диалог не открылся — не оставляем промпт NPC выключенным навсегда (см. Triggered в UpgradeService.lua)
			return
		end
		npcName = npcGui:FindFirstChild("name", true)
		npcArrow = npcGui:FindFirstChild("arrow", true)
		npcDialog = npcGui:FindFirstChild("dialog", true)
		npcPosition = npcRoot.Position

		currentNpc = npc
		npc:SetAttribute("Talking", true) -- см. Union-скрипт в модели NPC — переключает анимацию на "активную", пока идёт разговор
		talkingSound = startTalkingSound()

		dialogOpen = true
		npcDialog.Visible = true
		npcName.Visible = false
		if npcArrow then
			npcArrow.Visible = false
		end
		responsesFrame.Visible = true

		currentScaledLabels = { npcName, npcArrow, npcDialog }
		refreshResolutionScale()

		TweenService:Create(workspace.CurrentCamera, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { FieldOfView = 65 }):Play()

		task.spawn(function()
			typeText(npcDialog, tr("Welcome! What would you like to upgrade?"), Config.UpgradeShop.TypewriterCharDelay)
			if dialogOpen then
				revealOptions()
			end
		end)

		if distanceCheckConnection then
			distanceCheckConnection:Disconnect()
		end
		distanceCheckConnection = RunService.Heartbeat:Connect(function()
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			-- ФИКС "ЗВУК ДИАЛОГА ИГРАЕТ ВЕЧНО ПОСЛЕ СМЕРТИ": раньше здесь
			-- стоял голый `return`. Персонаж умер — HumanoidRootPart исчез —
			-- сторож молча выходил, диалог НИКОГДА не закрывался, и
			-- зацикленный "голос" NPC (он живёт в SoundService и респавн его
			-- не трогает) гудел до конца сессии. Нет персонажа = разговаривать
			-- физически не с кем, поэтому закрываем диалог, а не выходим.
			if not hrp then
				closeDialog()
				return
			end
			if not npcPosition then
				return
			end
			if (hrp.Position - npcPosition).Magnitude > Config.UpgradeShop.DialogRange then
				closeDialog()
			end
		end)

		-- Покачивание name/arrow, пока NPC МОЛЧИТ (тот же приём, что и в
		-- референсе — math.sin по StudsOffset) — И заметно БЫСТРЕЕ/живее,
		-- пока NPC АКТИВНО ГОВОРИТ (dialog виден): меньше делитель — короче
		-- период колебания — быстрее покачивание.
		if bobConnection then
			bobConnection:Disconnect()
		end
		local frameCount = 0
		bobConnection = RunService.Heartbeat:Connect(function()
			frameCount += 1
			if not (dialogOpen and npcGui) then
				return
			end
			if npcDialog.Visible then
				npcGui.StudsOffset = Vector3.new(0, math.sin(frameCount / 8) / 5 + 1.55, 0)
			else
				npcGui.StudsOffset = Vector3.new(0, math.sin(frameCount / 25) / 6 + 1.55, 0)
			end
		end)
	end

	for kind, option in optionButtons do
		connectClick(option, function()
			if not dialogOpen then
				return
			end
			requestUpgradePurchase(shopRemoteEvent, kind)
		end, "DialogueChoice")
	end

	local responsesCloseButton = responsesFrame:FindFirstChild("CloseButton", true)
	connectClick(responsesCloseButton, closeDialog, "DialogueChoice")

	local numberKeys = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three }
	UserInputService.InputBegan:Connect(function(input, processed)
		if not dialogOpen then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			closeDialog() -- закрыть можно и не отходя от NPC
			return
		end
		if processed then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		local index = table.find(numberKeys, input.KeyCode)
		if index and KIND_ORDER[index] then
			requestUpgradePurchase(shopRemoteEvent, KIND_ORDER[index])
		end
	end)

	shopRemoteEvent.OnClientEvent:Connect(function(action, a, b, c)
		if action == "Open" then
			openDialog(a)
		elseif action == "Status" then
			applyStatus(a)
		elseif action == "BuyResult" then
			local kind, ok, reason = a, b, c
			if ok then
				playUpgradeRevealCamera(kind, closeDialog)
			else
				cancelPendingUpgradeReveal(kind) -- покупка не удалась — вернуть видимость, если watcher уже что-то спрятал
				if reason then showBuyWarning(kind, reason) end
			end
		end
	end)
	end
end)()

--------------------------------------------------------------------------------
-- Находим готовый UI из StarterGui (Roblox клонирует его в PlayerGui при
-- ПЕРВОЙ загрузке персонажа — она может случиться позже старта этого
-- LocalScript, поэтому ждём без жёсткого таймаута, а не проверяем разово).
--
-- КОНТРАКТ (StarterGui/CartInteractionUi) — обязателен, иначе UI не появится:
--   ScreenGui "CartInteractionUi"
--   ├─ Frame "CartPromptGui"   → в нём TextLabel "Text"
--   │                            (необязательно: Frame "FillOverlay")
--   ├─ Frame "CartDropHintGui" → тот же контракт
--   └─ Frame "TalkPromptGui"   → тот же контракт (свой стиль для NPC-диалогов,
--                                см. ниже — НЕ переиспользует вид "Take Cart")
-- "FillOverlay" — заливка прогресса удержания (растёт по ширине). Если её
-- нет — прогресс просто не будет анимироваться, остальное работает.
--------------------------------------------------------------------------------

local screenGui = require(ReplicatedStorage.Shared.UiRegistry).Get("CartInteractionUi")
if not screenGui then
	warn("[CustomCartUI] CartInteractionUi is missing. Run tools/BuildAllUI.lua.")
	return
end
screenGui.ResetOnSpawn = false -- на случай, если в Studio забыли снять галочку

local promptFrame = screenGui:WaitForChild("CartPromptGui", 5)
local dropHint = screenGui:WaitForChild("CartDropHintGui", 5)
local promptText = promptFrame and promptFrame:FindFirstChild("Text", true)

if not (promptFrame and dropHint and promptText) then
	warn("[CustomCartUI] В CartInteractionUi не хватает CartPromptGui/CartDropHintGui с TextLabel 'Text' — UI не подключён. Проверь имена частей по контракту.")
	return
end

-- Отдельный кастомный промпт для NPC-диалогов (Rebirth/UpgradeShopNPC/
-- ShopNPC — см. соответствующие сервисы, все выставляют Style = Custom +
-- атрибут PromptKind = "Talk"). Необязателен: нет TalkPromptGui в сборке —
-- предупреждаем и просто используем тот же promptFrame, что и для тележки
-- (не идеально красиво, но ничего не ломает и не падает).
local talkPromptFrame = screenGui:FindFirstChild("TalkPromptGui", true)
local talkPromptText = talkPromptFrame and talkPromptFrame:FindFirstChild("Text", true)
if not (talkPromptFrame and talkPromptText) then
	warn("[CustomCartUI] В CartInteractionUi нет TalkPromptGui с TextLabel 'Text' — запусти tools/BuildAllUI.lua. Диалог с NPC пока будет использовать вид подсказки \"Take Cart\".")
	talkPromptFrame = promptFrame
	talkPromptText = promptText
end

-- FillOverlay необязателен: если его нет, прогресс удержания просто не
-- анимируется (dummy-заглушка, чтобы не плодить проверки на nil ниже).
local fillOverlay = promptFrame:FindFirstChild("FillOverlay", true)
local talkFillOverlay = talkPromptFrame:FindFirstChild("FillOverlay", true)
-- v20: цвет плашки — это цвет её рамки (скин темы), фон остаётся тёмным.
local function promptAccentStroke(frame)
	return frame:FindFirstChild("SkinStroke") or frame:FindFirstChildOfClass("UIStroke")
end
local promptBaseColor = promptAccentStroke(promptFrame) and promptAccentStroke(promptFrame).Color or promptFrame.BackgroundColor3
local talkPromptBaseColor = promptAccentStroke(talkPromptFrame) and promptAccentStroke(talkPromptFrame).Color or talkPromptFrame.BackgroundColor3
local function paintPromptFrame(frame, color)
	local accentStroke = promptAccentStroke(frame)
	if accentStroke and frame:GetAttribute("UiSkin") then
		accentStroke.Color = color
	else
		frame.BackgroundColor3 = color
	end
end
local promptTextLayouts = {
	[promptText] = { Position = promptText.Position, Size = promptText.Size },
	[talkPromptText] = { Position = talkPromptText.Position, Size = talkPromptText.Size },
}
for _, frame in { promptFrame, dropHint, talkPromptFrame } do
	if frame and frame.Size.X.Offset > 0 and frame.Size.Y.Offset > 0 then
		frame:SetAttribute("MobileBaseSize", Vector2.new(frame.Size.X.Offset, frame.Size.Y.Offset))
	end
end

local PROMPT_KEY_IMAGE = "rbxassetid://" .. tostring(Config.UI.PromptKeyImageId)
local function addPromptKeyImage(frame)
	frame.ClipsDescendants = false
	local oldBadge = frame:FindFirstChild("KeyBadge", true)
	if oldBadge and oldBadge:IsA("GuiObject") then
		oldBadge.Visible = false
	end
	local keyImage = frame:FindFirstChild("PromptKeyImage")
	if UserInputService.TouchEnabled then
		if keyImage and keyImage:IsA("GuiObject") then keyImage.Visible = false end
		return
	end
	if not keyImage then
		keyImage = Instance.new("ImageLabel")
		keyImage.Name = "PromptKeyImage"
		keyImage.AnchorPoint = Vector2.new(1, 0.5)
		keyImage.Position = UDim2.new(0, -8, 0.5, 0)
		local size = frame.Size.Y.Offset > 0 and frame.Size.Y.Offset or 46
		keyImage.Size = UDim2.fromOffset(size, size)
		keyImage.BackgroundTransparency = 1
		keyImage.Image = PROMPT_KEY_IMAGE
		keyImage.ScaleType = Enum.ScaleType.Fit
		keyImage.ZIndex = 10
		keyImage.Parent = frame
	end
end

addPromptKeyImage(promptFrame)
addPromptKeyImage(dropHint)
if talkPromptFrame ~= promptFrame then
	addPromptKeyImage(talkPromptFrame)
end

promptFrame.Visible = false
dropHint.Visible = false
if talkPromptFrame ~= promptFrame then
	talkPromptFrame.Visible = false
end

-- Подсказка "HOLD!"/"ЗАЖМИ!" над ЛЮБЫМ промптом, который реально требует
-- удержания (HoldDuration > 0 — тележка, взятие/спавн; жеоды; сейф;
-- подиум выбора руды), а не тапа (магазин/апгрейд/ребёрт/диалоги — у них
-- HoldDuration = 0, подсказка для них не показывается). Тот же стиль, что и
-- "CLICK!" у жеоды (см. GeodeUI.client.lua:ClickHint). Изначально это было
-- только для гайда над тележкой — расширено на все такие кнопки в игре,
-- потому что на телефоне не всегда очевидно, что кнопку нужно ИМЕННО
-- удерживать, а не один раз тапнуть.
local holdHint = promptFrame:FindFirstChild("HoldHint")
if not holdHint then
	holdHint = Instance.new("TextLabel")
	holdHint.Name = "HoldHint"
	holdHint.AnchorPoint = Vector2.new(0.5, 1)
	holdHint.Position = UDim2.new(0.5, 0, 0, -6)
	holdHint.Size = UDim2.fromOffset(150, 34)
	holdHint.BackgroundTransparency = 1
	require(game:GetService("ReplicatedStorage").Shared.UiKit).StyleText(holdHint, "Heading") -- v20: шрифт темы
	holdHint.TextSize = 22
	holdHint.TextColor3 = Color3.fromRGB(255, 235, 90)
	holdHint.ZIndex = 25
	holdHint.Parent = promptFrame
end
holdHint.Text = tr("HOLD!")
holdHint.Visible = false

-- Лёгкое непрерывное покачивание (поворот туда-сюда), пока подсказка
-- видна — чтобы взгляд сам цеплялся за неё, а не терялась статичным
-- текстом рядом с промптом.
RunService.RenderStepped:Connect(function()
	if not holdHint.Visible then return end
	holdHint.Rotation = math.sin(os.clock() * 6) * 8
end)

local fillTween = nil

--------------------------------------------------------------------------------
-- 1) Кастомный промпт — реагирует ТОЛЬКО на Style = Custom (тележка и
--    NPC-диалоги — всё остальное в игре обычные ProximityPrompt). Какой
--    именно pill показать — решает атрибут PromptKind на самом промпте:
--    "Talk" → talkPromptFrame (свой стиль у NPC), иначе (нет атрибута,
--    промпт тележки) → обычный promptFrame.
--------------------------------------------------------------------------------

local activePrompt = nil
local activeFrame = nil   -- какой из двух pill'ов сейчас показан (promptFrame или talkPromptFrame)
local activeFill = nil    -- FillOverlay именно активного pill'а (или nil)
local refreshDropHint = nil

local function addPromptTouchTarget(frame)
	local button = frame:FindFirstChild("TouchTarget")
	if not button then
		button = Instance.new("TextButton")
		button.Name = "TouchTarget"
		button.Size = UDim2.fromScale(1, 1)
		button.BackgroundTransparency = 1
		button.Text = ""
		button.ZIndex = 20
		button.Parent = frame
	end
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			if activePrompt then
				activePrompt:InputHoldBegin()
			end
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			if activePrompt then
				activePrompt:InputHoldEnd()
			end
		end
	end)
end
addPromptTouchTarget(promptFrame)
if talkPromptFrame ~= promptFrame then
	addPromptTouchTarget(talkPromptFrame)
end

local function resetFill()
	if fillTween then
		fillTween:Cancel()
		fillTween = nil
	end
	if activeFill then
		activeFill.Size = UDim2.new(0, 0, 1, 0)
	end
end

local function frameFor(prompt)
	if prompt:GetAttribute("PromptKind") == "Talk" then
		return talkPromptFrame, talkPromptText, talkFillOverlay
	end
	return promptFrame, promptText, fillOverlay
end

local function canUsePrompt(prompt)
	local ownerUserId = prompt:GetAttribute("OwnerUserId")
	if not ownerUserId or ownerUserId == player.UserId then
		return true
	end
	return prompt:GetAttribute("Stealable") == true
end

local shownPrompts = {} -- [ProximityPrompt] = последний inputType из PromptShown
local promptAttributeConnections = {}

local function promptWorldPosition(prompt)
	local parent = prompt.Parent
	if parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	elseif parent and parent:IsA("BasePart") then
		return parent.Position
	end
	return Vector3.zero
end

local function refreshActivePrompt()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local bestPrompt, bestInputType, bestPriority, bestDistance = nil, nil, -math.huge, math.huge
	for prompt, inputType in shownPrompts do
		if not prompt.Parent or not prompt.Enabled or not canUsePrompt(prompt) then
			continue
		end
		local priority = prompt:GetAttribute("PromptKind") == "Talk" and 2 or 1
		local distance = root and (promptWorldPosition(prompt) - root.Position).Magnitude or 0
		if priority > bestPriority or (priority == bestPriority and distance < bestDistance) then
			bestPrompt = prompt
			bestInputType = inputType
			bestPriority = priority
			bestDistance = distance
		end
	end

	if activePrompt ~= bestPrompt then
		resetFill()
	end
	promptFrame.Visible = false
	promptFrame:SetAttribute("MobileReleaseCrystal", false)
	if talkPromptFrame ~= promptFrame then
		talkPromptFrame.Visible = false
		talkPromptFrame:SetAttribute("MobileReleaseCrystal", false)
	end
	holdHint.Visible = false
	activePrompt = bestPrompt
	activeFrame = nil
	activeFill = nil

	if bestPrompt then
		local frame, text, fill = frameFor(bestPrompt)
		local mobileRelease = UserInputService.TouchEnabled and bestPrompt.Name == "ReleaseCrystalPrompt"
		frame:SetAttribute("MobileReleaseCrystal", mobileRelease)
		local baseTextLayout = promptTextLayouts[text]
		if mobileRelease then
			text.Position = UDim2.new(0, 36, 0.5, 0)
			text.Size = UDim2.new(1, -44, 1, -10)
		elseif baseTextLayout then
			text.Position = baseTextLayout.Position
			text.Size = baseTextLayout.Size
		end
		activeFrame = frame
		activeFill = fill
		local objectText = tr(bestPrompt.ObjectText)
		local actionText = tr(bestPrompt.ActionText)
		if bestPrompt:GetAttribute("PromptColor") == "Blue" then
			paintPromptFrame(frame, Color3.fromRGB(70, 150, 255))
		elseif frame == talkPromptFrame then
			paintPromptFrame(frame, talkPromptBaseColor)
		else
			paintPromptFrame(frame, promptBaseColor)
		end
		if objectText == "" then
			text.Text = actionText
		elseif actionText == "" then
			text.Text = objectText
		else
			text.Text = ("%s\n%s"):format(objectText, actionText)
		end
		local keyLabel = frame:FindFirstChild("KeyLabel", true)
		if keyLabel then
			-- Раньше тут ВСЕГДА было "TAP" на тапе, даже для промптов, которые
			-- реально требуют удержания — прямое противоречие с надписью
			-- "HOLD!" сверху же. Теперь текст на самой кнопке соответствует
			-- жесту, который реально нужен.
			--
			-- MouseClick — отдельный inputType (см. ProximityPrompt.ClickablePrompt
			-- в CartService:SpawnCartFor) для клика ПРЯМО ПО ТЕЛЕЖКЕ мышью —
			-- та же надпись "CLICK"/"HOLD", что и на тапе, а не буква клавиши E.
			local touchLabel = (tonumber(bestPrompt.HoldDuration) or 0) > 0 and "HOLD" or "CLICK"
			-- MouseClick в Enum.ProximityPromptInputType не существует —
			-- обращение к нему роняло скрипт; клик по объекту приходит как
			-- Keyboard, отдельно его не различить.
			local isPointerInput = bestInputType == Enum.ProximityPromptInputType.Touch
			keyLabel.Text = isPointerInput and tr(touchLabel) or bestPrompt.KeyboardKeyCode.Name
		end
		frame.Visible = true
		-- ОСОБЫЙ ВХОД "ПАДАЕТ СВЕРХУ" — только для промпта взятия тележки
		-- (PromptKind="CartGrab"), и только пока игрок НИ РАЗУ не брал
		-- тележку за эту сессию — по прямому запросу. Дальше (после
		-- первого успешного взятия, см. CartService:Attach) промпт
		-- становится полностью обычным, без всякой особой анимации —
		-- ровно "становится в норму, но только когда я возьму саму
		-- тележку".
		if bestPrompt:GetAttribute("PromptKind") == "CartGrab" and player:GetAttribute("HasEverGrabbedCart") ~= true then
			local restPosition = frame.Position
			frame.Position = restPosition - UDim2.fromOffset(0, 90)
			TweenService:Create(frame, TweenInfo.new(0.4, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {
				Position = restPosition,
			}):Play()
		end
		-- Универсально для ЛЮБОГО промпта, где реально нужно держать
		-- (HoldDuration > 0) — раньше это было большинство промптов в игре
		-- (тележка, жеоды, сейф), сейчас таких не осталось: все переведены
		-- на клик по фидбеку "везде, где нужно зажимать, сделай по клику"
		-- (см. ClickablePrompt=true на каждом из них). Ветка оставлена на
		-- случай, если в будущем добавится новый hold-промпт.
		--
		-- CLICK! — для ЛЮБОГО промпта с ClickablePrompt = true (тележка,
		-- спавн тележки, жеоды, сейф — все переведённые с hold на click).
		-- Обычные "чистые" тап-промпты (магазин/апгрейд/ребёрт/диалоги —
		-- они и раньше были HoldDuration = 0, без ClickablePrompt) хинт не
		-- получают — там и так всегда был один клик, подсказка не нужна.
		if (tonumber(bestPrompt.HoldDuration) or 0) > 0 then
			holdHint.Text = tr("HOLD!")
			holdHint.Parent = frame
			holdHint.Visible = true
		elseif bestPrompt.ClickablePrompt then
			holdHint.Text = tr("CLICK!")
			holdHint.Parent = frame
			holdHint.Visible = true
		end
	end
	-- Промпты рисуются на объектах (WorldPrompts.client.lua): выбор
	-- активного промпта здесь остаётся (на него опираются подсказка
	-- "отпустить тележку" и мобильная раскладка), но экранные плашки не
	-- показываются.
	if Config.UI.WorldPrompts ~= false then
		promptFrame.Visible = false
		talkPromptFrame.Visible = false
		holdHint.Visible = false
	end
	if refreshDropHint then
		refreshDropHint()
	else
		refreshMobileInteractionLayout()
	end
end

ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
	if prompt.Style ~= Enum.ProximityPromptStyle.Custom then
		return
	end
	shownPrompts[prompt] = inputType
	if not promptAttributeConnections[prompt] then
		promptAttributeConnections[prompt] = {
			prompt:GetAttributeChangedSignal("OwnerUserId"):Connect(refreshActivePrompt),
			prompt:GetAttributeChangedSignal("Stealable"):Connect(refreshActivePrompt),
		}
	end
	refreshActivePrompt()
end)

ProximityPromptService.PromptHidden:Connect(function(prompt)
	shownPrompts[prompt] = nil
	local connections = promptAttributeConnections[prompt]
	if connections then
		promptAttributeConnections[prompt] = nil
		for _, connection in connections do connection:Disconnect() end
	end
	refreshActivePrompt()
end)

ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
	if prompt ~= activePrompt or not activeFill then
		return
	end
	fillTween = TweenService:Create(
		activeFill,
		TweenInfo.new(math.max(prompt.HoldDuration, 0.05), Enum.EasingStyle.Linear),
		{ Size = UDim2.new(1, 0, 1, 0) }
	)
	fillTween:Play()
end)

ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt)
	if prompt == activePrompt then
		resetFill()
	end
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt == activePrompt then
		resetFill()
	end
end)
--------------------------------------------------------------------------------
-- 2) Подсказка отпускания — следует за атрибутом CarryingCart (реплицируется
--    сервером). Отпускание — МГНОВЕННОЕ по клику/тапу/E, см. dropCartNow
--    ниже (раньше требовалось удерживать Config.Cart.DropHoldDuration
--    секунд с заливкой прогресса).
--------------------------------------------------------------------------------

refreshDropHint = function()
	local carrying = player:GetAttribute("CarryingCart") == true
	-- При промптах на объектах (Config.UI.WorldPrompts) "Отпустить тележку"
	-- рисует WorldPrompts.client.lua прямо на тележке; экранная подсказка
	-- не показывается. Клавиша E/клик ниже работают как раньше.
	dropHint.Visible = carrying and activePrompt == nil and Config.UI.WorldPrompts == false
	refreshMobileInteractionLayout()
	if dropHint.Visible then
		-- Тот же плавающий "CLICK!" хинт, что и над обычными промптами (см.
		-- holdHint выше) — тележка теперь отпускается мгновенным кликом, а
		-- не удержанием, поэтому и подсказка та же, что у клик-действий.
		holdHint.Text = tr("CLICK!")
		holdHint.Parent = dropHint
		holdHint.Visible = true
	elseif not activePrompt then
		holdHint.Visible = false
	end
end

player:GetAttributeChangedSignal("CarryingCart"):Connect(refreshDropHint)
refreshDropHint()

-- Тележка теперь отпускается МГНОВЕННО по клику/тапу/нажатию E — раньше
-- требовалось удерживать Config.Cart.DropHoldDuration (2.5 сек) с
-- заливкой-прогрессом; убрано по фидбеку "везде, где нужно зажимать,
-- сделай по клику, с подсказкой CLICK".
local function dropCartNow()
	if player:GetAttribute("CarryingCart") ~= true then
		return
	end
	if dropRemote then
		dropRemote:FireServer()
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or UserInputService:GetFocusedTextBox() then
		return
	end
	if input.KeyCode == Enum.KeyCode.E then
		dropCartNow()
	end
end)

local dropTouchTarget = Instance.new("TextButton")
dropTouchTarget.Name = "TouchTarget"
dropTouchTarget.Size = UDim2.fromScale(1, 1)
dropTouchTarget.BackgroundTransparency = 1
dropTouchTarget.Text = ""
dropTouchTarget.ZIndex = 20
dropTouchTarget.Parent = dropHint
dropTouchTarget.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		dropCartNow()
	end
end)

--------------------------------------------------------------------------------
-- ХВАТ ЗА ТЕЛЕЖКУ (R6 IK), v14 — переписан с нуля.
--
-- ГЛАВНЫЙ ПРИНЦИП (и главное отличие от прошлых версий): анимация ходьбы/
-- стояния — это НЕ свойство детали руки, а `Motor6D.Transform`, который
-- Animator записывает в плечевой сустав КАЖДЫЙ КАДР, находя суставы по имени
-- внутри дерева персонажа в рантайме. Именно поэтому все прошлые попытки
-- (переименование, клон руки, клон всего персонажа, свой параллельный
-- Motor6D с правкой C0) рано или поздно "протекали": канал Transform в
-- формуле итоговой позы (Part0.CFrame * C0 * Transform * C1⁻¹) оставался
-- под контролем аниматора, а правки C0 в RenderStepped вдобавок опаздывали
-- на кадр относительно анимации торса.
--
-- РЕШЕНИЕ: с ригом не делается ВООБЩЕ ничего — ни клонов, ни скрытий, ни
-- переименований, ни новых суставов. Каждый кадр в `RunService.Stepped`
-- (который срабатывает СРАЗУ ПОСЛЕ того, как Animator записал Transform)
-- мы просто перезаписываем `Transform` штатных Left/Right Shoulder своим
-- прицеливанием на точку хвата. Аниматор пишет свою позу — мы каждый кадр
-- детерминированно пишем поверх. Утечка анимации невозможна по построению:
-- мы владеем тем же самым каналом, что и она, но пишем позже. Одежда,
-- аксессуары, цвета — родные, потому что рука — родная. Ноги/торс/Root
-- анимируются как обычно (их Transform мы не трогаем).
--
-- ВИДНО ВСЕМ: Transform не реплицируется, поэтому этот же код выполняется
-- на КАЖДОМ клиенте для КАЖДОГО держателя (не только для себя): клиент
-- находит все тележки с атрибутом `HolderUserId` (реплицируется сервером,
-- CartService:Attach) и ведёт IK для их держателей локально. Анимации
-- чужих персонажей тоже проигрываются локально на каждом клиенте, так что
-- перезапись в Stepped работает для них точно так же, как для своего.
--
-- РАСТЯЖЕНИЕ: "резиновое", без верхнего предела — Size руки по Y каждый
-- кадр подгоняется так, чтобы кончик руки математически точно совпадал с
-- точкой хвата, а плечевой конец оставался в плече (компенсация сдвига
-- центра детали зашита прямо в Transform, C0/C1 НЕ трогаются вовсе —
-- восстанавливать при отпускании нужно только Size, а Transform аниматор
-- сам перепишет уже в следующем кадре).
--
-- ТОЧКИ ХВАТА: маркеры LeftHandGrip/RightHandGrip в модели тележки — высший
-- приоритет. Если их нет — рандомный фолбэк на ближней к игроку стороне,
-- НО теперь детерминированный: Random сидируется атрибутом `GripSeed`
-- (ставит сервер при захвате) — все клиенты независимо приходят к ОДНИМ
-- И ТЕМ ЖЕ точкам, иначе каждый видел бы руки в разных местах. "Левая"
-- половина тоже считается детерминированно из геометрии (держатель стоит
-- лицом к ближней грани, его левая сторона = локальный Z тележки со знаком
-- facingSign), а не из мгновенного RightVector торса, который на разных
-- клиентах в момент настройки мог отличаться.
--------------------------------------------------------------------------------

local ARM_SHOULDER_WIDEN_STUDS = 0.65 -- вынос точки крепления от центра торса по X — рука растёт ИЗ плеча, а не из середины тела
local ARM_MIN_SIZE_Y = 0.2 -- защита от нулевого/отрицательного Size, реально почти не достигается
local RIG_SETUP_TIMEOUT = 3 -- сколько секунд ждать репликацию персонажа/тележки, прежде чем сдаться (реконсиляция ниже всё равно попробует снова)
local RECONCILE_INTERVAL = 1 -- раз в секунду сверяем "какие тележки держатся" с "какие риги активны" — ловит стриминг/позднюю репликацию/пропущенные сигналы
-- v17: плавный переход рук к тележке и обратно (смешивание с позой аниматора).
-- Одна таблица вместо нескольких локальных: в этом файле упёрлись в лимит
-- 200 локальных переменных верхнего уровня.
local GripBlend = {
	In = (Config.Animations and Config.Animations.PoseBlendIn) or 0.22,
	Out = (Config.Animations and Config.Animations.PoseBlendOut) or 0.25,
	Releasing = {}, -- [Player] = руки, плавно возвращающиеся после отпускания
	Smooth = function(x)
		x = math.clamp(x, 0, 1)
		return x * x * (3 - 2 * x)
	end,
}

-- Ортонормальный базис, у которого -Y (направление, куда R6-рука "висит"
-- по умолчанию) смотрит вдоль worldDirection. Тот же приём, что и раньше,
-- только теперь в МИРОВОМ пространстве — дальше желаемый CFrame руки
-- целиком переводится в Transform одной строкой.
local function aimBasis(worldDirection)
	local yAxis = -worldDirection.Unit
	local reference = math.abs(yAxis:Dot(Vector3.yAxis)) > 0.99 and Vector3.zAxis or Vector3.yAxis
	local xAxis = reference:Cross(yAxis)
	if xAxis.Magnitude < 1e-5 then
		xAxis = Vector3.xAxis
	end
	xAxis = xAxis.Unit
	local zAxis = xAxis:Cross(yAxis).Unit
	return xAxis, yAxis, zAxis
end

-- Рандомный фолбэк точек хвата (когда в модели нет маркеров) — ближняя к
-- держателю сторона, каждая рука строго в своей половине по Z. ЛОКАЛЬНЫЕ
-- (относительно Root) смещения. Детерминирован: один и тот же seed даёт
-- одни и те же точки на всех клиентах.
-- ФОЛБЭК №2 (последняя линия обороны, если даже луч промахнулся — см. ниже):
-- рандомная, но детерминированная точка на ближней к игроку стороне
-- бампер-бокса тележки. Хуже луча тем, что не смотрит на РЕАЛЬНУЮ форму —
-- просто гадает по габаритам Root, поэтому может повиснуть в воздухе у
-- дырчатой/неправильной формы модели.
local function randomFallbackGripOffsets(cartRoot, cartModel, seed)
	local size = cartRoot.Size
	local facingSign = -1 -- дефолт без FacingPoint: локальный -X смотрит на держателя (та же конвенция, что в CartService)
	local facingPoint = cartModel:FindFirstChild("FacingPoint", true)
	if facingPoint and facingPoint:IsA("BasePart") then
		local frontOffset = cartRoot.CFrame:PointToObjectSpace(facingPoint.Position)
		facingSign = frontOffset.X >= 0 and 1 or -1
	end

	local nearX = facingSign * (size.X / 2 + 0.3) -- чуть НАРУЖУ от поверхности, не внутрь геометрии

	-- Держатель стоит у ближней грани лицом к тележке (смотрит вдоль
	-- -facingSign*X). Его правая = Look×Up = -facingSign*localZ, значит
	-- ЛЕВАЯ половина — это z-знак, равный facingSign. Чистая геометрия,
	-- одинаковая на всех клиентах — в отличие от живого RightVector торса.
	local leftZSign = facingSign

	local halfZ = size.Z / 2
	local halfY = size.Y / 2
	local rng = Random.new(seed)

	local function pointOnHalf(zSign)
		-- 20%..80% своей половины по Z — не впритык к центральному шву и не в упор к краю.
		local z = zSign * (halfZ * (0.2 + rng:NextNumber() * 0.6))
		-- Примерно "ручная" высота — заметно выше нижнего края, но не у самого верха.
		local y = -halfY * 0.2 + rng:NextNumber() * (halfY * 0.9)
		return Vector3.new(nearX, y, z)
	end

	-- Порядок вызовов фиксирован (левая, потом правая) — иначе seed сидировал
	-- бы одинаково, а последовательность выборок разошлась бы.
	local leftOffset = pointOnHalf(leftZSign)
	local rightOffset = pointOnHalf(-leftZSign)
	return leftOffset, rightOffset
end

-- ГЛАВНЫЙ СПОСОБ (без всяких LeftHandGrip/RightHandGrip): в буквальном
-- смысле "проводим линию от руки" — луч от РЕАЛЬНОГО положения плеча
-- игрока (то самое AnchorLocal из buildArmState, переведённое в мировые
-- координаты) в сторону центра тележки, и берём ТОЧКУ, где луч реально
-- задевает её геометрию. Работает для любой формы модели (не только
-- прямоугольного бампер-бокса, как старый рандомный фолбэк ниже) — луч не
-- гадает по габаритам, а бьёт по настоящим частям тележки.
--
-- Никакой отдельной коррекции "какая сторона левая/правая" тут не нужно
-- (в отличие от маркеров/рандома ниже): луч ФИЗИЧЕСКИ стартует из плеча
-- нужной руки (левое плечо у персонажа всегда анатомически слева, это не
-- зависит от поворота/расположения тележки), так что где бы луч ни воткнулся
-- в тележку — это по определению правильная сторона именно для этой руки.
--
-- FilterType.Include + FilterDescendantsInstances = только сама тележка:
-- луч не может случайно зацепить тело игрока, других игроков или рельеф —
-- считается только реальная геометрия ЭТОЙ модели. Маркеры-ориентиры
-- (AttachPoint/FacingPoint/Bottom/LeftHandGrip/RightHandGrip) сервер уже
-- делает CanQuery = false при постройке тележки (см. CartService) — они
-- лучу в принципе не видны, попасть в них невозможно.
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
local function raycastGripOffset(shoulderWorld, cartRoot, cartModel)
	local toCenter = cartRoot.Position - shoulderWorld
	local distance = toCenter.Magnitude
	if distance < 0.05 then
		return nil
	end
	rayParams.FilterDescendantsInstances = { cartModel }
	-- +4 студа перелёта за центр — чтобы луч гарантированно прошёл НАСКВОЗЬ
	-- ближней грани, даже если геометрический центр реальной формы не
	-- совпадает с Root (несимметричные кастомные модели).
	local result = workspace:Raycast(shoulderWorld, toCenter.Unit * (distance + 4), rayParams)
	if not result then
		return nil
	end
	return cartRoot.CFrame:PointToObjectSpace(result.Position)
end

-- Реальные маркеры — высший приоритет, если билдер расставил их вручную
-- (мировая позиция переводится в ЛОКАЛЬНУЮ относительно Root — дальше
-- единообразно с остальными способами). Нет ОБОИХ сразу — считаем, что
-- маркеров нет вообще (либо оба, либо ни одного), и решение принимает
-- raycastGripOffset выше.
local function resolveMarkerGripOffsets(cartModel, cartRoot)
	local leftGrip = cartModel:FindFirstChild("LeftHandGrip", true)
	local rightGrip = cartModel:FindFirstChild("RightHandGrip", true)
	local function worldPosition(marker)
		if marker:IsA("Attachment") then
			return marker.WorldPosition
		elseif marker:IsA("BasePart") then
			return marker.Position
		end
		return nil
	end
	if leftGrip and rightGrip then
		local leftWorld = worldPosition(leftGrip)
		local rightWorld = worldPosition(rightGrip)
		if leftWorld and rightWorld and (leftWorld - rightWorld).Magnitude >= 0.1 then
			return cartRoot.CFrame:PointToObjectSpace(leftWorld),
				cartRoot.CFrame:PointToObjectSpace(rightWorld)
		end
		warn(("[CustomCartUI] %s: LeftHandGrip и RightHandGrip находятся в одной точке или имеют неверный тип"):format(cartModel.Name))
	end
	return nil
end

-- ГЕОМЕТРИЧЕСКАЯ КОРРЕКЦИЯ СТОРОНЫ. Названия маркеров ("LeftHandGrip"/
-- "RightHandGrip") сами по себе НЕ гарантия — тележка крепится на игроке
-- через FollowOffset+HolderSideRotation (см. Config.Cart), которые в сумме
-- заворачивают её ощутимо (по умолчанию тележка висит СЗАДИ игрока, ещё и
-- довёрнута на 90°) — итоговая мировая сторона точки, названной "Left...",
-- легко может оказаться физически справа от игрока и наоборот (отсюда
-- баг "руки крест-накрест"). Вместо того чтобы вычислять/угадывать нужный
-- угол аналитически (хрупко — любая правка Config.Cart/HolderSideRotation
-- или собственный FacingPoint в чужом ассете снова всё перепутает) —
-- определяем сторону КАЖДЫЙ РАЗ ПРИ ЗАХВАТЕ по факту: сравниваем, какая из
-- двух точек хвата реально лежит дальше вдоль настоящего RightVector
-- торса — та и есть правая, вторая — левая. Работает одинаково для
-- маркеров И для рандомного фолбэка, не зависит от имён/углов/будущих
-- переделок Config. Считается ОДИН РАЗ при настройке рига (не каждый
-- кадр) — иначе при резком развороте игрока руки на лету поменялись бы
-- местами, что смотрелось бы хуже, чем сам баг.
local function assignGripSides(torso, cartRoot, offsetA, offsetB)
	local torsoPosition = torso.Position
	local rightVector = torso.CFrame.RightVector
	local worldA = cartRoot.CFrame:PointToWorldSpace(offsetA)
	local worldB = cartRoot.CFrame:PointToWorldSpace(offsetB)
	local dotA = rightVector:Dot((worldA - torsoPosition).Unit)
	local dotB = rightVector:Dot((worldB - torsoPosition).Unit)
	if dotA > dotB then
		-- A лежит дальше вправо от торса — значит A это цель для ПРАВОЙ руки.
		return offsetB, offsetA -- leftOffset, rightOffset
	end
	return offsetA, offsetB
end

-- Активные риги: [Player] = состояние. На каждом клиенте — по ригу на
-- КАЖДОГО держателя тележки в мире, включая самого локального игрока
-- (никакого спец-случая для себя — один и тот же путь для всех).
local armRigs = {}
local rigSetupInFlight = {} -- [Player] = true, пока асинхронная настройка ждёт репликацию — чтобы не запускать вторую параллельно

local function restoreArm(armState)
	-- Возвращаем только Size — Transform аниматор сам перепишет следующим
	-- кадром, C0/C1 мы не трогали вовсе. pcall — на случай, если персонаж
	-- уже уничтожен респауном: восстанавливать нечего и не для кого.
	pcall(function()
		armState.Arm.Size = armState.RestSize
		armState.Motor.Transform = CFrame.identity
	end)
end

local function stopRig(plr, fadeArms)
	local rig = armRigs[plr]
	if not rig then
		return
	end
	armRigs[plr] = nil
	-- v17: при обычном отпускании руки возвращаются плавно (см. Stepped).
	if fadeArms and rig.Torso.Parent and rig.LastLeft and rig.LastRight and plr.Character == rig.Character then
		local torsoCFrame = rig.Torso.CFrame
		GripBlend.Releasing[plr] = {
			Left = rig.Left, Right = rig.Right, Torso = rig.Torso, Character = rig.Character,
			LeftLocal = torsoCFrame:PointToObjectSpace(rig.LastLeft),
			RightLocal = torsoCFrame:PointToObjectSpace(rig.LastRight),
			Weight = rig.Blend or 1,
		}
		return
	end
	restoreArm(rig.Left)
	restoreArm(rig.Right)
end

-- Собирает состояние одной руки. Ничего не создаёт и не прячет — только
-- запоминает ссылки и исходный Size.
local function buildArmState(character, torso, side)
	local motor = torso:FindFirstChild(side .. " Shoulder")
	local arm = character:FindFirstChild(side .. " Arm")
	if not (motor and motor:IsA("Motor6D") and arm and arm:IsA("BasePart")) then
		return nil
	end
	local c0Position = motor.C0.Position
	-- Точка "плеча" в локальных координатах торса: штатный C0, вынесенный
	-- чуть дальше от центра по X (знак сохраняем — левая влево, правая вправо).
	local anchorLocal = Vector3.new(
		c0Position.X + (c0Position.X >= 0 and 1 or -1) * ARM_SHOULDER_WIDEN_STUDS,
		c0Position.Y,
		c0Position.Z
	)
	return {
		Motor = motor,
		Arm = arm,
		RestSize = arm.Size,
		AnchorLocal = anchorLocal,
	}
end

-- Один кадр IK одной руки: желаемый МИРОВОЙ CFrame руки строится напрямую
-- (верхний торец точно в плече, кончик точно в точке хвата), а затем
-- переводится в Transform: из Part1 = Part0 * C0 * Transform * C1⁻¹ следует
-- Transform = C0⁻¹ * Part0.CFrame⁻¹ * desiredPart1 * C1. Аниматор записал
-- свой Transform мгновение назад (перед Stepped) — наша запись побеждает.
local function updateArm(armState, torsoCFrame, targetWorldPosition, weight)
	weight = GripBlend.Smooth(weight or 1)
	local shoulderWorld = torsoCFrame:PointToWorldSpace(armState.AnchorLocal)
	local direction = targetWorldPosition - shoulderWorld
	local distance = direction.Magnitude
	if distance < 0.05 then
		return -- цель практически в точке плеча — разворачивать нечего
	end

	-- Резиновое растяжение: длина руки РОВНО до цели, без верхнего предела.
	-- Цель ближе минимума — рука укорачивается до пола ARM_MIN_SIZE_Y, а
	-- кончик кладётся на цель всё равно (десятые доли студа, не заметно).
	local sizeY = math.max(distance, ARM_MIN_SIZE_Y)
	local restSize = armState.RestSize
	local arm = armState.Arm
	-- v17: во время перехода длина руки тоже плавно тянется от родной.
	local shownSizeY = restSize.Y + (sizeY - restSize.Y) * weight
	if math.abs(arm.Size.Y - shownSizeY) > 1e-3 or arm.Size.X ~= restSize.X or arm.Size.Z ~= restSize.Z then
		arm.Size = Vector3.new(restSize.X, shownSizeY, restSize.Z)
	end

	-- Базис: -Y руки вдоль направления на цель; центр — на полпути от плеча
	-- к цели. Верхний торец (центр + sizeY/2 * (+Y)) оказывается точно в
	-- плече, нижний (кончик) — точно в цели. Никаких C1-компенсаций — вся
	-- геометрия задана напрямую.
	local dirUnit = direction / distance
	local xAxis, yAxis, zAxis = aimBasis(direction)
	local desiredArmCFrame = CFrame.fromMatrix(shoulderWorld + dirUnit * (sizeY / 2), xAxis, yAxis, zAxis)

	local motor = armState.Motor
	local target = motor.C0:Inverse() * torsoCFrame:Inverse() * desiredArmCFrame * motor.C1
	motor.Transform = weight >= 1 and target or motor.Transform:Lerp(target, weight)
end

-- Асинхронный запуск рига для держателя: недолго ждём репликацию персонажа
-- (Torso/руки/плечи) и PrimaryPart тележки — но не вечно. Не R6 (нет Torso/
-- Shoulder) — тихо не включаем, остальная игра не страдает.
local function startRig(plr, cartModel)
	if armRigs[plr] or rigSetupInFlight[plr] then
		return
	end
	rigSetupInFlight[plr] = true
	task.spawn(function()
		local deadline = os.clock() + RIG_SETUP_TIMEOUT
		local character, torso, leftState, rightState, cartRoot

		while os.clock() < deadline do
			-- Держатель сменился/отпустил, пока ждали — начинать нечего.
			if cartModel.Parent == nil or cartModel:GetAttribute("HolderUserId") ~= plr.UserId then
				rigSetupInFlight[plr] = nil
				return
			end
			character = plr.Character
			torso = character and character:FindFirstChild("Torso")
			if torso then
				leftState = buildArmState(character, torso, "Left")
				rightState = buildArmState(character, torso, "Right")
			end
			cartRoot = cartModel.PrimaryPart
			if leftState and rightState and cartRoot then
				break
			end
			task.wait(0.05)
		end
		rigSetupInFlight[plr] = nil

		if not (leftState and rightState and cartRoot) then
			return -- не R6 / не доехала репликация — реконсиляция ниже попробует ещё раз через секунду
		end
		if cartModel.Parent == nil or cartModel:GetAttribute("HolderUserId") ~= plr.UserId or armRigs[plr] then
			return
		end

		local leftOffset, rightOffset = resolveMarkerGripOffsets(cartModel, cartRoot)
		if leftOffset and rightOffset then
			-- Явные части шаблона являются строгим контрактом: LeftHandGrip
			-- всегда ведёт левую руку, RightHandGrip правую. Автоперестановка
			-- здесь и создавала скрещивание при корректно собранном ассете.
			leftOffset, rightOffset = rightOffset, leftOffset
		else
			-- Маркеров нет — бьём лучом от РЕАЛЬНОГО плеча каждой руки в
			-- сторону тележки (см. raycastGripOffset выше). Сторона тут
			-- всегда верна по построению — коррекция не нужна.
			local torsoCFrame = torso.CFrame
			local leftShoulderWorld = torsoCFrame:PointToWorldSpace(leftState.AnchorLocal)
			local rightShoulderWorld = torsoCFrame:PointToWorldSpace(rightState.AnchorLocal)
			local rayLeft = raycastGripOffset(leftShoulderWorld, cartRoot, cartModel)
			local rayRight = raycastGripOffset(rightShoulderWorld, cartRoot, cartModel)
			if rayLeft and rayRight then
				leftOffset, rightOffset = rayLeft, rayRight
			else
				-- Совсем крайний случай (луч ничего не задел — например, у
				-- тележки временно нет ни одной CanQuery-части): старый
				-- рандомный фолбэк по габаритам, с той же коррекцией
				-- стороны, что и у маркеров.
				local seed = cartModel:GetAttribute("GripSeed") or cartModel:GetAttribute("HolderUserId") or 0
				leftOffset, rightOffset = randomFallbackGripOffsets(cartRoot, cartModel, seed)
				leftOffset, rightOffset = assignGripSides(torso, cartRoot, leftOffset, rightOffset)
			end
		end

		-- v17: если руки ещё возвращались после прошлого хвата — продолжаем
		-- с той же доли, иначе начинаем плавный подъём с нуля.
		local fading = GripBlend.Releasing[plr]
		GripBlend.Releasing[plr] = nil
		if fading and fading.Character == character then
			leftState.RestSize = fading.Left.RestSize
			rightState.RestSize = fading.Right.RestSize
		end
		armRigs[plr] = {
			Character = character,
			Torso = torso,
			CartModel = cartModel,
			CartRoot = cartRoot,
			LeftOffset = leftOffset,
			RightOffset = rightOffset,
			Left = leftState,
			Right = rightState,
			Blend = (fading and fading.Character == character) and fading.Weight or 0,
			LastTick = os.clock(),
		}

		-- ФИКС "РУКИ НЕ НА МЕСТЕ ПРИ ПЕРЕХВАТЕ ТЕЛЕЖКИ": раньше первая
		-- реальная поза рук выставлялась только в СЛЕДУЮЩЕМ тике
		-- RunService.Stepped (см. цикл ниже) — между моментом, когда риг
		-- уже "создан" (armRigs[plr] заполнен), и первым тиком Stepped
		-- руки на один кадр оставались в анимационной позе ходьбы/стояния,
		-- что при перехвате/краже тележки (когда игрок уже двигается и
		-- Stepped мог только что пройти в этом же кадре) иногда было
		-- заметно как дёрганье/неправильное положение рук. Считаем
		-- финальную позу СРАЗУ ЖЕ, синхронно, тем же кадром, а не ждём.
		local torsoCFrame = torso.CFrame
		local cartCFrame = cartRoot.CFrame
		local rigNow = armRigs[plr]
		rigNow.LastLeft = cartCFrame:PointToWorldSpace(leftOffset)
		rigNow.LastRight = cartCFrame:PointToWorldSpace(rightOffset)
		pcall(updateArm, rigNow.Left, torsoCFrame, rigNow.LastLeft, rigNow.Blend)
		pcall(updateArm, rigNow.Right, torsoCFrame, rigNow.LastRight, rigNow.Blend)
	end)
end


-- ЕДИНСТВЕННЫЙ цикл на все риги сразу. Stepped, а не RenderStepped: Animator
-- записывает Transform непосредственно ПЕРЕД Stepped — пишем после него в
-- том же кадре, никакого запаздывания на кадр и никакой возможности для
-- анимации "просочиться".
RunService.Stepped:Connect(function(_, dt)
	for plr, rig in pairs(armRigs) do
		local valid = rig.CartRoot.Parent ~= nil
			and rig.Torso.Parent ~= nil
			and plr.Character == rig.Character
			and rig.CartModel:GetAttribute("HolderUserId") == plr.UserId
		if not valid then
			-- Отпустил/умер/респаун/тележка выгрузилась стримингом — гасим.
			-- Если держит по-прежнему (например, просто пере-реплицировалось) —
			-- реконсиляция пересоберёт риг заново в течение секунды.
			-- v17: обычное отпускание (персонаж тот же) — руки плавно.
			stopRig(plr, rig.Torso.Parent ~= nil and plr.Character == rig.Character)
		else
			local torsoCFrame = rig.Torso.CFrame
			local cartCFrame = rig.CartRoot.CFrame
			rig.Blend = math.min(1, (rig.Blend or 1) + dt / GripBlend.In)
			rig.LastLeft = cartCFrame:PointToWorldSpace(rig.LeftOffset)
			rig.LastRight = cartCFrame:PointToWorldSpace(rig.RightOffset)
			updateArm(rig.Left, torsoCFrame, rig.LastLeft, rig.Blend)
			updateArm(rig.Right, torsoCFrame, rig.LastRight, rig.Blend)
		end
	end
	-- v17: руки плавно возвращаются к анимации после отпускания тележки.
	for plr, fade in pairs(GripBlend.Releasing) do
		fade.Weight -= dt / GripBlend.Out
		local alive = fade.Torso.Parent ~= nil and plr.Character == fade.Character
		if fade.Weight <= 0 or not alive or armRigs[plr] then
			GripBlend.Releasing[plr] = nil
			if not armRigs[plr] then
				restoreArm(fade.Left)
				restoreArm(fade.Right)
			end
		else
			local torsoCFrame = fade.Torso.CFrame
			updateArm(fade.Left, torsoCFrame, torsoCFrame:PointToWorldSpace(fade.LeftLocal), fade.Weight)
			updateArm(fade.Right, torsoCFrame, torsoCFrame:PointToWorldSpace(fade.RightLocal), fade.Weight)
		end
	end
end)

-- ОБНАРУЖЕНИЕ ДЕРЖАТЕЛЕЙ: мгновенно — по сигналу атрибута HolderUserId на
-- моделях тележек; страховочно — реконсиляцией раз в секунду (стриминг,
-- поздняя репликация, риг не собрался с первой попытки).
local function watchCartModel(instance)
	if not instance:IsA("Model") then
		return
	end
	local function refresh()
		local holderId = instance:GetAttribute("HolderUserId")
		-- Этой моделью мог владеть кто-то другой мгновение назад — гасим его риг.
		for plr, rig in pairs(armRigs) do
			if rig.CartModel == instance and plr.UserId ~= holderId then
				stopRig(plr, true)
			end
		end
		if holderId then
			local plr = Players:GetPlayerByUserId(holderId)
			if plr then
				startRig(plr, instance)
			end
		end
	end
	instance:GetAttributeChangedSignal("HolderUserId"):Connect(refresh)
	refresh()
end

workspace.ChildAdded:Connect(watchCartModel)
for _, instance in workspace:GetChildren() do
	watchCartModel(instance)
end

Players.PlayerRemoving:Connect(stopRig)

task.spawn(function()
	while true do
		task.wait(RECONCILE_INTERVAL)
		for _, instance in workspace:GetChildren() do
			if instance:IsA("Model") then
				local holderId = instance:GetAttribute("HolderUserId")
				if holderId then
					local plr = Players:GetPlayerByUserId(holderId)
					if plr and not armRigs[plr] then
						startRig(plr, instance)
					end
				end
			end
		end
	end
end)

--------------------------------------------------------------------------------
-- МАГАЗИН (Robux) — окно ShopUi + кнопка ShopEntry + отдельный диалог у
-- ShopNPC (см. Config.Shop/Config.ShopNpc, tools/BuildAllUI.lua,
-- ShopNpcService.lua). Быстрые кнопки GamepassQuickBar убраны целиком по
-- прямому запросу ("удали квикгеймпассы в целом, они не нужны справа
-- снизу") — все покупки геймпассов теперь только через общий магазин.
-- Все покупки идут ПРЯМО С КЛИЕНТА через стандартные
-- системные окна Roblox (MarketplaceService:Prompt*Purchase) — серверу
-- тут нечего проверять, платёж и начисление эффекта обрабатывает
-- MonetizationService:ProcessReceipt/PromptGamePassPurchaseFinished.
--------------------------------------------------------------------------------

-- no-op, пока НЕ переопределены ниже (если контракт ShopUi/ShopNPC не
-- собран — остальной UI/игра не должны падать, см. warn'ы ниже).
local setShopOpen = function(_open) end
local closeNpcDialogIfOpen = function() end
local openShopToTab = function(_tabName) end -- используется Toast'ом (кнопка "Open Shop" в уведомлении о нехватке денег, см. ниже) — переопределяется внутри блока ShopUi

-- Обёрнуто в отдельную функцию (а не голый do...end), потому что весь этот
-- файл — один Luau-чанк: без своей функции локальные переменные внутри
-- блока делят один регистровый бюджет (лимит 200) со ВСЕМ остальным кодом
-- выше по файлу, и он переполняется ("Out of local registers"). Отдельная
-- функция получает собственный чистый бюджет регистров.
local function setupShopUi()
	local UiRegistry = require(ReplicatedStorage.Shared.UiRegistry)
	local UiKit = require(ReplicatedStorage.Shared.UiKit)
	local shopUiGui = UiRegistry.Get("ShopUi")
	local shopPanel = shopUiGui and shopUiGui:FindFirstChild("Panel")
	local shopDimmer = shopUiGui and shopUiGui:FindFirstChild("Dimmer", true)
	if not (shopUiGui and shopPanel and shopDimmer) then
		warn("[CustomCartUI] StarterGui/ShopUi не найден или неполон (нужны Panel/Dimmer) — запусти tools/BuildAllUI.lua. Магазин работать не будет, остальной UI/игра не пострадают.")
	else
		shopUiGui.ResetOnSpawn = false
		shopUiGui.DisplayOrder = 25

		setShopOpen = function(open)
			if open then
				shopDimmer.Visible = true
				UiMotion.Open(shopPanel)
			else
				shopDimmer.Visible = false
				UiMotion.Close(shopPanel)
			end
		end

		local shopCloseButton = shopPanel:FindFirstChild("CloseButton", true)
		connectClick(shopCloseButton, function()
			setShopOpen(false)
			closeNpcDialogIfOpen()
		end, "DialogueChoice")
		connectClick(shopDimmer, function()
			setShopOpen(false)
			closeNpcDialogIfOpen()
		end)

		-- СЕКЦИИ (Config.Shop.Tabs) — по прямому запросу ("чтобы не было
		-- вкладок, а просто геймпассы категориями которые можно листать
		-- ниже") ВСЕ секции видны одновременно, одним вертикально
		-- прокручиваемым списком — вкладок и переключения между ними
		-- больше нет. Контейнеры "Cards_<Tab>" — тот же контракт имён,
		-- что и раньше (см. tools/BuildAllUI.lua), но теперь это просто
		-- пустая сетка (UIGridLayout, без предпостроенных слотов) — все
		-- карточки клонирует и наполняет клиент из CardTemplate под
		-- реальные товары, без ограничения "N карточек на экран" и без
		-- пагинации: сколько товаров, столько и карточек, секция просто
		-- растягивается по высоте (AutomaticSize).
		local body = shopPanel:FindFirstChild("Body", true)
		local cardTemplate = shopUiGui:FindFirstChild("CardTemplate", true)
		local sectionContainers = {} -- [tabName] = Frame "Cards_<Tab>"
		if body then
			for _, tabName in Config.Shop.Tabs do
				local container = body:FindFirstChild("Cards_" .. tabName, true)
				if container then
					sectionContainers[tabName] = container
				end
			end
		end
		if not cardTemplate then
			warn("[CustomCartUI] StarterGui/ShopUi без CardTemplate — карточки товаров показываться не будут. Запусти tools/BuildAllUI.lua заново.")
		end

		-- Товары каждой категории, собранные из Config.Shop.Items ОДИН раз
		-- (порядок — как в самом Config.Shop.Items).
		local itemsByTab = {}
		for _, item in Config.Shop.Items do
			itemsByTab[item.Tab] = itemsByTab[item.Tab] or {}
			table.insert(itemsByTab[item.Tab], item)
		end
		local starterPackProductId = Config.DevProducts.StarterPack and Config.DevProducts.StarterPack.Id or 0
		local starterPackPurchaseBlocked = false
		local function visibleItemsForTab(tabName)
			local visible = {}
			for _, item in itemsByTab[tabName] or {} do
				-- v3: снятые с продажи пассы (Hidden) и младшие звенья цепочки
				-- x2→x3→x5, если уже куплено старшее (HideIfOwned), не показываем.
				local hiddenByChain = false
				for _, ownedKey in item.HideIfOwned or {} do
					if player:GetAttribute("Owns_" .. ownedKey) == true then
						hiddenByChain = true
					end
				end
				if item.Hidden or hiddenByChain then
					-- пропуск
				elseif item.Id ~= "StarterPackDeal"
					or not starterPackPurchaseBlocked and player:GetAttribute("StarterPackClaimed") == false
				then
					table.insert(visible, item)
				end
			end
			return visible
		end

		local productIconCache = {}
		local productIconWaiters = {}

		-- v20: картинка товара ставится в IconHolder/PlaceholderIcon карточки,
		-- а не на всю карточку (раньше она заменяла подложку целиком). Пока
		-- картинки нет — виден эмодзи из названия товара.
		local function applySlotImage(slot, imageId)
			local icon = slot:FindFirstChild("PlaceholderIcon", true)
			if not icon then return end
			local emoji = icon:FindFirstChild("Emoji")
			if imageId and imageId ~= 0 then
				icon.Image = "rbxassetid://" .. tostring(imageId)
				if emoji then emoji.Visible = false end
			else
				icon.Image = ""
				if emoji then emoji.Visible = true end
			end
		end

		-- ImageId из конфига имеет приоритет. Если его нет, Roblox отдаёт
		-- IconImageAssetId самой страницы геймпасса/девпродукта. Запросы
		-- кэшируются, чтобы повторное открытие магазина не вызывало
		-- GetProductInfo заново.
		local function requestProductIcon(item, callback)
			local productId = item.ProductId
			if not productId or productId == 0 then
				callback(0)
				return
			end
			local infoType = item.ProductType == "GamePass" and Enum.InfoType.GamePass or Enum.InfoType.Product
			local cacheKey = item.ProductType .. ":" .. tostring(productId)
			local cached = productIconCache[cacheKey]
			if cached ~= nil then
				callback(cached)
				return
			end
			if productIconWaiters[cacheKey] then
				table.insert(productIconWaiters[cacheKey], callback)
				return
			end
			productIconWaiters[cacheKey] = { callback }
			task.spawn(function()
				local ok, productInfo = pcall(MarketplaceService.GetProductInfo, MarketplaceService, productId, infoType)
				local imageId = ok and productInfo and tonumber(productInfo.IconImageAssetId) or 0
				productIconCache[cacheKey] = imageId
				local waiters = productIconWaiters[cacheKey]
				productIconWaiters[cacheKey] = nil
				for _, waiter in waiters do
					waiter(imageId)
				end
				if not ok then
					warn(("[CustomCartUI] Не удалось загрузить иконку товара %s (%d) через GetProductInfo."):format(item.Id, productId))
				end
			end)
		end

		local function setSlotImage(slot, item)
			slot:SetAttribute("RenderedShopItemId", item.Id)
			if item.ImageId and item.ImageId ~= 0 then
				applySlotImage(slot, item.ImageId)
				return
			end
			applySlotImage(slot, 0)
			requestProductIcon(item, function(imageId)
				if imageId ~= 0 and slot.Parent and slot:GetAttribute("RenderedShopItemId") == item.Id then
					applySlotImage(slot, imageId)
				end
			end)
		end

		local ShopUiBuilder = require(ReplicatedStorage.Shared.UiBuilders.ShopUi)
		local TAB_FALLBACK_EMOJI = Config.Shop.TabEmoji or { Boosts = "⚡", Passes = "🎫", Cash = "💵", Weather = "⛅", Deals = "🎁" }
		-- «💰 2x Money» → «💰», «2x Money»: эмодзи уходит в иконку карточки.
		local function splitShopTitle(title)
			local first, rest = title:match("^(%S+)%s+(.+)$")
			if first and not first:find("[%w]") then
				return first, rest
			end
			return "", title
		end
		local function shopDescription(item)
			if item.Description then return tr(item.Description) end
			local descriptions = Config.Shop.Descriptions
			local text = descriptions and descriptions[item.Id]
			if text then return tr(text) end
			return item.ProductType == "GamePass" and tr("Permanent upgrade!") or tr("Instant delivery!")
		end

		local renderShop -- forward-declared: purchaseItem и renderSection обе на неё ссылаются

		-- Покупка — читается прямо с карточки, кликнувшей PriceButton (у
		-- каждой карточки теперь СВОЙ, постоянный PriceButton, не один
		-- переиспользуемый слот на "странице", как было при пагинации).
		local function purchaseItem(slot, priceButton)
			local productType = priceButton:GetAttribute("ProductType")
			local productId = priceButton:GetAttribute("ProductId")
			if priceButton:GetAttribute("Owned") == true then
				return
			end
			local isStarterPack = slot:GetAttribute("RenderedShopItemId") == "StarterPackDeal"
			if isStarterPack and (starterPackPurchaseBlocked or player:GetAttribute("StarterPackClaimed") ~= false) then
				return
			end
			if not productId or productId == 0 then
				warn("[CustomCartUI] Товар \"" .. slot.Name .. "\" ещё не настроен (ProductId = 0) — впиши реальный Id в Config.Shop (src/shared/Config.lua)")
				return
			end
			if productType == "GamePass" then
				MarketplaceService:PromptGamePassPurchase(player, productId)
			elseif productType == "DevProduct" then
				if isStarterPack then
					starterPackPurchaseBlocked = true
					renderShop()
					local ok, err = pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, productId)
					if not ok then
						starterPackPurchaseBlocked = false
						renderShop()
						warn("[CustomCartUI] Failed to open Starter Pack purchase prompt:", err)
					end
				else
					MarketplaceService:PromptProductPurchase(player, productId)
				end
			end
		end

		-- Заполняет ОДНУ секцию целиком — клонирует CardTemplate по числу
		-- реальных товаров этой категории (старые клоны, помеченные
		-- атрибутом IsShopCardClone, сносятся перед перестройкой).
		local function renderSection(tabName)
			local container = sectionContainers[tabName]
			if not (container and cardTemplate) then return end
			for _, child in container:GetChildren() do
				if child:GetAttribute("IsShopCardClone") == true then
					child:Destroy()
				end
			end
			local items = visibleItemsForTab(tabName)

			-- ПУСТОЙ ОТДЕЛ ПРЯЧЕМ ЦЕЛИКОМ. Секция строится билдером под каждую
			-- категорию заранее, и даже без единого товара она занимала место
			-- заголовком, подчёркиванием и подложкой. Несколько таких пустышек
			-- подряд и читались как "слишком большое разделение между
			-- отделами" — между двумя видимыми отделами стояли невидимые.
			-- v20.4: секция без товаров НЕ прячется — в ней карточки «?» (скоро).
			local section = container.Parent
			if section and section.Name:match("^Section_") then
				section.Visible = true
			end

			for i, item in items do
				local slot = cardTemplate:Clone()
				slot.Name = "Card_" .. tostring(item.Id)
				slot:SetAttribute("IsShopCardClone", true)
				slot.LayoutOrder = i
				slot.Visible = true
				slot.Parent = container

				setSlotImage(slot, item)
				local accent = UiKit.Accent(ShopUiBuilder.TabAccent(tabName))
				local emojiText, plainTitle = splitShopTitle(item.Title or "")
				local iconEmoji = slot:FindFirstChild("Emoji", true)
				if iconEmoji then
					iconEmoji.Text = item.Emoji or (emojiText ~= "" and emojiText) or TAB_FALLBACK_EMOJI[tabName] or "🛒"
				end
				local titleLabel = slot:FindFirstChild("Title", true)
				if titleLabel then
					titleLabel.Text = plainTitle
					local gradient = titleLabel:FindFirstChild("TextGradient")
					if gradient then
						gradient.Color = ColorSequence.new(accent.Light, accent.Main)
					else
						titleLabel.TextColor3 = accent.Light
					end
				end
				local descriptionLabel = slot:FindFirstChild("Description", true)
				if descriptionLabel then
					descriptionLabel.Text = shopDescription(item)
				end
				local badge = slot:FindFirstChild("Badge", true)
				if badge then
					badge.Visible = item.Badge ~= nil and item.Badge ~= ""
					local badgeText = badge:FindFirstChild("Count") or badge
					if badgeText:IsA("TextLabel") then badgeText.Text = item.Badge or "" end
				end
				-- Рамка карточки — цвет категории (как рамки товаров на референсе).
				local cardStroke = slot:FindFirstChild("SkinStroke") or slot:FindFirstChild("AccentStroke", true)
				if cardStroke and cardStroke:IsA("UIStroke") then
					cardStroke.Color = accent.Main
					cardStroke.Thickness = 2
				end
				-- v20.4: карточка подкрашена цветом категории (сверху вниз гаснет).
				slot.BackgroundColor3 = UiKit.Theme.Skins.Card.Color:Lerp(accent.Main, 0.22)
				local tint = slot:FindFirstChild("Tint")
				if tint then tint.Color = ColorSequence.new(accent.Main, accent.Dark or accent.Main) end
				local rays = slot:FindFirstChild("Rays", true)
				if rays and rays:IsA("ImageLabel") then
					rays.ImageColor3 = accent.Light -- v20.30: фон-картинка (UiTheme.Backdrops)
				elseif rays then
					for _, ray in rays:GetChildren() do
						if ray:IsA("GuiObject") then ray.BackgroundColor3 = accent.Light end
					end
				end
				local owned = item.ProductType == "GamePass" and item.PassKey and player:GetAttribute("Owns_" .. item.PassKey) == true
				local priceButton = slot:FindFirstChild("PriceButton", true)
				if priceButton then
					local robuxIcon = priceButton:FindFirstChild("RobuxIcon", true)
					local configuredRobuxIconId = Config.Icons.Robux or 0
					if robuxIcon and robuxIcon:IsA("ImageLabel") and configuredRobuxIconId ~= 0 then
						robuxIcon.Image = "rbxassetid://" .. configuredRobuxIconId
					end
					local hasRobuxIcon = robuxIcon
						and robuxIcon:IsA("ImageLabel")
						and robuxIcon.Image ~= ""
					if robuxIcon then
						robuxIcon.Visible = hasRobuxIcon == true and not owned
					end
					local caption = priceButton:FindFirstChild("Caption", true)
					if caption then
						caption.Text = owned and tr("OWNED") or ((hasRobuxIcon and "" or "R$ ") .. tostring(item.PriceRobux))
					end
					-- Купленный геймпасс: кнопка «OWNED», повторная покупка не открывается.
					priceButton:SetAttribute("Owned", owned == true)
					if owned then
						UiKit.ApplySkin(priceButton, "Button_Claim")
						if caption then caption.TextColor3 = UiKit.Theme.Skins.Button_Claim.TextColor end
					end
					priceButton:SetAttribute("ProductType", item.ProductType)
					priceButton:SetAttribute("ProductId", item.ProductId)
					connectClick(priceButton, function()
						purchaseItem(slot, priceButton)
					end)
				end
			end
		end

		-- v20.4: пустые места сетки — карточки «?»: ряд всегда полный, а
		-- категория без товаров показывает два «?» (как на референсе).
		local emptyTemplate = shopUiGui:FindFirstChild("EmptyCardTemplate", true)
		local function fillEmptySlots(tabName)
			local container = sectionContainers[tabName]
			if not (container and emptyTemplate) then return end
			local count = 0
			for _, child in container:GetChildren() do
				if child:GetAttribute("IsShopCardClone") == true then count += 1 end
			end
			local missing = count == 0 and 2 or (count % 2)
			for i = 1, missing do
				local empty = emptyTemplate:Clone()
				empty.Name = "Empty" .. i
				empty:SetAttribute("IsShopCardClone", true)
				empty.LayoutOrder = 1000 + i
				empty.Visible = true
				empty.Parent = container
			end
		end

		-- v20.4: FOREVER PACK (Config.Shop.ForeverPack): цепочка «бесплатно →
		-- пак → пак дороже» + большая карточка самого дорогого пака справа.
		local forever = Config.Shop.ForeverPack
		local foreverSection = body and body:FindFirstChild("Section_Forever")
		local foreverRemote = ReplicatedStorage.Shared:WaitForChild("ShopForeverRequest", 10)
		local function packMoneyText(packKey)
			local pack = Config.DevProducts[packKey]
			if packKey == "Free" then pack = { Minutes = forever.FreeMinutes or 3, Amount = 100 } end
			if not pack then return "" end
			local mine = tonumber(player:GetAttribute("MineTier")) or 1
			local cart = tonumber(player:GetAttribute("CartTier")) or 1
			return "$" .. NumberFormat.abbreviate(Config.MoneyPackAmount(pack, mine, cart, 1))
		end
		local function renderForever()
			if not (forever and foreverSection) then return end
			local stepDone = tonumber(player:GetAttribute("ForeverStep")) or 0
			local chain = foreverSection:FindFirstChild("Chain", true)
			for index, packKey in forever.Steps do
				local step = chain and chain:FindFirstChild("Step" .. index)
				if step then
					local button = step:FindFirstChild("Button")
					local caption = button and button:FindFirstChild("Caption")
					local robuxIcon = button and button:FindFirstChild("Icon")
					step.Title.Text = packMoneyText(packKey)
					local emoji = step:FindFirstChild("Emoji", true)
					if emoji then emoji.Text = packKey == "Free" and "🎁" or (index == 2 and "💵" or "💰") end
					local done = index <= stepDone
					local current = index == stepDone + 1
					step.Done.Visible = done
					if button then
						button.Visible = not done
						UiKit.SetButtonVariant(button, current and "Green" or "Yellow")
						button.ImageTransparency = current and 0 or 0.5
						button.BackgroundTransparency = current and 0 or 0.5
						button:SetAttribute("Current", current)
						if caption then
							if packKey == "Free" then
								caption.Text = tr("Claim")
							else
								local pack = Config.DevProducts[packKey]
								caption.Text = (robuxIcon and robuxIcon.Visible and "" or "R$ ") .. tostring(pack and pack.PriceRobux or "?")
							end
						end
					end
					step.BackgroundTransparency = done and 0.5 or 0.08
				end
			end
			local big = foreverSection:FindFirstChild("BigCard", true)
			local bigPack = Config.DevProducts[forever.Big or "MoneyPackLarge"]
			if big and bigPack then
				big.Subtitle.Text = packMoneyText(forever.Big or "MoneyPackLarge") .. "  ·  " .. tr("BEST VALUE!")
				local caption = big.Button:FindFirstChild("Caption")
				local robuxIcon = big.Button:FindFirstChild("Icon")
				if caption then caption.Text = (robuxIcon and robuxIcon.Visible and "" or "R$ ") .. tostring(bigPack.PriceRobux) end
			end
		end
		if forever and foreverSection then
			local chain = foreverSection:FindFirstChild("Chain", true)
			for index, packKey in forever.Steps do
				local step = chain and chain:FindFirstChild("Step" .. index)
				local button = step and step:FindFirstChild("Button")
				if button then
					connectClick(button, function()
						if button:GetAttribute("Current") ~= true then return end
						if packKey == "Free" then
							if foreverRemote then foreverRemote:FireServer("ClaimFree") end
						else
							local pack = Config.DevProducts[packKey]
							if pack and (pack.Id or 0) ~= 0 then MarketplaceService:PromptProductPurchase(player, pack.Id) end
						end
					end)
				end
			end
			local big = foreverSection:FindFirstChild("BigCard", true)
			if big then
				local function buyBig()
					local pack = Config.DevProducts[forever.Big or "MoneyPackLarge"]
					if pack and (pack.Id or 0) ~= 0 then MarketplaceService:PromptProductPurchase(player, pack.Id) end
				end
				connectClick(big, buyBig)
				connectClick(big:FindFirstChild("Button"), buyBig)
			end
			for _, attributeName in { "ForeverStep", "MineTier", "CartTier" } do
				player:GetAttributeChangedSignal(attributeName):Connect(renderForever)
			end
			-- Таймер обновления + анимация лучей большой карточки (только пока окно открыто).
			local refreshLabel = foreverSection:FindFirstChild("Refresh")
			local bigRays = big and big:FindFirstChild("Rays", true)
			local bigPulse = big and big:FindFirstChild("Pulse", true)
			local bigGlow = big and big:FindFirstChild("Glow")
			local chainRays = {}
			for _, d in foreverSection:GetDescendants() do
				if d.Name == "Rays" and d ~= bigRays then table.insert(chainRays, d) end
			end
			RunService.RenderStepped:Connect(function()
				if not shopPanel.Visible then return end
				local t = os.clock()
				if bigRays then bigRays.Rotation = (t * 25) % 360 end
				if bigPulse then bigPulse.Scale = 1 + math.sin(t * 3) * 0.06 end
				if bigGlow then bigGlow.BackgroundTransparency = 0.55 + math.sin(t * 3) * 0.12 end
				for _, rays in chainRays do rays.Rotation = (t * 12) % 360 end
			end)
			task.spawn(function()
				while true do
					if refreshLabel and shopPanel.Visible then
						local left = math.max(0, (tonumber(player:GetAttribute("ForeverRefreshAt")) or 0) - os.time())
						refreshLabel.Text = ("%s %dh %02dm"):format(tr("Refresh in:"), math.floor(left / 3600), math.floor(left % 3600 / 60))
					end
					task.wait(1)
				end
			end)
		end

		renderShop = function()
			for tabName in sectionContainers do
				renderSection(tabName)
				fillEmptySlots(tabName)
			end
			renderForever()
		end

		-- v20.4: навигация — кнопка категории листает список к её секции.
		local function scrollToSection(section)
			if not (section and body) then return end
			local target = body.CanvasPosition.Y + (section.AbsolutePosition.Y - body.AbsolutePosition.Y)
			local maxY = math.max(0, body.AbsoluteCanvasSize.Y - body.AbsoluteWindowSize.Y)
			TweenService:Create(body, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				CanvasPosition = Vector2.new(0, math.clamp(target, 0, maxY)),
			}):Play()
		end
		local navBar = shopPanel:FindFirstChild("NavBar", true)
		if navBar and body then
			for _, navButton in navBar:GetChildren() do
				local tabName = navButton.Name:match("^Nav_(.+)$")
				if tabName then
					connectClick(navButton, function()
						scrollToSection(body:FindFirstChild("Section_" .. tabName))
					end)
				end
			end
		end

		-- Купил геймпасс — карточка сразу показывает OWNED.
		player.AttributeChanged:Connect(function(attributeName)
			if attributeName:sub(1, 5) == "Owns_" then
				renderShop()
			end
		end)
		player:GetAttributeChangedSignal("StarterPackClaimed"):Connect(function()
			if player:GetAttribute("StarterPackClaimed") == true then starterPackPurchaseBlocked = true end
			renderShop()
		end)
		MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
			if userId ~= player.UserId or starterPackProductId == 0 or productId ~= starterPackProductId then return end
			starterPackPurchaseBlocked = purchased == true
			renderShop()
		end)

		renderShop() -- все секции строятся сразу — вкладок/страниц больше нет, всё доступно прокруткой

		-- Открыть магазин — используется Toast'ом (кнопка "Open Shop" в
		-- уведомлении о нехватке денег, см. секцию Toast ниже по файлу).
		-- Вкладок больше нет, поэтому tabName (если передан, см.
		-- PreferredTab в NotifyService/RebirthService/UpgradeService)
		-- используется только чтобы ПРОКРУТИТЬ список к нужной секции —
		-- сама секция всё равно всегда видна, просто не всегда в кадре.
		openShopToTab = function(tabName)
			setShopOpen(true)
			local container = tabName and sectionContainers[tabName]
			if container and body then
				task.defer(function()
					body.CanvasPosition = Vector2.new(0, math.max(0, container.AbsolutePosition.Y - body.AbsolutePosition.Y))
				end)
			end
		end

		UserInputService.InputBegan:Connect(function(input, processed)
			if processed then
				return
			end
			if input.KeyCode == Enum.KeyCode.Escape and shopPanel.Visible then
				setShopOpen(false)
				closeNpcDialogIfOpen()
			end
		end)
	end

	-- Магазин открывается только из CollectionMenu. ShopEntry удалён.
	local shopEntryGui = nil
	local shopButton = shopEntryGui and shopEntryGui:FindFirstChild("ShopButton", true)
	-- Прячем СРАЗУ, до любой другой настройки ниже (по прямому запросу —
	-- "убери с экрана лишние кнопки вроде кнопки магазина, всё должно
	-- открываться через книгу"): если что-то ниже в этой функции упадёт с
	-- ошибкой, кнопка всё равно уже не будет висеть на экране, а не
	-- останется видна просто потому, что до строки её выключения так и не
	-- дошло выполнение.
	if shopEntryGui then
		shopEntryGui.Enabled = false
	end
	if shopButton then
		shopEntryGui.ResetOnSpawn = false
		local hintBadge = shopButton:FindFirstChild("HintBadge", true)
		local shopHintImageId = Config.Shop.HintImageId ~= 0 and Config.Shop.HintImageId or Config.Icons.Hint or 0
		if hintBadge and shopHintImageId ~= 0 then
			if hintBadge:IsA("TextLabel") then hintBadge.Text = "" end
			local image = hintBadge:FindFirstChild("ConfiguredImage") or Instance.new("ImageLabel")
			image.Name = "ConfiguredImage"
			image.Size = UDim2.fromScale(1, 1)
			image.BackgroundTransparency = 1
			image.Image = "rbxassetid://" .. shopHintImageId
			image.ScaleType = Enum.ScaleType.Fit
			image.Parent = hintBadge
		end

		connectClick(shopButton, function()
			local currentPanel = shopUiGui and shopUiGui:FindFirstChild("Panel", true)
			local opening = not (currentPanel and currentPanel.Visible)
			setShopOpen(opening)
			if opening and hintBadge then
				hintBadge.Visible = false -- открыл магазин — подсказку прятать сразу, не ждать своего таймера
			end
		end)
		-- Кнопка-иконка магазина уже выключена выше (см. правку — теперь
		-- выключается СРАЗУ после WaitForChild, а не только тут), сама
		-- открывается из общего меню-книги (см. CollectionMenu.client.lua).
		-- setShopOpen продолжает работать как раньше, просто триггерится
		-- по-другому.
		local shopCollectionRequest = ReplicatedStorage.Shared:FindFirstChild("CollectionMenuOpenRequest")
		if shopCollectionRequest then
			shopCollectionRequest.Event:Connect(function(target)
				if target == "Shop" then
					local currentPanel = shopUiGui and shopUiGui:FindFirstChild("Panel", true)
					setShopOpen(not (currentPanel and currentPanel.Visible))
					if hintBadge then hintBadge.Visible = false end
				end
			end)
		end

		-- Знак "?" рядом с кнопкой — показывается ВРЕМЕНАМИ сам по себе
		-- (см. Config.Shop.HintShowDuration/HintHideDuration), не всегда,
		-- чтобы не отвлекать от игры. Пока магазин открыт — не показываем.
		if hintBadge then
			task.spawn(function()
				while true do
					task.wait(Config.Shop.HintHideDuration)
					local currentPanel = shopUiGui and shopUiGui:FindFirstChild("Panel", true)
					local shopIsOpen = currentPanel and currentPanel.Visible
					if not shopIsOpen then
						hintBadge.Visible = true
						task.wait(Config.Shop.HintShowDuration)
						hintBadge.Visible = false
					end
				end
			end)
		end
	end
	local shopCollectionRequest = ReplicatedStorage.Shared:FindFirstChild("CollectionMenuOpenRequest")
	if shopCollectionRequest then
		shopCollectionRequest.Event:Connect(function(target)
			if target == "Shop" then
				local currentPanel = shopUiGui and shopUiGui:FindFirstChild("Panel", true)
				setShopOpen(not (currentPanel and currentPanel.Visible))
			end
		end)
	end
end
setupShopUi()

--------------------------------------------------------------------------------
-- МОМЕНТАЛЬНОЕ ЗАПОЛНЕНИЕ ТЕЛЕЖКИ ЗА ROBUX — УБРАНО ЦЕЛИКОМ по прямому
-- запросу ("убери автозаполнение тележки целиком, этой уишки в целом не
-- должно быть"). Раньше эта кнопка появлялась, пока тележка стояла в
-- зоне шахты и в неё капала руда — с новой механикой добычи (НПС-
-- экспедиция, см. MineService.lua) такого состояния больше не бывает, так
-- что фича была бы не у дел, даже если бы её оставили. Сам билдер-код
-- кнопки (tools/BuildAllUI.lua) тоже вычищен. Developer Product
-- Config.DevProducts.CartFillByTier и его обработка в MonetizationService
-- намеренно НЕ тронуты — это просто данные/приёмка платежа, без
-- клиентской кнопки их всё равно никто не купит, удалять нечего ломать.
--------------------------------------------------------------------------------
-- НПС МАГАЗИНА (ShopNPC) — тот же билборд-приём, что и у продавца
-- прокачки (см. openDialog выше), но БЕЗ списка ответов: одна
-- приветственная реплика печатается на билборде над головой, и сразу
-- следом открывается окно ShopUi целиком (см. setShopOpen выше).
--------------------------------------------------------------------------------
task.spawn(function()
	local shopNpcRemote = ReplicatedStorage.Shared:WaitForChild("ShopNpcRequest", 5)
	if not shopNpcRemote then
		warn("[CustomCartUI] RemoteEvent ShopNpcRequest не появился — диалог с NPC магазина не будет работать.")
		return
	end

	local npcDialogOpen = false
	local npcPosition = nil
	local currentNpc = nil
	local talkingSound = nil -- см. startTalkingSound/stopTalkingSound — один зацикленный звук на весь диалог
	local npcGui, npcName, npcArrow, npcDialog
	local distanceCheckConnection = nil
	local bobConnection = nil

	local function closeNpcDialog()
		if not npcDialogOpen then
			return
		end
		npcDialogOpen = false
		if distanceCheckConnection then
			distanceCheckConnection:Disconnect()
			distanceCheckConnection = nil
		end
		if bobConnection then
			bobConnection:Disconnect()
			bobConnection = nil
		end
		if npcGui then
			npcName.Visible = true
			if npcArrow then
				npcArrow.Visible = true
			end
			npcDialog.Visible = false
		end
		if currentNpc then
			currentNpc:SetAttribute("Talking", false)
			currentNpc = nil
		end
		stopTalkingSound(talkingSound)
		talkingSound = nil
		shopNpcRemote:FireServer("Close") -- сообщает серверу — снова включить ProximityPrompt (см. ShopNpcService.lua, выключает его на время разговора)
		setShopOpen(false)
	end
	closeNpcDialogIfOpen = closeNpcDialog

	registerDialogCloser(closeNpcDialog) -- см. closeAllDialogs: диалог обязан закрыться при смерти игрока
	local function openNpcDialog(npc)
		local npcRoot = npc.PrimaryPart
		npcGui = npc:FindFirstChild("gui", true)
		if not (npcRoot and npcGui) then
			warn("[CustomCartUI] У ShopNPC нет PrimaryPart и/или BillboardGui \"gui\" где-нибудь внутри модели — не могу показать диалог")
			shopNpcRemote:FireServer("Close") -- диалог не открылся — не оставляем промпт NPC выключенным навсегда (см. Triggered в ShopNpcService.lua)
			return
		end
		npcName = npcGui:FindFirstChild("name", true)
		npcArrow = npcGui:FindFirstChild("arrow", true)
		npcDialog = npcGui:FindFirstChild("dialog", true)
		npcPosition = npcRoot.Position

		currentNpc = npc
		npc:SetAttribute("Talking", true)
		talkingSound = startTalkingSound()

		npcDialogOpen = true
		npcDialog.Visible = true
		npcName.Visible = false
		if npcArrow then
			npcArrow.Visible = false
		end

		currentScaledLabels = { npcName, npcArrow, npcDialog }
		refreshResolutionScale()

		task.spawn(function()
			typeText(npcDialog, tr(Config.ShopNpc.GreetingText), Config.ShopNpc.TypewriterCharDelay)
			if npcDialogOpen then
				setShopOpen(true) -- окно магазина открывается сразу вслед за репликой
			end
		end)

		if distanceCheckConnection then
			distanceCheckConnection:Disconnect()
		end
		distanceCheckConnection = RunService.Heartbeat:Connect(function()
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			-- ФИКС "ЗВУК ДИАЛОГА ИГРАЕТ ВЕЧНО ПОСЛЕ СМЕРТИ": раньше здесь
			-- стоял голый `return`. Персонаж умер — HumanoidRootPart исчез —
			-- сторож молча выходил, диалог НИКОГДА не закрывался, и
			-- зацикленный "голос" NPC (он живёт в SoundService и респавн его
			-- не трогает) гудел до конца сессии. Нет персонажа = разговаривать
			-- физически не с кем, поэтому закрываем диалог, а не выходим.
			if not hrp then
				closeNpcDialog()
				return
			end
			if not npcPosition then
				return
			end
			if (hrp.Position - npcPosition).Magnitude > Config.ShopNpc.DialogRange then
				closeNpcDialog()
			end
		end)

		-- Покачивание name/arrow, пока NPC МОЛЧИТ (тот же приём, что и у
		-- продавца прокачки выше) — И заметно БЫСТРЕЕ/живее, пока NPC
		-- АКТИВНО ГОВОРИТ (dialog виден).
		if bobConnection then
			bobConnection:Disconnect()
		end
		local frameCount = 0
		bobConnection = RunService.Heartbeat:Connect(function()
			frameCount += 1
			if not (npcDialogOpen and npcGui) then
				return
			end
			if npcDialog.Visible then
				npcGui.StudsOffset = Vector3.new(0, math.sin(frameCount / 8) / 5 + 1.55, 0)
			else
				npcGui.StudsOffset = Vector3.new(0, math.sin(frameCount / 25) / 6 + 1.55, 0)
			end
		end)
	end

	shopNpcRemote.OnClientEvent:Connect(function(action, npc)
		if action == "Open" then
			openNpcDialog(npc)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape and npcDialogOpen then
			closeNpcDialog()
		end
	end)
end)

--------------------------------------------------------------------------------
-- ДИАЛОГ РЕБЁРТА — тот же паттерн, что и у ShopNPC чуть выше (имя → реплика
-- печатной машинкой), но с добавлением реальных кнопок Confirm/Cancel вместо
-- мгновенного "подержал промпт — переродился" (см. RebirthService.lua).
-- Основные кнопки лежат в StarterGui/RebirthDialogButtons и могут иметь
-- собственные картинки/шрифты. Если ассет ещё не собран, создаём запасной.
--------------------------------------------------------------------------------
task.spawn(function()
	local rebirthRemote = ReplicatedStorage.Shared:WaitForChild("RebirthNpcRequest", 5)
	if not rebirthRemote then
		warn("[CustomCartUI] RemoteEvent RebirthNpcRequest не появился — диалог ребёрта не будет работать.")
		return
	end

	local function makeButton(parent, name, text, color)
		local button = Instance.new("ImageButton")
		button.Name = name
		button.Size = UDim2.fromOffset(190, 56)
		button.BackgroundColor3 = color
		button.AutoButtonColor = true
		button.Parent = parent
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = button
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Transparency = 0.5
		stroke.Parent = button
		local caption = Instance.new("TextLabel")
		caption.Name = "Caption"
		caption.Size = UDim2.fromScale(1, 1)
		caption.BackgroundTransparency = 1
		require(game:GetService("ReplicatedStorage").Shared.UiKit).StyleText(caption, "Number") -- v20: шрифт темы
		caption.Text = text
		caption.TextScaled = true
		caption.TextColor3 = Color3.new(1, 1, 1)
		caption.Parent = button
		return button
	end

	-- ОКНО РЕБЁРТА — по прямому запросу, "в стиле открытия жеод" (тёмная
	-- карточка по центру экрана, а не билборд-диалог над головой крота):
	-- слева — чек-лист условий (квадратик с галочкой/крестиком на каждое),
	-- справа — вкладка бонусов (что уже есть / что станет после ребёрта),
	-- снизу — большая кнопка REBIRTH и Cancel. Старый билборд над кротом
	-- остаётся только для имени (та же лёгкая "разговорная" анимация), вся
	-- реальная механика теперь в этом окне.
	-- v20: окно собирается билдером (Shared.PrestigeUiBuilder → StarterGui).
	local UiKit = require(ReplicatedStorage.Shared.UiKit)
	local rebirthGui = require(ReplicatedStorage.Shared.UiRegistry).Get("RebirthDialogButtons")
	local panel, closeButton, titleLabel, introLabel, requirementsFrame, bonusFrame, moneyBonusRow, speedBonusRow, confirmButton

	-- СВОЙ АССЕТ ИЗ STUDIO — по прямому запросу "сделай в билдере, чтобы я
	-- мог его менять" (тот же принцип, что и остальные плейсхолдеры в
	-- проекте — findAsset-first). Ожидаемые имена внутри: Panel (Frame),
	-- Requirements (Frame под чек-лист), Bonuses (Frame с двумя дочерними
	-- Frame'ами "MONEYRow"/"SPEEDRow", в каждом — TextLabel "Current" и
	-- "Next"), RebirthButton (GuiButton), CloseButton/CancelButton
	-- (GuiButton, необязателен).
	--
	-- ПО ПРЯМОМУ ЗАПРОСУ ("показывай целиком менюшку ребёрта, даже те
	-- элементы которые я создал и их нет в регистре") — раньше это была
	-- проверка "всё или ничего": не хватает ХОТЯ БЫ ОДНОГО из полного
	-- списка (Requirements/Bonuses/MoneyRow/SpeedRow/CancelButton) — и
	-- ВЕСЬ кастомный Panel выбрасывался целиком (`rebirthGui:Destroy()`),
	-- заменяясь код-генерируемым вариантом с нуля. Любые СВОИ элементы,
	-- которых нет в этом списке (декор, доп. текст, что угодно ещё) —
	-- пропадали вместе с ним.
	--
	-- Теперь обязателен только Panel + RebirthButton (без кнопки
	-- подтверждения престиж физически невозможен, это не опция) — а
	-- Requirements/Bonuses/чек-лист попросту не обновляются, если их нет,
	-- вместо того чтобы сносить всю панель. Сам Panel и всё, что в нём
	-- лежит (в том числе не входящее в этот список), всегда остаётся на
	-- экране как есть.
	local function findCompleteCustomGui(gui)
		local customPanel = gui:FindFirstChild("Panel", true)
		local customRebirthButton = gui:FindFirstChild("RebirthButton", true)
		if not (customPanel and customRebirthButton and customRebirthButton:IsA("GuiButton")) then
			return nil
		end
		local customRequirements = customPanel:FindFirstChild("Requirements", true)
		local customBonuses = customPanel:FindFirstChild("Bonuses", true)
		local customMoneyRow = customBonuses and customBonuses:FindFirstChild("MONEYRow", true)
		local customSpeedRow = customBonuses and customBonuses:FindFirstChild("SPEEDRow", true)
		if customMoneyRow and not (customMoneyRow:FindFirstChild("Current") and customMoneyRow:FindFirstChild("Next")) then
			customMoneyRow = nil
		end
		if customSpeedRow and not (customSpeedRow:FindFirstChild("Current") and customSpeedRow:FindFirstChild("Next")) then
			customSpeedRow = nil
		end
		return customPanel, customRequirements, customBonuses, customMoneyRow, customSpeedRow, customRebirthButton
	end

	local customPanel, customRequirements, customBonuses, customMoneyRow, customSpeedRow, customRebirthButton
	if rebirthGui then
		customPanel, customRequirements, customBonuses, customMoneyRow, customSpeedRow, customRebirthButton = findCompleteCustomGui(rebirthGui)
	end

	-- ЛЮБОЙ ЭЛЕМЕНТ С ИМЕНЕМ "CloseButton" ЗАКРЫВАЕТ ДИАЛОГ — по прямому
	-- запросу. Не один-единственный найденный элемент, а ВСЕ: билдер
	-- мог оставить несколько (например, отдельный для мобильной и
	-- десктопной раскладки) — каждый должен работать. "CancelButton" тоже
	-- принимается — это имя, которое ждал код-генерируемый вариант
	-- раньше, оставлено для обратной совместимости со старыми сборками.
	local customCloseButtons = {}
	if rebirthGui then
		for _, descendant in rebirthGui:GetDescendants() do
			if (descendant.Name == "CloseButton" or descendant.Name == "CancelButton") and descendant:IsA("GuiButton") then
				table.insert(customCloseButtons, descendant)
			end
		end
	end

	if customPanel then
		panel = customPanel
		requirementsFrame = customRequirements
		bonusFrame = customBonuses
		moneyBonusRow = customMoneyRow and { Current = customMoneyRow:FindFirstChild("Current"), Next = customMoneyRow:FindFirstChild("Next") } or nil
		speedBonusRow = customSpeedRow and { Current = customSpeedRow:FindFirstChild("Current"), Next = customSpeedRow:FindFirstChild("Next") } or nil
		confirmButton = customRebirthButton
		closeButton = customCloseButtons[1] -- см. closeButtons ниже — реальное закрытие вешается на ВСЕ customCloseButtons, это лишь для обратной совместимости мест, где переменная используется одиночно
		titleLabel = panel:FindFirstChild("Title", true)
		introLabel = panel:FindFirstChild("Intro", true)
		rebirthGui.Enabled = false
	else
	-- v10: окно престижа строит Shared.PrestigeUiBuilder (стиль магазина
	-- улучшений и дерева перков). Контракт имён тот же, что и раньше.
	if rebirthGui then rebirthGui:Destroy() end
	rebirthGui = require(ReplicatedStorage.Shared.PrestigeUiBuilder).Build()
	require(ReplicatedStorage.Shared.UiRegistry).HideTemplates(rebirthGui)
	rebirthGui.Parent = playerGui
	panel = rebirthGui:WaitForChild("Panel")
	closeButton = panel:FindFirstChild("CancelButton")
	titleLabel = panel:FindFirstChild("Tab") and panel.Tab:FindFirstChild("Title")
	introLabel = panel:FindFirstChild("Intro")
	requirementsFrame = panel:FindFirstChild("Requirements", true)
	bonusFrame = panel:FindFirstChild("Bonuses")
	local moneyRow = bonusFrame and bonusFrame:FindFirstChild("MONEYRow")
	local speedRow = bonusFrame and bonusFrame:FindFirstChild("SPEEDRow")
	moneyBonusRow = moneyRow and { Current = moneyRow:FindFirstChild("Current"), Next = moneyRow:FindFirstChild("Next") } or nil
	speedBonusRow = speedRow and { Current = speedRow:FindFirstChild("Current"), Next = speedRow:FindFirstChild("Next") } or nil
	confirmButton = panel:FindFirstChild("RebirthButton")
	end

	-- Для код-генерируемого варианта (customPanel == nil) исходный
	-- rebirthGui уничтожается и пересоздаётся заново чуть выше — любые
	-- customCloseButtons, найденные ДО этого момента, указывали бы на уже
	-- уничтоженные объекты. Поэтому customCloseButtons учитываются, только
	-- когда реально используется кастомная панель; иначе единственная
	-- кнопка закрытия — code-generated "X" (closeButton).
	local closeButtons = (customPanel and #customCloseButtons > 0) and customCloseButtons or { closeButton }

	local confirmEnabledColor = confirmButton.BackgroundColor3
	local confirmEnabledImageColor = confirmButton:IsA("ImageButton") and confirmButton.ImageColor3 or nil

	local dialogOpen = false
	local npcPosition = nil
	local currentNpc = nil
	local talkingSound = nil
	local npcGui, npcName, npcArrow
	local distanceCheckConnection = nil
	local bobConnection = nil
	local currentStatus = nil

	local function setButtonsUsable(usable)
		confirmButton.Active = usable
		if confirmButton:GetAttribute("UiSkin") then
			-- Кнопка темы: активная — зелёная, неактивная — тёмная.
			UiKit.ApplySkin(confirmButton, usable and "Button_Green" or "Button_Dark")
			if confirmButton.Image ~= "" then
				confirmButton.ImageColor3 = usable and Color3.new(1, 1, 1) or Color3.fromRGB(125, 125, 125)
			end
			return
		end
		confirmButton.AutoButtonColor = usable
		confirmButton.BackgroundColor3 = usable and confirmEnabledColor or Color3.fromRGB(105, 105, 110)
		if confirmEnabledImageColor then
			confirmButton.ImageColor3 = usable and confirmEnabledImageColor or Color3.fromRGB(125, 125, 125)
		end
	end

	local function closeRebirthDialog(skipServerNotify)
		if not dialogOpen then
			return
		end
		dialogOpen = false
		rebirthGui.Enabled = false
		if distanceCheckConnection then
			distanceCheckConnection:Disconnect()
			distanceCheckConnection = nil
		end
		if bobConnection then
			bobConnection:Disconnect()
			bobConnection = nil
		end
		if npcGui then
			npcName.Visible = true
			if npcArrow then
				npcArrow.Visible = true
			end
		end
		if currentNpc then
			currentNpc:SetAttribute("Talking", false)
			currentNpc = nil
		end
		stopTalkingSound(talkingSound)
		talkingSound = nil
		if not skipServerNotify then
			rebirthRemote:FireServer("Cancel") -- включает промпт обратно (см. RebirthService.lua Start())
		end
	end

	-- Строки чек-листа — клоны шаблона Templates/RequirementRow (галочка
	-- или крестик в квадратике слева, текст условия справа).
	local requirementTemplate = rebirthGui:FindFirstChild("Templates") and rebirthGui.Templates:FindFirstChild("RequirementRow")
	local function rebuildRequirements(requirements)
		for _, child in requirementsFrame:GetChildren() do
			if child:GetAttribute("RequirementClone") then child:Destroy() end
		end
		if not requirementsFrame:FindFirstChildOfClass("UIListLayout") then
			local layout = Instance.new("UIListLayout")
			layout.Padding = UDim.new(0, 8)
			layout.SortOrder = Enum.SortOrder.LayoutOrder
			layout.Parent = requirementsFrame
		end
		if not requirementTemplate then
			requirementTemplate = require(ReplicatedStorage.Shared.PrestigeUiBuilder).Build().Templates.RequirementRow
		end
		for index, requirement in requirements or {} do
			local row = requirementTemplate:Clone()
			row:SetAttribute("RequirementClone", true)
			row.Name = "Requirement" .. index
			row.LayoutOrder = index
			row.Visible = true
			local box = row:FindFirstChild("Box")
			local check = box and box:FindFirstChild("Check")
			local cross = box and box:FindFirstChild("Cross")
			if check then check.Visible = requirement.Met == true end
			if cross then cross.Visible = requirement.Met ~= true end
			local boxStroke = box and box:FindFirstChild("SkinStroke")
			if boxStroke then
				boxStroke.Color = requirement.Met and UiKit.Theme.Colors.Positive or UiKit.Theme.Colors.MutedText
			end
			local label = row:FindFirstChild("Label")
			if label then
				label.Text = requirement.Label
				label.TextColor3 = requirement.Met and Color3.fromRGB(170, 255, 170) or UiKit.Theme.Colors.SubText
			end
			row.Parent = requirementsFrame
		end
	end

	registerDialogCloser(closeRebirthDialog) -- см. closeAllDialogs: диалог обязан закрыться при смерти игрока
	local function openRebirthDialog(npc, status)
		currentStatus = status
		local npcRoot = npc.PrimaryPart
		npcGui = npc:FindFirstChild("gui", true)
		local name = npcGui and npcGui:FindFirstChild("name", true)
		if not (npcRoot and npcGui and name) then
			warn("[CustomCartUI] У RebirthNPC нет PrimaryPart и/или BillboardGui \"gui\" (name) — не могу показать диалог")
			rebirthRemote:FireServer("Cancel")
			return
		end
		npcName = name
		npcArrow = npcGui:FindFirstChild("arrow", true)
		npcPosition = npcRoot.Position

		currentNpc = npc
		npc:SetAttribute("Talking", true)
		talkingSound = startTalkingSound()

		dialogOpen = true
		npcName.Visible = false
		if npcArrow then
			npcArrow.Visible = false
		end

		introLabel.Text = status.Maxed
			and (status.CanAfford and "Ready to prestige! This resets Mine/Cart/Pickaxe to tier 1." or "Almost there — just need a bit more.")
			or ("Upgrade all 3 branches to tier %d first."):format(status.Cap)
		-- requirementsFrame/moneyBonusRow/speedBonusRow теперь МОГУТ быть
		-- nil — свой ассет из Studio не обязан содержать Requirements/
		-- Bonuses целиком (см. findCompleteCustomGui выше, "показывай
		-- целиком менюшку ребёрта, даже те элементы которые я создал и
		-- их нет в регистре"). Если билдер их не сделал — просто не
		-- обновляем эти конкретные тексты, вместо падения на индексации
		-- nil.
		if requirementsFrame then rebuildRequirements(status.Requirements) end
		if moneyBonusRow then
			moneyBonusRow.Current.Text = "NOW: " .. status.CurrentMoneyText
			moneyBonusRow.Next.Text = "NEXT: " .. status.BonusMoneyText
		end
		if speedBonusRow then
			speedBonusRow.Current.Text = "NOW: " .. status.CurrentSpeedText
			speedBonusRow.Next.Text = "NEXT: " .. status.BonusSpeedText
		end

		setButtonsUsable(status.AllMet)
		rebirthGui.Enabled = true

		if distanceCheckConnection then
			distanceCheckConnection:Disconnect()
		end
		distanceCheckConnection = RunService.Heartbeat:Connect(function()
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			-- ФИКС "ЗВУК ДИАЛОГА ИГРАЕТ ВЕЧНО ПОСЛЕ СМЕРТИ": раньше здесь
			-- стоял голый `return`. Персонаж умер — HumanoidRootPart исчез —
			-- сторож молча выходил, диалог НИКОГДА не закрывался, и
			-- зацикленный "голос" NPC (он живёт в SoundService и респавн его
			-- не трогает) гудел до конца сессии. Нет персонажа = разговаривать
			-- физически не с кем, поэтому закрываем диалог, а не выходим.
			if not hrp then
				closeRebirthDialog()
				return
			end
			if not npcPosition then
				return
			end
			if (hrp.Position - npcPosition).Magnitude > Config.UpgradeShop.DialogRange then
				closeRebirthDialog()
			end
		end)

		if bobConnection then
			bobConnection:Disconnect()
		end
		local frameCount = 0
		local baseBillboardOffset = npcGui:GetAttribute("BaseStudsOffset") or npcGui.StudsOffsetWorldSpace
		bobConnection = RunService.Heartbeat:Connect(function()
			frameCount += 1
			if not (dialogOpen and npcGui) then
				return
			end
			npcGui.StudsOffsetWorldSpace = baseBillboardOffset + Vector3.new(0, math.sin(frameCount / 25) / 6, 0)
		end)
	end

	connectClick(confirmButton, function()
		if not dialogOpen or not confirmButton.Active then
			return
		end
		setButtonsUsable(false)
		rebirthRemote:FireServer("Confirm")
	end, "DialogueChoice")

	for _, button in closeButtons do
		connectClick(button, function()
			closeRebirthDialog()
		end, "DialogueChoice")
	end

	rebirthRemote.OnClientEvent:Connect(function(action, a, b, c)
		if action == "Open" then
			openRebirthDialog(a, b)
		elseif action == "Result" then
			local success, resultCode, value = a, b, c
			local message
			if resultCode == "NeedBranches" then
				message = tr("rebirth.needBranches", { tier = value })
			elseif resultCode == "NeedMoney" then
				message = tr("rebirth.missing", { color = "FF9E3C", amount = value })
			elseif resultCode == "CartStolen" then
				message = tr("rebirth.stolen")
			elseif resultCode == "Success" then
				message = tr("rebirth.success", { multiplier = value })
			else
				message = tostring(resultCode)
			end
			introLabel.Text = message
			introLabel.TextColor3 = success and Color3.fromRGB(120, 255, 160) or Color3.fromRGB(255, 120, 120)
			setButtonsUsable(false)
			-- Диалог сам закрывается через паузу — успеть прочитать
			-- результат, не требуя лишнего клика.
			task.delay(1.6, function()
				closeRebirthDialog(true)
			end)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape and dialogOpen then
			closeRebirthDialog()
		end
	end)
end)

--------------------------------------------------------------------------------
-- ШИФТЛОК — свой, независимый от штатного PlayerModule, чтобы гарантированно
-- работать И на клавиатуре (Control — тот же бинд, что уже был), И на
-- телефоне (кнопка на экране; штатный Roblox shift-lock на мобиле её не
-- показывает без EnableMouseLockOption в правильном режиме — отсюда и
-- жалоба "не работает на телефоне"). Логика простая: пока включён — курсор
-- прячется и блокируется по центру (на ПК), а торс персонажа всегда
-- смотрит туда же, куда камера — тот же эффект, что у обычного Shift Lock.
-- Пока держит тележку — не вмешиваемся: поворотом там и так рулит сервер
-- (см. CartService/limitTurning), а не сам игрок.
--
-- Обёрнуто в отдельную функцию (не голый do...end) — та же причина, что у
-- setupToast/setupShopUi/setupQuickBar ниже по файлу: голый do...end делит
-- ОДИН регистровый бюджет (лимит 200) со всем кодом выше по файлу, и
-- освобождение регистров при выходе из do-блока — это лишь оптимизация
-- компилятора (-O1/-O2), которую Studio НЕ применяет в Play-режиме
-- (-O0) — там регистры do-блока НЕ переиспользуются, и следующий же
-- достаточно большой кусок кода валит компиляцию с "Out of local
-- registers... exceeded limit 200" (воспроизведено локально: luau-compile
-- -O0 падает именно тут, -O1/-O2 — нет; Studio использует -O0).
--------------------------------------------------------------------------------
local function setupShiftLock()
	local shiftLockEnabled = false

	local function applyShiftLockVisuals(enabled)
		UserInputService.MouseIconEnabled = not enabled
		if not UserInputService.TouchEnabled then
			-- MouseBehavior/LockCenter не имеет смысла на телефоне (нет
			-- курсора мыши) — трогаем только на ПК/с мышью.
			UserInputService.MouseBehavior = enabled and Enum.MouseBehavior.LockCenter or Enum.MouseBehavior.Default
		end
	end

	local function setShiftLock(enabled)
		shiftLockEnabled = enabled
		applyShiftLockVisuals(enabled)
	end

	local function toggleShiftLock()
		setShiftLock(not shiftLockEnabled)
	end

	-- v19.3: на ПК свой шифтлок БОЛЬШЕ НЕ РАБОТАЕТ — там стандартный Roblox
	-- Shift Lock на Shift (его включает server/ShiftLock.server.lua). Раньше
	-- этот скрипт вешал свой шифтлок на Ctrl, и он путался со стандартным.
	-- Свой остаётся только кнопкой 🔒 на телефоне, где стандартного нет.
	if not UserInputService.TouchEnabled then
		return
	end

	-- Торс всегда смотрит туда же, куда камера, пока шифтлок включён.
	RunService.RenderStepped:Connect(function()
		if not shiftLockEnabled then
			return
		end
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not hrp or not humanoid or humanoid.Health <= 0 then
			return
		end
		if player:GetAttribute("CarryingCart") then
			return -- поворотом уже рулит сервер (CartService.limitTurning) — не мешаем
		end
		local look = workspace.CurrentCamera.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		if flatLook.Magnitude > 0.001 then
			hrp.CFrame = CFrame.new(hrp.Position, hrp.Position + flatLook)
		end
	end)

	-- Выключаем шифтлок при смерти/респауне — не должен пережить персонажа
	-- (иначе курсор мог бы остаться залоченным на экране смерти).
	player.CharacterAdded:Connect(function()
		if shiftLockEnabled then
			setShiftLock(false)
		end
	end)

	-- МОБИЛЬНАЯ КНОПКА — показывается только на телефоне/планшете
	-- (UserInputService.TouchEnabled), делает ровно то же самое переключение.
	if UserInputService.TouchEnabled then
		-- v20: вид — Shared.UiBuilders.ShiftLockUi (StarterGui/MobileShiftLockButton).
		local gui = require(ReplicatedStorage.Shared.UiRegistry).Get("MobileShiftLockButton")
		gui.Enabled = true
		local button = gui:WaitForChild("ShiftLockButton")
		local iconImage = button:WaitForChild("Icon")
		local icon = iconImage:FindFirstChild("Emoji") or iconImage
		local stroke = button:FindFirstChild("SkinStroke") or Instance.new("UIStroke", button)

		connectClick(button, function()
			toggleShiftLock()
			local lockColor = shiftLockEnabled and Color3.fromRGB(120, 255, 160) or Color3.new(1, 1, 1)
			if icon:IsA("TextLabel") then icon.TextColor3 = lockColor end
			iconImage.ImageColor3 = lockColor
			stroke.Color = shiftLockEnabled and Color3.fromRGB(120, 255, 160) or Color3.new(1, 1, 1)
		end, "DialogueChoice")
	end
end
setupShiftLock()

--------------------------------------------------------------------------------
-- TOAST — короткие уведомления НА ЭКРАНЕ (ScreenGui "Toast", см.
-- NotifyService.lua/tools/BuildAllUI.lua). Любой серверный сервис зовёт
-- NotifyService:Show(player, text, opts) — здесь просто отображаем, что
-- прилетело. opts.ActionLabel — необязательная кнопка-действие; opts.Action
-- определяет, что она делает: "Shop" (по умолчанию, как раньше) открывает
-- магазин на вкладке opts.PreferredTab, "Invite" — системное окно
-- приглашения друга (SocialService), см. MonetizationService — реферальные
-- напоминания "пригласи друзей".
--------------------------------------------------------------------------------
-- Обёрнуто в отдельную функцию (не голый do...end) — та же причина, что у
-- setupShopUi/setupQuickBar выше: главный чанк делит один регистровый
-- бюджет (лимит 200) со всем кодом выше по файлу.
local function setupToast()
	-- v14.3: уведомления в стиле Grow a Garden. Вид — ReplicatedStorage.Shared
	-- .ToastUiBuilder (Studio-билдер tools/BuildAllUI.lua). Здесь —
	-- только логика:
	--   • на экране ОДНОВРЕМЕННО максимум 2 карточки (новая сверху, старая
	--     съезжает вниз);
	--   • если очередь растёт, время показа сокращается: 3–4 в ожидании —
	--     короче, 5+ — промежуточные «пролетают» почти мгновенно, пока
	--     очередь не догонит свежие. Ничего не выбрасывается;
	--   • одинаковые сообщения склеиваются в одну карточку с «x3».
	local ToastUiBuilder = require(ReplicatedStorage.Shared.ToastUiBuilder)
	local NCFG = Config.Notify

	-- v20: StarterGui/Toast (tools/BuildAllUI.lua); нет — соберётся билдером.
	local toastGui = require(ReplicatedStorage.Shared.UiRegistry).Get("Toast")
	if not toastGui then
		toastGui = ToastUiBuilder.Build()
		toastGui.Parent = playerGui
	end
	toastGui.ResetOnSpawn = false
	local stack = toastGui:FindFirstChild("Stack")
	local template = stack and stack:FindFirstChild("Panel")
	if not (stack and template) then
		warn("[CustomCartUI] В Toast нет Stack/Panel — уведомления отключены, остальная игра не пострадает.")
		return
	end
	template.Visible = false
	local autoScale = stack:FindFirstChild("AutoScale")
	local function updateScale()
		if autoScale then
			autoScale.Scale = UserInputService.TouchEnabled and (NCFG.MobileScale or 0.82) or 1
		end
	end
	updateScale()

	local MAX_VISIBLE = NCFG.MaxVisible or 2
	local GAP = NCFG.StackGap or 6
	local SLIDE = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

	local visible = {} -- [1] = самая свежая (сверху)
	local queue = {}
	local lastSoundAt = -math.huge

	local function panelHeight()
		return template.AbsoluteSize.Y > 0 and (template.AbsoluteSize.Y / math.max(autoScale and autoScale.Scale or 1, 0.01))
			or template.Size.Y.Offset
	end

	local function slotPosition(index)
		return UDim2.new(template.Position.X.Scale, template.Position.X.Offset, 0, (index - 1) * (panelHeight() + GAP))
	end

	local function relayout()
		for index, entry in visible do
			TweenService:Create(entry.Panel, SLIDE, { Position = slotPosition(index) }):Play()
		end
	end

	-- Сколько карточка должна провисеть с учётом ТЕКУЩЕЙ очереди. Считается
	-- заново каждый тик, поэтому если за время показа накопились новые —
	-- уже висящая карточка тоже ускоряется.
	local function durationFor(entry)
		local base = (entry.Opts and tonumber(entry.Opts.Duration)) or NCFG.Duration or 4
		local waiting = #queue
		if waiting >= (NCFG.SkipQueueAt or 5) then
			return math.min(base, NCFG.SkipSeconds or 0.45)
		elseif waiting >= (NCFG.FastQueueAt or 2) then
			return math.min(base, NCFG.FastSeconds or 1.3)
		end
		return base
	end

	local function accentFor(opts)
		local key = (opts and opts.Icon) or "Default"
		local colors = NCFG.AccentColors or {}
		return (opts and opts.AccentColor) or colors[key] or colors.Default or Color3.fromRGB(120, 230, 90)
	end

	local function showViewportPreview(viewport, spec)
		if not (viewport and viewport:IsA("ViewportFrame")) then return false end
		local ok = pcall(function()
			viewport:ClearAllChildren()
			local world = Instance.new("WorldModel")
			world.Parent = viewport
			local model
			if spec.GeodeType then
				model = PlaceholderFactory.Geode(spec.GeodeType)
			elseif spec.OreId then
				model = PlaceholderFactory.CollectionOre(spec.OreId)
			elseif spec.Tier then
				model = PlaceholderFactory.Crystal(spec.Tier)
			end
			if not model then error("no model") end
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false end
			end
			if model:IsA("BasePart") then model.Anchored = true; model.CanCollide = false end
			if spec.MutationId and spec.MutationId ~= "" then MutationVisuals.Apply(model, spec.MutationId) end
			model.Parent = world
			local center, size
			if model:IsA("Model") then
				local cf, s = model:GetBoundingBox()
				center, size = cf.Position, s
			else
				center, size = model.Position, model.Size
			end
			local distance = math.max(2, math.max(size.X, size.Y, size.Z) * 1.9)
			local cam = Instance.new("Camera")
			cam.FieldOfView = 45
			cam.CFrame = CFrame.lookAt(center + Vector3.new(distance * 0.55, distance * 0.4, distance), center)
			cam.Parent = viewport
			viewport.CurrentCamera = cam
		end)
		return ok
	end

	local function setCount(entry)
		local label = entry.Panel:FindFirstChild("Count")
		if not label then return end
		label.Visible = entry.Count > 1
		label.Text = "x" .. tostring(entry.Count)
		local pop = entry.Panel:FindFirstChild("Pop")
		if pop and entry.Count > 1 then
			pop.Scale = 1.08
			TweenService:Create(pop, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end

	local removeEntry -- объявлена заранее

	local function fillPanel(entry)
		local panel = entry.Panel
		local opts = entry.Opts
		local icon = panel:FindFirstChild("Icon", true)
		local viewport = panel:FindFirstChild("IconViewport", true)
		local text = panel:FindFirstChild("Text", true)
		local accent = panel:FindFirstChild("Accent", true)
		local actionButton = panel:FindFirstChild("ActionButton", true)

		if icon and icon:IsA("ImageLabel") then
			local configured = NCFG.Icons[(opts and opts.Icon) or "Default"] or NCFG.Icons.Default
			if typeof(configured) == "number" then
				icon.Image = configured ~= 0 and ("rbxassetid://" .. tostring(configured)) or ""
			elseif typeof(configured) == "string" then
				icon.Image = configured
			else
				icon.Image = ""
			end
		end
		local viewportShown = false
		if viewport and opts and opts.Viewport and (opts.Viewport.OreId or opts.Viewport.Tier or opts.Viewport.GeodeType) then
			viewportShown = showViewportPreview(viewport, opts.Viewport)
		end
		if viewport then viewport.Visible = viewportShown end
		if icon then icon.Visible = not viewportShown and icon.Image ~= "" end
		if accent then accent.BackgroundColor3 = accentFor(opts) end
		local panelStroke = panel:FindFirstChild("SkinStroke")
		if panelStroke then panelStroke.Color = accentFor(opts) end

		if text then
			text.RichText = opts and opts.RichText == true or false
			text.Text = entry.Message
			if opts and opts.TextColor then text.TextColor3 = opts.TextColor end
		end

		if actionButton then
			if opts and opts.ActionLabel then
				actionButton.Visible = true
				local caption = actionButton:FindFirstChild("Caption", true)
				if caption then caption.Text = opts.ActionLabel end
				-- Текст не должен залезать под кнопку.
				if text then
					text.Size = UDim2.new(text.Size.X.Scale, text.Size.X.Offset - actionButton.Size.X.Offset - 6, text.Size.Y.Scale, text.Size.Y.Offset)
				end
				local action = opts.Action or "Shop"
				local tab = opts.PreferredTab
				connectClick(actionButton, function()
					removeEntry(entry)
					if action == "Invite" then
						task.spawn(function()
							local ok, canInvite = pcall(function() return SocialService:CanSendGameInviteAsync(player) end)
							if ok and canInvite == true then
								pcall(function() SocialService:PromptGameInvite(player) end)
							end
						end)
					else
						openShopToTab(tab)
					end
				end, "DialogueChoice")
			else
				actionButton.Visible = false
			end
		end
	end

	removeEntry = function(entry)
		if entry.Removed then return end
		entry.Removed = true
		local index = table.find(visible, entry)
		if index then table.remove(visible, index) end
		local panel = entry.Panel
		local pop = panel:FindFirstChild("Pop")
		local out = TweenService:Create(pop or panel, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.In),
			pop and { Scale = 0 } or { Size = UDim2.fromOffset(0, 0) })
		out:Play()
		out.Completed:Once(function() panel:Destroy() end)
		relayout()
	end

	local pump -- объявлена заранее

	local function present(entry)
		local panel = template:Clone()
		panel.Name = "Toast"
		panel.Visible = true
		entry.Panel = panel
		entry.ShownAt = os.clock()
		fillPanel(entry)
		setCount(entry)
		table.insert(visible, 1, entry)
		-- Въезжает сверху (из-за «потолка» стопки) с лёгким попом.
		panel.Position = slotPosition(0)
		local pop = panel:FindFirstChild("Pop")
		if pop then
			pop.Scale = 0.6
			TweenService:Create(pop, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		panel.Parent = stack
		relayout()

		local now = os.clock()
		-- Звук — не на каждую «пролетающую» карточку, иначе каша.
		if playUiClick and now - lastSoundAt >= (#queue >= (NCFG.SkipQueueAt or 5) and 0.8 or 0.35) then
			lastSoundAt = now
			playUiClick("Notification")
		end

		task.spawn(function()
			while not entry.Removed do
				if os.clock() - entry.ShownAt >= durationFor(entry) then
					removeEntry(entry)
					break
				end
				task.wait(0.05)
			end
			pump()
		end)
	end

	pump = function()
		while #visible < MAX_VISIBLE and #queue > 0 do
			present(table.remove(queue, 1))
		end
		-- Очередь ждёт, а обе карточки заняты — старейшую выпихиваем раньше,
		-- если её «ускоренное» время уже вышло (durationFor это и считает).
	end

	local function sameAs(entry, message, opts)
		if entry.Message ~= message then return false end
		local a = entry.Opts and entry.Opts.ActionLabel
		local b = opts and opts.ActionLabel
		return a == b
	end

	local function enqueue(message, opts)
		message = tostring(message or "")
		if message == "" then return end
		-- Склейка одинаковых: сначала среди видимых, потом в очереди.
		for _, entry in visible do
			if not entry.Removed and sameAs(entry, message, opts) then
				entry.Count += 1
				entry.ShownAt = os.clock() -- продлеваем
				setCount(entry)
				return
			end
		end
		for _, entry in queue do
			if sameAs(entry, message, opts) then
				entry.Count += 1
				return
			end
		end
		table.insert(queue, { Message = message, Opts = typeof(opts) == "table" and opts or nil, Count = 1 })
		pump()
	end

	local notifyRemote = ReplicatedStorage.Shared:WaitForChild("NotifyRequest", 5)
	if notifyRemote then
		notifyRemote.OnClientEvent:Connect(enqueue)
	else
		warn("[CustomCartUI] RemoteEvent NotifyRequest не появился — всплывающие уведомления с сервера не будут доходить.")
	end
end
setupToast()

--------------------------------------------------------------------------------
-- ЭФФЕКТ НАЧИСЛЕНИЯ — сервер шлёт сумму после награды за гайд или продажи.
-- На экране показывается только текст суммы; 3D-монетки создаёт BankService.
--
-- Обёрнуто в функцию (не голый do...end) — та же причина, что у setupToast/
-- setupShiftLock выше: см. подробный комментарий там (Studio компилирует
-- Play-режим с -O0, где регистры do-блока не переиспользуются).
--------------------------------------------------------------------------------
local function setupMoneyGainFx()
	-- ИСПРАВЛЕНИЕ БАГА "деньги накладываются друг на друга": раньше КАЖДЫЙ
	-- вызов playMoneyGainFx строил СОВЕРШЕННО НОВЫЙ ScreenGui+Label в ОДНОЙ
	-- И ТОЙ ЖЕ точке экрана — при быстрых начислениях подряд (несколько
	-- квестов разом и т.п.) несколько "+$X" надписей оказывались буквально
	-- друг на друге, нечитаемо. Теперь один и тот же лейбл переиспользуется:
	-- новая сумма ПРИБАВЛЯЕТСЯ к текущей (с маленьким "попом" на каждое
	-- добавление, чтобы рост суммы был заметен), и только если новых
	-- начислений не было какое-то время — вся накопленная сумма угасает
	-- разом. Реальные деньги игрока при этом начисляются сервером СРАЗУ,
	-- как и раньше — это чисто визуальный индикатор, задержка только у
	-- цифры на экране, не у настоящего баланса.
	local moneyFxGui, moneyFxLabel, moneyFxContainer
	local moneyFxTotal = 0
	local moneyFxToken = 0

	-- v20: вид — Shared.UiBuilders.MoneyFxUi (StarterGui/MoneyGainFx).
	local MONEY_FX_SIZE = require(ReplicatedStorage.Shared.UiBuilders.MoneyFxUi).SIZE
	local function ensureMoneyFxGui()
		if moneyFxGui and moneyFxGui.Parent then return end
		moneyFxGui = require(ReplicatedStorage.Shared.UiRegistry).Get("MoneyGainFx")
		moneyFxContainer = moneyFxGui:WaitForChild("Container")
		moneyFxLabel = moneyFxContainer:WaitForChild("Label")
		moneyFxLabel.TextTransparency = 1
	end

	local function playMoneyGainFx(amount)
		if typeof(amount) ~= "number" or amount <= 0 then return end
		ensureMoneyFxGui()

		moneyFxTotal += amount
		moneyFxToken += 1
		local myToken = moneyFxToken

		moneyFxLabel.Text = "+$" .. NumberFormat.abbreviate(moneyFxTotal)
		moneyFxLabel.TextTransparency = 0
		-- Маленький "поп" на каждое добавление — видно, что сумма растёт,
		-- а не просто тихо подменяется числом.
		moneyFxContainer.Size = UDim2.fromOffset(MONEY_FX_SIZE.X * 1.12, MONEY_FX_SIZE.Y * 1.12)
		TweenService:Create(moneyFxContainer, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(MONEY_FX_SIZE.X, MONEY_FX_SIZE.Y),
		}):Play()

		if playUiClick then playUiClick("RewardMoney") end

		task.delay(0.6, function()
			if myToken ~= moneyFxToken then return end -- пришло новое начисление в пределах окна — ждём его, не гасим раньше времени
			if not moneyFxLabel.Parent then return end
			local fade = TweenService:Create(moneyFxLabel, TweenInfo.new(0.35), { TextTransparency = 1 })
			fade:Play()
			fade.Completed:Wait()
			if myToken ~= moneyFxToken then return end
			moneyFxTotal = 0
			-- Пустой текст — у обводки (UIStroke) не остаётся букв, контур не висит.
			moneyFxLabel.Text = ""
		end)
	end

	local tutorialRewardRemote = ReplicatedStorage.Shared:WaitForChild("TutorialRewardEvent", 5)
	if tutorialRewardRemote then tutorialRewardRemote.OnClientEvent:Connect(function(amount) playMoneyGainFx(amount) end) end
	local moneyGainRemote = ReplicatedStorage.Shared:WaitForChild("MoneyGainEvent", 5)
	if moneyGainRemote then moneyGainRemote.OnClientEvent:Connect(function(amount) playMoneyGainFx(amount) end) end
end
setupMoneyGainFx()

--------------------------------------------------------------------------------
-- ТАЙМЕР ЗАЩИТЫ НАД ГОЛОВОЙ — виден всем игрокам (не только владельцу),
-- чтобы было понятно, когда защищённого уже можно атаковать. Читает
-- атрибуты Protected/ProtectionEndsAtUnix (см. CombatService:GrantProtection —
-- тем же путём выдаётся и разовая защита новичку, и обычный щит по кнопке).
-- Чисто клиентское — ничего не реплицирует, только читает уже готовые атрибуты.
--
-- Обёрнуто в функцию, не голый do...end — см. подробный комментарий у
-- setupShiftLock выше (Studio компилирует Play-режим с -O0, где регистры
-- do-блока не переиспользуются).
--------------------------------------------------------------------------------
local function setupProtectionTimers()
	local protectionGuis = {} -- [Player] = BillboardGui

	local function removeProtectionGui(plr)
		local existing = protectionGuis[plr]
		if existing then
			existing:Destroy()
			protectionGuis[plr] = nil
		end
	end

	local function createProtectionGui(plr, character)
		removeProtectionGui(plr)
		local head = character and character:FindFirstChild("Head")
		if not head then return end

		local billboard = Instance.new("BillboardGui")
		billboard.Name = "ProtectionTimer"
		billboard.Size = UDim2.fromOffset(130, 32)
		billboard.StudsOffset = Vector3.new(0, 7.6, 0)
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = 100
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		require(game:GetService("ReplicatedStorage").Shared.UiKit).StyleText(label, "Number") -- v20: шрифт темы
		label.TextSize = 18
		label.TextColor3 = Config.Protection.Color
		label.Parent = billboard
		billboard.Parent = head
		protectionGuis[plr] = billboard

		task.spawn(function()
			while billboard.Parent do
				local endsAt = plr:GetAttribute("ProtectionEndsAtUnix")
				local remaining = endsAt and math.max(0, math.ceil(endsAt - os.time())) or 0
				if plr:GetAttribute("Protected") ~= true or remaining <= 0 then
					removeProtectionGui(plr)
					return
				end
				label.Text = tr("Shield {seconds}s", { seconds = remaining })
				task.wait(1)
			end
		end)
	end

	local function watchPlayer(plr)
		plr:GetAttributeChangedSignal("Protected"):Connect(function()
			if plr.Character and plr:GetAttribute("Protected") == true then
				createProtectionGui(plr, plr.Character)
			else
				removeProtectionGui(plr)
			end
		end)
		plr.CharacterAdded:Connect(function(character)
			if plr:GetAttribute("Protected") == true then
				createProtectionGui(plr, character)
			end
		end)
		if plr.Character and plr:GetAttribute("Protected") == true then
			createProtectionGui(plr, plr.Character)
		end
	end

	for _, plr in Players:GetPlayers() do
		watchPlayer(plr)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(removeProtectionGui)
end
setupProtectionTimers()

--------------------------------------------------------------------------------
-- ФОНОВАЯ МУЗЫКА — плейлист (Config.Music.Tracks) играет всю игру, по
-- очереди, один трек за другим: закончился текущий → сразу следующий →
-- дошли до конца списка → снова первый, по кругу до бесконечности. Чисто
-- клиентское — своя копия у каждого игрока, ничего не реплицируется и не
-- слышно другим. Отдельная SoundGroup "Music" (не "SFX") — существующий
-- SoundToggle в меню настроек её не трогает, это чисто фоновая музыка, не
-- звуки действий.
--
-- Обёрнуто в функцию, не голый do...end — см. подробный комментарий у
-- setupShiftLock выше (Studio компилирует Play-режим с -O0, где регистры
-- do-блока не переиспользуются).
--------------------------------------------------------------------------------
local function setupBackgroundMusic()
	-- Плейсхолдеры ("rbxassetid://0") не должны попадать в очередь — иначе
	-- Sound с несуществующим SoundId скорее всего вообще не даст .Ended,
	-- и плейлист намертво зависнет на первом же треке.
	local tracks = {}
	for _, id in Config.Music.Tracks do
		if id ~= "rbxassetid://0" and id ~= "" then
			table.insert(tracks, id)
		end
	end

	if #tracks > 0 then
		local musicSound = Instance.new("Sound")
		musicSound.Name = "BackgroundMusic"
		musicSound.Volume = 1
		musicSound.Looped = false
		musicSound.SoundGroup = musicSoundGroup
		musicSound.Parent = SoundService

		local currentIndex = 0
		local trackStartedAt = 0

		local function playNextTrack()
			currentIndex = currentIndex % #tracks + 1 -- дошли до конца списка (#tracks) — % возвращает 0, +1 снова даёт трек 1
			musicSound:Stop()
			musicSound.SoundId = tracks[currentIndex]
			musicSound.TimePosition = 0
			trackStartedAt = os.clock()
			musicSound:Play()
		end

		musicSound.Ended:Connect(function()
			task.defer(playNextTrack)
		end)
		playNextTrack() -- запускаем первый трек сразу при загрузке
		task.spawn(function()
			while musicSound.Parent do
				task.wait(1)
				local elapsed = os.clock() - trackStartedAt
				if musicSound.IsLoaded and musicSound.TimeLength > 0 then
					if not musicSound.Playing or elapsed > musicSound.TimeLength + 5 then
						playNextTrack()
					end
				elseif elapsed > 12 then
					-- Недоступный asset не отправляет Ended, поэтому пропускаем его.
					playNextTrack()
				end
			end
		end)
	end
end

setupBackgroundMusic()
