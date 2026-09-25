--------------------------------------------------------------------------------
-- CombatService
-- Server-authoritative PvP.
--   • Атаковать можно ТОЛЬКО без тележки: взял тележку → кирка исчезает.
--   • Урон одинаков для всех тиров (Catch-Up по HP). Физическое ВЫБИТИЕ руды
--     (из тележки и рук) ограничено ОБЩИМ кулдауном на жертву (Config.Combat.
--     KnockoutCooldown), не зависящим от тира кирки атакующего — второй слой
--     catch-up, раньше отсутствовавший (см. ApplyHit). Тир кирки по-прежнему
--     полностью решает частоту/силу самого урона — прокачанный противник
--     всё так же страшен, просто больше не может грабить чаще всех остальных.
--   • Удар по игроку с тележкой одновременно наносит тот же урон самой
--     тележке (её ХП теперь от ТИРА ТЕЛЕЖКИ, см. Config.CartTiers.MaxHealth,
--     не от игрока) — добьют тележку до нуля, она теряет весь груз и
--     открепляется сама, как при смерти держателя (см. CartService:DamageCart).
--   • Своя база (весь PlotPad) и зона сдачи руды в банке (SellZone) — НЕ
--     PvP-зона: находясь там, стать целью нельзя (см. isPositionSafe ниже),
--     но атаковать НАРУЖУ из зоны можно.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config)
local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)
local Sfx = require(ReplicatedStorage.Shared.Sfx)
local GroundCheck = require(ReplicatedStorage.Shared.GroundCheck)

local CombatService = {}

local Services = nil
local lastSwing = {}  -- [userId] = os.clock()
local swingSide = {}  -- [userId] = true (левый следующий) | false (правый следующий)
local animTracks = {} -- [userId] = { Left = track, Right = track, Idle = track }
local swingPlaybackId = {} -- отменяет старый delayed Stop, если уже начался новый замах
local idleConnections = {} -- [userId] = { RBXScriptConnection, ... }
local rng = Random.new()

-- v17: время смешивания позы с киркой (Config.Animations.ToolBlend).
local function toolBlend()
	return (Config.Animations and tonumber(Config.Animations.ToolBlend)) or 0.28
end

local function stopSwingAnimations(player, fadeTime)
	local userId = player.UserId
	swingPlaybackId[userId] = (swingPlaybackId[userId] or 0) + 1
	local tracks = animTracks[userId]
	if tracks then
		for _, side in { "Left", "Right" } do
			local track = tracks[side]
			if track and track.IsPlaying then
				track:Stop(fadeTime or 0)
			end
		end
	end
	return swingPlaybackId[userId]
end

local function disconnectIdleConnections(player)
	local connections = idleConnections[player.UserId]
	if connections then
		for _, connection in connections do connection:Disconnect() end
	end
	idleConnections[player.UserId] = nil
end

local function animationUri(id)
	if not id or id == 0 or id == "" or id == "0" or id == "rbxassetid://0" then return nil end
	local text = tostring(id)
	return text:match("^rbxassetid://") and text or "rbxassetid://" .. text
end

-- Кулдаун на ФИЗИЧЕСКОЕ выбитие руды — на ЖЕРТВУ (см. Config.Combat.KnockoutCooldown
-- и ApplyHit ниже): не зависит от того, кто и с какой киркой бьёт — этого
-- игрока нельзя обчистить чаще раза в N секунд, даже если атакующих несколько.
local lastKnockoutAt = {} -- [userId жертвы] = os.clock()

local lastFreeProtection = {} -- [userId] = os.clock() последней бесплатной активации
local protectionEndsAt = {}   -- [userId] = os.clock(), когда истекает текущая защита (для продления)

-- МИКРО-СТАН: [userId] = os.clock(), когда текущий стан закончится (см.
-- ApplyHit/_applyMicroStun ниже). Скорость на время стана обнуляет
-- CartService:recomputeWalkSpeed сам — читает IsStunned(player).
local stunnedUntil = {}
-- PvP v2 (см. блок «ШКАЛА ОГЛУШЕНИЯ» ниже по файлу)
local staggerState = {}  -- [userId] = { Value, LastHitAt, LastAttackerId, LastAttackerAt, ImmuneUntil, Token }
local comboState = {}    -- [attackerUserId] = { Count, LastAt }
local bountyClaimed = {} -- [userId] = true, пока тележка снова не опустеет ниже порога
local ragdollRecords = {} -- [userId] = record из enableRagdoll
local clashedAt = {}      -- [userId] = os.clock() последнего парирования (один замах = один клэш)

function CombatService:IsStunned(player)
	local until_ = stunnedUntil[player.UserId]
	return until_ ~= nil and os.clock() < until_
end

-- Едва заметная тряска на месте — НЕ перемещение, просто дрожание вокруг
-- текущей позиции (см. Config.Combat.StunShakeAmplitude/Interval). Работает
-- через AlignPosition (физический солвер сам плавно тянет HRP к каждой новой
-- крошечной случайной точке рядом) — надёжнее прямой записи CFrame на
-- физическом, не заанкоренном теле, не конфликтует с обычным движением
-- Humanoid. Останавливается сама через duration, чистит за собой инстансы.
local function applyStunShake(character, duration)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "StunShakeAttachment"
	attachment.Parent = hrp

	local align = Instance.new("AlignPosition")
	align.Attachment0 = attachment
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.MaxForce = 25000
	align.Responsiveness = 45
	align.Position = hrp.Position
	align.Parent = hrp

	local amplitude = Config.Combat.StunShakeAmplitude
	local interval = Config.Combat.StunShakeInterval
	local elapsed = 0
	local sinceLastJitter = 0

	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		if not hrp.Parent then
			connection:Disconnect()
			return
		end
		elapsed += dt
		sinceLastJitter += dt
		if elapsed >= duration then
			connection:Disconnect()
			align:Destroy()
			attachment:Destroy()
			return
		end
		if sinceLastJitter >= interval then
			sinceLastJitter = 0
			align.Position = hrp.Position + Vector3.new(
				(rng:NextNumber() - 0.5) * amplitude * 2,
				0,
				(rng:NextNumber() - 0.5) * amplitude * 2
			)
		end
	end)
end

-- Обнуляет скорость на Config.Combat.MicroStunDuration, затем возвращает её
-- к тому, что реально положено (тележка/руки, см. CartService:RecomputeSpeed) —
-- не жёстко на "базу", иначе сбросило бы замедление от груза после стана.
local function applyMicroStun(player)
	local until_ = os.clock() + Config.Combat.MicroStunDuration
	stunnedUntil[player.UserId] = until_
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
	end
	if character then
		-- pcall — тряска чисто косметическая поверх стана; если она вдруг
		-- упадёт с ошибкой, сам стан (WalkSpeed=0 выше и его снятие через
		-- task.delay ниже) не должен из-за этого сломаться целиком.
		local ok, err = pcall(applyStunShake, character, Config.Combat.MicroStunDuration)
		if not ok then
			warn("[CombatService] тряска при стане упала:", err)
		end
	end
	task.delay(Config.Combat.MicroStunDuration, function()
		if stunnedUntil[player.UserId] ~= until_ then
			return -- уже сняли/продлили новым попаданием — не наша забота
		end
		stunnedUntil[player.UserId] = nil
		if player.Parent and Services.CartService then
			Services.CartService:RecomputeSpeed(player)
		end
	end)
end

--------------------------------------------------------------------------------
-- Визуализация хитбокса удара — параллелепипед прямо перед атакующим,
-- РОВНО ТА ЖЕ геометрия (размер/смещение/масштаб по тиру), что findVictim
-- ниже использует для реального попадания — единая точка правды, не два
-- расходящихся representation одного и того же.
--------------------------------------------------------------------------------
local function debugDrawHitbox(hrp, hitboxSize, color)
	if not Config.Debug.ShowCombatHitbox then
		return
	end

	local box = Instance.new("Part")
	box.Shape = Enum.PartType.Block
	box.Size = hitboxSize
	box.CFrame = hrp.CFrame * CFrame.new(0, 0, -Config.Combat.HitboxForwardOffset)
	box.Anchored = true
	box.CanCollide = false
	box.CanQuery = false
	box.Material = Enum.Material.ForceField
	box.Color = color
	box.Transparency = 0.75
	box.Parent = workspace

	game:GetService("Debris"):AddItem(box, Config.Debug.CombatHitboxLifetime)
end

--------------------------------------------------------------------------------
-- VFX (создаётся сервером → реплицируется всем без клиентских скриптов)
--------------------------------------------------------------------------------

-- Один burst готового Assets/swing в центре игрока при каждом замахе.
-- ParticleEmitter не является физической деталью, поэтому коллизий у эффекта
-- нет; временный Attachment удаляется после завершения самых долгих частиц.
local warnedMissingSwingVfx = false
local function swingVfx(player, color)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local sourceAttachment = PlaceholderFactory.PickaxeSwingVFX()

	local attachment = Instance.new("Attachment")
	attachment.Name = "SwingVfxAttachment"
	attachment.Position = Vector3.zero
	attachment.Orientation = Vector3.new(0, 90, 0)
	attachment.Parent = root

	sourceAttachment.Parent = attachment
	local lifetime = 0.5
	for _, emitter in sourceAttachment:GetDescendants() do
		if emitter:IsA("ParticleEmitter") then
			emitter.Enabled = false
			emitter.Color = ColorSequence.new(color or Color3.fromRGB(255, 255, 255))
			emitter:Emit(math.max(1, math.floor(tonumber(emitter:GetAttribute("EmitCount")) or 10)))
			lifetime = math.max(lifetime, emitter.Lifetime.Max + 0.5)
		end
	end

	Debris:AddItem(attachment, lifetime)
end

-- VFX-плейсхолдер РОВНО на месте попадания (см. PlaceholderFactory.PickaxeHitVFX —
-- заменяется своим ассетом без изменения кода), не привязан к HRP жертвы —
-- работает одинаково что по телу, что по тележке, чем бы удар ни засчитался.
local function spawnHitVfx(position, color)
	local anchor = Instance.new("Part")
	anchor.Name = "PickaxeHitVfxAnchor"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = workspace
	local attachment = PlaceholderFactory.PickaxeHitVFX()
	attachment.Parent = anchor
	local lifetime = Config.Combat.HitVfxDuration
	for _, emitter in attachment:GetDescendants() do
		if emitter:IsA("ParticleEmitter") then
			emitter.Enabled = false
			emitter.Color = ColorSequence.new(color or Color3.fromRGB(255, 90, 90))
			emitter:Emit(math.max(1, math.floor(tonumber(emitter:GetAttribute("EmitCount")) or 10)))
			lifetime = math.max(lifetime, emitter.Lifetime.Max + 0.5)
		end
	end
	Debris:AddItem(anchor, lifetime)
end

-- Зелёная обводка (Highlight) + VFX над головой — на самом персонаже
-- держателя, пока щит реально активен (атрибут Protected) — независимо от
-- тележки: держит защиту, даже не неся тележку, оба эффекта всё равно
-- должны быть видны. Та же обводка вешается и на модель тележки (см.
-- CartService:setShieldVisible), а вот VFX теперь только здесь, над
-- головой, а не над тележкой — общий для игрока, а не только пока в руках
-- что-то есть.
local function ensureProtectionHighlight(character, color)
	local highlight = character:FindFirstChild("ProtectionHighlight")
	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.Name = "ProtectionHighlight"
		highlight.FillTransparency = 1 -- только контур, без подсветки объёма
		highlight.OutlineTransparency = 0
		highlight.Enabled = false
		highlight.Parent = character
	end
	-- Цвет обновляется КАЖДЫЙ раз (не только при создании) — так пасс,
	-- купленный посреди сессии, красится золотом сразу же, без пересоздания.
	highlight.OutlineColor = color
	return highlight
