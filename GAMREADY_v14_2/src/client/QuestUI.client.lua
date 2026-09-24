--------------------------------------------------------------------------------
-- QuestUI (LocalScript) v20 — ТРЕКЕР + ОКНО КВЕСТОВ.
--
-- Вид целиком собирается билдером (Shared.UiBuilders.QuestUi →
-- StarterGui/QuestUi через tools/BuildAllUI.lua) и правится в Studio.
-- Этот скрипт ничего не рисует сам: только клонирует шаблоны из
-- QuestUi/Templates и заполняет их данными квестов.
--
-- ТРЕКЕР (слева снизу, над портретом): ОДИН закреплённый квест. Кандидаты —
-- текущий STORY и несданные DAILY; клик листает. Навигация к квесту —
-- через атрибуты игрока QuestNavId / QuestNavKey / QuestNavWhy /
-- QuestNavTitle (читает client/QuestMarker.client.lua, он же пишет обратно
-- QuestNavDistance).
--
-- ОКНО (кнопка 📜 в топбаре): вкладки STORY / DAILY / WEEKLY. Награды —
-- фишками, выдаются автоматически. WEEKLY — очки дейликов и три сундука.
--
-- Контракт имён для остальных скриптов: ScreenGui "QuestUi", кнопка
-- "QuestToggleButton", окно "QuestModal" (CustomCartUI прячет подсказки,
-- пока оно открыто).
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local UiSfx = require(ReplicatedStorage.Shared.UiSfx)
local Localization = require(ReplicatedStorage.Shared.Localization)
local UiRegistry = require(ReplicatedStorage.Shared.UiRegistry)
local UiKit = require(ReplicatedStorage.Shared.UiKit)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage.Shared:WaitForChild("QuestRequest")
local MARKER = Config.QuestMarker or {}
local Theme = UiKit.Theme

-- Цвет вида квеста (рамка, полоса, заголовок).
local KIND_ACCENT = {
	Story = Theme.Accents.Gold,
	Daily = Theme.Accents.Blue,
	Weekly = Theme.Accents.Purple,
}

local function tr(text, args)
	local ok, result = pcall(Localization.Translate, player.LocaleId, text, args)
	return ok and result or text
end

--------------------------------------------------------------------------------
-- ЭКРАН
--------------------------------------------------------------------------------
local gui = UiRegistry.Get("QuestUi")
gui.ResetOnSpawn = false
local toggleButton = gui:WaitForChild("QuestToggleButton")
local toggleBadge = toggleButton:FindFirstChild("Badge")
local tracker = gui:WaitForChild("QuestTracker")
local dimmer = gui:WaitForChild("Dimmer")
local modal = gui:WaitForChild("QuestModal")
local closeButton = modal:FindFirstChild("CloseButton", true)
local tabs = modal:FindFirstChild("Tabs", true)
local content = modal:FindFirstChild("List", true)
local templates = gui:WaitForChild("Templates")

-- v19.4: кнопка — в ряд со штатными кнопками Roblox в топбаре.
require(ReplicatedStorage.Shared.TopbarDock).Add(toggleButton, 1)

-- Трекер — внутри контейнера HUD, над портретом и деньгами (двигается
-- вместе с HUD, в т.ч. при мобильной раскладке). Нет HUD — левый нижний угол.
task.spawn(function()
	local hud = playerGui:WaitForChild("Hud", 15)
	local hudGui = hud and hud:WaitForChild("HudGui", 5)
	if hudGui and hudGui:IsA("GuiObject") then
		tracker.AnchorPoint = Vector2.new(0, 1)
		tracker.Position = UDim2.new(0, 0, 0, -10)
		tracker.Parent = hudGui
	end
end)
local trackerScale = tracker:FindFirstChild("ResponsiveScale") or Instance.new("UIScale")
trackerScale.Name = "ResponsiveScale"
trackerScale.Parent = tracker
local modalScale = modal:FindFirstChild("ResponsiveScale") or Instance.new("UIScale")
modalScale.Name = "ResponsiveScale"
modalScale.Parent = modal

local function clone(name)
	local template = templates:FindFirstChild(name)
	local copy = template:Clone()
	copy.Visible = true
	return copy
end

local function setBar(holder, fraction, accent)
	local bar = holder and holder:FindFirstChild("Bar", true)
	local fill = bar and bar:FindFirstChild("Fill")
	if fill then
		fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
		if accent then
			fill.BackgroundColor3 = accent.Main
			if fill.Image ~= "" then fill.ImageColor3 = accent.Main end
		end
	end
end

local function setStroke(plate, color)
	local stroke = plate:FindFirstChild("SkinStroke")
	if stroke then stroke.Color = color end
end

