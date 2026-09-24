--------------------------------------------------------------------------------
-- EnsureTouchControls
--
-- ЕДИНСТВЕННАЯ ЗАДАЧА: гарантировать, что джойстик и кнопка прыжка на
-- телефоне всегда на экране и включены.
--
--------------------------------------------------------------------------------
-- ПОЧЕМУ ЭТОТ СКРИПТ ВСЁ ЕЩЁ НУЖЕН
--
-- MoonAnimationTest (интро) по прямому запросу больше НЕ отключает
-- управление вообще — ни при заходе, ни во время вступительной сцены. Это
-- убирает главный источник бага «нет джойстика», но не единственный
-- ТЕОРЕТИЧЕСКИЙ: TouchGui — обычный ScreenGui в PlayerGui, и его в
-- принципе может погасить что угодно постороннее — чужой скрипт, будущая
-- правка, гонка при респавне персонажа. Этот файл ничего не знает про
-- интро и вообще ни про какую игровую логику — он единственная точка
-- ответственности за один факт: «на тач-устройстве управление на экране
-- есть и включено», и держит его безусловно, всю сессию.
--
-- ПОЧЕМУ ПРОВЕРКА ПОСТОЯННАЯ, А НЕ ОДНОРАЗОВАЯ
--
-- TouchGui — не статичный объект: PlayerModule может пересоздать его на
-- новом персонаже, и в момент между уничтожением старого и появлением
-- нового объекта его нет вовсе. Одноразовая проверка «через N секунд после
-- захода» ловит только один момент времени и промахивается мимо остальных.
-- Цикл раз в секунду стоит примерно ничего (проверка нескольких детей
-- PlayerGui), а закрывает весь класс проблем разом.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

if not UserInputService.TouchEnabled then
	-- На устройстве без сенсорного экрана джойстику взяться неоткуда и
	-- незачем — выходим сразу, чтобы не гонять пустой цикл всю сессию.
	return
end

-- Имена ScreenGui, в которых Roblox держит экранное управление. ControlGui —
-- легаси-имя, встречается на старых клиентах; проверяем оба, это дешевле,
-- чем разбираться, какое из них актуально на конкретной сборке.
local CONTROL_GUI_NAMES = {
	TouchGui = true,
	ControlGui = true,
}

local function enableControlGuis()
	local found = false
	for _, gui in playerGui:GetChildren() do
		if gui:IsA("ScreenGui") and CONTROL_GUI_NAMES[gui.Name] then
			found = true
			if not gui.Enabled then
				gui.Enabled = true
			end
		end
	end
	return found
end

-- Достаём стандартный модуль управления. Он появляется в PlayerScripts не
-- мгновенно, поэтому ждём с таймаутом и не падаем, если его нет вовсе.
local function getControls()
	local playerScripts = player:FindFirstChild("PlayerScripts")
	if not playerScripts then return nil end
	local moduleScript = playerScripts:FindFirstChild("PlayerModule")
	if not moduleScript then return nil end
	local ok, controls = pcall(function()
		return require(moduleScript):GetControls()
	end)
	if ok then return controls end
	return nil
end

-- ОСНОВНОЙ ЦИКЛ. Работает всю сессию, безусловно — никаких проверок
-- IntroActive или чего-либо ещё: задача не «дождаться подходящего момента»,
-- а «управление всегда доступно».
task.spawn(function()
	while true do
		task.wait(1)
		if not enableControlGuis() then
			-- Самого ScreenGui нет вовсе (Enable() ещё не успел его
			-- создать, либо что-то его уничтожило) — поднимаем через
			-- PlayerModule. Enable() идемпотентен, повторный вызов на уже
			-- включённом управлении ничего не ломает.
			local controls = getControls()
			if controls then
				pcall(function() controls:Enable() end)
			end
		end
	end
end)

-- РЕСПАВН. PlayerModule пересоздаёт управление на новом персонаже, и в этот
-- момент TouchGui снова заменяется новым объектом. Пробегаемся сразу после
-- появления персонажа несколько раз подряд, не дожидаясь секундного цикла:
-- пропасть кнопкам ходьбы даже на секунду после смерти — очень заметно.
player.CharacterAdded:Connect(function()
	task.spawn(function()
		for _ = 1, 6 do
			task.wait(0.25)
			enableControlGuis()
		end
	end)
end)
