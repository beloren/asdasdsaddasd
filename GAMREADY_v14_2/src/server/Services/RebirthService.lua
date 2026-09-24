--------------------------------------------------------------------------------
-- RebirthService
-- НПС ребёрта СТОИТ НА КАЖДОМ УЧАСТКЕ (не один общий у банка) — как и
-- пьедесталы прокачки. Доступен, когда ВСЕ 3 ветки прокачки ЭТОГО игрока
-- достигли ТЕКУЩЕГО ТИР-КАПА (не физического максимума 8 — см.
-- Config.Rebirth.BaseTierCap/TierCapPerRebirth/MaxTierCap в DataService)
-- И у игрока хватает денег на сам ребёрт (Config.Rebirth.CostBase/CostGrowth).
-- Сбрасывает все три ветки, поднимает тир-кап на следующий ребёрт и даёт
-- постоянный множитель цены кристаллов.
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldUi = require(ReplicatedStorage.Shared.WorldUi) -- v20: стили мировых надписей (StarterGui/WorldUiTemplates)
local BigNum = require(ReplicatedStorage.Shared.BigNum)
Config.NpcBillboard = Config.NpcBillboard or {}
Config.NpcBillboard.RebirthNPC = Config.NpcBillboard.RebirthNPC or { Height = 3, SizeWidth = 4.2, SizeHeight = 1.0 }
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)
local Sfx = require(ReplicatedStorage.Shared.Sfx)

local RebirthService = {}

local Services = nil
local records = {} -- [player] = { Npc = Model, Prompt = ProximityPrompt, WatchdogToken = number }
local rebirthNpcRemote = nil
local lastRequest = {}

-- Сколько секунд диалог держит промпт выключенным максимум, если клиент по
-- любой причине не пришлёт "Close"/"Confirm" (см. тот же приём и подробный
-- комментарий в ShopNpcService.lua — там же разбор, почему нельзя полагаться
-- на единственное сообщение от клиента).
local REBIRTH_PROMPT_WATCHDOG_TIMEOUT = 45

function RebirthService:Init(services)
	Services = services
end

function RebirthService:Start()
	-- Канал общения диалога ребёрта — тот же контракт, что и у обычного
	-- ShopNpcRequest (см. ShopNpcService.lua): "Confirm" запускает реальный
	-- ребёрт, "Close"/"Cancel" просто закрывает диалог и включает промпт
	-- обратно. Один RemoteEvent на всю игру, отдельный от других NPC.
	rebirthNpcRemote = Instance.new("RemoteEvent")
	rebirthNpcRemote.Name = "RebirthNpcRequest"
	rebirthNpcRemote.Parent = ReplicatedStorage.Shared
	rebirthNpcRemote.OnServerEvent:Connect(function(player, action)
		local now = os.clock()
		local last = lastRequest[player.UserId]
		if last and now - last < 0.15 then
			return
		end
		lastRequest[player.UserId] = now

		local record = records[player]
		if action == "Close" or action == "Cancel" then
			if record and record.Prompt then
				record.DialogOpen = false
				record.Prompt.Enabled = true
				record.WatchdogToken = (record.WatchdogToken or 0) + 1
			end
		elseif action == "Confirm" then
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			local npcRoot = record and record.Npc and record.Npc.PrimaryPart
			local closeEnough = hrp and npcRoot and (hrp.Position - npcRoot.Position).Magnitude <= (record.Prompt.MaxActivationDistance + 2)
			if record and record.DialogOpen == true and record.Prompt and record.Prompt.Enabled == false and closeEnough then
				record.DialogOpen = false
				self:_tryRebirth(player)
				record.Prompt.Enabled = true
				record.WatchdogToken = (record.WatchdogToken or 0) + 1
			end
		end
	end)
	self:_startSkipAttributeLoop()
end

