--------------------------------------------------------------------------------
-- WeatherFX (LocalScript) v20.26 — эффекты погоды ПО ВСЕЙ КАРТЕ и молнии.
--
-- Сервер (WeatherService) меняет свет и небо сам (Lighting/Atmosphere
-- реплицируются) и присылает, какие эффекты включить: payload.Effects —
-- список имён из БИБЛИОТЕКИ ЭФФЕКТОВ, payload.Lightning — молнии.
--
-- БИБЛИОТЕКА: ReplicatedStorage.Assets.WeatherFX.<Имя> — Folder/Model:
--   • все ParticleEmitter внутри — эмиттеры эффекта (свойства как есть;
--     Rate = частиц в секунду на ОДНУ клетку карты, см. Config Fx.CellSize);
--   • все Sound внутри — фоновый звук, играет по кругу, пока эффект идёт;
--   • атрибуты папки: Mode = "Fall" | "Float" | "Ground" (см. ниже),
--     Height = число (стадов).
-- Нет такой папки — встроенный плейсхолдер (PLACEHOLDERS ниже). Какие
-- эффекты в какую погоду — Config.WeatherEvents.Events[].Effects и ClearEffects.
--
-- КАК ЭФФЕКТ ЛЕЖИТ НА КАРТЕ: карта делится на клетки CellSize×CellSize.
-- В каждой клетке рядом с камерой (Radius) стоит невидимая деталь с
-- эмиттерами; частицы живут В МИРЕ (не едут за камерой) — дождь идёт по
-- всей карте, как в Grow a Garden. Дальние клетки реже (FarRate), за
-- Radius — выключены. Режимы:
--   Fall   — плита на высоте Height над землёй клетки (и не ниже камеры
--            + 30): дождь, пепел, снег; эмиттер сыплет ВНИЗ;
--   Float  — объём от земли до Height: светлячки, искры, пыльца;
--   Ground — несколько точек прямо на земле клетки: брызги, туман.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local weatherRemote = ReplicatedStorage.Shared:WaitForChild("WeatherEvent", 10)
if not weatherRemote then
	warn("[WeatherFX] RemoteEvent WeatherEvent не появился - погодные VFX работать не будут, остальная игра не пострадает.")
	return
end

local WEATHER = Config.WeatherEvents or {}
local FX = WEATHER.Fx or {}
local CELL = FX.CellSize or 64
local RADIUS = FX.Radius or 260
local FULL_RADIUS = FX.FullRateRadius or 100
local FAR_RATE = FX.FarRate or 0.3
local FADE = math.max(FX.FadeSeconds or 2.5, 0.1)
local GROUND_POINTS = 6 -- точек на клетку в режиме Ground

local fxFolder = Instance.new("Folder")
fxFolder.Name = "WeatherFX"
fxFolder.Parent = workspace

--------------------------------------------------------------------------------
-- ВСТРОЕННЫЕ ЭФФЕКТЫ (плейсхолдеры). Свой вид — Assets/WeatherFX/<Имя>.
--------------------------------------------------------------------------------
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local RAIN_TEXTURE = (FX.RainTexture and FX.RainTexture ~= "") and FX.RainTexture or SMOKE
local function seq(...) return NumberSequence.new(...) end
local function keys(list)
	local out = {}
	for _, k in list do table.insert(out, NumberSequenceKeypoint.new(k[1], k[2])) end
	return NumberSequence.new(out)
end

local function rain(color, rate, speed, size, lifetime)
	return {
		Texture = RAIN_TEXTURE,
		Color = ColorSequence.new(color),
		Size = seq(size),
		Squash = seq(2.4), -- вытянуто вдоль полёта — штрих, а не точка
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Transparency = keys({ { 0, 0.45 }, { 0.8, 0.5 }, { 1, 1 } }),
		Lifetime = lifetime,
		Rate = rate,
		Speed = speed,
		SpreadAngle = Vector2.new(2, 2),
		Acceleration = Vector3.new(0, -20, 0),
		EmissionDirection = Enum.NormalId.Bottom,
		LightEmission = 0.15,
		LightInfluence = 0.6,
		WindAffectsDrag = true, -- наклон дождя — от workspace.GlobalWind
		Drag = 0.35,
	}
