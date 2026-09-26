--------------------------------------------------------------------------------
-- BaseNameMarkers (LocalScript) v20.43 — МЕТКА НАД КАЖДОЙ БАЗОЙ: аватарка
-- владельца и «<ник>'s Base» (TextScaled). Раньше метка была только над
-- своей базой; теперь видно, чья база чья.
--
-- Владелец берётся из атрибута OwnerUserId у PlotPad (ставит PlotService).
-- Метка держит постоянный размер на экране (размер в стадах ∝ расстоянию
-- до камеры) и прячется, когда ТЫ стоишь на этой базе (не мешает обзору).
-- Своя база — зелёная обводка аватарки, чужие — белая.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiKit = require(ReplicatedStorage.Shared.UiKit)

local player = Players.LocalPlayer

local MARKER_NAME = "BaseNameMarker"
local REFERENCE_DISTANCE = 30 -- на этом расстоянии метка REFERENCE_WIDTH × REFERENCE_HEIGHT стадов
local REFERENCE_WIDTH = 9.6
local REFERENCE_HEIGHT = 8.0
local HIDE_RADIUS = 35 -- ближе к центру базы — метка этой базы скрыта
local HEIGHT = 52

local markers = {} -- [pad] = { Gui, UserId }

local function padOf(plot)
	if not plot:IsA("Model") then return nil end
	local pad = plot.PrimaryPart or plot:FindFirstChild("PlotPad", true)
	return pad and pad:IsA("BasePart") and pad or nil
end

local function removeMarker(pad)
	local entry = markers[pad]
	if entry and entry.Gui then entry.Gui:Destroy() end
	markers[pad] = nil
end

local function buildMarker(pad, userId)
	removeMarker(pad)
	if not userId then return end
	local owner = Players:GetPlayerByUserId(userId)
	local name = owner and (owner.DisplayName ~= "" and owner.DisplayName or owner.Name) or nil

	local gui = Instance.new("BillboardGui")
	gui.Name = MARKER_NAME
	gui.Size = UDim2.fromScale(REFERENCE_WIDTH, REFERENCE_HEIGHT)
	gui.StudsOffset = Vector3.new(0, HEIGHT, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 500
	gui.Adornee = pad
	gui.ResetOnSpawn = false

	-- Аватарка — круг (поправка на неквадратный холст).
	local avatarHeight = 0.62
	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.AnchorPoint = Vector2.new(0.5, 0)
	avatar.Position = UDim2.fromScale(0.5, 0.02)
	avatar.Size = UDim2.fromScale(avatarHeight * (REFERENCE_HEIGHT / REFERENCE_WIDTH), avatarHeight)
	avatar.BackgroundColor3 = Color3.fromRGB(120, 75, 45)
	avatar.ScaleType = Enum.ScaleType.Fit
	avatar.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = avatar
	local ring = Instance.new("UIStroke")
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ring.Thickness = 4
	ring.Color = userId == player.UserId and Color3.fromRGB(120, 220, 90) or Color3.fromRGB(240, 240, 240)
	ring.Parent = avatar

	local label = Instance.new("TextLabel")
	label.Name = "NameLabel"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, 0.66)
	label.Size = UDim2.fromScale(1.2, 0.34)
	label.BackgroundTransparency = 1
	UiKit.StyleText(label, "Number")
	label.TextScaled = true
	label.TextWrapped = false
	label.TextColor3 = userId == player.UserId and Color3.fromRGB(255, 225, 90) or Color3.fromRGB(255, 255, 255)
	label.Text = name and ("%s's Base"):format(name) or "Base"
	label.Parent = gui
	local stroke = label:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(20, 20, 25)
	stroke.Parent = label

	-- v20.46: в PlayerGui, а не в сам участок: с StreamingEnabled часть
	-- участка выгружается и метка пропадала вместе с ней.
	local playerGui = player:FindFirstChild("PlayerGui")
	gui.Parent = playerGui or pad
	markers[pad] = { Gui = gui, UserId = userId }

	task.spawn(function()
		local ok, content = pcall(function()
			local thumb, ready = Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
			return ready and thumb or nil
		end)
		if ok and content and avatar.Parent then
			avatar.Image = content
			avatar.BackgroundTransparency = 1
		end
		-- Ник мог быть неизвестен (игрок ещё не пришёл в список).
		if not name and label.Parent then
			local okName, fetched = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
			if okName and fetched then label.Text = ("%s's Base"):format(fetched) end
		end
	end)
end

local function watchPlot(plot)
	local pad = padOf(plot)
	if not pad or markers[pad] ~= nil then return end
	markers[pad] = false
	local function refresh()
		local userId = tonumber(pad:GetAttribute("OwnerUserId"))
		local current = markers[pad]
		if current and current.UserId == userId then return end
		buildMarker(pad, userId)
		if not markers[pad] then markers[pad] = false end
	end
	pad:GetAttributeChangedSignal("OwnerUserId"):Connect(refresh)
	pad.AncestryChanged:Connect(function()
		if not pad:IsDescendantOf(workspace) then removeMarker(pad) end
	end)
	refresh()
end

-- v20.46: StreamingEnabled — PlotPad может догрузиться позже или
-- выгрузиться и прийти заново (новый объект). Раз в секунду досматриваем.
local function scanPlots(plots)
	for _, plot in plots:GetChildren() do
		local pad = padOf(plot)
		if pad and markers[pad] == nil then watchPlot(plot) end
	end
	for pad in markers do
		if not pad:IsDescendantOf(workspace) then removeMarker(pad) end
	end
end

task.spawn(function()
	local plots = workspace:WaitForChild("Plots", 30)
	if not plots then return end
	for _, plot in plots:GetChildren() do watchPlot(plot) end
	plots.ChildAdded:Connect(function(plot)
		task.defer(watchPlot, plot)
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			pcall(scanPlots, plots)
		end
	end)
	-- Ник пришедшего игрока: перестроить метку его базы.
	Players.PlayerAdded:Connect(function(other)
		for pad, entry in markers do
			if entry and entry.UserId == other.UserId then buildMarker(pad, other.UserId) end
		end
	end)
	while true do
		local camera = workspace.CurrentCamera
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		for pad, entry in markers do
			if entry and entry.Gui.Parent then
				if root then
					local flat = Vector3.new(root.Position.X - pad.Position.X, 0, root.Position.Z - pad.Position.Z)
					entry.Gui.Enabled = flat.Magnitude > HIDE_RADIUS
				else
					entry.Gui.Enabled = true
				end
				if camera then
					local factor = math.max((camera.CFrame.Position - pad.Position).Magnitude, 1) / REFERENCE_DISTANCE
					entry.Gui.Size = UDim2.fromScale(REFERENCE_WIDTH * factor, REFERENCE_HEIGHT * factor)
				end
			end
		end
		task.wait(0.2)
	end
end)
