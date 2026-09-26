--------------------------------------------------------------------------------
-- MerchantUI (LocalScript) — окно лавки торговца, панель зелий, табло биржи.
--
-- Геометрия — MerchantUiBuilder (собирается здесь, если в PlayerGui нет
-- готовой). Данные:
--   • workspace-атрибуты MarketMultiplier/MarketBucket/MerchantRestockAt —
--     курс и таймер (общие для сервера, обновляются без запросов);
--   • RemoteEvent MerchantState — личный снимок: остаток стока, цены по
--     тирам игрока, запас зелий; команды "Open" и "Restocked";
--   • RemoteFunction MerchantRequest — Buy.
-- Зелья после покупки лежат в инвентаре как снаряжение (GearService) —
-- отдельной панели у лавки нет.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Localization = require(ReplicatedStorage.Shared.Localization)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local MerchantUiBuilder = require(ReplicatedStorage.Shared.MerchantUiBuilder)

local UiSfx = nil
pcall(function() UiSfx = require(ReplicatedStorage.Shared.UiSfx) end)

local CFG = Config.Merchant
if not (CFG and CFG.Enabled) then return end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local shared = ReplicatedStorage:WaitForChild("Shared")
local stateRemote = shared:WaitForChild("MerchantState", 30)
local requestRemote = shared:WaitForChild("MerchantRequest", 30)
if not (stateRemote and requestRemote) then
	warn("[MerchantUI] Нет remotes торговца - сервис не запущен?")
	return
end

local function tr(text, args)
	if not text then return "" end
	local ok, translated = pcall(Localization.Translate, player.LocaleId, text, args)
	return ok and translated or text
end

local function sfx(name)
	if UiSfx then pcall(UiSfx.play, name) end
end

local function getGui(name, build)
	local gui = playerGui:FindFirstChild(name)
	if not gui then
		gui = build()
		gui.Parent = playerGui
	end
	return gui
end

-- v20: оба экрана собираются билдером (StarterGui/MerchantUi, MarketTicker).
local UiRegistry = require(ReplicatedStorage.Shared.UiRegistry)
local UiKit = require(ReplicatedStorage.Shared.UiKit)
local gui = UiRegistry.Get("MerchantUi") or getGui("MerchantUi", MerchantUiBuilder.Build)
local tickerGui = UiRegistry.Get("MarketTicker") or getGui("MarketTicker", MerchantUiBuilder.BuildMarketTicker)
-- v20.19: плашка курса сверху экрана выключена СРАЗУ (раньше строка стояла
-- ниже и не срабатывала, если что-то выше падало). Курс — над торговцем.
tickerGui.Enabled = CFG.ShowTicker == true

local window = gui.Window
local header = window.Header
local marketBar = window.Market
local list = window.Body.List
local template = list.ItemTemplate
local openScale = window:FindFirstChild("OpenScale")

local tickerPill = tickerGui.Pill
-- Включить плашку курса обратно: Config.Merchant.ShowTicker = true.

--------------------------------------------------------------------------------
-- ОБЩЕЕ
--------------------------------------------------------------------------------
local ROW_CLOSED = 118
local ROW_OPEN = 214

local function bucketInfo(bucketId)
	for _, bucket in CFG.Market.Buckets do
		if bucket.Id == bucketId then return bucket end
	end
	return CFG.Market.Buckets[3]
end

local function secondsLeft()
	local restockAt = workspace:GetAttribute("MerchantRestockAt") or 0
	return math.max(0, math.floor(restockAt - workspace:GetServerTimeNow()))
end

