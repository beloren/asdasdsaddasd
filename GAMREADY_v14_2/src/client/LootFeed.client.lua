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

-- v20: вид — Shared.UiBuilders.LootFeedUi (правится в StarterGui/LootFeedUi).
local gui = require(ReplicatedStorage.Shared.UiRegistry).Get("LootFeedUi")
local column = gui:WaitForChild("Feed")
local columnScale = column:WaitForChild("AutoScale")
local cardTemplate = gui:WaitForChild("Templates"):WaitForChild("CardTemplate")

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
		local card = cardTemplate:Clone()
		card.Visible = true -- шаблоны в Templates скрыты
		card.Name = "Card"
		card.LayoutOrder = order
		card.Size = UDim2.fromOffset(290, item.Sub and 58 or 48)
		card.Parent = column

		local body = card:WaitForChild("Body")
		body.Position = UDim2.new(1.2, 0, 0, 0)
		local stroke = body:FindFirstChild("SkinStroke")
		if stroke then stroke.Color = color end
		local strip = body:FindFirstChild("Strip")
		if strip then strip.BackgroundColor3 = color; strip.ImageColor3 = color end
		local image = body:FindFirstChild("Image")
		local emoji = body:FindFirstChild("Emoji")
		local iconValue = tostring(item.Icon or "✨")
		local isAsset = iconValue:match("^rbxasset") or iconValue:match("^%d+$")
		if image then image.Image = isAsset and (iconValue:match("^%d+$") and "rbxassetid://" .. iconValue or iconValue) or "" end
		if emoji then emoji.Text = isAsset and "" or iconValue end

		local title = body:WaitForChild("Title")
		title.Position = UDim2.fromOffset(62, item.Sub and 6 or 0)
		title.Size = UDim2.new(1, -70, 0, item.Sub and 28 or 48)
		title.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.25)
		title.Text = tr(tostring(item.Text or ""))
		local sub = body:FindFirstChild("Sub")
		if sub then
			sub.Text = tr(tostring(item.Sub or ""))
			sub.Visible = item.Sub ~= nil
		end
		local shine = body:WaitForChild("Shine")

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
local banner = gui:WaitForChild("Banner")
local bannerScale = banner:WaitForChild("Pop")
local bannerTitle = banner:WaitForChild("Title")
local bannerText = banner:WaitForChild("Text")
local bannerGradient = bannerText:FindFirstChild("TextGradient") or Instance.new("UIGradient", bannerText)
bannerGradient.Rotation = 0 -- перелив идёт слева направо

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
	-- v20.36: во время мини-игры шахты лента и баннер «RARE DROP!» молчат —
	-- редкость и так видна над рудой.
	if game:GetService("Players").LocalPlayer:GetAttribute("MineExpeditionActive") == true then return end
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
