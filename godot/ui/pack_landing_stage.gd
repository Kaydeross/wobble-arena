class_name PackLandingStage
extends SubViewport
## The ONE 3D stage of a pack landing page (ui/pack_landing.gd). Two ways to use it, never both at once:
##   * a plain stage (Construction, which keeps its own page): a Wobbler in the pack's hat and outfit idling on the left and a
##     swivelling turntable on the right that shows the pack's weapons one at a time, on a transparent background;
##   * a 3D SET (ui/pack_landing_set.gd: the kitchen, the snow globe, the desert suburb): the same Wobbler and weapon standing IN a lit
##     low-poly scene, like the title's Construction showcase (ui/showcase_stage.gd). The picture fills the whole hero band; frame()
##     puts the subject into the band's stage slot with a shifted lens (a frustum camera), so the scenery runs on behind the texts,
##     and the camera sways a little round the subject.
## One SubViewport serves every pack and all its weapons: set_scene(kind) swaps the set, show_weapon(id) the model (WeaponModels.build).
## No MSAA; on a set the key light casts the page's one cheap (orthogonal) shadow, never on the lowest graphics tier.
## active = false stops rendering (page hidden / covered); spin = false (lowest tier) renders once per change instead of every frame.
## Headless nothing renders; the page only builds this stage there when a test asks for it (PackLanding.force_fx).

const SIZE := Vector2i(440, 244)          ## the plain stage: 1.8 : 1, the page shows it with the same ratio
const MAX_PIXELS := 520000.0              ## a set never renders more than this (about one hero band on a phone)
const SPIN := 0.9                         ## rad/s of the turntable's swivel
const WEAPON_H := 1.9                     ## plain stage: the weapon is scaled so its longest side is about this tall (metres)
const WEAPON_X := 1.25
const WOB_X := -1.15
const MAX_TAN := 0.95                     ## a set's camera stands far enough that the band's far edge is under this off its axis
const D_MIN := 8.0
const D_MAX := 24.0
const SWAY := 0.05                        ## rad: the camera's slow swing round the subject

var weapon_id := ""
var active := false: set = set_active
var spin := true                          ## false: no per-frame work, a still render per change
var set3d: PackLandingSet                 ## the 3D set in use (null: the plain stage)
var _pivot: Node3D
var _anchor: Node3D
var _wob: Wobbler
var _model: Node3D
var _cam: Camera3D
var _env: Environment
var _sun: DirectionalLight3D
var _rim: DirectionalLight3D
var _t := 0.0
var _look := {}
var _view := Vector2(SIZE)                ## the picture's size on the page (canvas px) and the stage slot inside it
var _slot := Rect2(Vector2.ZERO, Vector2(SIZE))
var _dist := D_MIN
var _want_kind := ""
var _want_pal := {}
var _want_title := ""
var _want_fx := true

func _init() -> void:
	name = "PackLandingStage"
	size = SIZE
	own_world_3d = true
	transparent_bg = true
	msaa_3d = Viewport.MSAA_DISABLED
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	set_process(false)

func _ready() -> void:
	_env = Environment.new()
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.shadow_blur = 1.2
	_sun.shadow_opacity = 0.6
	add_child(_sun)
	_rim = DirectionalLight3D.new()
	_rim.name = "Rim"
	var r := Vector3(-0.8, 0.7, -1.2)
	_rim.transform = Transform3D(Basis.looking_at(-r.normalized(), Vector3.UP), r)
	add_child(_rim)
	_cam = Camera3D.new()
	_cam.name = "Cam"
	add_child(_cam)
	_cam.current = true
	_pivot = Node3D.new()
	_pivot.name = "Turntable"
	add_child(_pivot)
	_anchor = Node3D.new()
	_anchor.name = "Anchor"
	_pivot.add_child(_anchor)
	_wob = preload("res://actors/wobbler.tscn").instantiate()
	add_child(_wob)
	if not _look.is_empty(): _apply_look()
	set_scene(_want_kind, _want_pal, _want_title, _want_fx)

static func renders() -> bool:
	return DisplayServer.get_name() != "headless"

