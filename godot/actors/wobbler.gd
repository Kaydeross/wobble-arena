class_name Wobbler
extends Node3D
## The blocky low-poly character, VISUAL ONLY (no gameplay). Built in code like the web `Fighter` constructor and
## animated like `Fighter.animate` + `Fighter.applyPose` (public/index.html, CODEMAP section 8), with Spring2 wobble.
##
## API (docs/GODOT_ARCH.md): setup(class_id, skin, hat, color); apply_state(state) each frame; animate(dt);
## hit_kick(dir, force); set_weapon(key). Coordinates match the web game (Y up, a fighter at yaw 0 faces +Z).
## Keep this node at the identity transform inside the world: `pos` in the state is used as-is for the rig.
##
## FighterState keys read (all optional except pos): pos, vel, yaw, aim (arm target direction), grounded, crouch (0..1),
## dead, down_t, weapon, swing (-1 idle, 0..1.3), kick_t (-1 idle, 0..1), invuln, flash (seconds left, web 0.12 = full),
## class_id, skin, hat, color. Extras the web game has that the contract doesn't (yet): wish (Vector2 move input, for
## the stride), trap (bool, lying under a net), stiff (arm spring stiffness), fall_side (+1/-1).
## Faces (Sprint 2.4, docs/GRAPHICS.md): rage (float, FighterState.rage_t seconds left) and off_stage / panic (bool,
## airborne off the arena floor, falling to a ring-out); both optional, safe defaults keep the face idle.

const SIM_DOWN := Vector3(0, -1, 0)
const FLASH_FULL := 0.12            # web Fighter.flash after a hit (seconds)

# --- faces (Sprint 2.4): the 2-mesh eye rig, transformed, never added to. Docs: docs/GRAPHICS.md "Faces".
const EYE_SIZE := Vector3(0.1, 0.14, 0.06)   # the eye box the web game draws
const EYE_X := 0.13                          # eye offset on the head (neck space)
const EYE_Y := 0.36
const EYE_Z := 0.32
const BROW_SIZE := Vector3(0.13, 0.032, 0.05)   # brow bar merged into the eye mesh above LOW
const BROW_Y := 0.105                            # brow centre above the eye centre (same mesh, one draw call)
const X_EYE_SIZE := Vector3(0.15, 0.026, 0.05)   # one bar of the down/dead X (two bars, one surface)
const BLINK_WAIT_MIN := 2.5                  # idle blink: seconds between blink starts (own RNG)
const BLINK_WAIT_MAX := 4.5
const BLINK_DUR := 0.16                      # how long the eyes take to close and open (~10 frames at 60 Hz)
const ANGRY_ANGLE := 0.34                    # brow slant (rad) at full anger: inner ends down
const ANGRY_SQUINT := 0.78                   # eye height at full anger
const ANGRY_DROP := 0.006                    # eye/brow drop while angry (m)
const PANIC_WIDE := 1.34                     # eye height at full panic
const PANIC_WIDE_X := 1.18                   # eye width at full panic
const PANIC_LIFT := 0.014                    # eye/brow lift while panicking (m)
const PANIC_ANGLE := 0.11                    # brow inner ends up while panicking (rad)
const FACE_K_ANGRY := 12.0                   # blend rates (1/s)
const FACE_K_PANIC := 14.0

## Hit flash 0..1 (drives emission like the web game's emissive); decays by itself unless the state drives it.
var flash: float = 0.0
var class_id: String = ""
var skin_key: String = "none"
var hat_name: String = "none"
var color: int = WobblerLooks.DEFAULT_COLOR
var weapon: String = ""
var cls: Dictionary = {}

# --- rig nodes (same hierarchy as the JS Fighter). Post-v0.4.0 Sprint 4.2: the static meshes of every rigidly
# animated node are merged into ONE MeshInstance3D per node ("body mesh", "head mesh", ...), so a fighter costs ~12
# draws instead of ~35. The gameplay points the Fighter/Combat read (torso, head_mesh, hand, arm, arm_l, shoulder,
# legs) stay real nodes with exactly the old transforms: torso/head_mesh are plain Node3D markers now (their geometry
# lives in the body/neck merged meshes), and the ragdoll overlay's nodes (body, neck, legs, foot_meshes, arm, arm_l,
# arm_sleeve, arm_hand_mesh, hand) are unchanged. See docs/GRAPHICS.md "Fighter mesh batching".
var rig: Node3D                      # JS root: position, yaw, fall roll, squash
var body: Node3D
var neck: Node3D
var torso: Node3D                    # gameplay point (chest); the torso geometry is merged into body_mesh
var head_mesh: Node3D                # gameplay point (head) + eye parent; the head geometry is merged into neck_mesh
var eyes: Array[MeshInstance3D] = []
var legs: Array[Node3D] = []
var arm_l: Node3D
var shoulder: Node3D
var arm: Node3D                      # the aiming arm, positioned in world space each frame
var hand: Node3D
var hat: Node3D
var hat_spin: Node3D

# --- merged (batched) meshes: one per rigid node, plus the standalone animated ones the ragdoll overlay writes
var body_mesh: MeshInstance3D        # child of body: torso + belt + buckle + body-attached look parts
var neck_mesh: MeshInstance3D        # child of neck: head + neck-attached look parts
var arm_l_mesh: MeshInstance3D       # child of arm_l: off-arm sleeve + hand + armL look parts
var arm_mesh: MeshInstance3D         # child of arm: look parts attached to the aiming arm (none in the shipped looks)
var leg_meshes: Array[MeshInstance3D] = []   # children of legs[i] (named "Thigh" for the Locker): thigh + leg look parts
var _hat_meshes: Array[MeshInstance3D] = []  # hat chunks: one merged mesh, or one per part for hats with >= 6 parts
var _weapon_holder: Node3D
var _weapon_mi: MeshInstance3D
var _weapon_nodes: Dictionary = {}   # current key -> holder (locker_test reads it for the emote put-away contract)

# --- materials. Post-batching every part colour is baked into the mesh's vertex COLOR and the surfaces share one
# static material per role; the only per-fighter material is the flash one (hit flash / invulnerability drive emission).
var _mats: Array[StandardMaterial3D] = []
var _flash_mat: StandardMaterial3D
var _flash_mat_cull: StandardMaterial3D = null
var _skin_nodes: Array[Node] = []    # one marker per outfit part (site_map_test's Builder PPE contract); no meshes
var _class_specs: Array = []         # WobblerLooks.class_parts(...) for the current class
var _skin_specs: Array = []          # WobblerLooks.skin_parts(...) for the current outfit
var _hat_specs: Array = []           # WobblerLooks.hat_parts(...) for the current hat
var _team_tint := false              # recolor(color, true): the outfit keeps the team colour (world.gd)
var _look_batch := 0                 # > 0 while setup() changes several look fields: rebuild once at the end
var _flash_white := false
var _flash_k := -1.0

# --- merged-mesh cache. Geometry+colours depend only on class | outfit | hat | colour | team tint (not on the tier),
# so every fighter with the same look shares the ArrayMeshes; LRU-bounded in entries AND bytes (see
# look_cache_stats()). Weapons are cached separately by key (WeaponModels.build is fused into one surface).
const LOOK_CACHE_MAX := 24
const LOOK_CACHE_BYTES := 4 * 1024 * 1024
const WEAPON_CACHE_MAX := 48
static var _look_cache: Dictionary = {}
static var _look_order: Array[String] = []
static var _look_cache_bytes := 0
static var _weapon_meshes: Dictionary = {}
static var _weapon_order: Array[String] = []
static var _weapon_bytes := 0
static var _smats: Dictionary = {}

# --- animation state (Fighter.animate)
var lean := Spring2.new()
var head := Spring2.new()
var arm_dir := Vector3(0, -1, 0.2).normalized()
var arm_vel := Vector3.ZERO
var aim_target := Vector3(0, -1, 0.2).normalized()
var stiff: float = 25.0
var yaw: float = 0.0
var face_yaw: float = 0.0
var pos := Vector3.ZERO
var vel := Vector3.ZERO
var prev_vel := Vector3.ZERO
var wish := Vector2.ZERO
var grounded := true
var crouch_k: float = 0.0
var dead := false
var down_t: float = 0.0
var trap := false
var invuln := false
var swing: float = -1.0
var swing_yaw: float = 0.0
var slam := false
var kick_t: float = -1.0
var phase: float = 0.0
var stride: float = 0.0
var squash: float = 0.0
var was_g := true
var prev_vy: float = 0.0
var lie_k: float = 0.0
var lie_side: float = 1.0
var fall_a: float = 0.0
var fall_v: float = 0.0
var fall_side: float = 1.0
var _time: float = 0.0
var _state_flash := false
var _stiff_override := -1.0

