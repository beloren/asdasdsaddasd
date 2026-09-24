--------------------------------------------------------------------------------
-- DynamiteFX (LocalScript) v16 — ВЕСЬ ВИЗУАЛ ДИНАМИТА (D2 + D3).
--
-- Сервер (GearService) шлёт через Shared.DynamiteFx только «что и когда»:
--   "Throw" { Key, From, To, Apex, StartAt, LandAt, BoomAt } — бросок дугой;
--   "Place" { Key, Position, Face, LandAt, BoomAt }          — прилип к валуну;
--   "Boom"  { Key, Position, Radius }                         — взрыв (логика уже на сервере).
-- Времена — workspace:GetServerTimeNow(), поэтому у всех игроков шашка
-- летит и пульсирует синхронно и плавно (раньше её двигал сервер рывками).
--
-- Вид по Config.Dynamite.Types[key].Visual:
--   Stick  — одна шашка: «резиновая» пульсация (сквош/стретч), мигание;
--   Bundle — три шашки пульсируют вразнобой, взрыв цепочкой из трёх;
--   Barrel — бочка TNT с отсчётом 3-2-1 и большим «грибом».
-- Перед взрывом шашка раздувается до Fx.FinalInflate и на миг замирает.
-- Свои модели: ReplicatedStorage.Assets.<Key> (иначе плейсхолдер).
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config)
local Sfx = require(ReplicatedStorage.Shared.Sfx)

local player = Players.LocalPlayer
local FX = Config.Dynamite.Fx or {}

local remote = ReplicatedStorage.Shared:WaitForChild("DynamiteFx", 60)
if not remote then
	warn("[DynamiteFX] DynamiteFx не появился — визуал динамита отключён.")
	return
end

local folder = Instance.new("Folder")
folder.Name = "DynamiteFX"
folder.Parent = workspace

local function now()
	return workspace:GetServerTimeNow()
end

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do p[key] = value end
	return p
end

local function hasSound(name)
	local entry = Config.Sounds[name]
	return entry and typeof(entry.Id) == "string" and entry.Id ~= "" and entry.Id ~= "rbxassetid://0"
end

--------------------------------------------------------------------------------
-- МОДЕЛИ
--------------------------------------------------------------------------------
local function fuseSparks(parent)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "FuseSparks"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120), Color3.fromRGB(255, 120, 30))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.18, 0)
	emitter.Lifetime = NumberRange.new(0.2, 0.4)
	emitter.Speed = NumberRange.new(3, 6)
	emitter.SpreadAngle = Vector2.new(60, 60)
	emitter.Rate = 40
	emitter.Parent = parent
	return emitter
end

local function stick(color, length)
	local body = part({
		Shape = Enum.PartType.Cylinder, Size = Vector3.new(length, 0.45, 0.45),
		Color = color, Material = Enum.Material.SmoothPlastic,
	})
	return body
end

