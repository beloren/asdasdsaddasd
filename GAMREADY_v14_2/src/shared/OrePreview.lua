--------------------------------------------------------------------------------
-- OrePreview (v20.78) — 3D-превью стопки руды в ячейке UI. Только клиент.
--
-- Одно и то же для инвентаря (InventoryUI) и сундука-хранилища
-- (DecorStorageUI): настоящая модель руды из Assets (та же, что лежит в
-- мире: Crystal_<Key>[_V<n>], слиток - OreIngot), вариация + все мутации,
-- под ней силуэт-обводка (Config.Inventory.PreviewOutline*). Готовые модели
-- кэшируются по ключу (руда|вариация|мутации|слиток) и только клонируются.
--
-- OrePreview.Mount(container, stack) -> true/false: кладёт в container два
--   ViewportFrame ("ModelOutline" + "ModelView") на весь его размер.
-- OrePreview.Clear(container) - убирает их.
-- OrePreview.Template(stack) - готовая модель (не клонированная, из кэша).
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)
local MutationVisuals = require(ReplicatedStorage.Shared.MutationVisuals)
local MutationRoll = require(ReplicatedStorage.Shared.MutationRoll)

local OrePreview = {}

local cache = {}
local warned = {}

local function keyOf(stack)
	return table.concat({ tostring(stack.Ore), tostring(stack.Variant or 1), tostring(stack.Mutations or ""), stack.Smelted and "S" or "" }, "|")
end

local function mutationList(stack)
	local raw = stack.Mutations
	if type(raw) == "table" then return raw end
	if type(raw) ~= "string" then return {} end
	return MutationRoll.Parse((raw:gsub("%s", "")))
end

local function build(stack)
	local info = stack and stack.Ore and Config.OreByKey[stack.Ore]
	if not info then return nil end
	local variant = Config.OreVariants and Config.OreVariants[stack.Variant or 1]
	local factory = (stack.Smelted and PlaceholderFactory.OreIngot) or PlaceholderFactory.OreCrystal
	local ok, model = pcall(factory, info, variant)
	if not (ok and model) then
		if not warned[stack.Ore] then
			warned[stack.Ore] = true
			warn(("[OrePreview] не удалось собрать модель руды %s: %s"):format(tostring(stack.Ore), tostring(model)))
		end
		return nil
	end
	for _, d in (model:IsA("Model") and model:GetDescendants() or { model }) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
	local list = mutationList(stack)
	if #list > 0 and model:IsA("Model") then
		local okSplit, groups = pcall(MutationVisuals.SplitPartsForMutations, model, #list)
		local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		for index, mutationId in list do
			pcall(MutationVisuals.Apply, model, mutationId, root, okSplit and groups and groups[index] or nil)
		end
	elseif #list > 0 then
		for _, mutationId in list do
			pcall(MutationVisuals.Apply, model, mutationId, model, nil)
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("BillboardGui") or d:IsA("ProximityPrompt")
			or d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Sound") then
			d:Destroy()
		end
	end
	return model
end

function OrePreview.Template(stack)
	if not stack then return nil end
	local key = keyOf(stack)
	local cached = cache[key]
	if cached then return cached end
	local model = build(stack)
	if model then cache[key] = model end
	return model
end

function OrePreview.Clear(container)
	for _, name in { "ModelView", "ModelOutline" } do
		local old = container:FindFirstChild(name)
		if old then old:Destroy() end
	end
end

function OrePreview.Mount(container, stack)
	if not (container and stack) then return false end
	local key = keyOf(stack)
	local existing = container:FindFirstChild("ModelView")
	if existing and existing:GetAttribute("Key") == key then return true end
	OrePreview.Clear(container)
	local template = OrePreview.Template(stack)
	if not template then return false end

	local model = template:Clone()
	local size
	if model:IsA("Model") then
		model:PivotTo(CFrame.new())
		local boxCF, boundsSize = model:GetBoundingBox()
		model:PivotTo(CFrame.new(-boxCF.Position))
		size = boundsSize
	else
		model.CFrame = CFrame.new()
		size = model.Size
	end
	local distance = math.max(size.X, size.Y, size.Z) * 1.9 + 0.6
	local cameraCF = CFrame.lookAt(Vector3.new(distance * 0.45, distance * 0.35, distance), Vector3.new())
	local baseZ = container:IsA("GuiObject") and container.ZIndex or 1

	local function viewport(name, zIndex, scale)
		local frame = Instance.new("ViewportFrame")
		frame.Name = name
		frame.BackgroundTransparency = 1
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(0.5, 0.5)
		frame.Size = UDim2.fromScale(scale, scale)
		frame.ZIndex = zIndex
		local camera = Instance.new("Camera")
		camera.FieldOfView = 40
		camera.CFrame = cameraCF
		camera.Parent = frame
		frame.CurrentCamera = camera
		return frame
	end

	local invCfg = Config.Inventory or {}
	if invCfg.PreviewOutline ~= false then
		-- Силуэт: копия модели одним цветом, ровный свет без теней, рамка
		-- чуть больше основной - по краю модели выступает обводка.
		local outlineColor = invCfg.PreviewOutlineColor or Color3.new(0, 0, 0)
		local outline = viewport("ModelOutline", baseZ, 1 + (invCfg.PreviewOutlineScale or 0.12))
		outline.Ambient = Color3.new(1, 1, 1)
		outline.LightColor = Color3.new(0, 0, 0)
		local silhouette = model:Clone()
		for _, d in (silhouette:IsA("Model") and silhouette:GetDescendants() or { silhouette }) do
			if d:IsA("BasePart") then
				d.Color = outlineColor
				d.Material = Enum.Material.SmoothPlastic
				d.Reflectance = 0
				if d:IsA("MeshPart") then pcall(function() d.TextureID = "" end) end
			elseif d:IsA("Decal") or d:IsA("Texture") or d:IsA("SurfaceAppearance") then
				d:Destroy()
			end
		end
		silhouette.Parent = outline
		outline.Parent = container
	end

	local main = viewport("ModelView", baseZ + 1, 1)
	main.Ambient = Color3.fromRGB(170, 170, 175)
	main.LightColor = Color3.new(1, 1, 1)
	main.LightDirection = Vector3.new(-0.6, -1, -0.5)
	main:SetAttribute("Key", key)
	model.Parent = main
	main.Parent = container
	return true
end

return OrePreview
