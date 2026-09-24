--------------------------------------------------------------------------------
-- LikeRewardUI (v17) — «добавь в избранное → получи награду» + большой
-- призыв поставить лайк. Вид — общая деревянная карточка в стиле
-- уведомлений (shared/SocialRewardCard.lua). Старое окно с подарком-коробкой
-- удалено; авторский ассет StarterGui/LikeRewardUi, если он есть,
-- заменяется автоматически (его можно удалить).
--
-- Награда выдаётся только после НАСТОЯЩЕГО добавления в избранное: уже в
-- избранном (GetFavorite) или промпт завершился Success. У Roblox нет API,
-- чтобы проверить лайк, поэтому лайк — это крупная просьба с прогрессом
-- целей из Config.LikeGoals.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AvatarEditorService = game:GetService("AvatarEditorService")

local Config = require(ReplicatedStorage.Shared.Config)
local UiSfx = require(ReplicatedStorage.Shared.UiSfx)
local SocialRewardCard = require(ReplicatedStorage.Shared.SocialRewardCard)

if not Config.LikeReward or Config.LikeReward.Enabled ~= true then
	return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage.Shared:WaitForChild("LikeRewardRequest")

local ACTION_TEXT = "⭐ FAVORITE & CLAIM"

local gui = SocialRewardCard.Build(playerGui, {
	GuiName = "LikeRewardUi",
	ActionName = "FavoriteButton",
	Accent = Color3.fromRGB(235, 90, 130),
	HeaderIcon = "⭐",
	Title = "FAVORITE = FREE REWARD",
	ActionText = ACTION_TEXT,
})
local ui = SocialRewardCard.Controller(gui, { ActionName = "FavoriteButton" })
local favoriteButton = ui.Action

local state = { Claimed = false }
local showsThisSession = 0
local previewOpen = false

local function closePopup(instant)
	if not previewOpen and showsThisSession == 1 then
		player:SetAttribute("LikeRewardSequenceReady", true)
	end
	previewOpen = false
	ui.Hide(instant)
end

local function showPopup(force, preview)
	if (state.Claimed and not force) or ui.Open then return end
	previewOpen = preview == true
	if not previewOpen then showsThisSession += 1 end
	favoriteButton.Active = true
	ui.SetCaption(state.Claimed and "✅ ALREADY CLAIMED" or ACTION_TEXT)
	UiSfx.play("LikePrompt")
	ui.Show()
end

local function refreshRewards()
	local definition = Config.Skins and Config.Skins.Definitions and Config.Skins.Definitions[state.SkinId or Config.LikeReward.SkinId]
	local skinName = definition and definition.DisplayName or tostring(state.SkinId or Config.LikeReward.SkinId or "Skin")
	local geodeCount = tonumber(state.GeodeCount or Config.LikeReward.GeodeCount) or 0
	local geodeType = state.GeodeType or Config.LikeReward.GeodeType or ""
	ui.SetRewards("⛏ " .. skinName, geodeCount > 0 and ("💎 %dx %s"):format(geodeCount, geodeType) or nil)
end
refreshRewards()

ui.Close.Activated:Connect(function()
	UiSfx.play("UiButtonClick")
	closePopup()
end)
ui.Dimmer.Activated:Connect(function()
	closePopup()
end)

local waitingFavorite = false
local function claim()
	ui.SetCaption("✅ VERIFIED!")
	if not state.Claimed then remote:FireServer("Claim") end
end

AvatarEditorService.PromptSetFavoriteCompleted:Connect(function(itemId, _itemType, result)
	if not waitingFavorite or tonumber(itemId) ~= game.PlaceId then return end
	waitingFavorite = false
	if result == Enum.AvatarPromptResult.Success then
		claim()
	else
		favoriteButton.Active = true
		ui.SetCaption("⭐ FAVORITE TO CLAIM")
	end
end)

favoriteButton.Activated:Connect(function()
	if not favoriteButton.Active or state.Claimed then return end
	UiSfx.play("UiButtonClick")
	favoriteButton.Active = false
	ui.SetCaption("CHECKING...")
	local okCheck, isFavorite = pcall(function()
		return AvatarEditorService:GetFavorite(game.PlaceId, Enum.AvatarItemType.Asset)
	end)
	if okCheck and isFavorite == true then
		claim()
		return
	end
	waitingFavorite = true
	local ok, err = pcall(function()
		AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
	end)
	if not ok then
		waitingFavorite = false
		warn("[LikeRewardUI] PromptSetFavorite failed: " .. tostring(err))
		favoriteButton.Active = true
		ui.SetCaption(ACTION_TEXT)
	end
end)

remote.OnClientEvent:Connect(function(action, payload)
	if action == "AdminOpen" then
		showPopup(true)
		return
	end
	-- v16: удачный момент — предложение от SocialOfferService.
	if action == "Offer" then
		if not state.Claimed then showPopup() end
		return
	end
	if action ~= "State" or typeof(payload) ~= "table" then return end
	local wasClaimed = state.Claimed
	state = payload
	refreshRewards()
	if state.Claimed then
		player:SetAttribute("LikeRewardSequenceReady", true)
		if ui.Open and not wasClaimed then
			UiSfx.play("UiSuccess")
			ui.Celebrate("🎉 CLAIMED! THANKS!")
		end
	elseif not ui.Open then
		favoriteButton.Active = true
		ui.SetCaption(ACTION_TEXT)
	end
end)

local previewEvent = playerGui:FindFirstChild("PreviewLikeReward")
if not previewEvent then
	previewEvent = Instance.new("BindableEvent")
	previewEvent.Name = "PreviewLikeReward"
	previewEvent.Parent = playerGui
end
if previewEvent:IsA("BindableEvent") then
	previewEvent.Event:Connect(function() showPopup(true, true) end)
end

remote:FireServer("RequestState")
