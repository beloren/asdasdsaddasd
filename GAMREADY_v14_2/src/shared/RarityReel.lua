--------------------------------------------------------------------------------
-- RarityReel (v20.109) — ЛЕНТА РЕДКОСТЕЙ после мини-игры шахты (только
-- клиент, Config.MineExpedition.RarityReel).
-- v20.114: лента ВЕРТИКАЛЬНАЯ и без заднего фона - карточки редкостей
-- крутятся сверху вниз, замедляются, «чуть-чуть не доезжают» до карточки
-- повыше и встают на выпавшую редкость. Победная карточка увеличивается,
-- остальные гаснут, за ней - крутящиеся лучи редкости (UiKit.Backdrop).
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

local function makeCard(parent, rarity, width, height)
	local color = Config.RarityColors[rarity] or Color3.fromRGB(200, 200, 200)
	local tile = Instance.new("Frame")
	tile.AnchorPoint = Vector2.new(0.5, 0.5)
	tile.Size = UDim2.fromOffset(width, height)
	tile.BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.55)
	tile.BorderSizePixel = 0
	tile.ZIndex = 3
	tile.Parent = parent
	Instance.new("UICorner", tile).CornerRadius = UDim.new(0, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = color
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = tile
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.15), color:Lerp(Color3.new(0, 0, 0), 0.35))
	grad.Rotation = 90
	grad.Parent = tile
	local gem = Instance.new("Frame")
	gem.Name = "Gem"
	gem.AnchorPoint = Vector2.new(0.5, 0.5)
	gem.Position = UDim2.fromScale(0.24, 0.5)
	gem.SizeConstraint = Enum.SizeConstraint.RelativeYY
	gem.Size = UDim2.fromScale(0.42, 0.42)
	gem.Rotation = 45
	gem.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.25)
	gem.BorderSizePixel = 0
	gem.ZIndex = 4
	gem.Parent = tile
	local gemStroke = Instance.new("UIStroke")
	gemStroke.Thickness = 2
	gemStroke.Color = Color3.fromRGB(15, 10, 20)
	gemStroke.Parent = gem
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.new(0.42, 0, 0.5, 0)
	label.Size = UDim2.new(0.54, 0, 0.5, 0)
	label.Text = rarity:upper()
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.new(1, 1, 1)
	label.ZIndex = 4
	style(label)
	local labelStroke = Instance.new("UIStroke")
	labelStroke.Thickness = 2
	labelStroke.Parent = label
	label.Parent = tile
	return tile
end

