--------------------------------------------------------------------------------
-- PlotService
-- Участки — либо по кругу вокруг банка (по умолчанию, считается кодом), либо
-- ТАМ, ГДЕ САМ РАССТАВИШЬ (см. _resolveOrigins/workspace.PlotOrigins ниже) —
-- билдер сам решает, где на карте вообще стоит каждый участок. А что ГДЕ
-- СТОИТ ВНУТРИ одного участка (шахта, пьедестал прокачки, спавн тележки,
-- спавн игрока, НПС ребёрта) — читается из маркеров шаблона (см.
-- PlaceholderFactory.PlotTemplate), тоже раскладка билдера, не код.
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService") -- плавный возврат цвета шахты после починки (см. RestoreMineLook)

local Config = require(ReplicatedStorage.Shared.Config)
local PlaceholderFactory = require(ReplicatedStorage.Shared.PlaceholderFactory)

local PlotService = {}

local Services = nil
local plots = {}       -- массив слотов
local playerPlots = {} -- [player] = plotData
local fallbackSpawn    -- нейтральная точка возрождения для игроков без участка

function PlotService:Init(services)
	Services = services
end

-- Ищет маркер по имени и возвращает его мировой CFrame — маркер после
-- этого прячется (Transparency=1, CanCollide=false), чтобы не мешал
-- физически и визуально, каким бы его ни оставили в Studio.
--
-- ПОВОРОТ БЕЗ ИНСТРУМЕНТА ROTATE: если рядом лежит ещё одна деталь с тем
-- же именем и суффиксом "Look" (например, для "MineMarker" — "MineMarkerLook"),
-- поворот считается направлением ОТ маркера К НЕЙ — крутить сам маркер
-- руками не нужно, только подвинуть обе части в нужные точки инструментом
-- Move. Если такой детали нет — как и раньше, берётся собственный поворот
-- самого маркера (для тех, у кого Rotate прекрасно работает).
local function readMarker(container, name, optional)
	local part = container:FindFirstChild(name, true)
	if not part then
		assert(optional, "PlotTemplate обязан содержать маркер '" .. name .. "'")
		return nil
	end

	local cframe = part.CFrame
	local lookTarget = container:FindFirstChild(name .. "Look", true)
	if lookTarget then
		cframe = CFrame.lookAt(part.Position, lookTarget.Position)
		lookTarget.Transparency = 1
		lookTarget.CanCollide = false
	end

	part.Transparency = 1
	part.CanCollide = false
	return cframe
end

-- Самая нижняя мировая Y-координата детали, ЛЮБОГО поворота (не только
-- вокруг вертикали) — общая формула для oriented bounding box: проекция
-- половин размера по каждой локальной оси на мировую вертикаль.
-- Используется ниже, чтобы поставить PrimaryPart шахты РОВНО на землю,
-- независимо от того, как автор модели (или сам плейсхолдер) разместил
-- эту часть относительно остальной геометрии.
local function partBottomWorldY(part)
	local cf = part.CFrame
	local half = part.Size / 2
	local drop = math.abs(cf.RightVector.Y) * half.X
		+ math.abs(cf.UpVector.Y) * half.Y
		+ math.abs(cf.LookVector.Y) * half.Z
	return cf.Position.Y - drop
end

-- ГДЕ НА КАРТЕ стоит каждый участок. Если в workspace лежит Folder
-- "PlotOrigins" с частями внутри — берём позицию И поворот каждой такой
-- части (билдер расставил участки по карте сам, сколько частей — столько
-- и участков, Config.World.PlotCount в этом случае не используется).
-- Поворот можно задать как обычным вращением самой части (Rotate), так и
-- БЕЗ вращения вообще — деталь с тем же именем и суффиксом "Look" (для
-- части "Plot1" — деталь "Plot1Look") задаёт направление взгляда, тот же
-- приём, что и у маркеров внутри PlotTemplate (см. readMarker выше).
-- Если папки нет/она пустая — считаем места по кругу вокруг банка, как
-- раньше (Config.World.PlotRadius/PlotCount).
local function resolveOrigins()
	local originsFolder = workspace:FindFirstChild("PlotOrigins")
	if originsFolder then
		local origins = {}
		for _, part in originsFolder:GetChildren() do
			if part:IsA("BasePart") and not part.Name:match("Look$") then
				local cframe = part.CFrame
				local lookTarget = originsFolder:FindFirstChild(part.Name .. "Look")
				if lookTarget then
					cframe = CFrame.lookAt(part.Position, lookTarget.Position)
					lookTarget.Transparency = 1
					lookTarget.CanCollide = false
				end
				table.insert(origins, cframe)
				part.Transparency = 1
				part.CanCollide = false
				part.Anchored = true
			end
		end
		if #origins > 0 then
			return origins
		end
		warn("[PlotService] workspace/PlotOrigins найден, но внутри нет ни одной части — считаю кольцо вокруг банка автоматически")
	end

	local origins = {}
	for i = 1, Config.World.PlotCount do
		local angle = (i / Config.World.PlotCount) * math.pi * 2
		local position = Vector3.new(math.cos(angle), 0, math.sin(angle)) * Config.World.PlotRadius
		local rotation = CFrame.lookAt(position, Vector3.zero) - position
		origins[i] = CFrame.new(position.X, 0.5, position.Z) * rotation
	end
	return origins
end

