--------------------------------------------------------------------------------
-- UpgradeService
-- 3 НЕЗАВИСИМЫЕ ветки прокачки (Шахта / Тележка / Кирка) — но покупаются
-- теперь у ОДНОГО NPC-продавца в диалоге (см. CustomCartUI.client.lua),
-- а не через три отдельных физических пьедестала, как раньше. Вся логика
-- проверки/покупки (_tryBuy/_canAffordGap) не изменилась — просто раньше
-- к ней вёл клик по конкретному пьедесталу, а теперь — выбор пункта в
-- диалоге у NPC. Сервер как и раньше НЕ доверяет клиенту ничего, кроме
-- "какую ветку хочу купить" — все проверки (деньги, гэп между ветками,
-- тир-кап, угнана ли тележка) считаются заново на сервере при каждой попытке.
--
-- ЗАВИСИМОСТЬ МЕЖДУ ВЕТКАМИ: нельзя купить тир, если он окажется больше
-- чем на Config.BranchMaxGap (2) тира выше САМОЙ ОТСТАЮЩЕЙ из двух других
-- веток. Можно вырваться вперёд, но ненадолго — остальное придётся подтянуть.
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldUi = require(ReplicatedStorage.Shared.WorldUi) -- v20: стили мировых надписей (StarterGui/WorldUiTemplates)
local BigNum = require(ReplicatedStorage.Shared.BigNum)
Config.NpcBillboard = Config.NpcBillboard or {}
Config.NpcBillboard.UpgradeShopNPC = Config.NpcBillboard.UpgradeShopNPC or { Height = 1.55, SizeWidth = 240, SizeHeight = 90 }
local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)
local Sfx = require(ReplicatedStorage.Shared.Sfx)

local UpgradeService = {}

local Services = nil
local records = {} -- [player] = { Npc = Model }
local shopRemote = nil

local KINDS = { "Mine", "Cart", "Pickaxe" }

function UpgradeService:Init(services)
	Services = services

	-- Единственный канал общения с диалогом продавца: клиент просит открыть
	-- ("Open") или купить ветку ("Buy", kind) — сервер сам решает, что можно,
	-- и отвечает тем же RemoteEvent ("Status"/"BuyResult"). Клиенту нечего
	-- подделывать — все решения принимает сервер заново на каждый запрос.
	--
	-- lastRequest — защита от спама: эксплойт мог бы дёргать "Buy" тысячи
	-- раз в секунду. Само по себе ничего не даёт украсть (_tryBuy всё равно
	-- проверяет деньги/тиры заново каждый раз), но незачем зря пересчитывать
	-- статусы и слать FireClient на каждый вызов.
	local lastRequest = {}
	shopRemote = Instance.new("RemoteEvent")
	shopRemote.Name = "UpgradeShopRequest"
	shopRemote.Parent = ReplicatedStorage.Shared
	shopRemote.OnServerEvent:Connect(function(player, action, kind)
		-- "Close" НАМЕРЕННО обходит антиспам-дебаунс ниже. Он не
		-- экономический (просто включает промпт NPC обратно + двигает
		-- WatchdogToken), дешёвый и идемпотентный — throttle-ить его нечем
		-- оправдать, а вред реальный: раньше он попадал под общий дебаунс
		-- вместе с "Buy", и если "Close" приходил в те же 0.15с, что и
		-- предыдущее "Buy" (а именно так теперь и происходит: см.
		-- playUpgradeRevealCamera в CustomCartUI.client.lua — он закрывает
		-- диалог программно СРАЗУ по получении BuyResult, в том же
		-- сетевом такте), сообщение молча отбрасывалось. Промпт оставался
		-- Enabled=false, и диалог с продавцом переставал открываться
		-- ВООБЩЕ — до срабатывания 45-секундного watchdog'а
		-- (UPGRADE_PROMPT_WATCHDOG_TIMEOUT ниже). Именно это выглядело как
		-- "покупка после катсцены работает только после долгого отката".
		if action == "Close" then
			local record = records[player]
			if record and record.Prompt then
				record.Prompt.Enabled = true
				record.WatchdogToken = (record.WatchdogToken or 0) + 1
			end
			return
		end

		local now = os.clock()
		local last = lastRequest[player.UserId]
		if last and now - last < 0.15 then
			return
		end
		lastRequest[player.UserId] = now

		if action == "Open" then
			self:_sendStatus(player)
		elseif action == "Buy" and table.find(KINDS, kind) then
			local ok, reason = self:_tryBuy(player, kind)
			if not ok then
				local record = records[player]
				Sfx.play("UpgradeFail", record and record.Npc and record.Npc.PrimaryPart)
				if reason == "Not enough money" and Services.NotifyService then
					-- Не хватает игровых денег — предлагаем ПРЯМО НА ЭКРАНЕ
					-- зайти в магазин за Money Pack'ом/ускорителем денег
					-- (x2/x4/x6 Cash), а не просто молча отказать в покупке.
					Services.NotifyService:Show(player, "Not enough money! Buy a Money Pack or a cash-boost pass to speed things up.", {
						ActionLabel = "Open Shop",
						PreferredTab = "Deals",
						Icon = "Shop",
					})
				end
			end
			shopRemote:FireClient(player, "BuyResult", kind, ok, reason)
			self:_sendStatus(player) -- цены/статусы могли поменяться (в том числе у соседних веток)
		end
	end)
