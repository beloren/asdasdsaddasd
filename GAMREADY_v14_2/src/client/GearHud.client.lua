--------------------------------------------------------------------------------
-- GearHud (LocalScript) — снаряжение v8: слоты динамита и сундуков слева,
-- прицел и клик «использовать», окно лута. Логика — на сервере
-- (GearService); здесь только ввод и картинка.
--   • клик по слоту (или G — динамит) — взять/убрать из руки;
--   • с динамитом: клик по валуну — поставить, в другое место — бросить;
--   • с сундуком: клик по земле своей базы — поставить (идёт таймер).
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Localization = require(ReplicatedStorage.Shared.Localization)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function tr(text, args)
	local ok, result = pcall(Localization.Translate, player.LocaleId, text, args)
	return ok and result or text
end

-- v20: StarterGui/GearUi (tools/BuildAllUI.lua); нет — соберётся билдером.
local gui = require(ReplicatedStorage.Shared.UiRegistry).Get("GearUi")
if not gui or (tonumber(gui:GetAttribute("BuilderVersion")) or 0) < (Config.Chests.GearUiVersion or 1) then
	if gui then gui:Destroy() end
	gui = require(ReplicatedStorage.Shared.GearUiBuilder).Build()
	gui.Parent = playerGui
end
gui.ResetOnSpawn = false
local timerTemplate = gui:FindFirstChild("ChestTimerTemplate")
if timerTemplate then timerTemplate.Enabled = false end

local bar = gui:WaitForChild("GearBar")
local slotTemplate = bar:WaitForChild("SlotTemplate")
-- v9: снаряжение переехало в инвентарь/хотбар (InventoryUI) — левая
-- панель больше не показывается. Здесь остаются прицел, G и окно лута.
bar.Visible = false
local aimHint = gui:FindFirstChild("AimHint")
local lootPopup = gui:FindFirstChild("LootPopup")

local remote = ReplicatedStorage.Shared:WaitForChild("GearRequest", 30)
if not remote then
	warn("[GearHud] GearRequest не появился — снаряжение отключено на клиенте.")
	return
end

-- v12: первой идёт упаковка тележки — её постановка это первое, что игрок
-- вообще делает в игре (см. Config.CartPackage).
local ORDER = { "CartPackage", "Dynamite", "Dynamite_Medium", "Dynamite_Mega", "Chest_Common", "Chest_Rare", "Chest_Epic", "Chest_Legendary" }
local ICONS = { CartPackage = "🛒", Dynamite = "🧨", Chest_Common = "📦", Chest_Rare = "🎁", Chest_Epic = "💜", Chest_Legendary = "👑" }
local KEYS = { Dynamite = "G" }

local state = { Gear = {}, Held = "" }
local slots = {} -- [key] = TextButton

local function colorFor(key)
	if key == "CartPackage" then return Color3.fromRGB(120, 210, 255) end
	local rarity = key:match("^Chest_(%a+)$")
	local info = rarity and Config.Chests.Types[rarity]
	return info and info.Color or Color3.fromRGB(230, 70, 60)
end

local function slotFor(key)
	local slot = slots[key]
	if slot then return slot end
	slot = slotTemplate:Clone()
	slot.Name = "Slot_" .. key
	slot.LayoutOrder = table.find(ORDER, key) or 99
	local icon = slot:FindFirstChild("Icon")
	local image = slot:FindFirstChild("Image")
	local customImage = gui:GetAttribute("Icon_" .. key)
	if image and typeof(customImage) == "string" and customImage ~= "" then
		image.Image = customImage
		if icon then icon.Visible = false end
	elseif icon then
		icon.Text = ICONS[key] or "?"
	end
	local keyLabel = slot:FindFirstChild("Key")
	if keyLabel then keyLabel.Text = KEYS[key] or "" end
	local border = slot:FindFirstChild("Border")
	if border then border.Color = colorFor(key):Lerp(Color3.new(0, 0, 0), 0.4) end
	slot.Activated:Connect(function()
		remote:FireServer("Equip", key)
	end)
	slot.Parent = bar
	slots[key] = slot
	return slot
end

-- v20.5: ПОДСКАЗКА ПРЕДМЕТА В РУКЕ (кроме руды): название + «что делает ·
-- как применить» (Shared.ItemHints). Упаковку тележки подсказывает её
-- собственный предпросмотр (CartPlacement) — здесь не дублируем. Кирка —
-- только первые PICKAXE_HINT_SECONDS после того, как её взяли.
local ItemHints = require(ReplicatedStorage.Shared.ItemHints)
local hintTitle = aimHint and aimHint:FindFirstChild("Title")
local hintText = aimHint and aimHint:FindFirstChild("Text")
local PICKAXE_HINT_SECONDS = 4
local pickaxeHintUntil = 0

local function showHint(hint)
	if not aimHint then return end
	if not hint then
		aimHint.Visible = false
		return
	end
	if hintTitle and hintText then
		hintTitle.Text = tr(hint.Title)
		hintTitle.TextColor3 = hint.Color
		hintText.Text = ("%s  ·  %s"):format(tr(hint.What), tr(hint.How))
		local stroke = aimHint:FindFirstChild("SkinStroke")
		if stroke then stroke.Color = hint.Color end
	elseif aimHint:IsA("TextLabel") then
		aimHint.Text = ("%s — %s · %s"):format(tr(hint.Title), tr(hint.What), tr(hint.How))
	end
	aimHint.Visible = true
end

