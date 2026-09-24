--------------------------------------------------------------------------------
-- BuffBar (LocalScript) — ЕДИНАЯ панель активных эффектов справа.
--
-- Раньше каждый эффект показывал себя сам и по-своему: сейв-зона — своим
-- HUD'ом, погода — своим, баффы из жеод не показывались вообще. Игрок не
-- мог одним взглядом понять, что на нём сейчас висит.
--
-- Теперь все эффекты — иконки в одном столбце справа, и у каждой есть
-- подсказка: на ПК по наведению, на телефоне по нажатию (там наведения не
-- существует в принципе, и без этого половина игроков осталась бы без
-- объяснения). Иконки — ImageLabel: подставьте свой Image, и оформление
-- сменится без правок кода.
--
-- ИСТОЧНИКИ ЭФФЕКТОВ (каждый опционален — нет источника, нет иконки):
--   • баффы из жеод и наград   — RemoteEvent "BuffState" (BuffService);
--   • сейв-зона                — атрибут игрока "InSafeZone";
--   • погода                   — атрибут игрока "WeatherEvent".
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- На 20% меньше прежних 52/8 (по прямому запросу).
local ICON_SIZE = 42
local ICON_GAP = 6
-- Иконки идут В РЯД, не больше стольких в строке; следующая строка
-- растёт вверх над первой.
local ICONS_PER_ROW = 3

--------------------------------------------------------------------------------
-- КАРКАС
--------------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "BuffBar"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 12
gui.Parent = playerGui

local bar = Instance.new("Frame")
bar.Name = "Bar"
-- СПРАВА СНИЗУ (по прямому запросу). Растёт ВВЕРХ от нижнего края —
-- новые иконки не должны наезжать на хотбар, который тоже внизу по
-- центру, а слева-снизу-вверх не пересекается с ним при любой ширине.
bar.AnchorPoint = Vector2.new(1, 1)
bar.Position = UDim2.new(1, -12, 1, -18)
bar.Size = UDim2.fromOffset(ICON_SIZE * ICONS_PER_ROW + ICON_GAP * (ICONS_PER_ROW - 1), 0)
bar.AutomaticSize = Enum.AutomaticSize.Y
bar.BackgroundTransparency = 1
bar.Parent = gui

