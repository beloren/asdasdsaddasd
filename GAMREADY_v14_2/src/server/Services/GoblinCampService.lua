--------------------------------------------------------------------------------
-- GoblinCampService (v20.44) — ГОБЛИНСКИЙ ЛАГЕРЬ: волны, ИИ, дроп, табличка.
--
-- Настройки — Config.GoblinRaid (Waves, Ai, Flow, Marker, Kick).
-- Лагерь — Workspace/GoblinCamp: Zone (границы), Spawns/* (точки появления),
-- Marker (необязательно, точка таблички).
--
-- КАК УСТРОЕН ИИ (по советам DevForum для «нормальных» NPC):
--   • Один планировщик на всех, тики разнесены (Ai.TickSeconds на гоблина),
--     никаких Heartbeat/while-циклов на каждого NPC.
--   • Сервер владеет физикой (SetNetworkOwner(nil)) — движение не дёргается
--     от смены владельца; Humanoid:MoveTo вызывается каждый тик, поэтому
--     его 8-секундный таймаут никогда не срабатывает.
--   • Лишние состояния Humanoid выключены (см. GoblinService.createR6Placeholder),
--     гоблины не сталкиваются друг с другом (группа Goblins) и расходятся
--     сами (Ai.SeparationRadius).
--   • Конечный автомат: Wander → Chase → Windup (видимый замах) → Recover,
--     Stunned, Return (вышел за зону), Dead.
--   • Путь — ПОЛЕ НАПРАВЛЕНИЙ (flow field) по сетке лагеря: одно поле на
--     цель на всех гоблинов, пересчёт не чаще Flow.RecomputeSeconds.
--     Гоблин смотрит на несколько клеток вперёд и идёт к самой дальней
--     видимой — движение плавное, без «лесенки».
--   • Застрял (нет прогресса Ai.StuckSeconds) — прыжок и новая точка.
--   • Анимации играет клиент (GoblinAnimation.client) по атрибутам модели.
--
-- ГОБЛИНЫ ДОБИЛИ ИГРОКА — не смерть, а пинок домой (CombatService:GoblinKick).
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local GoblinStats = require(ReplicatedStorage.Shared.GoblinStats)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local Sfx = require(ReplicatedStorage.Shared.Sfx)

local GoblinCampService = {}
local Services

local CFG = Config.GoblinRaid
local AI = CFG.Ai or {}
local FLOW = CFG.Flow or {}

local goblins = {} -- [goblin] = true
local wave = nil -- текущая волна { Info, Tier, EndsAt, Damage = {[player]=n}, Total, Alive }
local nextWave = nil -- { Info, Tier, At }
local markerLabels = nil

--------------------------------------------------------------------------------
-- ЛАГЕРЬ
--------------------------------------------------------------------------------
local function campParts()
	local camp = workspace:FindFirstChild("GoblinCamp")
	local zone = camp and camp:FindFirstChild("Zone")
	if not (zone and zone:IsA("BasePart")) then return nil end
	local spawns = {}
	local folder = camp:FindFirstChild("Spawns")
	for _, point in folder and folder:GetChildren() or {} do
		if point:IsA("BasePart") then table.insert(spawns, point) end
	end
	if #spawns == 0 then table.insert(spawns, zone) end
	return zone, spawns, camp
end

local function insideZone(zone, position, margin)
	local p = zone.CFrame:PointToObjectSpace(position)
	margin = margin or 0
	return math.abs(p.X) <= zone.Size.X / 2 + margin and math.abs(p.Z) <= zone.Size.Z / 2 + margin
		and math.abs(p.Y) <= zone.Size.Y / 2 + 14
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

--------------------------------------------------------------------------------
-- ПОЛЕ НАПРАВЛЕНИЙ
--------------------------------------------------------------------------------
local grid = nil -- { Zone, Cell, NX, NZ, Height = {[idx] = y} }
local fields = {} -- [key] = { Dist, At, Cell }

local function excludeList()
	local list = {}
	local folder = workspace:FindFirstChild("Goblins")
	if folder then table.insert(list, folder) end
	local zones = workspace:FindFirstChild("GoblinZones")
	if zones then table.insert(list, zones) end
	local camp = workspace:FindFirstChild("GoblinCamp")
	if camp then
		for _, name in { "Zone", "Marker", "Spawns" } do
			local item = camp:FindFirstChild(name)
			if item then table.insert(list, item) end
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then table.insert(list, player.Character) end
	end
	return list
end

local function cellIndex(i, j)
	return j * grid.NX + i + 1
end

local function cellCenter(idx)
	local i = (idx - 1) % grid.NX
	local j = (idx - 1) // grid.NX
	local c = grid.Cell
	local lx = -grid.Zone.Size.X / 2 + (i + 0.5) * c
	local lz = -grid.Zone.Size.Z / 2 + (j + 0.5) * c
	local world = grid.Zone.CFrame:PointToWorldSpace(Vector3.new(lx, 0, lz))
	return Vector3.new(world.X, grid.Height[idx] or world.Y, world.Z)
end

local function buildGrid(zone)
	local c = math.max(2, FLOW.CellSize or 4)
	local nx = math.max(1, math.floor(zone.Size.X / c))
	local nz = math.max(1, math.floor(zone.Size.Z / c))
	grid = { Zone = zone, Cell = c, NX = nx, NZ = nz, Height = {} }
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = excludeList()
	rayParams.RespectCanCollide = true
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = excludeList()
	overlap.RespectCanCollide = true
	local clear = FLOW.ClearHeight or 5
	local topY = zone.Size.Y / 2 + 30
	local walkable = 0
	for j = 0, nz - 1 do
		for i = 0, nx - 1 do
			local lx = -zone.Size.X / 2 + (i + 0.5) * c
			local lz = -zone.Size.Z / 2 + (j + 0.5) * c
			local top = zone.CFrame:PointToWorldSpace(Vector3.new(lx, topY, lz))
			local hit = workspace:Raycast(top, Vector3.new(0, -(zone.Size.Y + 70), 0), rayParams)
			if hit and hit.Normal.Y > 0.6 and insideZone(zone, hit.Position, 0) then
				local box = CFrame.new(hit.Position + Vector3.new(0, clear / 2 + 0.7, 0))
				local blocked = workspace:GetPartBoundsInBox(box, Vector3.new(c * 0.55, clear, c * 0.55), overlap)
				if #blocked == 0 then
					grid.Height[cellIndex(i, j)] = hit.Position.Y
					walkable += 1
				end
			end
		end
	end
	if walkable == 0 then
		warn("[GoblinCampService] В GoblinCamp/Zone не найдено ни одной свободной клетки земли - гоблины будут идти напрямую.")
	end
	table.clear(fields)
end

local function cellAt(position)
	if not grid then return nil end
	local p = grid.Zone.CFrame:PointToObjectSpace(position)
	local i = math.clamp(math.floor((p.X + grid.Zone.Size.X / 2) / grid.Cell), 0, grid.NX - 1)
	local j = math.clamp(math.floor((p.Z + grid.Zone.Size.Z / 2) / grid.Cell), 0, grid.NZ - 1)
	local idx = cellIndex(i, j)
	if grid.Height[idx] then return idx end
	-- Ближайшая свободная клетка (стоит у стены/на объекте).
	for r = 1, 3 do
		local best, bestD = nil, math.huge
		for dj = -r, r do
			for di = -r, r do
				local ni, nj = i + di, j + dj
				if ni >= 0 and nj >= 0 and ni < grid.NX and nj < grid.NZ then
					local n = cellIndex(ni, nj)
					if grid.Height[n] then
						local d = di * di + dj * dj
						if d < bestD then best, bestD = n, d end
					end
				end
			end
		end
		if best then return best end
	end
	return nil
end

local NEIGHBORS = {
	{ 1, 0, 1 }, { -1, 0, 1 }, { 0, 1, 1 }, { 0, -1, 1 },
	{ 1, 1, 1.414 }, { 1, -1, 1.414 }, { -1, 1, 1.414 }, { -1, -1, 1.414 },
}

-- Можно ли шагнуть из idx в соседа (перепад высоты, без срезания углов).
local function canStep(i, j, di, dj)
	local ni, nj = i + di, j + dj
	if ni < 0 or nj < 0 or ni >= grid.NX or nj >= grid.NZ then return nil end
	local from, to = cellIndex(i, j), cellIndex(ni, nj)
	local h1, h2 = grid.Height[from], grid.Height[to]
	if not (h1 and h2) or math.abs(h1 - h2) > (FLOW.MaxStep or 3.5) then return nil end
	if di ~= 0 and dj ~= 0 then
		if not grid.Height[cellIndex(i + di, j)] or not grid.Height[cellIndex(i, j + dj)] then return nil end
	end
	return to
end

-- Дейкстра от цели по всей сетке (бинарная куча).
local function computeField(targetIdx)
	local dist = { [targetIdx] = 0 }
	local heap = { { 0, targetIdx } }
	local function push(item)
		table.insert(heap, item)
		local k = #heap
		while k > 1 do
			local parent = k // 2
			if heap[parent][1] <= heap[k][1] then break end
			heap[parent], heap[k] = heap[k], heap[parent]
			k = parent
		end
	end
	local function pop()
		local top = heap[1]
		local last = table.remove(heap)
		if #heap > 0 then
			heap[1] = last
			local k = 1
			while true do
				local l, r = k * 2, k * 2 + 1
				local m = k
				if heap[l] and heap[l][1] < heap[m][1] then m = l end
				if heap[r] and heap[r][1] < heap[m][1] then m = r end
				if m == k then break end
				heap[m], heap[k] = heap[k], heap[m]
				k = m
			end
		end
		return top
	end
	while #heap > 0 do
		local item = pop()
		local d, idx = item[1], item[2]
		if d <= (dist[idx] or math.huge) then
			local i, j = (idx - 1) % grid.NX, (idx - 1) // grid.NX
			for _, n in NEIGHBORS do
				local to = canStep(i, j, n[1], n[2])
				if to then
					local nd = d + n[3]
					if nd < (dist[to] or math.huge) then
						dist[to] = nd
						push({ nd, to })
					end
				end
			end
		end
	end
	return dist
end

local function fieldFor(key, targetIdx, now, static)
	local entry = fields[key]
	if entry and entry.Cell == targetIdx then return entry.Dist end
	if entry and not static and now - entry.At < (FLOW.RecomputeSeconds or 0.35) then return entry.Dist end
	local dist = computeField(targetIdx)
	fields[key] = { Dist = dist, At = now, Cell = targetIdx }
	return dist
end

-- Прямая по сетке без препятствий (для «срезания» и выбора точки прогулки).
local function gridLineClear(fromIdx, toIdx)
	local x0, z0 = (fromIdx - 1) % grid.NX, (fromIdx - 1) // grid.NX
	local x1, z1 = (toIdx - 1) % grid.NX, (toIdx - 1) // grid.NX
	local steps = math.max(math.abs(x1 - x0), math.abs(z1 - z0))
	if steps == 0 then return true end
	for s = 1, steps do
		local x = math.floor(x0 + (x1 - x0) * s / steps + 0.5)
		local z = math.floor(z0 + (z1 - z0) * s / steps + 0.5)
		if not grid.Height[cellIndex(x, z)] then return false end
	end
	return true
end

-- Следующая точка по полю: до 4 клеток вперёд, самая дальняя видимая.
local function nextPointOnField(dist, fromIdx)
	local current = fromIdx
	local best = nil
	for _ = 1, 4 do
		local i, j = (current - 1) % grid.NX, (current - 1) // grid.NX
		local nextIdx, nextD = nil, dist[current] or math.huge
		for _, n in NEIGHBORS do
			local to = canStep(i, j, n[1], n[2])
			if to and (dist[to] or math.huge) < nextD then nextIdx, nextD = to, dist[to] end
		end
		if not nextIdx then break end
		if gridLineClear(fromIdx, nextIdx) then best = nextIdx else break end
		current = nextIdx
	end
	return best and cellCenter(best) or nil
end

--------------------------------------------------------------------------------
-- ГОБЛИН
--------------------------------------------------------------------------------
local function setAttr(goblin, name, value)
	if goblin.Model.Parent and goblin.Model:GetAttribute(name) ~= value then
		goblin.Model:SetAttribute(name, value)
	end
end

local function bump(goblin, name)
	setAttr(goblin, name, (goblin.Model:GetAttribute(name) or 0) + 1)
end

local function moveTo(goblin, point, running)
	local humanoid = goblin.Humanoid
	local speed = goblin.WalkSpeed * (running and (AI.RunSpeedMult or 1.35) or 1)
	if math.abs(humanoid.WalkSpeed - speed) > 0.05 then humanoid.WalkSpeed = speed end
	-- Расходимся с соседями.
	local root = goblin.Root
	local push = Vector3.zero
	local radius = AI.SeparationRadius or 3.2
	for other in goblins do
		if other ~= goblin and not other.Dead and other.Root then
			local offset = flat(root.Position - other.Root.Position)
			local d = offset.Magnitude
			if d > 0.05 and d < radius then push += offset.Unit * (radius - d) end
		end
	end
	local target = point + push * 0.8
	if grid then
		-- Точка после расхождения должна остаться в лагере.
		local p = grid.Zone.CFrame:PointToObjectSpace(target)
		local hx, hz = grid.Zone.Size.X / 2 - 1.5, grid.Zone.Size.Z / 2 - 1.5
		target = grid.Zone.CFrame:PointToWorldSpace(Vector3.new(math.clamp(p.X, -hx, hx), p.Y, math.clamp(p.Z, -hz, hz)))
	end
	humanoid:MoveTo(target)
	goblin.MoveGoal = target
	setAttr(goblin, "GoblinMoving", true)
	setAttr(goblin, "GoblinRunning", running == true)
end

local function stop(goblin)
	goblin.Humanoid:MoveTo(goblin.Root.Position)
	goblin.MoveGoal = nil
	setAttr(goblin, "GoblinMoving", false)
	setAttr(goblin, "GoblinRunning", false)
end

local function faceTowards(goblin, position)
	local root = goblin.Root
	local look = Vector3.new(position.X, root.Position.Y, position.Z)
	if (look - root.Position).Magnitude > 0.05 then
		root.CFrame = CFrame.lookAt(root.Position, look)
	end
end

-- Идти к точке: напрямую, если видно, иначе по полю.
local function travel(goblin, key, destination, now, running, static)
	local root = goblin.Root
	if not grid then moveTo(goblin, destination, running) return end
	local fromIdx, toIdx = cellAt(root.Position), cellAt(destination)
	if not (fromIdx and toIdx) then moveTo(goblin, destination, running) return end
	if fromIdx == toIdx or gridLineClear(fromIdx, toIdx) then
		moveTo(goblin, destination, running)
		return
	end
	local dist = fieldFor(key, toIdx, now, static)
	local point = nextPointOnField(dist, fromIdx)
	moveTo(goblin, point or destination, running)
end

local function validTarget(player, zone)
	if not (player and player.Parent) then return nil end
	if player:GetAttribute("Protected") == true or player:GetAttribute("GoblinKicked") == true then return nil end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (hrp and humanoid and humanoid.Health > 0) then return nil end
	if not insideZone(zone, hrp.Position, 0) then return nil end
	return hrp, humanoid
end

local function pickTarget(goblin, zone)
	local root = goblin.Root
	local current = goblin.Target
	if current then
		local hrp = validTarget(current, zone)
		if hrp and flat(hrp.Position - root.Position).Magnitude <= (AI.DeaggroRadius or 40) then
			return current, hrp
		end
		goblin.Target = nil
	end
	local best, bestHrp, bestD = nil, nil, AI.AggroRadius or 28
	for _, player in Players:GetPlayers() do
		local hrp = validTarget(player, zone)
		if hrp then
			local d = flat(hrp.Position - root.Position).Magnitude
			if d < bestD then best, bestHrp, bestD = player, hrp, d end
		end
	end
	goblin.Target = best
	return best, bestHrp
end

local function cancelAttack(goblin)
	goblin.AttackToken = (goblin.AttackToken or 0) + 1
	if goblin.Attacking then
		goblin.Attacking = false
		goblin.Humanoid.AutoRotate = true
		setAttr(goblin, "GoblinAttacking", false)
	end
end

local function startAttack(goblin, player, hrp, now)
	goblin.Attacking = true
	goblin.AttackToken = (goblin.AttackToken or 0) + 1
	local token = goblin.AttackToken
	goblin.NextAttackAt = now + (AI.AttackCooldown or 1.6)
	stop(goblin)
	goblin.Humanoid.AutoRotate = false
	faceTowards(goblin, hrp.Position)
	setAttr(goblin, "GoblinAttacking", true)
	bump(goblin, "GoblinAttackSequence")
	Sfx.play("GoblinAttack", goblin.Model)
	local windup = AI.AttackWindup or 0.55
	task.delay(windup, function()
		if goblin.Dead or goblin.AttackToken ~= token or not goblin.Root.Parent then return end
		local character = player.Character
		local targetRoot = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if targetRoot and humanoid and humanoid.Health > 0
			and player:GetAttribute("Protected") ~= true and player:GetAttribute("GoblinKicked") ~= true
			and flat(targetRoot.Position - goblin.Root.Position).Magnitude <= (AI.HitRange or 7) then
			local damage = GoblinStats.Damage(goblin.Type, goblin.MineTier) * (goblin.DamageMultiplier or 1)
			Sfx.play("GoblinAttackHit", targetRoot)
			if humanoid.Health - damage <= 1 then
				-- ДОБИЛИ — пинок домой вместо смерти.
				humanoid.Health = math.max(1, humanoid.Health)
				goblin.Target = nil
				if Services.CombatService and Services.CombatService.GoblinKick then
					pcall(Services.CombatService.GoblinKick, Services.CombatService, player, goblin.Root.Position)
				end
			else
				humanoid:TakeDamage(damage)
			end
		end
	end)
	task.delay(windup + 0.35, function()
		if goblin.AttackToken ~= token or goblin.Dead then return end
		goblin.Attacking = false
		if goblin.Humanoid.Parent then goblin.Humanoid.AutoRotate = true end
		setAttr(goblin, "GoblinAttacking", false)
	end)
end

local function pickWanderPoint(goblin)
	if not grid then
		local angle = math.random() * math.pi * 2
		return goblin.Home + Vector3.new(math.cos(angle), 0, math.sin(angle)) * math.random() * (AI.WanderRadius or 16)
	end
	local fromIdx = cellAt(goblin.Root.Position)
	for _ = 1, 8 do
		local angle = math.random() * math.pi * 2
		local r = (0.3 + math.random() * 0.7) * (AI.WanderRadius or 16)
		local point = goblin.Home + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
		if insideZone(grid.Zone, point, -2) then
			local idx = cellAt(point)
			if idx and fromIdx and gridLineClear(fromIdx, idx) then return cellCenter(idx) end
		end
	end
	return nil
end

-- Застревание: цель есть, а расстояние до неё не сокращается.
local function checkStuck(goblin, now)
	local goal = goblin.MoveGoal
	if not goal then goblin.StuckSince = nil return end
	local d = flat(goal - goblin.Root.Position).Magnitude
	if d < 1.5 then goblin.StuckSince = nil return end
	if goblin.LastGoalDist and d < goblin.LastGoalDist - 0.25 then
		goblin.StuckSince = nil
	elseif not goblin.StuckSince then
		goblin.StuckSince = now
	elseif now - goblin.StuckSince > (AI.StuckSeconds or 1.6) then
		goblin.StuckSince = nil
		goblin.Humanoid.Jump = true
		goblin.WanderPoint = nil
		goblin.StuckCount = (goblin.StuckCount or 0) + 1
		if goblin.StuckCount >= 3 and grid then
			-- Совсем застрял — ставим на ближайшую свободную клетку.
			local idx = cellAt(goblin.Root.Position)
			if idx then goblin.Model:PivotTo(CFrame.new(cellCenter(idx) + Vector3.new(0, 3, 0))) end
			goblin.StuckCount = 0
		end
	end
	goblin.LastGoalDist = d
end

local function think(goblin, zone, now)
	local root = goblin.Root
	if goblin.Dead or not root.Parent then return end
	if now < (goblin.StunnedUntil or 0) then
		stop(goblin)
		return
	end
	if goblin.Model:GetAttribute("GoblinStunned") then setAttr(goblin, "GoblinStunned", false) end
	if goblin.Attacking then return end
	checkStuck(goblin, now)

	-- Выбросило из лагеря — домой.
	if not insideZone(zone, root.Position, 3) then
		goblin.Target = nil
		travel(goblin, "home" .. tostring(goblin.HomeCell), goblin.Home, now, true, true)
		return
	end

	local player, hrp = pickTarget(goblin, zone)
	if player and hrp then
		goblin.WanderPoint = nil
		local d = flat(hrp.Position - root.Position).Magnitude
		if d <= (AI.AttackRange or 5) then
			if now >= (goblin.NextAttackAt or 0) then
				startAttack(goblin, player, hrp, now)
			else
				-- Кулдаун: держим дистанцию, смотрим на цель.
				stop(goblin)
				faceTowards(goblin, hrp.Position)
			end
		else
			travel(goblin, "p" .. player.UserId, hrp.Position, now, true, false)
		end
		return
	end

	-- Никого — прогулка вокруг своей точки с паузами.
	if goblin.WanderPoint and flat(goblin.WanderPoint - root.Position).Magnitude > 2.5 and now < (goblin.WanderUntil or 0) then
		moveTo(goblin, goblin.WanderPoint, false)
		return
	end
	if goblin.WanderPoint then
		goblin.WanderPoint = nil
		local pause = AI.WanderPause or { 1.5, 4 }
		goblin.PauseUntil = now + pause[1] + math.random() * (pause[2] - pause[1])
		stop(goblin)
		return
	end
	if now < (goblin.PauseUntil or 0) then
		if goblin.MoveGoal then stop(goblin) end
		return
	end
	goblin.WanderPoint = pickWanderPoint(goblin)
	goblin.WanderUntil = now + 8
	if goblin.WanderPoint then moveTo(goblin, goblin.WanderPoint, false) end
end

--------------------------------------------------------------------------------
-- НАГРАДЫ
--------------------------------------------------------------------------------
local function caveOf(player)
	return math.clamp(math.floor(tonumber(player:GetAttribute("MineTier")) or 1), 1, #Config.MineTiers)
end

local function rewardKill(goblin)
	local player = goblin.LastAttacker
	if not (player and player.Parent and wave) then return end
	local drops = wave.Info.Drops or {}
	local perKill = drops.PerKill or {}
	local position = goblin.Root.Position
	local tiers = Services.DataService:GetTiers(player)
	local carts = perKill.MoneyCarts or { 0.1, 0.3 }
	local fraction = carts[1] + math.random() * (carts[2] - carts[1])
	local isBoss = goblin.Type == "King" or goblin.Type == "Golden"
	local mult = isBoss and (drops.BossMoneyMult or 5) or 1
	local amount = math.max(1, math.floor(Config.CartValue(tiers.Mine, tiers.Cart) * fraction * mult))
	Services.DataService:AddMoney(player, amount, position, true)
	if Services.BankService and Services.BankService.SpawnCoinBurst then
		pcall(Services.BankService.SpawnCoinBurst, Services.BankService, player, position, isBoss and 6 or 2)
	end
	if Services.GearService and math.random() < (perKill.Dynamite or 0) then
		pcall(Services.GearService.AddGear, Services.GearService, player, "Dynamite", 1)
	end
	if Services.GeodeService and math.random() < (perKill.Geode or 0) then
		local index = Config.GeodeTypeIndexForCave and Config.GeodeTypeIndexForCave(caveOf(player)) or 1
		local geodeType = Config.Geodes.Order[math.clamp(index, 1, #Config.Geodes.Order)]
		if geodeType then pcall(Services.GeodeService.AddGeodeDirectly, Services.GeodeService, player, geodeType) end
	end
	-- Книга существ: гоблин этого типа «найден».
	if Services.MutationBookService and Services.MutationBookService.RecordMobFound then
		pcall(Services.MutationBookService.RecordMobFound, Services.MutationBookService, player, goblin.Type)
	end
end

local function announceAll(text, color)
	if not Services.NotifyService then return end
	for _, player in Players:GetPlayers() do
		Services.NotifyService:Show(player, text, { Icon = "Goblin", Duration = 5, TextColor = color })
	end
end

--------------------------------------------------------------------------------
-- ВОЛНЫ
--------------------------------------------------------------------------------
local function serverCave()
	local total, count = 0, 0
	for _, player in Players:GetPlayers() do
		local mine = tonumber(player:GetAttribute("MineTier"))
		if mine then total += mine; count += 1 end
	end
	return count > 0 and total / count or 1
end

local function planWave(at)
	local cave = serverCave()
	local pool, total = {}, 0
	for _, info in CFG.Waves or {} do
		if cave >= (info.MinCave or 1) and cave <= (info.MaxCave or 99) then
			table.insert(pool, info)
			total += info.Weight or 1
		end
	end
	if #pool == 0 then pool, total = { CFG.Waves[1] }, 1 end
	local roll = math.random() * total
	local chosen = pool[1]
	for _, info in pool do
		roll -= info.Weight or 1
		if roll <= 0 then chosen = info break end
	end
	nextWave = { Info = chosen, Tier = math.clamp(math.ceil(cave * 10 / 15), 1, 10), At = at }
	workspace:SetAttribute("GoblinNextWave", chosen.Title)
end

local function removeGoblin(goblin)
	goblins[goblin] = nil
	goblin.Dead = true
	if goblin.Model.Parent then goblin.Model:Destroy() end
end

function GoblinCampService:_finishWave(cleared)
	local state = wave
	if not state then return end
	wave = nil
	workspace:SetAttribute("GoblinRaidActive", false)
	for goblin in goblins do
		if cleared then removeGoblin(goblin) else
			goblin.Dead = true
			setAttr(goblin, "GoblinDead", true)
			task.delay(0.8, function() removeGoblin(goblin) end)
		end
	end
	planWave(os.clock() + (CFG.IntervalSeconds or 300))
	if not cleared then
		announceAll("The goblins retreated into their camp.", Color3.fromRGB(200, 200, 210))
		return
	end
	local total = 0
	for _, dealt in state.Damage do total += dealt end
	local clearTable = (state.Info.Drops and state.Info.Drops.Clear) or {}
	if total > 0 and Services.GearService then
		for player, dealt in state.Damage do
			if player.Parent then
				local share = dealt / total
				for _, row in clearTable do
					if share >= row.MinShare then
						pcall(Services.GearService.GrantChest, Services.GearService, player, row.Chest, 1)
						break
					end
				end
			end
		end
	end
	announceAll(("%s defeated! Chests for everyone who fought."):format(state.Info.Title), Color3.fromRGB(120, 255, 150))
end

function GoblinCampService:_spawnGoblin(goblinType, tier, info, spawnPart, zone, folder)
	local offset = Vector3.new(math.random(-4, 4), 0, math.random(-4, 4))
	local position = spawnPart.Position + offset
	if grid then
		local idx = cellAt(position)
		if idx then position = cellCenter(idx) end
	end
	local ok, model = pcall(Services.GoblinService.CreateGoblinModel, Services.GoblinService, position + Vector3.new(0, 1, 0), tier, goblinType, zone.Position)
	if not (ok and model) then
		warn("[GoblinCampService] не удалось создать гоблина", goblinType, model)
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model.PrimaryPart
	if not (humanoid and root) then model:Destroy() return end
	local maxHealth = humanoid.MaxHealth * (info.HealthMult or 1)
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.BreakJointsOnDeath = false
	model:SetAttribute("GoblinCamp", info.Id)
	model:SetAttribute("GoblinMoving", false)
	model:SetAttribute("GoblinRunning", false)
	model:SetAttribute("GoblinAttacking", false)
	model.Parent = folder
	pcall(function() root:SetNetworkOwner(nil) end)
	local goblin = {
		Camp = true, Model = model, Humanoid = humanoid, Root = root, Type = goblinType, MineTier = tier,
		Definition = Config.Goblins.Types[goblinType], DamageMultiplier = info.DamageMult or 1,
		WalkSpeed = humanoid.WalkSpeed, Home = position, HomeCell = grid and cellAt(position) or 0,
		NextThink = os.clock() + math.random() * (AI.TickSeconds or 0.2), NextAttackAt = 0, HitCount = 0,
		Raid = true, RaidInfo = info,
	}
	goblins[goblin] = true
	humanoid.Died:Connect(function()
		if goblin.Dead then return end
		goblin.Dead = true
		cancelAttack(goblin)
		setAttr(goblin, "GoblinDead", true)
		Sfx.play("GoblinDeath", model)
		pcall(rewardKill, goblin)
		if wave then wave.Alive = math.max(0, wave.Alive - 1) end
		task.delay(1.2, function()
			removeGoblin(goblin)
			if wave and wave.Alive <= 0 then self:_finishWave(true) end
		end)
	end)
end

function GoblinCampService:StartWave()
	if wave then return end
	local zone, spawns = campParts()
	if not zone then return end
	if not grid or grid.Zone ~= zone then buildGrid(zone) end
	local plan = nextWave or { Info = CFG.Waves[1], Tier = 1 }
	nextWave = nil
	local folder = workspace:FindFirstChild("Goblins") or Instance.new("Folder")
	folder.Name = "Goblins"
	folder.Parent = workspace
	wave = { Info = plan.Info, Tier = plan.Tier, EndsAt = os.clock() + (CFG.DurationSeconds or 180), Damage = {}, Total = 0, Alive = 0 }
	workspace:SetAttribute("GoblinRaidActive", true)
	workspace:SetAttribute("GoblinRaidType", plan.Info.Title)
	local index = 0
	for _, unit in plan.Info.Units or {} do
		local goblinType, count = unit[1], unit[2] or 1
		if Config.Goblins.Types[goblinType] then
			for _ = 1, count do
				index += 1
				local spawnPart = spawns[((index - 1) % #spawns) + 1]
				self:_spawnGoblin(goblinType, plan.Tier, plan.Info, spawnPart, zone, folder)
			end
		end
	end
	for _ in goblins do wave.Alive += 1 end
	wave.Total = wave.Alive
	Sfx.play("GoblinWaveWarning", folder:FindFirstChildWhichIsA("Model"))
	announceAll(("%s attack the Goblin Camp!"):format(plan.Info.Title), plan.Info.Color)
	if Services.TutorialService then
		for _, player in Players:GetPlayers() do
			pcall(function() Services.TutorialService:ShowHint(player, "FirstGoblin") end)
		end
	end
end

--------------------------------------------------------------------------------
-- ТАБЛИЧКА НАД ЛАГЕРЕМ
--------------------------------------------------------------------------------
local function dropsText(info)
	local drops = info.Drops or {}
	local perKill = drops.PerKill or {}
	local parts = { "$ per kill" }
	if (perKill.Dynamite or 0) > 0 then table.insert(parts, ("%d%% Dynamite"):format(math.floor(perKill.Dynamite * 100 + 0.5))) end
	if (perKill.Geode or 0) > 0 then table.insert(parts, ("%d%% Geode"):format(math.floor(perKill.Geode * 100 + 0.5))) end
	local chests = {}
	for _, row in drops.Clear or {} do table.insert(chests, 1, row.Chest) end
	if #chests > 0 then table.insert(parts, "Chest: " .. table.concat(chests, "/")) end
	return table.concat(parts, "  ·  ")
end

local function formatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

local function buildMarker(zone, camp)
	local markerCfg = CFG.Marker or {}
	local anchorPart = camp:FindFirstChild("Marker")
	local anchor = Instance.new("Part")
	anchor.Name = "CampMarkerAnchor"
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	local base = (anchorPart and anchorPart:IsA("BasePart")) and anchorPart.Position or zone.Position
	anchor.Position = base + Vector3.new(0, markerCfg.Height or 22, 0)
	anchor.Parent = camp

	local gui = Instance.new("BillboardGui")
	gui.Name = "GoblinCampMarker"
	gui.Size = UDim2.fromOffset(300, 118)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = markerCfg.MaxDistance or 900
	gui.Adornee = anchor
	gui.Parent = anchor
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = gui
	local function line(order, height, color)
		local label = Instance.new("TextLabel")
		label.LayoutOrder = order
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, height, 0)
		label.TextScaled = true
		label.RichText = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = color
		label.Text = ""
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.fromRGB(20, 16, 12)
		stroke.Parent = label
		label.Parent = gui
		return label
	end
	markerLabels = {
		Title = line(1, 0.3, Color3.fromRGB(140, 230, 110)),
		Wave = line(2, 0.28, Color3.new(1, 1, 1)),
		Status = line(3, 0.22, Color3.fromRGB(255, 225, 130)),
		Drops = line(4, 0.2, Color3.fromRGB(220, 220, 220)),
	}
	markerLabels.Title.Text = "⚔ " .. (markerCfg.Title or "GOBLIN CAMP")
end

local function updateMarker(now)
	if not markerLabels then return end
	local info, statusText
	if wave then
		info = wave.Info
		statusText = ("%d/%d left  ·  %s"):format(wave.Alive, wave.Total, formatTime(wave.EndsAt - now))
	elseif nextWave then
		info = nextWave.Info
		statusText = #Players:GetPlayers() > 0 and ("Next wave in %s"):format(formatTime(nextWave.At - now)) or "Waiting for players"
	end
	if not info then return end
	local tier = wave and wave.Tier or nextWave and nextWave.Tier or 1
	markerLabels.Wave.Text = ("%s  <font color=\"#69EB82\">Lv. %d</font>"):format(info.Title, tier)
	markerLabels.Wave.TextColor3 = info.Color or Color3.new(1, 1, 1)
	markerLabels.Status.Text = statusText or ""
	markerLabels.Drops.Text = dropsText(info)
end

--------------------------------------------------------------------------------
-- ПУБЛИЧНОЕ
--------------------------------------------------------------------------------
function GoblinCampService:AllGoblins()
	return goblins
end

-- Урон от игрока (вызывает GoblinService:Damage → сюда).
function GoblinCampService:Damage(goblin, damage, attacker)
	if not goblin or goblin.Dead or not goblin.Humanoid then return 0 end
	local before = goblin.Humanoid.Health
	goblin.Humanoid:TakeDamage(damage)
	local dealt = math.max(0, before - goblin.Humanoid.Health)
	if dealt <= 0 then return 0 end
	Sfx.play("GoblinHit", goblin.Model)
	bump(goblin, "GoblinHitSequence")
	if attacker then
		goblin.LastAttacker = attacker
		if wave then wave.Damage[attacker] = (wave.Damage[attacker] or 0) + dealt end
		-- Кто бьёт — того и преследуем.
		local zone = grid and grid.Zone
		if zone and validTarget(attacker, zone) then goblin.Target = attacker end
	end
	goblin.HitCount += 1
	if goblin.HitCount % (AI.StunEveryHits or 3) == 0 and goblin.Humanoid.Health > 0 then
		cancelAttack(goblin)
		goblin.StunnedUntil = os.clock() + (AI.StunSeconds or 1.2)
		setAttr(goblin, "GoblinStunned", true)
		stop(goblin)
		if Services.GoblinService and Services.GoblinService.ShowGoblinHitVfx then
			Services.GoblinService:ShowGoblinHitVfx(goblin)
		end
	end
	return dealt
end

function GoblinCampService:IsActive()
	return wave ~= nil
end

function GoblinCampService:Init(services)
	Services = services
	if not (CFG and CFG.Enabled and CFG.UseCampService) then return end
	Players.PlayerRemoving:Connect(function(player)
		if wave then wave.Damage[player] = nil end
		fields["p" .. player.UserId] = nil
		for goblin in goblins do
			if goblin.Target == player then goblin.Target = nil end
			if goblin.LastAttacker == player then goblin.LastAttacker = nil end
		end
	end)
	task.spawn(function()
		local zone, _, camp = campParts()
		local waited = 0
		while not zone and waited < 60 do
			task.wait(5)
			waited += 5
			zone, _, camp = campParts()
		end
		if not zone then
			warn("[GoblinCampService] Workspace/GoblinCamp/Zone не найден - лагерь гоблинов выключен.")
			return
		end
		buildGrid(zone)
		buildMarker(zone, camp)
		planWave(os.clock() + (CFG.FirstWaveDelay or 90))
		local announced = false
		local lastMarker = 0
		-- ЕДИНСТВЕННЫЙ цикл: ИИ (тики разнесены), волны и табличка.
		RunService.Heartbeat:Connect(function()
			local now = os.clock()
			for goblin in goblins do
				if not goblin.Dead and now >= goblin.NextThink then
					goblin.NextThink = now + (AI.TickSeconds or 0.2)
					local ok, err = pcall(think, goblin, zone, now)
					if not ok then warn("[GoblinCampService] ИИ:", err) end
				end
			end
			if now - lastMarker >= 1 then
				lastMarker = now
				local ok, err = pcall(function()
					if wave then
						if now >= wave.EndsAt then self:_finishWave(false) end
					elseif nextWave and #Players:GetPlayers() > 0 then
						if not announced and now >= nextWave.At - (CFG.AnnounceBefore or 20) then
							announced = true
							announceAll(("%s at the Goblin Camp in %ds!"):format(nextWave.Info.Title, CFG.AnnounceBefore or 20), nextWave.Info.Color)
						end
						if now >= nextWave.At then
							announced = false
							self:StartWave()
						end
					elseif nextWave then
						-- Пусто на сервере — таймер стоит.
						nextWave.At = math.max(nextWave.At, now + 5)
					end
					updateMarker(now)
				end)
				if not ok then warn("[GoblinCampService] волна:", err) end
			end
		end)
	end)
end

-- Для админ-панели/тестов: начать волну сейчас.
function GoblinCampService:ForceWave()
	if wave then return end
	if not nextWave then planWave(os.clock()) end
	self:StartWave()
end

return GoblinCampService
