--------------------------------------------------------------------------------
-- QuestUI (LocalScript) v16 — ТРЕКЕР + ОКНО КВЕСТОВ.
--
-- ТРЕКЕР (слева, всегда на экране вне обучения): ОДИН закреплённый квест
-- (v17). Кандидаты — текущий STORY и несданные DAILY; клик листает. У каждого прогресс-бар; у выбранного
-- для навигации — 📍, строка «зачем» и расстояние до цели. Клик по строке —
-- вести навигацию к этому квесту (client/QuestMarker.client.lua читает
-- локальные атрибуты игрока QuestNavId / QuestNavKey / QuestNavWhy /
-- QuestNavTitle и пишет обратно QuestNavDistance).
--
-- ОКНО (кнопка 📜 в левом верхнем углу): вкладки STORY / DAILY / WEEKLY.
-- Награды — фишками (деньги, динамит, зелья, сундуки, жеоды, тотемы, очки
-- престижа), выдаются автоматически в момент выполнения. WEEKLY —
-- очки дейликов и три недельных сундука.
--
-- Контракт имён для остальных скриптов: ScreenGui "QuestUi", кнопка
-- "QuestToggleButton" (36×36 в (0,0) — рядом встаёт кнопка ежедневной
-- награды), окно "QuestModal" (CustomCartUI прячет подсказки, пока оно
-- открыто). Старый ассет StarterGui/QuestUi заменяется автоматически.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local UiSfx = require(ReplicatedStorage.Shared.UiSfx)
local Localization = require(ReplicatedStorage.Shared.Localization)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage.Shared:WaitForChild("QuestRequest")
local MARKER = Config.QuestMarker or {}
local UI_VERSION = 16

local COLORS = {
	Panel = Color3.fromRGB(28, 26, 40),
	Deep = Color3.fromRGB(18, 16, 28),
	Ink = Color3.fromRGB(10, 8, 18),
	Story = Color3.fromRGB(255, 205, 80),
	Daily = Color3.fromRGB(105, 210, 255),
	Weekly = Color3.fromRGB(190, 120, 255),
	Green = Color3.fromRGB(110, 235, 130),
	Muted = Color3.fromRGB(160, 160, 180),
	Bar = Color3.fromRGB(45, 42, 62),
}

local function tr(text, args)
	local ok, result = pcall(Localization.Translate, player.LocaleId, text, args)
	return ok and result or text
end

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0, 10)
	c.Parent = parent
	return c
end

local function stroke(parent, thickness, color, contextual)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color or COLORS.Ink
	s.ApplyStrokeMode = contextual and Enum.ApplyStrokeMode.Contextual or Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function text(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextScaled = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	for key, value in props do l[key] = value end
	l.Parent = parent
	stroke(l, 1.5, COLORS.Ink, true)
	return l
end

--------------------------------------------------------------------------------
-- ПОСТРОЕНИЕ
--------------------------------------------------------------------------------
local old = playerGui:FindFirstChild("QuestUi")
if old and old:GetAttribute("QuestUiVersion") ~= UI_VERSION then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "QuestUi"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
gui.DisplayOrder = 1200
gui:SetAttribute("QuestUiVersion", UI_VERSION)
gui.Parent = playerGui
-- Старый ассет из StarterGui может скопироваться позже — убираем дубль.
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "QuestUi" and child ~= gui then
		task.defer(function() child:Destroy() end)
	end
end)

local toggleButton = Instance.new("TextButton")
toggleButton.Name = "QuestToggleButton"
toggleButton.Position = UDim2.fromOffset(0, 0)
toggleButton.Size = UDim2.fromOffset(36, 36)
toggleButton.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
toggleButton.Text = "📜"
toggleButton.TextScaled = true
toggleButton.AutoButtonColor = false
toggleButton.Parent = gui
-- v19.4: кнопка — в ряд со штатными кнопками Roblox в топбаре.
require(ReplicatedStorage.Shared.TopbarDock).Add(toggleButton, 1)
corner(toggleButton, UDim.new(1, 0))
local toggleBadge = Instance.new("Frame")
toggleBadge.Name = "Badge"
toggleBadge.Size = UDim2.fromOffset(12, 12)
toggleBadge.Position = UDim2.new(1, -8, 0, -3)
toggleBadge.BackgroundColor3 = Color3.fromRGB(255, 70, 70)
toggleBadge.Visible = false
toggleBadge.Parent = toggleButton
corner(toggleBadge, UDim.new(1, 0))

