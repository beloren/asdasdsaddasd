--------------------------------------------------------------------------------
-- WorldUi (v20) — единая точка сборки МИРОВОГО интерфейса (BillboardGui,
-- SurfaceGui, надписи над объектами). Работает и на сервере, и на клиенте.
--
-- Шаблоны берутся из StarterGui/WorldUiTemplates (собирает
-- Shared.UiBuilders.WorldUi через tools/BuildAllUI.lua) — их можно править
-- в Studio. Если билдер не запускали, шаблоны собираются в памяти тем же
-- модулем, так что игра работает всегда.
--
--   WorldUi.Text(parent, name, style, props)  → TextLabel по образцу стиля
--        style: "Title" | "Heading" | "Number" | "Money" | "Body" | "Small" | "Glyph"
--   WorldUi.Restyle(label, style)             → перекрасить готовый TextLabel
--   WorldUi.Billboard(template, props)        → клон Billboards/<template>
--        (или пустой BillboardGui, если такого шаблона нет)
--   WorldUi.Plate(parent, name, plate, props) → клон Plates/<plate>
--------------------------------------------------------------------------------
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local WorldUi = {}

local cached = nil

local function templates()
	if cached and cached.Parent ~= nil then return cached end
	local found = nil
	if RunService:IsClient() then
		local Players = game:GetService("Players")
		local player = Players.LocalPlayer
		local playerGui = player and player:FindFirstChild("PlayerGui")
		found = playerGui and playerGui:FindFirstChild("WorldUiTemplates")
		if not found and StarterGui:FindFirstChild("WorldUiTemplates") and playerGui then
			found = playerGui:WaitForChild("WorldUiTemplates", 5)
		end
	else
		found = StarterGui:FindFirstChild("WorldUiTemplates")
	end
	if not found then
		-- Билдер не запускали — собираем шаблоны в памяти (в игру не кладём).
		local ok, built = pcall(function()
			return require(script.Parent.UiBuilders.WorldUi).Build()
		end)
		if ok then
			local holder = Instance.new("Folder")
			holder.Name = "WorldUiRuntime"
			built.Parent = holder
			found = built
		else
			warn("[WorldUi] Не удалось собрать шаблоны:", built)
		end
	end
	cached = found
	return found
end

local function apply(inst, props)
	if props then
		for key, value in props do
			inst[key] = value
		end
	end
end

local function sample(folderName, name)
	local root = templates()
	local folder = root and root:FindFirstChild(folderName)
	return folder and folder:FindFirstChild(name)
end

function WorldUi.Text(parent, name, style, props)
	local source = sample("TextStyles", style or "Heading") or sample("TextStyles", "Heading")
	local label
	if source then
		label = source:Clone()
	else
		label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
	end
	label.Name = name or "Text"
	label.Text = ""
	label.Size = UDim2.fromScale(1, 1)
	label.Position = UDim2.new()
	label.AnchorPoint = Vector2.zero
	label.Visible = true
	apply(label, props)
	label.Parent = parent
	return label
end

-- Переносит шрифт/обводку стиля на уже существующий TextLabel (например,
-- из авторского ассета) — не трогая его текст, размер и место.
function WorldUi.Restyle(label, style, keepColor)
	local source = sample("TextStyles", style or "Heading")
	if not (source and label and label:IsA("TextLabel")) then return label end
	label.FontFace = source.FontFace
	label.TextStrokeTransparency = 1
	if not keepColor then label.TextColor3 = source.TextColor3 end
	local stroke = label:FindFirstChild("TextStroke")
	local sourceStroke = source:FindFirstChild("TextStroke")
	if sourceStroke then
		if not stroke then
			stroke = sourceStroke:Clone()
			stroke.Parent = label
		else
			stroke.Thickness = sourceStroke.Thickness
			stroke.Color = sourceStroke.Color
		end
	end
	return label
end

function WorldUi.Billboard(templateName, props)
	local source = templateName and sample("Billboards", templateName)
	local board
	if source then
		board = source:Clone()
	else
		board = Instance.new("BillboardGui")
		board.AlwaysOnTop = true
		board.LightInfluence = 0
	end
	board.Enabled = true
	apply(board, props)
	return board
end

function WorldUi.Plate(parent, name, plateName, props)
	local source = sample("Plates", plateName or "Pill")
	local plate = source and source:Clone() or Instance.new("Frame")
	plate.Name = name or plateName
	plate.Visible = true
	apply(plate, props)
	plate.Parent = parent
	return plate
end

return WorldUi
