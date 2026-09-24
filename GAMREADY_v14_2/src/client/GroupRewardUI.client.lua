--------------------------------------------------------------------------------
-- GroupRewardUI (v17) — «вступи в группу → +% к продаже навсегда + сундук»
-- и крупный призыв поставить лайк. Вид — общая деревянная карточка в стиле
-- уведомлений (shared/SocialRewardCard.lua). Старое окно с подарком-коробкой
-- удалено; авторский ассет StarterGui/GroupRewardUi заменяется
-- автоматически (его можно удалить).
--
-- Членство перед выдачей проверяется сервером (GroupRewardService).
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GroupService = game:GetService("GroupService")

local Config = require(ReplicatedStorage.Shared.Config)
local UiSfx = require(ReplicatedStorage.Shared.UiSfx)
local SocialRewardCard = require(ReplicatedStorage.Shared.SocialRewardCard)

if not Config.GroupReward or Config.GroupReward.Enabled ~= true then
	return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage.Shared:WaitForChild("GroupRewardRequest")

local ACTION_TEXT = "👥 JOIN & CLAIM"

local gui = SocialRewardCard.Build(playerGui, {
	GuiName = "GroupRewardUi",
	ActionName = "JoinGroupButton",
	Accent = Color3.fromRGB(70, 140, 230),
	HeaderIcon = "👥",
	Title = "JOIN GROUP = MORE CASH",
	ActionText = ACTION_TEXT,
})
local ui = SocialRewardCard.Controller(gui, { ActionName = "JoinGroupButton" })
local joinGroupButton = ui.Action

local state = { Claimed = false, GroupId = 0 }

local function refreshRewards()
	local bonus = math.floor((tonumber(state.IncomeBonus or Config.GroupReward.IncomeBonus) or 0) * 100 + 0.5)
	local chestInfo = Config.Chests and Config.Chests.Types and Config.Chests.Types[state.ChestRarity or Config.GroupReward.ChestRarity or "Common"]
	local chestName = chestInfo and chestInfo.DisplayName or "Chest"
	ui.SetRewards(("💰 +%d%% CASH FOREVER"):format(bonus), state.Claimed and "✅ CHEST CLAIMED" or ("🎁 FREE %s"):format(chestName:upper()))
end
refreshRewards()

local function closePopup(instant)
	ui.Hide(instant)
end

local function showPopup(force)
	if (state.Claimed and state.Member and not force) or ui.Open then return end
	joinGroupButton.Active = true
	ui.SetCaption((state.Claimed and state.Member) and "✅ YOU'RE IN THE GROUP" or ACTION_TEXT)
	UiSfx.play("GroupPrompt")
	ui.Show()
end

ui.Close.Activated:Connect(function()
	UiSfx.play("UiButtonClick")
	closePopup()
end)
ui.Dimmer.Activated:Connect(function()
	closePopup()
end)

joinGroupButton.Activated:Connect(function()
	if not joinGroupButton.Active or (state.Claimed and state.Member) then return end
	UiSfx.play("UiButtonClick")
	local groupId = state.GroupId ~= 0 and state.GroupId or Config.GroupReward.GroupId
	if not groupId or groupId == 0 then
		warn("[GroupRewardUI] Config.GroupReward.GroupId не задан (0) — впиши ID своей группы.")
		return
	end
	local ok, err = pcall(function()
		GroupService:PromptJoinAsync(groupId)
	end)
	if not ok then
		warn("[GroupRewardUI] PromptJoinAsync failed: " .. tostring(err))
		return
	end
	joinGroupButton.Active = false
	ui.SetCaption("CHECKING...")
	task.delay(0.75, function()
		if not state.Claimed or not state.Member then remote:FireServer("Claim") end
	end)
	-- Если сервер не подтвердил членство — вернуть кнопку.
	task.delay(6, function()
		if ui.Open and not (state.Claimed and state.Member) then
			joinGroupButton.Active = true
			ui.SetCaption(ACTION_TEXT)
		end
	end)
end)

local function isDone(s)
	return s.Claimed == true and s.Member == true
end

remote.OnClientEvent:Connect(function(action, payload)
	if action == "AdminOpen" then
		showPopup(true)
		return
	end
	-- v16: удачный момент — предложение от SocialOfferService.
	if action == "Offer" then
		if not isDone(state) then showPopup(true) end
		return
	end
	if action ~= "State" or typeof(payload) ~= "table" then return end
	local wasDone = isDone(state)
	state = payload
	refreshRewards()
	if isDone(state) then
		if ui.Open and not wasDone then
			UiSfx.play("UiSuccess")
			ui.Celebrate("🎉 WELCOME! +CASH ON")
		end
	elseif not ui.Open then
		joinGroupButton.Active = true
		ui.SetCaption(ACTION_TEXT)
	end
end)

local previewEvent = playerGui:FindFirstChild("PreviewGroupReward")
if not previewEvent then
	previewEvent = Instance.new("BindableEvent")
	previewEvent.Name = "PreviewGroupReward"
	previewEvent.Parent = playerGui
end
if previewEvent:IsA("BindableEvent") then
	previewEvent.Event:Connect(function() showPopup(true) end)
end

remote:FireServer("RequestState")