local function formatLong(seconds)
	return ("%dm %02ds"):format(seconds // 60, seconds % 60)
end

local function formatShort(seconds)
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

local function pop(scaleObject, from)
	if not scaleObject then return end
	scaleObject.Scale = from or 1.15
	TweenService:Create(scaleObject, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function rarityColor(rarity)
	return CFG.RarityColors[rarity] or (Config.Relics and Config.Relics.RarityColors and Config.Relics.RarityColors[rarity]) or Color3.fromRGB(170, 170, 170)
end

--------------------------------------------------------------------------------
-- v14: ВКЛАДКИ (SHOP / BASE / RELICS). Строки строятся из снимка сервера —
-- товары цикла (тотемы, декор, лимитка) каждый рестрок новые.
--------------------------------------------------------------------------------
local body = window.Body
local tabsBar = window:FindFirstChild("Tabs")
if not tabsBar then
	tabsBar = Instance.new("Frame")
	tabsBar.Name = "Tabs"
	tabsBar.BackgroundTransparency = 1
	tabsBar.Size = UDim2.new(1, -24, 0, 38)
	tabsBar.Position = UDim2.fromOffset(12, 146)
	tabsBar.Parent = window
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 8)
	tabLayout.Parent = tabsBar
	body.Position = UDim2.fromOffset(12, 190)
	body.Size = UDim2.new(1, -24, 1, -202)
end

local currentTab = "Shop"
local tabButtons = {}
local lastState = nil
local rows = {} -- [itemId] = { Frame, Data }
local expandedId = nil
local busy = false
local renderList -- forward

local function makeTabButton(tab)
	-- Кнопка из билдера (StarterGui) — только подключаем клик.
	local existing = tabsBar:FindFirstChild(tab.Id)
	if existing and existing:IsA("GuiButton") then
		local label = existing:FindFirstChild("Label")
		if label then label.Text = tr(tab.Label) end
		existing.MouseButton1Click:Connect(function()
			sfx("UiButtonClick")
			currentTab = tab.Id
			renderList()
		end)
		tabButtons[tab.Id] = existing
		return
	end
	local b = Instance.new("TextButton")
	b.Name = tab.Id
	b.Text = ""
	b.AutoButtonColor = true
	b.Size = UDim2.fromOffset(130, 36)
	b.BackgroundColor3 = Color3.fromRGB(86, 46, 22)
	b.BorderSizePixel = 0
	b.Parent = tabsBar
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
	local s = Instance.new("UIStroke")
	s.Thickness = 2.5
	s.Color = Color3.fromRGB(50, 24, 10)
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = b
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(0.9, 0.75)
	l.Position = UDim2.fromScale(0.05, 0.125)
	require(game:GetService("ReplicatedStorage").Shared.UiKit).StyleText(l, "Heading") -- v20: шрифт темы
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Text = tr(tab.Label)
	l.Parent = b
	Instance.new("UIStroke", l).Thickness = 2
	b.MouseButton1Click:Connect(function()
		sfx("UiButtonClick")
		currentTab = tab.Id
		renderList()
	end)
	tabButtons[tab.Id] = b
end
for _, tab in CFG.Tabs or { { Id = "Shop", Label = "SHOP" } } do makeTabButton(tab) end

local function setExpanded(itemId)
	expandedId = itemId
	for id, row in rows do
		local open = id == itemId
		TweenService:Create(row.Frame, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
			Size = UDim2.new(1, -18, 0, open and ROW_OPEN or ROW_CLOSED),
		}):Play()
	end
end

local function paintBuy(row, message, color)
	local buy = row.Frame.BuyRow.Buy
	buy.Label.Text = message
	buy.BackgroundColor3 = color
end

-- v20.28: бонусы кирки цветом + сравнение с надетой.
local function buffText(data)
	local equipped = lastState and lastState.EquippedSkin or ""
	local mine = (equipped ~= "" and equipped ~= data.SkinId and Config.SkinBuffs and Config.SkinBuffs[equipped]) or {}
	local lines = {}
	for stat, value in data.Buffs do
		table.insert(lines, { stat, value })
	end
	table.sort(lines, function(a, b) return a[2] > b[2] end)
	local parts = {}
	for _, line in lines do
		local stat, value = line[1], line[2]
		local info = Config.SkinStats and Config.SkinStats[stat]
		local text = ("%s%d%% %s"):format(value >= 0 and "+" or "-", math.floor(math.abs(value) * 100 + 0.5), tr(info and info.Label or stat))
		local color = value >= 0 and "#78FF96" or "#FF7070"
		local compare = ""
		local now = tonumber(mine[stat])
		if now then
			compare = (' <font color="#B4B4C8">(%s%d%%)</font>'):format(now >= 0 and "+" or "-", math.floor(math.abs(now) * 100 + 0.5))
		end
		table.insert(parts, ('<font color="%s">%s</font>%s'):format(color, text, compare))
	end
	local role = Config.SkinRoles and Config.SkinRoles[data.SkinId]
	return (role and ('<font color="#FFE6AA">%s:</font> '):format(tr(role):upper()) or "") .. table.concat(parts, "  ")
