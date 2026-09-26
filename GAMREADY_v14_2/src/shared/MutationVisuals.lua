--------------------------------------------------------------------------------
-- MutationVisuals
-- Общая логика "как визуально применить мутацию к куску руды" (см.
-- Config.Mutations) — вынесена в Shared, чтобы ей одинаково пользовались и
-- сервер (CrystalService:Create — настоящая мутация на добытой руде), и
-- клиент (CollectionMenu.client.lua — превью в книге мутаций при наведении/
-- клике на ячейку). Раньше жила только в CrystalService.lua — превью в книге
-- иначе рисовало бы "что-то похожее", а не ТОЧНО то же самое, что видно в
-- игре.
--------------------------------------------------------------------------------

local Config = require(script.Parent.Config)
local CrystalUtil = require(script.Parent.CrystalUtil)
local PlaceholderFactory = require(script.Parent.PlaceholderFactory)

local MutationVisuals = {}

local function brighter(color, amount)
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

local function colorHex(color)
	return ("#%02X%02X%02X"):format(
		math.round(color.R * 255),
		math.round(color.G * 255),
		math.round(color.B * 255)
	)
end

function MutationVisuals.ColoredNames(mutationIds)
	local names = {}
	for _, mutationId in mutationIds or {} do
		local info = Config.Mutations[mutationId]
		if info then
			table.insert(names, ('<font color="%s">%s</font>'):format(
				colorHex(info.Color or Color3.new(1, 1, 1)),
				info.DisplayName:upper()
			))
		end
	end
	return table.concat(names, ' <font color="#FFFFFF">+</font> ')
end

-- Shared overhead-label styling keeps carried and podium crystals visually
-- consistent. No gradient here: the crystal income part uses RichText and must
-- stay green even for mutated crystals.
function MutationVisuals.StyleOverheadLabel(label, mutationIds, baseColor)
	if not label then return end
	require(script.Parent.WorldUi).Restyle(label, "Number", true) -- v20: стиль мирового текста
	label.TextColor3 = (baseColor or Color3.new(1, 1, 1)):Lerp(Color3.new(1, 1, 1), 0.72)
	label.RichText = true
	local oldGradient = label:FindFirstChild("MutationGradient")
	if oldGradient then oldGradient:Destroy() end
end

-- Универсально достаёт CFrame+Size "ограничивающей коробки" куска руды,
-- независимо от того, простой это Part-заглушка или сложная Model из
-- Studio — нужно, чтобы оболочка мутации ровно "садилась" на любую форму.
local function getBounds(crystal)
	if crystal:IsA("BasePart") then
		return crystal.CFrame, crystal.Size
	end
	return crystal:GetBoundingBox()
end

-- Прозрачный куб чуть крупнее самой руды, приваренный поверх (см.
-- Config.Mutations.Frozen/Radiant, Visual = "Shell"/"RainbowShell") — ровно то
-- простое решение, которое и просили: отдельный слой поверх модели, без
-- клонирования её реальной геометрии кусок-в-кусок.
local function addMutationShell(crystal, root, name, scale, transparency, color)
	local cframe, size = getBounds(crystal)
	local shell = Instance.new("Part")
	shell.Name = name
	shell.Shape = Enum.PartType.Block
	shell.Size = size * scale
	shell.CFrame = cframe
	shell.Anchored = root == nil -- для превью (без root — некуда приваривать) якорим саму оболочку
	shell.CanCollide = false
	shell.CanTouch = false
	shell.CanQuery = false
	shell.Massless = true
	shell.Material = Enum.Material.Glass
	shell.Color = color
	shell.Transparency = transparency
	shell.Parent = crystal
	if root then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = shell
		weld.Parent = shell
	end
	return shell
end

-- Общая покраска ВСЕЙ модели целиком в нужный материал+цвет (Molten/Void/
-- Celestial/Rusty — см. Config.Mutations, Visual = "MaterialSwap") —
-- проходим по каждому BasePart (что для одиночного Part-заглушки, что для
-- Model из нескольких кусков — работает одинаково).
local function allParts(crystal)
	local parts = {}
	for _, descendant in crystal:GetDescendants() do
		if descendant:IsA("BasePart") then table.insert(parts, descendant) end
	end
	if crystal:IsA("BasePart") then table.insert(parts, crystal) end
	return parts
end

-- reflectance необязателен — нужен только Golden, чтобы дать металлический
-- блеск без источника света (в тележке до 225 кристаллов, свет на каждый —
-- это прямая потеря кадров).
local function applyMaterialSwap(crystal, material, color, reflectance, targetParts)
	for _, part in targetParts or allParts(crystal) do
		if material then part.Material = material end
		if color then part.Color = color end
		if reflectance then part.Reflectance = reflectance end
	end
end

