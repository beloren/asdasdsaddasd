--------------------------------------------------------------------------------
-- SocialHud (LocalScript) v16 — маленькая кнопка 🎁 для наград «группа» и
-- «избранное». Видна, пока хоть что-то не забрано. Клик — два пункта:
-- 👥 группа (+10% навсегда + сундук) и ⭐ избранное. Сами окна —
-- GroupRewardUI / LikeRewardUI (открываются их BindableEvent'ами Preview*).
-- Никаких автопоказов: предложения в удачный момент шлёт SocialOfferService.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- v20.173: до ответа сервера кнопку не показываем - иначе она висела у тех,
-- кто уже всё забрал (состояние приходило раньше, чем мы начинали слушать)
local groupEnabled = Config.GroupReward and Config.GroupReward.Enabled and (tonumber(Config.GroupReward.GroupId) or 0) ~= 0
local favoriteEnabled = Config.LikeReward and Config.LikeReward.Enabled
local groupPending = false
local favoritePending = false

-- v20: вид — Shared.UiBuilders.SocialHudUi (StarterGui/SocialHud).
local gui = require(ReplicatedStorage.Shared.UiRegistry).Get("SocialHud")
local button = gui:WaitForChild("Gift")
if Config.SocialOffers and Config.SocialOffers.HudPosition then
	button.Position = Config.SocialOffers.HudPosition
end
local dot = button:WaitForChild("Dot")
local scale = button:WaitForChild("Pop")
local menu = button:WaitForChild("Menu")
require(ReplicatedStorage.Shared.TopbarDock).Add(button, 3)

local function menuButton(name, text, onClick)
	local b = menu:WaitForChild(name)
	local caption = b:FindFirstChild("Caption")
	if caption then caption.Text = text end
	b.Activated:Connect(function()
		menu.Visible = false
		onClick()
	end)
	return b
end

local function fire(name)
	local event = playerGui:FindFirstChild(name)
	if event and event:IsA("BindableEvent") then event:Fire() end
end

local bonus = math.floor(((Config.GroupReward and Config.GroupReward.IncomeBonus) or 0) * 100 + 0.5)
local groupButton = menuButton("GroupButton", ("👥 GROUP: +%d%% CASH"):format(bonus), function() fire("PreviewGroupReward") end)
local favoriteButton = menuButton("FavoriteButton", "⭐ FAVORITE: FREE SKIN", function() fire("PreviewLikeReward") end)

local function refresh()
	groupButton.Visible = groupPending == true
	favoriteButton.Visible = favoritePending == true
	button.Visible = groupPending == true or favoritePending == true
	if not button.Visible then menu.Visible = false end
end
refresh()

button.Activated:Connect(function()
	scale.Scale = 0.85
	TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	dot.Visible = false
	menu.Visible = not menu.Visible
end)

-- Слушаем те же State, что и окна наград.
local gotGroupState, gotLikeState = false, false
task.spawn(function()
	local groupRemote = ReplicatedStorage.Shared:WaitForChild("GroupRewardRequest", 60)
	if groupRemote then
		groupRemote.OnClientEvent:Connect(function(action, payload)
			if action == "State" and type(payload) == "table" then
				gotGroupState = true
				-- забрал награду - кнопку больше не показываем
				groupPending = groupEnabled and payload.Claimed ~= true
				refresh()
			end
		end)
		-- сами просим состояние (сервер может ещё грузить профиль - повторяем)
		for _, delaySeconds in { 0, 2, 5, 10, 20 } do
			task.wait(delaySeconds)
			if gotGroupState then break end
			groupRemote:FireServer("RequestState")
		end
	end
end)
task.spawn(function()
	local likeRemote = ReplicatedStorage.Shared:WaitForChild("LikeRewardRequest", 60)
	if likeRemote then
		likeRemote.OnClientEvent:Connect(function(action, payload)
			if action == "State" and type(payload) == "table" then
				gotLikeState = true
				favoritePending = favoriteEnabled and payload.Claimed ~= true
				refresh()
			end
		end)
		for _, delaySeconds in { 0, 2, 5, 10, 20 } do
			task.wait(delaySeconds)
			if gotLikeState then break end
			likeRemote:FireServer("RequestState")
		end
	end
end)
