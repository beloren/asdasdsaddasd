--------------------------------------------------------------------------------
-- RevealVfx (v20.35) — ОДНОРАЗОВЫЙ эффект «появления» в точке мира: редкая
-- руда выпала, сундук открылся, аура престижа. Только клиент.
--
--   RevealVfx.Play({ "Reveal_Epic", "RevealVFX" }, position, { Color, Power, Parent })
--
-- СВОЙ ЭФФЕКТ: первое найденное имя из списка в ReplicatedStorage.Assets
-- (можно в подпапке, например Assets/VFX/Reveal_Epic):
--   • Attachment / Part / Model / Folder с ParticleEmitter, Beam, Light, Sound
--     внутри. Эмиттеры выстреливают ОДИН раз: :Emit(атрибут EmitCount, по
--     умолчанию 20). Beam/Light горят Duration (атрибут у корня, 0.6 с) и
--     гаснут. Sound — проигрываются. Цвета — как в ассете (не перекрашиваются).
--   • opts.Parent (BasePart) — эффект крепится к детали и едет с ней (аура
--     на персонаже), иначе стоит в точке position.
-- Нет ассета — встроенный плейсхолдер, сила Power 1…6 (редкость):
-- искры цвета редкости, кольцо-волна, вспышка света; с 5 — звёзды,
-- с 6 — тёмные разряды.
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local RevealVfx = {}

RevealVfx.RarityPower = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6, Secret = 6 }

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function findAsset(names)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then return nil end
	for _, name in names do
		local found = assets:FindFirstChild(name) or assets:FindFirstChild(name, true)
		if found then return found end
	end
	return nil
end

local function holderPart(position, parent)
	local part = Instance.new("Part")
	part.Name = "RevealVfxHolder"
	part.Size = Vector3.one * 0.2
	part.Transparency = 1
	part.Anchored = parent == nil
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	if parent then
		part.CFrame = parent.CFrame
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = part
		weld.Part1 = parent
		weld.Parent = part
		part.Parent = parent
	else
		part.CFrame = CFrame.new(position)
		part.Parent = workspace.CurrentCamera or workspace
	end
	return part
end

local function playAsset(asset, position, opts)
	local holder = holderPart(position, opts.Parent)
	local clone = asset:Clone()
	local duration = tonumber(asset:GetAttribute("Duration")) or 0.6
	if clone:IsA("Attachment") then
		clone.Parent = holder
	elseif clone:IsA("BasePart") or clone:IsA("Model") then
		for _, d in (clone:IsA("Model") and clone:GetDescendants() or { clone, table.unpack(clone:GetDescendants()) }) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			end
		end
		if clone:IsA("Model") then clone:PivotTo(holder.CFrame) else clone.CFrame = holder.CFrame end
		clone.Parent = holder
		if opts.Parent then
			-- Модель крепим к детали, чтобы ехала вместе с ней.
			for _, d in (clone:IsA("Model") and clone:GetDescendants() or { clone }) do
				if d:IsA("BasePart") then
					d.Anchored = false
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = d
					weld.Part1 = holder
					weld.Parent = d
				end
			end
		end
	else
		-- Folder и прочее: всё, что внутри, — на держатель.
		local attachment = Instance.new("Attachment")
		attachment.Parent = holder
		for _, child in clone:GetChildren() do child.Parent = attachment end
		clone:Destroy()
	end
	local longest = duration
	for _, d in holder:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			d.Enabled = false
			d:Emit(math.max(1, math.floor(tonumber(d:GetAttribute("EmitCount")) or 20)))
			longest = math.max(longest, d.Lifetime.Max)
		elseif d:IsA("Beam") or d:IsA("Light") or d:IsA("Trail") then
			d.Enabled = true
			task.delay(duration, function() if d.Parent then d.Enabled = false end end)
		elseif d:IsA("Sound") then
			d:Play()
			longest = math.max(longest, d.TimeLength)
		end
	end
	Debris:AddItem(holder, longest + 0.5)
end

local function emitter(parent, props, count)
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.LightEmission = 1
	e.LightInfluence = 0
	for key, value in props do e[key] = value end
	e.Parent = parent
	e:Emit(count)
	return e
end

local function playPlaceholder(position, opts)
	local color = opts.Color or Color3.new(1, 1, 1)
	local power = math.clamp(opts.Power or 3, 1, 6)
	local holder = holderPart(position, opts.Parent)
	local attachment = Instance.new("Attachment")
	attachment.Parent = holder
	-- Искры веером вверх.
	emitter(attachment, {
		Texture = SPARKLE,
		Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.35), color),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4 + power * 0.08), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.5, 1),
		Speed = NumberRange.new(10, 16 + power * 3),
		SpreadAngle = Vector2.new(55, 55),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -30, 0),
		Drag = 2,
	}, 10 + power * 8)
	-- Мягкое облачко цвета редкости.
	emitter(attachment, {
		Texture = SMOKE,
		Color = ColorSequence.new(color),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 3 + power) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180),
		LightEmission = 0.6,
	}, 4 + power)
	if power >= 5 then
		-- Звёзды: крупные медленные блёстки.
		emitter(attachment, {
			Texture = SPARKLE,
			Color = ColorSequence.new(Color3.fromRGB(255, 245, 200)),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 1.1), NumberSequenceKeypoint.new(1, 0) }),
			Lifetime = NumberRange.new(0.9, 1.4),
			Speed = NumberRange.new(3, 7),
			SpreadAngle = Vector2.new(180, 180),
			RotSpeed = NumberRange.new(-120, 120),
		}, power * 3)
	end
	if power >= 6 then
		-- Тёмные разряды для самого редкого.
		emitter(attachment, {
			Texture = SPARKLE,
			Color = ColorSequence.new(Color3.fromRGB(40, 10, 60), color),
			LightEmission = 0.2,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) }),
			Lifetime = NumberRange.new(0.3, 0.6),
			Speed = NumberRange.new(18, 30),
			SpreadAngle = Vector2.new(180, 180),
		}, 30)
	end
	-- Кольцо-волна по земле (Rare+).
	if power >= 3 then
		local ring = Instance.new("Part")
		ring.Name = "RevealRing"
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.15, 1, 1)
		ring.Material = Enum.Material.Neon
		ring.Color = color
		ring.Transparency = 0.3
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.CastShadow = false
		ring.CFrame = CFrame.new(holder.Position - Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = workspace.CurrentCamera or workspace
		local size = 6 + power * 2
		TweenService:Create(ring, TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.15, size, size), Transparency = 1,
		}):Play()
		Debris:AddItem(ring, 0.7)
	end
	-- Вспышка света.
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 2 + power
	light.Range = 10 + power * 3
	light.Shadows = false
	light.Parent = holder
	TweenService:Create(light, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
	Debris:AddItem(holder, 1.8)
end

function RevealVfx.Play(names, position, opts)
	opts = opts or {}
	if typeof(names) == "string" then names = { names } end
	if typeof(position) ~= "Vector3" and not opts.Parent then return end
	local asset = findAsset(names or {})
	local ok, err = pcall(function()
		if asset then
			playAsset(asset, position, opts)
		else
			playPlaceholder(position, opts)
		end
	end)
	if not ok then warn("[RevealVfx]", err) end
end

return RevealVfx
