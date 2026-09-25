local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local UiMotion = require(ReplicatedStorage.Shared.UiMotion)
local UiSfx = require(ReplicatedStorage.Shared.UiSfx)
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage.Shared:WaitForChild("QuestRequest")

-- Иконка-эмодзи награды по типу (пока в Icon не поставлена картинка).
local KIND_EMOJI = { Money = "💰", Luck = "🍀", MutationPotion = "🧪", MiningBoost = "⛏", Skin = "🎨", CartColor = "🛒" }

local COLORS = {
	Panel = Color3.fromRGB(29, 34, 47),
	Card = Color3.fromRGB(52, 60, 78),
	Current = Color3.fromRGB(68, 112, 190),
	Claimed = Color3.fromRGB(50, 145, 82),
	Locked = Color3.fromRGB(55, 58, 68),
	Yellow = Color3.fromRGB(255, 204, 75),
	White = Color3.fromRGB(245, 247, 255),
	-- Цвет текста награды НА КАРТОЧКЕ, по типу (Kind) — см. render() ниже.
	-- Раньше весь текст награды всегда был обычным белым independent от
	-- того, деньги это, буст или скин — выглядело как мелкая подпись, а не
	-- как приз, который хочется получить.
	RewardMoney = Color3.fromRGB(120, 255, 140),
	RewardBoost = Color3.fromRGB(95, 210, 255),
	RewardSkin = Color3.fromRGB(255, 195, 70),
}

-- v20: окно собирается билдером (Shared.UiBuilders.DailyRewardUi →
-- StarterGui/DailyRewardUi) и правится в Studio; здесь только логика.
local UiKit = require(ReplicatedStorage.Shared.UiKit)
local gui = require(ReplicatedStorage.Shared.UiRegistry).Get("DailyRewardUi")
gui.DisplayOrder = 500

local dimmer = gui:FindFirstChild("Dimmer", true)
local panel = gui:FindFirstChild("Panel", true)
local closeButton = panel and panel:FindFirstChild("CloseButton", true)
local claimButton = panel and panel:FindFirstChild("ClaimButton", true)
local dayCards = {}
local cardsValid = true
for day = 1, 7 do
	dayCards[day] = panel and panel:FindFirstChild("Day" .. day, true)
	if not dayCards[day] or not dayCards[day]:IsA("GuiButton") then cardsValid = false end
end
if not (dimmer and panel and closeButton and claimButton and cardsValid) then
	warn("[DailyRewardUI] Contract is incomplete. Run tools/BuildAllUI.lua in Studio.")
	return
end

--------------------------------------------------------------------------------
-- КНОПКА ПОВТОРНОГО ОТКРЫТИЯ.
--
-- ЗАЧЕМ. До этого окно ежедневных наград нельзя было открыть ВРУЧНУЮ
-- вообще никак. Единственный путь — автопоказ, который срабатывает ОДИН
-- раз за сессию: через 2 минуты после захода (DAILY_REWARD_AUTO_OPEN_DELAY)
-- и только после завершения гайда. Последствия:
--   • Закрыл окно, не нажав CLAIM, — награда за день недоступна до
--     следующего захода. Стрик при этом продолжает тикать.
--   • Новый игрок за гайдом мог вообще не увидеть окно за всю первую
--     сессию.
--   • Проверить, на каком ты дне серии, было нельзя в принципе.
-- Со стороны это выглядело ровно как «награды за вход не работают».
--
-- Кнопка создаётся В КОДЕ, а не в Studio-ассете: так она появляется и у
-- тех, кто не перезапускал tools/BuildAllUI.lua, и контракт ассета
-- (проверка выше) остаётся прежним — ничего не ломается у существующих
-- сборок.
--------------------------------------------------------------------------------
local toggleButton = gui:FindFirstChild("DailyToggleButton")
-- v19.4: кнопка — в ряд со штатными кнопками Roblox в топбаре.
if toggleButton then
	require(ReplicatedStorage.Shared.TopbarDock).Add(toggleButton, 2)
end
local toggleBadge = toggleButton and toggleButton:FindFirstChild("Badge")

