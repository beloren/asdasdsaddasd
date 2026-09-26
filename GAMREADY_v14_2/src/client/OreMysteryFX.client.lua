--------------------------------------------------------------------------------
-- OreMysteryFX (LocalScript) — анимация "???" над ещё не раскрытой рудой и
-- "поп" настоящей надписи в момент раскрытия.
--
-- ПОЧЕМУ ЭТО НА КЛИЕНТЕ. Сервер (MineService: attachMysteryGui/revealPiece)
-- отвечает только за ФАКТЫ: билборд "MysteryGui" существует → руда ещё не
-- раскрыта; на нём появился атрибут Revealed → пора схлопнуться; на
-- "PriceGui" появился атрибут JustRevealed → пора показать настоящее имя.
-- Сама анимация (десятки изменений свойств в секунду на каждый кусок руды)
-- считается ЗДЕСЬ, у каждого игрока локально. Если бы её крутил сервер,
-- каждый кадр каждой буквы улетал бы в сеть всем клиентам — это буквально
-- худшее, что можно сделать с сетевым бюджетом ради косметики.
--
-- Скрипт полностью самодостаточен: нет папки MineGroundOre — просто ждёт.
-- Нет ни одной руды — цикл ничего не делает и почти ничего не стоит.
--------------------------------------------------------------------------------

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GROUND_FOLDER_NAME = "MineGroundOre"

-- Цвет "?" переливается между этими двумя — намеренно нейтральный
-- фиолетово-белый, чтобы НЕ намекать на редкость раньше времени (иначе
-- спойлер, который мы старательно прячем, утекал бы через цвет вопросиков).
local MYSTERY_COLOR_A = Color3.fromRGB(255, 255, 255)
local MYSTERY_COLOR_B = Color3.fromRGB(175, 140, 255)

-- Активные билборды: [BillboardGui] = { Marks = {TextLabel...}, Born = clock }
local tracked = {}

local function track(gui)
	if tracked[gui] then return end
	local marks = {}
	for _, child in gui:GetChildren() do
		if child:IsA("TextLabel") and child.Name:match("^Mark%d+$") then
			table.insert(marks, child)
		end
	end
	if #marks == 0 then return end
	-- Сортируем по позиции, а не по порядку GetChildren: порядок детей
	-- Roblox не гарантирует, а волна обязана идти слева направо.
	table.sort(marks, function(a, b) return a.Position.X.Scale < b.Position.X.Scale end)
	tracked[gui] = { Marks = marks, Born = os.clock(), Revealing = false }
end

local function untrack(gui)
	tracked[gui] = nil
end

--------------------------------------------------------------------------------
-- СХЛОПЫВАНИЕ "???" ПРИ РАСКРЫТИИ
--------------------------------------------------------------------------------
local function playCollapse(gui, entry)
	if entry.Revealing then return end
	entry.Revealing = true
	for index, mark in entry.Marks do
		-- Вопросики уходят не разом, а лесенкой — так читается "оно
		-- раскрывается", а не "надпись выключили".
		task.delay((index - 1) * 0.05, function()
			if not mark.Parent then return end
			local scale = mark:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
			scale.Parent = mark
			TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
				Scale = 0,
			}):Play()
			TweenService:Create(mark, TweenInfo.new(0.22), {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			}):Play()
		end)
	end
end

