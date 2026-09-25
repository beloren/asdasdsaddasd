--------------------------------------------------------------------------------
-- SafeBounceFX (LocalScript) v20.23 — сейф пружинит, когда из него забирают
-- деньги: сплющивается, вытягивается вверх и затухающе покачивается.
--
-- Сервер (PassiveIncomeService:Collect) увеличивает атрибут CollectPulse у
-- сейфа с тегом SafeBounce. Анимация — ЛОКАЛЬНО у каждого клиента: размеры
-- и позиции деталей вокруг центра нижней грани, в конце всё возвращается
-- ровно к исходным значениям. Своя модель сейфа (Assets/GeodeSafe) работает
-- так же — масштабируются все её BasePart.
--------------------------------------------------------------------------------
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local TAG = "SafeBounce"
-- Ключи масштаба: время (сек), ширина (X/Z), высота (Y).
local KEYS = {
	{ 0.00, 1.00, 1.00 },
	{ 0.07, 1.14, 0.80 }, -- сплющился
	{ 0.19, 0.93, 1.16 }, -- подпрыгнул вверх
	{ 0.31, 1.05, 0.95 },
	{ 0.42, 0.98, 1.03 },
	{ 0.52, 1.00, 1.00 },
}
local DURATION = KEYS[#KEYS][1]

local active = {} -- [safe] = { Start, Anchor, Parts = { [part] = { CFrame, Size } } }

local function partsOf(safe)
	if safe:IsA("BasePart") then
		local list = { safe }
		for _, d in safe:GetDescendants() do
			if d:IsA("BasePart") then table.insert(list, d) end
		end
		return list
	end
	local list = {}
	for _, d in safe:GetDescendants() do
		if d:IsA("BasePart") then table.insert(list, d) end
	end
	return list
end

-- Центр нижней грани в ориентации сейфа.
local function anchorOf(safe)
	local cf, size
	if safe:IsA("Model") then
		cf, size = safe:GetBoundingBox()
	else
		cf, size = safe.CFrame, safe.Size
	end
	return cf * CFrame.new(0, -size.Y / 2, 0)
end

local function sample(t)
	for i = 2, #KEYS do
		local a, b = KEYS[i - 1], KEYS[i]
		if t <= b[1] then
			local alpha = (t - a[1]) / (b[1] - a[1])
			alpha = alpha * alpha * (3 - 2 * alpha) -- smoothstep
			return a[2] + (b[2] - a[2]) * alpha, a[3] + (b[3] - a[3]) * alpha
		end
	end
	return 1, 1
end

local function apply(state, wide, tall)
	local anchor = state.Anchor
	local parts, frames = {}, {}
	for part, base in state.Parts do
		if part.Parent then
			local rel = anchor:ToObjectSpace(base.CFrame)
			local p = rel.Position
			local scaled = anchor * (CFrame.new(p.X * wide, p.Y * tall, p.Z * wide) * rel.Rotation)
			-- Размер детали по её собственным осям: сколько каждая ось
			-- смотрит «вверх» (растёт по высоте) и «вбок» (по ширине).
			local function axisScale(v)
				local up = math.abs(v.Y)
				return up * tall + (1 - up) * wide
			end
			part.Size = Vector3.new(
				base.Size.X * axisScale(rel.RightVector),
				base.Size.Y * axisScale(rel.UpVector),
				base.Size.Z * axisScale(-rel.LookVector)
			)
			table.insert(parts, part)
			table.insert(frames, scaled)
		end
	end
	workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end

local function restore(state)
	local parts, frames = {}, {}
	for part, base in state.Parts do
		if part.Parent then
			part.Size = base.Size
			table.insert(parts, part)
			table.insert(frames, base.CFrame)
		end
	end
	workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end

local function play(safe)
	if not safe.Parent then return end
	local state = active[safe]
	if state then
		state.Start = os.clock() -- уже пружинит — начинаем заново от исходной формы
		return
	end
	state = { Start = os.clock(), Anchor = anchorOf(safe), Parts = {} }
	for _, part in partsOf(safe) do
		state.Parts[part] = { CFrame = part.CFrame, Size = part.Size }
	end
	active[safe] = state
end

local function track(safe)
	safe:GetAttributeChangedSignal("CollectPulse"):Connect(function()
		play(safe)
	end)
end

for _, safe in CollectionService:GetTagged(TAG) do track(safe) end
CollectionService:GetInstanceAddedSignal(TAG):Connect(track)

RunService.RenderStepped:Connect(function()
	for safe, state in active do
		local t = os.clock() - state.Start
		if not safe.Parent or t >= DURATION then
			restore(state)
			active[safe] = nil
		else
			apply(state, sample(t))
		end
	end
end)