-- РАЗМЕР (Gigantic/Tiny). Тот же механизм, что уже используется для
-- естественного разброса руды +-8% в PlaceholderFactory.Crystal, поэтому с
-- любым ассетом ведёт себя предсказуемо: Model — через ScaleTo (не ломает
-- сварку деталей), одиночная деталь — прямым Size.
local function applyScale(crystal, factor)
	if not factor or factor <= 0 then return end
	if crystal:IsA("Model") then
		local ok = pcall(function() crystal:ScaleTo(crystal:GetScale() * factor) end)
		if ok then return end
	end
	for _, part in allParts(crystal) do
		part.Size = part.Size * factor
	end
end

-- ЧАСТИЦЫ (Toxic/Electric/Eclipsed). Заготовку отдаёт PlaceholderFactory —
-- там же описано, как подменить её своей.
--
-- ИСТОРИЯ БАГА "мутационные VFX не воспроизводятся": здесь стоял
--     local ok, attachment = pcall(PlaceholderFactory.MutationVfx, vfxName)
--     if not ok or not attachment then return end
-- а внутри MutationVfx — assert("... must be an Attachment"). Стоило
-- положить в Assets не голый Attachment, а Part/Model с эффектом внутри
-- (как их и хранят в Studio), assert бросал ошибку, pcall её ГЛОТАЛ, и
-- функция молча выходила: ни частиц, ни единого предупреждения в консоли.
-- Теперь PlaceholderFactory сам разбирает любую обёртку, а ошибку мы
-- логируем, а не прячем.
local function applyParticles(crystal, root, vfxName, color)
	local host = root or (crystal:IsA("BasePart") and crystal) or CrystalUtil.GetRoot(crystal)
	if not host then
		warn(("[MutationVisuals] Нет корневой детали для мутации %s - частицы не к чему прикрепить."):format(tostring(vfxName)))
		return
	end

	local ok, attachment = pcall(PlaceholderFactory.MutationVfx, vfxName)
	if not ok then
		warn(("[MutationVisuals] Не удалось собрать VFX \"%s\": %s"):format(tostring(vfxName), tostring(attachment)))
		return
	end
	if not attachment then
		warn(("[MutationVisuals] VFX \"%s\" не найден ни в ReplicatedStorage/Assets (MutationVFX_%s), ни среди встроенных заготовок."):format(tostring(vfxName), tostring(vfxName)))
		return
	end

	attachment.Name = "Mutation_" .. tostring(vfxName)

	local emitterCount = 0
	for _, emitter in attachment:GetDescendants() do
		if emitter:IsA("ParticleEmitter") then
			emitterCount += 1
			if color then emitter.Color = ColorSequence.new(color) end
			-- Мутационный эффект должен идти НЕПРЕРЫВНО, пока руда
			-- существует. Если автор ассета настроил эмиттер под разовый
			-- :Emit() (Rate = 0), при обычном Enabled = true он не покажет
			-- ровно ничего — поэтому даём ему минимальный поток и один
			-- стартовый залп, вместо того чтобы молча ничего не показать.
			if emitter.Rate <= 0 then
				emitter.Rate = 5
				emitter:Emit(math.max(1, math.floor(tonumber(emitter:GetAttribute("EmitCount")) or 6)))
			end
			emitter.Enabled = true
		end
	end
	if emitterCount == 0 then
		warn(("[MutationVisuals] VFX \"%s\" не содержит ни одного ParticleEmitter - эффект будет невидим."):format(tostring(vfxName)))
	end

	attachment.Parent = host
end

-- МЕРЦАНИЕ (Glitched). Прозрачность и оттенок дёргаются рывками, как
-- испорченный сигнал. Цикл останавливается сам, как только руду уничтожили —
-- проверяется по crystal.Parent, ровно как у радужной оболочки ниже.
local function animateFlicker(crystal, color, interval, targetParts)
	local parts = targetParts or allParts(crystal)
	local base = {}
	for _, part in parts do base[part] = part.Transparency end
	task.spawn(function()
		while crystal.Parent do
			local glitched = math.random() < 0.35
			for _, part in parts do
				if part.Parent then
					part.Transparency = glitched and math.min(0.85, (base[part] or 0) + 0.55) or (base[part] or 0)
					part.Color = glitched and Color3.fromHSV(math.random(), 0.9, 1) or color
				end
			end
			task.wait(interval or 0.09)
		end
	end)
end

-- ЕДИНЫЙ радужный "клок" — секунда абсолютного времени → оттенок 0..1.
-- И RainbowShell (Radiant), и RainbowSwap (Prismatic) ОБЯЗАНЫ брать цвет
-- ИМЕННО отсюда, а не считать свой независимый счётчик со случайной
-- стартовой фазой (как было раньше) — если обе мутации выпадут на одну
-- руду одновременно (полупрозрачная оболочка Radiant поверх
-- перекрашенного тела Prismatic), два рассинхронизированных таймера с
-- разной скоростью и случайным стартом визуально били друг о друга и
-- читались как резкое мерцание вместо плавного перелива. Единая функция
-- от os.clock() (не task.wait-счётчик — тот плыл бы при лагах, а
-- os.clock() держит скорость стабильной) гарантирует, что ЛЮБОЕ число
-- радужных мутаций на одном куске руды всегда идеально синхронно.
local RAINBOW_CYCLE_SECONDS = 6.25
local function rainbowHueNow()
	return (os.clock() / RAINBOW_CYCLE_SECONDS) % 1
