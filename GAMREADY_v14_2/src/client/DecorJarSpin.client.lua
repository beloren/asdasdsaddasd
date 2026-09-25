--------------------------------------------------------------------------------
-- DecorJarSpin (LocalScript) v20.22 — руда в банке на базе крутится и чуть
-- покачивается вверх-вниз.
--
-- Сервер (BaseDecorService:_refreshJar) кладёт в банку уменьшенную модель
-- "JarOre" с тегом DecorJarOre и атрибутами SpinSpeed / BobHeight. Крутим
-- ЛОКАЛЬНО: серверное вращение гнало бы CFrame всех деталей по сети каждый кадр.
--------------------------------------------------------------------------------
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local TAG = "DecorJarOre"
local tracked = {} -- [model] = { Base = CFrame, Phase = number }

local function track(model)
	if not model:IsA("Model") then return end
	tracked[model] = { Base = model:GetPivot(), Phase = math.random() * math.pi * 2 }
end

local function untrack(model)
	tracked[model] = nil
end

for _, model in CollectionService:GetTagged(TAG) do track(model) end
CollectionService:GetInstanceAddedSignal(TAG):Connect(track)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(untrack)

local elapsed = 0
RunService.RenderStepped:Connect(function(dt)
	elapsed += dt
	for model, state in tracked do
		if not model.Parent then
			tracked[model] = nil
			continue
		end
		local speed = tonumber(model:GetAttribute("SpinSpeed")) or 1.2
		local bob = tonumber(model:GetAttribute("BobHeight")) or 0.12
		local base = state.Base
		local offset = Vector3.new(0, math.sin(elapsed * 2 + state.Phase) * bob, 0)
		model:PivotTo(CFrame.new(base.Position + offset) * CFrame.Angles(0, elapsed * speed + state.Phase, 0) * base.Rotation)
	end
end)
