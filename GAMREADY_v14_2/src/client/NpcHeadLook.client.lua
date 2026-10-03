--------------------------------------------------------------------------------
-- NpcHeadLook (LocalScript) v20.152 — НПС ПОВОРАЧИВАЮТ ГОЛОВУ К ИГРОКУ.
-- Подошёл ближе Config.NpcHeadLook.Distance - НПС плавно смотрит на тебя
-- (поворот и наклон головы через сустав шеи Neck, R15 и R6). Отошёл или
-- зашёл за спину - голова плавно возвращается. Делается на клиенте: каждый
-- игрок видит, что НПС смотрит именно на него, сервер не нагружается.
-- Какие НПС: тег "NpcHeadLook" (ставит NpcIdle) + модели с именами из
-- Config.NpcHeadLook.Names. У модели без сустава Neck (кубики-заглушка)
-- ничего не происходит. Атрибут NoHeadLook = true на модели - выключить.
--------------------------------------------------------------------------------
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local CFG = Config.NpcHeadLook or {}
if CFG.Enabled == false then return end

local player = Players.LocalPlayer
local DISTANCE = CFG.Distance or 18
local MAX_YAW = math.rad(CFG.MaxYaw or 70)
local MAX_PITCH = math.rad(CFG.MaxPitch or 25)
local GIVE_UP_YAW = math.rad(CFG.GiveUpYaw or 120) -- игрок за спиной - не выворачиваем шею
local SPEED = CFG.TurnSpeed or 6

local NAMES = {}
for _, name in CFG.Names or { "MinerNPC", "UpgradeShopNPC", "RebirthNPC", "ShopNPC", "BankMerchant", "IslandKeeperNPC", "GamepassNPC" } do
	NAMES[name] = true
end

local npcs = {} -- [Model] = { Neck, BaseC0, Yaw, Pitch }

local function findNeck(model)
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and d.Name == "Neck" and d.Part0 and d.Part1 then return d end
	end
	return nil
end

local function track(model)
	if not (model and model:IsA("Model")) or npcs[model] then return end
	if model:GetAttribute("NoHeadLook") == true then return end
	if Players:GetPlayerFromCharacter(model) then return end
	-- сустав мог появиться позже (модель грузится по частям)
	task.spawn(function()
		local neck
		for _ = 1, 20 do
			neck = findNeck(model)
			if neck or not model.Parent then break end
			task.wait(0.5)
		end
		if neck and model.Parent and not npcs[model] then
			npcs[model] = { Neck = neck, BaseC0 = neck.C0, Yaw = 0, Pitch = 0 }
		end
	end)
end

local function consider(instance)
	if instance:IsA("Model") and NAMES[instance.Name] then track(instance) end
end

for _, model in CollectionService:GetTagged("NpcHeadLook") do track(model) end
CollectionService:GetInstanceAddedSignal("NpcHeadLook"):Connect(track)
for _, d in workspace:GetDescendants() do consider(d) end
workspace.DescendantAdded:Connect(consider)

local function approach(current, target, dt)
	return current + (target - current) * math.min(1, dt * SPEED)
end

RunService.RenderStepped:Connect(function(dt)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local eye = head and head.Position
	for model, entry in npcs do
		local neck = entry.Neck
		if not (model.Parent and neck.Parent and neck.Part0 and neck.Part1) then
			npcs[model] = nil
		else
			local targetYaw, targetPitch = 0, 0
			local npcHead = neck.Part1
			if eye and (npcHead.Position - eye).Magnitude <= DISTANCE then
				local dir = neck.Part0.CFrame:VectorToObjectSpace(eye - npcHead.Position)
				local yaw = math.atan2(-dir.X, -dir.Z)
				if math.abs(yaw) <= GIVE_UP_YAW then
					targetYaw = math.clamp(yaw, -MAX_YAW, MAX_YAW)
					local flat = math.sqrt(dir.X * dir.X + dir.Z * dir.Z)
					targetPitch = math.clamp(math.atan2(dir.Y, flat), -MAX_PITCH, MAX_PITCH)
				end
			end
			entry.Yaw = approach(entry.Yaw, targetYaw, dt)
			entry.Pitch = approach(entry.Pitch, targetPitch, dt)
			if math.abs(entry.Yaw) > 0.001 or math.abs(entry.Pitch) > 0.001 or neck.C0 ~= entry.BaseC0 then
				local base = entry.BaseC0
				-- поворот в пространстве туловища вокруг точки сустава шеи
				neck.C0 = CFrame.new(base.Position) * CFrame.Angles(0, entry.Yaw, 0) * CFrame.Angles(entry.Pitch, 0, 0) * base.Rotation
			end
		end
	end
end)
