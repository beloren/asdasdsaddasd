--------------------------------------------------------------------------------
-- MiningRhythmUI (LocalScript)
-- Мини-игра "успей нажать" во время добычи (см. Config.MiningRhythm) — по
-- прямому запросу, чтобы не было скучно стоять и ждать, пока шахта сама
-- заполнит тележку. Сервер (MineService.lua) время от времени присылает
-- приглашение (RemoteEvent "MiningRhythmPrompt") с токеном и окном на
-- реакцию; успел нажать вовремя — шлём токен обратно ("MiningRhythmHit"),
-- сервер САМ проверяет тайминг (клиентское время не доверенное) и,
-- если всё сошлось, кидает Config.MiningRhythm.RewardOreCount руды в
-- тележку одним махом. Промах — просто пропущенная возможность, без
-- какого-либо штрафа.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

-- РУДА v2: механика "тележка стоит в зоне шахты → мигает кнопка" выключена
-- (см. Config.MiningRhythm.Enabled = false и новый MineService.lua —
-- добыча теперь идёт через НПС-экспедицию, см. MineExpeditionUI.client.lua).
-- Выходим СРАЗУ, не дожидаясь 10-секундного таймаута WaitForChild ниже —
-- RemoteEvent'ы этой фичи больше не создаются сервером вообще, ждать их
-- бессмысленно, и это не ошибка, поэтому без warn.
if Config.MiningRhythm.Enabled ~= true then
	return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local promptRemote = ReplicatedStorage.Shared:WaitForChild("MiningRhythmPrompt", 10)
local hitRemote = ReplicatedStorage.Shared:WaitForChild("MiningRhythmHit", 10)
if not (promptRemote and hitRemote) then
	warn("[MiningRhythmUI] RemoteEvent'ы мини-игры не появились - фича не будет работать, остальная игра не пострадает.")
	return
end

-- v20: вид — Shared.UiBuilders.MiningRhythmUi (StarterGui/MiningRhythmUi).
local RhythmBuilder = require(ReplicatedStorage.Shared.UiBuilders.MiningRhythmUi)
local UiKit = require(ReplicatedStorage.Shared.UiKit)
local gui = require(ReplicatedStorage.Shared.UiRegistry).Get("MiningRhythmUi")
local promptContainer = gui:WaitForChild("PromptContainer")
local button = promptContainer:WaitForChild("RhythmButton")
local buttonCaption = button:WaitForChild("Caption")
local ringHolder = promptContainer:WaitForChild("RingHolder")
button.Visible = false
ringHolder.Visible = false -- иначе сегменты кольца видны сразу при заходе
local BUTTON_SIZE = RhythmBuilder.BUTTON_SIZE
local RING_SIZE = RhythmBuilder.RING_SIZE

local ringSegments = {}
for i = 1, RhythmBuilder.RING_SEGMENTS do
	local segment = ringHolder:FindFirstChild("Segment" .. i)
	if not segment then break end
	ringSegments[i] = segment
end
local RING_SEGMENTS = #ringSegments

local activeToken = nil
local hideTweenToken = 0

-- Случайная позиция В БЕЗОПАСНОЙ ЗОНЕ экрана — по прямому запросу "в
-- разных точках экрана, главное не на UI". Отступы от краёв специально
-- щедрые: сверху/снизу побольше (там обычно живёт хотбар/квесты/шкала
-- здоровья), по бокам поменьше.
local SAFE_ZONE = { Left = 0.12, Right = 0.88, Top = 0.22, Bottom = 0.72 }
local function randomSafePosition()
	local x = SAFE_ZONE.Left + math.random() * (SAFE_ZONE.Right - SAFE_ZONE.Left)
	local y = SAFE_ZONE.Top + math.random() * (SAFE_ZONE.Bottom - SAFE_ZONE.Top)
	return UDim2.fromScale(x, y)
end

