--------------------------------------------------------------------------------
-- SellFx (LocalScript) — ВСЯ ВИЗУАЛКА ПРОДАЖИ И МОНЕТОК.
--
-- Сервер больше ничего не двигает: он шлёт
--   SellFx      (всем)   — проданный кусок руды: откуда, куда, чей, сколько;
--   CoinBurstFx (игроку) — откуда высыпать монетки и "вес" начисления.
-- Здесь считаются дуги, вращение, отскоки и магнит — каждый кадр на
-- клиенте, поэтому плавно при любом пинге.
--
--   1. ПОЛЁТ РУДЫ. Короткий подскок → дуга Безье в банк с вращением и
--      сжатием → вспышка цвета руды в точке входа. Дуги у соседних кусков
--      чуть разные (боковой разброс) — поток руды выглядит как поток.
--   2. СЧЁТЧИК НАД БАНКОМ (только свой). "+$12.4K" копится за всю
--      продажу, подпрыгивает на каждом куске, рядом — курс биржи цветом
--      его корзины. Исчезает через CounterHideDelay после последнего куска.
--   3. МОНЕТКИ. Квадратные золотые плитки фонтаном из источника, кувырок,
--      отскок, пауза, магнит к игроку, звон с нарастающим тоном, искра.
--      Одна деталь на монету, BulkMoveTo, пул, потолок и слияние россыпей.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local CrystalUtil = require(ReplicatedStorage.Shared.CrystalUtil)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)
local WorldUi = require(ReplicatedStorage.Shared.WorldUi) -- v20: стили мировых надписей

local player = Players.LocalPlayer
local shared = ReplicatedStorage:WaitForChild("Shared")
local sellRemote = shared:WaitForChild("SellFx", 30)
local coinRemote = shared:WaitForChild("CoinBurstFx", 30)

local SELL = Config.SellFx
local COIN = Config.CoinFx

local fxFolder = Instance.new("Folder")
fxFolder.Name = "LocalSellFx"
fxFolder.Parent = workspace

local rng = Random.new()
local function range(pair) return pair[1] + rng:NextNumber() * (pair[2] - pair[1]) end

local function bezier(p0, p1, p2, t)
	local u = 1 - t
	return p0 * (u * u) + p1 * (2 * u * t) + p2 * (t * t)
end

local function stripPhysics(root)
	for _, part in root:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	if root:IsA("BasePart") then
		root.Anchored = true
		root.CanCollide = false
		root.CanQuery = false
		root.CanTouch = false
	end
end

--------------------------------------------------------------------------------
-- ВСПЫШКА у банка
--------------------------------------------------------------------------------
local function flash(position, color)
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Material = Enum.Material.Neon
	ball.Color = color
	ball.Size = Vector3.new(0.4, 0.4, 0.4)
	ball.Transparency = 0.15
	ball.Position = position
	stripPhysics(ball)
	ball.Parent = fxFolder
	local size = SELL.FlashSize
	local tween = TweenService:Create(ball, TweenInfo.new(SELL.FlashTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(size, size, size),
		Transparency = 1,
	})
	tween.Completed:Connect(function() ball:Destroy() end)
	tween:Play()
end

--------------------------------------------------------------------------------
-- ПОЛЁТ РУДЫ
--------------------------------------------------------------------------------
local function colorOf(root)
	if root:IsA("BasePart") then return root.Color end
	local part = root:FindFirstChildWhichIsA("BasePart", true)
	return part and part.Color or Color3.fromRGB(255, 220, 120)
end

