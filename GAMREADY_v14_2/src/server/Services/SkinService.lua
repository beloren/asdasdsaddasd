local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local SkinService = {}
local Services
local remote
local lastRequest = {}
local Assets = ReplicatedStorage:WaitForChild("Assets")

local function findSkinAsset(assetName)
	return Assets:FindFirstChild(assetName) or workspace:FindFirstChild(assetName, true)
end

local function kindEnabled(kind)
	return Config.Skins.EnabledKinds and Config.Skins.EnabledKinds[kind] == true
end

local function findPickaxeTemplate(asset)
	if not asset then return nil, false end
	local function hasDirectHandle(container)
		local handle = container:FindFirstChild("Handle")
		return handle and handle:IsA("BasePart")
	end
	local function hasDirectVisualRoot(container)
		local root = container:FindFirstChild("SkinRoot")
		if not root and container:IsA("Model") then root = container.PrimaryPart end
		return root and root:IsA("BasePart")
	end
	if asset:IsA("Tool") and hasDirectHandle(asset) then return asset, true end
	local nestedTool = asset:FindFirstChildWhichIsA("Tool", true)
	if nestedTool and hasDirectHandle(nestedTool) then return nestedTool, true end
	-- Studio assets are often saved as Model -> Handle + Union rather than
	-- an actual Tool. Treat that container as a complete visual template.
	if hasDirectHandle(asset) then return asset, false end
	-- Builder-created models use SkinRoot/PrimaryPart and are converted to a
	-- Tool below; the root is renamed to Handle during that conversion.
	if hasDirectVisualRoot(asset) then return asset, false end
	for _, descendant in asset:GetDescendants() do
		if not descendant:IsA("BasePart") and hasDirectHandle(descendant) then
			return descendant, descendant:IsA("Tool")
		end
		if not descendant:IsA("BasePart") and hasDirectVisualRoot(descendant) then
			return descendant, false
		end
	end
	return nil, false
end

local function hasValidAsset(definition)
	if not definition or not kindEnabled(definition.Kind) then return false end
	-- v10: скин можно носить и без своей модели (турбо-кирка) — тогда это
	-- обычная кирка, а весь смысл скина в его эффекте.
	if definition.AllowPlaceholder then return true end
	local source = findSkinAsset(definition.AssetName)
	if not source then return false end
	if definition.Kind == "Pickaxe" then
		local template = findPickaxeTemplate(source)
		return template ~= nil and template.Archivable
	end
	if source:IsA("BasePart") then return true end
	-- Tool skins use the exact same contract as regular pickaxes. Their direct
	-- Handle is only the visual alignment root; the live pickaxe stays intact.
	if source:IsA("Tool") then
		local handle = source:FindFirstChild("Handle")
		return handle ~= nil and handle:IsA("BasePart")
	end
	if not source:IsA("Model") then return false end
	local root = source:FindFirstChild("SkinRoot", true) or source.PrimaryPart or source:FindFirstChildWhichIsA("BasePart", true)
	return root ~= nil and root:IsA("BasePart")
end

local function cloneVisual(assetName, containerName, anchor, parent)
	local source = findSkinAsset(assetName)
	if not source then return nil end
	local visual = source:Clone()
	local toolVisual = visual:IsA("Tool")
	visual.Name = containerName
	for _, descendant in visual:GetDescendants() do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then descendant:Destroy() end
	end
	if visual:IsA("BasePart") then
		local model = Instance.new("Model")
		visual.Parent = model
		model.PrimaryPart = visual
		visual = model
		visual.Name = containerName
	elseif visual:IsA("Tool") then
		-- Разворачиваем Tool в обычный Model: второй вложенный Tool внутри
		-- уже надетой кирки/тележки ведёт себя непредсказуемо (Roblox может
		-- заново триггерить Equipped/Unequipped, RequiresHandle и т.п.),
		-- а нам нужна только его геометрия/эффекты, не сам инструмент.
		local model = Instance.new("Model")
		model.Name = containerName
		for _, child in visual:GetChildren() do
			child.Parent = model
		end
		visual:Destroy()
		visual = model
	end
	if not visual:IsA("Model") then visual:Destroy(); return nil end
	local skinRoot = toolVisual and visual:FindFirstChild("Handle")
		or visual:FindFirstChild("SkinRoot", true)
		or visual.PrimaryPart
		or visual:FindFirstChildWhichIsA("BasePart", true)
	if not skinRoot then visual:Destroy(); return nil end
	-- Align the declared skin root to the real Tool/Cart root. PivotTo alone
	-- depends on the model pivot saved by Studio and can offset Tool-shaped skins.
	local rootToPivot = skinRoot.CFrame:ToObjectSpace(visual:GetPivot())
	visual.PrimaryPart = skinRoot
	visual.Parent = parent
	visual:PivotTo(anchor.CFrame * rootToPivot)
	for _, descendant in visual:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Name = "SkinWeld"
			weld.Part0 = anchor
			weld.Part1 = descendant
			weld.Parent = descendant
		end
	end
	return visual
