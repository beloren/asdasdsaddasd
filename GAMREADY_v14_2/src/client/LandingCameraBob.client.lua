--------------------------------------------------------------------------------
-- LandingCameraBob (LocalScript) v17 — камера «пружинит» при приземлении.
--
-- После прыжка или падения камера коротко проседает вниз и мягко
-- возвращается, с одним небольшим перелётом вверх. Амплитуда маленькая и
-- зависит от скорости падения (Config.CameraLandBob). Работает только с
-- обычной камерой (CameraType.Custom) — катсцены и скриптовые камеры не
-- трогаются.
--
-- Смещение накладывается поверх уже посчитанной камеры (RenderStep после
-- Camera) и в следующем кадре снимается, если камеру никто не переписал —
-- тот же приём, что у тряски в MineExpeditionUI, поэтому смещения не
-- накапливаются и не мешают другим эффектам.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local CFG = Config.CameraLandBob or {}
if CFG.Enabled == false then return end

local player = Players.LocalPlayer

local STIFFNESS = CFG.Stiffness or 230
local DAMPING = CFG.Damping or 17
local MIN_FALL = CFG.MinFallSpeed or 14
local FULL_FALL = CFG.FullFallSpeed or 55
local KICK = CFG.KickVelocity or 6.5
local MAX_SCALE = CFG.MaxScale or 1.7
local PITCH = math.rad(CFG.PitchDegrees or 1.2)

local offset, velocity = 0, 0 -- студы по вертикали (минус — вниз)
local peakFallSpeed = 0
local written, writtenOffset = nil, CFrame.identity

local function watchCharacter(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not (humanoid and root) then return end
	peakFallSpeed = 0
	local tracking = RunService.Heartbeat:Connect(function()
		if not root.Parent then return end
		local state = humanoid:GetState()
		if state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping then
			local vy = root.AssemblyLinearVelocity.Y
			if -vy > peakFallSpeed then peakFallSpeed = -vy end
		end
	end)
	local stateConn = humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Landed then
			local speed = peakFallSpeed
			peakFallSpeed = 0
			if speed < MIN_FALL then return end
			local scale = math.clamp((speed - MIN_FALL) / math.max(1, FULL_FALL - MIN_FALL), 0.25, MAX_SCALE)
			velocity = math.min(velocity, -KICK * scale)
		elseif new == Enum.HumanoidStateType.Jumping then
			peakFallSpeed = 0
		end
	end)
	character.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			tracking:Disconnect()
			stateConn:Disconnect()
		end
	end)
end

if player.Character then task.spawn(watchCharacter, player.Character) end
player.CharacterAdded:Connect(watchCharacter)

RunService:BindToRenderStep("LandingCameraBob", Enum.RenderPriority.Camera.Value + 3, function(dt)
	local camera = workspace.CurrentCamera
	if not camera then return end
	dt = math.min(dt, 1 / 20)

	-- Пружина (полунеявный Эйлер — устойчив на любом FPS).
	local accel = -STIFFNESS * offset - DAMPING * velocity
	velocity += accel * dt
	offset += velocity * dt
	if math.abs(offset) < 1e-4 and math.abs(velocity) < 1e-3 then
		offset, velocity = 0, 0
	end

	local current = camera.CFrame
	-- Снимаем прошлое смещение, если камеру в этом кадре никто не пересчитал.
	local base = (written and current == written) and current * writtenOffset:Inverse() or current

	if camera.CameraType ~= Enum.CameraType.Custom or offset == 0 then
		if written and current == written then camera.CFrame = base end
		written = nil
		writtenOffset = CFrame.identity
		return
	end

	-- Вниз по мировой вертикали + лёгкий кивок камеры.
	local worldShift = CFrame.new(0, offset, 0)
	local pitch = CFrame.Angles(math.clamp(offset, -1, 1) * PITCH / 0.3, 0, 0)
	local target = (worldShift * base) * pitch
	writtenOffset = base:Inverse() * target
	camera.CFrame = target
	written = target
end)
