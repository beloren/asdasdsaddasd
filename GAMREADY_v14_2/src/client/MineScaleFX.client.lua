--------------------------------------------------------------------------------
-- MineScaleFX (LocalScript) v20.16 — анимация масштаба шахты (растяжение на
-- ударах мини-игры, «взрыв» при выбросе руды, «плевок» на каждый кусок)
-- проигрывается ЛОКАЛЬНО.
--
-- Сервер (MineService:_animateMineScale) больше не делает Model:ScaleTo
-- каждый кадр — он пишет атрибут MineScaleAnim (JSON: ключи T/S/E, тряска,
-- серверное время старта) на модель шахты с тегом MineScaleAnimated. Раньше
-- размеры и позиции ВСЕХ деталей шахты летели по сети каждый кадр, и в момент
-- выброса руды клиент подтормаживал прямо во время перелёта камеры.
--
-- Масштаб здесь — вручную по деталям (Size + CFrame вокруг точки у земли под
-- пивотом), а не Model:ScaleTo: так детали, которые сервер добавит в модель
-- посреди анимации (подмена входа), не искажаются, а по концу анимации всё
-- возвращается ровно к серверным значениям.
--------------------------------------------------------------------------------
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local TAG = "MineScaleAnimated"

local EASES = {
	OutQuad = function(a) return 1 - (1 - a) * (1 - a) end,
	InOutQuad = function(a)
		if a < 0.5 then return 2 * a * a end
		return 1 - ((-2 * a + 2) ^ 2) / 2
	end,
	OutBack = function(a)
		local c1, c3 = 1.4, 2.4
		return 1 + c3 * (a - 1) ^ 3 + c1 * (a - 1) ^ 2
	end,
}

local states = setmetatable({}, { __mode = "k" }) -- [mine] = state

local function serverNow()
	return workspace:GetServerTimeNow()
end

-- Снимок серверной (базовой) геометрии — от него считается любой масштаб.
local function capture(mine, state)
	if state.Base then
		-- Детали, которые сервер добавил в модель после снимка (подмена
		-- входа), — в снимок как есть: их серверные значения и есть база.
		for _, part in mine:GetDescendants() do
			if part:IsA("BasePart") and not state.Base[part] then
				state.Base[part] = { CFrame = part.CFrame, Size = part.Size }
			end
		end
		return
	end
	local okBox, boxCFrame, boxSize = pcall(function() return mine:GetBoundingBox() end)
	local okPivot, pivot = pcall(function() return mine:GetPivot() end)
	if not (okBox and okPivot) then return end
	state.Anchor = Vector3.new(pivot.Position.X, boxCFrame.Position.Y - boxSize.Y / 2, pivot.Position.Z)
	state.Base = {}
	for _, part in mine:GetDescendants() do
		if part:IsA("BasePart") then
			state.Base[part] = { CFrame = part.CFrame, Size = part.Size }
		end
	end
	state.K = 1
end

local function apply(state, k, shakeOffset)
	if not state.Base then return end
	local anchor = state.Anchor
	local parts, frames = {}, {}
	for part, base in state.Base do
		if part.Parent then
			part.Size = base.Size * k
			local position = anchor + (base.CFrame.Position - anchor) * k + shakeOffset
			table.insert(parts, part)
			table.insert(frames, base.CFrame.Rotation + position)
		end
	end
	workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	state.K = k
end

local function restore(state)
	if not state.Base then return end
	local parts, frames = {}, {}
	for part, base in state.Base do
		if part.Parent then
			part.Size = base.Size
			table.insert(parts, part)
			table.insert(frames, base.CFrame)
		end
	end
	workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	state.Base = nil
	state.K = 1
end

local function onAnim(mine)
	local raw = mine:GetAttribute("MineScaleAnim")
	if typeof(raw) ~= "string" then return end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or typeof(data) ~= "table" then return end
	local state = states[mine]
	if not state then
		state = { K = 1 }
		states[mine] = state
	end
	if data.Snap then
		state.Anim = nil
		restore(state)
		return
	end
	local current = tonumber(data.Current) or 1
	if current <= 0 then current = 1 end
	capture(mine, state)
	-- Ключи сервера — абсолютный масштаб модели; геометрия на сервере стоит в
	-- масштабе Current, поэтому локально это множитель S / Current.
	local keys = {}
	for _, frame in data.Keys or {} do
		table.insert(keys, { T = tonumber(frame.T) or 0, K = (tonumber(frame.S) or current) / current, Ease = EASES[frame.E] or EASES.OutQuad })
	end
	state.Anim = {
		Start = tonumber(data.Start) or serverNow(),
		From = state.K or 1,
		Keys = keys,
		Shake = tonumber(data.Shake) or 0,
		ShakeSeconds = tonumber(data.ShakeSeconds) or 0,
		Total = math.max(keys[#keys] and keys[#keys].T or 0, tonumber(data.ShakeSeconds) or 0),
	}
end

local function step()
	for mine, state in states do
		local anim = state.Anim
		if anim then
			if not mine.Parent then
				states[mine] = nil
				continue
			end
			local elapsed = math.max(0, serverNow() - anim.Start)
			local from, prevT, value = anim.From, 0, nil
			for _, frame in anim.Keys do
				if elapsed >= frame.T then
					from, prevT = frame.K, frame.T
				else
					local span = frame.T - prevT
					local a = span > 0 and math.clamp((elapsed - prevT) / span, 0, 1) or 1
					value = from + (frame.K - from) * frame.Ease(a)
					break
				end
			end
			value = value or from
			local shake = Vector3.zero
			if anim.Shake > 0 and elapsed < anim.ShakeSeconds then
				local amplitude = anim.Shake * (1 - elapsed / anim.ShakeSeconds) * value
				shake = Vector3.new((math.random() * 2 - 1) * amplitude, (math.random() * 2 - 1) * amplitude * 0.35, (math.random() * 2 - 1) * amplitude)
			end
			if elapsed >= anim.Total then
				state.Anim = nil
				if math.abs(value - 1) < 1e-3 then
					restore(state)
				else
					apply(state, value, Vector3.zero)
				end
			else
				apply(state, math.max(0.05, value), shake)
			end
		end
	end
end

local function track(mine)
	if not mine:IsA("Model") then return end
	mine:GetAttributeChangedSignal("MineScaleAnim"):Connect(function()
		onAnim(mine)
	end)
	onAnim(mine)
end

for _, mine in CollectionService:GetTagged(TAG) do track(mine) end
CollectionService:GetInstanceAddedSignal(TAG):Connect(track)
RunService.RenderStepped:Connect(step)
