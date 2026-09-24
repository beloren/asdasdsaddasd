--------------------------------------------------------------------------------
-- TutorialService — ОБУЧЕНИЕ v7 (см. Config.Tutorial).
--
-- ЧТО ЭТО ЗАМЕНИЛО. Весь прежний гайд жил на КЛИЕНТЕ, внутри одной функции
-- showInteractiveTutorial в CustomCartUI.client.lua (~1560 строк). Оттуда
-- следовали три проблемы, которые нельзя было починить, не переписав его:
--   • прогресс не сохранялся — `local tutorialStage = 1` на каждом заходе,
--     то есть вылет на шестом шаге отбрасывал игрока в самое начало;
--   • условия переходов читали клиентские атрибуты, часть которых после
--     переделок добычи (экспедиция) и тележки (упаковка) стала значить не
--     то, что написано в задании, — гайд вёл туда, где ничего не произойдёт;
--   • шаги были кодом, а не данными, поэтому правка текста требовала
--     править машину состояний.
--
-- ЗДЕСЬ ВСЁ НАОБОРОТ: шаги — таблица Config.Tutorial.Steps, состояние живёт
-- в профиле (Data.TutorialStep), условия проверяет сервер. Клиент
-- (TutorialUI.client.lua) получает готовую карточку "что показать" и умеет
-- ровно одно — попросить перейти к следующей реплике.
--
-- ВЗАИМОДЕЙСТВИЕ С ОСТАЛЬНЫМИ СЕРВИСАМИ — через два узких входа:
--   Count(player, key, amount) — "игрок что-то сделал" (сломал базовый
--                                валун, продал руду, закончил экспедицию);
--   SetFlag(player, key, value) — "состояние мира изменилось" (шахта
--                                 починена, тележка поставлена).
-- Оба безопасны при выключенном/пройденном обучении: просто выходят.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Sfx = require(ReplicatedStorage.Shared.Sfx)

local TutorialService = {}

local Services = nil
local states = {}        -- [player] = { Step, Phase, LineIndex, Counters, Flags }
local stateRemote = nil  -- сервер → клиент: что рисовать
local actionRemote = nil -- клиент → сервер: "Advance" / "Skip"
local hintRemote = nil   -- сервер → клиент: одноразовая контекстная подсказка

local PHASE_LINES = "Lines"   -- печатаем реплики ДО задания
local PHASE_TASK = "Task"     -- свёрнутая плашка, игрок выполняет
local PHASE_DONE = "Done"     -- реплика-реакция ПОСЛЕ выполнения

local function steps()
	return Config.Tutorial.Steps or {}
end

local function stepAt(index)
	return steps()[index]
end

--------------------------------------------------------------------------------
-- СОСТОЯНИЕ
--------------------------------------------------------------------------------

-- Список ScreenGui, которые обучение прячет до тех пор, пока шаг с полем
-- Reveal их не откроет. Держим МИНИМАЛЬНЫМ: прошлый гайд прятал половину
-- интерфейса до восьмого шага, а восьмой шаг при части конфигураций вообще
-- пропускался — и игрок доигрывал сессию без журнала квестов.
local HIDDEN_UNTIL_REVEALED = { "QuestUi" }

