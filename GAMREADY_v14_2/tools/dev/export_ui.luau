--!nocheck
--------------------------------------------------------------------------------
-- export_ui.luau — собрать ВЕСЬ интерфейс БЕЗ Studio и сохранить в файл.
--
--   lune run tools/dev/export_ui.luau            → StarterGui_UI.rbxm
--   lune run tools/dev/export_ui.luau ShopUi     → только указанные экраны
--
-- Нужен Lune (https://lune-org.github.io/docs). Скрипт поднимает мини-копию
-- ReplicatedStorage.Shared из src/shared, запускает те же билдеры, что и
-- tools/BuildAllUI.lua, и проверяет каждое свойство по базе Roblox (опечатка
-- в имени свойства = ошибка здесь, а не в Studio). Готовый .rbxm можно
-- перетащить в StarterGui в Studio — получится то же, что даёт BuildAllUI.
--------------------------------------------------------------------------------
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Instance = roblox.Instance
roblox.implementMethod("Instance", "WaitForChild", function(self, name)
	local child = self:FindFirstChild(name)
	assert(child, "WaitForChild: нет " .. self:GetFullName() .. "." .. tostring(name))
	return child
end)
local ROOT = "src/shared"

local game = Instance.new("DataModel")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local workspace = game:GetService("Workspace")

local paths = {} -- [ModuleScript] = file path
local function mirror(dir, parent)
	for _, name in fs.readDir(dir) do
		local full = dir .. "/" .. name
		if fs.isDir(full) then
			local folder = Instance.new("Folder")
			folder.Name = name
			folder.Parent = parent
			mirror(full, folder)
		elseif name:match("%.lua$") and not name:match("%.client%.lua$") and not name:match("%.server%.lua$") then
			local module = Instance.new("ModuleScript")
			module.Name = name:gsub("%.lua$", "")
			module.Parent = parent
			paths[module:GetFullName()] = full
		end
	end
end
local shared = Instance.new("Folder")
shared.Name = "Shared"
shared.Parent = ReplicatedStorage
mirror(ROOT, shared)
local assets = Instance.new("Folder")
assets.Name = "Assets"
assets.Parent = ReplicatedStorage

local fakeRunService = {
	IsClient = function() return false end,
	IsServer = function() return true end,
	IsStudio = function() return true end,
}
local fakeServices = {
	RunService = fakeRunService,
}
local gameProxy = setmetatable({}, {
	__index = function(_, key)
		if key == "GetService" then
			return function(_, name)
				return fakeServices[name] or game:GetService(name)
			end
		end
		return game[key]
	end,
})

local cache = {}
local baseEnv = getfenv(1)
local function makeEnv(scriptInstance)
	return setmetatable({
		script = scriptInstance,
		game = gameProxy,
		workspace = workspace,
		Instance = roblox.Instance,
		Enum = roblox.Enum,
		Color3 = roblox.Color3,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		NumberRange = roblox.NumberRange,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Vector2 = roblox.Vector2,
		Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame,
		Rect = roblox.Rect,
		Font = roblox.Font,
		BrickColor = roblox.BrickColor,
		TweenInfo = { new = function(...) return { ... } end },
		task = task,
		tick = os.clock,
		time = os.clock,
		wait = task.wait,
		warn = function(...) print("[warn]", ...) end,
		require = nil, -- ставится ниже
	}, { __index = baseEnv })
end

local function requireModule(module)
	if type(module) == "string" then
		return require(module)
	end
	local key = module:GetFullName()
	if cache[key] ~= nil then
		return cache[key]
	end
	local path = paths[key]
	assert(path, "require: неизвестный модуль " .. tostring(module))
	local env = makeEnv(module)
	env.require = requireModule
	local fn = luau.load(fs.readFile(path), { debugName = path, environment = env })
	local result = fn()
	cache[key] = result
	return result
end

local UiRegistry = requireModule(shared:FindFirstChild("UiRegistry"))

local filter = nil
if #process.args > 0 then
	filter = {}
	for _, name in process.args do
		filter[name] = true
	end
end

local failed = 0
local built = {}
for _, entry in UiRegistry.Entries do
	if not filter or filter[entry.Name] then
		local ok, result = pcall(UiRegistry.Build, entry.Name)
		if ok then
			result.Parent = StarterGui
			table.insert(built, result)
			print("✔ " .. entry.Name)
		else
			failed += 1
			print("✘ " .. entry.Name .. "\n    " .. tostring(result))
		end
	end
end

if #built > 0 then
	fs.writeFile("StarterGui_UI.rbxm", roblox.serializeModel(built))
	print(("Сохранено: StarterGui_UI.rbxm (%d экранов)"):format(#built))
end
if failed > 0 then
	process.exit(1)
end
