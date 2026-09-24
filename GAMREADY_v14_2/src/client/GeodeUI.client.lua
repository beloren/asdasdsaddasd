local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Config = require(ReplicatedStorage.Shared.Config)
local SoundVariation = require(ReplicatedStorage.Shared.SoundVariation)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local DropTables = require(ReplicatedStorage.Shared.DropTables) -- v18
local okReveal, RevealCards = pcall(require, ReplicatedStorage.Shared.RevealCards) -- v18
if not okReveal then RevealCards = nil end
local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)
-- Та же папка, в которой SkinService ищет модели скинов (hasValidAsset) —
-- нужна, чтобы панель шансов не обещала скины, ассетов которых ещё нет.
local skinAssets = ReplicatedStorage:WaitForChild("Assets")
local UiMotion = require(ReplicatedStorage.Shared.UiMotion)
local remote = ReplicatedStorage.Shared:WaitForChild("GeodeRequest")
local pendingOpenCount = 1
local beginCrack
local state
local selectedGeodeType

local rarityColors = {
	Common = Color3.fromRGB(150, 155, 165),
	Uncommon = Color3.fromRGB(75, 195, 105),
	Rare = Color3.fromRGB(70, 135, 245),
	Epic = Color3.fromRGB(170, 85, 235),
	Legendary = Color3.fromRGB(245, 190, 55),
	Mythic = Color3.fromRGB(235, 45, 95),
}

local function imageUri(id)
	return id and id ~= 0 and ("rbxassetid://" .. tostring(id)) or ""
end

local DROP_SCALE = UserInputService.TouchEnabled and 0.72 or 1
local function dropSize(size)
	return UDim2.fromOffset(size * DROP_SCALE, size * DROP_SCALE)
end

-- Камера ЗАМОРАЖИВАЕТСЯ на время открытия жеоды (см. lockCameraForOpening/
-- unlockCameraForOpening ниже) — по прямому запросу и чтобы гарантировать
-- пункт ниже: VFX-вспышка (см. emitDropVfx) ставится ОДИН РАЗ "перед
-- камерой" в момент открытия, а не пересчитывается каждый кадр. Если
-- камера продолжает крутиться (как было раньше — ничего её не
-- останавливало), вспышка застревает в мировых координатах на месте
-- эмита, а 2D-карточка результата остаётся по центру экрана — через
-- секунду-другую они визуально расходятся ("vfx не за жеодой"). Заморозка
-- камеры на всё время анимации убирает саму возможность разъехаться.
local geodeCameraRestoreType = Enum.CameraType.Custom
local geodeCameraLocked = false

local function lockCameraForOpening()
	if geodeCameraLocked then return end
	local camera = workspace.CurrentCamera
	if not camera then return end
	geodeCameraRestoreType = camera.CameraType
	camera.CameraType = Enum.CameraType.Scriptable
	geodeCameraLocked = true
end

local function unlockCameraForOpening()
	if not geodeCameraLocked then return end
	geodeCameraLocked = false
	local camera = workspace.CurrentCamera
	if camera then
		pcall(function() camera.CameraType = geodeCameraRestoreType end)
	end
end

local function findDropEmitter()
	local function resolveEmitter(container)
		if not container then return nil end
		if container:IsA("ParticleEmitter") then return container end
		return container:FindFirstChildWhichIsA("ParticleEmitter", true)
	end
	for _, name in { "GeodeDropVFX", "GeodeDropParticle", "DropVFX", "DropParticle", "ParticleEmitter" } do
		local direct = resolveEmitter(ReplicatedStorage:FindFirstChild(name))
		if direct then return direct end
		local asset = ReplicatedStorage:FindFirstChild("Assets")
		local nested = resolveEmitter(asset and asset:FindFirstChild(name))
		if nested then return nested end
	end
	return nil
end

local dropEmitterSource = findDropEmitter()
local function emitDropVfx(color)
	if not dropEmitterSource then return end
	local camera = workspace.CurrentCamera
	if not camera then return end

	lockCameraForOpening() -- см. комментарий выше — держит эту позицию валидной до closeAll()

	local holder = Instance.new("Part")
	holder.Name = "GeodeDropVFXHolder"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanTouch = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = camera.CFrame + camera.CFrame.LookVector * 3
	holder.Parent = camera

	local emitter = dropEmitterSource:Clone()
	emitter.Color = ColorSequence.new(color)
	emitter.Rate = 0
	emitter.Enabled = false
	emitter.Parent = holder
	emitter:Emit(math.max(1, tonumber(dropEmitterSource:GetAttribute("BurstCount")) or 36))
	Debris:AddItem(holder, math.max(2, emitter.Lifetime.Max + 1))
end

local function label(name, text, font)
	local item = Instance.new("TextLabel")
	item.Name = name
	item.BackgroundTransparency = 1
	require(game:GetService("ReplicatedStorage").Shared.UiKit).StyleText(item, "Number") -- v20: шрифт темы
	item.Text = text or ""
	item.TextColor3 = Color3.new(1, 1, 1)
	item.TextScaled = true
	item.TextWrapped = true
	return item
end

local function button(name, text, color)
	local item = Instance.new("TextButton")
	item.Name = name
	item.BackgroundColor3 = color
	item.BorderSizePixel = 0
	require(game:GetService("ReplicatedStorage").Shared.UiKit).StyleText(item, "Number") -- v20: шрифт темы
	item.Text = text
	item.TextColor3 = Color3.new(1, 1, 1)
	item.TextScaled = true
	return item
end

-- v9: окна строит GeodeUiBuilder («аметистовая пещера»; подиум банка —
-- BankPodiumUiBuilder). Нет в StarterGui или старая версия — строим сами.
local GeodeUiBuilder = require(ReplicatedStorage.Shared.GeodeUiBuilder)
-- v20: StarterGui/GeodeUi (tools/BuildAllUI.lua); нет — соберётся билдером.
local gui = require(ReplicatedStorage.Shared.UiRegistry).Get("GeodeUi")
if not gui or (tonumber(gui:GetAttribute("BuilderVersion")) or 0) < GeodeUiBuilder.VERSION then
	if gui then gui:Destroy() end
	gui = GeodeUiBuilder.Build()
	gui.Parent = playerGui
end
local dimmer = gui:FindFirstChild("Dimmer")
local vaultPanel = gui:FindFirstChild("VaultPanel")
local podiumPanel = gui:FindFirstChild("PodiumPanel")
local opening = gui:FindFirstChild("OpeningOverlay")
local geodeGrid = vaultPanel and vaultPanel:FindFirstChild("GeodeGrid")
local crystalGrid = podiumPanel and podiumPanel:FindFirstChild("CrystalGrid")
-- Панель покупки жеод — НЕОБЯЗАТЕЛЬНЫЙ элемент контракта: если в StarterGui
-- уже лежит свой GeodeUi, собранный ДО этой фичи (например, через
-- tools/BuildGeodeAssets.lua), панели просто не будет и кнопка "BUY GEODES"
-- нигде не появится — старый UI продолжает работать как раньше, ничего не
-- ломается. Появится сама, как только пересоберёшь GeodeUi (или используешь
-- свежий buildFallback — он ставится автоматически, если StarterGui/GeodeUi нет).
local buyGeodesPanel = gui:FindFirstChild("BuyGeodesPanel")
local buyGeodesGrid = buyGeodesPanel and buyGeodesPanel:FindFirstChild("BuyGeodesGrid")
local buyGeodeTemplate = buyGeodesGrid and buyGeodesGrid:FindFirstChild("BuyGeodeCardTemplate")
local buyOpenButton = vaultPanel and vaultPanel:FindFirstChild("BuyGeodesButton")
local geodeTemplate = geodeGrid and geodeGrid:FindFirstChild("GeodeCardTemplate")
local dropInfoPanel = vaultPanel and vaultPanel:FindFirstChild("DropInfoPanel")
local crackButton = dropInfoPanel and dropInfoPanel:FindFirstChild("CrackButton")
local infoTitle = dropInfoPanel and dropInfoPanel:FindFirstChild("InfoTitle", true)
local infoRarity = dropInfoPanel and dropInfoPanel:FindFirstChild("InfoRarity", true)
local infoChances = dropInfoPanel and dropInfoPanel:FindFirstChild("InfoChances", true)
local crystalTemplate = crystalGrid and crystalGrid:FindFirstChild("CrystalCardTemplate")
local eggImage = opening and opening:FindFirstChild("EggImage")
local crackGlow = opening and opening:FindFirstChild("CrackGlow")
crackGlow = nil
local leftHalf = opening and opening:FindFirstChild("LeftHalf")
local rightHalf = opening and opening:FindFirstChild("RightHalf")
local leftHalfImage = leftHalf and leftHalf:FindFirstChild("HalfImage")
local rightHalfImage = rightHalf and rightHalf:FindFirstChild("HalfImage")
local flash = opening and opening:FindFirstChild("Flash")
local resultImage = opening and opening:FindFirstChild("ResultImage")
local dropSilhouette = opening and opening:FindFirstChild("DropSilhouette")
local resultOutline = resultImage and (resultImage:FindFirstChild("DropOutline") or Instance.new("UIStroke"))
if resultOutline and not resultOutline.Parent then
	resultOutline.Name = "DropOutline"
	resultOutline.Thickness = Config.Geodes.DropOutlineThickness
	resultOutline.Transparency = Config.Geodes.DropOutlineTransparency
	resultOutline.Parent = resultImage
end
if resultOutline then
	resultOutline.Color = Color3.new(0, 0, 0)
	resultOutline.Thickness = 0
	resultOutline.Transparency = 1
end
local resultText = opening and opening:FindFirstChild("ResultText")
local skipButton = opening and opening:FindFirstChild("SkipButton")
-- КНОПКА ПРОПУСКА — ЖЁСТКО ВНИЗ СПРАВА (по прямому запросу).
--
-- Она живёт в оверлее вскрытия жеоды, который занимает весь экран, и её
-- положение приходит из собранного в Studio ассета — то есть может
-- оказаться где угодно, в том числе в верхней полосе, где у меню заголовок
-- и крестик. На телефоне это ровно та ситуация, из-за которой «не
-- закрывается менюшка»: палец метит в крестик, а попадает в SKIP.
--
-- Низ экрана свободен на всех шагах: там нет ни шапки панели, ни крестика,
-- ни карточки гайда (она на жеодных шагах тоже уехала вниз, но в
-- ДРУГОЙ ScreenGui с меньшим DisplayOrder, так что перекрыть эту кнопку не
-- может). Позицию задаём в коде, чтобы она не зависела от того, как и кем
-- пересобирался ассет.
if skipButton and skipButton:IsA("GuiObject") then
	skipButton.AnchorPoint = Vector2.new(1, 1)
	skipButton.Position = UDim2.new(1, -20, 1, -20)
	-- Выше всего внутри оверлея: чтобы её саму ничем не перекрыло.
	skipButton.ZIndex = 30
end
local goblinResultActive = false
local skipButtonLabel = skipButton and skipButton:FindFirstChildWhichIsA("TextLabel", true)
if not (dimmer and vaultPanel and podiumPanel and opening and geodeGrid and crystalGrid
	and geodeTemplate and crystalTemplate and dropInfoPanel and crackButton and infoTitle and infoRarity and infoChances
	and eggImage and flash and resultImage and resultText and skipButton) then
	warn("[GeodeUI] GeodeUi contract is incomplete. Re-run tools/BuildAllUI.lua.")
	return
end
opening.BackgroundTransparency = 1
if opening:IsA("ImageLabel") or opening:IsA("ImageButton") then opening.ImageTransparency = 1 end
-- v18: «🔍 ALL DROPS» — окно шансов с 3D-предпросмотром (client/DropPreviewUI).
do
	local allDrops = dropInfoPanel:FindFirstChild("AllDropsButton")
	if not allDrops then
		allDrops = Instance.new("TextButton")
		allDrops.Name = "AllDropsButton"
		allDrops.AnchorPoint = Vector2.new(1, 0)
		allDrops.Position = UDim2.new(1, -8, 0, 8)
		allDrops.Size = UDim2.fromOffset(104, 28)
		allDrops.BackgroundColor3 = Color3.fromRGB(150, 90, 230)
		require(game:GetService("ReplicatedStorage").Shared.UiKit).StyleText(allDrops, "Heading") -- v20: шрифт темы
		allDrops.TextScaled = true
		allDrops.TextColor3 = Color3.new(1, 1, 1)
		allDrops.Text = "🔍 ALL DROPS"
		allDrops.ZIndex = 20
		allDrops.Parent = dropInfoPanel
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 8)
		c.Parent = allDrops
		local st = Instance.new("UIStroke")
		st.Thickness = 2
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		st.Parent = allDrops
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 6)
		pad.PaddingRight = UDim.new(0, 6)
		pad.PaddingTop = UDim.new(0, 3)
		pad.PaddingBottom = UDim.new(0, 3)
		pad.Parent = allDrops
	end
	allDrops.Activated:Connect(function()
		local event = playerGui:FindFirstChild("OpenDropPreview")
		if event and event:IsA("BindableEvent") then
			event:Fire("Geode", selectedGeodeType or Config.Geodes.Order[1])
		end
	end)
end
-- v9: подиум банка — полоска дохода и блик золотой окантовки (вид задаёт
-- BankPodiumUiBuilder).
local bankIncomeFrame = podiumPanel:FindFirstChild("BankIncome")
local bankIncomeLabel = bankIncomeFrame and bankIncomeFrame:FindFirstChild("Text")
do
	local trim = podiumPanel:FindFirstChild("GoldTrim")
	local trimStroke = trim and trim:FindFirstChild("Trim")
	local shimmer = trimStroke and trimStroke:FindFirstChild("Shimmer")
	if shimmer then
		task.spawn(function()
			while shimmer.Parent do
				if podiumPanel.Visible then shimmer.Rotation = (shimmer.Rotation + 2) % 360 end
				task.wait(1 / 30)
			end
		end)
	end
end
local function updateBankIncome()
	if not (bankIncomeLabel and state) then return end
	local entry = state.InstalledOre and state.InstalledOre ~= "" and state.Collection and state.Collection[state.InstalledOre]
	if entry then
		bankIncomeLabel.Text = ("💰 +$%s/SEC"):format(NumberFormat.perSecond(entry.IncomePerMinute or 0))
		bankIncomeLabel.TextColor3 = Color3.fromRGB(110, 255, 140)
	else
		bankIncomeLabel.Text = "PICK A CRYSTAL"
		bankIncomeLabel.TextColor3 = Color3.fromRGB(255, 225, 130)
	end
end

resultText.TextStrokeColor3 = Color3.new(0, 0, 0)
resultText.TextStrokeTransparency = 0

