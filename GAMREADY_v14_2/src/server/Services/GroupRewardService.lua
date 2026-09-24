--------------------------------------------------------------------------------
-- GroupRewardService
-- Второе окно-подарок: "лайкни игру И вступи в группу → получи скин +
-- жеоды" (см. Config.GroupReward). Та же схема, что и LikeRewardService —
-- сама анимация целиком на клиенте (GroupRewardUI.client.lua), этот сервис
-- только говорит клиенту, когда показывать окно, и выдаёт награду по
-- запросу.
--
-- ВАЖНО: у "лайка" действительно нет API для проверки (см. подробности у
-- Config.LikeReward) — эта половина награды остаётся на доверии.
--
-- А ВОТ ПРО ГРУППУ В СТАРОМ КОММЕНТАРИИ ЗДЕСЬ БЫЛО НАПИСАНО НЕВЕРНО, и из-за
-- этого награда выдавалась ВООБЩЕ БЕЗ ПРОВЕРКИ: достаточно было отправить
-- "Claim" в этот RemoteEvent, ни в какую группу не вступая. Проверить
-- членство скриптом МОЖНО, просто не тем методом, о котором думал автор:
--   • GroupService:GetGroupsAsync(userId) — настоящий веб-запрос, отдаёт
--     АКТУАЛЬНЫЙ список групп. Именно он нужен здесь, потому что игрок
--     вступает в группу ПРЯМО СЕЙЧАС, посреди сессии.
--   • Player:IsInGroup(groupId) — дешёвый, но КЭШИРУЕТСЯ на момент захода
--     игрока на сервер. Для только что вступившего вернёт false, поэтому
--     годится только как быстрый положительный shortcut, а отрицательный
--     ответ от него ничего не доказывает (см. isInGroup ниже).
-- Подтвердить результат самого промпта PromptJoinAsync и правда нельзя — но
-- это и не нужно: мы спрашиваем не "нажал ли он кнопку", а "состоит ли он в
-- группе на самом деле", и на этот вопрос ответ есть.
--------------------------------------------------------------------------------

local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local GroupRewardService = {}

local Services = nil
local remote

-- Синхронный in-flight гард: выставляется В ПЕРВОЙ СТРОКЕ Claim, до любого
-- йилда. Без него спам по RemoteEvent запускал несколько Claim параллельно —
-- все они успевали пройти проверку data.GroupRewardClaimed (она выставляется
-- в самом конце, уже ПОСЛЕ йилдящих GrantNpcSkin/AddGeodeDirectly), и
-- награда могла выдаться повторно.
local claiming = {}   -- [player] = true, пока идёт выдача
local lastClaim = {}  -- [userId] = { [action] = os.clock() } — антиспам, отдельно по каждому действию

-- Реальная проверка членства. Порядок важен:
--   1. Player:IsInGroup — мгновенный, без веб-запроса. Если true — верим
--      сразу (ложноположительным он не бывает).
--   2. GroupService:GetGroupsAsync — если кэш сказал false, переспрашиваем
--      по-настоящему: игрок мог вступить минуту назад, прямо в этой сессии.
-- Оба в pcall: это сетевые вызовы, они падают при троттлинге, и падение не
-- должно ронять обработчик целиком.
local function isInGroup(player, groupId)
	local ok, result = pcall(function() return player:IsInGroup(groupId) end)
	if ok and result == true then
		return true
	end
	local groupsOk, groups = pcall(function() return GroupService:GetGroupsAsync(player.UserId) end)
	if not groupsOk or typeof(groups) ~= "table" then
		return false, "CheckFailed" -- сеть подвела: НЕ выдаём, но и не помечаем забранным — пусть попробует ещё раз
	end
	for _, group in groups do
		if group.Id == groupId then
			return true
		end
	end
	return false, "NotInGroup"
end

function GroupRewardService:Init(services)
	Services = services
	remote = ReplicatedStorage.Shared:FindFirstChild("GroupRewardRequest")
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = "GroupRewardRequest"
		remote.Parent = ReplicatedStorage.Shared
	end
	remote.OnServerEvent:Connect(function(player, action)
		-- Дебаунс — тот же приём, что в UpgradeService/DataService
		-- (RedeemCodeRequest): раньше этот ремоут можно было дёргать
		-- сотнями раз в секунду, и каждый вызов уходил в Claim с его
		-- веб-запросами и записями в DataStore.
		-- Дебаунс на ПАРУ (игрок + действие): "Claim" не должен съедать
		-- следующий за ним "RequestState" и наоборот — иначе панель может
		-- остаться с устаревшим состоянием.
		if typeof(action) ~= "string" then return end
		local now = os.clock()
		local byAction = lastClaim[player.UserId]
		if not byAction then
			byAction = {}
			lastClaim[player.UserId] = byAction
		end
		local last = byAction[action]
		if last and now - last < 0.5 then
			return
		end
		byAction[action] = now

		if action == "RequestState" then
			self:SendState(player)
		elseif action == "Claim" then
			self:Claim(player)
		end
	end)

	game:GetService("Players").PlayerRemoving:Connect(function(player)
		claiming[player] = nil
		lastClaim[player.UserId] = nil
	end)