local function buildPlaceholder(info)
	local model = Instance.new("Model")
	local visual = info.Visual or "Stick"
	local root
	if visual == "Barrel" then
		root = part({
			Name = "Root", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.4, 1.9, 1.9),
			Color = Color3.fromRGB(200, 50, 40), Material = Enum.Material.SmoothPlastic,
		})
		root.CFrame = CFrame.new(0, 1.2, 0) * CFrame.Angles(0, 0, math.rad(90))
		root.Parent = model
		for _, y in { 0.35, 2.05 } do
			local band = part({
				Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.18, 2, 2),
				Color = Color3.fromRGB(40, 40, 44), Material = Enum.Material.Metal,
			})
			band.CFrame = CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90))
			band.Parent = model
		end
		local label = part({ Size = Vector3.new(1.3, 0.8, 0.05), Color = Color3.fromRGB(245, 235, 210), Material = Enum.Material.SmoothPlastic })
		label.CFrame = CFrame.new(0, 1.2, -0.95)
		label.Parent = model
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.Parent = label
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Text = "TNT"
		text.TextScaled = true
		text.Font = Enum.Font.FredokaOne
		text.TextColor3 = Color3.fromRGB(200, 30, 30)
		text.Parent = gui
		local fuse = Instance.new("Attachment")
		fuse.Name = "Fuse"
		fuse.Position = Vector3.new(1.3, 0, 0) -- ось цилиндра = X корня = вверх
		fuse.Parent = root
	elseif visual == "Bundle" then
		root = part({ Name = "Root", Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1 })
		root.CFrame = CFrame.new(0, 0.45, 0)
		root.Parent = model
		local offsets = { Vector3.new(0, 0, -0.26), Vector3.new(0, 0, 0.26), Vector3.new(0, 0.42, 0) }
		for index, offset in offsets do
			local s = stick(info.Color or Color3.fromRGB(255, 120, 40), 1.6)
			s.Name = "Stick" .. index
			s.CFrame = CFrame.new(offset + Vector3.new(0, 0.45, 0))
			s:SetAttribute("PulsePhase", (index - 1) * 2.1)
			s.Parent = model
		end
		local band = part({ Size = Vector3.new(0.3, 1.05, 1.05), Color = Color3.fromRGB(30, 30, 34), Material = Enum.Material.Fabric })
		band.CFrame = CFrame.new(0, 0.62, 0)
		band.Parent = model
		local fuse = Instance.new("Attachment")
		fuse.Name = "Fuse"
		fuse.Position = Vector3.new(0.85, 0.2, 0)
		fuse.Parent = root
	else
		root = stick(info.Color or Color3.fromRGB(215, 45, 45), 1.4)
		root.Name = "Root"
		root.CFrame = CFrame.new(0, 0.25, 0)
		root.Parent = model
		local fuse = Instance.new("Attachment")
		fuse.Name = "Fuse"
		fuse.Position = Vector3.new(0.75, 0, 0)
		fuse.Parent = root
	end
	model.PrimaryPart = root
	model.WorldPivot = CFrame.new()
	return model
end

local function buildModel(key)
	local info = Config.Dynamite.Types[key] or Config.Dynamite.Types.Dynamite
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local asset = assets and assets:FindFirstChild(key, true)
	local model
	if asset and (asset:IsA("Model") or asset:IsA("BasePart")) then
		local clone = asset:Clone()
		if clone:IsA("BasePart") then
			model = Instance.new("Model")
			clone.Parent = model
			model.PrimaryPart = clone
		else
			model = clone
			model.PrimaryPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		end
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			elseif d:IsA("Script") or d:IsA("LocalScript") then
				d:Destroy()
			end
		end
		local boxCFrame, boxSize = model:GetBoundingBox()
		model.WorldPivot = CFrame.new(boxCFrame.Position - Vector3.new(0, boxSize.Y / 2, 0))
	else
		model = buildPlaceholder(info)
	end
	model.Name = "Dynamite_" .. key
	local root = model.PrimaryPart
	local fuse = root and root:FindFirstChild("Fuse")
	if root then fuseSparks(fuse or root) end
	local highlight = Instance.new("Highlight")
	highlight.FillColor = FX.FlashColor or Color3.fromRGB(255, 60, 60)
	highlight.OutlineTransparency = 1
	highlight.FillTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	return model, info, highlight
end

-- Запоминаем части относительно пивота, чтобы масштабировать без накопления ошибки.
local function captureBase(model)
	local pivot = model:GetPivot()
	local base = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			base[d] = {
				Rel = pivot:ToObjectSpace(d.CFrame),
				Size = d.Size,
				Phase = tonumber(d:GetAttribute("PulsePhase")) or 0,
			}
		end
	end
	return base
end

-- Ставит модель в pivot с масштабом scaleFn(phase) → (xz, y).
local function applyPose(base, pivot, scaleFn)
	for p, entry in base do
		if p.Parent then
			local xz, y = scaleFn(entry.Phase)
			local rel = entry.Rel
			local pos = rel.Position
			p.Size = entry.Size * math.max(0.05, (xz + y) * 0.5)
			p.CFrame = pivot * CFrame.new(pos.X * xz, pos.Y * y, pos.Z * xz) * rel.Rotation
		end
	end
end

--------------------------------------------------------------------------------
-- ВЗРЫВ
--------------------------------------------------------------------------------
local shakeToken = 0
local function shakeCamera(strength, seconds)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	shakeToken += 1
	local token = shakeToken
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - started
		if token ~= shakeToken or elapsed >= seconds or not humanoid.Parent then
			connection:Disconnect()
			if humanoid.Parent and token == shakeToken then humanoid.CameraOffset = Vector3.zero end
			return
		end
		local fade = 1 - elapsed / seconds
		humanoid.CameraOffset = Vector3.new(
			(math.random() - 0.5) * 2 * strength * fade,
			(math.random() - 0.5) * 2 * strength * fade,
			(math.random() - 0.5) * strength * fade
		)
	end)
