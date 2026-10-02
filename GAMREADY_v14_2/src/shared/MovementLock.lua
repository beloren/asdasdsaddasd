--------------------------------------------------------------------------------
-- MovementLock (v20.130) — БЕЗОПАСНАЯ БЛОКИРОВКА ХОДЬБЫ НА КЛИЕНТЕ.
--   MovementLock.Lock("Prestige", 120)   -- имя, предел в секундах
--   MovementLock.Unlock("Prestige")
-- Пока есть хоть одна блокировка, свой персонаж стоит (WalkSpeed/прыжок = 0,
-- держится каждый кадр - сервер может пересчитать скорость). Сняли все -
-- скорость возвращается к той, что задавал сервер. Блокировка с пределом
-- снимается сама, смерть/респавн снимает всё. Джойстик и управление НЕ
-- трогаются (Controls:Disable() на телефоне уничтожает джойстик).
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local MovementLock = {}
local locks = {} -- [имя] = момент истечения
-- v20.146: окно, ради которого стоим. Если оно не видно дольше 2 с (его
-- спрятал экран загрузки, его закрыли без Unlock) - блокировка снимается.
local guards = {} -- [имя] = { Gui, HiddenSince }
local saved = nil -- { Humanoid, WalkSpeed, JumpPower, JumpHeight }
local connection = nil
local player = Players.LocalPlayer

local function humanoidOf()
	local character = player and player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function guardVisible(gui)
	if not (gui and gui.Parent) then return false end
	if gui:IsA("LayerCollector") then return gui.Enabled end
	if gui:IsA("GuiObject") then return gui.Visible end
	return true
end

local function anyLock()
	local now = os.clock()
	for name, untilAt in locks do
		if now > untilAt then
			locks[name] = nil
			guards[name] = nil
		else
			local guard = guards[name]
			if guard then
				if guardVisible(guard.Gui) then
					guard.HiddenSince = nil
				else
					guard.HiddenSince = guard.HiddenSince or now
					if now - guard.HiddenSince > 2 then
						locks[name] = nil
						guards[name] = nil
					end
				end
			end
		end
	end
	return next(locks) ~= nil
end

local function release()
	if connection then connection:Disconnect() connection = nil end
	local entry = saved
	saved = nil
	if entry and entry.Humanoid and entry.Humanoid.Parent then
		local humanoid = entry.Humanoid
		humanoid.WalkSpeed = (entry.WalkSpeed and entry.WalkSpeed > 0) and entry.WalkSpeed or 16
		humanoid.JumpPower = (entry.JumpPower and entry.JumpPower > 0) and entry.JumpPower or 50
		humanoid.JumpHeight = (entry.JumpHeight and entry.JumpHeight > 0) and entry.JumpHeight or 7.2
	end
end

local function step()
	if not anyLock() then
		release()
		return
	end
	local humanoid = humanoidOf()
	if not humanoid then return end
	if not saved or saved.Humanoid ~= humanoid then
		saved = { Humanoid = humanoid, WalkSpeed = humanoid.WalkSpeed, JumpPower = humanoid.JumpPower, JumpHeight = humanoid.JumpHeight }
	end
	-- сервер поменял скорость, пока стоим, - запоминаем её как «вернуть»
	if humanoid.WalkSpeed > 0 then saved.WalkSpeed = humanoid.WalkSpeed end
	if humanoid.JumpPower > 0 then saved.JumpPower = humanoid.JumpPower end
	if humanoid.JumpHeight > 0 then saved.JumpHeight = humanoid.JumpHeight end
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid:Move(Vector3.zero)
end

-- guardGui (необязательно): ScreenGui/GuiObject окна - пока оно не видно,
-- блокировка не держит игрока (см. guards выше).
function MovementLock.Lock(name, maxSeconds, guardGui)
	locks[tostring(name)] = os.clock() + (tonumber(maxSeconds) or 60)
	guards[tostring(name)] = guardGui and { Gui = guardGui } or nil
	if not connection then connection = RunService.Heartbeat:Connect(step) end
	step()
end

function MovementLock.Unlock(name)
	locks[tostring(name)] = nil
	guards[tostring(name)] = nil
	if not anyLock() then release() end
end

function MovementLock.IsLocked()
	return anyLock()
end

if player then
	player.CharacterAdded:Connect(function()
		table.clear(locks)
		table.clear(guards)
		release()
	end)
end

return MovementLock