function RarityReel.Play(target, onDone)
	local cfg = Config.MineExpedition.RarityReel or {}
	local order = Config.RarityOrder
	local weights = cfg.Weights or {}
	local cardW = cfg.CardWidth or 300
	local cardH, gap = cfg.CardHeight or 92, cfg.TileGap or 10
	local step = cardH + gap
	local count = cfg.Tiles or 46
	local seconds = cfg.Seconds or 3.4
	local visibleCards = cfg.VisibleCards or 5
	local rng = Random.new()
	local targetIndex = count - 5
	local targetRank = table.find(order, target) or 1

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	-- телефон: всё уменьшаем, чтобы колонка влезла по высоте
	local fit = math.clamp((viewport.Y * 0.8) / (visibleCards * step), 0.45, 1)

	local gui = Instance.new("ScreenGui")
	gui.Name = "RarityReel"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 60
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	-- Лучи за победной карточкой (сначала скрыты).
	local rays
	if okKit and UiKit.Backdrop then
		local okRays, made = pcall(UiKit.Backdrop, gui, "Rays", target, {
			Size = UDim2.fromOffset(cardW * 1.9 * fit, cardW * 1.9 * fit),
			Color = Config.RarityColors[target],
			Transparency = 1,
			ZIndex = 1,
		})
		if okRays then rays = made end
	end

	-- Колонка без фона: CanvasGroup + градиент прозрачности гасит карточки к
	-- верхнему и нижнему краю.
	local band = Instance.new("CanvasGroup")
	band.Name = "Band"
	band.AnchorPoint = Vector2.new(0.5, 0.5)
	band.Position = UDim2.fromScale(0.5, 0.5)
	band.Size = UDim2.fromOffset(cardW * 1.3, visibleCards * step)
	band.BackgroundTransparency = 1
	band.BorderSizePixel = 0
	band.GroupTransparency = 1
	band.ZIndex = 2
	band.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = fit
	scale.Parent = band
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.22, 0.1),
		NumberSequenceKeypoint.new(0.78, 0.1), NumberSequenceKeypoint.new(1, 1),
	})
	fade.Parent = band

	-- Карточки: 1-я внизу, следующие выше; лента едет ВНИЗ, поэтому новые
	-- карточки приходят сверху.
	local strip = Instance.new("Frame")
	strip.Name = "Strip"
	strip.BackgroundTransparency = 1
	strip.Size = UDim2.new(1, 0, 0, 0)
	strip.Parent = band

	local rarities = {}
	for i = 1, count do rarities[i] = pickRarity(rng, weights, order) end
	rarities[targetIndex] = target
	-- дразнилка: следующая (выше, т.е. «ещё чуть-чуть») - редкость повыше
	if targetRank < #order and rng:NextNumber() < (cfg.TeaseChance or 0.75) then
		rarities[targetIndex + 1] = order[math.min(#order, targetRank + rng:NextInteger(1, 2))]
	end

	local tiles = {}
	for i, rarity in rarities do
		local tile = makeCard(strip, rarity, cardW, cardH)
		tile.Name = "Tile" .. i
		tile.Position = UDim2.new(0.5, 0, 0, -(i - 1) * step)
		tiles[i] = tile
	end

	-- Рамка-прицел по центру колонки.
	local marker = Instance.new("Frame")
	marker.Name = "Marker"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Position = UDim2.fromScale(0.5, 0.5)
	marker.Size = UDim2.fromOffset(cardW + 18, cardH + 14)
	marker.BackgroundTransparency = 1
	marker.ZIndex = 6
	marker.Parent = band
	Instance.new("UICorner", marker).CornerRadius = UDim.new(0, 16)
	local markerStroke = Instance.new("UIStroke")
	markerStroke.Thickness = 4
	markerStroke.Color = Color3.fromRGB(255, 215, 60)
	markerStroke.Parent = marker

	TweenService:Create(band, TweenInfo.new(0.2), { GroupTransparency = 0 }):Play()

	-- strip.Y = центр колонки, сдвинутый на позицию карточки.
	local center = visibleCards * step / 2
	local function yFor(index, inside)
		return center + (index - 1) * step + (inside or 0)
	end
	-- стоп с перелётом: выпавшая карточка уже чуть ниже центра, следующая
	-- (повыше редкостью) «почти заехала» - потом доводка обратно в центр
	local finalY = yFor(targetIndex, cardH * rng:NextNumber(0.28, 0.44))
	strip.Position = UDim2.new(0, 0, 0, center - rng:NextInteger(0, math.floor(cardH * 0.5)))
	local spin = TweenService:Create(strip, TweenInfo.new(seconds, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, 0, 0, finalY),
	})
	local lastTile = -1
	local tick = RunService.RenderStepped:Connect(function()
		local index = math.floor((strip.Position.Y.Offset - center) / step + 0.5)
		if index ~= lastTile then
			lastTile = index
			sfx("UiHover")
		end
	end)
	spin:Play()
	spin.Completed:Wait()
	tick:Disconnect()
	-- доводка ровно в центр
	local settle = TweenService:Create(strip, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, 0, 0, yFor(targetIndex)),
	})
	settle:Play()
	settle.Completed:Wait()

	-- АКЦЕНТ: остальные гаснут, победная крупнее, лучи сзади.
	local win = tiles[targetIndex]
	sfx("MineModifierReveal")
	TweenService:Create(markerStroke, TweenInfo.new(0.2), { Transparency = 1 }):Play()
	for i, tile in tiles do
		if i ~= targetIndex and math.abs(i - targetIndex) <= visibleCards then
			TweenService:Create(tile, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
			for _, d in tile:GetDescendants() do
				if d:IsA("TextLabel") then TweenService:Create(d, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
				elseif d:IsA("Frame") then TweenService:Create(d, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
				elseif d:IsA("UIStroke") then TweenService:Create(d, TweenInfo.new(0.25), { Transparency = 1 }):Play() end
			end
		end
	end
	if win then
		local winScale = Instance.new("UIScale")
		winScale.Parent = win
		win.ZIndex = 5
		TweenService:Create(winScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.18 }):Play()
		local glow = win:FindFirstChildOfClass("UIStroke")
		if glow then TweenService:Create(glow, TweenInfo.new(0.25), { Thickness = 6 }):Play() end
	end
	if rays then
		rays.Rotation = 0
		if UiKit.Spin then UiKit.Spin(rays, 40) end
		TweenService:Create(rays, TweenInfo.new(0.3), { ImageTransparency = 0.15 }):Play()
	end
	task.wait(cfg.HoldSeconds or 0.7)
	TweenService:Create(band, TweenInfo.new(0.22), { GroupTransparency = 1 }):Play()
	if rays then TweenService:Create(rays, TweenInfo.new(0.22), { ImageTransparency = 1 }):Play() end
	task.delay(0.3, function() gui:Destroy() end)
	if onDone then task.spawn(onDone) end
end

return RarityReel
