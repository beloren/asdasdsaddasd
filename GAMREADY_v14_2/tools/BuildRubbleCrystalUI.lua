--------------------------------------------------------------------------------
-- BuildRubbleCrystalUI — ОДНОРАЗОВЫЙ скрипт-сборщик, строит карточку
-- переноски кристалла (StarterGui/RubbleCrystalHotbar/Slot).
--
-- ОТДЕЛЬНЫЙ файл от BuildUIAssets.lua специально — чтобы не трогать/не
-- пересобирать заново весь остальной UI (PickaxeHotbar, HUD и т.д.), когда
-- меняешь именно эту карточку. Визуально — ТОЧНАЯ копия конструкции слота
-- кирки (makeActionSlot из BuildUIAssets.lua: скруглённые углы, обводка,
-- иконка по центру), только высота чуть больше и иконка не фиксированная —
-- какой именно кристалл сейчас в руках, решает RubbleCrystalUI.client.lua
-- во время игры (Image меняется на лету по Config.Geodes.Ores[oreId].ImageId).
--
-- Запускать через Command Bar (Studio), как и остальные Build*.lua.
--------------------------------------------------------------------------------

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
Config.Icons = Config.Icons or {}

-- Фон слота (необязательно) — впиши ID своей картинки, если хочешь другой
-- фон вместо однотонного плейсхолдера. Сама иконка кристалла ставится не
-- отсюда — она полностью управляется рантайм-скриптом (см. шапку файла).
local CRYSTAL_SLOT_BACKGROUND_IMAGE_ID = 0

local DARK_COLOR = Color3.fromRGB(20, 20, 25)

local function imageUri(id)
	if not id or id == 0 then
		return ""
	end
	return "rbxassetid://" .. tostring(id)
end

local function applyImage(instance, id)
	if not id or id == 0 then
		return
	end
	instance.Image = imageUri(id)
	instance.ScaleType = Enum.ScaleType.Stretch
	instance.BackgroundTransparency = 1
	local gradient = instance:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Enabled = false
	end
end

-- Копия makeActionSlot из BuildUIAssets.lua (см. комментарий в шапке — не
-- импортируем оттуда специально, чтобы этот файл ничего не трогал в старом
-- билдере и работал полностью самостоятельно).
local function makeActionSlot(name, position, size, strokeColor, backgroundImageId)
	local slot = Instance.new("ImageLabel")
	slot.Name = name
	slot.AnchorPoint = Vector2.new(0.5, 1)
	slot.Position = position
	slot.Size = size
	slot.BackgroundColor3 = Color3.fromRGB(30, 28, 35)
	slot.BorderSizePixel = 0
	slot.ClipsDescendants = true

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = slot

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = strokeColor
	stroke.Parent = slot

	applyImage(slot, backgroundImageId)

	-- Иконка — пустая по умолчанию (Image = ""), рантайм-скрипт сам
	-- проставляет Config.Geodes.Ores[oreId].ImageId при каждой смене
	-- переносимого кристалла (см. RubbleCrystalUI.client.lua).
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Image = ""
	icon.ScaleType = Enum.ScaleType.Fit
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.62, 0.62)
	icon.ZIndex = 2
	icon.Parent = slot

	-- Плейсхолдер-буква, пока Icon.Image пуст (нет картинки под конкретный
	-- oreId ещё, или ImageId = 0) — чтобы слот не выглядел пустым провалом.
	-- Рантайм-скрипт сам прячет её, как только выставляет реальную картинку.
	local placeholder = Instance.new("TextLabel")
	placeholder.Name = "Placeholder"
	placeholder.BackgroundTransparency = 1
	placeholder.Size = UDim2.fromScale(1, 1)
	placeholder.Font = Enum.Font.FredokaOne
	placeholder.TextScaled = true
	placeholder.TextColor3 = Color3.fromRGB(230, 230, 235)
	placeholder.TextStrokeColor3 = DARK_COLOR
	placeholder.TextStrokeTransparency = 0
	placeholder.Text = "?"
	placeholder.ZIndex = 2
	placeholder.Parent = slot

	return slot
end

local existing = StarterGui:FindFirstChild("RubbleCrystalHotbar")
if existing then
	existing:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RubbleCrystalHotbar"
screenGui.ResetOnSpawn = false -- см. PickaxeHotbar — респавн ручной, ResetOnSpawn=true снёс бы этот UI
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 5 -- тот же слой, что и PickaxeHotbar — стоят рядом в одном ряду
screenGui.Parent = StarterGui

-- Позиция здесь — это позиция, когда карточка ВИДНА (она скрыта, пока руки
-- пустые). Симметрична runtime-сдвигу кирки в RubbleCrystalUI.client.lua
-- (PICKAXE_SHIFT_OFFSET = 38, та же цифра, только в другую сторону) — вместе
-- пара [кристалл][кирка] стоит ровно по центру экрана, а не смещена влево.
local slot = makeActionSlot(
	"Slot",
	UDim2.new(0.5, -38, 1, -20),
	UDim2.fromOffset(68, 74),
	Color3.fromRGB(120, 200, 255), -- голубоватая обводка — отличает от серой кирки на глаз
	CRYSTAL_SLOT_BACKGROUND_IMAGE_ID
)
slot.Visible = false -- по умолчанию скрыт — RubbleCrystalUI.client.lua включает, пока кристалл в руках
slot.Parent = screenGui

print("[BuildRubbleCrystalUI] Done: RubbleCrystalHotbar/Slot created in StarterGui, styled like PickaxeHotbar. Runtime icon/visibility handled by RubbleCrystalUI.client.lua.")