end

-- [player] = {ParticleEmitter, ...} ТЕКУЩЕГО персонажа игрока — обнуляется
-- при каждом респавне (старые вместе со старым Character уже уничтожены).
local shieldParticlesByPlayer = {}
local tutorialProtectionEndsAt = {}

-- Объявлена заранее (тело — ниже): ensureProtectionShieldVfx должна уметь
-- позвать её повторно, когда Head допоздна реплицируется (см. фикс внутри).
local refreshCharacterProtectionHighlight

-- Строит (один раз на персонажа) VFX-точку щита, приваренную над Head —
-- см. PlaceholderFactory.ShieldVfx, тот же контракт замены своим ассетом,
-- что и раньше был у версии над тележкой.
local function ensureProtectionShieldVfx(player, character)
	local useVip = Services.MonetizationService and Services.MonetizationService:HasGoldenShield(player)

	local existing = character:FindFirstChild("ProtectionShieldVfx")
	if existing then
		-- КРИТИЧНЫЙ ФИКС: раньше эта функция строила VFX РОВНО ОДИН РАЗ и
		-- больше никогда не проверяла его снова — если ассет был собран как
		-- обычный (зелёный) ДО того, как владение пассом стало true (или
		-- обновилось не через RefreshShieldVisual), VFX над головой
		-- застревал зелёным навсегда, хотя обводка на тележке
		-- (CartService.setShieldVisible) и Highlight на персонаже
		-- (ensureProtectionHighlight выше) честно пересчитываются заново
		-- при каждом включении и красятся золотом сразу же. Снаружи это
		-- выглядело как "золотая обводка у тележки, а над игроком всё
		-- равно зелёный щит" — рассинхрон именно из-за этого раннего
		-- return'а. Чиним: помечаем собранный VFX атрибутом IsVip и, если
		-- он не совпадает с текущим реальным владением пасса, пересобираем
		-- ассет с нуля вместо того, чтобы молча выйти.
		if existing:GetAttribute("IsVip") == useVip then
			return
		end
		existing:Destroy()
		shieldParticlesByPlayer[player] = nil
	end
	local head = character:FindFirstChild("Head")
	if not head then
		-- БАГ, КОТОРЫЙ ЧИНИМ: совсем свежий персонаж, Head ещё не
		-- реплицировался (чаще всего случается ровно на самом первом спавне
		-- за сессию — то есть как раз пока активна защита новичка). Раньше
		-- здесь был тихий return в расчёте на "следующее изменение Protected
		-- повторит попытку" — но следующее изменение Protected для новичка
		-- наступит только через Config.Protection.NewbieDuration (300 сек),
		-- когда защита УЖЕ закончилась. VFX над головой в итоге строился
		-- только тогда — и сразу ВЫКЛЮЧЕННЫМ (protected к этому моменту уже
		-- false) — а привычный игроку "щит" (Highlight на персонаже) к тому
		-- времени уже погас. Со стороны выглядело так, будто щит над головой
		-- никогда толком не пропадает: на самом деле он и не появлялся
		-- вовремя, просто с опозданием строился в уже погашенном виде и
		-- либо не был виден вовсе, либо (если что-то позже снова меняло
		-- Protected) наоборот застревал. Вместо тихого return дожидаемся
		-- Head сами и пересчитываем состояние заново, как только он появится.
		task.spawn(function()
			local waitedHead = character:WaitForChild("Head", 5)
			if waitedHead and character.Parent and player.Character == character then
				refreshCharacterProtectionHighlight(player)
			end
		end)
		return
	end

	local shieldVfxFactory = useVip and PlaceholderFactory.ShieldVfxVIP or PlaceholderFactory.ShieldVfx
	local shieldVfxAsset, shieldVfxAnchor = shieldVfxFactory()
	-- КРИТИЧНО: если этот кусок останется Anchored=true (дефолт у
	-- плейсхолдер-деталей, см. newPart в PlaceholderFactory — и то же
	-- самое возможно, если билдер забудет снять галку на своём кастомном
	-- ассете) — WeldConstraint к заанкоренной части СТОПОРИТ всю сборку,
	-- к которой приварена, то есть буквально замораживает персонажа на
	-- месте. Снимаем принудительно, независимо от того, что было в ассете.
	shieldVfxAnchor.Anchored = false
	shieldVfxAnchor.Massless = true
	shieldVfxAnchor.CFrame = head.CFrame * CFrame.new(0, Config.Protection.VfxHeight, 0)
	if shieldVfxAsset:IsA("Model") then
		shieldVfxAsset.PrimaryPart = shieldVfxAnchor
	end
	shieldVfxAsset.Name = "ProtectionShieldVfx"
	shieldVfxAsset:SetAttribute("IsVip", useVip)
	shieldVfxAsset.Parent = character

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = shieldVfxAnchor
	weld.Parent = shieldVfxAnchor

	-- Все ParticleEmitter внутри VFX-ассета — рекурсивно, не важно, на самой
	-- части они или на вложенном Attachment (см. контракт ShieldVfx).
	local particles = {}
	for _, descendant in shieldVfxAsset:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = false
			table.insert(particles, descendant)
		end
	end
	shieldParticlesByPlayer[player] = particles
end

function refreshCharacterProtectionHighlight(player)
	local character = player.Character
	if not character then
		return
	end
	local protected = player:GetAttribute("Protected") == true
	local useVip = Services.MonetizationService and Services.MonetizationService:HasGoldenShield(player)
	local color = useVip and Config.GamePasses.CartGuard.OutlineColor or Config.Protection.Color

	local highlight = ensureProtectionHighlight(character, color)
	highlight.Enabled = protected

	if not protected then
		local existingVfx = character:FindFirstChild("ProtectionShieldVfx")
		if existingVfx then existingVfx:Destroy() end
		shieldParticlesByPlayer[player] = nil
		return
	end

	ensureProtectionShieldVfx(player, character) -- не пересоздаёт, если уже стоит на этом персонаже
	local particles = shieldParticlesByPlayer[player]
	if particles then
		for _, particle in particles do
			particle.Enabled = protected
		end
	end
end

-- Вызывается MonetizationService сразу после покупки GoldenShield (см.
-- PromptGamePassPurchaseFinished) — старый (зелёный, обычный) VFX уже мог
-- быть построен ДО покупки, поэтому пересобираем его целиком под VIP,
-- вместо того чтобы просто дождаться следующего изменения Protected.
function CombatService:RefreshShieldVisual(player)
	local character = player.Character
	if not character then
		return
	end
	local existingVfx = character:FindFirstChild("ProtectionShieldVfx")
	if existingVfx then
		existingVfx:Destroy()
	end
	shieldParticlesByPlayer[player] = nil
	refreshCharacterProtectionHighlight(player)
end

local function hookCharacterProtectionHighlight(player)
	player:GetAttributeChangedSignal("Protected"):Connect(function()
		refreshCharacterProtectionHighlight(player)
	end)
	player.CharacterAdded:Connect(function()
		shieldParticlesByPlayer[player] = nil -- старый персонаж и его VFX уже уничтожены вместе с ним
		refreshCharacterProtectionHighlight(player)
	end)
	refreshCharacterProtectionHighlight(player)
end

-- Выдаёт/продлевает защиту. Если уже активна — ДОБАВЛЯЕТ время к остатку,
-- а не сбрасывает счётчик заново (иначе платное продление посреди
-- бесплатной защиты обнулило бы уже накопленное время).
local function setProtectionEnd(player, newEnd)
	local now = os.clock()
	protectionEndsAt[player.UserId] = newEnd
	player:SetAttribute("Protected", true)
	-- Unix-время окончания (не os.clock(), он не переносится между клиентом
	-- и сервером) — клиент считает остаток сам, каждую секунду локально,
	-- не дёргая сервер, чтобы нарисовать таймер над головой (см. CustomCartUI).
	player:SetAttribute("ProtectionEndsAtUnix", os.time() + (newEnd - now))

	task.delay(newEnd - now, function()
		-- Снимаем защиту, только если с тех пор её не продлили ЕЩЁ раз —
		-- иначе более раннее task.delay могло бы преждевременно её снять.
		if protectionEndsAt[player.UserId] == newEnd then
			player:SetAttribute("Protected", false)
			protectionEndsAt[player.UserId] = nil
		end
	end)
end

local function grantProtection(player, duration)
	local now = os.clock()
	local currentEnd = protectionEndsAt[player.UserId]
	local newEnd = (currentEnd and currentEnd > now) and (currentEnd + duration) or (now + duration)
	setProtectionEnd(player, newEnd)
	return newEnd
end

-- Публичная обёртка — нужна MonetizationService, чтобы выдавать платное
-- продление (Config.Protection.PaidDuration) из своего ProcessReceipt, не
-- дублируя саму логику "продлить, а не сбросить" (см. grantProtection выше).
function CombatService:GrantProtection(player, duration)
	grantProtection(player, duration)
end

function CombatService:GrantTutorialProtection(player, duration)
	local newEnd = grantProtection(player, duration)
	tutorialProtectionEndsAt[player.UserId] = newEnd
	task.delay(duration, function()
		if tutorialProtectionEndsAt[player.UserId] == newEnd then
			tutorialProtectionEndsAt[player.UserId] = nil
		end
	end)
end

function CombatService:FinishTutorialProtection(player)
	local userId = player.UserId
	local tutorialEnd = tutorialProtectionEndsAt[userId]
	if not tutorialEnd then return end
	tutorialProtectionEndsAt[userId] = nil

	local now = os.clock()
	local currentEnd = protectionEndsAt[userId]
	local extraDuration = math.max(0, (currentEnd or 0) - tutorialEnd)
	if extraDuration > 0 then
		setProtectionEnd(player, now + extraDuration)
	else
		protectionEndsAt[userId] = nil
		player:SetAttribute("Protected", false)
		player:SetAttribute("ProtectionEndsAtUnix", 0)
	end
end

function CombatService:GetProtectionRemaining(player)
	return math.max(0, (protectionEndsAt[player.UserId] or 0) - os.clock())
end

function CombatService:SyncPaidProtection(player, unixEndsAt)
	local remaining = (tonumber(unixEndsAt) or 0) - os.time()
	if remaining <= 0 then
		return
	end
	local target = os.clock() + remaining
	setProtectionEnd(player, math.max(protectionEndsAt[player.UserId] or 0, target))
end

-- Возвращает (granted: bool, duration: number?) — вызывающий код (RemoteEvent
-- ниже) должен сообщить клиенту РЕАЛЬНУЮ выданную длительность, а не всегда
-- Config.Protection.FreeDuration: владелец GoldenShield получает больше.
local function tryFreeProtection(player)
	if Services.MonetizationService and not Services.MonetizationService:IsEntitlementsReady(player) then return false end
	local now = os.clock()
	local last = lastFreeProtection[player.UserId]
	-- v10: Cart Guard — дольше щит и короче откат.
	local guard = Services.MonetizationService and Services.MonetizationService:HasPass(player, "CartGuard")
	local cooldown = guard and (Config.GamePasses.CartGuard.Cooldown or Config.Protection.FreeCooldown) or Config.Protection.FreeCooldown
	if last and now - last < cooldown then
		return false
	end
	lastFreeProtection[player.UserId] = now

	local duration = Config.Protection.FreeDuration
	if guard then
		duration = Config.GamePasses.CartGuard.Duration or duration
	end
	grantProtection(player, duration)
	return true, duration
end

--------------------------------------------------------------------------------
local startSafeZoneReplication -- вперёд-объявлена: определена ниже, после isPositionSafe, а вызывается отсюда