end

local PLACEHOLDERS = {
	RainDrops = { Mode = "Fall", Height = 70, Emitters = {
		rain(Color3.fromRGB(200, 220, 245), 70, NumberRange.new(70, 80), 0.2, NumberRange.new(1.1, 1.3)),
	} },
	StormRain = { Mode = "Fall", Height = 75, Emitters = {
		rain(Color3.fromRGB(190, 210, 240), 120, NumberRange.new(85, 95), 0.24, NumberRange.new(1, 1.15)),
	} },
	BloodDrizzle = { Mode = "Fall", Height = 60, Emitters = {
		rain(Color3.fromRGB(190, 30, 40), 18, NumberRange.new(50, 58), 0.2, NumberRange.new(1.3, 1.5)),
	} },
	RainSplashes = { Mode = "Ground", Emitters = { {
		Texture = SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(215, 230, 250)),
		Size = keys({ { 0, 0.25 }, { 1, 0.9 } }),
		Squash = seq(-0.8), -- приплюснутое колечко
		Transparency = keys({ { 0, 0.35 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.2, 0.35),
		Rate = 22,
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(50, 50),
		EmissionDirection = Enum.NormalId.Top,
		LightInfluence = 0.8,
	} } },
	Mist = { Mode = "Ground", Emitters = { {
		Texture = SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(200, 210, 222)),
		Size = keys({ { 0, 9 }, { 1, 16 } }),
		Transparency = keys({ { 0, 1 }, { 0.3, 0.88 }, { 0.7, 0.9 }, { 1, 1 } }),
		Lifetime = NumberRange.new(6, 9),
		Rate = 0.5,
		Speed = NumberRange.new(0.5, 1.5),
		SpreadAngle = Vector2.new(80, 80),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-8, 8),
		EmissionDirection = Enum.NormalId.Top,
		LightInfluence = 1,
		WindAffectsDrag = true,
		Drag = 0.5,
	} } },
	Fireflies = { Mode = "Float", Height = 16, Emitters = { {
		Texture = SPARKLE,
		Color = ColorSequence.new(Color3.fromRGB(215, 255, 120)),
		Size = keys({ { 0, 0.1 }, { 0.5, 0.3 }, { 1, 0.1 } }),
		Transparency = keys({ { 0, 1 }, { 0.2, 0.1 }, { 0.5, 0.5 }, { 0.8, 0.05 }, { 1, 1 } }),
		Lifetime = NumberRange.new(4, 7),
		Rate = 2.5,
		Speed = NumberRange.new(0.4, 1.1),
		SpreadAngle = Vector2.new(180, 180),
		LightEmission = 1,
		LightInfluence = 0,
	} } },
	StarDust = { Mode = "Float", Height = 40, Emitters = { {
		Texture = SPARKLE,
		Color = ColorSequence.new(Color3.fromRGB(190, 210, 255)),
		Size = seq(0.18),
		Transparency = keys({ { 0, 1 }, { 0.3, 0.3 }, { 1, 1 } }),
		Lifetime = NumberRange.new(5, 8),
		Rate = 3,
		Speed = NumberRange.new(0.2, 0.5),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -0.3, 0),
		LightEmission = 0.9,
		LightInfluence = 0,
	} } },
	Embers = { Mode = "Float", Height = 20, Emitters = { {
		Texture = SPARKLE,
		Color = ColorSequence.new(Color3.fromRGB(255, 90, 60), Color3.fromRGB(160, 20, 30)),
		Size = keys({ { 0, 0.25 }, { 1, 0.05 } }),
		Transparency = keys({ { 0, 0.2 }, { 1, 1 } }),
		Lifetime = NumberRange.new(3, 6),
		Rate = 5,
		Speed = NumberRange.new(0.5, 1.5),
		SpreadAngle = Vector2.new(40, 40),
		Acceleration = Vector3.new(0, 1.4, 0),
		EmissionDirection = Enum.NormalId.Top,
		LightEmission = 1,
		LightInfluence = 0,
		WindAffectsDrag = true,
		Drag = 0.4,
	} } },
	Ash = { Mode = "Float", Height = 45, Emitters = { {
		Texture = SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(70, 62, 55)),
		Size = seq(0.3),
		Squash = seq(-0.5),
		Transparency = keys({ { 0, 1 }, { 0.2, 0.25 }, { 0.8, 0.3 }, { 1, 1 } }),
		Lifetime = NumberRange.new(7, 11),
		Rate = 6,
		Speed = NumberRange.new(0.3, 0.8),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -1.2, 0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-90, 90),
		LightInfluence = 1,
		WindAffectsDrag = true,
		Drag = 0.6,
	} } },
	Pollen = { Mode = "Float", Height = 20, Emitters = { {
		Texture = SPARKLE,
		Color = ColorSequence.new(Color3.fromRGB(255, 240, 170)),
		Size = seq(0.12),
		Transparency = keys({ { 0, 1 }, { 0.3, 0.4 }, { 1, 1 } }),
		Lifetime = NumberRange.new(5, 8),
		Rate = 1.5,
		Speed = NumberRange.new(0.2, 0.6),
		SpreadAngle = Vector2.new(180, 180),
		LightEmission = 0.5,
		LightInfluence = 0.5,
		WindAffectsDrag = true,
		Drag = 0.8,
	} } },
}

