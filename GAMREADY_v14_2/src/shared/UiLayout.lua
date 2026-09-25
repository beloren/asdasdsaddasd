--------------------------------------------------------------------------------
-- UiLayout (v20.16) — ДВЕ ВЕРСИИ ИНТЕРФЕЙСА: ПК и ТЕЛЕФОН.
--
-- Профиль устройства:
--   "Phone"   — сенсорный экран без клавиатуры, короткая сторона ≤ PhoneMaxShortSide;
--   "Tablet"  — сенсорный без клавиатуры, экран больше;
--   "Desktop" — всё остальное (ПК, ноутбук, консоль).
-- Config.UiLayout.ForceProfile = "Phone" — принудительно (проверка в Studio).
--
-- Что делает версия под профиль (клиент ResponsiveUi.client.lua):
--   1) Раскладка: Config.UiLayout.Overrides[профиль]["Экран/Элемент/…"] =
--      { свойства } — позиции/якоря/размеры/направление списков для этого
--      устройства. Так на телефоне HUD уходит из зоны джойстика и кнопки
--      прыжка, панель снаряжения ложится в ряд над хотбаром и т.д.
--   2) Масштаб: каждый верхний элемент каждого ScreenGui получает UIScale =
--      анимация × подгонка. Подгонка = «база профиля» (HUD на телефоне
--      мельче) × «влезает на экран целиком» (окно или плашка никогда не
--      вылезают за безопасную зону экрана, с отступом Margin).
--
-- Модуль чистый (без сервисов на уровне модуля) — его же использует
-- превью tools/dev/preview_ui.luau, чтобы проверять телефонную раскладку.
--------------------------------------------------------------------------------
local Config = require(script.Parent.Config)

local UiLayout = {}

local function cfg()
	return Config.UiLayout or {}
end

-- Профиль по параметрам устройства (чистая функция).
function UiLayout.ProfileFor(viewport, touchEnabled, keyboardEnabled)
	local forced = cfg().ForceProfile
	if forced == "Phone" or forced == "Tablet" or forced == "Desktop" then
		return forced
	end
	local short = math.min(viewport.X, viewport.Y)
	if touchEnabled and not keyboardEnabled then
		return short <= (cfg().PhoneMaxShortSide or 600) and "Phone" or "Tablet"
	end
	return "Desktop"
end

-- Профиль на клиенте (читает UserInputService и камеру).
function UiLayout.Profile()
	local ok, UserInputService = pcall(game.GetService, game, "UserInputService")
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	if not ok then return UiLayout.ProfileFor(viewport, false, true) end
	local touch = UserInputService.TouchEnabled
	local keyboard = UserInputService.KeyboardEnabled
	-- Новое API Roblox: предпочитаемый ввод (если доступно).
	local preferredOk, preferred = pcall(function() return UserInputService.PreferredInput end)
	if preferredOk and preferred ~= nil and typeof(preferred) == "EnumItem" then
		if preferred.Name == "Touch" then
			touch, keyboard = true, false
		elseif preferred.Name == "KeyboardAndMouse" then
			keyboard = true
		end
	end
	return UiLayout.ProfileFor(viewport, touch, keyboard)
end

function UiLayout.Margin(profile)
	local margins = cfg().Margin or {}
	return margins[profile] or 10
end

-- База масштаба HUD для профиля (зависит от короткой стороны экрана).
function UiLayout.HudScale(profile, bounds)
	local spec = (cfg().HudScale or {})[profile] or { Ref = 720, Min = 0.8, Max = 1 }
	local short = math.min(bounds.X, bounds.Y)
	return math.clamp(short / (spec.Ref or 720), spec.Min or 0.5, spec.Max or 1)
end

local function fullScreen(element)
	return element.Size.X.Scale >= 0.9 and element.Size.Y.Scale >= 0.9
end

-- Нужно ли управлять масштабом этого верхнего элемента.
function UiLayout.Manageable(screenName, element)
	if not element:IsA("GuiObject") then return false end
	if element:GetAttribute("NoAutoFit") then return false end
	local skip = cfg().Skip or {}
	if skip[screenName] or skip[screenName .. "/" .. element.Name] then return false end
	return not fullScreen(element)
end