end

-- Разрешено ли купить следующий тир ветки kind: не более чем на
-- Config.BranchMaxGap тиров выше самой отстающей из двух ОСТАЛЬНЫХ веток.
function UpgradeService:_canAffordGap(player, kind)
	local tiers = Services.DataService:GetTiers(player)
	local newTier = tiers[kind] + 1
	local minOther = math.huge
	for _, otherKind in KINDS do
		if otherKind ~= kind then
			minOther = math.min(minOther, tiers[otherKind])
		end
	end
	return (newTier - minOther) <= Config.BranchMaxGap
end

-- Снимок состояния ОДНОЙ ветки для диалога — во что превращается в тексте
-- решает уже клиент (см. CustomCartUI.client.lua), сервер только считает факты.
function UpgradeService:_branchStatus(player, kind)
	-- ОТОБРАЖАЕМЫЙ тир, а не внутренний: сломанная шахта показывается как
	-- ТИР 0, хотя внутри она первого тира (см. DataService:GetDisplayTier
	-- и Config.Mine.Broken — почему нельзя завести настоящий тир 0).
	local currentTier = Services.DataService:GetDisplayTier(player, kind)
	local absoluteMax = Services.DataService:GetBranchMaxTier(kind)

	-- v12: ПЕРВАЯ ТЕЛЕЖКА ПОКУПАЕТСЯ ОТДЕЛЬНО И СТОИТ НОЛЬ.
	--
	-- Тир тележки по-прежнему 1 + CartIndex, то есть "тира 0" в цепочке нет
	-- и быть не может — вместо него отдельный флаг владения
	-- (CartService:IsCartUnlocked). Пока он не поднят, ветка показывает не
	-- следующий шаг цепочки, а саму покупку тележки: цена 0, тир остаётся 1,
	-- шаг Config.CartChain НЕ тратится. Клиент рисует такую карточку как
	-- "GET CART · FREE" по флагу Unlock (см. CustomCartUI.client.lua).
	if kind == "Cart" and Services.CartService and not Services.CartService:IsCartUnlocked(player) then
		return {
			Kind = kind,
			State = "Buyable",
			Unlock = true,
			Tier = currentTier,
			NextTier = currentTier,
			Cost = 0,
			CanAfford = true,
			Blocked = false,
		}
	end

	if currentTier >= absoluteMax then
		return { Kind = kind, State = "Maxed", Tier = currentTier }
	end

	local cap = Services.DataService:GetBranchCap(player, kind)
	if currentTier >= cap then
		return { Kind = kind, State = "NeedRebirth", Tier = currentTier, Cap = cap }
	end

	local step = Services.DataService:GetNextBranchStep(player, kind)
	if not step then
		return { Kind = kind, State = "Error", Tier = currentTier }
	end

	-- v4: скип за Robux (Config.DevProducts.UpgradeSkip) — только когда
	-- денег не хватает и продукт для этого тира создан (Id ~= 0).
	local canAfford = BigNum.ge(Services.DataService:GetMoney(player), step.Cost)
	local skip = not canAfford and step.Repair ~= true and Config.DevProducts.UpgradeSkip
		and Config.DevProducts.UpgradeSkip[kind] and Config.DevProducts.UpgradeSkip[kind][step.Tier] or nil
	if skip and (skip.Id or 0) == 0 then skip = nil end

	return {
		Kind = kind,
		State = "Buyable",
		SkipProductId = skip and skip.Id or nil,
		SkipRobux = skip and skip.PriceRobux or nil,
		-- Repair — тот же приём, что и Unlock у первой тележки выше:
		-- карточка рисуется как "ПОЧИНИТЬ ШАХТУ", а не как обычный апгрейд.
		Repair = step.Repair == true,
		Tier = currentTier,
		NextTier = step.Tier,
		Cost = step.Cost,
		CanAfford = canAfford, -- v3: для карточек магазина
		Blocked = not self:_canAffordGap(player, kind), -- "подтяни другие ветки"
	}
