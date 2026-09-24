return function(gui, shared, require)
	gui.Enabled = true
	local req = gui.Panel:FindFirstChild("Requirements", true)
	for i, t in { "Mine tier 5", "Cart tier 5", "Pickaxe tier 5", "$1.2M" } do
		local r = gui.Templates.RequirementRow:Clone(); r.Visible = true; r.LayoutOrder = i; r.Label.Text = t; r.Parent = req
		if i > 2 then r.Box.Check.Visible = false; r.Box.Cross.Visible = true end
	end
end