-- Мини-игра НЕ должна появляться поверх окон "оцени игру"/"вступи в
-- группу" — по прямому запросу, чтобы не было конфликтов на экране.
-- Both ScreenGui — Enabled=true, пока показывается попап (см. showPopup/
-- closePopup в LikeRewardUI.client.lua/GroupRewardUI.client.lua).
local function isBlockingPopupOpen()
	local likeGui = playerGui:FindFirstChild("LikeRewardUi")
	local groupGui = playerGui:FindFirstChild("GroupRewardUi")
	return (likeGui and likeGui.Enabled) or (groupGui and groupGui.Enabled) or false
end

local function setRingLit(count)
	for i, segment in ringSegments do
		segment.Visible = i <= count
	end
end

local function hidePrompt()
	activeToken = nil
	button.Visible = false
	ringHolder.Visible = false
end

local function isCarryingCart()
	return player:GetAttribute("CarryingCart") == true
end

player:GetAttributeChangedSignal("CarryingCart"):Connect(function()
	if not isCarryingCart() then hidePrompt() end
end)

local function popIn()
	button.Size = UDim2.fromOffset(20, 20)
	ringHolder.Size = UDim2.fromOffset(30, 30)
	local tween = TweenService:Create(button, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
	})
	local ringTween = TweenService:Create(ringHolder, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(RING_SIZE, RING_SIZE),
	})
	tween:Play()
	ringTween:Play()
end

local function playHitFeedback()
	UiKit.SetButtonVariant(button, "Green")
	buttonCaption.Text = "NICE!"
	local tween = TweenService:Create(button, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = UDim2.fromOffset(BUTTON_SIZE * 1.3, BUTTON_SIZE * 1.3),
	})
	tween:Play()
	task.delay(0.16, hidePrompt)
end

button.Activated:Connect(function()
	if not activeToken then return end
	local token = activeToken
	hitRemote:FireServer(token)
	playHitFeedback()
end)

promptRemote.OnClientEvent:Connect(function(token, windowSeconds, step, maxSteps)
	if type(token) ~= "string" or type(windowSeconds) ~= "number" then return end
	if not isCarryingCart() then return end
	if isBlockingPopupOpen() then return end -- см. isBlockingPopupOpen выше — не мешаем окну лайка/группы
	step = tonumber(step) or 1
	maxSteps = tonumber(maxSteps) or 1
	activeToken = token

	-- Новая случайная точка на экране на КАЖДОЕ приглашение, включая
	-- продолжение комбо-цепочки — по прямому запросу "в разных точках".
	promptContainer.Position = randomSafePosition()

	-- Цвет разогревается с каждым шагом комбо (жёлтый → оранжевый →
	-- красный) — визуально "давит" сильнее ровно тогда, когда времени на
	-- реакцию физически меньше (см. Config.MiningRhythm.ComboWindowSeconds).
	local stepColors = {
		Color3.fromRGB(255, 210, 60),
		Color3.fromRGB(255, 170, 50),
		Color3.fromRGB(255, 130, 60),
		Color3.fromRGB(255, 95, 70),
		Color3.fromRGB(255, 60, 60),
	}
	UiKit.SetButtonVariant(button, "Yellow")
	UiKit.Tint(button, stepColors[math.clamp(step, 1, #stepColors)])
	buttonCaption.Text = maxSteps > 1 and ("TAP! %d/%d"):format(step, maxSteps) or "TAP!"
	button.Visible = true
	ringHolder.Visible = true
	setRingLit(RING_SEGMENTS)
	popIn()

	hideTweenToken += 1
	local myHideToken = hideTweenToken
	task.spawn(function()
		local steps = RING_SEGMENTS
		for i = steps, 0, -1 do
			if myHideToken ~= hideTweenToken or activeToken ~= token then
				return -- попали или пришло новое приглашение — не тикаем чужое кольцо
			end
			setRingLit(i)
			task.wait(windowSeconds / steps)
		end
		if activeToken == token then
			-- Не успели — тихо прячем, без штрафа и без звука/сообщения.
			-- Комбо на этом обрывается (см. MineService.lua — цепочка
			-- продолжается только сервером, только на реальное попадание).
			hidePrompt()
		end
	end)
end)
