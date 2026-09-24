--!nocheck
--------------------------------------------------------------------------------
-- preview_ui.luau — грубый HTML-превью экрана без Studio (для разработки).
--   lune run tools/dev/preview_ui.luau <Экран> [ширина высота] [показать1,показать2] [demo]
-- Собирает экран билдером, делает видимыми элементы из списка (например
-- Panel,Dimmer), по желанию наполняет демо-данными (tools/dev/demos) и
-- пишет preview_<Экран>.html. Шрифты/картинки приблизительные — это
-- проверка раскладки, а не точная копия Roblox.
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

local game = Instance.new("DataModel")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local workspace = game:GetService("Workspace")
local paths = {}
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
mirror("src/shared", shared)
local assetsFolder = Instance.new("Folder")
assetsFolder.Name = "Assets"
assetsFolder.Parent = ReplicatedStorage

local fakeServices = { RunService = { IsClient = function() return false end, IsServer = function() return true end, IsStudio = function() return true end } }
local gameProxy = setmetatable({}, { __index = function(_, key)
	if key == "GetService" then
		return function(_, name) return fakeServices[name] or game:GetService(name) end
	end
	return game[key]
end })
local cache = {}
local baseEnv = getfenv(1)
local requireModule
local function makeEnv(scriptInstance)
	return setmetatable({
		script = scriptInstance, game = gameProxy, workspace = workspace,
		Instance = roblox.Instance, Enum = roblox.Enum, Color3 = roblox.Color3,
		ColorSequence = roblox.ColorSequence, ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberSequence = roblox.NumberSequence, NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		NumberRange = roblox.NumberRange, UDim = roblox.UDim, UDim2 = roblox.UDim2, Vector2 = roblox.Vector2,
		Vector3 = roblox.Vector3, CFrame = roblox.CFrame, Rect = roblox.Rect, Font = roblox.Font, BrickColor = roblox.BrickColor,
		TweenInfo = { new = function(...) return { ... } end }, task = task, tick = os.clock, time = os.clock,
		warn = function(...) print("[warn]", ...) end, require = function(m) return requireModule(m) end,
	}, { __index = baseEnv })
end
requireModule = function(module)
	if type(module) == "string" then return require(module) end
	local key = module:GetFullName()
	if cache[key] ~= nil then return cache[key] end
	local path = assert(paths[key], "require: неизвестный модуль " .. key)
	local fn = luau.load(fs.readFile(path), { debugName = path, environment = makeEnv(module) })
	local result = fn()
	cache[key] = result
	return result
end

local screenName = process.args[1] or "ShopUi"
local VW = tonumber(process.args[2]) or 1280
local VH = tonumber(process.args[3]) or 720
local show = {}
for name in string.gmatch(process.args[4] or "", "[^,]+") do show[name] = true end
local demo = process.args[5]

local UiRegistry = requireModule(shared.UiRegistry)
-- Несколько экранов через «+»: Hud+HotbarUi — рисуются в один кадр.
local gui = Instance.new("ScreenGui")
gui.Name = "Preview"
for name in string.gmatch(screenName, "[^+]+") do
	local screen = UiRegistry.Build(name)
	for _, child in screen:GetChildren() do
		child.Parent = gui
	end
end
for _, d in gui:GetDescendants() do
	if show[d.Name] and d:IsA("GuiObject") then d.Visible = true end
end
if demo then
	local demoPath = "tools/dev/demos/" .. screenName .. ".luau"
	if fs.isFile(demoPath) then
		local env = makeEnv(nil)
		local fn = luau.load(fs.readFile(demoPath), { debugName = demoPath, environment = env })
		fn()(gui, shared, requireModule)
	end
end

--------------------------------------------------------------------------------
-- РАСКЛАДКА
--------------------------------------------------------------------------------
-- userdata-инстансы Lune не годятся как ключи таблиц — метим каждый id.
do
	local n = 0
	for _, d in gui:GetDescendants() do
		n += 1
		d:SetAttribute("__pid", n)
	end
end
local function pid(inst) return inst:GetAttribute("__pid") end
local function css(c, a)
	return ("rgba(%d,%d,%d,%.3f)"):format(math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5), a or 1)
end
local function childrenOf(inst)
	local list = {}
	for _, c in inst:GetChildren() do table.insert(list, c) end
	return list
end
local function findClass(inst, class)
	for _, c in inst:GetChildren() do if c.ClassName == class then return c end end
	return nil
end
local function isGui(c)
	return c:IsA("GuiObject")
end

local out = {}
local function emit(s) table.insert(out, s) end

