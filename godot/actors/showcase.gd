extends Node3D
## Wobbler showcase: lays characters out in a row under a simple sky light and camera.
## Modes (user arg --mode): classes (all 5 classes), outfits (classes in outfits + hats), hats (every hat), poses (animation poses).
## With --shot PATH it renders a few frames, saves a PNG and quits (tools/shoot-godot-showcase.sh).
##   godot --path godot res://actors/showcase.tscn -- --mode classes --shot /tmp/x.png

const CLASS_IDS := ["wobbler", "bruiser", "kid", "elder", "alien"]
const OUTFITS := ["hoodie", "skater", "chef", "suit", "sporty"]
const OUTFIT_HATS := ["party", "top", "crown", "wizard", "cowboy"]
const SWATCH := [0x39b5a8, 0xe3566b, 0x4a90d9, 0xf0b13c, 0x8e6bd8]

var mode := "classes"
var shot := ""
var wobblers: Array[Wobbler] = []
var states: Array[Dictionary] = []
var frame := 0
var shot_frames := 0
var cam: Camera3D


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--mode" and i + 1 < a.size():
			mode = a[i + 1]
		elif a[i] == "--shot" and i + 1 < a.size():
			shot = a[i + 1]
	_stage()
	match mode:
		"outfits":
			for i in 5:
				_add(CLASS_IDS[i], OUTFITS[i], OUTFIT_HATS[i], SWATCH[i], Vector3((i - 2) * 2.3, 0, 0))
		"hats":
			var hats: Array = WobblerLooks.data("cosmetics").get("hats", [])
			for i in hats.size():
				var row := i / 8
				var col := i % 8
				_add("wobbler", "none", hats[i], SWATCH[i % SWATCH.size()], Vector3((col - 3.5) * 2.0, 0, -row * 2.8))
		"poses":
			_poses()
		_:
			for i in 5:
				_add(CLASS_IDS[i], "none", "none", SWATCH[0], Vector3((i - 2) * 2.3, 0, 0))
	_camera()
	for i in 240:                                     # let the springs settle into the pose
		_tick(1.0 / 60.0)


func _stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.hex(0xbfe3f2ff)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.hex(0xdfe9eeff)          # roughly the web game's hemisphere light (sky white, ground 0x9bb7c4)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()                       # web sun at (22, 38, 12)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
	sun.look_at_from_position(Vector3(22, 38, 12) * 0.1, Vector3.ZERO, Vector3.UP)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color.hex(0x8fd16aff)
	gm.roughness = 1.0
	ground.material_override = gm
	add_child(ground)


func _camera() -> void:
	cam = Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	match mode:
		"hats":
			cam.look_at_from_position(Vector3(0, 6.5, 13.5), Vector3(0, 1.2, -1.4), Vector3.UP)
		_:
			cam.look_at_from_position(Vector3(0, 3.0, 12.0), Vector3(0, 1.25, 0), Vector3.UP)
	cam.current = true


func _add(cid: String, skin: String, hat: String, col: int, p: Vector3, extra: Dictionary = {}) -> Wobbler:
	var w: Wobbler = preload("res://actors/wobbler.tscn").instantiate()
	add_child(w)
	w.setup(cid, skin, hat, col)
	w.set_weapon("spatula")
	var st := {"pos": p, "vel": Vector3.ZERO, "yaw": 0.3, "grounded": true, "aim": Vector3(sin(0.3) * 0.5, -0.45, cos(0.3) * 0.5)}
	st.merge(extra, true)
	wobblers.append(w)
	states.append(st)
	return w


func _poses() -> void:
	var y := 0.3
	_add("wobbler", "none", "none", SWATCH[0], Vector3(-5.6, 0, 0), {"vel": Vector3(sin(y), 0, cos(y)) * 6.5, "wish": Vector2(1, 0)})     # running
	_add("wobbler", "none", "none", SWATCH[1], Vector3(-2.8, 0, 0), {"swing": 0.45, "_swing_run": true})                               # spatula swing
	_add("wobbler", "none", "none", SWATCH[2], Vector3(0, 0, 0), {"kick_t": 0.55, "_kick_run": true})                                  # kick
	_add("wobbler", "none", "none", SWATCH[3], Vector3(2.8, 0, 0), {"crouch": 1.0})                                                       # crouch
	_add("wobbler", "none", "none", SWATCH[4], Vector3(5.6, 0, 0), {"dead": true, "fall_side": 1.0})                                     # knocked out
	states[3]["flash"] = 0.12                       # crouching, in the middle of a hit flash


func _tick(dt: float) -> void:
	for i in wobblers.size():
		var st: Dictionary = states[i].duplicate()
		if st.get("_swing_run", false):               # start the swing a few frames before the shot so it is caught mid-arc
			st["swing"] = (frame - 228) * dt / 0.34 if frame >= 228 and frame < 240 + 20 else -1.0
		if st.get("_kick_run", false):
			st["kick_t"] = (frame - 220) * dt / 0.55 if frame >= 220 and frame < 240 + 33 else -1.0
		var w := wobblers[i]
		w.apply_state(st)
		w.animate(dt)
	frame += 1


func _process(dt: float) -> void:
	if shot == "":
		_tick(dt)
		return
	shot_frames += 1
	if shot_frames == 8:
		var img := get_viewport().get_texture().get_image()
		img.save_png(shot)
		print("SHOT ", shot, " ", img.get_size())
		get_tree().quit()
