--------------------------------------------------------------------------------
-- UiMotion
-- Единая анимация появления/скрытия модальных панелей ("дроп тележки"):
-- панель падает сверху с небольшим наклоном (как будто тележку тряхнуло и
-- вывалило груз), на приземлении — короткий приплюснутый импакт и отскок
-- на место. Никакого fade — только позиция/поворот/размер, поэтому в
-- отличие от типового "scale+fade spring" это читается как физический
-- удар, а не мягкое появление. Быстро и резко, но заметно (~0.22 сек).
--
-- Работает с ЛЮБЫМ GuiObject, у которого AnchorPoint = (0.5, 0.5) и
-- Position = UDim2.fromScale(0.5, 0.5) (все модальные панели проекта уже
-- построены именно так — ShopUi/SettingsUi/SkinUi/DailyRewardUi/GeodeUi).
-- Ничего в самой панели менять не нужно — модуль сам читает текущие
-- Position/Size один раз при первом вызове и использует их как "штатное"
-- состояние, к которому анимация возвращается.
--------------------------------------------------------------------------------

local TweenService = game:GetService("TweenService")

local UiMotion = {}

-- [panel] = { RestPosition = UDim2, RestSize = UDim2 } — запоминаем штатное
-- состояние один раз, чтобы повторные Open/Close не накапливали дрейф.
local rest = {}
local activeMotions = {}

--------------------------------------------------------------------------------
-- ИСПРАВЛЕНИЕ «РАБОТАЕТ, НО КРИВО — НАДО МНОГО РАЗ НАЖИМАТЬ, ЧТОБЫ ЗАКРЫЛОСЬ»
--
-- ПРИЧИНА. Close прячет панель (Visible = false) не сразу, а в САМОМ КОНЦЕ
-- цепочки твинов длиной ~0.17 с, и только если поколение анимации не
-- сменилось. А beginMotion в начале каждого Close увеличивает поколение и
-- ОТМЕНЯЕТ все идущие твины.
--
-- Отсюда порочный круг: игрок жмёт «закрыть», панель начинает улетать, но
-- ещё видима и Visible всё ещё true. Игрок, не увидев мгновенного отклика,
-- жмёт второй раз — Close вызывается снова, отменяет уже почти доигравший
-- твин, и обработчик завершения выходит по проверке PlaybackState.Cancelled,
-- ТАК И НЕ ВЫСТАВИВ Visible = false. Анимация начинается заново. Чем чаще
-- игрок жмёт (а он жмёт чаще именно потому, что «не сработало»), тем
-- надёжнее панель НЕ закрывается никогда.
--
-- На мышке это почти незаметно: один клик, 0.17 с, панель ушла. На телефоне
-- палец легко даёт два-три касания подряд, и панель залипает намертво.
--
-- РЕШЕНИЕ. Повторный Close по УЖЕ закрывающейся панели больше не
-- перезапускает анимацию — он просто добавляет свой onHidden в очередь и
-- выходит. Плюс сторожевой таймер: если анимацию всё-таки кто-то оборвал
-- (например, панель уничтожили или вызвали Open посреди закрытия), панель
-- принудительно прячется, а не остаётся висеть на экране.
--------------------------------------------------------------------------------
local closing = {}        -- [panel] = true, пока играет анимация закрытия
local pendingHidden = {}  -- [panel] = { onHidden, ... } — накопленные колбэки

local function finishClose(panel, state)
	closing[panel] = nil
	if panel.Parent then
		panel.Visible = false
		panel.Position = state.RestPosition
		panel.Rotation = 0
		panel.Size = state.RestSize
	end
	local callbacks = pendingHidden[panel]
	pendingHidden[panel] = nil
	for _, callback in callbacks or {} do
		-- pcall: сбойный колбэк одной панели не должен мешать остальным
		-- и, главное, не должен оставить closing[panel] взведённым.
		pcall(callback)
	end
end

local DROP_OFFSET = 46        -- на сколько студ-пикселей выше стартует падение
local TILT_DEGREES = 5        -- наклон "как будто тележку тряхнуло"
local SQUASH_PAD = 10         -- на сколько пикселей панель приплюснивается при ударе (ширина/высота)

local FALL_TIME = 0.11
local IMPACT_TIME = 0.05
local SETTLE_TIME = 0.07
local CLOSE_TIME = 0.13

local function beginMotion(panel)
	local motion = activeMotions[panel]
	if not motion then
		motion = { Generation = 0, Tweens = {} }
		activeMotions[panel] = motion
	end
	motion.Generation += 1
	local generation = motion.Generation
	for tween in motion.Tweens do
		tween:Cancel()
	end
	table.clear(motion.Tweens)
	return motion, generation
end

local function playTracked(motion, tween)
	motion.Tweens[tween] = true
	tween.Completed:Connect(function()
		motion.Tweens[tween] = nil
	end)
	tween:Play()
end

local function captureRest(panel)
	local state = rest[panel]
	if not state then
		state = { RestPosition = panel.Position, RestSize = panel.Size }
		rest[panel] = state
	end
	return state
end

