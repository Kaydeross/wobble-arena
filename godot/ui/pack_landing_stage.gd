class_name PackLandingStage
extends SubViewport
## The ONE 3D stage of a pack landing page (ui/pack_landing.gd): a Wobbler in the pack's hat and outfit idling on the left, and a
## swivelling turntable on the right that shows the pack's weapons one at a time, built by the real WeaponModels.build(id). One SubViewport
## serves all six weapons: show_weapon(id) swaps the model, nothing else is created. Transparent background, no shadows, no MSAA
## (the page is a menu; it has to leave the frame budget to the phone). active = false stops rendering (page hidden / covered);
## spin = false (lowest graphics tier) renders once per change instead of every frame.
## Headless nothing renders; the page only builds this stage there when a test asks for it (PackLanding.force_fx).

const SIZE := Vector2i(440, 244)          ## 1.8 : 1, the page shows it with the same ratio
const SPIN := 0.9                         ## rad/s of the turntable's swivel
const WEAPON_H := 1.9                     ## the weapon is scaled so its longest side is about this tall (metres)
const WEAPON_X := 1.25
const WOB_X := -1.15

var weapon_id := ""
var active := false: set = set_active
var spin := true                          ## false: no per-frame work, a still render per change
var _pivot: Node3D
var _anchor: Node3D
var _wob: Wobbler
var _model: Node3D
var _t := 0.0
var _look := {}

func _init() -> void:
	name = "PackLandingStage"
	size = SIZE
	own_world_3d = true
	transparent_bg = true
	msaa_3d = Viewport.MSAA_DISABLED
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	set_process(false)

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.86, 0.88, 0.92)
	env.ambient_light_energy = 0.62
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.25
	sun.shadow_enabled = false
	var p := Vector3(0.6, 1.2, 1.0)
	sun.transform = Transform3D(Basis.looking_at(-p.normalized(), Vector3.UP), p)
	add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.name = "Rim"
	rim.light_color = Color(1.0, 0.88, 0.7)
	rim.light_energy = 0.7
	var r := Vector3(-0.8, 0.7, -1.2)
	rim.transform = Transform3D(Basis.looking_at(-r.normalized(), Vector3.UP), r)
	add_child(rim)
	var cam := Camera3D.new()
	cam.name = "Cam"
	cam.fov = 30.0
	add_child(cam)
	cam.look_at_from_position(Vector3(0.05, 1.45, 6.1), Vector3(0.05, 1.12, 0), Vector3.UP)
	cam.current = true
	_pivot = Node3D.new()
	_pivot.name = "Turntable"
	_pivot.position = Vector3(WEAPON_X, 1.15, 0)
	add_child(_pivot)
	_anchor = Node3D.new()
	_anchor.name = "Anchor"
	_pivot.add_child(_anchor)
	_wob = preload("res://actors/wobbler.tscn").instantiate()
	_wob.position = Vector3(WOB_X, 0, 0)
	_wob.rotation.y = 0.5
	add_child(_wob)
	if not _look.is_empty(): _apply_look()
	if weapon_id != "": show_weapon(weapon_id)

static func renders() -> bool:
	return DisplayServer.get_name() != "headless"

## The pack's wobbler: class, hat, outfit id and colour (landing.json `wobbler`).
func set_look(look: Dictionary) -> void:
	_look = look
	if _wob != null: _apply_look()

func _apply_look() -> void:
	_wob.setup(str(_look.get("class", "wobbler")), str(_look.get("skin", "none")), str(_look.get("hat", "none")), int(_look.get("color", WobblerLooks.DEFAULT_COLOR)))
	_wob.set_weapon("")
	_wob.apply_state({"pos": Vector3.ZERO, "vel": Vector3.ZERO, "yaw": 0.0, "grounded": true, "aim": Vector3(0.4, -0.2, 1)})
	for i in 90: _wob.animate(1.0 / 60.0)
	_wob.position = Vector3(WOB_X, 0, 0)
	_wob.rotation.y = 0.5
	_still()

## Swaps the turntable model to weapon `id` (WeaponModels.build), fitted and centred, long side leaning up.
func show_weapon(id: String) -> void:
	weapon_id = id
	if _anchor == null: return
	if _model != null:
		_anchor.remove_child(_model)
		_model.queue_free()
		_model = null
	_model = WeaponModels.build(id)
	_anchor.add_child(_model)
	_anchor.transform = Transform3D.IDENTITY
	var b := _bounds(_model)
	if b.size.length() > 0.001:
		var ax := 1                                           # the longest axis of the model
		if b.size.x >= b.size.y and b.size.x >= b.size.z: ax = 0
		elif b.size.z > b.size.y: ax = 2
		var longest := maxf(b.size.x, maxf(b.size.y, b.size.z))
		var k := WEAPON_H / maxf(longest, 0.2)
		var to_up := Basis.IDENTITY                          # long side up (then leaned 28 degrees so it reads as a prop)
		if ax == 0: to_up = Basis(Vector3.BACK, PI * 0.5)
		elif ax == 2: to_up = Basis(Vector3.RIGHT, -PI * 0.5)
		var lean := Basis(Vector3.BACK, deg_to_rad(-28.0))
		var basis := (lean * to_up).scaled(Vector3(k, k, k))
		var c := b.get_center()
		_anchor.transform = Transform3D(basis, -(basis * c))
	_still()

## The model's bounds in its own space (mesh AABBs through their transforms below `root`).
func _bounds(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv := root.transform.affine_inverse()
	for mi: Node in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null: continue
		var xf := inv * _rel(root, m)
		var bb := m.mesh.get_aabb()
		for k in 8:
			var q := xf * bb.get_endpoint(k)
			if first:
				out = AABB(q, Vector3.ZERO)
				first = false
			else:
				out = out.expand(q)
	return out

## `n`'s transform relative to `root`'s parent space (does not need the tree).
func _rel(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root.get_parent():
		if cur is Node3D: xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf

func set_active(on: bool) -> void:
	active = on
	if _anchor == null: return
	var live := on and renders() and spin
	render_target_update_mode = SubViewport.UPDATE_ALWAYS if live else SubViewport.UPDATE_DISABLED
	set_process(live)
	if on and renders() and not spin: _still()

## One still render (a change while not spinning, or the first frame).
func _still() -> void:
	if not renders() or _anchor == null or not is_inside_tree(): return
	if active and spin: return
	if _wob != null: _wob.animate(0.0)
	render_target_update_mode = SubViewport.UPDATE_ONCE

func _process(dt: float) -> void:
	_t += dt
	_pivot.rotation.y = sin(_t * SPIN) * 1.05 + 0.3          # a swivel, never edge-on (the models are slim)
	_pivot.position.y = 1.15 + sin(_t * 1.6) * 0.06
	_wob.animate(dt)
