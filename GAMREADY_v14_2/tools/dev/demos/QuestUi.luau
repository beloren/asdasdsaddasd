return function(gui, shared, require)
	local UiKit = require(shared.UiKit)
	local t = gui.Templates
	local list = gui.QuestModal:FindFirstChild("List", true)
	local function add(name, order)
		local c = t:FindFirstChild(name):Clone(); c.LayoutOrder = order; c.Visible = true; c.Parent = list; return c
	end
	local h = add("SectionTitle", 1); h.Label.Text = "Daily Quests (23h 59m)"
	for i = 1, 3 do
		local c = add("QuestCard", i + 1)
		c.Bar.Fill.Size = UDim2.fromScale(0.3 * i, 1)
		c.Points.Visible = true
		for j, txt in { "$5,000", "1,000 EXP", "60 💎" } do
			local chip = t.Chip:Clone(); chip.Text = txt; chip.LayoutOrder = j; chip.Parent = c.Chips
		end
	end
	add("DoneCard", 10)
	gui.QuestModal.Visible = true
	gui.Dimmer.Visible = true
	local row = t.TrackerRow:Clone(); row.Parent = gui.QuestTracker; row.Bar.Fill.Size = UDim2.fromScale(0.4, 1)
end
