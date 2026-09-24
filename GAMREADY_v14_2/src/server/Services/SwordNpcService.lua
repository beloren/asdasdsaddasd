local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SwordNpcService = {}
local Services
local remote
local configuredNpcs = setmetatable({}, { __mode = "k" })
local lastTrigger = {}
local activeTalks = {}
local TALK_WATCHDOG = 45

local function setupNpc(npc)
	if configuredNpcs[npc] or not npc:IsA("Model") then return false end
	local root = npc.PrimaryPart or npc:FindFirstChild("HumanoidRootPart", true) or npc:FindFirstChildWhichIsA("BasePart", true)
	if not root then
		warn("[SwordNpcService] Workspace/SwordNPC не содержит BasePart")
		return false
	end
	npc.PrimaryPart = root
	local prompt = npc:FindFirstChild("SwordPrompt", true) or npc:FindFirstChildWhichIsA("ProximityPrompt", true)
	if not (prompt and prompt:IsA("ProximityPrompt")) then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "SwordPrompt"
		prompt.Parent = root
	end
	prompt.ObjectText = "Zavtrack"
	prompt.ActionText = "TALK"
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 10
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute("PromptKind", "Talk")
	prompt:SetAttribute("PromptColor", "Blue")
	configuredNpcs[npc] = true
	prompt.Triggered:Connect(function(player)
		if player:GetAttribute("UpgradeInProgress") == true then return end
		local now = os.clock()
		if now - (lastTrigger[player] or 0) < 1 then return end
		lastTrigger[player] = now
		prompt.Enabled = false
		activeTalks[player] = { Npc = npc, Prompt = prompt }
		remote:FireClient(player, "Begin", npc)
		task.delay(TALK_WATCHDOG, function()
			local active = activeTalks[player]
			if active and active.Prompt == prompt then
				activeTalks[player] = nil
				prompt.Enabled = true
			end
		end)
	end)
	return true
end

function SwordNpcService:Init(services)
	Services = services
	remote = ReplicatedStorage.Shared:FindFirstChild("SwordNpcRequest") or Instance.new("RemoteEvent")
	remote.Name = "SwordNpcRequest"
	remote.Parent = ReplicatedStorage.Shared
	remote.OnServerEvent:Connect(function(player, action)
		if action == "Close" then
			local active = activeTalks[player]
			if active and active.Prompt then active.Prompt.Enabled = true end
			activeTalks[player] = nil
			return
		end
		if action ~= "Claim" then return end
		local active = activeTalks[player]
		if not active then return end
		local character = player.Character
		local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
		local npcRoot = active.Npc and active.Npc.PrimaryPart
		if not playerRoot or not npcRoot or (playerRoot.Position - npcRoot.Position).Magnitude > 16 then
			if active.Prompt then active.Prompt.Enabled = true end
			activeTalks[player] = nil
			return
		end
		activeTalks[player] = nil
		local _, result = Services.SkinService:GrantNpcSkin(player, "Frostmorn")
		if active.Prompt then active.Prompt.Enabled = true end
		remote:FireClient(player, "Result", result)
	end)
end

function SwordNpcService:Start()
	local found = false
	for _, descendant in workspace:GetDescendants() do
		if descendant.Name == "SwordNPC" and descendant:IsA("Model") then
			found = true
			setupNpc(descendant)
		end
	end
	workspace.DescendantAdded:Connect(function(descendant)
		local candidate = descendant.Name == "SwordNPC" and descendant or descendant:FindFirstAncestor("SwordNPC")
		if candidate and candidate:IsA("Model") then task.defer(setupNpc, candidate) end
	end)
	if not found then warn("[SwordNpcService] SwordNPC пока не найден в Workspace; сервис подключит его при появлении") end
end

function SwordNpcService:CleanupPlayer(player)
	lastTrigger[player] = nil
	local active = activeTalks[player]
	if active and active.Prompt then active.Prompt.Enabled = true end
	activeTalks[player] = nil
end

return SwordNpcService
