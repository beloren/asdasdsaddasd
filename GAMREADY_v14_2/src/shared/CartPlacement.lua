--------------------------------------------------------------------------------
-- CartPlacement — ОДНА И ТА ЖЕ математика постановки тележки из упаковки для
-- КЛИЕНТА (зелёный/красный предпросмотр, CartPlacement.client.lua) и СЕРВЕРА
-- (финальная проверка перед созданием тележки, CartService:PlaceCartFromPackage).
--
-- ЗАЧЕМ ОБЩИЙ МОДУЛЬ. Клиенту нельзя верить: он присылает только ТОЧКУ, куда
-- целится игрок, а решение «можно/нельзя» сервер принимает сам, заново. Но
-- если бы у них были две разные реализации проверки, игрок регулярно видел
-- бы ЗЕЛЁНОЕ превью и получал отказ сервера (или наоборот) — классическое
-- рассогласование. Поэтому обе стороны зовут ровно эти функции, а различается
-- только список игнорируемых объектов (у клиента — свой призрак и персонаж,
-- у сервера — персонаж и уже существующие тележки).
--
-- ПОВОРОТ «ЛИЦОМ К ИГРОКУ». Та же самая конвенция, что у тележки В РУКАХ
-- (см. CartService:Attach): «передняя» сторона задаётся маркером FacingPoint
-- внутри модели, а если его нет — общим углом Config.Cart.HolderSideRotation.
-- Держа тележку, игрок стоит к ней лицом-от, и её перед смотрит НА него;
-- при постановке мы просто подставляем вместо поворота персонажа
-- «виртуальный» поворот, у которого LookVector направлен от тележки к игроку.
-- Никакой отдельной подгонки углов под каждую модель не нужно — тележка,
-- поставленная из упаковки, стоит ровно так же, как она стояла бы, если бы
-- игрок принёс её в руках и отпустил, повернувшись к ней.
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)

local CartPlacement = {}

local function cfg()
	return Config.CartPackage or {}
end

--------------------------------------------------------------------------------
-- ПОВОРОТ
--------------------------------------------------------------------------------

-- Угол разворота модели «лицом к держателю» — копия логики из
-- CartService:Attach (rotationAngle), вынесенная сюда, чтобы обе стороны
-- считали одинаково.
function CartPlacement.FacingAngle(model, root)
	local angle = math.rad((Config.Cart and Config.Cart.HolderSideRotation) or 90)
	if not (model and root) then
		return angle
	end
	local facingPoint = model:FindFirstChild("FacingPoint", true)
	if facingPoint and facingPoint:IsA("BasePart") then
		local localOffset = root.CFrame:PointToObjectSpace(facingPoint.Position)
		angle = -math.atan2(localOffset.X, localOffset.Z)
	end
	return angle
end

-- Итоговый CFrame тележки: стоит в position, передом к playerPosition.
--
-- Вывод формулы. В руках: cartRotation = hrpRotation * Angles(0, -angle, 0)
-- (AlignOrientation тянет тележку к якорю, у которого C1 = Angles(0, angle, 0),
-- см. CartService:Attach). Направление «от тележки к игроку» при этом равно
-- hrp.LookVector — тележка висит ПОЗАДИ игрока. Значит достаточно взять
-- виртуальный поворот, у которого LookVector смотрит от точки постановки на
-- игрока, и применить ту же поправку.
function CartPlacement.PlacementCFrame(position, playerPosition, facingAngle)
	local flat = (playerPosition - position) * Vector3.new(1, 0, 1)
	local look = flat.Magnitude > 1e-3 and flat.Unit or Vector3.zAxis
	local base = CFrame.lookAt(position, position + look)
	return base * CFrame.Angles(0, -(facingAngle or math.rad(90)), 0)
end

--------------------------------------------------------------------------------
-- ГЕОМЕТРИЯ МОДЕЛИ
--------------------------------------------------------------------------------