local iconMotion = {}
local activeIconTweens = {}
local pendingIconTasks = {}
local iconWaveGeneration = 0
for day, card in dayCards do
	local icon = card:FindFirstChild("Icon")
	if icon and icon:IsA("GuiObject") then
		local scale = icon:FindFirstChild("DailyRewardMotionScale") or Instance.new("UIScale")
		scale.Name = "DailyRewardMotionScale"
		scale.Scale = 1
		scale.Parent = icon
		-- Day нужен для расчёта индивидуального периода дыхания (см.
		-- startIconBreathing) — без него все семь иконок пульсировали бы с
		-- одинаковым периодом и рано или поздно сошлись бы в один такт.
		iconMotion[day] = { Icon = icon, Scale = scale, RestPosition = icon.Position, Day = day }
	else
		warn(("[DailyRewardUI] Panel.Day%d.Icon is missing or is not a GuiObject."):format(day))
	end
end

local function playTrackedIconTween(tween)
	activeIconTweens[tween] = true
	tween.Completed:Connect(function() activeIconTweens[tween] = nil end)
	tween:Play()
end

local function stopIconWave()
	iconWaveGeneration += 1
	for thread in pendingIconTasks do task.cancel(thread) end
	table.clear(pendingIconTasks)
	for tween in activeIconTweens do tween:Cancel() end
	table.clear(activeIconTweens)
	for _, motion in iconMotion do
		if motion.Icon.Parent then
			motion.Icon.Position = motion.RestPosition
			motion.Scale.Scale = 1
		end
	end
end

--------------------------------------------------------------------------------
-- ФОНОВОЕ "ДЫХАНИЕ" ИКОНОК
--
-- Раньше playIconWave() отыгрывал волну ОДИН раз при открытии, и дальше окно
-- стояло мёртвым. Теперь по окончании волны каждая иконка сама уходит в
-- бесконечную мягкую пульсацию, так что окно остаётся живым всё время, пока
-- открыто.
--
-- Почему НЕ через Shared/IconBounce.ApplyPulse, хотя она делает ровно это:
-- IconBounce тянет icon.Size НАПРЯМУЮ, а здесь вся анимация идёт через
-- отдельный UIScale (DailyRewardMotionScale). Смешав два канала, мы получили
-- бы две системы, дерущиеся за одну иконку, плюс stopIconWave() сбрасывает
-- Scale в 1 и не знал бы про Size — иконки бы дёргались и уезжали с места.
-- Поэтому дыхание живёт в том же канале UIScale, что и волна.
--
-- У каждого дня СВОЙ период вдоха (BREATH_TIME * (1 + day * 0.04)), а не
-- общий с разным стартовым сдвигом. Разные периоды означают, что иконки
-- постепенно расходятся по фазе и больше НИКОГДА не синхронизируются
-- обратно — иначе через минуту-другую все семь начали бы пульсировать
-- строем, как один механический тик.
--------------------------------------------------------------------------------
local BREATH_SCALE = 1.05 -- средняя заметность: видно, но не мельтешит
local BREATH_TIME = 0.7   -- половина цикла (вдох), полный цикл ~1.4 с

local function startIconBreathing(motion, generation)
	local breathThread
	breathThread = task.spawn(function()
		-- Период чуть свой у каждой иконки — см. комментарий выше.
		local period = BREATH_TIME * (1 + (motion.Day or 1) * 0.04)
		while generation == iconWaveGeneration and panel.Visible and motion.Icon.Parent do
			local up = TweenService:Create(motion.Scale, TweenInfo.new(period, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Scale = BREATH_SCALE })
			playTrackedIconTween(up)
			up.Completed:Wait()
			if generation ~= iconWaveGeneration or not panel.Visible or not motion.Icon.Parent then break end

			local down = TweenService:Create(motion.Scale, TweenInfo.new(period, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Scale = 1 })
			playTrackedIconTween(down)
			down.Completed:Wait()
		end
		pendingIconTasks[breathThread] = nil
	end)
	-- Регистрируем поток, чтобы stopIconWave() (закрытие окна) его снял —
	-- иначе при каждом открытии добавлялся бы ещё один вечный цикл поверх
	-- предыдущих, и через несколько открытий иконки пульсировали бы всё
	-- быстрее и рывками.
	pendingIconTasks[breathThread] = true
