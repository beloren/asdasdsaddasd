--------------------------------------------------------------------------------
-- CompassService (v20.110) — ТЕЛЕПОРТ ЧЕРЕЗ КОМПАС (Config.Compass).
-- Клиент (CompassUI) открывает мини-карту и просит телепорт:
--   "Center"        - центр мира (торговцы; маркер workspace.CompassCenterMarker,
--                     иначе зона продажи),
--   "Raft"          - свой плот (PlayerSpawnMarker участка),
--   "Island:<Id>"   - свой купленный остров.
-- Откат Config.Compass.Cooldown секунд; во время мини-игры шахты,
-- рагдолла и экономической транзакции телепорт запрещён.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local CompassService = {}
local Services = nil
local remote
local lastTeleport = {}

local function cfg()
	return Config.Compass or {}
end

local function partPosition(instance)
	if not instance then return nil end
	if instance:IsA("BasePart") then return instance.Position end
	if instance:IsA("Model") then return instance:GetPivot().Position end
	return nil
end

-- v20.125: «в город» = ПЕРЕД ТОРГОВЦЕМ РУДЫ (workspace.BankMerchant), лицом
-- к нему, на Config.Compass.MerchantDistance стадов. Нет торговца - маркер
-- CompassCenterMarker или зона продажи, как раньше.
function CompassService:_centerCFrame()
	local merchant = workspace:FindFirstChild("BankMerchant")
	if merchant and merchant:IsA("Model") then
		local pivot = merchant:GetPivot()
		local forward = Vector3.new(pivot.LookVector.X, 0, pivot.LookVector.Z)
		if forward.Magnitude < 0.05 then forward = Vector3.new(0, 0, -1) end
		local spot = pivot.Position + forward.Unit * (tonumber(cfg().MerchantDistance) or 9)
		return CFrame.lookAt(spot, Vector3.new(pivot.Position.X, spot.Y, pivot.Position.Z))
	end
	local marker = workspace:FindFirstChild(cfg().CenterMarkerName or "CompassCenterMarker", true)
	if marker and marker:IsA("BasePart") then return marker.CFrame end
	local zone = Services.WorldService and Services.WorldService:GetSellZone()
	local position = partPosition(zone)
	if not position then return nil end
	return CFrame.new(position + (cfg().CenterOffset or Vector3.new(0, 0, 18)))
end

function CompassService:_raftCFrame(player)
	local plot = Services.PlotService and Services.PlotService:GetPlot(player)
	if not plot then return nil end
	if typeof(plot.PlayerSpawnCFrame) == "CFrame" then return plot.PlayerSpawnCFrame end
	local position = partPosition(plot.Pad) or partPosition(plot.Content)
	return position and CFrame.new(position) or nil
end

function CompassService:_islandCFrame(player, islandId)
	if not (Services.IslandService and Services.IslandService:Owns(player, islandId)) then return nil end
	local plot = Services.PlotService and Services.PlotService:GetPlot(player)
	local model = plot and plot.Content and plot.Content:FindFirstChild("Island_" .. islandId)
	if not (model and model:IsA("Model")) then return nil end
	local surface = model:FindFirstChild("Surface")
	if surface and surface:IsA("BasePart") then
		return CFrame.new(surface.Position + Vector3.new(0, surface.Size.Y / 2, 0))
	end
	local boxCf, boxSize = model:GetBoundingBox()
	return CFrame.new(boxCf.Position + Vector3.new(0, boxSize.Y / 2, 0))
end

function CompassService:Destinations(player)
	local list = {}
	local center = self:_centerCFrame()
	if center then table.insert(list, { Id = "Center", Name = "Ore Merchant", Icon = "🏪", Position = center.Position }) end
	local raft = self:_raftCFrame(player)
	if raft then table.insert(list, { Id = "Raft", Name = "My Raft", Icon = "🏠", Position = raft.Position }) end
	for _, islandId in (Config.Islands and Config.Islands.Order) or {} do
		local cf = self:_islandCFrame(player, islandId)
		if cf then
			local def = Config.Islands.Definitions[islandId]
			table.insert(list, { Id = "Island:" .. islandId, Name = def and def.DisplayName or islandId, Icon = def and def.Icon or "🏝", Position = cf.Position })
		end
	end
	return list
end

function CompassService:Teleport(player, destId)
	if typeof(destId) ~= "string" then return false, "Unknown place" end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (hrp and humanoid and humanoid.Health > 0) then return false, "Not now" end
	local now = os.clock()
	local cooldown = tonumber(cfg().Cooldown) or 5
	local left = (lastTeleport[player] or -math.huge) + cooldown - now
	if left > 0 then return false, ("Wait %ds"):format(math.ceil(left)) end
	if player:GetAttribute("MineExpeditionActive") == true then return false, "Finish digging first" end
	if player:GetAttribute("Ragdolled") == true then return false, "You are knocked down" end
	if player:GetAttribute("EconomyTransactionLocked") == true then return false, "Try again" end
	local target
	if destId == "Center" then
		target = self:_centerCFrame()
	elseif destId == "Raft" then
		target = self:_raftCFrame(player)
	else
		local islandId = destId:match("^Island:(%w+)$")
		target = islandId and self:_islandCFrame(player, islandId)
	end
	if not target then return false, "Can't go there" end
	lastTeleport[player] = now
	-- в город - лицом к торговцу; остальное - туда же, куда смотрел игрок
	local look = destId == "Center" and target.LookVector or hrp.CFrame.LookVector
	local position = target.Position + Vector3.new(0, 3.5, 0)
	character:PivotTo(CFrame.lookAt(position, position + Vector3.new(look.X, 0, look.Z)))
	hrp.AssemblyLinearVelocity = Vector3.zero
	if Services.TutorialService then
		pcall(Services.TutorialService.Count, Services.TutorialService, player, "Teleported", 1)
	end
	return true, cooldown
end

function CompassService:Init(services)
	Services = services
	remote = ReplicatedStorage.Shared:FindFirstChild("CompassRequest") or Instance.new("RemoteFunction")
	remote.Name = "CompassRequest"
	remote.Parent = ReplicatedStorage.Shared
	remote.OnServerInvoke = function(player, action, value)
		if action == "Info" then
			local ok, list = pcall(self.Destinations, self, player)
			local left = math.max(0, (lastTeleport[player] or -math.huge) + (tonumber(cfg().Cooldown) or 5) - os.clock())
			return { Destinations = ok and list or {}, CooldownLeft = left }
		elseif action == "Teleport" then
			local ok, result, extra = pcall(self.Teleport, self, player, value)
			if not ok then return false, "Error" end
			return result, extra
		end
		return nil
	end
	Players.PlayerRemoving:Connect(function(player) lastTeleport[player] = nil end)
end

function CompassService:Start() end

return CompassService
