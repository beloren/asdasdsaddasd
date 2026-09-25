--------------------------------------------------------------------------------
-- SkinUI (LocalScript) — меню скинов v8 (Shared.SkinUiBuilder). Карточки
-- скинов кирки → экран скина: плюсы ▲ зелёным, минусы ▼ красным простыми
-- словами (Config.SkinBuffs / Config.SkinStats) → EQUIP / UNEQUIP.
-- Открывается из общего меню-книги (CollectionMenuOpenRequest "Skins").
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local UiMotion = require(ReplicatedStorage.Shared.UiMotion)
local UiSfx = require(ReplicatedStorage.Shared.UiSfx)
local Localization = require(ReplicatedStorage.Shared.Localization)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage.Shared:WaitForChild("SkinRequest")

local function tr(text, args)
	local ok, result = pcall(Localization.Translate, player.LocaleId, text, args)
	return ok and result or text
end

-- v20: меню собирается билдером (Shared.SkinUiBuilder → StarterGui/SkinUi).
local UiKit = require(ReplicatedStorage.Shared.UiKit)
local gui = require(ReplicatedStorage.Shared.UiRegistry).Get("SkinUi")
gui.ResetOnSpawn = false

local dimmer = gui:WaitForChild("Dimmer")
local panel = gui:WaitForChild("Panel")
local closeButton = panel:FindFirstChild("CloseButton", true)
local gridView = panel:FindFirstChild("GridView", true)
local grid = gridView:WaitForChild("Grid")
local cardTemplate = grid:WaitForChild("CardTemplate")
local detail = panel:FindFirstChild("DetailView", true)
local backButton = detail:WaitForChild("BackButton")
local previewCard = detail:WaitForChild("PreviewCard")
local nameLabel = detail:WaitForChild("Name")
local statsFrame = detail:WaitForChild("Stats")
local statTemplate = statsFrame:WaitForChild("StatTemplate")
local equipButton = detail:WaitForChild("EquipButton")

local RARITY_ORDER = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6 }
local state = { Owned = {}, Equipped = { Pickaxe = "" } }
local selectedId = nil

local function rarityColor(rarity)
	return Config.RarityColors and Config.RarityColors[rarity] or Color3.fromRGB(200, 200, 200)
end

local function imageFor(entry)
	local id = tonumber(entry.ImageId) or 0
	return id > 0 and ("rbxassetid://" .. id) or ""
end

local function resize()
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(800, 540)
	local scale = panel:FindFirstChild("ResponsiveScale")
	local baseWidth = panel:GetAttribute("BaseWidth") or 680
	local baseHeight = panel:GetAttribute("BaseHeight") or 470
	if scale then scale.Scale = math.min(1, (viewport.X - 24) / baseWidth, (viewport.Y - 40) / baseHeight) end
end

-- Строки баффов: сначала плюсы, потом минусы.
local function statLines(skinId)
	local buffs = Config.SkinBuffs and Config.SkinBuffs[skinId] or {}
	local lines = {}
	for stat, value in buffs do
		local info = Config.SkinStats and Config.SkinStats[stat]
		table.insert(lines, { Stat = stat, Value = value, Label = info and info.Label or stat })
	end
	table.sort(lines, function(a, b)
		if (a.Value > 0) ~= (b.Value > 0) then return a.Value > 0 end
		return math.abs(a.Value) > math.abs(b.Value)
	end)
	return lines
end

local function fillCard(card, entry)
	local image = card:FindFirstChild("Image")
	if image then image.Image = imageFor(entry) end
	local name = card:FindFirstChild("Name")
	if name then name.Text = entry.DisplayName end
	local rarity = card:FindFirstChild("Rarity")
	if rarity then
		rarity.Text = tr(string.upper(entry.Rarity or ""))
		rarity.TextColor3 = rarityColor(entry.Rarity)
	end
	local rarityStroke = card:FindFirstChild("RarityStroke") or card:FindFirstChild("SkinStroke")
	if rarityStroke then rarityStroke.Color = rarityColor(entry.Rarity) end
