# Ore mechanic rewrite — progress & roadmap

All Lua in this pass has been validated against a real Luau parser (not just eyeballed), so everything below is confirmed syntactically correct. It has **not** been run inside Roblox Studio — I don't have access to the engine or your 3D models here, so treat this as a strong first pass that needs a Studio playtest, not a guaranteed-perfect drop-in.

## ✅ Done

### Economy / ore data (`Config.lua`, `OreIncome.lua`, `CrystalService.lua`, `PlaceholderFactory.lua`)
- 15-tier / 18-ore chain exactly matching your table (Coal → Singularity), sliding 4-ore window per tier (3 inherited + 1 new).
- Weighted drop odds within a tier: 60/30/8/2 (oldest ore in the window → newest), via `Config.RollOreForTier`.
- Every dropped piece is rolled individually and shows honest odds: `IRON` / `1/20`, or two lines with a mutation: `IRON SOAKED` / `1/60`.
- Yield per successful mine run scales 5 (tier 1) → 20 (tier 15), `Config.Mine.OreYieldByTier`.
- Passive "crystal" income rebalanced to flat **5% of a full cart's value per minute** (`Config.Geodes.PassiveIncomePercentOfCart` × `PassiveIncomeMultiplier`), duplicate-level bonus and mutation cap both cut hard. Mining stays the dominant income source.
- `PlaceholderFactory.OreCrystal` looks for a builder asset per ore (`Crystal_Iron`, `Crystal_Singularity`, etc.), falls back to a colored placeholder.