end

local function boomWord(position, scale)
	local anchor = part({ Size = Vector3.one * 0.2, Transparency = 1 })
	anchor.CFrame = CFrame.new(position + Vector3.new(0, 2 * scale, 0))
	anchor.Parent = folder
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(7 * scale, 3 * scale)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	local words = FX.BoomWords or { "BOOM!" }
	label.Text = words[math.random(1, #words)]
	label.TextColor3 = Color3.fromRGB(255, 220, 60)
	label.Rotation = math.random(-12, 12)
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = Color3.fromRGB(120, 20, 10)
	stroke.Parent = label
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = 0.2
	uiScale.Parent = label
	TweenService:Create(uiScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(0.55, function()
		TweenService:Create(label, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.35), { Transparency = 1 }):Play()
		TweenService:Create(anchor, TweenInfo.new(0.35), { CFrame = anchor.CFrame + Vector3.new(0, 2, 0) }):Play()
	end)
	Debris:AddItem(anchor, 1.2)
end

local function burst(position, scale, radius, big)
	-- Огненный шар.
	local ball = part({
		Shape = Enum.PartType.Ball, Size = Vector3.one * 1.5, Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 170, 50),
	})
	ball.CFrame = CFrame.new(position + Vector3.new(0, 1, 0))
	ball.Parent = folder
	local ballSize = math.max(4, radius * 0.9) * scale
	TweenService:Create(ball, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * ballSize, Transparency = 1, Color = Color3.fromRGB(255, 90, 30),
	}):Play()
	Debris:AddItem(ball, 0.4)
	-- Ударная волна по земле.
	local ring = part({
		Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.15, 2, 2), Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 240, 200), Transparency = 0.2,
	})
	ring.CFrame = CFrame.new(position + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = folder
	TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.15, radius * 2.2 * scale, radius * 2.2 * scale), Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.5)
	-- Искры и дым.
	local holder = part({ Size = Vector3.one * 0.2, Transparency = 1 })
	holder.CFrame = CFrame.new(position + Vector3.new(0, 1, 0))
	holder.Parent = folder
	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 110, 30))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.5 * scale, 0)
	sparks.Lifetime = NumberRange.new(0.3, 0.7)
	sparks.Speed = NumberRange.new(25 * scale, 45 * scale)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Drag = 4
	sparks.Rate = 0
	sparks.Parent = holder
	sparks:Emit(math.floor(40 * scale))
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(big and Color3.fromRGB(70, 60, 55) or Color3.fromRGB(150, 145, 140))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2 * scale), NumberSequenceKeypoint.new(1, 6 * scale) })
	smoke.Transparency = NumberSequence.new(0.3, 1)
	smoke.Lifetime = NumberRange.new(0.8, 1.4)
	smoke.Speed = NumberRange.new(4, 10)
	smoke.SpreadAngle = Vector2.new(180, 60)
	smoke.Rate = 0
	smoke.Parent = holder
	smoke:Emit(math.floor(12 * scale))
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 170, 70)
	light.Range = radius * 2 * scale
	light.Brightness = 6
	light.Parent = holder
	TweenService:Create(light, TweenInfo.new(0.4), { Brightness = 0 }):Play()
	Debris:AddItem(holder, 2)
	boomWord(position, scale)
end

local function mushroom(position, radius)
	local stem = part({
		Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 2, 2), Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(90, 80, 75), Transparency = 0.1,
	})
	stem.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	stem.Parent = folder
	local cap = part({
		Shape = Enum.PartType.Ball, Size = Vector3.one * 2, Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(110, 95, 85), Transparency = 0.1,
	})
	cap.CFrame = CFrame.new(position)
	cap.Parent = folder
	local height = radius * 1.4
	TweenService:Create(stem, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(height, radius * 0.35, radius * 0.35), CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
	}):Play()
	TweenService:Create(cap, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(radius * 1.2, radius * 0.7, radius * 1.2), CFrame = CFrame.new(position + Vector3.new(0, height, 0)),
	}):Play()
	task.delay(0.9, function()
		TweenService:Create(stem, TweenInfo.new(0.8), { Transparency = 1 }):Play()
		TweenService:Create(cap, TweenInfo.new(0.8), { Transparency = 1, Size = cap.Size * 1.3 }):Play()
	end)
	Debris:AddItem(stem, 1.9)
	Debris:AddItem(cap, 1.9)