end

local function ensureRowExtras(row)
	local main = row.Frame.Main
	local star = main:FindFirstChild("Wish")
	if not star then
		star = Instance.new("TextButton")
		star.Name = "Wish"
		star.AnchorPoint = Vector2.new(1, 0)
		star.Position = UDim2.new(1, -10, 0, 8)
		star.Size = UDim2.fromOffset(36, 36)
		star.BackgroundTransparency = 1
		star.Text = "⭐"
		star.TextScaled = true
		star.ZIndex = 8
		star:SetAttribute("DisableGlobalHover", true)
		star.Parent = main
		local name = main:FindFirstChild("Name")
		if name then name.Size = UDim2.new(1, -180, name.Size.Y.Scale, name.Size.Y.Offset) end
		star.MouseButton1Click:Connect(function()
			local current = row.Data
			if not current then return end
			sfx("UiButtonClick")
			local ok, success, reason = pcall(function() return requestRemote:InvokeServer("Wish", current.Id) end)
			if not (ok and success) and ok and reason then
				sfx("UiError")
			end
		end)
	end
	local deal = main:FindFirstChild("DealBadge")
	if not deal then
		deal = Instance.new("TextLabel")
		deal.Name = "DealBadge"
		deal.AnchorPoint = Vector2.new(1, 1)
		deal.Position = UDim2.new(1, -12, 1, -54)
		deal.Size = UDim2.fromOffset(150, 26)
		deal.BackgroundTransparency = 1 -- v20.30: без подложки, только текст
		UiKit.StyleText(deal, "Heading")
		deal.TextScaled = true
		deal.TextColor3 = Color3.fromRGB(255, 80, 95)
		deal.ZIndex = 8
		deal.Parent = main
	end
	return star, deal
end

local function refreshRow(itemId)
	local row = rows[itemId]
	local data = row and row.Data
	if not data then return end
	local main = row.Frame.Main
	local star, dealBadge = ensureRowExtras(row)
	star.TextTransparency = data.Wished and 0 or 0.7
	dealBadge.Visible = data.Deal ~= nil
	dealBadge.Text = data.Deal and ("DEAL -%d%%"):format(data.Deal) or ""
	main.Stock.Text = tr("X{count} Stock", { count = data.Stock })
	main.Price.RichText = true
	if data.Deal and data.OldPrice then
		main.Price.Text = ('<font color="#A0A0A0"><s>$%s</s></font>  $%s'):format(NumberFormat.abbreviate(data.OldPrice), NumberFormat.abbreviate(data.Price))
	else
		main.Price.Text = "$" .. NumberFormat.abbreviate(data.Price)
	end
	local soldOut = data.Stock <= 0
	main.Stock.TextColor3 = soldOut and Color3.fromRGB(255, 110, 110) or Color3.fromRGB(205, 205, 205)
	main.IconBox.Icon.ImageTransparency = soldOut and 0.55 or 0
	main.IconBox.Emoji.TextTransparency = soldOut and 0.55 or 0
	-- v20.27: не в стоке — вся строка слегка темнее (товар виден, но не купить).
	local shade = row.Frame:FindFirstChild("SoldOutShade")
	if not shade then
		shade = Instance.new("Frame")
		shade.Name = "SoldOutShade"
		shade.BackgroundColor3 = Color3.new(0, 0, 0)
		shade.BorderSizePixel = 0
		shade.Size = UDim2.fromScale(1, 1)
		shade.ZIndex = 50
		shade.Active = false
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = shade
		shade.Parent = row.Frame
	end
	shade.BackgroundTransparency = soldOut and 0.5 or 1
	shade.Visible = soldOut
	if data.Lock then
		paintBuy(row, tr(data.Lock), Color3.fromRGB(120, 120, 120))
	elseif soldOut then
		paintBuy(row, tr("NO STOCK"), Color3.fromRGB(200, 50, 50))
		main.Stock.Text = tr("NO STOCK")
	else
		paintBuy(row, tr("BUY") .. "  $" .. NumberFormat.abbreviate(data.Price), Color3.fromRGB(60, 200, 60))
	end
	local effect = row.Frame:FindFirstChild("Effect")
	if effect then
		if data.Buffs then
			effect.RichText = true
			effect.TextWrapped = true
			effect.Size = UDim2.new(1, -24, 0, 30)
			effect.Text = buffText(data)
		else
			effect.RichText = false
			effect.Text = tr(data.Effect or "")
		end
	end
