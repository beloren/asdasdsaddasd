--------------------------------------------------------------------------------
-- AssetVfx v20.106 — эффекты из ReplicatedStorage.Assets.VFX (и вложенных
-- папок Assets): BigDynamite / MediumDynamite / SmallDynamite, BoomOrAttack,
-- Rocks, ThunderVFX, Sparkles, OpenVFX. Работает и на сервере (видно всем), и
-- на клиенте (видно только себе).
--
--   AssetVfx.PlayAt(name, position, opts)  — вспышка в точке (невидимая
--       деталь + клон аттачмента), сама удаляется через opts.Duration.
--   AssetVfx.AttachTo(name, part, opts)    — то же на детали (Rocks в валуне,
--       Sparkles на игроке).
--   opts: Color (перекраска эмиттеров), Scale (размер частиц), Duration
--         (сколько живёт, с), Burst (сколько частиц выпустить сразу; иначе
--         эмиттер просто включён Duration), Fallback (имя запасного эффекта,
--         по умолчанию OpenVFX).
-- Нет ни самого эффекта, ни запасного — ничего не происходит.
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local AssetVfx = {}

local function findTemplate(name)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then return nil end
	local vfx = assets:FindFirstChild("VFX") or assets:FindFirstChild("Vfx")
	return (vfx and (vfx:FindFirstChild(name) or vfx:FindFirstChild(name, true))) or assets:FindFirstChild(name, true)
end

-- Клон эффекта как Attachment (ParticleEmitter без аттачмента тоже годится -
-- заворачиваем его в новый Attachment).
function AssetVfx.Clone(name)
	local template = findTemplate(name)
	if not template then return nil end
	local clone = template:Clone()
	if clone:IsA("Attachment") then return clone end
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	if clone:IsA("ParticleEmitter") or clone:IsA("Light") or clone:IsA("Beam") then
		clone.Parent = attachment
		return attachment
	end
	local nested = clone:FindFirstChildWhichIsA("Attachment", true)
	if nested then
		nested.Parent = nil
		clone:Destroy()
		nested.Name = name
		return nested
	end
	for _, d in clone:GetDescendants() do
		if d:IsA("ParticleEmitter") or d:IsA("Light") then d.Parent = attachment end
	end
	clone:Destroy()
	return attachment
end

local function scaleSequence(sequence, factor)
	local points = {}
	for _, key in sequence.Keypoints do
		table.insert(points, NumberSequenceKeypoint.new(key.Time, key.Value * factor, key.Envelope * factor))
	end
	return NumberSequence.new(points)
end

local function prepare(attachment, opts)
	opts = opts or {}
	for _, d in attachment:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			if opts.Color then d.Color = ColorSequence.new(opts.Color) end
			if opts.Scale and opts.Scale ~= 1 then
				d.Size = scaleSequence(d.Size, opts.Scale)
				d.Speed = NumberRange.new(d.Speed.Min * opts.Scale, d.Speed.Max * opts.Scale)
			end
		elseif d:IsA("Light") and opts.Color then
			d.Color = opts.Color
		end
	end
end

local function fire(attachment, opts)
	opts = opts or {}
	local duration = opts.Duration or 1.5
	for _, d in attachment:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			local burst = opts.Burst or d:GetAttribute("EmitCount")
			if burst then
				d.Enabled = false
				d:Emit(math.max(1, math.floor(tonumber(burst) or 10)))
			else
				d.Enabled = true
				task.delay(math.max(0.1, duration - (d.Lifetime.Max or 0)), function()
					if d.Parent then d.Enabled = false end
				end)
			end
		end
	end
	Debris:AddItem(attachment, duration + 3)
end

local function resolve(name, opts)
	local attachment = AssetVfx.Clone(name)
	if not attachment and (opts == nil or opts.Fallback ~= false) then
		attachment = AssetVfx.Clone((opts and opts.Fallback) or "OpenVFX")
	end
	return attachment
end

function AssetVfx.PlayAt(name, position, opts)
	local attachment = resolve(name, opts)
	if not attachment or typeof(position) ~= "Vector3" then return nil end
	local holder = Instance.new("Part")
	holder.Name = "Vfx_" .. name
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one * 0.2
	holder.CFrame = CFrame.new(position)
	prepare(attachment, opts)
	attachment.CFrame = CFrame.new()
	attachment.Parent = holder
	holder.Parent = workspace
	fire(attachment, opts)
	Debris:AddItem(holder, (opts and opts.Duration or 1.5) + 3.2)
	return attachment
end

function AssetVfx.AttachTo(name, part, opts)
	if not (part and part:IsA("BasePart")) then return nil end
	local attachment = resolve(name, opts)
	if not attachment then return nil end
	prepare(attachment, opts)
	attachment.CFrame = CFrame.new(opts and opts.Offset or Vector3.zero)
	attachment.Parent = part
	fire(attachment, opts)
	return attachment
end

return AssetVfx