end

local function renderDetail()
	local entry
	for _, owned in state.Owned do
		if owned.Id == selectedId then entry = owned end
	end
	if not entry then return end
	fillCard(previewCard, entry)
	nameLabel.Text = entry.DisplayName
	nameLabel.TextColor3 = rarityColor(entry.Rarity):Lerp(Color3.new(1, 1, 1), 0.4)
	for _, child in statsFrame:GetChildren() do
		if child:IsA("TextLabel") and child ~= statTemplate then child:Destroy() end
	end
	local lines = statLines(entry.Id)
	-- v20.28: роль кирки первой строкой (Config.SkinRoles).
	local role = Config.SkinRoles and Config.SkinRoles[entry.Id]
	if role then
		local line = statTemplate:Clone()
		line.Name = "Role"
		line.LayoutOrder = 0
		line.Text = tr(role):upper()
		line.TextColor3 = Color3.fromRGB(255, 225, 150)
		line.Visible = true
		line.Parent = statsFrame
	end
	if #lines == 0 then
		local line = statTemplate:Clone()
		line.Text = tr("No bonuses — pure style")
		line.TextColor3 = Color3.fromRGB(190, 195, 215)
		line.Visible = true
		line.Parent = statsFrame
	end
	for index, info in lines do
		local line = statTemplate:Clone()
		line.Name = "Stat" .. index
		line.LayoutOrder = index
		local percent = math.floor(math.abs(info.Value) * 100 + 0.5)
		if info.Value > 0 then
			line.Text = ("+%d%%  %s"):format(percent, tr(info.Label))
			line.TextColor3 = Color3.fromRGB(110, 255, 150)
		else
			line.Text = ("-%d%%  %s"):format(percent, tr(info.Label))
			line.TextColor3 = Color3.fromRGB(255, 110, 110)
		end
		line.Visible = true
		line.Parent = statsFrame
	end
	local equipped = state.Equipped and state.Equipped.Pickaxe == entry.Id
	local text = equipButton:FindFirstChild("Text")
	if text then text.Text = equipped and tr("UNEQUIP") or tr("EQUIP") end
	if equipButton:GetAttribute("UiSkin") then
		UiKit.ApplySkin(equipButton, equipped and "Button_Dark" or "Button_Green")
	else
		equipButton.BackgroundColor3 = equipped and Color3.fromRGB(95, 98, 110) or Color3.fromRGB(70, 200, 95)
	end
end

local function showGrid()
	selectedId = nil
	detail.Visible = false
	gridView.Visible = true
end

local function showDetail(skinId)
	UiSfx.play("UiButtonClick")
	selectedId = skinId
	gridView.Visible = false
	detail.Visible = true
	renderDetail()
end