-- Меню "сколько жеод открыть" (x3/x1/x5) теперь СТРОИТСЯ в tools/
-- BuildGeodeUI.lua как обычный ассет — правится в Studio, а не только в
-- коде. Если это старый StarterGui/GeodeUi, собранный ДО этого изменения
-- (тул ещё не перезапускали) — openCountMenuFallback() воссоздаёт то же
-- самое кодом, как раньше, чтобы фича не сломалась до пересборки.
local function openCountMenuFallback()
	local menu = Instance.new("Frame")
	menu.Name = "OpenCountMenu"
	menu.AnchorPoint = Vector2.new(0.5, 0.5)
	menu.Position = UDim2.fromScale(0.5, 0.5)
	menu.Size = UDim2.fromOffset(420, 220)
	menu.BackgroundColor3 = Color3.fromRGB(30, 36, 49)
	menu.BorderSizePixel = 0
	menu.Visible = false
	menu.ZIndex = 40
	menu.Parent = gui

	local title = label("Title", "OPEN")
	title.Position = UDim2.fromOffset(20, 18)
	title.Size = UDim2.new(1, -40, 0, 42)
	title.ZIndex = 41
	title.Parent = menu

	for _, count in { 3, 1, 5 } do
		local option = button("Open" .. count, "", Color3.fromRGB(65, 155, 85))
		option.AnchorPoint = Vector2.new(0.5, 0)
		option.Position = UDim2.new(count == 3 and 0.22 or count == 1 and 0.5 or 0.78, 0, 0, 88)
		option.Size = UDim2.fromOffset(105, 76)
		option.ZIndex = 41
		option.Parent = menu
	end
	return menu
end

local openCountMenu = gui:FindFirstChild("OpenCountMenu") or openCountMenuFallback()

local openCountButtons = {}
for _, count in { 3, 1, 5 } do
	local passKey = count ~= 1 and "GeodeMaster" or nil -- v10: x3 и x5 — один пасс
	local passInfo = passKey and Config.GamePasses[passKey]
	local option = openCountMenu:FindFirstChild("Open" .. count)
	if option then
		openCountButtons[count] = option
		option.Activated:Connect(function()
			if count ~= 1 then
				if not passInfo or passInfo.Id == 0 then return end
				if player:GetAttribute("Owns_" .. passKey) ~= true then
					MarketplaceService:PromptGamePassPurchase(player, passInfo.Id)
					return
				end
			end
			pendingOpenCount = count
			openCountMenu.Visible = false
			task.defer(function()
				if beginCrack then beginCrack() end
			end)
		end)
	end
end

local function refreshOpenCountMenu()
	for count, option in openCountButtons do
		local passKey = count ~= 1 and "GeodeMaster" or nil
		local passInfo = passKey and Config.GamePasses[passKey]
		local configured = count == 1 or (passInfo and passInfo.Id ~= 0)
		local enoughGeodes = selectedGeodeType and state and (state.Geodes[selectedGeodeType] or 0) > 0
		local available = configured and enoughGeodes
		option.Text = count == 1 and "1" or ("x%d\nR$ %d"):format(count, passInfo and passInfo.PriceRobux or 0)
		option.Active = available
		option.AutoButtonColor = available
		option.BackgroundColor3 = not available and Color3.fromRGB(75, 80, 90)
			or count == 5 and Color3.fromRGB(145, 75, 205)
			or Color3.fromRGB(65, 155, 85)
	end
end

refreshOpenCountMenu()
for _, passKey in { "GeodeMaster" } do
	player:GetAttributeChangedSignal("Owns_" .. passKey):Connect(refreshOpenCountMenu)
end

local resultCards = opening:FindFirstChild("ResultCards")
if resultCards and not resultCards:IsA("Frame") then
	resultCards:Destroy()
	resultCards = nil
end
if not resultCards then
	resultCards = Instance.new("Frame")
	resultCards.Name = "ResultCards"
	resultCards.AnchorPoint = Vector2.new(0.5, 0.5)
	resultCards.Position = UDim2.fromScale(0.5, 0.5)
	resultCards.Size = UDim2.fromOffset(530, 360)
	resultCards.BackgroundTransparency = 1
	resultCards.Visible = false
	resultCards.ZIndex = 22
	resultCards.Parent = opening
end
local resultCardsLayout = resultCards:FindFirstChild("CardLayout")
if not resultCardsLayout or not resultCardsLayout:IsA("UIListLayout") then
	if resultCardsLayout then resultCardsLayout:Destroy() end
	resultCardsLayout = Instance.new("UIListLayout")
	resultCardsLayout.Name = "CardLayout"
	resultCardsLayout.Parent = resultCards
end
resultCardsLayout.FillDirection = Enum.FillDirection.Horizontal
resultCardsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
resultCardsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
resultCardsLayout.Padding = UDim.new(0, 18)
local resultCardsScale = resultCards:FindFirstChild("ResponsiveScale")
if not resultCardsScale or not resultCardsScale:IsA("UIScale") then
	if resultCardsScale then resultCardsScale:Destroy() end
	resultCardsScale = Instance.new("UIScale")
	resultCardsScale.Name = "ResponsiveScale"
	resultCardsScale.Parent = resultCards
end

local crackTapButton = opening:FindFirstChild("CrackTapButton")
if not crackTapButton then
	crackTapButton = Instance.new("TextButton")
	crackTapButton.Name = "CrackTapButton"
	crackTapButton.AnchorPoint = Vector2.new(0.5, 0.5)
	crackTapButton.Position = UDim2.fromScale(0.5, 0.5)
	-- Полный экран (было 290×290 по центру) — по прямому запросу камера
	-- теперь МЕДЛЕННО ВРАЩАЕТСЯ вокруг игрока, так что жеода на экране
	-- уже не стоит на месте по центру; "клик — засчитан" должен работать
	-- в любой точке экрана, а не только там, где жеода была в момент
	-- открытия старой 2D мини-игры.
	crackTapButton.Size = UDim2.fromScale(1, 1)
	crackTapButton.BackgroundTransparency = 1
	crackTapButton.Text = ""
	crackTapButton.AutoButtonColor = false
	crackTapButton.Visible = false
	crackTapButton.ZIndex = 22
	crackTapButton.Parent = opening
end

local clickHint = opening:FindFirstChild("ClickHint")
if not clickHint then
	clickHint = label("ClickHint", "CLICK!")
	clickHint.AnchorPoint = Vector2.new(1, 0.5)
	clickHint.Position = UDim2.new(0.5, -165, 0.48, 0)
	clickHint.Size = UDim2.fromOffset(130, 54)
	clickHint.TextColor3 = Color3.fromRGB(255, 235, 90)
	clickHint.TextStrokeColor3 = Color3.new(0, 0, 0)
	clickHint.TextStrokeTransparency = 0
	clickHint.ZIndex = 22
	clickHint.Visible = false
	clickHint.Parent = opening
end


local function playUiSound(name)
	local entry = Config.Sounds[name]
	local soundId = SoundVariation.Select(name, entry)
	if not soundId then return end
	local group = SoundService:FindFirstChild("SFX")
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundId
	sound.Volume = entry.Volume or 0.5
	if group and group:IsA("SoundGroup") then sound.SoundGroup = group end
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 4)
end

local pendingGeodeType
local openRequestActive = false
local animationSeen = false
local animationToken = 0
local selectedGeodeImage = ""
local selectedGeodeColor = Color3.new(1, 1, 1)
local crackTapCount = 0
local crackTapReadyAt = 0
local crackTapBusy = false
local crackTapToken = 0
local tapSequenceCompleted = false
local podiumSwitchReadyAt = 0
local podiumRequestPending = false
-- Объявлена заранее (тело — ниже, у неё есть свои зависимости вроде
-- vaultPanel/podiumPanel): нужна как upvalue в watchdog'е из
-- crackButton.Activated, который стоит выше её обычного объявления.
local closeAll
-- Момент последнего закрытия — гасит повторные нажатия (см. closeAll ниже).
local lastCloseAllAt = 0

local function colorHex(color)
	return ("#%02X%02X%02X"):format(math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255))
end

local function chanceText(chance)
	local percent = chance * 100
	return percent >= 10 and ("%.1f%%"):format(percent) or ("%.2f%%"):format(percent)
end

local function chanceLine(title, chance, rarity)
	local color = rarityColors[rarity] or Color3.new(1, 1, 1)
	return ('<font color="%s">%s » %s</font>'):format(colorHex(color), title, chanceText(chance))
end

local function resize()
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(800, 520)
	for _, panel in { vaultPanel, podiumPanel, buyGeodesPanel } do
		if not panel then continue end
		local scale = panel:FindFirstChild("ResponsiveScale")
		if scale then scale.Scale = math.min(1, viewport.X / 760, viewport.Y / 520) end
	end
end
resize()
if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resize) end

local function clearCards(grid, template)
	for _, child in grid:GetChildren() do
		if child:IsA("GuiObject") and child ~= template then child:Destroy() end
	end
end

local function setButtonText(item, value)
	local caption = item:FindFirstChild("Caption")
	if caption and caption:IsA("TextLabel") then
		caption.Text = value
		return
	end
	if item:IsA("TextButton") then
		item.Text = value
	end
end

local function renderVault()
	if not state then return end
	clearCards(geodeGrid, geodeTemplate)
	dropInfoPanel.Visible = false
	selectedGeodeType = nil
	crackButton.Active = false
	for _, geodeType in Config.Geodes.Order do
		local count = state.Geodes[geodeType] or 0
		if count <= 0 then continue end
		local card = geodeTemplate:Clone()
		card.Name = geodeType
		card.Visible = true
		local geodeInfo = Config.Geodes.Types[geodeType]
		local rarityColor = rarityColors[geodeInfo.Rarity] or geodeInfo.Color
		local slotBackground = card:FindFirstChild("IconBackground", true)
		local backgroundImage = imageUri(Config.Geodes.Images.SlotBackground)
		if backgroundImage ~= "" then slotBackground.Image = backgroundImage end
		slotBackground.ImageColor3 = rarityColor
		slotBackground.BackgroundColor3 = rarityColor
		slotBackground.BackgroundTransparency = slotBackground.Image == "" and 0 or 1
		local icon = card:FindFirstChild("Icon", true)
		local configuredImage = imageUri(Config.Geodes.Images[geodeType])
		if configuredImage ~= "" then
			icon.Image = configuredImage
			icon.BackgroundTransparency = 1
		else
			icon.BackgroundColor3 = geodeInfo.Color
			icon.BackgroundTransparency = 0
		end
		card:FindFirstChild("Name").Text = geodeInfo.DisplayName:upper()
		card:FindFirstChild("Count").Text = "x" .. tostring(count)
		card.Parent = geodeGrid
		local function showInfo()
			selectedGeodeType = geodeType
			selectedGeodeImage = icon.Image
			selectedGeodeColor = geodeInfo.Color
			-- v18: шансы из shared/DropTables — ровно то, что роллит сервер.
			local chanceLines = { '<font color="#FFFFFF">DROP CHANCES</font>' }
			local tableInfo = DropTables.Geode(geodeType)
			local rows = tableInfo and table.clone(tableInfo.Rows) or {}
			table.sort(rows, function(a, b) return a.Chance > b.Chance end)
			for _, row in rows do
				local label = row.Kind == "Money" and ("$" .. NumberFormat.abbreviate(row.Amount)) or row.Title
				table.insert(chanceLines, chanceLine(label:upper(), row.Chance, row.Rarity))
			end
			if (state and tonumber(state.GeodeHearts) or 0) > 0 then
				table.insert(chanceLines, ('<font color="#FF6FB4">💖 NEXT GEODE x%d (HEARTS: %d)</font>'):format(Config.Geodes.Heart.Rewards, state.GeodeHearts))
			end
			infoTitle.Text = geodeInfo.DisplayName:upper() .. " DROPS"
			infoRarity.Text = geodeInfo.Rarity:upper()
			infoRarity.TextColor3 = rarityColor
			infoChances.Text = table.concat(chanceLines, "\n")
			dropInfoPanel.Visible = true
			crackButton.Active = count > 0 and not openRequestActive
			local shownPosition = UDim2.new(1, -282, 0, 76)
			dropInfoPanel.Position = UDim2.new(1, 12, 0, 76)
			TweenService:Create(dropInfoPanel, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Position = shownPosition }):Play()
		end
		local infoButton = card:FindFirstChild("InfoButton")
		if infoButton then infoButton.Activated:Connect(function()
			showInfo()
		end) end
		card.Activated:Connect(function()
			if count > 0 and not openRequestActive then showInfo() end
		end)
	end
end

-- Панель "BUY GEODES" — весь этот блок целиком необязателен (см. комментарий
-- у объявления buyGeodesPanel выше): без него ничего не подключается и
-- ничего не падает, просто фичи нет, как будто её и не добавляли.
local renderBuyGeodes
if buyOpenButton and buyGeodesPanel and buyGeodesGrid and buyGeodeTemplate then
	renderBuyGeodes = function()
		if not state then return end
		clearCards(buyGeodesGrid, buyGeodeTemplate)
		for _, geodeType in Config.Geodes.Order do
			local pack = Config.DevProducts.GeodePacks and Config.DevProducts.GeodePacks[geodeType]
			if pack then
				local geodeInfo = Config.Geodes.Types[geodeType]
				local card = buyGeodeTemplate:Clone()
				card.Name = geodeType
				card.Visible = true
				local rarityColor = rarityColors[geodeInfo.Rarity] or geodeInfo.Color
				local slotBackground = card:FindFirstChild("IconBackground", true)
				local backgroundImage = imageUri(Config.Geodes.Images.SlotBackground)
				if backgroundImage ~= "" then slotBackground.Image = backgroundImage end
				slotBackground.ImageColor3 = rarityColor
				slotBackground.BackgroundColor3 = rarityColor
				slotBackground.BackgroundTransparency = slotBackground.Image == "" and 0 or 1
				-- Тут показываем иконку самого Developer Product'а (ту, что
				-- задаётся в Creator Dashboard) — а не декоративную картинку
				-- жеоды. Пока иконка не подгрузилась (или продукт ещё не
				-- заведён), просто оставляем цветной фон рарности пустым.
				local icon = card:FindFirstChild("Icon", true)
				icon.Image = ""
				icon.BackgroundTransparency = 1
				card:FindFirstChild("Name").Text = geodeInfo.DisplayName:upper()
				card:FindFirstChild("Owned").Text = "OWNED x" .. tostring(state.Geodes[geodeType] or 0)
				local buyButton = card:FindFirstChild("BuyButton")
				if pack.Id == 0 then
					-- Плейсхолдер ещё не заполнен реальным ProductId (см.
					-- Config.lua) — кнопка неактивна, чтобы не пытаться
					-- открыть покупку несуществующего продукта.
					setButtonText(buyButton, "COMING SOON")
					buyButton.Active = false
					buyButton.AutoButtonColor = false
					buyButton.BackgroundColor3 = Color3.fromRGB(90, 95, 105)
				else
					setButtonText(buyButton, ("BUY -- R$%d"):format(pack.PriceRobux or 0))
					buyButton.Active = true
					buyButton.AutoButtonColor = true
					buyButton.BackgroundColor3 = Color3.fromRGB(65, 155, 85)
					task.spawn(function()
						local ok, productInfo = pcall(MarketplaceService.GetProductInfo, MarketplaceService, pack.Id, Enum.InfoType.Product)
						local iconId = ok and productInfo and tonumber(productInfo.IconImageAssetId) or 0
						if iconId ~= 0 and card.Parent then
							icon.Image = "rbxassetid://" .. tostring(iconId)
							icon.BackgroundTransparency = 1
						end
					end)
					buyButton.Activated:Connect(function()
						MarketplaceService:PromptProductPurchase(player, pack.Id)
					end)
				end
				card.Parent = buyGeodesGrid
			end
		end
	end

	buyOpenButton.Activated:Connect(function()
		playUiSound("UiMenuOpen")
		renderBuyGeodes()
		vaultPanel.Visible = false
		UiMotion.Open(buyGeodesPanel)
	end)

	local buyCloseButton = buyGeodesPanel:FindFirstChild("CloseButton")
	if buyCloseButton then
		buyCloseButton.Activated:Connect(function()
			UiMotion.Close(buyGeodesPanel, function()
				if gui.Enabled then
					vaultPanel.Visible = true
					UiMotion.Open(vaultPanel)
				end
			end)
		end)
	end