# --- faces (Sprint 2.4, docs/GRAPHICS.md "Faces"): the TWO eye meshes are transformed by the state, never added to.
# Own deterministic blink clock/RNG (seeded once in setup(), never combat.rng, never the global RNG).
var rage: float = 0.0                ## state "rage" (FighterState.rage_t seconds left): angry brows while > 0
var off_stage := false               ## state "off_stage" / "panic": airborne off the arena floor (wide panic eyes)
var blink_seed: int = -1             ## >= 0 pins the blink personality (tests / tools); -1 = derive from the identity
var face_time: float = 0.0           ## the wobbler's own face clock, advanced only by animate()
var blink_t: float = -1.0            ## seconds into the current blink, -1.0 = eyes open
var blink_count := 0                 ## blinks started so far
var blink_interval: float = 0.0      ## the wait drawn for the current blink cycle (2.5-4.5 s)
var blink_started_at: float = -1.0   ## face_time of the last blink start
var eye_open: float = 1.0            ## vertical eye openness the rig got this frame (1 = normal, 0 = shut)
var brow_angle: float = 0.0          ## eye/brow slant the rig got this frame (rad; + = inner end down)
var angry_k: float = 0.0             ## 0..1 blend to the angry face
var panic_k: float = 0.0             ## 0..1 blend to the panic face
var _blink_wait: float = 0.0         ## seconds until the next blink start
var _x_eyes := false                 ## the down/dead X eye mesh is on
var _face_rng := RandomNumberGenerator.new()
var _eye_mesh: Mesh                  ## this tier's open-eye mesh (plain box on LOW, box + brow above)
var _eye_base_scale: Array[Vector3] = [Vector3.ONE, Vector3.ONE]   ## class eye scale (alien 1.5)
var _face_sig := Vector4(-1.0, 0.0, 0.0, 1.0)   ## (eye_open, brow_angle, lift, eye x scale) last applied; idle skips writes
static var _eye_brow_cache: ArrayMesh = null
static var _x_eye_cache: ArrayMesh = null

# --- emotes (web Fighter.emote + emotePose; actors/emote_poses.gd). Visual only: play_emote(id) / stop_emote().
var emote_id := ""                    ## the emote playing ("" = none)
var emote_t := 0.0
var emote_dur := 0.0
var e_yaw := 0.0                      ## this frame's emote offsets (web eYaw, eLX, eLZ, eHop, ePitch)
var e_lx := 0.0
var e_lz := 0.0
var e_hop := 0.0
var e_pitch := 0.0
var _e_crouch := 0.0

# --- ragdoll overlay (docs/RAGDOLL.md): "classic" | "ragdoll". Presentation only: Fighter reads the gameplay points
# from the classic pose, then overlay() re-poses the visible nodes; the next animate() restores the classic pose first.
var rig_mode: String = "classic"
var rig_scale := Vector3.ONE          ## classic rig scale this frame (squash, crouch, class size)
var foot_meshes: Array[MeshInstance3D] = []
var arm_sleeve: MeshInstance3D
var arm_hand_mesh: MeshInstance3D
var rag := RagdollRig.new()
## Seeded per-fighter gait (docs/RAGDOLL.md, M0): a deterministic "leg personality" for the ragdoll overlay, sampled
## once per fighter from the owning Fighter's identity (net_slot when online, else the match id) mixed with the look.
## Presentation only: no sim/net value, planted feet never move, classic mode is untouched (docs/RAGDOLL_STUDY.md).
var leg_wobble: float = 0.55          ## Settings "leg_wobble" 0..1 (0 = exactly the overlay pose before this feature)
var gait_seed: int = -1               ## >= 0 pins the personality (tests / tools); -1 = derive from identity + look
var _overlaid := false
var _xf_nodes: Array[Node3D] = []
var _xf_saved: Array[Transform3D] = []
var _gait_dirty := true               ## re-sample the gait constants on the next overlay (look or owner changed)
var _gait_pin := -2                   ## gait_seed the current constants were sampled with
var _settings_node: Node = null


func _init() -> void:
	_build()
	setup("wobbler", "none", "none", WobblerLooks.DEFAULT_COLOR)


func _ready() -> void:
	_bind_settings()


## Read Settings.leg_wobble once and follow live slider changes (Settings.changed). No autoload = the default.
func _bind_settings() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var st: Node = tree.root.get_node_or_null("Settings") if tree and tree.root else null
	if st == null:
		return
	_settings_node = st
	leg_wobble = clampf(float(st.get_value("leg_wobble", 0.55)), 0.0, 1.0)
	if not st.changed.is_connected(_on_setting):
		st.changed.connect(_on_setting)


func _on_setting(key: String, v: Variant) -> void:
	if key == "leg_wobble":
		leg_wobble = clampf(float(v), 0.0, 1.0)


## The deterministic gait seed: the owning Fighter's net_slot when online, else its match id, mixed with the look.
## Never the global RNG. A standalone wobbler (tests, tools) uses the look only unless `gait_seed` is pinned.
func gait_identity() -> int:
	if gait_seed >= 0:
		return gait_seed
	var id := 0
	var slot := -1
	var p := get_parent()
	if p != null:
		var st: Variant = p.get("state")           # Fighter.state (actors/fighter.gd): a soft read, presentation only
		if st != null and "id" in st and "net_slot" in st:
			id = int(st.id)
			slot = int(st.net_slot)
	return RagdollRig.mix_seed(class_id, skin_key, hat_name, color, id, slot)


