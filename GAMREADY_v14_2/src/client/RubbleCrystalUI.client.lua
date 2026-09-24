local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Config = require(ReplicatedStorage.Shared.Config)
local tradeRemote = ReplicatedStorage.Shared:WaitForChild("RubbleCrystalTradeRequest")

local giftPrompt
local giftTarget
local function clearGiftPrompt()
	if giftPrompt then giftPrompt:Destroy() end
	giftPrompt = nil
	giftTarget = nil
end

local function nearestGiftTarget()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local nearest, nearestDistance
	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer ~= player and otherPlayer.Character then
			local otherRoot = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
			local distance = otherRoot and (otherRoot.Position - root.Position).Magnitude
			if distance and distance <= 12 and (not nearestDistance or distance < nearestDistance) then
				nearest = otherPlayer
				nearestDistance = distance
			end
		end
	end
	return nearest
end

local function refreshGiftPrompt()
	local target = (player:GetAttribute("CarryingCrystal") or "") ~= "" and nearestGiftTarget() or nil
	if target == giftTarget and giftPrompt and giftPrompt.Parent then return end
	clearGiftPrompt()
	if not target then return end
	local root = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	giftTarget = target
	giftPrompt = Instance.new("ProximityPrompt")
	giftPrompt.Name = "GiftCrystalPrompt"
	giftPrompt.ActionText = "GIFT CRYSTAL"
	giftPrompt.ObjectText = target.DisplayName
	giftPrompt.HoldDuration = 0.7
	giftPrompt.MaxActivationDistance = 12
	giftPrompt.ClickablePrompt = true
	giftPrompt.KeyboardKeyCode = Enum.KeyCode.E
	giftPrompt.RequiresLineOfSight = false
	giftPrompt.Style = Enum.ProximityPromptStyle.Custom
	giftPrompt.Parent = root
	giftPrompt.Triggered:Connect(function()
		if giftTarget == target and (player:GetAttribute("CarryingCrystal") or "") ~= "" then
			tradeRemote:FireServer(target)
		end
	end)
end

player:GetAttributeChangedSignal("CarryingCrystal"):Connect(refreshGiftPrompt)
RunService.Heartbeat:Connect(refreshGiftPrompt)

local gui = Instance.new("ScreenGui")
gui.Name = "RubbleCrystalUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

-- Карточка переноски — не строится кодом здесь: это готовый инстанс из
-- StarterGui/RubbleCrystalHotbar/Slot (см. tools/BuildRubbleCrystalUI.lua),
-- визуально точная копия слота кирки. Этот скрипт только переключает
-- видимость и подставляет иконку/плейсхолдер под текущий oreId — саму
-- геометрию/стиль карточки трогать тут не нужно, она уже готова в Studio.
--
-- ВАЖНО: WaitForChild с таймаутом возвращает nil (не кидает ошибку), если
-- не нашёл — но вызов :WaitForChild НА nil уже кидает ошибку и раньше
-- ронял ВЕСЬ файл целиком (значит и трейд, и поза рук ниже тоже переставали
-- работать) просто потому, что билдер карточки ещё не запускали в Studio.
-- Теперь если карточки нет — предупреждаем в вывод и спокойно продолжаем
-- без неё, остальной скрипт (передача через промпт/поза рук) работает независимо.
local crystalHotbar = playerGui:WaitForChild("RubbleCrystalHotbar", 10)
local crystalSlot = crystalHotbar and crystalHotbar:WaitForChild("Slot", 10)
local crystalIcon = crystalSlot and crystalSlot:WaitForChild("Icon", 5)
local crystalPlaceholder = crystalSlot and crystalSlot:WaitForChild("Placeholder", 5)
if not (crystalSlot and crystalIcon and crystalPlaceholder) then
	warn("[RubbleCrystalUI] StarterGui.RubbleCrystalHotbar.Slot не найден — запустите tools/BuildRubbleCrystalUI.lua через Command Bar в Studio. Карточка кристалла не будет показываться, но передача через промпт и поза рук всё равно работают.")
end