-- Локальная копия проданного куска. Сервер свой кристалл уже удалил и
-- прислал только тип руды — строим ту же модель, что лежала в тележке.
-- Нет типа (старые кристаллы по тиру) — неоновый кубик его цвета/размера.
local function buildOre(payload)
	local info = payload.Ore and Config.OreByKey[payload.Ore]
	local ok, crystal = false, nil
	if info then
		local variant = Config.OreVariants and Config.OreVariants[payload.Variant or 1]
		ok, crystal = pcall(function()
			if payload.Smelted then return PlaceholderFactory.OreIngot(info, variant) end
			return PlaceholderFactory.OreCrystal(info, variant)
		end)
	elseif payload.Tier then
		ok, crystal = pcall(PlaceholderFactory.Crystal, payload.Tier)
	end
	if not ok or not crystal then
		crystal = Instance.new("Part")
		crystal.Size = typeof(payload.Size) == "Vector3" and payload.Size or Vector3.new(0.9, 0.9, 0.9)
		crystal.Color = typeof(payload.Color) == "Color3" and payload.Color or Color3.fromRGB(255, 220, 120)
		crystal.Material = Enum.Material.Neon
	end
	for _, child in crystal:GetDescendants() do
		if child:IsA("BillboardGui") or child:IsA("Script") or child:IsA("LocalScript") or child:IsA("ProximityPrompt") then
			child:Destroy()
		end
	end
	stripPhysics(crystal)
	crystal.Parent = fxFolder
	return crystal
end

-- Все летящие куски — в одном списке и одном цикле кадра (раньше у каждого
-- было своё подключение к RenderStepped). Масштаб модели меняется
-- ступенями по 10%: Model:ScaleTo обходит все детали модели, и вызывать его
-- каждый кадр для каждого куска — заметная доля кадра при продаже тележки.
local flights = {}

local function flyOre(payload)
	local to = payload.To
	local from = payload.From
	if typeof(to) ~= "Vector3" or typeof(from) ~= "Vector3" then return end
	local object = buildOre(payload)
	local isModel = object:IsA("Model")
	local root = isModel and (CrystalUtil.GetRoot(object) or object:FindFirstChildWhichIsA("BasePart", true)) or object
	local distance = (to - from).Magnitude
	local lift = from + Vector3.new(0, 1.2, 0)
	local flat = (to - from) * Vector3.new(1, 0, 1)
	local sideAxis = flat.Magnitude > 0.01 and Vector3.new(-flat.Z, 0, flat.X).Unit or Vector3.xAxis
	table.insert(flights, {
		Object = object,
		IsModel = isModel,
		Color = colorOf(root or object),
		BaseRotation = isModel and (object:GetPivot() - object:GetPivot().Position) or (object.CFrame - object.Position),
		BaseScale = isModel and object:GetScale() or 1,
		StartSize = not isModel and object.Size or nil,
		AppliedScale = 1,
		From = from,
		Lift = lift,
		To = to,
		Control = lift:Lerp(to, 0.5)
			+ Vector3.new(0, SELL.ArcHeight + distance * SELL.ArcPerStud, 0)
			+ sideAxis * ((rng:NextNumber() * 2 - 1) * SELL.SideJitter),
		SpinAxis = Vector3.new(rng:NextNumber() - 0.5, 1, rng:NextNumber() - 0.5).Unit,
		Started = os.clock(),
	})
end

local function placeFlight(flight, position, angle, scale)
	local cf = CFrame.new(position) * CFrame.fromAxisAngle(flight.SpinAxis, angle) * flight.BaseRotation
	if flight.IsModel then
		local stepped = math.max(0.1, math.floor(scale * 10 + 0.5) / 10)
		if stepped ~= flight.AppliedScale then
			flight.AppliedScale = stepped
			pcall(function() flight.Object:ScaleTo(flight.BaseScale * stepped) end)
		end
		flight.Object:PivotTo(cf)
	else
		flight.Object.Size = flight.StartSize * math.max(scale, 0.05)
		flight.Object.CFrame = cf
	end
end

RunService.RenderStepped:Connect(function()
	if #flights == 0 then return end
	local now = os.clock()
	local total = SELL.PopTime + SELL.FlightTime
	for index = #flights, 1, -1 do
		local flight = flights[index]
		local elapsed = now - flight.Started
		if not flight.Object.Parent then
			table.remove(flights, index)
		elseif elapsed < SELL.PopTime then
			local t = elapsed / SELL.PopTime
			placeFlight(flight, flight.From:Lerp(flight.Lift, t), 0, 1 + (SELL.PopScale - 1) * math.sin(t * math.pi * 0.5))
		elseif elapsed >= total then
			flash(flight.To, flight.Color)
			flight.Object:Destroy()
			table.remove(flights, index)
		else
			local t = math.clamp((elapsed - SELL.PopTime) / SELL.FlightTime, 0, 1)
			local eased = t * t * (3 - 2 * t) -- smoothstep: мягкий старт и финиш
			local scale = SELL.PopScale + (SELL.EndScale - SELL.PopScale) * (t ^ 1.6)
			placeFlight(flight, bezier(flight.Lift, flight.Control, flight.To, eased), eased * SELL.SpinTurns * math.pi * 2, scale)
		end
	end
end)

