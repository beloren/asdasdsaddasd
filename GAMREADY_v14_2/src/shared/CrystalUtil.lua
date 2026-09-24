--------------------------------------------------------------------------------
-- CrystalUtil
-- Кристалл может быть простым BasePart (плейсхолдер по умолчанию, см.
-- PlaceholderFactory.Crystal) ИЛИ Model с любым содержимым внутри (доп.
-- части, ParticleEmitter, PointLight, что угодно) — во втором случае
-- обязателен PrimaryPart с именем "Root": именно эта часть физически
-- крепится/двигается/сталкивается, а всё остальное внутри модели должно
-- быть приварено к ней (WeldConstraint, как Wall/Wheel у тележки) — тогда
-- оно катается вместе с Root само, без единой строчки отдельного кода.
--
-- GetRoot() — единая точка правды: возвращает именно ту часть, с которой
-- реально работает вся остальная игра (Anchored/CanCollide/Touched/
-- AssemblyLinearVelocity/Weld) — CrystalService/CartService/BankService
-- используют её вместо прямого обращения к самому кристаллу, чтобы не
-- дублировать эту проверку по всему проекту.
--------------------------------------------------------------------------------

local CrystalUtil = {}

function CrystalUtil.GetRoot(crystal)
	if crystal:IsA("BasePart") then
		return crystal
	end
	local root = crystal.PrimaryPart or crystal:FindFirstChild("Root", true)
	assert(root, "Кристалл-Model обязан иметь PrimaryPart/часть 'Root': " .. crystal:GetFullName())
	return root
end

return CrystalUtil