function RebirthService:_isMaxed(player)
	-- v8: лимитов нет — престиж открыт с пещеры Config.Prestige.MinCave.
	local tiers = Services.DataService:GetTiers(player)
	return (tiers.Mine or 1) >= (Config.Prestige and Config.Prestige.MinCave or 8)
end

-- Для чемоданчика перков (PrestigeService ставит его рядом с NPC).
function RebirthService:GetNpc(player)
	local record = records[player]
	return record and record.Npc or nil
end

-- Собирает всё, что нужно клиенту, чтобы нарисовать диалог ребёрта — та же
-- идея, что и Status у UpgradeService (см. CustomCartUI.client.lua), просто
-- своя, более простая форма для одного-единственного действия "ребёрт".
-- Текст диалога считается ЗДЕСЬ (не на клиенте) — клиент просто выводит его
-- с эффектом печатной машинки, ничего сам не форматирует. Цена — КОРОТКОЙ
-- аббревиатурой ("$15M", "$15T", см. NumberFormat.abbreviate): полное число
-- с точками-разделителями к этому моменту прогрессии превращалось в простыню
-- нулей на пол-экрана, которую невозможно прочитать. Цена обёрнута в RichText
-- <font color=...> — жёлтый, если хватает денег, оранжевый, если не хватает
-- (см. запрос "должно выделяться желтым или оранжевым цветом").
function RebirthService:_buildStatus(player)
	local maxed = self:_isMaxed(player)
	local cap = Services.DataService:GetTierCap(player)
	local cost = Services.DataService:GetRebirthCost(player)
	local money = Services.DataService:GetMoney(player)
	-- BigNum.ge, а не `money >= cost`: оба операнда здесь BigNum и оператор
	-- сработал бы, но стоит одному из них когда-нибудь стать обычным
	-- числом — Luau упадёт с "attempt to compare". Явная функция от типов
	-- не зависит вообще (см. шапку Shared/BigNum.lua).
	local canAfford = BigNum.ge(money, cost)
	local costColorHex = canAfford and "FFD75A" or "FF9E3C" -- жёлтый / оранжевый

	-- Требование слайма — та же формула, что в _tryRebirth (см. ниже по
	-- файлу), но посчитанная ЗАРАНЕЕ, для окна-превью (см.
	-- CustomCartUI.client.lua — новое окно диалога ребёрта, чек-лист
	-- условий). Раньше это проверялось только РЕАКТИВНО, при попытке
	-- нажать саму кнопку — игрок узнавал про требование слайма только
	-- после отказа, не видя его заранее в списке условий.

	-- v8: «кап» в текстах = пещера, с которой открыт престиж.
	cap = Config.Prestige and Config.Prestige.MinCave or cap
	local caveNow = Services.DataService:GetTiers(player).Mine
	local pointsGain = Services.PrestigeService and Services.PrestigeService.PointsForCave(caveNow) or 0
	local intro = "I'm the Prestige Mayor."
	local body
	if not maxed then
		body = Config.Rebirth.RequireOnlyCappedBranches
			and ("Reach Cave %d before I can prestige you."):format(cap)
			or ("You need to upgrade ALL 3 branches to tier %d before I can prestige you."):format(cap)
	else
		body = ("Prestiging resets your Cave, Cart, Pickaxe and money, and gives you <font color=\"#FFD75A\">%d prestige point%s</font> to spend on permanent perks in the case next to me. Deeper caves give more points."):format(pointsGain, pointsGain == 1 and "" or "s")
			.. (" It costs <font color=\"#%s\">$%s</font>."):format(costColorHex, NumberFormat.abbreviate(cost))
		if not canAfford then
			body ..= (" You still need <font color=\"#%s\">$%s</font> more."):format(costColorHex, NumberFormat.abbreviate(cost - money))
		end
	end

	local currentRebirths = Services.DataService:GetRebirths(player)
	local currentMultiplier = 1 + currentRebirths * Config.Rebirth.MultiplierPerRebirth
	local currentSpeedBonus = currentRebirths * Config.Rebirth.SpeedBonusPerRebirth
	local nextMultiplier = 1 + (currentRebirths + 1) * Config.Rebirth.MultiplierPerRebirth
	local nextSpeedBonus = (currentRebirths + 1) * Config.Rebirth.SpeedBonusPerRebirth
	-- Не сравниваем BigNum с обычным number: Luau не вызывает __lt для
	-- смешанной пары table/number. canAfford уже корректно сравнил два BigNum.
	local missingMoney = canAfford and 0 or (cost - money)

	-- ОСТРОВА (см. Config.Islands.RebirthRequires) — ребёрт закрыт, пока
	-- не куплены все нужные острова у Island Keeper.
	local islandsMet = true
	local islandsLabel = nil
	if Services.IslandService then
		islandsMet = Services.IslandService:HasRebirthIslands(player)
		islandsLabel = Services.IslandService:RebirthRequirementLabel()
	end

	-- Чек-лист собирается без дыр (nil посреди массива ломает передачу через Remote).
	local requirements = {}
	table.insert(requirements, { Label = Config.Rebirth.RequireOnlyCappedBranches and ("Reach Cave %d"):format(cap) or ("Upgrade all branches to tier %d"):format(cap), Met = maxed })
	table.insert(requirements, { Label = ("Save up $%s"):format(NumberFormat.abbreviate(cost)), Met = canAfford })
	if islandsLabel then
		table.insert(requirements, { Label = islandsLabel, Met = islandsMet })
	end

	return {
		Maxed = maxed,
		Cap = cap,
		Cost = cost,
		CostText = NumberFormat.abbreviate(cost),
		MissingMoneyText = NumberFormat.abbreviate(missingMoney),
		CanAfford = canAfford,
		Intro = intro,
		Body = body,
		-- ЧЕК-ЛИСТ УСЛОВИЙ — для нового окна диалога ребёрта (см.
		-- CustomCartUI.client.lua). Met=true — условие выполнено (зелёная
		-- галочка), false — не выполнено. AllMet — можно ли вообще нажимать
		-- кнопку REBIRTH прямо сейчас.
		Requirements = requirements,
		AllMet = maxed and canAfford and islandsMet,
		-- Превью бонусов ПОСЛЕ этого ребёрта (см. Config.Rebirth) — для
		-- второй, крупной строки в диалоге (см. CustomCartUI.client.lua).
		-- v8: вместо множителей — очки перков.
		CurrentMoneyText = ("%d POINTS"):format(math.max(0, math.floor(tonumber(player:GetAttribute("PrestigePoints")) or 0))),
		CurrentSpeedText = ("CAVE %d"):format(caveNow),
		BonusMoneyText = ("+%d POINTS"):format(pointsGain),
		BonusSpeedText = "PERKS NEVER RESET",
	}
