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
	sessions[player] = { JoinedAt = os.clock(), LastAt = -math.huge, Shown = {}, Pending = false }
end

function SocialOfferService:OnMetric(player, metric)
	if not CFG.Enabled then return end
	if not (CFG.HappyMetrics and CFG.HappyMetrics[metric]) then return end
	local session = sessions[player]
	if not session or session.Pending then return end
	local now = os.clock()
	if now - session.JoinedAt < (CFG.MinSessionSeconds or 180) then return end
	if now - session.LastAt < (CFG.GapSeconds or 600) then return end
	if player:GetAttribute("NeedsTutorial") == true or player:GetAttribute("Ragdolled") == true then return end
	for _, kind in CFG.Order or {} do
		local handler = HANDLERS[kind]
		if handler and not session.Shown[kind] then
			local ok, can, service = pcall(handler, player)
			if ok and can then
				session.Shown[kind] = true
				session.LastAt = now
				session.Pending = true
				task.delay(CFG.Delay or 1.5, function()
					session.Pending = false
					if player.Parent and player:GetAttribute("Ragdolled") ~= true then
						pcall(service.Offer, service, player)
					end
				end)
				return
			end
		end
	end
end

return SocialOfferService