--------------------------------------------------------------------------------
-- СЧЁТЧИК ПРОДАЖИ НАД БАНКОМ
--------------------------------------------------------------------------------
local counterAnchor = Instance.new("Part")
counterAnchor.Name = "SaleCounterAnchor"
counterAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
counterAnchor.Transparency = 1
stripPhysics(counterAnchor)
counterAnchor.Parent = fxFolder

local counterGui = Instance.new("BillboardGui")
counterGui.Name = "SaleCounter"
counterGui.Size = UDim2.fromOffset(300, 110)
counterGui.StudsOffset = Vector3.new(0, SELL.CounterHeight, 0)
counterGui.AlwaysOnTop = true
counterGui.LightInfluence = 0
counterGui.MaxDistance = 250
counterGui.Enabled = false
counterGui.Adornee = counterAnchor
counterGui.Parent = counterAnchor

local function strokeLabel(name, y, height, textSize, color)
	local label = WorldUi.Text(nil, "Text", "Heading")
	label.Name = name
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, y)
	label.Size = UDim2.new(1, 0, 0, height)
	label.TextSize = textSize
	label.TextColor3 = color
	label.Parent = counterGui
	return label
end
local amountLabel = strokeLabel("Amount", 0, 64, 54, Color3.fromRGB(90, 255, 90))
local marketLabel = strokeLabel("Market", 66, 36, 28, Color3.new(1, 1, 1))
local amountScale = Instance.new("UIScale")
amountScale.Parent = amountLabel

local saleTotal = 0
local saleToken = 0

local function bucketColor(bucketId)
	for _, bucket in Config.Merchant.Market.Buckets do
		if bucket.Id == bucketId then return bucket.Color, bucket.Label end
	end
	return Color3.new(1, 1, 1), ""
end

