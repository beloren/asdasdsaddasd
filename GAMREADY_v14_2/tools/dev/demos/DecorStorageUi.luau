return function(gui, shared, require)
	local panel = gui.Panel
	local template = panel.Templates.Cell
	local ores = {
		{ "IRON", 42, Color3.fromRGB(200, 200, 200) }, { "AMETHYST", 17, Color3.fromRGB(80, 160, 255) },
		{ "RUBY", 5, Color3.fromRGB(180, 90, 255) }, { "GOLD", 99, Color3.fromRGB(255, 200, 60) },
	}
	local function cell(parent, i, ore)
		local c = template:Clone()
		c.Visible = true
		c.LayoutOrder = i
		if ore then
			c.ItemName.Text = ore[1]
			c.Count.Text = "x" .. ore[2]
			c.RarityBar.BackgroundColor3 = ore[3]
		else
			c.RarityBar.Visible = false
			c.ImageTransparency = 0.35
		end
		c.Parent = parent
	end
	for i = 1, 10 do cell(panel.ChestGrid, i, ores[i]) end
	for i = 1, 7 do cell(panel.BagGrid, i, ores[(i % 4) + 1]) end
	panel.ChestLabel.Text = "CHEST 4/10"
end
