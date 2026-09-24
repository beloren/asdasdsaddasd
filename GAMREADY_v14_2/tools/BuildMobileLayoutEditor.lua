--------------------------------------------------------------------------------
-- BuildMobileLayoutEditor
-- Визуальный редактор мобильной раскладки — ЦЕЛИКОМ в Studio, без единой
-- строчки кода с твоей стороны.
--
-- КАК ПОЛЬЗОВАТЬСЯ:
-- 1) Запусти этот скрипт через Command Bar один раз.
-- 2) В Studio: Test → Device (переключись на телефон, любую модель).
-- 3) В Explorer открой StarterGui → MobileLayoutEditor → включи Enabled
--    (галочка) — увидишь цветные прямоугольники с подписями поверх экрана.
-- 4) Обычным перетаскиванием мышкой (как любой Frame) подвинь/растяни
--    каждый прямоугольник туда, где хочешь видеть настоящий элемент.
--    Подписи над каждым говорят, что это ("BOOK BUTTON", "QUEST PANEL").
-- 5) Когда закончил — запусти tools/HarvestMobileLayout.lua через Command
--    Bar. Он распечатает готовый кусок Lua в Output — скопируй его и
--    вставь в Config.lua, заменив текущее "Config.MobileLayout = {}".
-- 6) Выключи Enabled у MobileLayoutEditor обратно (или вообще удали его из
--    StarterGui) — игрокам он видеть не нужен, это только твой инструмент.
--
-- Чтобы добавить ЕЩЁ один элемент под управление этой системой: добавь сюда
-- новый addPlaceholder(...) с тем же именем-ключом, что передаёшь в
-- MobileLayoutOverride.Apply(key, element) в реальном скрипте элемента.
--------------------------------------------------------------------------------

local StarterGui = game:GetService("StarterGui")

local existing = StarterGui:FindFirstChild("MobileLayoutEditor")
if existing then existing:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "MobileLayoutEditor"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Enabled = false -- включи вручную в Explorer, когда будешь двигать
gui.Parent = StarterGui

local instructions = Instance.new("TextLabel")
instructions.Name = "Instructions"
instructions.Size = UDim2.new(1, 0, 0, 40)
instructions.BackgroundColor3 = Color3.new(0, 0, 0)
instructions.BackgroundTransparency = 0.3
instructions.Font = Enum.Font.SourceSansBold
instructions.TextScaled = true
instructions.TextColor3 = Color3.new(1, 1, 1)
instructions.Text = "Drag the boxes below, then run HarvestMobileLayout.lua"
instructions.Parent = gui

local function addPlaceholder(key, color, position, size)
	local frame = Instance.new("Frame")
	frame.Name = key -- ВАЖНО: имя = ключ в Config.MobileLayout, не переименовывай
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = 0.35
	frame.BorderSizePixel = 2
	frame.BorderColor3 = Color3.new(1, 1, 1)
	frame.Parent = gui
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.SourceSansBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0
	label.Text = key
	label.Parent = frame
	return frame
end

-- Текущие позиции по умолчанию (см. CollectionMenu.client.lua,
-- QuestUI.client.lua) — старт с них, чтобы не начинать с нуля.
addPlaceholder("BookButton", Color3.fromRGB(150, 100, 55), UDim2.new(0, 12, 0.5, -47), UDim2.fromOffset(52, 52))
addPlaceholder("QuestPanel", Color3.fromRGB(45, 140, 220), UDim2.new(0, 12, 0.5, -150), UDim2.fromOffset(280, 100))

print("[BuildMobileLayoutEditor] Done. Enable StarterGui.MobileLayoutEditor in Explorer, switch to a phone Device in Test settings, then drag the boxes.")
