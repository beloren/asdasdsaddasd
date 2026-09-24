--------------------------------------------------------------------------------
-- OrePickupFx (LocalScript) — v14.3: ПОДБОР РУДЫ КАК У МОНЕТОК.
--
-- Сервер засчитывает руду мгновенно (CrystalService:PickupToInventory) и
-- присылает сюда копию куска + где он лежал. Здесь чисто визуал, по той же
-- схеме, что у монеток (SellFx.client.lua):
--   1. POP     — кусок подпрыгивает вверх и чуть в сторону, крутится;
--   2. HANG    — на долю секунды зависает в верхней точке;
--   3. MAGNET  — срывается к игроку с ускорением и лёгким подъёмом,
--               к концу сжимается;
--   4. касание — искры и «дзынь», каждый следующий подряд чуть выше тоном.
-- Настройки — Config.OrePickupFx.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)

-- Ждём без таймаута: сервер создаёт remote при старте (CrystalService:Init).
local remote = ReplicatedStorage.Shared:WaitForChild("OrePickupFx")

local player = Players.LocalPlayer
local FX = Config.OrePickupFx or {}

local fxFolder = Instance.new("Folder")
fxFolder.Name = "OrePickupFxLocal"
fxFolder.Parent = workspace.CurrentCamera

local function range(pair, fallback)
	if type(pair) ~= "table" then return fallback end
	return pair[1] + math.random() * (pair[2] - pair[1])
end

-- Звон с нарастающим тоном (как у монеток).
local sounds = {}
do
	local info = Config.Sounds and (Config.Sounds.OrePickupChime or Config.Sounds.CrystalPickup)
	local id = info and info.Id
	if id and id ~= 0 then
		for _ = 1, 4 do
			local sound = Instance.new("Sound")
			sound.SoundId = typeof(id) == "number" and ("rbxassetid://" .. id) or id
			sound.Volume = (info.Volume or 0.5)
			sound.Parent = SoundService
			table.insert(sounds, sound)
		end
	end
end
local chain, lastChimeAt, soundIndex = 0, 0, 0
local function chime()
	if #sounds == 0 then return end
	local now = os.clock()
	if now - lastChimeAt < (FX.ChimeMinGap or 0.05) then return end
	if now - lastChimeAt > (FX.ChainResetSeconds or 0.8) then chain = 0 end
	lastChimeAt = now
	chain += 1
	soundIndex = soundIndex % #sounds + 1
	local sound = sounds[soundIndex]
	sound.PlaybackSpeed = math.min(FX.PitchMax or 1.6, (FX.PitchStart or 0.95) + chain * (FX.PitchStep or 0.05))
	sound.TimePosition = 0
	sound:Play()
end

local function sparkle(position, color)
	for i = 1, 3 do
		local spark = Instance.new("Part")
		spark.Anchored = true
		spark.CanCollide = false
		spark.CanQuery = false
		spark.CanTouch = false
		spark.CastShadow = false
		spark.Material = Enum.Material.Neon
		spark.Color = color or Color3.fromRGB(255, 240, 150)
		spark.Size = Vector3.new(0.3, 0.3, 0.3)
		spark.CFrame = CFrame.new(position) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		spark.Parent = fxFolder
		local out = spark.CFrame.Position + Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5) * (1 + i * 0.4)
		local tween = TweenService:Create(spark, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(1, 1, 1) * (1.4 - i * 0.3), Transparency = 1, Position = out,
		})
		tween.Completed:Once(function() spark:Destroy() end)
		tween:Play()
	end
end

-- Готовим локальную копию: всё заякорено, без коллизий, без лучей.
local function prepare(template)
	local copy = template:Clone()
	local parts = {}
	if copy:IsA("BasePart") then table.insert(parts, copy) end
	for _, d in copy:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") or d:IsA("ProximityPrompt") or d:IsA("BaseScript") then
			d:Destroy()
		end
	end
	for _, part in parts do
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
	end
	local color = nil
	for _, part in parts do
		if part.Transparency < 1 then color = part.Color break end
	end
	copy.Parent = fxFolder
	return copy, color
end

local active = {}

