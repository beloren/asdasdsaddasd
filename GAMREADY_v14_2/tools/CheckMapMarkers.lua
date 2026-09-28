-- CheckMapMarkers: ПРОВЕРКА КАРТЫ. Вставь в Command Bar Studio и нажми Enter.
-- Проверяет всё, что код игры ищет в Workspace (базы, торговец, продажа,
-- гоблины, валуны...), пишет в Output по пунктам [OK] / [!!] и сам чинит
-- мелочи: якорит маркеры, выключает им коллизию и ставит атрибут MapMarker
-- (в игре такие детали прячет сервер, в Studio их видно).
local BASE_SIZE = 240 -- сторона твоей базы (PlotTemplate), для проверки наложений

local function check()

local problems, fixes = 0, 0
local function ok(text) print("[OK]  " .. text) end
local function bad(text) problems += 1 warn("[!!]  " .. text) end
local function markPart(part)
	if not part:IsA("BasePart") then return end
	if not part.Anchored or part.CanCollide or not part:GetAttribute("MapMarker") then fixes += 1 end
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part:SetAttribute("MapMarker", true)
end

print("========== CheckMapMarkers ==========")

-- 1) БАЗЫ: Workspace.PlotOrigins/PlotN (+ PlotNLook)
local origins = workspace:FindFirstChild("PlotOrigins")
if not origins then
	bad("Нет папки Workspace.PlotOrigins - базы встанут кругом по Config.World (радиус PlotRadius).")
else
	local plots = {}
	for _, part in origins:GetChildren() do
		if part:IsA("BasePart") and not part.Name:match("Look$") then
			table.insert(plots, part)
			markPart(part)
			local look = origins:FindFirstChild(part.Name .. "Look")
			if look and look:IsA("BasePart") then
				markPart(look)
			else
				bad(part.Name .. ": нет " .. part.Name .. "Look - база повернётся так, как повёрнута сама деталь " .. part.Name)
			end
		end
	end
	table.sort(plots, function(a, b) return a.Name < b.Name end)
	if #plots == 8 then ok("PlotOrigins: 8 баз") else bad(("PlotOrigins: баз %d (нужно 8 - по числу игроков на сервере)"):format(#plots)) end
	-- Наложения: квадраты BASE_SIZE не должны пересекаться.
	for i = 1, #plots do
		for j = i + 1, #plots do
			local a, b = plots[i], plots[j]
			local d = (Vector3.new(a.CFrame.Position.X, 0, a.CFrame.Position.Z) - Vector3.new(b.CFrame.Position.X, 0, b.CFrame.Position.Z)).Magnitude
			if d < BASE_SIZE then
				bad(("%s и %s: центры в %d стадах, а база %d - базы наложатся"):format(a.Name, b.Name, math.floor(d), BASE_SIZE))
			end
		end
	end
	local heights = {}
	for _, p in plots do heights[math.floor(p.CFrame.Position.Y * 10 + 0.5)] = true end
	local count = 0
	for _ in heights do count += 1 end
	if count > 1 then bad("PlotOrigins: базы на разной высоте - проверь, что все PlotN стоят на одном уровне") else ok("PlotOrigins: все на одной высоте") end
end

-- 2) РЫНОК: модель с атрибутом IsBank (SellZone, Building, MerchantSpot)
local banks = {}
for _, inst in workspace:GetDescendants() do
	if inst:IsA("Model") and inst:GetAttribute("IsBank") then table.insert(banks, inst) end
end
if #banks == 0 then
	bad("Нет модели с атрибутом IsBank - игра поставит банк-заглушку в центр карты")
else
	if #banks > 1 then bad(("Моделей с IsBank - %d, игра возьмёт первую попавшуюся. Оставь одну."):format(#banks)) end
	local bank = banks[1]
	local zone = bank:FindFirstChild("SellZone", true)
	if zone and zone:IsA("BasePart") then ok(("Продажа: SellZone %dx%d"):format(math.floor(zone.Size.X), math.floor(zone.Size.Z))) else bad(bank:GetFullName() .. ": нет Part 'SellZone' - игра упадёт при старте") end
	if bank:FindFirstChild("Building", true) then ok("Продажа: Building есть (туда вылетает проданная руда)") else bad("В модели банка нет 'Building' - руда при продаже полетит в центр модели") end
	local spot = bank:FindFirstChild("MerchantSpot", true)
	if spot and spot:IsA("BasePart") then
		markPart(spot)
		ok("Торговец: MerchantSpot есть")
		local look = bank:FindFirstChild("MerchantSpotLook", true)
		if look and look:IsA("BasePart") then markPart(look) ok("Торговец: смотрит на MerchantSpotLook") else print("[--]  Торговец: MerchantSpotLook нет - будет смотреть от банка наружу") end
	else
		bad("Нет маркера MerchantSpot в модели банка - торговец встанет справа от зоны продажи")
	end
