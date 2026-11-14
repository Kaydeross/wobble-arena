extends SceneTree
## Quick play test (headless): the title's one-tap random match.
##   1 logic/quick_play.gd qp.pick(): every seed yields a valid playable game type / arena / class / bot count /
##     bot skill / floor (checked against the loaded content), the same seed picks the same match, and several seeds
##     give variety (more than one game type and arena); the Practice Range, Sandbox and Construction are never picked.
##   2 The real title (scenes/main.tscn) builds with the Quick play button under Play: it is visible on the title,
##     hidden on the online tab like the rest of Home, inside the safe area and at least 44 pt tall and wide on the
##     smallest landscape / portrait canvases, clear of Play, with its sub line / tooltip and a pressed handler.
##   godot --headless --path godot --script res://tests/quick_play_test.gd -- --no-save   (npm run test:godot-quick-play)

const MAIN := "res://scenes/main.tscn"
const MIN_TOUCH := 44.0
const QUICK := "Safe/Col/Body/Home/Quick"
## The smallest supported landscape sizes (with and without phone insets), the design canvas and portrait; `mode` is the
## Settings ui_scale (ui/ui_scale.gd) the layout test uses. 926x428 at the Large scale is the tightest title in the game.
const CASES := [
	[Vector2(667, 375), [0.0, 0.0, 0.0, 0.0], "normal"],      # iPhone SE / 8
	[Vector2(812, 375), [44.0, 0.0, 44.0, 21.0], "normal"],   # iPhone X / 13 mini: the shortest 44 pt canvas
	[Vector2(852, 393), [59.0, 0.0, 59.0, 21.0], "normal"],   # iPhone 15 / 16
	[Vector2(926, 428), [47.0, 0.0, 47.0, 21.0], "large"],    # the tightest column in the layout matrix
	[Vector2(667, 375), [0.0, 0.0, 0.0, 0.0], "large"],
	[Vector2(1170, 540), [0.0, 0.0, 0.0, 0.0], "normal"],     # the design canvas
	[Vector2(1280, 720), [0.0, 0.0, 0.0, 0.0], "normal"],
	[Vector2(390, 844), [0.0, 59.0, 0.0, 34.0], "normal"],    # portrait: the whole landscape layout scaled down
]
## Title column blocks that must stay inside the safe area (same as the layout test's own check).
const BLOCKS := ["Safe/Col/Top/Logo", "Safe/Col/Top/GuestChip", "Safe/Col/Body", "Safe/Col/Build"]
var fails := 0
var qp: GDScript                  ## logic/quick_play.gd, loaded after the autoloads exist (a --script main loop compiles
var sw: GDScript                  ## its own dependencies before that, and class scripts that name an autoload fail then)

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	qp = load("res://logic/quick_play.gd")
	sw = load("res://ui/setup_wizard.gd")
	for kv in [["offline_map", "arena"], ["mode", "classic"], ["bots", 3], ["difficulty", "normal"], ["class", "wobbler"]]:
		root.get_node("Settings").set_value(kv[0], kv[1])
	_picks()
	await _title()
	SafeArea.override = []
	print("QUICK %s" % ("ok" if fails == 0 else "FAILED %d" % fails))
	quit(0 if fails == 0 else 1)

# ---------------- pick() ----------------

func _picks() -> void:
	var content: Node = root.get_node("Content")   # (autoloads are not compile-time identifiers for a --script main loop)
	var modes: Dictionary = content.modes
	var maps: Dictionary = content.maps
	var classes: Dictionary = content.classes
	var diffs: Dictionary = content.difficulties
	var mode_set := {}
	var map_set := {}
	var class_set := {}
	var floor_set := {}
	var picks := 0
	for seed in range(1, 41):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var o: Dictionary = qp.pick(rng)
		var tag := "seed %d" % seed
		var mode := str(o.get("mode", ""))
		check(modes.has(mode), "%s mode '%s' is loaded content" % [tag, mode])
		check(not qp.NOT_QUICK.has(mode), "%s mode '%s' is not the range / Sandbox / Construction" % [tag, mode])
		check(qp.modes().has(mode), "%s mode '%s' is a quick-playable mode" % [tag, mode])
		var map := str(o.get("map", ""))
		check(maps.has(map), "%s map '%s' is loaded content" % [tag, map])
		check(qp.maps_for(mode).has(map), "%s map '%s' is allowed in %s" % [tag, map, mode])
		check(not qp.DEV_MAPS.has(map), "%s map '%s' is not a dev / range map" % [tag, map])
		var cls := str(o.get("class", ""))
		check(classes.has(cls), "%s class '%s' is loaded content" % [tag, cls])
		check(sw.owns_class(cls), "%s class '%s' is owned" % [tag, cls])
		var diff := str(o.get("difficulty", ""))
		check(diffs.has(diff), "%s difficulty '%s' is loaded content" % [tag, diff])
		var floor_kind := str(o.get("dyn", ""))
		check(Dynamics.KINDS.has(floor_kind), "%s floor '%s' is a known kind" % [tag, floor_kind])
		var bots := int(o.get("bots", -1))
		check(bots == ModeRules.bot_count(mode, modes, bots), "%s bots %d is what %s plays with" % [tag, bots, mode])
		check(bots >= 0 and bots <= 12, "%s bots %d in range" % [tag, bots])
		check(o.size() == 6 and o.has("mode") and o.has("map") and o.has("bots") and o.has("difficulty") and o.has("class") and o.has("dyn"),
			"%s the over dictionary has the six keys (%s)" % [tag, o.keys()])
		mode_set[mode] = true; map_set[map] = true; class_set[cls] = true; floor_set[floor_kind] = true
		picks += 1
	check(picks == 40, "40 picks checked")
	check(mode_set.size() > 1, "several seeds roll more than one game type (%s)" % [mode_set.keys()])
	check(map_set.size() > 1, "several seeds roll more than one arena (%s)" % [map_set.keys()])
	check(class_set.size() > 1, "several seeds roll more than one class")
	# the same seed picks the same match (the helper is a pure function of the RNG)
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 7; b.seed = 7
	check(qp.pick(a) == qp.pick(b), "the same seed picks the same match")
	# a fresh RNG seeded from the title's randomize() still gets a valid match
	var c := RandomNumberGenerator.new()
	c.randomize()
	var o2: Dictionary = qp.pick(c)
	check(qp.modes().has(str(o2["mode"])) and qp.maps_for(str(o2["mode"])).has(str(o2["map"])), "a random-seeded pick is valid")
	if fails == 0: print("QUICK picks: 40 seeds, %d game types, %d arenas, %d classes" % [mode_set.size(), map_set.size(), class_set.size()])