end

--------------------------------------------------------------------------------
-- 3D-ПОСТАНОВКА ОТКРЫТИЯ — ПОЛНАЯ ЗАМЕНА старой 2D мини-игры (по прямому
-- запросу: "удали привычную миниигру открытия жеоды к чертям"). EggImage/
-- CrackGlow/LeftHalf/RightHalf/DropSilhouette либо не строятся вовсе (см.
-- tools/BuildAllUI.lua), либо навсегда невидимы (EggImage — только
-- внутренний шаблон под ResultImage, см. buildFallback выше).
--
-- НОВОЕ ПОВЕДЕНИЕ (по прямому запросу):
--   • Камера отъезжает и МЕДЛЕННО ВРАЩАЕТСЯ ВОКРУГ ИГРОКА (не вокруг
--     наковальни) — см. startOrbitCamera.
--   • Игрок сам двигаться не может (WalkSpeed/JumpPower обнулены на время
--     сцены) — может только кликать, см. lockPlayerMovement.
--   • Декоративная 3D-жеода висит перед игроком, трясётся и растёт с
--     каждым засчитанным кликом (см. spawnGeodePropInFrontOfPlayer и
--     обработчик crackTapButton.Activated ниже).
--   • На расколе — жеода "ломается с партами вокруг" (осколки-дебрис,
--     см. shatterGeodeProp) и из неё разлетаются кривыми цветные трейлы
--     с дропом, которые на месте ВРАЩАЮТСЯ после приземления (см.
--     playCrackAndScatter/spinning ниже).
--
-- ВАЖНО: это ЧИСТО ВИЗУАЛЬНЫЙ слой — экономика (что именно выпало) по-
-- прежнему считается ТОЛЬКО сервером (см. GeodeService:OpenGeode), сервер
-- уже выдал награду к моменту, когда декоративные капли разлетаются, тут
-- только красиво показываем. "Подобрать может только тот, кто расколол" —
-- не отдельная проверка, а следствие архитектуры: капли — Instance'ы,
-- созданные ЭТИМ клиентом, другие игроки их физически не видят.
--------------------------------------------------------------------------------
local camera = workspace.CurrentCamera
local activeGeodeProp = nil
local activeAnvil = nil -- наковальня, на которой стоит текущая жеода (см. spawnGeodePropOnAnvil)
local geodePropBaseSize = Vector3.new(2, 2, 2)
local activeHammerTrack = nil
local crackSequenceActive = false
local scatterProps = {} -- {Part=, Spinning=bool}
local propResults = {} -- [Part] = соответствующий result (см. spawnScatterDrop/showDropNotification)
local showDropNotification -- forward-declared: определена ниже, после resultDetail (см. там)
local orbitConnection = nil
local orbitAngle = 0
local lockedHumanoid = nil
local lockedWalkSpeed = 16
local lockedJumpPower = 50
local geodeShakeAmp, geodeShakeUntil, geodeShakeTotal = 0, 0, 0.3 -- v14: тряска кадра катсцены

-- ВАЖНО: переиспользуем lockCameraForOpening/unlockCameraForOpening (см.
-- начало файла — тот же самый "заморозить камеру в Scriptable" механизм,
-- которым уже пользуется emitDropVfx), а не отдельную вторую пару lock/
-- restore — иначе при последовательном срабатывании обеих вторая
-- запомнила бы "Scriptable" как исходный тип камеры и захлопывала бы
-- камеру в Scriptable навсегда после открытия.
local function fovTo(value, seconds)
	TweenService:Create(camera, TweenInfo.new(seconds or 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = value }):Play()
end

-- FOV-"пружинка" на засчитанный удар — резкий наезд, плавный откат (тот же
-- приём, что и у мини-игры шахты).
local function fovKickGeode()
	local cfg = Config.Geodes
	local original = camera.FieldOfView
	local inTween = TweenService:Create(camera, TweenInfo.new(cfg.HitFOVKickSeconds * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = original + cfg.HitFOVKick })
	inTween:Play()
	inTween.Completed:Connect(function()
		TweenService:Create(camera, TweenInfo.new(cfg.HitFOVKickSeconds * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = original }):Play()
	end)
end

local function lockPlayerMovement()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	lockedHumanoid = humanoid
	lockedWalkSpeed = humanoid.WalkSpeed
	lockedJumpPower = humanoid.JumpPower
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
end

local function unlockPlayerMovement()
	if lockedHumanoid and lockedHumanoid.Parent then
		lockedHumanoid.WalkSpeed = lockedWalkSpeed
		lockedHumanoid.JumpPower = lockedJumpPower
		lockedHumanoid.JumpHeight = 7.2
	end
	lockedHumanoid = nil
end

local function stopOrbitCamera()
	if orbitConnection then
		orbitConnection:Disconnect()
		orbitConnection = nil
	end
end

-- Камера медленно кружится вокруг игрока (по прямому запросу), глядя на
-- него (и на висящую перед ним жеоду) — RenderStepped, а не один твин,
-- потому что вращение бесконечное, пока не закончится сцена.
local function startOrbitCamera()
	lockCameraForOpening()
	stopOrbitCamera()
	-- v14: не орбита, а постановочный кадр из-за плеча игрока, стоящего у
	-- наковальни. Имя функции оставлено ради совместимости с остальным кодом.
	local cut = Config.GeodeCutscene or {}
	local offset = cut.CameraOffset or Vector3.new(4.2, 4.4, 7.6)
	local current = nil
	orbitConnection = RunService.RenderStepped:Connect(function(dt)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local focusPart = (activeAnvil and activeAnvil.Parent) and activeAnvil or nil
		if not root then return end
		local focus = focusPart and (focusPart.Position + Vector3.new(0, focusPart.Size.Y / 2 + (cut.CameraLookHeight or 1.2), 0))
			or (root.Position + root.CFrame.LookVector * 4)
		local position = (root.CFrame * CFrame.new(offset.X, offset.Y, offset.Z)).Position
		local target = CFrame.lookAt(position, focus)
		current = current and current:Lerp(target, math.clamp(dt * 8, 0, 1)) or target
		local cf = current
		local now = os.clock()
		if now < geodeShakeUntil then
			local amp = geodeShakeAmp * (geodeShakeUntil - now) / geodeShakeTotal
			cf = cf * CFrame.new((math.random() * 2 - 1) * amp, (math.random() * 2 - 1) * amp, 0)
				* CFrame.Angles(0, 0, math.rad((math.random() * 2 - 1) * amp * 3))
		end
		camera.CFrame = cf
	end)
end

--------------------------------------------------------------------------------
-- v14: КАТСЦЕНА У НАКОВАЛЬНИ (Config.GeodeCutscene). Игрок встаёт перед
-- наковальней лицом к ней, в правой руке молот, камера из-за плеча. Каждый
-- клик = ОДИН взмах: анимация Config.Geodes.HammerAnimationId (не в цикле;
-- контакт — по маркеру ImpactMarker) или, если ID не задан, процедурный
-- взмах молота (замах назад → удар). На контакте — FOV-панч сильнее с
-- каждым ударом, тряска, искры, жеода трескается; последний удар — слоу-мо.
--------------------------------------------------------------------------------
local CUT = Config.GeodeCutscene or {}
local hammerModel = nil
local hammerWeld = nil
local hammerRestC0 = nil
local hammerTrack = nil
local hiddenToolParts = {}
local anchoredRoot = nil
local flashEffect = nil

local function stopHammerAnimation()
	if activeHammerTrack then
		pcall(function() activeHammerTrack:Stop(0.2) end)
		activeHammerTrack = nil
	end
end

-- Совместимость: раньше анимация молота крутилась в цикле всю сцену.
-- Теперь она играется по разу на каждый удар (см. playHammerSwing).
local function playHammerAnimation() end

local function rightHandOf(character)
	return character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
end

local function buildHammer()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local source = assets and assets:FindFirstChild(CUT.HammerAsset or "GeodeHammer")
	if source then
		local clone = source:Clone()
		local handle = clone:IsA("BasePart") and clone or clone:FindFirstChild("Handle", true)
		if clone:IsA("Model") and not handle then handle = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart", true) end
		if handle then
			local grip = nil
			if clone:IsA("Tool") then grip = clone.Grip end
			return clone, handle, grip
		end
		clone:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "GeodeHammer"
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.32, 2.6, 0.32)
	handle.Material = Enum.Material.Wood
	handle.Color = Color3.fromRGB(120, 78, 45)
	handle.Parent = model
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.5, 0.85, 0.85)
	head.Material = Enum.Material.Metal
	head.Color = Color3.fromRGB(95, 95, 105)
	head.CFrame = handle.CFrame * CFrame.new(0, 1.3, 0)
	head.Parent = model
	local band = Instance.new("Part")
	band.Name = "Band"
	band.Size = Vector3.new(0.4, 0.3, 0.4)
	band.Material = Enum.Material.Metal
	band.Color = Color3.fromRGB(200, 160, 60)
	band.CFrame = handle.CFrame * CFrame.new(0, 0.85, 0)
	band.Parent = model
	model.PrimaryPart = handle
	return model, handle, nil
end

local function detachHammer()
	if hammerTrack then pcall(function() hammerTrack:Stop(0.15) end) end
	hammerTrack = nil
	if hammerModel then hammerModel:Destroy() end
	hammerModel, hammerWeld, hammerRestC0 = nil, nil, nil
	for part, value in hiddenToolParts do
		if part.Parent then part.LocalTransparencyModifier = value end
	end
	table.clear(hiddenToolParts)
end

