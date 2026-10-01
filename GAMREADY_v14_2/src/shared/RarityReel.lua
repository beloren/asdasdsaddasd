--------------------------------------------------------------------------------
-- RarityReel (v20.109) — ЛЕНТА РЕДКОСТЕЙ после мини-игры шахты (только
-- клиент, Config.MineExpedition.RarityReel). Горизонтальная лента плиток
-- редкостей крутится как в кейсах, замедляется, «чуть-чуть не доезжает»
-- до плитки повыше и встаёт на выпавшую редкость.
--   RarityReel.Play("Epic", function() ... end)
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(script.Parent.Config)
local okKit, UiKit = pcall(require, script.Parent.UiKit)
local okSfx, UiSfx = pcall(require, script.Parent.UiSfx)

local RarityReel = {}

local function sfx(name)
	if okSfx then pcall(UiSfx.play, name) end
end

local function style(label, kind)
	if okKit and UiKit.StyleText then pcall(UiKit.StyleText, label, kind or "Heading") end
end

local function pickRarity(rng, weights, order)
	local total = 0
	for _, name in order do total += weights[name] or 0 end
	local roll = rng:NextNumber() * total
	for _, name in order do
		roll -= weights[name] or 0
		if roll <= 0 then return name end
	end
	return order[1]
end