-- Описание эффекта: { Name, Mode, Height, Templates = {ParticleEmitter}, Sounds = {Sound}, MaxLifetime }.
local definitions = {}
local function definitionFor(name)
	if definitions[name] then return definitions[name] end
	local def = { Name = name, Templates = {}, Sounds = {}, MaxLifetime = 1 }
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local library = assets and assets:FindFirstChild("WeatherFX")
	local asset = library and library:FindFirstChild(name)
	if asset then
		def.Mode = asset:GetAttribute("Mode") or "Fall"
		def.Height = tonumber(asset:GetAttribute("Height"))
		for _, item in asset:GetDescendants() do
			if item:IsA("ParticleEmitter") then
				table.insert(def.Templates, item)
			elseif item:IsA("Sound") then
				table.insert(def.Sounds, item)
			end
		end
	end
	if #def.Templates == 0 then
		local placeholder = PLACEHOLDERS[name]
		if not placeholder then
			if not asset then warn(("[WeatherFX] эффекта %q нет ни в Assets/WeatherFX, ни среди встроенных"):format(name)) end
			definitions[name] = def
			return def
		end
		def.Mode = def.Mode or placeholder.Mode
		def.Height = def.Height or placeholder.Height
		for index, props in placeholder.Emitters do
			local emitter = Instance.new("ParticleEmitter")
			emitter.Name = name .. index
			for key, value in props do emitter[key] = value end
			table.insert(def.Templates, emitter)
		end
	end
	def.Mode = def.Mode or "Fall"
	def.Height = def.Height or (def.Mode == "Fall" and 70 or 20)
	for _, template in def.Templates do
		def.MaxLifetime = math.max(def.MaxLifetime, template.Lifetime.Max)
	end
	definitions[name] = def
	return def
end

--------------------------------------------------------------------------------
-- ЗЕМЛЯ И КЛЕТКИ
--------------------------------------------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = false

local function refreshRayFilter()
	local list = { fxFolder, workspace.CurrentCamera }
	for _, other in Players:GetPlayers() do
		if other.Character then table.insert(list, other.Character) end
	end
	rayParams.FilterDescendantsInstances = list
end

local function groundAt(x, z)
	local hit = workspace:Raycast(Vector3.new(x, 2000, z), Vector3.new(0, -4000, 0), rayParams)
	return hit and hit.Position.Y or nil, hit
end