end

local function stripScripts(root)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
end

-- v10: турбо-кирка надета → RocketMode (CombatService читает его в бою).
local function syncRocketSkin(player, skinId)
	local rocketSkin = Config.RocketPickaxe and Config.RocketPickaxe.SkinId
	player:SetAttribute("RocketMode", rocketSkin ~= nil and skinId == rocketSkin)
end

local function refreshSkin(player, kind, skinId)
	if kind == "Pickaxe" then
		syncRocketSkin(player, skinId)
		Services.CombatService:RefreshPickaxe(player)
	else
		Services.CartService:RefreshCartSkin(player)
	end
end

function SkinService:Init(services)
	Services = services
	-- v18: скины «Пиратский клад» без своих моделей — собираем простые
	-- (shared/ProceduralSkins) и кладём в Assets под их AssetName. Дальше
	-- весь код видит их как обычные ассеты. Своя модель с тем же именем
	-- в Assets — приоритетнее, её не трогаем.
	local ProceduralSkins = require(ReplicatedStorage.Shared.ProceduralSkins)
	for skinId, definition in Config.Skins.Definitions do
		if definition.Procedural and definition.AssetName and not Assets:FindFirstChild(definition.AssetName)
			and ProceduralSkins.Has(skinId) then
			local ok, tool = pcall(ProceduralSkins.Build, skinId)
			if ok and tool then
				tool.Name = definition.AssetName
				tool.Parent = Assets
			else
				warn("[SkinService] Не удалось собрать скин", skinId, tool)
			end
		end
	end
	remote = ReplicatedStorage.Shared:FindFirstChild("SkinRequest") or Instance.new("RemoteEvent")
	remote.Name = "SkinRequest"
	remote.Parent = ReplicatedStorage.Shared
	remote.OnServerEvent:Connect(function(player, action, kind, skinId)
		if action == "RequestState" then
			local now = os.clock()
			if now - (lastRequest[player] or 0) < 0.15 then return end
			lastRequest[player] = now
			self:SendState(player)
		elseif action == "Equip" then
			self:Equip(player, kind, skinId)
		end
	end)
end