end

function UpgradeService:_sendStatus(player)
	local statuses = {}
	for _, kind in KINDS do
		statuses[kind] = self:_branchStatus(player, kind)
	end
	shopRemote:FireClient(player, "Status", statuses)
end

--------------------------------------------------------------------------------

-- Стабилизирует NPC независимо от того, что билдер сделал в своей
-- кастомной модели: анкорит и убирает коллизию у ВСЕХ частей (NPC никогда
-- физически не двигается и не должен толкать игроков — без этого
-- незаанкоренные/сталкивающиеся части эксплодируют физикой при спавне,
-- "прыгают на месте и улетают") и подгоняет модель по вертикали так, чтобы
-- её РЕАЛЬНЫЙ нижний край (по всей модели, GetBoundingBox — а не только
-- PrimaryPart, у гуманоидного рига ноги обычно ниже него) лёг ровно на пол
-- участка. Маркер (PillarMarker/RebirthMarker) даёт только X/Z и поворот —
-- его высота лишь ПРЕДПОЛАГАЕТ пропорции конкретной модели (расстояние от
-- PrimaryPart до "ступней"), а для чужого кастомного рига это предположение
-- почти наверняка не совпадёт: анкоренная модель просто останется там, где
-- предположение её оставило, — отсюда "проваливается под землю".
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

-- Диалог продавца открывается только если в модели есть BillboardGui "gui"
-- с TextLabel "name"/"arrow"/"dialog" внутри (см. CustomCartUI.client.lua:
-- openDialog) — у собственной модели билдера этого может не быть вообще.
-- Если своего "gui" в модели нет (или не хватает нужных лейблов внутри) — строим точно такой
-- же, как у плейсхолдера, сами, на PrimaryPart. Если билдер уже положил
-- рабочий "gui" — используем его как есть, не трогаем. "arrow" —
-- НЕОБЯЗАТЕЛЬНЫЙ лейбл (чисто декоративная подсказка-стрелка "нажми,
-- чтобы поговорить") — можно не класть его в свой билборд вообще, код
-- прекрасно работает и без него (см. также CustomCartUI.client.lua —
-- там все обращения к нему защищены проверкой на nil).
local function ensureShopGui(npc, primaryPart)
	local gui = npc:FindFirstChild("gui", true)
	local name = gui and gui:FindFirstChild("name", true)
	local dialog = gui and gui:FindFirstChild("dialog", true)
	if gui and name and dialog then
		return -- билдер уже положил рабочий gui (arrow может как быть, так и не быть) — не трогаем
	end
	if gui then
		gui:Destroy() -- есть, но не хватает name/dialog — пересоберём с нуля
	end

	gui = Instance.new("BillboardGui")
	gui.Name = "gui"
	gui.Size = UDim2.new(0, Config.NpcBillboard.UpgradeShopNPC.SizeWidth, 0, Config.NpcBillboard.UpgradeShopNPC.SizeHeight)
	gui.StudsOffset = Vector3.new(0, Config.NpcBillboard.UpgradeShopNPC.Height, 0)
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

	local nameLabel = label("name", UDim2.new(1, 0, 0.4, 0), UDim2.new(0, 0, 0, 0), Color3.fromRGB(170, 230, 170))
	nameLabel.Text = "EXPERIENCED MINER"

	local arrowLabel = label("arrow", UDim2.new(1, 0, 0.25, 0), UDim2.new(0, 0, 0.4, 0), Color3.new(1, 1, 1))
	arrowLabel.Text = "" -- v20.9: стрелку-фигуру рисует клиент (NpcNameStyle); символа ▼ в шрифтах нет

	local dialogLabel = label("dialog", UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0), Color3.new(1, 1, 1))
	dialogLabel.Visible = false
