extends SceneTree
## Shareable result card + the provider-neutral Share autoload (WP 0.6-C):
##   godot --headless --path godot --script res://tests/result_card_test.gd
## Checks the card builds from Save.finish_match()'s summary, the PNG lands at a deterministic timestamped path with the
## phone-friendly 1080x1920 size, the Share control follows Share.has_provider(), and a fake provider receives the path.

var fails := 0

func ok(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var nodes0 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	# Save.finish_match()'s summary (godot/autoload/save.gd), plus the match context world.gd adds for the card.
	var summary := {"coins": 85, "kos": 5, "hits": 17, "won": true, "total": 1234, "before": 1149,
		"next": {}, "goals": [], "streak": 0, "days": 1}
	var extra := {"mode": "Classic", "arena": "Arena", "deaths": 2, "team": false,
		"look": {"color": 0x39b5a8, "hat": "none", "skin": "none"}, "result": "You win!"}

	var card := ResultCard.build(summary, extra)
	ok(card != null and card.name == "ResultCard", "the card builds from a finish_match summary")
	ok(card.find_child("Result", true, false) is Label and (card.find_child("Result", true, false) as Label).text == "You win!",
		"the result line shows the win")
	var place := card.find_child("ModeArena", true, false) as Label
	ok(place != null and place.text.contains("Classic") and place.text.contains("Arena"), "the card shows mode + arena")
	var kos := card.find_child("KosValue", true, false) as Label
	var deaths := card.find_child("DeathsValue", true, false) as Label
	var coins := card.find_child("CoinsValue", true, false) as Label
	var total := card.find_child("Total", true, false) as Label
	ok(kos != null and kos.text == "5", "the card shows K.O.s")
	ok(deaths != null and deaths.text == "2", "the card shows deaths")
	ok(coins != null and coins.text == "+85", "the card shows coins earned this match")
	ok(total != null and total.text.contains("1234"), "the card shows the coin total")
	ok(card.find_child("Wobbler", true, false) != null, "the card draws the player's wobbler")
	ok(card.find_child("Logo", true, false) != null, "the card shows the game logo")
	card.free()

	var fixed := 1767225600   # 2026-01-01 00:00:00 UTC
	var path := ResultCard.path_for(summary, extra, fixed)
	ok(path == "user://share/wobblers_classic_20260101-000000.png", "deterministic timestamped PNG path: " + path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var out: String = await ResultCard.render(root, summary, extra, fixed)
	ok(out == path, "render writes the deterministic path: " + out)
	ok(FileAccess.file_exists(out), "the card PNG exists")
	var bytes := FileAccess.get_file_as_bytes(out)
	ok(bytes.size() > 8 and bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47,
		"the card file has a PNG signature")
	var img := Image.load_from_file(out)
	ok(img != null and not img.is_empty(), "the card PNG loads")
	ok(img != null and img.get_size() == Vector2i(1080, 1920), "the card is 1080x1920 portrait")

	var share: Node = root.get_node_or_null("Share")
	ok(share != null, "the Share autoload is registered")
	if share != null:
		share.set_provider(null)
		ok(not share.has_provider(), "has_provider is false with no provider")
		ok(ResultCard.share_control(share) == null, "no share control appears without a provider")
		ok(ResultCard.share_control(null) == null, "no share control without the service")
		var fake = load("res://tests/fake_share_provider.gd").new()
		share.set_provider(fake)
		ok(share.has_provider(), "has_provider is true with a provider")
		var btn := ResultCard.share_control(share)
		ok(btn != null and btn.name == "ShareResult", "the share control appears with a provider")
		if btn != null:
			ok(btn.text == TranslationServer.translate("Share card"), "the share control is translated")
			ok(btn.custom_minimum_size.y >= 60.0, "the share control is at least 60 canvas px (44 pt)")
			btn.free()
		var text := ResultCard.share_text(summary, extra)
		ok(share.share_image(out, text), "the provider accepts the card")
		ok(fake.calls.size() == 1 and fake.calls[0]["path"] == out, "the provider receives the card path")
		ok(fake.calls.size() == 1 and str(fake.calls[0]["text"]).contains("5") and str(fake.calls[0]["text"]).contains("2"),
			"the provider receives the share text")
		share.set_provider(null)
		ok(not share.share_image(out, text), "sharing is refused with no provider")

	if FileAccess.file_exists(out):
		DirAccess.remove_absolute(out)
	await process_frame
	var nodes1 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	print("NODES before=%d after=%d orphans=%d" % [nodes0, nodes1, orphans])
	ok(nodes1 <= nodes0, "no node leak (%d -> %d)" % [nodes0, nodes1])
	ok(orphans == 0, "no orphan nodes (%d)" % orphans)
	print("CARD ok" if fails == 0 else "CARD failed (%d)" % fails)
	quit(0 if fails == 0 else 1)
