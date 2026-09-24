-- Одноразовый фикс: вставь этот скрипт в Command Bar в Studio (View →
-- Command Bar) и выполни один раз. Включает Enabled = true у ScreenGui в
-- StarterGui, которые должны быть включены ВСЕГДА (см. полный список и
-- объяснение в src/client/EnsureCoreUiEnabled.client.lua — тот же список
-- поддерживается синхронно и на лету чинит уже подключённых игроков).
--
-- НЕ трогает PickaxeHotbar/ActionButtons/RebirthDialogButtons/GeodeUi —
-- им положено быть выключенными бOльшую часть времени, это не баг.

local StarterGui = game:GetService("StarterGui")

local ALWAYS_ON_GUIS = {
	"Hud",
	"CartInteractionUi",
	"SettingsMenu",
	"ShopEntry",
	"SkinEntry",
	"QuestUi",
	"ShopUi",
	"SkinUi",
	"DailyRewardUi",
	"DialogResponses",
	"Toast",
	"UpgradeShopCards",
}

local fixed = {}
local missing = {}
for _, name in ALWAYS_ON_GUIS do
	local gui = StarterGui:FindFirstChild(name)
	if gui then
		if not gui.Enabled then
			gui.Enabled = true
			table.insert(fixed, name)
		end
	else
		table.insert(missing, name)
	end
end

if #fixed > 0 then
	print("[FixDisabledUi] Включил обратно: " .. table.concat(fixed, ", "))
else
	print("[FixDisabledUi] Всё уже было включено, править нечего.")
end
if #missing > 0 then
	print("[FixDisabledUi] Не нашёл в StarterGui (это может быть нормально, если фича ещё не собрана): " .. table.concat(missing, ", "))
end