local function attachHammer()
	detachHammer()
	local character = player.Character
	local hand = character and rightHandOf(character)
	if not hand then return end
	-- Кирку (или другой инструмент) в руке на время сцены прячем.
	local tool = character:FindFirstChildOfClass("Tool")
	if tool then
		for _, part in tool:GetDescendants() do
			if part:IsA("BasePart") then
				hiddenToolParts[part] = part.LocalTransparencyModifier
				part.LocalTransparencyModifier = 1
			end
		end
	end
	local model, handle, toolGrip = buildHammer()
	local gripAttachment = hand:FindFirstChild("RightGripAttachment")
	local handCFrame = gripAttachment and gripAttachment.WorldCFrame or (hand.CFrame * CFrame.new(0, -hand.Size.Y / 2, 0))
	local defaultGrip = CFrame.new(0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -1, 0)
	local handleCFrame
	local gripInHandle = handle:FindFirstChild("Grip")
	if gripInHandle and gripInHandle:IsA("Attachment") then
		handleCFrame = handCFrame * gripInHandle.CFrame:Inverse()
	elseif toolGrip then
		handleCFrame = handCFrame * toolGrip:Inverse()
	else
		handleCFrame = handCFrame * defaultGrip:Inverse() * CFrame.new(0, 0.7, 0)
	end
	-- Остальные детали сохраняют положение относительно ручки.
	local offsets = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= handle then
			offsets[part] = handle.CFrame:ToObjectSpace(part.CFrame)
		end
	end
	if model:IsA("BasePart") then offsets = {} end
	handle.CFrame = handleCFrame
	for part, offset in offsets do part.CFrame = handleCFrame * offset end
	for _, part in (model:IsA("BasePart") and { model } or model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			if part ~= handle then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = handle
				weld.Part1 = part
				weld.Parent = handle
			end
		elseif part:IsA("Script") or part:IsA("LocalScript") then
			part:Destroy()
		end
	end
	local weld = Instance.new("Weld")
	weld.Name = "HammerGrip"
	weld.Part0 = hand
	weld.Part1 = handle
	weld.C0 = hand.CFrame:ToObjectSpace(handleCFrame)
	weld.Parent = handle
	hammerWeld = weld
	hammerRestC0 = weld.C0
	if model:IsA("Tool") then
		-- Tool не должен экипироваться системой инвентаря — держим как модель.
		local holder = Instance.new("Model")
		holder.Name = "GeodeHammer"
		for _, child in model:GetChildren() do child.Parent = holder end
		model:Destroy()
		model = holder
	end
	model.Name = "GeodeHammer"
	model.Parent = character
	hammerModel = model
end

-- Один взмах. onImpact вызывается в момент контакта с жеодой.
local function playHammerSwing(fast, onImpact)
	local fired = false
	local function impact()
		if fired then return end
		fired = true
		onImpact()
	end
	if fast then
		task.delay(0.05, impact)
		return
	end
	local id = tonumber(Config.Geodes.HammerAnimationId) or 0
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and (humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid))
	if id ~= 0 and animator then
		local ok = pcall(function()
			if not hammerTrack then
				local animation = Instance.new("Animation")
				animation.AnimationId = "rbxassetid://" .. tostring(id)
				hammerTrack = animator:LoadAnimation(animation)
				hammerTrack.Looped = false
				hammerTrack.Priority = Enum.AnimationPriority.Action4
			end
			local connection
			connection = hammerTrack:GetMarkerReachedSignal(CUT.ImpactMarker or "Hit"):Connect(function()
				connection:Disconnect()
				impact()
			end)
			hammerTrack:Play(0.05, 1, 1)
			task.delay(math.max(CUT.ImpactDelay or 0.3, (CUT.SwingSeconds or 0.8) * 0.85), function()
				if connection.Connected then connection:Disconnect() end
				impact()
			end)
		end)
		if ok then return end
	end
	-- ПРОЦЕДУРНЫЙ ВЗМАХ: молот уходит назад-вверх, потом резко вниз.
	local delayToImpact = CUT.ImpactDelay or 0.3
	if hammerWeld and hammerRestC0 then
		local back = hammerRestC0 * CFrame.Angles(math.rad(-70), 0, 0)
		local down = hammerRestC0 * CFrame.Angles(math.rad(45), 0, 0)
		local windup = TweenService:Create(hammerWeld, TweenInfo.new(delayToImpact * 0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { C0 = back })
		windup:Play()
		windup.Completed:Connect(function()
			if not hammerWeld then return end
			local strike = TweenService:Create(hammerWeld, TweenInfo.new(delayToImpact * 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { C0 = down })
			strike:Play()
			strike.Completed:Connect(function()
				impact()
				if hammerWeld then
					TweenService:Create(hammerWeld, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { C0 = hammerRestC0 }):Play()
				end
			end)
		end)
		task.delay(delayToImpact + 0.2, impact)
	else
		task.delay(delayToImpact, impact)
	end
end

-- Ставит игрока перед наковальней лицом к ней (корень заякорен на время сцены).
local function standAtAnvil(anvil)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (anvil and root and humanoid) then return end
	local toPlayer = Vector3.new(root.Position.X - anvil.Position.X, 0, root.Position.Z - anvil.Position.Z)
	local direction = toPlayer.Magnitude > 0.5 and toPlayer.Unit or Vector3.new(0, 0, 1)
	local standXZ = anvil.Position + direction * (CUT.StandDistance or 3.6)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, activeGeodeProp, anvil }
	local hit = workspace:Raycast(Vector3.new(standXZ.X, anvil.Position.Y + 8, standXZ.Z), Vector3.new(0, -40, 0), params)
	local groundY = hit and hit.Position.Y or (root.Position.Y - humanoid.HipHeight - root.Size.Y / 2)
	local standPos = Vector3.new(standXZ.X, groundY + humanoid.HipHeight + root.Size.Y / 2, standXZ.Z)
	root.CFrame = CFrame.lookAt(standPos, Vector3.new(anvil.Position.X, standPos.Y, anvil.Position.Z))
	root.AssemblyLinearVelocity = Vector3.zero
	root.Anchored = true
	anchoredRoot = root
end

local function shakeGeodeCamera(amount, seconds)
	geodeShakeAmp = amount
	geodeShakeTotal = seconds
	geodeShakeUntil = os.clock() + seconds
end

local function flash(brightness, seconds)
	if not flashEffect or not flashEffect.Parent then
		flashEffect = Instance.new("ColorCorrectionEffect")
		flashEffect.Name = "GeodeFlash"
		flashEffect.Parent = game:GetService("Lighting")
	end
	flashEffect.Brightness = brightness
	TweenService:Create(flashEffect, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
end

-- Снимает всё, что поставила катсцена (молот, якорь, вспышку).
local function releaseCutscene()
	detachHammer()
	if anchoredRoot and anchoredRoot.Parent then anchoredRoot.Anchored = false end
	anchoredRoot = nil
	if flashEffect then flashEffect:Destroy() flashEffect = nil end
	geodeShakeUntil = 0
end

-- Декоративная 3D-жеода висит перед игроком (не на наковальне — камера
-- теперь кружит вокруг ИГРОКА, см. ТЗ) — клонируется через
-- PlaceholderFactory.Geode (тот же плейсхолдер, что и реальный дроп жеод
-- из шахты), ничего не начисляет, чисто витрина.
-- Находит наковальню (Crusher) на участке игрока — по прямому запросу
-- "открытие жеоды должно быть строго на наковальне", а не висеть в
-- воздухе перед персонажем.
local function findOwnCrusher()
	local plots = workspace:FindFirstChild("Plots")
	local plotIndex = player:GetAttribute("PlotIndex")
	local plot = plots and plotIndex and plots:FindFirstChild("PlotPad_" .. tostring(plotIndex))
	local pad = plot and (plot.PrimaryPart or plot:FindFirstChild("PlotPad", true))
	local content = pad and pad:FindFirstChild("Content_" .. player.Name)
	local building = content and content:FindFirstChild("GeodeBuilding", true)
	return building and building:FindFirstChild("Crusher", true)
end

-- Декоративная 3D-жеода СТРОГО НА НАКОВАЛЬНЕ (по прямому запросу).
-- Возвращает (model, anvilPart) — anvilPart нужен вызывающему, чтобы
-- навести на него камеру и оттуда же запустить разлёт дропа.
-- Клонируется через PlaceholderFactory.Geode (тот же плейсхолдер, что и
-- реальный дроп жеод из шахты), ничего не начисляет, чисто витрина.
local function spawnGeodePropOnAnvil(geodeType)
	if not geodeType then return nil, nil end
	local crusher = findOwnCrusher()
	if not crusher then
		warn("[GeodeUI] Не нашлась наковальня (GeodeBuilding/Crusher) на участке игрока — жеода будет расколота без 3D-модели. Проверь, что участок построен.")
		return nil, nil
	end
	local ok, source = pcall(PlaceholderFactory.Geode, geodeType)
	if not (ok and source) then
		warn("[GeodeUI] PlaceholderFactory.Geode вернул ошибку/nil для", geodeType, ok and "" or source)
		return nil, crusher
	end
	local model = source:Clone()
	local part = model:IsA("Model") and (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)) or model
	if not part then
		warn("[GeodeUI] Клон жеоды без PrimaryPart/BasePart — уничтожаю.")
		model:Destroy()
		return nil, crusher
	end

	-- Ставим ровно НА верхнюю грань наковальни: центр жеоды поднимаем на
	-- половину высоты наковальни + половину высоты самой жеоды, иначе
	-- модель наполовину утонет в наковальне.
	local geodeHeight = model:IsA("Model") and select(2, model:GetBoundingBox()).Y or part.Size.Y
	local restCFrame = crusher.CFrame * CFrame.new(0, crusher.Size.Y / 2 + geodeHeight / 2, 0)
	if model:IsA("Model") then
		model.PrimaryPart = part
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
			end
		end
		model:PivotTo(restCFrame)
	else
		model.Anchored = true
		model.CanCollide = false
		model.CFrame = restCFrame
		geodePropBaseSize = model.Size
	end
	model.Parent = workspace
	return model, crusher
end

--------------------------------------------------------------------------------
-- СИГНАЛ КАТСЦЕНЫ: прячет/возвращает HUD (см. client/CinematicHud.client.lua).
-- "Найди или заведи" — порядок запуска клиентских скриптов не гарантирован.
--------------------------------------------------------------------------------
local cinematicMode = ReplicatedStorage.Shared:FindFirstChild("CinematicMode")
if not cinematicMode then
	cinematicMode = Instance.new("BindableEvent")
	cinematicMode.Name = "CinematicMode"
	cinematicMode.Parent = ReplicatedStorage.Shared
end

local function returnCrackCamera()
	releaseCutscene()
	crackSequenceActive = false
	cinematicMode:Fire(false) -- раскол кончился — возвращаем HUD
	fovTo(Config.Geodes.CameraFOVDefault, 0.4)
	unlockPlayerMovement()
	task.delay(0.4, function()
		stopOrbitCamera()
		unlockCameraForOpening()
	end)
end

-- Раскол "будто ломается или трескается с партами вокруг" (по прямому
-- запросу) — несколько осколков-дебрис разлетаются от жеоды и гаснут,
-- вместо простого уменьшения/вращения.
-- ОСКОЛКИ ПРИ КАЖДОМ УДАРЕ (по прямому запросу — "должны разлетаться
-- сто процентов"). Эмиттер СОЗДАЁТСЯ КОДОМ, а не ищется в
-- ReplicatedStorage: найденного там ассета может не быть, и тогда частиц
-- не появлялось бы вовсе. Здесь появляться нечему — эмиттер строится на
-- месте и сразу же выбрасывает свою порцию.
local function burstGeodeChips(position, color, amount)
	local holder = Instance.new("Part")
	holder.Name = "GeodeChipBurst"
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.Transparency = 1
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false
	holder.CFrame = CFrame.new(position)
	holder.Parent = workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = holder

	-- Крупная каменная крошка.
	local chips = Instance.new("ParticleEmitter")
	chips.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	chips.Color = ColorSequence.new(color)
	chips.LightEmission = 0.2
	chips.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	chips.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	chips.Lifetime = NumberRange.new(0.35, 0.7)
	chips.Speed = NumberRange.new(12, 22)
	chips.SpreadAngle = Vector2.new(180, 180)
	chips.Acceleration = Vector3.new(0, -60, 0) -- крошка падает, а не висит
	chips.Rotation = NumberRange.new(-180, 180)
	chips.RotSpeed = NumberRange.new(-260, 260)
	chips.Drag = 2
	chips.Rate = 0
	chips.Enabled = false
	chips.Parent = attachment

	-- Пыль, чтобы удар читался даже на светлом фоне.
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.35))
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 2.6),
	})
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Lifetime = NumberRange.new(0.3, 0.5)
	dust.Speed = NumberRange.new(3, 7)
	dust.SpreadAngle = Vector2.new(120, 120)
	dust.Drag = 6
	dust.Rate = 0
	dust.Enabled = false
	dust.Parent = attachment

	chips:Emit(amount or 18)
	dust:Emit(math.max(4, math.floor((amount or 18) / 3)))
	Debris:AddItem(holder, 1.2)
end

local function geodePropColor(geodeProp)
	local color = Color3.fromRGB(200, 190, 175)
	pcall(function()
		if geodeProp:IsA("BasePart") then
			color = geodeProp.Color
		elseif geodeProp:IsA("Model") then
			local part = geodeProp:FindFirstChildWhichIsA("BasePart", true)
			if part then color = part.Color end
		end
	end)
	return color
end

local function shatterGeodeProp(geodeProp)
	if not geodeProp then return end
	local origin = geodeProp:IsA("Model") and geodeProp:GetPivot().Position or geodeProp.Position
	local color = geodePropColor(geodeProp)
	local cfg = Config.Geodes

	-- Раскол = крупный бурст крошки + пыль + кольцо ударной волны + осколки.
	-- Раньше это был только разлёт кубиков, из-за чего момент читался как
	-- дешёвый "взрыв", а не как раскол камня.
	burstGeodeChips(origin, color, 46)

	local ring = Instance.new("Part")
	ring.Name = "GeodeShockwave"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, 1, 1)
	ring.CFrame = CFrame.new(origin) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = color:Lerp(Color3.new(1, 1, 1), 0.5)
	ring.Material = Enum.Material.Neon
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CastShadow = false
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, 16, 16),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.6)

	local flash = Instance.new("PointLight")
	flash.Color = color
	flash.Brightness = 5
	flash.Range = 22
	flash.Shadows = false
	flash.Parent = ring
	TweenService:Create(flash, TweenInfo.new(0.4), { Brightness = 0, Range = 6 }):Play()

	local pieceCount = math.max(8, math.floor(tonumber(cfg.ShatterPieceCount) or 7) * 2)
	for _ = 1, pieceCount do
		local piece = Instance.new("Part")
		piece.Name = "GeodeShard"
		-- Осколки РАЗНОЙ вытянутой формы, а не одинаковые кубики: камень
		-- колется на пластины, и именно это отличает раскол от взрыва.
		piece.Size = Vector3.new(
			0.25 + math.random() * 0.5,
			0.12 + math.random() * 0.25,
			0.3 + math.random() * 0.6
		)
		piece.Color = color:Lerp(Color3.new(0, 0, 0), math.random() * 0.25)
		piece.Material = Enum.Material.Slate
		piece.Anchored = true
		piece.CanCollide = false
		piece.CanQuery = false
		piece.CastShadow = false
		piece.CFrame = CFrame.new(origin)
		piece.Parent = workspace

		local direction = Vector3.new(math.random() * 2 - 1, math.random() * 0.7 + 0.35, math.random() * 2 - 1).Unit
		local speed = 7 + math.random() * 7
		local spinAxis = Vector3.new(math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1).Unit
		local spinSpeed = 8 + math.random() * 10
		task.spawn(function()
			local flightSeconds = (tonumber(cfg.ShatterFlightSeconds) or 0.4) + math.random() * 0.35
			local steps = math.max(8, math.floor(flightSeconds * 50))
			for step = 1, steps do
				if not piece.Parent then return end
				local alpha = step / steps
				local t = alpha * flightSeconds
				-- Настоящая баллистика: разлетелись и попадали вниз.
				local pos = origin + direction * speed * t + Vector3.new(0, -0.5 * 42 * t * t, 0)
				piece.CFrame = CFrame.new(pos) * CFrame.fromAxisAngle(spinAxis, spinSpeed * t)
				-- Гаснут только в конце, а не с первого кадра — иначе разлёт
				-- не успевает прочитаться.
				piece.Transparency = alpha < 0.65 and 0 or (alpha - 0.65) / 0.35
				task.wait(flightSeconds / steps)
			end
			piece:Destroy()
		end)
	end
	if geodeProp.Parent then geodeProp:Destroy() end
end

-- Цветной трейл-дроп, разлетающийся по дуге из точки раскола — приземлившись,
-- ВРАЩАЕТСЯ НА МЕСТЕ (по прямому запросу), пока его не подберут.
-- ПО ПРЯМОМУ ЗАПРОСУ: капля НЕ должна намекать, что внутри — "дроп вообще
-- не должен показываться после жеоды, только после поднятия". Раньше цвет
-- капли/трейла сразу выдавал редкость (rarityColors) — теперь нейтральный
-- тёмный цвет для всех, независимо от того, что внутри; какая награда —
-- игрок узнаёт только подобрав каплю (см. showDropNotification ниже).
local NEUTRAL_DROP_COLOR = Color3.fromRGB(60, 55, 70)

local function spawnScatterDrop(origin, landPos, flightSeconds, arcHeight, result)
	local prop = Instance.new("Part")
	prop.Name = "GeodeDropProp"
	prop.Shape = Enum.PartType.Ball
	local baseSize = Vector3.new(1.1, 1.1, 1.1)
	prop.Size = baseSize
	prop.Color = NEUTRAL_DROP_COLOR
	prop.Material = Enum.Material.SmoothPlastic
	prop.Anchored = true
	prop.CanCollide = false
	prop.CFrame = CFrame.new(origin)
	prop.Parent = workspace
	propResults[prop] = result

	-- НАДПИСЬ "1/N" НАД КАПЛЕЙ — как над рудой из шахты (по прямому
	-- запросу). Показывает ТОЛЬКО шанс, без названия: что именно внутри,
	-- игрок по-прежнему узнаёт лишь подобрав (это осознанное правило
	-- дропа, см. NEUTRAL_DROP_COLOR выше), а шанс спойлером не является.
	local chance = typeof(result) == "table" and tonumber(result.Chance) or nil
	if chance and chance > 0 then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "DropChanceGui"
		billboard.Size = UDim2.new(2.6, 0, 0.9, 0)
		billboard.StudsOffset = Vector3.new(0, 1.6, 0)
		billboard.AlwaysOnTop = true
		billboard.LightInfluence = 0
		billboard.MaxDistance = 80
		billboard.Adornee = prop
		billboard.Parent = prop

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		require(game:GetService("ReplicatedStorage").Shared.UiKit).StyleText(label, "Heading") -- v20: шрифт темы
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 225, 130)
		label.Text = ("1/%d"):format(math.max(1, math.round(1 / chance)))
		label.Parent = billboard
	end

	local trail = Instance.new("Trail")
	local a0 = Instance.new("Attachment", prop)
	a0.Position = Vector3.new(0, 0.5, 0)
	local a1 = Instance.new("Attachment", prop)
	a1.Position = Vector3.new(0, -0.5, 0)
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(NEUTRAL_DROP_COLOR)
	trail.Lifetime = 0.35
	trail.Parent = prop

	task.spawn(function()
		local steps = math.max(6, math.floor(flightSeconds * 40))
		for step = 1, steps do
			if not prop.Parent then return end
			local linear = step / steps
			-- ПО ПРЯМОМУ ЗАПРОСУ ("чутка медленнее и плавнее") — плавный
			-- разгон и торможение (ease-in-out) вместо равномерного
			-- линейного движения, так более медленный полёт не выглядит
			-- вялым/дёрганым.
			local alpha = linear * linear * (3 - 2 * linear) -- smoothstep
			local pos = origin:Lerp(landPos, alpha) + Vector3.new(0, math.sin(alpha * math.pi) * arcHeight, 0)
			prop.CFrame = CFrame.new(pos) * CFrame.Angles(0, alpha * math.pi * 3, 0)
			task.wait(flightSeconds / steps)
		end
		if prop.Parent then
			trail.Enabled = false
			table.insert(scatterProps, prop)

			-- "ПРИПЛЮЩИВАНИЕ" ПРИ ПРИЗЕМЛЕНИИ (по прямому запросу) —
			-- пружинка: сначала шире и ниже обычного (удар), потом чуть
			-- выше и уже обычного (отскок), потом плавно назад к
			-- нормальной форме. Меняем именно Size (не Scale модели — это
			-- простой Part), CFrame держим неизменным по центру landPos,
			-- чтобы приплющивание не "уезжало" по высоте.
			local cfg = Config.Geodes
			local landCFrame = CFrame.new(landPos)
			prop.CFrame = landCFrame
			local squashV = tonumber(cfg.LandingSquashVertical) or 0.6
			local squashH = tonumber(cfg.LandingSquashHorizontal) or 1.25
			local squashSeconds = math.max(0.1, tonumber(cfg.LandingSquashSeconds) or 0.35)
			local squashedSize = Vector3.new(baseSize.X * squashH, baseSize.Y * squashV, baseSize.Z * squashH)
			local overshootSize = Vector3.new(baseSize.X * 0.94, baseSize.Y * 1.08, baseSize.Z * 0.94)
			prop.Size = squashedSize
			local impactTween = TweenService:Create(prop, TweenInfo.new(squashSeconds * 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = overshootSize })
			impactTween:Play()
			impactTween.Completed:Connect(function()
				if not prop.Parent then return end
				TweenService:Create(prop, TweenInfo.new(squashSeconds * 0.65, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = baseSize }):Play()
			end)
		end
	end)
