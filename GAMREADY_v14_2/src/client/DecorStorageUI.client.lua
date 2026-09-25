--------------------------------------------------------------------------------
-- DecorStorageUI (LocalScript) v20.22 — окно сундука-хранилища на базе.
--
-- Промпт OPEN у сундука (BaseDecorService) → сервер шлёт "Open" с
-- состоянием: ячейки сундука (Items), руда из рюкзака (Backpack).
-- Клик по руде рюкзака — положить стопку в сундук, клик по ячейке сундука —
-- забрать в рюкзак. PUT ALL / TAKE ALL — всё сразу. Сервер после каждого
-- действия присылает "State"; отошёл далеко — "Close".
-- Окно собирает Shared.UiBuilders.DecorStorageUi (StarterGui/DecorStorageUi).
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local ItemPreview = require(ReplicatedStorage.Shared.ItemPreview)
local Builder = require(ReplicatedStorage.Shared.UiBuilders.DecorStorageUi)
local okSfx, UiSfx = pcall(require, ReplicatedStorage.Shared.UiSfx)

local player = Players.LocalPlayer
local remote = ReplicatedStorage.Shared:WaitForChild("DecorStorageRequest", 60)
if not remote then return end

local gui = require(ReplicatedStorage.Shared.UiRegistry).Get("DecorStorageUi")
gui.Enabled = false
local dimmer = gui:WaitForChild("Dimmer")
local panel = gui:WaitForChild("Panel")
local panelScale = panel:WaitForChild("PanelScale")
local title = panel:WaitForChild("TitleBar"):WaitForChild("Title")
local closeButton = panel:WaitForChild("CloseButton")
local chestLabel = panel:WaitForChild("ChestLabel")
local takeAll = panel:WaitForChild("TakeAllButton")
local chestGrid = panel:WaitForChild("ChestGrid")
local putAll = panel:WaitForChild("PutAllButton")
local bagGrid = panel:WaitForChild("BagGrid")
local emptyBag = panel:WaitForChild("EmptyBag")
local cellTemplate = panel:WaitForChild("Templates"):WaitForChild("Cell")

local W, H = panel.Size.X.Offset, panel.Size.Y.Offset

local function sfx(name) if okSfx then pcall(UiSfx.play, name) end end

local currentUid = nil
local currentModel = nil
local isOpen = false
local cleanups = {}

local function clearCells()
	for _, cleanup in cleanups do pcall(cleanup) end
	cleanups = {}
	for _, holder in { chestGrid, bagGrid } do
		for _, child in holder:GetChildren() do
			if child:IsA("GuiObject") and child:GetAttribute("StorageCell") then child:Destroy() end
		end
	end
end

local function rarityOf(stack)
	local info = Config.OreByKey[stack.Ore]
	return (Config.OreRarityFor and Config.OreRarityFor(stack.Ore, stack.Tier)) or (info and info.Rarity) or "Common"
end

local function nameOf(stack)
	local info = Config.OreByKey[stack.Ore]
	local name = info and info.DisplayName or tostring(stack.Ore)
	return stack.Smelted and (name .. " Ingot") or name
end

local function makeCell(parent, order, stack, onClick)
	local cell = cellTemplate:Clone()
	cell.Name = "Cell" .. order
	cell.LayoutOrder = order
	cell.Visible = true
	cell:SetAttribute("StorageCell", true)
	local preview = cell:FindFirstChild("Preview")
	local nameLabel = cell:FindFirstChild("ItemName")
	local count = cell:FindFirstChild("Count")
	local bar = cell:FindFirstChild("RarityBar")
	if stack then
		local rarity = rarityOf(stack)
		local color = Config.RarityColors[rarity] or Color3.fromRGB(200, 200, 200)
		if nameLabel then nameLabel.Text = nameOf(stack) end
		if count then count.Text = "x" .. tostring(stack.Count or 1) end
		if bar then
			bar.BackgroundColor3 = color
			bar.Visible = true
		end
		local stroke = cell:FindFirstChildWhichIsA("UIStroke")
		if stroke then stroke.Color = color end
		if preview and preview:IsA("ViewportFrame") then
			local mutations = nil
			if typeof(stack.Mutations) == "string" and stack.Mutations ~= "" then
				mutations = string.split(stack.Mutations, ",")
			end
			local ok, cleanup = pcall(ItemPreview.Mount, preview, { Kind = "Ore", OreId = stack.Ore, Mutations = mutations }, { Spin = false, Tilt = 18 })
			if ok and cleanup then table.insert(cleanups, cleanup) end
		end
	else
		if nameLabel then nameLabel.Text = "" end
		if count then count.Text = "" end
		if bar then bar.Visible = false end
		cell.ImageTransparency = math.max(cell.ImageTransparency, 0.35)
	end
	if onClick then
		cell.Activated:Connect(onClick)
	end
	cell.Parent = parent
	return cell