-- ТРЕКЕР
local tracker = Instance.new("Frame")
tracker.Name = "QuestTracker"
tracker.BackgroundTransparency = 1
-- v19.4: трекер — слева снизу, прямо над портретом и деньгами (Hud.HudGui).
-- Лежит внутри контейнера HUD, поэтому двигается вместе с ним (в т.ч. при
-- мобильной раскладке). Нет HUD — просто левый нижний угол.
tracker.AnchorPoint = Vector2.new(0, 1)
tracker.Position = UDim2.new(0, 12, 1, -140)
tracker.Size = UDim2.fromOffset(270, 80)
tracker.Parent = gui
task.spawn(function()
	local hud = playerGui:WaitForChild("Hud", 15)
	local hudGui = hud and hud:WaitForChild("HudGui", 5)
	if hudGui and hudGui:IsA("GuiObject") then
		tracker.AnchorPoint = Vector2.new(0, 1)
		tracker.Position = UDim2.new(0, 0, 0, -10)
		tracker.Parent = hudGui
	end
end)
local trackerLayout = Instance.new("UIListLayout")
trackerLayout.Padding = UDim.new(0, 6)
trackerLayout.SortOrder = Enum.SortOrder.LayoutOrder
trackerLayout.Parent = tracker
local trackerScale = Instance.new("UIScale")
trackerScale.Parent = tracker

-- ОКНО
local dimmer = Instance.new("TextButton")
dimmer.Name = "Dimmer"
dimmer.Text = ""
dimmer.AutoButtonColor = false
dimmer.BackgroundColor3 = Color3.new(0, 0, 0)
dimmer.BackgroundTransparency = 0.45
dimmer.Size = UDim2.new(1, 0, 1, 80)
dimmer.Position = UDim2.fromOffset(0, -60)
dimmer.Visible = false
dimmer.ZIndex = 10
dimmer.Parent = gui

local modal = Instance.new("Frame")
modal.Name = "QuestModal"
modal.AnchorPoint = Vector2.new(0.5, 0.5)
modal.Position = UDim2.fromScale(0.5, 0.52)
modal.Size = UDim2.fromOffset(640, 440)
modal.BackgroundColor3 = COLORS.Panel
modal.Visible = false
modal.ZIndex = 11
modal.Parent = gui
corner(modal, UDim.new(0, 16))
stroke(modal, 4, COLORS.Ink)
local modalScale = Instance.new("UIScale")
modalScale.Parent = modal

text(modal, { Text = "📜 " .. tr("QUESTS"), Size = UDim2.fromOffset(240, 40), Position = UDim2.fromOffset(18, 10), TextColor3 = COLORS.Story, ZIndex = 12 })
local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.Text = "X"
closeButton.Font = Enum.Font.FredokaOne
closeButton.TextScaled = true
closeButton.TextColor3 = Color3.new(1, 1, 1)
closeButton.BackgroundColor3 = Color3.fromRGB(225, 55, 70)
closeButton.AnchorPoint = Vector2.new(0.5, 0.5)
closeButton.Position = UDim2.new(1, -6, 0, 6)
closeButton.Size = UDim2.fromOffset(42, 42)
closeButton.ZIndex = 14
closeButton.Parent = modal
corner(closeButton, UDim.new(1, 0))
stroke(closeButton, 3, COLORS.Ink)

