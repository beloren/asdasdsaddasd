--------------------------------------------------------------------------------
-- LikeGoalService (v16) — ТАБЛО ЦЕЛЕЙ ПО ЛАЙКАМ (см. Config.LikeGoals).
--
-- Табло в мире у спавна: прогресс-бар «лайков сейчас / следующая цель» и
-- список целей с ✔/🔒. Достигнутая цель Code показывает промокод, Event
-- включает ивент для всех (GetEventMultiplier читает MonetizationService).
-- Число лайков скрипт прочитать не может — Config.LikeGoals.CurrentLikes
-- обновляется вручную (и игра публикуется заново).
--
-- Своя деталь: Workspace/LikeGoalBoard (Part). SurfaceGui кладётся на её
-- грань Front. Нет детали — ставится плейсхолдер-щит у SpawnLocation.
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local WorldUi = require(ReplicatedStorage.Shared.WorldUi) -- v20: стили мировых надписей (StarterGui/WorldUiTemplates)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)

local LikeGoalService = {}
local CFG = Config.LikeGoals or { Goals = {} }

local function parseDate(value)
	if typeof(value) == "number" then return value end
	if typeof(value) ~= "string" then return nil end
	local year, month, day = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if not year then return nil end
	local ok, dateTime = pcall(DateTime.fromUniversalTime, tonumber(year), tonumber(month), tonumber(day), 23, 59, 59)
	return ok and dateTime.UnixTimestamp or nil
end

local function likes()
	return math.max(0, math.floor(tonumber(CFG.CurrentLikes) or 0))
end

local function reached(goal)
	return likes() >= (tonumber(goal.Likes) or math.huge)
end

local function eventActive(goal)
	if not (CFG.Enabled and goal.Kind == "Event" and reached(goal)) then return false end
	local endsAt = parseDate(goal.EndsAt)
	return endsAt == nil or os.time() <= endsAt
end

-- Множитель активного ивента данного вида (Money / Luck). 1 — ивента нет.
function LikeGoalService:GetEventMultiplier(eventKind)
	local multiplier = 1
	for _, goal in CFG.Goals or {} do
		if goal.Event == eventKind and eventActive(goal) then
			multiplier = math.max(multiplier, tonumber(goal.Multiplier) or 1)
		end
	end
	return multiplier
end

--------------------------------------------------------------------------------
-- ТАБЛО
--------------------------------------------------------------------------------
local function findBoardPart()
	local part = workspace:FindFirstChild("LikeGoalBoard", true)
	if part and part:IsA("BasePart") then return part end
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local base = spawn and spawn.CFrame or CFrame.new(0, 0, 0)
	part = Instance.new("Part")
	part.Name = "LikeGoalBoard"
	part.Anchored = true
	part.Size = Vector3.new(12, 9, 0.6)
	part.Color = Color3.fromRGB(40, 36, 52)
	part.Material = Enum.Material.SmoothPlastic
	-- Рядом со спавном, лицом (Front) к нему.
	local position = base.Position + base.RightVector * 14 + Vector3.new(0, 5.5, 0)
	part.CFrame = CFrame.lookAt(position, Vector3.new(base.Position.X, position.Y, base.Position.Z))
	part.Parent = workspace
	return part
end

local function label(parent, props)
	local l = WorldUi.Text(nil, "Text", "Heading")
	l.BackgroundTransparency = 1
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	for key, value in props do l[key] = value end
	l.Parent = parent
	return l
end

function LikeGoalService:_buildBoard()
	local part = findBoardPart()
	local old = part:FindFirstChild("LikeGoalGui")
	if old then old:Destroy() end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LikeGoalGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Parent = part
	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(30, 24, 52)
	root.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.04, 0)
	pad.PaddingLeft = UDim.new(0.05, 0)
	pad.PaddingRight = UDim.new(0.05, 0)
	pad.Parent = root
	label(root, { Text = CFG.Title or "LIKE GOALS", Size = UDim2.fromScale(1, 0.13), TextColor3 = Color3.fromRGB(255, 215, 80) })
	label(root, { Text = CFG.Subtitle or "", Size = UDim2.fromScale(1, 0.07), Position = UDim2.fromScale(0, 0.13) })

	-- Прогресс до следующей цели.
	local nextGoal = nil
	for _, goal in CFG.Goals or {} do
		if not reached(goal) then nextGoal = goal break end
	end
	local barBack = Instance.new("Frame")
	barBack.Position = UDim2.fromScale(0, 0.23)
	barBack.Size = UDim2.fromScale(1, 0.1)
	barBack.BackgroundColor3 = Color3.fromRGB(15, 12, 25)
	barBack.Parent = root
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = barBack
	local fill = Instance.new("Frame")
	local target = nextGoal and nextGoal.Likes or math.max(1, likes())
	fill.Size = UDim2.fromScale(math.clamp(likes() / target, 0.02, 1), 1)
	fill.BackgroundColor3 = Color3.fromRGB(90, 220, 110)
	fill.Parent = barBack
	corner:Clone().Parent = fill
	label(barBack, {
		Text = nextGoal and ("👍 %s / %s"):format(NumberFormat.abbreviate(likes()), NumberFormat.abbreviate(nextGoal.Likes))
			or ("👍 %s — ALL GOALS REACHED!"):format(NumberFormat.abbreviate(likes())),
		Size = UDim2.fromScale(1, 1), ZIndex = 3,
	})

	-- Список целей.
	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromScale(0, 0.37)
	list.Size = UDim2.fromScale(1, 0.6)
	list.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0.03, 0)
	layout.Parent = list
	local count = math.max(1, #(CFG.Goals or {}))
	for index, goal in CFG.Goals or {} do
		local done = reached(goal)
		local text
		if done and goal.Kind == "Code" then
			text = ("✔ %s  —  CODE: %s"):format(NumberFormat.abbreviate(goal.Likes), tostring(goal.Code))
		elseif done and goal.Kind == "Event" then
			text = ("✔ %s  —  %s %s"):format(NumberFormat.abbreviate(goal.Likes), goal.Text or "", eventActive(goal) and "(ACTIVE!)" or "(ended)")
		else
			text = ("%s %s  —  %s"):format(done and "✔" or "🔒", NumberFormat.abbreviate(goal.Likes), goal.Text or "")
		end
		label(list, {
			Text = text, LayoutOrder = index, Size = UDim2.fromScale(1, 1 / count - 0.03),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = done and Color3.fromRGB(120, 255, 150) or Color3.fromRGB(200, 200, 215),
		})
	end
end

function LikeGoalService:Init(_services) end

function LikeGoalService:Start()
	if not CFG.Enabled then return end
	local ok, err = pcall(function() self:_buildBoard() end)
	if not ok then warn("[LikeGoalService] Табло не построено:", err) end
	-- Ивенты с EndsAt гаснут сами — раз в минуту перерисовываем табло.
	task.spawn(function()
		while true do
			task.wait(60)
			pcall(function() self:_buildBoard() end)
		end
	end)
	-- Атрибуты активных ивентов (для HUD и отладки).
	for _, goal in CFG.Goals or {} do
		if eventActive(goal) then
			workspace:SetAttribute("LikeEvent_" .. tostring(goal.Event), tonumber(goal.Multiplier) or 2)
		end
	end
end

return LikeGoalService
