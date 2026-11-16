class_name ResultsRewards
extends RefCounted
## The rewards block of the end-of-match results panel (world/world.gd): coins earned this match (K.O.s +5 each, +40
## for finishing, +60 more for a win: Save.finish_match), your K.O.s and hits, and the unlock progress towards the
## cheapest outfit or emote you do not own yet (a bar, or "You can buy it now!"). A "Goals" line says which coin goals
## the match completed (logic/quests.gd, claimed on the title's Goals screen) and the first-win-of-the-day streak bonus.

## ui_shots (tests/ui_shots.gd) turns the count-up and the bar fill off so the docs screenshots show the final values.
static var animate := true

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
	c.text = TranslationServer.translate("+%d coins") % int(r.get("coins", 0))
	c.add_theme_font_override("font", UiTheme.font(700))
	c.add_theme_font_size_override("font_size", 26)
	c.add_theme_color_override("font_color", UiTheme.ACCENT)
	row.add_child(c)
	var earned := int(r.get("coins", 0))
	if animate and earned > 0 and DisplayServer.get_name() != "headless":   # count-up (~1 s); the text is already final under headless / tests
		c.text = TranslationServer.translate("+%d coins") % 0
		c.ready.connect(func() -> void:
			var tw := c.create_tween()
			tw.tween_method(func(v: float) -> void: c.text = TranslationServer.translate("+%d coins") % int(round(v)), 0.0, float(earned), 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT))
	var k := Label.new()
	k.name = "Kos"
	k.theme_type_variation = &"MutedLabel"
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	k.text = _kos_text(r, int(r.get("total", 0)))
	box.add_child(k)
	# Double coins: one rewarded video (or the Remove ads free perk) pays an EXTRA earned amount, once per results panel.
	# Nothing is built as visible without a registered provider: AdUi owns that test.
	var ad_state := {"claimed": false, "total": int(r.get("total", 0))}
	var double_b := Button.new()
	double_b.name = "DoubleCoins"
	double_b.text = TranslationServer.translate("Double coins")
	double_b.custom_minimum_size = Vector2(0, 56)
	double_b.add_theme_font_size_override("font_size", 23)
	double_b.theme_type_variation = &"PrimaryButton"
	double_b.visible = earned > 0 and AdUi.rewarded_visible(AdUi.DOUBLE_COINS)
	var grant := func(granted: bool) -> void:
		if not granted or ad_state["claimed"] or not is_instance_valid(double_b): return
		ad_state["claimed"] = true
		var sv := AdUi.save()
		if sv != null: sv.call("add_coins", earned)
		ad_state["total"] = int(ad_state["total"]) + earned
		c.text = TranslationServer.translate("+%d coins") % (earned * 2)
		k.text = _kos_text(r, int(ad_state["total"]))
		double_b.visible = false
	double_b.pressed.connect(func() -> void:
		if ad_state["claimed"]: return
		AdUi.request_reward(AdUi.DOUBLE_COINS, grant))
	if double_b.visible:
		box.add_child(double_b)
		AdUi.prepare(AdUi.DOUBLE_COINS)
	var cls: Array = r.get("classes", [])
	if cls.size() > 0:                                   # a secret class unlocked by this match (ExtraClasses)
		var u := Label.new()
		u.name = "Unlocked"
		u.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		u.add_theme_font_size_override("font_size", 20)
		u.add_theme_color_override("font_color", UiTheme.GOOD)
		var names: Array = cls.map(func(id: String) -> String: return TranslationServer.translate(str(WobblerLooks.class_def(id).get("name", id))))
		u.text = TranslationServer.translate("Secret class unlocked: %s! Pick it in the Walldrobe. Shh, it's a secret") % ", ".join(names)
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
		p.text = TranslationServer.translate("You own every outfit and emote! Show-off")
		return box
	var price := int(nx["price"])
	var have := int(r.get("total", 0))
	if have >= price:
		p.text = TranslationServer.translate("You can buy %s now (%d coins)! Treat yourself") % [TranslationServer.translate(str(nx["name"])), price]
		p.add_theme_color_override("font_color", UiTheme.GOOD)
	else:
		p.text = TranslationServer.translate("Next unlock: %s · %d / %d coins") % [TranslationServer.translate(str(nx["name"])), have, price]
	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	bar.max_value = price
	bar.value = mini(have, price)
	if animate and DisplayServer.get_name() != "headless":   # the bar fills from where it stood before this match's coins
		var from_v := float(maxi(0, int(r.get("before", have - int(r.get("coins", 0))))))
		bar.value = minf(from_v, float(price))
		bar.ready.connect(func() -> void:
			bar.create_tween().tween_property(bar, "value", float(mini(have, price)), 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT))
	var bg := UiTheme.box(Color(0, 0, 0, 0.35), 6, Color(1, 1, 1, 0.12), 1, 0)
	var fg := UiTheme.box(UiTheme.GOOD if have >= price else UiTheme.ACCENT, 6, Color.TRANSPARENT, 0, 0)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	box.add_child(bar)
	return box

## The "K.O.s × 5 · match +40 · %d coins in all" line, with the running total after a doubled reward.
static func _kos_text(r: Dictionary, total: int) -> String:
	var kos := int(r.get("kos", 0))
	var kt: Array = [(TranslationServer.translate("%d K.O. × 5") if kos == 1 else TranslationServer.translate("%d K.O.s × 5")) % kos, TranslationServer.translate("match +40")]
	if r.get("won", false): kt.append(TranslationServer.translate("win +60"))
	kt.append(TranslationServer.translate("%d coins in all") % total)
	return " · ".join(kt)

## "+100 goal completed: Win a match (claim it in Goals) · First win today +30 (3-day streak)", "" when there is nothing to say.
static func goals_text(r: Dictionary) -> String:
	var parts: Array = []
	var done: Array = r.get("goals", [])
	if done.size() == 1:
		parts.append(TranslationServer.translate("+%d goal completed: %s (claim it in Goals)") % [int(done[0]["coins"]), TranslationServer.translate(str(done[0]["text"]))])
	elif done.size() > 1:
		var sum := 0
		for d: Dictionary in done: sum += int(d["coins"])
		parts.append(TranslationServer.translate("+%d: %d goals completed (claim them in Goals)") % [sum, done.size()])
	if int(r.get("streak", 0)) > 0:
		var days := int(r.get("days", 1))
		parts.append((TranslationServer.translate("First win today +%d (%d-day streak)") % [int(r["streak"]), days]) if days > 1 else (TranslationServer.translate("First win today +%d") % int(r["streak"])))
	return " · ".join(parts)
