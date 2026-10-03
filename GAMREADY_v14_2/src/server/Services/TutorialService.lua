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
local offerRemote
local confettiRemote
-- v20.150: аналитика обучения (OnboardingAnalyticsService) - всё в pcall
local function analytics(method, ...)
	local service = Services and Services.OnboardingAnalyticsService
	if service and service[method] then pcall(service[method], service, ...) end
end
local function confetti(player, size)
	if confettiRemote and player.Parent then confettiRemote:FireClient(player, size or "Small") end
end
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

-- v20.110: шаги ТЕКУЩЕЙ ветки - основное обучение или глава.
local function stepOf(state, index)
	local list = state and state.Steps or steps()
	return list[index]
end

local function chapterById(id)
	for _, chapter in Config.Tutorial.Chapters or {} do
		if chapter.Id == id then return chapter end
	end
	return nil
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

	-- v20.150: конфетти на экране (ScreenConfetti.client.lua): "Small" - шаг,
	-- "Big" - глава/обучение/подсказка с наградой
	confettiRemote = Instance.new("RemoteEvent")
	confettiRemote.Name = "ScreenConfetti"
	confettiRemote.Parent = ReplicatedStorage.Shared

	-- v20.140: предложение необязательной главы (плашка на 10 с)
	offerRemote = Instance.new("RemoteEvent")
	offerRemote.Name = "TutorialGuideOffer"
	offerRemote.Parent = ReplicatedStorage.Shared

	actionRemote = Instance.new("RemoteEvent")
	actionRemote.Name = "TutorialActionEvent"
	actionRemote.Parent = ReplicatedStorage.Shared
	actionRemote.OnServerEvent:Connect(function(player, action, value)
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
			self:_setHiddenUi(player, self:IsActive(player))
		elseif action == "UiHintSeen" and typeof(value) == "string" then
			-- v20.121: курсор-подсказка «куда нажать» показана ещё раз
			self:_uiHintSeen(player, value)
		elseif action == "AcceptGuide" and typeof(value) == "string" then
			-- v20.140: игрок нажал SHOW ME (плашка или журнал квестов)
			self:AcceptGuide(player, value)
		elseif action == "UiFlag" and typeof(value) == "string" then
			-- v20.110: клиентское событие (открыл квесты/компас) - только из списка
			if table.find(Config.Tutorial.ClientFlags or {}, value) then
				self:SetFlag(player, value, true)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		if self._broke then self._broke[player] = nil end
		if self._nextChapterAt then self._nextChapterAt[player] = nil end
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
			if tick % 2 == 0 then
				for _, player in Players:GetPlayers() do
					pcall(self._tickMicroHints, self, player)
					pcall(self._tickChapters, self, player)
				end
			end
			for player, state in states do
				-- v20.41: авто-листание реплик — на клиенте (TutorialUI), чтобы
				-- отсчёт начинался после катсцены, когда текст реально виден.
				-- v20.174: не успел за ChapterTaskSeconds - глава на паузу
				local stayStep = stepOf(state, state.Step)
				if player.Parent and state.Chapter and stayStep and stayStep.StayIf and not self:_check(player, stayStep.StayIf) then
					-- v20.175: условие шага пропало (не хватает денег на остров) - глава
					-- на паузу, вернётся, когда условие снова выполнится
					pcall(self._pauseChapter, self, player)
				elseif player.Parent and state.Phase == PHASE_TASK and state.TaskDeadline and os.clock() > state.TaskDeadline then
					pcall(self._pauseChapter, self, player)
				elseif player.Parent and state.Phase == PHASE_TASK then
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

-- v20.121: ПОВТОРНЫЕ ПОДСКАЗКИ КУРСОРОМ (Config.Tutorial.UiHints) - первые
-- Times раз курсор показывает, куда нажать, даже вне обучения. Счётчик в
-- профиле (data.UiHintCounts), клиенту - атрибутом UiHint_<Id>.
function TutorialService:_uiHintSeen(player, id)
	local spec
	for _, hint in Config.Tutorial.UiHints or {} do
		if hint.Id == id then spec = hint break end
	end
	if not spec then return end
	local data = Services.DataService:GetGeodeData(player)
	if not data then return end
	if type(data.UiHintCounts) ~= "table" then data.UiHintCounts = {} end
	local count = math.min((tonumber(data.UiHintCounts[id]) or 0) + 1, (spec.Times or 3) + 1)
	data.UiHintCounts[id] = count
	player:SetAttribute("UiHint_" .. id, count)
end

function TutorialService:SetupPlayer(player)
	task.delay(2, function() pcall(self._publishGuides, self, player) end) -- v20.140: раздел GUIDES в журнале
	local data = Services.DataService:GetGeodeData(player)
	if not data then return end
	for id, count in (type(data.UiHintCounts) == "table" and data.UiHintCounts) or {} do
		if typeof(id) == "string" then player:SetAttribute("UiHint_" .. id, tonumber(count) or 0) end
	end

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
	-- v20.108: шаги тележки (6-9) слились в один «SellOre» - переносим
	-- номер шага у тех, кто был посреди обучения.
	if Config.NoCarts and data.TutorialNoCartsLayout ~= true then
		data.TutorialNoCartsLayout = true
		local old = tonumber(data.TutorialStep) or 1
		if old >= 10 then
			data.TutorialStep = old - 3
		elseif old >= 6 then
			data.TutorialStep = 6
		end
	end
	local saved = math.clamp(tonumber(data.TutorialStep) or 1, 1, #steps() + 1)
	states[player] = {
		Step = saved,
		Phase = nil,
		LineIndex = 1,
		Counters = {},
		Flags = {},
		Revealed = {},
	}

	-- v20.40: размер рюкзака зависит от обучения (Config.Inventory.TutorialSlots).
	task.defer(function() if Services.InventoryService and player.Parent then pcall(Services.InventoryService.Sync, Services.InventoryService, player) end end)
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
	-- v20.110: главы (после основного обучения) не включают «режим новичка»
	local state = states[player]
	return state ~= nil and state.Chapter == nil
end

function TutorialService:GetChapter(player)
	local state = states[player]
	return state and state.Chapter or nil
end

function TutorialService:GetStepId(player)
	local state = states[player]
	local step = state and stepOf(state, state.Step)
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
	pcall(self._microEvent, self, player, key) -- v20.150: подсказки с наградой (сейф)
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
	if Config.Tutorial.ShowHints == false then return false end -- v20.93: подсказки выключены
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
	local step = stepOf(state, index)
	if not step then
		self:_complete(player)
		return
	end
	-- v20.110: действие при входе в шаг (например, руда в стоке у торговца)
	if step.OnEnter and self.OnEnter[step.OnEnter] then
		pcall(self.OnEnter[step.OnEnter], self, player, step)
	end
	if step.SkipUnless and not self:_check(player, step.SkipUnless) then
		self:_enterStep(player, index + 1, restoring)
		return
	end
	state.Step = index
	state.LineIndex = 1
	analytics("StepEntered", player, state.Chapter, index, step.Id, #(state.Steps or steps()), "Lines")

	-- СЧЁТЧИК ШАГА СТАРТУЕТ С НУЛЯ. Count копит прогресс всегда, в том
	-- числе на чужих шагах, — и без сброса продажа руды из рюкзака на
	-- втором шаге закрывала последний шаг «продай тележку» в ту же
	-- секунду, как игрок до него доходил. KeepEarlyProgress — для шагов,
	-- где забегать вперёд правильно (валуны, разбитые под вступительную
	-- реплику, засчитываются).
	-- v20.36: ResetCounters — обнулить чужие счётчики при входе в шаг
	-- (например, «подобрал руду» считаем только ПОСЛЕ экспедиции: всё,
	-- что игрок подберёт во время прощальной реплики, уже засчитается
	-- следующему шагу с KeepEarlyProgress).
	for _, key in step.ResetCounters or {} do
		state.Counters[key] = nil
	end
	-- v20.36: Highlight — какую карточку в окне улучшений подсветить
	-- крутящимися лучами ("Mine", "Cheapest"…); нет поля — подсветки нет.
	player:SetAttribute("TutorialHighlight", step.Highlight)
	player:SetAttribute("TutorialHighlightColor", step.HighlightColor)

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
		if data and state.Chapter then
			-- в главах - один раз на шаг главы
			data.TutorialGrants = type(data.TutorialGrants) == "table" and data.TutorialGrants or {}
			local key = state.Chapter .. ":" .. tostring(index)
			if not data.TutorialGrants[key] then
				data.TutorialGrants[key] = true
				Services.DataService:AddMoney(player, step.GrantMoney)
			end
		elseif data and data.TutorialRewardGiven ~= true then
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

	self:_armTimer(state, step)
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
	local step = stepOf(state, state.Step)
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
				self:_armTimer(state, step)
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
	elseif goal.Kind == "Near" then
		-- v20.110: дойти до цели (остров, НПС)
		local target = self:_resolveTarget(player, goal.Target or step.Target)
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local position = target and (target:IsA("BasePart") and target.Position or (target:IsA("Model") and target:GetPivot().Position))
		local near = hrp and position and (hrp.Position - position).Magnitude <= (goal.Radius or 20)
		return near and 1 or 0, 1
	elseif goal.Kind == "Check" then
		-- v20.110: проверка состояния игрока (см. TutorialService.Checks)
		local check = self.Checks[goal.Check]
		local ok, done = false, false
		if check then ok, done = pcall(check, self, player, goal.Arg) end
		return (ok and done) and 1 or 0, 1
	end
	return 0, 1
end

function TutorialService:_checkGoal(player)
	local state = states[player]
	if not state or state.Phase ~= PHASE_TASK then return end
	local step = stepOf(state, state.Step)
	if not step or not step.Goal then return end
	if step.Goal.Kind == "Ack" then return end -- закрывается только кнопкой
	local current, target = self:_goalProgress(player, step)
	-- v20.36: нечего грузить в тележку — шаг не должен стать тупиком.
	if current < target and step.CompleteWhenBagEmpty and Services.InventoryService then
		local ok, count = pcall(Services.InventoryService.CountItems, Services.InventoryService, player)
		if ok and tonumber(count) == 0 then current = target end
	end
	if current < target and step.CompleteWhenBagFull and Services.InventoryService then
		local ok, hasRoom = pcall(Services.InventoryService.HasAnyRoom, Services.InventoryService, player)
		if ok and hasRoom == false then current = target end
	end
	if current >= target then
		self:_finishStep(player)
	end
end

function TutorialService:_finishStep(player)
	local state = states[player]
	if not state then return end
	local step = stepOf(state, state.Step)
	if not step then return end

	state.TaskDeadline = nil -- v20.174: таймер шага снят
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	pcall(Sfx.play, "TutorialStepComplete", root)
	analytics("StepFinished", player)
	confetti(player, "Small")

	-- ПРОГРЕСС ФИКСИРУЕТСЯ В МОМЕНТ ВЫПОЛНЕНИЯ, а не после прощальной
	-- реплики. Счётчики в профиль не пишутся, поэтому раньше вылет на
	-- реплике "Для такой добычи нужна тележка" заставлял заново идти в
	-- экспедицию. Теперь перезаход сразу открывает следующий шаг.
	local data = Services.DataService:GetGeodeData(player)
	if data and state.Chapter then
		if not state.Transient then data.TutorialChapterActive = { Id = state.Chapter, Step = state.Step + 1 } end
	elseif data then
		data.TutorialStep = state.Step + 1
	end

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
	analytics("Skipped", player)
	if state.Chapter then
		self:_finishChapter(player, false)
		return
	end
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
	local state = states[player]
	if state and state.Chapter then
		self:_finishChapter(player, not state.Transient)
		return
	end
	self:_finish(player, true)
end

function TutorialService:_finish(player, rewarded)
	local state = states[player]
	if not state then return end
	states[player] = nil
	analytics("Completed", player, nil, #steps(), rewarded)
	if rewarded then confetti(player, "Big") end

	-- v20.40: размер рюкзака зависит от обучения (Config.Inventory.TutorialSlots).
	task.defer(function() if Services.InventoryService and player.Parent then pcall(Services.InventoryService.Sync, Services.InventoryService, player) end end)

	local data = Services.DataService:GetGeodeData(player)
	if data then
		data.TutorialVersion = Config.Tutorial.Version
		data.TutorialCompletedAt = os.time() -- см. QuestService:_scheduleTips
		data.TutorialStep = #steps()
	end
	player:SetAttribute("NeedsTutorial", false)
	player:SetAttribute("TutorialHighlight", nil) -- подсветка карточек только в обучении
	player:SetAttribute("TutorialHighlightColor", nil)
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
	-- v20.110: после основного обучения - пауза перед первой главой
	self._nextChapterAt = self._nextChapterAt or {}
	self._nextChapterAt[player] = os.clock() + (Config.Tutorial.ChapterGapSeconds or 6)
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
	elseif kind == "GroundOre" then
		-- v20.149: ближайшая СВОЯ выпавшая из шахты руда; нет - шахтёр
		local folder = workspace:FindFirstChild("MineGroundOre")
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local best, bestDistance = nil, math.huge
		if folder and root then
			for _, ore in folder:GetChildren() do
				if ore:GetAttribute("GroundOreOwner") == player.UserId then
					local ok, pivot = pcall(function() return ore:GetPivot() end)
					if ok then
						local distance = (pivot.Position - root.Position).Magnitude
						if distance < bestDistance then best, bestDistance = ore, distance end
					end
				end
			end
		end
		return best or (content and content:FindFirstChild("MinerNPC", true)) or nil
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
	elseif kind == "RebirthNPC" and Services.RebirthService and Services.RebirthService.GetNpc then
		local ok, npc = pcall(Services.RebirthService.GetNpc, Services.RebirthService, player)
		if ok and npc then return npc end
		return content and content:FindFirstChild("RebirthNPC", true) or nil
	elseif kind:sub(1, 6) == "Decor:" then
		-- v20.174: поставленный на базу предмет (банка, сундук) по Item
		local item = kind:sub(7)
		local data = Services.DataService:GetGeodeData(player)
		local folder = content and content:FindFirstChild("BaseDecor")
		for _, record in (data and data.PlacedDecor) or {} do
			if type(record) == "table" and record.Item == item and folder then
				for _, model in folder:GetChildren() do
					if model:GetAttribute("BaseDecorUid") == record.Uid then return model end
				end
			end
		end
		return nil
	elseif kind:sub(1, 6) == "World:" then
		-- v20.110: общие объекты мира (торговец, хранитель островов) - по имени
		self._worldCache = self._worldCache or {}
		local name = kind:sub(7)
		local cached = self._worldCache[name]
		if cached and cached.Parent then return cached end
		cached = workspace:FindFirstChild(name, true)
		if cached and cached:IsA("Folder") then cached = cached:FindFirstChildWhichIsA("Model") or cached:FindFirstChildWhichIsA("BasePart") end
		self._worldCache[name] = cached
		return cached
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
	local step = stepOf(state, state.Step)
	if not step then return end
	analytics("PhaseChanged", player, state.Phase)

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
		StepCount = #(state.Steps or steps()),
		Chapter = state.Chapter,
		UiTargets = step.UiTargets, -- v20.110: кнопки для затемнения/указателя
		Id = step.Id,
		Speaker = Config.Tutorial.SpeakerName,
		Portrait = Config.Tutorial.PortraitImageId,
		Text = text,
		TextArgs = step.TextArgs, -- v20.174: параметры {name}/{cost} реплики
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
		SkipText = state.Chapter and "SKIP" or nil,
		-- v20.174: полоска времени под плашкой задания главы
		TimeLeft = state.TaskDeadline and math.max(0, state.TaskDeadline - os.clock()) or nil,
		TimeTotal = state.TaskDeadline and (Config.Tutorial.ChapterTaskSeconds or 120) or nil,
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
	local stepIndex = state.Phase == PHASE_DONE and state.Step + 1 or state.Step
	if state.Transient then return end
	if state.Chapter then
		data.TutorialChapterActive = { Id = state.Chapter, Step = stepIndex }
	else
		data.TutorialStep = stepIndex
	end
end

--------------------------------------------------------------------------------
-- v20.110: ГЛАВЫ ОБУЧЕНИЯ (Config.Tutorial.Chapters). После основного
-- обучения каждая механика объясняется в момент, когда она становится
-- доступна: тот же диалог, затемнение и указатель. Глава висит целью,
-- пока игрок её не выполнит (или не нажмёт SKIP). Пройденные главы -
-- data.TutorialChapters, недоигранная - data.TutorialChapterActive.
--------------------------------------------------------------------------------
local BigNum = require(ReplicatedStorage.Shared.BigNum)

local function moneyAtLeast(player, amount)
	local ok, money = pcall(Services.DataService.GetMoney, Services.DataService, player)
	return ok and money ~= nil and not BigNum.lt(money, tonumber(amount) or 0)
end

TutorialService.Checks = {
	-- v20.118: кирка в руках (первый шаг обучения - взять её из хотбара)
	PickaxeEquipped = function(_, player)
		local character = player.Character
		if not character then return false end
		for _, child in character:GetChildren() do
			if child:IsA("Tool") and (child.Name == "Pickaxe" or child.Name:match("^Pickaxe")) then return true end
		end
		return false
	end,
	IslandOwned = function(_, player, id)
		return Services.IslandService ~= nil and Services.IslandService:Owns(player, id)
	end,
	CanAffordIsland = function(_, player, id)
		local def = Config.Islands and Config.Islands.Definitions[id]
		return def ~= nil and moneyAtLeast(player, def.Cost or 0)
	end,
	MoneyAtLeast = function(_, player, amount)
		return moneyAtLeast(player, amount)
	end,
	OreUnlockedAny = function(_, player)
		local data = Services.DataService:GetGeodeData(player)
		return data ~= nil and type(data.UnlockedOres) == "table" and next(data.UnlockedOres) ~= nil
	end,
	OreBoxOwned = function(_, player)
		local data = Services.DataService:GetGeodeData(player)
		for key, count in (data and data.Gear) or {} do
			if typeof(key) == "string" and key:match("^OreBox_") and (tonumber(count) or 0) > 0 then return true end
		end
		return data ~= nil and type(data.UnlockedOres) == "table" and next(data.UnlockedOres) ~= nil
	end,
	CanAffordOre = function(_, player)
		-- самая дешёвая покупная руда
		return moneyAtLeast(player, Config.OreShop and Config.OreShop.PriceBase or 250)
	end,
	HasGeode = function(_, player)
		local data = Services.DataService:GetGeodeData(player)
		for _, count in (data and data.Geodes) or {} do
			if (tonumber(count) or 0) > 0 then return true end
		end
		return false
	end,
	HasCrystal = function(_, player)
		local data = Services.DataService:GetGeodeData(player)
		return data ~= nil and type(data.GeodeCollection) == "table" and next(data.GeodeCollection) ~= nil
	end,
	-- v20.121: проверки для глав «новая механика»
	CarryingCrystal = function(_, player)
		local carrying = player:GetAttribute("CarryingCrystal")
		return typeof(carrying) == "string" and carrying ~= ""
	end,
	NotCarryingCrystal = function(_, player)
		local carrying = player:GetAttribute("CarryingCrystal")
		return not (typeof(carrying) == "string" and carrying ~= "")
	end,
	HasTotemItem = function(_, player)
		local data = Services.DataService:GetGeodeData(player)
		for key, count in (data and data.Gear) or {} do
			if typeof(key) == "string" and key:match("^Totem_") and (tonumber(count) or 0) > 0 then return true end
		end
		return false
	end,
	TotemPlacedAny = function(_, player)
		local data = Services.DataService:GetGeodeData(player)
		for _, record in (data and data.PlacedDecor) or {} do
			if type(record) == "table" and typeof(record.Item) == "string" and record.Item:match("^Totem_") then return true end
		end
		return false
	end,
	HasDynamite = function(_, player)
		local data = Services.DataService:GetGeodeData(player)
		for key, count in (data and data.Gear) or {} do
			if typeof(key) == "string" and key:match("^Dynamite") and (tonumber(count) or 0) > 0 then return true end
		end
		return false
	end,
	SafeHasMoney = function(_, player)
		local data = Services.DataService:GetGeodeData(player)
		return data ~= nil and (tonumber(data.GeodeSafeBalance) or 0) >= 1
	end,
	CrystalOnPodium = function(_, player)
		local data = Services.DataService:GetGeodeData(player)
		return data ~= nil and typeof(data.InstalledGeodeOre) == "string" and data.InstalledGeodeOre ~= ""
	end,
	-- v20.174: предмет есть в снаряжении ИЛИ уже стоит на базе (Arg - Id или префикс)
	GearOrPlaced = function(_, player, item)
		local data = Services.DataService:GetGeodeData(player)
		if not (data and typeof(item) == "string") then return false end
		for key, count in data.Gear or {} do
			if typeof(key) == "string" and key:sub(1, #item) == item and (tonumber(count) or 0) > 0 then return true end
		end
		for _, record in data.PlacedDecor or {} do
			if type(record) == "table" and typeof(record.Item) == "string" and record.Item:sub(1, #item) == item then return true end
		end
		return false
	end,
	Placed = function(_, player, item)
		local data = Services.DataService:GetGeodeData(player)
		for _, record in (data and data.PlacedDecor) or {} do
			if type(record) == "table" and typeof(record.Item) == "string" and record.Item:sub(1, #item) == item then return true end
		end
		return false
	end,
	MineLevelAtLeast = function(_, player, level)
		return (Services.DataService:GetTiers(player).Mine or 1) >= (tonumber(level) or 1)
	end,
	CanPrestige = function(_, player)
		local rebirth = Services.RebirthService
		if not (rebirth and rebirth._buildStatus) then return false end
		local ok, status = pcall(rebirth._buildStatus, rebirth, player)
		return ok and type(status) == "table" and status.AllMet == true
	end,
	HasPrestiged = function(_, player)
		local ok, count = pcall(Services.DataService.GetRebirths, Services.DataService, player)
		return ok and (tonumber(count) or 0) > 0
	end,
	PerkBoughtAny = function(_, player)
		local data = Services.DataService:GetGeodeData(player)
		for _, level in (data and data.Perks) or {} do
			if (tonumber(level) or 0) > 0 then return true end
		end
		return false
	end,
	-- v20.132: куплен конкретный перк (Arg - Id)
	PerkOwned = function(_, player, perkId)
		local data = Services.DataService:GetGeodeData(player)
		return data ~= nil and type(data.Perks) == "table" and (tonumber(data.Perks[perkId]) or 0) > 0
	end,
	-- v20.132: куплен перк из веток (не центральный Starter Miner)
	PerkBoughtBranch = function(_, player)
		local data = Services.DataService:GetGeodeData(player)
		local root = Config.Prestige and Config.Prestige.RootPerk
		for id, level in (data and data.Perks) or {} do
			if id ~= root and (tonumber(level) or 0) > 0 then return true end
		end
		return false
	end,
}

TutorialService.OnEnter = {
	-- v20.132: глава PrestigeIntro - одно очко престижа в подарок (один раз)
	GrantPrestigePoint = function(_, player)
		local data = Services.DataService:GetGeodeData(player)
		if not data or data.PrestigeIntroPoint == true then return end
		data.PrestigeIntroPoint = true
		if Services.PrestigeService then
			Services.PrestigeService:AddPoints(player, (Config.Tutorial and Config.Tutorial.PrestigeGiftPoints) or 1)
		end
		-- v20.135: тост не нужен - очко само вылетает и падает в счётчик HUD (HudCurrencyFx)
	end,
	-- v20.174: деньги на покупку предмета шага (step.GrantItem) - один раз на
	-- профиль, чтобы этапа тотемов/декора хватило целиком
	GrantItemPrice = function(_, player, step)
		local state = states[player]
		local data = Services.DataService:GetGeodeData(player)
		if not (data and state and step and step.GrantItem) then return end
		data.TutorialGrants = type(data.TutorialGrants) == "table" and data.TutorialGrants or {}
		local key = "Item:" .. step.GrantItem
		if data.TutorialGrants[key] then return end
		local ok, info = pcall(function() return require(ReplicatedStorage.Shared.PlaceableCatalog).Info(step.GrantItem) end)
		local price = ok and info and tonumber(info.Price) or 0
		if price <= 0 then return end
		data.TutorialGrants[key] = true
		Services.DataService:AddMoney(player, price)
		if Services.NotifyService then
			Services.NotifyService:Show(player, ("+$%s for %s"):format(tostring(price), info.DisplayName or step.GrantItem), { Icon = "Money", Duration = 3 })
		end
	end,
	-- v20.174: купленный ящик руды - строго в 1-й слот хотбара (курсор тапает в него)
	OreBoxToSlot1 = function(_, player)
		local data = Services.DataService:GetGeodeData(player)
		if not (data and Services.InventoryService and Services.InventoryService.PutGearInSlot) then return end
		for key, count in data.Gear or {} do
			if typeof(key) == "string" and key:match("^OreBox_") and (tonumber(count) or 0) > 0 then
				Services.InventoryService:PutGearInSlot(player, key, 1)
				return
			end
		end
	end,
	-- в стоке у торговца гарантированно есть хотя бы одна недорогая руда
	EnsureOreStock = function(_, player)
		if Services.MerchantService and Services.MerchantService.EnsureTutorialOre then
			Services.MerchantService:EnsureTutorialOre(player)
		end
	end,
}

function TutorialService:_check(player, spec)
	if spec == nil then return true end
	if type(spec) == "string" then spec = { Check = spec } end
	local check = self.Checks[spec.Check]
	if not check then return false end
	local ok, result = pcall(check, self, player, spec.Arg)
	return ok and result == true
end

function TutorialService:_chaptersDone(player)
	local data = Services.DataService:GetGeodeData(player)
	if not data then return nil end
	if type(data.TutorialChapters) ~= "table" then data.TutorialChapters = {} end
	return data.TutorialChapters
end

function TutorialService:_startChapter(player, chapter, stepIndex)
	if not chapter.Transient then
		local paused = self:_paused(player)
		if paused then paused[chapter.Id] = nil end
	end
	states[player] = {
		Transient = chapter.Transient == true,
		Step = stepIndex or 1,
		Phase = nil,
		LineIndex = 1,
		Counters = {},
		Flags = {},
		Revealed = {},
		Chapter = chapter.Id,
		Steps = chapter.Steps,
	}
	local data = Services.DataService:GetGeodeData(player)
	if data and not chapter.Transient then data.TutorialChapterActive = { Id = chapter.Id, Step = stepIndex or 1 } end
	player:SetAttribute("TutorialChapter", chapter.Id)
	self:_enterStep(player, stepIndex or 1, (stepIndex or 1) > 1)
end

function TutorialService:_finishChapter(player, rewarded)
	local state = states[player]
	if not (state and state.Chapter) then return end
	local chapter = chapterById(state.Chapter)
	states[player] = nil
	analytics("Completed", player, state.Chapter, chapter and #chapter.Steps or 0, rewarded)
	if rewarded then confetti(player, "Big") end
	local done = self:_chaptersDone(player)
	if done and not state.Transient then done[state.Chapter] = true end
	local data = Services.DataService:GetGeodeData(player)
	if data then data.TutorialChapterActive = nil end
	self:_publishGuides(player)
	player:SetAttribute("TutorialChapter", nil)
	player:SetAttribute("TutorialHighlight", nil)
	player:SetAttribute("TutorialHighlightColor", nil)
	if rewarded and chapter and (chapter.RewardMoney or 0) > 0 then
		Services.DataService:AddMoney(player, chapter.RewardMoney)
		if Services.NotifyService then
			Services.NotifyService:Show(player, ("📘 %s - +$%d"):format(chapter.Title or chapter.Id, chapter.RewardMoney), { Icon = "Reward", Duration = 3 })
		end
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if rewarded then pcall(Sfx.play, "TutorialComplete", root) end
	pcall(function() Services.DataService:SaveProfile(player) end)
	stateRemote:FireClient(player, { Phase = "Finished" })
	self._nextChapterAt = self._nextChapterAt or {}
	self._nextChapterAt[player] = os.clock() + (Config.Tutorial.ChapterGapSeconds or 6)
end

--------------------------------------------------------------------------------
-- v20.174: ТАЙМЕР ЗАДАНИЯ ГЛАВЫ. На задание главы - ChapterTaskSeconds
-- (2 мин, полоска под плашкой). Не успел - подсказка пропадает (глава на
-- паузе, data.TutorialPaused) и возвращается с того же шага, когда игрок
-- снова подходит к месту этой механики (цель шага или Near главы). Шаги без
-- места в мире (кнопки интерфейса) возвращаются через PausedRetrySeconds.
--------------------------------------------------------------------------------
function TutorialService:_armTimer(state, step)
	state.TaskDeadline = nil
	if not (state and state.Chapter and not state.Transient and state.Phase == PHASE_TASK) then return end
	if not step or (step.Goal and step.Goal.Kind == "Ack") then return end
	local seconds = tonumber(Config.Tutorial.ChapterTaskSeconds) or 120
	if seconds > 0 then state.TaskDeadline = os.clock() + seconds end
end

function TutorialService:_paused(player)
	local data = Services.DataService:GetGeodeData(player)
	if not data then return nil end
	if type(data.TutorialPaused) ~= "table" then data.TutorialPaused = {} end
	return data.TutorialPaused
end

function TutorialService:_pauseChapter(player)
	local state = states[player]
	if not (state and state.Chapter) then return end
	local step = stepOf(state, state.Step)
	local chapter = chapterById(state.Chapter)
	local paused = self:_paused(player)
	if paused and not state.Transient then
		paused[state.Chapter] = {
			Step = state.Step,
			Target = (step and step.Target) or (chapter and chapter.Near and chapter.Near.Target) or nil,
			At = os.time(),
			Left = false,
		}
	end
	analytics("Quit", player, "Timeout")
	states[player] = nil
	local data = Services.DataService:GetGeodeData(player)
	if data then data.TutorialChapterActive = nil end
	player:SetAttribute("TutorialChapter", nil)
	player:SetAttribute("TutorialHighlight", nil)
	player:SetAttribute("TutorialHighlightColor", nil)
	stateRemote:FireClient(player, { Phase = "Finished" })
	self._nextChapterAt = self._nextChapterAt or {}
	self._nextChapterAt[player] = os.clock() + (Config.Tutorial.ChapterGapSeconds or 6)
end

-- главы на паузе: вернуть, когда игрок снова у механики
function TutorialService:_tickPaused(player, done)
	local paused = self:_paused(player)
	if not paused then return false end
	local radius = Config.Tutorial.ResumeRadius or 30
	for id, info in paused do
		local chapter = chapterById(id)
		local step = chapter and type(info) == "table" and chapter.Steps[math.clamp(tonumber(info.Step) or 1, 1, #chapter.Steps)]
		if not chapter or done[id] or type(info) ~= "table" then
			paused[id] = nil
		elseif chapter.SkipIf and self:_check(player, chapter.SkipIf) then
			paused[id] = nil
			done[id] = true
			self:_publishGuides(player)
		elseif step and step.StayIf and not self:_check(player, step.StayIf) then
			-- v20.175: шаг пока невыполним (денег мало) - у механики только «бро, иди подзаработай»
			if info.Target and self:_resolveTarget(player, info.Target) then
				local near = self:_isNear(player, { Target = info.Target, Radius = radius })
				if self:_brokeHint(player, chapter, near) then return true end
			end
		elseif info.Target and self:_resolveTarget(player, info.Target) then
			local near = self:_isNear(player, { Target = info.Target, Radius = radius })
			if not near then
				info.Left = true
			elseif info.Left then
				self:_startChapter(player, chapter, math.clamp(tonumber(info.Step) or 1, 1, #chapter.Steps))
				return true
			end
		elseif os.time() - (tonumber(info.At) or 0) >= (Config.Tutorial.PausedRetrySeconds or 180) then
			self:_startChapter(player, chapter, math.clamp(tonumber(info.Step) or 1, 1, #chapter.Steps))
			return true
		end
	end
	return false
end

-- v20.174: подошёл к механике, а денег не хватает - короткий диалог
-- «бро, иди подзаработай» (один раз на подход, глава не засчитывается)
function TutorialService:_brokeHint(player, chapter, near)
	self._broke = self._broke or {}
	local shown = self._broke[player] or {}
	self._broke[player] = shown
	if not near then
		shown[chapter.Id] = nil
		return false
	end
	if shown[chapter.Id] or not chapter.BrokeHint then return false end
	shown[chapter.Id] = true
	-- шаблон {name}/{cost} подставляет клиент - тогда реплика переводится
	local args = { name = chapter.Title or "", cost = "" }
	local when = chapter.When
	if when and when.Check == "CanAffordIsland" then
		local def = Config.Islands and Config.Islands.Definitions[when.Arg]
		local okFmt, NumberFormat = pcall(require, ReplicatedStorage.Shared.NumberFormat)
		local cost = def and def.Cost or 0
		args.cost = "$" .. ((okFmt and NumberFormat.abbreviate) and NumberFormat.abbreviate(cost) or tostring(cost))
		args.name = def and def.DisplayName or args.name
	end
	self:_startChapter(player, {
		Id = "Broke_" .. chapter.Id,
		Title = chapter.Title,
		Transient = true,
		Steps = { { Id = "Broke", Lines = chapter.BrokeHint, TextArgs = args, Goal = { Kind = "Ack" } } },
	}, 1)
	return true
end

-- Есть ли глава, которую пора начать.
function TutorialService:_tickChapters(player)
	if states[player] or not player.Parent then return end
	if self:IsRequired(player) then return end
	if player:GetAttribute("MineExpeditionActive") == true then return end
	self._nextChapterAt = self._nextChapterAt or {}
	if (self._nextChapterAt[player] or 0) > os.clock() then return end
	local done = self:_chaptersDone(player)
	if not done then return end
	local data = Services.DataService:GetGeodeData(player)
	local active = data and data.TutorialChapterActive
	if type(active) == "table" and active.Id and not done[active.Id] then
		local chapter = chapterById(active.Id)
		local resumeStep = chapter and chapter.Steps[math.clamp(tonumber(active.Step) or 1, 1, #chapter.Steps)]
		if resumeStep and resumeStep.StayIf and not self:_check(player, resumeStep.StayIf) then
			-- v20.175: шаг сейчас невыполним (денег не хватает) - не восстанавливаем
			local paused = self:_paused(player)
			if paused then
				paused[active.Id] = { Step = tonumber(active.Step) or 1, Target = resumeStep.Target, At = os.time(), Left = false }
			end
			if data then data.TutorialChapterActive = nil end
			chapter = nil
		end
		if chapter then
			self:_startChapter(player, chapter, math.clamp(tonumber(active.Step) or 1, 1, #chapter.Steps))
			return
		end
	end
	-- v20.140: НЕОБЯЗАТЕЛЬНЫЕ главы (всё, кроме Required) сами не стартуют:
	-- игрок получает плашку «NEW: ... SHOW ME» на 10 с, а глава ложится в
	-- журнал квестов (раздел GUIDES) - запускается кнопкой, когда захочет.
	-- v20.174: главы на паузе (не успел за 2 мин) - вернуть у механики
	if self:_tickPaused(player, done) then return end
	local paused = self:_paused(player) or {}
	local offered = self:_guidesOffered(player)
	-- v20.149: главы с Near стартуют сами, когда игрок подошёл (или прошёл
	-- рядом) к нужному месту - магазину, НПС, постройке. Их не надо искать в
	-- журнале: подошёл к Island Keeper - началось обучение островам.
	for _, chapter in Config.Tutorial.Chapters or {} do
		if not chapter.Required and chapter.Near and not done[chapter.Id] and not paused[chapter.Id] then
			local after = true
			for _, id in chapter.After or {} do
				if not done[id] then after = false break end
			end
			local near = after and self:_isNear(player, chapter.Near)
			if near then
				if chapter.SkipIf and self:_check(player, chapter.SkipIf) then
					done[chapter.Id] = true
					self:_publishGuides(player)
				elseif self:_check(player, chapter.When) then
					if offered then offered[chapter.Id] = true end
					self:_publishGuides(player)
					self:_startChapter(player, chapter, 1)
					return
				elseif self:_brokeHint(player, chapter, true) then
					return
				end
			elseif after then
				self:_brokeHint(player, chapter, false)
			end
		end
	end
	for _, chapter in Config.Tutorial.Chapters or {} do
		-- главы с Near ждут, пока игрок подойдёт (выше), плашкой не предлагаются
		if not done[chapter.Id] and not paused[chapter.Id] and not (offered and offered[chapter.Id]) and not (chapter.Near and not chapter.Required) then
			local after = true
			for _, id in chapter.After or {} do
				if not done[id] and not (offered and offered[id]) then after = false break end
			end
			if after then
				if chapter.SkipIf and self:_check(player, chapter.SkipIf) then
					done[chapter.Id] = true -- уже умеет (старый игрок)
					self:_publishGuides(player)
				elseif self:_check(player, chapter.When) then
					if chapter.Required or not offered then
						self:_startChapter(player, chapter, 1)
					else
						offered[chapter.Id] = true
						self:_publishGuides(player)
						if offerRemote then
							local first = chapter.Steps and chapter.Steps[1]
							offerRemote:FireClient(player, {
								Id = chapter.Id,
								Title = chapter.Title or chapter.Id,
								Text = first and (first.Task or first.Short) or "",
								Reward = chapter.RewardMoney or 0,
								Seconds = Config.Tutorial.GuideBannerSeconds or 10,
							})
						end
						self._nextChapterAt[player] = os.clock() + (Config.Tutorial.ChapterGapSeconds or 6)
					end
					return
				end
			end
		end
	end
end


--------------------------------------------------------------------------------
-- v20.150: КОРОТКИЕ ПОДСКАЗКИ МЕХАНИК (Config.Tutorial.MicroHints, вариант C).
-- Не главы: одна строка на плашке «NEW» (TutorialGuideBanner) на 6 с, курсор
-- на кнопке (Config.Tutorial.UiHints), один раз на профиль. data.MicroHints
-- = { [Id] = "Shown" | "Done" }. Подсказка с DoneEvent (событие Count, напр.
-- SafeCollected) после него выдаёт Reward и конфетти.
--------------------------------------------------------------------------------
local function microHints(player)
	local data = Services.DataService:GetGeodeData(player)
	if not data then return nil end
	if type(data.MicroHints) ~= "table" then data.MicroHints = {} end
	return data.MicroHints
end

function TutorialService:_tickMicroHints(player)
	if states[player] or not player.Parent or self:IsRequired(player) then return end
	if player:GetAttribute("MineExpeditionActive") == true then return end
	self._nextMicroAt = self._nextMicroAt or {}
	if (self._nextMicroAt[player] or 0) > os.clock() then return end
	local seen = microHints(player)
	if not seen then return end
	for _, hint in Config.Tutorial.MicroHints or {} do
		if seen[hint.Id] == nil then
			if hint.SkipIf and self:_check(player, hint.SkipIf) then
				seen[hint.Id] = "Done" -- уже умеет
			elseif self:_check(player, hint.When) and (not hint.Near or self:_isNear(player, hint.Near)) then
				seen[hint.Id] = hint.DoneEvent and "Shown" or "Done"
				if offerRemote then
					offerRemote:FireClient(player, {
						Id = hint.Id, Hint = true, Icon = hint.Icon, Title = hint.Title or hint.Id, Text = hint.Text or "",
						Seconds = Config.Tutorial.MicroHintSeconds or 6,
						Reward = 0,
					})
				end
				analytics("Hint", player, "HintShown", hint.Id)
				self._nextMicroAt[player] = os.clock() + (Config.Tutorial.MicroHintGapSeconds or 8)
				return
			end
		end
	end
end

function TutorialService:_microEvent(player, key)
	local seen = microHints(player)
	if not seen then return end
	for _, hint in Config.Tutorial.MicroHints or {} do
		if hint.DoneEvent == key and seen[hint.Id] ~= "Done" then
			seen[hint.Id] = "Done"
			analytics("Hint", player, "HintDone", hint.Id)
			local reward = hint.Reward
			if reward and reward.Geode and Services.GeodeService then
				for _ = 1, math.max(1, tonumber(reward.Count) or 1) do
					pcall(Services.GeodeService.AddGeodeDirectly, Services.GeodeService, player, reward.Geode)
				end
				if Services.NotifyService then
					local geode = Config.Geodes.Types[reward.Geode]
					Services.NotifyService:Show(player, ("%s %s - +%d %s"):format(hint.Icon or "✅", hint.Title or hint.Id,
						math.max(1, tonumber(reward.Count) or 1), geode and geode.DisplayName or (reward.Geode .. " Geode")), { Icon = "Reward", Duration = 4 })
				end
			end
			if reward and (reward.Money or 0) > 0 then Services.DataService:AddMoney(player, reward.Money) end
			confetti(player, "Big")
		end
	end
end

-- v20.149: игрок рядом с местом главы? near = { Target = "...", Radius = N }
function TutorialService:_isNear(player, near)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	local targets = type(near.Targets) == "table" and near.Targets or { near.Target }
	for _, kind in targets do
		local target = self:_resolveTarget(player, kind)
		local position
		if target and target:IsA("BasePart") then
			position = target.Position
		elseif target and (target:IsA("Model") or target:IsA("Folder")) then
			local ok, pivot = pcall(function() return target:GetPivot() end)
			if ok then position = pivot.Position end
		end
		if position then
			local flat = Vector3.new(position.X - root.Position.X, 0, position.Z - root.Position.Z)
			if flat.Magnitude <= (near.Radius or 25) then return true end
		end
	end
	return false
end

-- v20.140: предложенные, но ещё не пройденные главы
function TutorialService:_guidesOffered(player)
	local data = Services.DataService:GetGeodeData(player)
	if not data then return nil end
	if type(data.TutorialOffered) ~= "table" then data.TutorialOffered = {} end
	return data.TutorialOffered
end

function TutorialService:_publishGuides(player)
	if not player.Parent then return end
	local offered = self:_guidesOffered(player) or {}
	local done = self:_chaptersDone(player) or {}
	local list = {}
	for _, chapter in Config.Tutorial.Chapters or {} do
		if offered[chapter.Id] and not done[chapter.Id] then table.insert(list, chapter.Id) end
	end
	player:SetAttribute("TutorialGuides", table.concat(list, ","))
end

function TutorialService:AcceptGuide(player, chapterId)
	if states[player] or self:IsRequired(player) then return end
	local chapter = chapterById(chapterId)
	local done = self:_chaptersDone(player)
	if not (chapter and done) or done[chapterId] then return end
	if player:GetAttribute("MineExpeditionActive") == true then return end
	self:_startChapter(player, chapter, 1)
end

return TutorialService
