--------------------------------------------------------------------------------
-- IconBounce
-- Периодически (не всё время, со случайной паузой) иконка подпрыгивает и
-- увеличивается, затем возвращается на исходное место и размер — живой,
-- но ненавязчивый акцент на HUD-иконках (монетка, ребёрт, кирка и т.п.).
--
-- Трогает ТОЛЬКО саму иконку (обычно дочерний ImageLabel "Icon" внутри
-- пилюли/слота) — не родительскую пилюлю/слот целиком, чтобы не сдвигать
-- текст рядом с ней.
--------------------------------------------------------------------------------

local TweenService = game:GetService("TweenService")

local IconBounce = {}

-- options (все не обязательны):
--   MinDelay/MaxDelay — пауза между прыжками, секунды (случайная в этом
--                       диапазоне каждый раз, чтобы разные иконки не
--                       прыгали синхронно одной толпой)
--   Scale             — во сколько раз увеличивается иконка на пике прыжка
--   Lift              — на сколько пикселей иконка дополнительно
--                       поднимается вверх во время прыжка
function IconBounce.Apply(icon, options)
	if not icon or not icon:IsA("GuiObject") then return end
	options = options or {}
	local minDelay = options.MinDelay or 4
	local maxDelay = options.MaxDelay or 9
	local scale = options.Scale or 1.25
	local lift = options.Lift or 10

	local baseSize = icon.Size
	local basePosition = icon.Position
	local upSize = UDim2.new(
		baseSize.X.Scale * scale, baseSize.X.Offset * scale,
		baseSize.Y.Scale * scale, baseSize.Y.Offset * scale
	)
	local upPosition = basePosition - UDim2.fromOffset(0, lift)

	task.spawn(function()
		while icon.Parent do
			task.wait(minDelay + math.random() * (maxDelay - minDelay))
			if not icon.Parent then break end

			-- Резкий прыжок вверх с небольшим "перескоком" (Back) —
			-- ощущается как "подпрыгнула", а не просто выросла на месте.
			local up = TweenService:Create(icon, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = upSize,
				Position = upPosition,
			})
			up:Play()
			up.Completed:Wait()
			if not icon.Parent then break end

			-- Возврат на место с лёгким пружинистым "приземлением" (Bounce).
			local down = TweenService:Create(icon, TweenInfo.new(0.22, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {
				Size = baseSize,
				Position = basePosition,
			})
			down:Play()
			down.Completed:Wait()
		end
	end)
end

-- Плавная НЕПРЕРЫВНАЯ "дыхательная" пульсация размера — растёт и
-- уменьшается обратно по кругу, без пауз между циклами (в отличие от
-- IconBounce.Apply выше, которая прыгает РЕДКО и со случайной паузой).
-- Для элементов, которые должны постоянно мягко привлекать взгляд —
-- например, кнопка-книга коллекции.
--
-- options (все не обязательны):
--   Scale    — во сколько раз увеличивается элемент в пике вдоха
--   Duration — сколько секунд идёт один "вдох" (столько же — "выдох")
function IconBounce.ApplyPulse(icon, options)
	if not icon or not icon:IsA("GuiObject") then return end
	options = options or {}
	local scale = options.Scale or 1.08
	local duration = options.Duration or 1.3

	local baseSize = icon.Size
	local upSize = UDim2.new(
		baseSize.X.Scale * scale, baseSize.X.Offset * scale,
		baseSize.Y.Scale * scale, baseSize.Y.Offset * scale
	)

	task.spawn(function()
		while icon.Parent do
			-- Sine — самое плавное ускорение/торможение из встроенных
			-- стилей, без "перескока" (в отличие от Back/Bounce в
			-- IconBounce.Apply) — тут нужен именно плавный вдох-выдох.
			local up = TweenService:Create(icon, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Size = upSize,
			})
			up:Play()
			up.Completed:Wait()
			if not icon.Parent then break end

			local down = TweenService:Create(icon, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Size = baseSize,
			})
			down:Play()
			down.Completed:Wait()
		end
	end)
end

return IconBounce
