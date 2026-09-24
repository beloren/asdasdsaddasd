--------------------------------------------------------------------------------
-- TextStrokeSync (LocalScript) v20 — обводка текста гаснет вместе с текстом.
--
-- В едином стиле (UiKit/WorldUi) обводка букв — отдельный UIStroke
-- "TextStroke". Когда скрипт плавно гасит надпись (TextTransparency → 1:
-- «+$X» при начислении денег, тосты, цифры урона, баннеры), сам UIStroke
-- об этом не знает — оставался пустой чёрный контур букв посреди экрана.
-- Здесь прозрачность каждого TextStroke привязана к прозрачности его текста:
--   stroke = база + (1 − база) × TextTransparency
-- (база — прозрачность, заданная обводке в Studio/билдере).
--------------------------------------------------------------------------------
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local bound = setmetatable({}, { __mode = "k" })

local function bind(stroke)
	if bound[stroke] or not stroke:IsA("UIStroke") or stroke.Name ~= "TextStroke" then return end
	local text = stroke.Parent
	if not (text and (text:IsA("TextLabel") or text:IsA("TextButton") or text:IsA("TextBox"))) then return end
	bound[stroke] = true
	local base = stroke:GetAttribute("BaseTransparency")
	if type(base) ~= "number" then
		base = stroke.Transparency
		stroke:SetAttribute("BaseTransparency", base)
	end
	local function sync()
		if stroke.Parent ~= text then return end
		stroke.Transparency = base + (1 - base) * text.TextTransparency
	end
	sync()
	text:GetPropertyChangedSignal("TextTransparency"):Connect(sync)
end

local function scan(root)
	for _, d in root:GetDescendants() do
		if d.Name == "TextStroke" then bind(d) end
	end
	root.DescendantAdded:Connect(function(d)
		if d.Name == "TextStroke" then
			-- Родитель клона может встать на место кадром позже.
			task.defer(bind, d)
		end
	end)
end

scan(playerGui)
scan(workspace) -- мировые надписи (WorldUi): над рудой, мобами, цифры урона