end

-- v20.29: СУНДУК ЦИКЛА — самая заметная карточка (как верхняя в магазине):
-- подсветка цветом редкости, мерцающая рамка, лучи за 3D-сундуком,
-- лента FEATURED и покачивающиеся монетки.
local function decorateFeatured(frame, data)
	local RunService = game:GetService("RunService")
	local color = rarityColor(data.Rarity)
	local main = frame.Main
	local iconBox = main.IconBox

	-- Подсветка цветом редкости: слой под содержимым (Main — ZIndex 3).
	local glow = Instance.new("Frame")
	glow.Name = "FeaturedGlow"
	glow.BorderSizePixel = 0
	glow.Size = UDim2.fromScale(1, 1)
	glow.BackgroundColor3 = color
	glow.BackgroundTransparency = 0.55
	glow.ZIndex = 2
	local glowGradient = Instance.new("UIGradient")
	glowGradient.Rotation = 0
	glowGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.5, 0.6), NumberSequenceKeypoint.new(1, 0.25),
	})
	glowGradient.Parent = glow
	local corner = frame:FindFirstChildOfClass("UICorner")
	if corner then corner:Clone().Parent = glow end
	glow.Parent = frame
	-- Блик пробегает по карточке.
	TweenService:Create(glowGradient, TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Offset = Vector2.new(0.25, 0) }):Play()
	glowGradient.Offset = Vector2.new(-0.25, 0)

	local stroke = frame:FindFirstChild("SkinStroke") or frame:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke", frame)
	stroke.Thickness = 3
	stroke.Color = color
	TweenService:Create(stroke, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Color = Color3.fromRGB(255, 245, 200) }):Play()

	-- Фон за иконкой — картинка по редкости сундука (UiTheme.RarityBackdrop).
	local rays = UiKit.Backdrop(iconBox, "FeaturedRays", data.ChestRarity or data.Rarity, {
		Size = UDim2.fromScale(1.7, 1.7),
		Color = color:Lerp(Color3.new(1, 1, 1), 0.3),
		Transparency = 0.1,
		ZIndex = 1,
	})

	-- 3D-сундук выпавшей редкости вместо эмодзи, медленно крутится.
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "ChestView"
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.ZIndex = 4
	viewport.Parent = iconBox
	local model = nil
	pcall(function()
		model = require(ReplicatedStorage.Shared.PlaceableFactory).BuildChest(data.ChestRarity)
	end)
	if model then
		iconBox.Emoji.Text = ""
		local world = Instance.new("WorldModel")
		world.Parent = viewport
		model.Parent = world
		local cf, size = model:GetBoundingBox()
		local camera = Instance.new("Camera")
		camera.FieldOfView = 40
		local distance = size.Magnitude / 2 / math.tan(math.rad(20)) * 1.05
		camera.CFrame = CFrame.lookAt(cf.Position + Vector3.new(0, distance * 0.35, distance), cf.Position)
		camera.Parent = viewport
		viewport.CurrentCamera = camera
		viewport.LightColor = Color3.new(1, 1, 1)
		viewport.Ambient = Color3.fromRGB(180, 180, 190)
		local base = model:GetPivot()
		local offset = base.Position - cf.Position
		local angle = 0
		local connection
		connection = RunService.RenderStepped:Connect(function(dt)
			if not frame.Parent then connection:Disconnect() return end
			if not gui.Enabled then return end
			angle += dt * 0.8
			model:PivotTo(CFrame.new(cf.Position) * CFrame.Angles(0, angle, 0) * CFrame.new(offset) * base.Rotation)
			if rays then rays.Rotation = (angle * 20) % 360 end
		end)
	end

	-- Лента FEATURED над иконкой.
	local ribbon = Instance.new("TextLabel")
	ribbon.Name = "FeaturedBadge"
	ribbon.AnchorPoint = Vector2.new(0.5, 0)
	ribbon.Position = UDim2.new(0.5, 0, 0, -8)
	ribbon.Size = UDim2.new(1, 16, 0, 24)
	ribbon.BackgroundColor3 = Color3.fromRGB(255, 190, 40)
	UiKit.StyleText(ribbon, "Heading")
	ribbon.TextScaled = true
	ribbon.TextColor3 = Color3.new(1, 1, 1)
	ribbon.Text = tr("FEATURED")
	ribbon.ZIndex = 9
	Instance.new("UICorner", ribbon).CornerRadius = UDim.new(0, 6)
	ribbon.Parent = iconBox

	local name = main:FindFirstChild("Name")
	if name then name.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.25) end

	-- Монетки вокруг карточки: мягко покачиваются.
	local spots = { { 0.42, 0.18 }, { 0.58, 0.72 }, { 0.72, 0.2 }, { 0.36, 0.78 }, { 0.8, 0.62 }, { 0.5, 0.12 } }
	for index, spot in spots do
		local coin = Instance.new("Frame")
		coin.Name = "FeaturedCoin" .. index
		coin.AnchorPoint = Vector2.new(0.5, 0.5)
		coin.Position = UDim2.fromScale(spot[1], spot[2])
		local size = 14 + (index % 3) * 4
		coin.Size = UDim2.fromOffset(size, size)
		coin.BackgroundColor3 = Color3.fromRGB(255, 205, 60)
		coin.BackgroundTransparency = 0.1
		coin.Rotation = index * 23
		coin.ZIndex = 2
		Instance.new("UICorner", coin).CornerRadius = UDim.new(1, 0)
		local coinStroke = Instance.new("UIStroke")
		coinStroke.Color = Color3.fromRGB(190, 120, 20)
		coinStroke.Thickness = 1.5
		coinStroke.Parent = coin
		local sign = Instance.new("TextLabel")
		sign.BackgroundTransparency = 1
		sign.Size = UDim2.fromScale(1, 1)
		sign.Text = "$"
		sign.TextScaled = true
		sign.TextColor3 = Color3.fromRGB(150, 90, 10)
		sign.FontFace = UiKit.Theme.Fonts.Number
		sign.ZIndex = 2
		sign.Parent = coin
		coin.Parent = main
		TweenService:Create(coin, TweenInfo.new(1.2 + index * 0.17, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			Position = UDim2.fromScale(spot[1], spot[2] - 0.08),
			Rotation = coin.Rotation + 25,
		}):Play()
	end
