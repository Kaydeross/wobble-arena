extends SceneTree
## Wobbler (visual) smoke test: builds every class with outfits and hats, drives apply_state/animate through a scripted
## sequence (run, jump, land, swing, kick, crouch, hits, knock-down, KO, trapped, invulnerable), and checks that nothing
## leaks, every pose value stays finite and the class proportions match shared/classes.json.
## godot --headless --path godot --script res://tests/wobbler_test.gd -- CLASSES_JSON

const FRAMES := 900
var fails: Array[String] = []


func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)


func _finite_v(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


func _finite_b(b: Basis) -> bool:
	return _finite_v(b.x) and _finite_v(b.y) and _finite_v(b.z)


func _count_nodes(n: Node) -> int:
	var k := 1
	for ch in n.get_children():
		k += _count_nodes(ch)
	return k


## scripted FighterState for frame k (60 Hz)
func _state(k: int, cid: String) -> Dictionary:
	var t := k / 60.0
	var a := t * 1.3
	var s := {"pos": Vector3(sin(a) * 4.0, 0.0, cos(a) * 4.0), "yaw": a + PI / 2, "grounded": true, "class_id": cid,
		"aim": Vector3(cos(t), -0.3, sin(t)), "weapon": "spatula", "swing": -1.0, "kick_t": -1.0, "crouch": 0.0}
	s["vel"] = Vector3(cos(a), 0.0, -sin(a)) * 5.2
	var ph := k % 450
	if ph >= 60 and ph < 100:                          # jump: up, then falling fast, then land
		var u := (ph - 60) / 40.0
		s["grounded"] = false
		s["vel"].y = lerpf(8.0, -9.0, u)
		s["pos"].y = 2.0 * sin(PI * u)
	elif ph >= 120 and ph < 150:
		s["swing"] = (ph - 120) / 30.0 * 1.29
	elif ph >= 160 and ph < 200:
		s["kick_t"] = (ph - 160) / 40.0
	elif ph >= 210 and ph < 240:
		s["crouch"] = 1.0
		s["vel"] = Vector3.ZERO
		s["flash"] = 0.12 * (1.0 - (ph - 210) / 30.0)
	elif ph >= 250 and ph < 300:
		s["down_t"] = 1.0
		s["vel"] = Vector3.ZERO
	elif ph >= 300 and ph < 370:
		s["dead"] = true
		s["weapon"] = null
		s["vel"] = Vector3.ZERO
	elif ph >= 370 and ph < 400:
		s["trap"] = true
	elif ph >= 400:
		s["invuln"] = true
		s["weapon"] = "ak" if ph < 420 else "spatula"   # a gun built on first equip
	return s


# ============================== faces (Sprint 2.4, docs/GRAPHICS.md "Faces") ==============================
## Deterministic checks for the 2-mesh eye rig: idle blinks in the 2.5-4.5 s window, angry brows on a swing / rage,
## wide panic eyes airborne off the stage, X eyes dead / down_t > 0, the eye count never leaves 2, no node or mesh
## appears, LOW gets no extra geometry, faces never move a gameplay node, and the blink clock replays from its seed.
const FACE_DT := 1.0 / 60.0
const EYE_BOX_VERTS := 36        # LowPoly box: 12 triangles, flat shading
const EYE_BROW_VERTS := 72       # eye box + brow bar merged into one surface (MID / HIGH)


func _idle_face_state() -> Dictionary:
	return {"pos": Vector3.ZERO, "vel": Vector3.ZERO, "yaw": 0.0, "grounded": true, "class_id": "wobbler",
		"aim": Vector3(0, -0.2, 1), "weapon": "spatula", "swing": -1.0, "kick_t": -1.0, "crouch": 0.0}


func _new_face_wobbler(scene: PackedScene, seed_pin: int = -1) -> Wobbler:
	var w: Wobbler = scene.instantiate()
	root.add_child(w)
	w.blink_seed = seed_pin
	w.setup("wobbler", "none", "none", 0x39b5a8)     # setup() seeds the blink clock once
	w.apply_state(_idle_face_state())
	return w


func _mesh_verts(m: Mesh) -> int:
	if m == null or m.get_surface_count() == 0:
		return 0
	var arrays := m.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	return v.size()


## Idle blink scheduling. Fully deterministic, no wall clock and no global RNG anywhere: the wobbler's own
## RandomNumberGenerator is seeded once in setup() (pinned here), the face clock only advances by the dt this test
## feeds, so the same build always produces the same blink times on every run and platform. Every wait is drawn in
## [2.5, 4.5] s; a start is detected by the frame that crosses the wait, so start-to-start can only be the drawn wait
## plus less than one frame (never early). Closed frames use the sin envelope: a handful of frames per blink.
func _face_blink_checks(scene: PackedScene) -> Dictionary:
	var w := _new_face_wobbler(scene, 0x51A7)
	var starts: Array[float] = []
	var drawn: Array[float] = []
	var closed: Array[int] = []
	var cur_closed := 0
	var was_blinking := false
	var min_open := 1.0
	var last_count := w.blink_count
	for k in int(40.0 / FACE_DT):
		w.apply_state(_idle_face_state())
		w.animate(FACE_DT)
		var blinking: bool = w.blink_t >= 0.0
		if blinking and not was_blinking:
			cur_closed = 0
		if blinking and w.eye_open < 0.25:
			cur_closed += 1
		if not blinking and was_blinking:
			closed.append(cur_closed)
		was_blinking = blinking
		if w.blink_count != last_count:
			last_count = w.blink_count
			starts.append(w.blink_started_at)
			drawn.append(w.blink_interval)
		min_open = minf(min_open, w.eye_open)
	_check(starts.size() >= 8, "face: %d blinks in 40 s idle (want >= 8)" % starts.size())
	var lo := 1e9
	var hi := -1e9
	for i in range(1, starts.size()):
		var d := starts[i] - starts[i - 1]
		lo = minf(lo, d)
		hi = maxf(hi, d)
		_check(d >= Wobbler.BLINK_WAIT_MIN - FACE_DT - 1e-4 and d <= Wobbler.BLINK_WAIT_MAX + FACE_DT + 1e-4,
			"face: blink interval %.3f s outside 2.5-4.5" % d)
	for iv in drawn:
		_check(iv >= Wobbler.BLINK_WAIT_MIN and iv <= Wobbler.BLINK_WAIT_MAX, "face: drawn blink wait %.3f outside 2.5-4.5" % iv)
	for c in closed:
		_check(c >= 2 and c <= 12, "face: blink held shut %d frames (want a few)" % c)
	_check(min_open < 0.15, "face: eyes never shut (min open %.2f)" % min_open)
	w.free()
	return {"count": starts.size(), "lo": lo, "hi": hi, "closed_min": closed.min() if not closed.is_empty() else -1,
		"closed_max": closed.max() if not closed.is_empty() else -1, "min_open": min_open}


## Same seed + same frames replay exactly; the pin is the identity when no owning Fighter is there; the schedule runs
## off the wobbler's own RNG (never combat.rng).
func _face_determinism_checks(scene: PackedScene) -> Dictionary:
	var wa := _new_face_wobbler(scene, 0x1234)
	var wb := _new_face_wobbler(scene, 0x1234)
	var wc := _new_face_wobbler(scene, 0x4321)
	var same := true
	for k in 900:
		for w: Wobbler in [wa, wb, wc]:
			w.apply_state(_idle_face_state())
			w.animate(FACE_DT)
		if wa.blink_count != wb.blink_count or wa.blink_started_at != wb.blink_started_at \
			or wa.blink_interval != wb.blink_interval or wa.eye_open != wb.eye_open:
			same = false
	_check(same, "face: same blink seed + frames did not replay exactly")
	_check(wa.blink_identity() != wc.blink_identity(), "face: two pinned blink seeds collided")
	var wd := _new_face_wobbler(scene)            # -1: derived from the identity + look (no Fighter parent here)
	var we := _new_face_wobbler(scene)
	_check(wd.blink_identity() == we.blink_identity(), "face: same identity + look got different blink seeds")
	var out := {"blinks": wa.blink_count, "seed_a": wa.blink_identity(), "seed_b": wc.blink_identity()}
	for w: Wobbler in [wa, wb, wc, wd, we]:
		w.free()
	return out


## Angry (swing / rage), panic (airborne off the stage) and X (dead / down) expressions on the same 2 eye meshes.
func _face_expression_checks(scene: PackedScene) -> Dictionary:
	var out := {}
	# --- angry on a melee swing: mirrored angled brows + squint
	var wa := _new_face_wobbler(scene, 0x2222)
	var sw := _idle_face_state()
	sw["swing"] = 0.45
	for k in 14:
		wa.apply_state(sw)
		wa.animate(FACE_DT)
	var a0 := wa.eyes[0].basis.get_euler().z
	var a1 := wa.eyes[1].basis.get_euler().z
	_check(wa.face_state() == "angry", "face: swing face is %s, want angry" % wa.face_state())
	_check(absf(wa.brow_angle) > 0.2, "face: swing brow angle %.2f too flat" % wa.brow_angle)
	_check(wa.eye_open < 0.95, "face: swing did not squint (open %.2f)" % wa.eye_open)
	_check(a0 * a1 < 0.0 and absf(a0 + a1) < 1e-3, "face: angry brows are not mirrored (%.3f / %.3f)" % [a0, a1])
	# --- angry while rage is up (no swing)
	var wr := _new_face_wobbler(scene, 0x2223)
	var rg := _idle_face_state()
	rg["rage"] = 1.5
	for k in 14:
		wr.apply_state(rg)
		wr.animate(FACE_DT)
	_check(wr.face_state() == "angry", "face: rage face is %s, want angry" % wr.face_state())
	_check(absf(wr.brow_angle) > 0.2, "face: rage brow angle %.2f too flat" % wr.brow_angle)
	for k in 90:                                    # drops back to idle once rage ends
		wr.apply_state(_idle_face_state())
		wr.animate(FACE_DT)
	_check(wr.angry_k < 0.05, "face: anger did not decay (%.2f)" % wr.angry_k)
	# --- panic: airborne off the arena floor
	var wp := _new_face_wobbler(scene, 0x3333)
	var pa := _idle_face_state()
	pa["grounded"] = false
	pa["vel"] = Vector3(0, -9, 0)
	pa["pos"] = Vector3(0, 4, 0)
	pa["off_stage"] = true
	for k in 24:
		wp.apply_state(pa)
		wp.animate(FACE_DT)
	_check(wp.face_state() == "panic", "face: off-stage fall is %s, want panic" % wp.face_state())
	_check(wp.panic_k > 0.9, "face: panic blend %.2f too low" % wp.panic_k)
	_check(wp.eye_open > Wobbler.PANIC_WIDE * 0.9, "face: panic eyes not wide (%.2f)" % wp.eye_open)
	_check(wp.eyes[0].basis.get_scale().y > Wobbler.PANIC_WIDE * 0.9, "face: panic eye scale %.2f" % wp.eyes[0].basis.get_scale().y)
	_check(absf(wp.eyes[0].position.y - Wobbler.EYE_Y) > 0.004, "face: panic eyes did not lift")
	# --- ...but never while standing on the floor, even if the flag is set
	var wg := _new_face_wobbler(scene, 0x3334)
	var gr := _idle_face_state()
	gr["off_stage"] = true
	for k in 24:
		wg.apply_state(gr)
		wg.animate(FACE_DT)
	_check(wg.panic_k < 0.05, "face: panic on the floor (k %.2f)" % wg.panic_k)
	# --- the "panic" alias key works too
	var wg2 := _new_face_wobbler(scene, 0x3335)
	var al := _idle_face_state()
	al["grounded"] = false
	al["vel"] = Vector3(0, -9, 0)
	al["panic"] = true
	for k in 24:
		wg2.apply_state(al)
		wg2.animate(FACE_DT)
	_check(wg2.panic_k > 0.9, "face: \"panic\" alias key ignored (k %.2f)" % wg2.panic_k)
	# --- X eyes: dead, then down_t > 0
	var wx := _new_face_wobbler(scene, 0x4444)
	var dd := _idle_face_state()
	dd["dead"] = true
	for k in 12:
		wx.apply_state(dd)
		wx.animate(FACE_DT)
	_check(wx.face_state() == "x" and wx._x_eyes, "face: dead face is %s, want x" % wx.face_state())
	_check(wx.eyes[0].mesh == Wobbler.x_eye_mesh() and wx.eyes[1].mesh == Wobbler.x_eye_mesh(), "face: dead eyes are not the X mesh")
	var wdn := _new_face_wobbler(scene, 0x4445)
	var dn := _idle_face_state()
	dn["down_t"] = 1.0
	for k in 12:
		wdn.apply_state(dn)
		wdn.animate(FACE_DT)
	_check(wdn.face_state() == "x" and wdn._x_eyes, "face: knocked-down face is %s, want x" % wdn.face_state())
	# --- a K.O. outranks panic, and respawning clears the X
	var xp := dn.duplicate()
	xp["dead"] = true
	xp["down_t"] = 0.0
	xp["grounded"] = false
	xp["off_stage"] = true
	for k in 12:
		wdn.apply_state(xp)
		wdn.animate(FACE_DT)
	_check(wdn.face_state() == "x", "face: dead + off-stage is not x (%s)" % wdn.face_state())
	for k in 30:
		wx.apply_state(_idle_face_state())
		wx.animate(FACE_DT)
	_check(wx.face_state() != "x" and not wx._x_eyes and wx.eyes[0].mesh != Wobbler.x_eye_mesh(), "face: X eyes did not clear on respawn")
	out["brow"] = wa.brow_angle
	out["open_angry"] = wa.eye_open
	out["open_panic"] = wp.eye_open
	out["lift"] = wp.eyes[0].position.y - Wobbler.EYE_Y
	for w: Wobbler in [wa, wr, wp, wg, wg2, wx, wdn]:
		w.free()
	return out


## The rig contract: still exactly 2 eye meshes, no mesh/node ever appears, LOW carries no extra geometry, and a live
## face never moves a game node (hand / arm / shoulder / head / chest / legs stay bit-identical).
func _face_rig_checks(scene: PackedScene) -> Dictionary:
	var w := _new_face_wobbler(scene, 0x6666)
	_check(w.eyes.size() == 2, "face: eye rig has %d meshes, want 2" % w.eyes.size())
	var eyes_live := 0
	for e in w.eyes:
		if e is MeshInstance3D and e.is_inside_tree() and e.get_parent() == w.neck:
			eyes_live += 1
	_check(eyes_live == 2, "face: %d live Eye MeshInstance3D nodes" % eyes_live)
	var meshes0 := w.mesh_count()
	var nodes0 := _count_nodes(w)
	var idle := _idle_face_state()
	var sw := idle.duplicate(); sw["swing"] = 0.9
	var rg := idle.duplicate(); rg["rage"] = 5.0
	var pa := idle.duplicate(); pa["grounded"] = false; pa["off_stage"] = true; pa["vel"] = Vector3(0, -8, 0)
	var dd := idle.duplicate(); dd["dead"] = true
	var dn := idle.duplicate(); dn["down_t"] = 0.8
	var counts_ok := true
	for st: Dictionary in [idle, sw, rg, pa, dd, dn]:
		for k in 30:
			w.apply_state(st)
			w.animate(FACE_DT)
			if w.mesh_count() != meshes0 or _count_nodes(w) != nodes0 or w.eyes.size() != 2:
				counts_ok = false
	_check(counts_ok, "face: mesh/node count changed while expressing (meshes %d, nodes %d)" % [meshes0, nodes0])
	# live faces only: every non-eye node (the gameplay points) bit-identical to an un-expressed twin
	var fa := _new_face_wobbler(scene, 0x1111)
	var fb := _new_face_wobbler(scene, 0x9999)       # different blink phase + anger + the panic flag
	var mismatch := 0
	for k in 480:
		var st := _idle_face_state()
		st["pos"] = Vector3(sin(k * 0.03) * 3.0, 0.0, cos(k * 0.03) * 3.0)
		st["vel"] = Vector3(cos(k * 0.03), 0.0, -sin(k * 0.03)) * 4.0
		st["yaw"] = k * 0.01
		st["fall_side"] = 1.0                      # pin it: the wobbler's fall_side fallback draws the global RNG
		if k >= 300:
			st["dead"] = true
			st["vel"] = Vector3.ZERO
		var st2 := st.duplicate()
		st2["rage"] = 2.0
		st2["off_stage"] = true
		fa.apply_state(st)
		fb.apply_state(st2)
		fa.animate(FACE_DT)
		fb.animate(FACE_DT)
		for i in fa._xf_nodes.size():
			if fa._xf_nodes[i].transform != fb._xf_nodes[i].transform:
				mismatch += 1
		# the gameplay proxies (the fighter reads hand / arm / head / chest): local transforms are enough, their whole
		# ancestor chain (rig / body / neck) is compared above and the tree is not inside the SceneTree yet in _initialize
		if fa.arm_dir != fb.arm_dir or fa.hand.transform != fb.hand.transform \
			or fa.head_mesh.transform != fb.head_mesh.transform \
			or fa.torso.transform != fb.torso.transform:
			mismatch += 1
	_check(mismatch == 0, "face: a face moved a game node (%d mismatches)" % mismatch)
	# Tier cost (measured, not assumed): LOW keeps the EXACT pre-feature eye box (the same cached LowPoly mesh, same
	# mesh count), MID / HIGH merge the brow bar into the same surface (72 verts, still two meshes / two draws). Both
	# sides are checked in one process by steering Settings.fx_quality; the brow side is only expected on a device whose
	# max quality is at least MID (headless PC is HIGH), so the test stays true on a web-class device too. The previous
	# user setting is restored, so a developer with fx_quality = low gets the same result.
	var st: Node = root.get_node_or_null("Settings")
	_check(st != null, "face: Settings autoload missing")
	var tier: Node = root.get_node_or_null("Tier")
	var max_q := int(tier.call("max_quality")) if tier != null else 2
	var low_verts := -1
	var high_verts := -1
	var low_meshes := -1
	var high_meshes := -1
	if st != null:
		var prev: Variant = st.get_value("fx_quality", "auto")
		st.persist = false
		st.set_value("fx_quality", "low")
		var wl := _new_face_wobbler(scene, 0x5555)
		low_verts = _mesh_verts(wl.eyes[0].mesh)
		low_meshes = wl.mesh_count()
		st.set_value("fx_quality", "high")
		var wh := _new_face_wobbler(scene, 0x5556)
		high_verts = _mesh_verts(wh.eyes[0].mesh)
		high_meshes = wh.mesh_count()
		st.set_value("fx_quality", prev)
		_check(low_verts == EYE_BOX_VERTS, "face: LOW eye mesh has %d verts, want the plain %d-vert box" % [low_verts, EYE_BOX_VERTS])
		_check(wl.eyes[0].mesh == LowPoly.box(Wobbler.EYE_SIZE.x, Wobbler.EYE_SIZE.y, Wobbler.EYE_SIZE.z),
			"face: LOW eye mesh is not the pre-feature box")
		var want_high := EYE_BROW_VERTS if max_q >= 1 else EYE_BOX_VERTS
		_check(high_verts == want_high, "face: max-quality-%d eye mesh has %d verts, want %d" % [max_q, high_verts, want_high])
		_check(wl.mesh_count() == meshes0 and wh.mesh_count() == meshes0,
			"face: a tier changed the mesh count (%d / %d, want %d)" % [low_meshes, high_meshes, meshes0])
		_check(wl.eyes.size() == 2 and wh.eyes.size() == 2, "face: a tier changed the eye count")
		# LOW still plays every expression with the node transform / the shared X mesh: no extra geometry needed
		var la := _idle_face_state()
		la["swing"] = 0.9
		for k in 14:
			wl.apply_state(la)
			wl.animate(FACE_DT)
		_check(absf(wl.brow_angle) > 0.2, "face: LOW cannot show angry brows (%.2f)" % wl.brow_angle)
		var lx := _idle_face_state()
		lx["dead"] = true
		for k in 6:
			wl.apply_state(lx)
			wl.animate(FACE_DT)
		_check(wl.face_state() == "x" and wl.eyes[0].mesh == Wobbler.x_eye_mesh(), "face: LOW cannot show X eyes")
		wl.free()
		wh.free()
	for f: Wobbler in [w, fa, fb]:
		f.free()
	return {"meshes": meshes0, "nodes": nodes0, "low_verts": low_verts, "high_verts": high_verts,
		"low_meshes": low_meshes, "high_meshes": high_meshes, "mismatch": mismatch}


## End-to-end wiring: the deferred Sprint 2.4 keys in Fighter.visual_state (now committed) reach the wobbler:
## rage_t -> angry brows, an airborne fall below every arena floor line -> panic eyes, dead -> X eyes. Also checks
## that "off_stage" stays false while grounded at the same height (it is about being airborne off the floor).
func _face_fighter_checks() -> Dictionary:
	var f: Fighter = load("res://actors/fighter.tscn").instantiate()
	root.add_child(f)
	var s := FighterState.new()
	s.id = 7
	s.class_id = "wobbler"
	f.bind(s, {"skin": "none", "hat": "none", "color": 0x39b5a8})
	var out := {}
	s.rage_t = 1.5
	var vs := f.visual_state()
	out["rage"] = vs.get("rage", null)
	_check(is_equal_approx(float(vs.get("rage", -1.0)), 1.5), "face: Fighter.visual_state did not pass rage_t (%s)" % [vs.get("rage", "missing")])
	for k in 20:
		f.present(FACE_DT)
	_check(f.wobbler.face_state() == "angry", "face: rage_t did not reach the wobbler (%s)" % f.wobbler.face_state())
	# a fall off the arena: airborne, below every floor (arena floor tops are >= 0, the ring-out line is -25)
	s.rage_t = 0.0
	s.phys.place(0.0, -5.0, 0.0)
	s.phys.grounded = false
	var vs2 := f.visual_state()
	out["off_stage"] = vs2.get("off_stage", null)
	_check(bool(vs2.get("off_stage", false)), "face: Fighter.visual_state did not flag the off-stage fall")
	for k in 20:
		f.present(FACE_DT)
	_check(f.wobbler.face_state() == "panic", "face: off-stage fall did not reach the wobbler (%s)" % f.wobbler.face_state())
	# ...but not while standing on the floor at the same height: off_stage is an AIRBORNE fall
	s.phys.grounded = true
	_check(not bool(f.visual_state().get("off_stage", true)), "face: off_stage is true while grounded")
	# K.O. -> X eyes through the same path (dead is a contract key, so this also proves the priority order)
	s.dead = true
	for k in 10:
		f.present(FACE_DT)
	_check(f.wobbler.face_state() == "x", "face: dead did not reach the wobbler as X (%s)" % f.wobbler.face_state())
	out["state"] = f.wobbler.face_state()
	f.free()
	return out


func _initialize() -> void:
	# the autoloads (Tier / Settings) are only inside the tree once the loop runs, and the face checks read the tier
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var classes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	var skins := ["none", "hoodie", "skater", "chef", "suit", "sporty", "robot"]   # robot: colours only (no builder yet)
	var hats := ["none", "party", "top", "crown", "prop", "halo", "viking"]
	var scene: PackedScene = load("res://actors/wobbler.tscn")
	var ci := 0
	for cid in classes:
		var c: Dictionary = classes[cid]
		var w: Wobbler = scene.instantiate()
		root.add_child(w)
		w.setup(cid, skins[ci % skins.size()], hats[ci % hats.size()], 0x39b5a8)
		w.set_weapon("spatula")
		w.set_weapon(null)
		w.set_weapon("spatula")
		# proportions from classes.json
		var wide: float = c.get("wide", 1.0)
		var deep := 1.0 + (wide - 1.0) * 0.5
		_check(is_equal_approx(w.neck.scale.x, c.get("head", 1.0)), "%s head scale %s" % [cid, w.neck.scale])
		_check(w.torso.scale.is_equal_approx(Vector3(wide, 1, deep)), "%s torso scale %s" % [cid, w.torso.scale])
		_check(is_equal_approx(w.arm_l.position.x, 0.52 * wide) and is_equal_approx(w.shoulder.position.x, -0.52 * wide), "%s shoulders" % cid)
		w.apply_state({"pos": Vector3.ZERO, "vel": Vector3.ZERO, "grounded": true})
		for i in 5:
			w.animate(1.0 / 60.0)
		var sz: float = c.get("size", 1.0)
		_check(absf(w.rig.basis.get_scale().y - sz) < 1e-3 and absf(w.rig.basis.get_scale().x - sz) < 1e-3, "%s size %s want %s" % [cid, w.rig.basis.get_scale(), sz])
		_check(absf(w.neck.basis.get_scale().x - float(c.get("head", 1.0))) < 1e-6, "%s neck pose scale" % cid)
		if c.has("skin"):
			var want := Color.hex(int(c["skin"]) << 8 | 0xff)
			_check((w.head_mesh.material_override as StandardMaterial3D).albedo_color.is_equal_approx(want), "%s skin tint" % cid)
		# swapping looks must not leak nodes or materials
		var nodes0 := _count_nodes(w)
		var mats0 := w._mats.size()
		for k in 6:
			w.set_skin(skins[(ci + k + 1) % skins.size()])
			w.set_hat(hats[(ci + k + 2) % hats.size()])
			w.set_class(classes.keys()[(ci + k) % classes.size()])
		w.setup(cid, skins[ci % skins.size()], hats[ci % hats.size()], 0x39b5a8)
		_check(_count_nodes(w) == nodes0, "%s nodes after look swaps %d != %d" % [cid, _count_nodes(w), nodes0])
		_check(w._mats.size() == mats0, "%s materials after look swaps %d != %d" % [cid, w._mats.size(), mats0])
		# scripted states
		var nodes1 := _count_nodes(w)
		var max_lean := 0.0
		var saw_flash := false
		var nodes_mid := -1
		for k in FRAMES:
			w.apply_state(_state(k, cid))
			if k % 97 == 50:
				w.hit_kick(Vector3(sin(k), 0.3, cos(k)).normalized(), 14.0)
			w.animate(1.0 / 60.0 if k % 5 else 1.0 / 30.0)
			max_lean = maxf(max_lean, absf(w.lean.x) + absf(w.lean.y))
			saw_flash = saw_flash or w._flash_k > 0.05
			if k == 449:
				nodes_mid = _count_nodes(w)
			var ok := _finite_v(w.rig.position) and _finite_b(w.rig.basis) and _finite_b(w.body.basis) and _finite_b(w.neck.basis) \
				and _finite_b(w.arm.basis) and _finite_v(w.arm.position) and _finite_v(w.arm_dir) and _finite_b(w.legs[0].basis) \
				and _finite_b(w.legs[1].basis) and _finite_b(w.arm_l.basis) and is_finite(w.lean.x + w.lean.y + w.head.x + w.head.y + w.fall_a) \
				and _finite_b(w.eyes[0].basis) and _finite_b(w.eyes[1].basis) \
				and is_finite(w.eye_open + w.brow_angle + w.panic_k + w.angry_k)
			if not ok:
				_check(false, "%s non-finite pose at frame %d" % [cid, k])
				break
		# the AK (holder + its WeaponModels tree) is built once on first equip, then nothing else may appear
		var ak := WeaponModels.build("ak")
		var ak_nodes := 1 + _count_nodes(ak)
		ak.free()
		_check(nodes_mid == nodes1 + ak_nodes and _count_nodes(w) == nodes_mid, "%s nodes during animation %d -> %d -> %d" % [cid, nodes1, nodes_mid, _count_nodes(w)])
		_check(absf(w.arm_dir.length() - 1.0) < 1e-6, "%s arm_dir not unit" % cid)
		_check(max_lean > 0.05 and max_lean < 5.0, "%s lean range %f" % [cid, max_lean])
		_check(saw_flash, "%s hit flash never lit" % cid)
		print("WOBBLER %-8s nodes=%d meshes=%d mats=%d max_lean=%.3f ok" % [cid, _count_nodes(w), w.mesh_count(), w._mats.size(), max_lean])
		w.free()
		ci += 1
	# faces (Sprint 2.4): deterministic expression checks on the shipped classes above, one rig per check
	var blink := _face_blink_checks(scene)
	var det := _face_determinism_checks(scene)
	var expr := _face_expression_checks(scene)
	var rig := _face_rig_checks(scene)
	var fighter := _face_fighter_checks()
	print("WOBBLER_FACE blink count=%d interval=%.2f..%.2f closed_frames=%d..%d min_open=%.2f" % [
		blink["count"], blink["lo"], blink["hi"], blink["closed_min"], blink["closed_max"], blink["min_open"]])
	print("WOBBLER_FACE replay blinks=%d seed_a=%d seed_b=%d" % [det["blinks"], det["seed_a"], det["seed_b"]])
	print("WOBBLER_FACE angry brow=%.2f open=%.2f | panic open=%.2f lift=%.3f" % [
		expr["brow"], expr["open_angry"], expr["open_panic"], expr["lift"]])
	print("WOBBLER_FACE rig meshes=%d nodes=%d eyes=2 mismatch=%d | LOW eye_verts=%d meshes=%d | HIGH eye_verts=%d meshes=%d" % [
		rig["meshes"], rig["nodes"], rig["mismatch"], rig["low_verts"], rig["low_meshes"], rig["high_verts"], rig["high_meshes"]])
	print("WOBBLER_FACE fighter rage=%s off_stage=%s dead_face=%s" % [fighter["rage"], fighter["off_stage"], fighter["state"]])
	for f in fails:
		print("FAIL ", f)
	print("WOBBLER_RESULT classes=%d fails=%d" % [ci, fails.size()])
	quit(0 if fails.is_empty() else 1)