# ---------------- the set ----------------

## The 3D set for `kind` ("" or a kind without one, like Construction: the plain stage). `pal`: the pack's landing palette,
## `title`: the pack's name, `fx`: particles allowed (never on the lowest tier).
func set_scene(kind: String, pal: Dictionary, title: String, fx: bool) -> void:
	_want_kind = kind
	_want_pal = pal
	_want_title = title
	_want_fx = fx
	if _wob == null: return
	var want := kind if PackLandingSet.has(kind) else ""
	if set3d != null and (set3d.kind != want or set3d.title != title or set3d.with_fx != fx):
		remove_child(set3d)
		set3d.queue_free()
		set3d = null
	if want != "" and set3d == null:
		set3d = PackLandingSet.make(want, pal, title, fx)
		add_child(set3d)
		move_child(set3d, 0)
	_apply_scene()

func _apply_scene() -> void:
	var s := set3d
	transparent_bg = s == null
	_env.background_mode = Environment.BG_COLOR if s != null else Environment.BG_CLEAR_COLOR
	_env.background_color = s.bg if s != null else Color.BLACK
	_env.ambient_light_color = s.ambient if s != null else Color(0.86, 0.88, 0.92)
	_env.ambient_light_energy = s.ambient_e if s != null else 0.62
	var p := s.key_dir if s != null else Vector3(0.6, 1.2, 1.0)
	_sun.transform = Transform3D(Basis.looking_at(-p.normalized(), Vector3.UP), p)
	_sun.light_color = s.key_col if s != null else Color.WHITE
	_sun.light_energy = s.key_e if s != null else 1.25
	_sun.shadow_enabled = s != null and s.shadow and Tier.q() > 0
	_rim.light_color = s.rim_col if s != null else Color(1.0, 0.88, 0.7)
	_rim.light_energy = s.rim_e if s != null else 0.7
	screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if s != null and Tier.q() > 0 else Viewport.SCREEN_SPACE_AA_DISABLED
	_pivot.position = s.weapon_pos if s != null else Vector3(WEAPON_X, 1.15, 0)
	_pivot.rotation = Vector3.ZERO
	_place_wob()
	if s == null:
		if size != SIZE: size = SIZE
		_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		_cam.keep_aspect = Camera3D.KEEP_HEIGHT
		_cam.fov = 30.0
		_cam.near = 0.05
		_cam.far = 100.0
		_cam.look_at_from_position(Vector3(0.05, 1.45, 6.1), Vector3(0.05, 1.12, 0), Vector3.UP)
	else:
		_place_cam()
		s.set_emitting(active and spin)
		s.animate(_t if spin else PackLandingSet.STILL_T, 0.0)
	if weapon_id != "": show_weapon(weapon_id)
	_still()

func _place_wob() -> void:
	var s := set3d
	_wob.position = s.wob_pos if s != null else Vector3(WOB_X, 0, 0)
	_wob.rotation.y = s.wob_yaw if s != null else 0.5
	var k := s.wob_scale if s != null else 1.0
	_wob.scale = Vector3(k, k, k)

## Where the set's picture goes on the page: it is `view` canvas px big and the subject belongs in `slot` (a rectangle inside it).
## The viewport takes the picture's size (never more than MAX_PIXELS).
func frame(view: Vector2, slot: Rect2) -> void:
	if view.x < 8.0 or view.y < 8.0 or slot.size.y < 8.0: return
	if view == _view and slot == _slot: return
	_view = view
	_slot = slot
	if set3d == null or _cam == null: return
	_place_cam()
	_still()

