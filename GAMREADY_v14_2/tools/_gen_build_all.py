# Перегенерирует tools/BuildAllUI.lua из отдельных UI-билдеров.
# Запуск: python3 tools/_gen_build_all.py  (из корня проекта или из tools/)
import io, os
os.chdir(os.path.dirname(os.path.abspath(__file__)))
ORDER = [
 ("BuildUIAssets.lua","HUD, кнопки, базовые окна (Hud, HudGui, …)"),
 ("BuildInventoryUI.lua","инвентарь и хотбар (HotbarUi)"),
 ("BuildNotificationUI.lua","уведомления / тосты — ToastUiBuilder"),
 ("BuildShopUi.lua","магазин за Robux (ShopUi)"),
 ("BuildQuestUI.lua","квесты (QuestUi)"),
 ("BuildTutorialUI.lua","диалоговое окно обучения (TutorialUi)"),
 ("BuildDailyRewardUI.lua","ежедневные награды"),
 ("BuildGroupRewardUI.lua","награда за группу"),
 ("BuildLikeRewardUI.lua","награда за лайк"),
 ("BuildStarterPackUI.lua","стартовый пак"),
 ("BuildReturnScreenUI.lua","экран возвращения"),
 ("BuildRebirthDialogUI.lua","окно престижа — PrestigeUiBuilder"),
 ("BuildRewardPopups.lua","всплывающие награды"),
 ("BuildMoneyFx.lua","летящие деньги"),
 ("BuildMobBillboardTemplates.lua","билборды мобов"),
 ("BuildRubbleCrystalUI.lua","UI кристаллов в завалах"),
 ("BuildCollectionMenu.lua","кнопка-книга и подменю (CollectionMenu)"),
 ("BuildMutationBookUI.lua","книга коллекции — CollectionBookUiBuilder"),
 ("BuildPerkUI.lua","престиж — PerkUiBuilder"),
 ("BuildGeodeUI.lua","жеоды + подиум банка — GeodeUiBuilder / BankPodiumUiBuilder"),
 ("BuildBoulderGameUI.lua","мини-игра валуна — BoulderGameUiBuilder"),
 ("BuildGearUI.lua","прицел и лут сундуков — GearUiBuilder"),
 ("BuildSkinUIv3.lua","скины — SkinUiBuilder"),
 ("BuildCombatUI.lua","бой — CombatUiBuilder"),
 ("BuildMineArcUI.lua","мини-игра шахты — MineVeinUiBuilder"),
 ("BuildMinerDialogUI.lua","диалог шахтёра — MinerDialogUiBuilder"),
 ("BuildOfferUI.lua","купоны предложений и кнопка 🚀 — OfferUiBuilder"),
]
header = open("BuildAllUI.lua", encoding="utf-8").read().split("-- ============================================================================\n")[0]
out = io.StringIO()
out.write(header)
for fname, what in ORDER:
    src = open(fname, encoding="utf-8", errors="replace").read()
    out.write("-- ============================================================================\n")
    out.write(f"-- {fname} — {what}\n")
    out.write("-- ============================================================================\n")
    out.write(f'__run("{fname}", "{what}", function()\n{src.rstrip()}\nend)\n\n')
out.write('print("[BuildAllUI] Готово:\\n  " .. table.concat(__report, "\\n  "))\n')
open("BuildAllUI.lua", "w", encoding="utf-8").write(out.getvalue())
print("BuildAllUI.lua regenerated")