end

local function boomSound(position, big)
	local anchor = part({ Size = Vector3.one * 0.2, Transparency = 1 })
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = folder
	Debris:AddItem(anchor, 6)
	local name = big and "DynamiteBigBoom" or "DynamiteBoom"
	if hasSound(name) then
		Sfx.play(name, anchor)
	elseif hasSound("DynamiteBoom") then
		Sfx.play("DynamiteBoom", anchor)
	else
		-- Нет своего звука — встроенный звук Explosion (без визуала и без силы).
		local explosion = Instance.new("Explosion")
		explosion.Visible = false
		explosion.BlastPressure = 0
		explosion.BlastRadius = 0
		explosion.DestroyJointRadiusPercent = 0
		explosion.Position = position
		explosion.Parent = folder
	end
end

local function playBoom(key, position, radius)
	local info = Config.Dynamite.Types[key] or Config.Dynamite.Types.Dynamite
	local visual = info.Visual or "Stick"
	radius = tonumber(radius) or info.Radius or 10
	if visual == "Bundle" then
		for index = 0, 2 do
			task.delay(index * (FX.ChainDelay or 0.1), function()
				local jitter = Vector3.new(math.random(-15, 15) / 10, 0, math.random(-15, 15) / 10)
				burst(position + jitter, 0.8, radius, false)
				boomSound(position, false)
			end)
		end
	elseif visual == "Barrel" then
		burst(position, 1.6, radius, true)
		mushroom(position, radius)
		boomSound(position, true)
	else
		burst(position, 1, radius, false)
		boomSound(position, false)
	end
	-- Тряска камеры по расстоянию.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		local distance = (root.Position - position).Magnitude
		local reach = radius * (FX.ShakeRadiusMult or 3)
		if distance < reach then
			local closeness = 1 - distance / reach
			local strength = (visual == "Barrel" and 1.4 or visual == "Bundle" and 1 or 0.7) * closeness
			shakeCamera(strength, 0.35 + 0.35 * closeness)
		end
	end
end

--------------------------------------------------------------------------------
-- ФИТИЛЬ: полёт → приземление → пульсация → раздувание
--------------------------------------------------------------------------------
local active = {} -- { { Model, Position, Key, Done } }

local function countdownGui(model)
	local root = model.PrimaryPart
	local gui = Instance.new("BillboardGui")
	gui.Name = "Countdown"
	gui.Size = UDim2.fromScale(3, 3)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = root
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 80, 60)
	label.Text = ""
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Parent = label
	local scale = Instance.new("UIScale")
	scale.Parent = label
	return label, scale
end