function PlotService:Start()
	local folder = Instance.new("Folder")
	folder.Name = "Plots"
	folder.Parent = workspace

	for i, origin in resolveOrigins() do
		local template = PlaceholderFactory.PlotTemplate()
		template.Name = "PlotPad_" .. i
		local namedPad = template:FindFirstChild("PlotPad", true)
		local pad = namedPad and namedPad:IsA("BasePart") and namedPad or template.PrimaryPart
		assert(pad and pad:IsA("BasePart"), "PlotTemplate обязан содержать BasePart 'PlotPad' (Part, MeshPart или UnionOperation)")
		template.PrimaryPart = pad
		template:PivotTo(origin)
		template.Parent = folder
		-- v14.4: ТЕРРИТОРИЯ УЧАСТКА — весь прямоугольник PlotTemplate (для
		-- установки декора, см. Shared/GroundCheck.InPlot). Габариты кладём
		-- атрибутами на PlotPad — их читает и клиентский призрак.
		local boundsCFrame, boundsSize = template:GetBoundingBox()
		pad:SetAttribute("PlotBoundsCFrame", boundsCFrame)
		pad:SetAttribute("PlotBoundsSize", boundsSize)

		local leaderboardCFrame = readMarker(template, "LeaderboardMarker", true)
			or (pad.CFrame * CFrame.new(0, pad.Size.Y / 2, pad.Size.Z / 2 - 2))
		local plot = {
			Index = i,
			Origin = origin,
			Pad = pad,
			Template = template,
			TakenBy = nil,
			-- Раскладка внутри участка — читаем ОДИН раз сразу после клонирования
			-- шаблона, дальше просто переиспользуем как готовые CFrame.
			MineCFrame = readMarker(template, "MineMarker"),
			-- v14.3: КУДА СМОТРИТ ШАХТА. Необязательный маркер: шахта
			-- разворачивается лицом к нему, руда вылетает в ту же сторону,
			-- камера мини-игры и вылета встаёт на эту ось. Нет маркера —
			-- старое поведение («влево от банка»).
			MineFacingCFrame = readMarker(template, "MineFacingMarker", true),
			PillarCFrame = readMarker(template, "PillarMarker"),
			-- ПАРКОВКА ТЕЛЕЖКИ — НЕОБЯЗАТЕЛЬНА. С v12 тележка выдаётся
			-- упаковкой и ставится игроком вручную где угодно, так что
			-- выделенное место под неё на участке больше не нужно. Нет
			-- маркера — берём точку перед шахтой: она гарантированно на
			-- пэде и не внутри модели.
			CartSpawnCFrame = readMarker(template, "CartSpawnMarker", true)
				or (readMarker(template, "MineMarker") * CFrame.new(0, 0, 12)),
			PlayerSpawnCFrame = readMarker(template, "PlayerSpawnMarker"),
			RebirthCFrame = readMarker(template, "RebirthMarker"),
			-- УСТАРЕЛО (v12): маркер кнопки "заспавнить тележку". Самой
			-- кнопки больше нет (тележка ставится из упаковки), поле
			-- оставлено только чтобы не ломать шаблоны участков, где
			-- маркер уже лежит. Код к нему не обращается.
			CartButtonCFrame = readMarker(template, "CartButtonMarker", true),
			-- Необязательный — где стоит НПС магазина (Robux), ОТДЕЛЬНО от
			-- продавца прокачки (PillarCFrame). Нет маркера в шаблоне
			-- (старый/чужой PlotTemplate без него) — ShopNpcService сам
			-- пропустит спавн NPC на этом участке, ничего не сломается.
			ShopCFrame = readMarker(template, "ShopMarker", true),
			GeodeBuildingCFrame = readMarker(template, "GeodeBuildingMarker", true)
				or (pad.CFrame * CFrame.new(-13, 2.5, 13)),
			GeodePodiumCFrame = readMarker(template, "GeodePodiumMarker", true)
				or (pad.CFrame * CFrame.new(13, 1.5, 13)),
			GeodeSafeCFrame = readMarker(template, "GeodeSafeMarker", true)
				or (pad.CFrame * CFrame.new(13, 2, 7)),
			LeaderboardCFrame = leaderboardCFrame,
			-- ЛИЧНЫЕ ВАЛУНЫ НА БАЗЕ (см. Config.Boulders.Base и
			-- RockService:SetupPlot). Необязательные: сколько маркеров
			-- BoulderMarker1/2/3... билдер положил в шаблон — столько
			-- валунов и встанет, ни одного не положил — участок просто
			-- будет без них, ничего не ломается (но тогда обучение не
			-- сможет дать игроку первую руду, см. Config.Tutorial).
			-- Читаем ПОДРЯД, до первого отсутствующего номера: дырка в
			-- нумерации почти всегда означает опечатку в Studio, и
			-- молча пропустить её хуже, чем остановиться.
			BoulderCFrames = (function()
				local result = {}
				local prefix = Config.Boulders.Base and Config.Boulders.Base.MarkerPrefix or "BoulderMarker"
				local limit = Config.Boulders.Base and Config.Boulders.Base.MaxPerPlot or 8
				for index = 1, limit do
					local marker = readMarker(template, prefix .. index, true)
					if not marker then break end
					table.insert(result, marker)
				end
				return result
			end)(),
			-- Необязательные маркеры островов (см. Config.Islands). Нет
			-- маркера — IslandService сам поставит остров позади участка.
			IslandCFrames = (function()
				local result = {}
				local islands = Config.Islands
				for id, definition in (islands and islands.Definitions) or {} do
					result[id] = readMarker(template, definition.PlotMarker or ("Island" .. id .. "Marker"), true)
				end
				return result
			end)(),
		}
		plots[i] = plot
		Services.LeaderboardService:SetupPlot(plot)
	end

	self:_buildFallbackSpawn()
end

-- ЗАПАСНОЙ СПАВН — для игрока, которому участок не достался (все заняты,
-- либо в workspace.PlotOrigins частей меньше, чем мест на сервере).
--
-- Зачем: у КАЖДОГО участка свой SpawnLocation с Neutral = true, и Roblox
-- считает их всех кандидатами на случайный спавн. Игроку без участка
-- RespawnLocation никто не выставлял (AssignPlot вернул nil, movePlayerToPlot
-- выходит сразу) — то есть его выбрасывало на СЛУЧАЙНУЮ ЧУЖУЮ БАЗУ, и туда
-- же после каждой смерти. Теперь ему явно назначается вот эта нейтральная
-- точка у банка. Выключить SpawnLocation'ы участков нельзя: RespawnLocation
-- работает только с Enabled = true.
function PlotService:_buildFallbackSpawn()
	local center = Vector3.new(0, 0, 0)
	if Services.WorldService and Services.WorldService.GetBankTargetPosition then
		local ok, bankPosition = pcall(function()
			return Services.WorldService:GetBankTargetPosition()
		end)
		if ok and typeof(bankPosition) == "Vector3" then center = bankPosition end
	end

	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "FallbackSpawn"
	spawnLocation.Size = Vector3.new(8, 1, 8)
	spawnLocation.CFrame = CFrame.new(center.X, center.Y + 4, center.Z + 18)
	spawnLocation.Anchored = true
	spawnLocation.Neutral = true
	spawnLocation.Duration = 0
	spawnLocation.Transparency = 1
	spawnLocation.CanCollide = false
	spawnLocation.Parent = workspace
	fallbackSpawn = spawnLocation