end

function RebirthService:_flash(player, _text)
	local record = records[player]
	if not record then
		return
	end
	Sfx.play("UpgradeFail", record.Npc.PrimaryPart)
end

--------------------------------------------------------------------------------

-- Стабилизирует NPC независимо от того, что билдер сделал в своей
-- кастомной модели: анкорит и убирает коллизию у ВСЕХ частей (NPC никогда
-- физически не двигается и не должен толкать игроков — без этого
-- незаанкоренные/сталкивающиеся части эксплодируют физикой при спавне,
-- "прыгают на месте и улетают") и подгоняет модель по вертикали так, чтобы
-- её РЕАЛЬНЫЙ нижний край (по всей модели, GetBoundingBox — а не только
-- PrimaryPart, у гуманоидного рига ноги обычно ниже него) лёг ровно на пол
-- участка. Маркер (RebirthMarker) даёт только X/Z и поворот — его высота
-- лишь ПРЕДПОЛАГАЕТ пропорции конкретной модели, а для чужого кастомного
-- рига это предположение почти наверняка не совпадёт: анкоренная модель
-- просто останется там, где предположение её оставило — отсюда
-- "проваливается под землю".
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

-- Необязательный "FacingPoint" внутри модели NPC — см. подробный
-- комментарий в UpgradeService.lua (та же логика, тот же приём, что и у
-- тележки/FacingPoint в CartService).
local function facingCorrection(npc, primaryPart)
	local facingPoint = npc:FindFirstChild("FacingPoint", true)
	if not (facingPoint and facingPoint:IsA("BasePart")) then
		return 0
	end
	local localOffset = primaryPart.CFrame:PointToObjectSpace(facingPoint.Position)
	return -math.atan2(localOffset.X, localOffset.Z)
