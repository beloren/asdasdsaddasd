local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldUi = require(ReplicatedStorage.Shared.WorldUi) -- v20: стили мировых надписей (StarterGui/WorldUiTemplates)
local CrystalUtil = require(ReplicatedStorage.Shared.CrystalUtil)
local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)
local Sfx = require(ReplicatedStorage.Shared.Sfx)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
-- ЕДИНСТВЕННЫЙ источник формул HP/урона/замедления гоблина. Раньше они были
-- здесь, а энциклопедия (CollectionMenu.client.lua) считала свои — и они
-- разошлись: книга показывала ровно половину настоящего HP и ~53% урона.
local GoblinStats = require(ReplicatedStorage.Shared.GoblinStats)

local GoblinService = {}
local Services
local active = {} -- [player] = {Goblins = {}, TutorialSpawned = bool}
-- v8: гоблинский рейд (см. блок «ГОБЛИНСКИЙ РЕЙД» ниже).
local raidGoblins = {} -- [goblin] = true
local raidState = nil -- { Type, Damage = {[player]=n}, EndsAt, Boss }
local GOBLIN_COLLISION_GROUP = "Goblins"
-- chaseTo объявлена заранее: она определена ниже, но нужна уже в
-- _finishObjective (доставка тележки/руды строится по маршруту, а не по
-- прямой) — см. комментарий там.
local chaseTo

local GOBLIN_TIER_RARITIES = {
	"Common", "Uncommon", "Rare", "Rare", "Epic",
	"Epic", "Legendary", "Legendary", "Mythic", "Mythic",
}