end

local function playIconWave()
	stopIconWave()
	local generation = iconWaveGeneration
	for day = 1, 7 do
		local motion = iconMotion[day]
		if motion then
			local delayedThread
			delayedThread = task.delay((day - 1) * 0.055, function()
				pendingIconTasks[delayedThread] = nil
				if generation ~= iconWaveGeneration or not panel.Visible or not motion.Icon.Parent then return end
				local moveUp = TweenService:Create(motion.Icon, TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
					Position = motion.RestPosition - UDim2.fromOffset(0, 6),
				})
				local scaleUp = TweenService:Create(motion.Scale, TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Scale = 1.08 })
				moveUp.Completed:Connect(function(state)
					if state ~= Enum.PlaybackState.Completed or generation ~= iconWaveGeneration or not motion.Icon.Parent then return end
					playTrackedIconTween(TweenService:Create(motion.Icon, TweenInfo.new(0.24, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Position = motion.RestPosition }))

					-- Возврат масштаба после волны — и сразу за ним старт
					-- бесконечного дыхания ИМЕННО ЭТОЙ иконки. Привязка к
					-- концу её собственного возврата (а не к общему таймеру
					-- "волна примерно закончилась") делает переход
					-- незаметным: иконка не успевает замереть между волной и
					-- дыханием. Заодно дыхание наследует шаг волны в 0.055 с,
					-- так что стартуют они уже вразнобой.
					local settle = TweenService:Create(motion.Scale, TweenInfo.new(0.24, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Scale = 1 })
					settle.Completed:Connect(function(settleState)
						if settleState ~= Enum.PlaybackState.Completed then return end
						if generation ~= iconWaveGeneration or not panel.Visible or not motion.Icon.Parent then return end
						startIconBreathing(motion, generation)
					end)
					playTrackedIconTween(settle)
				end)
				playTrackedIconTween(moveUp)
				playTrackedIconTween(scaleUp)
			end)
			pendingIconTasks[delayedThread] = true
		end
	end
end

--------------------------------------------------------------------------------
-- ДВИЖЕНИЕ КАРТОЧКИ ПРИ НАВЕДЕНИИ
--
-- Карточка слегка приподнимается и чуть наклоняется — этого хватает, чтобы
-- сетка дней перестала быть статичной таблицей и начала реагировать на
-- курсор.
--
-- ВАЖНО, ПОЧЕМУ ЗДЕСЬ НЕТ МАСШТАБА: карточки — это ImageButton, а значит их
-- УЖЕ обслуживает общий client/GlobalUiHover.client.lua, который вешает на
-- каждую кнопку свой UIScale ("GlobalHoverScale") и растягивает её до 1.06
-- при наведении. Добавь мы масштаб и тут — два эффекта перемножились бы
-- (1.06 x наш) и дёргали бы карточку двумя разными твинами одновременно.
-- Поэтому масштаб целиком оставлен общему механизму, а здесь только те
-- каналы, которых он не трогает: Position и Rotation. Ломать или отключать
-- GlobalUiHover ради этого не нужно.
--
-- На мобильных устройствах GlobalUiHover вообще не запускается (там нет
-- мыши), и MouseEnter/MouseLeave не приходят — на телефоне динамику
-- обеспечивает фоновое дыхание иконок выше, и это ожидаемо.
--------------------------------------------------------------------------------
local HOVER_LIFT = 3          -- на сколько пикселей карточка приподнимается
local HOVER_TILT = 1.5        -- наклон обычной карточки, градусы
local HOVER_TILT_WIDE = 0.6   -- наклон широкого баннера 7-го дня (см. ниже)
local HOVER_TIME = 0.12

local cardHoverTweens = {}

local function tweenCardHover(card, position, rotation)
	local previous = cardHoverTweens[card]
	if previous then previous:Cancel() end
	local tween = TweenService:Create(card, TweenInfo.new(HOVER_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = position,
		Rotation = rotation,
	})
	cardHoverTweens[card] = tween
	tween:Play()