-- Границы карты: Config или по габаритам всего в Workspace (один раз).
local bounds = nil
local function mapBounds()
	if bounds then return bounds end
	if FX.MapBounds then
		bounds = FX.MapBounds
		return bounds
	end
	local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
	for _, child in workspace:GetChildren() do
		if child ~= fxFolder and not child:IsA("Terrain") and not child:IsA("Camera") and not Players:GetPlayerFromCharacter(child) then
			local ok, cf, size = false, nil, nil
			if child:IsA("Model") then
				ok, cf, size = pcall(function() return child:GetBoundingBox() end)
			elseif child:IsA("BasePart") then
				ok, cf, size = true, child.CFrame, child.Size
			elseif child:IsA("Folder") then
				ok, cf, size = pcall(function()
					local extents = { math.huge, math.huge, -math.huge, -math.huge }
					for _, d in child:GetDescendants() do
						if d:IsA("BasePart") then
							extents[1] = math.min(extents[1], d.Position.X - d.Size.Magnitude / 2)
							extents[2] = math.min(extents[2], d.Position.Z - d.Size.Magnitude / 2)
							extents[3] = math.max(extents[3], d.Position.X + d.Size.Magnitude / 2)
							extents[4] = math.max(extents[4], d.Position.Z + d.Size.Magnitude / 2)
						end
					end
					if extents[1] > extents[3] then error("empty") end
					return CFrame.new((extents[1] + extents[3]) / 2, 0, (extents[2] + extents[4]) / 2), Vector3.new(extents[3] - extents[1], 0, extents[4] - extents[2])
				end)
			end
			if ok and cf then
				minX = math.min(minX, cf.Position.X - size.X / 2)
				minZ = math.min(minZ, cf.Position.Z - size.Z / 2)
				maxX = math.max(maxX, cf.Position.X + size.X / 2)
				maxZ = math.max(maxZ, cf.Position.Z + size.Z / 2)
			end
		end
	end
	if minX > maxX then
		minX, minZ, maxX, maxZ = -512, -512, 512, 512
	end
	local limit = (FX.MaxMapSize or 3000) / 2
	local cx, cz = (minX + maxX) / 2, (minZ + maxZ) / 2
	bounds = {
		Min = Vector2.new(math.max(minX, cx - limit) - CELL, math.max(minZ, cz - limit) - CELL),
		Max = Vector2.new(math.min(maxX, cx + limit) + CELL, math.min(maxZ, cz + limit) + CELL),
	}
	return bounds
end

local function cellPart(name, size, cframe)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = fxFolder
	return part
end

local function attachEmitters(def, part, share, list)
	for _, template in def.Templates do
		local emitter = template:Clone()
		emitter.Shape = Enum.ParticleEmitterShape.Box
		emitter:SetAttribute("BaseRate", template.Rate * share)
		emitter.Rate = 0
		emitter.Enabled = true
		emitter.Parent = part
		table.insert(list, emitter)
	end
end

-- Клетка эффекта: детали с эмиттерами. Для Fall высота плиты
-- обновляется (камера поднялась — дождь начинается выше неё).
local function buildCell(def, ix, iz)
	local cx, cz = (ix + 0.5) * CELL, (iz + 0.5) * CELL
	local cell = { Emitters = {}, Parts = {}, Center = Vector2.new(cx, cz) }
	local groundY = groundAt(cx, cz)
	cell.GroundY = groundY
	if def.Mode == "Ground" then
		for i = 1, GROUND_POINTS do
			local x = cx + (math.random() - 0.5) * CELL
			local z = cz + (math.random() - 0.5) * CELL
			local y = groundAt(x, z)
			if y then
				local part = cellPart(def.Name, Vector3.new(CELL / 3, 0.2, CELL / 3), CFrame.new(x, y + 0.15, z))
				table.insert(cell.Parts, part)
				attachEmitters(def, part, 1 / GROUND_POINTS, cell.Emitters)
			end
		end
	elseif def.Mode == "Float" then
		if groundY then
			local part = cellPart(def.Name, Vector3.new(CELL, def.Height, CELL), CFrame.new(cx, groundY + def.Height / 2, cz))
			table.insert(cell.Parts, part)
			attachEmitters(def, part, 1, cell.Emitters)
		end
	else
		local part = cellPart(def.Name, Vector3.new(CELL, 1, CELL), CFrame.new(cx, (groundY or 0) + def.Height, cz))
		cell.Top = part
		table.insert(cell.Parts, part)
		attachEmitters(def, part, 1, cell.Emitters)
	end
	return cell
end

local function destroyCell(cell)
	for _, part in cell.Parts do part:Destroy() end
end

