--------------------------------------------------------------------------------
-- PlayerPortraitHud (LocalScript) — по прямому запросу: живой 3D-портрет
-- персонажа СНОВА (не статичная картинка), но конкретно так:
--   • Камера смотрит ПРЯМО В ЛИЦО персонажу, тот стоит по центру кадра.
--   • Персонаж плавно покачивается влево-вправо (не крутится целиком) —
--     максимум ±45° от фронтального положения, синусоидой по времени.
-- StarterGui/Hud/HudGui/Portrait — ViewportFrame (см. tools/BuildUIAssets
-- .lua), билдер кладёт только рамку, содержимое — этот скрипт.
-- HudService.lua эту часть HUD не трогает — только текстовые плашки
-- баланса/престижа рядом.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local hudGui = playerGui:WaitForChild("Hud", 10)
local portrait = hudGui and hudGui:FindFirstChild("Portrait", true)
if not (portrait and portrait:IsA("ViewportFrame")) then
	warn("[PlayerPortraitHud] StarterGui/Hud без ViewportFrame 'Portrait' - портрет показываться не будет, остальной HUD/игра не пострадают. Запусти tools/BuildAllUI.lua заново.")
	return
end

local previewModel = nil
local previewBaseCFrame = CFrame.new()

local function clearPortrait()
	-- Чистим ТОЛЬКО 3D-содержимое прошлого кадра. ClearAllChildren снёс бы
	-- и PortraitFrame — рамку-ассет, которую билдер кладёт поверх портрета
	-- (её можно заменить своей картинкой), и она бы исчезала при каждой
	-- пересборке портрета: после респавна, смены скина и т.д.
	for _, child in portrait:GetChildren() do
		if child.Name ~= "PortraitFrame" then
			child:Destroy()
		end
	end
	previewModel = nil
end

-- Клонирует ТЕКУЩЕГО персонажа в ViewportFrame — та же техника, что и
-- превью скина в SkinUI.client.lua (WorldModel + камера), только источник
-- клона — сам character, кадрируем на голову/плечи (портрет), а не на
-- весь рост, и камера смотрит ПРЯМО В ЛИЦО (по прямому запросу), а не
-- сбоку/сверху.
local function showCharacter(character)
	clearPortrait()
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and rootPart) then return end

	local world = Instance.new("WorldModel")
	world.Parent = portrait

	-- Archivable = false где-то в персонаже (редко, но встречается у
	-- некоторых аватаров/аксессуаров) заставляет :Clone() молча вернуть
	-- nil вместо ошибки — временно форсируем true на оригинале (самого
	-- игрока это никак не меняет) и всё равно защищаемся nil-проверкой.
	local originalArchivable = character.Archivable
	character.Archivable = true
	local clone = character:Clone()
	character.Archivable = originalArchivable
	if not clone then
		warn("[PlayerPortraitHud] character:Clone() вернул nil (Archivable=false у какой-то части персонажа?) - портрет для этого игрока показан не будет.")
		world:Destroy()
		return
	end

	-- Скрипты/звуки клону не нужны — это неподвижная (кроме покачивания,
	-- которое крутим сами ниже) декоративная копия, не второй живой
	-- персонаж.
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("Sound") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
		elseif descendant:IsA("Tool") then
			descendant:Destroy() -- инструмент в руках не должен маячить на портрете
		end
	end
	local cloneHumanoid = clone:FindFirstChildOfClass("Humanoid")
	if cloneHumanoid then
		cloneHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None -- имя/хелсбар над головой клону не нужны
	end

	local cloneRoot = clone:FindFirstChild("HumanoidRootPart")
	if not cloneRoot then
		clone:Destroy()
		return
	end
	clone.Parent = world
	-- Базовая ориентация — "лицом вперёд", по центру. Дальше покачивание
	-- (см. RenderStepped ниже) крутит ОТНОСИТЕЛЬНО этой CFrame, а не
	-- накопительно, чтобы никогда не уехать за пределы ±45°.
	-- Развёрнут на 180° (по прямому запросу) — камера стоит со стороны +Z
	-- и смотрит на начало координат; при "смотрящей вперёд" (нулевой)
	-- ориентации персонаж своим лицом (-Z по умолчанию у Roblox-моделей)
	-- смотрел ОТ камеры, то есть был виден затылок. Поворот на 180°
	-- разворачивает лицо навстречу камере.
	previewBaseCFrame = CFrame.Angles(0, math.pi, 0)
	clone:PivotTo(previewBaseCFrame)
	previewModel = clone

	-- Кадрируем на голову/верх торса (портрет по плечи), камера СТРОГО
	-- НАПРОТИВ лица — персонаж центрирован и смотрит прямо в объектив,
	-- а не сбоку/три-четверти.
	local head = clone:FindFirstChild("Head")
	local headHeight = head and head.Position.Y or 1.5
	local camera = Instance.new("Camera")
	-- Чуть ближе (по прямому запросу) — было 3.2 студ от лица.
	camera.CFrame = CFrame.lookAt(Vector3.new(0, headHeight - 0.3, 2.6), Vector3.new(0, headHeight - 0.5, 0))
	camera.Parent = portrait
	portrait.CurrentCamera = camera
end

local function onCharacterAdded(character)
	-- Персонаж может ещё не догрузить части в момент CharacterAdded —
	-- секунда форы, иначе клон рискует остаться без Head/аксессуаров.
	task.wait(0.5)
	if player.Character == character then
		showCharacter(character)
	end
end

if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

-- Покачивание влево-вправо, МАКСИМУМ ±45° от фронтального положения (по
-- прямому запросу — "не крутится целиком") — синусоида по времени, а не
-- накопительный поворот, поэтому угол физически не может выйти за предел.
local SWAY_MAX_DEGREES = 45
local SWAY_SPEED = 0.5 -- рад/сек внутри синуса — один полный цикл влево-вправо занимает ~2π/0.5 ≈ 12.6 сек, плавно
RunService.RenderStepped:Connect(function()
	if previewModel and previewModel.Parent then
		local angle = math.rad(SWAY_MAX_DEGREES) * math.sin(os.clock() * SWAY_SPEED)
		previewModel:PivotTo(previewBaseCFrame * CFrame.Angles(0, angle, 0))
	end
end)