local function getTierColor(tier)
	local rarity = GOBLIN_TIER_RARITIES[math.clamp(tier, 1, #GOBLIN_TIER_RARITIES)]
	return Config.RarityColors[rarity] or Color3.new(1, 1, 1)
end

-- [userId] = bool — результат проверки на сессию. Нужен, потому что
-- GetRankInGroup ниже — настоящий сетевой запрос: он йилдит и умеет падать
-- при троттлинге. Раньше он вызывался напрямую, без pcall, прямо в
-- OnServerInvoke и в обработчике GoblinAdminRequest — при сбое сети инвок
-- падал с ошибкой у клиента, а не просто возвращал false. Права админа за
-- сессию не меняются, так что кэш здесь безопасен и заодно убирает лишние
-- запросы при каждом клике по панели.
local goblinAdminCache = {}

local function isGoblinAdmin(player)
	if RunService:IsStudio() or player.UserId == game.CreatorId then return true end
	local configured = Config.Goblins.AdminUserIds
	if configured and configured[player.UserId] then return true end
	if game.CreatorType ~= Enum.CreatorType.Group then return false end

	local cached = goblinAdminCache[player.UserId]
	if cached ~= nil then return cached end
	local ok, rank = pcall(function() return player:GetRankInGroup(game.CreatorId) end)
	if not ok then
		return false -- НЕ кэшируем сбой: следующая попытка переспросит заново
	end
	local isAdmin = (tonumber(rank) or 0) >= 255
	goblinAdminCache[player.UserId] = isAdmin
	return isAdmin
end

local function faceGoblinTarget(goblin, targetRoot)
	local root = goblin.Model and goblin.Model.PrimaryPart
	if not root or not targetRoot or not targetRoot.Parent then return end
	local target = targetRoot.Position
	local lookAt = Vector3.new(target.X, root.Position.Y, target.Z)
	if (lookAt - root.Position).Magnitude > 0.01 then
		root.CFrame = CFrame.lookAt(root.Position, lookAt)
	end
end

-- ОПТИМИЗАЦИЯ: раньше КАЖДЫЙ оглушённый и КАЖДЫЙ атакующий гоблин заводил
-- СВОЁ СОБСТВЕННОЕ RunService.Heartbeat:Connect (см. историю — было по
-- одному подключению на гоблина на каждое из двух состояний). При большой
-- волне, где сразу несколько гоблинов оглушены/атакуют одновременно, это
-- N независимых подписок на Heartbeat, каждая — отдельный переход
-- C++/Lua на каждый кадр. Теперь ОДНО общее подключение на весь сервис,
-- которое проходит по двум таблицам активных гоблинов — тот же визуальный
-- результат (дрожь при оглушении, разворот лицом к цели при атаке), но
-- без роста числа подписок вместе с размером волны.
local stunnedGoblins = {} -- [goblin] = basePivot (CFrame ДО оглушения — дрожь считается от него)
local attackFacingGoblins = {} -- [goblin] = targetRoot
local sharedEffectsConnection = nil

local function ensureSharedEffectsLoop()
	if sharedEffectsConnection then return end
	sharedEffectsConnection = RunService.Heartbeat:Connect(function()
		for goblin, basePivot in stunnedGoblins do
			if goblin.Dead or not goblin.Model.Parent then
				stunnedGoblins[goblin] = nil
			else
				local humanoid = goblin.Humanoid
				local root = goblin.Model.PrimaryPart
				local remaining = (goblin.StunnedUntil or 0) - os.clock()
				if remaining <= 0 then
					goblin.Model:PivotTo(basePivot)
					if humanoid then
						humanoid.WalkSpeed = goblin.BaseWalkSpeed or Config.Goblins.BaseWalkSpeed
						humanoid:Move(Vector3.zero)
					end
					if root then root.AssemblyLinearVelocity = Vector3.zero end
					goblin.Model:SetAttribute("GoblinStunned", false)
					stunnedGoblins[goblin] = nil
				else
					local elapsed = Config.Goblins.HitStunDuration - remaining
					local fade = math.clamp(remaining / Config.Goblins.HitStunDuration, 0, 1)
					local shake = math.sin(elapsed * 34) * math.rad(4.5) * fade
					local offset = math.sin(elapsed * 42) * 0.06 * fade
					if humanoid then humanoid:Move(Vector3.zero) end
					if root then root.AssemblyLinearVelocity = Vector3.zero end
					goblin.Model:PivotTo(basePivot * CFrame.new(offset, 0, 0) * CFrame.Angles(0, 0, shake))
				end
			end
		end
		for goblin, targetRoot in attackFacingGoblins do
			if goblin.Attacking and goblin.Model.Parent then
				faceGoblinTarget(goblin, targetRoot)
			else
				attackFacingGoblins[goblin] = nil
			end
		end
		-- Пусто в обеих таблицах — прямо сейчас не оглушён и не атакует ни
		-- один гоблин на всём сервере — можно спокойно отключить общий
		-- Heartbeat до следующего раза, а не крутить его вхолостую.
		if not (next(stunnedGoblins) or next(attackFacingGoblins)) then
			sharedEffectsConnection:Disconnect()
			sharedEffectsConnection = nil
		end
	end)
end

local function showGoblinHitVfx(goblin)
	local model = goblin.Model
	local head = model and model:FindFirstChild("Head")
	if not model or not head or not head:IsA("BasePart") then return end

	local highlight = goblin.HitHighlight
	if not highlight or not highlight.Parent then
		highlight = Instance.new("Highlight")
		highlight.Name = "GoblinHitHighlight"
		highlight.Adornee = model
		highlight.FillTransparency = 1
		highlight.OutlineColor = Color3.fromRGB(255, 45, 45)
		highlight.OutlineTransparency = 0
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Parent = model
		goblin.HitHighlight = highlight
	end
	highlight.Enabled = true
	goblin.HitHighlightToken = (goblin.HitHighlightToken or 0) + 1
	local highlightToken = goblin.HitHighlightToken
	task.delay(Config.Goblins.HitStunDuration, function()
		if goblin.HitHighlightToken == highlightToken and highlight.Parent then
			highlight.Enabled = false
		end
	end)

	local source = ReplicatedStorage:FindFirstChild("stunvfx")
	if source and source:IsA("Attachment") then
		local vfx = source:Clone()
		-- GoblinBillboard uses head.Size.Y * 0.5 + 0.5. Keep the stun VFX
		-- clearly above the name/HP instead of hiding it behind the billboard.
		vfx.Position = Vector3.new(0, head.Size.Y * 0.5 + 1.8, 0)
		-- ПОВОРОТ НА 90° — по прямому запросу: эффект был горизонтальным,
		-- должен быть вертикальным. Крутим сам Attachment (не трогаем
		-- исходный ассет в ReplicatedStorage) — поворот вокруг Z (крен),
		-- самый частый случай для "плоский/широкий эффект должен стать
		-- высоким". Если ось не та — поменяй 0, 0, 90 на 90, 0, 0 (вокруг X)
		-- или 0, 90, 0 (вокруг Y) здесь же.
		vfx.Orientation = Vector3.new(0, 0, 90)
		vfx.Parent = head
		for _, descendant in vfx:GetDescendants() do
			if descendant:IsA("ParticleEmitter") then
				descendant.Enabled = true
			end
		end
		Debris:AddItem(vfx, Config.Goblins.HitStunDuration)
	end
end

local function applyGoblinStun(goblin)
	if goblin.Dead or not goblin.Model.Parent then return end
	local humanoid = goblin.Humanoid
	local root = goblin.Model.PrimaryPart
	if not humanoid or not root then return end

	showGoblinHitVfx(goblin)
	goblin.StunnedUntil = os.clock() + Config.Goblins.HitStunDuration
	goblin.Model:SetAttribute("GoblinStunned", true)
	humanoid:Move(Vector3.zero)
	humanoid.WalkSpeed = 0
	root.AssemblyLinearVelocity = Vector3.zero

	if stunnedGoblins[goblin] then return end -- уже дрожит — просто продлили StunnedUntil выше, не нужен новый basePivot
	stunnedGoblins[goblin] = goblin.Model:GetPivot()
	ensureSharedEffectsLoop()
end

-- Сколько отступать назад после удара. Раньше целью отступления был самый
-- дальний из 4 фиксированных углов ВОКРУГ ZoneCenter (точки спавна) — если
-- бой шёл далеко от ZoneCenter (а погоня/предыдущее отступление почти
-- всегда его туда и уводит), гоблин срывался в забег через полкарты в одну
-- и ту же сторону, а не в короткий "отскок" от игрока. Из-за этого весь
-- цикл "удар -> отступление -> возврат" выглядел как бесконечное хождение
-- туда-сюда без повторных ударов.
local GOBLIN_RETREAT_HOP_DISTANCE = 7

local function finishGoblinAttack(goblin)
	if not goblin.Attacking then return end
	goblin.Attacking = false
	goblin.Model:SetAttribute("GoblinAttacking", false)
	attackFacingGoblins[goblin] = nil
	goblin.Humanoid.AutoRotate = true
	if goblin.AttackTargetRoot and goblin.AttackTargetRoot.Parent then
		local root = goblin.Model.PrimaryPart
		local targetPosition = goblin.AttackTargetRoot.Position
		local awayDirection = Vector3.new(root.Position.X - targetPosition.X, 0, root.Position.Z - targetPosition.Z)
		if awayDirection.Magnitude < 0.1 then
			-- Игрок и гоблин ровно друг на друге (редкий случай) — отходим в
			-- сторону, зависящую от слота построения, а не в одну и ту же
			-- жёстко зашитую сторону для всех гоблинов разом.
			local angle = goblin.FormationAngle or 0
			awayDirection = Vector3.new(math.cos(angle), 0, math.sin(angle))
		end
		awayDirection = awayDirection.Unit
		goblin.RetreatTarget = Vector3.new(root.Position.X, targetPosition.Y, root.Position.Z)
			+ awayDirection * GOBLIN_RETREAT_HOP_DISTANCE
		goblin.RetreatUntil = os.clock() + Config.Goblins.StealCooldown
	end
	goblin.AttackTargetRoot = nil
end

local function beginGoblinAttack(goblin, targetHumanoid, targetRoot)
	if goblin.Attacking or not targetHumanoid or not targetRoot then return false end
	goblin.Attacking = true
	goblin.AttackTargetRoot = targetRoot
	goblin.Humanoid.AutoRotate = false
	goblin.Humanoid:Move(Vector3.zero)
	goblin.Model:SetAttribute("GoblinAttacking", true)
	goblin.Model:SetAttribute("GoblinAttackSequence", (goblin.Model:GetAttribute("GoblinAttackSequence") or 0) + 1)
	Sfx.play("GoblinAttack", goblin.Model)
	faceGoblinTarget(goblin, targetRoot)
	attackFacingGoblins[goblin] = targetRoot
	ensureSharedEffectsLoop()
	local windup = Config.Goblins.AttackWindup
	local holdDuration = math.max(windup + 0.2, 0.7)
	task.delay(windup, function()
		local root = goblin.Model and goblin.Model.PrimaryPart
		if goblin.Dead or not goblin.Attacking or not root or not targetHumanoid.Parent
			or not targetRoot.Parent or targetRoot.Parent ~= targetHumanoid.Parent
			or (root.Position - targetRoot.Position).Magnitude > Config.Goblins.PlayerAttackRadius + 1 then return end
		-- ЩИТ: если игрок успел получить/продлить защиту уже ПОСЛЕ начала
		-- замаха (окно между beginGoblinAttack и этим task.delay), удар не
		-- должен долетать — проверяем ещё раз прямо здесь, а не только один
		-- раз при выборе цели (см. основной цикл ниже). "Protected" — тот же
		-- атрибут, что CombatService уже использует для PvP-защиты.
		local targetCharacter = targetRoot.Parent
		local targetPlayer = targetCharacter and Players:GetPlayerFromCharacter(targetCharacter)
		if targetPlayer and targetPlayer:GetAttribute("Protected") == true then return end
		if targetHumanoid.Health > 0 then
			local damage = GoblinStats.Damage(goblin.Type, goblin.MineTier) * (goblin.DamageMultiplier or 1)
			targetHumanoid:TakeDamage(damage)
			Sfx.play("GoblinAttackHit", targetRoot)
		end
	end)
	task.delay(holdDuration, function()
		if goblin.Dead or not goblin.Model.Parent then return end
		finishGoblinAttack(goblin)
	end)
	return true
end

--------------------------------------------------------------------------------
-- НАВИГАЦИЯ ГОБЛИНОВ — ПЕРЕПИСАНО ЦЕЛИКОМ.
--
-- ЧТО БЫЛО НЕ ТАК (корень ВСЕХ жалоб «ходят на месте туда-сюда» и «взяли
-- тележку и не знают, куда идти дальше»).
--
-- Смещение строя (separatedTarget) применялось к КАЖДОЙ точке, к которой
-- гоблин шёл — включая ПРОМЕЖУТОЧНЫЕ узлы маршрута и углы патруля. А
-- проверка «дошёл ли я» считалась до ЧИСТОЙ точки, без смещения. При волне
-- из двух и более гоблинов FormationRadius равен 2.6–4.5 студа, а порог
-- «узел пройден» — 2.5 студа. То есть гоблин рулил в точку, отстоящую от
-- узла на 3-4 студа вбок, честно её достигал, останавливался — и никогда
-- не оказывался ближе 2.5 студов от самого узла. Индекс узла не
-- увеличивался НИКОГДА.
--
-- Дальше всё складывалось в наблюдаемую картину:
--   • Гоблин с тележкой замирал на первом же узле дороги к банку и стоял
--     там вечно: маршрут есть, цель есть, а следующий узел недостижим по
--     построению. Со стороны — «украл тележку и не знает, куда идти».
--   • Детектор застревания не спасал: он считал застреванием только
--     случай «команда идти есть, а гоблин не двигается». Здесь же гоблин
--     «дошёл» — команда движения снималась сама, ChaseStuckFor обнулялся,
--     и аварийный пересчёт не запускался никогда.
--   • В патруле то же самое с углами квадрата: гоблин доходил до
--     смещённой точки, вставал, ждал таймер, брал новый случайный угол —
--     отсюда дёрганое «шаг вперёд, стоп, шаг в сторону».
--
-- Симптом лечили точечно и раньше (см. ветку отступления в _tickGoblin —
-- там порог сравнивают уже со смещённой точкой), но причину — общую для
-- всех веток — не трогали.
--
-- КАК СТАЛО.
--
--   1. Смещение строя применяется ТОЛЬКО к КОНЕЧНОЙ цели (игрок, тележка,
--      шахта, банк) и только когда гоблин уже на финальном отрезке. Узлы
--      маршрута и углы патруля — общая дорога, расходиться на ней незачем.
--   2. «Дошёл ли я» ВСЕГДА меряется до той же точки, к которой гоблин
--      реально рулит. Рассогласование, породившее баг, теперь невозможно
--      по построению.
--   3. Один примитив движения (steerTowards) на все ветки вместо смеси
--      Humanoid:MoveTo и Humanoid:Move. MoveTo держит собственную цель и
--      свой восьмисекундный таймаут, Move — нет; переключение между ними
--      на каждом тике и давало часть дрожания.
--   4. Застревание определяется по ОТСУТСТВИЮ ПРОГРЕССА К ЦЕЛИ, а не по
--      «стою на месте». Гоблин, который бодро кружит вокруг препятствия,
--      теперь тоже считается застрявшим и получает новый маршрут.
--   5. За тик проходится СКОЛЬКО УГОДНО уже пройденных узлов, а не один.
--      На спуске/спринте гоблин мог проскочить два узла за тик и потом
--      возвращаться к пропущенному — ещё один источник «туда-сюда».
--
-- ЧТО СТАЛО ДЕШЕВЛЕ (сервер):
--   • RaycastParams создавался ЗАНОВО на каждый рейкаст (2 на тик на
--     гоблина). Теперь один переиспользуемый объект на сервис.
--   • Рейкасты вперёд делались КАЖДЫЙ тик. Теперь только когда прогресс к
--     цели плохой — то есть когда впереди реально что-то мешает. На
--     свободной дороге это ноль рейкастов вместо двух.
--   • Path создавался и уничтожался на каждый пересчёт. Теперь один объект
--     на гоблина переиспользуется через ComputeAsync.
--   • Мёртвый код: continueWander читал goblin.WanderWaypoints, которые
--     НИКОГДА и НИГДЕ не заполнялись — функция вызывалась каждый холостой
--     тик и сразу выходила. Удалена.
--------------------------------------------------------------------------------

-- Один переиспользуемый объект на весь сервис вместо RaycastParams.new()
-- на каждый рейкаст. FilterDescendantsInstances переприсваивается перед
-- каждым использованием — это дешевле, чем аллокация нового объекта.
local goblinRayParams = RaycastParams.new()
goblinRayParams.FilterType = Enum.RaycastFilterType.Exclude

local function obstacleRayParams(goblin)
	goblinRayParams.FilterDescendantsInstances = {
		goblin.Model,
		workspace:FindFirstChild("Goblins"),
	}
	return goblinRayParams
end

-- Смещение слота в строю. ТОЛЬКО для конечных целей — см. шапку блока.
-- Слот фиксирован в мировых координатах: если выводить его из направления
-- «гоблин → цель», слот поворачивается вместе с подходом и гоблин
-- бесконечно кружит вокруг цели.
local function separatedTarget(player, goblin, target)
	local radius = goblin.FormationRadius or 0
	if radius <= 0 then return target end
	local angle = goblin.FormationAngle or 0
	return Vector3.new(
		target.X + math.cos(angle) * radius,
		target.Y,
		target.Z + math.sin(angle) * radius
	)
end

local function flatDistance(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Препятствием считается только НЕЖИВАЯ геометрия. Игрок и другой NPC —
-- это не стена: иначе гоблин, подбежав вплотную, видит цель как
-- «препятствие» и прыгает на месте вместо того, чтобы бить.
local function isSolidObstacle(result)
	if not result or not result.Instance.CanCollide then return false end
	local model = result.Instance:FindFirstAncestorOfClass("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") then return false end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return true
end

local function jumpOverObstacle(goblin, rootPosition, direction)
	local params = obstacleRayParams(goblin)
	local low = workspace:Raycast(rootPosition + Vector3.new(0, 0.45, 0), direction * 4, params)
	if isSolidObstacle(low) then
		goblin.Humanoid.Jump = true
		return true
	end
	local high = workspace:Raycast(rootPosition + Vector3.new(0, 2.3, 0), direction * 4, params)
	if isSolidObstacle(high) then
		goblin.Humanoid.Jump = true
		return true
	end
	return false
end

--------------------------------------------------------------------------------
-- ЕДИНСТВЕННЫЙ ПРИМИТИВ ДВИЖЕНИЯ.
--
-- destination — точка, к которой рулим. arrivalRadius — на каком удалении
-- считаем, что пришли. ВАЖНО: и то, и другое про ОДНУ И ТУ ЖЕ точку, здесь
-- нет и не может быть рассогласования, из-за которого возник исходный баг.
--
-- Возвращает true, если гоблин уже на месте.
--------------------------------------------------------------------------------
local function steerTowards(goblin, destination, arrivalRadius)
	local humanoid = goblin.Humanoid
	local root = goblin.Model.PrimaryPart
	if not (humanoid and root) or humanoid.Health <= 0 then return false end

	local distance = flatDistance(root.Position, destination)
	if distance <= (arrivalRadius or 2) then
		humanoid:Move(Vector3.zero)
		goblin.Model:SetAttribute("GoblinMoving", false)
		goblin.NoProgressFor = 0
		return true
	end

	local direction = Vector3.new(destination.X - root.Position.X, 0, destination.Z - root.Position.Z)
	if direction.Magnitude <= 0.05 then
		humanoid:Move(Vector3.zero)
		goblin.Model:SetAttribute("GoblinMoving", false)
		return true
	end
	direction = direction.Unit
	humanoid:Move(direction, false)
	goblin.Model:SetAttribute("GoblinMoving", true)

	-- ПРОГРЕСС К ЦЕЛИ, А НЕ «СДВИНУЛСЯ ЛИ Я».
	-- Старый детектор ловил только полную остановку. Гоблин, который
	-- упёрся в угол и бодро скользит вдоль стены, для него двигался
	-- нормально — и не получал нового маршрута никогда. Теперь считаем,
	-- СОКРАЩАЕТСЯ ли расстояние до цели: не сокращается — значит идём не
	-- туда, как бы резво мы при этом ни перебирали ногами.
	local now = os.clock()
	local lastAt = goblin.ProgressCheckedAt or now
	local elapsed = now - lastAt
	if elapsed >= 0.3 then
		local previous = goblin.LastGoalDistance
		goblin.ProgressCheckedAt = now
		goblin.LastGoalDistance = distance
		if previous and previous - distance < 0.35 then
			goblin.NoProgressFor = (goblin.NoProgressFor or 0) + elapsed
		else
			goblin.NoProgressFor = 0
		end
	end

	-- Рейкасты вперёд — ТОЛЬКО когда прогресс уже плохой. На свободной
	-- дороге (подавляющее большинство тиков) это ноль рейкастов вместо
	-- двух, что и было главной статьёй расхода у толпы гоблинов.
	if (goblin.NoProgressFor or 0) > 0.3 then
		jumpOverObstacle(goblin, root.Position, direction)
	end
	return false
end

-- Сбрасывает накопленную статистику прогресса. Обязателен при СМЕНЕ цели:
-- иначе расстояние до новой цели сравнивалось бы с расстоянием до старой,
-- и гоблин мгновенно объявлялся бы застрявшим.
local function resetProgress(goblin)
	goblin.NoProgressFor = 0
	goblin.LastGoalDistance = nil
	goblin.ProgressCheckedAt = nil
end

local function clearPath(goblin)
	goblin.ChaseWaypoints = nil
	goblin.ChaseWaypointIndex = nil
	goblin.ChaseTarget = nil
end

-- СМЕНА НАМЕРЕНИЯ. Детектор застревания сравнивает расстояние до цели с
-- расстоянием на прошлой проверке. Если гоблин переключился с патруля на
-- погоню (или с погони на доставку тележки), это расстояния до РАЗНЫХ
-- точек, и сравнивать их бессмысленно — можно моментально и на ровном
-- месте объявить гоблина застрявшим. Поэтому при каждой смене ветки
-- поведения статистика прогресса обнуляется. Вызывать дёшево: сравнение
-- строк и присваивание.
local function setIntent(goblin, intent)
	if goblin.Intent == intent then return end
	goblin.Intent = intent
	resetProgress(goblin)
	clearPath(goblin)
end

--------------------------------------------------------------------------------
-- ДВИЖЕНИЕ ПО МАРШРУТУ (навмеш) К КОНЕЧНОЙ ЦЕЛИ.
--
-- finalTarget — куда в итоге надо. applyFormation — раздвигать ли гоблинов
-- по слотам строя на ФИНАЛЬНОМ подходе (для игрока/тележки да, для дороги
-- к банку тоже да, чтобы двое не толкались в одной точке).
--------------------------------------------------------------------------------
chaseTo = function(goblin, targetPosition, arrivalRadius, applyFormation)
	local root = goblin.Model.PrimaryPart
	local humanoid = goblin.Humanoid
	if not (root and humanoid) then return false end
	local now = os.clock()
	arrivalRadius = arrivalRadius or 2.5

	-- Финальная точка со смещением строя — считаем ОДИН раз и дальше
	-- используем везде: и как цель движения, и как точку отсчёта «дошёл».
	local finalDestination = targetPosition
	if applyFormation ~= false then
		finalDestination = separatedTarget(goblin.Owner, goblin, targetPosition)
	end

	-- БЛИЗКАЯ ЦЕЛЬ — БЕЗ МАРШРУТА ВООБЩЕ.
	-- Навмеш на 10 студов по открытой площадке только добавляет углов:
	-- он ведёт по сетке, а не по прямой. Плюс это самый частый случай
	-- (бой, подход к тележке) — и самый дорогой, если каждый раз строить
	-- путь.
	if flatDistance(root.Position, finalDestination) <= 12 then
		clearPath(goblin)
		return steerTowards(goblin, finalDestination, arrivalRadius)
	end

	local goalMoved = goblin.ChaseTarget and flatDistance(goblin.ChaseTarget, targetPosition) > 6
	local stalled = (goblin.NoProgressFor or 0) >= 1.2
	local needsRecompute = (not goblin.ChaseWaypoints or goalMoved or stalled)
		and now >= (goblin.NextChaseRecomputeAt or 0)

	if needsRecompute then
		goblin.ChaseTarget = targetPosition
		-- Пересчёт не чаще раза в 0.6с на гоблина. Без этого троттла
		-- недостижимая цель (в стене, в воздухе, вне навмеша) заставляла
		-- вызывать тяжёлый ComputeAsync каждый тик AI — при полном сервере
		-- это сотни построений маршрута в секунду и сервер на 10-15 fps.
		goblin.NextChaseRecomputeAt = now + 0.6
		if stalled then goblin.NoProgressFor = 0 end

		-- Path переиспользуется, а не создаётся заново на каждый пересчёт.
		if not goblin.ChasePath then
			goblin.ChasePath = PathfindingService:CreatePath({
				AgentRadius = 2,
				AgentHeight = 5,
				AgentCanJump = true,
				WaypointSpacing = 6,
			})
		end
		local path = goblin.ChasePath
		local ok = pcall(function()
			path:ComputeAsync(root.Position, targetPosition)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			goblin.ChaseWaypoints = path:GetWaypoints()
			goblin.ChaseWaypointIndex = 2
			resetProgress(goblin)
			if goblin.ChasePathBlockedConnection then
				goblin.ChasePathBlockedConnection:Disconnect()
			end
			goblin.ChasePathBlockedConnection = path.Blocked:Connect(function(blockedIndex)
				if blockedIndex >= (goblin.ChaseWaypointIndex or 2) then
					goblin.ChaseWaypoints = nil
				end
			end)
		else
			-- Маршрут не построился — идём напрямик. Это штатный запасной
			-- путь, а не ошибка: цель может быть на платформе, в воздухе
			-- или просто вне навмеша.
			goblin.ChaseWaypoints = nil
		end
	end

	-- ПРОХОДИМ ВСЕ УЖЕ ПРОЙДЕННЫЕ УЗЛЫ ЗА ОДИН ТИК, а не один за тик.
	-- На спуске или с ускорением гоблин успевал миновать два узла между
	-- тиками, после чего разворачивался к пропущенному — ещё один
	-- источник «шага назад».
	local waypoints = goblin.ChaseWaypoints
	local waypoint
	if waypoints then
		local index = goblin.ChaseWaypointIndex or 2
		while true do
			local candidate = waypoints[index]
			if not candidate then break end
			if flatDistance(root.Position, candidate.Position) > 3.5 then
				waypoint = candidate
				break
			end
			index += 1
			resetProgress(goblin)
		end
		goblin.ChaseWaypointIndex = index
		if not waypoint then
			-- Узлы кончились: остаток пути — по прямой к финальной точке.
			clearPath(goblin)
		end
	end

	if waypoint then
		-- К УЗЛУ ИДЁМ БЕЗ СМЕЩЕНИЯ СТРОЯ. Это общая дорога, а не место
		-- встречи — именно смещение промежуточных узлов и ломало всё
		-- (см. шапку блока).
		local arrived = steerTowards(goblin, waypoint.Position, 3.5)
		if not arrived and waypoint.Action == Enum.PathWaypointAction.Jump then
			humanoid.Jump = true
		end
		-- Долго нет прогресса даже к ближайшему узлу — маршрут врёт
		-- (что-то построили поверх дороги, гоблина столкнули). Рвём его,
		-- следующий тик построит новый.
		if (goblin.NoProgressFor or 0) >= 1.2 then
			clearPath(goblin)
			goblin.NextChaseRecomputeAt = 0
		end
		return false
	end

	return steerTowards(goblin, finalDestination, arrivalRadius)
end

-- Совместимость с остальным кодом сервиса: короткий подход без навмеша.
local function moveGoblin(player, goblin, target, forceMoving)
	local destination = separatedTarget(player, goblin, target)
	local arrived = steerTowards(goblin, destination, forceMoving == true and 0 or 2.5)
	return arrived
end


--------------------------------------------------------------------------------
-- ПАТРУЛЬ.
--
-- Гоблин идёт к выбранной точке, пока НЕ ДОЙДЁТ (а не «пока не истечёт
-- таймер»), потом стоит паузу и выбирает следующую. Раньше цель менялась
-- по таймеру независимо от того, дошёл он или нет, и на смещении строя он
-- до неё в принципе не доходил — получалось вечное «полшага и стоп».
--
-- Точка выбирается СЛУЧАЙНО внутри зоны, а не строго по четырём углам
-- квадрата: угловой маршрут при нескольких гоблинах превращался в
-- одинаковый заметный хоровод по одному и тому же периметру.
--------------------------------------------------------------------------------
local function wander(goblin)
	local now = os.clock()
	local root = goblin.Model.PrimaryPart
	if not root then return end

	if goblin.WanderTarget then
		if not steerTowards(goblin, goblin.WanderTarget, 2.5) then
			-- Не дошёл, но и не приближается — точка недостижима
			-- (застройка участка, бортик). Берём другую, не залипая.
			if (goblin.NoProgressFor or 0) >= 1.5 then
				goblin.WanderTarget = nil
				goblin.NextWanderAt = now
			end
			return
		end
		-- Дошли: пауза перед следующей точкой.
		goblin.WanderTarget = nil
		goblin.NextWanderAt = now + Config.Goblins.WanderInterval + math.random() * 1.5
		return
	end

	if goblin.NextWanderAt and now < goblin.NextWanderAt then
		if goblin.Humanoid then goblin.Humanoid:Move(Vector3.zero) end
		goblin.Model:SetAttribute("GoblinMoving", false)
		return
	end

	local halfSize = Config.Goblins.WanderRadius > 0 and Config.Goblins.WanderRadius or 8
	local target
	for _ = 1, 4 do
		local candidate = goblin.ZoneCenter + Vector3.new(
			(math.random() * 2 - 1) * halfSize,
			0,
			(math.random() * 2 - 1) * halfSize
		)
		-- Точка должна быть достаточно далеко, иначе гоблин «дёргается»
		-- на месте короткими перебежками — визуально это ровно то самое
		-- «ходит туда-сюда», на что жалуются.
		if flatDistance(root.Position, candidate) >= halfSize * 0.5 then
			target = candidate
			break
		end
		target = candidate
	end
	goblin.WanderTarget = target
	resetProgress(goblin)
end

local function makePart(model, name, size, color, cframe, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.CFrame = cframe
	part.CanCollide = name ~= "HumanoidRootPart"
	part.Parent = parent or model
	return part
end

-- Кастомная модель гоблина — ReplicatedStorage.Assets.Goblin_<Тип>_<1|2|3>
-- (например Goblin_Warrior_1/_2/_3, Goblin_Golden_1/_2/_3) — по 3 случайных
-- скина на тип, для визуального разнообразия среди одинаковых по статам
-- гоблинов. Если ни одного из трёх не нашли — пробуем старое имя без
-- номера (Goblin_Warrior, для обратной совместимости с уже расставленными
-- ассетами до этого добавления), и только потом — процедурный плейсхолдер.
-- Обязательные части: HumanoidRootPart, Torso, Head, Left Arm, Right Arm,
-- Left Leg, Right Leg (именно с такими именами — на них завязаны бой/
-- переноска тележки/билборд). Если ассета нет или не хватает хоть одной
-- части — тихо переходим к следующему варианту/плейсхолдеру.
local GOBLIN_REQUIRED_PARTS = {"HumanoidRootPart", "Torso", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg"}
local groundPosition
local function findGoblinAsset(assetName)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local asset = assets and assets:FindFirstChild(assetName)
	if not asset then return nil end
	if not asset:IsA("Model") then
		warn(("[GoblinService] ReplicatedStorage.Assets.%s должен быть Model — пробую следующий вариант."):format(assetName))
		return nil
	end
	for _, partName in GOBLIN_REQUIRED_PARTS do
		local part = asset:FindFirstChild(partName)
		if not part or not part:IsA("BasePart") then
			warn(("[GoblinService] ReplicatedStorage.Assets.%s не хватает части '%s' — пробую следующий вариант."):format(assetName, partName))
			return nil
		end
	end
	return asset:Clone()
end

local function findGoblinAssetWithSkins(baseName)
	-- Три номера в случайном порядке — какой скин попадётся, решается
	-- заново при каждом спавне, и если конкретно этот вариант не собран
	-- правильно, пробуем следующий по порядку вместо немедленного отката
	-- на плейсхолдер.
	local order = {1, 2, 3}
	for index = #order, 2, -1 do
		local swapIndex = math.random(1, index)
		order[index], order[swapIndex] = order[swapIndex], order[index]
	end
	for _, skinNumber in order do
		local model = findGoblinAsset(("%s_%d"):format(baseName, skinNumber))
		if model then return model end
	end
	-- Ни одного пронумерованного скина не нашлось — пробуем старое имя без
	-- номера (обратная совместимость с ассетами, расставленными раньше).
	return findGoblinAsset(baseName)
end

local function createR6Placeholder(position, tier, bankPosition, goblinType, assetOverrideBaseName)
	local definition = Config.Goblins.Types[goblinType]
	local model = findGoblinAssetWithSkins(assetOverrideBaseName or ("Goblin_" .. goblinType))
	local usedCustomAsset = model ~= nil
	local root, torso, head, leftArm, rightArm, leftLeg, rightLeg
	if model then
		-- Keep the Humanoid from the supplied R6 dummy. Its rig setup and
		-- Animator are already valid; replacing it breaks imported animations.
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("AnimationController") then
				descendant:Destroy()
			elseif descendant:IsA("BasePart") then
				descendant.Anchored = false
				descendant.Massless = descendant.Name ~= "HumanoidRootPart"
			end
		end
		model:PivotTo(CFrame.new(position))
		root = model.HumanoidRootPart
		torso = model.Torso
		head = model.Head
		leftArm = model["Left Arm"]
		rightArm = model["Right Arm"]
		leftLeg = model["Left Leg"]
		rightLeg = model["Right Leg"]
		root.Transparency = 1
		root.CanCollide = false
		root.CanTouch = false
	else
		model = Instance.new("Model")
		root = makePart(model, "HumanoidRootPart", Vector3.new(2, 2, 1), Color3.new(1, 1, 1), CFrame.new(position), model)
		root.Transparency = 1
		root.CanCollide = false
		torso = makePart(model, "Torso", Vector3.new(2, 2, 1), Color3.fromRGB(80, 170, 70), CFrame.new(position + Vector3.new(0, 1.5, 0)), model)
		head = makePart(model, "Head", Vector3.new(2, 1, 1), Color3.fromRGB(110, 205, 85), CFrame.new(position + Vector3.new(0, 3, 0)), model)
		leftArm = makePart(model, "Left Arm", Vector3.new(1, 2, 1), Color3.fromRGB(80, 170, 70), CFrame.new(position + Vector3.new(-1.5, 1.5, 0)), model)
		rightArm = makePart(model, "Right Arm", Vector3.new(1, 2, 1), Color3.fromRGB(80, 170, 70), CFrame.new(position + Vector3.new(1.5, 1.5, 0)), model)
		leftLeg = makePart(model, "Left Leg", Vector3.new(1, 2, 1), Color3.fromRGB(45, 100, 55), CFrame.new(position + Vector3.new(-0.5, -0.5, 0)), model)
		rightLeg = makePart(model, "Right Leg", Vector3.new(1, 2, 1), Color3.fromRGB(45, 100, 55), CFrame.new(position + Vector3.new(0.5, -0.5, 0)), model)

		local function motor(name, part0, part1, c0, c1)
			local joint = Instance.new("Motor6D")
			joint.Name = name
			joint.Part0 = part0
			joint.Part1 = part1
			joint.C0 = c0
			joint.C1 = c1
			joint.Parent = part0
		end
		motor("RootJoint", root, torso, CFrame.new(0, 1, 0), CFrame.new())
		motor("Neck", torso, head, CFrame.new(0, 1, 0), CFrame.new(0, -0.5, 0))
		motor("Left Shoulder", torso, leftArm, CFrame.new(-1, 0.5, 0), CFrame.new(0, 0.5, 0))
		motor("Right Shoulder", torso, rightArm, CFrame.new(1, 0.5, 0), CFrame.new(0, 0.5, 0))
		motor("Left Hip", torso, leftLeg, CFrame.new(-0.5, -1, 0), CFrame.new(0, 1, 0))
		motor("Right Hip", torso, rightLeg, CFrame.new(0.5, -1, 0), CFrame.new(0, 1, 0))
	end
	model.Name = goblinType .. "Goblin"

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = Instance.new("Humanoid")
		humanoid.Parent = model
	end
	humanoid.DisplayName = "Goblin"
	-- ВАЖНО: MaxHealth должен выставляться ПЕРЕД Health. Если сначала задать
	-- Health, а MaxHealth (по умолчанию 100) ещё не обновлён, Roblox тут же
	-- обрежет Health до 100 — и здоровье гоблинов высоких тиров (у которых
	-- Health + tier*HealthPerTier легко превышает 100) окажется заниженным.
	local maxHealth = GoblinStats.Health(goblinType, tier, false)
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.WalkSpeed = Config.Goblins.BaseWalkSpeed + tier * 0.45
	humanoid.PlatformStand = false
	humanoid.Sit = false
	humanoid.AutoRotate = true
	humanoid.EvaluateStateMachine = true
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 50
	humanoid.AutoJumpEnabled = true
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	-- ПРОИЗВОДИТЕЛЬНОСТЬ. Стейт-машина Humanoid'а обсчитывается сервером
	-- КАЖДЫЙ физический шаг для каждого NPC, и стоит она тем дороже, чем
	-- больше состояний разрешено. Гоблину не нужно ничего из списка ниже:
	-- он не плавает, не летает, не садится и не переходит в ragdoll (при
	-- смерти модель всё равно уничтожается через 0.25с, см. Died-обработчик
	-- в SpawnWave). Оставляем включёнными только реально используемые
	-- Running / Freefall / Landed / Jumping / GettingUp.
	-- EvaluateStateMachine НЕ трогаем: без него перестанут работать прыжки
	-- через препятствия (humanoid.Jump = true в chaseTo/tryObstacleJump).
	for _, stateType in {
		Enum.HumanoidStateType.FallingDown,
		Enum.HumanoidStateType.Ragdoll,
		Enum.HumanoidStateType.Flying,
		Enum.HumanoidStateType.Swimming,
		Enum.HumanoidStateType.PlatformStanding,
		Enum.HumanoidStateType.StrafingNoPhysics,
		Enum.HumanoidStateType.Seated,
	} do
		pcall(function() humanoid:SetStateEnabled(stateType, false) end)
	end
	-- BreakJointsOnDeath = false убирает разлёт шести частей рига физикой в
	-- момент смерти (заметный спайк, особенно когда волну добивают залпом).
	-- Визуально разницы почти нет — модель удаляется через 0.25с. Если
	-- захочешь вернуть прежнее "рассыпание" — поставь true.
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	model.PrimaryPart = root
	local zoneFolder = workspace:FindFirstChild("GoblinZones") or Instance.new("Folder")
	zoneFolder.Name = "GoblinZones"
	zoneFolder.Parent = workspace
	local zone = Instance.new("Part")
	zone.Name = "AttackZone"
	zone.Shape = Enum.PartType.Block
	zone.Size = Vector3.new(Config.Goblins.AttackRadius * 2, 0.22, Config.Goblins.AttackRadius * 2)
	zone.CFrame = CFrame.new(position - Vector3.new(0, 0.85, 0))
	zone.Anchored = true
	zone.Color = Color3.fromRGB(255, 45, 45)
	zone.Material = Enum.Material.Neon
	zone.Transparency = 1
	zone.CastShadow = false
	zone.Locked = true
	zone.CanCollide = false
	zone.CanTouch = false
	zone.CanQuery = false
	zone.Parent = zoneFolder
	local zoneSurface = Instance.new("SurfaceGui")
	zoneSurface.Name = "AttackZoneSurface"
	zoneSurface.Face = Enum.NormalId.Top
	zoneSurface.AlwaysOnTop = true
	zoneSurface.LightInfluence = 0
	zoneSurface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	zoneSurface.PixelsPerStud = 2
	zoneSurface.Enabled = false
	zoneSurface.Parent = zone
	local zoneFill = Instance.new("Frame")
	zoneFill.Size = UDim2.fromScale(1, 1)
	zoneFill.BackgroundColor3 = Color3.fromRGB(255, 35, 35)
	zoneFill.BackgroundTransparency = 0.72
	zoneFill.BorderSizePixel = 0
	zoneFill.Parent = zoneSurface

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "GoblinInfo"
	billboard.Adornee = head
	billboard.Size = UDim2.fromOffset(200, 41)
	billboard.SizeOffset = Vector2.new(0, 0)
	billboard.StudsOffset = Vector3.new(0, 3.15, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = (Config.HealthDisplay and Config.HealthDisplay.GoblinMaxDistance) or 55
	-- Отрисовка фиксированного экранного варианта выполняется клиентом.
	-- BillboardGui оставляем как серверный fallback, но не показываем его.
	billboard.Enabled = false
	billboard.Parent = head

	local tierColor = getTierColor(tier)
	local iconBadge = Instance.new("Frame")
	iconBadge.Name = "IconBadge"
	iconBadge.Size = UDim2.fromOffset(38, 38)
	iconBadge.Position = UDim2.fromOffset(1, 1)
	iconBadge.BackgroundTransparency = 1
	iconBadge.BorderSizePixel = 0
	iconBadge.Parent = billboard
	local icon = Instance.new("ImageLabel")
	icon.Name = "GoblinIcon"
	icon.Size = UDim2.fromScale(1, 1)
	icon.BackgroundTransparency = 1
	icon.BorderSizePixel = 0
	icon.Image = Config.Goblins.IconImage or ""
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = iconBadge
	local iconFallback = WorldUi.Text(nil, "Text", "Number")
	iconFallback.Name = "IconPlaceholder"
	iconFallback.Size = UDim2.fromScale(1, 1)
	iconFallback.BackgroundTransparency = 1
	iconFallback.Text = "G"
	iconFallback.TextColor3 = tierColor
	iconFallback.TextSize = 18
	iconFallback.Visible = icon.Image == ""
	iconFallback.Parent = icon

	local info = Instance.new("Frame")
	info.Name = "Info"
	info.Size = UDim2.fromOffset(156, 38)
	info.Position = UDim2.fromOffset(42, 1)
	info.BackgroundTransparency = 1
	info.BorderSizePixel = 0
	info.Parent = billboard
	local title = WorldUi.Text(nil, "Text", "Number")
	title.Size = UDim2.new(1, -12, 0, 19)
	title.Position = UDim2.fromOffset(6, 1)
	title.BackgroundTransparency = 1
	title.TextSize = 11
	title.TextScaled = false
	title.RichText = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(238, 240, 235)
	title.Text = ("%s <font color=\"#69EB82\">Lv. %d</font>"):format(definition.DisplayName, tier)
	title.Parent = info
	local healthBack = Instance.new("Frame")
	healthBack.Name = "HealthBar"
	healthBack.Size = UDim2.new(1, -12, 0, 10)
	healthBack.Position = UDim2.new(0, 6, 1, -14)
	healthBack.BackgroundColor3 = Color3.fromRGB(7, 8, 9)
	healthBack.BackgroundTransparency = 0.15
	healthBack.BorderSizePixel = 0
	healthBack.ClipsDescendants = true
	healthBack.Parent = info
	local healthFill = Instance.new("Frame")
	healthFill.Name = "Fill"
	healthFill.Size = UDim2.fromScale(1, 1)
	healthFill.BackgroundColor3 = Color3.fromRGB(104, 207, 80)
	healthFill.BorderSizePixel = 0
	healthFill.Parent = healthBack
	local healthText = WorldUi.Text(nil, "Text", "Number")
	healthText.Size = UDim2.fromScale(1, 1)
	healthText.BackgroundTransparency = 1
	healthText.TextSize = 8
	healthText.TextScaled = false
	healthText.RichText = true
	healthText.TextColor3 = Color3.new(1, 1, 1)
	healthText.ZIndex = 2
	healthText.Parent = healthBack
	local function updateHealthBar(health)
		local ratio = math.clamp(health / humanoid.MaxHealth, 0, 1)
		healthFill.Size = UDim2.fromScale(ratio, 1)
		healthFill.BackgroundColor3 = ratio <= 0.3 and Color3.fromRGB(230, 60, 60) or ratio <= 0.6 and Color3.fromRGB(245, 190, 55) or Color3.fromRGB(90, 220, 90)
		healthText.Text = ("HP %d/%d"):format(math.max(0, math.ceil(health)), math.ceil(humanoid.MaxHealth))
	end
	updateHealthBar(humanoid.Health)
	humanoid.HealthChanged:Connect(updateHealthBar)
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	model:SetAttribute("GoblinMineTier", tier)
	model:SetAttribute("GoblinType", goblinType)
	local tierScale = 1 + math.clamp(tier - 1, 0, 9) * 0.40 / 9
	model:ScaleTo(definition.Size * tierScale)
	-- Humanoid uses HipHeight to keep the root above the floor. Scale it with
	-- the rig so larger goblins do not float after Model:ScaleTo.
	humanoid.HipHeight *= definition.Size * tierScale
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then descendant.CollisionGroup = GOBLIN_COLLISION_GROUP end
	end
	local ground = groundPosition(position)
	local pivotToRoot = root.CFrame:ToObjectSpace(model:GetPivot())
	local rootPosition = Vector3.new(
		position.X,
		ground.Y + root.Size.Y * 0.5 + humanoid.HipHeight,
		position.Z
	)
	local rootTarget = CFrame.lookAt(rootPosition, Vector3.new(bankPosition.X, rootPosition.Y, bankPosition.Z))
	model:PivotTo(rootTarget * pivotToRoot)
	zone.CFrame = CFrame.new(root.Position - Vector3.new(0, 0.85, 0))
	return model, zone, usedCustomAsset
end

local function pivotInstance(instance, cframe)
	if instance:IsA("Model") then instance:PivotTo(cframe) else instance.CFrame = cframe end
end

groundPosition = function(position)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local excluded = {}
	local goblinsFolder = workspace:FindFirstChild("Goblins")
	local zonesFolder = workspace:FindFirstChild("GoblinZones")
	if goblinsFolder then table.insert(excluded, goblinsFolder) end
	if zonesFolder then table.insert(excluded, zonesFolder) end
	params.FilterDescendantsInstances = excluded
	local result = workspace:Raycast(position + Vector3.new(0, 12, 0), Vector3.new(0, -80, 0), params)
	return result and result.Position or position - Vector3.new(0, 1, 0)
end

local function dropGroundPosition(player, position)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		return Vector3.new(position.X, root.Position.Y, position.Z)
	end
	warn(("[GoblinDrop] Не найден HumanoidRootPart игрока %s, использую raycast для высоты дропа."):format(player.Name))
	return groundPosition(position)
end

local function colorSequence(color)
	if typeof(color) ~= "Color3" then color = Color3.new(1, 1, 1) end
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, color),
		ColorSequenceKeypoint.new(1, color),
	})
end

local function scaleVisual(instance, scale)
	if instance:IsA("Model") then
		instance:ScaleTo(scale)
	elseif instance:IsA("BasePart") then
		instance.Size *= scale
	end
end

local function prepareVisual(instance)
	local root = instance:IsA("BasePart") and instance
		or (instance:IsA("Model") and instance.PrimaryPart)
		or instance:FindFirstChild("Root", true)
		or instance:FindFirstChildWhichIsA("BasePart", true)
	if not root then return nil end
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	return root
end

local function colorHex(color)
	return ("#%02X%02X%02X"):format(math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255))
end

local function placeVisualAtFloor(visual, root, floorPosition)
	pivotInstance(visual, CFrame.new(floorPosition))
	local bottomY
	if visual:IsA("Model") then
		local boundsCFrame, boundsSize = visual:GetBoundingBox()
		bottomY = boundsCFrame.Position.Y - boundsSize.Y * 0.5
	else
		bottomY = root.Position.Y - root.Size.Y * 0.5
	end
	local pivot = visual:IsA("Model") and visual:GetPivot() or root.CFrame
	pivotInstance(visual, pivot + Vector3.new(0, floorPosition.Y - bottomY + 0.05, 0))
	return visual:IsA("Model") and visual:GetPivot() or root.CFrame
end

local function faceVisualToward(visual, root, floorPosition, targetPosition)
	if not targetPosition then return visual:IsA("Model") and visual:GetPivot() or root.CFrame end
	local pivot = visual:IsA("Model") and visual:GetPivot() or root.CFrame
	local target = Vector3.new(targetPosition.X, pivot.Position.Y, targetPosition.Z)
	if (target - pivot.Position).Magnitude < 0.01 then return pivot end
	pivotInstance(visual, CFrame.lookAt(pivot.Position, target))
	local bottomY
	if visual:IsA("Model") then
		local boundsCFrame, boundsSize = visual:GetBoundingBox()
		bottomY = boundsCFrame.Position.Y - boundsSize.Y * 0.5
	else
		bottomY = root.Position.Y - root.Size.Y * 0.5
	end
	pivot = visual:IsA("Model") and visual:GetPivot() or root.CFrame
	pivotInstance(visual, pivot + Vector3.new(0, floorPosition.Y - bottomY + 0.05, 0))
	return visual:IsA("Model") and visual:GetPivot() or root.CFrame
end

local function animateVisualScale(visual, root, floorPosition, faceTarget, fromScale, toScale, duration, easingStyle, easingDirection)
	local baseScale = visual:IsA("Model") and visual:GetScale() or nil
	local baseSize = visual:IsA("BasePart") and visual.Size or nil
	local function apply(scale)
		if not visual.Parent then return end
		if baseScale then
			visual:ScaleTo(baseScale * scale)
		else
			visual.Size = baseSize * scale
		end
		if floorPosition then
			placeVisualAtFloor(visual, root, floorPosition)
			faceVisualToward(visual, root, floorPosition, faceTarget)
		end
	end
	apply(fromScale)
	local value = Instance.new("NumberValue")
	value.Value = fromScale
	local connection = value.Changed:Connect(apply)
	local tween = TweenService:Create(value, TweenInfo.new(duration, easingStyle or Enum.EasingStyle.Quad, easingDirection or Enum.EasingDirection.Out), {Value = toScale})
	tween:Play()
	tween.Completed:Wait()
	connection:Disconnect()
	value:Destroy()
	apply(toScale)
end

local function visiblePartCount(visual)
	local count = visual:IsA("BasePart") and visual.Transparency < 0.98 and visual.Size.Magnitude > 0.01 and 1 or 0
	for _, descendant in visual:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Transparency < 0.98 and descendant.Size.Magnitude > 0.01 then
			count += 1
		end
	end
	return count
end

local function resolveLootFloor(player, position, ignore, loot)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local excluded = {}
	if ignore then table.insert(excluded, ignore) end
	if loot then table.insert(excluded, loot) end
	local character = player.Character
	if character then table.insert(excluded, character) end
	local goblins = workspace:FindFirstChild("Goblins")
	local zones = workspace:FindFirstChild("GoblinZones")
	if goblins then table.insert(excluded, goblins) end
	if zones then table.insert(excluded, zones) end
	params.FilterDescendantsInstances = excluded
	local hit = workspace:Raycast(position + Vector3.new(0, 10, 0), Vector3.new(0, -1000, 0), params)
	if hit then
		return Vector3.new(position.X, hit.Position.Y, position.Z)
	end
	warn(("[GoblinDrop] Поверхность под предметом не найдена, использую высоту сундука: %s"):format(tostring(position)))
	return position
end

-- К какому размеру (наибольшая сторона, в студах) приводится коробка лута,
-- какой бы ассет под неё ни подложили. Без этого своя модель коробки из
-- Studio прилетала бы в игрока в своём "мировом" масштабе — сундук в рост
-- персонажа выглядит багом, а не наградой.
local LOOT_BOX_TARGET_STUDS = 2

local function normalizeLootBoxSize(loot)
	local size
	if loot:IsA("Model") then
		local _, boundsSize = loot:GetBoundingBox()
		size = boundsSize
	elseif loot:IsA("BasePart") then
		size = loot.Size
	end
	if not size then return end
	local largest = math.max(size.X, size.Y, size.Z)
	if largest <= 0.01 then return end
	local factor = LOOT_BOX_TARGET_STUDS / largest
	-- Уже подходящего размера — не трогаем вовсе: лишний ScaleTo на чужой
	-- модели способен разъехать сварки, если билдер собрал её нестандартно.
	if math.abs(factor - 1) < 0.05 then return end
	if loot:IsA("Model") then
		loot:ScaleTo(loot:GetScale() * factor)
	else
		loot.Size = loot.Size * factor
	end
end

-- ВИЗУАЛ НАГРАДЫ, ВЫПАДАЮЩЕЙ ИЗ ВАЛУНА/СУНДУКА. Награду, у которой нет
-- своего предмета в мире (скин и всё в этом духе), показываем КОРОБКОЙ:
-- она вылетает по дуге, падает на землю, подпрыгивает и влетает в игрока.
--
-- Раньше коробка бралась напрямую из ReplicatedStorage.Assets.box, а если
-- такого ассета не было (а его не создаёт ни один из tools/Build*.lua, то
-- есть по умолчанию не было НИКОГДА) — вместо коробки летел неоновый шарик.
-- Теперь коробку выдаёт PlaceholderFactory.LootBox() — она сама вернёт
-- либо твою модель из Assets (имена LootBox/Box/box), либо плейсхолдер-
-- коробку, который ты заменишь, не трогая код.
local function spawnChestLoot(player, kind, geodeType, position, color, onCollected, ignore)
	if kind == "Money" then color = Config.CoinFx.CoinColor end
	local usesLootBox = kind ~= "Geode" and kind ~= "Money"
	local loot = kind == "Geode" and PlaceholderFactory.Geode(geodeType)
		or kind == "Money" and PlaceholderFactory.Coin()
		or PlaceholderFactory.LootBox()
	if not loot:IsA("Model") and not loot:IsA("BasePart") then
		local container = loot
		loot = Instance.new("Model")
		loot.Name = "LootBox"
		for _, child in container:GetChildren() do child.Parent = loot end
		container:Destroy()
	end
	if kind == "Geode" then
		if loot:IsA("Model") then loot:ScaleTo(loot:GetScale() / 3) else loot.Size /= 3 end
	elseif usesLootBox then
		loot.Name = kind == "Boulder" and "BoulderRewardBox" or (kind == "Skin" and "SkinRewardBox" or "RewardBox")
		normalizeLootBoxSize(loot)
	end
	local root = prepareVisual(loot)
	if not root then
		warn(("[GoblinDrop] У предмета нет BasePart: player=%s kind=%s"):format(player.Name, kind))
		loot:Destroy()
		if onCollected then onCollected() end
		return
	end
	loot.Parent = workspace
	local angle = math.random() * math.pi * 2
	local distance = math.random(7, 11)
	local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local landPosition = resolveLootFloor(player, position + direction * distance, ignore, loot)
	local land = placeVisualAtFloor(loot, root, landPosition)
	local startPosition = position + Vector3.new(0, 1.4, 0)
	local start = CFrame.fromMatrix(startPosition, land.XVector, land.YVector, land.ZVector)
	pivotInstance(loot, start)
	local baseScale = loot:IsA("Model") and loot:GetScale() or nil
	local baseSize = loot:IsA("BasePart") and loot.Size or nil
	local function setSpitScale(scale)
		if baseScale then loot:ScaleTo(baseScale * scale) else loot.Size = baseSize * scale end
	end
	local attachment0 = Instance.new("Attachment")
	local attachment1 = Instance.new("Attachment")
	attachment0.Position = Vector3.new(0, 0.12, 0)
	attachment1.Position = Vector3.new(0, -0.12, 0)
	attachment0.Parent = root
	attachment1.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0 = attachment0
	trail.Attachment1 = attachment1
	trail.Color = colorSequence(color)
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.Lifetime = 0.28
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Parent = root
	local targetRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	-- Ось кувырка коробки — своя на каждый дроп, чтобы две коробки, выпавшие
	-- из одного валуна, не крутились абсолютно одинаково.
	local tumbleAxis = Vector3.new(math.random() * 0.6 + 0.2, math.random() * 0.6 + 0.2, (math.random() - 0.5) * 0.5)
	local progress = Instance.new("NumberValue")
	progress.Value = 0
	local connection = progress.Changed:Connect(function(alpha)
		if not loot.Parent then return end
		local spitScale = alpha < 0.22
			and 0.70 + (alpha / 0.22) * 0.50
			or 1.20 - ((alpha - 0.22) / 0.78) * 0.20
		setSpitScale(spitScale)
		local horizontal = startPosition:Lerp(land.Position, alpha)
		local arcHeight = math.sin(alpha * math.pi) * 6
		local arcPosition = horizontal + Vector3.new(0, arcHeight, 0)
		-- КОРОБКА КУВЫРКАЕТСЯ В ПОЛЁТЕ, монета/жеода — нет. Ящик, летящий
		-- по дуге без единого поворота, читается как приклеенный к
		-- невидимым рельсам; полный оборот за перелёт (и плавное
		-- затухание кувырка к посадке, чтобы коробка легла ровно, а не
		-- замерла на боку) делает выброс из камня "физическим".
		local orientation = CFrame.fromMatrix(arcPosition, land.XVector, land.YVector, land.ZVector)
		if usesLootBox then
			local settle = 1 - alpha * alpha -- к концу дуги кувырок сходит на нет
			orientation *= CFrame.Angles(tumbleAxis.X * alpha * math.pi * 2 * settle, tumbleAxis.Y * alpha * math.pi * 2 * settle, tumbleAxis.Z * alpha * math.pi * settle)
		end
		pivotInstance(loot, orientation)
	end)
	local fall = TweenService:Create(progress, TweenInfo.new(0.75, Enum.EasingStyle.Linear), {Value = 1})
	fall:Play()
	fall.Completed:Connect(function()
		if not loot.Parent then return end
		setSpitScale(1)
		pivotInstance(loot, land)
		local bounce = Instance.new("CFrameValue")
		bounce.Value = land
		local bounceConnection = bounce.Changed:Connect(function(value)
			if loot.Parent then pivotInstance(loot, value) end
		end)
		local bounceUp = TweenService:Create(bounce, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Value = land * CFrame.new(0, 0.65, 0)})
		bounceUp:Play()
		bounceUp.Completed:Wait()
		local bounceDown = TweenService:Create(bounce, TweenInfo.new(0.18, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {Value = land})
		bounceDown:Play()
		bounceDown.Completed:Wait()
		bounceConnection:Disconnect()
		bounce:Destroy()
		task.wait(1.25)
		if not loot.Parent then return end
		if connection then connection:Disconnect() end
		progress:Destroy()
		-- ИСПРАВЛЕНИЕ БАГА "не долетает до игрока, который сдвинулся":
		-- target ниже раньше вычислялся ОДИН РАЗ, ДО всей этой функции
		-- (fall+bounce+пауза — суммарно ~2.3 сек до этого момента), а
		-- потом лут летел к нему статическим твином. Игрок почти
		-- гарантированно успевал сдвинуться за такое время. Теперь позиция
		-- берётся ЗАНОВО прямо перед стартом фазы подлёта И пересчитывается
		-- каждый кадр во время самого полёта — та же логика, что и
		-- CrystalService:_flyToHand/_flyToBack/_flyToCart (см. их
		-- homeToTarget).
		local flightStart = loot:IsA("Model") and loot:GetPivot().Position or root.Position
		local function currentLootTarget()
			local liveRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			return liveRoot and (liveRoot.Position + Vector3.new(0, 1.5, 0))
		end
		local flightStartClock = os.clock()
		local flyDuration = 0.55
		local lastKnownTarget = currentLootTarget() or land.Position
		local flyConnection
		flyConnection = RunService.Heartbeat:Connect(function()
			if not loot.Parent then
				flyConnection:Disconnect()
				return
			end
			lastKnownTarget = currentLootTarget() or lastKnownTarget
			local alpha = math.clamp((os.clock() - flightStartClock) / flyDuration, 0, 1)
			local eased = alpha * alpha -- тот же разгон, что раньше давал Quad/In
			local position = flightStart:Lerp(lastKnownTarget, eased)
			pivotInstance(loot, CFrame.fromMatrix(position, land.XVector, land.YVector, land.ZVector))
			if alpha >= 1 then
				flyConnection:Disconnect()
				if loot.Parent then
					Sfx.play("LootPickup", targetRoot or root)
					local rewardSound = kind == "Money" and "RewardMoney"
						or kind == "Geode" and "RewardGeode"
						or kind == "Skin" and "RewardSkin"
					if rewardSound then Sfx.play(rewardSound, targetRoot or root) end
					loot:Destroy()
				end
				if onCollected then onCollected() end
			end
		end)
	end)
	-- Как и у сундука: страховка от мусора, а не таймер анимации. Цепочка
	-- предмета (полёт 0.75 + отскок 0.32 + пауза 1.25 + подлёт к игроку 0.55)
	-- занимает ~2.9с, но при просадке fps растягивается. Со старыми 4.5с
	-- Debris успевал уничтожить предмет ДО вызова onCollected — из-за чего
	-- счётчик собранных наград не доходил до нуля, итоговое уведомление
	-- "Goblin chest opened" не показывалось, а открытый сундук не закрывался.
	Debris:AddItem(loot, 20)
end

-- Гарантированно рабочий фолбэк для сундука (простая деревянная коробка).
-- Раньше фолбэк-ветка мутировала УЖЕ НАЙДЕННЫЙ инстанс из шаблона "Chest"
-- (close.Size = ..., close.Color = ..., close.Material = ...) — если Close
-- нашёлся, а Open нет (или наоборот), это пыталось выставить Size/Color/
-- Material на Model, у которой таких свойств просто нет → рантайм-ошибка,
-- которая обрывала spawnGoblinChest ДО того, как сундук вообще успевал
-- появиться в мире. Теперь для каждой недостающей половины (Close/Open)
-- строится независимый, гарантированно валидный Part — ничего чужого не
-- трогаем.
local function buildFallbackChestPart(name)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(3, 2, 2)
	part.Color = Color3.fromRGB(130, 75, 35)
	part.Material = Enum.Material.Wood
	return part
end

-- Ищем шаблон именно там, где он реально лежит: ReplicatedStorage -> Assets
-- -> Chest (тот же путь/конвенция, что и у остальных ассетов в
-- PlaceholderFactory.findAsset). Если чего-то не хватает — печатаем ТОЧНО,
-- чего именно, чтобы не гадать при следующей проверке.
local function findChestTemplate()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		warn("[GoblinService] ReplicatedStorage.Assets не найден — сундук гоблина будет простым деревянным ящиком-заглушкой.")
		return nil
	end
	local chest = assets:FindFirstChild("Chest")
	if not chest then
		warn("[GoblinService] ReplicatedStorage.Assets.Chest не найден — сундук гоблина будет простым деревянным ящиком-заглушкой.")
	end
	return chest
end

-- Оборачиваем масштабирование/подготовку визуала в pcall: если у авторского
-- Close/Open что-то не так (например, ScaleTo споткнётся об необычную
-- геометрию/риг конкретной модели), это НЕ должно рушить весь спавн сундука —
-- откатываемся на гарантированно рабочую деревянную коробку вместо того,
-- чтобы ничего не показать вообще.
local function safeBuildChestPiece(name, instance)
	if instance then
		local ok, result = pcall(function()
			if not instance:IsA("Model") and not instance:IsA("BasePart") then
				local container = instance
				instance = Instance.new("Model")
				instance.Name = name
				for _, child in container:GetChildren() do
					child.Parent = instance
				end
				container:Destroy()
			end
			scaleVisual(instance, 0.6)
			return prepareVisual(instance)
		end)
		local root = ok and result
		if root then
			return instance, root
		end
		warn(("[GoblinDrop] Не удалось подготовить Chest.%s (%s) — использую фолбэк."):format(name, ok and "нет BasePart" or tostring(result)))
		if instance and instance.Parent then instance:Destroy() end
	end
	local fallback = buildFallbackChestPart(name)
	return fallback, prepareVisual(fallback)
end

local function spawnGoblinChest(player, rewards, position)
	local chestColor = rewards[1] and rewards[1].Color or Color3.new(1, 1, 1)
	local template = findChestTemplate()
	local closeSource = template and template:FindFirstChild("Close", true)
	local openSource = template and template:FindFirstChild("Open", true)
	if template and not closeSource then
		warn("[GoblinService] ReplicatedStorage.Assets.Chest.Close не найден.")
	end
	if template and not openSource then
		warn("[GoblinService] ReplicatedStorage.Assets.Chest.Open не найден.")
	end
	local close, closeRoot = safeBuildChestPiece("Close", closeSource and closeSource:Clone())
	if visiblePartCount(close) == 0 then
		warn("[GoblinDrop] Chest.Close не содержит видимых деталей, использую видимый фолбэк.")
		close:Destroy()
		close, closeRoot = safeBuildChestPiece("Close", nil)
	end
	local character = player.Character
	local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
	local playerHumanoid = character and character:FindFirstChildOfClass("Humanoid")
	local floorY = playerRoot and (playerRoot.Position.Y - playerRoot.Size.Y * 0.5 - (playerHumanoid and playerHumanoid.HipHeight or 2)) or position.Y
	local forward = playerRoot and Vector3.new(playerRoot.CFrame.LookVector.X, 0, playerRoot.CFrame.LookVector.Z) or Vector3.new(0, 0, -1)
	if forward.Magnitude < 0.01 then forward = Vector3.new(0, 0, -1) end
	local chestFloor = (playerRoot and playerRoot.Position or position) + forward.Unit * 6
	chestFloor = Vector3.new(chestFloor.X, floorY, chestFloor.Z)
	local chestTarget = playerRoot and Vector3.new(playerRoot.Position.X, floorY, playerRoot.Position.Z) or nil
	close.Parent = workspace
	local chestCFrame = placeVisualAtFloor(close, closeRoot, chestFloor)
	faceVisualToward(close, closeRoot, chestFloor, chestTarget)
	chestCFrame = close:IsA("Model") and close:GetPivot() or closeRoot.CFrame
	animateVisualScale(close, closeRoot, chestFloor, chestTarget, 0.08, 1, 0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	Sfx.play("ChestSpawn", closeRoot)
	local shake = Instance.new("CFrameValue")
	shake.Value = chestCFrame
	local shakeConnection = shake.Changed:Connect(function(value)
		if close.Parent then pivotInstance(close, value) end
	end)
	local function notifyLootFallback()
		if not Services.NotifyService then return end
		local collected = table.create(#rewards)
		for index, reward in rewards do
			collected[index] = ("<font color=\"%s\">%s</font>"):format(colorHex(reward.Color), reward.Text)
		end
		Services.NotifyService:Show(player, "Goblin chest opened!\n" .. table.concat(collected, "\n"), {
			Duration = 4,
			RichText = true,
			TextColor = Color3.new(1, 1, 1),
			Icon = "Goblin",
		})
	end
	local openLoopSound
	task.spawn(function()
		local ok, err = pcall(function()
			task.wait(0.35)
			if not close.Parent then return end

			-- ЗВУК ОТКРЫТИЯ ЗВУЧИТ ВЕСЬ ПЕРИОД ТРЯСКИ, а не только в момент,
			-- когда сундук фактически распадается на "открытую" половину.
			-- Раньше ChestOpen проигрывался ОДИН РАЗ в самом конце — вся
			-- тряска (2 прыжка + 8 покачиваний + успокоение, ~2.3с) была
			-- озвучена только разовым ChestShake в самом начале, и открытие
			-- ощущалось как внезапный щелчок без нарастания.
			openLoopSound = Sfx.createLoop("ChestOpen", closeRoot)
			if openLoopSound then
				openLoopSound.Playing = true
			end

			for _ = 1, 2 do
				if _ == 1 then Sfx.play("ChestShake", closeRoot) end
				local jump = TweenService:Create(shake, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Value = chestCFrame * CFrame.new(0, 1.0, 0) * CFrame.Angles(0, 0, math.rad(3)),
				})
				jump:Play()
				jump.Completed:Wait()
				local land = TweenService:Create(shake, TweenInfo.new(0.32, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {
					Value = chestCFrame,
				})
				land:Play()
				land.Completed:Wait()
			end
			for index = 1, 8 do
				local angle = (index % 2 == 0 and 6 or -6) * math.min(1, index / 4)
				local wiggle = TweenService:Create(shake, TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
					Value = chestCFrame * CFrame.Angles(0, 0, math.rad(angle)),
				})
				wiggle:Play()
				wiggle.Completed:Wait()
			end
			local settle = TweenService:Create(shake, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Value = chestCFrame})
			settle:Play()
			settle.Completed:Wait()

			-- Тряска закончилась — глушим цикл ПЛАВНО, а не обрывом: резкий
			-- Stop() на длинном сэмпле слышен как щелчок ровно в момент,
			-- когда должен звучать следующий, финальный удар открытия ниже.
			if openLoopSound then
				local fade = TweenService:Create(openLoopSound, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Volume = 0 })
				fade:Play()
				fade.Completed:Wait()
				openLoopSound:Stop()
				openLoopSound:Destroy()
				openLoopSound = nil
			end

			if shakeConnection then shakeConnection:Disconnect() end
			shake:Destroy()
			if not close.Parent then return end
			close:Destroy()
			local open, openRoot = safeBuildChestPiece("Open", openSource and openSource:Clone())
			if visiblePartCount(open) == 0 then
				warn("[GoblinDrop] Chest.Open не содержит видимых деталей, использую видимый фолбэк.")
				open:Destroy()
				open, openRoot = safeBuildChestPiece("Open", nil)
			end
			open.Parent = workspace
			placeVisualAtFloor(open, openRoot, chestFloor)
			faceVisualToward(open, openRoot, chestFloor, chestTarget)
			local emitters = {}
			for _, descendant in open:GetDescendants() do
				if descendant:IsA("ParticleEmitter") then table.insert(emitters, descendant) end
			end
			if #emitters == 0 then
				local attachment = Instance.new("Attachment")
				attachment.Name = "GoblinChestVFXPoint"
				attachment.Parent = openRoot
				local emitter = Instance.new("ParticleEmitter")
				emitter.Name = "GoblinChestVFX"
				emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
				emitter.Lifetime = NumberRange.new(0.4, 0.8)
				emitter.Speed = NumberRange.new(4, 8)
				emitter.SpreadAngle = Vector2.new(180, 180)
				emitter.Rate = 0
				emitter.Parent = attachment
				table.insert(emitters, emitter)
			end
			for _, emitter in emitters do
				emitter.Color = colorSequence(chestColor)
				emitter:Emit(24)
			end
			local flash = Instance.new("PointLight")
			flash.Name = "GoblinChestVFXLight"
			flash.Color = chestColor
			flash.Brightness = 4
			flash.Range = 12
			flash.Parent = openRoot
			Debris:AddItem(flash, 0.8)
			Sfx.play("ChestOpen", openRoot)
			local collected = table.create(#rewards)
			local remaining = #rewards
			local chestFinished = false
			local function collectReward(index, reward)
				collected[index] = ("<font color=\"%s\">%s</font>"):format(colorHex(reward.Color), reward.Text)
				remaining -= 1
				if remaining <= 0 and Services.NotifyService then
					Services.NotifyService:Show(player, "Goblin chest opened!\n" .. table.concat(collected, "\n"), {
						Duration = 4,
						RichText = true,
						TextColor = Color3.new(1, 1, 1),
						Icon = "Goblin",
					})
				end
				if remaining <= 0 and not chestFinished then
					chestFinished = true
					task.spawn(function()
						if open.Parent then
							animateVisualScale(open, openRoot, chestFloor, chestTarget, 1, 0.08, 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In)
							if open.Parent then open:Destroy() end
						end
					end)
				end
			end
			for index, reward in rewards do
				local offset = Vector3.new((index - (#rewards + 1) / 2) * 0.8, 0, 0)
				spawnChestLoot(player, reward.Kind, reward.GeodeType, chestFloor + offset, reward.Color, function()
					collectReward(index, reward)
				end, open)
			end
			Debris:AddItem(open, 8)
		end)
		if not ok then
			warn("[GoblinService] spawnGoblinChest reveal sequence failed:", err)
			if shakeConnection then shakeConnection:Disconnect() end
			if shake.Parent then shake:Destroy() end
			if close.Parent then close:Destroy() end
			notifyLootFallback()
		end

		-- Страховка: если функция вышла раньше времени (ранний return из-за
		-- Debris, съевшего close посреди тряски — см. комментарий про 20с
		-- ниже — или ошибка в pcall выше) с уже запущенным циклом, он не
		-- должен продолжать играть сам по себе бесконечно. В нормальном
		-- сценарии openLoopSound к этому моменту уже nil (остановлен и
		-- уничтожен явно перед close:Destroy() выше).
		if openLoopSound then
			if openLoopSound.Parent then
				openLoopSound:Stop()
				openLoopSound:Destroy()
			end
			openLoopSound = nil
		end
	end)
	-- Debris здесь — только страховка от мусора: в нормальном сценарии close
	-- уничтожает сама последовательность тряски (~2.65с). Раньше стояло 4с,
	-- а последовательность состоит из 20 tween'ов с Completed:Wait(), каждый
	-- из которых добавляет минимум кадр сверху — на просевшем сервере (10-20
	-- fps) суммарно легко выходило за 4с, Debris убивал сундук ПОСРЕДИ
	-- анимации, срабатывал `if not close.Parent then return end`, и сундук
	-- не открывался вообще: награда игроку начислялась (она выдаётся раньше,
	-- в _rewardGoblin), но визуально "дроп не выпал". Запас увеличен.
	Debris:AddItem(close, 20)
end

local function playerGoblinTier(player)
	local tiers = Services.DataService:GetTiers(player)
	return math.max(
		-- v3: пещер 15, а типы/статы гоблинов рассчитаны на 9 тиров.
		Config.NineTierForCave(tonumber(tiers.Mine) or 1),
		tonumber(tiers.Cart) or 1,
		tonumber(tiers.Pickaxe) or 1
	)
end

local function chooseGoblinType(tier)
	local available = {}
	local totalWeight = 0
	for name, definition in Config.Goblins.Types do
		-- Weight <= 0 означает "в обычных волнах не появляется" (сейчас это
		-- Golden — страж валуна). Раньше он отсекался ТОЛЬКО диапазоном
		-- тиров 11-11: если бы кто-то поднял Config.Rebirth.MaxTierCap до
		-- 11, он оказался бы единственным подходящим типом, totalWeight
		-- стал бы 0, и roll <= 0 вернул бы именно его — то есть страж
		-- полез бы в обычные волны. Явная проверка надёжнее совпадения чисел.
		if definition.Weight > 0 and tier >= definition.MinMineTier and tier <= definition.MaxMineTier then
			totalWeight += definition.Weight
			table.insert(available, {Name = name, Definition = definition})
		end
	end
	if #available == 0 then return "Warrior" end
	local roll = math.random() * totalWeight
	for _, entry in available do
		roll -= entry.Definition.Weight
		if roll <= 0 then return entry.Name end
	end
	return available[#available].Name
end

local function getRoutePosition(player, index, count)
	local plot = Services.PlotService:GetPlot(player)
	local bank = Services.WorldService:GetBankTargetPosition()
	local base = plot and plot.Pad and plot.Pad.Position
	if not base then return nil end
	local flatBase = Vector3.new(base.X, base.Y + 2, base.Z)
	local flatBank = Vector3.new(bank.X, base.Y + 2, bank.Z)
	local toBank = flatBank - flatBase
	local totalDistance = toBank.Magnitude
	local direction = totalDistance < 1 and Vector3.new(0, 0, -1) or toBank.Unit
	local side = Vector3.new(-direction.Z, 0, direction.X)
	-- БЛИЖЕ К БАНКУ, ЧЕМ К ПЛОТУ игрока — по прямому запросу. Раньше было
	-- "край пода + 25 студов" — фиксированный отступ, который почти всегда
	-- держит гоблина рядом с плотом независимо от того, насколько далеко
	-- реально банк. Теперь берём ДОЛЮ полного расстояния плот→банк (0.65 —
	-- заметно дальше середины пути), а не фиксированные студы. minDistance/
	-- maxDistance — защита от вырожденного случая (банк аномально близко к
	-- плоту): без неё math.clamp упал бы, если min оказался бы больше max.
	local minDistance = math.max(plot.Pad.Size.X, plot.Pad.Size.Z) / 2 + 10
	local maxDistance = math.max(minDistance, totalDistance - 10)
	local spawnDistance = math.clamp(totalDistance * 0.65, minDistance, maxDistance)
	return flatBase + direction * spawnDistance + side * ((index - (count + 1) / 2) * Config.Goblins.SpawnSpacing), flatBank
end

function GoblinService:_removeGoblin(player, goblin)
	local state = active[player]
	if state then
		state.Goblins[goblin] = nil
		-- ЗОЛОТОЙ СТРАЖ НЕ УЧАСТВУЕТ В ЦИКЛЕ ВОЛН. У него Objective =
		-- "Guard", то есть _finishObjective для него НИКОГДА не возвращает
		-- true — он живёт у своего валуна, пока его не убьют. Пока он
		-- лежал в этой же таблице, условие "гоблинов не осталось" не
		-- выполнялось никогда: WaveInProgress навсегда оставался true, и
		-- обычные волны у игрока переставали спавниться до перезахода.
		local hasGoblin = false
		for other in state.Goblins do
			if not other.Elite then hasGoblin = true; break end
		end
		if not hasGoblin then
			state.WaveInProgress = false
			state.NextWaveAt = os.clock() + Config.Goblins.WaveInterval
			player:SetAttribute("GoblinWaveActive", false)
		end
	end
	if goblin and goblin.Zone and goblin.Zone.Parent then goblin.Zone:Destroy() end
	if goblin and goblin.StolenCart then
		-- Раньше при смерти гоблина с тележкой она так и оставалась
		-- заанкоренной/"украденной" навсегда — никто не вызывал
		-- ReleaseGoblinCart. Теперь освобождаем её, чтобы она вернулась к
		-- нормальному поведению (можно забрать/она снова физическая).
		Services.CartService:ReleaseGoblinCart(goblin.StolenCart)
		goblin.StolenCart = nil
	end
	if goblin and goblin.Attacking then
		goblin.Attacking = false
		attackFacingGoblins[goblin] = nil
		if goblin.Humanoid then goblin.Humanoid.AutoRotate = true end
	end
	stunnedGoblins[goblin] = nil
	if goblin and goblin.ChasePathBlockedConnection then
		goblin.ChasePathBlockedConnection:Disconnect()
		goblin.ChasePathBlockedConnection = nil
	end
	-- Последний построенный маршрут тоже нужно освободить явно: chaseTo
	-- убивает только ПРЕДЫДУЩИЙ путь при пересчёте, поэтому у гоблина,
	-- который умер или был удалён, самый свежий Path остался бы висеть.
	if goblin and goblin.ChasePath then
		pcall(function() goblin.ChasePath:Destroy() end)
		goblin.ChasePath = nil
	end
	if goblin and goblin.Model and goblin.Model.Parent then goblin.Model:Destroy() end
end

function GoblinService:_applySlowdown(player, mineTier)
	local amount = math.clamp(
		Config.Goblins.SlowdownMin + (mineTier - 1) * 0.02,
		Config.Goblins.SlowdownMin,
		Config.Goblins.SlowdownMax
	)
	player:SetAttribute("GoblinMineSlowdownMultiplier", 1 - amount)
	player:SetAttribute("GoblinMineSlowdownEndsAt", os.time() + Config.Goblins.SlowdownDuration)
	task.delay(Config.Goblins.SlowdownDuration, function()
		if player.Parent and (player:GetAttribute("GoblinMineSlowdownEndsAt") or 0) <= os.time() then
			player:SetAttribute("GoblinMineSlowdownMultiplier", 1)
			player:SetAttribute("GoblinMineSlowdownEndsAt", 0)
		end
	end)
end

function GoblinService:_applyTypeSlowdown(player, goblin)
	local definition = goblin.Definition
	local amount = math.clamp(definition.Slowdown + (goblin.MineTier - definition.MinMineTier) * 0.015, Config.Goblins.SlowdownMin, Config.Goblins.SlowdownMax)
	player:SetAttribute("GoblinMineSlowdownMultiplier", 1 - amount)
	player:SetAttribute("GoblinMineSlowdownEndsAt", os.time() + definition.SlowdownDuration)
	if Services.NotifyService then
		Services.NotifyService:Show(player, ('MINE SLOWED DOWN <font color="#FFD45A">%d SECONDS</font>'):format(definition.SlowdownDuration), {
			Duration = 4,
			RichText = true,
			TextColor = Color3.fromRGB(255, 90, 90),
			Icon = "Slow",
		})
	end
	task.delay(definition.SlowdownDuration, function()
		if player.Parent and (player:GetAttribute("GoblinMineSlowdownEndsAt") or 0) <= os.time() then
			player:SetAttribute("GoblinMineSlowdownMultiplier", 1)
			player:SetAttribute("GoblinMineSlowdownEndsAt", 0)
		end
	end)
end

function GoblinService:_steal(goblin, cart)
	if goblin.Stolen or not cart or #cart.Crystals <= 0 or goblin.Definition.StealCount <= 0 then return false end
	goblin.Stolen = true
	local tierProgress = goblin.MineTier - goblin.Definition.MinMineTier
	local configuredAmount = goblin.Type == "Thief"
		and math.clamp(goblin.Definition.StealCount + tierProgress, 3, 7)
		or goblin.Definition.StealCount + math.floor(tierProgress / 3)
	local amount = math.min(#cart.Crystals, math.clamp(configuredAmount, 1, Config.Goblins.MaxStealCount))
	local removed = Services.CartService:RemoveCrystals(cart, amount)
	goblin.Cargo = removed
	local hand = goblin.Model:FindFirstChild("Right Arm")
	for _, crystal in removed do
		local root = CrystalUtil.GetRoot(crystal)
		if root and root:IsA("BasePart") then
			crystal.Parent = goblin.Model
			root.CFrame = hand and hand.CFrame or goblin.Model.PrimaryPart.CFrame
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = hand or goblin.Model.PrimaryPart
			weld.Part1 = root
			weld.Parent = root
		end
	end
	-- Метрики "GoblinOreStolen" не существует ни в одном квесте
	-- (Config.Quests.Starter/Daily) — вызов RecordMetric с ней ничего не
	-- делал, только зря гонял _ensureDaily на каждую кражу. Убран. Если
	-- когда-нибудь появится квест "у тебя украли N руды" — вернуть строку
	-- сюда и завести метрику в конфиге.
	if goblin.Owner and Services.NotifyService then
		Services.NotifyService:Show(goblin.Owner, ('GOBLIN STOLE <font color="#FFD45A">%d ORE</font>!'):format(#removed), {
			Duration = 4,
			RichText = true,
			TextColor = Color3.fromRGB(255, 205, 70),
			Icon = "Stolen",
		})
	end
	return #removed > 0
end

local function isInSellZone(zone, position)
	if not zone then return false end
	local localPosition = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(localPosition.X) <= half.X + 2
		and math.abs(localPosition.Z) <= half.Z + 2
		and math.abs(localPosition.Y) <= 15
end

function GoblinService:_rewardGoblin(player, tier, position)
	-- Клампим к САМОМУ ВЫСОКОМУ описанному в конфиге тиру, а не к жёстко
	-- зашитой восьмёрке: раньше здесь стоял math.min(tier, 8), и после
	-- поднятия потолка тиров до 10 гоблины T9/T10 молча выдавали шансы
	-- уровня T8. Теперь предел берётся из самой таблицы — добавили строку в
	-- Config, и она сразу работает, без правки этого файла.
	local oddsByTier = Config.Goblins.RewardOddsByTier
	local maxOddsTier = 1
	for oddsTier in oddsByTier do
		if oddsTier > maxOddsTier then maxOddsTier = oddsTier end
	end
	local odds = oddsByTier[math.clamp(tier, 1, maxOddsTier)]
	-- Тип жеоды клампится по длине Config.Geodes.Order. Комментарий здесь
	-- устарел: типов жеод давно 10, а не 8, так что T9 даёт Quasar, а T10 —
	-- Singularity. Кламп остаётся на случай, если тир окажется выше длины
	-- Order (например, при будущем поднятии MaxTierCap без новых жеод).
	local geodeType = Config.Geodes.Order[math.min(tier, #Config.Geodes.Order)]
	local rewards = {}
	local rewardCount = math.random() < 0.12 and math.random(2, 3) or 1
	for _ = 1, rewardCount do
		local roll = math.random()
		if roll < odds.Money then
			-- v3: доля полной тележки пещеры этого тира (Config.Goblins.RewardCarts).
			local carts = Config.Goblins.RewardCarts
			local cave = Config.CaveForNineTier(tier)
			local cartValue = Config.CartValue(cave, Config.NaturalCartTierForCave(cave))
			local amount = math.max(1, math.floor(cartValue * (carts.Min + math.random() * (carts.Max - carts.Min)) + 0.5))
			-- suppressCoinBurst=true: монетка уже показывается ЧЕРЕЗ сундук
			-- (spawnChestLoot), когда тот открывается — без этого флага
			-- общая монетная вспышка выскакивала сразу через 0.25с после
			-- смерти гоблина, ЗАДОЛГО до того, как сундук вообще открывается
			-- (~3 секунды тряски), и выглядело так, будто награда выпадает
			-- раньше самого сундука.
			Services.DataService:AddMoney(player, amount, position, true)
			table.insert(rewards, { Kind = "Money", Text = "MONEY: $" .. NumberFormat.abbreviate(amount), Color = Config.CoinFx.CoinColor })
		elseif roll < odds.Money + odds.Geode then
			local geodeGranted, geodeStatus = Services.GeodeService:AddGeodeDirectly(player, geodeType)
			if geodeGranted or geodeStatus == "Pending" then
				table.insert(rewards, { Kind = "Geode", GeodeType = geodeType, Text = ("GEODE: %s"):format(geodeType), Color = Config.Geodes.Types[geodeType].Color })
			else
				local fallbackCave = Config.CaveForNineTier(tier)
				local amount = math.max(1, math.floor(Config.CartValue(fallbackCave, Config.NaturalCartTierForCave(fallbackCave)) * Config.Goblins.RewardCarts.Fallback + 0.5))
				Services.DataService:AddMoney(player, amount, position, true)
				table.insert(rewards, { Kind = "Money", Text = "MONEY: $" .. NumberFormat.abbreviate(amount), Color = Config.CoinFx.CoinColor })
			end
		else
			-- v18: скины — только из сундуков; вместо скина гоблин роняет Rare-сундук.
			if Services.GearService then
				Services.GearService:GrantChest(player, "Rare", 1, true)
				table.insert(rewards, { Kind = "Skin", Text = "RARE CHEST", Color = Config.Chests.Types.Rare.Color })
			else
				local fallbackCave = Config.CaveForNineTier(tier)
				local amount = math.max(1, math.floor(Config.CartValue(fallbackCave, Config.NaturalCartTierForCave(fallbackCave)) * Config.Goblins.RewardCarts.Fallback + 0.5))
				Services.DataService:AddMoney(player, amount, position, true) -- см. комментарий выше
				table.insert(rewards, { Kind = "Money", Text = "MONEY: $" .. NumberFormat.abbreviate(amount), Color = Config.CoinFx.CoinColor })
			end
		end
	end
	-- spawnGoblinChest ЙИЛДИТ (~0.45с на анимацию появления сундука), а
	-- вызывается он из обработчика Humanoid.Died. Раньше это блокировало
	-- обработку смерти: труп гоблина висел лишний момент, а для элитного
	-- гоблина с несколькими участниками задержка умножалась на их число
	-- (каждому участнику по 0.45с подряд). Награды уже начислены выше —
	-- визуал сундука ждать незачем, уводим его в отдельный поток.
	task.spawn(function()
		local spawnOk, spawnErr = pcall(spawnGoblinChest, player, rewards, position)
		if not spawnOk then
			warn(("[GoblinDrop] Не удалось создать сундук для %s: %s"):format(player.Name, tostring(spawnErr)))
			if Services.NotifyService then
				Services.NotifyService:Show(player, "Goblin reward collected", {
					Duration = 4,
					TextColor = Color3.fromRGB(255, 190, 55),
					Icon = "Goblin",
				})
			end
		end
	end)
end

function GoblinService:_finishObjective(player, goblin, bankPosition)
	if goblin.Definition.Objective == "Cart" and not goblin.Stolen then
		local cart = Services.CartService:GetHeldCart(player) or Services.CartService:GetOwnedCart(player)
		if cart and cart.Root and cart.HolderUserId == nil then
			-- Тележку уже тащит ДРУГОЙ гоблин — эту у него не отобрать
			-- (CartService:GoblinStealCart и так это гарантирует на своём
			-- уровне), но раньше при таком раскладе гоблин просто стоял у
			-- ZoneCenter и ничего не делал. Теперь всё равно подходит к
			-- тележке и, если в ней осталась руда, утаскивает её напрямую
			-- через _steal — то же самое, что уже умеют гоблины без
			-- CanStealCart.
			local contested = goblin.Definition.CanStealCart and cart.GoblinStolen and cart.GoblinCarrier ~= goblin
			setIntent(goblin, "Cart")
			moveGoblin(player, goblin, cart.Root.Position)
			if (cart.Root.Position - goblin.Model.PrimaryPart.Position).Magnitude <= Config.Goblins.ObjectiveInteractRadius then
				-- ОДИН РАЗ НА ГОБЛИНА. Раньше _applyTypeSlowdown вызывался
				-- БЕЗУСЛОВНО на КАЖДОМ тике, пока гоблин стоит рядом с
				-- тележкой — а ниже, в contested-ветке, при неудачном
				-- _steal гоблин не считался "разобравшимся" с целью и на
				-- следующем тике снова оказывался в радиусе. Итог — один
				-- застрявший (contested) гоблин мог бесконечно
				-- переприменять замедление шахты и спамить один и тот же
				-- тост "MINE SLOWED DOWN N SECONDS" каждые ~0.35с. Каждый
				-- гоблин теперь может задеть шахту замедлением РОВНО один
				-- раз за свою жизнь — как и Mine-objective ниже (там это
				-- уже было гарантировано неявно: гоблин удаляется сразу
				-- же после применения).
				if not goblin.SlowdownApplied then
					self:_applyTypeSlowdown(player, goblin)
					goblin.SlowdownApplied = true
				end
				if contested then
					if not self:_steal(goblin, cart) then
						-- Тележка занята и руды в ней уже нет — отступаем
						-- в зону и пробуем ещё раз на следующих тиках, НО
						-- НЕ БЕСКОНЕЧНО: раньше предела попыток не было, и
						-- гоблин мог вечно бегать к тележке и обратно, ни
						-- разу не "сдавшись" (goblin.Stolen так и
						-- оставался false) — это и есть тот самый
						-- бесконечный набег. После
						-- MaxContestedStealAttempts попыток гоблин сдаётся
						-- ровно как в обычном (не contested) провале ниже.
						goblin.ContestedStealAttempts = (goblin.ContestedStealAttempts or 0) + 1
						if goblin.ContestedStealAttempts >= (tonumber(Config.Goblins.MaxContestedStealAttempts) or 3) then
							goblin.Stolen = true
							goblin.Cargo = {}
						else
							moveGoblin(player, goblin, goblin.ZoneCenter)
						end
					end
				elseif goblin.Definition.CanStealCart then
					goblin.Stolen = Services.CartService:GoblinStealCart(cart, goblin)
					goblin.StolenCart = goblin.Stolen and cart or nil
					if goblin.Stolen then
						if goblin.Humanoid and goblin.BaseWalkSpeed then
							goblin.Humanoid.WalkSpeed = goblin.BaseWalkSpeed * Config.Goblins.CartCarrySlowdownMultiplier
						end
						if Services.NotifyService then
							Services.NotifyService:Show(player, "GOBLIN STOLE <font color=\"#FF5A5A\">YOUR CART</font>!", {
								Duration = 4,
								RichText = true,
								TextColor = Color3.fromRGB(255, 90, 90),
								Icon = "Stolen",
							})
						end
					end
				elseif not self:_steal(goblin, cart) then
					goblin.Stolen = true
					goblin.Cargo = {}
				end
			end
		end
	elseif goblin.Definition.Objective == "Mine" then
		local plot = Services.PlotService:GetPlot(player)
		local minePosition = plot and plot.MineZonePosition
		if minePosition then
			setIntent(goblin, "Mine")
			moveGoblin(player, goblin, minePosition)
			if (minePosition - goblin.Model.PrimaryPart.Position).Magnitude <= 8 then
				if not goblin.SlowdownApplied then
					self:_applyTypeSlowdown(player, goblin)
					goblin.SlowdownApplied = true
				end
				self:_removeGoblin(player, goblin)
				return true
			end
		end
	elseif goblin.Definition.Objective == "Guard" then
		-- Страж (золотой гоблин): никакой добычи и никакого банка. Победив
		-- игрока, он просто возвращается к своему валуну и патрулирует рядом,
		-- ожидая следующего. Никогда не возвращает true — задача стража не
		-- "выполняется", он живёт до тех пор, пока его не убьют.
		local root = goblin.Model.PrimaryPart
		local distanceHome = root and (Vector3.new(goblin.ZoneCenter.X, root.Position.Y, goblin.ZoneCenter.Z) - root.Position).Magnitude or 0
		if distanceHome > (Config.Goblins.WanderRadius > 0 and Config.Goblins.WanderRadius or 8) then
			-- Домой — без смещения строя: страж один, расходиться не с кем,
			-- а смещение только уводило бы точку возврата в сторону.
			setIntent(goblin, "GuardReturn")
			chaseTo(goblin, goblin.ZoneCenter, 3, false)
		else
			setIntent(goblin, "Wander")
			wander(goblin)
		end
		return false
	end
	if goblin.Stolen then
			local sellZone = Services.WorldService:GetSellZone()
			if isInSellZone(sellZone, goblin.StolenCart and goblin.StolenCart.Root.Position or goblin.Model.PrimaryPart.Position) then
				for _, crystal in goblin.Cargo or {} do crystal:Destroy() end
				if goblin.StolenCart then
				Services.CartService:RespawnAfterGoblinSteal(goblin.StolenCart)
				goblin.StolenCart = nil
			end
			self:_removeGoblin(player, goblin)
			return true
		end
		-- Дорога до банка строится ЧЕРЕЗ PathfindingService (chaseTo), а не
		-- прямым MoveTo. Банк почти всегда далеко и не на прямой видимости от
		-- места кражи, а гоблин тащит за собой тележку — на голом MoveTo он
		-- утыкался в первое же препятствие и толкал в него тележку. chaseTo
		-- сам строит обход, перестраивает маршрут при блокировке и прыгает
		-- через бортики.
		-- Дорога до банка строится ЧЕРЕЗ маршрут (chaseTo), а не прямым
		-- движением: банк почти всегда далеко и не на прямой видимости от
		-- места кражи, а гоблин тащит за собой тележку. Радиус прибытия
		-- здесь щедрый (4) — тележка широкая, утыкать её ровно в точку не
		-- нужно, до зоны продажи её донесёт проверка isInSellZone выше.
		setIntent(goblin, "Bank")
		-- ЦЕЛЬЮ СЧИТАЕТСЯ ПОЛОЖЕНИЕ ТЕЛЕЖКИ, А НЕ САМОГО ГОБЛИНА.
		--
		-- Продажу засчитывает isInSellZone выше, и проверяет она позицию
		-- УКРАДЕННОЙ ТЕЛЕЖКИ — а тележка волочится ЗА гоблином, отставая на
		-- несколько студов. Гоблин, доехавший ровно до точки банка,
		-- останавливался, а тележка в этот момент оставалась снаружи зоны:
		-- условие продажи не выполнялось никогда, гоблин стоял у банка с
		-- добычей до самой смерти. Со стороны — «дошёл и не знает, что
		-- делать дальше».
		--
		-- Лечим двумя штрихами: пока тележка не в зоне, целимся дальше
		-- точки банка ровно на длину отставания тележки, и радиус прибытия
		-- держим маленьким. Гоблин заезжает чуть глубже — тележка входит в
		-- зону — продажа засчитывается.
		local carriedRoot = goblin.StolenCart and goblin.StolenCart.Root
		local deliverTarget = bankPosition
		local arrival = 4
		if carriedRoot then
			local lag = (carriedRoot.Position - goblin.Model.PrimaryPart.Position).Magnitude
			if lag > 1 then
				local toBank = bankPosition - carriedRoot.Position
				local horizontal = Vector3.new(toBank.X, 0, toBank.Z)
				if horizontal.Magnitude > 0.05 then
					deliverTarget = bankPosition + horizontal.Unit * math.min(lag, 10)
				end
			end
			arrival = 1.5
		end
		chaseTo(goblin, deliverTarget, arrival, true)
	end
	return false
end

-- LOD ДЛЯ ТИКА AI (см. комментарий в конце _tickGoblin).
-- ACTIVE_TICK_INTERVAL — прежние 0.35с, с которыми работает гоблин в бою,
-- в погоне, при отходе и при доставке добычи. IDLE_TICK_INTERVAL — редкий
-- тик для гоблина, который просто патрулирует свою зону и вокруг которого
-- на IDLE_LOD_RADIUS студов нет ни одного игрока.
local ACTIVE_TICK_INTERVAL = 0.35
local IDLE_TICK_INTERVAL = 1.0
local AI_SCHEDULER_INTERVAL = 0.1
local AI_MAX_UPDATES_PER_STEP = 12
-- 70 студов при IDLE_TICK_INTERVAL = 1.0 даёт большой запас: даже спринтом
-- игрок проходит за секунду ~30 студов, то есть подойти на AttackRadius (30)
-- между двумя редкими тиками физически невозможно — гоблин успеет
-- переключиться на активный тик раньше, чем игрок окажется в радиусе атаки.
local IDLE_LOD_RADIUS = 70

local function nearestPlayerDistance(position)
	local best = math.huge
	for _, candidate in Players:GetPlayers() do
		local character = candidate.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			local distance = (root.Position - position).Magnitude
			if distance < best then best = distance end
		end
	end
	return best
end

-- Элитный (золотой) гоблин — общий PvP-моб, не привязанный к одному игроку
-- (в отличие от обычных гоблинов с приватной зоной на игрока). Раньше бой
-- проверял ТОЛЬКО character того игрока, который разбил валун — если этот
-- игрок отходил или был не рядом, гоблин полностью игнорировал всех
-- остальных, даже стоящих вплотную ("не реагирует на игрока рядом").
-- Теперь ищем ближайшего живого игрока в радиусе атаки — любого.
local function findNearestPlayerInRange(goblin)
	local primaryPart = goblin.Model.PrimaryPart
	if not primaryPart then return nil end
	local best, bestDistance = nil, Config.Goblins.AttackRadius
	for _, candidate in Players:GetPlayers() do
		local character = candidate.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		-- Щит: не выбираем защищённого игрока целью вообще — предпочитаем
		-- ближайшего АТАКУЕМОГО игрока, а не просто "ближайшего живого".
		if root and humanoid and humanoid.Health > 0 and candidate:GetAttribute("Protected") ~= true then
			local dist = (root.Position - primaryPart.Position).Magnitude
			if dist < bestDistance then
				best, bestDistance = candidate, dist
			end
		end
	end
	return best
end

function GoblinService:_tickGoblin(player, goblin, bankPosition)
	if not (player and player.Parent and goblin and goblin.Model and goblin.Model.Parent) or goblin.Dead then
		return false
	end
	if os.clock() < (goblin.StunnedUntil or 0) then
		goblin.Humanoid:Move(Vector3.zero)
		goblin.Model:SetAttribute("GoblinMoving", false)
		return false
	end
	local finished
	local ok, err = pcall(function()
			-- LOD: по умолчанию считаем тик "активным". Флаг взводится в
			-- true ЕДИНСТВЕННОЙ веткой — блужданием по своей зоне. Любой
			-- ранний return (атака, отход, возврат к зоне по поводку,
			-- доставка добычи) оставляет его false, то есть быстрый тик.
			-- Так безопаснее: забыть сбросить флаг в новой ветке нельзя.
			goblin.IdleTick = false
			-- Элитный (золотой) гоблин ищет ближайшего игрока в радиусе
			-- динамически (см. findNearestPlayerInRange) — обычные гоблины
			-- по-прежнему привязаны к своему единственному игроку (у каждого
			-- своя приватная зона, менять этот аспект не нужно).
			local targetPlayer = player
			if goblin.Elite then
				targetPlayer = findNearestPlayerInRange(goblin) or goblin.LastEliteTarget or player
				goblin.LastEliteTarget = targetPlayer
			end
			local character = targetPlayer.Character
			local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
			local playerHumanoid = character and character:FindFirstChildOfClass("Humanoid")
			local playerAlive = playerHumanoid and playerHumanoid.Health > 0
			-- ЩИТ: пока у targetPlayer висит защита (тот же "Protected",
			-- что CombatService выставляет для PvP), гоблины должны вести
			-- себя так, будто игрока тут вообще нет — не гнаться, не бить.
			-- Ниже это подмешано в условие погони/атаки, а не отдельным
			-- ранним return, чтобы естественно провалиться в уже готовую
			-- ветку "цели нет" (wander/донести добычу в банк, если несли).
			local playerProtected = targetPlayer:GetAttribute("Protected") == true
			if goblin.Attacking then
				-- During windup and recovery the NPC owns its facing and does not
				-- accept a new chase/retreat command. This prevents the attack
				-- animation from being interrupted by the AI tick.
				goblin.Humanoid:Move(Vector3.zero)
				faceGoblinTarget(goblin, goblin.AttackTargetRoot)
				return
			end
			if goblin.RetreatTarget then
				local root = goblin.Model.PrimaryPart
				-- КРИТИЧНО: сравнивать нужно с ТОЙ ЖЕ точкой, куда реально
				-- едет chaseTo, а он идёт не в RetreatTarget, а в
				-- separatedTarget(RetreatTarget) — со смещением на слот
				-- построения (FormationRadius). Раньше здесь мерилось
				-- расстояние до "чистого" RetreatTarget с порогом 2, а
				-- FormationRadius при волне из 2+ гоблинов равен 2.6–4.25 —
				-- то есть гоблин доезжал до своей точки строя и навсегда
				-- оставался на расстоянии ~3 от RetreatTarget, условие
				-- "retreatDistance > 2" не размыкалось НИКОГДА, и он
				-- застревал в ветке отступления после ПЕРВОГО же удара:
				-- не атаковал, не блуждал, только дёргался у точки отхода.
				-- Это и есть баг "ударяет один раз и начинает ходить
				-- туда-сюда".
				local retreatDestination = separatedTarget(player, goblin, goblin.RetreatTarget)
				local retreatDistance = (Vector3.new(retreatDestination.X, root.Position.Y, retreatDestination.Z) - root.Position).Magnitude
				-- Плюс жёсткий предохранитель по времени: отход в любом
				-- случае длится не дольше RetreatUntil (= StealCooldown).
				-- Даже если до точки отхода физически не дойти (застряли,
				-- точка в стене, столкнули игроком) — гоблин обязан выйти
				-- из отступления и вернуться в бой, а не залипнуть навсегда.
				local retreatExpired = os.clock() >= (goblin.RetreatUntil or 0)
				if retreatDistance > 2.5 and not retreatExpired then
					setIntent(goblin, "Retreat")
					chaseTo(goblin, goblin.RetreatTarget, 2.5, true)
					return
				end
				goblin.Model:SetAttribute("GoblinMoving", false)
				goblin.Humanoid:Move(Vector3.zero)
				goblin.RetreatTarget = nil
				if not retreatExpired then return end
				goblin.RetreatUntil = nil
			end

			if goblin.PlayerDefeated and playerAlive and playerRoot
				and (playerRoot.Position - goblin.Model.PrimaryPart.Position).Magnitude <= Config.Goblins.PlayerAttackRadius then
				-- Игрок respawn'ился (или был жив всё это время) и подошёл
				-- вплотную к гоблину, который уже был "победителем" (нёс
				-- тележку/копал руду) — возвращаемся в бой. Сам бросок
				-- тележки происходит в Damage() в момент реального попадания
				-- удара; здесь только включаем реакцию на близость игрока.
				goblin.PlayerDefeated = false
			end

			if goblin.PlayerDefeated then
				if self:_finishObjective(player, goblin, bankPosition) then
					finished = true
				end
			else
				-- ВАЖНО: расстояние до игрока должно считаться от текущей
				-- позиции гоблина, а не от ZoneCenter (точки спавна). Раньше
				-- тут мерилось (playerRoot - ZoneCenter) — стоило гоблина
				-- утащить погоней/отступлением от точки спавна хоть немного
				-- дальше AttackRadius, и игрок, стоящий вплотную к самому
				-- гоблину, переставал засчитываться как "в радиусе". Гоблин
				-- в этот момент падал в ветку wander() и просто патрулировал
				-- мимо игрока, не атакуя — это и есть баг "подхожу — бегают
				-- туда-сюда, но не бьют".
				local primaryPart = goblin.Model.PrimaryPart
				local distance = playerRoot and primaryPart and (playerRoot.Position - primaryPart.Position).Magnitude

				-- ПОВОДОК. Агро считается от позиции самого гоблина, поэтому
				-- без ограничителя игрок мог бесконечно уводить его за собой:
				-- гоблин всегда оставался в пределах AttackRadius от игрока и
				-- бежал хоть на другой конец карты, навсегда покидая зону.
				-- Считаем удаление от ZoneCenter и, перевалив за LeashRadius,
				-- принудительно отправляем домой, игнорируя игроков, пока не
				-- вернётся ближе LeashReturnRadius (гистерезис — иначе на
				-- самой границе он бы дёргался между погоней и возвратом).
				-- Золотому гоблину поводок короче: он страж своего валуна.
				local leashRadius = goblin.Elite and Config.Goblins.EliteLeashRadius or Config.Goblins.LeashRadius
				local leashReturnRadius = goblin.Elite and Config.Goblins.EliteLeashReturnRadius or Config.Goblins.LeashReturnRadius
				local homeDistance = primaryPart
					and (Vector3.new(goblin.ZoneCenter.X, primaryPart.Position.Y, goblin.ZoneCenter.Z) - primaryPart.Position).Magnitude
					or 0
				if homeDistance > leashRadius then
					goblin.ReturningHome = true
				elseif goblin.ReturningHome and homeDistance <= leashReturnRadius then
					goblin.ReturningHome = false
				end
				if goblin.ReturningHome then
					goblin.TargetedPlayer = false
					goblin.RetreatTarget = nil
					goblin.RetreatUntil = nil
					setIntent(goblin, "Leash")
					chaseTo(goblin, goblin.ZoneCenter, 3, false)
					return
				end

				if playerHumanoid and not playerAlive and goblin.TargetedPlayer then
					goblin.PlayerDefeated = true
					goblin.EverDefeatedPlayer = true
				elseif playerRoot and playerAlive and not playerProtected and distance and distance <= Config.Goblins.AttackRadius then
					goblin.TargetedPlayer = true
					local primaryPos = goblin.Model.PrimaryPart.Position
					local distanceToPlayer = (playerRoot.Position - primaryPos).Magnitude
					local now = os.clock()
					if distanceToPlayer <= Config.Goblins.PlayerAttackRadius and now >= (goblin.NextAttackAt or 0) then
						goblin.NextAttackAt = now + Config.Goblins.StealCooldown
						beginGoblinAttack(goblin, playerHumanoid, playerRoot)
					else
						-- Погоня через PathfindingService (с прыжками через
						-- препятствия) вместо голого MoveTo — раньше гоблин
						-- мог застрять у препятствия и просто "стоять и
						-- думать" вместо подхода вплотную, отсюда и промахи.
						-- Радиус прибытия чуть меньше радиуса удара, чтобы
						-- гоблин гарантированно вставал В зоне атаки, а не
						-- ровно на её границе, где следующий шаг игрока
						-- снова выбивает его из радиуса.
						setIntent(goblin, "Chase")
						chaseTo(goblin, playerRoot.Position, math.max(2, Config.Goblins.PlayerAttackRadius - 1), true)
					end
				else
					goblin.TargetedPlayer = false
					goblin.RetreatUntil = nil
					goblin.ChaseWaypoints = nil
					if goblin.EverDefeatedPlayer then
						-- Игрок отступил/не подошёл, а гоблин уже побеждал
						-- его раньше (и, возможно, нёс тележку/копал руду до
						-- прерывания боем) — продолжаем нести добычу в банк
						-- вместо блуждания.
						goblin.PlayerDefeated = true
					else
						goblin.IdleTick = true
						setIntent(goblin, "Wander")
						wander(goblin)
					end
				end
			end
	end)
	if not ok then
		warn("[GoblinService] _tickGoblin failed:", err)
		goblin.NextAiTick = os.clock() + ACTIVE_TICK_INTERVAL
		return false
	end
	if finished then return true end
		-- ПРОИЗВОДИТЕЛЬНОСТЬ, УРОВЕНЬ 1: РЕДКИЙ ТИК ДЛЯ ДАЛЁКИХ ГОБЛИНОВ.
		-- Гоблин, который только патрулирует и вокруг которого на
		-- IDLE_LOD_RADIUS нет ни одного игрока, тикает втрое реже. Как
		-- только рядом появляется кто угодно (или гоблин входит в любую
		-- активную ветку) — интервал сразу возвращается к 0.35с.
		--
		-- УРОВЕНЬ 2 живёт в новом ядре навигации (см. steerTowards): там
		-- рейкасты вперёд делаются НЕ каждый тик, а только когда гоблин
		-- перестал приближаться к цели. Раньше два рейкаста уходили на
		-- КАЖДЫЙ тик КАЖДОГО гоблина независимо от обстановки — при полном
		-- сервере это были сотни рейкастов в секунду, почти все впустую, на
		-- пустой дороге. Плюс сам объект RaycastParams больше не
		-- аллоцируется на каждый вызов, а Path переиспользуется вместо
		-- пересоздания на каждый пересчёт маршрута.
	local interval = ACTIVE_TICK_INTERVAL
	if goblin.IdleTick and not goblin.StolenCart and not goblin.Attacking then
		local root = goblin.Model.PrimaryPart
		if root and nearestPlayerDistance(root.Position) > IDLE_LOD_RADIUS then
			interval = IDLE_TICK_INTERVAL
		end
	end
	goblin.NextAiTick = os.clock() + interval
	return false
end

function GoblinService:_startAiScheduler()
	if self._aiSchedulerStarted then return end
	self._aiSchedulerStarted = true
	task.spawn(function()
		while true do
			task.wait(AI_SCHEDULER_INTERVAL)
			local now = os.clock()
			local ok, err = pcall(function()
				local updates = 0
				for player, state in active do
					if player.Parent and state then
						for goblin in state.Goblins do
							if updates < AI_MAX_UPDATES_PER_STEP and (goblin.NextAiTick or 0) <= now then
								updates += 1
								self:_tickGoblin(player, goblin, goblin.BankPosition)
								-- Several AI branches return early (attack, retreat,
								-- leash return). They must still schedule their next tick;
								-- otherwise one stale goblin can consume the whole per-step
								-- budget forever and freeze the rest of the wave.
								if goblin.Model and goblin.Model.Parent and not goblin.Dead
									and (goblin.NextAiTick or 0) <= now then
									goblin.NextAiTick = now + ACTIVE_TICK_INTERVAL
								end
							end
						end
					end
				end
			end)
			if not ok then
				warn("[GoblinService] AI scheduler failed:", err)
			end
		end
	end)
end

function GoblinService:SpawnWave(player, count, tutorial, force)
	if not player.Parent then return end
	local state = active[player]
	if not state or (state.WaveInProgress and not force) then return end
	-- v8: дорожные волны выключены — гоблины живут только в лагере рейда
	-- (Config.GoblinRaid). Обучающая волна у слайма остаётся для гайда.
	if Config.GoblinRaid and Config.GoblinRaid.Enabled and Config.GoblinRaid.DisableRoadWaves and not tutorial then
		state.NextWaveAt = os.clock() + (Config.Goblins.WaveInterval or 120)
		return
	end
	state.WaveInProgress = true
	if Services.TutorialService then
		pcall(function() Services.TutorialService:ShowHint(player, "FirstGoblin") end)
	end
	-- Сложность обычной волны зависит от самой развитой ветки игрока:
	-- прокачанная кирка/тележка тоже означает, что игрок уже готов к более
	-- сильным гоблинам. Золотой гоблин из валуна получает тир отдельно ниже.
	local tier = playerGoblinTier(player)
	local folder = workspace:FindFirstChild("Goblins") or Instance.new("Folder")
	folder.Name = "Goblins"
	folder.Parent = workspace
	count = math.clamp(math.floor(tonumber(count) or 1), 1, tutorial and Config.Goblins.TutorialWaveCount or 4)
	for index = 1, count do
		local position, bankPosition = getRoutePosition(player, index, count)
		if position then
			local goblinType = tutorial and "Warrior" or chooseGoblinType(tier)
			local definition = Config.Goblins.Types[goblinType]
			local model, zone = createR6Placeholder(position, tier, bankPosition, goblinType)
			model.Parent = folder
			Sfx.play("GoblinSpawn", model)
			local humanoidRef = model:FindFirstChildOfClass("Humanoid")
			local goblin = {Model = model, Zone = zone, Humanoid = humanoidRef, MineTier = tier, Owner = player, Stolen = false, Dead = false, Definition = definition, Type = goblinType, BaseWalkSpeed = humanoidRef and humanoidRef.WalkSpeed, BankPosition = bankPosition, NextAiTick = os.clock() + (index - 1) * 0.04}
			goblin.FormationRadius = count > 1 and math.min(4.5, 1.5 + count * 0.55) or 0
			goblin.FormationAngle = count > 1 and ((index - 1) / count) * math.pi * 2 or 0
			goblin.ZoneCenter = position
			state.Goblins[goblin] = true
			-- Config.Goblins.WaveLifetime до этого НИГДЕ не читался — поле
			-- было мёртвым, гоблины жили вечно. Теперь оно работает:
			-- 0 = выключено (прежнее поведение), >0 = через столько секунд
			-- недобитый гоблин уходит сам. Проверка Stolen обязательна —
			-- иначе гоблин испарится вместе с украденной тележкой на
			-- полпути к банку, и она останется висеть "ничьей".
			local lifetime = tonumber(Config.Goblins.WaveLifetime) or 0
			if lifetime > 0 then
				task.delay(lifetime, function()
					if goblin.Dead or goblin.Stolen or not goblin.Model.Parent then return end
					goblin.Model:Destroy()
					self:_removeGoblin(player, goblin)
				end)
			end
			-- Automatic ownership lets the nearest client render the physical
			-- humanoid smoothly; combat decisions remain server-authoritative.
			pcall(function() model.PrimaryPart:SetNetworkOwner(nil) end)
			model:SetAttribute("GoblinAttacking", false)
			model:SetAttribute("GoblinMoving", false)
			goblin.Humanoid.Died:Connect(function()
				if goblin.Dead then return end
				goblin.Dead = true
				Sfx.play(tutorial and "TutorialGoblinDefeated" or "GoblinDeath", model)
				if Services.MutationBookService then
					Services.MutationBookService:RecordMobFound(player, goblin.Type)
				end
				if goblin.StolenCart then
					Services.CartService:ReleaseGoblinCart(goblin.StolenCart)
					goblin.StolenCart = nil
				end
				if tutorial and player:GetAttribute("NeedsTutorial") == true then
					player:SetAttribute("TutorialGoblinKilled", true)
				end
				local rewardOk, rewardErr = pcall(function()
					self:_rewardGoblin(player, tier, model.PrimaryPart.Position)
				end)
				if not rewardOk then
					warn("[GoblinService] _rewardGoblin failed:", rewardErr)
				end
				task.delay(0.25, function() self:_removeGoblin(player, goblin) end)
			end)
		end
	end
	player:SetAttribute("GoblinWaveActive", true)
	player:SetAttribute("GoblinWaveTutorial", tutorial == true)
	if Services.NotifyService then
		Services.NotifyService:Show(player, tutorial and "A goblin appeared near your base — protect your cart!" or "Goblins appeared near your base — protect your cart!", { Icon = "Goblin" })
	end
	Sfx.play("GoblinWaveWarning", folder:FindFirstChildWhichIsA("Model"))
end

function GoblinService:FindInHitbox(player, hrp, hitboxSize, forwardOffset)
	local state = active[player]
	if not state then return nil end
	local half = hitboxSize / 2
	local centerZ = -forwardOffset
	local best, distance = nil, math.huge
	local function consider(goblin)
		if not goblin.Dead and goblin.Model.PrimaryPart then
			local localPosition = hrp.CFrame:PointToObjectSpace(goblin.Model.PrimaryPart.Position)
			if math.abs(localPosition.X) <= half.X and math.abs(localPosition.Y) <= half.Y
				and localPosition.Z >= centerZ - half.Z and localPosition.Z <= centerZ + half.Z then
				local currentDistance = (goblin.Model.PrimaryPart.Position - hrp.Position).Magnitude
				if currentDistance < distance then
					best, distance = goblin, currentDistance
				end
			end
		end
	end
	for goblin in state.Goblins do consider(goblin) end
	for goblin in raidGoblins do consider(goblin) end -- v8: рейд — бить может любой
	for owner, otherState in active do
		if owner ~= player then
			for goblin in otherState.Goblins do
				if goblin.Elite then consider(goblin) end
			end
		end
	end
	if best then
		return { Goblin = best, Hrp = best.Model.PrimaryPart, Humanoid = best.Humanoid, HitPosition = best.Model.PrimaryPart.Position }
	end
end

function GoblinService:Damage(goblin, damage, attacker)
	if goblin and goblin.Humanoid and not goblin.Dead then
		-- Damage does not make the goblin drop the cart. It keeps carrying it
		-- until delivery or death, matching the requested NPC behavior.
		local healthBefore = goblin.Humanoid.Health
		goblin.Humanoid:TakeDamage(damage)
		Sfx.play("GoblinHit", goblin.Model)
		if goblin.Humanoid.Health < healthBefore then
			goblin.SuccessfulHitCount = (goblin.SuccessfulHitCount or 0) + 1
			if goblin.SuccessfulHitCount % 3 == 0 then -- было %2 — по прямому запросу стан теперь на каждый 3-й удар (3-й, 6-й, 9-й...)
				applyGoblinStun(goblin)
			end
		end
		-- "Хоть какой-то урон" элитному гоблину = участие, независимо от
		-- того, ломал ли этот игрок исходный валун — см. дизайн-документ
		-- (лут элитки не должен зависеть от того, кто разбил камень).
		if goblin.Elite and goblin.EliteParticipants and attacker then
			goblin.EliteParticipants[attacker] = true
		end
		-- v8: вклад в рейд (сундук за зачистку по доле урона).
		if goblin.Raid and attacker then
			goblin.LastAttacker = attacker
			if raidState then
				raidState.Damage[attacker] = (raidState.Damage[attacker] or 0) + math.max(0, healthBefore - goblin.Humanoid.Health)
			end
		end
		return math.max(0, healthBefore - goblin.Humanoid.Health)
	end
	return 0
end

function GoblinService:SpawnEliteForBoulder(owner, position, tier, contributors)
	local state = active[owner]
	if not state or not owner.Parent then return false end
	local bankPosition = Services.WorldService:GetBankTargetPosition()
	-- "Золотой" гоблин теперь отдельный тип в энциклопедии (Config.Goblins.
	-- Types.Golden — копия статов короля с другим именем/цветом, см.
	-- Config.lua), а не просто перекрашенный King — раньше он записывался в
	-- энциклопедию как обычный "King" (goblin.Type == "King"), и убить его
	-- было неотличимо от обычного короля для RecordMobFound. Ищет свою
	-- модель ReplicatedStorage.Assets.Goblin_Golden_1/_2/_3 (3 скина, как и
	-- у остальных типов) — имя теперь просто следует общей конвенции.
	local model, zone, usedCustomAsset = createR6Placeholder(position + Vector3.new(0, 2, 0), tier, bankPosition, "Golden")
	model.Name = "EliteBoulderGoblin"
	model:SetAttribute("GoblinAttacking", false)
	model:SetAttribute("GoblinMoving", false)
	if not usedCustomAsset then
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then part.Color = Color3.fromRGB(255, 150, 45) end
		end
	end
	local goblinsFolder = workspace:FindFirstChild("Goblins") or Instance.new("Folder")
	goblinsFolder.Name = "Goblins"
	goblinsFolder.Parent = workspace
	model.Parent = goblinsFolder
	Sfx.play("EliteGoblinSpawn", model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	-- Множитель тот же, что энциклопедия использует для строки HP золотого
	-- гоблина (GoblinStats.Health(..., elite = true)) — держим его в одном
	-- месте, чтобы книга и сервер не разошлись снова.
	local baseHealth = humanoid and humanoid.MaxHealth or 100
	if humanoid then
		humanoid.MaxHealth = baseHealth * GoblinStats.EliteHealthMultiplier
		humanoid.Health = humanoid.MaxHealth
	end
	local goblin = {
		Model = model,
		Zone = zone,
		Humanoid = humanoid,
		MineTier = tier,
		Owner = owner,
		Stolen = false,
		Dead = false,
		Definition = Config.Goblins.Types.Golden,
		Type = "Golden",
		Elite = true,
		EliteParticipants = contributors or { [owner] = true },
		ZoneCenter = position,
		BaseWalkSpeed = humanoid and humanoid.WalkSpeed,
		FormationRadius = 0,
		FormationAngle = 0,
		BankPosition = bankPosition,
		NextAiTick = os.clock() + math.random() * AI_SCHEDULER_INTERVAL,
	}
	state.Goblins[goblin] = true
	pcall(function() model.PrimaryPart:SetNetworkOwner(nil) end)
	if humanoid then
		humanoid.Died:Connect(function()
			if goblin.Dead then return end
			goblin.Dead = true
			-- Золотой гоблин заводился как ОТДЕЛЬНЫЙ тип энциклопедии именно
			-- ради того, чтобы его убийство засчитывалось отдельно от обычного
			-- короля (см. комментарий выше по SpawnEliteForBoulder), но самого
			-- вызова RecordMobFound в этой ветке не было вовсе — он есть
			-- только у обычных гоблинов в SpawnWave. Из-за этого "Golden
			-- Goblin King" не открывался в энциклопедии НИКОГДА, сколько бы
			-- его ни убивали. Засчитываем всем участникам боя — тем же, кому
			-- идёт лут.
			if goblin.StolenCart then
				-- Обычный гоблин при смерти возвращает украденную тележку
				-- (см. Died в SpawnWave); у элитного этого не было, хотя
				-- Golden.CanStealCart = true — тележка оставалась висеть
				-- "украденной". _removeGoblin ниже подстрахует, но освобождаем
				-- явно и здесь, до задержек.
				Services.CartService:ReleaseGoblinCart(goblin.StolenCart)
				goblin.StolenCart = nil
			end
			local rewardPosition = model.PrimaryPart.Position
			for participant in goblin.EliteParticipants do
				if participant.Parent then
					local participantRoot = participant.Character and participant.Character:FindFirstChild("HumanoidRootPart")
					local participantPosition = participantRoot and participantRoot.Position or rewardPosition
					if Services.MutationBookService then
						Services.MutationBookService:RecordMobFound(participant, goblin.Type)
					end
					local drops = Services.RockService:GrantBoulderRewards(participant, tier, participantPosition, true)
					self:SpawnBoulderRewardChest(participant, participantPosition, tier, drops)
				end
			end
			self:_removeGoblin(owner, goblin)
		end)
	end
	return true
end

function GoblinService:SpawnBoulderRewardChest(player, position, tier, drops)
	-- Асинхронно по той же причине, что и в _rewardGoblin: этот метод
	-- вызывается в ЦИКЛЕ по всем участникам убийства элитного гоблина, а
	-- spawnGoblinChest йилдит ~0.45с. Последовательно это откладывало
	-- сундук последнего участника на 0.45с × число участников и на столько
	-- же задерживало удаление трупа.
	task.spawn(function()
		local ok, err = pcall(function()
			local rewards = {}
			for _, text in drops or {} do
				table.insert(rewards, {
					Kind = "Boulder",
					Text = text,
					Color = Color3.fromRGB(255, 190, 65),
				})
			end
			if #rewards == 0 then
				table.insert(rewards, {
					Kind = "Boulder",
					Text = ("Elite boulder reward (tier %d)"):format(tier),
					Color = Color3.fromRGB(255, 190, 65),
				})
			end
			spawnGoblinChest(player, rewards, position)
		end)
		if not ok then warn("[GoblinService] Elite boulder chest failed:", err) end
	end)
end

--------------------------------------------------------------------------------
-- v8 — ГОБЛИНСКИЙ РЕЙД (Config.GoblinRaid). Гоблины живут ТОЛЬКО в зоне
-- Workspace/GoblinCamp/Zone: бродят, бьют игроков, оказавшихся внутри, и
-- никогда её не покидают (все точки движения прижимаются к границам зоны).
-- Раз в IntervalSeconds — рейд случайного типа; лут с каждого гоблина
-- последнему ударившему, за зачистку — сундук по доле урона.
--------------------------------------------------------------------------------
local RAID_MODEL_BY_TYPE = { Thieves = "Thief", Brutes = "Berserker", Shamans = "Warrior", Bombers = "Warrior", Golden = "Golden" }

local function raidCamp()
	local camp = workspace:FindFirstChild("GoblinCamp")
	local zone = camp and camp:FindFirstChild("Zone")
	if not (zone and zone:IsA("BasePart")) then return nil end
	local spawns = {}
	local folder = camp:FindFirstChild("Spawns")
	for _, point in folder and folder:GetChildren() or {} do
		if point:IsA("BasePart") then table.insert(spawns, point) end
	end
	if #spawns == 0 then table.insert(spawns, zone) end
	return zone, spawns
end

local function insideZone(zone, position, margin)
	local localPoint = zone.CFrame:PointToObjectSpace(position)
	margin = margin or 0
	return math.abs(localPoint.X) <= zone.Size.X / 2 + margin and math.abs(localPoint.Z) <= zone.Size.Z / 2 + margin
		and math.abs(localPoint.Y) <= zone.Size.Y / 2 + 12
end

-- Точку прижимаем к границам зоны (гоблин НЕ выйдет наружу).
local function clampToZone(zone, position)
	local localPoint = zone.CFrame:PointToObjectSpace(position)
	local halfX, halfZ = zone.Size.X / 2 - 2, zone.Size.Z / 2 - 2
	local clamped = Vector3.new(math.clamp(localPoint.X, -halfX, halfX), localPoint.Y, math.clamp(localPoint.Z, -halfZ, halfZ))
	return zone.CFrame:PointToWorldSpace(clamped)
end

local function raidTier()
	local total, count = 0, 0
	for _, player in Players:GetPlayers() do
		local mine = tonumber(player:GetAttribute("MineTier"))
		if mine then total += mine; count += 1 end
	end
	local cave = count > 0 and total / count or 1
	return math.clamp(math.ceil(cave * 10 / 15), 1, 10)
end

local function pickRaidType()
	local total = 0
	for _, info in Config.GoblinRaid.Types do total += info.Weight or 1 end
	local roll = math.random() * total
	for _, info in Config.GoblinRaid.Types do
		roll -= info.Weight or 1
		if roll <= 0 then return info end
	end
	return Config.GoblinRaid.Types[1]
end

local function announceAll(text, color)
	if not Services.NotifyService then return end
	for _, player in Players:GetPlayers() do
		Services.NotifyService:Show(player, text, { Icon = "Goblin", Duration = 5, TextColor = color })
	end
end

function GoblinService:_rewardRaidKill(goblin)
	local player = goblin.LastAttacker
	if not (player and player.Parent) or goblin.Exploded then return end
	local cfg = Config.GoblinRaid.LootPerGoblin
	local tiers = Services.DataService:GetTiers(player)
	local carts = cfg.MoneyCarts[1] + math.random() * (cfg.MoneyCarts[2] - cfg.MoneyCarts[1])
	local mult = goblin.RaidInfo and goblin.RaidInfo.Boss and 6 or 1
	local amount = math.max(1, math.floor(Config.CartValue(tiers.Mine, tiers.Cart) * carts * mult))
	local position = goblin.Model.PrimaryPart and goblin.Model.PrimaryPart.Position
	Services.DataService:AddMoney(player, amount, position, true)
	if position then self:SpawnLooseReward(player, "Money", nil, position, Config.CoinFx and Config.CoinFx.CoinColor or Color3.fromRGB(255, 215, 80)) end
	if Services.GearService and math.random() < (cfg.DynamiteChance or 0) then
		Services.GearService:AddGear(player, "Dynamite", 1)
	end
end

function GoblinService:_finishRaid(cleared)
	local state = raidState
	if not state then return end
	raidState = nil
	workspace:SetAttribute("GoblinRaidActive", false)
	for goblin in raidGoblins do
		if goblin.Model and goblin.Model.Parent then goblin.Model:Destroy() end
		goblin.Dead = true
	end
	table.clear(raidGoblins)
	if not cleared then
		announceAll("The goblins retreated into their camp…", Color3.fromRGB(200, 200, 210))
		return
	end
	local total = 0
	for _, dealt in state.Damage do total += dealt end
	if total <= 0 then return end
	local top, topDamage = nil, 0
	for player, dealt in state.Damage do
		if dealt > topDamage then top, topDamage = player, dealt end
	end
	for player, dealt in state.Damage do
		if player.Parent and Services.GearService then
			local share = dealt / total
			local chest = nil
			if state.Boss and player == top then
				chest = Config.GoblinRaid.BossClearChest
			else
				for _, row in Config.GoblinRaid.ClearChest do
					if share >= row.MinShare then chest = row.Chest; break end
				end
			end
			if chest then Services.GearService:GrantChest(player, chest, 1) end
		end
	end
	announceAll(("%s cleared! Chests for everyone who fought."):format(state.Type.Title), Color3.fromRGB(120, 255, 150))
end

function GoblinService:StartRaid()
	if raidState or not Config.GoblinRaid.Enabled then return end
	local zone, spawns = raidCamp()
	if not zone then return end
	local info = pickRaidType()
	local tier = raidTier()
	local folder = workspace:FindFirstChild("Goblins") or Instance.new("Folder")
	folder.Name = "Goblins"
	folder.Parent = workspace
	raidState = { Type = info, Damage = {}, EndsAt = os.clock() + Config.GoblinRaid.DurationSeconds, Boss = info.Boss == true }
	workspace:SetAttribute("GoblinRaidActive", true)
	workspace:SetAttribute("GoblinRaidType", info.Title)
	for index = 1, info.Count do
		local spawnPart = spawns[((index - 1) % #spawns) + 1]
		local position = clampToZone(zone, spawnPart.Position + Vector3.new(math.random(-4, 4), 3, math.random(-4, 4)))
		local modelType = info.Model or RAID_MODEL_BY_TYPE[info.Id] or "Warrior" -- Config.GoblinRaid.Types[*].Model = ключ Config.Goblins.Types
		local ok, model, attackZone = pcall(createR6Placeholder, position, tier, position, modelType)
		-- Красный круг атаки дорожных гоблинов рейду не нужен — границы задаёт GoblinCamp/Zone.
		if typeof(attackZone) == "Instance" then attackZone:Destroy() end
		if ok and model then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid then
				local maxHealth = humanoid.MaxHealth * (info.HealthMult or 1)
				humanoid.MaxHealth = maxHealth
				humanoid.Health = maxHealth
				humanoid.WalkSpeed = humanoid.WalkSpeed * (info.SpeedMult or 1)
			end
			if info.Scale and info.Scale ~= 1 then pcall(function() model:ScaleTo(info.Scale) end) end
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and info.Color then
					local highlight = model:FindFirstChild("RaidTint") or Instance.new("Highlight")
					highlight.Name = "RaidTint"
					highlight.FillColor = info.Color
					highlight.FillTransparency = 0.75
					highlight.OutlineColor = info.Color
					highlight.Parent = model
					break
				end
			end
			model.Parent = folder
			pcall(function() model.PrimaryPart:SetNetworkOwner(nil) end)
			model:SetAttribute("GoblinAttacking", false)
			model:SetAttribute("GoblinMoving", false)
			model:SetAttribute("GoblinRaid", info.Id)
			local goblin = {
				Model = model, Humanoid = humanoid, MineTier = tier, Owner = nil, Dead = false,
				Definition = Config.Goblins.Types[modelType], Type = modelType, BaseWalkSpeed = humanoid and humanoid.WalkSpeed,
				BankPosition = position, Raid = true, RaidInfo = info, Home = position, DamageMultiplier = info.DamageMult or 1,
				NextAttackAt = 0, NextHealAt = 0,
			}
			raidGoblins[goblin] = true
			humanoid.Died:Connect(function()
				if goblin.Dead then return end
				goblin.Dead = true
				Sfx.play("GoblinDeath", model)
				pcall(function() self:_rewardRaidKill(goblin) end)
				task.delay(0.6, function()
					raidGoblins[goblin] = nil
					if model.Parent then model:Destroy() end
					if raidState and next(raidGoblins) == nil then self:_finishRaid(true) end
				end)
			end)
		end
	end
	Sfx.play("GoblinWaveWarning", folder:FindFirstChildWhichIsA("Model"))
	announceAll(("⚔ %s are raiding the Goblin Camp!"):format(info.Title), info.Color)
	-- Первая встреча с гоблинами — первый рейд, который игрок застал
	-- (дорожные волны в конфиге выключены, см. DisableRoadWaves).
	if Services.TutorialService then
		for _, player in game:GetService("Players"):GetPlayers() do
			pcall(function() Services.TutorialService:ShowHint(player, "FirstGoblin") end)
		end
	end
end

function GoblinService:_tickRaidGoblin(goblin, zone, now)
	local root = goblin.Model.PrimaryPart
	local humanoid = goblin.Humanoid
	if not (root and humanoid) or goblin.Dead or goblin.Attacking then return end
	local cfg = Config.GoblinRaid
	-- Выбросило из зоны — сразу домой.
	if not insideZone(zone, root.Position, 2) then
		humanoid:MoveTo(clampToZone(zone, goblin.Home))
		goblin.Model:SetAttribute("GoblinMoving", true)
		return
	end
	-- Шаман лечит своих.
	if goblin.RaidInfo.HealAllies and now >= goblin.NextHealAt then
		goblin.NextHealAt = now + 3
		for other in raidGoblins do
			local otherRoot = other.Model.PrimaryPart
			if not other.Dead and otherRoot and other.Humanoid and (otherRoot.Position - root.Position).Magnitude <= 16 then
				other.Humanoid.Health = math.min(other.Humanoid.MaxHealth, other.Humanoid.Health + other.Humanoid.MaxHealth * goblin.RaidInfo.HealAllies)
			end
		end
	end
	-- Цель — только игрок ВНУТРИ зоны и рядом.
	local target, targetHumanoid, best = nil, nil, cfg.AggroRadius
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		if hrp and hum and hum.Health > 0 and insideZone(zone, hrp.Position, 0) then
			local distance = (hrp.Position - root.Position).Magnitude
			if distance < best then target, targetHumanoid, best = hrp, hum, distance end
		end
	end
	if target then
		if best <= cfg.AttackRange and now >= goblin.NextAttackAt then
			goblin.NextAttackAt = now + cfg.AttackCooldown
			humanoid:MoveTo(root.Position)
			goblin.Model:SetAttribute("GoblinMoving", false)
			if goblin.RaidInfo.ExplodeOnAttack then
				local victim = Players:GetPlayerFromCharacter(target.Parent)
				beginGoblinAttack(goblin, targetHumanoid, target)
				task.delay(Config.Goblins.AttackWindup, function()
					if goblin.Dead or not root.Parent then return end
					local blast = Instance.new("Explosion")
					blast.Position = root.Position
					blast.BlastRadius = 8
					blast.BlastPressure = 0
					blast.DestroyJointRadiusPercent = 0
					blast.Parent = workspace
					if victim and Services.CombatService and Services.CombatService.BlastKnock then
						pcall(Services.CombatService.BlastKnock, Services.CombatService, victim, root.Position, nil)
					end
					goblin.Exploded = true
					humanoid.Health = 0
				end)
			else
				beginGoblinAttack(goblin, targetHumanoid, target)
			end
		elseif best > cfg.AttackRange * 0.8 then
			humanoid:MoveTo(clampToZone(zone, target.Position))
			goblin.Model:SetAttribute("GoblinMoving", true)
		end
		return
	end
	-- Никого — бродим вокруг своей точки.
	if not goblin.WanderPoint or (root.Position - goblin.WanderPoint).Magnitude < 3 or now >= (goblin.WanderUntil or 0) then
		local angle = math.random() * math.pi * 2
		local radius = math.random() * cfg.WanderRadius
		goblin.WanderPoint = clampToZone(zone, goblin.Home + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
		goblin.WanderUntil = now + 4 + math.random() * 3
		humanoid:MoveTo(goblin.WanderPoint)
		goblin.Model:SetAttribute("GoblinMoving", true)
	end
end

function GoblinService:_startRaidLoop()
	if not (Config.GoblinRaid and Config.GoblinRaid.Enabled) then return end
	task.spawn(function()
		local zone = raidCamp()
		local waited = 0
		while not zone and waited < 60 do
			task.wait(5)
			waited += 5
			zone = raidCamp()
		end
		if not zone then
			warn("[GoblinService] Workspace/GoblinCamp/Zone не найден — гоблинский рейд выключен (см. Config.GoblinRaid).")
			return
		end
		local nextRaidAt = os.clock() + Config.GoblinRaid.IntervalSeconds
		local announced = false
		while true do
			task.wait(0.25)
			local now = os.clock()
			local ok, err = pcall(function()
				if raidState then
					if now >= raidState.EndsAt then
						self:_finishRaid(false)
						nextRaidAt = now + Config.GoblinRaid.IntervalSeconds
					else
						for goblin in raidGoblins do
							if goblin.Model and goblin.Model.Parent then
								self:_tickRaidGoblin(goblin, zone, now)
							end
						end
					end
				elseif #Players:GetPlayers() > 0 then
					if not announced and now >= nextRaidAt - Config.GoblinRaid.AnnounceBefore then
						announced = true
						announceAll(("Goblin raid at the Goblin Camp in %ds!"):format(Config.GoblinRaid.AnnounceBefore), Color3.fromRGB(255, 190, 80))
					end
					if now >= nextRaidAt then
						announced = false
						self:StartRaid()
						nextRaidAt = now + Config.GoblinRaid.IntervalSeconds + Config.GoblinRaid.DurationSeconds
					end
				end
			end)
			if not ok then warn("[GoblinService] рейд:", err) end
		end
	end)
end

function GoblinService:SetupPlayer(player)
	active[player] = {Goblins = {}, WaveInProgress = false, NextWaveAt = os.clock() + Config.Goblins.WaveInterval}
	player:SetAttribute("GoblinMineSlowdownMultiplier", 1)
	player:SetAttribute("GoblinWaveActive", false)
	--------------------------------------------------------------------------
	-- УДАЛЕНА ОБУЧАЮЩАЯ ВОЛНА ГОБЛИНОВ (обучение v7).
	--
	-- Здесь стоял запуск гарантированной волны на базу новичка: прежний
	-- 12-шаговый гайд доводил игрока до шага "победи гоблина" и ждал её.
	-- В прологе v7 боя нет вообще (см. Config.Tutorial.Steps — семь шагов
	-- про добычу и продажу), а гоблины объясняются контекстной подсказкой
	-- FirstGoblin в момент первой настоящей встречи.
	--
	-- ВАЖНО, ПОЧЕМУ ЭТО НЕЛЬЗЯ БЫЛО ПРОСТО ОСТАВИТЬ: одним из условий
	-- запуска было MineTier >= 2, а в новом порядке тир 2 — это ровно
	-- починка шахты на четвёртом шаге. Волна прилетала бы на базу игрока,
	-- который к этому моменту ни разу не держал кирку как оружие и даже
	-- не имеет тележки, которую они пришли ломать.
	--
	-- Обычные волны и рейды (см. Config.Goblins) не тронуты и идут своим
	-- чередом — после обучения, как и у всех остальных игроков.
	--------------------------------------------------------------------------
	task.spawn(function()
		while player.Parent do
			task.wait(1)
			local ok, err = pcall(function()
				local tier = Services.DataService:GetTiers(player).Mine
				local tutorialBlocked = player:GetAttribute("NeedsTutorial") == true
				local state = active[player]
				if player.Parent and state and not tutorialBlocked and not state.WaveInProgress
					and os.clock() >= (state.NextWaveAt or 0) then
					self:SpawnWave(player, math.clamp(math.ceil(tier / 2), 1, 4), false)
				end
			end)
			if not ok then
				warn("[GoblinService] Goblin wave tick failed for", player.Name, ":", err)
			end
		end
	end)
end

-- Публичная обёртка над spawnChestLoot (тем же визуалом, что и у сундука
-- гоблина — предмет падает и по диагонали летит к игроку) — чтобы
-- RockService мог показывать награды с валуна ТЕМ ЖЕ эффектом, а не просто
-- молча начислять деньги/жеоду без анимации.
function GoblinService:SpawnLooseReward(player, kind, geodeType, position, color)
	local ok, err = pcall(spawnChestLoot, player, kind, geodeType, position, color, nil)
	if not ok then
		warn(("[GoblinService] SpawnLooseReward failed for %s: %s"):format(player.Name, tostring(err)))
	end
end

function GoblinService:Init(services)
	Services = services
	local shared = ReplicatedStorage:WaitForChild("Shared")
	local access = shared:FindFirstChild("GoblinAdminAccess") or Instance.new("RemoteFunction")
	access.Name = "GoblinAdminAccess"
	access.Parent = shared
	access.OnServerInvoke = function(player)
		return isGoblinAdmin(player)
	end
	local adminRequest = shared:FindFirstChild("GoblinAdminRequest") or Instance.new("RemoteEvent")
	adminRequest.Name = "GoblinAdminRequest"
	adminRequest.Parent = shared
	adminRequest.OnServerEvent:Connect(function(player, action, count)
		if not isGoblinAdmin(player) or action ~= "Spawn" then return end
		self:SpawnWave(player, math.clamp(math.floor(tonumber(count) or 1), 1, 4), false, true)
	end)
	self:_startAiScheduler()
	pcall(function() PhysicsService:RegisterCollisionGroup(GOBLIN_COLLISION_GROUP) end)
	PhysicsService:CollisionGroupSetCollidable(GOBLIN_COLLISION_GROUP, GOBLIN_COLLISION_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(GOBLIN_COLLISION_GROUP, "Cart", false)
	PhysicsService:CollisionGroupSetCollidable(GOBLIN_COLLISION_GROUP, "CartCarrier", false)
	Players.PlayerRemoving:Connect(function(player)
		goblinAdminCache[player.UserId] = nil
		local state = active[player]
		if state then
			local removing = {}
			for goblin in state.Goblins do table.insert(removing, goblin) end
			for _, goblin in removing do self:_removeGoblin(player, goblin) end
		end
		for _, otherState in active do
			for goblin in otherState.Goblins do
				if goblin.EliteParticipants then goblin.EliteParticipants[player] = nil end
			end
		end
		active[player] = nil
	end)
	-- v8: гоблинский рейд в лагере (Workspace/GoblinCamp).
	self:_startRaidLoop()
	Players.PlayerRemoving:Connect(function(player)
		if raidState then raidState.Damage[player] = nil end
	end)
end

return GoblinService
