class_name ResultsRewards
extends RefCounted
## The rewards block of the end-of-match results panel (world/world.gd): coins earned this match (K.O.s +5 each, +40
## for finishing, +60 more for a win: Save.finish_match), your K.O.s and hits, and the unlock progress towards the
## cheapest outfit or emote you do not own yet (a bar, or "You can buy it now!"). A "Goals" line says which coin goals
## the match completed (logic/quests.gd, claimed on the title's Goals screen) and the first-win-of-the-day streak bonus.

## `r` = Save.finish_match()'s summary ({} = nothing earned, e.g. the match was left early: shows nothing).
static func make(r: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.name = "Rewards"
	box.add_theme_constant_override("separation", 6)
	if r.is_empty(): return box
	var row := HBoxContainer.new()
	row.name = "Coins"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	row.add_child(LockerScreen.LockerIcon.new("coin", 26))
	var c := Label.new()
	c.name = "Earned"
	c.text = "+%d coins" % int(r.get("coins", 0))
	c.add_theme_font_override("font", UiTheme.font(700))
	c.add_theme_font_size_override("font_size", 26)
	c.add_theme_color_override("font_color", UiTheme.ACCENT)
	row.add_child(c)
	var k := Label.new()
	k.name = "Kos"
	k.theme_type_variation = &"MutedLabel"
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var kos := int(r.get("kos", 0))
	k.text = "%d K.O.%s × 5 · match +40%s · %d coins in all" % [kos, "" if kos == 1 else "s", " · win +60" if r.get("won", false) else "", int(r.get("total", 0))]
	box.add_child(k)
	var cls: Array = r.get("classes", [])
	if cls.size() > 0:                                   # a secret class unlocked by this match (ExtraClasses)
		var u := Label.new()
		u.name = "Unlocked"
		u.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		u.add_theme_font_size_override("font_size", 20)
		u.add_theme_color_override("font_color", UiTheme.GOOD)
		var names: Array = cls.map(func(id: String) -> String: return str(WobblerLooks.class_def(id).get("name", id)))
		u.text = "Secret class unlocked: %s! Pick it in the Walldrobe. Shh, it's a secret" % ", ".join(names)
		box.add_child(u)
	var gl := goals_text(r)
	if gl != "":
		var g := Label.new()
		g.name = "Goals"
		g.text = gl
		g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		g.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		g.custom_minimum_size = Vector2(200, 0)
		g.add_theme_font_size_override("font_size", 19)
		g.add_theme_color_override("font_color", UiTheme.GOOD)
		box.add_child(g)
	var nx: Dictionary = r.get("next", {})
	var p := Label.new()
	p.name = "Next"
	p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_theme_font_size_override("font_size", 18)
	box.add_child(p)
	if nx.is_empty():
		p.text = "You own every outfit and emote! Show-off"
		return box
	var price := int(nx["price"])
	var have := int(r.get("total", 0))
	if have >= price:
		p.text = "You can buy %s now (%d coins)! Treat yourself" % [nx["name"], price]
		p.add_theme_color_override("font_color", UiTheme.GOOD)
	else:
		p.text = "Next unlock: %s · %d / %d coins" % [nx["name"], have, price]
	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	bar.max_value = price
	bar.value = mini(have, price)
	var bg := UiTheme.box(Color(0, 0, 0, 0.35), 6, Color(1, 1, 1, 0.12), 1, 0)
	var fg := UiTheme.box(UiTheme.GOOD if have >= price else UiTheme.ACCENT, 6, Color.TRANSPARENT, 0, 0)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	box.add_child(bar)
	return box

## "+100 goal completed: Win a match (claim it in Goals) · First win today +30 (3-day streak)", "" when there is nothing to say.
static func goals_text(r: Dictionary) -> String:
	var parts: Array = []
	var done: Array = r.get("goals", [])
	if done.size() == 1:
		parts.append("+%d goal completed: %s (claim it in Goals)" % [int(done[0]["coins"]), done[0]["text"]])
	elif done.size() > 1:
		var sum := 0
		for d: Dictionary in done: sum += int(d["coins"])
		parts.append("+%d: %d goals completed (claim them in Goals)" % [sum, done.size()])
	if int(r.get("streak", 0)) > 0:
		var days := int(r.get("days", 1))
		parts.append("First win today +%d%s" % [int(r["streak"]), " (%d-day streak)" % days if days > 1 else ""])
	return " · ".join(parts)