function RarityReel.Play(target, onDone)
	local cfg = Config.MineExpedition.RarityReel or {}
	local order = Config.RarityOrder
	local weights = cfg.Weights or {}
	local tileW, gap = cfg.TileWidth or 118, cfg.TileGap or 8
	local count = cfg.Tiles or 46
	local seconds = cfg.Seconds or 3.4
	local rng = Random.new()
	local targetIndex = count - 5
	local targetRank = table.find(order, target) or 1

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "RarityReel"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 60
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local band = Instance.new("Frame")
	band.Name = "Band"
	band.AnchorPoint = Vector2.new(0.5, 0.5)
	band.Position = UDim2.fromScale(0.5, 0.5)
	band.Size = UDim2.new(1, 0, 0, tileW + 46)
	band.BackgroundColor3 = Color3.fromRGB(12, 10, 20)
	band.BackgroundTransparency = 1
	band.BorderSizePixel = 0
	band.ClipsDescendants = true
	band.Parent = gui
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.18, 0.15),
		NumberSequenceKeypoint.new(0.82, 0.15), NumberSequenceKeypoint.new(1, 1),
	})
	fade.Parent = band

	local strip = Instance.new("Frame")
	strip.Name = "Strip"
	strip.BackgroundTransparency = 1
	strip.AnchorPoint = Vector2.new(0, 0.5)
	strip.Size = UDim2.new(0, count * (tileW + gap), 0, tileW)
	strip.Position = UDim2.new(0.5, 0, 0.5, 0)
	strip.Parent = band

	local rarities = {}
	for i = 1, count do rarities[i] = pickRarity(rng, weights, order) end
	rarities[targetIndex] = target
	-- дразнилка: соседняя плитка - редкость повыше
	if targetRank < #order and rng:NextNumber() < (cfg.TeaseChance or 0.75) then
		rarities[targetIndex + 1] = order[math.min(#order, targetRank + rng:NextInteger(1, 2))]
	end

	local tiles = {}
	for i, rarity in rarities do
		local color = Config.RarityColors[rarity] or Color3.fromRGB(200, 200, 200)
		local tile = Instance.new("Frame")
		tile.Name = "Tile" .. i
		tile.Size = UDim2.fromOffset(tileW, tileW)
		tile.Position = UDim2.fromOffset((i - 1) * (tileW + gap), 0)
		tile.BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.55)
		tile.BorderSizePixel = 0
		tile.Parent = strip
		Instance.new("UICorner", tile).CornerRadius = UDim.new(0, 12)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Color = color
		stroke.Parent = tile
		local grad = Instance.new("UIGradient")
		grad.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.15), color:Lerp(Color3.new(0, 0, 0), 0.35))
		grad.Rotation = 90
		grad.Parent = tile
		local gem = Instance.new("Frame")
		gem.Name = "Gem"
		gem.AnchorPoint = Vector2.new(0.5, 0.5)
		gem.Position = UDim2.fromScale(0.5, 0.4)
		gem.Size = UDim2.fromScale(0.36, 0.36)
		gem.Rotation = 45
		gem.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.25)
		gem.BorderSizePixel = 0
		gem.Parent = tile
		local gemStroke = Instance.new("UIStroke")
		gemStroke.Thickness = 2
		gemStroke.Color = Color3.fromRGB(15, 10, 20)
		gemStroke.Parent = gem
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.new(0.5, 0, 1, -6)
		label.Size = UDim2.new(1, -10, 0.26, 0)
		label.Text = rarity:upper()
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		style(label)
		local labelStroke = Instance.new("UIStroke")
		labelStroke.Thickness = 2
		labelStroke.Parent = label
		label.Parent = tile
		tiles[i] = tile
	end

	-- указатель по центру
	local marker = Instance.new("Frame")
	marker.Name = "Marker"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Position = UDim2.fromScale(0.5, 0.5)
	marker.Size = UDim2.new(0, 4, 1, -8)
	marker.BackgroundColor3 = Color3.fromRGB(255, 215, 60)
	marker.BorderSizePixel = 0
	marker.ZIndex = 5
	marker.Parent = band
	for _, top in { true, false } do
		local arrow = Instance.new("TextLabel")
		arrow.BackgroundTransparency = 1
		arrow.AnchorPoint = Vector2.new(0.5, top and 0 or 1)
		arrow.Position = UDim2.new(0.5, 0, top and 0 or 1, 0)
		arrow.Size = UDim2.fromOffset(30, 22)
		arrow.Text = top and "▼" or "▲"
		arrow.TextScaled = true
		arrow.TextColor3 = Color3.fromRGB(255, 215, 60)
		arrow.ZIndex = 6
		arrow.Parent = band
	end

	TweenService:Create(band, TweenInfo.new(0.25), { BackgroundTransparency = 0.15 }):Play()

	-- стоп ближе к правому краю целевой плитки - «почти соседняя»
	local stopInside = tileW * rng:NextNumber(0.78, 0.92)
	local finalX = -((targetIndex - 1) * (tileW + gap) + stopInside)
	local startX = rng:NextInteger(0, math.floor(tileW * 0.5))
	strip.Position = UDim2.new(0.5, startX, 0.5, 0)
	local spin = TweenService:Create(strip, TweenInfo.new(seconds, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, finalX, 0.5, 0),
	})
	-- щелчок на каждой плитке
	local lastTile = -1
	local tick = RunService.RenderStepped:Connect(function()
		local index = math.floor((-strip.Position.X.Offset) / (tileW + gap))
		if index ~= lastTile then
			lastTile = index
			sfx("UiHover")
		end
	end)
	spin:Play()
	spin.Completed:Wait()
	tick:Disconnect()
	-- качнулась к соседней и вернулась
	local wobble = TweenService:Create(strip, TweenInfo.new(0.16, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, true), {
		Position = UDim2.new(0.5, finalX - (tileW - stopInside) * 0.6, 0.5, 0),
	})
	wobble:Play()
	wobble.Completed:Wait()

	local win = tiles[targetIndex]
	if win then
		sfx("MineModifierReveal")
		local scale = Instance.new("UIScale")
		scale.Parent = win
		win.ZIndex = 4
		TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.15 }):Play()
		local glow = win:FindFirstChildOfClass("UIStroke")
		if glow then TweenService:Create(glow, TweenInfo.new(0.25), { Thickness = 6 }):Play() end
	end
	task.wait(cfg.HoldSeconds or 0.5)
	local out = TweenService:Create(band, TweenInfo.new(0.2), { BackgroundTransparency = 1 })
	out:Play()
	for _, d in band:GetDescendants() do
		if d:IsA("GuiObject") then
			pcall(function() TweenService:Create(d, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play() end)
			if d:IsA("TextLabel") then TweenService:Create(d, TweenInfo.new(0.2), { TextTransparency = 1 }):Play() end
		end
	end
	task.delay(0.25, function() gui:Destroy() end)
	if onDone then task.spawn(onDone) end
end

return RarityReel