function SkinService:SetupPlayer(player)
	local data = Services.DataService:GetGeodeData(player)
	if not data then return end
	syncRocketSkin(player, data.EquippedSkins and data.EquippedSkins.Pickaxe or "")
	local testGrant = RunService:IsStudio()
		and Config.Skins.DeveloperTestGrants
		and Config.Skins.DeveloperTestGrants[string.lower(player.Name)]
	if testGrant and data.DeveloperTestGrantVersion < testGrant.Version then
		local previousOwned = table.clone(data.OwnedSkins)
		local previousGeodes = table.clone(data.Geodes)
		local previousVersion = data.DeveloperTestGrantVersion
		local previousStarterGranted = data.SkinStarterGranted
		for skinId, definition in Config.Skins.Definitions do
			if kindEnabled(definition.Kind) and definition.NpcExclusive ~= true then data.OwnedSkins[skinId] = true end
		end
		for geodeType, amount in (testGrant.Geodes or {}) do
			if Config.Geodes.Types[geodeType] then
				data.Geodes[geodeType] = (data.Geodes[geodeType] or 0) + amount
			end
		end
		data.DeveloperTestGrantVersion = testGrant.Version
		data.SkinStarterGranted = true
		if not Services.DataService:SaveProfile(player) then
			data.OwnedSkins = previousOwned
			data.Geodes = previousGeodes
			data.DeveloperTestGrantVersion = previousVersion
			data.SkinStarterGranted = previousStarterGranted
		end
	end
	if Config.Skins.GrantRandomStarterSkin and not data.SkinStarterGranted then
		local pool = {}
		for skinId, definition in Config.Skins.Definitions do
			if definition.NpcExclusive ~= true and hasValidAsset(definition) then table.insert(pool, skinId) end
		end
		table.sort(pool)
		if #pool > 0 then
			local skinId = pool[Random.new(player.UserId):NextInteger(1, #pool)]
			data.OwnedSkins[skinId] = true
			data.SkinStarterGranted = true
			if not Services.DataService:SaveProfile(player) then
				data.OwnedSkins[skinId] = nil
				data.SkinStarterGranted = false
			end
		end
	end
	self:SendState(player)
end

function SkinService:GetState(player)
	local data = Services.DataService:GetGeodeData(player)
	if not data then return nil end
	local owned = {}
	for skinId, isOwned in data.OwnedSkins do
		local definition = Config.Skins.Definitions[skinId]
		if isOwned == true and definition and hasValidAsset(definition) then
			table.insert(owned, {
				Id = skinId, Kind = definition.Kind, DisplayName = definition.DisplayName,
				Rarity = definition.Rarity, AssetName = definition.AssetName, ImageId = definition.ImageId,
			})
		end
	end
	table.sort(owned, function(a, b) return a.DisplayName < b.DisplayName end)
	-- v20.27: ВСЕ скины кирок (для «?»-карточек ещё не открытых во вкладке
	-- SKINS). Только редкость и Id — имя/картинку закрытого не раскрываем.
	local all = {}
	for skinId, definition in Config.Skins.Definitions do
		if definition.Kind == "Pickaxe" and kindEnabled("Pickaxe") and data.OwnedSkins[skinId] ~= true then
			table.insert(all, { Id = skinId, Kind = definition.Kind, Rarity = definition.Rarity })
		end
	end
	return {
		Owned = owned,
		Locked = all,
		Equipped = {
			Pickaxe = kindEnabled("Pickaxe") and data.EquippedSkins.Pickaxe or "",
			Cart = kindEnabled("Cart") and data.EquippedSkins.Cart or "",
			Ore = "",
		},
	}
end

function SkinService:SendState(player, command)
	if player.Parent then remote:FireClient(player, command or "State", self:GetState(player)) end
end

function SkinService:Equip(player, kind, skinId)
	if (kind ~= "Pickaxe" and kind ~= "Cart") or not kindEnabled(kind) then self:SendState(player); return false end
	skinId = typeof(skinId) == "string" and skinId or ""
	local data = Services.DataService:GetGeodeData(player)
	local definition = Config.Skins.Definitions[skinId]
	if not data or player:GetAttribute("EconomyTransactionLocked") == true then self:SendState(player); return false end
	if skinId ~= "" and (not definition or not hasValidAsset(definition) or definition.Kind ~= kind or data.OwnedSkins[skinId] ~= true) then self:SendState(player); return false end
	local previous = data.EquippedSkins[kind]
	if previous == skinId then self:SendState(player); return true end
	player:SetAttribute("EconomyTransactionLocked", true)
	data.EquippedSkins[kind] = skinId
	-- Apply and replicate first. DataStore latency must never delay a visual
	-- equipment action; persistence happens afterwards and rolls back safely.
	refreshSkin(player, kind, skinId)
	-- v8: у скинов свои баффы/дебаффы (Config.SkinBuffs) — скорость пересчитываем сразу.
	if Services.CartService then pcall(Services.CartService.RefreshSpeed, Services.CartService, player) end
	self:SendState(player)
	if not Services.DataService:SaveProfile(player) then
		data.EquippedSkins[kind] = previous
		refreshSkin(player, kind, previous)
		player:SetAttribute("EconomyTransactionLocked", false)
		self:SendState(player)
		return false
	end
	player:SetAttribute("EconomyTransactionLocked", false)
	return true
end

function SkinService:UnlockFromGeode(data, geodeType)
	local pool = {}
	for skinId, definition in Config.Skins.Definitions do
		if definition.Geodes and definition.Geodes[geodeType] and hasValidAsset(definition) then table.insert(pool, skinId) end
	end
	if #pool == 0 then return nil, false end
	table.sort(pool)
	local skinId = pool[math.random(1, #pool)]
	local isNew = data.OwnedSkins[skinId] ~= true
	data.OwnedSkins[skinId] = true
	return skinId, isNew
end

-- Есть ли скин у игрока. Нужен QuestService, чтобы не выдавать на повторном
-- круге стрика ежедневных наград уже открытый скин (GrantNpcSkin в этом
-- случае молча возвращает success, ничего не выдав).
-- Можно ли выдать скин вообще (есть ли ассет или разрешённый плейсхолдер).
-- Нужна лавке торговца: скин без модели не должен продаваться.
function SkinService:IsSkinAvailable(skinId)
	local definition = Config.Skins.Definitions[skinId]
	return definition ~= nil and hasValidAsset(definition) == true
end

function SkinService:OwnsSkin(player, skinId)
	local data = Services.DataService:GetGeodeData(player)
	return data ~= nil and data.OwnedSkins[skinId] == true
end

function SkinService:GrantSkin(player, skinId)
	local definition = Config.Skins.Definitions[skinId]
	local data = Services.DataService:GetGeodeData(player)
	if not data or not hasValidAsset(definition) then return false end
	if data.OwnedSkins[skinId] == true then return true end
	data.OwnedSkins[skinId] = true
	if not Services.DataService:SaveProfile(player) then data.OwnedSkins[skinId] = nil; return false end
	self:SendState(player)
	return true
end

function SkinService:GrantRandomSkinFromGeode(player, geodeType)
	local pool = {}
	for skinId, definition in Config.Skins.Definitions do
		if definition.Geodes and definition.Geodes[geodeType] and hasValidAsset(definition) then
			table.insert(pool, skinId)
		end
	end
	if #pool == 0 then return nil, false end
	local skinId = pool[math.random(1, #pool)]
	if not self:GrantSkin(player, skinId) then return nil, false end
	return skinId, true
end

-- ИСПРАВЛЕНИЕ БАГА "НАГРАДА ЗА ГРУППУ НЕ ВЫДАЁТ СКИН".
-- Раньше здесь стояло жёсткое требование definition.NpcExclusive == true.
-- Config.GroupReward.SkinId в какой-то момент переписали на "DevSword" —
-- а это ОБЫЧНЫЙ геодный скин (Geodes = { Nebula = true }), у него поля
-- NpcExclusive нет и быть не должно. В результате GrantNpcSkin молча
-- возвращал false, GroupRewardService видел, что жеоды-то выдались, и
-- ПОМЕЧАЛ НАГРАДУ ЗАБРАННОЙ — игрок навсегда терял скин, ради которого
-- вступал в группу, и видел в награде совсем не то, что показывала
-- карточка.
--
-- Проверка NpcExclusive тут в принципе не защищала ни от чего: этот метод
-- вызывается ТОЛЬКО с сервера, из доверенных наградных сервисов
-- (GroupRewardService/LikeRewardService/DataService — ежедневные награды),
-- клиент до него не дотягивается. Единственная содержательная проверка —
-- существует ли ассет скина в Studio, её и оставляем.
function SkinService:GrantNpcSkin(player, skinId)
	local definition = Config.Skins.Definitions[skinId]
	local data = Services.DataService:GetGeodeData(player)
	if not data or not definition then
		return false, "MissingAsset"
	end
	if not hasValidAsset(definition) then
		warn(("[SkinService] Скин %s нельзя выдать: в ReplicatedStorage/Assets нет рабочего ассета \"%s\" (или у него нет Handle/SkinRoot). Проверь Config.Skins.Definitions.%s.AssetName."):format(
			tostring(skinId), tostring(definition.AssetName), tostring(skinId)))
		return false, "MissingAsset"
	end
	if data.OwnedSkins[skinId] == true then
		return true, "AlreadyOwned"
	end
	if player:GetAttribute("EconomyTransactionLocked") == true then return false, "Busy" end
	player:SetAttribute("EconomyTransactionLocked", true)
	data.OwnedSkins[skinId] = true
	self:SendState(player)
	if not Services.DataService:SaveProfile(player) then
		data.OwnedSkins[skinId] = nil
		player:SetAttribute("EconomyTransactionLocked", false)
		self:SendState(player)
		return false, "SaveFailed"
	end
	player:SetAttribute("EconomyTransactionLocked", false)
	return true, "Granted"
end

function SkinService:CreatePickaxeTool(player, baseTool)
	if not baseTool or not baseTool:IsA("Tool") then return baseTool end
	local data = Services.DataService:GetGeodeData(player)
	local skinId = data and data.EquippedSkins.Pickaxe or ""
	if skinId == "" then return baseTool end
	local definition = Config.Skins.Definitions[skinId]
	if not definition or not kindEnabled("Pickaxe") then return baseTool end
	local source = findSkinAsset(definition.AssetName)
	local template, isToolTemplate = findPickaxeTemplate(source)
	if not template then
		warn(("[SkinService] Скин %s не содержит контейнер с прямым BasePart Handle: ReplicatedStorage/Assets/%s (класс ассета: %s)."):format(
			skinId,
			definition.AssetName,
			source and source.ClassName or "отсутствует"
		))
		return baseTool
	end

	-- Clone the complete container first so all internal constraint references
	-- are remapped together. A Model/Folder wrapper is converted to a Tool only
	-- after cloning; its Handle, Union and weld instances remain untouched.
	local cloneOk, clonedTemplate = pcall(function() return template:Clone() end)
	if not cloneOk or not clonedTemplate then
		warn(("[SkinService] Не удалось клонировать скин %s; проверь Archivable у Tool и его частей."):format(skinId))
		return baseTool
	end
	stripScripts(clonedTemplate)
	local tool
	if isToolTemplate then
		tool = clonedTemplate
	else
		tool = Instance.new("Tool")
		tool.Grip = baseTool.Grip
		for _, child in clonedTemplate:GetChildren() do
			child.Parent = tool
		end
		clonedTemplate:Destroy()
	end
	if not tool:FindFirstChild("Handle") then
		local visualRoot = tool:FindFirstChild("SkinRoot")
		if visualRoot and visualRoot:IsA("BasePart") then
			visualRoot.Name = "Handle"
		end
	end
	local handle = tool:FindFirstChild("Handle")
	if not (handle and handle:IsA("BasePart")) then
		warn(("[SkinService] Скин %s не удалось преобразовать в Tool: отсутствует прямой BasePart Handle."):format(skinId))
		tool:Destroy()
		return baseTool
	end
	for name, value in baseTool:GetAttributes() do
		tool:SetAttribute(name, value)
	end
	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end
	tool.Name = "Pickaxe"
	tool.CanBeDropped = false
	tool.Enabled = baseTool.Enabled
	tool.ManualActivationOnly = baseTool.ManualActivationOnly
	tool.RequiresHandle = true
	baseTool:Destroy()
	return tool
end

function SkinService:ApplyCartSkin(player, data)
	if not data or not data.Model then return end
	local old = data.Model:FindFirstChild("AppliedCartSkin")
	if old then old:Destroy() end
	for _, descendant in data.Model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("SkinBaseTransparency") ~= nil then
			descendant.Transparency = descendant:GetAttribute("SkinBaseTransparency")
		end
	end
	if not kindEnabled("Cart") then return end
	local profile = Services.DataService:GetGeodeData(player)
	local skinId = profile and profile.EquippedSkins.Cart or ""
	if skinId == "" then return end
	local definition = Config.Skins.Definitions[skinId]
	if not definition then return end
	local visual = cloneVisual(definition.AssetName, "AppliedCartSkin", data.Root, data.Model)
	if not visual then
		warn(("[SkinService] cloneVisual вернул nil для скина %s (AssetName=%s) при надевании на тележку - см. tools/ValidateSkinAssets.lua."):format(skinId, definition.AssetName))
		return
	end
	for _, descendant in data.Model:GetDescendants() do
		if descendant:IsA("BasePart") and not descendant:IsDescendantOf(visual)
			and descendant:GetAttribute("SkinBaseTransparency") ~= nil then
			descendant.Transparency = 1
		end
	end
end

function SkinService:CleanupPlayer(player)
	lastRequest[player] = nil
end

return SkinService