end

-- 3) ГОБЛИНЫ: Workspace.GoblinCamp (Zone + Spawns + Marker)
local camp = workspace:FindFirstChild("GoblinCamp")
if not camp then
	bad("Нет Workspace.GoblinCamp - волны гоблинов не появятся")
else
	local zone = camp:FindFirstChild("Zone")
	if zone and zone:IsA("BasePart") then
		markPart(zone)
		ok(("Гоблины: Zone %dx%d"):format(math.floor(zone.Size.X), math.floor(zone.Size.Z)))
	else
		bad("GoblinCamp: нет Part 'Zone'")
	end
	local spawns = camp:FindFirstChild("Spawns")
	local n = 0
	for _, p in spawns and spawns:GetChildren() or {} do
		if p:IsA("BasePart") then
			n += 1
			markPart(p)
			if zone and zone:IsA("BasePart") then
				local rel = zone.CFrame:PointToObjectSpace(p.CFrame.Position)
				if math.abs(rel.X) > zone.Size.X / 2 or math.abs(rel.Z) > zone.Size.Z / 2 then bad("GoblinCamp: " .. p.Name .. " стоит ВНЕ Zone") end
			end
		end
	end
	if n > 0 then ok(("Гоблины: точек появления %d"):format(n)) else bad("GoblinCamp: в папке Spawns нет ни одной детали") end
	local m = camp:FindFirstChild("Marker")
	if m and m:IsA("BasePart") then markPart(m) ok("Гоблины: Marker (табличка лагеря) есть") else bad("GoblinCamp: нет Part 'Marker' - табличка лагеря не появится") end
end

-- 4) ВАЛУНЫ: Workspace.RubbleBoulderSpawnPoints (16 точек, атрибут Tier 1-9)
local points = workspace:FindFirstChild("RubbleBoulderSpawnPoints")
if not points then
	bad("Нет Workspace.RubbleBoulderSpawnPoints - валуны не появятся")
else
	local n, tiers = 0, {}
	for _, p in points:GetChildren() do
		if p:IsA("BasePart") then
			n += 1
			markPart(p)
			local t = tonumber(p:GetAttribute("Tier"))
			if t then tiers[math.clamp(math.floor(t), 1, 9)] = true end
		end
	end
	if n >= 16 then ok(("Валуны: точек %d"):format(n)) else bad(("Валуны: точек %d, нужно 16"):format(n)) end
	local missing = {}
	for t = 1, 9 do if not tiers[t] then table.insert(missing, t) end end
	if #missing == 0 then ok("Валуны: есть точки всех тиров 1-9") else print("[--]  Валуны: нет атрибута Tier для тиров " .. table.concat(missing, ",") .. " (игра сама раздаст тиры по кругу)") end
end

-- 5) НЕОБЯЗАТЕЛЬНОЕ
local keeper = workspace:FindFirstChild("IslandKeeperMarker", true)
if keeper and keeper:IsA("BasePart") then markPart(keeper) ok("Смотритель островов: IslandKeeperMarker есть") else print("[--]  Нет IslandKeeperMarker - смотритель островов встанет у банка") end
local keeperLook = workspace:FindFirstChild("IslandKeeperMarkerLook", true)
if keeperLook and keeperLook:IsA("BasePart") then markPart(keeperLook) end
if workspace:FindFirstChild("LikeGoalBoard") then ok("Табло лайков: LikeGoalBoard есть") else print("[--]  Нет LikeGoalBoard - табло лайков встанет у точки спавна") end
local spans = workspace:FindFirstChild("BridgeSpans", true)
if spans then for _, p in spans:GetChildren() do markPart(p) end ok("Рамки под мосты: " .. #spans:GetChildren()) end
if workspace:FindFirstChild("Baseplate") then print("[--]  В Workspace остался Baseplate - если он под островом, убери его") end

print(("========== Итог: проблем %d, исправлено мелочей %d =========="):format(problems, fixes))
end -- check()

check()
