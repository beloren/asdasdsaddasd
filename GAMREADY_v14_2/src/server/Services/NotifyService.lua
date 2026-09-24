--------------------------------------------------------------------------------
-- NotifyService
-- ЕДИНАЯ точка для коротких сообщений НА ЭКРАНЕ игрока (ScreenGui "Toast",
-- см. tools/BuildNotificationUI.lua/CustomCartUI.client.lua) — не 3D-биллборд у
-- конкретного объекта (как, например, вспышка над NPC в RebirthService),
-- а прямо в UI, видно всегда, независимо от того, куда смотрит камера.
--
-- Любой другой сервис может позвать Services.NotifyService:Show(player,
-- text, opts) — сам ничего строить/реплицировать не должен.
--
-- opts (необязательно):
--   Icon         — смысловой ключ из Config.Notify.Icons.
--   ActionLabel  — текст кнопки-действия ("Open Shop" и т.п.). Не задан —
--                  кнопки не будет, просто текст.
--   Action       — что делает кнопка: "Shop" (по умолчанию) открывает
--                  магазин, "Invite" — системное окно приглашения друга.
--   PreferredTab — если Action = "Shop", на какую вкладку магазина
--                  переключиться при клике (см. Config.Shop.Tabs). Не
--                  задан — магазин просто откроется на текущей/первой
--                  вкладке.
--   Duration     — сколько секунд тост виден, прежде чем спрячется сам.
--                  Не задан — берётся Config.Notify.Duration.
--   Viewport     — { OreId, MutationId } — вместо плоской Icon-картинки
--                  показывает живое 3D-превью конкретной руды/мутации
--                  (тот же принцип, что в книге мутаций). См. RockService —
--                  "редкая находка на валуне" — и CustomCartUI.client.lua,
--                  блок TOAST, где это рендерится.
--
-- Пример (см. UpgradeService/RebirthService — "не хватает денег"):
--   Services.NotifyService:Show(player, "Not enough money!", {
--       ActionLabel = "Open Shop",
--       PreferredTab = "Deals",
--   })
--
-- Пример (см. MonetizationService — реферальное напоминание):
--   Services.NotifyService:Show(player, "Invite friends for bonus money!", {
--       ActionLabel = "Invite",
--       Action = "Invite",
--   })
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NotifyService = {}

local notifyRemote = nil
local bankTrailRemote = nil
local lootFeedRemote = nil
local Services = nil

function NotifyService:Init(services)
	Services = services
	notifyRemote = Instance.new("RemoteEvent")
	notifyRemote.Name = "NotifyRequest"
	notifyRemote.Parent = ReplicatedStorage.Shared
	bankTrailRemote = Instance.new("RemoteEvent")
	bankTrailRemote.Name = "BankTrailHintEvent"
	bankTrailRemote.Parent = ReplicatedStorage.Shared
	-- v14: ЛЕНТА ЛУТА справа + баннер по центру для редкого (см.
	-- client/LootFeed.client.lua). Любой сервис: NotifyService:LootFeed(player,
	-- { { Icon, Text, Color, Rarity, Sub }, ... }, { Title, Color }?).
	lootFeedRemote = ReplicatedStorage.Shared:FindFirstChild("LootFeedEvent") or Instance.new("RemoteEvent")
	lootFeedRemote.Name = "LootFeedEvent"
	lootFeedRemote.Parent = ReplicatedStorage.Shared
end

function NotifyService:LootFeed(player, items, header)
	if not (player and player.Parent and lootFeedRemote) then return end
	if typeof(items) ~= "table" or #items == 0 then return end
	lootFeedRemote:FireClient(player, items, header)
end

function NotifyService:ShowBankTrailOnce(player, cargoKind)
	if cargoKind ~= "Rubble" and cargoKind ~= "Hand" then return false end
	if not (player and player.Parent and Services and Services.DataService) then return false end
	-- Та же причина, что и в Show выше — ничего постороннего поверх гайда.
	if player:GetAttribute("NeedsTutorial") == true then return false end
	if not Services.DataService:MarkHintSeenAndSave(player, "FirstExternalCrystalBankTrail") then return false end
	local stillCarrying = player.Parent
		and (cargoKind == "Rubble" and player:GetAttribute("CarryingCrystal") ~= ""
			or cargoKind == "Hand" and (player:GetAttribute("HandOreCount") or 0) > 0)
	if not stillCarrying then
		Services.DataService:ClearHintSeenAndSave(player, "FirstExternalCrystalBankTrail")
		return false
	end
	bankTrailRemote:FireClient(player, cargoKind)
	return true
end

function NotifyService:Show(player, text, opts)
	if not (player and player.Parent) then
		return -- игрок уже вышел, пока сообщение летело — фаер клиенту без адресата ничего не делает, но проверка дешёвая
	end
	-- Во время основного гайда (Config.Tutorial) на экране не должно быть
	-- НИЧЕГО, кроме самой карточки гайда — по прямому запросу. Любой тост
	-- отсюда (ошибка покупки, "не хватает денег", завершение квеста и
	-- т.п.) рисуется поверх игры точно там же, где карточка, и реально
	-- перекрывает/отвлекает от неё. Единая точка входа для ВСЕХ серверных
	-- тостов (см. шапку файла) — значит один этот guard закрывает вообще
	-- все вызовы NotifyService:Show по всему проекту разом, без похода по
	-- каждому месту вызова отдельно.
	--
	-- ИСКЛЮЧЕНИЕ — ошибки и возвраты денег (Icon = "Error"/"Refund") и
	-- всё, что помечено opts.Critical = true. Без них новичок молча
	-- упирался в отказ ("не хватает денег", "покупка не удалась, деньги
	-- возвращены") и не понимал, что произошло.
	if player:GetAttribute("NeedsTutorial") == true then
		local critical = typeof(opts) == "table"
			and (opts.Critical == true or opts.Icon == "Error" or opts.Icon == "Refund")
		if not critical then return end
	end
	notifyRemote:FireClient(player, text, opts)
end

return NotifyService
