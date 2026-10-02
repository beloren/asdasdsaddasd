--------------------------------------------------------------------------------
-- BoulderOutline (v20.132) — ЧЁРНАЯ ОБВОДКА НА ВАЛУНАХ (как на игроках).
-- Roblox рисует не больше ~31 Highlight одновременно, поэтому обводку
-- получают только ближайшие Config.Boulders.OutlineMaxCount валунов в
-- радиусе OutlineDistance (свои базовые и дикие). Highlight создаётся на
-- клиенте - у каждого игрока свои ближайшие.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local cfg = Config.Boulders or {}
if cfg.Outline == false then return end
local outlineColor = (Config.PlayerOutline and Config.PlayerOutline.Color) or Color3.new(0, 0, 0)

local player = Players.LocalPlayer
local boulders = {} -- [model] = true

local function isBoulder(model)
	return model:IsA("Model") and (model:GetAttribute("IsRubbleBoulder") == true or model.Name == "RubbleBoulder")
end

local function track(model)
	if boulders[model] or not isBoulder(model) then return end
	boulders[model] = true
	model.AncestryChanged:Connect(function(_, parent)
		if not parent then boulders[model] = nil end
	end)
end

for _, d in workspace:GetDescendants() do
	if d:IsA("Model") then track(d) end
end
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") then
		track(d)
		if not boulders[d] and d:GetAttribute("IsRubbleBoulder") == nil then
			task.delay(1, function() if d.Parent then track(d) end end)
		end
	end
end)

local function setOutline(model, on)
	local h = model:FindFirstChild("BoulderOutline")
	if on then
		if not h then
			h = Instance.new("Highlight")
			h.Name = "BoulderOutline"
			h.DepthMode = Enum.HighlightDepthMode.Occluded
			h.FillTransparency = 1
			h.FillColor = Color3.fromRGB(255, 0, 0)
			h.OutlineColor = outlineColor
			h.OutlineTransparency = 0
			h.Adornee = model
			h.Parent = model
		end
	elseif h then
		h:Destroy()
	end
end

local maxCount = cfg.OutlineMaxCount or 14
local maxDistance = cfg.OutlineDistance or 160
while true do
	task.wait(0.5)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local list = {}
	for model in boulders do
		if model.Parent then
			local ok, pivot = pcall(model.GetPivot, model)
			local distance = (ok and root) and (pivot.Position - root.Position).Magnitude or math.huge
			table.insert(list, { model, distance })
		else
			boulders[model] = nil
		end
	end
	table.sort(list, function(a, b) return a[2] < b[2] end)
	for index, entry in list do
		setOutline(entry[1], index <= maxCount and entry[2] <= maxDistance)
	end
end