local function bumpCounter(payload)
	saleTotal += tonumber(payload.Payout) or 0
	saleToken += 1
	local myToken = saleToken
	counterAnchor.Position = payload.To
	amountLabel.Text = "+$" .. NumberFormat.abbreviate(saleTotal)
	local market = tonumber(payload.Market) or workspace:GetAttribute("MarketMultiplier") or 1
	local color, label = bucketColor(workspace:GetAttribute("MarketBucket"))
	marketLabel.Text = ("x%.2f %s"):format(market, label)
	marketLabel.TextColor3 = color
	counterGui.Enabled = true
	amountScale.Scale = 1.18
	TweenService:Create(amountScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(SELL.CounterHideDelay, function()
		if myToken ~= saleToken then return end
		counterGui.Enabled = false
		saleTotal = 0
	end)
end

--------------------------------------------------------------------------------
-- МОНЕТКИ — квадратные золотые плитки
--------------------------------------------------------------------------------
local pool = {}
local active = {}

local function newCoin()
	local coin = Instance.new("Part")
	coin.Name = "Coin"
	coin.Shape = Enum.PartType.Block
	coin.Size = COIN.CoinSize
	coin.Color = COIN.CoinColor
	coin.Material = Enum.Material.SmoothPlastic
	stripPhysics(coin)
	coin.CastShadow = false
	coin.Locked = true
	return coin
end

local function takeCoin()
	local coin = table.remove(pool) or newCoin()
	coin.Transparency = 0
	coin.Parent = fxFolder
	return coin
end

local function releaseCoin(coin)
	if #pool < COIN.PoolSize then
		-- В пуле деталь остаётся в папке, просто уезжает далеко вниз и
		-- прячется: снятие/возврат Parent у десятков деталей в кадр —
		-- тоже работа движка, а так пул почти бесплатен.
		coin.Transparency = 1
		coin.CFrame = CFrame.new(0, -10000, 0)
		table.insert(pool, coin)
	else
		coin:Destroy()
	end
end

-- Звон с нарастающим тоном (не чаще ChimeMinGap).
local sounds = {}
do
	local sound = Config.Sounds and Config.Sounds.CoinCollect
	local ids = {}
	if sound then
		if sound.Variants then for _, id in sound.Variants do table.insert(ids, id) end end
		if sound.Id and sound.Id ~= 0 then table.insert(ids, sound.Id) end
	end
	for index = 1, 4 do
		local id = ids[((index - 1) % math.max(#ids, 1)) + 1]
		if id then
			local instance = Instance.new("Sound")
			instance.SoundId = typeof(id) == "number" and ("rbxassetid://" .. id) or id
			instance.Volume = (sound.Volume or 0.5) * 0.7
			instance.Parent = SoundService
			table.insert(sounds, instance)
		end
	end
end
local chain = 0
local lastChimeAt = 0
local soundIndex = 0
local function chime()
	if #sounds == 0 then return end
	local now = os.clock()
	if now - lastChimeAt < COIN.ChimeMinGap then return end
	if now - lastChimeAt > COIN.ChainResetSeconds then chain = 0 end
	lastChimeAt = now
	chain += 1
	soundIndex = soundIndex % #sounds + 1
	local sound = sounds[soundIndex]
	sound.PlaybackSpeed = math.min(COIN.PitchMax, COIN.PitchStart + chain * COIN.PitchStep)
	sound.TimePosition = 0
	sound:Play()
end

-- Искры подбора — тоже из пула (раньше Instance.new на каждую монету).
local sparkPool = {}
local function sparkle(position)
	local spark = table.remove(sparkPool)
	if not spark then
		spark = Instance.new("Part")
		spark.Shape = Enum.PartType.Block
		spark.Material = Enum.Material.Neon
		spark.Color = Color3.fromRGB(255, 240, 150)
		stripPhysics(spark)
		spark.CastShadow = false
		spark.Parent = fxFolder
	end
	spark.Size = Vector3.new(0.3, 0.3, 0.3)
	spark.Transparency = 0
	spark.CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(45), math.rad(45))
	local tween = TweenService:Create(spark, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(1.3, 1.3, 1.3), Transparency = 1,
	})
	tween.Completed:Connect(function()
		spark.CFrame = CFrame.new(0, -10000, 0)
		if #sparkPool < 16 then table.insert(sparkPool, spark) else spark:Destroy() end
	end)
	tween:Play()
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function groundY(position, fallback)
	local filter = { fxFolder }
	if player.Character then table.insert(filter, player.Character) end
	rayParams.FilterDescendantsInstances = filter
	local hit = workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -60, 0), rayParams)
	return hit and hit.Position.Y or fallback
end