# ---------------- the title ----------------

func _title() -> void:
	var shown := false
	for c: Array in CASES:
		var win: Vector2 = c[0]
		var cs := UiScale.canvas_size(win, str(c[2]), true)
		var k := cs.x / win.x                        # canvas px per pt
		var ins: Array = c[1]
		SafeArea.override = [ins[0] * k, ins[1] * k, ins[2] * k, ins[3] * k]
		var vp := SubViewport.new()
		vp.size = Vector2i(cs)
		vp.disable_3d = true
		root.add_child(vp)
		var main: Control = load(MAIN).instantiate()
		vp.add_child(main)
		main.browser.auto_refresh = false
		for i in 4:
			await process_frame
		var tag := "%dx%d" % [win.x, win.y]
		check(main.quick_b != null, "%s the title built the Quick play button" % tag)
		var qb: Button = main.get_node_or_null(QUICK) as Button
		check(qb != null and qb == main.quick_b, "%s the button sits under Play at %s" % [tag, QUICK])
		if qb == null:
			vp.queue_free()
			continue
		check(main.quick_b.is_visible_in_tree(), "%s Quick play is visible on the title" % tag)
		var safe := Rect2(Vector2(SafeArea.override[0], SafeArea.override[1]), cs - Vector2(SafeArea.override[0] + SafeArea.override[2], SafeArea.override[1] + SafeArea.override[3]))
		var r: Rect2 = main.quick_b.get_global_rect()
		check(safe.grow(0.5).encloses(r), "%s Quick play %s is inside the safe area %s" % [tag, r, safe])
		check(r.size.x >= 60.0 and r.size.y >= 60.0, "%s Quick play is %s (the designed 60 px touch target)" % [tag, r.size])
		if win.x > win.y:      # the 44 pt scale only applies to landscape (portrait shows the layout scaled down, like every page)
			var touch_px := MIN_TOUCH * cs.x / win.x
			check(r.size.x >= touch_px - 0.5 and r.size.y >= touch_px - 0.5, "%s Quick play %.1f x %.1f px is at least 44 pt (need %.1f)" % [tag, r.size.x, r.size.y, touch_px])
		var play_rect: Rect2 = main.play.get_global_rect()
		check(not r.grow(-0.5).intersects(play_rect.grow(-0.5)), "%s Quick play does not overlap Play" % tag)
		for other: Button in [main.play, main.online_b]:
			check(not r.grow(-0.5).intersects(other.get_global_rect().grow(-0.5)), "%s Quick play does not overlap %s" % [tag, other.name])
		var col: Control = main.get_node("Safe/Col")
		check(col.get_combined_minimum_size().y <= safe.size.y + 0.5, "%s title column min height %.0f fits %.0f" % [tag, col.get_combined_minimum_size().y, safe.size.y])
		check(main.quick_b.tooltip_text == "Random arena and mode", "%s tooltip says what it does (%s)" % [tag, main.quick_b.tooltip_text])
		var sub: Label = main.quick_b.get_node("Stack/Sub")
		check(sub.text == "Random arena and mode", "%s sub line says what it does (%s)" % [tag, sub.text])
		check(qb.pressed.get_connections().size() > 0, "%s Quick play is wired" % tag)
		for b: String in BLOCKS:      # the title column still fits the safe area with the extra button (Build is the lowest)
			var br: Rect2 = (main.get_node(b) as Control).get_global_rect()
			check(safe.grow(0.5).encloses(br), "%s %s %s is inside the safe area %s" % [tag, b, br, safe])
		# the online tab hides the whole Home column, Quick play with it (like Play)
		main.show_tab(true)
		await process_frame
		check(not main.quick_b.is_visible_in_tree(), "%s Quick play is hidden on the online tab" % tag)
		main.show_tab(false)
		await process_frame
		check(main.quick_b.is_visible_in_tree(), "%s Quick play is back on the title" % tag)
		print("QUICK title %s canvas %dx%d: quick %s, column %.0f / %.0f" % [tag, cs.x, cs.y, r.size, col.get_combined_minimum_size().y, safe.size.y])
		shown = true
		vp.queue_free()
		await process_frame
	check(shown, "at least one title case ran")
	# the quick action picks a valid match (the world itself is covered by test:godot-world)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var over: Dictionary = qp.pick(rng)
	check(over.has("map") and over.has("mode") and over.has("bots") and over.has("difficulty"), "the action's over dictionary is ready for play_offline")
