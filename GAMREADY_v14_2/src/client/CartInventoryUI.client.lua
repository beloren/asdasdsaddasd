--------------------------------------------------------------------------------
-- CartInventoryUI (LocalScript) v20.105 — ОКНО ТЕЛЕЖКИ (доп. действие R у
-- своей стоящей тележки, CartService:OpenInventory).
--
-- Вид — тот же, что у сундука-хранилища (Shared.UiBuilders.DecorStorageUi,
-- отдельная копия окна): сверху руда В ТЕЛЕЖКЕ стопками, снизу руда
-- рюкзака. Клик по стопке тележки - забрать в рюкзак, клик по руде рюкзака -
-- положить в тележку. Забранная руда Config.Cart.InventoryNoAutoDepositSeconds
-- (10 с) не переливается обратно сама - таймер внизу окна.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local OrePreview = require(ReplicatedStorage.Shared.OrePreview)
local UiKit = require(ReplicatedStorage.Shared.UiKit)
local Builder = require(ReplicatedStorage.Shared.UiBuilders.DecorStorageUi)
local okSfx, UiSfx = pcall(require, ReplicatedStorage.Shared.UiSfx)

local player = Players.LocalPlayer
local remote = ReplicatedStorage.Shared:WaitForChild("CartInventoryRequest", 60)
if not remote then return end

-- Своя копия окна сундука (два окна могут жить независимо).
local gui = Builder.Build()
UiKit.HideTemplates(gui)
gui.Name = "CartInventoryUi"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local dimmer = gui:WaitForChild("Dimmer")
local panel = gui:WaitForChild("Panel")
local panelScale = panel:WaitForChild("PanelScale")
local title = panel:WaitForChild("TitleBar"):WaitForChild("Title")
local closeButton = panel:WaitForChild("CloseButton")
local cartLabel = panel:WaitForChild("ChestLabel")
local takeAll = panel:WaitForChild("TakeAllButton")
local putAll = panel:WaitForChild("PutAllButton")
local bagGrid = panel:WaitForChild("BagGrid")
local emptyBag = panel:WaitForChild("EmptyBag")
local hint = panel:FindFirstChild("Hint")
local cellTemplate = panel:WaitForChild("Templates"):WaitForChild("Cell")

-- В тележке стопок может быть больше 10 - верхняя сетка прокручивается.
local cartGrid
do
	local old = panel:WaitForChild("ChestGrid")
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "CartGrid"
	scroll.Position = old.Position
	scroll.Size = old.Size
	scroll.ZIndex = old.ZIndex
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	for _, child in old:GetChildren() do child.Parent = scroll end
	scroll.Parent = panel
	old:Destroy()
	cartGrid = scroll
end
title.Text = "CART"
local putLabel = putAll:FindFirstChildWhichIsA("TextLabel", true)
if putLabel then putLabel.Text = "PUT ALL" end

local W, H = panel.Size.X.Offset, panel.Size.Y.Offset
local PAUSE = (Config.Cart and Config.Cart.InventoryNoAutoDepositSeconds) or 10
local HINT_TEXT = ("Click ore to move it. Ore you take out won't go back into the cart for %ds."):format(PAUSE)

local function sfx(name) if okSfx then pcall(UiSfx.play, name) end end

local isOpen = false
local cleanups = {}

local function clearCells()
	for _, cleanup in cleanups do pcall(cleanup) end
	cleanups = {}
	for _, holder in { cartGrid, bagGrid } do
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
	local color = Config.RarityColors[rarityOf(stack)] or Color3.fromRGB(200, 200, 200)
	if nameLabel then nameLabel.Text = nameOf(stack) end
	if count then count.Text = "x" .. tostring(stack.Count or 1) end
	if bar then
		bar.BackgroundColor3 = color
		bar.Visible = true
	end
	local stroke = cell:FindFirstChildWhichIsA("UIStroke")
	if stroke then stroke.Color = color end
	if preview then
		local view = Instance.new("Frame")
		view.Name = "OreView"
		view.BackgroundTransparency = 1
		view.AnchorPoint = preview.AnchorPoint
		view.Position = preview.Position
		view.Size = preview.Size
		view.ZIndex = preview.ZIndex
		view.Parent = cell
		preview.Visible = false
		local ok, mounted = pcall(OrePreview.Mount, view, stack)
		if not (ok and mounted) then
			local info = Config.OreByKey[stack.Ore]
			view.BackgroundTransparency = 0
			view.BackgroundColor3 = info and info.Color or Color3.fromRGB(150, 150, 160)
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent = view
		end
	end
	if onClick then cell.Activated:Connect(onClick) end
	cell.Parent = parent
	return cell
end

local function render(state)
	clearCells()
	local items = state.Items or {}
	cartLabel.Text = ("CART %d/%d"):format(tonumber(state.Count) or 0, tonumber(state.Capacity) or 0)
	for index, stack in items do
		makeCell(cartGrid, index, stack, function()
			sfx("UiButtonClick")
			remote:FireServer("Withdraw", stack.Key)
		end)
	end
	local backpack = state.Backpack or {}
	for index, stack in backpack do
		makeCell(bagGrid, index, stack, function()
			sfx("UiButtonClick")
			remote:FireServer("Deposit", stack.Uid)
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

local function ownCart()
	for _, model in workspace:GetDescendants() do
		if model:IsA("Model") and model:FindFirstChild("CartInventoryPrompt", true) then
			local prompt = model:FindFirstChild("CartInventoryPrompt", true)
			if prompt:GetAttribute("OwnerUserId") == player.UserId then return model end
		end
	end
	return nil
end
local currentCart = nil

local function close()
	if not isOpen then return end
	isOpen = false
	gui.Enabled = false
	clearCells()
	currentCart = nil
	sfx("UiMenuClose")
end

local function open(state)
	render(state)
	currentCart = ownCart()
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
	elseif action == "State" and typeof(state) == "table" and isOpen then
		render(state)
	elseif action == "Close" then
		close()
	end
end)

takeAll.Activated:Connect(function()
	sfx("UiButtonClick")
	remote:FireServer("WithdrawAll")
end)
putAll.Activated:Connect(function()
	sfx("UiButtonClick")
	remote:FireServer("DepositAll")
end)
closeButton.Activated:Connect(close)
dimmer.Activated:Connect(close)
UserInputService.InputBegan:Connect(function(input)
	if isOpen and input.KeyCode == Enum.KeyCode.Escape then close() end
end)

-- Отошёл от тележки / взял её в руки - окно закрывается; внизу - таймер
-- «руда не вернётся в тележку ещё N с».
task.spawn(function()
	while true do
		task.wait(0.25)
		if isOpen then
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			local far = not (currentCart and currentCart.Parent and hrp)
				or (hrp.Position - currentCart:GetPivot().Position).Magnitude > ((Config.Cart and Config.Cart.InventoryUseDistance) or 16) + 2
				or player:GetAttribute("CarryingCart") == true
			if far then close() end
			if hint then
				local left = (tonumber(player:GetAttribute("CartDepositPausedUntil")) or 0) - workspace:GetServerTimeNow()
				hint.Text = left > 0 and ("Taken ore stays in your backpack: %ds"):format(math.ceil(left)) or HINT_TEXT
			end
		end
	end
end)
