--------------------------------------------------------------------------------
-- LootBeamFX (LocalScript) — СТОЛБ СВЕТА НАД РЕДКИМ ЛУТОМ (v14).
--
-- Сервер помечает лут атрибутом LootBeamColor (Color3): редкая руда из
-- базовых валунов (RockService:spawnBaseBoulderOre), кристаллы с мутацией
-- или высокой редкости (spawnLooseCrystal). Здесь над таким предметом
-- рисуется вертикальный луч и мягкое кольцо на земле, пока предмет существует.
-- Луч висит на невидимой детали, которая просто следует за позицией лута,
-- поэтому кувыркание/вращение самого куска его не качает.
--------------------------------------------------------------------------------
local RunService = game:GetService("RunService")

local tracked = {} -- [instance] = { Holder, Root }

local function rootOf(instance)
	if instance:IsA("BasePart") then return instance end
	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChild("Root", true) or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function attach(instance)
	if tracked[instance] then return end
	local color = instance:GetAttribute("LootBeamColor")
	if typeof(color) ~= "Color3" then return end
	local root = rootOf(instance)
	if not root then return end
	local holder = Instance.new("Part")
	holder.Name = "LootBeamHolder"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one * 0.2
	holder.CFrame = CFrame.new(root.Position)
	holder.Parent = workspace.CurrentCamera or workspace
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -0.5, 0)
	bottom.Parent = holder
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, 14, 0)
	top.Parent = holder
	local beam = Instance.new("Beam")
	beam.Attachment0 = bottom
	beam.Attachment1 = top
	beam.Color = ColorSequence.new(color)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Width0 = 1.4
	beam.Width1 = 0.2
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	beam.Parent = holder
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 9
	light.Brightness = 1.6
	light.Parent = holder
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(color)
	sparkle.LightEmission = 1
	sparkle.Rate = 6
	sparkle.Lifetime = NumberRange.new(0.8, 1.4)
	sparkle.Speed = NumberRange.new(1.5, 3)
	sparkle.EmissionDirection = Enum.NormalId.Top
	sparkle.SpreadAngle = Vector2.new(20, 20)
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Parent = bottom
	tracked[instance] = { Holder = holder, Root = root, Beam = beam, Born = os.clock() }
end

local function detach(instance)
	local entry = tracked[instance]
	if not entry then return end
	tracked[instance] = nil
	if entry.Holder then entry.Holder:Destroy() end
end

local function watch(instance)
	if instance:GetAttribute("LootBeamColor") ~= nil then attach(instance) end
end

for _, instance in workspace:GetDescendants() do
	watch(instance)
end
workspace.DescendantAdded:Connect(function(instance)
	-- Атрибут может выставляться сразу после вставки — даём кадр.
	task.defer(watch, instance)
end)
workspace.DescendantRemoving:Connect(detach)

RunService.RenderStepped:Connect(function()
	for instance, entry in tracked do
		if not instance.Parent or not entry.Root.Parent or instance:GetAttribute("LootBeamColor") == nil then
			detach(instance)
		else
			entry.Holder.CFrame = CFrame.new(entry.Root.Position)
			-- Луч «вырастает» первые полсекунды.
			local grow = math.clamp((os.clock() - entry.Born) / 0.5, 0, 1)
			entry.Beam.Width0 = 1.4 * grow
		end
	end
end)