-- Пока карточка кристалла видна, кирка должна ЧУТЬ-ЧУТЬ отъехать вправо —
-- чтобы пара [кристалл][кирка] стояла ровно по центру экрана, а не кирка
-- одна по центру + кристалл слева от неё (что смещает видимый "центр
-- тяжести" пары влево). Сдвиг = половина ширины слота (68) + половина
-- отступа между карточками (8) = 38 — ровно на столько же кристалл смещён
-- влево от центра в tools/BuildRubbleCrystalUI.lua.
local PICKAXE_SHIFT_OFFSET = 38
local pickaxeSlot = playerGui:WaitForChild("PickaxeHotbar", 10)
pickaxeSlot = pickaxeSlot and pickaxeSlot:WaitForChild("Slot", 5)
local pickaxeBasePosition = pickaxeSlot and pickaxeSlot.Position
local pickaxeShifted = false
local function setPickaxeShifted(shifted)
	if not pickaxeSlot or shifted == pickaxeShifted then return end
	pickaxeShifted = shifted
	local offset = shifted and PICKAXE_SHIFT_OFFSET or 0
	TweenService:Create(pickaxeSlot, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(pickaxeBasePosition.X.Scale, pickaxeBasePosition.X.Offset + offset, pickaxeBasePosition.Y.Scale, pickaxeBasePosition.Y.Offset),
	}):Play()
end

--------------------------------------------------------------------------------
-- ПОЗА "РУКИ НАД ГОЛОВОЙ" — пока персонаж несёт кристалл, обе руки подняты,
-- как будто он держит его над головой (сам кристалл физически прикреплён к
-- голове через WeldConstraint — см. RockService:CarryCrystal; поза рук —
-- чисто косметическая надстройка сверху, с точкой крепления не связана).
--
-- Прошлая версия использовала дефолтную анимацию ПРЫЖКА R6 (Action priority)
-- — технически решает гонку с "Animate", НО эта анимация двигает не только
-- руки, а всё тело (по сути реально "подпрыгивает" персонаж) — не то, что
-- нужно. Возвращаемся к прямой правке Motor6D.Transform, но ТОЛЬКО у
-- "Right Shoulder"/"Left Shoulder" — гарантированно НИЧЕГО, кроме рук, не
-- трогаем (ноги/торс в принципе не участвуют, значит никакого "прыжка" по
-- определению). Пишем Transform КАЖДЫЙ кадр в RenderStepped (после
-- Stepped/Heartbeat, где встроенный "Animate" обновляет позу ходьбы/покоя),
-- поэтому наша правка оказывается "последним словом" за кадр даже если
-- Animate тоже что-то пишет туда в этом же кадре.
--------------------------------------------------------------------------------

local ARM_RAISE_TRANSFORM = CFrame.Angles(math.rad(-165), 0, 0) -- см. примечание ниже
local POSE_LERP_SPEED = 12 -- скорость сглаживания подъёма/опускания рук

local posedJoints = {} -- [Model] = { Right = Motor6D, Left = Motor6D, Progress = number }

local function watchPlayerPose(targetPlayer)
	local function onCharacter(character)
		-- WaitForChild (не FindFirstChild) — на случай, если суставы рига
		-- ещё не успели полностью прогрузиться в момент CharacterAdded.
		local torso = character:WaitForChild("Torso", 5)
		local right = torso and torso:WaitForChild("Right Shoulder", 5)
		local left = torso and torso:WaitForChild("Left Shoulder", 5)
		if not (right and right:IsA("Motor6D") and left and left:IsA("Motor6D")) then return end
		posedJoints[character] = { Right = right, Left = left, Progress = 0 }
		character.AncestryChanged:Connect(function(_, parent)
			if not parent then posedJoints[character] = nil end
		end)
	end
	targetPlayer.CharacterAdded:Connect(onCharacter)
	if targetPlayer.Character then onCharacter(targetPlayer.Character) end
end

for _, otherPlayer in Players:GetPlayers() do watchPlayerPose(otherPlayer) end
Players.PlayerAdded:Connect(watchPlayerPose)