-- Пока панель играет анимацию закрытия (сквош + улёт + поворот), любые
-- ScrollingFrame внутри неё физически прячутся (Visible = false), а не
-- просто клипаются — раньше пробовали одного ClipsDescendants=true на
-- панели, но при повороте (Rotation ~= 0 во время улёта) клиппинг у
-- Roblox иногда считает по НЕ повёрнутому прямоугольнику, и прокрученные
-- за край карточки на миг всё равно вылезали. Так — гарантированно: если
-- контент не рендерится вообще, ему неоткуда вылезти.
local function setScrollingContentVisible(panel, visible)
	for _, descendant in panel:GetDescendants() do
		if descendant:IsA("ScrollingFrame") then
			descendant.Visible = visible
		end
	end
end

local function squashedSize(size)
	-- Шире и ниже на SQUASH_PAD пикселей — читается как приплюснутый удар
	-- об пол, без обращения к неоднородному Scale (которого у UDim2 нет).
	return UDim2.new(
		size.X.Scale, size.X.Offset + SQUASH_PAD,
		size.Y.Scale, size.Y.Offset - SQUASH_PAD
	)
end

-- Проигрывает вход панели. Вызывай ПОСЛЕ panel.Visible = true (или сам
-- модуль выставит Visible, если передать panel как есть — оба варианта ок).
function UiMotion.Open(panel)
	local state = captureRest(panel)
	-- Открытие отменяет закрытие: панель снова на экране, значит ни
	-- сторожу, ни очереди колбэков «панель спрятана» тут больше делать
	-- нечего.
	closing[panel] = nil
	pendingHidden[panel] = nil
	local motion, generation = beginMotion(panel)
	setScrollingContentVisible(panel, true)
	panel.Visible = true
	panel.Rotation = -TILT_DEGREES
	panel.Position = state.RestPosition - UDim2.fromOffset(0, DROP_OFFSET)
	panel.Size = state.RestSize

	local fall = TweenService:Create(panel, TweenInfo.new(FALL_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = state.RestPosition,
		Rotation = 0,
	})
	fall.Completed:Connect(function(playbackState)
		if playbackState ~= Enum.PlaybackState.Completed or motion.Generation ~= generation or not panel.Parent then return end
		local impact = TweenService:Create(panel, TweenInfo.new(IMPACT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = squashedSize(state.RestSize),
		})
		impact.Completed:Connect(function(impactState)
			if impactState ~= Enum.PlaybackState.Completed or motion.Generation ~= generation or not panel.Parent then return end
			local settle = TweenService:Create(panel, TweenInfo.new(SETTLE_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = state.RestSize,
			})
			playTracked(motion, settle)
		end)
		playTracked(motion, impact)
	end)
	playTracked(motion, fall)
end

-- Проигрывает выход панели и вызывает onHidden() (например, panel.Visible
-- = false) в момент, когда панель ушла с экрана — используй его для
-- реальной уборки, не полагайся на Visible сразу после вызова Close.
function UiMotion.Close(panel, onHidden)
	local state = captureRest(panel)

	-- ГЛАВНАЯ ЗАЩИТА (см. подробное обоснование у объявления closing выше):
	-- панель уже закрывается — не перезапускаем анимацию, иначе повторное
	-- нажатие отменяет почти доигравший твин и панель не закроется вовсе.
	if closing[panel] then
		if onHidden then
			pendingHidden[panel] = pendingHidden[panel] or {}
			table.insert(pendingHidden[panel], onHidden)
		end
		return
	end
	closing[panel] = true
	pendingHidden[panel] = { }
	if onHidden then table.insert(pendingHidden[panel], onHidden) end

	-- СТОРОЖ. Полная цепочка закрытия занимает 0.04 + 0.13 = 0.17 с.
	-- Полсекунды — с многократным запасом. Если к этому моменту панель всё
	-- ещё числится закрывающейся, значит твин кто-то оборвал: прячем
	-- принудительно. Лучше пропустить анимацию, чем оставить игрока в окне,
	-- из которого он не может выйти.
	task.delay(0.5, function()
		if closing[panel] then
			finishClose(panel, state)
		end
	end)

	local motion, generation = beginMotion(panel)
	setScrollingContentVisible(panel, false)
	local anticipation = TweenService:Create(panel, TweenInfo.new(0.04, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = squashedSize(state.RestSize),
	})
	anticipation.Completed:Connect(function(playbackState)
		if playbackState ~= Enum.PlaybackState.Completed or motion.Generation ~= generation or not panel.Parent then return end
		if not closing[panel] then return end -- закрытие уже завершено сторожем или отменено Open
		local drop = TweenService:Create(panel, TweenInfo.new(CLOSE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = state.RestPosition - UDim2.fromOffset(0, DROP_OFFSET * 1.4),
			Rotation = TILT_DEGREES,
			Size = state.RestSize,
		})
		drop.Completed:Connect(function(dropState)
			if dropState ~= Enum.PlaybackState.Completed or motion.Generation ~= generation or not panel.Parent then return end
			finishClose(panel, state)
		end)
		playTracked(motion, drop)
	end)
	playTracked(motion, anticipation)
end

return UiMotion
