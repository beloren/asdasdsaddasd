--------------------------------------------------------------------------------
-- ShopNpcService
-- НПС МАГАЗИНА (Robux) — СТОИТ НА КАЖДОМ УЧАСТКЕ, отдельно от продавца
-- прокачки (UpgradeService, тот берёт игровые деньги за тиры). Этот NPC
-- ничего не проверяет и не продаёт сам — заговорить с ним просто открывает
-- клиентское окно "ShopUi" (см. CustomCartUI.client.lua), а сами покупки
-- геймпассов/девпродуктов идут через стандартные системные окна Roblox
-- (MarketplaceService:PromptGamePassPurchase/PromptProductPurchase),
-- вызываемые ПРЯМО С КЛИЕНТА — серверу тут проверять нечего, Roblox сам
-- обрабатывает оплату и дёргает ProcessReceipt в MonetizationService.
--
-- Тот же билборд-контракт "gui" (name/arrow/dialog), что и у
-- UpgradeShopNPC — см. подробный комментарий в UpgradeService.lua/
-- CustomCartUI.client.lua про то, что именно ожидается внутри модели.
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldUi = require(ReplicatedStorage.Shared.WorldUi) -- v20: стили мировых надписей (StarterGui/WorldUiTemplates)
Config.NpcBillboard = Config.NpcBillboard or {}
Config.NpcBillboard.ShopNPC = Config.NpcBillboard.ShopNPC or { Height = 1.55, SizeWidth = 240, SizeHeight = 90 }
local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)

local ShopNpcService = {}

local Services = nil
local records = {} -- [player] = { Npc = Model }
local shopNpcRemote = nil

function ShopNpcService:Init(services)
	Services = services

	-- Канал общения: сервер просит клиента открыть диалог/шоп ("Open", npc);
	-- клиент в ответ сообщает, когда диалог закрылся ("Close" — ушёл из
	-- радиуса/нажал Escape/закрыл окно магазина), чтобы сервер снова включил
	-- промпт (см. Triggered в SetupPlot — выключает его на время разговора).
	-- Сами покупки клиент инициирует напрямую через MarketplaceService, сюда
	-- это не идёт.
	--
	-- lastRequest — защита от спама (см. тот же приём в UpgradeService.lua).
	local lastRequest = {}
	shopNpcRemote = Instance.new("RemoteEvent")
	shopNpcRemote.Name = "ShopNpcRequest"
	shopNpcRemote.Parent = ReplicatedStorage.Shared
	shopNpcRemote.OnServerEvent:Connect(function(player, action)
		local now = os.clock()
		local last = lastRequest[player.UserId]
		if last and now - last < 0.15 then
			return
		end
		lastRequest[player.UserId] = now

		if action == "Close" then
			local record = records[player]
			if record and record.Prompt then
				record.Prompt.Enabled = true
				record.WatchdogToken = (record.WatchdogToken or 0) + 1 -- отменяет отложенный watchdog ниже, диалог закрылся штатно
			end
		end
	end)
end

-- ФИКС "ЛОМАЮТСЯ ПРОМПТЫ У КРОТА-МЕРЧАНТА": раньше промпт выключался в
-- Triggered и включался обратно ТОЛЬКО по явному "Close" от клиента. Если
-- клиент не прислал "Close" (вылетел/потерял соединение, ошибка в
-- LocalScript-е диалога, игрок умер/телепортировался посреди разговора,
-- запрос потерялся) — промпт оставался Enabled=false НАВСЕГДА, и NPC
-- переставал реагировать. Правильная защита — не полагаться на ЕДИНСТВЕННОЕ
-- сообщение от клиента: заводим watchdog-таймер при каждом открытии,
-- который сам включит промпт обратно через WatchdogTimeout секунд, даже
-- если "Close" так и не пришёл. Токен внутри `record` отменяет устаревшие
-- срабатывания watchdog'а, если "Close" всё же пришёл раньше (см. выше).
local SHOP_PROMPT_WATCHDOG_TIMEOUT = 45 -- сек — с запасом больше любого реального диалога/шопа

-- Дословно те же хелперы, что и в UpgradeService/RebirthService (см.
-- подробные комментарии там) — каждый NPC-сервис самодостаточен, не тянет
-- общий модуль ради пары функций.
local function stabilizeNpc(npc, groundY, isCustom)
	-- Анкор + отключение коллизий — ТОЛЬКО для код-генерируемого
	-- плейсхолдера (без него блочный человечек падает/расползается от
	-- физики). Для своего ассета — по прямому запросу — не трогаем: у
	-- модели может быть свой скрипт с движением/анимацией, которому
	-- нужна работающая физика/коллизия, и глушить её молча нельзя.
	if not isCustom then
		for _, descendant in npc:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
			end
		end
	end
	-- Коррекция по высоте (чтобы модель не проваливалась/не парила над
	-- маркером) — часть самого позиционирования на маркере, а не лишняя
	-- "обработка", поэтому применяется всегда, в том числе к своему ассету.
	local cf, size = npc:GetBoundingBox()
	local bottomY = cf.Position.Y - size.Y / 2
	local correction = groundY - bottomY
	if math.abs(correction) > 1e-3 then
		npc:PivotTo(npc:GetPivot() + Vector3.new(0, correction, 0))
	end
end

local function facingCorrection(npc, primaryPart)
	local facingPoint = npc:FindFirstChild("FacingPoint", true)
	if not (facingPoint and facingPoint:IsA("BasePart")) then
		return 0
	end
	local localOffset = primaryPart.CFrame:PointToObjectSpace(facingPoint.Position)
	return -math.atan2(localOffset.X, localOffset.Z)
