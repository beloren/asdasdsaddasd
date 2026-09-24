--------------------------------------------------------------------------------
-- HudService
-- Экранный HUD: круглый портрет живого персонажа (ViewportFrame,
-- заполняется/крутится клиентским src/client/PlayerPortraitHud.client.lua —
-- этот сервис его не трогает) + плашка баланса + плашка престижа
-- (см. ТЗ/референс — заменили прежнюю пару одинаковых пилюль в столбик).
-- Обновляется СЕРВЕРОМ (изменения Instance реплицируются) — отдельных
-- клиентских скриптов у текстовых плашек нет.
--
-- UI НЕ СОЗДАЁТСЯ КОДОМ. Он лежит готовым в StarterGui/Hud (собран билдером
-- в Studio, см. tools/BuildUIAssets.lua), Roblox сам клонирует его в
-- PlayerGui каждому игроку — сервис лишь находит нужные части по именам и
-- обновляет текст.
--
-- КОНТРАКТ (StarterGui/Hud) — обязателен, иначе HUD у игрока не появится:
--   ScreenGui "Hud"  (ResetOnSpawn лучше false — респавн ручной)
--   ├─ (где угодно внутри) ViewportFrame "Portrait" — портрет персонажа (см. PlayerPortraitHud.client.lua, этот сервис его не трогает)
--   ├─ (где угодно внутри) Frame "MoneyPill"    → в нём TextLabel "Value"
--   └─ (где угодно внутри) Frame "RebirthPill"  → в нём TextLabel "Value"
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)

local HudService = {}

local records = {} -- [player] = { Gui, Connections }

-- Находит части внутри готового ScreenGui (см. КОНТРАКТ в шапке).
local function locatePillParts(gui)
	local obsoleteHandOrePill = gui:FindFirstChild("HandOrePill", true)
	if obsoleteHandOrePill then
		obsoleteHandOrePill:Destroy()
	end
	local moneyPill = gui:FindFirstChild("MoneyPill", true)
	local rebirthPill = gui:FindFirstChild("RebirthPill", true)
	local moneyLabel = moneyPill and moneyPill:FindFirstChild("Value", true)
	local rebirthLabel = rebirthPill and rebirthPill:FindFirstChild("Value", true)
	if not (moneyPill and rebirthPill and moneyLabel and rebirthLabel) then
		return nil
	end
	return {
		MoneyPill = moneyPill,
		MoneyLabel = moneyLabel,
		RebirthPill = rebirthPill,
		RebirthLabel = rebirthLabel,
	}
end

--------------------------------------------------------------------------------

function HudService:Init(_services) end

function HudService:SetupPlayer(player)
	local playerGui = player:WaitForChild("PlayerGui", 15)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not playerGui or not leaderstats then
		return
	end
	local money = leaderstats:WaitForChild("Money")
	-- "Prestige" — новое имя того же IntValue (см. DataService:SetupPlayer).
	-- Здесь именно WaitForChild, поэтому старое имя означало бы вечное
	-- ожидание и молча неработающий HUD.
	local rebirths = leaderstats:WaitForChild("Prestige")

	-- Подключает логику к конкретному экземпляру "Hud". Возвращает список
	-- connections или nil, если частей внутри не хватает.
	local function bind(gui)
		local parts = locatePillParts(gui)
		if not parts then
			warn("[HudService] В 'Hud' не хватает MoneyPill/RebirthPill с TextLabel 'Value' внутри — HUD не подключён. Проверь имена частей по контракту.")
			return nil
		end
		gui.ResetOnSpawn = false -- чтобы этот клон не уничтожался на будущих респавнах
		parts.MoneyPill.AutomaticSize = Enum.AutomaticSize.None
		parts.RebirthPill.AutomaticSize = Enum.AutomaticSize.None
		parts.MoneyLabel.TextScaled = false
		parts.MoneyLabel.TextSize = 28
		parts.MoneyLabel.AutomaticSize = Enum.AutomaticSize.None
		parts.MoneyLabel.TextYAlignment = Enum.TextYAlignment.Center
		parts.RebirthLabel.TextScaled = false
		parts.RebirthLabel.TextSize = 28
		parts.RebirthLabel.AutomaticSize = Enum.AutomaticSize.None

		local function refreshMoney()
			parts.MoneyLabel.Text = "$" .. money.Value
		end
		local function refreshRebirths()
			-- "PRESTIGE: " — префикс из референса (картинка баланса/
			-- престижа), раньше показывали голое число.
			parts.RebirthLabel.Text = "PRESTIGE: " .. NumberFormat.abbreviate(rebirths.Value)
		end
		refreshMoney()
		refreshRebirths()

		return {
			money.Changed:Connect(function()
				refreshMoney()
			end),
			rebirths.Changed:Connect(function()
				refreshRebirths()
			end),
		}
	end

	local function disconnectAll(record)
		if record and record.Connections then
			for _, connection in record.Connections do
				connection:Disconnect()
			end
		end
	end

	-- StarterGui клонируется в PlayerGui при загрузке персонажа и
	-- реплицируется на сервер — ждём появления "Hud".
	local gui = playerGui:FindFirstChild("Hud") or playerGui:WaitForChild("Hud", 10)
	if not gui then
		warn("[HudService] StarterGui/Hud не найден в PlayerGui — HUD не будет показан. Проверь, что ScreenGui 'Hud' лежит в StarterGui.")
		return
	end

	records[player] = { Gui = gui, Connections = bind(gui) }

	-- Страховка на случай, если у шаблона в StarterGui ResetOnSpawn остался
	-- true: тогда Roblox при каждом респавне уничтожает старый клон и
	-- создаёт новый (со сброшенным на "Label" текстом). Ловим новый "Hud"
	-- и переподключаемся к нему, чтобы HUD не "замерзал" после смерти.
	playerGui.ChildAdded:Connect(function(child)
		if child.Name ~= "Hud" or not records[player] then
			return
		end
		local record = records[player]
		if record.Gui == child then
			return
		end
		disconnectAll(record)
		records[player] = { Gui = child, Connections = bind(child) }
	end)
end

function HudService:CleanupPlayer(player)
	local record = records[player]
	if not record then
		return
	end
	records[player] = nil
	if record.Connections then
		for _, connection in record.Connections do
			connection:Disconnect()
		end
	end
	-- gui сам уничтожится вместе с PlayerGui игрока при выходе; отдельно
	-- Destroy не зовём — это клон из StarterGui, живущий в его PlayerGui.
end

return HudService
