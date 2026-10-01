--------------------------------------------------------------------------------
-- SellMoleService (v20.108) — КРОТ-СКУПЩИК НА ЗОНЕ ПРОДАЖИ (Config.SellMole).
--
-- Игрок с рудой зашёл в зону продажи → перед ним (в пределах зоны) из
-- земли вылезает крот (модель Assets/SellMole или заглушка) и открывает
-- игроку меню SELL ALL / SELL HAND / NOT NOW (клиент: SellMoleUI).
-- После ответа крот зарывается и исчезает. Вся анимация (вылез, «дышит»
-- масштабом, зарылся, комья земли) - на клиентах по атрибуту State модели;
-- сервер только ставит модель, продаёт и убирает.
--
-- Повторно крот вылезает, только когда игрок вышел из зоны и зашёл снова
-- (после SELL HAND, если руда ещё осталась, - через пару секунд сам).
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local SellMoleService = {}
local Services = nil

local remote
local folder
local states = {} -- [player] = { Mole, Busy, NeedsExit, RespawnAt }

local function cfg()
	return Config.SellMole or {}
end

local function makePlaceholder()
	local model = Instance.new("Model")
	model.Name = "SellMole"
	local brown = Color3.fromRGB(120, 82, 55)
	local function part(name, shape, size, offset, color, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape
		p.Size = size
		p.CFrame = CFrame.new(offset)
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	part("Body", Enum.PartType.Ball, Vector3.new(3.4, 3.4, 3.4), Vector3.new(0, 1.7, 0), brown)
	part("Head", Enum.PartType.Ball, Vector3.new(2.4, 2.4, 2.4), Vector3.new(0, 3.5, -0.6), brown)
	part("Snout", Enum.PartType.Ball, Vector3.new(1.1, 0.9, 1.1), Vector3.new(0, 3.2, -1.75), Color3.fromRGB(205, 160, 125))
	part("Nose", Enum.PartType.Ball, Vector3.new(0.5, 0.45, 0.5), Vector3.new(0, 3.35, -2.25), Color3.fromRGB(255, 120, 150))
	part("EyeL", Enum.PartType.Ball, Vector3.new(0.38, 0.38, 0.38), Vector3.new(-0.5, 3.95, -1.62), Color3.fromRGB(20, 15, 15))
	part("EyeR", Enum.PartType.Ball, Vector3.new(0.38, 0.38, 0.38), Vector3.new(0.5, 3.95, -1.62), Color3.fromRGB(20, 15, 15))
	part("PawL", Enum.PartType.Ball, Vector3.new(0.9, 0.6, 0.9), Vector3.new(-1.1, 2.2, -1.5), Color3.fromRGB(230, 170, 150))
	part("PawR", Enum.PartType.Ball, Vector3.new(0.9, 0.6, 0.9), Vector3.new(1.1, 2.2, -1.5), Color3.fromRGB(230, 170, 150))
	local hat = part("Helmet", Enum.PartType.Ball, Vector3.new(2.5, 1.3, 2.5), Vector3.new(0, 4.45, -0.5), Color3.fromRGB(255, 200, 40))
	hat.Material = Enum.Material.SmoothPlastic
	local root = part("Root", Enum.PartType.Block, Vector3.new(1, 1, 1), Vector3.new(0, 0, 0), brown)
	root.Transparency = 1
	model.PrimaryPart = root
	-- нос смотрит в -Z (LookVector), как у CFrame.lookAt
	return model
end

local function buildModel()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local source = assets and assets:FindFirstChild(cfg().ModelName or "SellMole")
	local model = source and source:Clone() or makePlaceholder()
	model.Name = "SellMole"
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart", true)
	end
	local scale = tonumber(cfg().Scale) or 1
	if scale ~= 1 then pcall(model.ScaleTo, model, scale) end
	return model
end

local function zoneSpot(zone, hrp)
	-- точка перед игроком, зажатая в границы зоны
	local look = hrp.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	if look.Magnitude < 0.1 then look = Vector3.new(0, 0, -1) end
	local wanted = hrp.Position + look.Unit * (cfg().Distance or 7)
	local rel = zone.CFrame:PointToObjectSpace(wanted)
	local margin = cfg().EdgeMargin or 3
	local hx = math.max(0, zone.Size.X / 2 - margin)
	local hz = math.max(0, zone.Size.Z / 2 - margin)
	rel = Vector3.new(math.clamp(rel.X, -hx, hx), rel.Y, math.clamp(rel.Z, -hz, hz))
	local point = zone.CFrame:PointToWorldSpace(rel)
	-- земля под точкой
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { folder, zone }
	for _, other in Players:GetPlayers() do
		if other.Character then table.insert(ignore, other.Character) end
	end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(Vector3.new(point.X, hrp.Position.Y + 12, point.Z), Vector3.new(0, -60, 0), params)
	local groundY = hit and hit.Position.Y or (hrp.Position.Y - 3)
	return Vector3.new(point.X, groundY, point.Z)
end

local function placeModel(model, ground, facing)
	local flat = Vector3.new(facing.X, ground.Y, facing.Z)
	if (flat - ground).Magnitude < 0.1 then flat = ground + Vector3.new(0, 0, -1) end
	model:PivotTo(CFrame.lookAt(ground, flat))
	-- низ модели ровно на землю
	local boxCf, boxSize = model:GetBoundingBox()
	local bottom = boxCf.Position.Y - boxSize.Y / 2
	model:PivotTo(model:GetPivot() + Vector3.new(0, ground.Y - bottom, 0))
end

function SellMoleService:_hasOre(player)
	return Services.InventoryService and Services.InventoryService:CountItems(player) > 0
end

function SellMoleService:_spawn(player, zone, hrp)
	local state = states[player]
	local model = buildModel()
	local ground = zoneSpot(zone, hrp)
	placeModel(model, ground, hrp.Position)
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("State", "Rise")
	model:SetAttribute("GroundY", ground.Y)
	model.Parent = folder
	state.Mole = model
	state.SpawnedAt = os.clock()
	local lines = cfg().Lines or { "Selling today?" }
	local held = player:GetAttribute("HeldOreUid")
	local heldStack = held and Services.InventoryService:GetStackByUid(player, held)
	task.delay(cfg().RiseSeconds or 0.55, function()
		if state.Mole ~= model or not player.Parent then return end
		remote:FireClient(player, "Open", {
			Npc = model,
			Line = lines[math.random(1, #lines)],
			Count = Services.InventoryService:CountItems(player),
			Capacity = Services.InventoryService:GetCapacity(player) == math.huge and -1 or Services.InventoryService:GetCapacity(player),
			HandCount = heldStack and heldStack.Count or 0,
		})
	end)
end

function SellMoleService:_burrow(player)
	local state = states[player]
	local model = state and state.Mole
	if not model then return end
	state.Mole = nil
	if model.Parent then
		model:SetAttribute("State", "Burrow")
		task.delay((cfg().BurrowSeconds or 0.5) + 1.6, function()
			if model.Parent then model:Destroy() end
		end)
	end
end

function SellMoleService:_onChoice(player, choice)
	local state = states[player]
	if not (state and state.Mole and not state.Busy) then return end
	local model = state.Mole
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp or (hrp.Position - model:GetPivot().Position).Magnitude > 22 then
		self:_burrow(player)
		state.NeedsExit = true
		return
	end
	if choice == "All" or choice == "Hand" then
		state.Busy = true
		local target = model:GetPivot().Position + Vector3.new(0, 2.5, 0)
		local sold = 0
		local ok, err = pcall(function()
			sold = Services.BankService:SellBackpackBatch(player, choice, target)
		end)
		if not ok then warn("[SellMoleService] продажа упала:", err) end
		if sold == 0 and choice == "Hand" and Services.NotifyService then
			Services.NotifyService:Show(player, "Take ore in your hand first!", { Duration = 2.5 })
		end
		state.Busy = false
		self:_burrow(player)
		if choice == "Hand" and self:_hasOre(player) then
			state.RespawnAt = os.clock() + 2 -- руда осталась - крот вернётся
		else
			state.NeedsExit = true
		end
	else
		self:_burrow(player)
		state.NeedsExit = true
	end
end

function SellMoleService:Init(services)
	Services = services
	remote = ReplicatedStorage.Shared:FindFirstChild("SellMoleRequest") or Instance.new("RemoteEvent")
	remote.Name = "SellMoleRequest"
	remote.Parent = ReplicatedStorage.Shared
	folder = workspace:FindFirstChild("SellMoles") or Instance.new("Folder")
	folder.Name = "SellMoles"
	folder.Parent = workspace
end

function SellMoleService:Start()
	if not (cfg().Enabled) then return end
	remote.OnServerEvent:Connect(function(player, action, value)
		if action == "Choice" and (value == "All" or value == "Hand" or value == "No") then
			self:_onChoice(player, value)
		elseif action == "Close" then
			local state = states[player]
			if state and state.Mole and not state.Busy then
				self:_burrow(player)
				state.NeedsExit = true
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local state = states[player]
		if state and state.Mole then state.Mole:Destroy() end
		states[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			local zone = Services.WorldService and Services.WorldService:GetSellZone()
			if not zone then continue end
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(function()
					local state = states[player]
					if not state then
						state = {}
						states[player] = state
					end
					local character = player.Character
					local hrp = character and character:FindFirstChild("HumanoidRootPart")
					local humanoid = character and character:FindFirstChildOfClass("Humanoid")
					local inZone = hrp and humanoid and humanoid.Health > 0 and Services.BankService:IsInZone(zone, hrp.Position)
					if not inZone then
						state.NeedsExit = false
						state.RespawnAt = nil
						if state.Mole and not state.Busy then
							self:_burrow(player)
						end
						return
					end
					if state.Mole or state.Busy or state.NeedsExit then return end
					if state.RespawnAt and os.clock() < state.RespawnAt then return end
					if player:GetAttribute("EconomyTransactionLocked") == true then return end
					if not self:_hasOre(player) then return end
					state.RespawnAt = nil
					self:_spawn(player, zone, hrp)
				end)
				if not ok then warn("[SellMoleService] цикл:", err) end
			end
		end
	end)
end

return SellMoleService
