local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local states = {}

local function loadTrack(animator, id, priority, looped)
	if not animator or not id or id == 0 then return nil end
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. tostring(id)
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()
	if not ok then
		warn("[GoblinAnimation] Failed to load animation", id, track)
		return nil
	end
	track.Priority = priority
	track.Looped = looped
	return track
end

local function setLocomotion(state, moving)
	if state.Attacking then moving = false end
	local wanted = moving and state.walk or state.idle
	local other = moving and state.idle or state.walk
	if state.moving == moving and (not wanted or wanted.IsPlaying) then return end
	state.moving = moving
	if other and other.IsPlaying then other:Stop(0.12) end
	if wanted and not wanted.IsPlaying then wanted:Play(0.12, 1, 1) end
end

local function playAttack(state)
	if #state.attacks == 0 then return end
	state.attackIndex = state.attackIndex % #state.attacks + 1
	local track = state.attacks[state.attackIndex]
	track:Stop(0)
	track:Play(0.08, 1, 1)
end

-- Та же гонка репликации, что и в GoblinBillboard: на момент ChildAdded (и
-- даже на следующем кадре после task.defer) Humanoid/Animator могут ещё не
-- доехать до клиента. Раньше bindGoblin в этом случае молча выходил и
-- никогда не пробовал снова — конкретный гоблин навсегда оставался БЕЗ
-- анимаций (стоял в T-позе / скользил без ходьбы), пока соседний работал
-- нормально. Ждём появления нужных объектов вместо мгновенной сдачи.
local binding = {}
local bindGoblinTracks

local function bindGoblin(model)
	if states[model] or binding[model] then return end
	binding[model] = true
	task.spawn(function()
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			local deadline = os.clock() + 10
			repeat
				task.wait(0.1)
				humanoid = model:FindFirstChildOfClass("Humanoid")
			until humanoid or os.clock() > deadline or not model.Parent
		end
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if humanoid and not animator then
			-- Animator создаётся сервером внутри Humanoid и реплицируется
			-- отдельно от него — ждём и его, иначе LoadAnimation некуда
			-- будет вызвать.
			animator = humanoid:WaitForChild("Animator", 10)
		end
		binding[model] = nil
		if not model.Parent then return end
		if not humanoid or not animator then
			warn(("[GoblinAnimation] У модели %s нет Humanoid/Animator — анимации не привязаны."):format(model.Name))
			return
		end
		if states[model] then return end
		bindGoblinTracks(model, humanoid, animator)
	end)
end

bindGoblinTracks = function(model, humanoid, animator)
	for _, track in animator:GetPlayingAnimationTracks() do
		track:Stop(0)
	end
	local config = Config.Goblins.Animations or {}
	local state = {
		Model = model,
		Humanoid = humanoid,
		Attacking = model:GetAttribute("GoblinAttacking") == true,
		moving = false,
		attackIndex = 0,
		idle = loadTrack(animator, config.Idle, Enum.AnimationPriority.Idle, true),
		walk = loadTrack(animator, config.Walk, Enum.AnimationPriority.Movement, true),
		attacks = {},
	}
	for _, id in config.Attacks or {} do
		local track = loadTrack(animator, id, Enum.AnimationPriority.Action, false)
		if track then table.insert(state.attacks, track) end
	end
	states[model] = state

	-- ПРОИЗВОДИТЕЛЬНОСТЬ: раньше здесь висел ОТДЕЛЬНЫЙ RunService.Heartbeat
	-- на каждого гоблина. Гоблины лежат в общей папке workspace.Goblins и
	-- реплицируются ВСЕМ, а не только своему владельцу, поэтому при 8
	-- игроках у каждого клиента набиралось до 40 отдельных подписок на 60 Гц,
	-- и каждая читала AssemblyLinearVelocity и MoveDirection — свойства,
	-- которые ходят через границу Lua↔C++. Теперь состояние просто лежит в
	-- таблице states, а обходит её один общий цикл ниже (см. updateAll).
	state.Root = humanoid.RootPart or model.PrimaryPart
	state.attackChanged = model:GetAttributeChangedSignal("GoblinAttackSequence"):Connect(function()
		playAttack(state)
	end)
	state.attackingChanged = model:GetAttributeChangedSignal("GoblinAttacking"):Connect(function()
		state.Attacking = model:GetAttribute("GoblinAttacking") == true
		if state.Attacking then setLocomotion(state, false) end
	end)
	state.removed = model.AncestryChanged:Connect(function(_, parent)
		if parent then return end
		if state.attackChanged then state.attackChanged:Disconnect() end
		if state.attackingChanged then state.attackingChanged:Disconnect() end
		states[model] = nil
	end)
	setLocomotion(state, false)
end

--------------------------------------------------------------------------------
-- ЕДИНСТВЕННЫЙ цикл на всех гоблинов сразу (вместо Heartbeat на каждого).
--
-- Два независимых ограничителя нагрузки:
--   1. ЧАСТОТА. Переключение "стоит / идёт" — это выбор одного из двух
--      зацикленных треков с кроссфейдом 0.12с. Считать его 60 раз в секунду
--      бессмысленно: ~15 Гц визуально неотличимы, а работы вчетверо меньше.
--   2. ДИСТАНЦИЯ. Гоблина дальше CULL_DISTANCE не видно (билборды гаснут на
--      70 студов, сам риг на таком расстоянии — несколько пикселей), поэтому
--      его локомоцию не трогаем вообще. Анимации при этом НЕ ломаются:
--      трек продолжает играть сам по себе, мы лишь не переключаем его, а как
--      только гоблин приблизится — состояние пересчитается на первом же тике.
--------------------------------------------------------------------------------

local UPDATE_INTERVAL = 1 / 15
local CULL_DISTANCE = 120
local CULL_DISTANCE_SQ = CULL_DISTANCE * CULL_DISTANCE

local accumulated = 0

RunService.Heartbeat:Connect(function(dt)
	accumulated += dt
	if accumulated < UPDATE_INTERVAL then return end
	accumulated = 0

	local camera = workspace.CurrentCamera
	local origin = camera and camera.CFrame.Position

	for model, state in states do
		if model.Parent then
			if state.Attacking then
				-- Атака важнее любого culling'а: замах должен погасить
				-- ходьбу немедленно, иначе руки поедут поверх удара.
				setLocomotion(state, false)
			else
				local root = state.Root
				if not root or not root.Parent then
					root = state.Humanoid.RootPart or model.PrimaryPart
					state.Root = root
				end
				if root then
					local skip = false
					if origin then
						local offset = root.Position - origin
						skip = offset:Dot(offset) > CULL_DISTANCE_SQ
					end
					if not skip then
						local velocity = root.AssemblyLinearVelocity
						local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
						local serverMoving = model:GetAttribute("GoblinMoving") == true
						local hasMoveIntent = state.Humanoid.MoveDirection.Magnitude > 0.01
						-- Сервер публикует намерение двигаться сразу же, как
						-- только выдаёт MoveTo, поэтому анимация не ждёт,
						-- пока доедет реплицированная скорость.
						setLocomotion(state, serverMoving or hasMoveIntent or horizontalSpeed > 0.5)
					end
				end
			end
		end
	end
end)

local function watchFolder(folder)
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then bindGoblin(child) end
	end
	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			task.defer(bindGoblin, child)
		end
	end)
end

local folder = workspace:FindFirstChild("Goblins")
if folder then watchFolder(folder) end
workspace.ChildAdded:Connect(function(child)
	if child.Name == "Goblins" and child:IsA("Folder") then watchFolder(child) end
end)
