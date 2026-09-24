--------------------------------------------------------------------------------
-- BuffService — временные баффы из жеод (см. ТЗ "касательно дропа из жеоды
-- можно добавить х2 деньги, х2 удача, х2 скорость/урон на минуту/5 минут").
--
-- Простой утилитарный сервис без зависимостей: хранит активные баффы
-- игрока в памяти (НЕ в сейв-профиле — временные баффы намеренно не
-- переживают выход из игры, это разовая награда за геоду, а не постоянный
-- прогресс), остальные сервисы читают текущий бонус через GetBonus/
-- GetMultiplier в СВОЕЙ уже существующей точке расчёта множителя:
--   • Деньги  → MonetizationService:GetCashMultiplier (тот же множитель,
--     что и денежные геймпассы — складывается с ними, как и они между собой).
--   • Скорость → MonetizationService:GetSpeedMultiplier (геймпасс Speed
--     Boost), плюс сразу пересчитывает WalkSpeed через CartService, иначе
--     бафф был бы виден только со следующего события (взял/бросил тележку).
--   • Урон    → MonetizationService:GetDamageMultiplier (геймпасс Double
--     Damage).
--   • Удача   → CrystalService (luckFor) — ДОБАВКА (не множитель): удача
--     на низких тирах близка к нулю, умножать там нечего.
--
-- Несколько источников одного вида баффа НЕ складываются — берётся
-- сильнейший, а слабее просто продлевает его действие (иначе разумно
-- фармить геоды ради бесконечно растущего х100 куда выгоднее, чем сама
-- игра, ровно то, о чём просили "максимально занерфить").
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage") -- для RemoteEvent панели баффов, см. PushState

local BuffService = {}
local Services = nil

local active = {} -- [player] = { [kind] = { Amount = number, ExpiresAt = os.clock(), Label = string } }

function BuffService:Init(services)
	Services = services
	Players.PlayerRemoving:Connect(function(player)
		active[player] = nil
	end)
end

local function reapply(player, kind)
	if kind == "Speed" and Services.CartService and Services.CartService.RecomputeWalkSpeed then
		Services.CartService:RecomputeWalkSpeed(player)
	end
	-- Money/Luck/Damage читаются "на лету" в их собственной точке расчёта
	-- (см. шапку файла) — пересчитывать сразу нечего, следующая продажа/
	-- ролл/удар сам увидит актуальное значение.
end

-- kind: "Money" | "Speed" | "Damage" | "Luck". amount — БОНУС сверх 1.0
-- (0.5 = +50%, для Money/Speed/Damage читается как множитель 1+amount; для
-- Luck — как прямая добавка к значению удачи, см. шапку файла).
function BuffService:Grant(player, kind, amount, durationSeconds, label)
	if not player or not player.Parent then return end
	amount = tonumber(amount) or 0
	durationSeconds = tonumber(durationSeconds) or 60
	if amount <= 0 or durationSeconds <= 0 then return end

	active[player] = active[player] or {}
	local now = os.clock()
	local existing = active[player][kind]
	local expiresAt = now + durationSeconds
	if existing and existing.ExpiresAt > now and existing.Amount >= amount then
		-- Уже активен равный-или-сильнее бафф того же вида — просто
		-- продлеваем действие, не показываем игроку "даунгрейд".
		existing.ExpiresAt = math.max(existing.ExpiresAt, expiresAt)
	else
		active[player][kind] = { Amount = amount, ExpiresAt = expiresAt, Label = label }
	end
	reapply(player, kind)

	task.delay(durationSeconds + 0.05, function()
		local entry = active[player] and active[player][kind]
		if entry and entry.ExpiresAt <= os.clock() then
			active[player][kind] = nil
			reapply(player, kind)
		end
	end)
end

-- Текущий активный бонус (0, если ничего не активно или бафф истёк).
function BuffService:GetBonus(player, kind)
	local playerActive = active[player]
	local entry = playerActive and playerActive[kind]
	if not entry then return 0 end
	if entry.ExpiresAt <= os.clock() then
		playerActive[kind] = nil
		return 0
	end
	return entry.Amount
end

-- v18: «заряды» баффа (Mutation Magnet): уменьшает Amount; на нуле бафф снят.
function BuffService:Consume(player, kind, amount)
	local playerActive = active[player]
	local entry = playerActive and playerActive[kind]
	if not entry or entry.ExpiresAt <= os.clock() then return false end
	entry.Amount -= (amount or 1)
	if entry.Amount <= 0 then
		playerActive[kind] = nil
		reapply(player, kind)
	end
	pcall(function() self:PushState(player) end)
	return true
end

-- Удобная обёртка для мест, которые считают именно множитель (1 = нет бонуса).
function BuffService:GetMultiplier(player, kind)
	return 1 + self:GetBonus(player, kind)
end

-- Для HUD/таймера, если понадобится показать активные баффы игроку.
function BuffService:GetActiveBuffs(player)
	local list = {}
	local playerActive = active[player]
	if not playerActive then return list end
	local now = os.clock()
	for kind, entry in playerActive do
		if entry.ExpiresAt > now then
			table.insert(list, { Kind = kind, Amount = entry.Amount, SecondsLeft = entry.ExpiresAt - now, Label = entry.Label })
		end
	end
	return list
end

--------------------------------------------------------------------------------
-- РЕПЛИКАЦИЯ ПАНЕЛИ БАФФОВ
--
-- Клиент рисует иконки активных баффов (см. client/BuffBar.client.lua), но
-- сам он НЕ знает ни сроков, ни величин — всё это живёт на сервере.
-- Поэтому раз в секунду отправляем снимок активных баффов тому игроку,
-- которого он касается. Секунда — достаточно для обратного отсчёта на
-- иконке и пренебрежимо мало по трафику (несколько чисел на игрока).
--------------------------------------------------------------------------------
local buffStateRemote = ReplicatedStorage.Shared:FindFirstChild("BuffState")
if not buffStateRemote then
	buffStateRemote = Instance.new("RemoteEvent")
	buffStateRemote.Name = "BuffState"
	buffStateRemote.Parent = ReplicatedStorage.Shared
end

function BuffService:PushState(player)
	if not (player and player.Parent) then return end
	local list = self:GetActiveBuffs(player)
	-- SecondsLeft округляем: дробные доли секунды на иконке не нужны, а
	-- целые числа лучше жмутся и не дёргают текст каждый кадр.
	for _, entry in list do
		entry.SecondsLeft = math.max(0, math.floor(entry.SecondsLeft))
	end
	buffStateRemote:FireClient(player, list)
end

task.spawn(function()
	while true do
		task.wait(1)
		for _, player in Players:GetPlayers() do
			-- pcall: один упавший игрок не должен останавливать рассылку
			-- всем остальным.
			pcall(function() BuffService:PushState(player) end)
		end
	end
end)

return BuffService
