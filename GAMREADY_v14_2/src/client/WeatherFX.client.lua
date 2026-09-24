--------------------------------------------------------------------------------
-- WeatherFX (LocalScript)
-- Погодные ивенты (см. Config.WeatherEvents/WeatherService.lua) — сервер
-- меняет Lighting сам (обычная репликация свойств, отдельно слать не
-- нужно), а этот скрипт добавляет VFX и баннер-анонс.
--
-- VFX ПРИВЯЗАН К КАМЕРЕ, а не раскидан по конкретным точкам карты — так
-- эффект реально читается как "по всей карте" (куда бы игрок ни пошёл,
-- эффект всегда рядом), без необходимости знать конкретную геометрию
-- уровня, и намного дешевле, чем N расставленных по карте эмиттеров.
--
-- АССЕТЫ (тот же принцип, что PlaceholderFactory.lua — см. его шапку):
-- если в ReplicatedStorage/Assets лежит Model/Folder с именем
-- "<Kind>VFX" — берутся ВСЕ ParticleEmitter внутри него (можно положить
-- сколько угодно разных, все будут спавниться вместе на одном риге,
-- который следует за камерой — см. rig ниже). Нет такого ассета —
-- используется плейсхолдер (один простой ParticleEmitter), который уже
-- работает "из коробки", ничего донастраивать не обязательно.
--   NightVFX          → Model/Folder, внутри любые ParticleEmitter
--   RainVFX            → Model/Folder, внутри любые ParticleEmitter
--   ThunderstormVFX     → Model/Folder, внутри любые ParticleEmitter
--   BloodMoonVFX        → Model/Folder, внутри любые ParticleEmitter
--   SolarEclipseVFX      → Model/Folder, внутри любые ParticleEmitter
-- Свойства самих эмиттеров (Rate/Color/Speed и т.д.) переносятся как есть
-- из ассета — ничего не перезаписывается, кроме Enabled (сервис сам
-- включает/выключает нужный набор при смене погоды).
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local weatherRemote = ReplicatedStorage.Shared:WaitForChild("WeatherEvent", 10)
if not weatherRemote then
	warn("[WeatherFX] RemoteEvent WeatherEvent не появился — погодные VFX работать не будут, остальная игра не пострадает.")
	return
end

--------------------------------------------------------------------------------
-- РИГ — по прямому запросу переделан из точки перед камерой в большой
-- прозрачный ПРЯМОУГОЛЬНИК (не куб — шире и длиннее, чем в высоту),
-- центрированный прямо на игроке, так что игрок ВСЕГДА внутри него.
-- Эмиттеры (см. makeEmitter ниже) используют Shape=Box — тогда частицы
-- рождаются по всему ОБЪЁМУ этого прямоугольника, а не летят наружу из
-- одной далёкой точки, как раньше. Большая дистанция — чтобы частицы не
-- заканчивались резко на краю поля зрения.
--------------------------------------------------------------------------------
local rig = Instance.new("Part")
rig.Name = "WeatherRig"
rig.Size = Vector3.new(160, 70, 160)
rig.Transparency = 1
rig.Anchored = true
rig.CanCollide = false
rig.CanQuery = false
rig.CanTouch = false
rig.CastShadow = false
rig.Parent = workspace

RunService.RenderStepped:Connect(function()
	local camera = workspace.CurrentCamera
	if not camera then return end
	rig.CFrame = CFrame.new(camera.CFrame.Position)
end)

--------------------------------------------------------------------------------
-- ОДИН ParticleEmitter НА КАЖДЫЙ VfxKind — строятся один раз, дальше просто
-- Enabled true/false на нужном. Так проще и дешевле, чем создавать/уничтожать
-- эмиттеры на каждую смену ивента.
--------------------------------------------------------------------------------
local function findWeatherAsset(name)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then return nil end
	return assets:FindFirstChild(name) or assets:FindFirstChild(name, true)
end

local function makeEmitter(name, props)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Enabled = false
	-- Форма эмиссии — ПО ВСЕМУ ОБЪЁМУ rig'а (см. его комментарий выше), а
	-- не из одной точки. InAndOut — частицы могут рождаться где угодно
	-- внутри прямоугольника, а не только на его гранях (Surface).
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.InAndOut
	for key, value in props do
		emitter[key] = value
	end
	emitter.Parent = rig
	return emitter
end