end

local function buildRow(data)
	local frame = template:Clone()
	frame.Name = data.Id
	frame.Visible = true
	frame.Size = UDim2.new(1, -18, 0, ROW_CLOSED)
	local main = frame.Main
	main:FindFirstChild("Name").Text = tr(data.DisplayName or data.Id)
	main.IconBox.Icon.Image = data.Image or ""
	main.IconBox.Emoji.Text = data.Image and "" or (data.Icon or "?")
	main.Rarity.BackgroundColor3 = rarityColor(data.Rarity)
	main.Rarity.Label.Text = tr(data.Rarity or "")
	frame.BuyRow.Position = UDim2.fromOffset(10, 150)
	local effect = frame:FindFirstChild("Effect")
	if not effect then
		effect = Instance.new("TextLabel")
		effect.Name = "Effect"
		effect.BackgroundTransparency = 1
		effect.Position = UDim2.fromOffset(12, 120)
		effect.Size = UDim2.new(1, -24, 0, 26)
		require(game:GetService("ReplicatedStorage").Shared.UiKit).StyleText(effect, "Heading") -- v20: шрифт темы
		effect.TextScaled = true
		effect.TextXAlignment = Enum.TextXAlignment.Left
		effect.TextColor3 = Color3.fromRGB(255, 230, 170)
		effect.Parent = frame
		Instance.new("UIStroke", effect).Thickness = 1.6
	end
	local builtBadge = main.IconBox:FindFirstChild("LimitedBadge")
	if data.Limited and builtBadge then
		builtBadge.Visible = true
		local badgeText = builtBadge:FindFirstChild("Text")
		if badgeText then badgeText.Text = tr("LIMITED") end
		local glow = frame:FindFirstChild("SkinStroke") or frame:FindFirstChildOfClass("UIStroke")
		if glow then
			glow.Color = Color3.fromRGB(255, 70, 100)
			TweenService:Create(glow, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Color = Color3.fromRGB(255, 200, 80) }):Play()
		end
	elseif data.Limited then
		local badge = Instance.new("TextLabel")
		badge.Name = "LimitedBadge"
		badge.AnchorPoint = Vector2.new(0.5, 0)
		badge.Position = UDim2.new(0.5, 0, 0, -6)
		badge.Size = UDim2.new(1, 8, 0, 22)
		badge.BackgroundColor3 = Color3.fromRGB(230, 40, 70)
		require(game:GetService("ReplicatedStorage").Shared.UiKit).StyleText(badge, "Heading") -- v20: шрифт темы
		badge.TextScaled = true
		badge.TextColor3 = Color3.new(1, 1, 1)
		badge.Text = tr("LIMITED")
		badge.ZIndex = 5
		badge.Parent = main.IconBox
		Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 6)
		local glow = frame:FindFirstChildOfClass("UIStroke")
		if glow then
			glow.Color = Color3.fromRGB(255, 70, 100)
			TweenService:Create(glow, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Color = Color3.fromRGB(255, 200, 80) }):Play()
		end
	end
	if data.Featured then
		local ok, err = pcall(decorateFeatured, frame, data)
		if not ok then warn("[MerchantUI] featured:", err) end
	elseif data.Limited or data.Kind == "Mystery" then
		-- v20.30: особые товары — вращающийся фон за иконкой (лимитка — по
		-- редкости, «???» — спираль).
		-- «???» — случайный цвет полосок (каждый раз другой).
		local backdropColor = data.Kind == "Mystery" and Color3.fromHSV(math.random(), 0.55, 1)
			or rarityColor(data.Rarity):Lerp(Color3.new(1, 1, 1), 0.3)
		local backdrop = UiKit.Backdrop(main.IconBox, "SpecialRays", data.Kind == "Mystery" and "Mystery" or data.Rarity, {
			Size = UDim2.fromScale(1.6, 1.6),
			Color = backdropColor,
			Transparency = 0.15,
			ZIndex = 1,
		})
		local spin
		spin = game:GetService("RunService").RenderStepped:Connect(function(dt)
			if not frame.Parent then spin:Disconnect() return end
			if gui.Enabled then backdrop.Rotation = (backdrop.Rotation + dt * 18) % 360 end
		end)
	end
	frame.Parent = list

	local row = { Frame = frame, Data = data }
	rows[data.Id] = row

	main.MouseButton1Click:Connect(function()
		sfx("UiButtonClick")
		setExpanded(expandedId ~= data.Id and data.Id or nil)
	end)
	frame.BuyRow.Buy.MouseButton1Click:Connect(function()
		local current = row.Data
		if busy or not current or current.Lock or current.Stock <= 0 then
			sfx("UiError")
			return
		end
		busy = true
		local ok, success, reason = pcall(function()
			return requestRemote:InvokeServer("Buy", current.Id)
		end)
		busy = false
		if ok and success then
			sfx("UiSuccess")
			local scale = frame.Main.IconBox:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", frame.Main.IconBox)
			pop(scale, 1.3)
			-- v20.28: «???» — что внутри, показывает карточка открытия.
			if typeof(reason) == "table" and reason.Kind then
				local okCards, RevealCards = pcall(require, ReplicatedStorage.Shared.RevealCards)
				if okCards then
					pcall(RevealCards.Show, { reason }, { Title = "MYSTERY ITEM", Color = rarityColor(reason.Rarity) })
				end
			end
		else
			sfx("UiError")
			paintBuy(row, tr(ok and (reason or "Purchase failed") or "Try again"), Color3.fromRGB(200, 50, 50))
			task.delay(1.4, function() refreshRow(current.Id) end)
		end
	end)
	return row
