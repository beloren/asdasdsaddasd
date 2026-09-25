--------------------------------------------------------------------------------
-- PrestigeAuraFX (LocalScript) v20.35 — АУРА-КОРОНА вокруг игрока после
-- престижа. Видят все: сервер (RebirthService) ставит игроку атрибут
-- PrestigeFxAt, каждый клиент проигрывает эффект на его персонаже.
--
-- Свой эффект: ReplicatedStorage.Assets.PrestigeVFX (можно в подпапке VFX) —
-- Attachment / Part / Model / Folder с эмиттерами, светом, звуком; крепится
-- к HumanoidRootPart и выстреливает один раз (см. shared/RevealVfx).
-- Нет ассета — плейсхолдер: вспышка у ног, золотая аура на теле ~4 с и
-- вращающаяся корона из золотых зубцов над головой.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local RevealVfx = require(ReplicatedStorage.Shared.RevealVfx)

local GOLD = Color3.fromRGB(255, 205, 70)
local AURA_SECONDS = 4

local function hasAsset()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	return assets and (assets:FindFirstChild("PrestigeVFX") or assets:FindFirstChild("PrestigeVFX", true)) ~= nil
end

local function crown(head)
	local parts = {}
	local spikes = 7
	for i = 1, spikes do
		local spike = Instance.new("Part")
		spike.Name = "PrestigeCrownSpike"
		spike.Size = Vector3.new(0.18, 0.55, 0.18)
		spike.Material = Enum.Material.Neon
		spike.Color = GOLD
		spike.Anchored = true
		spike.CanCollide = false
		spike.CanQuery = false
		spike.CanTouch = false
		spike.CastShadow = false
		spike.Transparency = 1
		spike.Parent = workspace.CurrentCamera
		table.insert(parts, spike)
	end
	local band = Instance.new("Part")
	band.Name = "PrestigeCrownBand"
	band.Shape = Enum.PartType.Cylinder
	band.Size = Vector3.new(0.14, 1.5, 1.5)
	band.Material = Enum.Material.Neon
	band.Color = GOLD
	band.Anchored = true
	band.CanCollide = false
	band.CanQuery = false
	band.CanTouch = false
	band.CastShadow = false
	band.Transparency = 1
	band.Parent = workspace.CurrentCamera
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		if not head.Parent or t > AURA_SECONDS + 0.6 then
			connection:Disconnect()
			for _, p in parts do p:Destroy() end
			band:Destroy()
			return
		end
		-- Появление, покачивание, растворение.
		local alpha = math.min(t / 0.35, 1) * (1 - math.clamp((t - AURA_SECONDS) / 0.6, 0, 1))
		local lift = 1.35 + math.sin(t * 3) * 0.08 + (1 - math.min(t / 0.35, 1)) * 1.5
		local center = head.Position + Vector3.new(0, lift, 0)
		local spin = t * 1.8
		band.CFrame = CFrame.new(center) * CFrame.Angles(0, spin, math.rad(90))
		band.Transparency = 1 - alpha * 0.7
		for i, spike in parts do
			local angle = spin + (i / #parts) * math.pi * 2
			spike.CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * 0.7, 0.3, math.sin(angle) * 0.7))
			spike.Transparency = 1 - alpha
		end
	end)
end

local function aura(root)
	local attachment = Instance.new("Attachment")
	attachment.Name = "PrestigeAura"
	attachment.Parent = root
	local glow = Instance.new("ParticleEmitter")
	glow.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	glow.Color = ColorSequence.new(Color3.fromRGB(255, 245, 190), GOLD)
	glow.LightEmission = 1
	glow.LightInfluence = 0
	glow.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	glow.Lifetime = NumberRange.new(0.8, 1.4)
	glow.Rate = 40
	glow.Speed = NumberRange.new(1.5, 3.5)
	glow.SpreadAngle = Vector2.new(180, 180)
	glow.Acceleration = Vector3.new(0, 3, 0)
	glow.Shape = Enum.ParticleEmitterShape.Cylinder
	glow.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	glow.Parent = attachment
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Brightness = 2.5
	light.Range = 12
	light.Parent = attachment
	task.delay(AURA_SECONDS, function()
		glow.Enabled = false
		TweenService:Create(light, TweenInfo.new(0.6), { Brightness = 0 }):Play()
	end)
	task.delay(AURA_SECONDS + 1.6, function() attachment:Destroy() end)
end

local function play(target)
	local character = target.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local head = character and character:FindFirstChild("Head")
	if not root then return end
	if hasAsset() then
		RevealVfx.Play({ "PrestigeVFX" }, nil, { Parent = root, Color = GOLD, Power = 6 })
		return
	end
	RevealVfx.Play({ "__none__" }, root.Position - Vector3.new(0, 2.5, 0), { Color = GOLD, Power = 5 })
	aura(root)
	if head then crown(head) end
end

local function track(target)
	target:GetAttributeChangedSignal("PrestigeFxAt"):Connect(function()
		play(target)
	end)
end

for _, target in Players:GetPlayers() do track(target) end
Players.PlayerAdded:Connect(track)