end

function PlotService:GetFallbackSpawn()
	return fallbackSpawn
end

--------------------------------------------------------------------------------

function PlotService:AssignPlot(player)
	local plot = nil
	for _, candidate in plots do
		if candidate.TakenBy == nil then
			plot = candidate
			break
		end
	end
	if not plot then
		warn("[PlotService] Нет свободных участков для", player.Name)
		return nil
	end
	plot.TakenBy = player
	plot.Pad:SetAttribute("OwnerUserId", player.UserId)
	player:SetAttribute("PlotIndex", plot.Index)

	local content = Instance.new("Folder")
	content.Name = "Content_" .. player.Name
	content.Parent = plot.Pad
	plot.Content = content

	local tiers = Services.DataService:GetTiers(player)

	self:_buildMine(plot, tiers.Mine) -- позиция/поворот — plot.MineCFrame, из маркера шаблона

	-- Парковка тележек — ОТДЕЛЬНОЕ место на участке, не привязано к шахте
	-- (раньше тележка спавнилась прямо в зоне шахты и точка съезжала при
	-- каждом апгрейде шахты вместе с моделью). Позиция — plot.CartSpawnCFrame,
	-- из маркера "CartSpawnMarker" шаблона.
	local parkingPad = Instance.new("Part")
	parkingPad.Name = "CartParkingPad"
	parkingPad.Size = Vector3.new(10, 0.2, 8)
	parkingPad.CFrame = plot.CartSpawnCFrame * CFrame.new(0, -0.9, 0)
	parkingPad.Anchored = true
	parkingPad.CanCollide = false
	parkingPad.Color = Color3.fromRGB(90, 110, 140)
	parkingPad.Material = Enum.Material.SmoothPlastic
	parkingPad.TopSurface = Enum.SurfaceType.Smooth
	parkingPad.Parent = plot.Content

	-- Персональный спавн — позиция plot.PlayerSpawnCFrame, из маркера
	-- "PlayerSpawnMarker" шаблона. Invisible/без коллизии — это чисто
	-- функциональная точка возрождения, а не физическая площадка: видимая
	-- цветная плита выглядит как забытый плейсхолдер и мешала бы ходьбе.
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Size = Vector3.new(6, 1, 6)
	spawnLocation.CFrame = plot.PlayerSpawnCFrame
	spawnLocation.Anchored = true
	spawnLocation.Neutral = true
	spawnLocation.Duration = 0
	spawnLocation.Transparency = 1
	spawnLocation.CanCollide = false
	spawnLocation.Parent = content
	plot.PlayerSpawnLocation = spawnLocation
	player.RespawnLocation = spawnLocation

	playerPlots[player] = plot
	Services.UpgradeService:SetupPlot(player, plot)
	Services.RebirthService:SetupPlot(player, plot)
	pcall(function() Services.PrestigeService:SetupPlot(player, plot) end) -- v8: чемоданчик перков у NPC ребёрта
	pcall(function() Services.GearService:SetupPlot(player, plot) end) -- v8: поставленные сундуки (таймер идёт и оффлайн)
	-- v12: физической кнопки "Spawn New" больше нет — тележка появляется
	-- только из упаковки, которую игрок ставит сам (см. CartService,
	-- раздел "ВЛАДЕНИЕ ТЕЛЕЖКОЙ И УПАКОВКА"). Строка вызова
	-- CartService:SetupRespawnButton удалена вместе с самой функцией.
	Services.ShopNpcService:SetupPlot(player, plot)
	Services.GeodeService:SetupPlot(player, plot)
	Services.PassiveIncomeService:SetupPlot(player, plot)
	Services.MineService:SetupPlot(player, plot) -- НПС-шахтёр у входа в шахту, см. MineService "РУДА v2"
	-- Личные валуны на базе (см. Config.Boulders.Base). ПОСЛЕ MineService:
	-- их тир считается от шахты, а она к этому моменту уже построена.
	if Services.RockService and Services.RockService.SetupPlot then
		pcall(function() Services.RockService:SetupPlot(player, plot) end)
	end
	-- Острова позади участка (наковальня / доход / плавильня) — строятся
	-- сразу для уже купленных, без анимации. ПОСЛЕ Geode/PassiveIncome:
	-- те выставляют атрибуты туториала и офлайн-доход.
	if Services.IslandService then
		Services.IslandService:SetupPlot(player, plot)
	end
	-- v14: тотемы, декор и реликвии, поставленные игроком (позиции
	-- относительно участка — встают на место на любом участке).
	if Services.BaseDecorService then
		local ok, err = pcall(function() Services.BaseDecorService:SetupPlot(player, plot) end)
		if not ok then warn("[PlotService] BaseDecorService:SetupPlot упал:", err) end
	end
	return plot
end