end

local cardRest = {}
for day, card in dayCards do
	cardRest[card] = card.Position

	-- Наклон в разные стороны у соседних карточек: если все кренятся
	-- одинаково, сетка выглядит как один съехавший блок, а не как отдельные
	-- реагирующие карточки. У 7-го дня наклон меньше: это широкий баннер на
	-- 490px, и те же 1.5 градуса увели бы его углы заметно сильнее, чем у
	-- квадратных карточек 150x150 — визуально это читалось бы как перекос
	-- всей панели.
	local tilt = day == 7 and HOVER_TILT_WIDE or HOVER_TILT
	if day % 2 == 0 then tilt = -tilt end

	card.MouseEnter:Connect(function()
		if not panel.Visible then return end
		tweenCardHover(card, cardRest[card] - UDim2.fromOffset(0, HOVER_LIFT), tilt)
	end)
	card.MouseLeave:Connect(function()
		tweenCardHover(card, cardRest[card], 0)
	end)
end

-- Сброс наведения: если окно закрылось, пока курсор стоял на карточке,
-- MouseLeave может не прийти вовсе — и карточка осталась бы приподнятой и
-- повёрнутой до конца сессии.
local function resetCardHover()
	for card, rest in cardRest do
		local tween = cardHoverTweens[card]
		if tween then tween:Cancel() end
		cardHoverTweens[card] = nil
		if card.Parent then
			card.Position = rest
			card.Rotation = 0
		end
	end
end

local dailyVfxVisible = false
local assets = ReplicatedStorage:FindFirstChild("Assets")
local directVfxSource = ReplicatedStorage:FindFirstChild("DailyRewardVFX")
local assetsVfxSource = assets and assets:FindFirstChild("DailyRewardVFX")
local function resolveEmitter(container)
	if not container then return nil end
	if container:IsA("ParticleEmitter") then return container end
	return container:FindFirstChildWhichIsA("ParticleEmitter", true)
end
local vfxSource = resolveEmitter(directVfxSource) or resolveEmitter(assetsVfxSource)
local vfxHolder
local vfxEmitter
if vfxSource and vfxSource:IsA("ParticleEmitter") then
	vfxHolder = Instance.new("Part")
	vfxHolder.Name = "DailyRewardVFXHolder"
	vfxHolder.Size = Vector3.new(0.2, 0.2, 0.2)
	vfxHolder.Transparency = 1
	vfxHolder.Anchored = true
	vfxHolder.CanCollide = false
	vfxHolder.CanTouch = false
	vfxHolder.CanQuery = false
	vfxHolder.CastShadow = false
	vfxHolder.Parent = workspace
	vfxEmitter = vfxSource:Clone()
	vfxEmitter.LockedToPart = true
	vfxEmitter.Enabled = false
	vfxEmitter.Parent = vfxHolder
	local function syncVfxEnabled()
		local enabled = dailyVfxVisible and player:GetAttribute("IntroActive") ~= true
		if vfxEmitter.Enabled and not enabled then vfxEmitter:Clear() end
		vfxEmitter.Enabled = enabled
	end

	local vfxConnection
	vfxConnection = RunService.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		if not camera then return end
		syncVfxEnabled()
		if not vfxEmitter.Enabled then return end
		local viewport = camera.ViewportSize
		if viewport.X <= 0 or viewport.Y <= 0 then return end
		local screenPosition = panel.AbsolutePosition + panel.AbsoluteSize / 2
		local depth = tonumber(vfxSource:GetAttribute("Depth")) or 12
		local referenceHeight = tonumber(vfxSource:GetAttribute("ReferenceViewportHeight")) or 1080
		local scaledDepth = depth * viewport.Y / referenceHeight
		local halfHeight = scaledDepth * math.tan(math.rad(camera.FieldOfView) / 2)
		local normalizedX = (screenPosition.X / viewport.X - 0.5) * 2
		local normalizedY = (0.5 - screenPosition.Y / viewport.Y) * 2
		vfxHolder.CFrame = camera.CFrame * CFrame.new(
			normalizedX * halfHeight * viewport.X / viewport.Y,
			normalizedY * halfHeight,
			-scaledDepth
		)
	end)
	local introConnection = player:GetAttributeChangedSignal("IntroActive"):Connect(syncVfxEnabled)
	gui.Destroying:Connect(function()
		introConnection:Disconnect()
		vfxConnection:Disconnect()
		vfxHolder:Destroy()
	end)
