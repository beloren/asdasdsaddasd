--------------------------------------------------------------------------------
-- FurnaceFX (LocalScript) — анимация плавильни на островах (у ВСЕХ игроков).
--
-- Сервер (IslandService) ставит на модель печи атрибуты:
--   IsSmelter = true
--   FurnaceActive = true/false — внутри что-то плавится (сервер сам
--                   переключает видимость моделей furnace_active /
--                   furnace_inactive);
--   SquashTarget  = "furnace_active" — анимировать эту модель внутри печи,
--                   "" — всю печь (плейсхолдер);
--   SpitCount     — растёт на 1 при каждом "плевке" готовыми слитками.
--
-- Пока печь активна, она ритмично и РЕЗКО проседает вниз по высоте (и чуть
-- раздаётся вширь), затем пружинит обратно — "плавится". При плевке —
-- сильный рывок: присела → вытянулась вверх → села на место.
--
-- Всё только ЛОКАЛЬНО: размеры и CFrame деталей меняются на клиенте и не
-- реплицируются. Каждый кадр позиции считаются от опорной детали (PrimaryPart
-- печи), поэтому анимация не мешает серверу двигать остров (подъём из-под
-- земли) — печь просто едет вместе с опорой.
--------------------------------------------------------------------------------

local RunService = game:GetService("RunService")

-- Ритм "плавления": каждый период — резкое проседание, пауза, отскок.
local PERIOD = 1.05
local PRESS_SECONDS = 0.09   -- резко вниз
local HOLD_SECONDS = 0.12    -- держит "расплывшись"
local RELEASE_SECONDS = 0.28 -- пружинит обратно
local SQUASH_Y = 0.12        -- насколько проседает по высоте (доля)
local SQUASH_XZ = 0.06       -- насколько раздаётся вширь
local SPIT_SECONDS = 0.55
local MAX_DISTANCE = 220     -- дальше — не анимируем (экономия)

local tracked = {} -- [Model] = record

local function easeOutBack(t)
	local c1, c3 = 1.7, 2.7
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

-- Кривая плавления: 0 = покой, 1 = максимальное проседание.
local function meltAmount(t)
	local phase = t % PERIOD
	if phase < PRESS_SECONDS then
		local a = phase / PRESS_SECONDS
		return a * a -- резкий, ускоряющийся рывок вниз
	end
	phase -= PRESS_SECONDS
	if phase < HOLD_SECONDS then return 1 end
	phase -= HOLD_SECONDS
	if phase < RELEASE_SECONDS then
		local a = phase / RELEASE_SECONDS
		-- отскок с небольшим перелётом выше покоя (отрицательное значение)
		return 1 - easeOutBack(a)
	end
	return 0
end

-- Рывок "плевка": присела (0..0.25), вытянулась вверх (0.25..0.5), села.
local function spitAmount(elapsed)
	if elapsed >= SPIT_SECONDS then return 0 end
	local t = elapsed / SPIT_SECONDS
	if t < 0.25 then return (t / 0.25) * 1.6 end
	if t < 0.5 then return 1.6 - ((t - 0.25) / 0.25) * 2.6 end
	return -1 + easeOutBack((t - 0.5) / 0.5)
end

local function restore(record)
	for _, entry in record.Parts do
		local part = entry.Part
		if part.Parent then
			part.Size = entry.Size
			part.CFrame = record.Anchor.CFrame * entry.Offset
		end
	end
end

-- Снимок "покоя": смещение каждой детали от опоры и её размер. Снимаем
-- заново при каждом включении — модель могла быть пересобрана/сдвинута.
local function capture(record)
	local model = record.Model
	local anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not anchor then return false end
	local targetName = model:GetAttribute("SquashTarget")
	local target = (typeof(targetName) == "string" and targetName ~= "") and model:FindFirstChild(targetName, true) or model
	if not target then target = model end
	record.Anchor = anchor
	record.Parts = {}
	local minY = math.huge
	local sumX, sumZ, count = 0, 0, 0
	for _, part in target:GetDescendants() do
		if part:IsA("BasePart") and part ~= anchor and part:GetAttribute("NoSquash") ~= true
			and part.Name ~= "Mouth" then
			local offset = anchor.CFrame:ToObjectSpace(part.CFrame)
			table.insert(record.Parts, { Part = part, Offset = offset, Size = part.Size })
			-- низ детали в системе опоры
			local half = part.Size / 2
			local drop = math.abs(offset.RightVector.Y) * half.X + math.abs(offset.UpVector.Y) * half.Y + math.abs(offset.LookVector.Y) * half.Z
			minY = math.min(minY, offset.Position.Y - drop)
			sumX += offset.Position.X
			sumZ += offset.Position.Z
			count += 1
		end
	end
	if count == 0 then return false end
	-- Точка, к которой всё "оседает": низ анимируемой части, по центру.
	record.Pivot = Vector3.new(sumX / count, minY, sumZ / count)
	return true