end

-- ТОТ ЖЕ КОНТРАКТ "gui" (name/arrow/dialog), что и у остальных NPC —
-- см. подробный комментарий в UpgradeService.lua/ShopNpcService.lua. Раньше
-- у Rebirth NPC был только плоский "InfoGui" с одной строкой текста и
-- мгновенный hold-to-trigger промпт — по просьбе "сделать точно так же как
-- и с обычным" здесь теперь тот же полноценный диалог (имя → объяснение →
-- Confirm/Cancel), что и у продавца прокачки/магазина.
local function ensureRebirthDialogGui(npc, primaryPart)
	local gui = npc:FindFirstChild("gui", true)
	if gui then
		gui:Destroy()
	end

	gui = Instance.new("BillboardGui")
	gui.Name = "gui"
	gui.Size = UDim2.fromScale(
		Config.NpcBillboard.RebirthNPC.SizeWidth * 3.6,
		Config.NpcBillboard.RebirthNPC.SizeHeight * 3.6
	)
	gui.SizeOffset = Vector2.new(0, 0.5)
	local boundsCFrame, boundsSize = npc:GetBoundingBox()
	local topPosition = boundsCFrame:PointToWorldSpace(Vector3.new(0, boundsSize.Y * 0.5 + 0.35, 0))
	local baseOffset = topPosition - primaryPart.Position
	gui.StudsOffsetWorldSpace = baseOffset
	gui:SetAttribute("BaseStudsOffset", baseOffset)
	gui.Adornee = primaryPart
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 60
	gui.Parent = primaryPart

	local function label(labelName, size, position, color)
		local text = WorldUi.Text(nil, "Text", "Number")
		text.Name = labelName
		text.BackgroundTransparency = 1
		text.Size = size
		text.Position = position
		text.TextSize = 30
		text.TextScaled = true
		text.TextColor3 = color
		text.TextWrapped = true
		text.RichText = true -- нужно для выделения цены жёлтым/оранжевым прямо в тексте диалога (см. клиент)
		text.Text = ""
		text.Parent = gui


		return text
	end

	local nameLabel = label("name", UDim2.new(1, 0, 0.28, 0), UDim2.new(0, 0, 0, 0), Color3.fromRGB(255, 215, 120))
	nameLabel.Text = "PRESTIGE MAYOR"

	local arrowLabel = label("arrow", UDim2.new(1, 0, 0.18, 0), UDim2.new(0, 0, 0.28, 0), Color3.new(1, 1, 1))
	arrowLabel.Text = "" -- v20.9: стрелку-фигуру рисует клиент (NpcNameStyle); символа ▼ в шрифтах нет

	local dialogLabel = label("dialog", UDim2.new(1, 0, 0.7, 0), UDim2.new(0, 0, 0, 0), Color3.new(1, 1, 1))
	dialogLabel.Visible = false

	-- Вторая строка, крупнее основной реплики — что даёт СЛЕДУЮЩИЙ ребёрт
	-- (см. RebirthService:_buildStatus -> BonusMoneyText/BonusSpeedText).
	local bonusLabel = label("bonus", UDim2.new(1, 0, 0.3, 0), UDim2.new(0, 0, 0.7, 0), Color3.fromRGB(120, 255, 140))
	bonusLabel.Visible = false
end

