extends SceneTree
## Ragdoll overlay screenshots (docs/RAGDOLL.md; needs a real renderer, opens a window):
##   godot --path godot --resolution 1280x720 --script res://tests/ragdoll_shots.gd -- --no-save --out DIR [--mode classic]
## Saves DIR/godot-ragdoll-{running,midstride,hit,down,getup}.png. Fighters are driven by scripted FighterStates.

const DT := 1.0 / 60.0
const SHOTS := ["running", "midstride", "hit", "down", "getup"]
const LOOKS := [["wobbler", "none", "none", 0x39b5a8], ["bruiser", "hoodie", "top", 0xe3566b], ["kid", "sporty", "party", 0x4a90d9]]

var out_dir := "."
var mode := "ragdoll"
var idx := 0
var stage: Node3D
var cam: Camera3D


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--out" and i + 1 < a.size(): out_dir = a[i + 1]
		if a[i] == "--mode" and i + 1 < a.size(): mode = a[i + 1]
	process_frame.connect(_next, CONNECT_ONE_SHOT)


func _build_stage() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.hex(0xbfe3f2ff)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.hex(0xdfe9eeff)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	stage.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	stage.add_child(sun)
	sun.look_at_from_position(Vector3(4, 10, 6), Vector3.ZERO, Vector3.UP)
	var floor_m := StandardMaterial3D.new()
	floor_m.albedo_color = Color.hex(0x8fd16aff)
	floor_m.roughness = 1.0
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	fl.mesh = pm
	fl.material_override = floor_m
	stage.add_child(fl)
	var grid_m := StandardMaterial3D.new()
	grid_m.albedo_color = Color.hex(0x7cbd58ff)
	for i in range(-20, 21, 2):                       # floor stripes so foot planting reads
		var st := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.06, 0.005, 80)
		st.mesh = bm
		st.material_override = grid_m
		st.position = Vector3(i, 0.003, 0)
		stage.add_child(st)
	cam = Camera3D.new()
	cam.fov = 40
	stage.add_child(cam)
	cam.current = true


func _w(look: Array) -> Wobbler:
	var w: Wobbler = load("res://actors/wobbler.tscn").instantiate()
	stage.add_child(w)
	w.rig_mode = mode
	w.setup(look[0], look[1], look[2], look[3])
	w.set_weapon("spatula")
	return w


func _step(w: Wobbler, s: Dictionary) -> void:
	w.apply_state(s)
	w.animate(DT)
	if w.rig_mode == "ragdoll":
		w.overlay(DT)


## Straight-line run along +X at speed v, starting at x0 (frame k).
func _run_state(k: int, x0: float, z: float, v: float) -> Dictionary:
	return {"pos": Vector3(x0 + v * k * DT, 0, z), "vel": Vector3(v, 0, 0), "yaw": PI / 2, "grounded": true,
		"wish": Vector2(1, 0), "aim": Vector3(1, -0.15, 0), "hp": 100.0}


func _next() -> void:
	if stage: stage.free()
	if idx >= SHOTS.size():
		quit(0); return
	_build_stage()
	var shot: String = SHOTS[idx]
	var focus := Vector3.ZERO
	match shot:
		"running", "midstride":
			var ws: Array[Wobbler] = []
			var n := 3 if shot == "running" else 1
			for i in n: ws.append(_w(LOOKS[i]))
			var frames := 100 if shot == "running" else 200
			for k in frames:
				for i in n:
					_step(ws[i], _run_state(k + i * 7, -10.0 - i * 1.2, i * 2.2 - 2.2 if n > 1 else 0.0, 6.6 - i * 1.4))
				if shot == "midstride" and k > 120 and mode == "ragdoll":
					var r := ws[0].rag
					var mid := (r.step_t[0] > 0.45 and r.step_t[0] < 0.6) or (r.step_t[1] > 0.45 and r.step_t[1] < 0.6)
					if mid: break
			focus = ws[0].pos + Vector3(-0.6 if n > 1 else 0.0, 1.0, 2.0 if n > 1 else 0.0)
			cam.look_at_from_position(focus + (Vector3(1.2, 1.4, 9.5) if n > 1 else Vector3(0.0, 0.6, 5.2)), focus, Vector3.UP)
		"hit":
			var v := _w(LOOKS[0])
			var a := _w(LOOKS[1])
			var base := {"vel": Vector3.ZERO, "grounded": true, "hp": 100.0, "aim": Vector3(-1, -0.1, 0)}
			for k in 66:
				var sv := base.duplicate()
				sv["pos"] = Vector3(0.6 * clampf((k - 58) / 10.0, 0.0, 1.0), 0, 0)
				sv["yaw"] = -PI / 2
				sv["vel"] = Vector3(4.0 if k >= 58 else 0.0, 0, 0)
				if k >= 58: sv["hp"] = 70.0
				var sa := base.duplicate()
				sa["pos"] = Vector3(-1.9, 0, 0)
				sa["yaw"] = PI / 2
				sa["aim"] = Vector3(1, 0, 0)
				sa["swing"] = clampf((k - 46) / 14.0, 0.0, 1.29) if k >= 46 else -1.0
				_step(a, sa)
				v.apply_state(sv)
				if k == 58: v.hit_kick(Vector3(1, 0.25, 0).normalized(), 16.0)
				v.animate(DT)
				if v.rig_mode == "ragdoll": v.overlay(DT)
			focus = Vector3(-0.6, 1.1, 0)
			cam.look_at_from_position(focus + Vector3(0.8, 0.9, 5.4), focus, Vector3.UP)
		"down", "getup":
			var w := _w(LOOKS[0])
			var frames := 60 + (55 if shot == "down" else 76)
			for k in frames:
				var s := {"pos": Vector3.ZERO, "vel": Vector3.ZERO, "yaw": 0.4, "grounded": true, "hp": 100.0, "aim": Vector3(0.3, -0.2, 1)}
				if k >= 60 and k < 120:
					s["down_t"] = 1.0 - (k - 60) / 60.0
					s["fall_side"] = 1.0
					s["hp"] = 75.0
				if k == 60: w.hit_kick(Vector3(-0.8, 0.3, -0.5).normalized(), 15.0)
				_step(w, s)
			focus = Vector3(0, 0.6, 0)
			cam.look_at_from_position(focus + Vector3(3.2, 1.6, 3.6), focus, Vector3.UP)
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join("godot-ragdoll-%s%s.png" % [shot, "" if mode == "ragdoll" else "-classic"])
	root.get_texture().get_image().save_png(path)
	print("SHOT ", path)
	idx += 1
	_next.call_deferred()