local function spawnCoins(origin, count)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	origin = origin or (hrp.Position + Vector3.new(0, 3, 0))
	count = math.min(count, COIN.MaxActive - #active)
	if count <= 0 then return end
	local floor = groundY(origin, origin.Y - 3) + COIN.CoinSize.Y / 2
	for _ = 1, count do
		local angle = rng:NextNumber() * math.pi * 2
		local sideSpeed = range(COIN.SideSpeed)
		table.insert(active, {
			Coin = takeCoin(),
			Position = origin + Vector3.new(0, 1, 0),
			Velocity = Vector3.new(math.cos(angle) * sideSpeed, range(COIN.LaunchSpeed), math.sin(angle) * sideSpeed),
			Floor = floor,
			Phase = "Air",
			Bounces = 0,
			RestUntil = 0,
			Spin = range(COIN.SpinSpeed),
			Angle = rng:NextNumber() * math.pi * 2,
			Yaw = angle,
			Born = os.clock(),
		})
	end
end

-- Слияние частых россыпей: продажа тележки присылает их пачкой, и каждая
-- по отдельности лишь множит детали. Всё, что пришло за MergeWindow,
-- высыпается одной горстью.
local pendingCount = 0
local pendingOrigin = nil
local pendingScheduled = false
local function burst(origin, weight)
	local count = math.clamp(math.floor(COIN.MinCoins + (tonumber(weight) or 1) * COIN.CoinsPerWeight), COIN.MinCoins, COIN.MaxCoins)
	pendingCount = math.min(COIN.MaxCoins, pendingCount + count)
	pendingOrigin = pendingOrigin or origin
	if pendingScheduled then return end
	pendingScheduled = true
	task.delay(COIN.MergeWindow, function()
		pendingScheduled = false
		local total, from = pendingCount, pendingOrigin
		pendingCount, pendingOrigin = 0, nil
		spawnCoins(from, total)
	end)
end

local movedParts = {}
local movedFrames = {}

RunService.RenderStepped:Connect(function(dt)
	if #active == 0 then return end
	dt = math.min(dt, 1 / 20)
	local now = os.clock()
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local target = hrp and (hrp.Position + Vector3.new(0, 0.8, 0))
	table.clear(movedParts)
	table.clear(movedFrames)
	for index = #active, 1, -1 do
		local coin = active[index]
		local done = now - coin.Born > COIN.MaxLifetime
		if coin.Phase == "Air" then
			coin.Velocity += Vector3.new(0, -COIN.Gravity * dt, 0)
			coin.Position += coin.Velocity * dt
			if coin.Position.Y <= coin.Floor and coin.Velocity.Y < 0 then
				coin.Position = Vector3.new(coin.Position.X, coin.Floor, coin.Position.Z)
				coin.Bounces += 1
				if coin.Bounces >= 2 or math.abs(coin.Velocity.Y) < 6 then
					coin.Phase = "Rest"
					coin.RestUntil = now + range(COIN.RestTime)
					coin.Velocity = Vector3.zero
				else
					coin.Velocity = Vector3.new(coin.Velocity.X * 0.55, -coin.Velocity.Y * COIN.Bounce, coin.Velocity.Z * 0.55)
				end
			end
		elseif coin.Phase == "Rest" then
			coin.Spin = math.max(2, coin.Spin * 0.92)
			if now >= coin.RestUntil then coin.Phase = "Magnet" end
		elseif coin.Phase == "Magnet" and target then
			local offset = target - coin.Position
			local distance = offset.Magnitude
			if distance <= COIN.CollectDistance then
				chime()
				sparkle(coin.Position)
				done = true
			else
				-- Небольшой подъём: монетка "срывается" с земли, а не ползёт.
				coin.Velocity += (offset.Unit * COIN.MagnetAccel + Vector3.new(0, 20, 0)) * dt
				if coin.Velocity.Magnitude > COIN.MagnetMaxSpeed then
					coin.Velocity = coin.Velocity.Unit * COIN.MagnetMaxSpeed
				end
				-- Гасим скорость мимо цели — иначе монетка кружит вокруг игрока.
				local along = coin.Velocity:Dot(offset.Unit)
				local lateral = coin.Velocity - offset.Unit * along
				coin.Velocity = offset.Unit * along + lateral * 0.85
				coin.Position += coin.Velocity * dt
			end
		elseif not target then
			done = true
		end

		if done then
			releaseCoin(coin.Coin)
			table.remove(active, index)
		else
			coin.Angle += coin.Spin * dt
			-- Плитка кувыркается вокруг своей оси и медленно поворачивается —
			-- то плашмя, то ребром: квадрат читается с любого ракурса.
			table.insert(movedParts, coin.Coin)
			table.insert(movedFrames, CFrame.new(coin.Position)
				* CFrame.Angles(0, coin.Yaw + coin.Angle * 0.35, 0)
				* CFrame.Angles(coin.Angle, 0, 0))
		end
	end
	-- Один вызов движка на все монеты вместо присвоения CFrame каждой.
	if #movedParts > 0 then
		workspace:BulkMoveTo(movedParts, movedFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end)

--------------------------------------------------------------------------------
-- ПОДПИСКИ
--------------------------------------------------------------------------------
if sellRemote then
	sellRemote.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then return end
		-- Чужие продажи рисуем только рядом: руда в банк летит у всех на
		-- глазах, но дальний банк не стоит кадров.
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local mine = payload.Holder == player.UserId
		if not mine and (not hrp or not payload.To or (hrp.Position - payload.To).Magnitude > 220) then
			return
		end
		task.spawn(flyOre, payload)
		if mine and (tonumber(payload.Payout) or 0) > 0 then
			bumpCounter(payload)
		end
	end)
end

if coinRemote then
	coinRemote.OnClientEvent:Connect(function(origin, weight)
		burst(typeof(origin) == "Vector3" and origin or nil, weight)
	end)
end
