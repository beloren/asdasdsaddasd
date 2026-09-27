--------------------------------------------------------------------------------
-- BenchChatter (LocalScript) - РЕПЛИКИ НА СКАМЕЙКЕ.
--
-- Игрок сел на декор-скамейку (Seat внутри модели с BaseDecorUid) - над его
-- головой почти сразу выскакивает реплика и печатается по одной букве.
-- Просидел дольше - следующая реплика. Встал - реплика пропадает.
-- Каждый клиент рисует это сам для всех игроков, по сети ничего не шлётся.
-- Тексты и тайминги - Config.BenchChatter.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldUi = require(ReplicatedStorage.Shared.WorldUi)

local CFG = Config.BenchChatter or {}
local tokens = {} -- [character] = число; меняется при каждом сесть/встать

local function isDecorSeat(seat)
	local node = seat
	while node and node ~= workspace do
		if node:IsA("Model") and node:GetAttribute("BaseDecorUid") ~= nil then return true end
		node = node.Parent
	end
	return false
end

local function clearBubble(character)
	local head = character and character:FindFirstChild("Head")
	local old = head and head:FindFirstChild("BenchChatter")
	if old then old:Destroy() end
end

local function say(character, text, token)
	local head = character:FindFirstChild("Head")
	if not head then return end
	clearBubble(character)

	local width = CFG.WidthStuds or 9
	local height = CFG.HeightStuds or 1.5
	local gui = Instance.new("BillboardGui")
	gui.Name = "BenchChatter"
	gui.Adornee = head
	gui.Size = UDim2.new(width * 0.6, 0, height * 0.6, 0)
	gui.StudsOffset = Vector3.new(0, CFG.HeightOffset or 2.4, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = CFG.MaxDistance or 70
	gui.ResetOnSpawn = false
	gui.Parent = head

	local label = WorldUi.Text(gui, "Line", "Heading")
	label.TextScaled = true
	label.TextColor3 = CFG.TextColor or Color3.fromRGB(255, 255, 255)
	label.Text = text
	label.MaxVisibleGraphemes = 0

	-- Выскакивает с лёгким пружинным «поп».
	TweenService:Create(gui, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(width, 0, height, 0),
	}):Play()

	local count = utf8.len(text) or #text
	local perChar = CFG.SecondsPerLetter or 0.06
	for i = 1, count do
		if tokens[character] ~= token or not gui.Parent then return end
		label.MaxVisibleGraphemes = i
		local char = utf8.char(utf8.codepoint(text, utf8.offset(text, i)))
		-- На точках и запятых - короткая пауза, как в живой речи.
		task.wait((char == "." or char == "," or char == "!" or char == "?") and perChar * 3 or perChar)
	end
	label.MaxVisibleGraphemes = -1

	task.wait(CFG.HoldSeconds or 4)
	if tokens[character] ~= token or not gui.Parent then return end
	local fade = TweenInfo.new(0.5)
	TweenService:Create(label, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	for _, stroke in label:GetDescendants() do
		if stroke:IsA("UIStroke") then TweenService:Create(stroke, fade, { Transparency = 1 }):Play() end
	end
	task.wait(0.5)
	if gui.Parent then gui:Destroy() end
end

local function watchCharacter(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end
	tokens[character] = 0
	local function onSeat()
		tokens[character] = (tokens[character] or 0) + 1
		local token = tokens[character]
		clearBubble(character)
		local seat = humanoid.SeatPart
		if not (seat and isDecorSeat(seat)) then return end
		for _, line in CFG.Lines or {} do
			task.delay(line.At or 0, function()
				if tokens[character] ~= token or humanoid.SeatPart ~= seat then return end
				say(character, tostring(line.Text or ""), token)
			end)
		end
	end
	humanoid:GetPropertyChangedSignal("SeatPart"):Connect(onSeat)
	character.AncestryChanged:Connect(function()
		if not character.Parent then tokens[character] = nil end
	end)
	if humanoid.SeatPart then onSeat() end
end

local function watchPlayer(player)
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then task.spawn(watchCharacter, player.Character) end
end

if CFG.Enabled ~= false then
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do task.spawn(watchPlayer, player) end
end
