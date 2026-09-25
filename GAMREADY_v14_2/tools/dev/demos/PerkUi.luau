return function(gui, shared, require)
	local Config = require(shared.Config)
	local panel = gui.Panel
	panel.Visible = true
	local tree = panel.Tree
	local NODE, GAP = 58, 30
	for bi, branch in Config.Prestige.Branches do
		local column = tree.BranchTemplate:Clone()
		column.Name = "B" .. bi
		column.Visible = true
		column.LayoutOrder = bi
		column.Header.Text.Text = branch.Title
		column.Parent = tree
		for index, perkId in branch.Perks do
			local y = (index - 1) * (NODE + GAP)
			if index > 1 then
				local line = tree.LinkTemplate:Clone()
				line.Visible = true
				line.Position = UDim2.new(0.5, 0, 0, y - GAP + 10)
				line.Size = UDim2.fromOffset(line.Size.X.Offset, GAP - 10)
				line.Parent = column.Nodes
			end
			local node = tree.NodeTemplate:Clone()
			node.Visible = true
			node.Position = UDim2.new(0.5, 0, 0, y)
			node.Size = UDim2.fromOffset(NODE, NODE)
			node.LevelChip.Level.Text = "3/10"
			node.Parent = column.Nodes
		end
	end
end
