--------------------------------------------------------------------------------
-- BridgeRiseFX (LocalScript) v20.25 — мосты выезжают из-под земли, когда
-- игрок подходит, и уходят обратно, когда он отходит (Config.Bridges).
--
-- Мост — любая Model в Workspace с именем по Config.Bridges.NamePattern
-- ("Bridge", "Bridge2", …). Всё ЛОКАЛЬНО: у каждого игрока свой вид, сервер
-- мосты не двигает. Спрятанный мост опущен под землю на Depth и невидим
-- (LocalTransparencyModifier у деталей и декалей, выключены свет, частицы,
-- лучи и надписи). По спрятанному мосту пройти нельзя — его нет под ногами.
--
-- Подъём: волна по частям моста от ближнего к игроку края, каждая часть
-- «перелетает» вверх и пружинит на место (Back Out). Спуск: короткий
-- подскок вверх и уход вниз (Back In), к концу исчезает.
--
-- Анкоренные детали двигаются напрямую (BulkMoveTo), неанкоренные едут за
-- ними по сваркам. Если сервер сам сдвинет мост (например, он внутри
-- острова, который выезжает при покупке) — новая позиция становится базой.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local CFG = Config.Bridges or {}
if CFG.Enabled == false then return end

local player = Players.LocalPlayer
local PATTERN = CFG.NamePattern or "^Bridge"
local SHOW = CFG.ShowDistance or 38
local HIDE = math.max(CFG.HideDistance or 52, SHOW + 4)
local RISE = CFG.RiseSeconds or 0.9
local SINK = CFG.SinkSeconds or 0.75
local OVERSHOOT = CFG.Overshoot or 1.6
local STAGGER = CFG.Stagger or 0.035
local WAVE_MAX = 0.45 -- волна по частям не дольше этого (сек), сколько бы деталей ни было

local bridges = {} -- [model] = state

local function backOut(a)
	local s = OVERSHOOT
	return 1 + (s + 1) * (a - 1) ^ 3 + s * (a - 1) ^ 2
end

local function backIn(a)
	local s = OVERSHOOT
	return (s + 1) * a ^ 3 - s * a ^ 2
end

--------------------------------------------------------------------------------
-- СОСТОЯНИЕ МОСТА
--------------------------------------------------------------------------------
local FX_CLASSES = { ParticleEmitter = true, PointLight = true, SpotLight = true, SurfaceLight = true, Beam = true, Trail = true, Fire = true, Smoke = true, Sparkles = true }

local function addItem(state, item)
	if item:IsA("BasePart") then
		if item.Anchored then
			state.Parts[item] = { Base = item.CFrame, Expected = item.CFrame, Delay = 0 }
		end
		state.Visuals[item] = "Part"
	elseif item:IsA("Decal") or item:IsA("Texture") then
		state.Visuals[item] = "Part"
	elseif FX_CLASSES[item.ClassName] then
		state.Fx[item] = item.Enabled
	elseif item:IsA("BillboardGui") or item:IsA("SurfaceGui") then
		state.Fx[item] = item.Enabled
	end
end

local function measure(state)
	local ok, cf, size = pcall(function() return state.Model:GetBoundingBox() end)
	if ok then
		-- Габарит — в НЕ сдвинутом положении (база): детали сейчас ниже
		-- базы на Offset, значит база выше на столько же.
		state.Box = cf + Vector3.new(0, state.Offset, 0)
		state.Size = size
	end
	state.Depth = CFG.Depth or ((state.Size and state.Size.Y or 6) + 3)
end

-- Задержки волны: от края моста, ближнего к игроку.
local function planWave(state, fromPosition)
	if not state.Box then return end
	local size = state.Size
	local axis = size.X >= size.Z and state.Box.RightVector or state.Box.LookVector
	local half = math.max(size.X, size.Z) / 2
	local count = 0
	for _ in state.Parts do count += 1 end
	local span = math.min(STAGGER * count, WAVE_MAX)
	local towards = true -- игрок со стороны +axis: волна идёт от того края
	if fromPosition then
		towards = (fromPosition - state.Box.Position):Dot(axis) >= 0
	end
	for part, info in state.Parts do
		local along = (info.Base.Position - state.Box.Position):Dot(axis) / math.max(half, 0.1) -- -1…1
		local t = towards and (1 - along) / 2 or (1 + along) / 2
		info.Delay = math.clamp(t, 0, 1) * span
	end
	state.Span = span
end

local function setVisible(state, visibility)
	-- visibility: 1 — виден полностью, 0 — невидим.
	local modifier = 1 - visibility
	for item in state.Visuals do
		if item.Parent then item.LocalTransparencyModifier = modifier end
	end
	local on = visibility > 0.5
	if state.FxOn ~= on then
		state.FxOn = on
		for item, original in state.Fx do
			if item.Parent then item.Enabled = on and original or false end
		end
	end
end

-- offsetFor(info) → смещение вниз (стадов, 0 = на месте).
local function place(state, offsetFor)
	local parts, frames = {}, {}
	for part, info in state.Parts do
		if part.Parent then
			local offset = offsetFor(info)
			local target = info.Base - Vector3.new(0, offset, 0)
			info.Expected = target
			table.insert(parts, part)
			table.insert(frames, target)
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