local function renderGrid()
	for _, child in grid:GetChildren() do
		if child:IsA("GuiButton") and child ~= cardTemplate then child:Destroy() end
	end
	local list = {}
	for _, entry in state.Owned or {} do
		if entry.Kind == "Pickaxe" then table.insert(list, entry) end
	end
	table.sort(list, function(a, b)
		local ra, rb = RARITY_ORDER[a.Rarity] or 0, RARITY_ORDER[b.Rarity] or 0
		if ra ~= rb then return ra > rb end
		return a.DisplayName < b.DisplayName
	end)
	for index, entry in list do
		local card = cardTemplate:Clone()
		card.Name = "Card_" .. entry.Id
		card.LayoutOrder = index
		fillCard(card, entry)
		local badge = card:FindFirstChild("Equipped")
		if badge then badge.Visible = state.Equipped and state.Equipped.Pickaxe == entry.Id end
		card.Visible = true
		card.Activated:Connect(function() showDetail(entry.Id) end)
		card.Parent = grid
	end
	-- v20.27: ещё не открытые скины — после своих, карточкой «?»: видна
	-- только редкость (цвет рамки), имя и картинка скрыты, нажать нельзя.
	local locked = {}
	for _, entry in state.Locked or {} do
		if entry.Kind == "Pickaxe" then table.insert(locked, entry) end
	end
	table.sort(locked, function(a, b)
		local ra, rb = RARITY_ORDER[a.Rarity] or 0, RARITY_ORDER[b.Rarity] or 0
		if ra ~= rb then return ra < rb end
		return a.Id < b.Id
	end)
	for index, entry in locked do
		local card = cardTemplate:Clone()
		card.Name = "Locked_" .. entry.Id
		card.LayoutOrder = #list + index
		fillCard(card, { DisplayName = "???", Rarity = entry.Rarity, ImageId = 0 })
		local badge = card:FindFirstChild("Equipped")
		if badge then badge.Visible = false end
		local image = card:FindFirstChild("Image")
		if image then image.ImageTransparency = 1 end
		local mark = Instance.new("TextLabel")
		mark.Name = "LockedMark"
		mark.BackgroundTransparency = 1
		-- «?» там же, где картинка скина, и ПОВЕРХ затемнения — яркий.
		mark.Size = image and image.Size or UDim2.fromScale(0.6, 0.55)
		mark.AnchorPoint = image and image.AnchorPoint or Vector2.new(0.5, 0.5)
		mark.Position = image and image.Position or UDim2.fromScale(0.5, 0.42)
		UiKit.StyleText(mark, "Title")
		mark.Text = "?"
		mark.TextScaled = true
		mark.TextColor3 = rarityColor(entry.Rarity):Lerp(Color3.new(1, 1, 1), 0.35)
		mark.ZIndex = (image and image.ZIndex or card.ZIndex) + 20
		mark.Parent = card
		-- Затемнение и без нажатия.
		card.Active = false
		card.AutoButtonColor = false
		card.Selectable = false
		card:SetAttribute("DisableGlobalHover", true)
		local shade = Instance.new("Frame")
		shade.Name = "LockedShade"
		shade.BackgroundColor3 = Color3.new(0, 0, 0)
		shade.BackgroundTransparency = 0.45
		shade.BorderSizePixel = 0
		shade.Size = UDim2.fromScale(1, 1)
		shade.ZIndex = mark.ZIndex - 1 -- над картинкой и подписями, под «?»
		local corner = card:FindFirstChildOfClass("UICorner")
		if corner then corner:Clone().Parent = shade end
		shade.Parent = card
		card.Visible = true
		card.Parent = grid
	end
	if selectedId and detail.Visible then renderDetail() end
end

local function open()
	resize()
	UiSfx.play("UiMenuOpen")
	dimmer.Visible = true
	showGrid()
	renderGrid()
	UiMotion.Open(panel)
	remote:FireServer("RequestState")
end
local function close()
	UiMotion.Close(panel)
	dimmer.Visible = false
end
closeButton.Activated:Connect(close)
dimmer.Activated:Connect(close)
backButton.Activated:Connect(function()
	UiSfx.play("UiCancel")
	showGrid()
end)
equipButton.Activated:Connect(function()
	if not selectedId then return end
	UiSfx.play("UiButtonClick")
	local equipped = state.Equipped and state.Equipped.Pickaxe == selectedId
	remote:FireServer("Equip", "Pickaxe", equipped and "" or selectedId)
end)

local openRequest = ReplicatedStorage.Shared:FindFirstChild("CollectionMenuOpenRequest")
if not openRequest then
	openRequest = Instance.new("BindableEvent")
	openRequest.Name = "CollectionMenuOpenRequest"
	openRequest.Parent = ReplicatedStorage.Shared
end
openRequest.Event:Connect(function(target)
	if target == "Skins" then open() end
end)

remote.OnClientEvent:Connect(function(command, payload)
	if command == "State" and type(payload) == "table" then
		state = payload
		renderGrid()
	end
end)
remote:FireServer("RequestState")
