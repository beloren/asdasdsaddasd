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
-- иерархия лежит в StarterGui/ReturnScreenUi (см. tools/BuildAllUI.lua
-- — запусти его в Studio, если хочешь подвинуть/перекрасить экран руками).
-- Этот скрипт только НАХОДИТ инстансы по имени и подставляет в них текст —
-- никакой позиционной вёрстки здесь больше нет. Если билдер ни разу не
-- запускался (например, сразу после клонирования репозитория), ниже есть
-- buildFallback() — временная копия той же вёрстки в коде, чтобы экран не
-- пропал молча, плюс warn с напоминанием запустить билдер.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
-- v20: экран собирается билдером (Shared.UiBuilders.ReturnScreenUi →
-- StarterGui/ReturnScreenUi); нет в StarterGui — соберётся тем же билдером.
--------------------------------------------------------------------------------
local gui = require(ReplicatedStorage.Shared.UiRegistry).Get("ReturnScreenUi")
gui.DisplayOrder = 900

local dimmer = gui:FindFirstChild("Dimmer")
local panel = gui:FindFirstChild("Panel")
local title = panel and panel:FindFirstChild("Title", true)
local subtitle = panel and panel:FindFirstChild("AwaySubtitle", true)
local rowCart = panel and panel:FindFirstChild("RowCart", true)
local rowSafe = panel and panel:FindFirstChild("RowSafe", true)
local rowStreak = panel and panel:FindFirstChild("RowStreak", true)
local hintLabel = panel and panel:FindFirstChild("HintLabel", true)
local collectButton = panel and panel:FindFirstChild("CollectButton", true)
local panelScale = panel and panel:FindFirstChild("PanelScale", true)

if not (dimmer and panel and title and subtitle and rowCart and rowSafe and rowStreak and hintLabel and collectButton and panelScale) then
	warn("[ReturnScreenUI] Contract is incomplete. Run tools/BuildAllUI.lua in Studio.")
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
	if player:GetAttribute("NeedsTutorial") == true then
		-- Сводку не показываем, но пополнение денег — всё равно видно.
		local money = tonumber(payload.OfflineMoney) or 0
		if money > 0 then
			local ok, CoinShower = pcall(require, ReplicatedStorage.Shared.CoinShower)
			if ok then task.delay(1.5, CoinShower.Play, money) end
		end
		return
	end

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
	local offlineMoney = tonumber(payload.OfflineMoney) or 0
	if offlineMoney > 0 then
		-- v20.9: офлайн-доход деньгами (уже на счёте).
		rowCart.Visible = true
		local value = rowValue(rowCart)
		if value then
			value.Text = "+$" .. NumberFormat.abbreviate(math.floor(offlineMoney))
			value.TextColor3 = rowCart:GetAttribute("RowValueColor") or value.TextColor3
		end
	elseif cartOre > 0 then
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

	local collectCaption = collectButton:FindFirstChild("Caption")
	if collectCaption then
		collectCaption.Text = cfg.ButtonText or "COLLECT ALL"
	elseif collectButton:IsA("TextButton") then
		collectButton.Text = cfg.ButtonText or "COLLECT ALL"
	end

	-- v20.27: деньги за офлайн уже на счёте — на закрытии экрана монетки
	-- вылетают из кнопки и «пополняют» счётчик денег (shared/CoinShower).
	local showered = false
	local function shower()
		if showered or offlineMoney <= 0 then return end
		showered = true
		local ok, CoinShower = pcall(require, ReplicatedStorage.Shared.CoinShower)
		if ok then
			local from = collectButton.AbsoluteSize.X > 0 and CoinShower.ScreenCenter(collectButton) or nil
			task.defer(CoinShower.Play, offlineMoney, from)
		end
	end
	local connection
	connection = collectButton.MouseButton1Click:Connect(function()
		connection:Disconnect()
		shower()
		close()
	end)
	local closeButton = panel:FindFirstChild("CloseButton", true)
	if closeButton and closeButton:IsA("GuiButton") then
		local closeConnection
		closeConnection = closeButton.MouseButton1Click:Connect(function()
			closeConnection:Disconnect()
			if connection.Connected then connection:Disconnect() end
			shower()
			close()
		end)
	end

	-- Автозакрытие: экран не должен зависать поверх игры, если игрок
	-- отвлёкся или тапнул мимо. Токен — если за это время пришёл новый
	-- пакет (перезаход), старый таймер ничего не закроет.
	task.delay(tonumber(cfg.AutoCloseAfter) or 20, function()
		if activeToken == token then
			if connection.Connected then connection:Disconnect() end
			shower()
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
