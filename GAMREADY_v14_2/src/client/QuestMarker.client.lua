--------------------------------------------------------------------------------
-- QuestMarker (LocalScript) v16 — НАВИГАЦИЯ К ЦЕЛИ КВЕСТА.
--
-- Куда вести, решает QuestUI: он ставит ЛОКАЛЬНЫЕ атрибуты игрока
--   QuestNavKey   — вид цели (Bank, UpgradeShopNPC, Boulder, Mine, …);
--   QuestNavWhy   — «зачем» (показывается в трекере);
-- а этот скрипт рисует:
--   • ТРЕЙЛ от ног до цели — тот же скроллящийся луч, что в обучении
--     (Config.Tutorial.Trail*); ближе Config.QuestMarker.ArriveDistance —
--     прячется;
--   • ЗНАК «!» над целью (PlaceholderFactory.QuestMarker, своя модель —
--     ReplicatedStorage.Assets.QuestMarker);
--   • ШЕВРОН у ног, повёрнутый к цели;
--   • СТРЕЛКУ у края экрана, если цель вне кадра;
--   • РАССТОЯНИЕ — в атрибут QuestNavDistance (его показывает трекер).
-- Во время обучения молчит (там свой трейл).
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local cfg = Config.QuestMarker
local tutorialCfg = Config.Tutorial or {}

if not cfg or cfg.Enabled == false then
	return
end

--------------------------------------------------------------------------------
-- ПОИСК ЦЕЛЕЙ
--------------------------------------------------------------------------------
local function ownPlotPad()
	local plots = workspace:FindFirstChild("Plots")
	local plotIndex = player:GetAttribute("PlotIndex")
	local plot = plots and plotIndex and plots:FindFirstChild("PlotPad_" .. tostring(plotIndex))
	return plot and (plot.PrimaryPart or plot:FindFirstChild("PlotPad", true)) or nil
end

local function ownPlotContent()
	local pad = ownPlotPad()
	return pad and pad:FindFirstChild("Content_" .. player.Name)
end

local function rootPosition()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root.Position or nil
end

local function nearestBreakableBoulder()
	local origin = rootPosition()
	if not origin then return nil end
	local pickaxeTier = tonumber(player:GetAttribute("PickaxeTier")) or 1
	local best, bestDistance = nil, math.huge
	for _, model in workspace:GetChildren() do
		if model:IsA("Model") and model:GetAttribute("IsRubbleBoulder") == true then
			local tier = tonumber(model:GetAttribute("Tier")) or 1
			local health = tonumber(model:GetAttribute("Health")) or 0
			if health > 0 and (tier - pickaxeTier) < 3 and model.PrimaryPart then
				local distance = (model.PrimaryPart.Position - origin).Magnitude
				if distance < bestDistance then best, bestDistance = model, distance end
			end
		end
	end
	return best
end

local function nearestOtherPlayer()
	local origin = rootPosition()
	if not origin then return nil end
	local best, bestDistance = nil, math.huge
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local character = other.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0 then
				local distance = (root.Position - origin).Magnitude
				if distance < bestDistance then best, bestDistance = character, distance end
			end
		end
	end
	return best
end

local function inContent(...)
	local contentFolder = ownPlotContent()
	if not contentFolder then return nil end
	for _, name in { ... } do
		local found = contentFolder:FindFirstChild(name, true)
		if found then return found end
	end
	return nil
end

local resolvers = {
	Bank = function() return workspace:FindFirstChild("SellZone", true) end,
	Boulder = nearestBreakableBoulder,
	NearestPlayer = nearestOtherPlayer,
	UpgradeShopNPC = function() return inContent("UpgradeShopNPC") end,
	RebirthNPC = function() return inContent("RebirthNPC") end,
	PrestigeCase = function() return inContent("PrestigeCase", "RebirthNPC") end,
	GeodeVault = function() return inContent("Crusher", "GeodeBuilding") end,
	GeodeSafe = function() return inContent("GeodeSafe", "GeodePodium") end,
	Mine = function() return inContent("ENTRY", "Entry", "MineDoor") end,
	PlotBase = function() return ownPlotPad() end,
	Merchant = function() return workspace:FindFirstChild("BankMerchant") or workspace:FindFirstChild("SellZone", true) end,
	IslandKeeper = function()
		return workspace:FindFirstChild("IslandKeeperNPC", true) or workspace:FindFirstChild("IslandKeeper", true)
			or workspace:FindFirstChild("IslandKeeperMarker", true)
	end,
}
-- Цели, которые двигаются или меняются, — перерешаем каждую секунду.
local DYNAMIC = { Boulder = true, NearestPlayer = true }

