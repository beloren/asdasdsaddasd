--------------------------------------------------------------------------------
-- AmbientGlow
-- Лёгкий "VFX"-эффект позади UI-элемента — БЕЗ настоящего ParticleEmitter
-- (у Roblox его нельзя парентить на GuiObject, только на BasePart/
-- Attachment — это ограничение платформы, не баг). Вместо текстур — простые
-- кружки (Frame + UICorner на полный радиус), чтобы не зависеть ни от
-- какого rbxassetid: гарантированно рендерятся у всех, всегда.
--
-- Искры сами по себе всплывают, разлетаются в стороны/вверх и гаснут —
-- ОДИН общий Heartbeat-цикл двигает все частицы сразу (тот же принцип, что
-- был у старого UIShimmer — не по отдельному подключению на каждую
-- искру).
--------------------------------------------------------------------------------

local RunService = game:GetService("RunService")

local AmbientGlow = {}

local particles = {} -- { Sparkle = Frame, Born = os.clock(), Life = n, StartPosition, DriftX, DriftY }
local driverStarted = false

local function ensureDriver()
	if driverStarted then return end
	driverStarted = true
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for i = #particles, 1, -1 do
			local p = particles[i]
			if not p.Sparkle.Parent then
				table.remove(particles, i)
			else
				local t = (now - p.Born) / p.Life
				if t >= 1 then
					p.Sparkle:Destroy()
					table.remove(particles, i)
				else
					p.Sparkle.Position = p.StartPosition + UDim2.fromOffset(p.DriftX * t, p.DriftY * t)
					-- Парабола: прозрачность 1 (невидимо) на старте и в конце
					-- жизни, 0 (полностью видно) примерно в середине —
					-- получается плавное появление и угасание одной формулой,
					-- без отдельных фаз fade-in/fade-out.
					p.Sparkle.BackgroundTransparency = 1 - (4 * t * (1 - t))
				end
			end
		end
	end)
end

-- Создаёт постоянно тлеющий рой искр внутри container (обычно невидимый
-- Frame, синхронизированный по позиции с целевым элементом — см.
-- CollectionMenu.client.lua, где он держится позади кнопки-книги за счёт
-- более низкого ZIndex, а не через дочерние отношения).
--
-- options (все не обязательны):
--   Colors        — таблица Color3, случайный выбор на каждую искру
--   SpawnMinDelay/SpawnMaxDelay — пауза между рождением новых искр, сек
--   SparkleSize   — диаметр искры, пиксели
--   LifeMin/LifeMax — сколько живёт одна искра, сек
--   SpreadX       — разброс по горизонтали за жизнь искры, пиксели
--   RiseY         — на сколько поднимается вверх за жизнь искры, пиксели
function AmbientGlow.Apply(container, options)
	if not container or not container:IsA("GuiObject") then return end
	options = options or {}
	local colors = options.Colors or {
		Color3.fromRGB(255, 210, 110),
		Color3.fromRGB(255, 235, 180),
		Color3.fromRGB(255, 180, 90),
	}
	local spawnMin = options.SpawnMinDelay or 0.15
	local spawnMax = options.SpawnMaxDelay or 0.4
	local sparkleSize = options.SparkleSize or 6
	local lifeMin = options.LifeMin or 0.9
	local lifeMax = options.LifeMax or 1.5
	local spreadX = options.SpreadX or 34
	local riseY = options.RiseY or 46

	ensureDriver()

	task.spawn(function()
		while container.Parent do
			task.wait(spawnMin + math.random() * (spawnMax - spawnMin))
			if not container.Parent then break end

			local size = container.AbsoluteSize
			-- Пока лэйаут ещё не посчитан (первый кадр), AbsoluteSize может
			-- быть (0,0) — просто спавним из центра в этом случае, не ждём.
			local spreadBoxX = (size.X > 0) and (size.X * 0.3) or 12
			local spreadBoxY = (size.Y > 0) and (size.Y * 0.3) or 12

			local sparkle = Instance.new("Frame")
			sparkle.Name = "Sparkle"
			sparkle.AnchorPoint = Vector2.new(0.5, 0.5)
			sparkle.Size = UDim2.fromOffset(sparkleSize, sparkleSize)
			sparkle.BackgroundColor3 = colors[math.random(1, #colors)]
			sparkle.BorderSizePixel = 0
			sparkle.ZIndex = container.ZIndex
			local startPosition = UDim2.new(
				0.5, (math.random() * 2 - 1) * spreadBoxX,
				0.5, (math.random() * 2 - 1) * spreadBoxY
			)
			sparkle.Position = startPosition
			sparkle.Parent = container
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0) -- полный круг
			corner.Parent = sparkle

			table.insert(particles, {
				Sparkle = sparkle,
				Born = os.clock(),
				Life = lifeMin + math.random() * (lifeMax - lifeMin),
				StartPosition = startPosition,
				DriftX = (math.random() - 0.5) * 2 * spreadX,
				DriftY = -(riseY * (0.6 + math.random() * 0.4)), -- вверх, с разбросом силы
			})
		end
	end)
end

return AmbientGlow
