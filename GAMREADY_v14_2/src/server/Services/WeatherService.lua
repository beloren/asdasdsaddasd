--------------------------------------------------------------------------------
-- WeatherService
-- Погодные ивенты (см. Config.WeatherEvents) — раз в RollIntervalSeconds
-- бросает кубик, выбирает следующий ивент (или "чистое небо"), плавно
-- меняет освещение по всему серверу и сообщает клиентам, что показывать
-- (VFX/анонс). CrystalService/RockService спрашивают у него текущие бусты
-- мутаций при каждом броске новой руды (см. GetActiveBoosts/
-- GetForcedMutation) — сам WeatherService ничего не знает про руду,
-- только хранит "что сейчас усилено" и меняет небо/анонс.
--------------------------------------------------------------------------------

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

-- Та же проверка админки, что и у GoblinService (см. его isGoblinAdmin) —
-- не вынесена в общий модуль, чтобы не плодить лишнюю кросс-зависимость
-- между сервисами ради одной маленькой функции.
local weatherAdminCache = {}
local function isWeatherAdmin(player)
	if RunService:IsStudio() or player.UserId == game.CreatorId then return true end
	local configured = Config.Goblins.AdminUserIds
	if configured and configured[player.UserId] then return true end
	if game.CreatorType ~= Enum.CreatorType.Group then return false end
	local cached = weatherAdminCache[player.UserId]
	if cached ~= nil then return cached end
	local ok, rank = pcall(function() return player:GetRankInGroup(game.CreatorId) end)
	if not ok then
		return false -- НЕ кэшируем сбой: следующая попытка переспросит заново
	end
	local isAdmin = (tonumber(rank) or 0) >= 255
	weatherAdminCache[player.UserId] = isAdmin
	return isAdmin
end

local WeatherService = {}

local Services = nil
local weatherRemote = nil

local currentEvent = nil -- запись из Config.WeatherEvents.Events, или nil = чистое небо
local currentEventEndsAt = 0 -- os.time() момента, когда текущий ивент закончится (0 при чистом небе)

-- ФОРВАРД-ДЕКЛАРАЦИЯ (ИСПРАВЛЕНИЕ КРАША ПОКУПКИ ПОГОДЫ ЗА ROBUX).
-- Раньше applyEvent объявлялась как `local function applyEvent` ДАЛЕКО НИЖЕ
-- по файлу (после pickNextEvent/resolveLightingTarget), а
-- WeatherService:PurchaseTriggerEvent вызывал её ВЫШЕ этого объявления.
-- В Lua локальная переменная видна только с точки объявления и ниже,
-- поэтому имя applyEvent внутри PurchaseTriggerEvent резолвилось в
-- ГЛОБАЛЬНОЕ — а глобального такого нет. Итог: "attempt to call a nil
-- value" ровно на строке вызова, ошибка вылетала внутри
-- MarketplaceService.ProcessReceipt (см. MonetizationService), чек НЕ
-- подтверждался, Roblox уходил в бесконечный retry — робуксы списаны,
-- погода не менялась. ForceEvent (админ-панель) стоит НИЖЕ объявления,
-- поэтому у админа всё работало — отсюда и расхождение "у меня работает,
-- за деньги нет". Объявляем имя здесь, а ниже присваиваем в него функцию
-- (`applyEvent = function(...)`), чтобы оба вызова видели один и тот же
-- апвалью.
local applyEvent
local defaultLighting = nil -- снимок ДО первого применения погоды — на него откатываемся при "Clear"
local defaultSky = nil -- снимок ОРИГИНАЛЬНОГО Sky (или nil, если его не было) — на случай отсутствия любых скайбоксов-ассетов
local LIGHTING_TWEEN_SECONDS = 6 -- плавный переход, не мгновенный щелчок освещения

--------------------------------------------------------------------------------
-- СКАЙБОКСЫ ПОД ПОГОДУ (по прямому запросу) — тот же принцип "плейлохолдер
-- или свой ассет", что и PlaceholderFactory.lua/WeatherFX.client.lua:
--   "<EventId>Sky" (например "NightSky", "RainSky", "BloodMoonSky",
--   "ThunderstormSky", "SolarEclipseSky") — Sky-объект в ReplicatedStorage/
--   Assets. Найден — клонируется в Lighting. Не найден — откат на общий
--   "NightSky" (для тёмных ивентов, IsDark=true) или "DaySky" (для
--   светлых) — тоже в ReplicatedStorage/Assets, если они там есть. Нет и
--   их — Sky не трогаем вообще (остаётся то, что было).
--------------------------------------------------------------------------------
local function findSkyAsset(name)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then return nil end
	local found = assets:FindFirstChild(name) or assets:FindFirstChild(name, true)
	if found and found:IsA("Sky") then return found end
	return nil
