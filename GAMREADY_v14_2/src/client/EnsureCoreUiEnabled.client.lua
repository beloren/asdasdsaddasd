--------------------------------------------------------------------------------
-- ЕДИНСТВЕННАЯ ЗАДАЧА ЭТОГО СКРИПТА: подстраховать основной UI игры от
-- случайно выключенного Enabled = false на ScreenGui в StarterGui (например,
-- если кто-то в Studio выделил все ScreenGui разом и снял галочку Enabled).
--
-- Ни один из скриптов ниже НИКОГДА сам не включает обратно .Enabled этих
-- конкретных ScreenGui — они считают, что Enabled и так true по умолчанию
-- (как оно и бывает у свежесозданного ScreenGui). Если сохранённое значение
-- в StarterGui случайно стало false, оно так и останется false у всех
-- игроков, пока кто-то не заметит и не поправит вручную. Этот скрипт чинит
-- это на лету, для каждого игрока, при заходе.
--
-- ВАЖНО: сюда попадают ScreenGui, которые должны быть включены всегда после
-- завершения заставки, включая базовый HUD, хотбар и книжку меню.
-- НЕ добавляй сюда: ActionButtons (переключаются по
-- HasPickaxe/CarryingCart), RebirthDialogButtons и GeodeUi (открываются и
-- закрываются по ходу игры) — им положено быть выключенными бOльшую часть
-- времени, форсить Enabled=true на них — это баг, а не фикс. Туда же
-- относятся ShopEntry/SkinEntry — они НАМЕРЕННО выключены НАВСЕГДА (см.
-- CollectionMenu.client.lua), их старые кнопки-иконки заменены одной общей
-- кнопкой-книгой.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")

local ALWAYS_ON_GUIS = {
	"Hud",
	"HotbarUi",
	"CollectionMenu",
	"CartInteractionUi",
	-- "SettingsMenu" отсюда УБРАН: настройки сняты с экрана целиком
	-- (Config.UI.SettingsMenuEnabled = false, см. CustomCartUI). Если его
	-- здесь оставить, этот сторож и сторож в CustomCartUI бесконечно
	-- включали бы/выключали его друг за другом.
	-- ShopEntry и SkinEntry раньше были тут — теперь НАМЕРЕННО выключены
	-- (CollectionMenu.client.lua/CustomCartUI.client.lua/SkinUI.client.lua
	-- сами их гасят: .Enabled = false), их кнопки-иконки заменены одной
	-- общей кнопкой-книгой (CollectionMenu), которая и открывает магазин/
	-- скины сама, программно. Держать их тут — значит откатывать это
	-- намеренное выключение обратно каждый раз, ЛОМАЯ клик по новой кнопке
	-- (старые иконки снова показывались и перекрывали её).
	"QuestUi",
	"ShopUi",
	"SkinUi",
	"DailyRewardUi",
	"Toast",
	"UpgradeShopCards", -- необязательная фича — если её нет, просто пропустится
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function forceEnable(name)
	-- WaitForChild с таймаутом: часть этих ScreenGui клонируется из
	-- StarterGui почти мгновенно, часть достраивается фолбэком в других
	-- LocalScript'ах (QuestUI/DailyRewardUI и т.п.) чуть позже — ждём и то,
	-- и другое, но не вечно, чтобы не зависнуть на действительно
	-- отсутствующей (необязательной) фиче вроде UpgradeShopCards.
	local gui = playerGui:WaitForChild(name, 5)
	if not gui then
		return
	end
	if player:GetAttribute("IntroActive") ~= true and not gui.Enabled then
		gui.Enabled = true
		warn(("[EnsureCoreUiEnabled] %s был выключен (Enabled=false) — включил обратно."):format(name))
	end
	-- На случай, если что-то (например, повторный клон при ResetOnSpawn
	-- где-то по ошибке True) выключит его позже — держим один короткий
	-- сторож на изменение свойства, а не бесконечный цикл.
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if player:GetAttribute("IntroActive") ~= true and not gui.Enabled then
			gui.Enabled = true
		end
	end)
	player:GetAttributeChangedSignal("IntroActive"):Connect(function()
		if player:GetAttribute("IntroActive") ~= true then
			gui.Enabled = true
		end
	end)
end

for _, name in ALWAYS_ON_GUIS do
	task.spawn(forceEnable, name)
end

-- НАСТРОЙКИ СНЯТЫ С ЭКРАНА (Config.UI.SettingsMenuEnabled = false). Гасим
-- собранный в Studio SettingsMenu сразу, как только он склонировался в
-- PlayerGui: основной обработчик в CustomCartUI доходит до него позже, и
-- без этого шестерёнка успевала мелькнуть на экране при заходе.
task.spawn(function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ok, Config = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
	end)
	if not ok or not Config.UI or Config.UI.SettingsMenuEnabled ~= false then
		return
	end
	local function hide(gui)
		if gui.Name == "SettingsMenu" and gui:IsA("ScreenGui") then
			gui.Enabled = false
		end
	end
	for _, gui in playerGui:GetChildren() do
		hide(gui)
	end
	playerGui.ChildAdded:Connect(hide)
end)