function PlotService:_buildMine(plot, tier)
	-- ПОРЯДОК ЗДЕСЬ ВАЖЕН. Раньше старая шахта уничтожалась ПЕРВОЙ строкой,
	-- а обязательная деталь "Zone" у новой проверялась только в самом низу
	-- функции, через assert. На кривой пользовательской модели Mine_TierN
	-- (проект прямо предлагает подкладывать свои ассеты) это разносило
	-- участок в необратимое состояние: старая шахта уже удалена, новая уже
	-- поставлена и записана в plot.MineModel, а plot.MineZonePosition/
	-- MineZoneCFrame/MineZoneSize остались от ПРЕДЫДУЩЕГО тира. От них
	-- зависят позиции по умолчанию (шахтёр, вход, падение руды, цель
	-- гоблинов) — рассинхрон тира и этих позиций сбивал бы их с толку.
	-- И всё это уже
	-- ПОСЛЕ того, как UpgradeService:_tryBuy списал деньги и повысил тир.
	-- Теперь новая модель полностью собирается и проверяется, и только потом
	-- заменяет старую; при неудаче участок остаётся ровно как был.
	local mine = PlaceholderFactory.Mine(tier)
	if not mine.PrimaryPart then
		warn(
			("[PlotService] У модели '%s' (Mine_Tier%d) не назначен PrimaryPart — без него нечего ставить на землю, позиция/поворот шахты будут непредсказуемыми. Назначь PrimaryPart в Properties: возьми ту часть модели, которая физически должна стоять/касаться земли (например, фундамент или нижний этаж, а не крыша) — её нижний край код теперь САМ подгонит вплотную к полу участка. \"Перёд\" модели (там, где должна парковаться тележка/Zone) должен смотреть в ЛОКАЛЬНЫЙ +Z от этой части."):format(
				mine.Name,
				tier
			)
		)
	end
	mine:PivotTo(plot.MineCFrame)

	-- ШАХТА ПОВЁРНУТА ЛИЦОМ К БАНКУ (по прямому запросу — "налево 90
	-- градусов, если смотреть со стороны банка"). Считаем это ДИНАМИЧЕСКИ
	-- от реальной позиции банка на карте, а не правкой маркера в Studio:
	-- маркер один на всех игроков, а участков много, и на каждом это давало
	-- бы свой угол — тут код сам довернёт шахту на КАЖДОМ участке.
	--
	-- Геометрия: пусть bankwardDir — направление от шахты к банку (по
	-- горизонтали). Наблюдатель СТОИТ У БАНКА и смотрит НА УЧАСТОК, то есть
	-- его собственный взгляд направлен противоположно bankwardDir. "Левая"
	-- рука наблюдателя, стоящего лицом к участку, — это Y × (-bankwardDir).
	-- Именно в эту сторону и должен теперь смотреть перёд шахты (её
	-- LookVector).
	--
	-- Меняем ТОЛЬКО поворот вокруг вертикали (yaw): позиция и наклон,
	-- которые уже расставил маркер/поправка высоты ниже, не трогаются.
	do
		local bankPosition = nil
		if Services.WorldService and Services.WorldService.GetBankTargetPosition then
			local ok, position = pcall(function()
				return Services.WorldService:GetBankTargetPosition()
			end)
			if ok and typeof(position) == "Vector3" then bankPosition = position end
		end

		plot.MineFacingDir = nil
		if plot.MineFacingCFrame then
			-- v14.3: лицом к MineFacingMarker из PlotTemplate.
			local minePosition = mine:GetPivot().Position
			local flat = (plot.MineFacingCFrame.Position - minePosition) * Vector3.new(1, 0, 1)
			if flat.Magnitude > 0.1 then
				local facing = flat.Unit
				mine:PivotTo(CFrame.lookAt(minePosition, minePosition + facing) * CFrame.Angles(0, math.rad(Config.Mine.ModelFrontYaw or 0), 0))
				-- Если «перёд» модели не совпадает с её LookVector, положи в
				-- модель шахты деталь MineFront перед входом — довернём так,
				-- чтобы именно она смотрела на маркер.
				local front = mine:FindFirstChild("MineFront", true)
				if front and front:IsA("BasePart") then
					local pivot = mine:GetPivot()
					local d = (front.Position - pivot.Position) * Vector3.new(1, 0, 1)
					if d.Magnitude > 0.1 then
						d = d.Unit
						local yaw = math.atan2(d:Cross(facing).Y, d:Dot(facing))
						mine:PivotTo(CFrame.new(pivot.Position) * CFrame.Angles(0, yaw, 0) * pivot.Rotation)
					end
					front.Transparency = 1
					front.CanCollide = false
				end
				plot.MineFacingDir = facing
			end
		elseif bankPosition then
			local minePosition = mine:GetPivot().Position
			local bankwardDir = (bankPosition - minePosition) * Vector3.new(1, 0, 1)
			if bankwardDir.Magnitude > 0.1 then
				bankwardDir = bankwardDir.Unit
				local observerForward = -bankwardDir -- банк смотрит НА участок
				local observerLeft = Vector3.yAxis:Cross(observerForward)
				if observerLeft.Magnitude > 0.1 then
					local facing = observerLeft.Unit
					-- v20.34: визуальный перёд модели (Config.Mine.ModelFrontYaw).
					mine:PivotTo(CFrame.lookAt(minePosition, minePosition + facing) * CFrame.Angles(0, math.rad(Config.Mine.ModelFrontYaw or 0), 0))
					plot.MineFacingDir = facing
				end
			end
		end
		-- Клиенту: куда смотрит лицо шахты (катсцена улучшения тира снимает
		-- именно отсюда, а не со стороны банка).
		if plot.MineFacingDir then mine:SetAttribute("MineFrontDir", plot.MineFacingDir) end
	end

	-- ПРИВЯЗКА К ЗЕМЛЕ: MineMarker в шаблоне участка задаёт X/Z и поворот,
	-- но его высота (Y) — это лишь ПРЕДПОЛОЖЕНИЕ о том, где у конкретной
	-- модели шахты находится PrimaryPart относительно её нижнего края. Для
	-- плейсхолдера это предположение верно почти всегда (он строится с
	-- расчётом на эту высоту), но у любого чужого готового ассета
	-- (произвольная высота/пропорции) оно почти наверняка не совпадёт —
	-- шахта либо повиснет в воздухе, либо провалится под землю. Поэтому
	-- после расстановки по маркеру ВСЕГДА досчитываем и подгоняем высоту
	-- заново: реальный нижний край PrimaryPart (см. partBottomWorldY,
	-- учитывает любой поворот) должен лечь ровно на верх пола участка
	-- (plot.Pad) — если не совпало, сдвигаем модель по вертикали на
	-- разницу. Работает одинаково и для плейсхолдера, и для готового
	-- ассета билдера — оба проходят через один и тот же PrimaryPart.
	if mine.PrimaryPart then
		local groundY = plot.Pad.Position.Y + plot.Pad.Size.Y / 2
		local correction = groundY - partBottomWorldY(mine.PrimaryPart)
		if math.abs(correction) > 1e-3 then
			mine:PivotTo(mine:GetPivot() + Vector3.new(0, correction, 0))
		end
	end

	-- "Zone" БОЛЬШЕ НЕ ОБЯЗАТЕЛЬНА (по прямому запросу). Раньше её
	-- отсутствие целиком проваливало применение тира — самый частый способ
	-- сломать себе шахту кастомным ассетом на пустом месте, хотя Zone
	-- давно уже используется только как ИСТОЧНИК ПОЗИЦИЙ (куда падает
	-- руда, где стоит шахтёр, куда идут гоблины), а не как что-то, от чего
	-- зависит сама механика добычи.
	--
	-- Нет детали — строим её САМИ: невидимый, некликаемый Part перед
	-- шахтой (локальный +Z от PrimaryPart, на её ширину дальше нижнего
	-- края). Он ничем не хуже авторской Zone для всех вычислений ниже —
	-- они используют только Position/CFrame/Size.
	local zone = mine:FindFirstChild("Zone", true)
	local zoneIsSynthetic = false
	if not zone then
		zoneIsSynthetic = true
		local anchor = mine.PrimaryPart or mine:FindFirstChildWhichIsA("BasePart", true)
		if not anchor then
			-- Совсем пусто — даже якорить не от чего. Единственный случай,
			-- когда действительно нечего собрать.
			mine:Destroy()
			warn(("[PlotService] У модели шахты Mine_Tier%d нет ни одной BasePart — тир НЕ применён, участок оставлен без изменений."):format(tier))
			return false
		end

		local _, boundsSize = mine:GetBoundingBox()
		zone = Instance.new("Part")
		zone.Name = "Zone"
		zone.Size = Vector3.new(math.max(6, boundsSize.X * 0.6), 1, math.max(6, boundsSize.Z * 0.4))
		zone.CFrame = anchor.CFrame * CFrame.new(0, -anchor.Size.Y / 2, anchor.Size.Z / 2 + zone.Size.Z / 2)
		zone.Anchored = true
		zone.CanCollide = false
		zone.CanQuery = false
		zone.CanTouch = false
		zone.Transparency = 1
		zone.Parent = mine

		warn(("[PlotService] У модели шахты Mine_Tier%d нет детали 'Zone' — сгенерирована временная перед входом. Если авто-позиция выглядит неправильно, добавьте свою деталь 'Zone' в модель."):format(tier))
	end

	-- Точка невозврата: с этого места и до конца функции нет ничего, что
	-- могло бы упасть, поэтому состояние участка меняем одним куском.
	if plot.TakenBy then
		plot.TakenBy:SetAttribute("MineTier", tier)
	end
	if plot.MineModel then
		plot.MineModel:Destroy()
	end
	-- Метка "это модель шахты участка" для клиента (катсцена улучшения):
	-- по имени шахту путали с MinerNPC/MineActor из той же папки.
	mine:SetAttribute("PlotMine", true)
	mine.Parent = plot.Content
	plot.MineModel = mine

	plot.MineZonePosition = zone.Position
	plot.MineZoneCFrame = zone.CFrame -- см. MineService: проверка "тележка внутри зоны" идёт по РЕАЛЬНОЙ площади этой части, а не по радиусу от центра
	plot.MineZoneSize = zone.Size

	-- Откуда руда визуально "падает" перед тем, как лечь в слот тележки
	-- (см. MineService/CartService:AddCrystal). Необязательный маркер —
	-- если билдер его не поставил (или у кастомного ассета его нет вовсе),
	-- берём разумный дефолт прямо над зоной парковки: чуть выше обычной
	-- высоты тележки, чтобы всё равно было похоже на "выпало сверху", а не
	-- бралось из центра Zone. ВАЖНО: отсюда реально используется только
	-- ВЫСОТА (Y) — X/Z каждый раз берутся от текущей позиции тележки в
	-- MineService, чтобы руда падала прямо над ней в ЛЮБОМ месте Zone, а не
	-- только строго по центру.
	local dropPoint = mine:FindFirstChild("OreDropPoint", true)
	plot.OreDropPosition = dropPoint and dropPoint.Position or (zone.Position + Vector3.new(0, 4, 0))

	-- НОВОЕ (см. ТЗ "переписать систему механики сбора руды"): где стоит
	-- НПС-шахтёр ("слева от шахты") и куда камера/игрок "заходят внутрь"
	-- на мини-игру. Необязательные маркеры внутри модели Mine_TierN —
	-- "MinerMarker" и "MineEntryPoint". Если билдер их не положил, берём
	-- разумный дефолт от Zone: НПС — на ширину Zone левее её центра,
	-- точка входа — чуть впереди Zone (в её локальном +Z, "внутрь" шахты).
	local minerMarker = mine:FindFirstChild("MinerMarker", true)
	plot.MinerCFrame = (minerMarker and minerMarker:IsA("BasePart"))
		and minerMarker.CFrame
		or (zone.CFrame * CFrame.new(-(zone.Size.X / 2 + 4), 0, 0))

	-- ENTRY (по прямому запросу — "центром шахты должен являться ENTRY,
	-- оттуда и должна вылетать руда"). Ищем ту же деталь, что и
	-- MineService:_applyEntryMesh (регистронезависимо, "ENTRY"/"Entry") —
	-- это авторский вход, самая осмысленная точка отсчёта для шахты, и
	-- она ПРИОРИТЕТНЕЕ и абстрактного маркера "MineEntryPoint", и
	-- дефолта от Zone: ENTRY, если она есть, побеждает оба.
	local entry = nil
	local entryModel = nil
	for _, descendant in mine:GetDescendants() do
		if descendant.Name:upper() == "ENTRY" then
			if descendant:IsA("BasePart") then
				entry = descendant
				break
			elseif descendant:IsA("Model") and not entryModel then
				entryModel = descendant -- v14.4: ENTRY может быть и моделью
			end
		end
	end

	-- v14.4: ТОЧКА ЗАХОДА/ВЫХОДА = СЕРЕДИНА ENTRY (центр детали или
	-- габаритов модели ENTRY). Шахтёр и клон заходят в неё и из неё же
	-- выходят (см. MineService:_minePath / _finishExpedition).
	local entryMarker = mine:FindFirstChild("MineEntryPoint", true)
	local entryModelCFrame = entryModel and (entryModel:GetBoundingBox())
	plot.MineEntryCFrame = entry and entry.CFrame
		or entryModelCFrame
		or (entryMarker and entryMarker:IsA("BasePart") and entryMarker.CFrame)
		or (zone.CFrame * CFrame.new(0, 0, zone.Size.Z / 2 + 6))

	if entry then
		-- ENTRY — ЦЕНТР ШАХТЫ. PrimaryPart нужен был для расстановки на
		-- земле (партBottomWorldY чуть выше уже отработал по НЕЙ, по
		-- фундаменту) — эта переприсвойка идёт СТРОГО ПОСЛЕ подгонки
		-- высоты и ничего физически не двигает: PrimaryPart — это просто
		-- ссылка, задающая точку Model:GetPivot()/ScaleTo() для всего,
		-- что случится с моделью дальше (рост при ударах, "взрыв" по
		-- завершении мини-игры — см. MineService:_stretchMine/_burstMine).
		-- Раньше та рос вокруг фундамента, что при несимметричной модели
		-- визуально "сползало" в сторону; теперь рост идёт от входа.
		mine.PrimaryPart = entry
	end

	-- ПОСТОЯННЫЙ РАЗМЕР ШАХТЫ: +30% для ЛЮБОГО тира (по прямому запросу).
	-- Ставим ПОСЛЕ того, как PrimaryPart уже указывает на ENTRY (если она
	-- есть): Model:ScaleTo растягивает модель вокруг ЕЁ ТЕКУЩЕГО пивота, и
	-- нам как раз нужно, чтобы шахта росла от входа, а не от фундамента.
	-- Позиция/поворот/подгонка по земле уже закончены на этом месте, так
	-- что рост не собьёт ничего из посчитанного выше.
	--
	-- Это ОБЩАЯ база для временных эффектов мини-игры (рост при ударах,
	-- "взрыв") — см. Config.MineExpedition.MineBaseScale и
	-- MineService:_stretchMine/_burstMine, которые считают уже ОТ НЕЁ, а не
	-- от 1: иначе первый же удар мини-игры откатил бы шахту обратно к
	-- авторскому размеру.
	do
		local baseScale = Config.MineExpedition and Config.MineExpedition.MineBaseScale or 1
		if baseScale ~= 1 then
			pcall(function() mine:ScaleTo(baseScale) end)
		end
	end

	-- MineDoor — часть/меш модели шахты, которая получает неоновый
	-- материал + цвет редкости и включает свои VFX-attachment'ы во время
	-- мини-игры и на вылете руды (см. Config.MineDoorRarityColor и
	-- MineService:_applyDoorRarity). Необязательно — если билдер не
	-- положил такую часть, просто не будет этого конкретного эффекта,
	-- остальная механика продолжает работать.
	plot.MineDoorPart = mine:FindFirstChild("MineDoor", true)
	if plot.MineDoorPart and not plot.MineDoorPart:IsA("BasePart") then
		plot.MineDoorPart = nil
	end

	-- МАРКЕРЫ КАМЕРЫ МИНИ-ИГРЫ ШАХТЫ (по прямому запросу — "камера летает
	-- не так, как хочет сейчас, а я буду спавнить маркеры с направлением
	-- куда она должна смотреть при каждой ситуации"). Билдер кладёт В
	-- МОДЕЛЬ ШАХТЫ пары частей: "CameraMarker1" (где стоит камера) +
	-- "CameraMarker1Look" (на что она смотрит — просто точка в
	-- пространстве, БЕЗ вращения самой части, camera:LookAt строит
	-- поворот сама), затем "CameraMarker2"/"CameraMarker2Look" и т.д. —
	-- сколько нужно, без ограничения сверху. Какой маркер за какую
	-- стадию мини-игры отвечает — см. Config.MineExpedition
	-- .CameraMarkerForStage (там просто номер маркера на каждую стадию,
	-- ничего не программируется). Если для номера нет пары — часть
	-- маркеров, дальше не ищем.
	plot.CameraMarkers = {}
	local markerIndex = 1
	while true do
		local marker = mine:FindFirstChild("CameraMarker" .. markerIndex, true)
		local look = mine:FindFirstChild("CameraMarker" .. markerIndex .. "Look", true)
		if not (marker and marker:IsA("BasePart") and look and look:IsA("BasePart")) then
			break
		end
		plot.CameraMarkers[markerIndex] = { Position = marker.Position, LookAt = look.Position }
		markerIndex += 1
	end
	if next(plot.CameraMarkers) == nil then
		warn("[PlotService] В модели шахты не нашлось ни одной пары CameraMarkerN/CameraMarkerNLook — камера мини-игры шахты будет использовать старое поведение по умолчанию (см. MineExpeditionUI.client.lua). Это не ошибка, просто билдер ещё не расставил маркеры.")
	end

	-- ШАХТА ЕЩЁ НЕ ПОЧИНЕНА (см. Config.Mine.Broken и Config.Tutorial) —
	-- гасим модель в чёрный неон. Вызывается ЗДЕСЬ, а не из TutorialService,
	-- потому что модель шахты пересобирается заново на каждом апгрейде и на
	-- каждой выдаче участка: любое другое место пришлось бы синхронизировать
	-- с этими перестройками вручную.
	if plot.TakenBy and Services.TutorialService
		and not Services.TutorialService:IsMineRepaired(plot.TakenBy)
	then
		self:ApplyBrokenMineLook(plot)
	end

	return true
end

--------------------------------------------------------------------------------
-- ВНЕШНИЙ ВИД СЛОМАННОЙ ШАХТЫ.
--
-- Оригинальные цвет/материал каждой детали запоминаются в её собственных
-- атрибутах (_OrigColor/_OrigMaterial), а не в отдельной таблице на стороне
-- сервиса. Причина: модель шахты живёт дольше, чем любое состояние в памяти
-- сервиса (её пересобирает _buildMine, у неё свой жизненный цикл), и
-- таблица рано или поздно разошлась бы с реальными деталями. Атрибут едет
-- вместе с деталью и не может от неё отстать.
--------------------------------------------------------------------------------
local function eachMinePart(mine, fn)
	if not mine then return end
	local skip = (Config.Mine.Broken and Config.Mine.Broken.SkipNames) or {}
	for _, descendant in mine:GetDescendants() do
		if descendant:IsA("BasePart") and not skip[descendant.Name] and descendant.Transparency < 1 then
			fn(descendant)
		end
	end
end

-- Всё, что даёт детали "вид": текстуры мешей, наклейки, PBR-обвязка.
-- Именно их снятие и делает шахту «обесточенной» — модель остаётся на
-- месте со всей геометрией, но теряет отделку.
local function eachMineSkin(mine, fn)
	if not mine then return end
	for _, descendant in mine:GetDescendants() do
		if descendant:IsA("SurfaceAppearance") or descendant:IsA("Decal") or descendant:IsA("Texture") then
			fn(descendant)
		end
	end
end

function PlotService:ApplyBrokenMineLook(plot)
	local mine = plot and plot.MineModel
	local cfg = Config.Mine.Broken
	if not (mine and cfg) then return end
	if mine:GetAttribute("MineBroken") == true then return end -- уже погашена, второй проход затёр бы исходные значения

	eachMinePart(mine, function(part)
		if part:GetAttribute("_OrigMaterial") == nil then
			part:SetAttribute("_OrigColor", part.Color)
			part:SetAttribute("_OrigMaterial", part.Material.Name)
			-- TextureID есть только у MeshPart; у обычных Part его нет,
			-- поэтому читаем защищённо и запоминаем, только если он был.
			if part:IsA("MeshPart") then
				local ok, texture = pcall(function() return part.TextureID end)
				if ok and texture and texture ~= "" then
					part:SetAttribute("_OrigTexture", texture)
				end
			end
		end
		part.Color = cfg.Color
		part.Material = cfg.Material
		-- СНИМАЕМ ТЕКСТУРУ МЕША. Ради этого всё и затевалось: модель шахты
		-- почти целиком из мешей, и покраска .Color на них почти не видна —
		-- цвет перемножается с текстурой и даёт грязное пятно, а не
		-- «выключено». Пустой TextureID показывает голый меш, и вот он уже
		-- честно читается как обесточенный.
		if part:IsA("MeshPart") and part:GetAttribute("_OrigTexture") ~= nil then
			pcall(function() part.TextureID = "" end)
		end
	end)

	-- SurfaceAppearance перекрывает и цвет, и TextureID — пока он на детали,
	-- снятие текстуры вообще не видно. Поэтому его временно отключаем,
	-- пряча в саму деталь (не удаляем: восстановить было бы нечем).
	-- SurfaceAppearance перекрывает и цвет, и TextureID — пока он на детали,
	-- снятие текстуры вообще не видно. Убрать его свойством нельзя (у него
	-- нет Enabled), поэтому переносим в служебную папку внутри модели и
	-- запоминаем, откуда взяли. Не удаляем: восстановить было бы нечем.
	local stash = mine:FindFirstChild("_BrokenSkins")
	if not stash then
		stash = Instance.new("Folder")
		stash.Name = "_BrokenSkins"
		stash.Parent = mine
	end
	eachMineSkin(mine, function(skin)
		if skin:IsDescendantOf(stash) then return end
		if skin:IsA("SurfaceAppearance") then
			local origin = Instance.new("ObjectValue")
			origin.Name = "Origin"
			origin.Value = skin.Parent
			origin.Parent = skin
			skin.Parent = stash
		else
			if skin:GetAttribute("_OrigTransparency") == nil then
				skin:SetAttribute("_OrigTransparency", skin.Transparency)
			end
			skin.Transparency = 1
		end
	end)

	mine:SetAttribute("MineBroken", true)
end
-- Возвращает запомненный вид и играет анимацию починки. Идемпотентна:
-- деталь без _OrigMaterial просто пропускается, поэтому повторный вызов
-- (или вызов на уже целой шахте) ничего не портит.
function PlotService:RestoreMineLook(plot)
	local mine = plot and plot.MineModel
	local cfg = Config.Mine.Broken
	if not (mine and cfg) then return end
	if mine:GetAttribute("MineBroken") ~= true then return end
	mine:SetAttribute("MineBroken", false)

	-- v20.40: ПОЛНАЯ ПЕРЕСБОРКА. Возврат запомненного вида терял часть
	-- модели (детали/наклейки, которые скрипты шахты или «чёрный» вид успели
	-- поменять). Теперь после починки шахта ставится заново из шаблона того
	-- же тира — все детали на месте. Не вышло — старый путь ниже.
	local owner = plot.TakenBy
	local tier = owner and tonumber(owner:GetAttribute("MineTier"))
	if owner and tier and self:SetMineTier(owner, tier) and plot.MineModel and plot.MineModel ~= mine then
		mine = plot.MineModel -- MineRepaired уже true → чёрный вид не накладывается
	else

	-- 1) Возвращаем отделку. Текстуры и SurfaceAppearance — мгновенно:
	--    они не твинятся, а «проявляться» им и не нужно, вспышка ниже
	--    перекрывает момент подмены.
	local stash = mine:FindFirstChild("_BrokenSkins")
	if stash then
		for _, skin in stash:GetChildren() do
			local origin = skin:FindFirstChild("Origin")
			if origin and origin.Value then
				skin.Parent = origin.Value
			end
			if origin then origin:Destroy() end
		end
		stash:Destroy()
	end

	local info = TweenInfo.new(cfg.RepairFadeSeconds or 1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	eachMinePart(mine, function(part)
		local originalMaterial = part:GetAttribute("_OrigMaterial")
		if originalMaterial == nil then return end
		local originalColor = part:GetAttribute("_OrigColor")
		local originalTexture = part:GetAttribute("_OrigTexture")
		if part:IsA("MeshPart") and originalTexture ~= nil then
			pcall(function() part.TextureID = originalTexture end)
		end
		for _, skin in part:GetDescendants() do
			if (skin:IsA("Decal") or skin:IsA("Texture")) and skin:GetAttribute("_OrigTransparency") ~= nil then
				skin.Transparency = skin:GetAttribute("_OrigTransparency")
				skin:SetAttribute("_OrigTransparency", nil)
			end
		end
		-- Материал не твинится (не числовое свойство) — возвращаем сразу,
		-- плавным делаем только цвет.
		part.Material = Enum.Material[originalMaterial] or part.Material
		if typeof(originalColor) == "Color3" then
			TweenService:Create(part, info, { Color = originalColor }):Play()
		end
		part:SetAttribute("_OrigColor", nil)
		part:SetAttribute("_OrigMaterial", nil)
		part:SetAttribute("_OrigTexture", nil)
	end)
	end -- v20.40: старый путь (без пересборки)

	-- 2) АНИМАЦИЯ ПОЧИНКИ. Починка — это по сути апгрейд шахты, и выглядеть
	--    она должна как событие, а не как молчаливая смена цвета: модель
	--    коротко приседает и распрямляется, снизу бьёт вспышка. Делается
	--    на сервере, потому что модель шахты серверная и реплицируется
	--    всем — соседи по серверу увидят починку так же, как владелец.
	local primary = mine.PrimaryPart or mine:FindFirstChildWhichIsA("BasePart", true)
	if primary then
		local origin = mine:GetPivot()
		local squash = origin * CFrame.new(0, -1.6, 0)
		pcall(function() mine:PivotTo(squash) end)
		task.spawn(function()
			local steps = 14
			for i = 1, steps do
				local alpha = i / steps
				-- обратный «пружинный» выход: проскакивает вверх и садится
				local eased = 1 - math.cos(alpha * math.pi * 0.5)
				local overshoot = math.sin(alpha * math.pi) * 0.5
				pcall(function()
					mine:PivotTo(origin * CFrame.new(0, -1.6 * (1 - eased) + overshoot, 0))
				end)
				task.wait(0.03)
			end
			pcall(function() mine:PivotTo(origin) end)
		end)

		local flash = Instance.new("Part")
		flash.Shape = Enum.PartType.Ball
		flash.Material = Enum.Material.Neon
		flash.Color = Color3.fromRGB(255, 220, 130)
		flash.Size = Vector3.new(2, 2, 2)
		flash.Anchored = true
		flash.CanCollide = false
		flash.CanQuery = false
		flash.CanTouch = false
		flash.CFrame = CFrame.new(origin.Position)
		flash.Parent = mine
		TweenService:Create(flash, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(34, 34, 34),
			Transparency = 1,
		}):Play()
		game:GetService("Debris"):AddItem(flash, 0.7)
	end
end

-- Возвращает true, только если тир реально применён (см. _buildMine).
-- UpgradeService:_tryBuy опирается на это, чтобы вернуть деньги, если шахту
-- не удалось перестроить.
function PlotService:SetMineTier(player, tier)
	local plot = playerPlots[player]
	if not plot then
		return false
	end
	local ok = self:_buildMine(plot, tier) == true
	-- Тир шахты сменил модель → маркер MinerMarker/MineEntryPoint пересчитан
	-- заново в _buildMine (см. plot.MinerCFrame выше). НПС-шахтёр должен
	-- переехать вместе с новой моделью, иначе он останется стоять у старой
	-- (уже снесённой) шахты.
	if ok and Services.MineService then
		Services.MineService:RepositionNpc(player, plot)
	end
	return ok
end

function PlotService:GetPlot(player)
	return playerPlots[player]
end

-- Все участки разом (занятые и свободные) — нужно CombatService для проверки
-- безопасной зоны (весь PlotPad — не PvP-зона, см. Config.Combat.SafeZoneYPadding),
-- без привязки к конкретному игроку.
function PlotService:GetAllPlots()
	return plots
end

function PlotService:ReleasePlot(player)
	-- Валуны живут в plot.Content и умрут вместе с ним, но их точки лежат в
	-- таблице RockService — без явного снятия она копила бы мусор на каждом
	-- заходе/выходе игрока за сессию сервера.
	if Services.RockService and Services.RockService.ReleasePlotBoulders then
		pcall(function() Services.RockService:ReleasePlotBoulders(player) end)
	end
	local plot = playerPlots[player]
	if not plot then
		return
	end
	playerPlots[player] = nil
	plot.TakenBy = nil
	plot.Pad:SetAttribute("OwnerUserId", nil)
	player:SetAttribute("PlotIndex", nil)
	plot.MineModel = nil
	-- Геометрия зоны добычи оставалась от ПРЕДЫДУЩЕГО владельца. Обычно её
	-- перезапишет _buildMine при следующей выдаче участка, но он умеет
	-- вернуть false (у кастомной модели Mine_TierN нет обязательной детали
	-- 'Zone') — и тогда новый игрок унаследовал бы чужую зону: MineService
	-- считал бы тележку "в шахте" не там, где она стоит.
	plot.MineZonePosition = nil
	plot.MineZoneCFrame = nil
	plot.MineZoneSize = nil
	plot.OreDropPosition = nil
	plot.MinerCFrame = nil
	plot.MineEntryCFrame = nil
	plot.MineDoorPart = nil
	plot.CameraMarkers = nil
	plot.PlayerSpawnLocation = nil
	if plot.Content then
		plot.Content:Destroy()
		plot.Content = nil
	end
end

return PlotService
