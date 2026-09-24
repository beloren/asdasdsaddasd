--------------------------------------------------------------------------------
-- EssenceFX (LocalScript) v18 — вспышка на подиуме, когда игрок наносит
-- эссенцию мутации на кристалл (PassiveIncomeService:ApplyEssence).
-- Столб света цвета мутации, кольцо по земле и искры вверх.
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local remote = ReplicatedStorage.Shared:WaitForChild("EssenceFx", 30)
if not remote then return end

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local function fxPart(props)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	for key, value in props do part[key] = value end
	part.Parent = workspace
	return part
end

remote.OnClientEvent:Connect(function(podium, color)
	if typeof(podium) ~= "Instance" or not podium.Parent then return end
	color = typeof(color) == "Color3" and color or Color3.fromRGB(200, 120, 255)
	local cf, size
	if podium:IsA("Model") then
		cf, size = podium:GetBoundingBox()
	elseif podium:IsA("BasePart") then
		cf, size = podium.CFrame, podium.Size
	else
		return
	end
	local top = cf.Position + Vector3.new(0, size.Y / 2, 0)

	-- Столб света.
	local beam = fxPart({ Shape = Enum.PartType.Cylinder, Color = color, Transparency = 0.2,
		Size = Vector3.new(0.2, 3, 3), CFrame = CFrame.new(top + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)) })
	TweenService:Create(beam, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(26, 3.4, 3.4), CFrame = CFrame.new(top + Vector3.new(0, 13, 0)) * CFrame.Angles(0, 0, math.rad(90)),
	}):Play()
	task.delay(0.35, function()
		local fade = TweenService:Create(beam, TweenInfo.new(0.6), { Transparency = 1, Size = Vector3.new(26, 0.4, 0.4) })
		fade.Completed:Once(function() beam:Destroy() end)
		fade:Play()
	end)

	-- Кольцо по земле.
	local ring = fxPart({ Shape = Enum.PartType.Cylinder, Color = color, Transparency = 0.3,
		Size = Vector3.new(0.1, 2, 2), CFrame = CFrame.new(top) * CFrame.Angles(0, 0, math.rad(90)) })
	local grow = TweenService:Create(ring, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.1, 18, 18), Transparency = 1,
	})
	grow.Completed:Once(function() ring:Destroy() end)
	grow:Play()

	-- Искры вверх.
	local anchor = fxPart({ Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(top + Vector3.new(0, 1, 0)) })
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Speed = NumberRange.new(10, 22)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Acceleration = Vector3.new(0, -8, 0)
	emitter.Enabled = false
	emitter.Parent = anchor
	emitter:Emit(60)
	task.delay(1.6, function() anchor:Destroy() end)
end)