end

local function applySky(event)
	local skyAsset = event and findSkyAsset(event.Id .. "Sky")
	if not skyAsset and event then
		skyAsset = findSkyAsset(event.IsDark and "NightSky" or "DaySky")
	elseif not skyAsset and not event then
		-- "Clear" (event=nil) — пробуем общий DaySky как разумный дефолт
		-- для чистого неба, прежде чем откатываться на исходный снимок.
		skyAsset = findSkyAsset("DaySky")
	end

	local existingSky = Lighting:FindFirstChildOfClass("Sky")
	if not skyAsset then
		-- Ничего подходящего не нашлось — откатываемся на снимок исходного
		-- Sky (снятый один раз при первом запуске, см. Init), а не молча
		-- оставляем скайбокс от ПРЕДЫДУЩЕГО ивента висеть неправильно.
		if existingSky then existingSky:Destroy() end
		if defaultSky then
			local restored = defaultSky:Clone()
			restored.Parent = Lighting
		end
		return
	end
	if existingSky then existingSky:Destroy() end
	local clone = skyAsset:Clone()
	clone.Parent = Lighting
end

--------------------------------------------------------------------------------
-- v20.26: НЕБО-ГРАДИЕНТ И СВЕТ ПОГОДЫ (Look). Вместо картинок-скайбоксов —
-- Atmosphere (градиент «горизонт → зенит»), свои WeatherColorCorrection и
-- WeatherBloom в Lighting, звёзды/луна/солнце у Sky и (если задано) Clouds.
-- Всё плавно переходит за Config.WeatherEvents.LookTweenSeconds.
--
-- Откуда берётся вид (первое найденное):
--   1) Assets/Weather/<Id>/Look (для ясной погоды — Assets/Weather/Clear/Look):
--      положите туда настроенные в Studio Atmosphere, ColorCorrectionEffect,
--      BloomEffect, Clouds, Sky — берутся их свойства (у Sky с картинками —
--      и картинки скайбокса);
--   2) Config.WeatherEvents.Events[].Look / ClearLook.
-- SunRays погода не трогает.
--------------------------------------------------------------------------------
local LOOK_PROPS = {
	Atmosphere = { Class = "Atmosphere", Props = { "Density", "Offset", "Color", "Decay", "Glare", "Haze" } },
	ColorCorrection = { Class = "ColorCorrectionEffect", Props = { "TintColor", "Saturation", "Contrast", "Brightness" } },
	Bloom = { Class = "BloomEffect", Props = { "Intensity", "Size", "Threshold" } },
	Clouds = { Class = "Clouds", Props = { "Cover", "Density", "Color" } },
	Sky = { Class = "Sky", Props = { "StarCount", "SunAngularSize", "MoonAngularSize", "CelestialBodiesShown" } },
}
local SKY_TEXTURES = { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp", "SunTextureId", "MoonTextureId" }

local function lookTarget(kind, create)
	if kind == "Atmosphere" then
		local found = Lighting:FindFirstChildOfClass("Atmosphere")
		if not found and create then
			found = Instance.new("Atmosphere")
			found.Parent = Lighting
		end
		return found
	elseif kind == "ColorCorrection" or kind == "Bloom" then
		local name = kind == "ColorCorrection" and "WeatherColorCorrection" or "WeatherBloom"
		local found = Lighting:FindFirstChild(name)
		if not found and create then
			found = Instance.new(LOOK_PROPS[kind].Class)
			found.Name = name
			found.Parent = Lighting
		end
		return found
	elseif kind == "Clouds" then
		local terrain = workspace:FindFirstChildOfClass("Terrain")
		local found = terrain and terrain:FindFirstChildOfClass("Clouds")
		if not found and create and terrain then
			found = Instance.new("Clouds")
			found.Parent = terrain
		end
		return found
	elseif kind == "Sky" then
		local found = Lighting:FindFirstChildOfClass("Sky")
		if not found and create then
			found = Instance.new("Sky")
			found.Parent = Lighting
		end
		return found
	end
	return nil
end

-- Вид из Studio: Assets/Weather/<Id>/Look → { Atmosphere = {…}, … }.
local function lookFromAssets(id)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Weather")
	folder = folder and folder:FindFirstChild(id)
	folder = folder and folder:FindFirstChild("Look")
	if not folder then return nil end
	local look = {}
	for kind, spec in LOOK_PROPS do
		local source = folder:FindFirstChildOfClass(spec.Class)
		if source then
			local values = {}
			for _, prop in spec.Props do values[prop] = source[prop] end
			if kind == "Sky" and source.SkyboxBk ~= "" then
				values.Textures = {}
				for _, prop in SKY_TEXTURES do values.Textures[prop] = source[prop] end
			end
			look[kind] = values
		end
	end
	return look
end

local function applyLook(event)
	local cfg = Config.WeatherEvents
	local look = lookFromAssets(event and event.Id or "Clear") or (event and event.Look) or cfg.ClearLook
	if not look then return end
	local info = TweenInfo.new(cfg.LookTweenSeconds or LIGHTING_TWEEN_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	for kind, values in look do
		local spec = LOOK_PROPS[kind]
		local target = spec and lookTarget(kind, true)
		if target then
			local tweened = {}
			for _, prop in spec.Props do
				local value = values[prop]
				if typeof(value) == "boolean" then
					target[prop] = value
				elseif value ~= nil then
					tweened[prop] = value
				end
			end
			if values.Textures then
				for prop, texture in values.Textures do target[prop] = texture end
			end
			if next(tweened) then
				local ok, err = pcall(function() TweenService:Create(target, info, tweened):Play() end)
				if not ok then warn("[WeatherService] Look " .. kind .. ":", err) end
			end
		end
	end
end

local function snapshotLighting()
	return {
		ClockTime = Lighting.ClockTime,
		Brightness = Lighting.Brightness,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		FogColor = Lighting.FogColor,
		FogEnd = Lighting.FogEnd,
	}
end

local function tweenLightingTo(target)
	local tween = TweenService:Create(
		Lighting,
		TweenInfo.new(LIGHTING_TWEEN_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		target
	)
	tween:Play()
end

-- Данные, которые реально нужны клиенту (VFX + текст анонса) — не весь
-- Lighting-пресет, он применяется только на сервере, клиент просто видит
-- результат репликации свойств Lighting сам по себе (Lighting — обычный
-- реплицируемый сервис, отдельно слать его не нужно).
local function publicEventPayload(event)
	if not event then
		-- По прямому запросу — "чтобы слева снизу писалось когда и
		-- солнечная погода": раньше при Clear отправляли буквально nil,
		-- клиент прятал подпись целиком и не знал, сколько ждать до смены.
		-- Теперь шлём таблицу и для Clear тоже — VfxKind отсутствует, это
		-- по-прежнему корректно выключает частицы/молнии на клиенте (там
		-- уже nil-safe: `payload and payload.VfxKind or nil`).
		return { Id = "Clear", DisplayName = "Sunny", EndsAt = currentEventEndsAt, Effects = Config.WeatherEvents.ClearEffects or {} }
	end
	return {
		Id = event.Id,
		DisplayName = event.DisplayName,
		VfxKind = event.VfxKind,
		Effects = event.Effects or {}, -- v20.26: эффекты по карте (client/WeatherFX)
		Lightning = event.Lightning == true,
		AnnounceText = event.AnnounceText,
		EndsAt = currentEventEndsAt,
	}
end

function WeatherService:Init(services)
	Services = services

	weatherRemote = Instance.new("RemoteEvent")
	weatherRemote.Name = "WeatherEvent"
	weatherRemote.Parent = ReplicatedStorage.Shared
	defaultLighting = snapshotLighting()
	local existingSky = Lighting:FindFirstChildOfClass("Sky")
	if existingSky then defaultSky = existingSky:Clone() end
	-- Планируем ПЕРВЫЙ естественный бросок через полный интервал — та же
	-- задержка перед первым роллом, что была раньше (сервер стартует с
	-- чистым небом, не сразу что-то роллит). currentEventEndsAt=0 по
	-- умолчанию означал бы "уже пора роллить" — цикл в Start() ниже
	-- крутится с самого начала, а не после первого task.wait.
	currentEventEndsAt = os.time() + Config.WeatherEvents.RollIntervalSeconds
	-- v20.26: сразу ясное небо-градиент (без ожидания первой смены погоды).
	task.defer(applyLook, nil)

	-- ПРОСТАЯ АДМИН-ПАНЕЛЬ ДЛЯ БЫСТРОГО ТЕСТА (см. WeatherAdminPanel.
	-- client.lua) — по прямому запросу. Права проверяются СЕРВЕРОМ на
	-- каждый вызов (не один раз при показе панели) — клиент никогда не
	-- является источником истины про то, кто админ.
	local adminCheckRemote = Instance.new("RemoteFunction")
	adminCheckRemote.Name = "WeatherAdminCheck"
	adminCheckRemote.Parent = ReplicatedStorage.Shared
	adminCheckRemote.OnServerInvoke = function(player)
		return isWeatherAdmin(player)
	end

	local adminCommandRemote = Instance.new("RemoteEvent")
	adminCommandRemote.Name = "WeatherAdminCommand"
	adminCommandRemote.Parent = ReplicatedStorage.Shared
	adminCommandRemote.OnServerEvent:Connect(function(player, eventId)
		self:ForceEvent(player, eventId)
	end)
end

-- { [mutationId] = множитель } активного ивента, или nil при чистом небе —
-- см. MutationRoll.Roll(luck, weatherBoosts) в CrystalService/RockService.
function WeatherService:GetActiveBoosts()
	return currentEvent and currentEvent.BoostedMutations or nil
end

-- ТОЛЬКО у Solar Eclipse (см. Config.WeatherEvents.SolarEclipse.
-- ForcedMutationChance) — id мутации, которую нужно принудительно
-- добавить к уже брошенному набору (см. MutationRoll.ForceInclude), или
-- nil, если сейчас нет форс-эффекта либо не повезло с шансом.
function WeatherService:GetForcedMutation()
	if not currentEvent or not currentEvent.ForcedMutationChance then return nil end
	if math.random() >= currentEvent.ForcedMutationChance then return nil end
	-- ForcedMutationChance относится к ОДНОЙ конкретной мутации ивента —
	-- сейчас так устроен только Solar Eclipse (единственная запись в
	-- BoostedMutations), next() тут не гадание, а прямое обращение к ней.
	local mutationId = next(currentEvent.BoostedMutations)
	return mutationId
end

-- Покупка платного погодного ивента (см. Config.DevProducts.Weather*/
-- MonetizationService.lua) — та же механика, что и ForceEvent у
-- админ-панели, НО БЕЗ проверки прав: сама покупка за реальные деньги и
-- есть допуск, права админа тут ни при чём.
-- ЗАЩИТА КУПЛЕННОЙ ПОГОДЫ (по прямому запросу — "если куплено, не может
-- переключиться, пока не пройдёт 5 минут", ТОЛЬКО для донатерских
-- ивентов). isPurchaseProtected=true, пока текущий ивент — купленный и
-- ещё не доиграл. Естественный ролл (см. Start ниже) уважает эту защиту
-- полностью. Другая ПОКУПКА во время защиты НЕ перебивает текущую —
-- встаёт в очередь (queuedPurchaseEventId) и применяется САМА, как только
-- защита снимется — деньги никогда не пропадают впустую. Админ-панель
-- (ForceEvent) ЭТУ защиту полностью игнорирует и всегда работает
-- мгновенно — это тестовый инструмент, не платная механика.
local isPurchaseProtected = false
local queuedPurchaseEventId = nil

function WeatherService:PurchaseTriggerEvent(eventId)
	for _, event in Config.WeatherEvents.Events do
		if event.Id == eventId then
			if isPurchaseProtected and os.time() < currentEventEndsAt then
				-- Уже идёт чья-то купленная погода, её время ещё не вышло —
				-- новую покупку СТАВИМ В ОЧЕРЕДЬ, а не перебиваем и не
				-- теряем: сработает сама сразу после текущей.
				queuedPurchaseEventId = eventId
				return true
			end
			applyEvent(event)
			isPurchaseProtected = true
			return true
		end
	end
	return false
end

function WeatherService:GetCurrentEventId()
	return currentEvent and currentEvent.Id or "Clear"
end

-- СТРОГОЕ ЧЕРЕДОВАНИЕ — по прямому запросу: "через 5 минут гарантировано
-- была другая [погода]... а после них гарантировано выпадал опять день".
-- Больше НЕТ шанса на "чистое небо после чистого неба" или "погода после
-- погоды" — ровно Clear → ивент → Clear → ивент... Если последним был
-- Clear (currentEvent == nil, включая самый первый запуск сервера) —
-- ивент выбирается ОБЯЗАТЕЛЬНО, по ОТНОСИТЕЛЬНЫМ весам (Chance каждого
-- события друг к другу — Rain/Night по-прежнему самые вероятные, просто
-- нормализовано так, чтобы в сумме давало 100%, раз "ничего" больше не
-- вариант). Если последним был реальный ивент — гарантированно Clear.
local function pickNextEvent()
	if currentEvent ~= nil then
		return nil -- только что был реальный ивент — теперь гарантированно чистое небо
	end
	local events = Config.WeatherEvents.Events
	local totalWeight = 0
	for _, event in events do
		totalWeight += event.Chance
	end
	if totalWeight <= 0 then
		return nil -- защита от вырожденного конфига (все Chance = 0)
	end
	local roll = math.random() * totalWeight
	local cumulative = 0
	for _, event in events do
		cumulative += event.Chance
		if roll < cumulative then
			return event
		end
	end
	return events[#events] -- защита от погрешности округления на самом хвосте
end

-- Считает реальный Lighting-таргет для ивента. Если у ивента задан
-- DarknessRatio (см. Config.WeatherEvents — сейчас у всех пяти ивентов)
-- — Brightness/Ambient/OutdoorAmbient берутся НЕ из захардкоженных чисел
-- в конфиге, а как доля от РЕАЛЬНОГО дневного освещения этой конкретной
-- карты (defaultLighting, снятый один раз при старте сервера, см. Init).
-- Так "на 20% темнее дня" остаётся верным всегда, а не только если чей-то
-- день случайно оказался именно той яркости, под которую подбирались
-- цифры в конфиге. Цветовой оттенок (Ambient/OutdoorAmbient) сохраняется
-- прежним — просто масштабируется по яркости, не становится нейтральным.
local function scaleColorBrightness(color, ratio)
	return Color3.new(
		math.clamp(color.R * ratio, 0, 1),
		math.clamp(color.G * ratio, 0, 1),
		math.clamp(color.B * ratio, 0, 1)
	)
end

local function resolveLightingTarget(event)
	if not event then return defaultLighting end
	local target = {}
	for key, value in event.Lighting do
		target[key] = value
	end
	if event.DarknessRatio and defaultLighting then
		target.Brightness = defaultLighting.Brightness * event.DarknessRatio
		-- Оттенок события (синий у ночи, красный у кровавой луны) остаётся
		-- ведущим — блендим ЕГО ЖЕ цвет к нужной яркости через дневной
		-- эталон, а не считаем с нуля нейтральным серым.
		local eventAmbient = event.Lighting.Ambient
		local eventOutdoor = event.Lighting.OutdoorAmbient
		if eventAmbient then
			local dayLuma = (defaultLighting.Ambient.R + defaultLighting.Ambient.G + defaultLighting.Ambient.B) / 3
			local eventLuma = (eventAmbient.R + eventAmbient.G + eventAmbient.B) / 3
			local lumaRatio = eventLuma > 0.001 and (math.max(dayLuma, 0.15) * event.DarknessRatio) / eventLuma or event.DarknessRatio
			target.Ambient = scaleColorBrightness(eventAmbient, lumaRatio)
		end
		if eventOutdoor then
			local dayLuma = (defaultLighting.OutdoorAmbient.R + defaultLighting.OutdoorAmbient.G + defaultLighting.OutdoorAmbient.B) / 3
			local eventLuma = (eventOutdoor.R + eventOutdoor.G + eventOutdoor.B) / 3
			local lumaRatio = eventLuma > 0.001 and (math.max(dayLuma, 0.15) * event.DarknessRatio) / eventLuma or event.DarknessRatio
			target.OutdoorAmbient = scaleColorBrightness(eventOutdoor, lumaRatio)
		end
	end
	return target
end

-- ВНИМАНИЕ: НЕ `local function` — имя уже объявлено форвард-декларацией в
-- начале файла (см. подробный комментарий там). Вернуть сюда `local`
-- означает создать ВТОРУЮ переменную с тем же именем и заново сломать
-- покупку погоды за Robux.
applyEvent = function(event)
	currentEvent = event
	-- ИСПРАВЛЕНИЕ РЕАЛЬНОГО БАГА "ставлю Clear — тут же встаёт рандомная
	-- погода": раньше при Clear (event=nil) currentEventEndsAt сбрасывался
	-- в 0. os.time() — это большой положительный unix-таймстамп, поэтому
	-- "0 - os.time()" получался огромным ОТРИЦАТЕЛЬНЫМ числом, и цикл
	-- естественного ролла (см. Start() ниже) читал это как "уже давно пора
	-- перебрасывать" — новый случайный ивент вставал СРАЗУ ЖЕ на
	-- следующем опросе. Теперь Clear защищён тем же полным интервалом, что
	-- и любой настоящий ивент — реально остаётся чистым небом до
	-- следующего планового ролла, а не долю секунды.
	currentEventEndsAt = os.time() + Config.WeatherEvents.RollIntervalSeconds
	tweenLightingTo(resolveLightingTarget(event))
	if Config.WeatherEvents.UseSkyboxAssets then applySky(event) end
	applyLook(event)
	-- nil (Clear) тоже шлём явно — клиент должен погасить VFX/убрать
	-- баннер предыдущего ивента, а не оставить их висеть навсегда.
	local payload = publicEventPayload(event)
	weatherRemote:FireAllClients(payload)
	if event then
		if Services.AnnounceService then
			Services.AnnounceService:Broadcast(nil, nil, { { Text = event.AnnounceText, Color = Color3.new(1, 1, 1) } })
		end
		-- ТОСТ — по прямому запросу вместо/вместе с чатом: анонс погоды
		-- должен быть заметным всплывающим уведомлением, а не строкой,
		-- которую легко пропустить в чате. Duration = 8 (дольше обычных
		-- 3.5-4 сек у большинства тостов) — это целое предложение, не
		-- короткая транзакционная строка, нужно время прочитать.
		if Services.NotifyService then
			for _, player in Players:GetPlayers() do
				Services.NotifyService:Show(player, event.AnnounceText, { Icon = "Quest", Duration = 8 })
			end
		end
	end
end

-- Админ-панель дёргает это напрямую через RemoteEvent (см. Init выше) —
-- права проверяются ЗДЕСЬ, не полагаемся на то, что клиент уже
-- отфильтровал не-админов на своей стороне (UI можно подделать).
function WeatherService:ForceEvent(player, eventId)
	if not isWeatherAdmin(player) then return false end
	-- Админка ВСЕГДА мгновенная — не донатерская механика, защита её не
	-- касается вообще. Очередь купленной погоды НЕ трогаем: если игрок
	-- реально заплатил, его ивент всё равно сработает сам, как только
	-- закончится тестовое окно админа — деньги не пропадают из-за теста.
	isPurchaseProtected = false
	if eventId == "Clear" or eventId == nil then
		applyEvent(nil)
		return true
	end
	for _, event in Config.WeatherEvents.Events do
		if event.Id == eventId then
			applyEvent(event)
			return true
		end
	end
	return false
end

-- Вызывается один раз при заходе игрока (см. Main.server.lua) — без этого
-- игрок, зашедший СРЕДИ активного ивента, видел бы дефолтное небо и не
-- получал бустов мутаций до следующего броска (может быть почти 5 минут).
function WeatherService:SyncPlayer(player)
	if not player.Parent then return end
	weatherRemote:FireClient(player, publicEventPayload(currentEvent))
end

function WeatherService:Start()
	if not Config.WeatherEvents.Enabled then return end
	task.spawn(function()
		while true do
			-- Опрос короткими шагами, а не один большой task.wait — по
			-- прямому запросу: событие, запущенное покупкой, сдвигает
			-- currentEventEndsAt вперёд (см. applyEvent), и цикл должен
			-- это ЗАМЕТИТЬ и подождать дольше, а не сбить только что
			-- купленный ивент по СТАРОМУ расписанию естественного ролла.
			local remaining = currentEventEndsAt - os.time()
			if remaining > 0 then
				task.wait(math.min(remaining, 5))
			else
				local ok, err = pcall(function()
					-- Если во время защиты кто-то купил ДРУГУЮ погоду —
					-- она встала в очередь (см. PurchaseTriggerEvent) и
					-- применяется здесь ПЕРВОЙ, раньше обычного случайного
					-- ролла — оплаченный эффект не теряется.
					if queuedPurchaseEventId then
						local queuedId = queuedPurchaseEventId
						queuedPurchaseEventId = nil
						for _, event in Config.WeatherEvents.Events do
							if event.Id == queuedId then
								applyEvent(event)
								isPurchaseProtected = true
								return
							end
						end
					end
					isPurchaseProtected = false
					applyEvent(pickNextEvent())
				end)
				if not ok then
					warn("[WeatherService] Роллинг погоды упал (цикл продолжает работать):", err)
				end
			end
		end
	end)
end

return WeatherService