-- ПРИМЕЧАНИЕ: угол подобран приблизительно (нет возможности проверить
-- визуально без Studio) — если руки поднимаются не совсем "над головой",
-- подправьте градус по X в ARM_RAISE_TRANSFORM выше на глаз в редакторе.
-- Используем RunService.Stepped, а не RenderStepped — ровно то же событие,
-- которым уже пользуется проверенный IK хвата за тележку
-- (CustomCartUI.client.lua) для постоянной перезаписи Motor6D.Transform.
-- Максимальная консистентность с уже работающей в игре техникой.
-- ВАЖНО: Transform трогаем ТОЛЬКО пока реально несём кристалл или ещё не
-- закончили переход обратно вниз. Раньше "иначе сбросить в identity"
-- срабатывало КАЖДЫЙ кадр, даже когда кристалла в руках уже давно нет —
-- а обычная ходьба/покой сама постоянно меняет тот же Transform (взмах
-- руками при шаге). Мы это перебивали обратно в identity каждый кадр,
-- поэтому руки казались "замороженными" всегда, а не только при переноске.
-- Теперь как только переход вниз завершён (target=0 и Progress уже 0) —
-- просто НЕ трогаем Transform вообще, отдавая полный контроль обратно
-- штатной анимации ходьбы/покоя.
RunService.Stepped:Connect(function(_, deltaTime)
	for character, record in posedJoints do
		if not character.Parent then
			posedJoints[character] = nil
		else
			local owner = Players:GetPlayerFromCharacter(character)
			local target = (owner and owner:GetAttribute("CarryingCrystal") or "") ~= "" and 1 or 0
			if target == 1 or record.Progress > 0.002 then
				record.Progress = record.Progress + (target - record.Progress) * math.min(1, deltaTime * POSE_LERP_SPEED)
				if target == 0 and record.Progress <= 0.002 then
					-- Последний кадр перехода — вернули руки в нейтраль и
					-- со следующего кадра полностью отпускаем Transform.
					record.Progress = 0
					record.Right.Transform = CFrame.new()
					record.Left.Transform = CFrame.new()
				else
					local pose = CFrame.new():Lerp(ARM_RAISE_TRANSFORM, record.Progress)
					record.Right.Transform = pose
					record.Left.Transform = pose
				end
			end
		end
	end
end)

RunService.RenderStepped:Connect(function()
	local oreId = player:GetAttribute("CarryingCrystal") or ""
	if UserInputService.TouchEnabled and pickaxeSlot and crystalSlot then
		-- Пока кристалл в руках, удерживаем пару рядом. Без кристалла позицию
		-- кирки не трогаем: ей управляет mobile interaction layout, который
		-- сдвигает слот влево при появлении ProximityPrompt.
		local hasCrystal = oreId ~= ""
		crystalSlot.Position = UDim2.new(0.5, -38, 1, -20)
		if hasCrystal then
			pickaxeSlot.Position = UDim2.new(0.5, 38, 1, -20)
		end
	end
	if crystalSlot then
		crystalSlot.Visible = oreId ~= ""
		if not UserInputService.TouchEnabled then
			setPickaxeShifted(oreId ~= "")
		end
		if oreId ~= "" then
			-- Config.Geodes.Ores содержит и обычные жеодные руды, и валунные
			-- (смерджены в Config.lua) — иконка должна красиво показывать ОБЕ
			-- категории, не только 10 кастомных с валунов. ImageId меняется по
			-- айдишнику конкретного кристалла; пока картинки нет (ImageId=0 или
			-- ассет ещё не прописан) — показываем плейсхолдер "?" вместо пустоты.
			local info = Config.Geodes.Ores[oreId]
			local imageId = info and info.ImageId
			if imageId and imageId ~= 0 then
				crystalIcon.Image = "rbxassetid://" .. tostring(imageId)
				crystalIcon.ImageColor3 = Color3.new(1, 1, 1)
				crystalPlaceholder.Visible = false
			else
				crystalIcon.Image = ""
				crystalPlaceholder.Visible = true
				crystalPlaceholder.TextColor3 = info and info.Color or Color3.fromRGB(230, 230, 235)
			end
		end
	end
end)