function CombatService:Init(services)
	Services = services
	startSafeZoneReplication()


	-- Зелёная обводка щита на персонаже — для всех игроков сразу и на все
	-- будущие респавны (см. hookCharacterProtectionHighlight выше).
	Players.PlayerAdded:Connect(hookCharacterProtectionHighlight)
	for _, player in Players:GetPlayers() do
		hookCharacterProtectionHighlight(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		shieldParticlesByPlayer[player] = nil
		tutorialProtectionEndsAt[player.UserId] = nil
	end)

	-- Единственное назначение — сказать клиенту "взмах принят, начинай
	-- визуальный отсчёт отката" (клиент сам знает длительность из
	-- Config.PickaxeTiers[тир].Cooldown через атрибут PickaxeTier — сюда
	-- ничего передавать не нужно). Сам взмах/урон по-прежнему полностью
	-- server-authoritative, клиент только рисует UI.
	local remote = Instance.new("RemoteEvent")
	remote.Name = "PickaxeSwungEvent"
	remote.Parent = ReplicatedStorage.Shared
	self._swungRemote = remote
	local damageRemote = Instance.new("RemoteEvent")
	damageRemote.Name = "DamageNumberEvent"
	damageRemote.Parent = ReplicatedStorage.Shared
	self._damageRemote = damageRemote

	-- PvP v2: обратная связь клиенту (комбо, рагдолл, клэш, импульс отлёта).
	local feedbackRemote = Instance.new("RemoteEvent")
	feedbackRemote.Name = "CombatFeedbackEvent"
	feedbackRemote.Parent = ReplicatedStorage.Shared
	self._feedbackRemote = feedbackRemote
	if Config.Stagger and Config.Stagger.Enabled then
		self:_startStaggerLoop()
	end

	-- Бесплатная защита (кнопка на экране) — сервер сам проверяет кулдаун,
	-- клиенту нечего подделывать. Подтверждаем клиенту ТОЛЬКО при реальной
	-- активации (не при отказе из-за кулдауна) — так его визуальный
	-- отсчёт всегда синхронен с настоящим состоянием.
	--
	-- lastFreeAttempt/lastPaidAttempt — защита от спама (см. тот же приём
	-- в UpgradeService.lua).
	local lastFreeAttempt = {}
	local freeProtectionRemote = Instance.new("RemoteEvent")
	freeProtectionRemote.Name = "ActivateFreeProtectionRequest"
	freeProtectionRemote.Parent = ReplicatedStorage.Shared
	freeProtectionRemote.OnServerEvent:Connect(function(player)
		local now = os.clock()
		local last = lastFreeAttempt[player.UserId]
		if last and now - last < 0.5 then
			return
		end
		lastFreeAttempt[player.UserId] = now

		local granted, duration = tryFreeProtection(player)
		if granted then
			Services.QuestService:RecordMetric(player, "UseShield", 1)
			freeProtectionRemote:FireClient(player, duration) -- 60 сек для владельцев GoldenShield, иначе Config.Protection.FreeDuration (30)
			if Services.DataService and Services.NotifyService
				and Services.DataService:MarkHintSeen(player, "FirstShieldUse") then
				Services.NotifyService:Show(player, "The shield protects your cargo. Attacking someone will disable it.", { Icon = "Shield" })
			end
		end
	end)

	-- Платное продление — настоящий Developer Product (Config.Protection.PaidProductId).
	-- Пока не создан (ID = 0) — по-честному предупреждаем в логах и ничего
	-- не делаем, вместо того чтобы падать на попытке промпта с ID=0.
	local lastPaidAttempt = {}
	local paidProtectionRemote = Instance.new("RemoteEvent")
	paidProtectionRemote.Name = "BuyProtectionExtensionRequest"
	paidProtectionRemote.Parent = ReplicatedStorage.Shared
	paidProtectionRemote.OnServerEvent:Connect(function(player)
		local now = os.clock()
		local last = lastPaidAttempt[player.UserId]
		if last and now - last < 0.5 then
			return
		end
		lastPaidAttempt[player.UserId] = now

		if Config.Protection.PaidProductId == 0 then
			warn("[CombatService] Config.Protection.PaidProductId не задан — создай Developer Product в Creator Dashboard (см. README) и впиши сюда его ID")
			return
		end
		MarketplaceService:PromptProductPurchase(player, Config.Protection.PaidProductId)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastFreeAttempt[player.UserId] = nil
		lastPaidAttempt[player.UserId] = nil
	end)

	-- ВАЖНО: обработка самой покупки (MarketplaceService.ProcessReceipt)
	-- переехала в MonetizationService — он ЕДИНСТВЕННЫЙ на всю игру и
	-- дёргает CombatService:GrantProtection выше. Здесь остаётся только
	-- показ промпта покупки (см. paidProtectionRemote выше).
end

--------------------------------------------------------------------------------
-- Валидация цели на сервере: реальное попадание в прямоугольный хитбокс
-- перед атакующим (см. Config.Combat.HitboxSize/HitboxForwardOffset — та же
-- геометрия, что рисует debugDrawHitbox), а не дистанция+сектор — проверяется
-- и до тела игрока, И до его тележки (если несёт, см. ниже), чем бы из двух
-- атакующий ни целился, ближайшая — та и засчитывается. Возвращает
-- дескриптор { Player, Character, Hrp, Humanoid } — обёртка нужна ApplyHit
-- ниже, единой точке применения урона.
--------------------------------------------------------------------------------

-- Ближайшая к точке `toward` точка на поверхности/внутри ориентированного
-- бокса (boxCFrame/boxSize) — так удар засчитывается по любому краю
-- тележки, а не только точно по центру одной её части.
local function closestPointOnBox(boxCFrame, boxSize, toward)
	local local_ = boxCFrame:PointToObjectSpace(toward)
	local half = boxSize / 2
	local clamped = Vector3.new(
		math.clamp(local_.X, -half.X, half.X),
		math.clamp(local_.Y, -half.Y, half.Y),
		math.clamp(local_.Z, -half.Z, half.Z)
	)
	return boxCFrame:PointToWorldSpace(clamped)
end

-- true, если `point` реально лежит ВНУТРИ ориентированного бокса (не просто
-- ближайшая точка — точный containment-тест), с запасом по высоте
-- (extraYPadding) — плоские Part-зоны (PlotPad, SellZone) иначе накрывали
-- бы только совсем узкий слой прямо на уровне пола.
local function isPointInBox(boxCFrame, boxSize, point, extraYPadding)
	local local_ = boxCFrame:PointToObjectSpace(point)
	local half = boxSize / 2
	return math.abs(local_.X) <= half.X
		and math.abs(local_.Y) <= half.Y + (extraYPadding or 0)
		and math.abs(local_.Z) <= half.Z
end

--------------------------------------------------------------------------------
-- БЕЗОПАСНЫЕ ЗОНЫ: своя база (PlotPad целиком) и зона сдачи руды в банке
-- (SellZone) — НЕ PvP-зона. Позиционная проверка, без привязки к владельцу
-- (см. Config.Combat.SafeZoneYPadding) — используется В findVictim ниже,
-- отдельно для позиции тела И позиции тележки жертвы.
--------------------------------------------------------------------------------
local function isPositionSafe(position)
	local padding = Config.Combat.SafeZoneYPadding

	local sellZone = Services.WorldService and Services.WorldService:GetSellZone()
	if sellZone and isPointInBox(sellZone.CFrame, sellZone.Size, position, padding) then
		return true
	end

	-- v20.34: сейф-зона участка — весь столб над ним (GroundCheck.InPlot):
	-- любая высота над любой частью PlotTemplate, а не только пол.
	if Services.PlotService then
		for _, plot in Services.PlotService:GetAllPlots() do
			if plot.Pad and GroundCheck.InPlot(plot.Pad, position, 0) then
				return true
			end
		end
	end

	return false
end

-- РЕПЛИКАЦИЯ "Я В СЕЙВ-ЗОНЕ" — для панели баффов (см.
-- client/BuffBar.client.lua). isPositionSafe выше уже умеет отвечать на
-- этот вопрос для сервера (используется в findVictim), но клиент об этом
-- не знал вообще: атрибут никогда не выставлялся. Здесь та же проверка
-- переиспользуется, а не дублируется отдельной геометрией где-то ещё, и
-- пишется в атрибут игрока — SetAttribute сам решает, реплицировать
-- изменение или нет, поэтому лишнего трафика при "ничего не изменилось"
-- не будет.
--------------------------------------------------------------------------------
startSafeZoneReplication = function()
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				local safe = root and isPositionSafe(root.Position) or false
				if player:GetAttribute("InSafeZone") ~= safe then
					player:SetAttribute("InSafeZone", safe)
				end
			end
		end
	end)
end

local function pingAdjustedHitboxSize(attacker)
	local ping = 0
	pcall(function()
		ping = attacker:GetNetworkPing()
	end)
	local ratio = math.clamp(ping, 0, Config.Combat.MaxPingCompensation) / Config.Combat.MaxPingCompensation
	local padding = ratio * Config.Combat.MaxPingHitboxPadding
	return Config.Combat.HitboxSize + Vector3.new(padding * 2, 0, padding * 2)
end

local function findVictim(attacker, hitboxSize)
	local character = attacker.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end

	local half = hitboxSize / 2
	local centerZ = -Config.Combat.HitboxForwardOffset -- "вперёд" в локальных координатах CFrame — отрицательный Z

	local best, bestDistance = nil, math.huge

	local function consider(targetPosition, candidateHumanoid, descriptor, isCart, isIdleCart, ignoreSafeZone)
		if not targetPosition then
			return
		end
		if not isIdleCart and (not candidateHumanoid or candidateHumanoid.Health <= 0) then
			return -- у брошенной тележки нет Humanoid'а — этот гейт только для игроков/держателей
		end
		if not ignoreSafeZone and isPositionSafe(targetPosition) then
			return -- своя база ИЛИ зона банка — не PvP-зона, см. Config.Combat.SafeZoneYPadding
		end
		local local_ = hrp.CFrame:PointToObjectSpace(targetPosition)
		local withinBox = math.abs(local_.X) <= half.X
			and math.abs(local_.Y) <= half.Y
			and local_.Z >= (centerZ - half.Z)
			and local_.Z <= (centerZ + half.Z)
		if not withinBox then
			return
		end
		local distance = (targetPosition - hrp.Position).Magnitude
		if distance < bestDistance then
			best, bestDistance = descriptor, distance
			-- Точное место попадания И была ли это именно тележка (не тело) —
			-- нужно ApplyHit ниже для VFX на месте удара и отдельного звука
			-- "удар по тележке" (см. Config.Sounds.PickaxeHitCart).
			descriptor.HitPosition = targetPosition
			descriptor.HitCart = isCart or false
		end
	end

	local goblinVictim = Services.GoblinService and Services.GoblinService:FindInHitbox(
		attacker,
		hrp,
		hitboxSize,
		Config.Combat.HitboxForwardOffset
	)
	if goblinVictim then
		consider(goblinVictim.Hrp.Position, goblinVictim.Humanoid, goblinVictim, false, false, true)
	end

	local rockVictim = Services.RockService and Services.RockService:FindInHitbox(
		attacker,
		hrp,
		hitboxSize,
		Config.Combat.HitboxForwardOffset
	)
	if rockVictim then
		rockVictim.Rock = rockVictim.Rock
		consider(rockVictim.HitPosition, nil, rockVictim, false, true, true)
	end

	for _, other in Players:GetPlayers() do
		if other == attacker or other:GetAttribute("Protected") then
			continue -- защищённого нельзя выбрать целью вообще
		end
		local otherCharacter = other.Character
		local otherHrp = otherCharacter and otherCharacter:FindFirstChild("HumanoidRootPart")
		local otherHumanoid = otherCharacter and otherCharacter:FindFirstChildOfClass("Humanoid")
		local descriptor = { Player = other, Character = otherCharacter, Hrp = otherHrp, Humanoid = otherHumanoid }
		consider(otherHrp and otherHrp.Position, otherHumanoid, descriptor, false)

		-- Тележка держателя тоже волочится позади него (см.
		-- Config.Cart.FollowOffset) и физически торчит дальше, чем сам
		-- игрок — удар, нацеленный именно в неё, а не в тело владельца,
		-- должен засчитываться так же, как удар по нему самому. Если в
		-- модели тележки есть отдельная часть "Hitbox" — используем её
		-- размер целиком (ближайшая точка на её поверхности), иначе как
		-- раньше — только точка в центре Root.
		local cart = Services.CartService and Services.CartService:GetHeldCart(other)
		if cart then
			local hitboxPart = cart.Model:FindFirstChild("Hitbox", true)
			if hitboxPart then
				consider(closestPointOnBox(hitboxPart.CFrame, hitboxPart.Size, hrp.Position), otherHumanoid, descriptor, true)
			else
				consider(cart.Root.Position, otherHumanoid, descriptor, true)
			end
		end
	end

	-- Свободные тележки (никто не держит) — их тоже можно бить, чтобы
	-- выбивать руду, НО только пока они НЕ стоят дома, на базе владельца
	-- (см. CartService:IsAtOwnerBase — своя база всё ещё безопасная зона
	-- для тележки, ровно как и для игрока в isPositionSafe выше).
	if Services.CartService then
		for _, cart in Services.CartService:GetAllCarts() do
			if cart.HolderUserId == nil and not cart.GoblinStolen and not Services.CartService:IsAtOwnerBase(cart) then
				local descriptor = { IdleCart = cart }
				local hitboxPart = cart.Model:FindFirstChild("Hitbox", true)
				if hitboxPart then
					consider(closestPointOnBox(hitboxPart.CFrame, hitboxPart.Size, hrp.Position), nil, descriptor, true, true)
				else
					consider(cart.Root.Position, nil, descriptor, true, true)
				end
			end
		end
	end

	return best
