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
	gui.QuestModal.Visible = _G.PREVIEW_MODAL == true
	gui.Dimmer.Visible = _G.PREVIEW_MODAL == true
	for i, q in { { "Goblin King 2", "Give items to 'Goblin King'.", "- Bring 3 Topaz and 10000 gold." }, { "Sensei Moro Final", "Find the rarest ores to the forge!", "- Get Fireite: 0/3" } } do
		local row = t.TrackerRow:Clone()
		row.Visible = true
		row.LayoutOrder = i
		row.Header.Title.Text = q[1]
		row.Why.Text = q[2]
		row.Objective.Text.Text = q[3]
		row.Parent = gui.QuestTracker
	end
end
