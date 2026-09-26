--------------------------------------------------------------------------------
-- ExampleNpcStretchScript — ПРИМЕР, не часть рантайма игры.
--
-- ЧТО ЭТО: готовый Script для растягивающейся анимации NPC (например, крот,
-- вылезающий из земли, или любой NPC, где хочется "дышащее"/пружинистое
-- растяжение по высоте) + шляпа/аксессуар, которая едет вместе с растяжением,
-- сама не растягиваясь, + плавный поворот к ближайшему игроку в радиусе.
--
-- КУДА ПОЛОЖИТЬ: этот файл — не Rojo-скрипт игры (в default.project.json не
-- подключён специально) и НЕ вставляется в Command Bar. Скопируй его
-- СОДЕРЖИМОЕ в обычный Script ВНУТРИ своей кастомной модели NPC
-- (UpgradeShopNPC/RebirthNPC в ReplicatedStorage/Assets) — Parent скрипта
-- должен быть той деталью, которая растягивается (например, Union-геометрия
-- тела): правой кнопкой на неё → Insert Object → Script → вставить сюда.
--
-- КОНТРАКТ ВНУТРИ ТВОЕЙ МОДЕЛИ (необязательные части, ищутся рекурсивно по
-- всей модели NPC, не только среди соседей):
--   Hat  — Part или Model (с PrimaryPart) — сама шляпа/аксессуар на макушке.
--          Нет её — предупреждение в Output, ничего не двигается.
--   Head — Part или Model (с PrimaryPart), НЕОБЯЗАТЕЛЬНО — если голова
--          отдельная деталь, а не сам растягивающийся кусок (script.Parent).
--          Нет её — шляпа садится прямо на верх script.Parent.
--
-- СИНХРОНИЗАЦИЯ С ДИАЛОГОМ: если это модель UpgradeShopNPC, CustomCartUI.
-- client.lua сам ставит атрибут "Talking" (true/false) на модель NPC при
-- открытии/закрытии диалога — скрипт ниже сам его читает и переключает
-- анимацию на более активную, пока идёт разговор, ПРЕРЫВАЯ текущий твин
-- сразу же (не дожидаясь конца текущего вдоха/выдоха).
--
-- ПОВОРОТ К ИГРОКУ: пока кто-то в радиусе FACE_RADIUS — NPC плавно
-- разворачивается к нему (только вокруг вертикали, не наклоняется). Никого
-- рядом нет — стоит в том положении, куда его повернул сервер (маркер
-- участка + необязательный FacingPoint, см. PLACEHOLDERS_GUIDE.md).
--------------------------------------------------------------------------------

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local union = script.Parent
local originalSize = union.Size
local restCFrame = union.CFrame -- поворот "по умолчанию", когда рядом никого нет (задан сервером)

--------------------------------------------------------------------------------
-- НАХОДИМ МОДЕЛЬ NPC ЦЕЛИКОМ (самый верхний Model в цепочке родителей) —
-- на ней CustomCartUI.client.lua ставит атрибут "Talking".
--------------------------------------------------------------------------------
local npcModel = union
while npcModel.Parent and npcModel.Parent:IsA("Model") do
	npcModel = npcModel.Parent
end

--------------------------------------------------------------------------------
-- ПОВОРОТ К БЛИЖАЙШЕМУ ИГРОКУ В РАДИУСЕ.
--------------------------------------------------------------------------------
local FACE_RADIUS = 14      -- студ — дальше этого NPC не реагирует на игрока
local FACE_TURN_SPEED = 6   -- выше — резче поворачивается

RunService.Heartbeat:Connect(function(dt)
	local closestDist = FACE_RADIUS
	local closestPos = nil
	for _, plr in Players:GetPlayers() do
		local character = plr.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local dist = (hrp.Position - union.Position).Magnitude
			if dist < closestDist then
				closestDist = dist
				closestPos = hrp.Position
			end
		end
	end

	local targetCFrame = restCFrame
	if closestPos then
		local flat = Vector3.new(closestPos.X - union.Position.X, 0, closestPos.Z - union.Position.Z)
		if flat.Magnitude > 0.1 then
			targetCFrame = CFrame.lookAt(union.Position, union.Position + flat)
		end
	end

	-- Лерпим ТОЛЬКО поворот — обе CFrame построены на одной и той же
	-- union.Position, так что позиция не плывёт, меняется только ориентация.
	union.CFrame = union.CFrame:Lerp(targetCFrame, math.clamp(dt * FACE_TURN_SPEED, 0, 1))
end)

--------------------------------------------------------------------------------
-- ДВА ПРОФИЛЯ АНИМАЦИИ — "простой" (лёгкое дыхание) и "разговор" (заметно
-- активнее). Переключение теперь МГНОВЕННОЕ: смена атрибута "Talking"
-- сразу отменяет текущий твин (Tween:Cancel() досрочно освобождает
-- Completed:Wait() ниже) — цикл тут же перечитывает профиль и стартует
-- заново, а не ждёт, пока доиграется текущий вдох/выдох.
--------------------------------------------------------------------------------
local PROFILES = {
	Idle = {
		HeightMultiplier = 1.15,      -- лёгкое дыхание, +15% к высоте
		Duration = 0.6,
		EasingStyle = Enum.EasingStyle.Sine,
		Pause = 0.4,
	},
	Talking = {
		HeightMultiplier = 1.8,
		Duration = 0.2,
		EasingStyle = Enum.EasingStyle.Back,
		Pause = 0.05,
	},
}

