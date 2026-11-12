extends Node3D
## Weapon showcase: every WeaponModels model in a labelled grid (modes grid1, grid2) or held by wobblers (mode held).
## With --shot PATH it renders a few frames, saves a PNG and quits (tools/shoot-godot-weapons.sh).
##   godot --path godot res://actors/weapons_showcase.tscn -- --mode grid1 --shot /tmp/x.png

const COLS := 7
const CELL := Vector2(2.5, 3.7)
const HELD := ["ak", "katana", "rocket", "bow"]
const SWATCH := [0x39b5a8, 0xe3566b, 0x4a90d9, 0xf0b13c]

var mode := "grid1"
var shot := ""
var shot_frames := 0
var wobblers: Array[Wobbler] = []
var states: Array[Dictionary] = []


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--mode" and i + 1 < a.size():
			mode = a[i + 1]
		elif a[i] == "--shot" and i + 1 < a.size():
			shot = a[i + 1]
	_stage()
	if mode == "held":
		_held()
	else:
		_grid(0 if mode == "grid1" else 14)


func _stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.hex(0xbfe3f2ff)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.hex(0xdfe9eeff)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.1
	add_child(sun)
	sun.look_at_from_position(Vector3(22, 38, 12) * 0.1, Vector3.ZERO, Vector3.UP)


func _grid(first: int) -> void:
	var keys := WeaponModels.KEYS.slice(first, first + 14)
	var rows := 2
	for i in keys.size():
		var col := i % COLS
		var row := i / COLS
		var c := Vector3((col - (COLS - 1) / 2.0) * CELL.x, (0.5 - row) * CELL.y, 0)
		var holder := Node3D.new()
		holder.position = c
		holder.rotation.y = deg_to_rad(-55)                    # three-quarter view: side profile of guns, face of blades
		add_child(holder)
		var m := WeaponModels.build(keys[i])
		holder.add_child(m)
		var bb := WeaponModels.bounds(m)
		m.position = -(bb.position + bb.size * 0.5) + Vector3(0, 0.25, 0)
		var s := clampf(2.5 / maxf(bb.size.y, bb.size.x * 1.5), 0.0, 2.4)
		holder.scale = Vector3.ONE * s
		var l := Label3D.new()
		l.text = keys[i]
		l.font_size = 96
		l.pixel_size = 0.0045
		l.modulate = Color.hex(0x1b2a33ff)
		l.outline_size = 0
		l.no_depth_test = true
		l.position = c + Vector3(0, -CELL.y * 0.5 + 0.28, 0.5)
		add_child(l)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = rows * CELL.y
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 8, 18), Vector3.ZERO, Vector3.UP)
	cam.current = true


func _held() -> void:
	for i in HELD.size():
		var w: Wobbler = preload("res://actors/wobbler.tscn").instantiate()
		add_child(w)
		w.setup("wobbler", "none", "none", SWATCH[i])
		w.set_weapon(HELD[i])
		var yaw := 0.35
		var aim := Vector3(sin(yaw) * 0.9, -0.35, cos(yaw) * 0.9).normalized()
		if HELD[i] in ["katana", "bow"]:
			aim = Vector3(sin(yaw) * 0.5, -0.8, cos(yaw) * 0.5).normalized()
		var st := {"pos": Vector3((i - 1.5) * 3.2, 0, 0), "vel": Vector3.ZERO, "yaw": yaw, "grounded": true, "aim": aim}
		wobblers.append(w)
		states.append(st)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color.hex(0x8fd16aff)
	ground.material_override = gm
	add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 2.4, 9.5), Vector3(0, 1.2, 0), Vector3.UP)
	cam.current = true
	for k in 240:
		_tick(1.0 / 60.0)


func _tick(dt: float) -> void:
	for i in wobblers.size():
		wobblers[i].apply_state(states[i])
		wobblers[i].animate(dt)


func _process(dt: float) -> void:
	_tick(dt)
	if shot == "":
		return
	shot_frames += 1
	if shot_frames == 8:
		var img := get_viewport().get_texture().get_image()
		img.save_png(shot)
		print("SHOT ", shot, " ", img.get_size())
		get_tree().quit()