local function hideNow(state)
	state.Mode = "Hidden"
	state.Offset = state.Depth
	place(state, function() return state.Depth end)
	setVisible(state, 0)
end

local function track(model)
	if bridges[model] or not model:IsA("Model") or not model:IsDescendantOf(workspace) or not string.match(model.Name, PATTERN) then return end
	-- Модель внутри другого моста ("BridgeRail" в "Bridge") едет вместе с ним.
	local parent = model.Parent
	while parent and parent ~= workspace do
		if parent:IsA("Model") and string.match(parent.Name, PATTERN) then return end
		parent = parent.Parent
	end
	local state = { Model = model, Parts = {}, Visuals = {}, Fx = {}, Offset = 0, Mode = "Shown" }
	for _, item in model:GetDescendants() do addItem(state, item) end
	measure(state)
	bridges[model] = state
	hideNow(state)
	model.DescendantAdded:Connect(function(item)
		-- Догрузились части (StreamingEnabled) — сразу в текущее состояние.
		addItem(state, item)
		local info = state.Parts[item]
		if info then
			info.Expected = info.Base - Vector3.new(0, state.Offset, 0)
			item.CFrame = info.Expected
		end
		if state.Visuals[item] then item.LocalTransparencyModifier = state.Mode == "Hidden" and 1 or 0 end
		if state.Fx[item] ~= nil and state.Mode == "Hidden" then item.Enabled = false end
	end)
	model.DescendantRemoving:Connect(function(item)
		state.Parts[item] = nil
		state.Visuals[item] = nil
		state.Fx[item] = nil
	end)
end

--------------------------------------------------------------------------------
-- РАССТОЯНИЕ И АНИМАЦИЯ
--------------------------------------------------------------------------------
local function distanceTo(state, position)
	if not state.Box then return math.huge end
	local localPos = state.Box:PointToObjectSpace(position)
	local half = state.Size / 2
	local clamped = Vector3.new(
		math.clamp(localPos.X, -half.X, half.X),
		math.clamp(localPos.Y, -half.Y, half.Y),
		math.clamp(localPos.Z, -half.Z, half.Z)
	)
	return (localPos - clamped).Magnitude
end

local function start(state, mode, position)
	planWave(state, position)
	state.Mode = mode
	state.Started = os.clock()
	state.FxOn = nil
end

-- Сервер сдвинул деталь (остров выезжает и т.п.) — её новая позиция = база.
local function syncFromServer(state)
	local moved = false
	for part, info in state.Parts do
		if part.Parent and (part.CFrame.Position - info.Expected.Position).Magnitude > 0.02 then
			info.Base = part.CFrame
			moved = true
		end
	end
	if moved then
		local offset = state.Offset
		place(state, function() return offset end)
		measure(state)
	end
end

local sinceCheck = 0
RunService.Heartbeat:Connect(function(dt)
	sinceCheck += dt
	local check = sinceCheck >= 0.2
	if check then sinceCheck = 0 end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local position = root and root.Position

	for model, state in bridges do
		if not model.Parent then
			bridges[model] = nil
			continue
		end
		if check then
			syncFromServer(state)
			if position and (state.Mode == "Hidden" or state.Mode == "Shown") then
				local distance = distanceTo(state, position)
				if state.Mode == "Hidden" and distance <= SHOW then
					start(state, "Rising", position)
				elseif state.Mode == "Shown" and distance >= HIDE then
					start(state, "Sinking", position)
				end
			end
		end

		if state.Mode == "Rising" then
			local elapsed = os.clock() - state.Started
			local depth = state.Depth
			place(state, function(info)
				local a = math.clamp((elapsed - info.Delay) / RISE, 0, 1)
				return depth * (1 - backOut(a))
			end)
			setVisible(state, math.clamp(elapsed / (RISE * 0.35), 0, 1))
			if elapsed >= RISE + (state.Span or 0) then
				state.Mode = "Shown"
				state.Offset = 0
				place(state, function() return 0 end)
				setVisible(state, 1)
			end
		elseif state.Mode == "Sinking" then
			local elapsed = os.clock() - state.Started
			local depth = state.Depth
			place(state, function(info)
				local a = math.clamp((elapsed - info.Delay) / SINK, 0, 1)
				return depth * backIn(a)
			end)
			local total = SINK + (state.Span or 0)
			setVisible(state, 1 - math.clamp((elapsed / total - 0.6) / 0.4, 0, 1))
			if elapsed >= total then
				hideNow(state)
			end
		end
	end
end)

--------------------------------------------------------------------------------
-- ПОИСК МОСТОВ
--------------------------------------------------------------------------------
for _, item in workspace:GetDescendants() do
	if item:IsA("Model") then track(item) end
end
workspace.DescendantAdded:Connect(function(item)
	if item:IsA("Model") then
		-- Модель могла прийти пустой (стриминг/клон) — даём детям догрузиться.
		task.defer(track, item)
	end
end)