end

-- Если билдер (Studio-ассет "ShopNPC") уже положил рабочий "gui" с
-- name/dialog — используем как есть, иначе строим сами (тот же
-- приём, что ensureShopGui в UpgradeService.lua). "arrow" — необязательный
-- декоративный лейбл (см. подробный комментарий в UpgradeService.lua).
local function ensureShopGui(npc, primaryPart)
	local gui = npc:FindFirstChild("gui", true)
	local name = gui and gui:FindFirstChild("name", true)
	local dialog = gui and gui:FindFirstChild("dialog", true)
	if gui and name and dialog then
		return
	end
	if gui then
		gui:Destroy()
	end

	gui = Instance.new("BillboardGui")
	gui.Name = "gui"
	gui.Size = UDim2.new(0, Config.NpcBillboard.ShopNPC.SizeWidth, 0, Config.NpcBillboard.ShopNPC.SizeHeight)
	gui.StudsOffset = Vector3.new(0, Config.NpcBillboard.ShopNPC.Height, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 60
	gui.Parent = primaryPart

	local function label(labelName, size, position, color)
		local text = WorldUi.Text(nil, "Text", "Heading")
		text.Name = labelName
		text.BackgroundTransparency = 1
		text.Size = size
		text.Position = position
		text.TextSize = 30
		text.TextColor3 = color
		text.TextWrapped = true
		text.Text = ""
		text.Parent = gui


		return text
	end

	local nameLabel = label("name", UDim2.new(1, 0, 0.4, 0), UDim2.new(0, 0, 0, 0), Color3.fromRGB(255, 215, 120))
	nameLabel.Text = "Item Shop"

	local arrowLabel = label("arrow", UDim2.new(1, 0, 0.25, 0), UDim2.new(0, 0, 0.4, 0), Color3.new(1, 1, 1))
	arrowLabel.Text = "▼"

	local dialogLabel = label("dialog", UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0), Color3.new(1, 1, 1))
	dialogLabel.Visible = false
end

function ShopNpcService:SetupPlot(player, plot)
	if not plot.ShopCFrame then
		return -- старый/чужой PlotTemplate без ShopMarker — просто нет NPC магазина на этом участке
	end

	local npc, isCustom = PlaceholderFactory.ShopNPC()
	local primaryPart = npc.PrimaryPart
	local correction = facingCorrection(npc, primaryPart)
	npc:PivotTo(plot.ShopCFrame * CFrame.Angles(0, correction, 0)) -- позиция из маркера "ShopMarker" шаблона участка
	npc.Parent = plot.Content

	stabilizeNpc(npc, plot.Pad.Position.Y + plot.Pad.Size.Y / 2, isCustom)

	-- ПО ПРЯМОМУ ЗАПРОСУ: свой ассет — только позиционирование на маркере
	-- (выше) и промпт взаимодействия (ниже). Сдвиг шляп и билборд с
	-- именем/репликами — "уберите билборды над ними, я сделаю
	-- самостоятельно".
	if not isCustom then
		PlaceholderFactory.ShiftNpcHats(npc, -2.20)
		ensureShopGui(npc, primaryPart)
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = ""
	prompt.ActionText = "SHOP"
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 10
	prompt.Style = Enum.ProximityPromptStyle.Custom -- свой вид рисует src/client (CustomCartUI.client.lua) — НЕ дефолтный серый Roblox
	prompt:SetAttribute("PromptKind", "Talk")
	prompt:SetAttribute("OwnerUserId", player.UserId)
	prompt.Parent = primaryPart

	records[player] = { Npc = npc, Prompt = prompt, WatchdogToken = 0 }

	prompt.Triggered:Connect(function(triggerer)
		if triggerer ~= player then
			return -- открывает магазин только владелец участка
		end
		if player:GetAttribute("UpgradeInProgress") == true then return end
		prompt.Enabled = false -- пока идёт диалог, промпт не мигает и не триггерится повторно — см. OnServerEvent("Close") ниже, включает обратно
		shopNpcRemote:FireClient(player, "Open", npc) -- клиент сам найдёт "gui" в модели и покажет диалог + окно ShopUi

		-- Watchdog — см. комментарий у SHOP_PROMPT_WATCHDOG_TIMEOUT выше:
		-- если клиент по любой причине не пришлёт "Close", промпт всё
		-- равно сам оживёт через таймаут вместо того, чтобы сломаться
		-- навсегда.
		local record = records[player]
		record.WatchdogToken += 1
		local myToken = record.WatchdogToken
		task.delay(SHOP_PROMPT_WATCHDOG_TIMEOUT, function()
			local currentRecord = records[player]
			if currentRecord and currentRecord.WatchdogToken == myToken and currentRecord.Prompt then
				currentRecord.Prompt.Enabled = true
			end
		end)
	end)

	-- Респавн (смерть посреди диалога, телепорт и т.п.) — на всякий случай
	-- тоже возвращает промпт в рабочее состояние, а не оставляет его
	-- застрявшим в Enabled=false с прошлой жизни персонажа.
	player.CharacterAdded:Connect(function()
		local record = records[player]
		if record and record.Prompt then
			record.WatchdogToken = (record.WatchdogToken or 0) + 1
			record.Prompt.Enabled = true
		end
	end)
end

function ShopNpcService:CleanupPlayer(player)
	records[player] = nil -- инстансы уничтожает PlotService вместе с участком
end

return ShopNpcService