--------------------------------------------------------------------------------
-- СОСТОЯНИЕ
--------------------------------------------------------------------------------
local latestState = nil
local currentTab = "Story"
local modalOpen = false
local selectedId = nil -- квест, к которому ведём навигацию

local function navKeyOf(quest)
	return quest.Nav or (MARKER.MetricTargets and MARKER.MetricTargets[quest.Metric]) or nil
end

local function whyOf(quest)
	return quest.Why or (MARKER.MetricWhy and MARKER.MetricWhy[quest.Metric]) or ""
end

local function short(n)
	if n >= 1e6 then return ("%.1fM"):format(n / 1e6) end
	if n >= 1e3 then return ("%.1fK"):format(n / 1e3) end
	return tostring(math.floor(n))
end

local function progressText(quest)
	local target = tonumber(quest.Target) or 1
	local progress = math.min(tonumber(quest.Progress) or 0, target)
	if quest.Metric == "PlayTime" then
		return ("%d/%d min"):format(math.floor(progress / 60), math.floor(target / 60))
	end
	return ("%s/%s"):format(short(progress), short(target))
end

-- Активные квесты для трекера (STORY + несданные DAILY).
local function trackedQuests(state)
	local list = {}
	for _, quest in state and state.Starter or {} do
		if quest.Active then
			quest.Kind = "Story"
			table.insert(list, quest)
			break
		end
	end
	if state and state.DailyUnlocked then
		for _, quest in state.Daily or {} do
			if not quest.Claimed and not quest.Blocked then
				quest.Kind = "Daily"
				table.insert(list, quest)
			end
		end
	end
	return list
end

local function tutorialActive()
	return player:GetAttribute("NeedsTutorial") == true
end

local function applyNavigation(list)
	local chosen = nil
	for _, quest in list do
		if quest.Id == selectedId then chosen = quest end
	end
	chosen = chosen or list[1]
	selectedId = chosen and chosen.Id or nil
	local key = chosen and navKeyOf(chosen) or nil
	player:SetAttribute("QuestNavId", selectedId or "")
	player:SetAttribute("QuestNavKey", (not tutorialActive() and key) or "")
	player:SetAttribute("QuestNavWhy", chosen and whyOf(chosen) or "")
	player:SetAttribute("QuestNavTitle", chosen and (chosen.Short or chosen.Title) or "")
end

local function distanceSuffix(quest)
	local distance = tonumber(player:GetAttribute("QuestNavDistance"))
	return (navKeyOf(quest) and distance) and ("  ·  %dm"):format(math.floor(distance)) or ""
end

--------------------------------------------------------------------------------
-- ТРЕКЕР
--------------------------------------------------------------------------------
local trackerRows = {}
local collapsedRows = {} -- [questId] = true — свёрнут кнопкой «^»
local MAX_TRACKED = 1 -- v20.7: на экране только один (закреплённый Track) квест

local function titleCase(text)
	return (string.gsub(string.lower(text), "(%a)([%w']*)", function(first, rest) return string.upper(first) .. rest end))
end

-- Заголовок — название квеста, ниже — описание, строка цели — короткая
-- формулировка (Short) с прогрессом: «◇ - Clear The Way: 0/3».
local function fillTrackerRow(row, quest)
	local header = row:WaitForChild("Header")
	header.Title.Text = tr(quest.Title or quest.Short or "")
	local objective = row:FindFirstChild("Objective")
	if objective then
		local goal = quest.Short and titleCase(tr(quest.Short)) or tr("Progress")
		objective.Text.Text = ("- %s: %s%s"):format(goal, progressText(quest), distanceSuffix(quest))
	end
	local description = quest.Description and quest.Description ~= "" and quest.Description or whyOf(quest)
	row.Why.Text = tr(description)
	local collapsed = collapsedRows[quest.Id] == true
	row.Why.Visible = not collapsed and row.Why.Text ~= ""
	if objective then objective.Visible = not collapsed end
	header.Caret.Text = collapsed and "v" or "^"
end

-- v20.3: трекер как на референсе — до MAX_TRACKED квестов списком, без
-- подложек; «^» сворачивает квест до заголовка, клик по заголовку — тоже.
local function renderTracker(state)
	for _, row in trackerRows do row:Destroy() end
	trackerRows = {}
	if tutorialActive() then
		tracker.Visible = false
		return
	end
	local list = trackedQuests(state)
	applyNavigation(list)
	-- Закреплённый (Track) — первым.
	table.sort(list, function(a, b)
		if (a.Id == selectedId) ~= (b.Id == selectedId) then return a.Id == selectedId end
		return false
	end)
	tracker.Visible = #list > 0
	for index, quest in list do
		if index > MAX_TRACKED then break end
		local row = clone("TrackerRow")
		row.Name = "Row_" .. tostring(quest.Id)
		row.LayoutOrder = index
		fillTrackerRow(row, quest)
		row.Parent = tracker
		local questId = quest.Id
		row.Activated:Connect(function()
			UiSfx.play("UiButtonClick")
			collapsedRows[questId] = not collapsedRows[questId] or nil
			fillTrackerRow(row, quest)
		end)
		table.insert(trackerRows, row)
	end
