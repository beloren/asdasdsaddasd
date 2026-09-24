--------------------------------------------------------------------------------
-- ЭКРАН ВОЗВРАЩЕНИЯ — «WHILE YOU WERE AWAY»
--
-- Один экран со всеми офлайн-итогами сразу вместо четырёх разрозненных
-- всплывашек в разное время. Смысл ровно в этом: три мелких события, которые
-- игрок не связывает между собой, дают три слабых эмоции, а собранные в один
-- момент — одну сильную «меня тут ждали».
--
-- Данные приходят ГОТОВЫМИ с сервера (ReturnScreenService), клиент ничего не
-- считает и ничего не выдаёт: руда уже лежит в тележке, деньги уже начислены
-- в сейф. Кнопка здесь — это «понятно, играем», а не транзакция. Подделать
-- отсюда нечего.
--
-- ВАЖНО ПРО ФОРМУЛИРОВКИ. Строка сейфа говорит «Safe accumulated», а НЕ
-- «получено» — деньги действительно лежат в сейфе и их ещё нужно забрать у
-- самого сейфа на участке. Врать тут нельзя: игрок пойдёт проверять баланс,
-- не увидит там этих денег и решит, что игра его обманула.
--
-- ОТКУДА ГЕОМЕТРИЯ. Раньше весь экран строился кодом в рантайме (единственный
-- такой экран в проекте). Теперь, как и Daily/Group/Like Reward, авторская
-- иерархия лежит в StarterGui/ReturnScreenUi (см. tools/BuildReturnScreenUI.lua
-- — запусти его в Studio, если хочешь подвинуть/перекрасить экран руками).
-- Этот скрипт только НАХОДИТ инстансы по имени и подставляет в них текст —
-- никакой позиционной вёрстки здесь больше нет. Если билдер ни разу не
-- запускался (например, сразу после клонирования репозитория), ниже есть
-- buildFallback() — временная копия той же вёрстки в коде, чтобы экран не
-- пропал молча, плюс warn с напоминанием запустить билдер.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ReturnScreenEvent")

local cfg = Config.ReturnScreen or {}