function RebirthService:SetupPlot(player, plot)
	local npc, isCustom = PlaceholderFactory.RebirthNPC()
	local primaryPart = npc.PrimaryPart
	local correction = facingCorrection(npc, primaryPart)
	npc:PivotTo(plot.RebirthCFrame * CFrame.Angles(0, correction, 0)) -- позиция из маркера "RebirthMarker" шаблона участка (см. PlotService), поворот — маркер + FacingPoint-коррекция выше
	npc.Parent = plot.Content

	stabilizeNpc(npc, plot.Pad.Position.Y + plot.Pad.Size.Y / 2, isCustom)

	-- ПО ПРЯМОМУ ЗАПРОСУ: свой ассет из ReplicatedStorage — только
	-- позиционирование на маркере (выше) и промпт взаимодействия (ниже).
	-- Сдвиг шляп, билборд с именем/репликами и чистка старого InfoGui —
	-- всё это было "дополнительной обработкой" модели, которую просили
	-- убрать: "уберите билборды над ними, я сделаю самостоятельно".
	if not isCustom then
		PlaceholderFactory.ShiftNpcHats(npc, -2.20)
		ensureRebirthDialogGui(npc, primaryPart)

		-- Старый постоянный статус "Upgrade ALL 3 branches..." больше не нужен:
		-- условия и цена показываются только внутри диалога после взаимодействия.
		-- Удаляем InfoGui и из кастомного ассета, если он там остался со старых версий.
		local infoGui = npc:FindFirstChild("InfoGui", true)
		if infoGui then
			infoGui:Destroy()
		end
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = ""
	prompt.ActionText = "REBIRTH"
	prompt.HoldDuration = 0 -- решение больше не принимается ЗДЕСЬ — открывает диалог с явным Confirm/Cancel, случайно ничего не срабатывает
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 10
	prompt.Style = Enum.ProximityPromptStyle.Custom -- свой вид рисует src/client (тот же "Talk"-стиль, что у остальных NPC — см. CustomCartUI.client.lua)
	prompt:SetAttribute("PromptKind", "Talk")
	prompt:SetAttribute("OwnerUserId", player.UserId)
	prompt.Parent = primaryPart

	records[player] = { Npc = npc, Prompt = prompt, WatchdogToken = 0 }
	player:SetAttribute("NeedsRebirthSkip", false)

	-- ТОТ ЖЕ ФОРМАТ ДИАЛОГА, ЧТО И У ОБЫЧНЫХ NPC (см. ShopNpcService.lua/
	-- UpgradeService.lua): промпт открывает диалоговое окно на клиенте
	-- вместо того, чтобы решать всё сам по одному Triggered — сначала кто
	-- это ("Rebirth Mole"), потом объяснение условия (все ветки на макс.
	-- тир) и цена (выделена жёлтым/оранжевым — см. клиент), и только потом
	-- отдельная кнопка Confirm/Cancel. Промпт выключается на время диалога
	-- и включается обратно по "Close"/"Cancel"/"Confirm" (см. Start выше)
	-- ИЛИ по watchdog-таймеру, если клиент так и не ответил.
	prompt.Triggered:Connect(function(triggerer)
		if triggerer ~= player then
			return -- диалог ребёрта — только у своего НПС, на своей базе
		end
		if player:GetAttribute("UpgradeInProgress") == true then return end
		prompt.Enabled = false
		local record = records[player]
		record.WatchdogToken += 1
		record.DialogOpen = true
		local myToken = record.WatchdogToken
		rebirthNpcRemote:FireClient(player, "Open", npc, self:_buildStatus(player))
		task.delay(REBIRTH_PROMPT_WATCHDOG_TIMEOUT, function()
			local currentRecord = records[player]
			if currentRecord and currentRecord.WatchdogToken == myToken and currentRecord.Prompt then
				currentRecord.DialogOpen = false
				currentRecord.Prompt.Enabled = true
			end
		end)
	end)

	player.CharacterAdded:Connect(function()
		local record = records[player]
		if record and record.Prompt then
			record.DialogOpen = false
			record.WatchdogToken = (record.WatchdogToken or 0) + 1
			record.Prompt.Enabled = true
		end
	end)
