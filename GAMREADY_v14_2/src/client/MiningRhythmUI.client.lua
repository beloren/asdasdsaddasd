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
	warn("[MiningRhythmUI] RemoteEvent'ы мини-игры не появились — фича не будет работать, остальная игра не пострадает.")
	return
end

local gui = Instance.new("ScreenGui")
gui.Name = "MiningRhythmUi"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Parent = playerGui

-- Кольцо-таймер (уменьшающаяся дуга) вокруг самой кнопки — те же
-- дискретные сегменты, что уже использованы у кольца ХП валунов
-- (RockService.lua) и билборда слайма — единый визуальный язык проекта
-- вместо честной радиальной заливки (которая на UI требует более
-- хрупких трюков с ClipsDescendants/UIGradient, см. эти же файлы).
local RING_SEGMENTS = 10

-- Контейнер, который двигается по экрану целиком (кнопка+кольцо внутри
-- него всегда выровнены друг на друга, независимо от того, куда он
-- переехал) — по прямому запросу "в разных точках экрана". Безопасная
-- зона (см. randomSafePosition ниже) специально держится подальше от
-- краёв экрана, где обычно живёт остальной HUD (хотбар снизу, квесты/
-- шахта сверху и т.п.) — "главное не на UI".
local promptContainer = Instance.new("Frame")
promptContainer.Name = "PromptContainer"
promptContainer.AnchorPoint = Vector2.new(0.5, 0.5)
promptContainer.Position = UDim2.fromScale(0.5, 0.5)
promptContainer.Size = UDim2.fromOffset(120, 120)
promptContainer.BackgroundTransparency = 1
promptContainer.Parent = gui

local button = Instance.new("TextButton")
button.Name = "RhythmButton"
button.AnchorPoint = Vector2.new(0.5, 0.5)
button.Position = UDim2.fromScale(0.5, 0.5)
button.Size = UDim2.fromOffset(92, 92)
button.BackgroundColor3 = Color3.fromRGB(255, 210, 60)
button.AutoButtonColor = false
button.Font = Enum.Font.Arcade
button.TextScaled = true
button.TextColor3 = Color3.fromRGB(30, 24, 8)
button.TextStrokeTransparency = 1
button.Text = "TAP!"
button.Visible = false
button.ZIndex = 5
button.Parent = promptContainer
-- Квадратная кнопка по прямому запросу — БЕЗ UICorner (раньше был
-- CornerRadius=0.5, превращавший её в круг). TextButton по умолчанию и
-- так прямоугольный, скруглять было специально нужно только для круга.

local buttonStroke = Instance.new("UIStroke")
buttonStroke.Thickness = 3
buttonStroke.Color = Color3.fromRGB(255, 255, 255)
buttonStroke.Parent = button

local ringHolder = Instance.new("Frame")
ringHolder.Name = "RingHolder"
ringHolder.AnchorPoint = Vector2.new(0.5, 0.5)
ringHolder.Position = UDim2.fromScale(0.5, 0.5)
ringHolder.Size = UDim2.fromOffset(118, 118)
ringHolder.BackgroundTransparency = 1
ringHolder.ZIndex = 4
ringHolder.Parent = promptContainer
ringHolder.Visible = false -- ИНАЧЕ 10 белых квадратиков-сегментов видны сразу при заходе, до первого приглашения мини-игры (button.Visible уже был false, а этот — забыт)

-- Точка на ПЕРИМЕТРЕ КВАДРАТА (не круга — по прямому запросу) для t в
-- диапазоне [0, 4): каждая целая часть — одна сторона квадрата (верх →
-- право → низ → лево), дробная часть — положение вдоль этой стороны.
-- Возвращает x,y в масштабе [0,1] (0,0 — левый верхний угол).
local function squarePerimeterPoint(t)
	t = t % 4
	local side = math.floor(t)
	local along = t - side
	if side == 0 then return along, 0
	elseif side == 1 then return 1, along
	elseif side == 2 then return 1 - along, 1
	else return 0, 1 - along end
end

local ringSegments = {}
for i = 1, RING_SEGMENTS do
	local x, y = squarePerimeterPoint((i - 1) / RING_SEGMENTS * 4)
	local segment = Instance.new("Frame")
	segment.Name = "Segment" .. i
	segment.AnchorPoint = Vector2.new(0.5, 0.5)
	segment.Size = UDim2.fromOffset(12, 12)
	segment.Position = UDim2.fromScale(x, y)
	segment.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	segment.BackgroundTransparency = 0
	segment.BorderSizePixel = 0
	segment.ZIndex = 4
	-- Квадратные сегменты — БЕЗ UICorner, тот же принцип, что у кнопки.
	segment.Parent = ringHolder
	ringSegments[i] = segment
end

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
		Size = UDim2.fromOffset(92, 92),
	})
	local ringTween = TweenService:Create(ringHolder, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(118, 118),
	})
	tween:Play()
	ringTween:Play()
end

local function playHitFeedback()
	button.BackgroundColor3 = Color3.fromRGB(120, 255, 140)
	button.Text = "NICE!"
	local tween = TweenService:Create(button, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = UDim2.fromOffset(120, 120),
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
	button.BackgroundColor3 = stepColors[math.clamp(step, 1, #stepColors)]
	button.Text = maxSteps > 1 and ("TAP! %d/%d"):format(step, maxSteps) or "TAP!"
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
