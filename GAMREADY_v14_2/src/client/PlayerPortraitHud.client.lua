--------------------------------------------------------------------------------
-- PlayerPortraitHud (LocalScript) — по прямому запросу: живой 3D-портрет
-- персонажа СНОВА (не статичная картинка), но конкретно так:
--   • Камера смотрит ПРЯМО В ЛИЦО персонажу, тот стоит по центру кадра.
--   • v20.129: персонаж неподвижен, в нейтральной позе (без анимаций).
-- StarterGui/Hud/HudGui/Portrait — ViewportFrame (см. tools/BuildUIAssets
-- .lua), билдер кладёт только рамку, содержимое — этот скрипт.
-- HudService.lua эту часть HUD не трогает — только текстовые плашки
-- баланса/престижа рядом.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local hudGui = playerGui:WaitForChild("Hud", 10)

-- v20.112: HUD одной картинкой - ImageId берём из Config на лету, чтобы
-- новая картинка появилась без пересборки UI (заглушка-рамки прячется).
do
	local okConfig, Config = pcall(require, game:GetService("ReplicatedStorage").Shared.Config)
	local cfg = okConfig and Config.UI and Config.UI.HudImage
	local imageId = cfg and tonumber(cfg.ImageId) or 0
	local background = hudGui and hudGui:FindFirstChild("Background", true)
	if imageId > 0 and background and background:IsA("ImageLabel") then
		background.Image = "rbxassetid://" .. imageId
		local holder = hudGui:FindFirstChild("Placeholder", true)
		if holder then holder.Visible = false end
	end
end
local portrait = hudGui and hudGui:FindFirstChild("Portrait", true)
if not (portrait and portrait:IsA("ViewportFrame")) then
	warn("[PlayerPortraitHud] StarterGui/Hud без ViewportFrame 'Portrait' - портрет показываться не будет, остальной HUD/игра не пострадают. Запусти tools/BuildAllUI.lua заново.")
	return
end

local previewModel = nil

local function clearPortrait()
	-- Чистим ТОЛЬКО 3D-содержимое прошлого кадра (рамка PortraitFrame остаётся).
	for _, child in portrait:GetChildren() do
		if child.Name ~= "PortraitFrame" then
			child:Destroy()
		end
	end
	previewModel = nil
end

-- v20.129: ПОРТРЕТ СПЕРЕДИ И БЕЗ АНИМАЦИЙ. Раньше клонировался персонаж
-- прямо в позе текущей анимации (бег, удар киркой) и ещё качался на ±45°,
-- из-за чего в кадре был виден бок / низ. Теперь:
--   1) свежий риг по внешности игрока (HumanoidDescription) в нейтральной
--      позе; если не вышло - клон персонажа со сброшенными суставами;
--   2) риг неподвижен, камера ставится строго напротив лица (по LookVector
--      головы), портрет по плечи.
local function stripClone(model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("Sound")
			or descendant:IsA("Tool") or descendant:IsA("Animator") or descendant:IsA("ForceField") then
			descendant:Destroy()
		elseif descendant:IsA("Motor6D") then
			descendant.Transform = CFrame.identity -- поза без анимации
		elseif descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.Anchored = false
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.PlatformStand = true
	end
end

local function buildRig(character, humanoid)
	local okDesc, description = pcall(humanoid.GetAppliedDescription, humanoid)
	if okDesc and description then
		local okRig, rig = pcall(function()
			return Players:CreateHumanoidModelFromDescription(description, humanoid.RigType)
		end)
		if okRig and rig then return rig end
	end
	local originalArchivable = character.Archivable
	character.Archivable = true
	local clone = character:Clone()
	character.Archivable = originalArchivable
	return clone
end

local function showCharacter(character)
	clearPortrait()
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not (humanoid and character:FindFirstChild("HumanoidRootPart")) then return end

	local world = Instance.new("WorldModel")
	world.Parent = portrait
	local rig = buildRig(character, humanoid)
	if not rig then
		warn("[PlayerPortraitHud] не удалось собрать риг для портрета")
		world:Destroy()
		return
	end
	stripClone(rig)
	local root = rig:FindFirstChild("HumanoidRootPart")
	if not root then
		rig:Destroy()
		return
	end
	root.Anchored = true
	rig.PrimaryPart = root
	rig.Parent = world
	rig:PivotTo(CFrame.new())
	previewModel = rig

	-- камера строго напротив лица, по плечи
	local head = rig:FindFirstChild("Head")
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	if head then
		local face = Vector3.new(head.CFrame.LookVector.X, 0, head.CFrame.LookVector.Z)
		if face.Magnitude < 0.05 then face = Vector3.new(0, 0, -1) end
		local focus = head.Position - Vector3.new(0, 0.35, 0)
		camera.CFrame = CFrame.lookAt(focus + face.Unit * 4.2 + Vector3.new(0, 0.15, 0), focus)
	else
		camera.CFrame = CFrame.lookAt(Vector3.new(0, 1.5, -4.2), Vector3.new(0, 1.2, 0))
	end
	camera.Parent = portrait
	portrait.CurrentCamera = camera
end

local function onCharacterAdded(character)
	-- Персонаж может ещё не догрузить части/внешность в момент CharacterAdded.
	task.wait(1)
	if player.Character == character then
		showCharacter(character)
	end
end

if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