end

-- Раскол декоративной жеоды (см. shatterGeodeProp) + разлёт декоративных
-- капель дропа кривыми (см. spawnScatterDrop). results — уже НАЧИСЛЕННЫЕ
-- сервером награды (см. GeodeService:OpenGeode), тут только красиво
-- показываем при ПОДБОРЕ (см. showDropNotification), не начисляем повторно.
-- ВАЖНО: НИКАКОГО VFX/раскрытия в момент раскола (по прямому запросу) —
-- только сам разлёт нейтральных капель.
local function playCrackAndScatter(geodeProp, results)
	local cfg = Config.Geodes
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local origin = geodeProp and (geodeProp:IsA("Model") and geodeProp:GetPivot().Position or geodeProp.Position)
		or (root and root.Position + root.CFrame.LookVector * -4)
		or Vector3.new()

	shatterGeodeProp(geodeProp)

	local dropCount = math.min(cfg.ScatterMaxDrops, math.max(1, #results))
	for i = 1, dropCount do
		local result = results[i] or results[1]
		task.delay((i - 1) * 0.05, function()
			-- ДРОП ЛЕТИТ В СТОРОНУ ИГРОКА (по прямому запросу), а не в
			-- случайную сторону: иначе за ним приходилось бегать, а половина
			-- улетала за спину, где её не видно.
			local character = player.Character
			local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
			local toPlayer = playerRoot and (playerRoot.Position - origin) * Vector3.new(1, 0, 1)
			local direction = (toPlayer and toPlayer.Magnitude > 1) and toPlayer.Unit
				or Vector3.new(0, 0, 1)
			-- Небольшой веер, чтобы несколько капель не легли одна в одну.
			local spread = math.rad((math.random() - 0.5) * 70)
			direction = (CFrame.Angles(0, spread, 0) * direction).Unit
			local distance = cfg.ScatterRadius * (0.45 + math.random() * 0.55)
			local landXZ = origin + direction * distance

			-- ТОЧНО НА ЗЕМЛЮ: ищем настоящую поверхность лучом сверху вниз.
			-- Раньше высота задавалась как "origin - 1.5" наугад, и на любом
			-- уклоне капля висела в воздухе или тонула в земле.
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { character, workspace:FindFirstChild("MineGroundOre") }
			local hit = workspace:Raycast(landXZ + Vector3.new(0, 24, 0), Vector3.new(0, -120, 0), params)
			local landPos = hit and (hit.Position + Vector3.new(0, 0.6, 0))
				or Vector3.new(landXZ.X, origin.Y - 1.5, landXZ.Z)

			spawnScatterDrop(origin, landPos, cfg.ScatterFlightSeconds, cfg.ScatterArcHeight, result)
		end)
	end

	-- Камера возвращается игроку не позже CameraReturnTimeout — даже если
	-- игрок не добежал собрать все капли, залипнуть в катсцене нельзя.
	task.delay(math.max(cfg.CameraReturnSeconds, 0.3), returnCrackCamera)
end

-- Приземлившиеся капли вращаются на месте (по прямому запросу), пока их
-- не подберут — подбор простой проверкой расстояния каждый кадр (капли —
-- Anchored/CanCollide=false, обычный Touched тут менее надёжен). "Подобрать
-- может только тот, кто расколол" выполняется автоматически — эти
-- Instance'ы существуют только в мире ЭТОГО клиента. Подбор — единственный
-- момент, когда игрок узнаёт, что было в этой конкретной капле (см.
-- showDropNotification, определена ниже после resultDetail).
RunService.Heartbeat:Connect(function(dt)
	if #scatterProps == 0 then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	for i = #scatterProps, 1, -1 do
		local prop = scatterProps[i]
		if not prop.Parent then
			propResults[prop] = nil
			table.remove(scatterProps, i)
		else
			prop.CFrame = prop.CFrame * CFrame.Angles(0, dt * 2.4, 0)
			if root and (prop.Position - root.Position).Magnitude <= 3.5 then
				pcall(playUiSound, "GeodeDrop")
				if showDropNotification then
					showDropNotification(propResults[prop])
				end
				propResults[prop] = nil
				prop:Destroy()
				table.remove(scatterProps, i)
			end
		end
	end
end)

local function shakeGeodeForTap(token, finalTap)
	crackTapBusy = true
	local duration = math.max(0.12, tonumber(Config.Geodes.CrackTapShakeDuration) or 0.22)
	local stepDuration = duration / 4
	task.spawn(function()
		for _, angle in { -12, 10, -7, 0 } do
			if token ~= crackTapToken or not activeGeodeProp or not activeGeodeProp.Parent then return end
			pcall(function()
				if activeGeodeProp:IsA("Model") then
					activeGeodeProp:PivotTo(activeGeodeProp:GetPivot() * CFrame.Angles(0, 0, math.rad(angle)))
				else
					activeGeodeProp.Orientation = Vector3.new(activeGeodeProp.Orientation.X, activeGeodeProp.Orientation.Y, angle)
				end
			end)
			task.wait(stepDuration)
		end
		if token ~= crackTapToken then return end
		crackTapBusy = false
		if finalTap then
			tapSequenceCompleted = true
			crackTapButton.Visible = false
			remote:FireServer("OpenGeode", pendingGeodeType, pendingOpenCount)
		end
	end)
end

local activeCrackBall = nil
local spawnCrackBall -- forward-declared: onCrackHit ниже вызывает её раньше, чем она определена по тексту файла

local function destroyCrackBall()
	if activeCrackBall then
		activeCrackBall:Destroy()
		activeCrackBall = nil
	end
end

-- ПО ПРЯМОМУ ЗАПРОСУ: "игра на экране должна выглядеть как шарики, на
-- которые надо тыкать в рандомных точках на экране" — было: один
-- невидимый клик-на-весь-экран (после недавнего фикса бага "не вижу
-- миниигру"). Теперь: реальный видимый шарик (ImageLabel/ImageButton),
-- на КАЖДЫЙ клик исчезает и тут же появляется заново в НОВОЙ случайной
-- точке экрана — ровно то же число попаданий (Config.Geodes.CrackTapCount),
-- тот же момент отправки запроса на сервер (последний засчитанный клик),
-- просто честно видно, куда тыкать.
-- Контакт молота с жеодой: искры, рост, трещины, FOV-панч и тряска —
-- с каждым ударом сильнее.
local function geodeImpact(hitIndex, isFinal)
	local cut = Config.GeodeCutscene or {}
	playUiSound("GeodeTap")
	local base = (cut.FovStart or 62) + (cut.FovStepPerHit or -3) * (hitIndex - 1)
	local kick = (cut.KickBase or -5) + (cut.KickPerHit or -2.5) * (hitIndex - 1)
	shakeGeodeCamera((cut.ShakeBase or 0.22) + (cut.ShakePerHit or 0.14) * (hitIndex - 1), isFinal and 0.6 or 0.3)
	if not isFinal then
		TweenService:Create(camera, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = base + kick }):Play()
		task.delay(0.07, function()
			TweenService:Create(camera, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = base + (cut.FovStepPerHit or -3) }):Play()
		end)
	end
	if activeGeodeProp then
		local hitPosition = activeGeodeProp:IsA("Model") and activeGeodeProp:GetPivot().Position or activeGeodeProp.Position
		local color = geodePropColor(activeGeodeProp)
		burstGeodeChips(hitPosition, color, 18 + hitIndex * 8)
		local growth = 1 + hitIndex * 0.1
		pcall(function()
			if activeGeodeProp:IsA("Model") then
				activeGeodeProp:ScaleTo(growth)
			else
				activeGeodeProp.Size = geodePropBaseSize * growth
			end
		end)
		-- Трещины: свечение изнутри растёт с каждым ударом.
		local glow = activeGeodeProp:FindFirstChild("CrackGlow")
		if not glow then
			glow = Instance.new("Highlight")
			glow.Name = "CrackGlow"
			glow.FillColor = Color3.fromRGB(255, 220, 140)
			glow.OutlineColor = Color3.fromRGB(255, 240, 200)
			glow.FillTransparency = 1
			glow.OutlineTransparency = 1
			glow.DepthMode = Enum.HighlightDepthMode.Occluded
			glow.Parent = activeGeodeProp
		end
		local required = math.max(2, math.floor(tonumber(Config.Geodes.CrackTapCount) or 3))
		local share = math.clamp(hitIndex / required, 0, 1)
		TweenService:Create(glow, TweenInfo.new(0.1), { FillTransparency = 0.95 - 0.45 * share, OutlineTransparency = 0.7 - 0.6 * share }):Play()
	end
end

-- Финал: слоу-мо (наезд и удержание), вспышка, потом раскол.
local function playGeodeFinale(onDone)
	local cut = Config.GeodeCutscene or {}
	TweenService:Create(camera, TweenInfo.new(0.12, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { FieldOfView = cut.FinalFov or 42 }):Play()
	flash(cut.FlashBrightness or 0.5, (cut.FinalHold or 0.5) + 0.2)
	task.delay(cut.FinalHold or 0.5, onDone)
end

local function onCrackHit(fast)
	if not openRequestActive or not pendingGeodeType or not crackSequenceActive then return end
	local now = os.clock()
	if crackTapBusy or now < crackTapReadyAt then return end
	local cut = Config.GeodeCutscene or {}
	clickHint.Visible = false
	crackTapReadyAt = now + (fast and 0.12 or (cut.SwingSeconds or 0.8))
	crackTapCount += 1
	local hitIndex = crackTapCount
	local required = math.max(2, math.floor(tonumber(Config.Geodes.CrackTapCount) or 3))
	local isFinal = crackTapCount >= required
	local token = crackTapToken
	destroyCrackBall()
	if isFinal then crackTapBusy = true end
	playHammerSwing(fast, function()
		if token ~= crackTapToken then return end
		geodeImpact(hitIndex, isFinal)
		if isFinal then
			playGeodeFinale(function()
				if token == crackTapToken then
					crackTapBusy = false
					shakeGeodeForTap(token, true)
				end
			end)
		else
			shakeGeodeForTap(token, false)
			spawnCrackBall()
		end
	end)
end

-- Шарик — простой ImageLabel-билдер (по прямому запросу "сделай
-- имейджлабел билдер"): круглый (UICorner половина), с обводкой, лёгкой
-- пульсацией для заметности, в случайной точке экрана с отступом от
-- краёв (не заезжает за пределы и не прячется под HUD по углам).
spawnCrackBall = function()
	destroyCrackBall()
	-- v20: шарик — клон CrackBallTemplate из билдера (его вид правится в Studio).
	local ballTemplate = opening:FindFirstChild("CrackBallTemplate")
	local ball
	if ballTemplate then
		ball = ballTemplate:Clone()
		ball.Visible = true
	else
		ball = Instance.new("ImageButton")
		ball.BackgroundColor3 = Color3.fromRGB(255, 210, 60)
		ball.ScaleType = Enum.ScaleType.Fit
		ball.ZIndex = 25
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = ball
	end
	ball.Name = "CrackBall"
	ball.AnchorPoint = Vector2.new(0.5, 0.5)
	local size = 92 * DROP_SCALE
	ball.Size = UDim2.fromOffset(size, size)
	local marginX, marginY = 0.16, 0.24
	local x = marginX + math.random() * (1 - marginX * 2)
	local y = marginY + math.random() * (1 - marginY * 2)
	ball.Position = UDim2.fromScale(x, y)
	local ballImage = imageUri(Config.Geodes.Images.CrackBall or 0)
	if ballImage ~= "" then ball.Image = ballImage end
	ball.Parent = opening
	ball.Activated:Connect(function() onCrackHit(false) end)
	activeCrackBall = ball
	TweenService:Create(ball, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Size = UDim2.fromOffset(size * 1.12, size * 1.12),
	}):Play()
	return ball
end

beginCrack = function()
	if not selectedGeodeType or openRequestActive or not state or (state.Geodes[selectedGeodeType] or 0) <= 0 then
		warn(("[GeodeUI] beginCrack прервана на входной проверке: selectedGeodeType=%s openRequestActive=%s state=%s count=%s (диагностика на время бага 'не вижу миниигру')"):format(
			tostring(selectedGeodeType), tostring(openRequestActive), tostring(state ~= nil), tostring(state and selectedGeodeType and state.Geodes[selectedGeodeType])
		))
		return
	end
	if not findOwnCrusher() then
		warn("[GeodeUI] Нельзя открыть жеоду: наковальня не найдена на своём участке.")
		return
	end
	warn("[GeodeUI] beginCrack: старт 3D-сцены раскалывания, gui.Enabled=", gui.Enabled)
	playUiSound("GeodeTap")
	openRequestActive = true
	crackButton.Active = false
	pendingGeodeType = selectedGeodeType
	-- Физически выключаем GeodePrompt на время тапанья (см. серверный
	-- обработчик "SetCrackingPromptEnabled") — раньше его можно было случайно
	-- задеть прямо посреди анимации (легко на телефоне, стоя вплотную к
	-- машине) и сервер прислал бы "OpenVault", выдёргивая из процесса. Теперь
	-- промпт физически не среагирует, пока не закончим (см. closeAll ниже).
	remote:FireServer("SetCrackingPromptEnabled", false)
	vaultPanel.Visible = false
	dimmer.Visible = false
	opening.Visible = true -- нужен видимым как контейнер для CrackTapButton/ClickHint ниже (сам он прозрачный, см. buildFallback) — БАГ ИСПРАВЛЕН: раньше тут стояло false, что визуально прятало вообще всё внутри opening, включая CrackTapButton/ClickHint (Roblox прячет детей вместе с родителем), и мини-игра переставала быть видна/кликабельна целиком.
	resultImage.Visible = false
	resultText.Visible = false
	resultCards.Visible = false
	openCountMenu.Visible = false
	skipButton.Visible = false
	crackTapCount = 0
	crackTapReadyAt = 0
	crackTapBusy = false
	crackTapToken += 1
	tapSequenceCompleted = false
	crackTapButton.Visible = true
	spawnCrackBall()
	crackSequenceActive = true
	clickHint.Visible = true
	-- v10: кнопка «скип» доступна СРАЗУ — она просто дотапывает жеоду за тебя.
	skipButton.Visible = true
	if skipButton:IsA("TextButton") then
		skipButton.Text = "SKIP >"
	elseif skipButtonLabel then
		skipButtonLabel.Text = "SKIP >"
	end

	-- 3D-ПОСТАНОВКА (по прямому запросу — "камера отдаётся и вращается
	-- вокруг игрока медленно, игрок сам не может двигаться, может только
	-- кликать, жеода трясётся и увеличивается"). Старая 2D мини-игра
	-- (яйцо-картинка, которая трясётся/растёт/раскалывается на экране)
	-- убрана целиком — EggImage/CrackGlow/LeftHalf/RightHalf/DropSilhouette
	-- либо не строятся вовсе (см. tools/BuildAllUI.lua), либо всегда
	-- невидимы (EggImage — просто внутренний шаблон под ResultImage).
	stopHammerAnimation()
	if activeGeodeProp then activeGeodeProp:Destroy(); activeGeodeProp = nil end
	lockPlayerMovement()
	-- Жеода ставится СТРОГО НА НАКОВАЛЬНЮ (по прямому запросу), и камера
	-- кружит уже вокруг НЕЁ, а не вокруг игрока — иначе наковальня то и
	-- дело уходила бы из кадра.
	activeGeodeProp, activeAnvil = spawnGeodePropOnAnvil(pendingGeodeType)
	cinematicMode:Fire(true) -- прячем HUD на время раскола
	-- v14: игрок у наковальни, молот в руке, кадр из-за плеча.
	standAtAnvil(activeAnvil)
	attachHammer()
	startOrbitCamera()
	fovTo((Config.GeodeCutscene and Config.GeodeCutscene.FovStart) or Config.Geodes.CameraFOVCracking, Config.Geodes.CameraDollySeconds)

	-- Страховка (на случай ЛЮБОГО другого способа зависнуть, не только
	-- GeodePrompt, см. фикс в remote.OnClientEvent ниже): если за разумное
	-- время сервер так и не прислал ни OpenResult, ни OpenFailed — сами
	-- снимаем блокировку и закрываем зависший оверлей, вместо того чтобы
	-- держать кнопку открытия недоступной до перезахода. crackTapToken в
	-- замыкании — если игрок тем временем НАЧАЛ новую (легитимную) попытку,
	-- токен уже другой, и этот сторож ничего не трогает.
	local watchdogToken = crackTapToken
	task.delay(20, function()
		if crackTapToken == watchdogToken and openRequestActive then
			warn("[GeodeUI] Сервер не ответил на открытие жеоды вовремя — снимаю блокировку самостоятельно.")
			openRequestActive = false
			crackButton.Active = true
			closeAll()
		end
	end)
end

crackButton.Activated:Connect(function()
	if not selectedGeodeType or openRequestActive or not state or (state.Geodes[selectedGeodeType] or 0) <= 0 then return end
	refreshOpenCountMenu()
	openCountMenu.Visible = true
end)

local collectionContext
local collectionContextBackdrop
local renderPodium -- forward-declare: openCollectionContext (ниже) вызывает её раньше, чем она определена по тексту файла
local function closeCollectionContext()
	if collectionContext then collectionContext.Visible = false end
	if collectionContextBackdrop then collectionContextBackdrop.Visible = false end
end

local function openCollectionContext(oreId, entry)
	if collectionContext then collectionContext:Destroy() end
	-- v20: меню — клон шаблона CollectionContextTemplate из билдера
	-- (Shared.GeodeUiBuilder), подложка — CollectionContextBackdrop.
	if not collectionContextBackdrop then
		collectionContextBackdrop = gui:FindFirstChild("CollectionContextBackdrop")
		if collectionContextBackdrop and collectionContextBackdrop:IsA("GuiButton") then
			collectionContextBackdrop.Activated:Connect(closeCollectionContext)
		end
	end
	if collectionContextBackdrop then collectionContextBackdrop.Visible = true end
	local template = gui:FindFirstChild("CollectionContextTemplate")
	if not template then
		template = GeodeUiBuilder.Build():FindFirstChild("CollectionContextTemplate")
	end
	collectionContext = template:Clone()
	collectionContext.Name = "CollectionContext"
	collectionContext.Parent = gui
	local closeButton = collectionContext:FindFirstChild("Close")
	if closeButton then closeButton.Activated:Connect(closeCollectionContext) end
	local confirm = collectionContext:FindFirstChild("ConfirmDelete")
	local cancel = collectionContext:FindFirstChild("CancelDelete")
	local deleteButton = collectionContext:FindFirstChild("Delete")
	local confirmed = false
	if confirm then
		confirm.Activated:Connect(function()
			if confirmed then return end
			confirmed = true
			state.Collection[oreId] = nil
			if state.InstalledOre == oreId then state.InstalledOre = "" end
			remote:FireServer("DeleteOre", oreId)
			closeCollectionContext()
			renderPodium()
		end)
	end
	if cancel then
		cancel.Activated:Connect(function()
			if confirm then confirm.Visible = false end
			cancel.Visible = false
			if deleteButton then deleteButton.Visible = true end
		end)
	end
	for _, actionName in { "Install", "Extract", "Delete" } do
		local actionButton = collectionContext:FindFirstChild(actionName)
		if actionButton then
			actionButton.Activated:Connect(function()
				if actionName == "Install" then
					-- АНТИ-ДАБЛ-КЛИК: флаг блокирует только в пределах окна
					-- кулдауна Config.Geodes.CrystalSwitchCooldown — даже без
					-- ответа сервера кнопка разблокируется сама.
					local now = os.clock()
					if podiumRequestPending and now < podiumSwitchReadyAt then return end
					podiumRequestPending = true
					podiumSwitchReadyAt = now + math.max(0.1, tonumber(Config.Geodes.CrystalSwitchCooldown) or 0.6)
					local installing = state.InstalledOre ~= oreId
					-- Мгновенное локальное обновление, SendState подтвердит.
					state.InstalledOre = installing and oreId or ""
					renderPodium()
					remote:FireServer(installing and "InstallOre" or "RemoveOre", oreId)
					closeCollectionContext()
				elseif actionName == "Extract" then
					local collectionEntry = state.Collection[oreId]
					if collectionEntry then
						if not collectionEntry.Copies or collectionEntry.Copies <= 1 then
							state.Collection[oreId] = nil
							if state.InstalledOre == oreId then state.InstalledOre = "" end
						else
							collectionEntry.Copies -= 1
						end
						renderPodium()
					end
					remote:FireServer("ExtractOre", oreId)
					closeCollectionContext()
				else
					-- Удаление — через подтверждение YES / NO.
					actionButton.Visible = false
					if confirm then confirm.Visible = true end
					if cancel then cancel.Visible = true end
				end
			end)
		end
	end
	local title = collectionContext:FindFirstChild("Title")
	if title then title.Text = (entry.DisplayName or oreId):upper() end
	collectionContext.Visible = true
end

-- ЗНАЧОК МУТАЦИИ ПОВЕРХ ИКОНКИ РУДЫ. Садится в правый нижний угол и занимает
-- треть стороны — так силуэт самого гема остаётся читаемым, а мутация видна
-- сразу, без наведения.
--
-- Мутировавшая руда лежит в ОТДЕЛЬНОЙ ячейке коллекции (см. CollectionKey на
-- сервере), поэтому обычный Quartz и Rusty Quartz — две разные карточки, и
-- значок однозначно относится к своей.
--
-- Только картинка — БЕЗ фона и обводки (см. запрос "убери обводку и задний
-- фон для иконок мутаций"). ImageColor3 красит саму картинку в цвет своей
-- мутации, поэтому даже один и тот же нейтральный by-default белый значок
-- (rbxassetid, залитый одним цветом на белом) для разных мутаций будет
-- выглядеть по-разному — не нужно рисовать 16 разноцветных картинок вручную.
-- Если IconId ещё не проставлен (0 = плейсхолдер), значок просто не рисуется:
-- никакого цветного квадрата-заглушки больше нет, ТОЛЬКО картинка.
local MUTATION_BADGE_FRACTION = 1 / 3

local function applyMutationBadge(icon, mutations)
	for _, existing in icon:GetChildren() do
		if existing.Name == "MutationBadge" then existing:Destroy() end
	end
	if typeof(mutations) ~= "table" or #mutations == 0 then return end

	for index, mutationId in mutations do
		local info = Config.Mutations[mutationId]
		local configured = info and imageUri(info.IconId) or ""
		if info and configured ~= "" then
			local badge = Instance.new("ImageLabel")
			badge.Name = "MutationBadge"
			badge.AnchorPoint = Vector2.new(1, 1)
			-- Смещаем каждый следующий значок влево на свою ширину, чтобы
			-- несколько мутаций не легли друг на друга.
			badge.Position = UDim2.new(1, 0, 1, 0) - UDim2.fromScale(MUTATION_BADGE_FRACTION * (index - 1), 0)
			badge.Size = UDim2.fromScale(MUTATION_BADGE_FRACTION, MUTATION_BADGE_FRACTION)
			badge.SizeConstraint = Enum.SizeConstraint.RelativeXX -- всегда квадрат, как бы ни тянулась карточка
			badge.BackgroundTransparency = 1
			badge.ZIndex = icon.ZIndex + 3
			badge.Image = configured
			badge.ImageColor3 = Color3.new(1, 1, 1)
			badge.ImageTransparency = 0
			badge.Parent = icon
		end
	end
end

-- АВТОСОРТИРОВКА КОЛЛЕКЦИИ НА ПОДИУМЕ: самый дорогой кристалл — первым,
-- самый дешёвый — последним.
--
-- Почему это вообще понадобилось: раньше `state.Collection` — это словарь
-- (ключ вида "Quartz" или "Quartz#Rusty", см. CollectionKey), и карточки
-- создавались обычным обходом `for key, entry in state.Collection`, то есть
-- в НЕОПРЕДЕЛЁННОМ хеш-порядке. Сетка (UIGridLayout) при этом стояла на
-- SortOrder.Name, так что итоговый порядок на экране был алфавитным по
-- внутреннему id руды — к ценности он не имел никакого отношения, и
-- "Amethyst" за копейки лежал выше "Titanheart".
--
-- Ценность считаем по ДОХОДУ (IncomePerMinute) — это ровно то число, что
-- написано на самой карточке ("$X/MIN"), и именно ради него кристалл ставят
-- на подиум. Сервер уже присылает его посчитанным целиком: с учётом уровня
-- (Config.Geodes.IncomePerLevel) и множителя мутации (см. incomeFor в
-- GeodeService), поэтому Rusty-версия руды честно встанет выше своей
-- обычной, а не рядом с ней.
local function crystalSortValue(entry)
	local value = tonumber(entry and entry.IncomePerMinute) or 0
	-- NaN уронил бы table.sort ошибкой "invalid order function" — сравнение
	-- с самим собой это единственный способ его поймать.
	if value ~= value then return 0 end
	return value
end

-- Доп. критерии на случай равного дохода — чтобы карточки не прыгали между
-- перерисовками (сортировка обязана быть строгой и полной, иначе порядок
-- одинаковых по цене кристаллов зависел бы от случайного хеш-порядка):
-- сначала уровень, потом число копий, и в самом конце ключ ячейки как
-- гарантированно уникальный tie-breaker.
local function sortedCollection(collection)
	local list = {}
	for key, entry in collection do
		table.insert(list, { Key = key, Entry = entry })
	end
	table.sort(list, function(a, b)
		local valueA, valueB = crystalSortValue(a.Entry), crystalSortValue(b.Entry)
		if valueA ~= valueB then return valueA > valueB end
		local levelA, levelB = tonumber(a.Entry.Level) or 1, tonumber(b.Entry.Level) or 1
		if levelA ~= levelB then return levelA > levelB end
		local copiesA, copiesB = tonumber(a.Entry.Copies) or 0, tonumber(b.Entry.Copies) or 0
		if copiesA ~= copiesB then return copiesA > copiesB end
		return a.Key < b.Key
	end)
	return list
end

-- Порядок задаётся через LayoutOrder, поэтому сетку нужно переключить с
-- SortOrder.Name. Делаем это в рантайме и ТОЛЬКО для CrystalGrid: тогда
-- сортировка работает и с UI, собранным старым tools/BuildAllUI.lua (там
-- тоже прописан SortOrder.Name), а витрина жеод и магазин продолжают
-- сортироваться как раньше. UIGridStyleLayout — общий базовый класс
-- UIGridLayout и UIListLayout, так что подхватится любой из них.
local crystalGridLayout = crystalGrid:FindFirstChildWhichIsA("UIGridStyleLayout")
if crystalGridLayout then
	crystalGridLayout.SortOrder = Enum.SortOrder.LayoutOrder
else
	warn("[GeodeUI] В CrystalGrid нет UIGridLayout — карточки не будут отсортированы по ценности.")
end

renderPodium = function()
	if not state then return end
	clearCards(crystalGrid, crystalTemplate)
	for index, item in sortedCollection(state.Collection) do
		local oreId, entry = item.Key, item.Entry
		local card = crystalTemplate:Clone()
		card.Name = oreId
		-- Позиция в сетке = место в отсортированном списке. 1 — самый дорогой.
		card.LayoutOrder = index
		card.Visible = true
		local rarityColor = rarityColors[entry.Rarity] or rarityColors.Common
		local slotBackground = card:FindFirstChild("IconBackground", true)
		local backgroundImage = imageUri(Config.Geodes.Images.SlotBackground)
		if backgroundImage ~= "" then slotBackground.Image = backgroundImage end
		slotBackground.ImageColor3 = rarityColor
		slotBackground.BackgroundColor3 = rarityColor
		slotBackground.BackgroundTransparency = slotBackground.Image == "" and 0 or 1
		local icon = card:FindFirstChild("Icon", true)
		local configuredImage = imageUri(entry.ImageId)
		if configuredImage ~= "" then
			icon.Image = configuredImage
			icon.BackgroundTransparency = 1
		else
			icon.BackgroundColor3 = entry.Color or Color3.new(1, 1, 1)
			icon.BackgroundTransparency = 0
		end
		applyMutationBadge(icon, entry.Mutations)
		card:FindFirstChild("Name").Text = ("%s (LVL %d)"):format(entry.DisplayName:upper(), entry.Level or 1)
		card:FindFirstChild("Income").Text = "$" .. NumberFormat.perSecond(entry.IncomePerMinute) .. "/SEC"
		local installedLabel = card:FindFirstChild("Installed")
		if installedLabel then installedLabel.Visible = false end
		-- Рамка «стоит на подиуме» — из шаблона карточки (BankPodiumUiBuilder).
		local selectionFrame = slotBackground:FindFirstChild("SelectionFrame")
		if not selectionFrame then
			selectionFrame = Instance.new("Frame")
			selectionFrame.Name = "SelectionFrame"
			selectionFrame.Position = UDim2.fromOffset(3, 3)
			selectionFrame.Size = UDim2.new(1, -6, 1, -6)
			selectionFrame.BackgroundTransparency = 1
			selectionFrame.ZIndex = slotBackground.ZIndex + 2
			selectionFrame.Parent = slotBackground
			local selectionStroke = Instance.new("UIStroke")
			selectionStroke.Name = "SelectionStroke"
			selectionStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			selectionStroke.Color = Color3.fromRGB(255, 215, 80) -- v9: золото банка
			selectionStroke.Thickness = 3
			selectionStroke.Parent = selectionFrame
		end
		selectionFrame.Visible = state.InstalledOre == oreId
		card.Parent = crystalGrid
		card.Activated:Connect(function() openCollectionContext(oreId, entry) end)
	end
	updateBankIncome()
end

local function resultDetail(result)
	if result.Kind == "Buff" then
		return result.Title or "TEMPORARY BUFF"
	end
	if result.Kind == "Essence" then -- v18
		return "APPLY AT YOUR PODIUM"
	end
	if result.Kind == "Heart" then -- v18
		return ("NEXT GEODE x%d REWARDS"):format(Config.Geodes.Heart.Rewards or 3)
	end
	if result.Kind == "Junk" then -- v17: мусор
		return (tonumber(result.Value) or 0) > 0 and ("JUNK · $%s"):format(NumberFormat.abbreviate(result.Value)) or "JUNK · WORTHLESS"
	end
	return result.Kind == "Money" and (result.Jackpot and "JACKPOT" or "MONEY FOUND")
		or result.Kind == "Geode" and "GOBLIN DROP"
		or result.Kind == "Skin" and (result.Duplicate and "DUPLICATE CONVERTED TO MONEY" or ((result.SkinType or ""):upper() .. " SKIN UNLOCKED"))
		or ((result.Upgraded and ("UPGRADED TO LEVEL %d"):format(result.Level)) or ("$%s/SEC"):format(NumberFormat.perSecond(result.IncomePerMinute)))
end

--------------------------------------------------------------------------------
-- НОТИФИКАЦИЯ ПОДБОРА КАПЛИ (по прямому запросу — "дроп из жеоды должен
-- показываться как нотификейшн справа или слева вылазить"). Своя отдельная
-- ScreenGui, не зависящая от gui.Enabled основного окна GeodeUi — игрок
-- может закрыть окно хранилища и продолжать собирать капли по всей
-- площадке, нотификации должны появляться и после закрытия окна.
--------------------------------------------------------------------------------
local dropNotifyGui = Instance.new("ScreenGui")
dropNotifyGui.Name = "GeodeDropNotifications"
dropNotifyGui.ResetOnSpawn = false
dropNotifyGui.IgnoreGuiInset = true
dropNotifyGui.DisplayOrder = 30
dropNotifyGui.Parent = playerGui

local dropNotifyStack = {}

showDropNotification = function(result)
	-- v18: подобранная капля открывается КАРТОЧКОЙ (shared/RevealCards) —
	-- тот же вид, что у сундуков. Несколько капель подряд — одной пачкой.
	if RevealCards and typeof(result) == "table" then
		RevealCards.Push(result, { Title = "GEODE DROP", Color = Color3.fromRGB(190, 150, 255) })
		return
	end
	local card = Instance.new("Frame")
	card.Name = "DropNotify"
	card.Size = UDim2.fromOffset(260, 74)
	card.BackgroundColor3 = Color3.fromRGB(22, 20, 28)
	card.BackgroundTransparency = 0.05
	card.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = (result and rarityColors[result.Rarity]) or Color3.fromRGB(200, 200, 200)
	stroke.Parent = card

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -20, 0, 26)
	title.Position = UDim2.fromOffset(10, 8)
	require(game:GetService("ReplicatedStorage").Shared.UiKit).StyleText(title, "Heading") -- v20: шрифт темы
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Text = (result and (result.Title or "REWARD") or "REWARD"):upper()
	title.Parent = card

	local detail = Instance.new("TextLabel")
	detail.BackgroundTransparency = 1
	detail.Size = UDim2.new(1, -20, 0, 30)
	detail.Position = UDim2.fromOffset(10, 36)
	require(game:GetService("ReplicatedStorage").Shared.UiKit).StyleText(detail, "Body") -- v20: шрифт темы
	detail.TextScaled = true
	detail.TextXAlignment = Enum.TextXAlignment.Left
	detail.TextColor3 = (result and rarityColors[result.Rarity]) or Color3.fromRGB(220, 220, 220)
	detail.Text = result and resultDetail(result) or ""
	detail.Parent = card

	-- Стопка — несколько подряд подобранных капель не перекрывают друг
	-- друга, каждая следующая появляется чуть ниже предыдущей.
	local index = #dropNotifyStack + 1
	table.insert(dropNotifyStack, card)
	local rowY = 16 + (index - 1) * 82
	local hiddenPos = UDim2.new(1, 20, 0, rowY)
	local shownPos = UDim2.new(1, -276, 0, rowY)
	card.Position = hiddenPos
	card.Parent = dropNotifyGui
	TweenService:Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = shownPos }):Play()
	task.delay(2.6, function()
		if not card.Parent then return end
		local slideOut = TweenService:Create(card, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = hiddenPos })
		slideOut:Play()
		slideOut.Completed:Connect(function()
			card:Destroy()
			local idx = table.find(dropNotifyStack, card)
			if idx then table.remove(dropNotifyStack, idx) end
		end)
	end)
end

local function populateResultCards(results)
	for _, child in resultCards:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	local gridResults = #results > 2
	if gridResults then
		if resultCardsLayout then resultCardsLayout:Destroy() end
		resultCardsLayout = Instance.new("UIGridLayout")
		resultCardsLayout.Name = "CardLayout"
		resultCardsLayout.CellPadding = UDim2.fromOffset(10, 10)
		resultCardsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		resultCardsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		resultCardsLayout.Parent = resultCards
	else
		if resultCardsLayout then resultCardsLayout:Destroy() end
		resultCardsLayout = Instance.new("UIListLayout")
		resultCardsLayout.Name = "CardLayout"
		resultCardsLayout.FillDirection = Enum.FillDirection.Horizontal
		resultCardsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		resultCardsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		resultCardsLayout.Padding = UDim.new(0, 18)
		resultCardsLayout.Parent = resultCards
	end
	local cardWidth = #results == 1 and 300 or gridResults and (#results <= 6 and 155 or 105) or 245
	local cardHeight = gridResults and (#results <= 6 and 175 or 130) or 350
	if gridResults and resultCardsLayout:IsA("UIGridLayout") then
		resultCardsLayout.CellSize = UDim2.fromOffset(cardWidth, cardHeight)
		resultCardsLayout.FillDirectionMaxCells = #results <= 6 and 3 or 5
	end
	for index, result in results do
		-- v20: карточка — клон ResultCardTemplate из билдера (GeodeUiBuilder).
		local cardTemplate = opening:FindFirstChild("ResultCardTemplate")
		local card, image, text
		local imageSize = gridResults and math.max(70, cardWidth - 18) or 220
		if cardTemplate then
			card = cardTemplate:Clone()
			card.Visible = true
			image = card:FindFirstChild("ResultImage")
			text = card:FindFirstChild("ResultText")
		else
			card = Instance.new("Frame")
			card.BackgroundTransparency = 1
			card.ZIndex = 22
			image = Instance.new("ImageLabel")
			image.Name = "ResultImage"
			image.AnchorPoint = Vector2.new(0.5, 0)
			image.BackgroundTransparency = 1
			image.ScaleType = Enum.ScaleType.Fit
			image.ZIndex = 22
			image.Parent = card
			local outline = Instance.new("UIStroke")
			outline.Name = "DropOutline"
			outline.Thickness = 0
			outline.Transparency = 1
			outline.Parent = image
			text = label("ResultText", "")
			text.TextStrokeColor3 = Color3.new(0, 0, 0)
			text.TextStrokeTransparency = 0
			text.ZIndex = 22
			text.Parent = card
		end
		card.Name = "ResultCard" .. index
		card.Size = UDim2.fromOffset(cardWidth, cardHeight)
		card.LayoutOrder = index
		card.Parent = resultCards

		image.Position = UDim2.new(0.5, 0, 0, 8)
		image.Size = UDim2.fromOffset(imageSize, imageSize)
		local configuredImage = imageUri(result.ImageId)
		local rarityTint = rarityColors[result.Rarity] or Color3.new(1, 1, 1)
		local imageStroke = image:FindFirstChild("SkinStroke")
		if imageStroke then imageStroke.Color = rarityTint end
		if configuredImage ~= "" then
			image.Image = configuredImage
			image.BackgroundTransparency = 1
		else
			image.BackgroundColor3 = rarityTint
			image.BackgroundTransparency = 0
		end
		applyMutationBadge(image, result.Mutations)

		text.Position = UDim2.fromOffset(4, gridResults and imageSize + 5 or 232)
		text.Size = UDim2.new(1, -8, 0, gridResults and cardHeight - imageSize - 8 or 108)
		text.TextColor3 = rarityTint
		local mutationLine = result.MutationNames and ("\n" .. result.MutationNames) or ""
		text.Text = (result.Title or "REWARD"):upper() .. mutationLine .. "\n" .. resultDetail(result)
	end
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(800, 520)
	local columns = gridResults and (#results <= 6 and 3 or 5) or #results
	local rows = gridResults and math.ceil(#results / columns) or 1
	local width = #results == 1 and 300 or gridResults and columns * cardWidth + (columns - 1) * 10 or 508
	local height = gridResults and rows * cardHeight + (rows - 1) * 10 or 360
	resultCards.Size = UDim2.fromOffset(width, height)
	resultCardsScale.Scale = math.min(1, (viewport.X - 24) / width, (viewport.Y - 80) / height)
end

function closeAll()
	-- ЗАЩИТА ОТ ПОВТОРНЫХ НАЖАТИЙ (жалоба «надо много раз нажимать, чтобы
	-- закрылось»). Сама анимация закрытия теперь устойчива к повторным
	-- вызовам (см. UiMotion.Close), но closeAll делает и другую работу:
	-- шлёт SetCrackingPromptEnabled на сервер, крутит токены анимаций,
	-- сбрасывает состояние. Прогонять всё это по три раза на каждое
	-- нервное касание незачем — особенно remote, который при частых тапах
	-- превращается в поток вызовов к серверу.
	--
	-- 0.35 с чуть больше полной длительности анимации закрытия (0.17 с),
	-- то есть за окном подавления панель уже гарантированно скрыта, и
	-- следующий закрывающий тап (если игрок успел открыть окно заново)
	-- отработает нормально.
	local now = os.clock()
	if now - (lastCloseAllAt or 0) < 0.35 then return end
	lastCloseAllAt = now

	unlockCameraForOpening() -- см. lockCameraForOpening — closeAll это ЕДИНАЯ гарантированная точка выхода (см. комментарий чуть ниже), значит и единственное безопасное место для разморозки
	destroyCrackBall()
	stopOrbitCamera()
	releaseCutscene()
	unlockPlayerMovement()
	crackSequenceActive = false
	stopHammerAnimation()
	if activeGeodeProp then
		activeGeodeProp:Destroy()
		activeGeodeProp = nil
	end
	activeAnvil = nil
	for _, prop in scatterProps do
		if prop.Parent then prop:Destroy() end
	end
	table.clear(scatterProps)
	-- v10 ФИКС: возвращаем HUD. Раньше катсценный режим снимался только в
	-- returnCrackCamera, и при выходе через closeAll (скип, OpenFailed,
	-- сторож) интерфейс оставался скрытым — «пропало уи после жеоды».
	cinematicMode:Fire(false)
	closeCollectionContext()
	dimmer.Visible = false
	openCountMenu.Visible = false
	goblinResultActive = false
	animationToken += 1
	crackTapToken += 1
	crackTapButton.Visible = false
	clickHint.Visible = false
	crackTapBusy = false
	crackTapCount = 0
	podiumRequestPending = false
	opening.Visible = false
	resultCards.Visible = false
	pendingGeodeType = nil
	-- Обратно включаем GeodePrompt (см. crackButton.Activated выше) — это
	-- единая точка выхода для ВСЕХ путей (успешное открытие, OpenFailed,
	-- кнопка "скип", watchdog-сторож), так что промпт гарантированно не
	-- останется выключенным навсегда. Идемпотентно — если промпт и так был
	-- включён (закрыли не через раскалывание, а просто панель), ничего не
	-- меняется.
	remote:FireServer("SetCrackingPromptEnabled", true)
	local activePanel = vaultPanel.Visible and vaultPanel
		or (podiumPanel.Visible and podiumPanel)
		or (buyGeodesPanel and buyGeodesPanel.Visible and buyGeodesPanel)
		or nil
	if activePanel then
		UiMotion.Close(activePanel, function()
			local stillOpen = vaultPanel.Visible or podiumPanel.Visible or (buyGeodesPanel and buyGeodesPanel.Visible)
			if not stillOpen then gui.Enabled = false end
		end)
	else
		gui.Enabled = false
	end
end

local function finishOpening(token)
	if token ~= animationToken then return end
	animationSeen = true
	task.wait(tonumber(Config.Geodes.ResultDisplayDuration) or 3)
	if token == animationToken then closeAll() end
end

local function showResult(payload, newState)
	local bundled = typeof(payload) == "table" and typeof(payload.Results) == "table"
	local results = bundled and payload.Results or { payload }
	local result = results[1]
	if not result then return end
	goblinResultActive = not bundled and result.GoblinDrop == true

	-- 3D-ПОСТАНОВКА: раскол декоративной жеоды + разлёт декоративных
	-- цветных капель дропа (см. playCrackAndScatter выше) — только для
	-- обычного открытия через crackButton (не для GoblinDrop, тот вообще
	-- не проходит через beginCrack). Награды УЖЕ начислены сервером к
	-- этому моменту — тут только красиво показываем.
	stopHammerAnimation()
	if not goblinResultActive and crackSequenceActive then
		playCrackAndScatter(activeGeodeProp, results)
		activeGeodeProp = nil
	elseif geodeCameraLocked then
		returnCrackCamera()
	end

	openRequestActive = false
	crackTapButton.Visible = false
	destroyCrackBall()
	clickHint.Visible = false
	gui.Enabled = true
	state = newState or state
	if goblinResultActive then
		dimmer.Visible = false
		vaultPanel.Visible = false
		podiumPanel.Visible = false
		if buyGeodesPanel then buyGeodesPanel.Visible = false end
		opening.BackgroundTransparency = 1
	else
		dimmer.Visible = false
	end
	animationToken += 1
	local token = animationToken

	-- ПО ПРЯМОМУ ЗАПРОСУ: обычное открытие через наковальню (не GoblinDrop)
	-- больше НЕ показывает ни вспышку/VFX открытия, ни карточки результата
	-- сразу после раскола — "дроп вообще не должен показываться после
	-- жеоды, только после поднятия". Сами награды разлетаются декоративными
	-- каплями (см. playCrackAndScatter выше, оно уже вызвано раньше в этой
	-- функции) и КАЖДАЯ капля по отдельности показывает, что в ней было,
	-- только когда игрок её физически подберёт (см. Heartbeat-подбор —
	-- всплывающая нотификация сбоку экрана, см. showDropNotification).
	if goblinResultActive then
		opening.Visible = true
		skipButton.Visible = animationSeen
		if skipButton:IsA("TextButton") then
			skipButton.Text = "CLICK TO CLOSE"
		elseif skipButtonLabel then
			skipButtonLabel.Text = "CLICK TO CLOSE"
		end
		playUiSound("GeodeDrop")
		emitDropVfx(rarityColors[result.Rarity] or Color3.new(1, 1, 1))
		task.spawn(function()
			flash.BackgroundTransparency = 1
			TweenService:Create(flash, TweenInfo.new(0.08), { BackgroundTransparency = 0 }):Play()
			task.wait(0.09)
			if token ~= animationToken then return end
			TweenService:Create(flash, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
			local configuredImage = imageUri(result.ImageId)
			if configuredImage ~= "" then
				resultImage.Image = configuredImage
				resultImage.BackgroundTransparency = 1
			else
				resultImage.Image = ""
				resultImage.BackgroundColor3 = rarityColors[result.Rarity] or Color3.new(1, 1, 1)
				resultImage.BackgroundTransparency = 0
			end
			resultImage.Visible = true
			resultImage.Size = UDim2.fromOffset(20, 20)
			resultText.TextColor3 = rarityColors[result.Rarity] or Color3.new(1, 1, 1)
			resultOutline.Thickness = 0
			resultOutline.Transparency = 1
			applyMutationBadge(resultImage, result.Mutations)
			local mutationLine = result.MutationNames and ("\n" .. result.MutationNames) or ""
			resultText.Text = (result.Title or "REWARD"):upper() .. mutationLine .. "\n" .. resultDetail(result)
			resultText.Visible = true
			TweenService:Create(resultImage, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = dropSize(250) }):Play()
			finishOpening(token)
		end)
	else
		opening.Visible = false
		resultImage.Visible = false
		resultText.Visible = false
		resultCards.Visible = false
		animationSeen = true
		-- Небольшая пауза — дать доиграть звуку раскола/разлёту капель,
		-- прежде чем закрыть окно хранилища и вернуть игрока в игру (сами
		-- капли и вращение камеры продолжают жить своей жизнью, см.
		-- playCrackAndScatter/returnCrackCamera — окно им не мешает).
		task.delay(0.4, function()
			if token == animationToken then closeAll() end
		end)
	end
end

vaultPanel.CloseButton.Activated:Connect(closeAll)

--------------------------------------------------------------------------------
-- ФИКС «НА ТЕЛЕФОНЕ НЕ НАЖИМАЕТСЯ КРЕСТИК, ИЗ МЕНЮ НЕ ВЫЙТИ»
--
-- ПРИЧИНА. Dimmer — это НЕ Frame, а полноэкранный TextButton
-- (Size = UDim2.fromScale(1, 1), см. buildFallback выше и одноимённый
-- элемент в собранном в Studio GeodeUi). Кнопка на весь экран поглощает
-- КАЖДОЕ касание в своей области, а ZIndex ей никто никогда не выставлял —
-- то есть он равен 1 по умолчанию. Если у панели или у её крестика в
-- Studio-ассете ZIndex тоже оставлен по умолчанию (а это самый обычный
-- случай — дизайнер просто не трогает это поле), то Dimmer оказывается с
-- ними НА ОДНОМ УРОВНЕ и выигрывает по порядку потомков: он добавлен в
-- gui позже панелей. Итог — крестик видно, он подсвечивается, но нажатие
-- до него не доходит. На мышке это иногда «проскакивает» из-за разной
-- точки попадания, на тач-экране палец толще и промахивается стабильно —
-- поэтому баг и воспроизводится только на телефоне.
--
-- ЛЕЧИМ ДВУМЯ СПОСОБАМИ СРАЗУ, потому что вёрстка панелей живёт в Studio
-- и полагаться на одно предположение о ней нельзя:
--
--   1) ZIndex затемнения ПРИНУДИТЕЛЬНО опускается ниже всех соседей.
--      После этого ни один слой панели не может быть им перекрыт, каким
--      бы ZIndex его ни наделили в Studio.
--
--   2) Само затемнение становится кнопкой «закрыть» — тап мимо панели
--      закрывает меню. Это стандартное поведение модальных окон и,
--      главное, огромная и промахонеустойчивая цель для пальца: даже если
--      крестик по какой-то ещё причине окажется недоступен, игрок больше
--      не может застрять в меню (жалоба «зависла, оттуда никак не выйти,
--      даже если сдохнуть»).
--------------------------------------------------------------------------------
local function normalizeDimmerLayer()
	-- ВТОРАЯ ЧАСТЬ ЗАЩИТЫ КРЕСТИКА: поднимаем сам крестик над всем
	-- содержимым СВОЕЙ панели. Затемнение мы опускаем ниже панелей (ниже),
	-- но внутри панели крестик тоже может оказаться перекрыт — например,
	-- декоративной рамкой или шапкой, нарисованной в Studio позже него.
	-- Снаружи это выглядит одинаково: «крестик видно, нажатие не проходит».
	for _, panel in { vaultPanel, podiumPanel, buyGeodesPanel } do
		local closeButton = panel and panel:FindFirstChild("CloseButton", true)
		if closeButton and closeButton:IsA("GuiObject") then
			local highest = closeButton.ZIndex
			for _, descendant in panel:GetDescendants() do
				if descendant:IsA("GuiObject") and descendant ~= closeButton then
					highest = math.max(highest, descendant.ZIndex)
				end
			end
			if closeButton.ZIndex <= highest then
				closeButton.ZIndex = highest + 1
			end
		end
	end

	if not dimmer or not dimmer:IsA("GuiObject") then return end
	local lowest = nil
	for _, sibling in gui:GetChildren() do
		if sibling ~= dimmer and sibling:IsA("GuiObject") then
			lowest = lowest and math.min(lowest, sibling.ZIndex) or sibling.ZIndex
		end
	end
	-- -1 гарантирует строгое «ниже», даже если у самой нижней панели ZIndex 0.
	dimmer.ZIndex = (lowest or 1) - 1
end
normalizeDimmerLayer()
-- Панели могут досоздаваться позже (см. buyGeodesPanel — необязательный
-- элемент контракта), поэтому пересчитываем при появлении новых соседей.
gui.ChildAdded:Connect(function()
	task.defer(normalizeDimmerLayer)
end)

if dimmer:IsA("GuiButton") then
	dimmer.Activated:Connect(function()
		-- Во время анимации вскрытия жеоды закрывать нельзя: игрок ещё не
		-- увидел награду, а closeAll оборвал бы сцену на середине. Ровно то
		-- же условие, что и у skipButton ниже.
		if opening.Visible and not (animationSeen or goblinResultActive) then return end
		closeAll()
	end)
end

-- Всплеск при покупке жеоды за Robux — та же самая "финальная" часть
-- анимации, что и при обычном открытии жеоды (вспышка + плашка с иконкой,
-- влетающая с Back-easing), но БЕЗ тряски/раскалывания: жеода тут не
-- открывается ради награды, она просто добавляется в хранилище, поэтому
-- показываем не рандомный дроп, а саму купленную жеоду.
local function showGeodePurchasePop(geodeType)
	local geodeInfo = Config.Geodes.Types[geodeType]
	if not geodeInfo or openRequestActive then return end
	animationToken += 1
	local token = animationToken
	gui.Enabled = true
	opening.Visible = true
	resultCards.Visible = false
	skipButton.Visible = false
	crackTapButton.Visible = false
	clickHint.Visible = false
	eggImage.Visible = false
	if leftHalf then leftHalf.Visible = false end
	if rightHalf then rightHalf.Visible = false end
	if crackGlow then crackGlow.Visible = false end
	if dropSilhouette then dropSilhouette.Visible = false end
	resultImage.Visible = false
	applyMutationBadge(resultImage, nil)
	resultText.Visible = false
	playUiSound("GeodeReveal")
	emitDropVfx(rarityColors[geodeInfo.Rarity] or geodeInfo.Color or Color3.new(1, 1, 1))
	task.spawn(function()
		flash.BackgroundTransparency = 1
		TweenService:Create(flash, TweenInfo.new(0.08), { BackgroundTransparency = 0 }):Play()
		task.wait(0.09)
		if token ~= animationToken then return end
		local rarityColor = rarityColors[geodeInfo.Rarity] or geodeInfo.Color
		local configuredImage = imageUri(Config.Geodes.Images[geodeType])
		if configuredImage ~= "" then
			resultImage.Image = configuredImage
			resultImage.BackgroundTransparency = 1
		else
			resultImage.Image = ""
			resultImage.BackgroundColor3 = rarityColor
			resultImage.BackgroundTransparency = 0
		end
		resultImage.Visible = true
		resultImage.Size = UDim2.fromOffset(20, 20)
		resultText.TextColor3 = rarityColor
		resultText.Text = geodeInfo.DisplayName:upper() .. "\nPURCHASED -- ADDED TO STORAGE"
		resultText.Visible = true
		TweenService:Create(flash, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(resultImage, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = dropSize(250) }):Play()
		task.wait(tonumber(Config.Geodes.ResultDisplayDuration) or 3)
		if token ~= animationToken then return end
		-- В отличие от finishOpening/closeAll, тут НЕ закрываем VaultPanel/
		-- BuyGeodesPanel — это всплеск ПОВЕРХ того, что уже открыто (или
		-- поверх игры, если ничего не открыто), а не отдельный экран.
		opening.Visible = false
		resultImage.Visible = false
		resultText.Visible = false
		local stillOpen = vaultPanel.Visible or podiumPanel.Visible or (buyGeodesPanel and buyGeodesPanel.Visible)
		if not stillOpen then gui.Enabled = false end
	end)
end

-- Покупку жеоды подтверждает сервер (ProcessReceipt), но это может занять
-- пару секунд — без обратной связи игрок может решить, что покупка не
-- прошла, и попытаться купить снова. PromptProductPurchaseFinished летит
-- клиенту сразу после закрытия окна оплаты Roblox — используем его для
-- МГНОВЕННОГО (оптимистичного) обновления счётчика "OWNED x_" и всплеска,
-- не дожидаясь настоящего SendState с сервера. Само событие в Roblox не
-- доверенное (клиент теоретически может подделать isPurchased), но здесь
-- это не проблема: реальная выдача жеоды всё равно только в ProcessReceipt
-- на сервере — тут мы только рисуем, ничего не начисляем по-настоящему.
MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
	if not isPurchased or userId ~= player.UserId then return end
	local purchasedGeodeType
	for geodeType, pack in Config.DevProducts.GeodePacks or {} do
		if pack.Id ~= 0 and pack.Id == productId then
			purchasedGeodeType = geodeType
			break
		end
	end
	if not purchasedGeodeType then return end
	if state then
		state.Geodes = state.Geodes or {}
		state.Geodes[purchasedGeodeType] = (tonumber(state.Geodes[purchasedGeodeType]) or 0) + 1
	end
	if buyGeodesPanel and buyGeodesPanel.Visible and renderBuyGeodes then renderBuyGeodes() end
	if vaultPanel.Visible then renderVault() end
	showGeodePurchasePop(purchasedGeodeType)
end)

podiumPanel.CloseButton.Activated:Connect(closeAll)
-- v10: во время раскола «скип» дотапывает жеоду мгновенно, после раскола —
-- закрывает окно результата, как раньше.
local skipBusy = false
skipButton.Activated:Connect(function()
	if animationSeen or goblinResultActive then
		closeAll()
		return
	end
	if not (crackSequenceActive and openRequestActive) or skipBusy then return end
	skipBusy = true
	local token = crackTapToken
	task.spawn(function()
		for _ = 1, (tonumber(Config.Geodes.CrackTapCount) or 5) + 2 do
			if crackTapToken ~= token or not crackSequenceActive or not openRequestActive then break end
			crackTapReadyAt = 0 -- пропускаем задержку между засчитанными ударами
			onCrackHit(true)
			task.wait(0.05)
		end
		skipBusy = false
	end)
end)

remote.OnClientEvent:Connect(function(command, payload, newState)
	-- БАГ, КОТОРЫЙ ЧИНИМ: GeodePrompt (проксимити-промпт у хранилища,
	-- кликабельный мгновенно, без удержания — легко задеть на телефоне,
	-- стоя вплотную к машине, что игрок и так делает во время раскалывания)
	-- шлёт "OpenVault"
	-- КАЖДЫЙ раз при срабатывании, не проверяя, не открывает ли этот игрок
	-- прямо сейчас жеоду. Раньше "OpenVault"/"OpenPodium" безусловно прятали
	-- opening-оверлей (opening.Visible = false), но НЕ сбрасывали
	-- openRequestActive — а он снимается только по OpenResult/OpenFailed,
	-- которые приходят ТОЛЬКО после завершения тап-последовательности и
	-- реального запроса "OpenGeode" на сервер. Если игрока выдернуло из
	-- оверлея раньше, чем он дотапал, openRequestActive застревал в true
	-- НАВСЕГДА — дальше crackButton.Activated просто молча ничего не делал
	-- до перезахода. Фикс: пока реально идёт раскалывание — просто
	-- игнорируем эти пуши, не прерывая процесс; игрок довершает тап-серию
	-- как ни в чём не бывало, и может открыть хранилище заново сам, когда
	-- закончит.
	if openRequestActive and (command == "OpenVault" or command == "OpenPodium") then
		return
	end
	if command == "OpenVault" then
		playUiSound("UiMenuOpen")
		state = payload
		renderVault()
		gui.Enabled = true
		-- Окно открылось заново — снимаем окно подавления повторных
		-- закрытий (см. closeAll), иначе первый же тап по крестику сразу
		-- после переоткрытия мог быть проглочен как «дребезг».
		lastCloseAllAt = 0
		dimmer.Visible = true
		podiumPanel.Visible = false
		if buyGeodesPanel then buyGeodesPanel.Visible = false end
		opening.Visible = false
		UiMotion.Open(vaultPanel)
	elseif command == "OpenPodium" then
		playUiSound("UiMenuOpen")
		state = payload
		podiumRequestPending = false
		renderPodium()
		gui.Enabled = true
		-- Окно открылось заново — снимаем окно подавления повторных
		-- закрытий (см. closeAll), иначе первый же тап по крестику сразу
		-- после переоткрытия мог быть проглочен как «дребезг».
		lastCloseAllAt = 0
		dimmer.Visible = true
		vaultPanel.Visible = false
		if buyGeodesPanel then buyGeodesPanel.Visible = false end
		opening.Visible = false
		UiMotion.Open(podiumPanel)
	elseif command == "State" then
		state = payload
		podiumRequestPending = false
		if vaultPanel.Visible then renderVault() end
		if podiumPanel.Visible then renderPodium() end
		if renderBuyGeodes and buyGeodesPanel and buyGeodesPanel.Visible then renderBuyGeodes() end
	elseif command == "PodiumState" then
		state = payload
		podiumRequestPending = false
		if podiumPanel.Visible then renderPodium() end
		elseif command == "OpenResult" then
			showResult(payload, newState)
		elseif command == "GoblinResult" then
			showResult(payload, state)
	elseif command == "OpenFailed" then
		openRequestActive = false
		closeAll()
	end
end)

remote:FireServer("RequestState")