-- «Окно» — модальная панель по центру экрана; всё прочее — HUD.
function UiLayout.IsWindow(element, natural)
	if element:GetAttribute("UiWindow") then return true end
	return element.AnchorPoint.X == 0.5 and element.Position.X.Scale == 0.5
		and natural.X >= 300 and natural.Y >= 180
end

-- Естественный размер элемента (без UIScale) в пикселях экрана.
function UiLayout.NaturalSize(element, bounds)
	return Vector2.new(
		element.Size.X.Scale * bounds.X + element.Size.X.Offset,
		element.Size.Y.Scale * bounds.Y + element.Size.Y.Offset
	)
end

-- Точка якоря элемента относительно ScreenGui (UIScale масштабирует вокруг неё).
function UiLayout.AnchorPosition(element, bounds)
	return Vector2.new(
		element.Position.X.Scale * bounds.X + element.Position.X.Offset,
		element.Position.Y.Scale * bounds.Y + element.Position.Y.Offset
	)
end

-- Максимальный масштаб k ≤ base, при котором элемент целиком на экране.
function UiLayout.Fit(anchorPos, natural, anchorPoint, bounds, margin, base)
	local k = base
	local function limit(space, part)
		if part > 0.5 then
			k = math.min(k, space / part)
		end
	end
	local axes = {
		{ anchorPos.X, natural.X, anchorPoint.X, bounds.X },
		{ anchorPos.Y, natural.Y, anchorPoint.Y, bounds.Y },
	}
	for _, axis in axes do
		local p, size, ap, b = axis[1], axis[2], axis[3], axis[4]
		if p >= 0 and p <= b then
			limit(p - margin, ap * size)
			limit(b - margin - p, (1 - ap) * size)
		else
			-- Элемент за краем (выезжающая анимация) — только «влезает по размеру».
			limit(b - margin * 2, size)
		end
	end
	return math.clamp(k, cfg().MinScale or 0.3, math.max(base, 0.01))
end

-- Полный расчёт подгонки для верхнего элемента экрана.
--   extraNatural — (необяз.) измеренный размер для AutomaticSize-элементов.
function UiLayout.FitScale(element, profile, bounds, extraNatural)
	local natural = UiLayout.NaturalSize(element, bounds)
	if extraNatural then
		natural = Vector2.new(math.max(natural.X, extraNatural.X), math.max(natural.Y, extraNatural.Y))
	end
	local window = UiLayout.IsWindow(element, natural)
	local base = window and (((cfg().WindowMaxScale or {})[profile]) or 1) or UiLayout.HudScale(profile, bounds)
	local custom = element:GetAttribute("UiScale_" .. profile)
	if typeof(custom) == "number" then base = custom end
	return UiLayout.Fit(UiLayout.AnchorPosition(element, bounds), natural, element.AnchorPoint, bounds, UiLayout.Margin(profile), base), window
end

-- Найти объект по пути внутри экрана: "HudGui", "GearBar/UIListLayout".
local function resolve(root, path)
	local node = root
	for part in string.gmatch(path, "[^/]+") do
		if not node then return nil end
		node = node:FindFirstChild(part) or (part:match("^UI") and node:FindFirstChildOfClass(part)) or nil
	end
	return node
end

-- Применить раскладку профиля к экрану. Каждый объект получает её один раз
-- (атрибут UiLayoutProfile), поэтому можно звать сколько угодно раз —
-- объекты, появившиеся позже, догонятся на следующем проходе.
function UiLayout.ApplyOverrides(screenGui, profile)
	local overrides = ((cfg().Overrides or {})[profile]) or {}
	local prefix = screenGui.Name .. "/"
	for path, props in overrides do
		if path:sub(1, #prefix) == prefix then
			local node = resolve(screenGui, path:sub(#prefix + 1))
			if node and node:GetAttribute("UiLayoutProfile") ~= profile then
				node:SetAttribute("UiLayoutProfile", profile)
				for key, value in props do
					if key:sub(1, 1) == "@" then
						node:SetAttribute(key:sub(2), value) -- «@Имя» — атрибут, а не свойство
					else
						pcall(function() node[key] = value end)
						if key == "Position" then
							-- CinematicHud возвращает HUD после катсцены сюда,
							-- а не на запомненную «ПК-позицию».
							node:SetAttribute("LayoutPosition", value)
						end
					end
				end
			end
		end
	end
end

return UiLayout
