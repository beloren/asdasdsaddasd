--------------------------------------------------------------------------------
-- TutorialGuideBanner (v20.140) — ПЛАШКА «NEW: <механика>» на 10 секунд.
-- Сервер (TutorialService) больше не запускает необязательные главы сам:
-- присылает TutorialGuideOffer - сверху появляется плашка с кнопкой
-- SHOW ME и полоской времени. Нажал - глава обучения начинается. Не нажал -
-- она остаётся в журнале квестов (QUESTS → GUIDES), запустить можно оттуда.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UiKit = require(ReplicatedStorage.Shared.UiKit)
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local offerRemote = ReplicatedStorage.Shared:WaitForChild("TutorialGuideOffer", 60)
local actionRemote = ReplicatedStorage.Shared:WaitForChild("TutorialActionEvent", 60)
if not (offerRemote and actionRemote) then return end

-- v20.150: подписи переводятся (Localization)
local function tr(text, args)
	local ok, Localization = pcall(require, ReplicatedStorage.Shared.Localization)
	if not ok then return text end
	local okT, out = pcall(Localization.Translate, player.LocaleId, text, args)
	return okT and out or text
end

local function sfx(name)
	pcall(function() require(ReplicatedStorage.Shared.UiSfx).play(name) end)
end

local gui = Instance.new("ScreenGui")
gui.Name = "TutorialGuideBanner"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 120
gui:SetAttribute("CinematicKeep", true)
gui.Parent = playerGui

local banner = Instance.new("Frame")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, -120)
banner.Size = UDim2.fromOffset(440, 74)
banner.BackgroundColor3 = Color3.fromRGB(28, 24, 44)
banner.BackgroundTransparency = 0.08
banner.Visible = false
banner.Parent = gui
Instance.new("UICorner", banner).CornerRadius = UDim.new(0, 12)
UiKit.Stroke(banner, UiKit.Theme.Accents.Gold.Main, 2.5, 0, "Outline")
local scale = Instance.new("UIScale")
scale.Parent = banner

local icon = UiKit.Text(banner, "Icon", "📘", { _Style = "Heading", Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(44, 44) })
icon.TextScaled = true
local title = UiKit.Text(banner, "Title", "NEW", {
	_Style = "Heading",
	Position = UDim2.fromOffset(62, 8),
	Size = UDim2.new(1, -200, 0, 30),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = UiKit.Theme.Accents.Gold.Main,
})
title.TextScaled = true
local subtitle = UiKit.Text(banner, "Subtitle", "", {
	_Style = "Body",
	Position = UDim2.fromOffset(62, 38),
	Size = UDim2.new(1, -200, 0, 22),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(225, 225, 235),
})
subtitle.TextScaled = true
local button = Instance.new("TextButton")
button.Name = "ShowMe"
button.AnchorPoint = Vector2.new(1, 0.5)
button.Position = UDim2.new(1, -12, 0.5, -2)
button.Size = UDim2.fromOffset(120, 44)
button.BackgroundColor3 = Color3.fromRGB(80, 200, 90)
button.Text = "SHOW ME"
button.TextScaled = true
button.TextColor3 = Color3.new(1, 1, 1)
button.AutoButtonColor = true
UiKit.StyleText(button, "Heading")
button.Parent = banner
Instance.new("UICorner", button).CornerRadius = UDim.new(0, 10)
local barBack = Instance.new("Frame")
barBack.Name = "Timer"
barBack.AnchorPoint = Vector2.new(0.5, 1)
barBack.Position = UDim2.new(0.5, 0, 1, -4)
barBack.Size = UDim2.new(1, -24, 0, 4)
barBack.BackgroundColor3 = Color3.fromRGB(10, 8, 18)
barBack.BorderSizePixel = 0
barBack.Parent = banner
local bar = Instance.new("Frame")
bar.Name = "Fill"
bar.Size = UDim2.fromScale(1, 1)
bar.BackgroundColor3 = UiKit.Theme.Accents.Gold.Main
bar.BorderSizePixel = 0
bar.Parent = barBack

local current = nil
local token = 0

local function hide()
	token += 1
	local my = token
	current = nil
	TweenService:Create(banner, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(0.5, 0, 0, -120) }):Play()
	task.delay(0.32, function()
		if my == token then banner.Visible = false end
	end)
end

local function layout()
	local camera = workspace.CurrentCamera
	local view = camera and camera.ViewportSize or Vector2.new(1280, 720)
	scale.Scale = math.clamp((view.X - 24) / 440, 0.6, 1)
end

local function show(offer)
	token += 1
	local my = token
	current = offer
	layout()
	-- v20.150: короткая подсказка механики (Hint = true) - без SHOW ME,
	-- текст на всю ширину; гайд - с кнопкой, как раньше
	local isHint = offer.Hint == true
	button.Visible = not isHint
	button.Text = tr("SHOW ME")
	icon.Text = offer.Icon or (isHint and "💡" or "📘")
	title.Size = UDim2.new(1, isHint and -76 or -200, 0, 30)
	subtitle.Size = UDim2.new(1, isHint and -76 or -200, 0, 22)
	title.Text = (isHint and "" or (tr("NEW") .. ": ")) .. tr(tostring(offer.Title or "")):upper()
	local reward = tonumber(offer.Reward) or 0
	-- v20.174: ключевые слова цветом
	subtitle.RichText = true
	subtitle.Text = require(game:GetService("ReplicatedStorage").Shared.TutorialColors).Paint(tr(tostring(offer.Text or ""))) .. (reward > 0 and ('  ·  <font color="#6CFF7E">+$' .. reward .. "</font>") or "")
	banner.Visible = true
	banner.Position = UDim2.new(0.5, 0, 0, -120)
	TweenService:Create(banner, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, 64) }):Play()
	sfx("QuestProgress")
	local seconds = tonumber(offer.Seconds) or 10
	bar.Size = UDim2.fromScale(1, 1)
	TweenService:Create(bar, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) }):Play()
	task.delay(seconds, function()
		if my == token and current then hide() end
	end)
end

button.Activated:Connect(function()
	if not current then return end
	sfx("UiButtonClick")
	actionRemote:FireServer("AcceptGuide", current.Id)
	hide()
end)

offerRemote.OnClientEvent:Connect(function(offer)
	if typeof(offer) == "table" and offer.Id then show(offer) end
end)
