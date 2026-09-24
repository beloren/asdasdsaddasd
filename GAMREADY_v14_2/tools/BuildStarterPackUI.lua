--------------------------------------------------------------------------------
-- Standalone Studio builder for StarterGui/StarterPackOffer — баннер с
-- радужной надписью "STARTER KIT" + отсчётом (см. Config.DevProducts.
-- StarterPack.OfferWindowSeconds) и экран "что внутри" с ценой и кнопкой
-- покупки. Вся анимация (радуга/отсчёт) и логика показа — в
-- src/client/StarterPackUI.client.lua, здесь только статичная разметка.
-- Rerunning this script destroys and rebuilds only this exact ScreenGui.
--------------------------------------------------------------------------------

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

Config.DevProducts = Config.DevProducts or {}
local pack = Config.DevProducts.StarterPack or { PriceRobux = 99, Contents = {} }
local STARTER_PACK_ICON_IMAGE = "rbxassetid://100116175987177"

local COLORS = {
	Panel = Color3.fromRGB(29, 34, 47),
	Header = Color3.fromRGB(55, 91, 166),
	Row = Color3.fromRGB(40, 46, 62),
	White = Color3.fromRGB(245, 247, 255),
	Green = Color3.fromRGB(80, 195, 90),
	Banner = Color3.fromRGB(24, 27, 38),
}

local function label(name, text, size, position, textSize)
	local item = Instance.new("TextLabel")
	item.Name = name
	item.Size = size
	item.Position = position
	item.BackgroundTransparency = 1
	item.Font = Enum.Font.Arcade
	item.Text = text
	item.TextColor3 = COLORS.White
	item.TextSize = textSize
	item.TextStrokeTransparency = 1
	item.TextWrapped = true
	return item
end

local existing = StarterGui:FindFirstChild("StarterPackOffer")
if existing then existing:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "StarterPackOffer"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
gui.DisplayOrder = 400
gui.Parent = StarterGui

--------------------------------------------------------------------------------
-- БАННЕР — плашка справа по центру. Enabled/Visible полностью
-- решает клиент (см. StarterPackUI.client.lua): новый ли игрок, в окне ли
-- ещё OfferWindowSeconds, не куплен ли пак уже.
--------------------------------------------------------------------------------
local banner = Instance.new("ImageButton")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(1, 1)
banner.Position = UDim2.new(1, -20, 1, -20)
banner.Size = UDim2.fromOffset(286, 86)
banner.BackgroundColor3 = COLORS.Banner
banner.BorderSizePixel = 0
banner.AutoButtonColor = false
banner.Image = ""
banner.ZIndex = 10
banner.Visible = false
banner.Parent = gui

local bannerIcon = Instance.new("ImageLabel")
bannerIcon.Name = "Icon"
bannerIcon.AnchorPoint = Vector2.new(0, 0.5)
bannerIcon.Position = UDim2.fromOffset(10, 43)
bannerIcon.Size = UDim2.fromOffset(66, 66)
bannerIcon.BackgroundTransparency = 1
bannerIcon.ScaleType = Enum.ScaleType.Fit
bannerIcon.Image = STARTER_PACK_ICON_IMAGE
bannerIcon.ZIndex = 11
bannerIcon.Parent = banner

-- Цвет здесь ЛЮБОЙ (StarterPackUI.client.lua перекрашивает его в цикле HSV
-- каждый кадр, пока баннер виден) — TextColor3 ниже просто стартовое значение.
local rainbowTitle = label("RainbowTitle", "STARTER KIT", UDim2.new(1, -88, 0, 28), UDim2.fromOffset(84, 7), 20)
rainbowTitle.TextColor3 = Color3.fromRGB(255, 90, 90)
rainbowTitle.ZIndex = 11
rainbowTitle.Parent = banner

local countdown = label("Countdown", "10:00", UDim2.new(1, -88, 0, 24), UDim2.fromOffset(84, 39), 18)
countdown.TextColor3 = Color3.fromRGB(220, 225, 235)
countdown.ZIndex = 11
countdown.Parent = banner