end

-- Расстояние в трекере обновляется навигатором через атрибут.
player:GetAttributeChangedSignal("QuestNavDistance"):Connect(function()
	if not latestState then return end
	for _, candidate in trackedQuests(latestState) do
		local row = tracker:FindFirstChild("Row_" .. tostring(candidate.Id))
		if row then fillTrackerRow(row, candidate) end
	end
end)

--------------------------------------------------------------------------------
-- ОКНО
--------------------------------------------------------------------------------
local function clearContent()
	for _, child in content:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
end

local function addChips(holder, chips)
	if not holder then return end
	for index, chip in chips or {} do
		local label = clone("Chip")
		label.LayoutOrder = index
		label.Text = ("%s %s"):format(chip.Icon or "", chip.Text or "")
		label.Parent = holder
	end
end

local renderModal

local function questCard(quest, order, accent, done)
	if done then
		local card = clone("DoneCard")
		card.Name = "Quest_" .. tostring(quest.Id)
		card.LayoutOrder = order
		card.Title.Text = "✅ " .. tr(quest.Title or "")
		card.Parent = content
		return card
	end
	local card = clone("QuestCard")
	card.Name = "Quest_" .. tostring(quest.Id)
	card.LayoutOrder = order
	setStroke(card, accent.Main)
	card.Title.Text = tr(quest.Title or "")
	card.Title.TextColor3 = accent.Light
	card.Progress.Text = progressText(quest)
	card.Description.Text = tr(quest.Description or "")
	local why = whyOf(quest)
	card.Why.Text = why ~= "" and ("💡 " .. tr(why)) or ""
	setBar(card, (tonumber(quest.Progress) or 0) / math.max(1, tonumber(quest.Target) or 1), accent)
	addChips(card:FindFirstChild("Chips"), quest.Chips)
	-- Кнопка «вести сюда» (Track).
	local track = card:FindFirstChild("TrackButton")
	if track then
		track.Visible = navKeyOf(quest) ~= nil
		local caption = track:FindFirstChild("Caption")
		if caption then
			caption.Text = quest.Id == selectedId and tr("Tracking") or tr("Track")
		end
		track.Activated:Connect(function()
			UiSfx.play("UiButtonClick")
			selectedId = quest.Id
			renderTracker(latestState)
			renderModal()
		end)
	end
	card.Parent = content
	return card
end

local function sectionTitle(label, order, accent)
	local header = clone("SectionTitle")
	header.LayoutOrder = order
	local text = header:FindFirstChild("Label")
	if text then text.Text = label end
	local line = header:FindFirstChild("Line")
	if line and accent then
		line.BackgroundColor3 = accent.Main
		if line.Image ~= "" then line.ImageColor3 = accent.Main end
	end
	header.Parent = content
	return header
end

local function info(label, order)
	local text = clone("Info")
	text.LayoutOrder = order
	text.Text = label
	text.Parent = content
	return text
end

local function renderStory(state)
	local order = 0
	local active, done = nil, {}
	for _, quest in state.Starter or {} do
		if quest.Active then active = quest elseif quest.Completed then table.insert(done, quest) end
	end
	local accent = KIND_ACCENT.Story
	order += 1
	if active then
		sectionTitle(tr("Main Quests"), order, accent)
		order += 1
		questCard(active, order, accent, false)
	else
		sectionTitle(tr("All story quests complete!"), order, Theme.Accents.Green)
	end
	if #done > 0 then
		order += 1
		sectionTitle(tr("COMPLETED"), order, Theme.Accents.Grey)
		for index = #done, 1, -1 do
			order += 1
			questCard(done[index], order, accent, true)
		end
	end
end

local function formatLeft(seconds)
	seconds = math.max(0, math.floor(seconds))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	return hours > 0 and ("%dh %02dm"):format(hours, minutes) or ("%dm"):format(minutes)
end

local function renderDaily(state)
	local order = 1
	local accent = KIND_ACCENT.Daily
	local resets = tonumber(state.DailyResetsAt)
	sectionTitle(resets and ("%s (%s)"):format(tr("Daily Quests"), formatLeft(resets - os.time())) or tr("Daily Quests"), order, accent)
	if not state.DailyUnlocked then
		order += 1
		info(tr("Finish the tutorial to unlock daily quests."), order)
		return
	end
	for _, quest in state.Daily or {} do
		order += 1
		local card = questCard(quest, order, accent, quest.Claimed == true)
		if not quest.Claimed then
			local points = card:FindFirstChild("Points")
			if points then
				points.Visible = true
				points.Text = ("+%d ⭐"):format(tonumber(quest.WeeklyPoints) or 0)
			end
			local blocked = card:FindFirstChild("Blocked")
			if blocked and quest.Blocked then
				blocked.Visible = true
				blocked.Text = tr("Needs 2+ players on the server")
				card.Why.Visible = false
			end
		end
	end
