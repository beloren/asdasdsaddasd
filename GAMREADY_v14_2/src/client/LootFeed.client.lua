--------------------------------------------------------------------------------
-- LootFeed (LocalScript) — ЛЕНТА ЛУТА СПРАВА + БАННЕР ПО ЦЕНТРУ (v14).
--
-- Источники:
--   • RemoteEvent Shared.LootFeedEvent (NotifyService:LootFeed) — сервер;
--   • BindableEvent Shared.LootFeedLocal — другие клиентские скрипты
--     (BoulderGameUI отдаёт сюда награды валуна).
-- Формат: items = { { Icon, Text, Color, Rarity, Sub }, ... },
--         header = { Title, Color }? — заголовок-баннер по центру.
--
-- Карточка выезжает справа, стопкой (новые сверху), с рамкой цвета
-- редкости и лёгким «блеском». Редкое (Config.BoulderLoot.BannerRarities)
-- дополнительно показывается крупным баннером по центру экрана.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Localization = require(ReplicatedStorage.Shared.Localization)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local CFG = Config.BoulderLoot or {}

local UiSfx = nil
pcall(function() UiSfx = require(ReplicatedStorage.Shared.UiSfx) end)

local function tr(text)
	local ok, result = pcall(Localization.Translate, player.LocaleId, text)
	return ok and result or text
end

local shared = ReplicatedStorage:WaitForChild("Shared")
local localEvent = shared:FindFirstChild("LootFeedLocal")
if not localEvent then
	localEvent = Instance.new("BindableEvent")
	localEvent.Name = "LootFeedLocal"
	localEvent.Parent = shared
end

local gui = Instance.new("ScreenGui")
gui.Name = "LootFeedUi"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 40
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local column = Instance.new("Frame")
column.Name = "Feed"
column.AnchorPoint = Vector2.new(1, 0.5)
column.Position = UDim2.new(1, -14, 0.5, 0)
column.Size = UDim2.fromOffset(300, 420)
column.BackgroundTransparency = 1
column.Parent = gui
local columnScale = Instance.new("UIScale")
columnScale.Parent = column
local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
layout.Padding = UDim.new(0, 6)
layout.Parent = column

local function fitScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	columnScale.Scale = math.clamp(viewport.Y / 820, 0.6, 1.05)
end
fitScale()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitScale)
end

local function rarityColor(rarity, fallback)
	return (rarity and (Config.RarityColors[rarity] or (Config.Relics.RarityColors or {})[rarity])) or fallback or Color3.new(1, 1, 1)
end

local order = 0
local cards = {}

local function removeCard(card)
	for index, existing in cards do
		if existing == card then table.remove(cards, index) break end
	end
	if not card.Parent then return end
	local body = card:FindFirstChild("Body")
	if body then
		local out = TweenService:Create(body, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(1.2, 0, 0, 0) })
		out:Play()
		out.Completed:Wait()
	end
	card:Destroy()
end

local function pushCard(item, delaySeconds)
	task.delay(delaySeconds or 0, function()
		order -= 1
		local color = typeof(item.Color) == "Color3" and item.Color or rarityColor(item.Rarity)
		local card = Instance.new("Frame")
		card.Name = "Card"
		card.LayoutOrder = order
		card.BackgroundTransparency = 1
		card.Size = UDim2.fromOffset(290, item.Sub and 58 or 48)
		card.ClipsDescendants = false
		card.Parent = column

		local body = Instance.new("Frame")
		body.Name = "Body"
		body.Size = UDim2.fromScale(1, 1)
		body.Position = UDim2.new(1.2, 0, 0, 0)
		body.BackgroundColor3 = Color3.fromRGB(22, 24, 34)
		body.BackgroundTransparency = 0.15
		body.Parent = card
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = body
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2.5
		stroke.Color = color
		stroke.Parent = body
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(color:Lerp(Color3.new(0, 0, 0), 0.55), Color3.fromRGB(22, 24, 34))
		gradient.Parent = body
		local strip = Instance.new("Frame")
		strip.Size = UDim2.new(0, 6, 1, -10)
		strip.Position = UDim2.fromOffset(5, 5)
		strip.BackgroundColor3 = color
		strip.Parent = body
		Instance.new("UICorner", strip).CornerRadius = UDim.new(1, 0)

		local icon = Instance.new("TextLabel")
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.fromOffset(40, 40)
		icon.Position = UDim2.new(0, 16, 0.5, -20)
		icon.Font = Enum.Font.GothamBold
		icon.TextScaled = true
		icon.Text = tostring(item.Icon or "✨")
		icon.Parent = body

		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Position = UDim2.fromOffset(62, item.Sub and 6 or 0)
		title.Size = UDim2.new(1, -70, 0, item.Sub and 28 or 48)
		title.Font = Enum.Font.FredokaOne
		title.TextScaled = true
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.25)
		title.Text = tr(tostring(item.Text or ""))
		title.Parent = body
		local titleStroke = Instance.new("UIStroke")
		titleStroke.Thickness = 1.6
		titleStroke.Parent = title
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 24
		limit.Parent = title

		if item.Sub or item.Rarity then
			local sub = Instance.new("TextLabel")
			sub.BackgroundTransparency = 1
			sub.Position = UDim2.fromOffset(62, item.Sub and 32 or 30)
			sub.Size = UDim2.new(1, -70, 0, 20)
			sub.Font = Enum.Font.GothamBold
			sub.TextScaled = true
			sub.TextXAlignment = Enum.TextXAlignment.Left
			sub.TextColor3 = Color3.fromRGB(215, 215, 225)
			sub.Text = tr(tostring(item.Sub or ""))
			sub.Visible = item.Sub ~= nil
			sub.Parent = body
			local subLimit = Instance.new("UITextSizeConstraint")
			subLimit.MaxTextSize = 16
			subLimit.Parent = sub
		end

		-- Блик по карточке.
		local shine = Instance.new("Frame")
		shine.BackgroundColor3 = Color3.new(1, 1, 1)
		shine.BackgroundTransparency = 0.7
		shine.BorderSizePixel = 0
		shine.Size = UDim2.new(0, 26, 1, 0)
		shine.Position = UDim2.new(-0.2, 0, 0, 0)
		shine.Rotation = 12
		shine.Parent = body
		body.ClipsDescendants = true

		TweenService:Create(body, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0, 0, 0, 0) }):Play()
		task.delay(0.25, function()
			TweenService:Create(shine, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { Position = UDim2.new(1.2, 0, 0, 0) }):Play()
		end)
		if UiSfx then pcall(UiSfx.play, "UiButtonClick") end

		table.insert(cards, card)
		while #cards > (CFG.FeedMax or 6) do
			task.spawn(removeCard, cards[1])
		end
		task.delay(CFG.FeedLifetime or 4.5, function() removeCard(card) end)
	end)