end

renderList = function()
	for id, button in tabButtons do
		if button:GetAttribute("UiSkin") then
			UiKit.ApplySkin(button, id == currentTab and "TabActive" or "Tab")
		else
			button.BackgroundColor3 = id == currentTab and Color3.fromRGB(96, 196, 64) or Color3.fromRGB(86, 46, 22)
		end
	end
	local state = lastState
	if not state then return end
	local visible = {}
	for _, data in state.Items or {} do
		if (data.Tab or "Shop") == currentTab then visible[data.Id] = data end
	end
	for id, row in rows do
		if not visible[id] then
			row.Frame:Destroy()
			rows[id] = nil
		end
	end
	local count = 0
	for _, data in state.Items or {} do
		if visible[data.Id] then
			count += 1
			-- Сундук цикла сменил редкость — карточку собираем заново.
			local existing = rows[data.Id]
			if existing and data.Featured and existing.Data and existing.Data.ChestRarity ~= data.ChestRarity then
				existing.Frame:Destroy()
				rows[data.Id] = nil
			end
			local row = rows[data.Id] or buildRow(data)
			row.Data = data
			row.Frame.LayoutOrder = (tonumber(data.Order) or count) + 1000
			refreshRow(data.Id)
		end
	end
	local empty = list:FindFirstChild("EmptyNote")
	if not empty then
		empty = Instance.new("TextLabel")
		empty.Name = "EmptyNote"
		empty.BackgroundTransparency = 1
		empty.Size = UDim2.new(1, -30, 0, 70)
		require(game:GetService("ReplicatedStorage").Shared.UiKit).StyleText(empty, "Heading") -- v20: шрифт темы
		empty.TextScaled = true
		empty.TextColor3 = Color3.fromRGB(230, 210, 180)
		empty.LayoutOrder = 99999
		empty.Parent = list
	end
	empty.Visible = count == 0
	empty.Text = tr("Nothing in stock - wait for the next restock!")