end

local function render(state)
	clearCells()
	currentUid = state.Uid
	title.Text = string.upper(tostring(state.Name or "Storage Chest"))
	local slots = tonumber(state.Slots) or 10
	local items = state.Items or {}
	chestLabel.Text = ("CHEST %d/%d"):format(#items, slots)
	for index = 1, slots do
		local stack = items[index]
		makeCell(chestGrid, index, stack, stack and function()
			sfx("UiButtonClick")
			remote:FireServer("Withdraw", currentUid, index)
		end or nil)
	end
	local backpack = state.Backpack or {}
	for index, stack in backpack do
		makeCell(bagGrid, index, stack, function()
			sfx("UiButtonClick")
			remote:FireServer("Deposit", currentUid, stack.Uid)
		end)
	end
	emptyBag.Visible = #backpack == 0
	putAll.Visible = #backpack > 0
	takeAll.Visible = #items > 0
end

local function fitScale()
	local camera = workspace.CurrentCamera
	local v = camera and camera.ViewportSize or Vector2.new(1280, 720)
	return math.min(1, (v.X - 20) / W, (v.Y - 20) / H)
end

local function findModel(uid)
	for _, model in workspace:GetDescendants() do
		if model:IsA("Model") and model:GetAttribute("BaseDecorUid") == uid and model:GetAttribute("OwnerUserId") == player.UserId then
			return model
		end
	end
	return nil
end

local function close()
	if not isOpen then return end
	isOpen = false
	gui.Enabled = false
	clearCells()
	currentUid, currentModel = nil, nil
	sfx("UiMenuClose")
end

local function open(state)
	render(state)
	currentModel = findModel(state.Uid)
	if not isOpen then
		isOpen = true
		gui.Enabled = true
		local target = fitScale()
		panelScale.Scale = target * 0.85
		TweenService:Create(panelScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
		sfx("UiMenuOpen")
	end
end

remote.OnClientEvent:Connect(function(action, state)
	if action == "Open" and typeof(state) == "table" then
		open(state)
	elseif action == "State" and typeof(state) == "table" and isOpen and state.Uid == currentUid then
		render(state)
	elseif action == "Close" then
		close()
	end
end)

takeAll.Activated:Connect(function()
	if currentUid then
		sfx("UiButtonClick")
		remote:FireServer("WithdrawAll", currentUid)
	end
end)
putAll.Activated:Connect(function()
	if currentUid then
		sfx("UiButtonClick")
		remote:FireServer("DepositAll", currentUid)
	end
end)
closeButton.Activated:Connect(close)
dimmer.Activated:Connect(close)
UserInputService.InputBegan:Connect(function(input)
	if isOpen and input.KeyCode == Enum.KeyCode.Escape then close() end
end)

-- Отошёл от сундука (или его убрали) — окно закрывается само.
task.spawn(function()
	while true do
		task.wait(0.5)
		if isOpen then
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			local far = not (currentModel and currentModel.Parent and hrp)
				or (hrp.Position - currentModel:GetPivot().Position).Magnitude > ((Config.Placeables.Storage or {}).UseDistance or 14) + 2
			if far then close() end
		end
	end
end)
