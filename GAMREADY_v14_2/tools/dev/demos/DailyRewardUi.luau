return function(gui, shared, require)
	local Config = require(shared.Config)
	gui.Panel.Visible = true
	gui.Dimmer.Visible = true
	for i = 1, 7 do
		local card = gui.Panel:FindFirstChild("Day" .. i, true)
		local r = Config.Quests.PlaytimeRewards[i]
		card.Reward.Text = r.Text
		card.Day.Text = ({ "1 MIN", "5 MIN", "10 MIN", "20 MIN", "30 MIN", "45 MIN", "1 HOUR" })[i]
		if i <= 2 then card.Check.Visible = true; card.SkinStroke.Color = Color3.fromRGB(80, 200, 90) end
		if i == 3 then card.Brackets.Visible = true; card.SkinStroke.Color = Color3.fromRGB(255, 204, 75) end
	end
end