--------------------------------------------------------------------------------
-- "ПОП" НАСТОЯЩЕЙ НАДПИСИ (имя / шанс / цена) СРАЗУ ПОСЛЕ РАСКРЫТИЯ
--------------------------------------------------------------------------------
local function playPricePop(priceGui)
	local label = priceGui:FindFirstChildWhichIsA("TextLabel")
	if not label then return end
	local scale = label:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = label
	end
	scale.Scale = 0.1
	TweenService:Create(scale, TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
end

local function revealPriceGui(priceGui)
	if priceGui:GetAttribute("JustRevealed") ~= true then return end
	if priceGui:GetAttribute("_Popped") == true then return end
	priceGui:SetAttribute("_Popped", true)

	-- ПОРЯДОК КРИТИЧЕН: сначала сжимаем в точку, и только ПОТОМ включаем.
	-- Если включить раньше, зритель успеет увидеть надпись в полный
	-- размер — это и было вторым, "лишним" появлением.
	local label = priceGui:FindFirstChildWhichIsA("TextLabel")
	if label then
		local scale = label:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		scale.Scale = 0.01
		scale.Parent = label
	end
	priceGui.Enabled = true
	playPricePop(priceGui)
end

local function watchPriceGui(priceGui)
	revealPriceGui(priceGui)
	-- Подписка на сам атрибут: срабатывает В ТОТ ЖЕ КАДР, когда сервер
	-- его поставил. Опрос раз в полсекунды (он остался запасным путём для
	-- руды, приехавшей позже) давал задержку до 0.5 с — за это время
	-- надпись успевала побыть видимой без анимации.
	if priceGui:GetAttribute("_Watched") ~= true then
		priceGui:SetAttribute("_Watched", true)
		priceGui:GetAttributeChangedSignal("JustRevealed"):Connect(function()
			revealPriceGui(priceGui)
		end)
	end
end

--------------------------------------------------------------------------------
-- ОБХОД ПАПКИ С РУДОЙ
--------------------------------------------------------------------------------
local function scan(folder)
	for _, crystal in folder:GetChildren() do
		local mystery = crystal:FindFirstChild("MysteryGui", true)
		if mystery and mystery:IsA("BillboardGui") then
			track(mystery)
		end
		local priceGui = crystal:FindFirstChild("PriceGui", true)
		if priceGui then
			watchPriceGui(priceGui)
		end
	end
end

local function bindFolder(folder)
	scan(folder)
	folder.ChildAdded:Connect(function(crystal)
		-- Билборды приезжают репликацией чуть позже самой руды, поэтому
		-- не хватаем их в тот же кадр — отложенный проход дешевле и
		-- надёжнее, чем DescendantAdded на всю папку.
		task.delay(0.1, function()
			if crystal.Parent ~= folder then return end
			local mystery = crystal:FindFirstChild("MysteryGui", true)
			if mystery and mystery:IsA("BillboardGui") then track(mystery) end
		end)
	end)
end

task.spawn(function()
	local folder = workspace:WaitForChild(GROUND_FOLDER_NAME, 60)
	if folder then
		bindFolder(folder)
	else
		warn("[OreMysteryFX] workspace." .. GROUND_FOLDER_NAME .. " не появилась - анимация '???' выключена.")
	end
end)

--------------------------------------------------------------------------------
-- ГЛАВНЫЙ ЦИКЛ: волна + покачивание + перелив цвета
--------------------------------------------------------------------------------
local rescanClock = 0

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()

	-- Редкий перепроверочный обход (раз в полсекунды) — страховка на
	-- случай, если ChildAdded отработал раньше репликации билборда.
	rescanClock += dt
	if rescanClock >= 0.5 then
		rescanClock = 0
		local folder = workspace:FindFirstChild(GROUND_FOLDER_NAME)
		if folder then scan(folder) end
	end

	for gui, entry in tracked do
		if not gui.Parent then
			untrack(gui)
		else
			if gui:GetAttribute("Revealed") == true then
				playCollapse(gui, entry)
			end
			if not entry.Revealing then
				local elapsed = now - entry.Born
				for index, mark in entry.Marks do
					if mark.Parent then
						-- Фаза сдвинута на каждый знак — получается бегущая
						-- волна, а не три синхронно прыгающих символа.
						local phase = elapsed * 6 - (index - 1) * 0.7
						local bounce = math.sin(phase)
						-- Прыжок вверх-вниз внутри своей трети билборда.
						mark.Position = UDim2.new(
							(index - 1) / 3,
							0,
							0,
							math.round(-bounce * 6)
						)
						-- Лёгкий наклон в такт прыжку — "живые" вопросики.
						mark.Rotation = bounce * 10
						-- Перелив цвета общий для всех трёх, чтобы надпись
						-- читалась как одно целое, а не три гирлянды.
						mark.TextColor3 = MYSTERY_COLOR_A:Lerp(
							MYSTERY_COLOR_B,
							(math.sin(elapsed * 3) + 1) * 0.5
						)
					end
				end
			end
		end
	end
end)