--------------------------------------------------------------------------------
-- АКТИВНЫЕ ЭФФЕКТЫ: плавное появление/затухание, клетки вокруг камеры
--------------------------------------------------------------------------------
local active = {} -- [name] = { Def, Weight, Target, Cells = { [key] = cell }, Sounds = {}, DeadAt }

local function startEffect(name)
	local effect = active[name]
	if effect then
		effect.Target = 1
		effect.DeadAt = nil
		return
	end
	local def = definitionFor(name)
	if #def.Templates == 0 and #def.Sounds == 0 then return end
	effect = { Def = def, Weight = 0, Target = 1, Cells = {}, Sounds = {} }
	for _, template in def.Sounds do
		local sound = template:Clone()
		sound:SetAttribute("BaseVolume", template.Volume)
		sound.Volume = 0
		sound.Looped = true
		sound.Parent = SoundService
		sound:Play()
		table.insert(effect.Sounds, sound)
	end
	active[name] = effect
end

local function stopEffect(name)
	local effect = active[name]
	if effect then effect.Target = 0 end
end

local function removeEffect(name)
	local effect = active[name]
	if not effect then return end
	active[name] = nil
	for _, cell in effect.Cells do destroyCell(cell) end
	for _, sound in effect.Sounds do sound:Destroy() end
end

local function rateFactor(distance)
	if distance <= FULL_RADIUS then return 1 end
	local t = math.clamp((distance - FULL_RADIUS) / math.max(RADIUS - FULL_RADIUS, 1), 0, 1)
	return 1 + (FAR_RATE - 1) * t
end

local sinceUpdate = 0
RunService.Heartbeat:Connect(function(dt)
	-- Вес эффектов — каждый кадр (плавно), клетки — 4 раза в секунду.
	for name, effect in active do
		local step = dt / FADE
		if effect.Weight < effect.Target then
			effect.Weight = math.min(effect.Target, effect.Weight + step)
		elseif effect.Weight > effect.Target then
			effect.Weight = math.max(effect.Target, effect.Weight - step)
		end
		if effect.Target == 0 and effect.Weight <= 0 then
			-- Даём долететь уже выпущенным частицам и убираем.
			effect.DeadAt = effect.DeadAt or (os.clock() + effect.Def.MaxLifetime + 0.5)
			if os.clock() >= effect.DeadAt then removeEffect(name) end
		end
	end
	sinceUpdate += dt
	if sinceUpdate < 0.25 then return end
	sinceUpdate = 0
	if not next(active) then return end

	local camera = workspace.CurrentCamera
	if not camera then return end
	refreshRayFilter()
	local camPos = camera.CFrame.Position
	local map = mapBounds()
	local minIx = math.floor((math.max(camPos.X - RADIUS, map.Min.X)) / CELL)
	local maxIx = math.floor((math.min(camPos.X + RADIUS, map.Max.X)) / CELL)
	local minIz = math.floor((math.max(camPos.Z - RADIUS, map.Min.Y)) / CELL)
	local maxIz = math.floor((math.min(camPos.Z + RADIUS, map.Max.Y)) / CELL)

	for _, effect in active do
		local def = effect.Def
		for _, sound in effect.Sounds do
			sound.Volume = (sound:GetAttribute("BaseVolume") or 0.5) * effect.Weight
		end
		if #def.Templates > 0 then
			local wanted = {}
			if effect.Weight > 0 or effect.Target > 0 then
				for ix = minIx, maxIx do
					for iz = minIz, maxIz do
						local cx, cz = (ix + 0.5) * CELL, (iz + 0.5) * CELL
						local distance = Vector2.new(cx - camPos.X, cz - camPos.Z).Magnitude
						if distance <= RADIUS then
							local key = ix .. ":" .. iz
							wanted[key] = distance
							if not effect.Cells[key] then
								effect.Cells[key] = buildCell(def, ix, iz)
							end
						end
					end
				end
			end
			for key, cell in effect.Cells do
				local distance = wanted[key]
				if distance then
					cell.FarSince = nil
					local factor = rateFactor(distance) * effect.Weight
					for _, emitter in cell.Emitters do
						emitter.Rate = (emitter:GetAttribute("BaseRate") or 0) * factor
					end
					if cell.Top then
						-- Дождь начинается не ниже, чем чуть выше камеры.
						local topY = math.max((cell.GroundY or camPos.Y - 40) + def.Height, camPos.Y + 30)
						if math.abs(cell.Top.Position.Y - topY) > 8 then
							cell.Top.CFrame = CFrame.new(cell.Center.X, topY, cell.Center.Y)
						end
					end
				else
					for _, emitter in cell.Emitters do emitter.Rate = 0 end
					cell.FarSince = cell.FarSince or os.clock()
					if os.clock() - cell.FarSince > def.MaxLifetime + 1 then
						destroyCell(cell)
						effect.Cells[key] = nil
					end
				end
			end
		end
	end
end)