end

-- РАДУГА ПО САМОЙ РУДЕ (Prismatic) — в отличие от RainbowShell у Radiant,
-- где радужная оболочка НАДЕТА поверх, здесь перекрашивается сама модель.
local function animateRainbowSwap(crystal, targetParts)
	local parts = targetParts or allParts(crystal)
	local destroyed = false
	local destroyingConnection = crystal.Destroying:Connect(function()
		destroyed = true
	end)
	task.spawn(function()
		-- CrystalService применяет мутацию до помещения новой руды в тележку.
		-- Раньше цикл видел Parent=nil и завершался ещё до первого кадра.
		while not destroyed and crystal.Parent == nil do
			task.wait()
		end
		while not destroyed and crystal.Parent do
			local color = Color3.fromHSV(rainbowHueNow(), 0.85, 1)
			for _, part in parts do
				if part.Parent then part.Color = color end
			end
			task.wait(0.03)
		end
		destroyingConnection:Disconnect()
	end)
end

-- Радужная оболочка — та же "коробка поверх модели", что у Frozen, но цвет
-- непрерывно бежит по кругу через HSV, а не стоит на месте одним оттенком.
-- Останавливается сама, как только оболочку destroy'ат (продали/сгорела/
-- закрыли превью). Берёт цвет из ТОГО ЖЕ rainbowHueNow(), что и
-- RainbowSwap выше — см. комментарий над функцией про синхронизацию.
local function animateRainbowShell(shell)
	task.spawn(function()
		while shell.Parent do
			shell.Color = Color3.fromHSV(rainbowHueNow(), 0.85, 1)
			task.wait(0.03)
		end
	end)
end

-- root — необязателен: для настоящей руды в игре передавай
-- CrystalUtil.GetRoot(crystal) (мутация приваривается и едет вместе с
-- рудой), для превью в книге мутаций можно не передавать вообще (оболочка
-- сама станет anchored).
function MutationVisuals.Apply(crystal, mutationId, root, targetParts)
	local info = Config.Mutations[mutationId]
	if not info then return end
	if root == nil and not crystal:IsA("BasePart") then
		root = CrystalUtil.GetRoot(crystal)
	end
	if info.Visual == "Shell" then
		addMutationShell(crystal, root, "Mutation_" .. mutationId, info.ShellScale, info.ShellTransparency, info.Color)
	elseif info.Visual == "MaterialSwap" then
		applyMaterialSwap(crystal, info.Material, info.Color, info.Reflectance, targetParts)
	elseif info.Visual == "RainbowShell" then
		local shell = addMutationShell(crystal, root, "Mutation_" .. mutationId, info.ShellScale, info.ShellTransparency, Color3.new(1, 1, 1))
		animateRainbowShell(shell)
	elseif info.Visual == "Scale" then
		applyScale(crystal, info.ScaleFactor) -- ВСЕГДА весь объект целиком — частичный масштаб выглядел бы сломанным, чередование сюда не применяется
	elseif info.Visual == "Particles" then
		applyMaterialSwap(crystal, info.Material, info.Color, info.Reflectance, targetParts)
		applyParticles(crystal, root, info.VfxName, info.Color)
	elseif info.Visual == "Flicker" then
		applyMaterialSwap(crystal, info.Material, info.Color, info.Reflectance, targetParts)
		animateFlicker(crystal, info.Color, info.FlickerInterval, targetParts)
	elseif info.Visual == "RainbowSwap" then
		applyMaterialSwap(crystal, info.Material, Color3.new(1, 1, 1), info.Reflectance, targetParts)
		animateRainbowSwap(crystal, targetParts)
	end
end

-- ЧЕРЕДОВАНИЕ МЕЖДУ ЧАСТЯМИ ПРИ НЕСКОЛЬКИХ МУТАЦИЯХ СРАЗУ — по прямому
-- запросу: "если несколько мутаций то пусть они чередуются друг с другом
-- (типо один парт такой а другой парт такой)". Раньше каждая мутация из
-- списка красила ВСЕ детали подряд — вторая мутация тихо перезаписывала
-- цвет/материал первой на каждой детали, и итог выглядел как "только
-- последняя мутация", а не честная комбинация обеих. Round-robin разбивает
-- ВСЕ детали модели поровну между мутациями по кругу (деталь 1 → мутация
-- 1, деталь 2 → мутация 2, деталь 3 → мутация 1, ...), каждая мутация
-- красит только СВОИ детали — обе видны одновременно, по-честному.
function MutationVisuals.SplitPartsForMutations(crystal, mutationCount)
	local parts = allParts(crystal)
	if mutationCount <= 1 or #parts <= 1 then
		return nil -- одна мутация или один кусок — делить нечего, обычный путь (все детали)
	end
	local groups = {}
	for i = 1, mutationCount do groups[i] = {} end
	for i, part in parts do
		local groupIndex = ((i - 1) % mutationCount) + 1
		table.insert(groups[groupIndex], part)
	end
	return groups
end

return MutationVisuals