local function launch(template, position)
	local copy, color = prepare(template)
	local isModel = copy:IsA("Model")
	local baseScale = 1
	local baseSize = nil
	if isModel then
		local ok, scale = pcall(function() return copy:GetScale() end)
		baseScale = ok and scale or 1
	else
		baseSize = copy.Size
	end
	local angle = math.random() * math.pi * 2
	local side = range(FX.SideSpeed, 5)
	table.insert(active, {
		Object = copy,
		IsModel = isModel,
		BaseScale = baseScale,
		BaseSize = baseSize,
		Color = color,
		Position = position,
		Velocity = Vector3.new(math.cos(angle) * side, range(FX.LaunchSpeed, 26), math.sin(angle) * side),
		Phase = "Pop",
		Born = os.clock(),
		HangUntil = 0,
		Spin = range(FX.SpinSpeed, 8),
		Angle = 0,
		Scale = 1,
	})
end

local function setScale(entry, factor)
	if math.abs(entry.Scale - factor) < 0.02 then return end
	entry.Scale = factor
	if entry.IsModel then
		pcall(function() entry.Object:ScaleTo(math.max(0.05, entry.BaseScale * factor)) end)
	elseif entry.BaseSize then
		entry.Object.Size = entry.BaseSize * math.max(0.05, factor)
	end
end

RunService.RenderStepped:Connect(function(dt)
	if #active == 0 then return end
	dt = math.min(dt, 1 / 20)
	local now = os.clock()
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local target = hrp and (hrp.Position + Vector3.new(0, 0.9, 0))
	for index = #active, 1, -1 do
		local entry = active[index]
		local done = now - entry.Born > (FX.MaxLifetime or 2.5) or not entry.Object.Parent
		if entry.Phase == "Pop" then
			entry.Velocity += Vector3.new(0, -(FX.Gravity or 90) * dt, 0)
			entry.Position += entry.Velocity * dt
			if entry.Velocity.Y <= 0 then
				entry.Phase = "Hang"
				entry.HangUntil = now + range(FX.HangTime, 0.08)
				entry.Velocity = Vector3.zero
			end
		elseif entry.Phase == "Hang" then
			entry.Position += Vector3.new(0, math.sin((now - entry.HangUntil) * 20) * 0.01, 0)
			if now >= entry.HangUntil then entry.Phase = "Magnet" end
		elseif entry.Phase == "Magnet" and target then
			local offset = target - entry.Position
			local distance = offset.Magnitude
			if distance <= (FX.CollectDistance or 1.8) then
				chime()
				sparkle(entry.Position, entry.Color)
				done = true
			else
				entry.Velocity += (offset.Unit * (FX.MagnetAccel or 240) + Vector3.new(0, 18, 0)) * dt
				local maxSpeed = FX.MagnetMaxSpeed or 110
				if entry.Velocity.Magnitude > maxSpeed then entry.Velocity = entry.Velocity.Unit * maxSpeed end
				local along = entry.Velocity:Dot(offset.Unit)
				local lateral = entry.Velocity - offset.Unit * along
				entry.Velocity = offset.Unit * along + lateral * 0.82
				entry.Position += entry.Velocity * dt
				-- Сжимается на подлёте (последние ~5 стадов).
				setScale(entry, math.clamp(distance / (FX.ShrinkDistance or 5), FX.MinScale or 0.3, 1))
			end
		elseif not target then
			done = true
		end

		if done then
			entry.Object:Destroy()
			table.remove(active, index)
		else
			entry.Angle += entry.Spin * dt
			entry.Object:PivotTo(CFrame.new(entry.Position) * CFrame.Angles(entry.Angle * 0.6, entry.Angle, 0))
		end
	end
end)

remote.OnClientEvent:Connect(function(template, position, name)
	if typeof(position) ~= "Vector3" then return end
	if not template and typeof(name) == "string" then
		local folder = ReplicatedStorage:WaitForChild("OrePickupFxTemplates", 2)
		template = folder and folder:WaitForChild(name, 1.5)
	end
	if not template then
		sparkle(position)
		chime()
		return
	end
	local ok, err = pcall(launch, template, position)
	if not ok then warn("[OrePickupFx]", err) end
end)
