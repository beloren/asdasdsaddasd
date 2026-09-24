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
function GroundCheck.InPlot(pad, position)
	if not (pad and pad.Parent) then return false end
	local boundsCFrame = pad:GetAttribute("PlotBoundsCFrame")
	local boundsSize = pad:GetAttribute("PlotBoundsSize")
	if typeof(boundsCFrame) ~= "CFrame" or typeof(boundsSize) ~= "Vector3" then
		boundsCFrame, boundsSize = pad.CFrame, pad.Size
	end
	local rel = boundsCFrame:PointToObjectSpace(position)
	local margin = cfg().PlotMargin or 1
	return math.abs(rel.X) <= boundsSize.X / 2 + margin
		and math.abs(rel.Z) <= boundsSize.Z / 2 + margin
		and rel.Y >= -boundsSize.Y / 2 - 8
		and rel.Y <= boundsSize.Y / 2 + 60
end

-- Совместимость со старым кодом: луч вниз, (ok, position, hitInstance).
function GroundCheck.Probe(position, _pad, ignore)
	local ok, point, _, instance = GroundCheck.Surface(position, Vector3.yAxis, ignore)
	return ok, point, instance
end

return GroundCheck