func _place_cam() -> void:
	var s := set3d
	var k := minf(1.0, sqrt(MAX_PIXELS / maxf(_view.x * _view.y, 1.0)))
	var sz := Vector2i(maxi(int(round(_view.x * k)), 16), maxi(int(round(_view.y * k)), 16))
	if sz != size: size = sz
	var m := s.view_h / _slot.size.y                      # metres per canvas px at the subject
	var c := _slot.get_center()
	_dist = clampf(maxf(c.x, _view.x - c.x) * m / MAX_TAN, D_MIN, D_MAX)
	var n := 0.5
	_cam.projection = Camera3D.PROJECTION_FRUSTUM
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.near = n
	_cam.far = 200.0
	_cam.size = _view.y * m * n / _dist
	_cam.frustum_offset = Vector2((_view.x * 0.5 - c.x) * m, (c.y - _view.y * 0.5) * m) * (n / _dist)
	_pose_cam(0.0, 0.0)
	_sun.directional_shadow_max_distance = _dist + 14.0
	s.fit(_cam.position, _dist)

func _pose_cam(yaw: float, nod: float) -> void:
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -(set3d.pitch + nod))
	_cam.transform = Transform3D(b, set3d.focus + b.z * _dist)

## Where a point of the set shows in the picture (canvas px of `view`, see frame()).
func screen_of(world: Vector3) -> Vector2:
	return _cam.unproject_position(world) * (_view / Vector2(size))

## How far in front of the camera a point is (metres along its view axis).
func depth_of(world: Vector3) -> float:
	return -(_cam.global_transform.affine_inverse() * world).z

func particle_total() -> int:
	return set3d.particle_total() if set3d != null else 0

## Everything this stage draws: mesh instances and multimeshes (the budget is PackLandingSet.MESH_CAP).
func mesh_count() -> int:
	return find_children("*", "MeshInstance3D", true, false).size() + find_children("*", "MultiMeshInstance3D", true, false).size()

## A tap on the stage: the set answers (the snow swirls, the burners flare, the kangaroo hops).
func shake() -> void:
	if set3d != null and spin: set3d.shake()

# ---------------- the Wobbler and the weapon ----------------

## The pack's wobbler: class, hat, outfit id and colour (landing.json `wobbler`).
func set_look(look: Dictionary) -> void:
	_look = look
	if _wob != null: _apply_look()

func _apply_look() -> void:
	_wob.setup(str(_look.get("class", "wobbler")), str(_look.get("skin", "none")), str(_look.get("hat", "none")), int(_look.get("color", WobblerLooks.DEFAULT_COLOR)))
	_wob.set_weapon("")
	_wob.apply_state({"pos": Vector3.ZERO, "vel": Vector3.ZERO, "yaw": 0.0, "grounded": true, "aim": Vector3(0.4, -0.2, 1)})
	for i in 90: _wob.animate(1.0 / 60.0)
	_place_wob()
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
		var k := (set3d.weapon_h if set3d != null else WEAPON_H) / maxf(longest, 0.2)
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

# ---------------- running ----------------

func set_active(on: bool) -> void:
	active = on
	if _anchor == null: return
	var live := on and renders() and spin
	render_target_update_mode = SubViewport.UPDATE_ALWAYS if live else SubViewport.UPDATE_DISABLED
	set_process(live)
	if set3d != null: set3d.set_emitting(on and spin)
	if on and renders() and not spin: _still()

## One still render (a change while not spinning, or the first frame).
func _still() -> void:
	if not renders() or _anchor == null or not is_inside_tree(): return
	if active and spin: return
	if _wob != null: _wob.animate(0.0)
	if set3d != null:
		set3d.animate(_t if spin else PackLandingSet.STILL_T, 0.0)
		_pivot.rotation.y = 0.5
	render_target_update_mode = SubViewport.UPDATE_ONCE

func _process(dt: float) -> void:
	_t += dt
	_wob.animate(dt)
	if set3d == null:
		_pivot.rotation.y = sin(_t * SPIN) * 1.05 + 0.3          # a swivel, never edge-on (the models are slim)
		_pivot.position.y = 1.15 + sin(_t * 1.6) * 0.06
		return
	_pivot.rotation.y = _t * 0.7                                 # a slow turntable
	_pivot.position.y = set3d.weapon_pos.y + sin(_t * 1.6) * 0.03
	set3d.animate(_t, dt)
	_pose_cam(sin(_t * 0.31) * SWAY, sin(_t * 0.23 + 1.0) * 0.008)