local function anchorOf(target)
	if not target or not target.Parent then return nil end
	if target:IsA("Model") then
		local ok, cframe, size = pcall(target.GetBoundingBox, target)
		if ok and cframe then
			return cframe.Position + Vector3.new(0, size.Y * 0.5, 0), cframe.Position - Vector3.new(0, size.Y * 0.5, 0)
		end
		local primary = target.PrimaryPart
		if primary then
			return primary.Position + Vector3.new(0, primary.Size.Y * 0.5, 0), primary.Position - Vector3.new(0, primary.Size.Y * 0.5, 0)
		end
		return nil
	end
	if target:IsA("BasePart") then
		return target.Position + Vector3.new(0, target.Size.Y * 0.5, 0), target.Position - Vector3.new(0, target.Size.Y * 0.5, 0)
	end
	if target:IsA("Folder") then
		local part = target:FindFirstChildWhichIsA("BasePart", true)
		return part and anchorOf(part)
	end
	return nil
end

--------------------------------------------------------------------------------
-- ВИЗУАЛ
--------------------------------------------------------------------------------
local folder = Instance.new("Folder")
folder.Name = "QuestNavigation"
folder.Parent = workspace

local function invisiblePart(name)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.one * 0.2
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Parent = folder
	return p
end

-- Трейл (как в обучении).
local trailAnchor = invisiblePart("QuestTrailEnd")
local trailEnd = Instance.new("Attachment")
trailEnd.Parent = trailAnchor
local trail = Instance.new("Beam")
trail.Name = "QuestTrail"
trail.Width0 = tutorialCfg.TrailWidth or 2.2
trail.Width1 = tutorialCfg.TrailWidth or 2.2
trail.FaceCamera = true
trail.Color = ColorSequence.new(cfg.Color or tutorialCfg.TrailColor or Color3.fromRGB(255, 215, 90))
trail.Attachment1 = trailEnd
trail.Enabled = false
if (tutorialCfg.TrailTextureId or 0) ~= 0 then
	trail.Texture = "rbxassetid://" .. tutorialCfg.TrailTextureId
	trail.TextureMode = Enum.TextureMode.Wrap
	trail.TextureLength = tutorialCfg.TrailTextureLength or 4
	trail.TextureSpeed = tutorialCfg.TrailScrollSpeed or 3
end
trail.Parent = trailAnchor

local trailStart = nil
local function attachToCharacter(character)
	local root = character and character:WaitForChild("HumanoidRootPart", 10)
	if not root then return end
	if trailStart then trailStart:Destroy() end
	trailStart = Instance.new("Attachment")
	trailStart.Name = "QuestTrailStart"
	trailStart.Position = Vector3.new(0, -2.2, 0)
	trailStart.Parent = root
	trail.Attachment0 = trailStart
end
if player.Character then task.spawn(attachToCharacter, player.Character) end
player.CharacterAdded:Connect(attachToCharacter)

-- Шеврон у ног.
local chevron = Instance.new("Part")
chevron.Name = "QuestChevron"
chevron.Size = Vector3.new(2, 0.05, 2)
chevron.Transparency = 1
chevron.Anchored = true
chevron.CanCollide = false
chevron.CanQuery = false
chevron.CanTouch = false
-- v20: вид шеврона и стрелки — Shared.UiBuilders.QuestMarkerUi
-- (StarterGui/QuestMarkerUi; свою картинку клади в Image — надпись спрячется).
local markerUi = require(ReplicatedStorage.Shared.UiRegistry).Get("QuestMarkerUi")
local markerColor = cfg.Color or Color3.fromRGB(255, 215, 90)
local function paintGlyph(holder, transparency)
	local image = holder:FindFirstChild("Image")
	local glyph = holder:FindFirstChild("Glyph")
	local hasImage = image and image.Image ~= ""
	if image then image.ImageColor3 = markerColor end
	if glyph then
		glyph.TextColor3 = markerColor
		glyph.TextTransparency = transparency or 0
		glyph.Visible = not hasImage
	end
end
local chevronGui = markerUi:WaitForChild("Templates"):WaitForChild("Chevron"):Clone()
chevronGui.Parent = chevron
paintGlyph(chevronGui, 0.15)

-- Стрелка у края экрана.
local edgeArrow = markerUi:WaitForChild("EdgeArrow")
paintGlyph(edgeArrow, 0)
edgeArrow.Visible = false