local function formatDuration(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local days = math.floor(seconds / 86400)
	local hours = math.floor((seconds % 86400) / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	if days > 0 then return ("%dd %dh"):format(days, hours) end
	if hours > 0 then return ("%dh %02dm"):format(hours, minutes) end
	return ("%dm"):format(minutes)
end

--------------------------------------------------------------------------------
-- FALLBACK. Ровно та же вёрстка, что и в tools/BuildReturnScreenUI.lua, но
-- собранная кодом — на случай, если билдер ещё не запускали в этом Studio-
-- проекте. Держать её синхронной с билдером не нужно 1-в-1: это подстраховка
-- на один запуск, а не второй источник истины по стилю.
--------------------------------------------------------------------------------
local function corner(parent, radius)
	local instance = Instance.new("UICorner")
	instance.CornerRadius = UDim.new(0, radius)
	instance.Parent = parent
	return instance
end

local function stroke(parent, thickness, color, transparency)
	local instance = Instance.new("UIStroke")
	instance.Thickness = thickness
	instance.Color = color
	instance.Transparency = transparency or 0
	instance.Parent = parent
	return instance
end

local function fallbackRow(name, order, emoji, caption, valueColor, parent)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, 0, 0, 46)
	frame.BackgroundColor3 = Color3.fromRGB(28, 33, 46)
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame:SetAttribute("RowValueColor", valueColor)
	frame.Parent = parent
	corner(frame, 10)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = frame

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0, 34, 1, 0)
	icon.BackgroundTransparency = 1
	icon.Font = Enum.Font.GothamBold
	icon.Text = emoji
	icon.TextScaled = true
	icon.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Position = UDim2.new(0, 40, 0, 0)
	label.Size = UDim2.new(1, -40, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.Text = caption
	label.TextColor3 = Color3.fromRGB(196, 204, 220)
	label.TextSize = 15
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = frame

	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.Size = UDim2.fromScale(1, 1)
	value.BackgroundTransparency = 1
	value.Font = Enum.Font.GothamBold
	value.Text = ""
	value.TextColor3 = valueColor or Color3.fromRGB(255, 255, 255)
	value.TextSize = 17
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.Parent = frame

	return frame
end

local function buildFallback()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ReturnScreenUi"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 900
	gui.Parent = playerGui

	local dimmer = Instance.new("Frame")
	dimmer.Name = "Dimmer"
	dimmer.Size = UDim2.fromScale(1, 1)
	dimmer.BackgroundColor3 = Color3.new(0, 0, 0)
	dimmer.BackgroundTransparency = 1
	dimmer.BorderSizePixel = 0
	dimmer.Visible = false
	dimmer.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.86, 0, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 16)
	stroke(panel, 2, Color3.fromRGB(90, 130, 200), 0.35)

	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(420, math.huge)
	sizeLimit.Parent = panel

	local scale = Instance.new("UIScale")
	scale.Name = "PanelScale"
	scale.Scale = 0.9
	scale.Parent = panel

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 18)
	pad.PaddingBottom = UDim.new(0, 18)
	pad.PaddingLeft = UDim.new(0, 18)
	pad.PaddingRight = UDim.new(0, 18)
	pad.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.LayoutOrder = 0
	title.Size = UDim2.new(1, 0, 0, 26)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Text = "WHILE YOU WERE AWAY"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 20
	title.Parent = panel

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "AwaySubtitle"
	subtitle.LayoutOrder = 1
	subtitle.Size = UDim2.new(1, 0, 0, 18)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.Text = "You were gone"
	subtitle.TextColor3 = Color3.fromRGB(138, 147, 166)
	subtitle.TextSize = 14
	subtitle.Parent = panel

	local spacer = Instance.new("Frame")
	spacer.Name = "Spacer"
	spacer.LayoutOrder = 2
	spacer.Size = UDim2.new(1, 0, 0, 6)
	spacer.BackgroundTransparency = 1
	spacer.Parent = panel

	fallbackRow("RowCart", 3, "⛏️", "Mine kept working", Color3.fromRGB(120, 220, 255), panel)
	fallbackRow("RowSafe", 4, "🔐", "Safe accumulated", Color3.fromRGB(95, 255, 130), panel)
	fallbackRow("RowStreak", 5, "🔥", "Streak", Color3.fromRGB(255, 190, 70), panel)

	local hint = Instance.new("TextLabel")
	hint.Name = "HintLabel"
	hint.LayoutOrder = 6
	hint.Size = UDim2.new(1, 0, 0, 16)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Gotham
	hint.Text = "Your cart is loaded — deliver it to the bank"
	hint.TextColor3 = Color3.fromRGB(138, 147, 166)
	hint.TextSize = 12
	hint.Visible = false
	hint.Parent = panel

	local button = Instance.new("TextButton")
	button.Name = "CollectButton"
	button.LayoutOrder = 7
	button.Size = UDim2.new(1, 0, 0, 44)
	button.BackgroundColor3 = Color3.fromRGB(60, 150, 250)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.Text = "COLLECT ALL"
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextSize = 17
	button.AutoButtonColor = true
	button.Parent = panel
	corner(button, 10)

	return gui
end

--------------------------------------------------------------------------------
-- КОНТРАКТ. Ищем авторскую версию (playerGui клонирует StarterGui сам, до
-- этого момента может понадобиться подождать секунду), иначе строим fallback.
--------------------------------------------------------------------------------
local gui = playerGui:FindFirstChild("ReturnScreenUi")
local authored = StarterGui:FindFirstChild("ReturnScreenUi")
if not gui and authored then gui = playerGui:WaitForChild("ReturnScreenUi", 5) end
if not gui then
	warn("[ReturnScreenUI] StarterGui/ReturnScreenUi not found — using code fallback. Run tools/BuildReturnScreenUI.lua in Studio to make it editable.")
	gui = buildFallback()
end
gui.DisplayOrder = 900

local dimmer = gui:FindFirstChild("Dimmer")
local panel = gui:FindFirstChild("Panel")
local title = panel and panel:FindFirstChild("Title")
local subtitle = panel and panel:FindFirstChild("AwaySubtitle")
local rowCart = panel and panel:FindFirstChild("RowCart")
local rowSafe = panel and panel:FindFirstChild("RowSafe")
local rowStreak = panel and panel:FindFirstChild("RowStreak")
local hintLabel = panel and panel:FindFirstChild("HintLabel")
local collectButton = panel and panel:FindFirstChild("CollectButton")
local panelScale = panel and panel:FindFirstChild("PanelScale")

