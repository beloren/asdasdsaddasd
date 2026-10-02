--------------------------------------------------------------------------------
-- TreeReveal (v20.144) — анимации появления узлов деревьев прокачки
-- (Experienced Miner, Island Keeper, престиж). Через Size, а не UIScale:
-- на кнопках уже висит UIScale наведения, второй Roblox не применяет.
--   TreeReveal.Pop(node, delay)              пузырёк: 0 → размер с отскоком
--   TreeReveal.FadeIn(guiObject, delay)      плавное проявление (линии)
--   TreeReveal.Darken(backdrop, target, delay)
-- Config.TreeReveal: Stagger (пауза между пузырьками), PopSeconds, ...
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

local TreeReveal = {}

local function cfg()
	return Config.TreeReveal or {}
end
function TreeReveal.Settings()
	local c = cfg()
	return {
		RootSeconds = c.RootSeconds or 0.4,       -- центральный узел
		DarkenDelay = c.DarkenDelay or 0.3,       -- затемнение после центра
		DarkenSeconds = c.DarkenSeconds or 0.35,
		FirstDelay = c.FirstDelay or 0.55,        -- первый пузырёк после центра
		Stagger = c.Stagger or 0.07,              -- между пузырьками
		LateGap = c.LateGap or 0.2,               -- пауза перед доступными (некупленными)
		PopSeconds = c.PopSeconds or 0.34,
		LineSeconds = c.LineSeconds or 0.22,
		Sound = c.Sound ~= false,
		ChromeAt = c.ChromeAt or 0.7,             -- доля веток, после которой появляются кнопки
		ChromeStagger = c.ChromeStagger or 0.08,  -- между кнопками
	}
end

-- Момент для кнопок окна (PERKS / SHRINES / CLOSE ...): после того как
-- появилась бОльшая часть веток. times - список моментов появления узлов.
function TreeReveal.ChromeTime(times, fallback)
	if #times == 0 then return fallback or 0 end
	table.sort(times)
	local index = math.clamp(math.ceil(#times * TreeReveal.Settings().ChromeAt), 1, #times)
	return times[index]
end

-- Кнопки и надписи окна - пузырьками по очереди начиная с delay.
function TreeReveal.Chrome(list, delay, token, tokenRef)
	local s = TreeReveal.Settings()
	local index = 0
	for _, gui in list do
		if gui and gui:IsA("GuiObject") then
			TreeReveal.Pop(gui, delay + index * s.ChromeStagger, nil, token, tokenRef)
			index += 1
		end
	end
end

local function baseSize(gui)
	local stored = gui:GetAttribute("RevealSize")
	if typeof(stored) == "UDim2" then return stored end
	gui:SetAttribute("RevealSize", gui.Size)
	return gui.Size
end
TreeReveal.BaseSize = baseSize

-- Спрятать до анимации (узел остаётся на месте, просто нулевого размера).
function TreeReveal.Prepare(gui)
	local size = baseSize(gui)
	gui.Size = UDim2.new(0, 0, 0, 0)
	gui.Visible = true
	return size
end

local popSound = nil
local function tick()
	if not TreeReveal.Settings().Sound then return end
	local ok, UiSfx = pcall(require, ReplicatedStorage.Shared.UiSfx)
	if ok and UiSfx and UiSfx.play then
		local now = os.clock()
		if popSound and now - popSound < 0.05 then return end
		popSound = now
		pcall(UiSfx.play, "ReelTick")
	end
end

function TreeReveal.Pop(gui, delay, seconds, token, tokenRef)
	local size = TreeReveal.Prepare(gui)
	local s = TreeReveal.Settings()
	local function run()
		if token and tokenRef and tokenRef() ~= token then return end
		if not gui.Parent then return end
		gui.Size = UDim2.new(size.X.Scale * 0.2, size.X.Offset * 0.2, size.Y.Scale * 0.2, size.Y.Offset * 0.2)
		TweenService:Create(gui, TweenInfo.new(seconds or s.PopSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = size }):Play()
		tick()
	end
	if delay and delay > 0 then task.delay(delay, run) else run() end
end

function TreeReveal.FadeIn(gui, delay, seconds)
	local target = gui:GetAttribute("RevealTransparency")
	if type(target) ~= "number" then
		target = gui.BackgroundTransparency
		gui:SetAttribute("RevealTransparency", target)
	end
	gui.BackgroundTransparency = 1
	gui.Visible = true
	task.delay(delay or 0, function()
		if gui.Parent then
			TweenService:Create(gui, TweenInfo.new(seconds or TreeReveal.Settings().LineSeconds), { BackgroundTransparency = target }):Play()
		end
	end)
end

function TreeReveal.Darken(backdrop, target, delay, seconds)
	if not backdrop then return end
	backdrop.BackgroundTransparency = 1
	task.delay(delay or 0, function()
		if backdrop.Parent then
			TweenService:Create(backdrop, TweenInfo.new(seconds or TreeReveal.Settings().DarkenSeconds, Enum.EasingStyle.Quad), { BackgroundTransparency = target }):Play()
		end
	end)
end

return TreeReveal