end

local function renderWeekly(state)
	local accent = KIND_ACCENT.Weekly
	local points = tonumber(state.WeeklyPoints) or 0
	local chests = state.Weekly or {}
	local maxPoints = 1
	for _, chest in chests do maxPoints = math.max(maxPoints, chest.Points) end
	sectionTitle(tr("WEEKLY POINTS: {p}", { p = tostring(points) }), 1, accent)
	local weekly = clone("WeeklyBar")
	weekly.LayoutOrder = 2
	setBar(weekly, points / maxPoints, accent)
	weekly.Parent = content
	info(tr("Complete daily quests to earn ⭐. Chests are sent to your inventory."), 3)
	for index, chest in chests do
		local chestInfo = Config.Chests.Types[chest.Rarity]
		local card = clone("ChestCard")
		card.LayoutOrder = 3 + index
		local color = chestInfo and chestInfo.Color or accent.Main
		setStroke(card, color)
		card.Title.Text = ("🎁 %s"):format(chestInfo and chestInfo.DisplayName or chest.Rarity)
		card.Title.TextColor3 = color
		card.Status.Text = chest.Claimed and ("✅ " .. tr("RECEIVED")) or ("%d/%d ⭐"):format(math.min(points, chest.Points), chest.Points)
		card.Status.TextColor3 = chest.Claimed and Theme.Colors.Positive or Theme.Colors.SubText
		card.Parent = content
	end
end

renderModal = function()
	if not (modalOpen and latestState) then return end
	clearContent()
	if tabs then UiKit.SetTabActive(tabs, currentTab .. "Tab") end
	if currentTab == "Story" then
		renderStory(latestState)
	elseif currentTab == "Daily" then
		renderDaily(latestState)
	else
		renderWeekly(latestState)
	end
end

for _, id in { "Story", "Daily", "Weekly" } do
	local button = tabs and tabs:FindFirstChild(id .. "Tab")
	if button then
		button.Activated:Connect(function()
			UiSfx.play("UiButtonClick")
			currentTab = id
			renderModal()
		end)
	end
end

local function fitModalScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local width = modal:GetAttribute("BaseWidth") or modal.Size.X.Offset
	local height = modal:GetAttribute("BaseHeight") or modal.Size.Y.Offset
	return math.min(1, (viewport.X - 24) / math.max(width, 1), (viewport.Y - 60) / math.max(height, 1))
end

local function openModal()
	if modalOpen then return end
	modalOpen = true
	modal.Visible = true
	dimmer.Visible = true
	UiSfx.play("UiMenuOpen")
	local target = fitModalScale()
	modalScale.Scale = target * 0.85
	TweenService:Create(modalScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
	renderModal()
	remote:FireServer("RequestState")
end

local function closeModal()
	if not modalOpen then return end
	modalOpen = false
	modal.Visible = false
	dimmer.Visible = false
	UiSfx.play("UiMenuClose")
end

toggleButton.Activated:Connect(function()
	if modalOpen then closeModal() else openModal() end
end)
if closeButton then closeButton.Activated:Connect(closeModal) end
dimmer.Activated:Connect(closeModal)
UserInputService.InputBegan:Connect(function(input)
	if modalOpen and input.KeyCode == Enum.KeyCode.Escape then closeModal() end
end)

--------------------------------------------------------------------------------
-- СЕТЬ
--------------------------------------------------------------------------------
local function render(state)
	if type(state) ~= "table" then return end
	latestState = state
	toggleButton.Visible = not tutorialActive()
	-- Точка на кнопке: есть несданные дейлики.
	local pendingDaily = false
	for _, quest in state.Daily or {} do
		if not quest.Claimed then pendingDaily = true end
	end
	if toggleBadge then toggleBadge.Visible = pendingDaily and state.DailyUnlocked == true end
	renderTracker(state)
	renderModal()
end

remote.OnClientEvent:Connect(function(action, state)
	if action == "State" or action == "Open" then render(state) end
end)
remote:FireServer("RequestState")
task.delay(1, function()
	if not latestState then remote:FireServer("RequestState") end
end)

player:GetAttributeChangedSignal("NeedsTutorial"):Connect(function()
	if latestState then render(latestState) end
end)

local function fitTracker()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	trackerScale.Scale = math.clamp(viewport.Y / 820, 0.7, 1)
	if modalOpen then modalScale.Scale = fitModalScale() end
end
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitTracker)
end
fitTracker()