end

--------------------------------------------------------------------------------
-- БАННЕР ПО ЦЕНТРУ
--------------------------------------------------------------------------------
local banner = Instance.new("Frame")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0.5)
banner.Position = UDim2.fromScale(0.5, 0.3)
banner.Size = UDim2.fromOffset(560, 120)
banner.BackgroundTransparency = 1
banner.Visible = false
banner.Parent = gui
local bannerScale = Instance.new("UIScale")
bannerScale.Parent = banner
local bannerTitle = Instance.new("TextLabel")
bannerTitle.BackgroundTransparency = 1
bannerTitle.Size = UDim2.new(1, 0, 0.45, 0)
bannerTitle.Font = Enum.Font.FredokaOne
bannerTitle.TextScaled = true
bannerTitle.TextColor3 = Color3.new(1, 1, 1)
bannerTitle.Parent = banner
Instance.new("UIStroke", bannerTitle).Thickness = 3
local bannerText = Instance.new("TextLabel")
bannerText.BackgroundTransparency = 1
bannerText.Position = UDim2.fromScale(0, 0.45)
bannerText.Size = UDim2.new(1, 0, 0.55, 0)
bannerText.Font = Enum.Font.FredokaOne
bannerText.TextScaled = true
bannerText.Parent = banner
Instance.new("UIStroke", bannerText).Thickness = 3.5
local bannerGradient = Instance.new("UIGradient")
bannerGradient.Parent = bannerText

local bannerToken = 0
local function showBanner(title, text, color)
	bannerToken += 1
	local token = bannerToken
	bannerTitle.Text = tr(title or "RARE DROP!")
	bannerTitle.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.5)
	bannerText.Text = tr(text or "")
	bannerText.TextColor3 = Color3.new(1, 1, 1)
	bannerGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color),
		ColorSequenceKeypoint.new(0.5, color:Lerp(Color3.new(1, 1, 1), 0.6)),
		ColorSequenceKeypoint.new(1, color),
	})
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local fit = math.clamp(viewport.X / 1100, 0.55, 1.1)
	banner.Visible = true
	bannerScale.Scale = fit * 0.2
	TweenService:Create(bannerScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = fit }):Play()
	bannerGradient.Offset = Vector2.new(-1, 0)
	TweenService:Create(bannerGradient, TweenInfo.new(1.6, Enum.EasingStyle.Linear), { Offset = Vector2.new(1, 0) }):Play()
	if UiSfx then pcall(UiSfx.play, "UiSuccess") end
	task.delay(2.6, function()
		if token ~= bannerToken then return end
		local out = TweenService:Create(bannerScale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 })
		out:Play()
		out.Completed:Wait()
		if token == bannerToken then banner.Visible = false end
	end)
end

local function handle(items, header)
	if typeof(items) ~= "table" then return end
	local bannerItem = nil
	for index, item in items do
		if typeof(item) == "table" then
			pushCard(item, (index - 1) * 0.12)
			if not bannerItem and item.Rarity and (CFG.BannerRarities or {})[item.Rarity] then
				bannerItem = item
			end
		end
	end
	if typeof(header) == "table" and header.Title then
		local item = bannerItem or items[1] or {}
		showBanner(header.Title, item.Text, typeof(header.Color) == "Color3" and header.Color or rarityColor(item.Rarity))
	elseif bannerItem then
		showBanner(("%s DROP!"):format(string.upper(bannerItem.Rarity)), bannerItem.Text, rarityColor(bannerItem.Rarity, bannerItem.Color))
	end
end

local remote = shared:WaitForChild("LootFeedEvent", 30)
if remote then
	remote.OnClientEvent:Connect(handle)
end
localEvent.Event:Connect(handle)