local tabs = Instance.new("Frame")
tabs.BackgroundTransparency = 1
tabs.Position = UDim2.fromOffset(18, 56)
tabs.Size = UDim2.new(1, -36, 0, 38)
tabs.ZIndex = 12
tabs.Parent = modal
local tabsLayout = Instance.new("UIListLayout")
tabsLayout.FillDirection = Enum.FillDirection.Horizontal
tabsLayout.Padding = UDim.new(0, 8)
tabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabsLayout.Parent = tabs

local content = Instance.new("ScrollingFrame")
content.Name = "List"
content.BackgroundColor3 = COLORS.Deep
content.BorderSizePixel = 0
content.Position = UDim2.fromOffset(18, 102)
content.Size = UDim2.new(1, -36, 1, -120)
content.ScrollBarThickness = 6
content.AutomaticCanvasSize = Enum.AutomaticSize.Y
content.CanvasSize = UDim2.new()
content.ZIndex = 12
content.Parent = modal
corner(content, UDim.new(0, 12))
local contentLayout = Instance.new("UIListLayout")
contentLayout.Padding = UDim.new(0, 8)
contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
contentLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
contentLayout.Parent = content
local contentPad = Instance.new("UIPadding")
contentPad.PaddingTop = UDim.new(0, 10)
contentPad.PaddingBottom = UDim.new(0, 10)
contentPad.Parent = content

--------------------------------------------------------------------------------
-- СОСТОЯНИЕ
--------------------------------------------------------------------------------
local latestState = nil
local currentTab = "Story"
local modalOpen = false
local selectedId = nil -- квест, к которому ведём навигацию
local tabButtons = {}

local function navKeyOf(quest)
	return quest.Nav or (MARKER.MetricTargets and MARKER.MetricTargets[quest.Metric]) or nil
end

local function whyOf(quest)
	return quest.Why or (MARKER.MetricWhy and MARKER.MetricWhy[quest.Metric]) or ""
end

local function progressText(quest)
	local target = tonumber(quest.Target) or 1
	local progress = math.min(tonumber(quest.Progress) or 0, target)
	if quest.Metric == "PlayTime" then
		return ("%d/%d min"):format(math.floor(progress / 60), math.floor(target / 60))
	end
	local function short(n)
		if n >= 1e6 then return ("%.1fM"):format(n / 1e6) end
		if n >= 1e3 then return ("%.1fK"):format(n / 1e3) end
		return tostring(math.floor(n))
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

--------------------------------------------------------------------------------
-- ФИШКИ НАГРАД
--------------------------------------------------------------------------------
local function chipsRow(parent, chips, zIndex)
	local row = Instance.new("Frame")
	row.Name = "Chips"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 24)
	row.ZIndex = zIndex
	row.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.Parent = row
	for _, chip in chips or {} do
		local label = Instance.new("TextLabel")
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.fromOffset(0, 24)
		label.BackgroundColor3 = COLORS.Bar
		label.Font = Enum.Font.GothamBold
		label.TextSize = 14
		label.TextColor3 = Color3.fromRGB(255, 225, 120)
		label.Text = ("%s %s"):format(chip.Icon or "", chip.Text or "")
		label.ZIndex = zIndex
		label.Parent = row
		corner(label, UDim.new(0, 8))
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 8)
		pad.PaddingRight = UDim.new(0, 8)
		pad.Parent = label
	end
	return row
end

local function bar(parent, fraction, color, zIndex, height)
	local back = Instance.new("Frame")
	back.Name = "Bar"
	back.BackgroundColor3 = COLORS.Bar
	back.Size = UDim2.new(1, 0, 0, height or 10)
	back.ZIndex = zIndex
	back.Parent = parent
	corner(back, UDim.new(1, 0))
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = color
	fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	fill.ZIndex = zIndex + 1
	fill.Parent = back
	corner(fill, UDim.new(1, 0))
	return back
end

--------------------------------------------------------------------------------
-- ТРЕКЕР
--------------------------------------------------------------------------------
local trackerRows = {}