end

local function resize()
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(600, 700)
	local scale = panel:FindFirstChild("ResponsiveScale")
	local baseWidth = panel:GetAttribute("BaseWidth") or 560
	local baseHeight = panel:GetAttribute("BaseHeight") or 590
	if scale then scale.Scale = math.min(1, (viewport.X - 24) / baseWidth, (viewport.Y - 40) / baseHeight) end
end
local viewportConnection
local function bindCurrentCamera()
	if viewportConnection then viewportConnection:Disconnect(); viewportConnection = nil end
	local camera = workspace.CurrentCamera
	if camera then viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(resize) end
	resize()
end
local cameraConnection = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCurrentCamera)
bindCurrentCamera()
gui.Destroying:Connect(function()
	if viewportConnection then viewportConnection:Disconnect() end
	cameraConnection:Disconnect()
end)

local openedOnJoin = false
local rewardState

local function setText(root, name, text)
	local item = root:FindFirstChild(name, true)
	if item and item:IsA("TextLabel") then item.Text = text end
end

-- Секунды → короткая подпись ступени ("1 MIN", "45 MIN", "1 HOUR").
local function formatMilestone(seconds)
	if seconds >= 3600 then
		local hours = seconds / 3600
		return (hours % 1 == 0 and "%d HOUR" or "%.1f HOUR"):format(hours)
	end
	return ("%d MIN"):format(math.floor(seconds / 60 + 0.5))
end

-- Сколько осталось до ступени.
local function formatRemaining(seconds)
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 60 then
		return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
	end
	return ("%ds"):format(seconds)
end

-- НАГРАДЫ ЗА ВРЕМЯ В ИГРЕ вместо ежедневных (по прямому запросу).
--
-- Карточки те же самые (Day1..Day7 из билдера — имена контракта менять
-- не стали, чтобы не ломать вёрстку), но показывают теперь ступени
-- игрового времени: 1 мин, 5, 10, 20, 30, 45 и час. Прогресс считает
-- СЕРВЕР и присылает в data.Playtime — клиент только рисует и просит
-- забрать конкретную ступень.
local function render(data)
	if typeof(data) ~= "table" then return end
	rewardState = data

	local playtime = data.Playtime
	local entries = playtime and playtime.Entries or {}
	local elapsed = playtime and playtime.Elapsed or 0
	local anyReady = false

	for index = 1, 7 do
		local card = dayCards[index]
		if card then
			local entry = entries[index]
			local reward = Config.Quests.PlaytimeRewards[index]
			if not (entry and reward) then
				card.Visible = false
			else
				card.Visible = true
				setText(card, "Day", formatMilestone(reward.Seconds))
				setText(card, "Reward", reward.Text or "REWARD")

				local rewardLabel = card:FindFirstChild("Reward", true)
				if rewardLabel then
					local rewardColor = COLORS.RewardMoney
					if reward.Kind == "MiningBoost" then
						rewardColor = COLORS.RewardBoost
					elseif reward.Kind == "Skin" or reward.Kind == "CartColor" then
						rewardColor = COLORS.RewardSkin
					end
					rewardLabel.TextColor3 = rewardColor
				end

				-- Вид состояния: забрано — зелёная рамка и галочка; готово —
				-- жёлтая рамка и уголки выделения; ещё рано — серая рамка.
				local stateColor = entry.Claimed and COLORS.Claimed or entry.Ready and COLORS.Yellow or COLORS.Locked
				local cardStroke = card:FindFirstChild("SkinStroke")
				if cardStroke then
					cardStroke.Color = stateColor
				else
					card.BackgroundColor3 = stateColor
				end
				local check = card:FindFirstChild("Check")
				if check then check.Visible = entry.Claimed == true end
				local brackets = card:FindFirstChild("Brackets")
				if brackets then brackets.Visible = entry.Ready == true and not entry.Claimed end
				local emoji = card:FindFirstChild("Emoji", true)
				if emoji and emoji.Parent and emoji.Parent.Name == "Icon" and emoji.Parent.Image == "" then
					emoji.Text = KIND_EMOJI[reward.Buff or reward.Kind] or "🎁"
				end
				setText(
					card,
					"Status",
					entry.Claimed and "CLAIMED"
						or entry.Ready and "CLICK TO CLAIM"
						or formatRemaining(reward.Seconds - elapsed)
				)
				card.Active = entry.Ready == true
				if entry.Ready then anyReady = true end
			end
		end
	end

	if toggleBadge then toggleBadge.Visible = anyReady end
	claimButton.Active = anyReady
	local claimText = anyReady and "CLAIM REWARD" or ("PLAYED " .. formatRemaining(elapsed))
	if claimButton:GetAttribute("UiSkin") then
		UiKit.ApplySkin(claimButton, anyReady and "Button_Green" or "Button_Claim")
	else
		claimButton.AutoButtonColor = anyReady
		claimButton.BackgroundColor3 = anyReady and COLORS.Claimed or COLORS.Locked
	end
	local claimCaption = claimButton:FindFirstChild("Caption")
	if claimCaption then
		claimCaption.Text = claimText
	elseif claimButton:IsA("TextButton") then
		claimButton.Text = claimText
	end