### New mine-expedition flow (`MineService.lua`, `PlotService.lua`, `PlaceholderFactory.lua`, `CartService.lua`, `MineExpeditionUI.client.lua`)
- Old "cart parked in zone → ore auto-drips" mechanic fully disabled (`Config.MiningRhythm.Enabled = false`, code left in place, not deleted, easy to resurrect).
- `MinerNPC` placeholder + dialog → **GO TO MINE** button → server-driven walk-in, camera dolly back/up (same technique as your existing upgrade-reveal camera).
- Server-authoritative arc minigame: needle sweeps a track, 3 sequential random hit zones, client never trusted for timing (mirrors the old rhythm-minigame's honesty check).
- Each hit: FOV kick, mine "bulge" (ScaleTo pulse), MineDoor part recolors (progressive warm-up, then final color by the rarest ore in the batch — `Config.MineDoorRarityColor`). `VFX_<Rarity>` particle/beam/trail children under `MineDoor` are auto-toggled.
- Ore batch rolled (rarest piece first/center, then a pair, then waves), ejected on a parabolic path from the door to scattered ground points, landing black ("spoiler shell", same trick your mutation visuals already use), then revealed with the odds billboard after a short pause.
- Ore now lands in `workspace.MineGroundOre` instead of flying into the cart — **new** `CartService` heartbeat loop picks it up when you drive the cart over it (reuses your existing "fly into cart slot" animation).
- Geode drop-on-mine (pity timer + tutorial-guaranteed geode) still routes through the existing `GeodeService:TrySpawnForMine`, unchanged.

## ⚠️ Known gap — needs your attention before shipping
The **old mining tutorial** (first-cart funding, guaranteed early geode slot, "load N ore to advance") was written *inside* the old infinite mining loop. I preserved the guaranteed-geode call and re-added the HUD attributes it reads (`MineActive`, `MiningCartTier`, etc.), but the "auto-fund the player when their first cart fills" step is not wired into the new expedition flow yet. New players will need this addressed before the tutorial is trustworthy again — flagged with a `TODO` comment directly in `MineService.lua:StartLoop`.

## ❌ Not started yet (from your two messages)
1. **Geode opening rework** — hammer-tap minigame (2–3 hits, camera framing player + anvil), new drop table with temporary buffs (×2 money/luck/speed).
2. **Fisch-style shop UI** — mine/cart/pickaxe card layout, asset-driven (`Mine_Tier1..15`, etc.), and making sure it composes with UI elements you add later.
3. Extending `CartTiers`/`PickaxeTiers`/`MineChain` gameplay stats to reach 15 tiers, and — separately — the Robux gamepass tables (`CartFillByTier`, etc.) which are hard-capped at 9 because they reference **real Roblox asset IDs** I can't invent. Extending those needs actual Dev Product IDs from your Creator Dashboard.

## ✅ Done (this pass, continued)
- `Config.Buffs` — the 4 buff definitions (Money/Luck/Speed/Damage), durations pool (60s / 300s, matches "on a minute, 5 minutes").
- `GeodeService:rollReward` now has a working `Kind = "Buff"` branch — rolls a random buff + duration, calls `BuffService:Grant`, returns a result card the existing UI renders.
- `GeodeUI.client.lua` result cards handle `Kind == "Buff"` titles correctly.
- Trimmed the crack-tap count from 4 → 3 to match "hit it 2-3 times".
- Full repo re-validated end to end — 0 syntax errors across all files.

## Still open
1. The 3D camera-framed hammer-swing presentation (player + geode on an anvil) — I deliberately left your existing, working 2D tap-crack UI alone rather than replace it; wiring in 3D staging on top of it is a reasonable follow-up if you still want it.
2. Fisch-style shop UI.
3. Extending `CartTiers`/`PickaxeTiers`/`MineChain` to 15 tiers, and the Robux gamepass tables (need real Dev Product IDs from you).
4. The mining-tutorial gap flagged earlier (`MineService.lua:StartLoop` TODO).

## ✅ Done (this pass — fixes from your Studio feedback + image references)
- **Camera direction fixed**: was pulling back along the wrong side of `MineEntryPoint` (ending up underground/in textures). Flipped the sign; added a one-line `CAMERA_BACK_SIGN` toggle in `MineExpeditionUI.client.lua` in case a specific mine tier's marker is still oriented the other way.
- **Arc minigame rebuilt to match your reference image**: was a flat horizontal bar, now a proper radial fan (rainbow-colored wedges + rotating needle on a hinge, matching the pixel-art reference's shape/feel). Target zone is redrawn each round as a bright highlight overlaid on the fan. Structure only — colors/art are still placeholder, ready for your builder pass.
- **Balance/Prestige HUD redesigned to match your reference image**: old side-by-side money/rebirth pill pair removed. New layout: circular character-portrait `ViewportFrame` on the left (new `PlayerPortraitHud.client.lua` clones your live character into it and rotates it slowly, same technique your `SkinUI.client.lua` already uses for skin previews) + dark balance bar + smaller "PRESTIGE: N" bar underneath, matching the reference. Kept the exact same part-name contract (`MoneyPill`/`RebirthPill`/`Value`) so `HudService.lua`'s server-side update logic didn't need touching — only the visual layout in `tools/BuildUIAssets.lua` and the prestige label's "PRESTIGE: " prefix changed.

## ✅ Done (gamepass shop redesign, this pass)
- Redesigned `tools/BuildShopUi.lua` (the Studio-side template builder for `StarterGui/ShopUi`) to match the "Prospector's Shop" reference: dark panel with rounded corners + purple stroke, dark header with a purple-gradient italic-style title and a ribbon-shaped icon placeholder on the left, red "X" close button, gold-accented tabs (renamed "Deals" tab's *display* text only to "Products" — the underlying `"Deals"` key is untouched everywhere else in the codebase, zero risk to `RebirthService`/`UpgradeService`/`NotifyService`/localization that reference it by that key). Cards now have rounded corners and a colored accent border (purple for gamepasses, gold for one-time purchases) instead of a flat rectangle.
- This UI is populated live from your **real, existing** `Config.Shop.Items`/`Config.GamePasses`/`Config.DevProducts` (Golden Shield, cash multiplier passes, weather-event triggers, money packs, geode packs, etc.) — not the specific items shown in your reference screenshot (Strength Totem, Meteor Shower, Void Portal, etc. are from a different game and aren't things your project has); the reference was treated as a **style guide**, matching layout/card chrome/colors, not literal content to copy in. If you actually want new mechanics like a server-wide "Meteor Shower" luck event or a "Void Portal", that's new gameplay design beyond a UI reskin — happy to scope that separately if you want it.
- Made two small, register-safe edits inside `CustomCartUI.client.lua`'s already-isolated `setupShopUi()` function (tab highlight color, card accent-by-type) — re-verified with `-O0` that the file still compiles clean after these.
- Did **not** touch the single-page-with-sections layout (Forever Pack / Products / Passes all visible at once, scrolling) — kept your existing, working tabbed-pagination architecture (Passes / Products tabs) rather than re-architecting it, since that's a much bigger structural change with more risk for less clear benefit.


## ✅ Done (this pass — cart animation, quest UI, full audit)
- **Cart-loading animation improved**: ore pieces no longer land in a perfect grid facing the same way. Slot positions now get small random jitter (±18% of a cell) so neighbors sit slightly closer/farther apart, and every piece now visibly tumbles (a guaranteed 90/180/270° flip around a random horizontal axis) as it falls before settling into its final resting spin.
- **Quest UI restyled toward the Fisch-style reference**: blue ribbon-bookmark icon + blue "QUESTS" title + red X, added a "Main Quests" section header with an underline above the list.

## 🔍 Audit against everything asked for so far

**Confirmed working / already satisfied:**
- Full mine-expedition flow, arc minigame, MineDoor rarity VFX, ordered ejection, ground pickup — in place.
- 15-tier/18-ore chain, honest odds display, yield scaling 5→20 — in place.
- Economy rebalance (crystal passive income → 5%/min of cart value) — in place.
- Geode buffs + rebalanced drop table — in place.
- Geode quantity-selection ("choose which geode + how many") — already existed in the project before this rework (`OpenCountMenu`), confirmed intact.
- Instant/no-delay slime selling — `Config.Bank.SellMinimumDelay` (0.035s) and the coin-stagger delay (0.04s/coin) are both already imperceptibly small; didn't find an actual multi-second delay to remove. Looks pre-fixed.
- `Mine_TierN` asset naming — already the established convention, now covers 1–15 automatically.

**Found and just fixed — this was a real gap:**
- The upgrade shop (Mine/Cart/Pickaxe purchase cards) was never reordered — it was still Mine/Cart/Pickaxe (mine on the left), not mine-in-the-middle as originally requested. I'd mistakenly only redesigned the *gamepass* shop a few turns back and missed this one entirely. Fixed in `tools/BuildUpgradeShopCards.lua` and its runtime counterpart in `CustomCartUI.client.lua` (kept in sync — same class of bug as the earlier shop-tab-color mismatch) to Pickaxe/Mine/Cart.

**Confirmed still NOT done (real, open gaps):**
- The upgrade shop's visual skin (colors/borders/art) — only the card *order* is fixed now, not restyled to match Fisch yet.
- `CartTiers`/`PickaxeTiers`/`MineChain` still only go to 9 tiers, not 15.
- 3D camera-framed hammer/anvil geode-opening presentation — still using the existing 2D tap-crack UI.
- "Mastery" quest tab and true Daily/Weekly sections with real reset timers — no backend system exists for these; didn't fake a countdown UI that doesn't actually reset anything.
- Quest reference's "Track" text-button style vs. the checkbox-pin explicitly requested earlier in this conversation — kept the checkbox since it was a direct prior fix.
- Real Robux gamepass Dev Product IDs for tiers 10–15, and "all UI in Fisch style" generally — only Shop and Quests touched so far; collection menu, mutation book, and other HUD elements are still the old look.

## ✅ Done — upgrade shop (Mine/Cart/Pickaxe) redesigned to match Fisch style
- `tools/BuildUpgradeShopCards.lua` restyled to match the same dark/rounded/colored-accent look as the gamepass shop and quest menu: dark navy header (was green) + gold ribbon-bookmark icon + red X close button, dark rounded panel.
- Found and removed a leftover "flatten" step at the end of the builder that was **destroying every rounded corner and border on purpose** (an earlier "flat pixel-art, no outlines" style choice from before this rework) — it was silently undoing all the rounding/stroke code throughout the file. Removed it so the new Fisch-style rounded corners and colored borders actually show up.
- Each branch's card now has its own colored accent border instead of one neutral color for all three: gold for Mine (the centered, primary card), purple for Pickaxe, blue for Cart.
- Checked `CustomCartUI.client.lua` for the same "hardcoded duplicate color" trap that bit the shop tabs and card order earlier — the only matching-looking hardcoded reds there belong to unrelated buttons (settings/mute toggles), not this shop, so no sync fix was needed this time.

## ✅ Done (this pass — bug fix, cart-fill removal, full shop re-architecture)
- **Fixed the `PlayerPortraitHud` crash** (`attempt to index nil with 'GetDescendants'`): `character:Clone()` can return `nil` if `Archivable` is `false` anywhere on the model. Now forces `Archivable = true` before cloning (restores it after) and added a defensive nil-check so it warns instead of hard-crashing if cloning still fails for some other reason.
- **Removed the cart auto-fill-for-Robux UI entirely** ("FILL INSTANTLY" button) — both the builder code (`tools/BuildUIAssets.lua`) and the client logic (`setupInstantFillUi` in `CustomCartUI.client.lua`) are gone. Left the underlying `Config.DevProducts.CartFillByTier` data and its `MonetizationService` receipt handling alone (harmless orphaned data — no client entry point can trigger a purchase of it anymore).
- **Shop fully re-architected** — this was the biggest piece. Previously: tabs (Passes/Deals) + fixed 6-slot pagination with Prev/Next. Now: **no tabs**, every category is its own section stacked vertically in one scrolling list, exactly like your reference (`tools/BuildShopUi.lua` rebuilt from scratch; `setupShopUi` in `CustomCartUI.client.lua` rewritten to match — dynamic card cloning per real item instead of fixed page slots, no pagination logic left anywhere).
- **Applied your attached style guide** to the shop specifically: minimal 0–4px corner radii (no big rounded pills), thin 1px borders instead of heavy strokes, functional color coding (yellow price/action buttons instead of green, blue section headers, red close, purple/gold reserved for gamepass-vs-product accent only). The "Prospector's Shop" purple title/ribbon branding from your reference image was kept as an intentional exception (brand identity, not a generic UI color).
- Re-verified `CustomCartUI.client.lua` compiles clean at `-O0` after this large rewrite (still the fragile file from before — this edit was net register-*negative*, since pagination/tab code was larger than what replaced it).

## Still open
- **Geode 3D opening** (camera pulls back to frame both geode-on-anvil and player, hammer-swing animation + 2–3 on-screen tap hits, FOV spring per hit, scatter drop pickup-only-by-breaker) — not started. This is a similarly-sized feature to the mine-expedition rebuild from earlier in this conversation; next up if you want it.
- Applying the attached style guide to the *rest* of the UI (upgrade shop's colors/corners, quest menu, HUD, collection menu, etc.) — only the shop has the new flat/functional-color treatment so far.
- Everything else listed as open in earlier summaries (tier tables capped at 9, real gamepass Dev Product IDs for 10–15, the mining-tutorial auto-fund gap).

## ✅ Done — geode 3D opening (this pass)
Built on top of your existing 2D tap-crack system rather than replacing it — the same tap count, cooldown, and "final tap fires the server request" logic is untouched; this adds a 3D world layer around it:
- **Camera** pulls back on `beginCrack` to frame both the player and the geode-crushing station ("Crusher" — your project already has this built as the geode-opening anvil, I didn't need to add a new one), reusing your existing `lockCameraForOpening`/`unlockCameraForOpening` freeze system rather than building a second, conflicting one (found and avoided a real bug here: a second independent camera-lock would have captured "Scriptable" as its own restore state and left the camera stuck permanently).
- **Hammer animation** plays on the player's Humanoid if you set `Config.Geodes.HammerAnimationId` (0 = skipped, no error).
- **FOV "spring"** kicks on every qualified tap (`Config.Geodes.HitFOVKick`), same technique as the mine minigame.
- A **decorative 3D geode model** appears on the anvil during the tapping (via your existing `PlaceholderFactory.Geode`), and on completion it spins and shrinks away.
- **Scattered decorative drop props** fly out from the anvil in an arc and land around it (count capped at `Config.Geodes.ScatterMaxDrops`); the player collects them by walking up to them. These are client-only decorative instances — the actual rewards were already granted by the server the moment the tap sequence finished (economy untouched), so "only the person who broke it can pick things up" is automatically true: nobody else's client even has these props.
- Camera eases back to the player during/after the scatter, with a hard timeout so nobody can get stuck in the cutscene chasing the last prop.
- Full cleanup wired into the existing `closeAll()` exit point (stops the hammer animation, destroys any leftover geode model/props) so nothing lingers if the player closes the window mid-sequence.

This is all still placeholder-tier visually (a generic ball for scattered drops, no real hammer animation until you supply an ID) — same "you'll skin this yourself" pattern as everything else in this project.

## ✅ Done — old geode 2D minigame deleted, replaced with orbit-camera 3D version
By direct request, the classic 2D "tap the egg icon, watch it shake and grow, then split into two halves" minigame is now genuinely gone from the source, not just hidden:
- **Deleted at the source**: `EggImage`/`CrackGlow`/`LeftHalf`/`RightHalf`/`DropSilhouette` construction removed from both `tools/BuildGeodeUI.lua` and the client-side fallback builder in `GeodeUI.client.lua`. (`EggImage` survives only as a permanently-invisible internal template, since `ResultImage` used to clone from it — harmless, never shown.)
- **New behavior** (matches your correction from the anvil-framing version): camera pulls back and **slowly orbits around the player** (not a fixed anvil), player movement is locked (`WalkSpeed`/`JumpPower` zeroed, restored after) so they can only click, a 3D geode floats in front of them and **shakes + grows** with every click.
- On completion: the geode **shatters into flying debris shards** that tumble outward and fade (not just a scale-down), and colored **Trail-enabled drops fly out in curved arcs**, landing and then **spinning in place** until the player walks up and collects them.
- The tap hit-region is now full-screen (was a small fixed 290×290 box) since the orbiting camera means the geode isn't reliably centered on screen anymore.
- Found and fixed a real bug during cleanup: `showResult` was still calling the new scatter function with the old (now-deleted) anvil-based signature — would have hard-crashed the moment any geode finished cracking. Fixed and re-verified.
- Full cleanup wired into the existing single exit point (`closeAll()`): stops the camera orbit, unlocks player movement, resets the crack-sequence flag, and destroys any leftover geode/props — so nothing gets stuck if the player closes the window mid-sequence.
- Re-validated: 0 syntax errors, register usage 148/200 (safe margin) on the client file, full repo re-checked clean.

## 🐛 Fixed: minigame invisible after previous pass
Found the bug from your report ("не вижу на экране миниигру"). In `beginCrack`, I'd set `opening.Visible = false` thinking the 2D overlay Frame itself wasn't needed anymore now that the scene is 3D — but `CrackTapButton` (the fullscreen click-catcher) and `ClickHint` ("CLICK!" text) are both children of that same `opening` Frame, and Roblox hides all descendants when a parent Frame's `Visible` is false, regardless of the children's own `Visible` property. So the fix accidentally hid the entire interaction layer along with it. Changed back to `opening.Visible = true` (it's fully transparent itself, so this doesn't reintroduce any 2D visuals — only unhides the invisible-but-functional click button and hint text). Re-validated clean.

## ✅ Done — geode drop reveal deferred to pickup, ball-tap minigame, HUD repositioning
- **Geode drops no longer show what they are until picked up.** Scattered drop props are now a neutral dark color (no more rarity-tinted hint), and the old immediate VFX flash + result-card reveal right after the crack is gone entirely for the normal (non-goblin) flow. Each drop now shows a **slide-in notification from the right edge of the screen** (stacks cleanly if you grab several in a row) only at the moment you actually walk up and collect it — matches "дроп не должен показываться после жеоды, только после поднятия."
- **Replaced the fullscreen invisible click-catcher with an actual visible ball-tap minigame**, built as a real ImageLabel/ImageButton: a pulsing circular ball spawns at a random point on screen, tapping it registers a hit and immediately respawns a new ball at a new random position, same hit count and same server-request timing as before.
- **Weather label and Safe Zone label moved to the bottom-right** (were bottom-left).
- **Player portrait HUD moved to bottom-left** and **replaced the live 3D character viewport with a static Roblox avatar thumbnail** (`Players:GetUserThumbnailAsync`) — much simpler, no more character-cloning edge cases, and it's what was actually asked for.
- All changes re-validated (0 syntax errors, register budget 158/200 on the geode client script — still safe).

## ✅ Done — portrait HUD back to live 3D viewport, face-forward with limited sway
Reverted the static-thumbnail portrait back to a live `ViewportFrame` character render per your follow-up, but built to your exact spec this time:
- Camera sits directly in front of the character's face (not the old three-quarter angle) — character centered, looking straight at camera.
- Instead of a full continuous spin, the character now **sways left-right within a hard ±45° limit** using a sine wave computed from a fixed base orientation each frame — it physically cannot drift past that limit since it's not cumulative rotation.
- Kept the `Archivable`/nil-clone defensive fix from before so this can't reintroduce the earlier crash.
- Position stays bottom-left as you set previously.
- `tools/BuildUIAssets.lua` reverted `Portrait` back to `ViewportFrame` — **you'll need to re-run that Command Bar script again** since it flipped back from the ImageLabel version.

## ✅ Done — one consolidated script to rebuild all UI
Created `tools/BuildAllUI.lua` — paste this ONE file into Studio's Command Bar and run it; it deletes and rebuilds all 23 UI screens in one go (Hud, Shop, Upgrade Shop, Quests, Geode vault + count menu, Collection Menu, Mutation Book (+ crystals tab), Rubble Crystal UI, Skin entry/UI, Rebirth dialog, Leaderboards, Notifications, Daily Reward, Like/Group reward popups, Starter Pack, Return Screen, Tutorial card, Money FX). No more running 20+ separate Command Bar scripts one at a time.

Technical notes:
- This is a **mechanical concatenation**, not hand-written — each `tools/BuildXxx.lua`'s body is wrapped in its own `local function` and called via `pcall`, so (a) a failure in one builder doesn't stop the rest, and you get a clear OK/FAILED report per screen at the end, and (b) each builder gets its own fresh Luau register budget — this avoids the exact 200-register-limit crash from earlier in this session, confirmed by compiling it and checking (peaks at only ~54/200 registers).
- Deliberately **left out** `BuildLikeRewardUI.lua`/`BuildGroupRewardUI.lua` — these are already-deprecated thin wrappers that just call `BuildRewardPopups.lua` (which is included and builds both windows itself).
- Deliberately **left out** pure 3D-asset/spawn-point builders (`BuildGeodeAssets`, `BuildSkinAssets`, `BuildCartSizeGuides`, `BuildRubbleBoulderSpawnPoints`, `BuildMobBillboardTemplates`, `BuildNewAssetWorkspacePack`) and one-off utility/editor scripts (`BuildMobileLayoutEditor`, `FixDisabledUi`, `HarvestMobileLayout`, `GearModelRotationScript`, `ExampleNpcStretchScript`) — these aren't "delete and rebuild a UI screen" scripts and could have unintended side effects if auto-run blind; run those individually if you specifically need them.
- **Keep editing the individual `tools/BuildXxx.lua` files**, not this one directly — it's a generated snapshot. If you want it regenerated after further edits, just ask.

## ✅ Done — GamepassQuickBar removed entirely
Deleted the bottom-right quick-gamepass-buttons feature completely, not just hidden:
- Removed the entire `setupQuickBar()` function (~600 lines) from `CustomCartUI.client.lua`, plus its dead defensive `Config.QuickBar.*` defaults and its entries in the mobile-scaling and other-UI-names lists.
- Deleted `tools/BuildGamepassQuickBar.lua` outright and removed it from `tools/BuildAllUI.lua` (regenerated, now 22 blocks) and the "always-on" ScreenGui lists in `EnsureCoreUiEnabled.client.lua` and `FixDisabledUi.lua`.
- Left `Config.QuickBar` itself in `Config.lua` alone — `tools/BuildShopEntry.lua` still reads `Config.QuickBar.HintImageId` for an unrelated icon on the shop button, so removing the table would've broken that.
- Left the server-side `NeedsRebirthSkip`/gamepass-ownership attribute logic in `RebirthService`/`MonetizationService` alone — it's cheap to compute and not exclusively tied to the quick bar; only its one actual UI consumer is gone now.
- Re-validated: 0 syntax errors, full repo clean.

**Re-run `tools/BuildAllUI.lua` (or delete `StarterGui.GamepassQuickBar` by hand)** to remove the old ScreenGui from your place — code changes alone won't delete an asset that's already sitting in StarterGui from a previous build.

## ✅ Done — geode drop scatter made much more appealing
- **Distance**: scatter radius more than doubled (`Config.Geodes.ScatterRadius` 7 → 16 studs) — drops fly out much farther from the break point.
- **Speed/smoothness**: flight time increased (0.55s → 0.85s) with a smoothstep ease-in-out curve instead of linear movement, and the arc height raised (6 → 9) so the slower flight still reads as a satisfying toss rather than a slow drift. Camera-return timing bumped to match so it doesn't snap back before drops land.
- **Landing squash-and-stretch**: on impact, each drop briefly flattens wider and shorter, springs to a slight overshoot taller/narrower, then eases back to its normal round shape — classic squash-and-stretch, tunable via the new `Config.Geodes.LandingSquashVertical/Horizontal/Seconds`.
- Re-validated: 0 syntax errors, register budget unchanged (158/200).

## ✅ Done — portrait viewport rotated 180° and moved closer
Realized the previous camera setup was showing the back of the character's head, not the face — Roblox characters face -Z by default, and the camera sat on the +Z side looking inward, so it was looking at the same side the character was facing away toward. Rotated the character's base orientation 180° so it now faces the camera, and pulled the camera in slightly (3.2 → 2.6 studs). The ±45° sway still works the same, just now sweeping around a face-forward pose instead of a backward one.

## ✅ Done — camera markers, cart restriction removed, ore-drop physics fixed, stray buttons hardened

**Camera marker system** (replaces computed dolly with builder-placed markers):
- `PlotService` now collects `CameraMarkerN`/`CameraMarkerNLook` part pairs from inside the mine model — place as many as you want, name them sequentially.
- `Config.MineExpedition.CameraMarkerForStage` maps stage names (`WalkIn`/`Minigame`/`Eject`/`WalkOut`) to marker numbers — pure data, no code changes needed to reassign.
- `MineExpeditionUI.client.lua` uses your marker's position/look-at directly when present; falls back to the old computed dolly only for stages where you haven't placed markers yet, so nothing goes dark mid-setup.

**Cart restriction removed**: expeditions can now start with a full or non-empty cart — capacity is only enforced where it actually matters (ground pickup).

**Ore ejection physics overhaul**:
- Found and fixed the actual bug behind "ore appears in the air, not on the ground": landing height was inherited from a leftover point positioned *above* the old cart-fill mechanic, never real ground. Replaced with a downward raycast against the plot's own floor for every landing spot.
- Landed ore now spins in place continuously (shared server Heartbeat, stops naturally once picked up) — no per-piece coroutine needed.
- Scatter radius, arc height, and flight time all increased; each flying piece now has a real `Trail` and tumbles on a random horizontal axis (proper end-over-end "volleyball" tumble instead of a flat vertical spin).
- Confirmed the reveal order (rarest → center first, then a side pair, then waves) was already correct from earlier work.

**Stray UI buttons**: found that `ShopEntry`/`SkinEntry` were already supposed to be routed entirely through the collection-menu "book" (pre-existing code, not new), but the disabling happened *late* in each setup function — meaning any earlier error in that same function would leave the old floating button visible on screen. Moved both disables to fire immediately after the GUI is found, before any code that could throw, so they're hidden unconditionally regardless of what happens afterward.

All changes validated: 0 syntax errors, full repo clean.

## ✅ Done — drop location, ejection timing, cart physics, arc minigame rebuild

**Ore drop location**: now lands around `plot.PlayerSpawnCFrame` (the exact point where you respawn on your own plot) instead of a leftover point near the mine door.

**Ejection timing rewritten from scratch** — the old system was many independent parallel timers with small, hard-to-follow offsets. Replaced with a single linear sequence: batch 1 (rarest, center) ejects → wait `Config.MineExpedition.BatchGapSeconds` (2s) → batch 2 (side pair) ejects **and batch 1 reveals its rarity at that exact moment** → wait 2s → batch 3 ejects and batch 2 reveals → ... → the final batch reveals itself after landing since there's no "next" batch to trigger it. Matches "rarity only reveals when the next one appears" exactly.

**Cart stacking — real physics** (this one's a genuine risk, flagged below): ore now actually falls with `Anchored = false` and real collision, tumbling and settling against the existing pile and cart walls like a real physical object, then gets frozen in place (`Anchored = true`, welded at wherever it physically landed) instead of animating to a predetermined grid slot. **I could not test this live** — physics behavior (bounce, clipping, interaction with the cart's own movement constraints) can only really be verified in Studio. If pieces end up flying out of the cart or clipping oddly, the fix is almost certainly tuning `PHYSICS_SETTLE_SECONDS` or the random impulse strength in `CartService.lua`, both isolated in one place.

**Arc minigame rebuilt from the actual root cause**: the previous version anchored every colored piece *at* the pivot and let it grow outward — that's a pie-slice fan, not the rainbow-arc band from your reference. Rewrote it so each piece is centered *on* the circle at a fixed radius and rotated tangent to it, so they line up edge-to-edge into a real curved band matching the picture. The target-zone highlight now overlays directly on that same band (not a separate ring floating outside it), so it's clear which stretch of the arc you're aiming for. The needle logic (radiating from the pivot, swinging ±85°) was already correct and didn't need to change.

All validated: 0 syntax errors, full repo clean.

## ✅ Done — cart physics reverted, minigame now has real stakes
- **Cart physics removed entirely**, back to the deterministic slot-tween system (with the jitter + tumble improvements from earlier kept — pieces still don't look robotic, but they mathematically cannot overlap since the grid guarantees spacing).
- **First/rarest drop is now permanently marked GIGANTIC**: scaled 1.5x and gets its own glowing badge above the normal price tag, revealed at the same moment as its rarity.
- **Arc minigame now has real risk/reward**: zone width is randomized every round (8%–22% of the arc) instead of fixed — narrower zones are harder to hit but grant a bigger "luck" bonus. Every successful hit also gives a flat luck bonus regardless of zone size. Accumulated luck nudges the final ore roll toward the rarer slots in the tier's 4-ore pool (capped, doesn't override the base odds table, and the *displayed* "1/N" odds stay honest/unaffected — only the actual roll is nudged). Visible to the player via the hit counter now showing "LUCK +N%".

## ❌ Not done — flagged clearly, this is a real feature, not a quick add
**Ore variant system (1/2/3 per ore type)** — turning today's ~18 ores into ~54 mesh-based value tiers (variant 1 cheapest, 2 slightly above, 3 most expensive) touches the core economy data model, the drop-roll logic, the UI labels, and eventually real mesh assets once you have them. I did not attempt this in the same pass as the changes above — it deserves its own focused turn rather than being rushed in alongside everything else. Ready to start on it whenever you want.

## ✅ Done — ejection animation, minigame rework, builders, ore variants

**Ejection animation rebuilt on researched principles** (Disney 12 principles / "game juice" — squash & stretch, anticipation, arcs, slow-in/out):
- *Anticipation*: ore briefly crouches/compresses before launching.
- *Volume-preserving stretch*: stretches along its direction of travel proportional to actual speed, narrowing laterally by 1/√factor so it reads as a body with mass, not an inflating balloon (the specific mistake the research called out).
- *Squared arc*: apex is reached earlier than mid-flight with a slight hang, then an accelerating fall — flat parabolas read as lifeless.
- *Squash on impact*: flattens, rebounds slightly stretched, settles — kept short (a few frames) per the research's warning about rubbery-looking deformation.

**Minigame reworked around the actual complaint** ("каша, непонятно куда тыкать"): the old arc had a decorative rainbow that meant nothing plus one anonymous hit zone. Now the track is neutral dark, and each round the server sends a real zone layout — `Red | Yellow | GREEN | Yellow | Red` — that's drawn exactly as the server will judge it. Green is narrow, centered, visually thicker, and worth the most luck (0.10); yellow is middling (0.05); red is wide and nearly worthless (0.01) but still counts so the round progresses. Hit feedback now names the zone ("PERFECT!" / "GOOD" / "WEAK") in that zone's own color.

**Builders added/updated**:
- New `tools/BuildMineArcUI.lua` — the arc minigame is now a Studio asset you can restyle by hand; the client uses it when present and falls back to code otherwise. Round zone colors/widths stay in `Config.MineExpedition.ZoneKinds` **on purpose** — drawing them in Studio would let the visuals drift from what the server actually scores.
- `tools/BuildNotificationUI.lua` restyled to match the geode drop-notification card (dark right-edge card, 4px corners, accent stroke) — the client derives its slide animation from the panel position, so it adapted automatically.
- Both registered in `tools/BuildAllUI.lua` (now 23 blocks).

**Ore variants 1/2/3 finished**: `Config.OreVariants` (×1.00 / ×1.25 / ×1.60 value, weights 60/30/10) rolled independently on top of the ore itself, so 18 ores → 54 combinations without touching tier tables. Variant shows in the label ("IRON II"), scales the rock slightly, sets a `CrystalVariant` attribute, and multiplies into the honest displayed odds. Mesh hook is ready: drop `Crystal_<Ore>_V<N>` (e.g. `Crystal_Iron_V3`) into Assets and the factory picks it up, falling back to the shared `Crystal_<Ore>` for variants you haven't modeled yet.

## ✅ Done — crash fix, anvil geode, shop categories, daily rewards restyle

**Fixed `CollectionMenu:1244` crash** — this was my own regression: when I rebuilt `Config.MineTiers` from the ore chain back in the first pass, I dropped the `Description` field the old table had, so the mutation card's `string.format` got nil. Added real descriptions to all 18 ores, propagated `Description` into `MineTiers`, and made the consumer nil-safe so a missing description can never crash the menu again.

**Geode opening is now strictly on the anvil** — the decorative geode is placed on the Crusher's top face (height computed from the model's bounding box so it doesn't sink in), and the orbit camera now circles *the anvil* rather than the player, so the anvil can't drift out of frame.

**Shop split into real categories with per-section gradients**: `Boosts` (gold), `Game Passes` (purple), `Cash Packs` (green), `Weather Events` (red), `Special Offers` (blue). Each section gets a gradient backdrop and a header tinted to match. `Deals` was deliberately kept as a live key because `RebirthService`/`UpgradeService`/`NotifyService` reference it via `PreferredTab` — renaming it would have silently broken those "you need more money → open shop" prompts.

**Daily Rewards restyled to shop style** — dark translucent panel, 4px corners, dark header with the same ribbon bookmark + red X, card strokes, day 7 highlighted green, yellow claim button.

**Arc minigame builder** — `tools/BuildMineArcUI.lua` was already added last pass and is registered in `BuildAllUI.lua` (23 blocks); the client prefers the Studio asset and falls back to code.

## ⚙️ Inventory system — foundation built (server-side complete, UI still to do)

Implemented exactly to the rules you specified:
- **Pickup by walking over ore** — one shared Heartbeat loop (cheaper than a Touched handler per rock, and unaffected by whether a rock got collision after landing). Only the owner of a drop can pick it up.
- **Routing**: cart in hand → cart; otherwise → backpack. Single source of truth (`InventoryService:TryPickup`) so both paths can't drift apart.
- **Selling from both** backpack and cart.
- **Death drop = 25% random**, removed one item at a time from random stacks rather than wiping whole stacks — otherwise "25%" could have wiped your entire supply of one rare ore.
- **Slots**: 24 base, `ExtraPouch` repurposed to **+12 slots** (its old +2 hand-carry bonus is *kept* so existing buyers don't lose what they paid for), new **`InfinitePouch`** pass removes the cap. Added to the shop — `Id = 0` until you create it in the Creator Dashboard.
- **Pickaxe switching** across any unlocked tier, plus **skin buffs** (`Config.PickaxeSkinBuffs` — small Damage/Luck/Speed bonuses so skins matter without outpacing real upgrades). Skin ownership is verified server-side via `SkinService:OwnsSkin`, so nobody can equip a Void skin they don't own.
- **Gifting** validated server-side: distance checked, and the recipient's space is confirmed *before* removing the item from the giver — otherwise the ore would vanish from one inventory without arriving in the other.
- Stacks only merge when ore + variant + mutations all match, so a Frozen Iron II can't get swallowed into a plain Iron II pile.
- Hotbar stores stack indices, which shift when a stack empties — the removal path repairs those references so a slot can't silently point at someone else's item.

**Still to build**: the inventory UI itself (Backpack/Pickaxes tabs, search/sort, the hotbar with the F pickaxe slot), holding ore in hand with its rarity billboard, and the gift hold-interaction on the client.

## ✅ Inventory UI complete

**New `tools/BuildInventoryUI.lua`** builds two ScreenGuis, styled to match the shop (dark translucent panels, 4px corners, functional colors):
- `InventoryUi` — Backpack / Pickaxes / Index tabs (each with its own gradient like the reference), search box, cycling sort button, Sell All, slot counter, item grid with 3D viewport previews, and a right-hand detail panel.
- `HotbarUi` — slots laid out `1 2 3 [F] 4 5 6`, with the pickaxe slot **physically centered** via LayoutOrder and visually distinguished (larger, gold stroke), per your requirement that the center slot is always the pickaxe.

**New `src/client/InventoryUI.client.lua`**:
- Renders the server snapshot only — no client-side economy.
- **Ore in hand**: selecting a hotbar slot welds a real 3D ore model to the character's hand (so it moves with the arm animation rather than floating at a fixed offset) with a billboard above it showing name + rarity, colored by rarity.
- **Gifting**: hold LMB on another player while holding ore; the server re-validates distance and recipient space.
- Keys 1–6 select slots, F clears held ore for the pickaxe.
- Held item auto-clears if that stack is sold/gifted away, and on respawn.
- Search filters, sort cycles Rarity → Value → Name.

**Index tab** opens your existing Collection Menu rather than duplicating it — maintaining two copies of the same screen would guarantee they drift apart. Both scripts now create the shared open-request BindableEvent the same way, since it's created lazily by whichever script loads first and a race would have left one of them silently dead.

Added `SellBackpack` to the server's action handler (the client referenced it before it existed). Registered in `BuildAllUI.lua` — now 24 blocks.

**Not wired yet**: the Pickaxes tab renders no grid (the server API `EquipPickaxe`/`GetSkinBuffs` exists and is ready, but the tab's cards aren't built), and the skin buffs aren't yet read by CombatService/mining. Those are the natural next step.

## ✅ Done — remaining three inventory items

**1. Skin buffs now actually apply.** `Config.PickaxeSkinBuffs` was previously data with no effect. Wired into the three existing single choke points:
- `Damage` → `CombatService:_swing` (multiplies after the gamepass multiplier)
- `Luck` → `CrystalService.luckFor` (additive, same reasoning as the geode luck buff — multiplying near-zero base luck does nothing)
- `Speed` → `CartService.recomputeWalkSpeed` (applied to the base, so cart-load slowdown still stacks on top and a skin can't cancel out carrying weight)

**2. F key now genuinely equips the pickaxe.** It previously only cleared held ore. Now it (and clicking the center slot) equips/unequips the real Tool via `Humanoid:EquipTool`, mirroring how the old hotbar did it since Roblox's default Backpack UI is disabled.

**3. Pickaxes tab is now populated.** One card per unlocked tier (newest first), equipped tier marked with a green stroke and "ON", 3D preview rendered from the Tool's Handle (a Tool itself won't render in a ViewportFrame). Clicking sends `EquipPickaxe` to the server, which re-validates the tier.

**Tier switching now actually changes the pickaxe in your hands**: `CombatService:_giveTool` reads the player's *chosen* tier instead of always the highest, and `EquipPickaxe` calls the existing `RefreshPickaxe` to swap the Tool, plus recomputes WalkSpeed since the skin's speed bonus may have changed.

### ⚠️ Caught a serious self-inflicted bug while doing this
The old hotbar in `CustomCartUI` binds **both `1` and `F`** to the pickaxe, which collides with the new layout where `1` is an ore slot. My first fix used a top-level `return` to bail out of that section — which in a LocalScript would have **silently killed the remaining ~4,870 lines of that file** (cooldowns, cart respawn/protection buttons, shop, toasts, everything below). Caught it before packaging and replaced it with a scoped `legacyHotbarDisabled` flag that hides the legacy bar and makes its key handler stand down, leaving the rest of the file intact.

## 🔍 Bug audit of the inventory work — 4 real bugs found and fixed

**1. Player setup never ran in Studio solo-play (critical).** `InventoryService` connected its own `Players.PlayerAdded` inside `Init`. But `Main.server.lua` already has an `onPlayerAdded` pipeline that *also* covers players already in the game, and runs each service's `SetupPlayer` **after the data profile loads**. My version bypassed all of that, so: a player already present at Init (the normal case when you hit Play in Studio) got no death hook and no initial sync, and even when it did fire it could race ahead of profile loading and sync an empty inventory. Converted to a proper `InventoryService:SetupPlayer(player)` registered in Main's step list.

**2. RemoteEvent spam when the backpack is full.** `AddOre` called `Sync` on its failure path even though nothing changed, and the pickup loop retries every 0.08s per nearby rock — so standing next to a pile with a full backpack fired continuous network traffic. Removed the pointless sync and added an up-front guard that skips the scan entirely when there's nowhere to put anything.

**3. My own fix for #2 introduced a false negative**, caught on review: the guard checked only free *slots*, which would have blocked topping up a partially-filled stack when slots were full — a pickup that `AddOre` would actually have accepted. Replaced with `HasAnyRoom`, which also counts non-full stacks.

**4. Death drop fired one RemoteEvent per item.** Dropping 25% of a large backpack meant dozens of syncs in a tight loop. `RemoveAt` now takes a `silent` flag; the death loop syncs once at the end.

Also cleaned up an unreadable one-liner in `fillViewport` that computed an unused variable.

### ⚠️ Known limitation, not a bug — flagging honestly
Held ore is spawned **client-side**, so **only the holder sees the ore in their hands and its rarity label** — other players see nothing. Gifting still works correctly (the server validates and transfers), but the visual is local-only. Making it visible to everyone requires the server to spawn the held model and weld it, which is a real change, not a tweak. Tell me if you want that.
