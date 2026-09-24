--------------------------------------------------------------------------------
-- LikeRewardService
-- Окно "добавь в избранное И лайкни игру → получи скин на кирку + жеоды"
-- (см. Config.LikeReward). Сама анимация подарка — целиком на клиенте
-- (LikeRewardUI.client.lua), этот сервис только: говорит клиенту, когда
-- можно/нужно показать окно (см. SetupPlayer), и выдаёт награду по запросу
-- (см. Claim). Независимо от Config.GroupReward/GroupRewardService (то
-- окно — лайк + вступление в группу, за отдельную награду).
--
-- ВАЖНО (см. подробный комментарий у Config.LikeReward): у Roblox нет API
-- для проверки лайка игры скриптом — награда выдаётся по нажатию кнопки
-- "CLAIM" на доверии, без реальной верификации. Это ограничение платформы.
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local LikeRewardService = {}

local Services = nil
local remote

-- Синхронный in-flight гард: выставляется В ПЕРВОЙ СТРОКЕ Claim, до любого
-- йилда. Раньше единственной защитой был флаг data.LikeRewardClaimed, а он
-- ставится в САМОМ КОНЦЕ Claim — уже после GrantNpcSkin и цепочки
-- AddGeodeDirectly, каждый из которых йилдит на SaveProfile (DataStore).
-- Пока первый Claim висел на этих йилдах, второй спокойно проходил ту же
-- проверку и шёл выдавать награду повторно. RemoteEvent при этом можно было
-- дёргать без ограничений, так что попасть в это окно было делом техники.
local claiming = {}   -- [player] = true, пока идёт выдача
local lastClaim = {}  -- [userId] = { [action] = os.clock() } — антиспам, отдельно по каждому действию

function LikeRewardService:Init(services)
	Services = services
	remote = ReplicatedStorage.Shared:FindFirstChild("LikeRewardRequest")
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = "LikeRewardRequest"
		remote.Parent = ReplicatedStorage.Shared
	end
	remote.OnServerEvent:Connect(function(player, action)
		-- Дебаунс — тот же приём, что в UpgradeService/DataService
		-- (RedeemCodeRequest).
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

function LikeRewardService:SetupPlayer(player)
	self:SendState(player)
end

-- v16: для SocialOfferService — есть ли что предложить.
function LikeRewardService:CanOffer(player)
	if not Config.LikeReward.Enabled then return false end
	local data = Services.DataService:GetGeodeData(player)
	return data ~= nil and data.LikeRewardClaimed ~= true
end

function LikeRewardService:Offer(player)
	self:SendState(player)
	remote:FireClient(player, "Offer")
end

function LikeRewardService:SendState(player)
	if not Config.LikeReward.Enabled then return end
	local data = Services.DataService:GetGeodeData(player)
	if not data then return end
	remote:FireClient(player, "State", {
		Claimed = data.LikeRewardClaimed == true,
		SkinId = Config.LikeReward.SkinId,
		GeodeType = Config.LikeReward.GeodeType,
		GeodeCount = Config.LikeReward.GeodeCount,
	})
end

-- Выдаёт скин + жеоды. Скин и каждая жеода выдаются ОТДЕЛЬНО (каждая из
-- этих функций уже сама надёжно и идемпотентно сохраняет прогресс — см.
-- SkinService:GrantNpcSkin/GeodeService:AddGeodeDirectly), поэтому тут не
-- нужна отдельная общая транзакция вокруг обеих — она бы только столкнулась
-- с их СОБСТВЕННЫМИ внутренними блокировками (EconomyTransactionLocked).
function LikeRewardService:Claim(player)
	if not Config.LikeReward.Enabled then return false end

	-- Синхронный гард ДО любого йилда — см. `claiming` вверху файла.
	if claiming[player] then return false end

	local data = Services.DataService:GetGeodeData(player)
	if not data or data.LikeRewardClaimed == true then
		self:SendState(player)
		return false
	end
	claiming[player] = true

	-- ТА ЖЕ ЛОГИКА, ЧТО И В GroupRewardService (см. подробный комментарий
	-- там): скин — обязательная часть награды, а не «желательная». Раньше
	-- достаточно было выдать жеоды, чтобы награда считалась забранной
	-- НАВСЕГДА — и если скин по какой-то причине не выдавался, игрок терял
	-- именно то, ради чего он вообще жал кнопку.
	local skinGranted = Services.SkinService:GrantNpcSkin(player, Config.LikeReward.SkinId)
	if not skinGranted then
		claiming[player] = nil
		warn(("[LikeRewardService] Не удалось выдать скин %s игроку %s — награда НЕ помечена забранной, игрок сможет забрать её позже. Проверь ассет Config.Skins.Definitions.%s.AssetName в ReplicatedStorage/Assets."):format(
			tostring(Config.LikeReward.SkinId), player.Name, tostring(Config.LikeReward.SkinId)))
		if Services.NotifyService then
			Services.NotifyService:Show(player, "Reward is temporarily unavailable. Please try again in a moment.", { Icon = "Error" })
		end
		self:SendState(player)
		return false
	end

	local geodesGranted = 0
	for _ = 1, Config.LikeReward.GeodeCount do
		if Services.GeodeService:AddGeodeDirectly(player, Config.LikeReward.GeodeType) then
			geodesGranted += 1
		end
	end
	if geodesGranted < Config.LikeReward.GeodeCount then
		warn(("[LikeRewardService] Игроку %s выдано жеод: %d из %d. Скин выдан, награда засчитана."):format(
			player.Name, geodesGranted, Config.LikeReward.GeodeCount))
	end

	data.LikeRewardClaimed = true
	Services.DataService:SaveProfile(player)
	claiming[player] = nil
	if Services.NotifyService then
		Services.NotifyService:Show(player, "THANKS FOR FAVORITING! Reward claimed.", { Icon = "Reward" })
	end
	self:SendState(player)
	return true
end

return LikeRewardService
