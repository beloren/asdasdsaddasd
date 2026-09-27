--------------------------------------------------------------------------------
-- GroundCheck — «можно ли сюда поставить» для тотемов/декора/реликвий.
-- Один модуль на сервере и клиенте: призрак красный ровно там, где сервер
-- откажет.
--
-- v14.4: ставить можно на ЛЮБУЮ поверхность — пол, крышу, стол, склон,
-- стену, другой тотем. Если поверхность пологая (не круче
-- Config.Placeables.UprightSlope), предмет стоит ровно вертикально; если
-- круче (стена, крутой склон, потолок) — «прилипает» к ней: его верх
-- смотрит по нормали поверхности.
--
-- Территория игрока — ВЕСЬ прямоугольник его PlotTemplate (габариты
-- модели шаблона), а не только PlotPad. PlotService кладёт габариты на
-- PlotPad атрибутами PlotBoundsCFrame / PlotBoundsSize.
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local GroundCheck = {}

local function cfg()
	return Config.Placeables or {}
end

-- Любая коллизионная деталь или Terrain — опора.
function GroundCheck.IsGroundPart(instance)
	if not instance then return false end
	if instance:IsA("Terrain") then return true end
	return instance:IsA("BasePart") and instance.CanCollide
end

-- Есть ли поверхность под точкой вдоль -up. Возвращает
-- (ok, surfacePosition, surfaceNormal, hitInstance).
function GroundCheck.Surface(position, up, ignore)
	up = (typeof(up) == "Vector3" and up.Magnitude > 0.1) and up.Unit or Vector3.yAxis
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	params.IgnoreWater = true
	params.RespectCanCollide = true
	local hit = workspace:Raycast(position + up * 1.2, -up * 2.6, params)
	if not (hit and GroundCheck.IsGroundPart(hit.Instance)) then
		return false, nil, nil, hit and hit.Instance
	end
	return true, hit.Position, hit.Normal, hit.Instance
end

-- Стоит ли на такой поверхности вертикально (true) или «прилипает» (false).
function GroundCheck.IsUpright(normal)
	return normal.Y >= math.cos(math.rad(cfg().UprightSlope or 40))
end

-- Поворот предмета на поверхности с нормалью normal и доворотом yaw (градусы)
-- вокруг этой нормали.
function GroundCheck.Orientation(normal, yawDegrees)
	local yaw = math.rad(yawDegrees or 0)
	if GroundCheck.IsUpright(normal) then
		return CFrame.Angles(0, yaw, 0)
	end
	local up = normal.Unit
	local right = up:Cross(Vector3.yAxis)
	if right.Magnitude < 0.05 then right = Vector3.xAxis end -- потолок/пол вверх ногами
	right = right.Unit
	return CFrame.fromMatrix(Vector3.zero, right, up) * CFrame.Angles(0, yaw, 0)
end

-- Точка внутри территории участка (весь прямоугольник PlotTemplate)?
-- v20.34: участок — это ВЕСЬ столб над прямоугольником PlotTemplate, любой
-- высоты (крыши, острова, мосты, прыжок — всё «на участке»). Снизу — до 8
-- стадов под нижним краем. margin — запас по краям (по умолчанию PlotMargin).
function GroundCheck.InPlot(pad, position, margin)
	if not (pad and pad.Parent) then return false end
	local boundsCFrame = pad:GetAttribute("PlotBoundsCFrame")
	local boundsSize = pad:GetAttribute("PlotBoundsSize")
	if typeof(boundsCFrame) ~= "CFrame" or typeof(boundsSize) ~= "Vector3" then
		boundsCFrame, boundsSize = pad.CFrame, pad.Size
	end
	local rel = boundsCFrame:PointToObjectSpace(position)
	margin = margin or cfg().PlotMargin or 1
	return math.abs(rel.X) <= boundsSize.X / 2 + margin
		and math.abs(rel.Z) <= boundsSize.Z / 2 + margin
		and rel.Y >= -boundsSize.Y / 2 - 8
end

-- v20.42: поставить модель так, чтобы её НИЗ (по рамке) лёг на точку cf
-- вдоль «верха» cf — для моделей с пивотом в центре (сундуки).
function GroundCheck.SeatModel(model, cf)
	model:PivotTo(cf)
	local boxCF, size = model:GetBoundingBox()
	local up = cf.UpVector
	local halfUp = math.abs(boxCF.RightVector:Dot(up)) * size.X / 2
		+ math.abs(boxCF.UpVector:Dot(up)) * size.Y / 2
		+ math.abs(boxCF.LookVector:Dot(up)) * size.Z / 2
	local bottom = (boxCF.Position - cf.Position):Dot(up) - halfUp
	model:PivotTo(cf + up * -bottom)
end

-- v20.x: ТОЧКА ВНУТРИ ТВЁРДОГО (под землёй / внутри детали)?
local function solidAt(point, overlap)
	local ok, buried = pcall(function()
		local half = Vector3.new(0.5, 0.5, 0.5)
		local region = Region3.new(point - half, point + half):ExpandToGrid(4)
		local materials, occupancies = workspace.Terrain:ReadVoxels(region, 4)
		local material = materials[1][1][1]
		return material ~= Enum.Material.Air and material ~= Enum.Material.Water and occupancies[1][1][1] > 0.5
	end)
	if ok and buried then return true end
	for _, part in workspace:GetPartBoundsInRadius(point, 0.05, overlap) do
		if part.CanCollide then return true end
	end
	return false
end

-- v20.x: ПОСЛЕ ПЕРЕЗАХОДА предмет ставится по сохранённой точке, но земля
-- под ней могла оказаться другой (другой участок, Terrain вокруг PlotPad,
-- свой PlotOrigins на другой высоте). Ищем настоящую поверхность вдоль
-- «верха» предмета:
--   1) рядом (±1.5 стада) - встаём ровно на неё (обычный случай);
--   2) точка внутри земли/детали - поднимаемся на поверхность над ней
--      (до 32 стадов), предмет больше не уходит под землю;
--   3) под точкой пусто - опускаемся на поверхность, если она не дальше
--      8 стадов (предмет не висит в воздухе).
-- Ничего не нашли - остаётся сохранённая точка. Поворот не меняется.
function GroundCheck.Resnap(cf, ignore)
	local up = cf.UpVector
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	params.IgnoreWater = true
	params.RespectCanCollide = true
	local function cast(fromHeight, length)
		local hit = workspace:Raycast(cf.Position + up * fromHeight, -up * length, params)
		if hit and GroundCheck.IsGroundPart(hit.Instance) then return hit end
		return nil
	end
	local function at(hit)
		return CFrame.new(hit.Position) * cf.Rotation
	end
	local near = cast(1.5, 3)
	if near then return at(near) end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = ignore or {}
	overlap.RespectCanCollide = true
	if solidAt(cf.Position + up * 0.3, overlap) then
		for _, height in { 4, 8, 16, 32 } do
			local hit = cast(height, height + 1.5)
			if hit then return at(hit) end
		end
		return cf
	end
	local below = cast(1.5, 9.5)
	if below then return at(below) end
	return cf
end

-- Совместимость со старым кодом: луч вниз, (ok, position, hitInstance).
function GroundCheck.Probe(position, _pad, ignore)
	local ok, point, _, instance = GroundCheck.Surface(position, Vector3.yAxis, ignore)
	return ok, point, instance
end

return GroundCheck