-- Габариты корпуса и расстояние от Root до физического низа — нужны и для
-- посадки на землю, и для проверки «место свободно». Работает для любой
-- пользовательской модели Cart_TierN, ничего в ней не требуя.
function CartPlacement.MeasureModel(model, root)
	local _, size = model:GetBoundingBox()
	local rootToBottom
	local bottomMarker = model:FindFirstChild("Bottom", true)
	if bottomMarker and bottomMarker:IsA("BasePart") then
		rootToBottom = math.max(0.1, root.Position.Y - bottomMarker.Position.Y)
	else
		local lowest = math.huge
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") and descendant.CanCollide then
				local cf, partSize = descendant.CFrame, descendant.Size
				local halfHeight = math.abs(cf.RightVector.Y) * partSize.X * 0.5
					+ math.abs(cf.UpVector.Y) * partSize.Y * 0.5
					+ math.abs(cf.LookVector.Y) * partSize.Z * 0.5
				lowest = math.min(lowest, descendant.Position.Y - halfHeight)
			end
		end
		rootToBottom = lowest < math.huge and math.max(0.1, root.Position.Y - lowest) or root.Size.Y * 0.5
	end
	return size, rootToBottom
end

--------------------------------------------------------------------------------
-- ПРИЦЕЛ
--
-- Куда игрок целится: луч камеры через курсор/палец. Если луч ни во что не
-- попал (небо), берём точку на DefaultDistance перед камерой и опускаем её
-- на землю — превью не должно «пропадать», когда игрок смотрит в горизонт.
-- Только клиент, серверу приходит уже готовая точка.
--------------------------------------------------------------------------------
function CartPlacement.AimPoint(camera, screenPoint, ignoreList)
	if not camera then return nil end
	local ray = camera:ViewportPointToRay(screenPoint.X, screenPoint.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoreList or {}
	params.RespectCanCollide = true
	local hit = workspace:Raycast(ray.Origin, ray.Direction * (cfg().MaxDistance or 26) * 2, params)
	if hit then
		return hit.Position
	end
	return ray.Origin + ray.Direction * (cfg().DefaultDistance or 10)
end

--------------------------------------------------------------------------------
-- ПРОВЕРКА МЕСТА
--
-- Возвращает: ok (boolean), reason (строка для подсказки/уведомления),
-- cframe (куда именно встанет тележка).
--
-- ПОЧЕМУ ПРОВЕРКА ИМЕННО ТАКАЯ (v12.1 — переделано, прошлая была слишком
-- строгой и краснела почти везде).
--
-- Прошлая версия била ОДНИМ лучом в точку прицела и брала нормаль этой
-- точки. На реальной карте это провал: камень, трава, стык двух частей,
-- меш-террейн — и нормаль в одной случайной точке оказывается почти
-- вертикальной стенкой, хотя площадка под тележку там прекрасная. Плюс
-- коробка пересечений строилась РАЗДУТОЙ (габариты + запас) и цепляла
-- соседнюю стену, бортик, декорацию — отсюда вечное "Something is in the way".
--
-- Теперь:
--   • земля ищется НЕСКОЛЬКИМИ лучами по всей площади тележки (центр + углы
--     + середины сторон). Достаточно, чтобы отозвалась ЧАСТЬ из них — так
--     тележка ставится и на краю платформы, и на кочках, и на мостике;
--   • ровность считается не по нормали одной точки, а по РАЗБРОСУ ВЫСОТ
--     между замерами: важно ведь не то, под каким углом стоит один камешек,
--     а то, есть ли под тележкой ступенька, на которой она повиснет;
--   • за высоту берётся САМЫЙ ВЫСОКИЙ замер плюс зазор — тележка встаёт
--     ЧУТЬ НАД землёй и сама оседает/выравнивается физикой, когда её
--     отпускают (см. CartService:_playInflate → _settleUpright). Поэтому
--     неровности больше не мешают: ничто не проваливается в склон;
--   • коробка пересечений УЖАТА по горизонтали и приподнята над землёй, а
--     всё, что лежит НИЖЕ дна тележки (пол, бордюр, трава, рельс), в помехи
--     не записывается — это поверхность, на которую ставят, а не препятствие.
--------------------------------------------------------------------------------

-- Мировая AABB детали: нужна, чтобы понять, лежит ли найденная помеха НИЖЕ
-- дна тележки (тогда это пол, а не препятствие).
local function partTopY(part)
	local cf, size = part.CFrame, part.Size
	local halfHeight = math.abs(cf.RightVector.Y) * size.X * 0.5
		+ math.abs(cf.UpVector.Y) * size.Y * 0.5
		+ math.abs(cf.LookVector.Y) * size.Z * 0.5
	return part.Position.Y + halfHeight
end

-- Помеха ли эта деталь для тележки. Правило намеренно СНИСХОДИТЕЛЬНОЕ —
-- запрещать постановку должно только то, во что тележка реально упрётся:
--   • персонажи не мешают (отойдут, и тележка с ними не сталкивается);
--   • всё, верх чего ниже дна тележки, — это ПОЛ, бордюр, рельс, трава,
--     то есть поверхность, на которую ставят, а не препятствие;
--   • незаякоренная мелочь (руда на земле, ящики, обломки) не мешает:
--     тележка её просто растолкает, когда поедет;
--   • а вот ДРУГАЯ ТЕЛЕЖКА мешает, хоть она и незаякорена — две тележки в
--     одной точке это сломанная физика и потерянный груз.
function CartPlacement.IsObstacle(part, cartBottomY)
	local model = part:FindFirstAncestorOfClass("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then
		return false
	end
	if partTopY(part) <= cartBottomY + 0.5 then
		return false
	end
	local ancestorCart = part:FindFirstAncestor("Carts")
	if model and (model.Name:match("^Cart_") or ancestorCart) then
		return true
	end
	return part.Anchored
end

function CartPlacement.Validate(options)
	local position = options.Position
	local playerPosition = options.PlayerPosition
	local model = options.Model
	local root = options.Root
	local ignoreList = options.IgnoreList or {}
	local settings = cfg()

	if typeof(position) ~= "Vector3" or typeof(playerPosition) ~= "Vector3" then
		return false, "No spot", nil
	end

	local flatDistance = ((position - playerPosition) * Vector3.new(1, 0, 1)).Magnitude
	if flatDistance > (settings.MaxDistance or 34) then
		return false, "Too far away", nil
	end
	if flatDistance < (settings.MinDistance or 2.5) then
		return false, "Too close to you", nil
	end

	local size, rootToBottom = CartPlacement.MeasureModel(model, root)
	local facingAngle = CartPlacement.FacingAngle(model, root)
	-- Ориентация нужна заранее: замеры земли раскладываются по площади
	-- тележки в её собственных осях, а не по осям мира.
	local aim = CartPlacement.PlacementCFrame(position, playerPosition, facingAngle)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoreList
	params.RespectCanCollide = true

	-- ЗАМЕРЫ ЗЕМЛИ. Девять лучей по площади тележки, слегка ужатой внутрь
	-- (0.4), чтобы угловые лучи не сваливались с края площадки.
	local halfX = size.X * 0.4
	local halfZ = size.Z * 0.4
	local offsets = {
		Vector2.new(0, 0),
		Vector2.new(halfX, halfZ), Vector2.new(-halfX, halfZ),
		Vector2.new(halfX, -halfZ), Vector2.new(-halfX, -halfZ),
		Vector2.new(halfX, 0), Vector2.new(-halfX, 0),
		Vector2.new(0, halfZ), Vector2.new(0, -halfZ),
	}

	local rayUp = tonumber(settings.GroundRayUp) or 8
	local rayDown = tonumber(settings.GroundRayDown) or 60
	local hits, highest, lowest = 0, -math.huge, math.huge
	local centerHit = nil
	for index, offset in offsets do
		local origin = aim * CFrame.new(offset.X, rayUp, offset.Y)
		local result = workspace:Raycast(origin.Position, Vector3.new(0, -(rayUp + rayDown), 0), params)
		if result then
			hits += 1
			highest = math.max(highest, result.Position.Y)
			lowest = math.min(lowest, result.Position.Y)
			if index == 1 then centerHit = result end
		end
	end

	-- Достаточно, чтобы отозвалась ТРЕТЬ замеров: тележку можно ставить на
	-- краю площадки, на мостике, на узкой полке — лишь бы она не висела в
	-- пустоте целиком.
	local minHits = math.max(2, math.ceil(#offsets / 3))
	if hits < minHits then
		return false, "No ground here", nil
	end

	-- РОВНОСТЬ — по перепаду высот под тележкой, а не по нормали точки.
	-- Перепад больше ступеньки (по умолчанию 5 стадов на всю длину) — это
	-- уже склон/обрыв, тележка там не встанет ровно.
	-- v14.3: перепад высот больше НЕ запрещает постановку (0 = выключено):
	-- тележка встаёт над самой высокой точкой с зазором и сама оседает.
	local spread = highest - lowest
	local maxSpread = tonumber(settings.MaxGroundSpread) or 0
	if maxSpread > 0 and spread > maxSpread then
		return false, "Ground is too uneven", nil
	end

	-- Дополнительная страховка от отвесной стены: если центр всё-таки
	-- отозвался, смотрим его нормаль с ОЧЕНЬ щадящим порогом.
	if centerHit then
		local slope = math.deg(math.acos(math.clamp(centerHit.Normal:Dot(Vector3.yAxis), -1, 1)))
		if slope > (tonumber(settings.MaxSlope) or 50) then
			return false, "Can't place on a wall", nil
		end
	end

	-- Свой участок, если так настроено (Config.CartPackage.OwnPlotOnly).
	local pad = options.Pad
	if settings.OwnPlotOnly and pad then
		local localPoint = pad.CFrame:PointToObjectSpace(Vector3.new(position.X, pad.Position.Y, position.Z))
		if math.abs(localPoint.X) > pad.Size.X / 2 - 2 or math.abs(localPoint.Z) > pad.Size.Z / 2 - 2 then
			return false, "Place it on YOUR base", nil
		end
	end

	-- ВЫСОТА ОТНОСИТЕЛЬНО ИГРОКА. Лучи-замеры ищут пол глубоко (GroundRayDown),
	-- и без этой проверки прицел в стену на краю обрыва ставил бы тележку
	-- на дно ущелья под собой — формально "там есть ровная земля", а по
	-- факту игрок до неё не дойдёт.
	local heightDelta = math.abs(highest - playerPosition.Y)
	if heightDelta > (tonumber(settings.MaxHeightDifference) or 16) then
		return false, "Can't reach that spot", nil
	end

	-- ВЫСОТА: по самому высокому замеру + зазор. Тележка намеренно встаёт
	-- ЧУТЬ НАД землёй и оседает сама — так ни одно колесо не оказывается
	-- утопленным в бугре.
	local gap = tonumber(settings.GroundGap) or 0.9
	local placement = CartPlacement.PlacementCFrame(
		Vector3.new(position.X, highest + rootToBottom + gap, position.Z),
		playerPosition,
		facingAngle
	)

	-- МЕСТО СВОБОДНО. Коробка УЖЕ габаритов тележки и поднята над землёй:
	-- цель — поймать стену/столб/другую тележку, а не бордюр под колёсами.
	local shrink = tonumber(settings.ClearanceShrink) or 0.8
	local heightFactor = math.clamp(tonumber(settings.ClearanceHeightFactor) or 0.55, 0.1, 1)
	local boxSize = Vector3.new(
		math.max(0.8, size.X - shrink),
		math.max(0.8, size.Y * heightFactor),
		math.max(0.8, size.Z - shrink)
	)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = ignoreList
	overlapParams.RespectCanCollide = true
	overlapParams.MaxParts = 24

	-- Дно коробки — на уровне дна тележки плюс небольшой подъём, чтобы не
	-- цеплять поверхность, на которой она стоит.
	local cartBottomY = placement.Position.Y - rootToBottom
	local boxCFrame = CFrame.new(placement.Position.X, cartBottomY + 0.35 + boxSize.Y * 0.5, placement.Position.Z)
		* (placement.Rotation)
	for _, part in workspace:GetPartBoundsInBox(boxCFrame, boxSize, overlapParams) do
		if CartPlacement.IsObstacle(part, cartBottomY) then
			return false, "Something is in the way", nil
		end
	end

	return true, "Place cart", placement
end

-- Что игнорировать серверу: персонажи всех игроков (они отойдут) и
-- перечисленные дополнительно объекты.
function CartPlacement.DefaultIgnoreList(extra)
	local list = {}
	for _, plr in Players:GetPlayers() do
		if plr.Character then
			table.insert(list, plr.Character)
		end
	end
	for _, item in extra or {} do
		table.insert(list, item)
	end
	return list
end

return CartPlacement
