extends Node3D
## Offline test world: builds a map with MapBuilder, drives a placeholder player with FighterPhysics at the web game's
## fixed step (SIM = 1/120, one accumulator, like `frame`/`simStep` in public/index.html ~10077 / ~9612) and follows it
## with the third-person camera. Input comes from one InputState fed by keyboard/mouse, gamepad and touch.
## Map from the export var, or `-- --map=<id>` on the command line.

const SIM := 1.0 / 120.0
const FALL_Y := -25.0          ## below this the player has fallen out and respawns
const PLAYER_COLOR := 0xffd23f

@export var map_id := "arena"
## false = the sim only advances when sim_step() is called (headless tests)
@export var auto_run := true

@onready var env_node: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun
@onready var cam: FollowCamera = $Camera
@onready var player_node: Node3D = $Player
@onready var input: PlayerInput = $PlayerInput
@onready var touch: TouchControls = $UI/TouchControls
@onready var hud: Label = $UI/Hud
@onready var pause_menu: Control = $UI/Pause

var phys := FighterPhysics.new()
var map_node: MapBuilder.MapNode
var solids: Array = []
var acc := 0.0
var sim_time := 0.0
var paused := false
var face_yaw := PI
var falls := 0
var last_tap := ""
var _prev_pos := Vector3.ZERO
var _fps_t := 0.0
var _touch_was := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			map_id = a.substr(6)
	Tier.configure_viewport(get_viewport())
	touch.state = input.state
	touch.pause_pressed.connect(_toggle_pause)
	input.pause_requested.connect(_toggle_pause)
	$UI/Pause/Box/Resume.pressed.connect(_toggle_pause)
	$UI/Pause/Box/Title.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main.tscn"))
	pause_menu.visible = false
	load_map(map_id)

func load_map(id: String) -> void:
	if map_node:
		map_node.queue_free()
	map_id = id
	map_node = MapBuilder.build(id)
	add_child(map_node)
	solids = map_node.solids
	env_node.environment = MapBuilder.make_environment(map_node.map)
	MapBuilder.setup_sun(sun, map_node.map)
	Tier.configure_sun(sun, map_node.shadow_area)
	phys.ice_grip = map_node.map.has("grip")
	respawn()

func respawn() -> void:
	var p := map_node.spawn_point()
	phys.place(p.x, p.y, p.z)
	phys.grounded = false
	_prev_pos = p
	# face the middle of the map, like the online spawn (index.html ~8845)
	cam.yaw = atan2(-p.x, -p.z) if Vector2(p.x, p.z).length() > 0.5 else PI
	cam.pitch = -0.2
	face_yaw = cam.yaw
	_sync_visual(p)

func player_pos() -> Vector3:
	return Vector3(phys.px, phys.py, phys.pz)

## One fixed simulation step (the order follows playerControl + Fighter.physics, index.html ~9391 / ~5569).
func sim_step(dt: float) -> void:
	var st := input.state
	var mv := st.move()
	var f := mv.y
	var r := mv.x
	var s := sin(cam.yaw)
	var c := cos(cam.yaw)
	var wish := Vector2(s * f - c * r, c * f + s * r).limit_length(1.0)
	phys.wish_x = wish.x
	phys.wish_z = wish.y
	var aiming := st.aiming()
	var squat := st.is_held("crouch")
	var sprint := st.is_held("sprint") and not aiming and f > 0.0 and not squat
	phys.speed = (3.8 if aiming else (10.5 if sprint else 7.5)) * (0.5 if squat else 1.0)
	phys.crouch_k += ((1.0 if squat else 0.0) - phys.crouch_k) * minf(1.0, dt * 12.0)
	if st.is_held("jump") and not squat:
		phys.want_jump = true
	for a in ["swap", "reload", "shove", "kick", "dash", "spatula", "slot1", "slot2", "slot3"]:
		if st.consume(a):
			last_tap = a   # weapon/combat actions arrive with the combat track; shown on the HUD for now
	# facing: the camera direction while aiming/firing, else the direction of travel
	if aiming or st.is_held("fire"):
		face_yaw = cam.yaw
	elif Vector2(phys.vx, phys.vz).length() > 0.8 and wish.length() > 0.05:
		face_yaw = atan2(phys.vx, phys.vz)
	phys.step(dt, solids)
	sim_time += dt
	if phys.py < FALL_Y:
		falls += 1
		respawn()

func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	if not paused:
		cam.add_look(input.state.take_look())
	if auto_run and not paused:
		acc += minf(dt, 0.1)
		while acc >= SIM:
			_prev_pos = player_pos()
			sim_step(SIM)
			acc -= SIM
	var vis := _prev_pos.lerp(player_pos(), clampf(acc / SIM, 0.0, 1.0)) if auto_run else player_pos()
	_sync_visual(vis)
	cam.follow(dt, vis, input.state.aiming() and not paused, solids)
	_update_hud(delta)

func _sync_visual(p: Vector3) -> void:
	player_node.position = p
	player_node.rotation.y = lerp_angle(player_node.rotation.y, face_yaw, 0.35)
	var body: Node3D = player_node.get_node("Body")
	body.scale.y = 1.0 - 0.75 / FighterPhysics.FH * phys.crouch_k
	body.position.y = FighterPhysics.FH * body.scale.y / 2.0

func _update_hud(delta: float) -> void:
	_fps_t += delta
	if _fps_t < 0.25:
		return
	_fps_t = 0.0
	var name_s := str(map_node.map.get("name", map_id)) if map_node else map_id
	var hint := ""
	if Tier.is_pc() and not touch.visible and not input.mouse_captured() and not paused:
		hint = "\nClick to look around (Esc: menu)"
	hud.text = "%s  |  %s  |  %d fps  |  %s%s%s" % [name_s, Tier.tier_name(), Engine.get_frames_per_second(),
		"grounded" if phys.grounded else "air", ("  |  " + last_tap) if last_tap != "" else "", hint]

func _toggle_pause() -> void:
	paused = not paused
	pause_menu.visible = paused
	touch.release_all()
	if paused:
		_touch_was = touch.visible
		touch.visible = false
	else:
		touch.visible = _touch_was
	input.state.clear()
	if paused:
		input.release_mouse()
	acc = 0.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED and not paused and auto_run:
		_toggle_pause()   # phones: app sent to background