end

-- Необязательный "FacingPoint" внутри модели NPC — тот же приём, что и у
-- тележки (см. CartService): маркер (PillarMarker/RebirthMarker) сам по
-- себе задаёт, КУДА в мире должен смотреть NPC (поворот маркера — крути
-- его самого или используй компаньон "...Look", см. PLACEHOLDERS_GUIDE.md),
-- а FacingPoint — это ОТДЕЛЬНАЯ настройка "а что вообще считать 'перёдом'
-- у ЭТОЙ конкретной модели", на случай если твоя модель построена so, что
-- её собственный перёд не совпадает с обычным локальным +Z. Нет
-- FacingPoint — направление берётся как есть, без коррекции.
local function facingCorrection(npc, primaryPart)
	local facingPoint = npc:FindFirstChild("FacingPoint", true)
	if not (facingPoint and facingPoint:IsA("BasePart")) then
		return 0
	end
	local localOffset = primaryPart.CFrame:PointToObjectSpace(facingPoint.Position)
	return -math.atan2(localOffset.X, localOffset.Z)
end

function UpgradeService:SetupPlot(player, plot)
	local npc, isCustom = PlaceholderFactory.UpgradeShopNPC()
	local primaryPart = npc.PrimaryPart
	local correction = facingCorrection(npc, primaryPart)
	npc:PivotTo(plot.PillarCFrame * CFrame.Angles(0, correction, 0)) -- позиция из маркера "PillarMarker" шаблона участка (см. PlotService), поворот — маркер + FacingPoint-коррекция выше
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
	prompt.ActionText = "UPGRADE"
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 10
	prompt.Style = Enum.ProximityPromptStyle.Custom -- свой вид рисует src/client (CustomCartUI.client.lua) — НЕ дефолтный серый Roblox
	prompt:SetAttribute("PromptKind", "Talk")
	prompt:SetAttribute("OwnerUserId", player.UserId)
	prompt.Parent = primaryPart

	records[player] = { Npc = npc, Prompt = prompt, WatchdogToken = 0 }

	-- Watchdog — тот же фикс, что и у мерчанта/ребёрта (см. ShopNpcService.
	-- lua/RebirthService.lua): если клиент по любой причине не пришлёт
	-- "Close" (дисконнект, ошибка UI, смерть посреди диалога), промпт
	-- раньше оставался Enabled=false навсегда. Теперь он сам оживает через
	-- таймаут, а токен отменяет устаревшее срабатывание, если "Close"
	-- пришёл раньше.
	local UPGRADE_PROMPT_WATCHDOG_TIMEOUT = 45

	prompt.Triggered:Connect(function(triggerer)
		if triggerer ~= player then
			return -- прокачивает только владелец участка
		end
		prompt.Enabled = false -- пока идёт диалог, промпт не мигает и не триггерится повторно — см. OnServerEvent("Close") ниже, включает обратно
		shopRemote:FireClient(player, "Open", npc) -- клиент сам найдёт "gui" где-нибудь в модели для диалога
		self:_sendStatus(player)

		local record = records[player]
		record.WatchdogToken += 1
		local myToken = record.WatchdogToken
		task.delay(UPGRADE_PROMPT_WATCHDOG_TIMEOUT, function()
			local currentRecord = records[player]
			if currentRecord and currentRecord.WatchdogToken == myToken and currentRecord.Prompt then
				currentRecord.Prompt.Enabled = true
			end
		end)
	end)

	player.CharacterAdded:Connect(function()
		local record = records[player]
		if record and record.Prompt then
			record.WatchdogToken = (record.WatchdogToken or 0) + 1
			record.Prompt.Enabled = true
		end
	end)