end

function RebirthService:_tryRebirth(player)
	if player:GetAttribute("EconomyTransactionLocked") == true then return end
	if Services.IslandService and not Services.IslandService:HasRebirthIslands(player) then
		local text = "Unlock all islands at the Island Keeper first!"
		self:_flash(player, text)
		if rebirthNpcRemote then
			rebirthNpcRemote:FireClient(player, "Result", false, text)
		end
		return
	end
	if not self:_isMaxed(player) then
		local cap = Services.DataService:GetTierCap(player)
		self:_flash(player, Config.Rebirth.RequireOnlyCappedBranches and ("Reach Cave %d first!"):format(cap) or ("Upgrade ALL 3 branches to tier %d first!"):format(cap))
		if rebirthNpcRemote then
			rebirthNpcRemote:FireClient(player, "Result", false, "NeedBranches", cap)
		end
		return
	end
	-- Гейт слайма удалён вместе со слаймом (его заменил торговец банка).
	local cost = Services.DataService:GetRebirthCost(player)
	local money = Services.DataService:GetMoney(player)
	if BigNum.lt(money, cost) then
		local missing = cost - money
		self:_flash(player, ("Need $%s more for prestige!"):format(NumberFormat.abbreviate(missing)))
		if rebirthNpcRemote then
			rebirthNpcRemote:FireClient(player, "Result", false, "NeedMoney", NumberFormat.abbreviate(missing))
		end
		if Services.NotifyService then
			-- Та же подсказка на экране, что и при нехватке денег на
			-- прокачку (см. UpgradeService) — предлагаем зайти в магазин,
			-- а не просто отказать в ребёрте.
			Services.NotifyService:Show(player, "Not enough money! Buy a Money Pack or a cash-boost pass to speed things up.", {
				ActionLabel = "Open Shop",
				PreferredTab = "Deals",
				Icon = "Shop",
			})
		end
		return
	end
	if not Services.CartService:CanUpgradeOwnedCart(player) then
		self:_flash(player, "Get your cart back first, it is stolen!")
		if rebirthNpcRemote then
			rebirthNpcRemote:FireClient(player, "Result", false, "CartStolen")
		end
		return
	end

	local caveBeforePrestige = Services.DataService:GetTiers(player).Mine
	if not Services.DataService:DoRebirth(player) then
		return
	end
	-- v8: очки перков за престиж (чем глубже пещера — тем больше).
	if Services.PrestigeService then
		Services.PrestigeService:AddPoints(player, Services.PrestigeService.PointsForCave(caveBeforePrestige))
	end

	-- Вся руда из инвентаря (рюкзак, хотбар, руки) пропадает — по
	-- прямому запросу. Груз тележки сгорает ниже (UpgradeOwnedCart(..., true)).
	if Services.InventoryService and Services.InventoryService.ClearAllOre then
		local ok, err = pcall(function()
			Services.InventoryService:ClearAllOre(player)
		end)
		if not ok then
			warn("[Rebirth] Не удалось очистить руду из инвентаря:", err)
		end
	end

	-- Руда в плавильне — тоже руда: без этого через плавильню можно было бы
	-- "пронести" руду сквозь ребёрт. Сами острова и уровень плавильни
	-- остаются — это постоянная прогрессия, а не расходник.
	if Services.IslandService then
		pcall(function() Services.IslandService:OnRebirth(player) end)
	end

	-- Всё физическое возвращается к тиру 1 во всех трёх ветках
	-- v8: перк Head Start — престиж начинается сразу с пещеры 1 + уровень.
	local headStart = 0
	if Services.PrestigeService then
		headStart = math.clamp(math.floor(Services.PrestigeService:PerkBonus(player, "HeadStart")), 0, #Config.MineChain)
		local data = Services.DataService:GetGeodeData(player)
		if data and headStart > 0 then data.MineIndex = headStart end
	end
	Services.PlotService:SetMineTier(player, 1 + headStart)
	Services.CartService:UpgradeOwnedCart(player, true) -- true = груз старой тележки сгорает, не переносится (см. CartService)
	Services.CombatService:RefreshPickaxe(player)
	Services.CombatService:RefreshPlayerHealth(player)
	Services.CartService:RefreshSpeed(player)
	Services.UpgradeService:RefreshAllLabels(player)
	if Services.QuestService then Services.QuestService:RecordMetric(player, "Rebirths", 1) end

	local multiplier = Services.DataService:GetCrystalMultiplier(player)
	-- Единственное место в файле, где records[player] разыменовывался без
	-- проверки (везде рядом — `record and record.Npc and ...`). Если игрок
	-- вышел, пока шёл ребёрт, здесь падала ошибка — причём УЖЕ ПОСЛЕ того,
	-- как DoRebirth закоммитил сброс веток, так что дальнейшие строки
	-- (уведомление клиенту, лог) не выполнялись.
	local record = records[player]
	Sfx.play("Rebirth", record and record.Npc and record.Npc.PrimaryPart)
	if rebirthNpcRemote then
		rebirthNpcRemote:FireClient(player, "Result", true, "Success", ("%.1f"):format(multiplier))
	end
	print(("[Rebirth] %s переродился, множитель цены руды теперь x%.1f"):format(player.Name, multiplier))
end

function RebirthService:CleanupPlayer(player)
	lastRequest[player.UserId] = nil
	records[player] = nil -- инстансы уничтожает PlotService вместе с участком
end

-- Вызывается MonetizationService СРАЗУ после того, как покупка "скипа
-- ребёрта" довела деньги игрока до цены — просто повторяет обычную попытку
-- ребёрта. Если игрок уже прокачал все 3 ветки до тир-капа (а просто не
-- хватало денег — самый частый случай, ради которого и покупают скип),
-- ребёрт пройдёт сразу же. Если ветки ещё НЕ прокачаны — _tryRebirth сам
-- покажет "NeedBranches", деньги при этом всё равно остаются зачисленными.
function RebirthService:AttemptRebirthAfterPurchase(player)
	self:_tryRebirth(player)
end

-- Кнопка в GamepassQuickBar (см. Config.QuickBar/CustomCartUI.client.lua)
-- должна всплывать САМА, когда игрок реально стоит перед ребёртом, но ему
-- не хватает денег — ровно так же контекстно, как GoldenShield/FastMining.
-- Атрибут "NeedsRebirthSkip" — единая точка правды для этого условия,
-- обновляется здесь фоново (а не только в момент открытия диалога у НПС),
-- иначе кнопка не появилась бы, пока игрок сам не подойдёт и не откроет
-- диалог хотя бы раз.
local function refreshSkipAttribute(player)
	if not Services then return end
	local maxed = RebirthService:_isMaxed(player)
	local needsSkip = false
	if maxed then
		local cost = Services.DataService:GetRebirthCost(player)
		local money = Services.DataService:GetMoney(player)
		local rebirthNumber = Services.DataService:GetRebirths(player) + 1
		local product = (Config.DevProducts.RebirthSkip or {})[rebirthNumber]
		needsSkip = BigNum.lt(money, cost) and product ~= nil and (product.Id or 0) ~= 0
	end
	player:SetAttribute("NeedsRebirthSkip", needsSkip)
end

function RebirthService:_startSkipAttributeLoop()
	task.spawn(function()
		while true do
			task.wait(2)
			local ok, err = pcall(function()
				for _, player in Players:GetPlayers() do
					if records[player] then
						refreshSkipAttribute(player)
					end
				end
			end)
			if not ok then
				warn("[RebirthService] Обновление NeedsRebirthSkip упало (цикл продолжает работать):", err)
			end
		end
	end)
end

return RebirthService
