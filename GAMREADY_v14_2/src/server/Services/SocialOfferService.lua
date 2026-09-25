--------------------------------------------------------------------------------
-- SocialOfferService (v16) — МЯГКИЕ ПРЕДЛОЖЕНИЯ «вступи в группу» и
-- «добавь в избранное» (см. Config.SocialOffers).
--
-- Окна больше не всплывают по таймеру. Предложение показывается только в
-- удачный момент — когда QuestService записал «счастливую» метрику
-- (продал тележку, нашёл редкое, престиж, открыл сундук):
--   • не раньше MinSessionSeconds от захода и не во время обучения;
--   • каждое окно — максимум один раз за сессию;
--   • между двумя любыми окнами — не меньше GapSeconds;
--   • не пока игрок в рагдолле.
-- v20.14: окно показывается через 20-30 сек ПОСЛЕ удачи (не перекрывая её);
-- новая удача отодвигает показ, «занятый» игрок — тоже (см. isBusy).
-- Порядок — Config.SocialOffers.Order. Уже выполненное не предлагается.
-- Вручную оба окна всегда открываются кнопкой 🎁 в HUD (SocialHud).
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local SocialOfferService = {}
local Services = nil
local CFG = Config.SocialOffers or {}

local sessions = {} -- [player] = { JoinedAt, LastAt, Shown = {}, Pending = bool }

local HANDLERS = {
	Group = function(player)
		local service = Services.GroupRewardService
		return service and service.CanOffer and service:CanOffer(player), service
	end,
	Favorite = function(player)
		local service = Services.LikeRewardService
		return service and service.CanOffer and service:CanOffer(player), service
	end,
}

function SocialOfferService:Init(services)
	Services = services
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)
end

function SocialOfferService:SetupPlayer(player)
	sessions[player] = { JoinedAt = os.clock(), LastAt = -math.huge, Shown = {}, Pending = false, ShowAt = 0 }
end

-- Игрок сейчас в «моменте», который окно не должно перекрыть.
local function isBusy(player)
	return player:GetAttribute("NeedsTutorial") == true
		or player:GetAttribute("Ragdolled") == true
		or player:GetAttribute("MineExpeditionActive") == true
		or player:GetAttribute("GoblinWaveActive") == true
		or player:GetAttribute("UpgradeInProgress") == true
end

local function randomDelay()
	local low = tonumber(CFG.DelayMin) or 20
	local high = math.max(low, tonumber(CFG.DelayMax) or 30)
	return low + math.random() * (high - low)
end

function SocialOfferService:OnMetric(player, metric)
	if not CFG.Enabled then return end
	if not (CFG.HappyMetrics and CFG.HappyMetrics[metric]) then return end
	local session = sessions[player]
	if not session then return end
	local now = os.clock()
	if session.Pending then
		-- Новая удача, пока ждём показа, — отодвигаем окно, чтобы не
		-- перекрыть и её.
		session.ShowAt = math.max(session.ShowAt, now + (tonumber(CFG.DelayMin) or 20))
		return
	end
	if now - session.JoinedAt < (CFG.MinSessionSeconds or 180) then return end
	if now - session.LastAt < (CFG.GapSeconds or 600) then return end
	if player:GetAttribute("NeedsTutorial") == true then return end
	for _, kind in CFG.Order or {} do
		local handler = HANDLERS[kind]
		if handler and not session.Shown[kind] then
			local ok, can, service = pcall(handler, player)
			if ok and can then
				session.Shown[kind] = true
				session.LastAt = now
				session.Pending = true
				session.ShowAt = now + randomDelay()
				local giveUpAt = now + (tonumber(CFG.MaxWaitSeconds) or 180)
				task.spawn(function()
					while player.Parent and sessions[player] == session do
						local t = os.clock()
						if t >= session.ShowAt and not isBusy(player) then break end
						if t >= giveUpAt then
							-- Слишком долго занят — не показываем, попробуем при следующей удаче.
							session.Pending = false
							session.Shown[kind] = nil
							return
						end
						task.wait(1)
					end
					session.Pending = false
					if player.Parent and sessions[player] == session then
						session.LastAt = os.clock()
						pcall(service.Offer, service, player)
					end
				end)
				return
			end
		end
	end
end

return SocialOfferService