-- СЕТКА ВМЕСТО СТОЛБЦА (по прямому запросу "не сверху вниз, а в ряд,
-- максимум три"). StartCorner = BottomRight: первая иконка — в правом
-- нижнем углу, следующие встают левее, четвёртая начинает новую строку
-- ВЫШЕ первой, так что панель по-прежнему растёт от нижнего края вверх и
-- не наезжает на хотбар.
local layout = Instance.new("UIGridLayout")
layout.CellSize = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
layout.CellPadding = UDim2.fromOffset(ICON_GAP, ICON_GAP)
layout.FillDirection = Enum.FillDirection.Horizontal
layout.FillDirectionMaxCells = ICONS_PER_ROW
layout.StartCorner = Enum.StartCorner.BottomRight
layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = bar

-- Подсказка одна на всю панель: показывать по одной на иконку значило бы
-- держать десяток невидимых фреймов без всякой пользы.
local tooltip = Instance.new("Frame")
tooltip.Name = "Tooltip"
tooltip.AnchorPoint = Vector2.new(1, 1)
tooltip.Size = UDim2.fromOffset(240, 78)
tooltip.BackgroundColor3 = Color3.fromRGB(25, 27, 29)
tooltip.BackgroundTransparency = 0.1
tooltip.BorderSizePixel = 0
tooltip.Visible = false
tooltip.ZIndex = 20
tooltip.Parent = gui

local tooltipCorner = Instance.new("UICorner")
tooltipCorner.CornerRadius = UDim.new(0, 8)
tooltipCorner.Parent = tooltip

local tooltipStroke = Instance.new("UIStroke")
tooltipStroke.Color = Color3.fromRGB(255, 255, 255)
tooltipStroke.Transparency = 0.75
tooltipStroke.Thickness = 1
tooltipStroke.Parent = tooltip

local tooltipTitle = Instance.new("TextLabel")
tooltipTitle.Name = "Title"
tooltipTitle.Position = UDim2.fromOffset(10, 8)
tooltipTitle.Size = UDim2.new(1, -20, 0, 20)
tooltipTitle.BackgroundTransparency = 1
tooltipTitle.Font = Enum.Font.GothamBold
tooltipTitle.TextSize = 15
tooltipTitle.TextXAlignment = Enum.TextXAlignment.Left
tooltipTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
tooltipTitle.ZIndex = 21
tooltipTitle.Parent = tooltip

local tooltipBody = Instance.new("TextLabel")
tooltipBody.Name = "Body"
tooltipBody.Position = UDim2.fromOffset(10, 30)
tooltipBody.Size = UDim2.new(1, -20, 1, -38)
tooltipBody.BackgroundTransparency = 1
tooltipBody.Font = Enum.Font.Gotham
tooltipBody.TextSize = 13
tooltipBody.TextWrapped = true
tooltipBody.TextXAlignment = Enum.TextXAlignment.Left
tooltipBody.TextYAlignment = Enum.TextYAlignment.Top
tooltipBody.TextColor3 = Color3.fromRGB(215, 215, 225)
tooltipBody.ZIndex = 21
tooltipBody.Parent = tooltip

local shownFor = nil

local function hideTooltip()
	shownFor = nil
	tooltip.Visible = false
end

local function showTooltip(icon, title, body)
	shownFor = icon
	tooltipTitle.Text = title
	tooltipBody.Text = body
	-- Иконки теперь стоят В РЯД, поэтому подсказка открывается НАД
	-- иконкой (правым краем по правому краю иконки), а не слева от неё —
	-- слева стоят соседние иконки, и подсказка бы их закрывала.
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local x = icon.AbsolutePosition.X + icon.AbsoluteSize.X
	local y = icon.AbsolutePosition.Y - 8
	x = math.clamp(x, tooltip.AbsoluteSize.X + 8, viewport.X - 8)
	y = math.max(y, tooltip.AbsoluteSize.Y + 8)
	tooltip.Position = UDim2.fromOffset(x, y)
	tooltip.Visible = true
end

-- На телефоне наведения нет, поэтому подсказка открывается нажатием и
-- закрывается повторным нажатием или тапом по другой иконке.
local function bindTooltip(icon, getTitle, getBody)
	icon.MouseEnter:Connect(function()
		if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then return end
		showTooltip(icon, getTitle(), getBody())
	end)
	icon.MouseLeave:Connect(function()
		if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then return end
		if shownFor == icon then hideTooltip() end
	end)
	icon.Activated:Connect(function()
		if shownFor == icon then
			hideTooltip()
		else
			showTooltip(icon, getTitle(), getBody())
		end
	end)
end

--------------------------------------------------------------------------------
-- ИКОНКИ
--------------------------------------------------------------------------------
-- [id] = { Button, Timer, Spec }
local icons = {}

local function makeIcon(id, spec, order)
	local button = Instance.new("ImageButton")
	button.Name = "Buff_" .. id
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
	button.BackgroundColor3 = Color3.fromRGB(25, 27, 29)
	button.BackgroundTransparency = 0.15
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Image = "" -- ← сюда свой ассет иконки
	button.ScaleType = Enum.ScaleType.Fit
	button.Parent = bar

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Name = "Accent"
	stroke.Thickness = 2
	stroke.Color = spec.Color or Color3.fromRGB(200, 200, 200)
	stroke.Parent = button

	-- Запасная подпись: пока Image пустой, иконка всё равно читается.
	-- Клиент прячет её сам, как только подставлен ассет.
	local glyph = Instance.new("TextLabel")
	glyph.Name = "Glyph"
	glyph.Size = UDim2.fromScale(1, 0.6)
	glyph.BackgroundTransparency = 1
	glyph.Font = Enum.Font.GothamBold
	glyph.TextScaled = true
	glyph.Text = spec.IconText or "?"
	glyph.TextColor3 = spec.Color or Color3.fromRGB(255, 255, 255)
	glyph.Parent = button

	local timer = Instance.new("TextLabel")
	timer.Name = "Timer"
	timer.AnchorPoint = Vector2.new(0.5, 1)
	timer.Position = UDim2.new(0.5, 0, 1, -2)
	timer.Size = UDim2.new(1, 0, 0, 12)
	timer.BackgroundTransparency = 1
	timer.Font = Enum.Font.GothamBold
	timer.TextSize = 10
	timer.TextColor3 = Color3.fromRGB(255, 255, 255)
	timer.TextStrokeTransparency = 0.6
	timer.Text = ""
	timer.Parent = button

	-- Появление: "выпрыгивает" из точки. Позицию в сетке задаёт
	-- UIGridLayout, двигать Position бесполезно — поэтому анимируем масштаб.
	local popScale = Instance.new("UIScale")
	popScale.Scale = 0.2
	popScale.Parent = button
	TweenService:Create(popScale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()

	local entry = { Button = button, Timer = timer, Glyph = glyph, Spec = spec }
	bindTooltip(button, function()
		return entry.Spec.DisplayName or id
	end, function()
		return entry.Spec.Description or ""
	end)
	icons[id] = entry
	return entry
end

local function removeIcon(id)
	local entry = icons[id]
	if not entry then return end
	icons[id] = nil
	if shownFor == entry.Button then hideTooltip() end
	local tween = TweenService:Create(entry.Button, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
	})
	local popScale = entry.Button:FindFirstChildOfClass("UIScale")
	if popScale then
		TweenService:Create(popScale, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.2 }):Play()
	end
	tween.Completed:Connect(function()
		if entry.Button.Parent then entry.Button:Destroy() end
	end)
	tween:Play()