if not (dimmer and panel and title and subtitle and rowCart and rowSafe and rowStreak and hintLabel and collectButton and panelScale) then
	warn("[ReturnScreenUI] Contract is incomplete. Run tools/BuildReturnScreenUI.lua in Studio.")
	return
end

local function rowValue(rowFrame)
	return rowFrame:FindFirstChild("Value")
end

local activeToken

local function close()
	if not activeToken then return end
	activeToken = nil
	TweenService:Create(panelScale, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.9 }):Play()
	TweenService:Create(dimmer, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
	task.delay(0.22, function()
		if activeToken then return end -- новый экран уже открылся поверх — не гасим его
		dimmer.Visible = false
		panel.Visible = false
	end)
end

local function present(payload)
	if typeof(payload) ~= "table" then return end
	-- Ничего постороннего поверх основного гайда — та же причина, что и в
	-- NotifyService:Show. В отличие от Daily Reward это одноразовое
	-- серверное событие (не поллинг), поэтому просто не показываем: для
	-- игрока, который ТОЛЬКО ЧТО завёл аккаунт (обычный случай для гайда),
	-- офлайн-заработка ещё физически нет, а для уже игравшего, которому
	-- гайд включили заново (например, версию гайда подняли), один пропуск
	-- сводки — приемлемая цена за то, чтобы не отвлекать от карточки гайда.
	if player:GetAttribute("NeedsTutorial") == true then return end

	local token = {}
	activeToken = token

	dimmer.Visible = true
	panel.Visible = true
	dimmer.BackgroundTransparency = 1
	TweenService:Create(dimmer, TweenInfo.new(0.25), { BackgroundTransparency = 0.45 }):Play()

	panelScale.Scale = 0.9
	TweenService:Create(panelScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	title.Text = cfg.Title or "WHILE YOU WERE AWAY"
	subtitle.Text = "You were gone " .. formatDuration(payload.OfflineSeconds)

	local cartOre = tonumber(payload.CartOre) or 0
	if cartOre > 0 then
		rowCart.Visible = true
		local value = rowValue(rowCart)
		if value then
			value.Text = ("%d ore  ·  $%s"):format(cartOre, NumberFormat.abbreviate(math.floor(payload.CartValue or 0)))
			value.TextColor3 = rowCart:GetAttribute("RowValueColor") or value.TextColor3
		end
	else
		rowCart.Visible = false
	end

	local safe = tonumber(payload.Safe) or 0
	if safe > 0 then
		rowSafe.Visible = true
		local value = rowValue(rowSafe)
		if value then
			value.Text = "$" .. NumberFormat.abbreviate(math.floor(safe))
			value.TextColor3 = rowSafe:GetAttribute("RowValueColor") or value.TextColor3
		end
	else
		rowSafe.Visible = false
	end

	if payload.Streak and payload.Streak > 0 then
		rowStreak.Visible = true
		local streakLabel = rowStreak:FindFirstChild("Label")
		if streakLabel then streakLabel.Text = ("Day %d streak"):format(payload.Streak) end
		local value = rowValue(rowStreak)
		if value then
			if (payload.StreakSeconds or 0) <= 0 then
				value.Text = "Reward ready"
			else
				value.Text = "Resets in " .. formatDuration(payload.StreakSeconds)
			end
			value.TextColor3 = rowStreak:GetAttribute("RowValueColor") or value.TextColor3
		end
	else
		rowStreak.Visible = false
	end

	-- Подсказка, что руда лежит в тележке и её ещё надо довезти: без неё
	-- игрок может решить, что деньги уже у него, и не понять, зачем ехать.
	hintLabel.Visible = cartOre > 0

	collectButton.Text = cfg.ButtonText or "COLLECT ALL"

	local connection
	connection = collectButton.MouseButton1Click:Connect(function()
		connection:Disconnect()
		close()
	end)

	-- Автозакрытие: экран не должен зависать поверх игры, если игрок
	-- отвлёкся или тапнул мимо. Токен — если за это время пришёл новый
	-- пакет (перезаход), старый таймер ничего не закроет.
	task.delay(tonumber(cfg.AutoCloseAfter) or 20, function()
		if activeToken == token then
			if connection.Connected then connection:Disconnect() end
			close()
		end
	end)
end

remote.OnClientEvent:Connect(function(payload)
	local ok, err = pcall(present, payload)
	if not ok then
		warn("[ReturnScreenUI] Не удалось показать экран возвращения:", err)
	end
end)