local function run(kind, payload)
	local key = payload.Key
	local model, info, highlight = buildModel(key)
	local visual = info.Visual or "Stick"
	local landAt = tonumber(payload.LandAt) or now()
	local boomAt = tonumber(payload.BoomAt) or (landAt + 1.5)
	local restPivot
	if kind == "Place" then
		local position = payload.Position
		local face = typeof(payload.Face) == "Vector3" and payload.Face or position + Vector3.new(0, 0, 1)
		local flat = Vector3.new(face.X, position.Y, face.Z)
		restPivot = (flat - position).Magnitude > 0.1 and CFrame.lookAt(position, flat) or CFrame.new(position)
	else
		restPivot = CFrame.new(payload.To) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	end
	model:PivotTo(restPivot)
	model.Parent = folder
	local base = captureBase(model)
	local entry = { Model = model, Position = restPivot.Position, Key = key, Done = false }
	table.insert(active, entry)

	local countdownLabel, countdownScale
	if visual == "Barrel" then countdownLabel, countdownScale = countdownGui(model) end
	local lastCount = nil
	local lastPulse = -1
	local phase = 0
	local landed = kind == "Place"
	local landFxAt = nil
	if kind == "Throw" and hasSound("DynamiteThrow") then Sfx.play("DynamiteThrow", model) end
	if hasSound("DynamiteFuse") then Sfx.play("DynamiteFuse", model) end

	local from, to = payload.From, payload.To
	local startAt = tonumber(payload.StartAt) or now()
	local apex = tonumber(payload.Apex) or 6
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		if entry.Done or not model.Parent then
			connection:Disconnect()
			return
		end
		local t = now()
		if not landed and kind == "Throw" then
			local flight = math.max(0.05, landAt - startAt)
			local k = math.clamp((t - startAt) / flight, 0, 1)
			local position = from:Lerp(to, k) + Vector3.new(0, 4 * apex * k * (1 - k), 0)
			local spin = (t - startAt)
			applyPose(base, CFrame.new(position) * CFrame.Angles(spin * 9, spin * 5, 0), function() return 1, 1 end)
			if k >= 1 then
				landed = true
				landFxAt = t
			end
			return
		end
		-- Приземление: короткий «шлёп» (сквош) перед пульсацией.
		local squash = 0
		if landFxAt and t - landFxAt < 0.18 then
			squash = math.sin((t - landFxAt) / 0.18 * math.pi) * 0.35
		end
		local fuse = math.max(0.05, boomAt - landAt)
		local progress = math.clamp((t - landAt) / fuse, 0, 1)
		local hold = FX.FinalHold or 0.08
		local inflateTime = 0.14
		local untilBoom = boomAt - t
		if untilBoom <= inflateTime + hold then
			-- Раздувание и «замирание» перед взрывом.
			local k = math.clamp(1 - (untilBoom - hold) / inflateTime, 0, 1)
			local s = 1 + ((FX.FinalInflate or 1.6) - 1) * (1 - (1 - k) ^ 3)
			applyPose(base, restPivot, function() return s, s end)
			highlight.FillTransparency = 0.15
			if untilBoom < -1 then
				-- Сервер не прислал Boom (потеря пакета) — не висим вечно.
				entry.Done = true
				model:Destroy()
			end
			return
		end
		local hz = (FX.PulseStartHz or 2) + ((FX.PulseEndHz or 9) - (FX.PulseStartHz or 2)) * progress
		phase += dt * hz * math.pi * 2
		local amplitude = ((FX.PulseTo or 1.25) - (FX.PulseFrom or 1)) * (0.35 + 0.65 * progress)
		applyPose(base, restPivot, function(partPhase)
			local wave = math.sin(phase + partPhase)
			local s = (FX.PulseFrom or 1) + amplitude * (wave * 0.5 + 0.5)
			-- «Резина»: вытягивается вверх, сужаясь по бокам, и наоборот.
			return s * (1 + 0.08 * wave + squash * 0.6), s * (1 - 0.12 * wave - squash)
		end)
		-- Мигание и тиканье — раз за период пульса.
		local cycle = math.floor(phase / (math.pi * 2))
		highlight.FillTransparency = (math.sin(phase) > 0.3) and 0.35 or 1
		if cycle ~= lastPulse then
			lastPulse = cycle
			if hasSound("DynamiteTick") and progress > 0.15 then Sfx.play("DynamiteTick", model) end
		end
		if countdownLabel then
			local count = math.ceil(untilBoom)
			if count <= 3 and count ~= lastCount then
				lastCount = count
				countdownLabel.Text = tostring(math.max(1, count))
				countdownScale.Scale = 1.6
				TweenService:Create(countdownScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
		end
	end)
end

local function finishNearest(position)
	local best, bestIndex, bestDistance = nil, nil, 6
	for index, entry in active do
		local distance = (entry.Position - position).Magnitude
		if not entry.Done and distance < bestDistance then
			best, bestIndex, bestDistance = entry, index, distance
		end
	end
	if best then
		best.Done = true
		if best.Model.Parent then best.Model:Destroy() end
		table.remove(active, bestIndex)
	end
	-- Уборка завершённых.
	for index = #active, 1, -1 do
		if active[index].Done then table.remove(active, index) end
	end
end

remote.OnClientEvent:Connect(function(kind, payload)
	if type(payload) ~= "table" then return end
	if kind == "Throw" or kind == "Place" then
		if not Config.Dynamite.Types[payload.Key] then return end
		local ok, err = pcall(run, kind, payload)
		if not ok then warn("[DynamiteFX] ", err) end
	elseif kind == "Boom" and typeof(payload.Position) == "Vector3" then
		finishNearest(payload.Position)
		local ok, err = pcall(playBoom, payload.Key, payload.Position, payload.Radius)
		if not ok then warn("[DynamiteFX] ", err) end
	end
end)
