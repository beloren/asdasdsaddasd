--------------------------------------------------------------------------------
-- GamepassNpcService (v20.131) — НПС, КОТОРЫЙ ОТКРЫВАЕТ МАГАЗИН ГЕЙМПАССОВ.
-- Один на всю карту (Config.GamepassNpc).
--
-- КАК ПОСТАВИТЬ:
--   1. В Workspace положи деталь "GamepassNpcMarker" - НПС встанет ступнями
--      на её нижнюю грань.
--   2. (необязательно) деталь "GamepassNpcMarkerLook" - НПС повернётся к ней
--      лицом. Без неё смотрит туда же, куда передняя грань маркера.
--   Маркеры в игре становятся невидимыми и без коллизии.
--   Модель: ReplicatedStorage.Assets.GamepassNPC (любой риг/модель), или
--   модель "GamepassNPC", поставленная на карту руками (она главнее маркера
--   по месту, только получает промпт). Нет ни того ни другого - плейсхолдер.
--   Нет маркера и модели на карте - НПС не появляется (warn в Output).
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)
local NpcNameTag = require(ReplicatedStorage.Shared.NpcNameTag)
local NpcIdle = require(ReplicatedStorage.Shared.NpcIdle) -- v20.132: стойка как у продавца островов

local GamepassNpcService = {}
local remote
local lastTrigger = {}

local function cfg()
	return Config.GamepassNpc or {}
end

local function hideMarker(part)
	if part and part:IsA("BasePart") then
		part.Transparency = 1
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Anchored = true
		for _, child in part:GetChildren() do
			if child:IsA("Decal") or child:IsA("Texture") or child:IsA("SurfaceGui") or child:IsA("BillboardGui") then
				child:Destroy()
			end
		end
	end
end

local function placeholder()
	local model = PlaceholderFactory.ShopNPC()
	model.Name = "GamepassNPC"
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and (part.Name == "Torso" or part.Name == "Arm") then
			part.Color = Color3.fromRGB(255, 200, 60)
		end
	end
	return model
end

function GamepassNpcService:_spawn()
	local c = cfg()
	local marker = workspace:FindFirstChild(c.MarkerName or "GamepassNpcMarker", true)
	local look = workspace:FindFirstChild((c.MarkerName or "GamepassNpcMarker") .. "Look", true)
	local npc = workspace:FindFirstChild(c.ModelName or "GamepassNPC", true)
	if npc and not npc:IsA("Model") then npc = nil end

	if not npc then
		if not (marker and marker:IsA("BasePart")) then
			warn("[GamepassNpcService] Нет Workspace.GamepassNpcMarker - НПС магазина геймпассов не поставлен")
			return
		end
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local asset = assets and assets:FindFirstChild(c.ModelName or "GamepassNPC", true)
		if asset and asset:IsA("Model") then
			npc = asset:Clone()
		else
			npc = placeholder()
			for _, part in npc:GetDescendants() do
				if part:IsA("BasePart") then part.Anchored = true; part.CanCollide = false end
			end
		end
		npc.Name = c.ModelName or "GamepassNPC"
		if not npc.PrimaryPart then
			npc.PrimaryPart = npc:FindFirstChild("HumanoidRootPart", true) or npc:FindFirstChildWhichIsA("BasePart", true)
		end
		local facing = marker.CFrame.LookVector
		if look and look:IsA("BasePart") then
			facing = look.Position - marker.Position
		end
		npc.Parent = workspace
		PlaceholderFactory.StandOnMarker(npc, marker, facing)
	end
	hideMarker(marker)
	hideMarker(look)

	local root = npc.PrimaryPart or npc:FindFirstChild("HumanoidRootPart", true) or npc:FindFirstChildWhichIsA("BasePart", true)
	if not root then
		warn("[GamepassNpcService] у модели GamepassNPC нет деталей")
		return
	end
	if root:IsA("BasePart") then root.Anchored = true end

	task.defer(NpcIdle.Play, npc, "GamepassNPC")
	local title = c.Name or "Gamepass Shop"
	pcall(NpcNameTag.Ensure, npc, title)
	local prompt = npc:FindFirstChild("GamepassPrompt", true)
	if not (prompt and prompt:IsA("ProximityPrompt")) then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "GamepassPrompt"
		prompt.Parent = root
	end
	prompt.ObjectText = title
	prompt.ActionText = c.ActionText or "SHOP"
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = c.PromptDistance or 10
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute("PromptKind", "Talk")
	prompt:SetAttribute("PromptColor", "Gold")
	prompt.Triggered:Connect(function(player)
		local now = os.clock()
		if now - (lastTrigger[player] or 0) < 0.6 then return end
		lastTrigger[player] = now
		remote:FireClient(player, "Open")
	end)
end

function GamepassNpcService:Init()
	remote = ReplicatedStorage.Shared:FindFirstChild("GamepassNpcEvent") or Instance.new("RemoteEvent")
	remote.Name = "GamepassNpcEvent"
	remote.Parent = ReplicatedStorage.Shared
	game:GetService("Players").PlayerRemoving:Connect(function(player) lastTrigger[player] = nil end)
end

function GamepassNpcService:Start()
	if cfg().Enabled == false then return end
	task.spawn(function()
		-- карта (и маркер) могут подгрузиться чуть позже сервисов
		for _ = 1, 10 do
			if workspace:FindFirstChild(cfg().MarkerName or "GamepassNpcMarker", true)
				or workspace:FindFirstChild(cfg().ModelName or "GamepassNPC", true) then
				break
			end
			task.wait(1)
		end
		local ok, err = pcall(function() self:_spawn() end)
		if not ok then warn("[GamepassNpcService] " .. tostring(err)) end
	end)
end

return GamepassNpcService