end

--------------------------------------------------------------------------------
-- ПРИЁМ СОСТОЯНИЯ
--------------------------------------------------------------------------------
local function applyState(state)
	if typeof(state) ~= "table" then return end
	lastState = state
	renderList()
end

local function open()
	if gui.Enabled then return end
	gui.Enabled = true
	sfx("UiMenuOpen")
	if openScale then
		openScale.Scale = 0.85
		TweenService:Create(openScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

local function close()
	if not gui.Enabled then return end
	sfx("UiMenuClose")
	gui.Enabled = false
	setExpanded(nil)
	currentTab = "Shop"
end

stateRemote.OnClientEvent:Connect(function(command, state)
	applyState(state)
	if command == "Open" then
		open()
	elseif command == "Restocked" and gui.Enabled then
		-- Новый сток пока окно открыто — лёгкий "встряс" списка.
		for _, row in rows do
			local scale = row.Frame:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", row.Frame)
			pop(scale, 1.04)
		end
	end
end)

header.Close.MouseButton1Click:Connect(close)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Escape and gui.Enabled then close() end
end)

-- RESTOCK — dev product из Config.DevProducts.Micro.MerchantRestock.
header.Restock.MouseButton1Click:Connect(function()
	local product = Config.DevProducts and Config.DevProducts.Micro and Config.DevProducts.Micro.MerchantRestock
	local productId = product and tonumber(product.Id) or 0
	if productId == 0 then
		sfx("UiError")
		header.Restock.Label.Text = tr("SOON")
		task.delay(1.4, function() header.Restock.Label.Text = tr("RESTOCK") end)
		warn("[MerchantUI] Config.DevProducts.Micro.MerchantRestock.Id = 0 - создайте продукт в Creator Dashboard.")
		return
	end
	sfx("UiButtonClick")
	MarketplaceService:PromptProductPurchase(player, productId)
end)

-- Закрыть, когда игрок отошёл от торговца.
local function merchantModel()
	for _, child in workspace:GetChildren() do
		if child:GetAttribute("BankMerchant") then return child end
	end
	return nil
end

--------------------------------------------------------------------------------
-- КУРС И ТАЙМЕРЫ (окно, HUD-плашка, табло над торговцем)
--------------------------------------------------------------------------------
local lastMarket = nil

local function paintMarket()
	local multiplier = workspace:GetAttribute("MarketMultiplier") or 1
	local bucket = bucketInfo(workspace:GetAttribute("MarketBucket"))
	local valueText = ("x%.2f"):format(multiplier)

	marketBar.Value.Text = valueText
	marketBar.Value.TextColor3 = bucket.Color
	marketBar.Bucket.BackgroundColor3 = bucket.Color
	marketBar.Bucket.Label.Text = tr(bucket.Label)
	if multiplier >= 1.15 then
		marketBar.Hint.Text = tr("Great time to sell!")
	elseif multiplier < 0.9 then
		marketBar.Hint.Text = tr("Prices are low - wait?")
	else
		marketBar.Hint.Text = tr("Normal prices")
	end

	tickerPill.Value.Text = (multiplier >= 1 and "📈 " or "📉 ") .. tr("ORE") .. " " .. valueText
	tickerPill.Value.TextColor3 = bucket.Color

	local model = merchantModel()
	local board = model and model:FindFirstChild("MerchantBoard", true)
	if board then
		-- v20.19: «ORE PRICE» золотым, курс — цветом корзины (рост/падение).
		board.Market.RichText = true
		board.Market.Text = ('<font color="#FFD24A">%s</font> %s'):format(tr("ORE PRICE"), valueText)
		board.Market.TextColor3 = bucket.Color
	end

	if lastMarket and lastMarket ~= multiplier then
		pop(tickerPill:FindFirstChild("Pop"), 1.3)
	end
	lastMarket = multiplier