end

local function applyScale(record, sx, sy, sz)
	local anchorCFrame = record.Anchor.CFrame
	local pivot = record.Pivot
	for _, entry in record.Parts do
		local part = entry.Part
		if part.Parent then
			local offset = entry.Offset
			local p = offset.Position - pivot
			local position = pivot + Vector3.new(p.X * sx, p.Y * sy, p.Z * sz)
			local rotation = offset - offset.Position
			-- Масштаб по мировым (опорным) осям → по локальным осям детали.
			local r, u, l = offset.RightVector, offset.UpVector, offset.LookVector
			local fx = math.abs(r.X) * sx + math.abs(r.Y) * sy + math.abs(r.Z) * sz
			local fy = math.abs(u.X) * sx + math.abs(u.Y) * sy + math.abs(u.Z) * sz
			local fz = math.abs(l.X) * sx + math.abs(l.Y) * sy + math.abs(l.Z) * sz
			part.Size = Vector3.new(entry.Size.X * fx, entry.Size.Y * fy, entry.Size.Z * fz)
			part.CFrame = anchorCFrame * CFrame.new(position) * rotation
		end
	end
end

local function track(model)
	if tracked[model] then return end
	local record = {
		Model = model,
		Active = false,
		Parts = {},
		StartedAt = os.clock(),
		SpitAt = -math.huge,
		LastSpitCount = tonumber(model:GetAttribute("SpitCount")) or 0,
	}
	tracked[model] = record

	local function refreshActive()
		local active = model:GetAttribute("FurnaceActive") == true
		if active == record.Active then return end
		if active then
			record.Active = capture(record)
			record.StartedAt = os.clock()
		else
			if record.Anchor then restore(record) end
			record.Active = false
		end
	end
	model:GetAttributeChangedSignal("FurnaceActive"):Connect(refreshActive)
	model:GetAttributeChangedSignal("SpitCount"):Connect(function()
		local count = tonumber(model:GetAttribute("SpitCount")) or 0
		if count <= record.LastSpitCount then return end
		record.LastSpitCount = count
		-- Плевок бывает и у уже остывшей печи (последняя руда допеклась) —
		-- снимаем покой, если ещё не сняли.
		if not record.Active then capture(record) end
		record.SpitAt = os.clock()
		record.SpitRestorePending = true
	end)
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then tracked[model] = nil end
	end)
	-- Атрибуты могут доехать кадром позже модели.
	task.defer(refreshActive)
end

local function consider(instance)
	if instance:IsA("Model") and instance:GetAttribute("IsSmelter") == true then
		track(instance)
	elseif instance:IsA("Model") and instance.Name == "Smelter" then
		-- Атрибут IsSmelter мог ещё не доехать.
		task.defer(function()
			if instance.Parent and instance:GetAttribute("IsSmelter") == true then track(instance) end
		end)
	end
end

task.spawn(function()
	local plots = workspace:WaitForChild("Plots", 60)
	if not plots then return end
	for _, descendant in plots:GetDescendants() do consider(descendant) end
	plots.DescendantAdded:Connect(consider)
end)

RunService.RenderStepped:Connect(function()
	local camera = workspace.CurrentCamera
	local cameraPosition = camera and camera.CFrame.Position
	local now = os.clock()
	for model, record in tracked do
		local spitElapsed = now - record.SpitAt
		local spitting = spitElapsed < SPIT_SECONDS
		-- Рывок кончился у остывшей печи — возвращаем детали в покой.
		if not spitting and record.SpitRestorePending then
			record.SpitRestorePending = false
			if not record.Active and record.Anchor and record.Anchor.Parent then restore(record) end
		end
		if (record.Active or spitting) and record.Anchor and record.Anchor.Parent and model.Parent then
			if cameraPosition and (record.Anchor.Position - cameraPosition).Magnitude > MAX_DISTANCE then
				continue
			end
			local melt = record.Active and meltAmount(now - record.StartedAt) or 0
			local spit = spitting and spitAmount(spitElapsed) or 0
			-- Плевок перекрывает ритм: во время рывка ритм не смешиваем.
			local squash = spitting and spit or melt
			local sy = 1 - SQUASH_Y * squash
			local sxz = 1 + SQUASH_XZ * squash
			applyScale(record, sxz, sy, sxz)
		end
	end
end)