end

-- Снимает откат покупки досрочно. Нужен на путях, где покупка ОТКАТИЛАСЬ
-- (постройка модели не удалась, деньги вернули) — держать игрока в
-- пятисекундном ожидании после несостоявшегося апгрейда бессмысленно.
local function releaseUpgradeCooldown(player)
	if not player.Parent then return end
	player:SetAttribute("UpgradeCooldownToken", (tonumber(player:GetAttribute("UpgradeCooldownToken")) or 0) + 1)
	player:SetAttribute("UpgradeInProgress", false)
	player:SetAttribute("UpgradeCooldownEndsAt", 0)
end

function UpgradeService:_tryBuy(player, kind)
	if player:GetAttribute("EconomyTransactionLocked") == true then return false, "Saving another reward, try again" end
	if player:GetAttribute("UpgradeInProgress") == true then
		-- Сообщаем КОНКРЕТНОЕ оставшееся время, а не глухое "уже идёт":
		-- игрок должен понимать, что это откат на несколько секунд, а не
		-- поломка (см. Config.UpgradeShop.PurchaseCooldownSeconds).
		local remaining = math.max(0, (tonumber(player:GetAttribute("UpgradeCooldownEndsAt")) or 0) - os.time())
		if remaining > 0 then
			return false, ("Upgrade cooldown: %ds"):format(remaining)
		end
		return false, "Upgrade is already in progress"
	end
	-- УДАЛЁН ГЕЙТ ПРЕЖНЕГО ГАЙДА ("продай первую тележку, прежде чем
	-- улучшать шахту"). В обучении v7 шахта чинится ДО того, как у игрока
	-- появляется тележка. Починка — отдельный НУЛЕВОЙ шаг ветки шахты
	-- (DataService:GetNextBranchStep, флаг Repair): MineIndex она не
	-- двигает, MineChain[1] после неё остаётся следующей покупкой.
	-- v12: ПОКУПКА ПЕРВОЙ ТЕЛЕЖКИ — отдельная ветка, ДО всей обычной
	-- проверки цепочки. Она ничего не стоит, не тратит шаг Config.CartChain
	-- и не трогает деньги: поднимает флаг владения и выдаёт УПАКОВКУ, из
	-- которой игрок сам поставит тележку там, где захочет
	-- (CartService:UnlockFirstCart → GrantPackage).
	if kind == "Cart" and Services.CartService and not Services.CartService:IsCartUnlocked(player) then
		if not Services.CartService:UnlockFirstCart(player) then
			return false, "Something went wrong"
		end
		local record = records[player]
		Sfx.play("Upgrade", record and record.Npc and record.Npc.PrimaryPart)
		self:_sendStatus(player)
		return true
	end

	local currentTier = Services.DataService:GetBranchTier(player, kind)
	local absoluteMax = Services.DataService:GetBranchMaxTier(kind)
	local cap = Services.DataService:GetBranchCap(player, kind)

	if currentTier >= absoluteMax then
		return false, "Already at max tier"
	end
	if currentTier >= cap then
		return false, ("Need PRESTIGE (cap tier %d)"):format(cap)
	end

	local step = Services.DataService:GetNextBranchStep(player, kind)
	if not step then
		return false, "Something went wrong" -- страховка на рассинхрон
	end
	-- BigNum.lt принимает BigNum слева и обычное число справа без всякой
	-- обёртки — раньше приходилось городить вычитание с isNegative(),
	-- потому что прямое `money < step.Cost` роняло сервер.
	if BigNum.lt(Services.DataService:GetMoney(player), step.Cost) then
		if Services.MonetizationService then Services.MonetizationService:NotEnoughMoney(player, step.Cost, "Upgrade:" .. tostring(kind)) end
		return false, "Not enough money"
	end
	if not self:_canAffordGap(player, kind) then
		return false, "Catch up other branches first"
	end
	if kind == "Cart" and not Services.CartService:CanUpgradeOwnedCart(player) then
		return false, "Your cart is stolen!"
	end

	-- ОТКАТ ПОКУПКИ (см. Config.UpgradeShop.PurchaseCooldownSeconds — там
	-- подробно, почему прежних 2 секунд НЕ ХВАТАЛО и как это ломало модели).
	--
	-- Два атрибута, а не один:
	--   • UpgradeInProgress — булев замок, его читает проверка в начале
	--     _tryBuy (осталась как была).
	--   • UpgradeCooldownEndsAt — os.time() конца отката, его читает КЛИЕНТ,
	--     чтобы гасить кнопки и рисовать обратный отсчёт, а не давать
	--     игроку жать в пустоту и получать отказ.
	-- Токен нужен, чтобы отложенное снятие замка от ПЕРВОЙ покупки не сняло
	-- замок, поставленный ВТОРОЙ (иначе окно снова открывается раньше срока).
	local cooldown = tonumber(Config.UpgradeShop and Config.UpgradeShop.PurchaseCooldownSeconds) or 5
	local cooldownToken = (tonumber(player:GetAttribute("UpgradeCooldownToken")) or 0) + 1
	player:SetAttribute("UpgradeCooldownToken", cooldownToken)
	player:SetAttribute("UpgradeInProgress", true)
	player:SetAttribute("UpgradeCooldownEndsAt", os.time() + cooldown)
	task.delay(cooldown, function()
		if not player.Parent then return end
		if (tonumber(player:GetAttribute("UpgradeCooldownToken")) or 0) ~= cooldownToken then
			return -- за это время была НОВАЯ покупка, её откат ещё идёт — не снимаем чужой замок
		end
		player:SetAttribute("UpgradeInProgress", false)
		player:SetAttribute("UpgradeCooldownEndsAt", 0)
	end)
	Services.DataService:AddMoney(player, -step.Cost)
	-- ПОЧИНКА НЕ ДВИГАЕТ ВЕТКУ. Раньше IncrementBranch стоял здесь
	-- безусловно, и починка тихо поднимала MineIndex 0 → 1: по данным
	-- шахта становилась тира 2 (при модели тира 1), шаг MineChain[1] за
	-- $220 пропускался даром, а MineIndex > 0 ещё и запускал миграцию
	-- тележки в CartService:SetupPlayer у новичка посреди обучения.
	if not (kind == "Mine" and step.Repair == true) then
		Services.DataService:IncrementBranch(player, kind)
	end

	if kind == "Mine" and step.Repair == true then
		-- ПОЧИНКА. Модель НЕ пересобирается: тир не меняется (шахта и так
		-- внутренне первого тира, см. DataService:GetDisplayTier), меняется
		-- только её вид — текстуры возвращаются, чёрный неон сходит, играет
		-- анимация (PlotService:RestoreMineLook).
		--
		-- Раньше починка была склеена с покупкой MineChain[1], и на одном
		-- кадре происходило сразу три вещи: снос модели, сборка новой
		-- модели тира 2 и наложение на неё чёрного вида, который тут же
		-- снимался. Отсюда и был заметный пролаг в момент починки.
		if not (Services.TutorialService and Services.TutorialService:RepairMine(player)) then
			releaseUpgradeCooldown(player)
			Services.DataService:AddMoney(player, step.Cost)
			return false, "Mine repair failed"
		end
		if Services.NotifyService then
			Services.NotifyService:Show(player, "THE MINE IS OPEN", { Duration = 2.5 })
		end
	elseif kind == "Mine" then
		-- Такой же возврат денег, как у ветки Cart ниже: _buildMine может
		-- отказаться применять тир, если у модели Mine_TierN нет
		-- обязательной детали 'Zone'. Раньше результат игнорировался.
		if not Services.PlotService:SetMineTier(player, step.Tier) then
			-- Покупка откатилась целиком — держать игрока в 5-секундном
			-- откате не за что, снимаем его сразу.
			releaseUpgradeCooldown(player)
			Services.DataService:AddMoney(player, step.Cost)
			warn(("[UpgradeService] Апгрейд шахты для %s не удался - деньги (%d) возвращены."):format(player.Name, step.Cost))
			Services.NotifyService:Show(player, "Mine upgrade failed. Your money was refunded.", { Icon = "Refund" })
			return false, "Mine upgrade failed"
		end
		-- Тир базовых валунов привязан к шахте — после апгрейда они
		-- обязаны пересобраться (см. RockService:RefreshPlotBoulders).
		if Services.RockService and Services.RockService.RefreshPlotBoulders then
			pcall(function() Services.RockService:RefreshPlotBoulders(player) end)
		end
	elseif kind == "Cart" then
		-- Возврат денег, если тележку физически не удалось пересобрать.
		-- Порядок вызовов здесь такой, что деньги и тир УЖЕ списаны/выданы
		-- выше, а UpgradeOwnedCart уничтожает старую тележку ДО постройки
		-- новой — если постройка провалится (например, у пользовательской
		-- модели Cart_TierN нет детали 'Root'), игрок останется без тележки
		-- и без денег. Раньше результат вызова просто игнорировался.
		if not Services.CartService:UpgradeOwnedCart(player) then
			releaseUpgradeCooldown(player) -- см. комментарий в ветке Mine выше
			Services.DataService:AddMoney(player, step.Cost)
			warn(("[UpgradeService] Апгрейд тележки для %s не удался - деньги (%d) возвращены."):format(player.Name, step.Cost))
			Services.NotifyService:Show(player, "Cart upgrade failed. Your money was refunded.", { Icon = "Refund" })
			return false, "Cart upgrade failed"
		end
	elseif kind == "Pickaxe" then
		Services.CombatService:RefreshPickaxe(player)
		Services.CombatService:RefreshPlayerHealth(player)
		-- Потолок тира базовых валунов считается от кирки — см.
		-- plotBoulderTier: без пересборки прокачка кирки не разблокировала
		-- бы камни, которые она уже способна взять.
		if Services.RockService and Services.RockService.RefreshPlotBoulders then
			pcall(function() Services.RockService:RefreshPlotBoulders(player) end)
		end
	end

	local record = records[player]
	Sfx.play("Upgrade", record and record.Npc and record.Npc.PrimaryPart)
	Services.CartService:RefreshSpeed(player)
	local isRepair = kind == "Mine" and step.Repair == true
	-- Шаг обучения «первый апгрейд» (Config.Tutorial.Steps, FirstUpgrade).
	-- Починка апгрейдом не считается: это бесплатная часть пролога.
	if not isRepair and Services.TutorialService then
		pcall(function() Services.TutorialService:Count(player, "UpgradesBought", 1) end)
	end
	if Services.QuestService and not isRepair then
		Services.QuestService:RecordMetric(player, "Upgrades", 1)
		local tiers = Services.DataService:GetTiers(player)
		if tiers.Mine > 1 and tiers.Cart > 1 and tiers.Pickaxe > 1 then
			Services.QuestService:RecordMetric(player, "BalancedUpgrades", 1, true)
		end
	end

	if step.Tier >= absoluteMax and Services.DataService:MarkHintSeen(player, "NearRebirth") then
		Services.NotifyService:Show(player, "This branch is maxed! Max all 3 to unlock Prestige for a permanent ore price boost.", { Icon = "Rebirth" })
	end

	return true
end

-- v4: после покупки скипа (MonetizationService) деньги уже доведены до цены
-- шага — проводим обычную покупку. Если идёт откат прошлой покупки, ждём его.
function UpgradeService:BuyAfterSkip(player, kind)
	for _ = 1, 40 do
		if not player.Parent then return end
		if player:GetAttribute("UpgradeInProgress") ~= true then break end
		task.wait(0.25)
	end
	local ok, reason = self:_tryBuy(player, kind)
	if shopRemote then
		shopRemote:FireClient(player, "BuyResult", kind, ok, reason)
	end
	self:_sendStatus(player)
end

-- Вызывается RebirthService после успешного ребёрта — толкнуть игроку
-- свежий статус диалога (если он у продавца стоит открытым прямо сейчас,
-- клиент сам решит, обновлять ли видимый текст — см. CustomCartUI).
function UpgradeService:RefreshAllLabels(player)
	self:_sendStatus(player)
end

function UpgradeService:CleanupPlayer(player)
	records[player] = nil -- инстансы уничтожает PlotService вместе с участком
end

return UpgradeService