local activeTween = nil

task.spawn(function()
	while true do
		local profile = npcModel:GetAttribute("Talking") and PROFILES.Talking or PROFILES.Idle

		local stretchedSize = Vector3.new(originalSize.X, originalSize.Y * profile.HeightMultiplier, originalSize.Z)
		local tweenInfo = TweenInfo.new(profile.Duration, profile.EasingStyle, Enum.EasingDirection.Out)

		activeTween = TweenService:Create(union, tweenInfo, { Size = stretchedSize })
		activeTween:Play()
		activeTween.Completed:Wait()

		activeTween = TweenService:Create(union, tweenInfo, { Size = originalSize })
		activeTween:Play()
		activeTween.Completed:Wait()

		task.wait(profile.Pause)
	end
end)

-- Как только "Talking" меняется — обрываем текущий твин немедленно, чтобы
-- цикл выше сразу перечитал профиль, вместо ожидания конца текущего цикла.
npcModel:GetAttributeChangedSignal("Talking"):Connect(function()
	if activeTween then
		activeTween:Cancel()
	end
end)

--------------------------------------------------------------------------------
-- ГОЛОВА И ШЛЯПА: ОБЕ едут вместе с растяжением, сами НЕ растягиваются.
--
-- ПОЧЕМУ ШЛЯПА ПРОВАЛИВАЛАСЬ ВНУТРЬ UNION: позиция считалась как "верх
-- union", и туда ставился ЦЕНТР шляпы — то есть половина шляпы неизбежно
-- уходила НИЖЕ этой точки, в тело union. Нужно было поднять ещё и на
-- половину высоты САМОЙ шляпы, чтобы её НИЖНИЙ край (а не центр) лёг на
-- верх union — это и добавлено ниже (targetHalfHeight).
--
-- ПОЧЕМУ НЕ Weld/WeldConstraint: сварка фиксирует ОДНО относительное
-- смещение один раз, в момент создания, а union меняет Size каждый кадр —
-- сварка не подстроилась бы под текущую высоту.
--------------------------------------------------------------------------------
local function findRigid(name)
	local inst = npcModel:FindFirstChild(name, true)
	if not inst then
		return nil, nil
	end
	local part = inst
	if inst:IsA("Model") then
		part = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
	end
	if not (part and part:IsA("BasePart")) then
		return inst, nil
	end
	return inst, part
end

-- Половина высоты цели (Part — просто Size.Y/2, Model — по реальному
-- бокс-охвату всех её частей, на случай если шляпа сама собрана из
-- нескольких кусков).
local function halfHeightOf(inst, part)
	if inst:IsA("Model") then
		local _, size = inst:GetBoundingBox()
		return size.Y / 2
	end
	return part.Size.Y / 2
end

local headInst, headPart = findRigid("Head")
local hatInst, hatPart = findRigid("Hat")

if not hatInst then
	warn("[ExampleNpcStretchScript] Не нашёл 'Hat' нигде внутри модели NPC ('" .. npcModel:GetFullName() .. "') - шляпа не будет двигаться. Проверь имя (регистр важен: 'Hat', не 'hat', и без лишних пробелов).")
elseif not hatPart then
	warn("[ExampleNpcStretchScript] 'Hat' найден (" .. hatInst:GetFullName() .. "), но это Model без PrimaryPart и без единой BasePart внутри - назначь PrimaryPart шляпе.")
end

local HEAD_OFFSET = 0 -- доп. зазор над union перед головой, студ
local HAT_OFFSET = 0  -- доп. зазор над головой/union перед шляпой, студ
local HAT_FORWARD_OFFSET = -2.2 -- смещение шляпы по локальной оси Z вперёд/назад относительно головы, студ

local function moveOnTop(targetInst, targetPart, baseCFrame, baseTopLocalY, offset, forwardOffset)
	local targetHalfHeight = halfHeightOf(targetInst, targetPart)
	local topWorld = baseCFrame * CFrame.new(0, baseTopLocalY + offset + targetHalfHeight, forwardOffset or 0)
	if targetInst:IsA("Model") then
		targetInst:PivotTo(topWorld)
	elseif targetInst:IsA("BasePart") then
		targetInst.CFrame = topWorld
	end
end

if hatPart then
	RunService.Heartbeat:Connect(function()
		local unionTopLocalY = union.Size.Y / 2

		if headPart then
			moveOnTop(headInst, headPart, union.CFrame, unionTopLocalY, HEAD_OFFSET)
			local headTopLocalY = headPart.Size.Y / 2
			moveOnTop(hatInst, hatPart, headPart.CFrame, headTopLocalY, HAT_OFFSET, HAT_FORWARD_OFFSET)
		else
			moveOnTop(hatInst, hatPart, union.CFrame, unionTopLocalY, HAT_OFFSET, HAT_FORWARD_OFFSET)
		end
	end)
end