-- Знак «!».
local marker = nil
local function ensureMarker()
	if marker and marker.Parent then return marker end
	local ok, model, isCustomAsset = pcall(PlaceholderFactory.QuestMarker)
	if not ok or not model then return nil end
	model.Name = "QuestMarker"
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			if not isCustomAsset and cfg.Color and descendant.Name ~= "__keepColor" then
				descendant.Color = cfg.Color
			end
		end
	end
	marker = model
	return marker
end

--------------------------------------------------------------------------------
-- ЦИКЛ
--------------------------------------------------------------------------------
local currentKey = ""
local currentTarget = nil

local function hideAll()
	trail.Enabled = false
	chevron.Parent = nil
	edgeArrow.Visible = false
	if marker then marker.Parent = nil end
end

local function resolve()
	local key = player:GetAttribute("QuestNavKey") or ""
	if player:GetAttribute("NeedsTutorial") == true then key = "" end
	currentKey = key
	local resolver = resolvers[key]
	currentTarget = resolver and resolver() or nil
end

player:GetAttributeChangedSignal("QuestNavKey"):Connect(resolve)
player:GetAttributeChangedSignal("NeedsTutorial"):Connect(resolve)
task.spawn(function()
	while true do
		task.wait(cfg.RefreshInterval or 1)
		if DYNAMIC[currentKey] or not (currentTarget and currentTarget.Parent) then
			pcall(resolve)
		end
	end
end)

local lastDistanceSent = 0
RunService.RenderStepped:Connect(function()
	local top, bottom = anchorOf(currentTarget)
	local origin = rootPosition()
	if currentKey == "" or not top or not origin then
		hideAll()
		if currentKey == "" and player:GetAttribute("QuestNavDistance") ~= nil then
			player:SetAttribute("QuestNavDistance", nil)
		end
		return
	end
	local flat = Vector3.new(bottom.X, origin.Y, bottom.Z)
	local distance = (flat - origin).Magnitude
	local now = os.clock()
	if now - lastDistanceSent > 0.3 then
		lastDistanceSent = now
		player:SetAttribute("QuestNavDistance", math.floor(distance))
	end
	if distance > (cfg.MaxVisibleDistance or 2000) then
		hideAll()
		return
	end
	local arrived = distance <= (cfg.ArriveDistance or 12)

	-- Знак над целью.
	if ensureMarker() then
		marker.Parent = folder
		local clock = os.clock()
		local bob = math.sin(clock * (2 * math.pi) / (cfg.BobPeriod or 2.6)) * (cfg.BobAmplitude or 0.35)
		local spin = (clock % (cfg.SpinPeriod or 6)) / (cfg.SpinPeriod or 6) * (2 * math.pi)
		marker:PivotTo(CFrame.new(top + Vector3.new(0, (cfg.Height or 5.5) + bob, 0)) * CFrame.Angles(0, spin, 0))
	end

	-- Трейл до цели (у земли цели).
	trailAnchor.CFrame = CFrame.new(Vector3.new(bottom.X, math.max(bottom.Y, origin.Y - 3), bottom.Z) + Vector3.new(0, 0.3, 0))
	trail.Enabled = cfg.TrailEnabled ~= false and not arrived and trail.Attachment0 ~= nil

	-- Шеврон у ног.
	if not arrived then
		local direction = (flat - origin)
		direction = direction.Magnitude > 0.1 and direction.Unit or Vector3.new(0, 0, -1)
		local base = origin + direction * 3.2 - Vector3.new(0, 2.8, 0)
		chevron.CFrame = CFrame.lookAt(base, base + direction)
		chevron.Parent = folder
	else
		chevron.Parent = nil
	end

	-- Стрелка у края экрана, если цель вне кадра.
	local camera = workspace.CurrentCamera
	if camera then
		local screen, onScreen = camera:WorldToViewportPoint(top)
		if onScreen then
			edgeArrow.Visible = false
		else
			local viewport = camera.ViewportSize
			local center = viewport / 2
			local offset = Vector2.new(screen.X, screen.Y) - center
			if screen.Z < 0 then offset = -offset end
			if offset.Magnitude < 1 then offset = Vector2.new(0, -1) end
			local dir = offset.Unit
			local margin = 40
			local scaleX = (center.X - margin) / math.max(0.001, math.abs(dir.X))
			local scaleY = (center.Y - margin) / math.max(0.001, math.abs(dir.Y))
			local position = center + dir * math.min(scaleX, scaleY)
			edgeArrow.Position = UDim2.fromOffset(position.X, position.Y)
			edgeArrow.Rotation = math.deg(math.atan2(dir.Y, dir.X))
			edgeArrow.Visible = true
		end
	end
end)

resolve()