end

function GroupRewardService:SetupPlayer(player)
	-- v16: проверяем членство сразу при входе — бонус +10% работает, даже
	-- если игрок вступил в группу давно и окно больше не открывает.
	task.spawn(function()
		local groupId = tonumber(Config.GroupReward.GroupId) or 0
		if groupId ~= 0 and player.Parent then
			local member = isInGroup(player, groupId)
			if player.Parent then player:SetAttribute("GroupMember", member == true) end
		end
		self:SendState(player)
	end)
end

function GroupRewardService:SendState(player)
	if not Config.GroupReward.Enabled then return end
	local data = Services.DataService:GetGeodeData(player)
	if not data then return end
	remote:FireClient(player, "State", {
		Claimed = data.GroupRewardClaimed == true,
		Member = player:GetAttribute("GroupMember") == true,
		GroupId = Config.GroupReward.GroupId,
		IncomeBonus = Config.GroupReward.IncomeBonus or 0,
		ChestRarity = Config.GroupReward.ChestRarity or "Common",
	})
end

-- v16: для SocialOfferService — есть ли что предложить.
function GroupRewardService:CanOffer(player)
	if not Config.GroupReward.Enabled or (tonumber(Config.GroupReward.GroupId) or 0) == 0 then return false end
	local data = Services.DataService:GetGeodeData(player)
	if not data then return false end
	return not (data.GroupRewardClaimed == true and player:GetAttribute("GroupMember") == true)
end

function GroupRewardService:Offer(player)
	self:SendState(player)
	remote:FireClient(player, "Offer")
end

-- v16: проверка членства + разовый подарок (сундук). Если подарок уже
-- забран — просто перепроверяет членство (включает бонус +10%).
function GroupRewardService:Claim(player)
	if not Config.GroupReward.Enabled then return false end
	-- ГАРД №1 (синхронный, до любого йилда) — см. `claiming` вверху файла.
	if claiming[player] then return false end
	local data = Services.DataService:GetGeodeData(player)
	if not data then return false end
	local groupId = tonumber(Config.GroupReward.GroupId) or 0
	if groupId == 0 then
		warn("[GroupRewardService] Config.GroupReward.GroupId = 0 — награда за группу не выдаётся, пока не вписан реальный ID группы (см. Config.lua).")
		self:SendState(player)
		return false
	end
	claiming[player] = true
	-- ГАРД №2 — РЕАЛЬНАЯ ПРОВЕРКА ЧЛЕНСТВА (GetGroupsAsync, не кэш).
	local member, reason = isInGroup(player, groupId)
	if not member then
		claiming[player] = nil
		if player.Parent and reason ~= "CheckFailed" then player:SetAttribute("GroupMember", false) end
		if Services.NotifyService then
			Services.NotifyService:Show(player, reason == "CheckFailed"
				and "Could not verify group membership right now. Please try again."
				or "Join the group, then press JOIN GROUP again to verify.", { Icon = reason == "CheckFailed" and "Error" or "Social" })
		end
		self:SendState(player)
		return false
	end
	player:SetAttribute("GroupMember", true)
	if data.GroupRewardClaimed ~= true then
		-- Разовый подарок — сундук (Config.GroupReward.ChestRarity).
		local rarity = Config.GroupReward.ChestRarity or "Common"
		local ok = Services.GearService and pcall(Services.GearService.GrantChest, Services.GearService, player, rarity, 1, true)
		if not ok then
			claiming[player] = nil
			if Services.NotifyService then
				Services.NotifyService:Show(player, "Reward is temporarily unavailable. Please try again in a moment.", { Icon = "Error" })
			end
			self:SendState(player)
			return false
		end
		data.GroupRewardClaimed = true
		Services.DataService:SaveProfile(player)
	end
	claiming[player] = nil
	if Services.NotifyService then
		Services.NotifyService:Show(player, ("THANKS FOR JOINING! +%d%% sell price active + free chest!"):format(
			math.floor((Config.GroupReward.IncomeBonus or 0) * 100 + 0.5)), { Icon = "Reward" })
	end
	self:SendState(player)
	return true
end

return GroupRewardService
