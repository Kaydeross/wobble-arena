class_name CharacterStage
extends SubViewport
## The one 3D stage behind the Character page cards (ui/setup_wizard.gd): the real low-poly Wobbler
## (actors/wobbler.tscn + WobblerLooks: class proportions and accessories, the player's outfit, hat and colour from
## Settings) on a small pedestal, lit like a match (MapBuilder sun + hemisphere ambient, linear tonemap) plus a rim
## light from behind, with a soft sun shadow. Transparent background, so the card colour shows through.
## Cheap on a phone: one SubViewport for every card.
##   bake(ids)   renders each class once (idle pose) into a cached ImageTexture (`baked[id]`), one frame per class;
##   live(id)    puts that class on the stage and keeps rendering it (slow turn) for the selected card only;
##   active      false stops rendering (page hidden): no per-frame cost off-screen.
## Headless (tests) nothing renders: bake() just records the ids, cards keep the live ViewportTexture.

signal baked_one(id: String)

const SIZE := Vector2i(300, 380)
const SPIN := 0.7               ## rad/s for the selected card
const IDLE_YAW := 0.45          ## baked cards look a little to the side

var baked := {}                 ## class id -> ImageTexture (or null when headless)
var current := ""
var active := false: set = set_active
var _pivot: Node3D
var _wob: Wobbler
var _baking := false
var _spin := 0.0
var _want := ""                 ## the class live() asked for (applied after a bake)

func _init() -> void:
	name = "CharacterStage"
	size = SIZE
	own_world_3d = true
	transparent_bg = true
	msaa_3d = Viewport.MSAA_4X
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	set_process(false)

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.hex(0xffffffff).lerp(Color.hex(0x9bb7c4ff), 0.5)   # HemisphereLight stand-in
	env.ambient_light_energy = 0.95 / PI * 1.25
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()                     # MapBuilder.setup_sun direction, a bit brighter on a card
	sun.name = "Sun"
	sun.light_energy = 1.35 / PI * 1.6
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 12.0
	var p := Vector3(0.7, 1.2, 0.9)
	sun.transform = Transform3D(Basis.looking_at(-p.normalized(), Vector3.UP), p)
	add_child(sun)
	var rim := DirectionalLight3D.new()                     # rim: from behind and above, cool, no shadow
	rim.name = "Rim"
	rim.light_color = Color(0.8, 0.93, 1.0)
	rim.light_energy = 0.9
	var r := Vector3(-0.8, 0.9, -1.2)
	rim.transform = Transform3D(Basis.looking_at(-r.normalized(), Vector3.UP), r)
	add_child(rim)
	var ped := MeshInstance3D.new()                         # pedestal that catches the shadow
	ped.name = "Pedestal"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.95; cm.bottom_radius = 1.0; cm.height = 0.12; cm.radial_segments = 16
	ped.mesh = cm
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.2, 0.42, 0.47)
	pm.roughness = 1.0
	ped.material_override = pm
	ped.position.y = -0.06
	add_child(ped)
	var cam := Camera3D.new()
	cam.name = "Cam"
	cam.fov = 30.0
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.55, 5.3), Vector3(0, 1.0, 0), Vector3.UP)
	cam.current = true
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	_wob = preload("res://actors/wobbler.tscn").instantiate()
	_pivot.add_child(_wob)

static func renders() -> bool:
	return DisplayServer.get_name() != "headless"

## The player's look from Settings (outfit, hat, colour: what the match will show).
static func look() -> Dictionary:
	var sk: Dictionary = Content.cosmetics.get("skins", {}).get(str(Settings.get_value("skin", "none")), {})
	var col := int(sk.get("col", Settings.get_value("color", WobblerLooks.DEFAULT_COLOR)))
	return {"skin": str(Settings.get_value("skin", "none")), "hat": str(Settings.get_value("hat", "none")), "color": col}

## Puts class `id` on the stage and lets the springs settle into the idle pose.
func pose(id: String, yaw: float) -> void:
	var lk := look()
	_wob.setup(id, lk["skin"], lk["hat"], lk["color"])
	_wob.set_weapon("")
	_wob.apply_state({"pos": Vector3.ZERO, "vel": Vector3.ZERO, "yaw": 0.0, "grounded": true, "aim": Vector3(0, -0.4, 1)})
	for i in 90: _wob.animate(1.0 / 60.0)
	_pivot.rotation.y = yaw
	current = id

## Renders every class once into `baked` (one frame each), then goes back to the live class.
func bake(ids: Array) -> void:
	if _baking: return
	_baking = true
	set_process(false)
	for id: String in ids:
		if baked.has(id): continue
		if not renders() or not is_inside_tree():
			baked[id] = null
			continue
		pose(id, IDLE_YAW)
		render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		if not is_inside_tree(): break
		var img := get_texture().get_image()
		baked[id] = ImageTexture.create_from_image(img) if img and not img.is_empty() else null
		baked_one.emit(id)
	_baking = false
	if _want != "": pose(_want, _spin)
	set_active(active)

func is_baking() -> bool:
	return _baking

## The selected card's class, turning slowly.
func live(id: String) -> void:
	_want = id
	if _baking: return
	if id != current: pose(id, _spin)
	set_active(active)

func set_active(on: bool) -> void:
	active = on
	if _baking: return
	render_target_update_mode = SubViewport.UPDATE_ALWAYS if on and renders() else SubViewport.UPDATE_DISABLED
	set_process(on)

func _process(dt: float) -> void:
	_spin = wrapf(_spin + SPIN * dt, -PI, PI)
	_pivot.rotation.y = _spin
	_wob.animate(dt)