-- Собирает набор ParticleEmitter для одного вида погоды. Если в
-- ReplicatedStorage/Assets есть "<kind>VFX" — клонирует ИЗ НЕГО все
-- ParticleEmitter (сколько угодно, любые свойства — ничего не
-- перезаписывается), парентит на rig и включает/выключает их все вместе.
-- Нет такого ассета — используется один плейсхолдер-эмиттер (placeholderProps)
-- как и раньше, чтобы эффект работал сразу, без обязательной донастройки.
local function buildEmitterSet(kind, placeholderProps)
	local asset = findWeatherAsset(kind .. "VFX")
	if asset then
		local found = {}
		for _, descendant in asset:GetDescendants() do
			if descendant:IsA("ParticleEmitter") then
				local clone = descendant:Clone()
				clone.Enabled = false
				clone.Parent = rig
				table.insert(found, clone)
			end
		end
		if #found > 0 then
			return found
		end
		warn(("[WeatherFX] %sVFX найден, но внутри нет ни одного ParticleEmitter — использую плейсхолдер."):format(kind))
	end
	return { makeEmitter(kind, placeholderProps) }
end

local emitterSets = {
	Night = buildEmitterSet("Night", {
		Color = ColorSequence.new(Color3.fromRGB(200, 210, 255)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 0.05) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.5, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(3, 6),
		Rate = 45, -- поднято с 18 — теперь частицы разлетаются по всему большому rig'у (см. его комментарий выше), не из одной точки, иначе выглядело бы слишком редко
		Speed = NumberRange.new(0.2, 0.6),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 0.05, 0),
		Rotation = NumberRange.new(0, 360),
		LightEmission = 0.8,
		LightInfluence = 0,
	}),
	Rain = buildEmitterSet("Rain", {
		Color = ColorSequence.new(Color3.fromRGB(150, 180, 220)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.08), NumberSequenceKeypoint.new(1, 0.08) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.55) }),
		Lifetime = NumberRange.new(0.6, 0.9),
		Rate = 220,
		Speed = NumberRange.new(38, 45),
		SpreadAngle = Vector2.new(3, 3),
		Acceleration = Vector3.new(0, -25, 0),
		LightEmission = 0.1,
		LightInfluence = 0.4,
	}),
	Thunderstorm = buildEmitterSet("Thunderstorm", {
		Color = ColorSequence.new(Color3.fromRGB(160, 200, 255)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 0.1) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.6) }),
		Lifetime = NumberRange.new(0.5, 0.8),
		Rate = 240,
		Speed = NumberRange.new(40, 48),
		SpreadAngle = Vector2.new(4, 4),
		Acceleration = Vector3.new(0, -25, 0),
		LightEmission = 0.3,
		LightInfluence = 0.3,
	}),
	BloodMoon = buildEmitterSet("BloodMoon", {
		Color = ColorSequence.new(Color3.fromRGB(160, 20, 20)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.75), NumberSequenceKeypoint.new(0.5, 0.6), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(5, 9),
		Rate = 16, -- поднято с 6 — та же причина, что и у Night выше
		Speed = NumberRange.new(0.3, 0.8),
		SpreadAngle = Vector2.new(180, 180),
		LightEmission = 0.2,
		LightInfluence = 0.5,
	}),
	SolarEclipse = buildEmitterSet("SolarEclipse", {
		Color = ColorSequence.new(Color3.fromRGB(120, 75, 30)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 3.5) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(0.5, 0.65), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(6, 10),
		Rate = 14, -- поднято с 5 — та же причина, что и у Night выше
		Speed = NumberRange.new(0.15, 0.4),
		SpreadAngle = Vector2.new(180, 180),
		LightEmission = 0,
		LightInfluence = 0.7,
	}),
}

local function setEmittersEnabled(kind, enabled)
	local set = emitterSets[kind]
	if not set then return end
	for _, emitter in set do
		emitter.Enabled = enabled
	end
end

--------------------------------------------------------------------------------
-- ПАДАЮЩИЕ КАПЛИ (Rain/BloodMoon) — по прямому запросу: реальные тонкие
-- квадратные Part'ы, физически падающие с неба вокруг игрока, а не только
-- ParticleEmitter. Пул ФИКСИРОВАННОГО размера, части ПЕРЕИСПОЛЬЗУЮТСЯ
-- (сбрасываются наверх по достижении низа), а не создаются/уничтожаются
-- каждый раз — так десятки капель падают непрерывно почти бесплатно по
-- производительности (простая арифметика на кадр, без Instance.new в
-- рантайме). Держится на том же rig, что и частицы выше — вокруг камеры,
-- а не в фиксированных мировых координатах, поэтому всегда рядом с
-- игроком вне зависимости от размера карты.
local function buildFallingPool(count, size, color, material, transparency, fallSpeed, radius, dropHeight)
	local parts = {}
	for i = 1, count do
		local part = Instance.new("Part")
		part.Name = "Drop"
		part.Size = size
		part.Color = color
		part.Material = material
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1 -- скрыта, пока пул не включён
		part.Parent = workspace
		parts[i] = part
	end
	return {
		Parts = parts,
		FallSpeed = fallSpeed,
		Radius = radius,
		DropHeight = dropHeight,
		Transparency = transparency,
		Enabled = false,
	}
end