local function renderTracker(state)
	for _, row in trackerRows do row:Destroy() end
	trackerRows = {}
	if tutorialActive() then
		tracker.Visible = false
		return
	end
	local list = trackedQuests(state)
	applyNavigation(list)
	-- v17: на экране только ОДИН закреплённый квест. Остальные — в окне 📜
	-- (кнопка 🧭 закрепляет), а клик по плашке листает к следующему.
	local quest, pinnedIndex = nil, 1
	for index, candidate in list do
		if candidate.Id == selectedId then quest, pinnedIndex = candidate, index end
	end
	tracker.Visible = quest ~= nil
	if not quest then return end
	local color = quest.Kind == "Story" and COLORS.Story or COLORS.Daily
	local row = Instance.new("TextButton")
	row.Name = "Row_" .. tostring(quest.Id)
	row.Text = ""
	row.AutoButtonColor = false
	row.LayoutOrder = 1
	row.BackgroundColor3 = COLORS.Panel
	row.BackgroundTransparency = 0.05
	row.Size = UDim2.new(1, 0, 0, 76)
	row.Parent = tracker
	corner(row, UDim.new(0, 10))
	stroke(row, 3, color)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 6)
	pad.Parent = row
	local counter = #list > 1 and ("  %d/%d"):format(pinnedIndex, #list) or ""
	text(row, {
		Text = "📍 " .. tr(quest.Short or quest.Title),
		Size = UDim2.new(1, -70, 0, 20), TextColor3 = color,
	})
	text(row, {
		Text = progressText(quest), Size = UDim2.fromOffset(70, 20), Position = UDim2.new(1, -70, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = COLORS.Green,
	})
	local fraction = (tonumber(quest.Progress) or 0) / math.max(1, tonumber(quest.Target) or 1)
	local barFrame = bar(row, fraction, color, 2, 8)
	barFrame.Position = UDim2.fromOffset(0, 24)
	local why = whyOf(quest)
	local distance = tonumber(player:GetAttribute("QuestNavDistance"))
	local suffix = (navKeyOf(quest) and distance) and ("  ·  %dm"):format(math.floor(distance)) or ""
	local whyLabel = text(row, {
		Name = "Why", Text = "➜ " .. tr(why) .. suffix, Size = UDim2.new(1, #list > 1 and -44 or 0, 0, 28),
		Position = UDim2.fromOffset(0, 36), Font = Enum.Font.GothamBold, TextColor3 = COLORS.Muted,
		TextWrapped = true,
	})
	whyLabel.TextScaled = true
	if #list > 1 then
		local cycle = text(row, {
			Name = "Cycle", Text = "⇄" .. counter, Size = UDim2.fromOffset(44, 18), Position = UDim2.new(1, -44, 0, 42),
			TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.GothamBold, TextColor3 = COLORS.Muted,
		})
		cycle.TextScaled = true
	end
	row.Activated:Connect(function()
		if #list <= 1 then
			UiSfx.play("UiButtonClick")
			return
		end
		UiSfx.play("UiButtonClick")
		local nextQuest = list[(pinnedIndex % #list) + 1]
		selectedId = nextQuest and nextQuest.Id or selectedId
		renderTracker(latestState)
	end)
	table.insert(trackerRows, row)
end

-- Расстояние в трекере обновляется навигатором через атрибут.
player:GetAttributeChangedSignal("QuestNavDistance"):Connect(function()
	local row = selectedId and tracker:FindFirstChild("Row_" .. tostring(selectedId))
	local whyLabel = row and row:FindFirstChild("Why")
	if whyLabel and latestState then
		local quest
		for _, candidate in trackedQuests(latestState) do
			if candidate.Id == selectedId then quest = candidate end
		end
		if quest then
			local distance = tonumber(player:GetAttribute("QuestNavDistance"))
			local suffix = (navKeyOf(quest) and distance) and ("  ·  %dm"):format(math.floor(distance)) or ""
			whyLabel.Text = "➜ " .. tr(whyOf(quest)) .. suffix
		end
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

local function questCard(quest, order, color, done)
	local card = Instance.new("Frame")
	card.Name = "Quest_" .. tostring(quest.Id)
	card.LayoutOrder = order
	card.BackgroundColor3 = COLORS.Panel
	card.BackgroundTransparency = done and 0.4 or 0
	card.Size = UDim2.new(1, -20, 0, done and 44 or 116)
	card.ZIndex = 13
	card.Parent = content
	corner(card, UDim.new(0, 12))
	stroke(card, 2, done and COLORS.Ink or color)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.PaddingTop = UDim.new(0, 8)
	pad.Parent = card
	text(card, {
		Text = (done and "✔ " or "") .. tr(quest.Title or ""), Size = UDim2.new(1, -110, 0, 24),
		TextColor3 = done and COLORS.Muted or color, ZIndex = 14,
	})
	text(card, {
		Text = done and "" or progressText(quest), Size = UDim2.fromOffset(110, 24), Position = UDim2.new(1, -110, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = COLORS.Green, ZIndex = 14,
	})
	if done then return card end
	text(card, {
		Text = tr(quest.Description or ""), Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 26),
		Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(225, 225, 235), ZIndex = 14,
	})
	local why = whyOf(quest)
	if why ~= "" then
		text(card, {
			Text = "💡 " .. tr(why), Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 46),
			Font = Enum.Font.GothamBold, TextColor3 = COLORS.Muted, ZIndex = 14,
		})
	end
	local fraction = (tonumber(quest.Progress) or 0) / math.max(1, tonumber(quest.Target) or 1)
	local barFrame = bar(card, fraction, color, 14, 8)
	barFrame.Position = UDim2.fromOffset(0, 66)
	local chips = chipsRow(card, quest.Chips, 14)
	chips.Position = UDim2.fromOffset(0, 80)
	-- Кнопка «вести сюда».
	if navKeyOf(quest) then
		local go = Instance.new("TextButton")
		go.Text = quest.Id == selectedId and "📍" or "🧭"
		go.TextScaled = true
		go.BackgroundColor3 = COLORS.Bar
		go.AnchorPoint = Vector2.new(1, 0)
		go.Position = UDim2.new(1, 0, 0, 78)
		go.Size = UDim2.fromOffset(30, 28)
		go.ZIndex = 15
		go.Parent = card
		corner(go, UDim.new(0, 8))
		go.Activated:Connect(function()
			UiSfx.play("UiButtonClick")
			selectedId = quest.Id
			renderTracker(latestState)
			go.Text = "📍"
		end)
	end
	return card
end

local function sectionTitle(label, order, color)
	local l = text(content, { Text = label, Size = UDim2.new(1, -20, 0, 22), LayoutOrder = order, TextColor3 = color, ZIndex = 13 })
	return l
end

local function renderStory(state)
	local order = 0
	local active, done = nil, {}
	for _, quest in state.Starter or {} do
		if quest.Active then active = quest elseif quest.Completed then table.insert(done, quest) end
	end
	if active then
		order += 1
		sectionTitle(tr("CURRENT"), order, COLORS.Story)
		order += 1
		questCard(active, order, COLORS.Story, false)
	else
		order += 1
		sectionTitle(tr("All story quests complete!"), order, COLORS.Green)
	end
	if #done > 0 then
		order += 1
		sectionTitle(tr("COMPLETED"), order, COLORS.Muted)
		for index = #done, 1, -1 do
			order += 1
			questCard(done[index], order, COLORS.Story, true)
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
	local resets = tonumber(state.DailyResetsAt)
	sectionTitle(resets and tr("New quests in {t}", { t = formatLeft(resets - os.time()) }) or tr("DAILY"), order, COLORS.Daily)
	if not state.DailyUnlocked then
		order += 1
		sectionTitle(tr("Finish the tutorial to unlock daily quests."), order, COLORS.Muted)
		return
	end
	for _, quest in state.Daily or {} do
		order += 1
		local card = questCard(quest, order, COLORS.Daily, quest.Claimed == true)
		if not quest.Claimed then
			text(card, {
				Text = ("+%d ⭐"):format(tonumber(quest.WeeklyPoints) or 0), Size = UDim2.fromOffset(60, 18),
				Position = UDim2.new(1, -95, 0, 46), TextXAlignment = Enum.TextXAlignment.Right,
				TextColor3 = COLORS.Weekly, ZIndex = 14,
			})
			if quest.Blocked then
				text(card, {
					Text = tr("Needs 2+ players on the server"), Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 46),
					Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(255, 150, 110), ZIndex = 15,
				})
			end
		end
	end
end

local function renderWeekly(state)
	local points = tonumber(state.WeeklyPoints) or 0
	local chests = state.Weekly or {}
	local maxPoints = 1
	for _, chest in chests do maxPoints = math.max(maxPoints, chest.Points) end
	sectionTitle(tr("WEEKLY POINTS: {p}", { p = tostring(points) }), 1, COLORS.Weekly)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, -20, 0, 22)
	holder.LayoutOrder = 2
	holder.ZIndex = 13
	holder.Parent = content
	bar(holder, points / maxPoints, COLORS.Weekly, 13, 14)
	sectionTitle(tr("Complete daily quests to earn ⭐. Chests are sent to your inventory."), 3, COLORS.Muted).Font = Enum.Font.GothamBold
	for index, chest in chests do
		local info = Config.Chests.Types[chest.Rarity]
		local card = Instance.new("Frame")
		card.LayoutOrder = 3 + index
		card.BackgroundColor3 = COLORS.Panel
		card.Size = UDim2.new(1, -20, 0, 48)
		card.ZIndex = 13
		card.Parent = content
		corner(card, UDim.new(0, 12))
		stroke(card, 2, info and info.Color or COLORS.Weekly)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 12)
		pad.PaddingRight = UDim.new(0, 12)
		pad.PaddingTop = UDim.new(0, 10)
		pad.Parent = card
		text(card, {
			Text = ("🎁 %s"):format(info and info.DisplayName or chest.Rarity), Size = UDim2.new(0.6, 0, 0, 26),
			TextColor3 = info and info.Color or Color3.new(1, 1, 1), ZIndex = 14,
		})
		text(card, {
			Text = chest.Claimed and ("✔ " .. tr("RECEIVED")) or ("%d/%d ⭐"):format(math.min(points, chest.Points), chest.Points),
			Size = UDim2.new(0.4, 0, 0, 26), Position = UDim2.fromScale(0.6, 0), TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = chest.Claimed and COLORS.Green or COLORS.Muted, ZIndex = 14,
		})
	end
end

local function renderModal()
	if not (modalOpen and latestState) then return end
	clearContent()
	for id, button in tabButtons do
		local color = id == "Story" and COLORS.Story or id == "Daily" and COLORS.Daily or COLORS.Weekly
		button.BackgroundColor3 = id == currentTab and color or COLORS.Bar
		button.TextColor3 = id == currentTab and COLORS.Ink or Color3.new(1, 1, 1)
	end
	if currentTab == "Story" then
		renderStory(latestState)
	elseif currentTab == "Daily" then
		renderDaily(latestState)
	else
		renderWeekly(latestState)
	end
end

for order, id in { "Story", "Daily", "Weekly" } do
	local button = Instance.new("TextButton")
	button.Name = id .. "Tab"
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(130, 38)
	button.Font = Enum.Font.FredokaOne
	button.TextScaled = true
	button.Text = tr(id:upper())
	button.BackgroundColor3 = COLORS.Bar
	button.TextColor3 = Color3.new(1, 1, 1)
	button.AutoButtonColor = false
	button.ZIndex = 13
	button.Parent = tabs
	corner(button, UDim.new(0, 10))
	stroke(button, 2, COLORS.Ink)
	button.Activated:Connect(function()
		UiSfx.play("UiButtonClick")
		currentTab = id
		renderModal()
	end)
	tabButtons[id] = button
end

local function fitModalScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	return math.min(1, (viewport.X - 24) / 640, (viewport.Y - 60) / 440)
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
closeButton.Activated:Connect(closeModal)
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
	toggleBadge.Visible = pendingDaily and state.DailyUnlocked == true
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
