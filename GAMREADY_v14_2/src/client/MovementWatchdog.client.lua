--------------------------------------------------------------------------------
-- MovementWatchdog (LocalScript) v20.146 — «ПОСЛЕ ЗАХОДА НЕ МОГУ ХОДИТЬ».
-- Раз в полсекунды проверяет свой персонаж. Если он дольше 3 с стоит со
-- скоростью 0 (или без прыжка), а причин нет - нет блокировки MovementLock
-- (окно престижа, мини-игры), нет мини-игры шахты/валуна, рагдолла, стана и
-- экрана загрузки, - просит сервер пересчитать скорость (SpeedResync) и
-- заново включает управление и обычную камеру. Ничего не ломает, если всё
-- в порядке: срабатывает только на «зависшего» игрока.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local MovementLock = require(ReplicatedStorage.Shared:WaitForChild("MovementLock"))
local resync = ReplicatedStorage.Shared:WaitForChild("SpeedResync", 30)

local function busy()
	return player:GetAttribute("AssetsLoaded") == false
		or player:GetAttribute("IntroActive") == true
		or player:GetAttribute("MineExpeditionActive") == true
		or player:GetAttribute("BoulderGameActive") == true
		or player:GetAttribute("Ragdolled") == true
		or player:GetAttribute("Stunned") == true
		or MovementLock.IsLocked()
end

local function controls()
	local playerScripts = player:FindFirstChild("PlayerScripts")
	local module = playerScripts and playerScripts:FindFirstChild("PlayerModule")
	if not module then return nil end
	local ok, result = pcall(function() return require(module):GetControls() end)
	return ok and result or nil
end

local stuckSince = nil
local lastFix = 0
while true do
	task.wait(0.5)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local stuck = humanoid and humanoid.Health > 0 and not busy()
		and (humanoid.WalkSpeed < 0.5 or (humanoid.JumpPower <= 0 and humanoid.UseJumpPower) or humanoid.PlatformStand)
	if stuck then
		stuckSince = stuckSince or os.clock()
		if os.clock() - stuckSince > 3 and os.clock() - lastFix > 3 then
			lastFix = os.clock()
			if resync then resync:FireServer() end
			local c = controls()
			if c then pcall(function() c:Enable() end) end
			if humanoid.PlatformStand and player:GetAttribute("Ragdolled") ~= true then humanoid.PlatformStand = false end
			local camera = workspace.CurrentCamera
			if camera and camera.CameraType == Enum.CameraType.Scriptable
				and player:FindFirstChildOfClass("PlayerGui"):GetAttribute("CameraHold") == nil then
				camera.CameraSubject = humanoid
				camera.CameraType = Enum.CameraType.Custom
			end
			warn("[MovementWatchdog] персонаж стоял без причины - вернул управление")
		end
	else
		stuckSince = nil
	end
end