local function randomDropPosition(pool, originY, yOffset)
	local angle = math.random() * math.pi * 2
	local dist = math.random() * pool.Radius
	local rigPos = rig.Position
	return CFrame.new(rigPos.X + math.cos(angle) * dist, originY + yOffset, rigPos.Z + math.sin(angle) * dist)
end

local function setFallingPoolEnabled(pool, enabled)
	pool.Enabled = enabled
	local originY = rig.Position.Y
	for _, part in pool.Parts do
		if enabled then
			-- Случайная высота ПО ВСЕМУ диапазону при включении — иначе все
			-- капли стартовали бы с одной высоты синхронной "волной".
			part.CFrame = randomDropPosition(pool, originY, (math.random() - 0.5) * pool.DropHeight)
			part.Transparency = pool.Transparency
		else
			part.Transparency = 1
		end
	end
end

local fallingPools = {
	Rain = buildFallingPool(28, Vector3.new(0.14, 0.42, 0.14), Color3.fromRGB(150, 190, 230), Enum.Material.Glass, 0.25, 42, 34, 48),
	BloodMoon = buildFallingPool(10, Vector3.new(0.13, 0.4, 0.13), Color3.fromRGB(170, 20, 20), Enum.Material.Neon, 0.15, 18, 26, 40),
	-- Лёгкий дождь ВО ВРЕМЯ ГРОЗЫ ("немного") — по прямому запросу, отдельный
	-- пул поменьше, той же формы/цвета, что у Rain, включается вместе с
	-- Thunderstorm (см. applyWeather ниже).
	ThunderstormRain = buildFallingPool(10, Vector3.new(0.14, 0.42, 0.14), Color3.fromRGB(150, 190, 230), Enum.Material.Glass, 0.3, 42, 30, 46),
}

RunService.Heartbeat:Connect(function(dt)
	local originY = rig.Position.Y
	for _, pool in fallingPools do
		if pool.Enabled then
			for _, part in pool.Parts do
				local pos = part.Position
				local newY = pos.Y - pool.FallSpeed * dt
				if newY < originY - pool.DropHeight * 0.5 then
					part.CFrame = randomDropPosition(pool, originY, pool.DropHeight * 0.5)
				else
					part.Position = Vector3.new(pos.X, newY, pos.Z)
				end
			end
		end
	end
end)


--------------------------------------------------------------------------------
-- ВСПЫШКИ МОЛНИЙ — только на Thunderstorm: полноэкранная белая плашка,
-- редкая и короткая, дешёвая замена честному молниевому VFX.
--------------------------------------------------------------------------------
local lightningGui = Instance.new("ScreenGui")
lightningGui.Name = "WeatherLightning"
lightningGui.IgnoreGuiInset = true
lightningGui.DisplayOrder = 40
lightningGui.ResetOnSpawn = false
lightningGui.Parent = playerGui

local lightningFlash = Instance.new("Frame")
lightningFlash.Size = UDim2.fromScale(1, 1)
lightningFlash.BackgroundColor3 = Color3.new(1, 1, 1)
lightningFlash.BackgroundTransparency = 1
lightningFlash.ZIndex = 1
lightningFlash.Parent = lightningGui

local lightningLoopToken = 0

local function stopLightningLoop()
	lightningLoopToken += 1
end

