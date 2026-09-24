--------------------------------------------------------------------------------
-- MutationBookService
-- "Найдено / не найдено" по каждой комбинации (тир руды × мутация) — см.
-- Config.Mutations. Просто галочки, без счётчика повторов (по просьбе).
-- Не сохраняет НЕМЕДЛЕННО на каждую находку (мутации могут посыпаться
-- пачкой при продаже полной тележки — до 14 штук на топовом тире) —
-- полагается на обычный периодический автосейв (Config.Data.AutosaveInterval),
-- та же логика, что уже разбирали для SaveProfile-спама в этом чате.
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local MutationBookService = {}

local Services = nil
local remote

local function key(tier, mutationId)
	return tostring(tier) .. "_" .. mutationId
end

function MutationBookService:Init(services)
	Services = services
	remote = ReplicatedStorage.Shared:FindFirstChild("MutationBookRequest")
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = "MutationBookRequest"
		remote.Parent = ReplicatedStorage.Shared
	end
	remote.OnServerEvent:Connect(function(player, action)
		if action == "RequestState" then
			self:SendState(player)
		end
	end)
end

function MutationBookService:SetupPlayer(player)
	-- v9: разовая миграция старой книги (тир × мутация) в книгу по РУДЕ:
	-- отмечаем самую частую руду того тира с той же мутацией. Без наград.
	local data = Services.DataService:GetGeodeData(player)
	if data and data.OreBookMigrated ~= true then
		data.OreBookMigrated = true
		data.OreBook = data.OreBook or {}
		for k in data.MutationsFound or {} do
			local tier, mutationId = tostring(k):match("^(%d+)_(.+)$")
			local tierInfo = tier and Config.MineTiers[tonumber(tier)]
			local ore = tierInfo and tierInfo.Ores and tierInfo.Ores[1]
			if ore and Config.Mutations[mutationId] then
				data.OreBook[ore.Key] = true
				data.OreBook[ore.Key .. "|" .. mutationId] = true
			end
		end
	end
	self:SendState(player)
end

-- v9: НАГРАДА ЗА ОТКРЫТИЕ В КОЛЛЕКЦИИ — каждая новая руда и каждая новая
-- мутация на ней. Маленькая, в долях полной тележки текущей пещеры.
local function rewardFor(player, carts)
	local cfg = Config.Collection or {}
	local tiers = Services.DataService:GetTiers(player)
	local cartValue = Config.CartValue(tiers.Mine, tiers.Cart)
	return math.max(cfg.MinReward or 25, math.floor(cartValue * carts))
end

function MutationBookService:RecordOre(player, oreKey, mutations)
	local data = Services.DataService:GetGeodeData(player)
	local oreInfo = Config.OreByKey[oreKey]
	if not (data and oreInfo) then return end
	data.OreBook = data.OreBook or {}
	local cfg = Config.Collection or {}
	local found = {}
	if not data.OreBook[oreKey] then
		data.OreBook[oreKey] = true
		table.insert(found, { Name = oreInfo.DisplayName, Reward = rewardFor(player, cfg.RewardOreCarts or 0.03) })
	end
	if mutations and #mutations > 0 and Services.TutorialService then
		pcall(function() Services.TutorialService:ShowHint(player, "FirstMutation") end)
	end
	for _, mutationId in mutations or {} do
		local key = oreKey .. "|" .. mutationId
		local mutation = Config.Mutations[mutationId]
		if mutation and not data.OreBook[key] then
			data.OreBook[key] = true
			table.insert(found, { Name = oreInfo.DisplayName .. " + " .. mutation.DisplayName, Reward = rewardFor(player, cfg.RewardMutationCarts or 0.05) })
		end
	end
	if #found == 0 then return end
	local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
	for _, entry in found do
		Services.DataService:AddMoney(player, entry.Reward)
		if Services.NotifyService then
			Services.NotifyService:Show(player, ("📖 NEW: %s  +$%s"):format(entry.Name, NumberFormat.abbreviate(entry.Reward)), {
				Icon = "Reward", Duration = 3, TextColor = Color3.fromRGB(255, 215, 80),
			})
		end
	end
	self:SendState(player)
end

function MutationBookService:SendState(player)
	local data = Services.DataService:GetGeodeData(player)
	if not data then return end
	remote:FireClient(player, { Mutations = data.MutationsFound or {}, Mobs = data.MobsFound or {}, OreBook = data.OreBook or {} })
end

-- Вызывается CrystalService:Create при каждой найденной мутации. НЕ
-- сохраняет сразу (см. комментарий выше) — просто помечает в памяти и тут
-- же шлёт клиенту, чтобы книга обновлялась вживую, если она открыта.
function MutationBookService:RecordFound(player, tier, mutationId)
	local data = Services.DataService:GetGeodeData(player)
	if not data then return end
	if not data.MutationsFound then data.MutationsFound = {} end
	local k = key(tier, mutationId)
	if data.MutationsFound[k] then return end -- уже отмечено — нет смысла слать лишний State
	data.MutationsFound[k] = true
	self:SendState(player)
end

function MutationBookService:RecordMobFound(player, mobId)
	local data = Services.DataService:GetGeodeData(player)
	if not data or not Config.Goblins.Types[mobId] then return end
	if not data.MobsFound then data.MobsFound = {} end
	if data.MobsFound[mobId] then return end
	data.MobsFound[mobId] = true
	self:SendState(player)
end

return MutationBookService