# ================================================================ material: the ONE place parts get their look
## Flat-shaded low-poly material (web `lm`). MID / HIGH tiers (docs/GRAPHICS.md): soft wrap lighting (keeps every
## facet its own tone; full toon flattened the low-poly look) and a sun rim light so fighters read against busy
## levels; specular off.
## LOW keeps plain lambert. Stays a StandardMaterial3D: hit flash and recolours drive albedo / emission as before.
func _make_mat(c: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.hex(c << 8 | 0xff)
	m.roughness = 0.95
	m.metallic = 0.0
	m.emission_enabled = true
	m.emission = Color.hex(0xff6644ff)
	m.emission_energy_multiplier = 0.0
	if _gfx_q() >= 1:
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		m.roughness = 0.6
		m.rim_enabled = true
		m.rim = 0.6
		m.rim_tint = 0.3
	return m


static func _gfx_q() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	var t: Node = tree.root.get_node_or_null("Tier") if tree and tree.root else null
	return int(t.call("quality")) if t else 2


## A flashing body material: albedo WHITE, the part colour comes from the baked vertex COLOR of the merged meshes
## (vertex_color_is_srgb makes the sRGB part colours look exactly like the old per-part albedo). One per fighter.
func _new_flash_mat() -> StandardMaterial3D:
	var m := _make_mat(0xffffff)
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	_mats = [m]
	return m


## The per-wobbler flash material, or a second one with cull disabled for an open-shell ("sph") body/outfit part
## (no shipped look needs it today; kept so a look change can never drop a part's two-sided look).
func _role_material(role: String) -> Material:
	match role:
		"f":
			return _flash_mat
		"fo":
			if _flash_mat_cull == null:
				_flash_mat_cull = _new_flash_mat()
				_flash_mat_cull.cull_mode = BaseMaterial3D.CULL_DISABLED
				_mats.append(_flash_mat_cull)
			return _flash_mat_cull
		_:
			return _shared_material(role)


## Static materials shared by every wobbler (vertex-colour albedo; no per-fighter state). Roles:
##   s  = outfit body/belt/hat, o = open shell (cull disabled), m = buckle (metallic), w = held weapon,
##   e  = eyes (plain albedo, no vertex colours), g:<hex>:<energy> = glowing part (continuous emission).
static func _shared_material(role: String) -> StandardMaterial3D:
	var q := _gfx_q()
	var key := "%d|%s" % [q, role]
	if _smats.has(key):
		return _smats[key]
	var m := StandardMaterial3D.new()
	m.roughness = 0.95
	m.metallic = 0.0
	m.emission_enabled = false
	var vc := true
	match role:
		"m":
			m.metallic = 0.3
			m.roughness = 0.5
		"o":
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"e":
			m.albedo_color = _col(WobblerLooks.EYE)
			vc = false
		_:
			if role.begins_with("g:"):
				var bits := role.split(":")
				m.emission_enabled = true
				m.emission = _col(int(bits[1]))
				m.emission_energy_multiplier = float(bits[2])
	if q >= 1:
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		m.rim_enabled = true
		m.rim = 0.6
		m.rim_tint = 0.3
	if vc:
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
	_smats[key] = m
	return m


static func _col(c: int) -> Color:
	return Color.hex(c << 8 | 0xff)


static func _euler_xyz(r: Vector3) -> Basis:           # three.js default Euler order 'XYZ' (matrix Rx * Ry * Rz)
	return Basis(Vector3.RIGHT, r.x) * Basis(Vector3.UP, r.y) * Basis(Vector3.BACK, r.z)


static func _euler_yxz(r: Vector3) -> Basis:           # three.js 'YXZ' (matrix Ry * Rx * Rz)
	return Basis(Vector3.UP, r.y) * Basis(Vector3.RIGHT, r.x) * Basis(Vector3.BACK, r.z)


func _mesh(parent: Node3D, mesh: Mesh, m: Material, p: Vector3, nm: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = p
	if nm != "":
		mi.name = nm
	parent.add_child(mi)
	return mi


func _group(parent: Node3D, p: Vector3, nm: String) -> Node3D:
	var g := Node3D.new()
	g.name = nm
	g.position = p
	parent.add_child(g)
	return g


# ================================================================ build (Fighter constructor, ~4817)
## The node skeleton only: rigid groups, the gameplay-point markers, the two eye meshes and the standalone meshes the
## ragdoll overlay animates separately (arm_sleeve, arm_hand_mesh, foot_meshes). Every other mesh is merged per rigid
## node by _rebuild_visual().
func _build() -> void:
	rig = _group(self, Vector3.ZERO, "Rig")
	body = _group(rig, Vector3(0, 0.8, 0), "Body")
	torso = Node3D.new()                 # chest gameplay point (Fighter._read_points); geometry merged into body_mesh
	torso.name = "Torso"
	torso.position = Vector3(0, 0.425, 0)
	body.add_child(torso)
	neck = _group(body, Vector3(0, 0.85, 0), "Neck")
	head_mesh = Node3D.new()             # head gameplay point (Fighter._read_points) + eye parent; geometry merged
	head_mesh.name = "Head"
	head_mesh.position = Vector3(0, 0.32, 0)
	neck.add_child(head_mesh)
	# faces (Sprint 2.4): MID / HIGH merge a brow bar into the SAME eye surface (2 meshes, 2 draw calls as before);
	# LOW keeps the plain eye box, so the web build carries no extra geometry (docs/GRAPHICS.md "Faces"). The eye
	# material is shared and static: it never flashes, exactly like before.
	_eye_mesh = _face_eye_mesh() if _gfx_q() >= 1 else LowPoly.box(EYE_SIZE.x, EYE_SIZE.y, EYE_SIZE.z)
	for sx in [-EYE_X, EYE_X]:
		eyes.append(_mesh(neck, _eye_mesh, _shared_material("e"), Vector3(sx, EYE_Y, EYE_Z), "Eye"))
	for x in [-0.2, 0.2]:
		var g := _group(rig, Vector3(x, 0.8, 0), "Leg")
		legs.append(g)
		# the ragdoll overlay writes foot_meshes[i].basis every overlay frame, so the foot stays its own mesh
		var foot := MeshInstance3D.new()
		foot.name = "Foot"
		foot.position = Vector3(0, -0.74, 0.07)
		g.add_child(foot)
		foot_meshes.append(foot)
	arm_l = _group(body, Vector3(0.52, 0.75, 0), "ArmL")             # local +X is the character's left
	shoulder = _group(body, Vector3(-0.52, 0.75, 0), "Shoulder")        # right shoulder
	arm = _group(self, Vector3.ZERO, "Arm")                              # aiming arm: free in world space
	# the overlay stretches the sleeve and slides the hand along the arm: both stay their own meshes
	arm_sleeve = _mesh(arm, LowPoly.cyl(0.11, 0.09, 0.85, 5), null, Vector3(0, -0.425, 0), "Sleeve")
	arm_hand_mesh = _mesh(arm, LowPoly.ico(0.14, 0), null, Vector3(0, -0.85, 0), "Hand")
	hand = _group(arm, Vector3(0, -0.85, 0), "Grip")
	_xf_nodes = [rig, body, neck, legs[0], legs[1], foot_meshes[0], foot_meshes[1], arm_l, arm, arm_sleeve, arm_hand_mesh, hand]
	_flash_mat = _new_flash_mat()


# ============================== batching (post-v0.4.0 Sprint 4.2) ==============================
## One part's local transform (pos, three.js XYZ Euler, scale) exactly like the pre-batching per-part nodes.
static func _part_xf(pt: Array) -> Transform3D:
	var p: Array = pt[3]
	var b := Basis()
	if pt.size() > 4 and pt[4] is Array:
		var r: Array = pt[4]
		b = _euler_xyz(Vector3(r[0], r[1], r[2]))
	var s := Vector3.ONE
	if pt.size() > 5 and pt[5] is Array:
		s = Vector3(pt[5][0], pt[5][1], pt[5][2])
	return Transform3D(b.scaled_local(s), Vector3(p[0], p[1], p[2]))


## A part colour: int / "tone" / "toneD" / [mul, mix] (tinted from the outfit's top colour, hexMix).
static func _spec_color(spec: Variant, main: int, skin_tone: int) -> Color:
	if spec is Array:
		return _col(WobblerLooks.hex_mix(main, float(spec[0]), float(spec[1])))
	if spec is String:
		return _col(skin_tone if spec == "tone" else WobblerLooks.hex_mix(skin_tone, 0.9, 0.0))
	return _col(int(spec))


## The material role a part bakes into: "f" flashable body/outfit, "fo" flashable open shell, "s" static,
## "o" static open shell (seen from inside: beanie, viking helmet), "g:<hex>:<energy>" a continuously glowing part.
static func _spec_role(pt: Array, is_static: bool) -> String:
	var glow: Variant = pt[5] if pt.size() > 5 else null
	if glow is Dictionary and glow.has("glow"):
		return "g:%d:%s" % [int(glow["glow"]), str(glow.get("glow_k", 0.6))]
	var open_shell: bool = String(pt[1][0]) == "sph"
	if is_static:
		return "o" if open_shell else "s"
	return "fo" if open_shell else "f"


static func _target_of(parent: String) -> String:
	match parent:
		"armL": return "arml"
		"leg0", "leg1": return parent
		"body", "neck", "arm": return parent
		_: return ""


func _parent_node(key: String) -> Node3D:
	match key:
		"neck": return neck
		"body": return body
		"leg0": return legs[0]
		"leg1": return legs[1]
		"armL": return arm_l
		"arm": return arm
		"hat": return hat
		"spin": return hat_spin
		_: return null


## Appends one part's transformed, flat-shaded geometry + its baked colour into a target/role buffer.
static func _append_geometry(buf: Dictionary, target: String, role: String, mesh: Mesh, xf: Transform3D, col: Color,
		extra_scale := Vector3.ONE) -> void:
	if not mesh is ArrayMesh:
		return
	var arrays := (mesh as ArrayMesh).surface_get_arrays(0)
	if arrays.size() <= Mesh.ARRAY_NORMAL: return
	var vv: Variant = arrays[Mesh.ARRAY_VERTEX]
	var nv: Variant = arrays[Mesh.ARRAY_NORMAL]
	if not (vv is PackedVector3Array) or not (nv is PackedVector3Array): return
	var verts: PackedVector3Array = vv
	var norms: PackedVector3Array = nv
	if verts.is_empty() or verts.size() != norms.size():
		return
	var xf2 := xf
	if extra_scale != Vector3.ONE:
		xf2 = Transform3D(xf.basis.scaled_local(extra_scale), xf.origin)
	if not buf.has(target):
		buf[target] = {}
	var roles: Dictionary = buf[target]
	if not roles.has(role):
		roles[role] = {"v": [], "n": [], "c": []}
	var slot: Dictionary = roles[role]
	var vs: Array = slot["v"]
	var ns: Array = slot["n"]
	var cs: Array = slot["c"]
	var nb := xf2.basis.inverse().transposed()
	for i in verts.size():
		vs.append(xf2 * verts[i])
		ns.append((nb * norms[i]).normalized())
		cs.append(col)
	slot["v"] = vs
	slot["n"] = ns
	slot["c"] = cs


## Resolves a WobblerLooks part (pos/rot/scale against a rigid parent) and appends it. `is_static` = hats (never flash).
func _add_look_part(buf: Dictionary, pt: Array, is_static: bool, is_class: bool, main: int, skin_tone: int,
		no_head: bool) -> void:
	var parent := String(pt[0])
	if parent == "armL":
		parent = "armL"
	var target := _target_of(parent)
	if target == "":
		if parent == "hat" or parent == "spin":
			target = parent
		else:
			return
	if is_class and no_head and parent == "neck":
		return                                    # class hair/antennae would float around a cup/log outfit
	var role := _spec_role(pt, is_static)
	var mesh := LowPoly.from_spec(pt[1])
	_append_geometry(buf, target, role, mesh, _part_xf(pt), _spec_color(pt[2], main, skin_tone))


## One ArrayMesh surface per role from a buffer (role order is deterministic: flash, static, open shell, metal, glow).
static func _buf_to_mesh(roles: Dictionary) -> ArrayMesh:
	var order: Array = []
	for r: String in ["f", "fo", "s", "o", "m"]:
		if roles.has(r):
			order.append(r)
	var glow_roles: Array = []
	for r: String in roles:
		if r.begins_with("g:") and not glow_roles.has(r):
			glow_roles.append(r)
	glow_roles.sort()
	order.append_array(glow_roles)
	var m := ArrayMesh.new()
	for role: String in order:
		var slot: Dictionary = roles[role]
		var vs: Array = slot["v"]
		if vs.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(vs)
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(slot["n"])
		arrays[Mesh.ARRAY_COLOR] = PackedColorArray(slot["c"])
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


static func _roles_of(roles: Dictionary) -> PackedStringArray:
	var m := _buf_to_mesh(roles)        # deterministic order, built once here to reuse its surface count
	var out := PackedStringArray()
	if m.get_surface_count() == 0:
		return out
	# the same role order _buf_to_mesh uses
	for r: String in ["f", "fo", "s", "o", "m"]:
		if roles.has(r):
			out.append(r)
	var glow_roles: Array = []
	for r: String in roles:
		if r.begins_with("g:") and not glow_roles.has(r):
			glow_roles.append(r)
	glow_roles.sort()
	for r: String in glow_roles:
		out.append(r)
	return out


static func _single_surface(mesh: Mesh, col: Color) -> ArrayMesh:
	var out := ArrayMesh.new()
	if not mesh is ArrayMesh:
		return out
	var arrays := (mesh as ArrayMesh).surface_get_arrays(0)
	if arrays.size() <= Mesh.ARRAY_NORMAL: return out
	var vv: Variant = arrays[Mesh.ARRAY_VERTEX]
	var nv: Variant = arrays[Mesh.ARRAY_NORMAL]
	if not (vv is PackedVector3Array) or not (nv is PackedVector3Array): return out
	var verts: PackedVector3Array = vv
	var norms: PackedVector3Array = nv
	if verts.size() != norms.size(): return out
	var cols := PackedColorArray()
	cols.resize(verts.size())
	cols.fill(col)
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = verts
	a[Mesh.ARRAY_NORMAL] = norms
	a[Mesh.ARRAY_COLOR] = cols
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return out


static func _mesh_bytes(m: Mesh) -> int:
	var total := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		if arr[Mesh.ARRAY_VERTEX] != null:
			total += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() * 12
		if arr[Mesh.ARRAY_NORMAL] != null:
			total += (arr[Mesh.ARRAY_NORMAL] as PackedVector3Array).size() * 12
		if arr[Mesh.ARRAY_COLOR] != null:
			total += (arr[Mesh.ARRAY_COLOR] as PackedColorArray).size() * 16
	return total


## The per-fighter colour palette, exactly the old per-material recolour rules (torso/sleeves = main, head/hands/feet =
## accent or the class skin colour, thighs = pants, feet = shoes, outfit parts keep their own colour or a tint).
func _palette() -> Dictionary:
	var sk := WobblerLooks.skin_def(skin_key)
	var sk_empty := sk.is_empty()
	var main := color
	if not sk_empty and not _team_tint:
		main = int(sk.get("col", color))
	var accent := WobblerLooks.ACCENT
	var skin_tone := WobblerLooks.ACCENT
	if not sk_empty:
		skin_tone = int(sk.get("tone", WobblerLooks.ACCENT))
		accent = skin_tone
	var pants := main
	var shoes := WobblerLooks.ACCENT
	if not sk_empty:
		var pv: Variant = sk.get("pants", main)
		pants = skin_tone if pv is String else int(pv)
		shoes = int(sk.get("shoes", skin_tone))
	if cls.has("skin"):                                  # Zorp: green skin on head, hands and feet
		accent = int(cls["skin"])
		shoes = accent
	return {"main": main, "accent": accent, "tone": skin_tone, "pants": pants, "shoes": shoes,
		"wide": float(cls.get("wide", 1.0)), "noHead": sk.get("noHead", false), "noBelt": sk.get("noBelt", false),
		"noTorso": sk.get("noTorso", false), "noHat": sk.get("noHat", false), "thin": float(sk.get("thin", 1.0))}


## Builds every merged mesh for the CURRENT look (cached by class|outfit|hat|colour|team tint).
func _build_visual() -> Dictionary:
	var pal := _palette()
	var main := int(pal["main"])
	var accent := int(pal["accent"])
	var tone := int(pal["tone"])
	var skin_tone := tone
	var wide: float = pal["wide"]
	var deep := 1.0 + (wide - 1.0) * 0.5
	var th: float = pal["thin"]
	var no_head: bool = pal["noHead"]
	var buf := {}
	# --- base body / head / belt / legs / off arm (the old _build meshes, colours from the old material groups)
	if not pal["noTorso"]:
		_append_geometry(buf, "body", "f", LowPoly.cyl(0.4, 0.34, 0.85, 6),
			Transform3D(Basis().scaled_local(Vector3(wide, 1, deep)), Vector3(0, 0.425, 0)), _col(main))
	if not no_head:
		_append_geometry(buf, "neck", "f", LowPoly.ico(0.36, 0), Transform3D(Basis(), Vector3(0, 0.32, 0)), _col(accent))
	if not pal["noBelt"]:
		_append_geometry(buf, "body", "s", LowPoly.cyl(0.385, 0.36, 0.1, 6),
			Transform3D(Basis().scaled_local(Vector3(wide, 1, deep)), Vector3(0, 0.17, 0)), _col(WobblerLooks.BELT))
		_append_geometry(buf, "body", "m", LowPoly.box(0.11, 0.09, 0.05),
			Transform3D(Basis(), Vector3(0, 0.17, 0.37 * deep)), _col(WobblerLooks.BUCKLE))
	for i in 2:
		_append_geometry(buf, "leg%d" % i, "f", LowPoly.cyl(0.15, 0.12, 0.8, 5),
			Transform3D(Basis(), Vector3(0, -0.4, 0)), _col(int(pal["pants"])), Vector3(th, 1, th))
	# off arm: sleeve and hand share one rigid node, so one mesh (the sleeve is slimmed by `thin`, like the old node scale)
	_append_geometry(buf, "arml", "f", LowPoly.cyl(0.11, 0.09, 0.75, 5),
		Transform3D(Basis(), Vector3(0, -0.375, 0)), _col(main), Vector3(th, 1, th))
	_append_geometry(buf, "arml", "f", LowPoly.ico(0.13, 0), Transform3D(Basis(), Vector3(0, -0.78, 0)), _col(accent))
	# --- class accessories, then outfit parts (hats are separate chunks: some hat contracts need per-part meshes)
	for pt: Array in _class_specs:
		_add_look_part(buf, pt, false, true, main, skin_tone, no_head)
	for pt: Array in _skin_specs:
		_add_look_part(buf, pt, false, false, main, skin_tone, no_head)
	# --- merged meshes + their surface roles
	var meshes := {}
	var roles := {}
	var total := 0
	for target: String in buf:
		var m := _buf_to_mesh(buf[target])
		if m.get_surface_count() == 0:
			continue
		meshes[target] = m
		roles[target] = _roles_of(buf[target])
		total += _mesh_bytes(m)
	# --- the standalone animated meshes (node transforms stay exactly as before)
	var sleeve := _single_surface(LowPoly.cyl(0.11, 0.09, 0.85, 5), _col(main))
	var arm_hand := _single_surface(LowPoly.ico(0.14, 0), _col(accent))
	var feet := _single_surface(LowPoly.box(0.26, 0.12, 0.4), _col(int(pal["shoes"])))
	total += _mesh_bytes(sleeve) + _mesh_bytes(arm_hand) + _mesh_bytes(feet)
	# --- hats: one merged mesh (or one per part for hats with >= 6 parts, which the site-map PPE contract counts)
	var hat_chunks: Array = []
	if hat_name != "none" and not _hat_specs.is_empty():
		if _hat_specs.size() < 6:
			var hbuf := {}
			for pt: Array in _hat_specs:
				_add_look_part(hbuf, pt, true, false, main, skin_tone, no_head)
			for parent: String in hbuf:
				var hm := _buf_to_mesh(hbuf[parent])
				if hm.get_surface_count() == 0:
					continue
				hat_chunks.append({"parent": parent, "mesh": hm, "roles": _roles_of(hbuf[parent]),
					"xf": Transform3D.IDENTITY})
				total += _mesh_bytes(hm)
		else:
			for pt: Array in _hat_specs:
				var role := _spec_role(pt, true)
				var one := _single_surface(LowPoly.from_spec(pt[1]), _spec_color(pt[2], main, skin_tone))
				var par := String(pt[0])
				if par != "spin":
					par = "hat"
				hat_chunks.append({"parent": par, "mesh": one, "roles": PackedStringArray([role]),
					"xf": _part_xf(pt)})
				total += _mesh_bytes(one)
	return {"meshes": meshes, "roles": roles, "sleeve": sleeve, "hand": arm_hand, "feet": feet,
		"hat_chunks": hat_chunks, "bytes": total}


## Look-cache lookup (LRU in entries AND bytes): a fighter with the same class/outfit/hat/colour/team tint shares the
## merged ArrayMeshes of an earlier one. Rebuilt only on a look change, never per frame.
func _look_visual() -> Dictionary:
	var key := "%s|%s|%s|%d|%d" % [class_id, skin_key, hat_name, color, 1 if _team_tint else 0]
	if _look_cache.has(key):
		_look_order.erase(key)
		_look_order.append(key)
		return _look_cache[key]
	var v := _build_visual()
	_look_cache[key] = v
	_look_order.append(key)
	_look_cache_bytes += int(v["bytes"])
	while _look_order.size() > 1 and (_look_order.size() > LOOK_CACHE_MAX \
			or _look_cache_bytes > LOOK_CACHE_BYTES):
		var old: String = _look_order[0]
		if old == key:
			break
		_look_order.remove_at(0)
		_look_cache_bytes -= int((_look_cache[old] as Dictionary)["bytes"])
		_look_cache.erase(old)
	return v


## Cache diagnostics (docs/GRAPHICS.md "Fighter mesh batching"): entries, bytes and the bounds.
static func look_cache_stats() -> Dictionary:
	return {"entries": _look_cache.size(), "bytes": _look_cache_bytes, "max_entries": LOOK_CACHE_MAX,
		"max_bytes": LOOK_CACHE_BYTES, "weapons": _weapon_meshes.size(), "weapon_bytes": _weapon_bytes}


static func clear_look_cache() -> void:
	_look_cache.clear()
	_look_order.clear()
	_look_cache_bytes = 0
	_weapon_meshes.clear()
	_weapon_order.clear()
	_weapon_bytes = 0


# ================================================================ looks
func setup(p_class_id: String, p_skin: String = "none", p_hat: String = "none", p_color: int = WobblerLooks.DEFAULT_COLOR) -> void:
	_look_batch += 1
	color = p_color
	set_class(p_class_id)
	set_skin(p_skin)
	set_hat(p_hat)
	_look_batch -= 1
	_rebuild_visual()
	_face_setup()


## Applies the current look (merged meshes + flags). Batched inside setup() so one look change rebuilds once.
func _refresh_visual() -> void:
	if _look_batch <= 0:
		_rebuild_visual()


## Fighter.setClass + classLook: proportions plus a few cheap accessories. Looks only.
func set_class(id: String) -> void:
	_gait_dirty = true
	if not WobblerLooks.data("classes").has(id):
		id = "wobbler"
	class_id = id
	cls = WobblerLooks.class_def(id)
	var wide: float = cls.get("wide", 1.0)
	var deep := 1.0 + (wide - 1.0) * 0.5
	var arm_x := 0.52 * wide
	neck.scale = Vector3.ONE * float(cls.get("head", 1.0))
	torso.scale = Vector3(wide, 1, deep)          # the gameplay marker keeps the old torso scale (tests / tools)
	arm_l.position.x = arm_x
	shoulder.position.x = -arm_x
	var ek := 1.5 if id == "alien" else 1.0
	_face_sig.x = -1.0
	for i in eyes.size():
		_eye_base_scale[i] = Vector3(ek, ek, 1)
		eyes[i].basis = Basis().scaled_local(_eye_base_scale[i])
	_class_specs = WobblerLooks.class_parts(id, arm_x, deep)
	_refresh_visual()


## Outfit (Fighter.setSkin). Keys come from cosmetics.json skins; unknown keys mean no outfit.
func set_skin(key: String) -> void:
	_gait_dirty = true
	skin_key = key if WobblerLooks.skin_def(key).size() > 0 else "none"
	_skin_specs = WobblerLooks.skin_parts(skin_key) if skin_key != "none" else []
	_refresh_visual()


func set_hat(name: String) -> void:
	_gait_dirty = true
	for mi: MeshInstance3D in _hat_meshes:
		if is_instance_valid(mi):
			mi.free()
	_hat_meshes.clear()
	if hat != null:
		hat.free()                                # frees the spin group and its meshes too
	hat = null
	hat_spin = null
	hat_name = name if WobblerLooks.HATS.has(name) else "none"
	_hat_specs = [] if hat_name == "none" else WobblerLooks.hat_parts(hat_name)
	if hat_name != "none":
		hat = _group(neck, Vector3(0, 0.62, 0), "Hat")
		if WobblerLooks.HAT_SPIN_Y.has(hat_name):
			hat_spin = _group(hat, Vector3(0, WobblerLooks.HAT_SPIN_Y[hat_name], 0), "Spin")
	_refresh_visual()


## Fighter.recolor: body colour; outfits keep their own top colour (team matches pass team = true to force `c`).
## The colours are baked into the merged meshes, so this rebuilds them (cache shared per colour).
func recolor(c: int, team: bool = false) -> void:
	_gait_dirty = true
	color = c
	_team_tint = team
	_refresh_visual()


## Builds/updates the merged meshes for the current look and the per-outfit flags (eyes/hat visibility, thin limbs).
func _rebuild_visual() -> void:
	var look := _look_visual()
	var meshes: Dictionary = look["meshes"]
	var roles: Dictionary = look["roles"]
	body_mesh = _apply_target(body, "BodyMesh", "body", look, body_mesh)
	neck_mesh = _apply_target(neck, "HeadMesh", "neck", look, neck_mesh)
	leg_meshes.resize(2)
	leg_meshes[0] = _apply_target(legs[0], "Thigh", "leg0", look, leg_meshes[0])
	leg_meshes[1] = _apply_target(legs[1], "Thigh", "leg1", look, leg_meshes[1])
	arm_l_mesh = _apply_target(arm_l, "ArmLMesh", "arml", look, arm_l_mesh)
	arm_mesh = _apply_target(arm, "ArmMerge", "arm", look, arm_mesh)
	arm_sleeve.mesh = look["sleeve"]
	arm_sleeve.material_override = _flash_mat
	arm_hand_mesh.mesh = look["hand"]
	arm_hand_mesh.material_override = _flash_mat
	for i in 2:
		foot_meshes[i].mesh = look["feet"]
		foot_meshes[i].material_override = _flash_mat
	_apply_hats(look)
	_apply_look_flags()
	_apply_flash()


## Puts (or removes) one merged mesh on its rigid node and sets the per-surface materials.
func _apply_target(parent: Node3D, nm: String, key: String, look: Dictionary, mi: MeshInstance3D) -> MeshInstance3D:
	if not (look["meshes"] as Dictionary).has(key):
		if mi != null and is_instance_valid(mi):
			mi.free()
		return null
	if mi == null or not is_instance_valid(mi):
		mi = MeshInstance3D.new()
		mi.name = nm
		parent.add_child(mi)
	mi.mesh = look["meshes"][key]
	mi.material_override = null
	_apply_surface_materials(mi, look["roles"][key])
	return mi


## surface_set_override_material per merged surface: the flash material for body/outfit surfaces, shared statics for
## belt/buckle/hats/glow (exactly the old per-part material roles, just fewer instances).
func _apply_surface_materials(mi: MeshInstance3D, roles: PackedStringArray) -> void:
	for i in roles.size():
		mi.set_surface_override_material(i, _role_material(roles[i]))


## Hats: one merged mesh chunk (or one per part for hats with >= 6 parts: the site-map PPE test counts hat meshes).
func _apply_hats(look: Dictionary) -> void:
	for mi: MeshInstance3D in _hat_meshes:
		if is_instance_valid(mi):
			mi.free()
	_hat_meshes.clear()
	if hat == null:
		return
	for ch: Dictionary in look["hat_chunks"]:
		var parent: Node3D = hat if String(ch["parent"]) == "hat" else hat_spin
		if parent == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "HatMesh"
		mi.mesh = ch["mesh"]
		mi.transform = ch["xf"]
		parent.add_child(mi)
		_apply_surface_materials(mi, ch["roles"])
		_hat_meshes.append(mi)


## The old _skin_flags: eyes/hat visibility, slim (`thin`) arms/feet; plus one marker node per outfit part so the
## site_map_test Builder PPE contract (_skin_nodes size/validity) keeps its meaning without a mesh per part.
func _apply_look_flags() -> void:
	var sk := WobblerLooks.skin_def(skin_key)
	var th := float(sk.get("thin", 1.0))        # web skinFlags `thin`: slim arms and legs (Ballerina)
	for e in eyes:
		e.visible = not sk.get("noEyes", false)
	if hat != null:
		hat.visible = not sk.get("noHat", false)
	arm_sleeve.scale = Vector3(th, 1, th)
	for i in 2:
		foot_meshes[i].scale = Vector3(minf(1.0, th * 1.2), 1, 1)
	for n: Node in _skin_nodes:
		if is_instance_valid(n):
			n.free()
	_skin_nodes.clear()
	for pt: Array in _skin_specs:
		var parent := _parent_node(String(pt[0]))
		if parent == null:
			continue
		var marker := Node3D.new()
		marker.name = "SkinPart"
		marker.transform = _part_xf(pt)
		parent.add_child(marker)
		_skin_nodes.append(marker)


# ================================================================ weapons
## One merged ArrayMesh per weapon key: WeaponModels.build's per-part boxes fused into a single surface, colours baked
## into vertex COLOR (the merged mesh is shared by every wobbler that ever held the weapon).
static func _weapon_visual(k: String) -> ArrayMesh:
	if _weapon_meshes.has(k):
		_weapon_order.erase(k)
		_weapon_order.append(k)
		return _weapon_meshes[k]
	var tree := WeaponModels.build(k)
	var verts: Array = []
	var norms: Array = []
	var cols: Array = []
	_collect_weapon(tree, Transform3D.IDENTITY, verts, norms, cols)
	tree.free()
	var m := ArrayMesh.new()
	if not verts.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(verts)
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(norms)
		arrays[Mesh.ARRAY_COLOR] = PackedColorArray(cols)
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if m.get_surface_count() == 0:
		return m                     # nothing fusable: not cached, set_weapon() falls back to the per-part model
	_weapon_meshes[k] = m
	_weapon_order.append(k)
	_weapon_bytes += _mesh_bytes(m)
	while _weapon_order.size() > WEAPON_CACHE_MAX:
		var old: String = _weapon_order[0]
		_weapon_order.remove_at(0)
		_weapon_bytes -= _mesh_bytes(_weapon_meshes[old])
		_weapon_meshes.erase(old)
	return m


static func _collect_weapon(n: Node, parent_xf: Transform3D, verts: Array, norms: Array, cols: Array) -> void:
	if not (n is Node3D):
		return
	if not (n as Node3D).visible:
		return
	var xf := parent_xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		var mat := mi.material_override as StandardMaterial3D
		var col := mat.albedo_color if mat != null else Color.WHITE
		var nb := xf.basis.inverse().transposed()
		# Fuse every triangle surface. A weapon model may carry a non-triangle surface (the Net Gun's wireframe
		# icosahedron is Mesh.PRIMITIVE_LINES and has no normals), so read the arrays as Variants and skip anything
		# that cannot be fused into the triangle soup; without this guard the typed read below errors on Nil.
		for si in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(si)
			if arrays.size() <= Mesh.ARRAY_NORMAL: continue
			var vv: Variant = arrays[Mesh.ARRAY_VERTEX]
			var nv: Variant = arrays[Mesh.ARRAY_NORMAL]
			if not (vv is PackedVector3Array) or not (nv is PackedVector3Array): continue
			var v: PackedVector3Array = vv
			var nn: PackedVector3Array = nv
			if v.is_empty() or v.size() != nn.size(): continue
			for i in v.size():
				verts.append(xf * v[i])
				norms.append((nb * nn[i]).normalized())
				cols.append(col)
	for c in n.get_children():
		_collect_weapon(c, xf, verts, norms, cols)


## Held weapon mesh in the aiming hand, fused into one MeshInstance3D (the holder is rebuilt on every weapon change,
## so a fighter keeps exactly one held-weapon node pair and weapon pickups never grow its node tree).
func set_weapon(key: Variant) -> void:
	var k: String = "" if key == null else String(key)
	weapon = k
	if _weapon_holder != null:
		_weapon_holder.free()
		_weapon_holder = null
		_weapon_mi = null
	_weapon_nodes.clear()
	if k != "":
		_weapon_holder = _group(hand, Vector3.ZERO, "W_" + k)
		var fused := _weapon_visual(k)
		if fused != null and fused.get_surface_count() > 0:
			_weapon_mi = MeshInstance3D.new()
			_weapon_mi.name = "Model"
			_weapon_mi.mesh = fused
			_weapon_mi.material_override = _shared_material("w")
			_weapon_holder.add_child(_weapon_mi)
		else:
			# Fallback: nothing to fuse (a model made only of lines/points). Keep the old per-part nodes so a weapon
			# can never turn invisible; no shipped key takes this path (they all have triangle surfaces).
			_weapon_holder.add_child(WeaponModels.build(k))
		_weapon_nodes[k] = _weapon_holder
	_show_weapon()
	var wd: Dictionary = WobblerLooks.data("weapons").get(k, {})
	stiff = float(wd.get("stiff", 25.0)) if k != "" else 25.0


## Emotes put the weapon away (web build 60): the held weapon shows only when no emote plays.
func _show_weapon() -> void:
	if _weapon_holder != null:
		_weapon_holder.visible = weapon != "" and emote_id == ""


# ================================================================ emotes
## Starts emote `id` (data/extra/locker.json EMOTES). false when it cannot play now (web playEmote: not while down,
## dead, trapped, swinging or kicking) or the id is unknown.
func play_emote(id: String) -> bool:
	var e := LockerData.emote(id)
	if e.is_empty() or dead or down_t > 0.0 or trap or swing >= 0.0 or kick_t >= 0.0:
		return false
	emote_id = id
	emote_t = 0.0
	emote_dur = float(e.get("dur", 2.0))
	_show_weapon()
	return true


func stop_emote() -> void:
	if emote_id == "":
		return
	emote_id = ""
	_show_weapon()


func is_emoting() -> bool:
	return emote_id != ""


## This frame's emote pose ({} when none). It ends when its time is up, or on a fall, K.O., net, swing or kick, or
## when the fighter walks off (the web game slows you down instead; this port keeps gameplay untouched).
func _emote_pose(dt: float) -> Dictionary:
	if emote_id == "":
		return {}
	emote_t += dt
	var walks := wish.length_squared() > 0.09 and emote_t > 0.3
	if emote_t >= emote_dur or dead or down_t > 0.0 or trap or swing >= 0.0 or kick_t >= 0.0 or walks:
		stop_emote()
		return {}
	return EmotePoses.pose(emote_id, emote_t, emote_dur, yaw)


# ================================================================ state in
func apply_state(s: Dictionary) -> void:
	if s.has("class_id") or s.has("skin") or s.has("hat") or s.has("color"):
		var ci: String = s.get("class_id", class_id)
		var sk: String = s.get("skin", skin_key)
		var ht: String = s.get("hat", hat_name)
		var co: int = s.get("color", color)
		if ci != class_id:
			set_class(ci)
		if sk != skin_key:
			set_skin(sk)
		if ht != hat_name:
			set_hat(ht)
		if co != color:
			recolor(co)
	if s.has("weapon"):
		var w: Variant = s["weapon"]
		if (w if w != null else "") != weapon:
			set_weapon(w)
	pos = s.get("pos", pos)
	var nv: Vector3 = s.get("vel", vel)
	var g: bool = s.get("grounded", grounded)
	if g and not grounded and vel.y < -5.0:                  # landing thump (Fighter.physics)
		lean.kick(-vel.y * 0.12, 0.0)
		head.kick(-vel.y * 0.25, 0.0)
	vel = nv
	grounded = g
	face_yaw = s.get("yaw", face_yaw)
	if s.has("aim"):
		var a: Vector3 = s["aim"]
		if a.length_squared() > 1e-8:
			aim_target = a.normalized()
	if s.has("wish"):
		wish = s["wish"]
	else:                                                     # no input in the state: walking = moving on the ground
		var hv := Vector2(vel.x, vel.z)
		wish = hv.normalized() if hv.length() > 0.3 else Vector2.ZERO
	crouch_k = clampf(s.get("crouch", crouch_k), 0.0, 1.0)
	var nd: bool = s.get("dead", false)
	var ndt: float = s.get("down_t", 0.0)
	if (nd and not dead) or (ndt > 0.0 and down_t <= 0.0):
		fall_side = float(s.get("fall_side", -1.0 if randf() < 0.5 else 1.0))
	dead = nd
	down_t = ndt
	trap = s.get("trap", false)
	invuln = s.get("invuln", false)
	_stiff_override = s.get("stiff", -1.0)
	rage = maxf(0.0, float(s.get("rage", 0.0)))               # faces (Sprint 2.4): optional, safe defaults
	off_stage = bool(s.get("off_stage", s.get("panic", false)))
	var nsw: float = s.get("swing", -1.0)
	if nsw >= 0.0 and swing < 0.0:                            # meleeBegin: the lunge lean
		swing_yaw = face_yaw
		slam = not grounded and not dead and down_t <= 0.0
		lean.kick(-3.2 if slam else -2.2, 0.0)
	swing = nsw
	var nk: float = s.get("kick_t", -1.0)
	if nk >= 0.3 and kick_t < 0.3 and not dead and down_t <= 0.0:     # kickStep: the whip
		lean.kick(-3.2, 0.0)
		head.kick(-2.5, 0.0)
	kick_t = nk
	if s.has("hp"):
		rag.note_hp(float(s["hp"]))
	if s.has("flash"):
		_state_flash = true
		flash = clampf(float(s["flash"]) / FLASH_FULL, 0.0, 1.0)


## A hit lands (Fighter.hit, the visual half): lean/head kick away from the blow, the arm flung, a flash.
func hit_kick(dir: Vector3, force: float) -> void:
	var s := sin(yaw)
	var c := cos(yaw)
	var d_f := dir.x * s + dir.z * c
	var d_r := -dir.x * c + dir.z * s
	lean.kick(-d_f * force * 0.22, -d_r * force * 0.22)
	head.kick(-d_f * force * 0.5, -d_r * force * 0.5)
	arm_vel += dir * force * 0.3
	rag.hit(-d_f * force * 0.22, -d_r * force * 0.22, yaw, float(cls.get("size", 1.0)))
	if not _state_flash:
		flash = 1.0


# ================================================================ animate (Fighter.animate ~5619 + applyPose ~5882)
func animate(dt: float) -> void:
	if _overlaid:                                           # undo the ragdoll overlay: nodes back to the classic pose
		_restore_classic()
	if dt <= 0.0:
		return
	_time += dt
	var wob := 2.2 * float(cls.get("wob", 1.0))
	yaw += wrapf(face_yaw - yaw, -PI, PI) * minf(1.0, 12.0 * dt)
	var ax := clampf((vel.x - prev_vel.x) / dt, -400.0, 400.0)
	var az := clampf((vel.z - prev_vel.z) / dt, -400.0, 400.0)
	prev_vel = vel
	var s := sin(yaw)
	var c := cos(yaw)
	var a_f := ax * s + az * c
	var a_r := -ax * c + az * s
	var v_f := vel.x * s + vel.z * c
	var v_r := -vel.x * c + vel.z * s
	lean.step(dt, 95.0 / wob, 0.28, -a_f * 0.45, -a_r * 0.45, clampf(v_f * 0.03, -0.45, 0.45), clampf(v_r * 0.03, -0.4, 0.4))
	head.step(dt, 60.0 / wob, 0.2, -a_f * 0.9, -a_r * 0.9)

	# poses that steer the aiming arm: emote, melee swing (meleeTick), falling over, lying trapped
	var st := stiff if _stiff_override < 0.0 else _stiff_override
	var target := aim_target
	var ep := _emote_pose(dt)
	if not ep.is_empty() and ep["aim"] != null and (ep["aim"] as Vector3).length_squared() > 1e-8:
		target = (ep["aim"] as Vector3).normalized()
		st = 70.0
	e_yaw = ep.get("yaw", 0.0); e_lx = ep.get("lx", 0.0); e_lz = ep.get("lz", 0.0)
	e_hop = ep.get("hop", 0.0); e_pitch = ep.get("pitch", 0.0)
	_e_crouch += (float(ep.get("crouch", 0.0)) - _e_crouch) * minf(1.0, dt * 14.0)
	if swing >= 0.0 and not dead and down_t <= 0.0:
		var ss := sin(swing_yaw)
		var cs := cos(swing_yaw)
		var t := clampf(swing, 0.0, 1.0)
		if slam:                                            # overhead: from up behind the head, down in front
			var pitch := lerpf(1.25, -1.3, t)
			target = Vector3(ss * cos(pitch), sin(pitch), cs * cos(pitch)).normalized()
		else:                                               # side swipe right to left
			var a := lerpf(1.7, -1.7, t)
			target = Vector3(ss * cos(a) - cs * sin(a), -0.02, cs * cos(a) + ss * sin(a)).normalized()
	var down := dead or down_t > 0.0
	var fall_target := 0.0
	if dead:
		fall_target = fall_side * (PI / 2.0 * 0.98 + TAU)
	elif down:
		fall_target = fall_side * PI / 2.0 * 0.98
	if dead:
		fall_v += (-34.0 * (fall_a - fall_target) - 11.7 * fall_v) * dt
	else:
		fall_v += (-60.0 * (fall_a - fall_target) - 7.0 * fall_v) * dt
	fall_a += fall_v * dt
	if down:
		if dead:
			var pr := clampf(fall_a / fall_target, 0.0, 1.0)
			var up := 1.0 - clampf((pr - 0.15) / 0.7, 0.0, 1.0)
			target = Vector3(sin(pr * 24.0) * 0.8 * up, 1.1 * up - (1.0 - up), cos(pr * 24.0) * 0.8 * up).normalized()
		else:
			target = SIM_DOWN
		st = 8.0
	var lie_on := trap and not dead and down_t <= 0.0
	lie_k += ((1.0 if lie_on else 0.0) - lie_k) * minf(1.0, dt * 7.0)
	if lie_on:
		target = SIM_DOWN
		st = 8.0

	# aiming arm: a spring chasing the target direction (the "awkward aim")
	var k_arm := (3.0 if swing >= 0.0 else 1.0) * (st / wob)
	var cdamp := 2.0 * sqrt(k_arm) * 0.32
	var acc := (target - arm_dir) * k_arm - arm_vel * cdamp
	acc.x += -ax * 0.06
	acc.z += -az * 0.06
	arm_vel += acc * dt
	arm_dir = (arm_dir + arm_vel * dt).normalized()

	# legs and the swinging off-arm: stride follows input, so sliding keeps the legs still
	var walking := wish.length_squared() > 0.0025 and not dead and down_t <= 0.0
	var sp_raw := Vector2(vel.x, vel.z).length()
	stride += ((sp_raw if walking or not grounded else 0.0) - stride) * minf(1.0, 14.0 * dt)
	var sp := stride
	phase += sp * dt * 1.5
	var amp := minf(sp / 5.0, 1.0) * 0.85 if grounded else 0.4
	var leg0 := sin(phase) * amp + (0.0 if grounded else 0.5)
	var leg1 := -sin(phase) * amp + (0.0 if grounded else -0.3)
	var arm_lx := -sin(phase) * amp * 0.9 - lean.x * 0.8
	var arm_lz := 0.15 + absf(lean.y) * 0.8
	if hat_spin:
		hat_spin.rotation.y += dt * 20.0
	var body_y := 0.8 + (absf(sin(phase)) * 0.07 * minf(sp / 5.0, 1.0) if grounded else 0.0)
	if kick_t >= 0.0 and down_t <= 0.0 and not dead:      # floppy kick: wind back, whip forward, flop home
		var t := kick_t
		var a := 0.0
		if t < 0.3:
			a = lerpf(0.0, 0.7, t / 0.3)
		elif t < 0.5:
			a = lerpf(0.7, -2.0, (t - 0.3) / 0.2)
		elif t < 0.65:
			a = -2.0
		else:
			a = lerpf(-2.0, 0.0, minf(1.0, (t - 0.65) / 0.35))
		leg1 = a
		leg0 = 0.15
		arm_lz = 0.9
	if not ep.is_empty():                                   # the emote's own off-arm, legs and head
		if ep["arm_l"] != null:
			arm_lx = ep["arm_l"].x; arm_lz = ep["arm_l"].y
		if ep["legs"] != null:
			leg0 = ep["legs"].x; leg1 = ep["legs"].y
		if ep["head"] != null:
			head.kick(ep["head"].x * dt * 20.0, ep["head"].y * dt * 20.0)
	if grounded and not was_g and prev_vy < -4.0:          # landing squash
		squash = minf(0.28, -prev_vy * 0.025)
	was_g = grounded
	prev_vy = vel.y
	squash *= maxf(0.0, 1.0 - dt * 9.0)
	if not _state_flash:
		flash = maxf(0.0, flash - dt / FLASH_FULL)

	# ---- applyPose
	var d_t0 := fall_side * (PI / 2.0 * 0.98 + TAU)
	var d_p := clampf(fall_a / d_t0, 0.0, 1.15) if dead else 0.0
	var lift := 1.5 * sin(PI * clampf(d_p * 1.5, 0.0, 1.0)) if dead else absf(sin(fall_a)) * 0.4
	rig.position = Vector3(pos.x, pos.y + lift + lie_k * 0.3 + e_hop, pos.z)
	var rx := lie_k * lie_side * PI / 2.0 * 0.98 + (-fall_side * TAU * clampf(d_p * 1.1, 0.0, 1.0) if dead else 0.0)
	var size_k := float(cls.get("size", 1.0))
	var stv := 0.0 if grounded else clampf(vel.y * 0.012, -0.08, 0.1)
	var sy := (1.0 - 0.3 * maxf(crouch_k, _e_crouch) * (1.0 - lie_k)) * (1.0 - squash + stv)
	var sxz := 1.0 + squash * 0.6 - stv * 0.5
	rig_scale = Vector3(sxz, sy, sxz) * size_k
	rig.basis = _euler_yxz(Vector3(rx - e_pitch, yaw + e_yaw, fall_a)).scaled_local(rig_scale)
	body.position.y = body_y
	body.basis = _euler_xyz(Vector3(lean.x + e_lx, 0, lean.y + e_lz))
	var neck_x := head.x
	if dead and d_p > 0.02:                                # flailing while it tumbles, then limp
		var fl := sin(d_p * 34.0) * (1.0 - clampf(d_p, 0.0, 1.0))
		var w := 1.0 - clampf((d_p - 0.15) / 0.85, 0.0, 1.0)
		leg0 = fl * 1.3 * w + (1.0 - w) * 0.25
		leg1 = -fl * 1.3 * w - (1.0 - w) * 0.2
		arm_lx = cos(d_p * 30.0) * 0.9 * w
		arm_lz = 0.5 + 1.7 * w
		neck_x = head.x - 0.9 * w
	neck.basis = _euler_xyz(Vector3(neck_x, 0, head.y)).scaled_local(Vector3.ONE * float(cls.get("head", 1.0)))
	legs[0].basis = Basis(Vector3.RIGHT, leg0)
	legs[1].basis = Basis(Vector3.RIGHT, leg1)
	arm_l.basis = _euler_xyz(Vector3(arm_lx, 0, arm_lz))
	var sh := rig.transform * (body.transform * shoulder.position)
	arm.position = sh
	arm.basis = Basis(_arc(SIM_DOWN, arm_dir)).scaled(Vector3.ONE * size_k)
	_face_step(dt)
	_apply_flash()


## Ragdoll overlay (rig_mode "ragdoll"): call AFTER the gameplay points were read from the classic pose.
func overlay(dt: float) -> void:
	if emote_id != "":                                      # a dance keeps the classic pose (the ragdoll would undo it)
		return
	if _gait_dirty or gait_seed != _gait_pin:               # sample the personality once per fighter (look/owner change)
		_gait_pin = gait_seed
		_gait_dirty = false
		rag.set_gait(gait_identity(), float(cls.get("wob", 1.0)))
	if not _overlaid:
		_xf_saved.resize(_xf_nodes.size())
		for i in _xf_nodes.size():
			_xf_saved[i] = _xf_nodes[i].transform
	var grip := arm.transform * hand.transform              # the classic (= sim) grip, wobbler-local
	rag.update(self, dt)
	rag.render(self, dt, grip)
	_overlaid = true


## A Combat `lean` kick, for the ragdoll's hit reaction (the classic springs get theirs from Fighter.on_event).
func ragdoll_hit(a: float, b: float) -> void:
	rag.hit(a, b, yaw, float(cls.get("size", 1.0)))


func _restore_classic() -> void:
	for i in _xf_saved.size():
		_xf_nodes[i].transform = _xf_saved[i]
	_overlaid = false


static func _arc(from: Vector3, to: Vector3) -> Quaternion:   # three.js Quaternion.setFromUnitVectors
	var r := from.dot(to) + 1.0
	var q: Quaternion
	if r < 1e-6:
		q = Quaternion(-from.y, from.x, 0.0, 0.0) if absf(from.x) > absf(from.z) else Quaternion(0.0, -from.z, from.y, 0.0)
	else:
		var cr := from.cross(to)
		q = Quaternion(cr.x, cr.y, cr.z, r)
	return q.normalized()


func _apply_flash() -> void:
	var white := invuln and not dead
	var k := (0.28 + 0.4 * (0.5 + 0.5 * sin(_time * 14.0))) if white else flash * 0.8
	if white == _flash_white and absf(k - _flash_k) < 1e-4:
		return
	if white != _flash_white:
		for m in _mats:
			m.emission = Color.WHITE if white else Color.hex(0xff6644ff)
	_flash_white = white
	_flash_k = k
	for m in _mats:
		m.emission_energy_multiplier = k


## Every MeshInstance3D in the character (for tests / the graphics pass).
func mesh_count() -> int:
	return _count(self)


func _count(n: Node) -> int:
	var k := 1 if n is MeshInstance3D else 0
	for ch in n.get_children():
		k += _count(ch)
	return k


## What a fighter costs the renderer (docs/GRAPHICS.md "Fighter mesh batching", the perf/gfx gates): MeshInstance3D
## nodes (all / visible in tree), the surfaces they draw (all / visible), the unique materials and the node total.
## Batched meshes have several surfaces but one mesh node; hidden held-weapon holders count in the "all" numbers only.
func mesh_stats() -> Dictionary:
	var out := {"meshes": 0, "meshes_visible": 0, "surfaces": 0, "surfaces_visible": 0, "nodes": 0,
		"materials": 0}
	var mats := {}
	_stats_walk(self, out, mats)
	out["materials"] = mats.size()
	return out


func _stats_walk(n: Node, out: Dictionary, mats: Dictionary) -> void:
	out["nodes"] += 1
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		out["meshes"] += 1
		var vis := mi.is_visible_in_tree()
		if vis:
			out["meshes_visible"] += 1
		var mesh: Mesh = mi.mesh
		var sf := 0 if mesh == null else mesh.get_surface_count()
		out["surfaces"] += sf
		if vis:
			out["surfaces_visible"] += sf
		if mi.material_override != null:
			mats[mi.material_override] = true
		for i in sf:
			var m := mi.get_surface_override_material(i)
			if m != null:
				mats[m] = true
	for ch in n.get_children():
		_stats_walk(ch, out, mats)


## Unique material instances this fighter renders with (the merged-mesh statics are shared; only the flash material and
## an occasional cull-off flash clone are per fighter). Replaces the old per-part `_mats` leak check in the tests.
func material_count() -> int:
	return int(mesh_stats()["materials"])


# ================================================================ faces (Sprint 2.4, docs/GRAPHICS.md "Faces")
## The eye rig stays exactly TWO MeshInstance3D: every expression is a transform of those nodes (plus a mesh swap to the
## shared X surface while dead / down). No node, material or draw call is added, and nothing the combat code reads
## (hand, arm, shoulder, head, chest, legs) is touched, in either rig mode.
##   idle    eyes open, a blink every 2.5-4.5 s (own deterministic RNG, seeded once in setup())
##   blink   eyes close and open over a few frames (sin envelope, BLINK_DUR)
##   angry   inner brow ends angle down + eyes squint: melee swing (swing >= 0) or rage up (state "rage" > 0)
##   panic   wide eyes, brows lifted: airborne off the arena floor (state "off_stage" / "panic")
##   x       crossed bars: dead or down_t > 0
func face_state() -> String:
	if dead or down_t > 0.0:
		return "x"
	if panic_k > 0.5:
		return "panic"
	if angry_k > 0.5:
		return "angry"
	if blink_t >= 0.0:
		return "blink"
	return "idle"


## The blink personality: the owning Fighter's identity + look (gait_identity, the M0 pattern) or the pinned
## `blink_seed`. Never the global RNG and never Combat.rng: presentation only, deterministic over the same dt sequence.
func blink_identity() -> int:
	if blink_seed >= 0:
		return blink_seed
	return (gait_identity() ^ 0x5F356495) & 0x7fffffff


## Seed the blink clock once per setup (a look / owner change restarts the schedule deterministically).
func _face_setup() -> void:
	_face_rng = RandomNumberGenerator.new()
	_face_rng.seed = blink_identity()
	_blink_wait = _face_rng.randf_range(BLINK_WAIT_MIN, BLINK_WAIT_MAX)
	blink_interval = _blink_wait
	blink_t = -1.0
	angry_k = 0.0
	panic_k = 0.0
	_x_set(false)
	_face_sig.x = -1.0
	_pose_eyes()


## One face frame: blend toward the state's expression, run the blink clock, apply the transform to the two eyes.
func _face_step(dt: float) -> void:
	face_time += dt
	var x_on := dead or down_t > 0.0
	_blink_tick(dt)
	var panic_target := 1.0 if off_stage and not grounded and not x_on else 0.0
	var angry_target := 1.0 if (rage > 0.0 or swing >= 0.0) and not x_on else 0.0
	panic_k += (panic_target - panic_k) * minf(1.0, dt * FACE_K_PANIC)
	angry_k += (angry_target - angry_k) * minf(1.0, dt * FACE_K_ANGRY)
	_x_set(x_on)
	_pose_eyes()


## Countdown to the next blink start; the interval between starts is drawn from [BLINK_WAIT_MIN, BLINK_WAIT_MAX].
func _blink_tick(dt: float) -> void:
	_blink_wait -= dt
	if _blink_wait <= 0.0:
		blink_t = 0.0
		blink_started_at = face_time
		blink_count += 1
		blink_interval = _face_rng.randf_range(BLINK_WAIT_MIN, BLINK_WAIT_MAX)
		_blink_wait += blink_interval
	elif blink_t >= 0.0:
		blink_t += dt
		if blink_t >= BLINK_DUR:
			blink_t = -1.0


## Swap the two eye meshes to / from the shared crossed-bar X surface (still the same two meshes / draw calls).
func _x_set(on: bool) -> void:
	if on == _x_eyes:
		return
	_x_eyes = on
	var m: Mesh = x_eye_mesh() if on else _eye_mesh
	for e in eyes:
		if e != null:
			e.mesh = m


## Apply this frame's expression to the two eye nodes (children of `neck`: the head and every gameplay point are
## separate nodes, so faces can never move them).
func _pose_eyes() -> void:
	var x_on := _x_eyes
	var panic := 0.0 if x_on else panic_k
	var angry := (0.0 if x_on else angry_k) * (1.0 - panic)
	var open := 1.0
	if blink_t >= 0.0 and not x_on and panic < 0.5:
		open = 1.0 - sin(PI * clampf(blink_t / BLINK_DUR, 0.0, 1.0))
	eye_open = 1.0 if x_on else open * (1.0 - (1.0 - ANGRY_SQUINT) * angry) * (1.0 + (PANIC_WIDE - 1.0) * panic)
	var inner := ANGRY_ANGLE * angry - PANIC_ANGLE * panic      # + = inner brow ends down
	var lift := PANIC_LIFT * panic - ANGRY_DROP * angry
	var sx := 1.0 + (PANIC_WIDE_X - 1.0) * panic
	brow_angle = signf(-EYE_X) * inner
	var sig := Vector4(eye_open, brow_angle, lift, sx)
	if sig == _face_sig:                                        # unchanged (idle): skip the two node writes
		return
	_face_sig = sig
	for i in eyes.size():
		var e := eyes[i]
		if e == null:
			continue
		var ex := -EYE_X if i == 0 else EYE_X
		var b := _eye_base_scale[i]
		var ang := signf(ex) * inner
		e.basis = _euler_xyz(Vector3(0, 0, ang)).scaled_local(Vector3(b.x * sx, b.y * eye_open, b.z))
		e.position = Vector3(ex, EYE_Y, EYE_Z) + Vector3(0, lift, 0)


## The MID / HIGH open eye: the eye box plus a brow bar in ONE surface (one draw call). Static and shared by every
## wobbler: +24 triangles per wobbler, no extra MeshInstance3D, material or draw call. LOW keeps the plain eye box.
static func _face_eye_mesh() -> ArrayMesh:
	if _eye_brow_cache != null:
		return _eye_brow_cache
	_eye_brow_cache = _combine_meshes([
		[EYE_SIZE, Vector3.ZERO, 0.0],
		[BROW_SIZE, Vector3(0.0, BROW_Y, 0.0), 0.0],
	])
	return _eye_brow_cache


## The dead / down X eye: two crossed bars in one surface, swapped into the same two eye meshes while down. Shared.
static func x_eye_mesh() -> ArrayMesh:
	if _x_eye_cache != null:
		return _x_eye_cache
	var a := X_EYE_SIZE
	_x_eye_cache = _combine_meshes([[a, Vector3.ZERO, PI / 4.0], [a, Vector3.ZERO, -PI / 4.0]])
	return _x_eye_cache


## One ArrayMesh surface from several (size, centre, Z rotation) boxes: the cached LowPoly box arrays transformed and
## appended, so each face part stays a single draw call.
static func _combine_meshes(parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	for part: Array in parts:
		var sz: Vector3 = part[0]
		var centre: Vector3 = part[1]
		var rot := Basis(Vector3.BACK, float(part[2]))
		var arrays := LowPoly.box(sz.x, sz.y, sz.z).surface_get_arrays(0)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in v.size():
			verts.append(rot * v[i] + centre)
		for i in n.size():
			norms.append(rot * n[i])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = norms
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return m