end

local function open()
	UiSfx.play("UiMenuOpen")
	dimmer.Visible = true
	dailyVfxVisible = true
	if vfxEmitter then
		vfxEmitter.Enabled = player:GetAttribute("IntroActive") ~= true
		if not vfxEmitter.Enabled then vfxEmitter:Clear() end
	end
	UiMotion.Open(panel)
	playIconWave()
end

local function close()
	stopIconWave()
	resetCardHover()
	dailyVfxVisible = false
	if vfxEmitter then vfxEmitter.Enabled = false; vfxEmitter:Clear() end
	dimmer.Visible = false
	UiMotion.Close(panel)
end


closeButton.Activated:Connect(close)
-- И кнопка "CLAIM DAY X" снизу, И клик прямо по карточке дня — оба способа
-- забрать награду теперь одинаково сразу закрывают окно. Раньше клик по
-- карточке НЕ закрывал сам — вместо этого статус менялся на "CLICK TO
-- CLOSE" и требовал второго клика по той же карточке, что и путало
-- (человек просто жал на крестик, не понимая, что нужно кликнуть ещё раз).
-- Забрать КОНКРЕТНУЮ ступень. Готовность проверяет сервер; здесь только
-- не даём жать по явно не готовой карточке, чтобы не слать мусор.
local function claim(index)
	local entries = rewardState and rewardState.Playtime and rewardState.Playtime.Entries
	local entry = entries and entries[index]
	if entry and entry.Ready then
		claimButton.Active = false
		remote:FireServer("ClaimPlaytimeReward", index)
	end
end

-- Кнопка снизу забирает ПЕРВУЮ готовую ступень — чтобы не заставлять
-- искать нужную карточку глазами.
local function claimFirstReady()
	local entries = rewardState and rewardState.Playtime and rewardState.Playtime.Entries
	if not entries then return end
	for index, entry in entries do
		if entry.Ready then
			claim(index)
			return
		end
	end
end

if toggleButton then toggleButton.Activated:Connect(function()
	-- Панель уже открыта — кнопка работает как переключатель, чтобы её
	-- нельзя было «залипить» повторным нажатием.
	if panel.Visible then close() else open() end
end) end

claimButton.Activated:Connect(claimFirstReady)
for day, card in dayCards do
	if card:IsA("GuiButton") then card.Activated:Connect(function()
		-- Active НЕ гасим руками: состояние карточки целиком принадлежит
		-- render(), и следующий State от сервера всё равно его перепишет.
		-- Ручная правка тут только рассинхронила бы картинку с сервером.
		claim(day)
	end) end
end