local function padOf(inst, w, h)
	local p = findClass(inst, "UIPadding")
	if not p then return 0, 0, 0, 0 end
	return p.PaddingLeft.Scale * w + p.PaddingLeft.Offset, p.PaddingTop.Scale * h + p.PaddingTop.Offset,
		p.PaddingRight.Scale * w + p.PaddingRight.Offset, p.PaddingBottom.Scale * h + p.PaddingBottom.Offset
end

local measure -- (inst, parentW, parentH) -> w, h  (with automatic size)

local function sortedGuiChildren(inst)
	local list = {}
	for _, c in inst:GetChildren() do if isGui(c) and c.Visible then table.insert(list, c) end end
	table.sort(list, function(a, b)
		if a.LayoutOrder ~= b.LayoutOrder then return a.LayoutOrder < b.LayoutOrder end
		return a.Name < b.Name
	end)
	return list
end

-- returns content height/width needed by layout inside inst of width w (for automatic size)
local function layoutContent(inst, w, h)
	local list = findClass(inst, "UIListLayout")
	local grid = findClass(inst, "UIGridLayout")
	local pl, pt, pr, pb = padOf(inst, w, h)
	local cw, ch = w - pl - pr, h - pt - pb
	if grid then
		local kids = sortedGuiChildren(inst)
		local cellW = grid.CellSize.X.Scale * cw + grid.CellSize.X.Offset
		local cellH = grid.CellSize.Y.Scale * ch + grid.CellSize.Y.Offset
		local gapX = grid.CellPadding.X.Scale * cw + grid.CellPadding.X.Offset
		local gapY = grid.CellPadding.Y.Scale * ch + grid.CellPadding.Y.Offset
		local perRow = math.max(1, math.floor((cw + gapX) / (cellW + gapX)))
		local rows = math.ceil(#kids / perRow)
		local placed = {}
		for i, k in kids do
			local col = (i - 1) % perRow
			local row = math.floor((i - 1) / perRow)
			placed[pid(k)] = { pl + col * (cellW + gapX), pt + row * (cellH + gapY), cellW, cellH }
		end
		return placed, pl + pr + perRow * cellW, pt + pb + math.max(0, rows * cellH + (rows - 1) * gapY)
	elseif list then
		local kids = sortedGuiChildren(inst)
		local horizontal = list.FillDirection == roblox.Enum.FillDirection.Horizontal
		local gap = list.Padding.Scale * (horizontal and cw or ch) + list.Padding.Offset
		local sizes = {}
		local total, cross = 0, 0
		for i, k in kids do
			local kw, kh = measure(k, cw, ch)
			sizes[pid(k)] = { kw, kh }
			total += (horizontal and kw or kh) + (i > 1 and gap or 0)
			cross = math.max(cross, horizontal and kh or kw)
		end
		local placed = {}
		local cursor = 0
		local start = 0
		if horizontal then
			if list.HorizontalAlignment == roblox.Enum.HorizontalAlignment.Center then start = (cw - total) / 2
			elseif list.HorizontalAlignment == roblox.Enum.HorizontalAlignment.Right then start = cw - total end
		else
			if list.VerticalAlignment == roblox.Enum.VerticalAlignment.Center then start = (ch - total) / 2
			elseif list.VerticalAlignment == roblox.Enum.VerticalAlignment.Bottom then start = ch - total end
		end
		for _, k in kids do
			local kw, kh = sizes[pid(k)][1], sizes[pid(k)][2]
			if horizontal then
				local y = pt
				if list.VerticalAlignment == roblox.Enum.VerticalAlignment.Center then y = pt + (ch - kh) / 2
				elseif list.VerticalAlignment == roblox.Enum.VerticalAlignment.Bottom then y = pt + ch - kh end
				placed[pid(k)] = { pl + start + cursor, y, kw, kh }
				cursor += kw + gap
			else
				local x = pl
				if list.HorizontalAlignment == roblox.Enum.HorizontalAlignment.Center then x = pl + (cw - kw) / 2
				elseif list.HorizontalAlignment == roblox.Enum.HorizontalAlignment.Right then x = pl + cw - kw end
				placed[pid(k)] = { x, pt + start + cursor, kw, kh }
				cursor += kh + gap
			end
		end
		if horizontal then return placed, pl + pr + total, pt + pb + cross end
		return placed, pl + pr + cross, pt + pb + total
	end
	return nil, 0, 0
end

measure = function(inst, pw, ph)
	local w = inst.Size.X.Scale * pw + inst.Size.X.Offset
	local h = inst.Size.Y.Scale * ph + inst.Size.Y.Offset
	local aspect = findClass(inst, "UIAspectRatioConstraint")
	if aspect then
		if w / math.max(h, 1) > aspect.AspectRatio then w = h * aspect.AspectRatio else h = w / aspect.AspectRatio end
	end
	local auto = inst.AutomaticSize
	if auto ~= roblox.Enum.AutomaticSize.None and not inst:IsA("ScrollingFrame") then
		local _, cw, ch = layoutContent(inst, w, h)
		if (auto == roblox.Enum.AutomaticSize.Y or auto == roblox.Enum.AutomaticSize.XY) then h = math.max(h, ch) end
		if (auto == roblox.Enum.AutomaticSize.X or auto == roblox.Enum.AutomaticSize.XY) then
			if inst:IsA("TextLabel") or inst:IsA("TextButton") then
				local len = utf8.len((inst.Text:gsub("<[^>]+>", ""))) or 1
				w = math.max(w, len * (inst.TextSize * 0.5) + 8)
			else
				w = math.max(w, cw)
			end
		end
	end
	return w, h
end

local function stripRich(t)
	return (t:gsub("<br%s*/?>", "\n"):gsub("<[^>]+>", ""))
end
local function esc(t)
	return (t:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub("\n", "<br>"))
end

local function strokeFor(inst)
	for _, c in inst:GetChildren() do
		if c.ClassName == "UIStroke" and c.Enabled then return c end
	end
end
local function gradientFor(inst)
	for _, c in inst:GetChildren() do
		if c.ClassName == "UIGradient" and c.Enabled then return c end
	end
end

local function render(inst, x, y, w, h, depth, clipParent)
	if not inst.Visible then return end
	local styles = {}
	table.insert(styles, ("left:%.1fpx;top:%.1fpx;width:%.1fpx;height:%.1fpx;"):format(x, y, w, h))
	local bgA = 1 - inst.BackgroundTransparency
	local grad = gradientFor(inst)
	if bgA > 0.001 then
		local c = inst.BackgroundColor3
		if grad and not (inst:IsA("TextLabel") or inst:IsA("TextButton")) then
			local k0 = grad.Color.Keypoints[1].Value
			local k1 = grad.Color.Keypoints[#grad.Color.Keypoints].Value
			local c0 = roblox.Color3.new(c.R * k0.R, c.G * k0.G, c.B * k0.B)
			local c1 = roblox.Color3.new(c.R * k1.R, c.G * k1.G, c.B * k1.B)
			local t0, t1 = 0, 0
			pcall(function()
				t0 = grad.Transparency.Keypoints[1].Value
				t1 = grad.Transparency.Keypoints[#grad.Transparency.Keypoints].Value
			end)
			table.insert(styles, ("background:linear-gradient(%ddeg,%s,%s);"):format((grad.Rotation + 90) % 360, css(c0, bgA * (1 - t0)), css(c1, bgA * (1 - t1))))
		else
			table.insert(styles, "background:" .. css(c, bgA) .. ";")
		end
	end
	local corner = findClass(inst, "UICorner")
	if corner then
		local r = corner.CornerRadius.Scale * math.min(w, h) + corner.CornerRadius.Offset
		table.insert(styles, ("border-radius:%.1fpx;"):format(r))
	end
	local stroke = strokeFor(inst)
	local isText = inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox")
	if stroke and (stroke.ApplyStrokeMode == roblox.Enum.ApplyStrokeMode.Border or not isText) then
		table.insert(styles, ("box-shadow:0 0 0 %.1fpx %s;"):format(stroke.Thickness, css(stroke.Color, 1 - stroke.Transparency)))
	end
	if inst.Rotation ~= 0 then table.insert(styles, ("transform:rotate(%ddeg);"):format(inst.Rotation)) end
	if inst.ClipsDescendants or inst:IsA("ScrollingFrame") then table.insert(styles, "overflow:hidden;") end
	table.insert(styles, ("z-index:%d;"):format(inst.ZIndex))
	emit(('<div title="%s" style="%s">'):format(inst:GetFullName(), table.concat(styles)))

	if isText then
		local text = inst.Text
		if inst:IsA("TextBox") and text == "" then text = inst.PlaceholderText end
		text = stripRich(text)
		local len = math.max(1, utf8.len(text) or #text)
		local size = inst.TextSize
		if inst.TextScaled then
			local lines = 1
			size = math.min(h * 0.92, (w / (len * 0.52)))
			if size < h * 0.45 and inst.TextWrapped then
				-- многострочный
				for n = 2, 4 do
					local s = math.min(h / n * 0.92, w / (len / n * 0.52))
					if s > size then size = s; lines = n end
				end
			end
			local limit = findClass(inst, "UITextSizeConstraint")
			if limit then size = math.min(size, limit.MaxTextSize) end
			size = math.min(size, 100)
		end
		local face = inst.FontFace
		local weight = face.Weight.Value
		local italic = face.Style == roblox.Enum.FontStyle.Italic
		local ta = inst.TextXAlignment == roblox.Enum.TextXAlignment.Left and "left" or inst.TextXAlignment == roblox.Enum.TextXAlignment.Right and "right" or "center"
		local va = inst.TextYAlignment == roblox.Enum.TextYAlignment.Top and "flex-start" or inst.TextYAlignment == roblox.Enum.TextYAlignment.Bottom and "flex-end" or "center"
		local tstyle = ("position:absolute;inset:0;display:flex;align-items:%s;justify-content:%s;text-align:%s;font-family:'Source Sans 3','Source Sans Pro',Arial,sans-serif;font-size:%.1fpx;line-height:1.05;font-weight:%d;font-style:%s;color:%s;")
			:format(va, ta == "left" and "flex-start" or ta == "right" and "flex-end" or "center", ta, size, weight, italic and "italic" or "normal", css(inst.TextColor3, 1 - inst.TextTransparency))
		local tg = gradientFor(inst)
		if tg then
			local k0 = tg.Color.Keypoints[1].Value
			local k1 = tg.Color.Keypoints[#tg.Color.Keypoints].Value
			tstyle ..= ("background:linear-gradient(180deg,%s,%s);-webkit-background-clip:text;background-clip:text;-webkit-text-fill-color:transparent;"):format(css(k0), css(k1))
		end
		if stroke and stroke.ApplyStrokeMode == roblox.Enum.ApplyStrokeMode.Contextual then
			local t, col = stroke.Thickness, css(stroke.Color, 1 - stroke.Transparency)
			local shadows = {}
			for a = 0, 15 do
				local ang = a / 16 * math.pi * 2
				table.insert(shadows, ("%.1fpx %.1fpx 0 %s"):format(math.cos(ang) * t, math.sin(ang) * t, col))
			end
			if tg then
				emit(('<span style="%s;color:transparent;text-shadow:%s">%s</span>'):format(tstyle:gsub("color:[^;]+;", ""), table.concat(shadows, ","), esc(text)))
			else
				tstyle ..= "text-shadow:" .. table.concat(shadows, ",") .. ";"
			end
		end
		emit(('<span style="%s">%s</span>'):format(tstyle, esc(text)))
	end
	if (inst:IsA("ImageLabel") or inst:IsA("ImageButton")) and inst.Image ~= "" then
		emit(('<div style="position:absolute;inset:0;outline:1px dashed rgba(255,255,255,.35);font:10px monospace;color:#ccc">img</div>'))
	end

	local placed = layoutContent(inst, w, h)
	local pl, pt = padOf(inst, w, h)
	local kids = {}
	for _, c in inst:GetChildren() do
		if isGui(c) then table.insert(kids, c) end
	end
	table.sort(kids, function(a, b) return a.ZIndex < b.ZIndex end)
	local pl2, pt2, pr2, pb2 = padOf(inst, w, h)
	local cw, ch = w - pl2 - pr2, h - pt2 - pb2
	for _, c in kids do
		if placed and placed[pid(c)] then
			local p = placed[pid(c)]
			render(c, p[1], p[2], p[3], p[4], depth + 1)
		else
			local layoutHandled = findClass(inst, "UIListLayout") or findClass(inst, "UIGridLayout")
			if not layoutHandled or not c.Visible then
				local cw2, ch2 = measure(c, cw, ch)
				local cx = pl + c.Position.X.Scale * cw + c.Position.X.Offset - c.AnchorPoint.X * cw2
				local cy = pt + c.Position.Y.Scale * ch + c.Position.Y.Offset - c.AnchorPoint.Y * ch2
				render(c, cx, cy, cw2, ch2, depth + 1)
			end
		end
	end
	emit("</div>")
end

emit(('<!doctype html><html><head><meta charset="utf-8"><link href="https://fonts.googleapis.com/css2?family=Source+Sans+3:ital,wght@1,600;1,700;1,900&display=swap" rel="stylesheet"><style>div{position:absolute;box-sizing:border-box}body{margin:0;background:#4a5a3a}</style></head><body><div style="left:0;top:0;width:%dpx;height:%dpx;overflow:hidden;background:linear-gradient(#6d7c55,#3b3a2c)">'):format(VW, VH))
local roots = {}
for _, c in gui:GetChildren() do if isGui(c) then table.insert(roots, c) end end
table.sort(roots, function(a, b) return a.ZIndex < b.ZIndex end)
for _, c in roots do
	local w, h = measure(c, VW, VH)
	local x = c.Position.X.Scale * VW + c.Position.X.Offset - c.AnchorPoint.X * w
	local y = c.Position.Y.Scale * VH + c.Position.Y.Offset - c.AnchorPoint.Y * h
	render(c, x, y, w, h, 0)
end
emit("</div></body></html>")
local file = "preview_" .. screenName .. ".html"
fs.writeFile(file, table.concat(out, "\n"))
print("→ " .. file)