--------------------------------------------------------------------------------
-- МОЛНИИ (Events[].Lightning = true; настройки — Config.WeatherEvents.Lightning)
--------------------------------------------------------------------------------
local LCFG = WEATHER.Lightning or {}

local lightningGui = Instance.new("ScreenGui")
lightningGui.Name = "WeatherLightning"
lightningGui.IgnoreGuiInset = true
lightningGui.DisplayOrder = 40
lightningGui.ResetOnSpawn = false
lightningGui.Parent = playerGui

local lightningFlash = Instance.new("Frame")
lightningFlash.Size = UDim2.fromScale(1, 1)
lightningFlash.BackgroundColor3 = Color3.fromRGB(225, 235, 255)
lightningFlash.BackgroundTransparency = 1
lightningFlash.BorderSizePixel = 0
lightningFlash.Parent = lightningGui

-- Вспышка неба: своя цветокоррекция (сервер свою не трогает).
local flashCorrection = Instance.new("ColorCorrectionEffect")
flashCorrection.Name = "LightningFlash"
flashCorrection.Parent = Lighting

local function flash(strength)
	flashCorrection.Brightness = 0.35 * strength
	flashCorrection.Contrast = 0.15 * strength
	TweenService:Create(flashCorrection, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0, Contrast = 0 }):Play()
	lightningFlash.BackgroundTransparency = 1 - 0.35 * strength
	TweenService:Create(lightningFlash, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end

local function neon(parent, name, color, transparency, size, cframe)
	local part = Instance.new("Part")
	part.Name = name
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = parent
	return part
end

-- Ломаная линия из точек → неоновые сегменты (ядро + свечение).
local function boltPath(holder, points, thickness)
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local length = (b - a).Magnitude
		if length > 0.01 then
			local cf = CFrame.lookAt(a, b) * CFrame.new(0, 0, -length / 2)
			neon(holder, "Core", Color3.fromRGB(240, 245, 255), 0, Vector3.new(thickness, thickness, length), cf)
			neon(holder, "Glow", Color3.fromRGB(150, 185, 255), 0.6, Vector3.new(thickness * 3, thickness * 3, length), cf)
		end
	end
end

local function jagged(from, to, segments, jitter)
	local points = { from }
	for i = 1, segments - 1 do
		local t = i / segments
		local offset = (1 - t * 0.6) * jitter
		table.insert(points, from:Lerp(to, t) + Vector3.new((math.random() - 0.5) * offset, (math.random() - 0.5) * offset * 0.3, (math.random() - 0.5) * offset))
	end
	table.insert(points, to)
	return points
end

local function spawnBolt(ground, near)
	local holder = Instance.new("Folder")
	holder.Name = "LightningBolt"
	holder.Parent = fxFolder
	local top = ground + Vector3.new((math.random() - 0.5) * 30, 170, (math.random() - 0.5) * 30)
	local main = jagged(top, ground, 12, 14)
	boltPath(holder, main, near and 0.45 or 0.6)
	-- Одна-две ветки от верхней половины.
	for _ = 1, math.random(1, 2) do
		local start = main[math.random(2, 6)]
		local finish = start + Vector3.new((math.random() - 0.5) * 50, -(25 + math.random() * 35), (math.random() - 0.5) * 50)
		boltPath(holder, jagged(start, finish, 5, 8), 0.25)
	end
	local lightPart = neon(holder, "Impact", Color3.fromRGB(200, 220, 255), 1, Vector3.one, CFrame.new(ground + Vector3.new(0, 3, 0)))
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(190, 210, 255)
	light.Range = near and 40 or 60
	light.Brightness = 8
	light.Shadows = false
	light.Parent = lightPart
	task.delay(0.1, function()
		for _, part in holder:GetChildren() do
			if part:IsA("BasePart") and part.Name ~= "Impact" then
				TweenService:Create(part, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
			end
		end
		TweenService:Create(light, TweenInfo.new(0.4), { Brightness = 0 }):Play()
	end)
	task.delay(0.6, function() holder:Destroy() end)
end

-- Удар рядом: блоки травы разлетаются, падают, подпрыгивают и тают.
local function grassBurst(ground, hit)
	local range = LCFG.GrassBlocks or { 12, 18 }
	local colors = LCFG.GrassColors or { Color3.fromRGB(90, 170, 70) }
	local surfaceColor = hit and hit.Instance and hit.Instance:IsA("BasePart") and hit.Instance.Color or nil
	local blocks = {}
	for i = 1, math.random(range[1], range[2]) do
		local size = 0.5 + math.random() * 0.7
		local color = colors[math.random(1, #colors)]
		if surfaceColor and i % 3 == 0 then color = surfaceColor end
		local part = Instance.new("Part")
		part.Name = "GrassChunk"
		part.Size = Vector3.one * size
		part.Material = Enum.Material.Grass
		part.Color = color
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CFrame = CFrame.new(ground + Vector3.new((math.random() - 0.5) * 2, size / 2, (math.random() - 0.5) * 2))
		part.Parent = fxFolder
		local angle = math.random() * math.pi * 2
		local out = 10 + math.random() * 14
		table.insert(blocks, {
			Part = part,
			Velocity = Vector3.new(math.cos(angle) * out, 18 + math.random() * 16, math.sin(angle) * out),
			Spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 14,
			Rotation = CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6),
			Floor = ground.Y + size / 2,
			Size = size,
		})
	end
	-- Облачко пыли и искры в точке удара.
	local dust = neon(fxFolder, "StrikeDust", Color3.new(1, 1, 1), 1, Vector3.one, CFrame.new(ground + Vector3.new(0, 0.5, 0)))
	local puff = Instance.new("ParticleEmitter")
	puff.Texture = SMOKE
	puff.Color = ColorSequence.new(Color3.fromRGB(150, 140, 120))
	puff.Size = keys({ { 0, 2 }, { 1, 6 } })
	puff.Transparency = keys({ { 0, 0.4 }, { 1, 1 } })
	puff.Lifetime = NumberRange.new(0.8, 1.4)
	puff.Speed = NumberRange.new(4, 9)
	puff.SpreadAngle = Vector2.new(180, 40)
	puff.Rate = 0
	puff.Parent = dust
	puff:Emit(12)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARKLE
	sparks.Color = ColorSequence.new(Color3.fromRGB(200, 225, 255))
	sparks.LightEmission = 1
	sparks.Size = keys({ { 0, 0.5 }, { 1, 0 } })
	sparks.Lifetime = NumberRange.new(0.3, 0.6)
	sparks.Speed = NumberRange.new(15, 30)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Acceleration = Vector3.new(0, -40, 0)
	sparks.Rate = 0
	sparks.Parent = dust
	sparks:Emit(25)
	task.delay(2, function() dust:Destroy() end)

	local started = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		local age = os.clock() - started
		local fade = math.clamp((age - 1.6) / 0.8, 0, 1)
		for _, block in blocks do
			local v = block.Velocity
			v -= Vector3.new(0, 70 * dt, 0)
			local pos = block.Part.Position + v * dt
			if pos.Y <= block.Floor and v.Y < 0 then
				pos = Vector3.new(pos.X, block.Floor, pos.Z)
				v = Vector3.new(v.X * 0.55, -v.Y * 0.35, v.Z * 0.55)
				if math.abs(v.Y) < 2.5 then v = Vector3.new(v.X * 0.6, 0, v.Z * 0.6) end
				block.Spin *= 0.5
			end
			block.Velocity = v
			block.Rotation *= CFrame.Angles(block.Spin.X * dt, block.Spin.Y * dt, block.Spin.Z * dt)
			block.Part.CFrame = CFrame.new(pos) * block.Rotation
			block.Part.Transparency = fade
			if fade > 0 then block.Part.Size = Vector3.one * block.Size * (1 - fade * 0.6) end
		end
		if fade >= 1 then
			connection:Disconnect()
			for _, block in blocks do block.Part:Destroy() end
		end
	end)
end

-- Лёгкая тряска камеры (затухающая).
local shakeUntil, shakeAmp = 0, 0
local function shake(amplitude, seconds)
	shakeAmp = math.max(shakeAmp * math.max(0, shakeUntil - os.clock()) / 0.4, amplitude)
	shakeUntil = os.clock() + seconds
end
RunService:BindToRenderStep("WeatherLightningShake", Enum.RenderPriority.Camera.Value + 1, function()
	local left = shakeUntil - os.clock()
	if left <= 0 then return end
	local camera = workspace.CurrentCamera
	if not camera then return end
	local a = shakeAmp * math.clamp(left / 0.4, 0, 1)
	camera.CFrame *= CFrame.new((math.random() - 0.5) * a, (math.random() - 0.5) * a, 0)
end)

local function thunder(distance)
	local ids = LCFG.ThunderSoundIds or {}
	if #ids == 0 then return end
	task.delay(math.clamp(distance / 300, 0.05, 1.5), function()
		local sound = Instance.new("Sound")
		sound.SoundId = ids[math.random(1, #ids)]
		sound.Volume = (LCFG.ThunderVolume or 0.8) * math.clamp(1.2 - distance / 400, 0.35, 1)
		sound.PlaybackSpeed = 0.9 + math.random() * 0.2
		sound.Parent = SoundService
		sound:Play()
		sound.Ended:Connect(function() sound:Destroy() end)
		task.delay(15, function() if sound.Parent then sound:Destroy() end end)
	end)
end

local function strike()
	local camera = workspace.CurrentCamera
	if not camera then return end
	refreshRayFilter()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local near = root ~= nil and math.random() < (LCFG.NearChance or 0.22)
	local center = near and root.Position or camera.CFrame.Position
	local range = near and (LCFG.NearDistance or { 14, 26 }) or (LCFG.FarDistance or { 90, 260 })
	local angle = math.random() * math.pi * 2
	local distance = range[1] + math.random() * (range[2] - range[1])
	if not near then
		-- Дальние удары — в основном перед камерой, чтобы их было видно.
		local look = camera.CFrame.LookVector
		angle = math.atan2(look.Z, look.X) + (math.random() - 0.5) * 2.2
	end
	local x, z = center.X + math.cos(angle) * distance, center.Z + math.sin(angle) * distance
	local groundY, hit = groundAt(x, z)
	if not groundY then return end
	local ground = Vector3.new(x, groundY, z)
	spawnBolt(ground, near)
	flash(near and 1 or 0.55)
	local fromCamera = (ground - camera.CFrame.Position).Magnitude
	thunder(fromCamera)
	if near then
		grassBurst(ground, hit)
		shake(LCFG.ShakeNear or 0.35, 0.4)
	else
		shake(LCFG.ShakeFar or 0.06, 0.25)
	end
end

local lightningToken = 0
local function startLightning()
	lightningToken += 1
	local token = lightningToken
	task.spawn(function()
		while token == lightningToken do
			task.wait((LCFG.IntervalMin or 4) + math.random() * ((LCFG.IntervalMax or 11) - (LCFG.IntervalMin or 4)))
			if token ~= lightningToken then return end
			local ok, err = pcall(strike)
			if not ok then warn("[WeatherFX] молния:", err) end
		end
	end)
end

local function stopLightning()
	lightningToken += 1
end

--------------------------------------------------------------------------------
-- СМЕНА ПОГОДЫ
--------------------------------------------------------------------------------
local function applyWeather(payload)
	local wanted = {}
	for _, name in (payload and payload.Effects) or {} do
		wanted[name] = true
	end
	for name in active do
		if not wanted[name] then stopEffect(name) end
	end
	for name in wanted do
		startEffect(name)
	end
	if payload and payload.Lightning then
		startLightning()
	else
		stopLightning()
	end
end

weatherRemote.OnClientEvent:Connect(applyWeather)