-- ЗАДЕРЖКА АВТОПОКАЗА ПРИ ЗАХОДЕ. Раньше окно выскакивало СРАЗУ на первом
-- же "State" от сервера — то есть буквально в первые секунды после захода,
-- одновременно (или почти) с экраном возврата (ReturnScreenUI) и прочими
-- приветственными всплывашками. Два модальных окна, конкурирующих за
-- внимание в первые секунды — это грубо и оба теряются на фоне друг друга.
-- Автопоказ теперь ждёт DAILY_REWARD_AUTO_OPEN_DELAY секунд с момента
-- старта этого скрипта (= момента захода) и срабатывает, только если к
-- этому времени награду ещё не забрали и игрок сам не открыл окно раньше.
-- Ручное открытие (кнопка/промпт → action == "Open") по-прежнему МГНОВЕННОЕ,
-- задержка касается только автопоказа "на всякий случай, вдруг забудете".
local DAILY_REWARD_AUTO_OPEN_DELAY = 120

remote.OnClientEvent:Connect(function(action, state)
	if action ~= "State" and action ~= "Open" then return end
	if typeof(state) ~= "table" then return end
	-- Рисуем ВЕСЬ state, а не state.DailyReward: награды за время игры
	-- лежат в state.Playtime, рядом с ежедневными, а не внутри них. С
	-- прежним аргументом render получал таблицу без поля Playtime и прятал
	-- все карточки — панель была пустой.
	render(state)
	if action == "Open" then
		openedOnJoin = true
		open()
	elseif not openedOnJoin then
		openedOnJoin = true
		task.delay(DAILY_REWARD_AUTO_OPEN_DELAY, function()
			local function tryOpen()
				-- Открываем только если ещё есть что забрать — иначе через
				-- 2 минуты игроку молча вылезло бы окно "CLAIMED TODAY", в
				-- котором взять уже нечего, просто отвлекающий шум.
				-- Открываем, только если есть ГОТОВАЯ ступень. Поле Claimed
				-- осталось от ежедневных наград и у наград за время игры не
				-- существует вовсе — условие было всегда истинным, и окно
				-- вылезало даже когда забирать нечего.
				local entries = rewardState and rewardState.Playtime and rewardState.Playtime.Entries
				local anyReady = false
				for _, entry in entries or {} do
					if entry.Ready then anyReady = true break end
				end
				if anyReady then
					open()
				end
			end
			-- Основной гайд у нового игрока вполне может идти дольше двух
			-- минут — ничего постороннего поверх него, та же причина, что
			-- и в NotifyService:Show. Ждём, пока NeedsTutorial не станет
			-- false, и только тогда открываем (если ещё актуально).
			if player:GetAttribute("NeedsTutorial") == true then
				local conn
				conn = player:GetAttributeChangedSignal("NeedsTutorial"):Connect(function()
					if player:GetAttribute("NeedsTutorial") ~= true then
						conn:Disconnect()
						tryOpen()
					end
				end)
			else
				tryOpen()
			end
		end)
	end
end)

remote:FireServer("RequestState")


--------------------------------------------------------------------------------
-- ЛОКАЛЬНЫЙ ТИК ОБРАТНОГО ОТСЧЁТА
--
-- Сервер шлёт State редко (на клейм и по событиям), а на карточках стоит
-- таймер "сколько осталось". Без локального хода он замер бы до следующего
-- пакета и выглядел бы сломанным. Поэтому раз в секунду ДОБАВЛЯЕМ секунду
-- к локальной копии Elapsed и перерисовываем — источником истины при
-- каждом State всё равно остаётся сервер, а ступень "готова" он проверяет
-- заново при клейме.
--------------------------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(1)
		local playtime = rewardState and rewardState.Playtime
		if playtime and panel.Visible then
			playtime.Elapsed = (playtime.Elapsed or 0) + 1
			for index, entry in playtime.Entries or {} do
				local reward = Config.Quests.PlaytimeRewards[index]
				if reward and not entry.Claimed and playtime.Elapsed >= reward.Seconds then
					entry.Ready = true
				end
			end
			local ok, err = pcall(render, rewardState)
			if not ok then warn("[DailyRewardUI] render failed:", err) end
		end
	end
end)