function TutorialService:Init(services)
	Services = services

	stateRemote = Instance.new("RemoteEvent")
	stateRemote.Name = "TutorialStateEvent"
	stateRemote.Parent = ReplicatedStorage.Shared

	hintRemote = Instance.new("RemoteEvent")
	hintRemote.Name = "TutorialHintEvent"
	hintRemote.Parent = ReplicatedStorage.Shared

	actionRemote = Instance.new("RemoteEvent")
	actionRemote.Name = "TutorialActionEvent"
	actionRemote.Parent = ReplicatedStorage.Shared
	actionRemote.OnServerEvent:Connect(function(player, action)
		-- Клиент не присылает ни номер шага, ни прогресс — только намерение.
		-- Подделать переход через него невозможно: сервер сам решает, что
		-- сейчас за фаза и можно ли из неё уйти.
		if action == "Advance" then
			self:_advance(player)
		elseif action == "Skip" then
			self:_skip(player)
		elseif action == "Ready" then
			-- КЛИЕНТ ПОДНЯЛСЯ И ГОТОВ ПРИНИМАТЬ.
			--
			-- Без этого обучение выглядело полностью мёртвым у части
			-- игроков: SetupPlayer шлёт первую карточку в момент выдачи
			-- участка, а LocalScript к этой секунде мог ещё не успеть
			-- подписаться на OnClientEvent. Пакет, отправленный до
			-- подписки, Roblox не буферизует — он просто теряется, и на
			-- экране не появлялось НИЧЕГО до первого случайного
			-- обновления прогресса.
			self:_push(player)
			self:_setHiddenUi(player, states[player] ~= nil)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

function TutorialService:Start()
	-- Фоновая проверка целей типа Flag/Counter, которые могли измениться в
	-- обход Count/SetFlag (например, игрок купил шахту ещё до того, как
	-- обучение дошло до этого шага). Интервал намеренно ленивый: это
	-- страховка, а не основной путь — основной идёт через Count/SetFlag и
	-- реагирует мгновенно.
	task.spawn(function()
		local tick = 0
		while true do
			task.wait(1)
			tick += 1
			for player, state in states do
				if player.Parent and state.Phase == PHASE_TASK then
					local ok, err = pcall(function() self:_checkGoal(player) end)
					if not ok then warn("[TutorialService] проверка цели упала:", err) end
					-- ЦЕЛЬ СТРЕЛКИ ЖИВАЯ, а не снимок на момент входа в шаг:
					-- валун ломается и респавнится, НПС может достроиться
					-- позже участка, тележка появляется только после
					-- постановки. Без переотправки стрелка одиножды
					-- указывала в пустоту (или никуда) и больше не
					-- восстанавливалась до конца шага.
					if tick % 2 == 0 and states[player] then
						pcall(function() self:_push(player) end)
					end
				end
			end
		end
	end)
end

function TutorialService:SetupPlayer(player)
	local data = Services.DataService:GetGeodeData(player)
	if not data then return end

	-- Флаг починки шахты восходит к профилю, а не к тиру: тир шахты у
	-- нового игрока и так 1 (MineIndex = 0), и отличить "тир 1, потому что
	-- ещё не чинил" от "тир 1, потому что только что сделал престиж"
	-- по нему невозможно. См. Config.Mine.Broken — почему не тир 0.
	-- Через IsMineRepaired, а не напрямую из профиля: при выключенном
	-- обучении (Config.Tutorial.Enabled = false) шахта обязана считаться
	-- починенной, иначе магазин вечно показывал бы карточку починки, а
	-- экспедиция была бы заблокирована навсегда.
	player:SetAttribute("MineRepaired", self:IsMineRepaired(player))

	if not self:IsRequired(player) then
		player:SetAttribute("NeedsTutorial", false)
		self:_setHiddenUi(player, false)
		return
	end

	player:SetAttribute("NeedsTutorial", true)
	-- Верхняя граница #steps() + 1, а не #steps(): TutorialStep пишется
	-- как "следующий шаг" уже в момент выполнения текущего (см.
	-- _finishStep). Игрок, вышедший на прощальной реплике последнего шага,
	-- приходит с #steps() + 1 — обучение у него просто завершается.
	local saved = math.clamp(tonumber(data.TutorialStep) or 1, 1, #steps() + 1)
	states[player] = {
		Step = saved,
		Phase = nil,
		LineIndex = 1,
		Counters = {},
		Flags = {},
		Revealed = {},
	}
	-- Reveal ПРОЙДЕННЫХ шагов тоже действует: раньше открывался только
	-- Reveal текущего шага, и перезаход на шаг ПОСЛЕ открывающего снова
	-- прятал интерфейс до конца обучения.
	for index = 1, saved - 1 do
		local earlier = stepAt(index)
		for _, name in (earlier and earlier.Reveal) or {} do
			states[player].Revealed[name] = true
		end
	end
	-- Прячем то, что шаги откроют позже. Делается ПОСЛЕ восстановления
	-- шага: если игрок вернулся на шаг, который уже что-то открыл, это
	-- переоткроется ниже в _enterStep.
	self:_setHiddenUi(player, true)
	-- restoring = true ТОЛЬКО если игрок реально возвращается на
	-- пройденный ранее шаг. Раньше здесь стояла жёсткая true — и вступление
	-- не видел вообще НИКТО, даже игрок, зашедший в игру первый раз в жизни:
	-- первый шаг сразу сворачивался в плашку-задание, которую нечем закрыть.
	self:_enterStep(player, saved, saved > 1)
end

function TutorialService:CleanupPlayer(player)
	self:_save(player)
	states[player] = nil
end

function TutorialService:IsRequired(player)
	if Config.Tutorial.Enabled == false then return false end
	local data = Services.DataService:GetGeodeData(player)
	return data ~= nil and (tonumber(data.TutorialVersion) or 0) < Config.Tutorial.Version
end

function TutorialService:IsActive(player)
	return states[player] ~= nil
end

function TutorialService:GetStepId(player)
	local state = states[player]
	local step = state and stepAt(state.Step)
	return step and step.Id or nil
end

--------------------------------------------------------------------------------
-- ПОЧИНКА ШАХТЫ
--
-- Живёт здесь, а не в MineService/UpgradeService, по одной причине: это
-- состояние обучения, и читают его сразу трое (MineService — пускать ли в
-- экспедицию, PlotService — красить ли шахту в чёрный, сам туториал — цель
-- шага). Единая точка правды дешевле, чем три согласованные копии.
--------------------------------------------------------------------------------

function TutorialService:IsMineRepaired(player)
	if Config.Tutorial.Enabled == false then return true end
	local data = Services.DataService:GetGeodeData(player)
	if not data then
		-- Профиль ещё не загружен — считаем шахту ПОЧИНЕННОЙ. Это
		-- осознанно: ложное "сломана" заблокировало бы экспедицию
		-- действующему игроку, а ложное "починена" в худшем случае даст
		-- лишний заход в шахту на долю секунды до загрузки профиля.
		return true
	end
	return data.MineRepaired == true
end

function TutorialService:RepairMine(player)
	local data = Services.DataService:GetGeodeData(player)
	if not data or data.MineRepaired == true then return false end
	data.MineRepaired = true
	player:SetAttribute("MineRepaired", true)

	local plot = Services.PlotService and Services.PlotService:GetPlot(player)
	if plot and Services.PlotService.RestoreMineLook then
		pcall(function() Services.PlotService:RestoreMineLook(plot) end)
	end
	-- Валуны на базе привязаны к тиру шахты — после починки они обязаны
	-- пересобраться, иначе остались бы стоять на стартовом тире.
	if Services.RockService and Services.RockService.RefreshPlotBoulders then
		pcall(function() Services.RockService:RefreshPlotBoulders(player) end)
	end
	self:SetFlag(player, "MineRepaired", true)
	return true
end

--------------------------------------------------------------------------------
-- ВХОДЫ ДЛЯ ДРУГИХ СЕРВИСОВ
--------------------------------------------------------------------------------

function TutorialService:Count(player, key, amount)
	local state = states[player]
	if not state then return end
	state.Counters[key] = (state.Counters[key] or 0) + (tonumber(amount) or 1)
	if state.Phase == PHASE_TASK then
		self:_checkGoal(player)
		-- Цель могла не выполниться, но прогресс изменился — плашка
		-- задания показывает счётчик, её надо обновить в любом случае.
		if states[player] and states[player].Phase == PHASE_TASK then
			self:_push(player)
		end
	end
end

function TutorialService:SetFlag(player, key, value)
	local state = states[player]
	if not state then return end
	state.Flags[key] = value ~= false
	if state.Phase == PHASE_TASK then
		self:_checkGoal(player)
	end
end

--------------------------------------------------------------------------------
-- КОНТЕКСТНЫЕ ПОДСКАЗКИ (слой 2, см. Config.Tutorial.Hints).
--
-- Намеренно НЕ часть машины шагов: они не блокируют игру, не идут по
-- порядку и работают всю жизнь профиля, а не только в первые две минуты.
-- Разовость хранится в том же Data.SeenHints, где и прежние одноразовые
-- подсказки, — отдельного поля профиля заводить не нужно.
--------------------------------------------------------------------------------
function TutorialService:ShowHint(player, hintKey)
	local text = Config.Tutorial.Hints and Config.Tutorial.Hints[hintKey]
	if not text then return false end
	local data = Services.DataService:GetGeodeData(player)
	if not data then return false end
	data.SeenHints = data.SeenHints or {}
	if data.SeenHints[hintKey] then return false end
	-- Во время самого пролога подсказки не показываются: два источника
	-- текста на экране разом — верный способ, чтобы не прочитали ни один.
	-- Но и НЕ ТЕРЯЮТСЯ: раньше жеода с базового валуна в прологе (шанс
	-- 18% на валун) навсегда съедала подсказку про жеоды. Теперь ключ
	-- встаёт в очередь и показывается после пролога (_flushQueuedHints).
	if states[player] then
		data.QueuedHints = data.QueuedHints or {}
		if not table.find(data.QueuedHints, hintKey) then
			table.insert(data.QueuedHints, hintKey)
		end
		return false
	end
	data.SeenHints[hintKey] = true
	hintRemote:FireClient(player, {
		Speaker = Config.Tutorial.SpeakerName,
		Portrait = Config.Tutorial.PortraitImageId,
		Text = text,
	})
	return true
end

-- Подсказки, отложенные на время пролога. Идут по одной с паузой —
-- очередь из трёх окон подряд читалась бы как ещё один экран текста.
function TutorialService:_flushQueuedHints(player)
	local data = Services.DataService:GetGeodeData(player)
	local queued = data and data.QueuedHints
	if not queued or #queued == 0 then return end
	data.QueuedHints = nil
	local gap = tonumber(Config.Tutorial.QueuedHintGapSeconds) or 8
	task.spawn(function()
		for index, hintKey in queued do
			task.wait(index == 1 and 3 or gap)
			if not player.Parent then return end
			pcall(function() self:ShowHint(player, hintKey) end)
		end
	end)
end

--------------------------------------------------------------------------------
-- МАШИНА ШАГОВ
--------------------------------------------------------------------------------

function TutorialService:_enterStep(player, index, restoring)
	local state = states[player]
	if not state then return end
	local step = stepAt(index)
	if not step then
		self:_complete(player)
		return
	end
	state.Step = index
	state.LineIndex = 1

	-- СЧЁТЧИК ШАГА СТАРТУЕТ С НУЛЯ. Count копит прогресс всегда, в том
	-- числе на чужих шагах, — и без сброса продажа руды из рюкзака на
	-- втором шаге закрывала последний шаг «продай тележку» в ту же
	-- секунду, как игрок до него доходил. KeepEarlyProgress — для шагов,
	-- где забегать вперёд правильно (валуны, разбитые под вступительную
	-- реплику, засчитываются).
	local goal = step.Goal
	if goal and goal.Kind == "Counter" and not step.KeepEarlyProgress then
		for _, key in goal.Keys or { goal.Key } do
			state.Counters[key] = nil
		end
	end

	-- Разовая выдача денег при ВХОДЕ в шаг (шаг «первый апгрейд»: игроку
	-- нужно на что-то купить). Отмечается в профиле, чтобы перезаход не
	-- выдавал её повторно, а _finish не выдал ту же награду второй раз.
	if step.GrantMoney and step.GrantMoney > 0 then
		local data = Services.DataService:GetGeodeData(player)
		if data and data.TutorialRewardGiven ~= true then
			data.TutorialRewardGiven = true
			Services.DataService:AddMoney(player, step.GrantMoney)
		end
	end

	-- КАКУЮ ФАЗУ ПОКАЗАТЬ.
	--
	-- Шаг с целью "Ack" закрывается ТОЛЬКО кнопкой "Далее", а кнопка живёт
	-- на диалоговом окне — в свёрнутой плашке-задании её нет. Поэтому такой
	-- шаг обязан открыться диалогом при любых обстоятельствах, включая
	-- перезаход. Иначе он превращается в тупик: задание висит, выполнить
	-- его нечем, и единственный выход — "пропустить обучение".
	--
	-- Для остальных шагов при ВОССТАНОВЛЕНИИ реплики не проигрываем: игрок
	-- их уже читал, и заставлять прокликивать вступление после каждого
	-- вылета — быстрый способ приучить жать "пропустить".
	local hasLines = step.Lines ~= nil and #step.Lines > 0
	local isTalkStep = step.Goal ~= nil and step.Goal.Kind == "Ack"
	if hasLines and (isTalkStep or not restoring) then
		state.Phase = PHASE_LINES
	else
		state.Phase = PHASE_TASK
	end

	if step.Reveal then
		for _, name in step.Reveal do
			state.Revealed[name] = true
		end
		self:_applyReveal(player)
	end

	self:_save(player)
	self:_push(player)

	if state.Phase == PHASE_TASK and step.Goal and step.Goal.Kind == "Ack" then
		-- Шаг-разговор, у которого не осталось реплик (все прочитаны до
		-- перезахода), закрываем сразу. Показать его плашкой нельзя —
		-- закрыть её было бы нечем.
		self:_finishStep(player)
	elseif state.Phase == PHASE_TASK then
		-- Цель могла быть выполнена ещё до того, как обучение до неё
		-- дошло (игрок сам нашёл торговца и купил шахту). Проверяем сразу,
		-- иначе он застрял бы на задании, которое уже сделал.
		self:_checkGoal(player)
	end
end

function TutorialService:_advance(player)
	local state = states[player]
	if not state then return end
	local step = stepAt(state.Step)
	if not step then return end

	if state.Phase == PHASE_LINES then
		state.LineIndex += 1
		if state.LineIndex > #(step.Lines or {}) then
			-- ШАГ-РАЗГОВОР ЗАКАНЧИВАЕТСЯ ВМЕСТЕ С РЕПЛИКАМИ.
			--
			-- Раньше он отсюда падал в PHASE_TASK — и это был тупик:
			-- свёрнутая плашка-задание не имеет кнопки "Далее", а закрыть
			-- шаг с целью "Ack" больше нечем. Игрок дочитывал вступление,
			-- получал плашку "подойди к шахтёру", подходил к шахтёру — и
			-- не происходило ровно ничего, потому что подход к НПС этот
			-- шаг никогда и не закрывал.
			if step.Goal and step.Goal.Kind == "Ack" then
				self:_finishStep(player)
			else
				state.Phase = PHASE_TASK
				self:_push(player)
				self:_checkGoal(player)
			end
		else
			self:_push(player)
		end
		return
	end

	if state.Phase == PHASE_DONE then
		state.LineIndex += 1
		if state.LineIndex > #(step.Done or {}) then
			self:_enterStep(player, state.Step + 1)
		else
			self:_push(player)
		end
		return
	end

	-- Фаза задания: "Далее" закрывает только шаги-разговоры (Goal.Kind ==
	-- "Ack"). На обычном задании кнопки нет вообще, так что сюда приходит
	-- либо подделанный пакет, либо гонка — молча игнорируем.
	if state.Phase == PHASE_TASK and step.Goal and step.Goal.Kind == "Ack" then
		self:_finishStep(player)
	end
end

function TutorialService:_goalProgress(player, step)
	local state = states[player]
	local goal = step.Goal
	if not (state and goal) then return 0, 1 end
	if goal.Kind == "Ack" then
		return 0, 1
	elseif goal.Kind == "Counter" then
		-- Keys (список) вместо Key — НЕСКОЛЬКО РАВНОПРАВНЫХ СПОСОБОВ
		-- закрыть шаг: засчитывается сумма по всем ключам. Нужно там, где
		-- игрок мог прийти к той же цели своим путём (продать руду руками,
		-- а не рейсом тележки) — требовать после этого "правильный"
		-- способ значит наказывать за сообразительность.
		if goal.Keys then
			local total = 0
			for _, key in goal.Keys do
				-- Скобки обязательны: без них "or 0" относится ко всему
				-- сложению, а не к чтению счётчика.
				total = total + (state.Counters[key] or 0)
			end
			return total, math.max(1, tonumber(goal.Target) or 1)
		end
		return state.Counters[goal.Key] or 0, math.max(1, tonumber(goal.Target) or 1)
	elseif goal.Kind == "Flag" then
		local done = state.Flags[goal.Key] == true or player:GetAttribute(goal.Key) == true
		return done and 1 or 0, 1
	end
	return 0, 1
end

function TutorialService:_checkGoal(player)
	local state = states[player]
	if not state or state.Phase ~= PHASE_TASK then return end
	local step = stepAt(state.Step)
	if not step or not step.Goal then return end
	if step.Goal.Kind == "Ack" then return end -- закрывается только кнопкой
	local current, target = self:_goalProgress(player, step)
	if current >= target then
		self:_finishStep(player)
	end
end

function TutorialService:_finishStep(player)
	local state = states[player]
	if not state then return end
	local step = stepAt(state.Step)
	if not step then return end

	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	pcall(Sfx.play, "TutorialStepComplete", root)

	-- ПРОГРЕСС ФИКСИРУЕТСЯ В МОМЕНТ ВЫПОЛНЕНИЯ, а не после прощальной
	-- реплики. Счётчики в профиль не пишутся, поэтому раньше вылет на
	-- реплике "Для такой добычи нужна тележка" заставлял заново идти в
	-- экспедицию. Теперь перезаход сразу открывает следующий шаг.
	local data = Services.DataService:GetGeodeData(player)
	if data then data.TutorialStep = state.Step + 1 end

	if step.Done and #step.Done > 0 then
		state.Phase = PHASE_DONE
		state.LineIndex = 1
		self:_push(player)
	else
		self:_enterStep(player, state.Step + 1)
	end
end

function TutorialService:_skip(player)
	local state = states[player]
	if not state then return end
	-- Пропуск НЕ выдаёт награду, но ЧИНИТ ШАХТУ и открывает первую
	-- тележку. Раньше пропустивший оставался со сломанной шахтой, починка
	-- у него стоила $220 (бесплатна только внутри обучения), денег ноль,
	-- а объяснить, где их взять, было уже некому. Базовый цикл
	-- (шахта → тележка → банк) обязан быть доступен сразу.
	--
	-- Порядок важен: сперва _finish (состояние обучения снято), потом
	-- починка. Иначе RepairMine → SetFlag закрывал бы текущий шаг со
	-- звуком и прощальной репликой за мгновение до закрытия окна, а тост
	-- "возьми упаковку в руки" глушился бы как тост во время обучения.
	self:_finish(player, false)
	pcall(function() self:RepairMine(player) end)
	if Services.CartService and Services.CartService.IsCartUnlocked
		and not Services.CartService:IsCartUnlocked(player) then
		pcall(function() Services.CartService:UnlockFirstCart(player) end)
	end
end

function TutorialService:_complete(player)
	self:_finish(player, true)
end

function TutorialService:_finish(player, rewarded)
	local state = states[player]
	if not state then return end
	states[player] = nil

	local data = Services.DataService:GetGeodeData(player)
	if data then
		data.TutorialVersion = Config.Tutorial.Version
		data.TutorialCompletedAt = os.time() -- см. QuestService:_scheduleTips
		data.TutorialStep = #steps()
	end
	player:SetAttribute("NeedsTutorial", false)
	self:_setHiddenUi(player, false)

	if rewarded then
		-- Деньги могли уже прийти при входе в шаг FirstUpgrade (GrantMoney).
		local reward = Config.Tutorial.Reward
		if reward and reward.Money and reward.Money > 0
			and not (data and data.TutorialRewardGiven == true) then
			if data then data.TutorialRewardGiven = true end
			Services.DataService:AddMoney(player, reward.Money)
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		pcall(Sfx.play, "TutorialComplete", root)
		pcall(function()
			Services.DataService:AwardBadge(player, Config.Badges and Config.Badges.TutorialComplete)
		end)
	end

	pcall(function() Services.DataService:SaveProfile(player) end)
	-- Временная защита новичка снимается вместе с обучением — иначе она
	-- продолжала бы висеть непонятно до какого момента.
	if Services.CombatService and Services.CombatService.FinishTutorialProtection then
		pcall(function() Services.CombatService:FinishTutorialProtection(player) end)
	end
	-- Панель квестов до этого момента скрыта (см. QuestUI.client.lua) —
	-- без явного SendState она не появится, пока не прилетит случайный
	-- следующий апдейт по прогрессу какого-нибудь квеста.
	if Services.QuestService then
		pcall(function() Services.QuestService:SendState(player) end)
		pcall(function() Services.QuestService:_scheduleTips(player) end)
	end

	stateRemote:FireClient(player, { Phase = "Finished" })
	self:_flushQueuedHints(player)
end

--------------------------------------------------------------------------------
-- ОТПРАВКА СОСТОЯНИЯ КЛИЕНТУ
--------------------------------------------------------------------------------

-- Цель для стрелки/трейла. Отдаём КЛИЕНТУ САМ Instance, а не строковый
-- дескриптор: Roblox реплицирует ссылки на инстансы через RemoteEvent
-- как есть, и это избавляет клиент от собственного поиска по миру —
-- ровно того поиска, который в прошлом гайде и разъезжался с игрой каждый
-- раз, когда что-то в мире переименовывали.
function TutorialService:_resolveTarget(player, kind)
	if not kind then return nil end
	local plot = Services.PlotService and Services.PlotService:GetPlot(player)
	local content = plot and plot.Content

	if kind == "Bank" then
		return Services.WorldService and Services.WorldService:GetSellZone() or nil
	elseif kind == "BaseBoulder" then
		if Services.RockService and Services.RockService.GetNearestPlotBoulder then
			local ok, model = pcall(Services.RockService.GetNearestPlotBoulder, Services.RockService, player)
			if ok then return model end
		end
		return nil
	elseif kind == "Cart" then
		local cart = Services.CartService and (Services.CartService:GetHeldCart(player)
			or Services.CartService:GetOwnedCart(player))
		return cart and cart.Root or nil
	elseif content then
		-- MinerNPC / UpgradeShopNPC и любые другие именованные объекты на
		-- участке ищутся по имени — они строятся кодом, имена стабильны.
		return content:FindFirstChild(kind, true)
	end
	return nil
end

function TutorialService:_push(player)
	local state = states[player]
	if not state then return end
	local step = stepAt(state.Step)
	if not step then return end

	local text
	if state.Phase == PHASE_LINES then
		text = (step.Lines or {})[state.LineIndex]
	elseif state.Phase == PHASE_DONE then
		text = (step.Done or {})[state.LineIndex]
	end

	local current, target = self:_goalProgress(player, step)

	stateRemote:FireClient(player, {
		Phase = state.Phase,
		StepIndex = state.Step,
		StepCount = #steps(),
		Id = step.Id,
		Speaker = Config.Tutorial.SpeakerName,
		Portrait = Config.Tutorial.PortraitImageId,
		Text = text,
		Short = step.Short,
		Task = step.Task,
		Progress = current,
		ProgressTarget = target,
		-- Счётчик в плашке нужен только там, где он реально что-то
		-- значит: "0/2 камня" помогает, "0/1 продажа" — шум.
		ShowProgress = step.Goal ~= nil and step.Goal.Kind == "Counter" and target > 1,
		Target = self:_resolveTarget(player, step.Target),
		-- Пропуск доступен на любом шаге: последний шаг (апгрейд) без
		-- него мог бы стать тупиком, если игрок успел потратить деньги.
		CanSkip = true,
	})
end

-- Цель в мире может появиться/исчезнуть уже после отправки состояния
-- (валун сломали и он респавнится, тележку поставили). Клиент сам за этим
-- не следит — переотправляем текущее состояние по таймеру, пока идёт шаг.
function TutorialService:RefreshTarget(player)
	local state = states[player]
	if state then self:_push(player) end
end

--------------------------------------------------------------------------------
-- СКРЫТИЕ UI НА ВРЕМЯ ОБУЧЕНИЯ
--------------------------------------------------------------------------------
function TutorialService:_applyReveal(player)
	local state = states[player]
	stateRemote:FireClient(player, {
		Phase = "Reveal",
		Hidden = self:_hiddenList(state),
	})
end

function TutorialService:_hiddenList(state)
	local hidden = {}
	for _, name in HIDDEN_UNTIL_REVEALED do
		if not (state and state.Revealed[name]) then
			table.insert(hidden, name)
		end
	end
	return hidden
end

function TutorialService:_setHiddenUi(player, hide)
	stateRemote:FireClient(player, {
		Phase = "Reveal",
		Hidden = hide and self:_hiddenList(states[player]) or {},
	})
end

function TutorialService:_save(player)
	local state = states[player]
	local data = Services.DataService:GetGeodeData(player)
	if not (state and data) then return end
	-- В фазе Done задание шага УЖЕ выполнено (см. _finishStep) — пишем
	-- следующий шаг. Иначе сохранение при выходе (CleanupPlayer)
	-- затирало бы продвижение и перезаход снова требовал бы экспедицию.
	data.TutorialStep = state.Phase == PHASE_DONE and state.Step + 1 or state.Step
end

return TutorialService