end

workspace:GetAttributeChangedSignal("MarketMultiplier"):Connect(paintMarket)
workspace:GetAttributeChangedSignal("MarketBucket"):Connect(paintMarket)
paintMarket()

tickerPill.MouseButton1Click:Connect(function()
	-- Плашка — подсказка, а не кнопка магазина: лавка открывается только у
	-- торговца. Короткое напоминание, где он.
	local original = tickerPill.Timer.Text
	tickerPill.Timer.Text = tr("at the bank")
	task.delay(1.5, function()
		if tickerPill.Timer.Text == tr("at the bank") then tickerPill.Timer.Text = original end
	end)
end)

task.spawn(function()
	while true do
		local seconds = secondsLeft()
		header.Timer.Text = tr("New stock in {time}", { time = formatLong(seconds) })
		if tickerPill.Timer.Text ~= tr("at the bank") then
			tickerPill.Timer.Text = formatShort(seconds)
		end
		local model = merchantModel()
		local board = model and model:FindFirstChild("MerchantBoard", true)
		if board then
			board.Timer.RichText = true
			board.Timer.Text = ('%s <font color="#FFFFFF">%s</font>'):format(tr("New stock in"), formatShort(seconds))
		end
		-- Отошёл от лавки — окно закрывается само.
		if gui.Enabled and model then
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if hrp and (hrp.Position - model:GetPivot().Position).Magnitude > (CFG.PromptDistance or 12) + 14 then
				close()
			end
		end
		-- Паинт курса на случай, если табло торговца появилось позже атрибута.
		if board and board.Market.Text == "" then paintMarket() end
		task.wait(0.25)
	end
end)

-- Первичная загрузка состояния лавки.
task.spawn(function()
	local ok, success, state = pcall(function()
		return requestRemote:InvokeServer("GetState")
	end)
	if ok and success then applyState(state) end
end)

--------------------------------------------------------------------------------
-- v20.28: «!» НАД ТОРГОВЦЕМ — отмеченный звёздочкой товар в стоке
-- (атрибут игрока MerchantWishAlert, гаснет, когда открыл лавку).
--------------------------------------------------------------------------------
task.spawn(function()
	local alert = nil
	local function refreshAlert()
		local names = player:GetAttribute("MerchantWishAlert")
		if typeof(names) ~= "string" or names == "" then
			if alert then alert.Enabled = false end
			return
		end
		local npc = workspace:FindFirstChild("BankMerchant")
		local anchor = npc and (npc.PrimaryPart or npc:FindFirstChild("Head", true) or npc:FindFirstChildWhichIsA("BasePart", true))
		if not anchor then return end
		if not (alert and alert.Parent) then
			alert = Instance.new("BillboardGui")
			alert.Name = "MerchantWishAlert"
			alert.Size = UDim2.fromScale(6, 1.6)
			alert.StudsOffsetWorldSpace = Vector3.new(0, 5.5, 0)
			alert.AlwaysOnTop = true
			alert.LightInfluence = 0
			alert.DistanceLowerLimit = 10
			alert.MaxDistance = 400
			local text = Instance.new("TextLabel")
			text.Name = "Text"
			text.BackgroundTransparency = 1
			text.Size = UDim2.fromScale(1, 1)
			UiKit.StyleText(text, "Heading")
			text.TextScaled = true
			text.TextColor3 = Color3.fromRGB(255, 225, 90)
			text.Parent = alert
			local scale = Instance.new("UIScale")
			scale.Parent = text
			TweenService:Create(scale, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.15 }):Play()
			alert.Parent = playerGui
		end
		alert.Adornee = anchor
		alert.Text.Text = "⭐ " .. tr("IN STOCK!")
		alert.Enabled = true
	end
	player:GetAttributeChangedSignal("MerchantWishAlert"):Connect(refreshAlert)
	refreshAlert()
end)