--------------------------------------------------------------------------------
-- ЭКРАН "ЧТО ВНУТРИ" — открывается кликом по баннеру.
--------------------------------------------------------------------------------
local dimmer = Instance.new("TextButton")
dimmer.Name = "Dimmer"
dimmer.Size = UDim2.fromScale(1, 1)
dimmer.BackgroundColor3 = Color3.fromRGB(12, 15, 22)
dimmer.BackgroundTransparency = 0.35
dimmer.BorderSizePixel = 0
dimmer.AutoButtonColor = false
dimmer.Text = ""
dimmer.Visible = false
dimmer.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "Details"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
local rowCount = math.max(1, #pack.Contents)
panel.Size = UDim2.fromOffset(420, 168 + rowCount * 36)
panel.BackgroundColor3 = COLORS.Panel
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
local scale = Instance.new("UIScale")
scale.Name = "ResponsiveScale"
scale.Parent = panel

local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 56)
header.BackgroundColor3 = COLORS.Header
header.BorderSizePixel = 0
header.Parent = panel
local title = label("Title", "STARTER KIT", UDim2.new(1, -60, 1, 0), UDim2.fromOffset(20, 0), 24)
title.Parent = header
local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -12, 0, 10)
closeButton.Size = UDim2.fromOffset(38, 36)
closeButton.BackgroundColor3 = Color3.fromRGB(190, 65, 70)
closeButton.BorderSizePixel = 0
closeButton.Font = Enum.Font.Arcade
closeButton.Text = "X"
closeButton.TextColor3 = COLORS.White
closeButton.TextSize = 18
closeButton.TextStrokeTransparency = 1
closeButton.Parent = header

-- Строки списка — один в один по Config.DevProducts.StarterPack.Contents.
-- Правишь ТЕКСТ содержимого пака в Config.lua, а не здесь; перезапускаешь
-- этот билдер только если поменялось ЧИСЛО строк (иначе панель не той
-- высоты) или нужно поправить сам стиль строки.
local contentsFrame = Instance.new("Frame")
contentsFrame.Name = "Contents"
contentsFrame.Position = UDim2.fromOffset(20, 68)
contentsFrame.Size = UDim2.new(1, -40, 0, rowCount * 36)
contentsFrame.BackgroundTransparency = 1
contentsFrame.Parent = panel

for index, line in pack.Contents do
	local row = Instance.new("Frame")
	row.Name = "Row" .. index
	row.Position = UDim2.fromOffset(0, (index - 1) * 36)
	row.Size = UDim2.new(1, 0, 0, 32)
	row.BackgroundColor3 = COLORS.Row
	row.BorderSizePixel = 0
	row.Parent = contentsFrame

	local checkmark = label("Checkmark", "✔", UDim2.fromOffset(28, 32), UDim2.fromOffset(6, 0), 16)
	checkmark.TextColor3 = COLORS.Green
	checkmark.Parent = row

	local text = label("Text", line, UDim2.new(1, -44, 1, 0), UDim2.fromOffset(38, 0), 15)
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.Parent = row
end

local buyButton = Instance.new("TextButton")
buyButton.Name = "BuyButton"
buyButton.Position = UDim2.fromOffset(20, 88 + rowCount * 36)
buyButton.Size = UDim2.new(1, -40, 0, 48)
buyButton.BackgroundColor3 = COLORS.Green
buyButton.BorderSizePixel = 0
buyButton.Font = Enum.Font.Arcade
buyButton.Text = ("BUY FOR R$ %d"):format(pack.PriceRobux or 99)
buyButton.TextColor3 = Color3.fromRGB(20, 25, 20)
buyButton.TextSize = 18
buyButton.TextStrokeTransparency = 1
buyButton.Parent = panel

print("[BuildStarterPackUI] StarterGui/StarterPackOffer создан. Замени Banner/Icon и добавь иконки к строкам Contents в Studio при желании.")