local function refreshHint()
	local held = player:GetAttribute("HeldGear") or ""
	if held ~= "" then
		if held == ((Config.CartPackage and Config.CartPackage.GearKey) or "CartPackage") then
			showHint(nil)
		else
			showHint(ItemHints.For(held))
		end
		return
	end
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if tool and os.clock() < pickaxeHintUntil then
		showHint(ItemHints.Pickaxe(player:GetAttribute("PickaxeTier")))
	else
		showHint(nil)
	end
end

local function watchPickaxe(character)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			pickaxeHintUntil = os.clock() + PICKAXE_HINT_SECONDS
			refreshHint()
			task.delay(PICKAXE_HINT_SECONDS + 0.05, refreshHint)
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then refreshHint() end
	end)
end
if player.Character then watchPickaxe(player.Character) end
player.CharacterAdded:Connect(watchPickaxe)

local function render()
	for _, key in ORDER do
		local count = math.max(0, math.floor(tonumber(state.Gear[key]) or 0))
		if count > 0 and bar.Visible then
			local slot = slotFor(key)
			slot.Visible = true
			local countLabel = slot:FindFirstChild("Count")
			if countLabel then countLabel.Text = "x" .. count end
			local selected = slot:FindFirstChild("Selected")
			if selected then selected.Thickness = (state.Held == key) and 4 or 0 end
		elseif slots[key] then
			slots[key].Visible = false
		end
	end
	refreshHint()
end

player:GetAttributeChangedSignal("HeldGear"):Connect(function()
	state.Held = player:GetAttribute("HeldGear") or ""
	render()
end)

local lootToken = 0
local function showLoot(extra)
	if not lootPopup or type(extra) ~= "table" then return end
	lootToken += 1
	local token = lootToken
	local title = lootPopup:FindFirstChild("Title")
	local list = lootPopup:FindFirstChild("List")
	local lineTemplate = list and list:FindFirstChild("LineTemplate")
	local info = Config.Chests.Types[extra.Rarity or ""]
	if title then
		title.Text = tr("{name} OPENED!", { name = info and info.DisplayName:upper() or "CHEST" })
		if info then title.TextColor3 = info.Color end
	end
	if list and lineTemplate then
		for _, child in list:GetChildren() do
			if child:IsA("TextLabel") and child ~= lineTemplate then child:Destroy() end
		end
		for index, item in extra.Items or {} do
			local line = lineTemplate:Clone()
			line.Name = "Line" .. index
			line.LayoutOrder = index
			line.Text = "+ " .. tostring(item.Text or "")
			if item.Kind == "Skin" or item.Kind == "PrestigePoint" then
				line.TextColor3 = Color3.fromRGB(255, 215, 80)
			end
			line.Visible = true
			line.Parent = list
		end
	end
	lootPopup.Visible = true
	local pop = lootPopup:FindFirstChild("Pop")
	if pop then
		pop.Scale = 0.6
		TweenService:Create(pop, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	task.delay(3.5, function()
		if lootToken == token then lootPopup.Visible = false end
	end)
end

remote.OnClientEvent:Connect(function(command, payload, extra)
	if type(payload) == "table" and payload.Gear then
		state.Gear = payload.Gear
		state.Held = payload.Held or state.Held
	end
	if command == "Loot" then
		showLoot(extra)
	elseif command == "BuyResult" and type(payload) == "table" and payload.Ok == false then
		-- Причину покажет магазин (UpgradeShopV3 слушает то же событие).
	end
	render()
end)

-- ПРИЦЕЛ: луч из камеры через курсор/тап.
local function aimFrom(point, isScreenSpace)
	local camera = workspace.CurrentCamera
	if not camera then return nil, nil end
	-- Мышь (GetMouseLocation) — координаты вьюпорта; тап — экранные (без верхней полосы).
	local ray = isScreenSpace and camera:ScreenPointToRay(point.X, point.Y) or camera:ViewportPointToRay(point.X, point.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 300, params)
	if hit then return hit.Instance, hit.Position end
	return nil, ray.Origin + ray.Direction * 40
end

UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.G and not processed then
		-- v9: G — динамит в руку/из руки. Берём САМЫЙ БОЛЬШОЙ, какой есть;
		-- повторный G с динамитом в руке — следующий вид (или убрать).
		local held = player:GetAttribute("HeldGear") or ""
		local gear = state.Gear or {}
		local owned = {}
		for index = #Config.Dynamite.Order, 1, -1 do
			local k = Config.Dynamite.Order[index]
			if (tonumber(gear[k]) or 0) > 0 then table.insert(owned, k) end
		end
		local key = owned[1] or "Dynamite"
		if Config.Dynamite.Types[held] then
			local at = table.find(owned, held)
			key = (at and owned[at + 1]) or held -- после последнего — тот же ключ = убрать
		end
		remote:FireServer("Equip", key)
		return
	end
	local held = player:GetAttribute("HeldGear") or ""
	if held == "" or processed then return end
	-- v14: тотемы/декор/реликвии ставит PlacementGhost.client.lua (со своим CFrame).
	-- v20.9: сундуки — тоже через призрак PlacementGhost.
	if held:match("^Totem_") or held:match("^Decor_") or held:match("^Relic:") or held:match("^Chest_") then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local mouse = UserInputService:GetMouseLocation()
		local instance, position = aimFrom(mouse, false)
		if position then remote:FireServer("Use", instance, position) end
	elseif input.UserInputType == Enum.UserInputType.Touch then
		local instance, position = aimFrom(Vector2.new(input.Position.X, input.Position.Y), true)
		if position then remote:FireServer("Use", instance, position) end
	end
end)

remote:FireServer("GetState")
