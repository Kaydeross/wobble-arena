extends SceneTree
## Breakable props shatter into VISIBLE PropDebris (docs/DESTRUCTIBLE.md). Run by tools/test-godot-destruct.js:
##   godot --headless --path godot --script res://tests/prop_debris_test.gd -- --no-save
## Breaks every component in a real offline World and checks the pieces: they exist, are visible, wear a material, have a
## sane scale, are inside the map bounds and not below the floor, and (stepped) they land, sink away and are freed.

var fails := 0
var checks := 0

func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL ", msg)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	for map_id in ["arena", "park", "farm"]:
		await _map(map_id)
	await _pose_event_regression()
	print("PROPDEBRIS %s checks=%d fails=%d" % ["ok" if fails == 0 else "FAILED", checks, fails])
	quit(0 if fails == 0 else 1)

func _map(map_id: String) -> void:
	var w: Node = load("res://world/world.tscn").instantiate()
	w.map_id = map_id; w.mode_id = "classic"
	w.auto_run = false; w.bot_count = 3; w.rng_seed = 4242
	root.add_child(w)
	await process_frame
	var d: Destruct = w.sim.destruct
	check(d != null and d.total() > 0, "%s: has breakables" % map_id)
	if d == null: w.queue_free(); return
	var geo: Dictionary = (w.map_node.map.get("geometry", {}) as Dictionary)
	var half := float(w.map_node.map.get("size", 100.0))
	for i in d.total():
		var p: Dictionary = d.props[i]
		d.break_hit(i, 99999.0, [1.0, 0.0, 0.0])
	w.present(0.0)
	var deb: PropDebris = w._debris
	check(deb != null and is_instance_valid(deb) and deb.is_inside_tree(), "%s: PropDebris is in the tree under the map" % map_id)
	if deb == null: w.queue_free(); return
	check(deb.piece_count() > 0, "%s: breaking spawned pieces (%d)" % [map_id, deb.piece_count()])
	var bad := 0
	for q in deb._pieces:
		var n: MeshInstance3D = q["node"]
		var g := n.global_position
		var ok := n.is_visible_in_tree() and n.mesh != null and n.material_override != null \
			and n.scale.x > 0.02 and n.scale.y > 0.02 and n.scale.z > 0.02 and n.scale.x < 3.0 \
			and g.is_finite() and absf(g.x) < 400.0 and absf(g.z) < 400.0 and g.y > -0.5 and g.y < 40.0
		if not ok:
			bad += 1
			if bad <= 3: print("  bad piece at ", g, " scale ", n.scale, " vis ", n.is_visible_in_tree())
	check(bad == 0, "%s: every piece is visible, sane-sized, in bounds, above ground (%d bad)" % [map_id, bad])
	# they must survive long enough to be seen: still there after 0.5 s of frames
	for k in 30: deb._process(1.0 / 60.0)
	check(deb.piece_count() > 0, "%s: pieces still alive after 0.5 s" % map_id)
	for k in 400: deb._process(1.0 / 60.0)
	check(deb.piece_count() == 0 and deb.crown_count() == 0, "%s: pieces sink away afterwards" % map_id)
	w.queue_free()
	await process_frame

## Regression: World._drain_pose_events used to REPLACE sim.combat.events with a new array. Destruct appends its break /
## prop_hit / respawn events to the original array (same reference), so after the first lean/head/arm event of a match
## every later break was stranded and its debris never appeared. The queue must stay the very same array.
func _pose_event_regression() -> void:
	var w: Node = load("res://world/world.tscn").instantiate()
	w.map_id = "arena"; w.mode_id = "classic"
	w.auto_run = false; w.bot_count = 1; w.rng_seed = 4242
	root.add_child(w)
	await process_frame
	var d: Destruct = w.sim.destruct
	var q: Array = w.sim.combat.events
	q.append({"type": "lean", "f": w.sim.player, "a": 0.1, "b": 0.0})
	w._drain_pose_events()
	check(w.sim.combat.events == q and is_same(w.sim.combat.events, q), "pose drain keeps the same events array")
	d.break_hit(0, 99999.0, [1.0, 0.0, 0.0])
	w.present(0.0)
	check(w._debris != null and w._debris.piece_count() > 0, "a break after a pose event still shatters into debris")
	w.queue_free()
	await process_frame
