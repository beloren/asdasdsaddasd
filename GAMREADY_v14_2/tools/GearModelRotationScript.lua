--------------------------------------------------------------------------------
-- Вставь содержимое этого файла в обычный Script внутри Part.
-- Зеленая ось Roblox = локальная ось Y.
--------------------------------------------------------------------------------

local RunService = game:GetService("RunService")

local part = script.Parent
if not part:IsA("BasePart") then
	warn("[GearModelRotation] Script должен находиться непосредственно внутри Part")
	return
end

-- Если Union соединён с другими деталями Weld/WeldConstraint, Roblox считает
-- их одной сборкой и переносит всё вместе. Отсоединяем только этот Union.
part:BreakJoints()
part.Anchored = true

local ROTATIONS_PER_MINUTE = 5 -- скорость: полных оборотов в минуту
local MAX_START_DELAY = 0.45 -- максимальный разброс старта между копиями, секунд

local startCFrame = part.CFrame
local position = part.Position

-- Разные позиции дают разные фазы, поэтому соседние модели не синхронизируются.
local seed = math.abs(
	math.floor(position.X * 31 + position.Y * 47 + position.Z * 73)
)
local startDelay = (seed % 1000) / 1000 * MAX_START_DELAY
local angularSpeed = math.rad(ROTATIONS_PER_MINUTE * 6)
local elapsed = 0

RunService.Heartbeat:Connect(function(deltaTime)
	elapsed += deltaTime

	local activeTime = math.max(elapsed - startDelay, 0)
	local angle = activeTime * angularSpeed

	-- Вращаем только эту деталь вокруг ее локальной зеленой оси Y.
	part.CFrame = startCFrame * CFrame.Angles(0, angle, 0)
end)