-- Молния — цепочка Beam-сегментов между дрожащими (midpoint displacement)
-- точками от "неба" до "земли" рядом с игроком. Beam — сознательный выбор
-- по итогам изучения форума разработчиков: это стандартный лёгкий приём
-- для молний в Roblox (готовая кривая/дрожь у самого Beam, не нужно
-- вручную городить десятки мелких Part'ов ради того же визуального
-- результата) — молния короткоживущая (0.5 сек, см. Debris ниже) и
-- редкая (см. startLightningLoop), так что даже создание/уничтожение
-- нескольких Instance на вспышку не создаёт постоянной нагрузки.
local function spawnLightningBolt()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local cf = camera.CFrame
	local angle = math.random() * math.pi * 2
	local dist = 18 + math.random() * 22
	local groundPoint = cf.Position + cf.LookVector * 35 + Vector3.new(math.cos(angle) * dist, -8, math.sin(angle) * dist)
	local topPoint = groundPoint + Vector3.new(0, 85, 0)

	local holder = Instance.new("Folder")
	holder.Name = "LightningBolt"
	holder.Parent = workspace

	local SEGMENTS = 7
	local points = { topPoint }
	for i = 2, SEGMENTS do
		local t = (i - 1) / SEGMENTS
		local point = topPoint:Lerp(groundPoint, t)
		-- Джиттер сильнее у "неба" и затухает к земле — классический
		-- зигзаг молнии через смещение средних точек (midpoint displacement).
		local jitter = (1 - t) * 6 + 1.5
		point += Vector3.new((math.random() - 0.5) * jitter, 0, (math.random() - 0.5) * jitter)
		points[i] = point
	end
	points[SEGMENTS + 1] = groundPoint

	-- НЕОНОВЫЕ ПАРТЫ вместо Beam — по прямому запросу ("было бы прикольно").
	-- Каждый сегмент зигзага — реальный светящийся Part, натянутый между
	-- двумя соседними точками (CFrame.lookAt + масштаб по расстоянию), плюс
	-- более толстая полупрозрачная Neon-обёртка вокруг него для эффекта
	-- свечения (тот же трюк "core + glow", что часто используют для
	-- неоновых эффектов — второй Part вместо честного источника света,
	-- дешевле по производительности). Всего 14 Part'ов на молнию (7
	-- сегментов × 2), все Anchored/CanCollide=false и живут 0.5 сек — с
	-- редкими вспышками (раз в 4-13 сек) это не создаёт постоянной нагрузки.
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local segmentLength = (b - a).Magnitude
		if segmentLength > 0.01 then
			local segmentCFrame = CFrame.lookAt(a, b) * CFrame.new(0, 0, -segmentLength * 0.5)

			local core = Instance.new("Part")
			core.Name = "LightningCore"
			core.Material = Enum.Material.Neon
			core.Color = Color3.fromRGB(235, 240, 255)
			core.Size = Vector3.new(0.3, 0.3, segmentLength)
			core.Anchored = true
			core.CanCollide = false
			core.CanQuery = false
			core.CanTouch = false
			core.CastShadow = false
			core.CFrame = segmentCFrame
			core.Parent = holder

			local glow = Instance.new("Part")
			glow.Name = "LightningGlow"
			glow.Material = Enum.Material.Neon
			glow.Color = Color3.fromRGB(150, 190, 255)
			glow.Transparency = 0.55
			glow.Size = Vector3.new(0.85, 0.85, segmentLength)
			glow.Anchored = true
			glow.CanCollide = false
			glow.CanQuery = false
			glow.CanTouch = false
			glow.CastShadow = false
			glow.CFrame = segmentCFrame
			glow.Parent = holder
		end
	end

	-- Плавное угасание вместо резкого исчезновения по Debris — по прямому
	-- запросу. Держим яркой короткое время, потом твин Transparency у всех
	-- частей одновременно, и только ПОСЛЕ затухания финальная очистка.
	task.delay(0.12, function()
		if not holder.Parent then return end
		for _, part in holder:GetChildren() do
			if part:IsA("BasePart") then
				TweenService:Create(part, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Transparency = 1,
				}):Play()
			end
		end
	end)
	Debris:AddItem(holder, 0.55)
end

local function startLightningLoop()
	lightningLoopToken += 1
	local myToken = lightningLoopToken
	task.spawn(function()
		while myToken == lightningLoopToken do
			task.wait(4 + math.random() * 9) -- редкая, не на каждый кадр
			if myToken ~= lightningLoopToken then return end
			spawnLightningBolt()
			local flashTween1 = TweenService:Create(lightningFlash, TweenInfo.new(0.04), { BackgroundTransparency = 0.55 })
			flashTween1:Play()
			flashTween1.Completed:Wait()
			if myToken ~= lightningLoopToken then return end
			local flashTween2 = TweenService:Create(lightningFlash, TweenInfo.new(0.3), { BackgroundTransparency = 1 })
			flashTween2:Play()
		end
	end)
end

--------------------------------------------------------------------------------
-- ОБРАБОТЧИК СОБЫТИЯ
--------------------------------------------------------------------------------
local currentVfxKind = nil

local function applyWeather(payload)
	-- Гасим VFX предыдущего ивента (включая "Clear", когда payload = nil).
	if currentVfxKind then
		setEmittersEnabled(currentVfxKind, false)
		if fallingPools[currentVfxKind] then
			setFallingPoolEnabled(fallingPools[currentVfxKind], false)
		end
	end
	setFallingPoolEnabled(fallingPools.ThunderstormRain, false)
	stopLightningLoop()
	currentVfxKind = payload and payload.VfxKind or nil

	if currentVfxKind then
		setEmittersEnabled(currentVfxKind, true)
		if fallingPools[currentVfxKind] then
			setFallingPoolEnabled(fallingPools[currentVfxKind], true)
		end
	end
	if currentVfxKind == "Thunderstorm" then
		startLightningLoop()
		-- Немного дождя во время грозы — по прямому запросу.
		setFallingPoolEnabled(fallingPools.ThunderstormRain, true)
	end
	-- Анонс — через обычный Toast (см. WeatherService.lua:applyEvent,
	-- Services.NotifyService:Show), не отдельным баннером: один-единственный
	-- путь показа уведомлений во всей игре, без дублирования.
end

weatherRemote.OnClientEvent:Connect(applyWeather)