end

local function formatSeconds(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	if seconds >= 60 then
		return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
	end
	return ("%ds"):format(seconds)
end

--------------------------------------------------------------------------------
-- СБОРКА СПИСКА ЭФФЕКТОВ
--------------------------------------------------------------------------------
local activeBuffs = {}     -- последний снимок баффов от сервера
local currentWeather = nil -- текущее погодное событие (см. подписку ниже)

-- Цвета по Id события (см. Config.WeatherEvents.Events) — там самих цветов
-- нет, только AnnounceText/DisplayName, поэтому подбираем по смыслу.
-- Яркие, читаемые версии цвета каждого ивента — не буквальный тёмный
-- "дождевой синий", специально высветлено для контраста с тёмным HUD.
-- Перенесено из удалённого SafeZoneHud вместе с самой подписью погоды.
local WEATHER_COLORS = {
	Night = Color3.fromRGB(165, 185, 255),
	Rain = Color3.fromRGB(110, 190, 255),
	Thunderstorm = Color3.fromRGB(150, 220, 255),
	BloodMoon = Color3.fromRGB(255, 90, 90),
	SolarEclipse = Color3.fromRGB(195, 130, 255),
}

-- DisplayName лежит в Config.WeatherEvents.Events — это МАССИВ, а не
-- словарь по Id, поэтому ищем перебором. Сервер шлёт DisplayName и сам,
-- это запасной путь на случай старого payload.
local function weatherDisplayName(id)
	local events = Config.WeatherEvents and Config.WeatherEvents.Events
	for _, event in events or {} do
		if event.Id == id then return event.DisplayName end
	end
	return id
end

local function collectEffects()
	local effects = {}

	for _, entry in activeBuffs do
		local info = Config.Buffs[entry.Kind] or {}
		table.insert(effects, {
			Id = "Buff_" .. entry.Kind,
			DisplayName = info.DisplayName or entry.Label or entry.Kind,
			Description = info.Description or "",
			IconText = info.IconText,
			Color = info.Color,
			SecondsLeft = entry.SecondsLeft,
		})
	end

	-- Сейв-зона: CombatService переиспользует свою же боевую проверку
	-- isPositionSafe (своя база + зона сдачи в банке) и раз в 0.5с пишет
	-- результат в этот атрибут игрока (см. startSafeZoneReplication).
	if player:GetAttribute("InSafeZone") == true then
		table.insert(effects, {
			Id = "SafeZone",
			DisplayName = "SAFE ZONE",
			Description = "You are protected here. Other players cannot attack you or steal your cart inside a safe zone.",
			IconText = "SZ",
			Color = Color3.fromRGB(120, 220, 160),
		})
	end

	-- Погода: реальный payload WeatherService (см.
	-- WeatherService.publicEventPayload) — { Id, DisplayName, EndsAt,
	-- AnnounceText }. "Clear" присылается тоже (сервер шлёт таблицу, а не
	-- nil, специально ради этого), но чистое небо в панель не выносим —
	-- оно не эффект, показывать нечего.
	local weather = currentWeather
	if typeof(weather) == "table" and weather.Id and weather.Id ~= "Clear" then
		local secondsLeft = typeof(weather.EndsAt) == "number"
			and math.max(0, weather.EndsAt - os.time())
			or nil
		table.insert(effects, {
			Id = "Weather_" .. weather.Id,
			DisplayName = weather.DisplayName or weatherDisplayName(weather.Id),
			-- AnnounceText — тот же текст, что игрок уже видел объявлением
			-- в чат при старте события: он и есть готовое человеческое
			-- описание "что это значит", отдельного текста заводить не
			-- пришлось.
			Description = weather.AnnounceText or "A weather event is active. It changes which ore and mutations you find.",
			IconText = "WX",
			Color = WEATHER_COLORS[weather.Id] or Color3.fromRGB(150, 190, 255),
			SecondsLeft = secondsLeft,
		})
	end

	return effects
end

local function refresh()
	local effects = collectEffects()
	local seen = {}

	for order, effect in effects do
		seen[effect.Id] = true
		local entry = icons[effect.Id]
		if not entry then
			entry = makeIcon(effect.Id, effect, order)
		else
			entry.Spec = effect
			entry.Button.LayoutOrder = order
		end
		entry.Timer.Text = effect.SecondsLeft and formatSeconds(effect.SecondsLeft) or ""
		-- Ассет подставлен — прячем запасную подпись, иначе буквы
		-- просвечивали бы поверх картинки.
		entry.Glyph.Visible = entry.Button.Image == ""
		-- Подсказка открыта прямо сейчас — обновляем и её, иначе таймер в
		-- ней замер бы до закрытия.
		if shownFor == entry.Button then
			tooltipTitle.Text = effect.DisplayName
			tooltipBody.Text = effect.Description
		end
	end

	for id in icons do
		if not seen[id] then removeIcon(id) end
	end
end

--------------------------------------------------------------------------------
-- ИСТОЧНИКИ
--------------------------------------------------------------------------------
task.spawn(function()
	local remote = ReplicatedStorage.Shared:WaitForChild("BuffState", 20)
	if not remote then
		-- Не фатально: сейв-зона и погода показываются и без этого канала.
		warn("[BuffBar] RemoteEvent BuffState не появился — иконки баффов из жеод показываться не будут.")
		return
	end
	remote.OnClientEvent:Connect(function(list)
		if typeof(list) ~= "table" then return end
		activeBuffs = list
		refresh()
	end)
end)

player:GetAttributeChangedSignal("InSafeZone"):Connect(refresh)

-- Погода: тот же канал, что слушает WeatherFX. Payload может быть таблицей
-- с описанием события либо nil (ясно) — приводим к имени события.
task.spawn(function()
	local weatherRemote = ReplicatedStorage.Shared:WaitForChild("WeatherEvent", 20)
	if not weatherRemote then return end
	weatherRemote.OnClientEvent:Connect(function(payload)
		-- Payload — таблица { Id, DisplayName, EndsAt, AnnounceText } (см.
		-- WeatherService.publicEventPayload); сервер шлёт её и для "Clear",
		-- collectEffects сам решает, что Clear не показываем.
		currentWeather = typeof(payload) == "table" and payload or nil
		refresh()
	end)
end)

refresh()

--------------------------------------------------------------------------------
-- УБОРКА СТАРЫХ ТЕКСТОВЫХ ПОДПИСЕЙ (по прямому запросу: "надписи safe zone,
-- thunderstorm удали — они уже есть прямоугольниками справа снизу").
--
-- В коде проекта этих подписей давно нет (SafeZoneHud.client.lua удалён),
-- но default.project.json держит $ignoreUnknownInstances у
-- StarterPlayerScripts — Rojo НЕ удаляет из места скрипты, которых больше
-- нет в src. Старый SafeZoneHud так и оставался в Studio и продолжал
-- рисовать надписи. Здесь: гасим такой скрипт, если он есть, и прячем его
-- текстовые подписи. Лучше всё равно удалить его руками из
-- StarterPlayer/StarterPlayerScripts.
--------------------------------------------------------------------------------
local LEGACY_SCRIPT_NAMES = { SafeZoneHud = true }
local LEGACY_GUI_NAMES = { SafeZoneHud = true, SafeZoneGui = true, WeatherHud = true }
local LEGACY_LABEL_NAMES = { WeatherLabel = true, SafeZoneLabel = true }

local statusTexts = { ["SAFE ZONE"] = true }
for _, event in (Config.WeatherEvents and Config.WeatherEvents.Events) or {} do
	if event.DisplayName then statusTexts[event.DisplayName:upper()] = true end
end

local function isLegacyStatusLabel(label)
	if label:IsDescendantOf(gui) then return false end
	if LEGACY_LABEL_NAMES[label.Name] then return true end
	local text = (label.ContentText ~= "" and label.ContentText or label.Text):upper()
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	return statusTexts[text] == true
end

local function hideLegacy(instance)
	if not instance.Parent then return end
	if instance:IsA("ScreenGui") and LEGACY_GUI_NAMES[instance.Name] then
		instance.Enabled = false
	elseif instance:IsA("TextLabel") and isLegacyStatusLabel(instance) then
		-- Прячем только подписи в правом нижнем углу — та же надпись в
		-- другом месте (например, в меню) нас не касается.
		local camera = workspace.CurrentCamera
		local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
		local position = instance.AbsolutePosition
		if LEGACY_LABEL_NAMES[instance.Name] or (position.X > viewport.X * 0.5 and position.Y > viewport.Y * 0.5) then
			instance.Visible = false
		end
	end
end

local playerScripts = player:FindFirstChild("PlayerScripts")
if playerScripts then
	for _, child in playerScripts:GetChildren() do
		if child:IsA("LocalScript") and LEGACY_SCRIPT_NAMES[child.Name] then
			child.Enabled = false
			warn("[BuffBar] Найден устаревший скрипт " .. child.Name .. " — отключён. Удали его из StarterPlayer/StarterPlayerScripts в Studio.")
		end
	end
end
for _, descendant in playerGui:GetDescendants() do
	hideLegacy(descendant)
end
playerGui.DescendantAdded:Connect(function(descendant)
	task.defer(hideLegacy, descendant)
	if descendant:IsA("TextLabel") then
		descendant:GetPropertyChangedSignal("Text"):Connect(function()
			hideLegacy(descendant)
		end)
	end
end)