end

--------------------------------------------------------------------------------

function CombatService:SetupPlayer(player)
	-- Взял тележку → кирка исчезает. Оставил → вернулась.
	player:GetAttributeChangedSignal("CarryingCart"):Connect(function()
		if player:GetAttribute("CarryingCart") then
			self:_removeTool(player)
		else
			self:_giveTool(player)
		end
	end)

	player.CharacterAdded:Connect(function()
		-- PvP v2: новый персонаж — чистое состояние шкалы/рагдолла.
		self:_resetStagger(player)
		task.wait(0.2) -- ждём Backpack
		self:RefreshPlayerHealth(player)
		self:_giveTool(player)
	end)
	if player.Character then
		self:RefreshPlayerHealth(player)
		self:_giveTool(player)
	end
	if Services.DataService then
		self:SyncPaidProtection(player, Services.DataService:GetPaidProtectionEndsAt(player))
	end
end

function CombatService:RefreshPlayerHealth(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local previousMax = math.max(1, humanoid.MaxHealth)
	local ratio = math.clamp(humanoid.Health / previousMax, 0, 1)
	local tier = Services.DataService:GetBranchTier(player, "Pickaxe")
	local healthMultiplier = Services.MonetizationService and Services.MonetizationService:GetHealthMultiplier(player) or 1
	local maxHealth = (100 + math.max(0, tier - 1) * 8) * healthMultiplier
	humanoid.MaxHealth = maxHealth
	humanoid.Health = math.clamp(maxHealth * ratio, 0, maxHealth)
end

function CombatService:RefreshPickaxe(player)
	local character = player.Character
	local wasEquipped = character and character:FindFirstChild("Pickaxe") ~= nil
	self:_removeTool(player)
	self:_giveTool(player)
	if wasEquipped and character == player.Character and not player:GetAttribute("CarryingCart") then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local backpack = player:FindFirstChild("Backpack")
		local tool = backpack and backpack:FindFirstChild("Pickaxe")
		if humanoid and tool and tool:IsA("Tool") then humanoid:EquipTool(tool) end
	end
end

function CombatService:RefreshPickaxeSkin(player)
	self:RefreshPickaxe(player)
	return true
end

function CombatService:_removeTool(player)
	stopSwingAnimations(player, toolBlend())
	self:_stopPickaxeIdle(player, toolBlend())
	local function isPickaxeTool(child)
		return child:IsA("Tool") and (child.Name == "Pickaxe" or child.Name:match("^Pickaxe_Tier%d+$") ~= nil)
	end
	local function clear(container)
		if not container then
			return
		end
		for _, child in container:GetChildren() do
			if isPickaxeTool(child) then
				child:Destroy()
			end
		end
	end
	clear(player:FindFirstChild("Backpack"))
	clear(player.Character)
	player:SetAttribute("HasPickaxe", false) -- клиентский хотбар прячет слот
end

function CombatService:_giveTool(player)
	if not player.Parent or player:GetAttribute("CarryingCart") then
		return
	end
	local backpack = player:FindFirstChild("Backpack")
	local character = player.Character
	if not backpack or not character then
		return
	end
	for _, container in { backpack, character } do
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and (child.Name == "Pickaxe" or child.Name:match("^Pickaxe_Tier%d+$")) then
				return
			end
		end
	end

	-- Игрок может сознательно носить не самый высокий из открытых тиров
	-- (см. InventoryService:GetEquippedPickaxeTier) — берём именно его,
	-- иначе переключение тира в инвентаре ничего бы не меняло в руках.
	local tier = Services.DataService:GetTiers(player).Pickaxe
	if Services.InventoryService then
		local okTier, equipped = pcall(Services.InventoryService.GetEquippedPickaxeTier, Services.InventoryService, player)
		if okTier and equipped then tier = equipped end
	end
	local tool = PlaceholderFactory.Pickaxe(tier)
	tool = Services.SkinService:CreatePickaxeTool(player, tool)
	tool.Activated:Connect(function() -- server-side событие Tool
		self:_swing(player, tool)
	end)
	-- Pickaxe idle включается только на месте; walk/jump остаются у Animate.
	-- При любой смене экипировки гасим одноразовые треки предыдущего удара.
	tool.Equipped:Connect(function()
		stopSwingAnimations(player, 0.05)
		task.defer(function() self:_refreshPickaxeIdle(player) end)
	end)
	tool.Unequipped:Connect(function()
		stopSwingAnimations(player, toolBlend())
		self:_stopPickaxeIdle(player, toolBlend())
	end)
	-- Не держим Tool в Character постоянно: стандартный Animate воспринимает
	-- это как вечный tool-action и на удалённых клиентах может выглядеть как
	-- бесконечный замах. Кастомный хотбар сам вызывает Humanoid:EquipTool по
	-- клавише 1/F или клику, несмотря на скрытый стандартный Backpack UI.
	tool.Parent = backpack

	-- Клиентский хотбар (CustomCartUI.client.lua) читает эти атрибуты, чтобы
	-- показать слот кирки и правильно тонировать иконку по тиру — не нужен
	-- отдельный RemoteEvent, атрибуты реплицируются сами.
	player:SetAttribute("PickaxeTier", tier)
	player:SetAttribute("HasPickaxe", true)

	self:_loadSwingAnimations(player, character)
end

-- Две анимации замаха (слева/справа), чередуются при каждом ударе.
function CombatService:_stopPickaxeIdle(player, fadeTime)
	local tracks = animTracks[player.UserId]
	local idle = tracks and tracks.Idle
	if idle and idle.IsPlaying then idle:Stop(fadeTime or toolBlend()) end
end

function CombatService:_refreshPickaxeIdle(player)
	local tracks = animTracks[player.UserId]
	local idle = tracks and tracks.Idle
	if not idle then return end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local state = humanoid and humanoid:GetState()
	local blockedState = state == Enum.HumanoidStateType.Dead
		or state == Enum.HumanoidStateType.Jumping
		or state == Enum.HumanoidStateType.Freefall
		or state == Enum.HumanoidStateType.Climbing
		or state == Enum.HumanoidStateType.Swimming
		or state == Enum.HumanoidStateType.Seated
	local shouldPlay = humanoid ~= nil
		and character:FindFirstChild("Pickaxe") ~= nil
		and humanoid.MoveDirection.Magnitude < 0.05
		and humanoid.FloorMaterial ~= Enum.Material.Air
		and not blockedState
	if shouldPlay then
		if not idle.IsPlaying then idle:Play(toolBlend(), 1, 1) end
	elseif idle.IsPlaying then
		idle:Stop(toolBlend())
	end
end

function CombatService:_loadSwingAnimations(player, character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end

	stopSwingAnimations(player, 0)
	self:_stopPickaxeIdle(player, 0)
	disconnectIdleConnections(player)

	local tracks = {}
	local specs = { Left = Config.Animations.PickaxeSwingLeft, Right = Config.Animations.PickaxeSwingRight }
	for side, id in specs do
		id = animationUri(id)
		if id then
			local animation = Instance.new("Animation")
			animation.AnimationId = id
			local ok, track = pcall(function()
				return animator:LoadAnimation(animation)
			end)
			if ok then
				track.Looped = false -- один раз на удар, не по кругу — не полагаемся на настройку самого ассета
				-- ФИКС АНИМАЦИИ ЗАМАХА НА ХОДУ: без явного Priority трек
				-- использует приоритет, сохранённый в самом ассете (часто
				-- Movement или ниже) — тогда, стоит игроку пойти/побежать
				-- ВО ВРЕМЯ замаха, встроенная Walk-анимация (тоже
				-- Movement) конкурирует за те же кости и замах либо
				-- обрезается, либо визуально "ломается"/дёргается.
				-- Action выше Movement по приоритету — замах гарантированно
				-- перекрывает ходьбу, независимо от того, что настроено в
				-- самом animation-ассете.
				track.Priority = Enum.AnimationPriority.Action2
				tracks[side] = track
			end
		end
	end
	local idleId = animationUri(Config.Animations.PickaxeIdle)
	if idleId then
		local animation = Instance.new("Animation")
		animation.AnimationId = idleId
		local ok, idleTrack = pcall(function() return animator:LoadAnimation(animation) end)
		if ok then
			idleTrack.Looped = true
			idleTrack.Priority = Enum.AnimationPriority.Action
			tracks.Idle = idleTrack
		end
	end
	animTracks[player.UserId] = tracks
	idleConnections[player.UserId] = {
		humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(function() self:_refreshPickaxeIdle(player) end),
		humanoid.StateChanged:Connect(function() self:_refreshPickaxeIdle(player) end),
		humanoid:GetPropertyChangedSignal("FloorMaterial"):Connect(function() self:_refreshPickaxeIdle(player) end),
	}
	self:_refreshPickaxeIdle(player)
end

--------------------------------------------------------------------------------

-- Считает случайную, но ГАРАНТИРОВАННО направленную НАРУЖУ (от source)
-- скорость выброса — исключает "приземление обратно внутрь" физически,
-- а не удачей рандома. NoCollisionConstraint с source на время полёта
-- (см. CrystalService:MakeLoose) добивает последний край случаев, когда
-- источник (тележка/жертва) сам ещё движется навстречу вылетающей руде.
local function ejectVelocity()
	local angle = rng:NextNumber(0, math.pi * 2)
	local outSpeed = rng:NextNumber(Config.Combat.KnockoutEjectOutSpeed.Min, Config.Combat.KnockoutEjectOutSpeed.Max)
	local upSpeed = rng:NextNumber(Config.Combat.KnockoutEjectUpSpeed.Min, Config.Combat.KnockoutEjectUpSpeed.Max)
	local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
	return direction * outSpeed + Vector3.new(0, upSpeed, 0)
end

--------------------------------------------------------------------------------
-- Применяет "удар" к цели: урон + условный микро-стан + часть руды ИЗ ТЕЛЕЖКИ И/ИЛИ
-- ИЗ РУК физически выбивается на дорогу. ЕДИНАЯ точка входа для урона по
-- игроку (см. _swing ниже) — бьёт "по игроку И по его грузу одним действием".
--------------------------------------------------------------------------------
-- [Model] = os.clock() последнего успешного выбития руды из ЭТОЙ конкретной
-- брошенной тележки — свой кулдаун, отдельный от lastKnockoutAt (тот привязан
-- к игроку-жертве, тут жертвы вообще нет).
local lastIdleCartKnockoutAt = setmetatable({}, { __mode = "k" })

-- Удар по брошенной (никем не удерживаемой) тележке — см. findVictim выше.
-- Никакого урона/стана/влияния на жертву (её просто нет), только физическое
-- выбитие руды, с тем же процентом/кулдауном, что и у обычного удара по
-- тележке в руках, и тем же потолком Config.Combat.CartKnockoutMaxPerHit.
local function applyIdleCartHit(attacker, cart, hitPosition, knockoutPercent, knockoutMax, vfxColor)
	spawnHitVfx(hitPosition or cart.Root.Position, vfxColor)
	Sfx.play("PickaxeHitCart", cart.Root)

	local now = os.clock()
	local last = lastIdleCartKnockoutAt[cart.Model]
	if last and now - last < Config.Combat.KnockoutCooldown then
		return
	end
	-- CombatHits раньше писалась ВЫШЕ этой проверки, то есть на каждый взмах
	-- по брошенной тележке — без всякого кулдауна и без живой жертвы. При
	-- Cooldown кирки в 1 сек квест "Ready to Fight" (10 попаданий) и
	-- ежедневки закрывались за десять секунд долблением неподвижного объекта.
	-- Теперь метрика идёт под тем же кулдауном, что и само выбивание руды.
	if cart.OwnerUserId ~= attacker.UserId then Services.QuestService:RecordMetric(attacker, "CombatHits", 1) end

	local count = Services.CartService:GetCrystalCount(cart)
	local geodeCount = Services.CartService:GetGeodeCount(cart)
	if count <= 0 and geodeCount <= 0 then
		return
	end
	local knockedOre = 0
	if count > 0 then
		local cappedMax = math.min(knockoutMax, Config.Combat.CartKnockoutMaxPerHit)
		local amount = math.clamp(math.ceil(count * knockoutPercent), Config.Combat.KnockoutMin, cappedMax)
		local removed = Services.CartService:RemoveCrystals(cart, amount)
		knockedOre += #removed
		for _, crystal in removed do
			Services.CrystalService:MakeLoose(crystal, ejectVelocity(), cart.OwnerUserId, cart.Model)
		end
	end
	if knockedOre > 0 and cart.OwnerUserId ~= attacker.UserId then Services.QuestService:RecordMetric(attacker, "OreStolen", knockedOre) end
	for _, geode in Services.CartService:RemoveGeodes(cart, geodeCount > 0 and 1 or 0) do
		Services.CrystalService:MakeLoose(geode, ejectVelocity(), cart.OwnerUserId, cart.Model)
	end
	Sfx.play("CrystalKnockout", cart.Root)
	lastIdleCartKnockoutAt[cart.Model] = now
end

--------------------------------------------------------------------------------
-- PVP v2 — ШКАЛА ОГЛУШЕНИЯ, РАГДОЛЛ, ПАРИРОВАНИЕ, НАГРАДА ЗА ГОЛОВУ, КОМБО
-- (см. Config.Stagger). Удар по игроку заполняет шкалу (атрибут "Stagger"
-- 0..1 на ИГРОКЕ — его читают билборды у всех клиентов). Полная шкала →
-- рагдолл: суставы Motor6D заменяются BallSocketConstraint'ами, PlatformStand,
-- клиент жертвы (он владеет физикой своего персонажа) переводит Humanoid в
-- Physics и получает импульс отлёта. Вылетает ровно Config.Stagger.DropCount
-- руды — самая дорогая (руки → ручной перенос → тележка).
--------------------------------------------------------------------------------

local function staggerFor(player)
	local state = staggerState[player.UserId]
	if not state then
		state = { Value = 0, LastHitAt = 0, ImmuneUntil = 0, Token = 0 }
		staggerState[player.UserId] = state
	end
	return state
end

local function setStagger(player, value)
	local state = staggerFor(player)
	state.Value = math.clamp(value, 0, 1)
	-- Округление до сотых — чтобы не слать атрибут на каждый крошечный шаг спада.
	player:SetAttribute("Stagger", math.floor(state.Value * 20 + 0.5) / 20)
end

local function equippedPickaxeTier(player)
	local tier = Services.DataService:GetTiers(player).Pickaxe
	if Services.InventoryService then
		local ok, equipped = pcall(Services.InventoryService.GetEquippedPickaxeTier, Services.InventoryService, player)
		if ok and equipped then tier = equipped end
	end
	return math.clamp(tier or 1, 1, #Config.PickaxeTiers)
end

local function feedback(player, payload)
	if CombatService._feedbackRemote and player and player.Parent then
		CombatService._feedbackRemote:FireClient(player, payload)
	end
end

local function horizontalDirection(from, to, fallback)
	local delta = (to - from) * Vector3.new(1, 0, 1)
	if delta.Magnitude < 0.1 then
		return fallback
	end
	return delta.Unit
end

-- РАГДОЛЛ ------------------------------------------------------------------
local function enableRagdoll(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local record = {
		Motors = {},
		Created = {},
		Humanoid = humanoid,
		RequiresNeck = humanoid and humanoid.RequiresNeck,
		BreakJoints = humanoid and humanoid.BreakJointsOnDeath,
	}
	if humanoid then
		humanoid.RequiresNeck = false -- иначе отключённый Neck убьёт персонажа
		humanoid.BreakJointsOnDeath = false
		humanoid.PlatformStand = true
	end
	local torso = character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")
	for _, motor in character:GetDescendants() do
		if motor:IsA("Motor6D") and motor.Part0 and motor.Part1
			and motor.Name ~= "RootJoint" and motor.Name ~= "Root"
			-- Только суставы МЕЖДУ частями тела: якорь тележки (CartFollowAnchorMotor,
			-- Part0 = HRP) и всё прочее, прикреплённое к персонажу, не трогаем.
			and motor.Part0.Name ~= "HumanoidRootPart"
			and motor.Part0.Parent == character and motor.Part1.Parent == character
			and not motor:FindFirstAncestorOfClass("Tool")
			and not motor.Part1:FindFirstAncestorOfClass("Tool")
		then
			local a0 = Instance.new("Attachment")
			a0.Name = "RagdollA0"
			a0.CFrame = motor.C0
			a0.Parent = motor.Part0
			local a1 = Instance.new("Attachment")
			a1.Name = "RagdollA1"
			a1.CFrame = motor.C1
			a1.Parent = motor.Part1
			local socket = Instance.new("BallSocketConstraint")
			socket.Name = "RagdollSocket"
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.LimitsEnabled = true
			socket.UpperAngle = (motor.Name == "Neck") and 30 or 70
			socket.TwistLimitsEnabled = true
			socket.TwistLowerAngle = -40
			socket.TwistUpperAngle = 40
			socket.Parent = motor.Part0
			table.insert(record.Created, a0)
			table.insert(record.Created, a1)
			table.insert(record.Created, socket)
			motor.Enabled = false
			table.insert(record.Motors, motor)

			-- Руки/ноги у R6 не сталкиваются с миром — без коллайдера они
			-- проваливаются сквозь пол. Невидимый коллайдер чуть меньше конечности.
			local limb = motor.Part1
			if limb:IsA("BasePart") and limb.Name ~= "Head" and limb ~= torso then
				local collider = Instance.new("Part")
				collider.Name = "RagdollCollider"
				collider.Size = limb.Size * Vector3.new(0.7, 0.8, 0.7)
				collider.Transparency = 1
				collider.CanCollide = true
				collider.CanQuery = false
				collider.CanTouch = false
				collider.Massless = true
				collider.CFrame = limb.CFrame
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = collider
				weld.Part1 = limb
				weld.Parent = collider
				if torso then
					local noCollide = Instance.new("NoCollisionConstraint")
					noCollide.Part0 = collider
					noCollide.Part1 = torso
					noCollide.Parent = collider
				end
				collider.Parent = character
				table.insert(record.Created, collider)
			end
		end
	end
	return record
end

local function disableRagdoll(record)
	if not record then return end
	for _, instance in record.Created do
		pcall(function() instance:Destroy() end)
	end
	for _, motor in record.Motors do
		pcall(function() motor.Enabled = true end)
	end
	local humanoid = record.Humanoid
	if humanoid and humanoid.Parent then
		pcall(function()
			humanoid.PlatformStand = false
			humanoid.RequiresNeck = record.RequiresNeck ~= false
			humanoid.BreakJointsOnDeath = record.BreakJoints ~= false
		end)
	end
end

-- ВЫПАДЕНИЕ ОДНОЙ РУДЫ -----------------------------------------------------
-- Порядок: кусок в руках из хотбара → ручной перенос → тележка. Везде —
-- самая дорогая. Возвращает { Name, Value } или nil (выпадать было нечему).
local function dropOneOre(victimPlayer, victimHrp)
	local origin = victimHrp.Position + Vector3.new(0, 2, 0)

	local heldUid = victimPlayer:GetAttribute("HeldOreUid")
	if heldUid and Services.InventoryService and Services.InventoryService.TakeOneByUid then
		local removed = Services.InventoryService:TakeOneByUid(victimPlayer, heldUid)
		local info = removed and Config.OreByKey[removed.Ore]
		if info then
			local variant = Config.OreVariants[removed.Variant or 1]
			local crystal = removed.Smelted and PlaceholderFactory.OreIngot(info, variant) or PlaceholderFactory.OreCrystal(info, variant)
			crystal:SetAttribute("CrystalOre", removed.Ore)
			crystal:SetAttribute("CrystalVariant", removed.Variant or 1)
			crystal:SetAttribute("Mutations", removed.Mutations)
			crystal:SetAttribute("CrystalValue", removed.Value or 0)
			if removed.Smelted then crystal:SetAttribute("Smelted", true) end
			crystal:PivotTo(CFrame.new(origin))
			Services.CrystalService:MakeLoose(crystal, ejectVelocity(), victimPlayer.UserId, victimPlayer.Character, victimPlayer.UserId)
			return { Name = info.DisplayName, Value = removed.Value or 0 }
		end
	end

	if Services.HandCarryService and Services.HandCarryService.RemoveMostValuable
		and Services.HandCarryService:GetCount(victimPlayer) > 0
	then
		local entry = Services.HandCarryService:RemoveMostValuable(victimPlayer)[1]
		if entry then
			local crystal = PlaceholderFactory.Crystal(entry.Tier)
			crystal:SetAttribute("CrystalTier", entry.Tier)
			crystal:SetAttribute("CrystalValue", entry.Value)
			crystal:SetAttribute("CrystalPoints", entry.Points or 0)
			crystal:PivotTo(CFrame.new(origin))
			Services.CrystalService:MakeLoose(crystal, ejectVelocity(), entry.OwnerUserId or victimPlayer.UserId, victimPlayer.Character, victimPlayer.UserId)
			local tierInfo = Config.MineTiers[math.clamp(tonumber(entry.Tier) or 1, 1, #Config.MineTiers)]
			return { Name = tierInfo and tierInfo.DisplayName or "Ore", Value = entry.Value or 0 }
		end
	end

	local cart = Services.CartService:GetHeldCart(victimPlayer)
	if cart and Services.CartService:GetCrystalCount(cart) > 0 then
		local crystal = Services.CartService:RemoveMostValuable(cart)[1]
		if crystal then
			Services.CrystalService:MakeLoose(crystal, ejectVelocity(), victimPlayer.UserId, cart.Model)
			local ore = Config.OreByKey[crystal:GetAttribute("CrystalOre")]
			return { Name = ore and ore.DisplayName or (crystal:GetAttribute("CrystalName") or "Ore"), Value = crystal:GetAttribute("CrystalValue") or 0 }
		end
	end
	return nil
end

-- НАГРАДА ЗА ГОЛОВУ --------------------------------------------------------
local function computeBounty(player)
	local cfg = Config.Stagger
	if not (cfg.BountyEnabled and Services.CartService) then return 0 end
	local cart = Services.CartService:GetHeldCart(player)
	if not cart or (cart.Capacity or 0) <= 0 then
		bountyClaimed[player.UserId] = nil
		return 0
	end
	local fill = #cart.Crystals / cart.Capacity
	if fill < cfg.BountyMinFill then
		bountyClaimed[player.UserId] = nil -- продал/растерял — награда может объявиться снова
		return 0
	end
	if bountyClaimed[player.UserId] then return 0 end
	local combo = Services.CartService.GetComboMultiplier and Services.CartService:GetComboMultiplier(cart) or 1
	return math.max(0, math.floor((cart.ValueSum or 0) * combo * cfg.BountyShare))
end

-- v10: потери от рагдолла → предложение «вернуть 50%» (MonetizationService).
local function recordLoss(victimPlayer, droppedList)
	local total = 0
	for _, info in droppedList or {} do total += tonumber(info.Value) or 0 end
	if total > 0 and Services.MonetizationService and Services.MonetizationService.RecordLoss then
		pcall(Services.MonetizationService.RecordLoss, Services.MonetizationService, victimPlayer, total)
	end
end

-- v10: ракетная кирка включена (пасс + переключатель R).
-- v10: турбо-кирка — это СКИН (Config.RocketPickaxe.SkinId). Атрибут
-- RocketMode ставит SkinService при надевании/снятии.
local function rocketActive(player)
	return player:GetAttribute("RocketMode") == true
		and Services.MonetizationService ~= nil
		and Services.MonetizationService:HasPass(player, "RocketPickaxe")
end
CombatService.IsRocketActive = function(_, player) return rocketActive(player) end

-- v10: микротранзакция «встать сейчас» — снять рагдолл досрочно.
function CombatService:EndRagdollNow(player)
	if player:GetAttribute("Ragdolled") ~= true then return false end
	local state = staggerFor(player)
	state.Token += 1 -- отменяет отложенные снятия
	state.ImmuneUntil = os.clock() + (Config.Stagger.ImmunitySeconds or 3)
	local record = ragdollRecords[player.UserId]
	disableRagdoll(record)
	ragdollRecords[player.UserId] = nil
	player:SetAttribute("Ragdolled", false)
	task.delay(Config.Stagger.ImmunitySeconds or 3, function()
		if player.Parent then player:SetAttribute("StaggerImmune", false) end
	end)
	return true
end

function CombatService:_ragdoll(attacker, victimPlayer, victimHrp, attackerHrp, override)
	local cfg = Config.Stagger
	if type(override) == "table" then
		-- v10: ракетный удар — свои отброс/время/выпадение поверх Config.Stagger.
		cfg = setmetatable(override, { __index = Config.Stagger })
	end
	local character = victimPlayer.Character
	local state = staggerFor(victimPlayer)
	state.Token += 1
	local token = state.Token
	local now = os.clock()
	state.ImmuneUntil = now + cfg.RagdollSeconds + cfg.ImmunitySeconds
	setStagger(victimPlayer, 0)

	victimPlayer:SetAttribute("Ragdolled", true)
	victimPlayer:SetAttribute("StaggerImmune", true)
	local record = nil
	if character then
		local ok, result = pcall(enableRagdoll, character)
		if ok then
			record = result
		else
			warn("[CombatService] рагдолл не включился:", result)
		end
	end
	ragdollRecords[victimPlayer.UserId] = record

	local direction = horizontalDirection(attackerHrp.Position, victimHrp.Position, -victimHrp.CFrame.LookVector)
	local impulse = direction * cfg.KnockbackSpeed + Vector3.new(0, cfg.KnockbackUp, 0)

	local dropped = {}
	for _ = 1, math.max(0, cfg.DropCount or 1) do
		local ok, info = pcall(dropOneOre, victimPlayer, victimHrp)
		if ok and info then
			table.insert(dropped, info)
		elseif not ok then
			warn("[CombatService] выпадение руды упало:", info)
		end
	end
	-- Квест «DIE 3 TIMES» теперь засчитывает и рагдоллы (смертей в PvP больше нет).
	Services.QuestService:RecordMetric(victimPlayer, "Deaths", 1)
	recordLoss(victimPlayer, dropped)
	if #dropped > 0 then
		Sfx.play("CrystalKnockout", victimHrp)
		Services.QuestService:RecordMetric(attacker, "OreStolen", #dropped)
	end

	local bountyPaid = 0
	local bounty = tonumber(victimPlayer:GetAttribute("Bounty")) or 0
	if bounty > 0 and not bountyClaimed[victimPlayer.UserId] then
		bountyClaimed[victimPlayer.UserId] = true
		victimPlayer:SetAttribute("Bounty", 0)
		bountyPaid = bounty
		Services.DataService:AddMoney(attacker, bounty, victimHrp.Position)
	end

	local combo = comboState[attacker.UserId]
	feedback(victimPlayer, {
		Kind = "Knocked",
		Impulse = impulse,
		Seconds = cfg.RagdollSeconds,
		By = attacker.DisplayName,
		Ore = dropped[1] and dropped[1].Name or nil,
	})
	feedback(attacker, {
		Kind = "Knockdown",
		Combo = combo and combo.Count or 1,
		Victim = victimPlayer.DisplayName,
		Ore = dropped[1] and dropped[1].Name or nil,
		OreValue = dropped[1] and dropped[1].Value or 0,
		Bounty = bountyPaid,
	})
	if bountyPaid > 0 and Services.NotifyService then
		Services.NotifyService:Show(victimPlayer, ("%s claimed the bounty on your head!"):format(attacker.DisplayName), { Icon = "Money", Duration = 3 })
	end

	task.delay(cfg.RagdollSeconds, function()
		if state.Token ~= token then return end
		disableRagdoll(record)
		if ragdollRecords[victimPlayer.UserId] == record then
			ragdollRecords[victimPlayer.UserId] = nil
		end
		if victimPlayer.Parent then
			victimPlayer:SetAttribute("Ragdolled", false)
		end
	end)
	task.delay(cfg.RagdollSeconds + cfg.ImmunitySeconds, function()
		if state.Token ~= token then return end
		if victimPlayer.Parent then
			victimPlayer:SetAttribute("StaggerImmune", false)
		end
	end)
end

function CombatService:_clash(attacker, victimPlayer, attackerHrp, victimHrp)
	local cfg = Config.Stagger
	local now = os.clock()
	-- Очко, которое соперник успел набить в этом же обмене, возвращаем.
	local attackerState = staggerFor(attacker)
	if attackerState.LastAttackerId == victimPlayer.UserId and now - (attackerState.LastAttackerAt or 0) <= cfg.ClashWindow then
		setStagger(attacker, attackerState.Value - (attackerState.LastGain or 0))
	end
	-- Один и тот же встречный замах не даёт второго клэша (кулдаун замаха
	-- lastSwing при этом НЕ трогаем — иначе парирование сбрасывало бы откат).
	clashedAt[victimPlayer.UserId] = now
	clashedAt[attacker.UserId] = now

	local toVictim = horizontalDirection(attackerHrp.Position, victimHrp.Position, attackerHrp.CFrame.LookVector)
	local up = Vector3.new(0, cfg.ClashKnockUp, 0)
	feedback(attacker, { Kind = "Clash", Impulse = -toVictim * cfg.ClashKnockback + up, Other = victimPlayer.DisplayName })
	feedback(victimPlayer, { Kind = "Clash", Impulse = toVictim * cfg.ClashKnockback + up, Other = attacker.DisplayName })
	local midpoint = (attackerHrp.Position + victimHrp.Position) / 2 + Vector3.new(0, 1.5, 0)
	spawnHitVfx(midpoint, Color3.fromRGB(255, 240, 150))
	Sfx.play("PickaxeHit", attackerHrp)
	comboState[attacker.UserId] = nil
	comboState[victimPlayer.UserId] = nil
end

-- Один удар киркой по игроку в режиме PvP v2.
function CombatService:_staggerHit(attacker, victim)
	local cfg = Config.Stagger
	local victimPlayer = victim.Player
	local victimHrp = victim.Hrp
	local attackerHrp = attacker.Character and attacker.Character:FindFirstChild("HumanoidRootPart")
	if not (victimPlayer and victimHrp and attackerHrp) then return end
	local now = os.clock()

	-- ПАРИРОВАНИЕ: жертва сама замахнулась на атакующего в пределах окна.
	local victimSwing = lastSwing[victimPlayer.UserId]
	if victimSwing and now - victimSwing <= cfg.ClashWindow
		and (clashedAt[victimPlayer.UserId] or 0) < victimSwing
		and not victimPlayer:GetAttribute("CarryingCart")
		and victimPlayer:GetAttribute("Ragdolled") ~= true
	then
		local toAttacker = horizontalDirection(victimHrp.Position, attackerHrp.Position, nil)
		if toAttacker and victimHrp.CFrame.LookVector:Dot(toAttacker) >= cfg.ClashFacingDot then
			self:_clash(attacker, victimPlayer, attackerHrp, victimHrp)
			return
		end
	end

	local state = staggerFor(victimPlayer)
	if victimPlayer:GetAttribute("Ragdolled") == true or now < (state.ImmuneUntil or 0) then
		feedback(attacker, { Kind = "Immune" })
		return
	end

	-- v10: 🚀 РАКЕТНАЯ КИРКА — готовый удар сразу валит и далеко отбрасывает.
	if rocketActive(attacker) then
		local readyAt = tonumber(attacker:GetAttribute("RocketReadyAt")) or 0
		if workspace:GetServerTimeNow() >= readyAt then
			local rocket = Config.RocketPickaxe
			attacker:SetAttribute("RocketReadyAt", workspace:GetServerTimeNow() + (rocket.Cooldown or 18))
			self:_ragdoll(attacker, victimPlayer, victimHrp, attackerHrp, {
				KnockbackSpeed = rocket.KnockbackSpeed,
				KnockbackUp = rocket.KnockbackUp,
				RagdollSeconds = rocket.RagdollSeconds,
				DropCount = rocket.DropCount,
			})
			return
		end
	end

	-- Комбо атакующего (визуал).
	local combo = comboState[attacker.UserId]
	if combo and now - combo.LastAt <= cfg.ComboWindow then
		combo.Count += 1
	else
		combo = { Count = 1 }
		comboState[attacker.UserId] = combo
	end
	combo.LastAt = now

	local tier = equippedPickaxeTier(attacker)
	local hits = cfg.HitsByPickaxeTier[tier] or cfg.HitsByPickaxeTier[#cfg.HitsByPickaxeTier] or 3
	local gain = 1 / math.max(1, hits)
	local monetization = Services.MonetizationService
	if monetization then
		if (monetization:GetDamageMultiplier(attacker) or 1) > 1 then
			gain *= cfg.DoubleDamageProgressMultiplier
		end
		if (monetization:GetHealthMultiplier(victimPlayer) or 1) > 1 then
			gain *= cfg.DoubleHealthProgressMultiplier
		end
	end
	-- v8: скины — Stagger у атакующего, Toughness у жертвы.
	if Services.PrestigeService then
		gain *= math.max(0.2, 1 + Services.PrestigeService:Stat(attacker, "Stagger"))
		gain *= math.max(0.2, 1 - Services.PrestigeService:Stat(victimPlayer, "Toughness"))
	end
	state.LastHitAt = now
	state.LastAttackerId = attacker.UserId
	state.LastAttackerAt = now
	-- Подсказка "по тебе ударили" (Config.Tutorial.Hints.FirstPvpHit).
	if Services.TutorialService then
		pcall(function() Services.TutorialService:ShowHint(victimPlayer, "FirstPvpHit") end)
	end
	state.LastGain = gain
	-- 0.999 — защита от накопленной погрешности float (4 × 0.25 должно добивать).
	local newValue = state.Value + gain
	if newValue >= 0.999 then
		self:_ragdoll(attacker, victimPlayer, victimHrp, attackerHrp)
		return
	end
	setStagger(victimPlayer, newValue)
	feedback(attacker, { Kind = "Hit", Combo = combo.Count, Stagger = newValue })
end

-- Новый персонаж — чистое состояние шкалы/рагдолла.
function CombatService:_resetStagger(player)
	local state = staggerState[player.UserId]
	if state then
		state.Token += 1
		state.ImmuneUntil = 0
	end
	ragdollRecords[player.UserId] = nil
	setStagger(player, 0)
	player:SetAttribute("Ragdolled", false)
	player:SetAttribute("StaggerImmune", false)
end

-- Спад шкалы и пересчёт награды — один фоновый цикл на весь сервер.
function CombatService:_startStaggerLoop()
	local cfg = Config.Stagger
	local sinceBounty = 0
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for userId, state in staggerState do
			if state.Value > 0 and now - state.LastHitAt >= cfg.DecayDelay then
				local player = Players:GetPlayerByUserId(userId)
				if player then
					setStagger(player, state.Value - cfg.DecayPerSecond * dt)
				else
					staggerState[userId] = nil
				end
			end
		end
		sinceBounty += dt
		if sinceBounty >= (cfg.BountyRefresh or 1) then
			sinceBounty = 0
			for _, player in Players:GetPlayers() do
				local ok, bounty = pcall(computeBounty, player)
				bounty = ok and bounty or 0
				if (player:GetAttribute("Bounty") or 0) ~= bounty then
					player:SetAttribute("Bounty", bounty)
				end
			end
		end
	end)
end

function CombatService:ApplyHit(attacker, victim, damage, knockoutPercent, knockoutMax, vfxColor)
	if victim.Rock then
		-- v8: мини-игра валунов — первый удар открывает её (RockService).
		if Config.BoulderGame and Config.BoulderGame.Enabled and Services.RockService.OnPickaxeHit then
			Services.RockService:OnPickaxeHit(victim.Rock, attacker)
			spawnHitVfx(victim.SurfacePosition or victim.HitPosition or victim.Rock.Model:GetPivot().Position, vfxColor)
			Sfx.play("PickaxeHit", victim.Rock.Model)
			return
		end
		local dealt = Services.RockService:Damage(victim.Rock, attacker, damage)
		-- SurfacePosition — точка на поверхности камня со стороны бьющего
		-- (см. RockService:FindInHitbox). HitPosition для валуна — это его
		-- ЦЕНТР, он нужен для попадания в хитбокс, но вспышка и цифра урона,
		-- рождённые в центре, оказывались внутри геометрии и были не видны.
		local visualPosition = victim.SurfacePosition or victim.HitPosition or victim.Rock.Model:GetPivot().Position
		-- v19: цифру урона по валуну рисует client/BoulderHitFX (RockService шлёт BoulderHitFx).
		local _ = dealt
		spawnHitVfx(visualPosition, vfxColor)
		Sfx.play("PickaxeHit", victim.Rock.Model)
		return
	end
	if victim.Goblin then
		local dealt = Services.GoblinService:Damage(victim.Goblin, damage, attacker)
		if dealt and dealt > 0 then self._damageRemote:FireClient(attacker, victim.Hrp, dealt, victim.HitPosition) end
		spawnHitVfx(victim.HitPosition or victim.Hrp.Position, vfxColor)
		Sfx.play("PickaxeHit", victim.Hrp)
		return
	end
	if victim.IdleCart then
		applyIdleCartHit(attacker, victim.IdleCart, victim.HitPosition, knockoutPercent, knockoutMax, vfxColor)
		return
	end

	local victimHrp = victim.Hrp
	local humanoid = victim.Humanoid
	if not humanoid or not victimHrp or humanoid.Health <= 0 then
		return
	end

	-- PVP v2 (Config.Stagger): удар по игроку заполняет шкалу оглушения.
	if Config.Stagger and Config.Stagger.Enabled and victim.Player then
		spawnHitVfx(victim.HitPosition or victimHrp.Position, vfxColor)
		Sfx.play(victim.HitCart and "PickaxeHitCart" or "PickaxeHit", victimHrp)
		Services.QuestService:RecordMetric(attacker, "CombatHits", 1)
		-- Квесты «DEAL N DAMAGE» считают урон кирки за удар, хотя HP больше не снимается.
		Services.QuestService:RecordMetric(attacker, "Damage", math.floor(damage + 0.5))
		if Services.HandCarryService then
			Services.HandCarryService:ReturnStolenToOwner(victim.Player, attacker, Config.HandCarry.ReturnToOwnerPerHit)
		end
		local ok, err = pcall(self._staggerHit, self, attacker, victim)
		if not ok then warn("[CombatService] stagger hit failed:", err) end
		if not Config.Stagger.PlayerHitsDealDamage then
			return
		end
	end
	local healthBeforeHit = humanoid.Health
	humanoid:TakeDamage(damage)
	local dealt = math.min(damage, healthBeforeHit)
	if dealt > 0 then self._damageRemote:FireClient(attacker, victimHrp, dealt, victim.HitPosition or victimHrp.Position) end
	spawnHitVfx(victim.HitPosition or victimHrp.Position, vfxColor) -- см. findVictim/consider — точная точка попадания, тело или тележка
	Sfx.play(victim.HitCart and "PickaxeHitCart" or "PickaxeHit", victimHrp)

	if not victim.Player then
		return -- страховка на случай будущих неигровых целей — сейчас findVictim их не возвращает
	end
	Services.QuestService:RecordMetric(attacker, "CombatHits", 1)
	Services.QuestService:RecordMetric(attacker, "Damage", dealt)

	-- Микро-стан от попадания отключён: удар сохраняет урон, выбивание груза
	-- и визуальные эффекты, но больше не обнуляет скорость игрока.
	if Services.HandCarryService then
		Services.HandCarryService:ReturnStolenToOwner(
			victim.Player,
			attacker,
			Config.HandCarry.ReturnToOwnerPerHit
		)
	end

	-- ХП тележки — от её тира (Config.CartTiers.MaxHealth), тот же урон
	-- прилетает и по ней (см. CartService:DamageCart). Если он её "добивает" —
	-- она сама открепляется и высыпает весь груз, дальнейший процентный
	-- knockout ниже просто не найдёт что выбивать (RemoveCrystals с уже
	-- пустой тележки — no-op).
	local cart = Services.CartService:GetHeldCart(victim.Player)
	if cart then
		local dealt, droppedOre = Services.CartService:DamageCart(cart, damage)
		Services.DataService:AddCartDamage(attacker, dealt)
		if droppedOre > 0 then Services.QuestService:RecordMetric(attacker, "OreStolen", droppedOre) end
	end

	-- РЕАЛЬНЫЙ CATCH-UP: физическое выбитие руды (и из тележки, И из рук)
	-- ограничено ОБЩИМ кулдауном на жертву (Config.Combat.KnockoutCooldown),
	-- НЕ зависящим от тира кирки атакующего — см. комментарий в Config.
	-- HP-урон + урон по тележке применяются ВСЕГДА, микро-стан исключён для
	-- игрока с кристаллом в руках; этот
	-- гейт трогает только физическое выбитие груза.
	local now = os.clock()
	local last = lastKnockoutAt[victim.Player.UserId]
	local canKnockout = not last or (now - last) >= Config.Combat.KnockoutCooldown
	local knockedSomething = false

	-- Часть кристаллов физически вылетает ИЗ ТЕЛЕЖКИ жертвы на дорогу —
	-- гарантированно наружу (см. ejectVelocity), с временным отключением
	-- коллизии с самой тележкой, чтобы не застревать в её геометрии.
	if canKnockout and cart then
		local count = Services.CartService:GetCrystalCount(cart)
		if count > 0 then
			-- См. Config.Combat.CartKnockoutMaxPerHit — не больше 5 руды из
			-- тележки за один тычок, даже если тир кирки формально
			-- разрешает больше (knockoutMax).
			local cappedMax = math.min(knockoutMax, Config.Combat.CartKnockoutMaxPerHit)
			local amount = math.clamp(math.ceil(count * knockoutPercent), Config.Combat.KnockoutMin, cappedMax)
			local removed = Services.CartService:RemoveCrystals(cart, amount)
			for _, crystal in removed do
				Services.CrystalService:MakeLoose(crystal, ejectVelocity(), victim.Player.UserId, cart.Model)
			end
			if #removed > 0 then Services.QuestService:RecordMetric(attacker, "OreStolen", #removed) end
			Sfx.play("CrystalKnockout", victimHrp)
			knockedSomething = true
		end
		local geodeCount = Services.CartService:GetGeodeCount(cart)
		if geodeCount > 0 then
			for _, geode in Services.CartService:RemoveGeodes(cart, 1) do
				Services.CrystalService:MakeLoose(geode, ejectVelocity(), victim.Player.UserId, cart.Model)
			end
			Sfx.play("CrystalKnockout", victimHrp)
			knockedSomething = true
		end
	end

	-- То же самое для руды В РУКАХ (см. HandCarryService) — та же формула
	-- %/максимума, тот же гарантированно-наружный вылет, тот же временный
	-- no-collide, только источник — сам игрок, а не тележка.
	if canKnockout and Services.HandCarryService and Services.HandCarryService:GetCount(victim.Player) > 0 then
		local handCount = Services.HandCarryService:GetCount(victim.Player)
		local handAmount = math.clamp(math.ceil(handCount * knockoutPercent), Config.Combat.KnockoutMin, knockoutMax)
		local removed = Services.HandCarryService:RemoveForKnockout(victim.Player, handAmount)
		if #removed > 0 then
			Services.QuestService:RecordMetric(attacker, "OreStolen", #removed)
			for _, entry in removed do
				local crystal = PlaceholderFactory.Crystal(entry.Tier)
				crystal:SetAttribute("CrystalTier", entry.Tier)
				crystal:SetAttribute("CrystalValue", entry.Value)
				crystal:SetAttribute("CrystalPoints", entry.Points or 0)
				crystal:PivotTo(CFrame.new(victimHrp.Position + Vector3.new(0, 1.5, 0)))
				-- ФИКС "ВОР МГНОВЕННО ПОДБИРАЕТ ОБРАТНО ВЫБИТУЮ ИЗ НЕГО РУДУ":
				-- entry.OwnerUserId — это ИЗНАЧАЛЬНЫЙ владелец (у кого
				-- своровали), а не victim.Player — если жертва удара сама
				-- была вором, entry.OwnerUserId ей не равен, и старая
				-- проверка isOwnerPickup в CrystalService её никак не
				-- ловила. Пятый параметр — отдельный лок именно на
				-- victim.Player (кто физически только что нёс и потерял
				-- это ударом), независимо от того, кто "законный" владелец.
				Services.CrystalService:MakeLoose(crystal, ejectVelocity(), entry.OwnerUserId or victim.Player.UserId, victim.Character, victim.Player.UserId)
			end
			Sfx.play("CrystalKnockout", victimHrp)
			knockedSomething = true
		end
	end

	if knockedSomething then
		lastKnockoutAt[victim.Player.UserId] = now -- кулдаун запускается, только если реально что-то выбили
		if Services.DataService and Services.NotifyService
			and Services.DataService:MarkHintSeen(attacker, "SawDroppedOre") then
			Services.NotifyService:Show(attacker, "Pick up dropped ore and sell it at the bank!", { Icon = "Ore" })
		end
	end
end

function CombatService:_swing(player)
	if player:GetAttribute("CarryingCart") then
		return -- с тележкой бить нельзя (страховка)
	end
	if player:GetAttribute("Ragdolled") == true then
		return -- PvP v2: лежащий в рагдолле не бьёт
	end
	if player:GetAttribute("HeldGear") and player:GetAttribute("HeldGear") ~= "" then
		return -- v8: в руке динамит/сундук — киркой не машем
	end
	if Services.RockService and Services.RockService.HasSession and Services.RockService:HasSession(player) then
		return -- v8: идёт мини-игра валуна — удары идут через неё (RockService)
	end

	-- Тир кирки берём у InventoryService: игрок может СОЗНАТЕЛЬНО носить
	-- не самый высокий из открытых тиров (см. InventoryService
	-- :GetEquippedPickaxeTier). Если сервис почему-то недоступен —
	-- откатываемся на прокачанный тир, как было раньше.
	local pickaxeTier = Services.DataService:GetTiers(player).Pickaxe
	if Services.InventoryService then
		local ok, equipped = pcall(Services.InventoryService.GetEquippedPickaxeTier, Services.InventoryService, player)
		if ok and equipped then pickaxeTier = equipped end
	end
	local tierConfig = Config.PickaxeTiers[pickaxeTier]
	local damage = tierConfig.Damage * (Services.MonetizationService and Services.MonetizationService:GetDamageMultiplier(player) or 1)
	-- Мелкий бафф от надетого СКИНА кирки (см. Config.PickaxeSkinBuffs) —
	-- добавка в долях (0.05 = +5%), намеренно маленькая, чтобы скин не
	-- обгонял реальный апгрейд тира.
	if Services.InventoryService then
		local ok, buffs = pcall(Services.InventoryService.GetSkinBuffs, Services.InventoryService, player)
		if ok and buffs and buffs.Damage then
			damage *= (1 + buffs.Damage)
		end
	end

	-- Кулдаун — теперь СВОЙ у каждого тира (см. Config.PickaxeTiers): слабая
	-- кирка бьёт редко, прокачанная — часто. Поэтому тир нужен уже здесь,
	-- до проверки, а не после неё.
	local now = os.clock()
	local last = lastSwing[player.UserId]
	local rocketOn = rocketActive(player)
	if rocketOn then
		damage *= Config.RocketPickaxe.DamageMultiplier or 0.4 -- v10: ракетная кирка слабо копает
	end
	local swingCooldown = tierConfig.Cooldown * (rocketOn and (Config.RocketPickaxe.SwingCooldownMultiplier or 1.35) or 1)
	if last and now - last < swingCooldown then
		return
	end
	lastSwing[player.UserId] = now
	if player:GetAttribute("Protected") then
		-- Only an accepted swing removes protection; rejected cooldown input does not.
		player:SetAttribute("Protected", false)
		protectionEndsAt[player.UserId] = nil
		if Services.DataService then Services.DataService:ClearPaidProtection(player) end
	end
	self._swungRemote:FireClient(player) -- клиент запускает визуальный отсчёт отката на хотбаре

	-- VFX запускается ПОЧТИ сразу, синхронно с самим стартом анимации замаха
	-- (0.05 — та же задержка, с которой ниже стартует track:Play(0.05)).
	-- Было 0.4 сек "чтобы совпасть с визуальным контактом кирки" — расчёт
	-- держался на предположении про ДЛИННУЮ анимацию замаха, но плейсхолдер-
	-- клипы короче, и на них VFX фактически всплывал уже ПОСЛЕ того, как
	-- игрок увидел сам замах — ощущалось как запаздывание эффекта.
	task.delay(0.05, function()
		if player.Parent then
			swingVfx(player, tierConfig.VfxColor)
		end
	end)

	local character = player.Character
	local attackerHrp = character and character:FindFirstChild("HumanoidRootPart")
	local hitboxSize = pingAdjustedHitboxSize(player)
	if attackerHrp then
		debugDrawHitbox(attackerHrp, hitboxSize, tierConfig.VfxColor)
	end

	-- Чередование: левый замах → правый → левый → ...
	local useLeft = swingSide[player.UserId] ~= false
	swingSide[player.UserId] = not useLeft
	local tracks = animTracks[player.UserId]
	local track = tracks and (useLeft and tracks.Left or tracks.Right)
	if track then
		local playbackId = stopSwingAnimations(player, 0.05)
		track.Looped = false
		track:Play(0.05)
		track.TimePosition = 0
		local returnFade = Config.Combat.SwingReturnFadeTime
		local swingSpeed = 0.9
		track:AdjustSpeed(swingSpeed)

		-- Не подгоняем клип под общий duration: у каждой кирки своя натуральная
		-- скорость. Останавливаем только после фактической длины трека.
		local stopAfter = track.Length > 0 and track.Length / swingSpeed or Config.Combat.SwingAnimationDuration / swingSpeed
		task.delay(math.max(0, stopAfter - returnFade), function()
			if swingPlaybackId[player.UserId] == playbackId and track.IsPlaying then
				track:Stop(returnFade)
			end
		end)
	end
	local tool = character and character:FindFirstChild("Pickaxe")
	Sfx.play("PickaxeSwing", (tool and tool:FindFirstChild("Handle")) or character and character:FindFirstChild("HumanoidRootPart"))

	local deadline = os.clock() + Config.Combat.HitboxActiveDuration
	while true do
		local victim = findVictim(player, hitboxSize)
		if victim then
			self:ApplyHit(player, victim, damage, tierConfig.KnockoutPercent, tierConfig.KnockoutMax, tierConfig.VfxColor)
			return
		end
		if os.clock() >= deadline then
			break
		end
		RunService.Heartbeat:Wait()
	end
end

-- v8: только анимация + звук замаха (удары мини-игры валуна и броски
-- динамита — без хитбокса и без кулдауна тула).
function CombatService:PlaySwingVisual(player)
	local character = player.Character
	local useLeft = swingSide[player.UserId] ~= false
	swingSide[player.UserId] = not useLeft
	local tracks = animTracks[player.UserId]
	local track = tracks and (useLeft and tracks.Left or tracks.Right)
	if track then
		local playbackId = stopSwingAnimations(player, 0.05)
		track.Looped = false
		track:Play(0.05)
		track.TimePosition = 0
		track:AdjustSpeed(1.4)
		-- v20: клиент мини-игры замедляет этот взмах (замах, стоп-кадр,
		-- разгон — BoulderGameUI). Раньше сервер гасил трек по таймеру
		-- ОБЫЧНОЙ скорости и обрывал замедленную анимацию посередине.
		-- Теперь трек не зациклен и доигрывает сам; сервер лишь страхует
		-- остановку с большим запасом (на случай зависшего трека).
		local stopAfter = (track.Length > 0 and track.Length / 1.4 or 0.8) + 2
		task.delay(math.max(0, stopAfter - Config.Combat.SwingReturnFadeTime), function()
			if swingPlaybackId[player.UserId] == playbackId and track.IsPlaying then
				track:Stop(Config.Combat.SwingReturnFadeTime)
			end
		end)
	end
	local tool = character and character:FindFirstChild("Pickaxe")
	Sfx.play("PickaxeSwing", (tool and tool:FindFirstChild("Handle")) or character and character:FindFirstChild("HumanoidRootPart"))
end

-- v8: рагдолл от динамита (GearService) — короткий, выбивает 1 руду.
function CombatService:BlastKnock(victimPlayer, center, attacker, options)
	local base = Config.Dynamite
	local stats = type(options) == "table" and type(options.Stats) == "table" and options.Stats or nil
	-- v9: у каждого вида динамита свои отброс, время рагдолла и выбивание руды.
	local cfg = {
		KnockSpeed = stats and stats.KnockSpeed or base.KnockSpeed,
		KnockUp = stats and stats.KnockUp or base.KnockUp,
		RagdollSeconds = stats and stats.RagdollSeconds or base.RagdollSeconds,
		DropCount = stats and stats.DropCount or base.DropCount,
	}
	local selfBlast = type(options) == "table" and options.Self == true
	local character = victimPlayer.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	-- Щит и безопасная зона защищают только от ЧУЖОГО динамита.
	if not selfBlast then
		if victimPlayer:GetAttribute("Protected") then return end
		if isPositionSafe(hrp.Position) then return end
	end
	local direction = horizontalDirection(center, hrp.Position, Vector3.new(0, 0, 1))
	-- v16 (K2): ближе к эпицентру — сильнее отброс и выше подброс.
	local fx = base.Fx or {}
	local radius = type(options) == "table" and tonumber(options.Radius) or nil
	local closeness = 0
	if radius and radius > 0 then
		closeness = math.clamp(1 - (hrp.Position - center).Magnitude / radius, 0, 1)
	end
	local boost = 1 + (fx.EpicenterBonus or 0) * closeness
	local impulse = direction * cfg.KnockSpeed * boost + Vector3.new(0, cfg.KnockUp * boost, 0)
	local state = staggerFor(victimPlayer)
	if victimPlayer:GetAttribute("Ragdolled") == true or os.clock() < (state.ImmuneUntil or 0) then
		feedback(victimPlayer, { Kind = "Clash", Impulse = impulse * 0.6, Other = "" })
		return
	end
	state.Token += 1
	local token = state.Token
	state.ImmuneUntil = os.clock() + cfg.RagdollSeconds + 1.5
	victimPlayer:SetAttribute("Ragdolled", true)
	local record = nil
	local ok, result = pcall(enableRagdoll, character)
	if ok then record = result end
	ragdollRecords[victimPlayer.UserId] = record
	local dropped = nil
	local droppedAll = {}
	for _ = 1, selfBlast and 0 or math.max(0, cfg.DropCount or 1) do
		local okDrop, info = pcall(dropOneOre, victimPlayer, hrp)
		if okDrop and info then
			dropped = dropped or info
			table.insert(droppedAll, info)
		end
	end
	recordLoss(victimPlayer, droppedAll)
	feedback(victimPlayer, {
		Kind = "Knocked", Impulse = impulse, Seconds = cfg.RagdollSeconds,
		By = selfBlast and "your own dynamite" or (attacker and attacker.DisplayName or "Dynamite"),
		Ore = dropped and dropped.Name or nil,
		-- v16 (K2): взрыв — замирание перед отлётом, кувырок, эффект приземления.
		Blast = type(options) == "table" and options.Blast == true or nil,
		HitStop = fx.HitStop, Spin = fx.TumbleSpin, Closeness = closeness,
	})
	task.delay(cfg.RagdollSeconds, function()
		if state.Token ~= token then return end
		disableRagdoll(record)
		if ragdollRecords[victimPlayer.UserId] == record then ragdollRecords[victimPlayer.UserId] = nil end
		if victimPlayer.Parent then victimPlayer:SetAttribute("Ragdolled", false) end
	end)
end

function CombatService:IsPositionSafe(position)
	return isPositionSafe(position)
end

function CombatService:CleanupPlayer(player)
	stopSwingAnimations(player, 0)
	self:_stopPickaxeIdle(player, 0)
	disconnectIdleConnections(player)
	lastSwing[player.UserId] = nil
	swingSide[player.UserId] = nil
	animTracks[player.UserId] = nil
	swingPlaybackId[player.UserId] = nil
	lastFreeProtection[player.UserId] = nil
	protectionEndsAt[player.UserId] = nil
	stunnedUntil[player.UserId] = nil
	lastKnockoutAt[player.UserId] = nil
	staggerState[player.UserId] = nil
	comboState[player.UserId] = nil
	bountyClaimed[player.UserId] = nil
	clashedAt[player.UserId] = nil
	disableRagdoll(ragdollRecords[player.UserId])
	ragdollRecords[player.UserId] = nil
end

return CombatService
