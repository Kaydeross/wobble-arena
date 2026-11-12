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

const SIM_DOWN := Vector3(0, -1, 0)
const FLASH_FULL := 0.12            # web Fighter.flash after a hit (seconds)

## Hit flash 0..1 (drives emission like the web game's emissive); decays by itself unless the state drives it.
var flash: float = 0.0
var class_id: String = ""
var skin_key: String = "none"
var hat_name: String = "none"
var color: int = WobblerLooks.DEFAULT_COLOR
var weapon: String = ""
var cls: Dictionary = {}

# --- rig nodes (same hierarchy as the JS Fighter)
var rig: Node3D                      # JS root: position, yaw, fall roll, squash
var body: Node3D
var neck: Node3D
var torso: MeshInstance3D
var head_mesh: MeshInstance3D
var eyes: Array[MeshInstance3D] = []
var belt: MeshInstance3D
var buckle: MeshInstance3D
var legs: Array[Node3D] = []
var arm_l: Node3D
var hand_l: MeshInstance3D
var shoulder: Node3D
var arm: Node3D                      # the aiming arm, positioned in world space each frame
var hand: Node3D
var hat: Node3D
var hat_spin: Node3D

# --- materials (each part owns one, so flash/recolour work per fighter, like Fighter.mats)
var _mats: Array[StandardMaterial3D] = []
var _color_mats: Array[StandardMaterial3D] = []
var _accent_mats: Array[StandardMaterial3D] = []
var _leg_mats: Array[StandardMaterial3D] = []
var _foot_mats: Array[StandardMaterial3D] = []
var _tint: Array = []                # [mat, mul, mix]: outfit parts tinted from the top colour
var _skin_nodes: Array[Node] = []
var _cls_nodes: Array[Node] = []
var _weapon_nodes: Dictionary = {}
var _flash_white := false
var _flash_k := -1.0

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


func _init() -> void:
	_build()
	setup("wobbler", "none", "none", WobblerLooks.DEFAULT_COLOR)


# ================================================================ material: the ONE place parts get their look
## Flat-shaded low-poly material (web `lm`). The graphics pass swaps this for the rim-light shader.
func _make_mat(c: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.hex(c << 8 | 0xff)
	m.roughness = 0.95
	m.metallic = 0.0
	m.emission_enabled = true
	m.emission = Color.hex(0xff6644ff)
	m.emission_energy_multiplier = 0.0
	return m


## A flashing body material, sorted into the colour groups the web game recolours.
func _mat(c: int, group: String = "") -> StandardMaterial3D:
	var m := _make_mat(c)
	_mats.append(m)
	match group:
		"color": _color_mats.append(m)
		"accent": _accent_mats.append(m)
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
func _build() -> void:
	rig = _group(self, Vector3.ZERO, "Rig")
	body = _group(rig, Vector3(0, 0.8, 0), "Body")
	torso = _mesh(body, LowPoly.cyl(0.4, 0.34, 0.85, 6), _mat(WobblerLooks.DEFAULT_COLOR, "color"), Vector3(0, 0.425, 0), "Torso")
	neck = _group(body, Vector3(0, 0.85, 0), "Neck")
	head_mesh = _mesh(neck, LowPoly.ico(0.36, 0), _mat(WobblerLooks.ACCENT, "accent"), Vector3(0, 0.32, 0), "Head")
	var eye_mat := _make_mat(WobblerLooks.EYE)
	eye_mat.emission_enabled = false
	for sx in [-0.13, 0.13]:
		eyes.append(_mesh(neck, LowPoly.box(0.1, 0.14, 0.06), eye_mat, Vector3(sx, 0.36, 0.32), "Eye"))
	var belt_mat := _make_mat(WobblerLooks.BELT)
	belt_mat.emission_enabled = false
	var buckle_mat := _make_mat(WobblerLooks.BUCKLE)
	buckle_mat.emission_enabled = false
	buckle_mat.metallic = 0.3
	buckle_mat.roughness = 0.5
	belt = _mesh(body, LowPoly.cyl(0.385, 0.36, 0.1, 6), belt_mat, Vector3(0, 0.17, 0), "Belt")
	buckle = _mesh(body, LowPoly.box(0.11, 0.09, 0.05), buckle_mat, Vector3(0, 0.17, 0.37), "Buckle")
	for x in [-0.2, 0.2]:
		var g := _group(rig, Vector3(x, 0.8, 0), "Leg")
		var lm := _mat(WobblerLooks.DEFAULT_COLOR, "color")
		var fm := _mat(WobblerLooks.ACCENT, "accent")
		_leg_mats.append(lm)
		_foot_mats.append(fm)
		_mesh(g, LowPoly.cyl(0.15, 0.12, 0.8, 5), lm, Vector3(0, -0.4, 0), "Thigh")
		_mesh(g, LowPoly.box(0.26, 0.12, 0.4), fm, Vector3(0, -0.74, 0.07), "Foot")
		legs.append(g)
	arm_l = _group(body, Vector3(0.52, 0.75, 0), "ArmL")             # local +X is the character's left
	_mesh(arm_l, LowPoly.cyl(0.11, 0.09, 0.75, 5), _mat(WobblerLooks.DEFAULT_COLOR, "color"), Vector3(0, -0.375, 0), "Sleeve")
	hand_l = _mesh(arm_l, LowPoly.ico(0.13, 0), _mat(WobblerLooks.ACCENT, "accent"), Vector3(0, -0.78, 0), "HandL")
	shoulder = _group(body, Vector3(-0.52, 0.75, 0), "Shoulder")        # right shoulder
	arm = _group(self, Vector3.ZERO, "Arm")                              # aiming arm: free in world space
	_mesh(arm, LowPoly.cyl(0.11, 0.09, 0.85, 5), _mat(WobblerLooks.DEFAULT_COLOR, "color"), Vector3(0, -0.425, 0), "Sleeve")
	_mesh(arm, LowPoly.ico(0.14, 0), _mat(WobblerLooks.ACCENT, "accent"), Vector3(0, -0.85, 0), "Hand")
	hand = _group(arm, Vector3(0, -0.85, 0), "Grip")


## Builds a list of look parts (see WobblerLooks) under this rig. Returns the created nodes.
func _add_parts(parts: Array, flashes: bool, extra_parents: Dictionary = {}) -> Array[Node]:
	var out: Array[Node] = []
	var sk := WobblerLooks.skin_def(skin_key)
	var tone: int = sk.get("tone", WobblerLooks.ACCENT)
	for pt in parts:
		var parent: Node3D
		match String(pt[0]):
			"neck": parent = neck
			"body": parent = body
			"leg0": parent = legs[0]
			"leg1": parent = legs[1]
			"armL": parent = arm_l
			"arm": parent = arm
			_: parent = extra_parents.get(pt[0], null)
		if parent == null:
			continue
		var spec: Variant = pt[2]
		var c: int
		var tinted := false
		if spec is Array:
			tinted = true
			c = 0xffffff
		elif spec is String:
			c = tone if spec == "tone" else WobblerLooks.hex_mix(tone, 0.9, 0.0)
		else:
			c = int(spec)
		var m := _mat(c) if flashes else _make_mat(c)
		if tinted:
			_tint.append([m, spec[0], spec[1]])
		if pt.size() > 5 and pt[5] is Dictionary and pt[5].has("glow"):
			m.emission = _col(pt[5]["glow"])
			m.emission_energy_multiplier = pt[5].get("glow_k", 0.6)
		if String(pt[1][0]) == "sph":
			m.cull_mode = BaseMaterial3D.CULL_DISABLED            # open shells (beanie, viking helmet) are seen from inside too
		var p: Array = pt[3]
		var mi := _mesh(parent, LowPoly.from_spec(pt[1]), m, Vector3(p[0], p[1], p[2]))
		var r := Vector3.ZERO
		var s := Vector3.ONE
		if pt.size() > 4:
			r = Vector3(pt[4][0], pt[4][1], pt[4][2])
		if pt.size() > 5 and pt[5] is Array:
			s = Vector3(pt[5][0], pt[5][1], pt[5][2])
		mi.basis = _euler_xyz(r).scaled_local(s)
		out.append(mi)
	return out


# ================================================================ looks
func setup(p_class_id: String, p_skin: String = "none", p_hat: String = "none", p_color: int = WobblerLooks.DEFAULT_COLOR) -> void:
	color = p_color
	set_class(p_class_id)
	set_skin(p_skin)
	set_hat(p_hat)


## Fighter.setClass + classLook: proportions plus a few cheap accessories. Looks only.
func set_class(id: String) -> void:
	if not WobblerLooks.data("classes").has(id):
		id = "wobbler"
	class_id = id
	cls = WobblerLooks.class_def(id)
	for n in _cls_nodes:
		_free_part(n)
	_cls_nodes.clear()
	var wide: float = cls.get("wide", 1.0)
	var deep := 1.0 + (wide - 1.0) * 0.5
	var arm_x := 0.52 * wide
	neck.scale = Vector3.ONE * float(cls.get("head", 1.0))
	torso.scale = Vector3(wide, 1, deep)
	belt.scale = Vector3(wide, 1, deep)
	buckle.position.z = 0.37 * deep
	arm_l.position.x = arm_x
	shoulder.position.x = -arm_x
	var ek := 1.5 if id == "alien" else 1.0
	for e in eyes:
		e.scale = Vector3(ek, ek, 1)
	_cls_nodes = _add_parts(WobblerLooks.class_parts(id, arm_x, deep), true)
	_skin_flags()
	recolor(color)


## Outfit (Fighter.setSkin). Keys come from cosmetics.json skins; unknown keys mean no outfit.
func set_skin(key: String) -> void:
	for n in _skin_nodes:
		_free_part(n)
	_skin_nodes.clear()
	_tint.clear()
	skin_key = key if WobblerLooks.skin_def(key).size() > 0 else "none"
	if skin_key != "none":
		_skin_nodes = _add_parts(WobblerLooks.skin_parts(skin_key), true)
	recolor(color)
	_skin_flags()


func set_hat(name: String) -> void:
	if hat:
		hat.free()
	hat = null
	hat_spin = null
	hat_name = name if WobblerLooks.HATS.has(name) else "none"
	if hat_name == "none":
		return
	hat = _group(neck, Vector3(0, 0.62, 0), "Hat")
	var extra := {"hat": hat}
	if WobblerLooks.HAT_SPIN_Y.has(hat_name):
		hat_spin = _group(hat, Vector3(0, WobblerLooks.HAT_SPIN_Y[hat_name], 0), "Spin")
		extra["spin"] = hat_spin
	_add_parts(WobblerLooks.hat_parts(hat_name), false, extra)
	_skin_flags()


## Fighter.recolor: body colour; outfits keep their own top colour (team matches pass team = true to force `c`).
func recolor(c: int, team: bool = false) -> void:
	color = c
	var sk := WobblerLooks.skin_def(skin_key)
	var main: int = c if sk.is_empty() or team else int(sk.get("col", c))
	for m in _color_mats:
		m.albedo_color = _col(main)
	if sk.is_empty():
		for m in _accent_mats:
			m.albedo_color = _col(WobblerLooks.ACCENT)
	else:
		for t in _tint:
			t[0].albedo_color = _col(WobblerLooks.hex_mix(main, t[1], t[2]))
		var tone: int = sk.get("tone", WobblerLooks.ACCENT)
		for m in _accent_mats:
			m.albedo_color = _col(tone)
		var pants: Variant = sk.get("pants", main)
		for m in _leg_mats:
			m.albedo_color = _col(tone if pants is String else int(pants))
		for m in _foot_mats:
			m.albedo_color = _col(int(sk.get("shoes", tone)))
	if cls.has("skin"):                                        # Zorp: green skin on head, hands and feet
		for m in _accent_mats:
			m.albedo_color = _col(int(cls["skin"]))


func _skin_flags() -> void:
	var sk := WobblerLooks.skin_def(skin_key)
	belt.visible = not sk.get("noBelt", false)
	buckle.visible = belt.visible
	head_mesh.visible = not sk.get("noHead", false)
	torso.visible = not sk.get("noTorso", false)
	for e in eyes:
		e.visible = not sk.get("noEyes", false)
	if hat:
		hat.visible = not sk.get("noHat", false)


func _free_part(n: Node) -> void:
	if n is MeshInstance3D:
		var m: Material = n.material_override
		_mats.erase(m)
		_color_mats.erase(m)
		_accent_mats.erase(m)
	n.get_parent().remove_child(n)
	n.free()


## Held weapon mesh in the aiming hand (built once per key). "" / null = empty hand.
func set_weapon(key: Variant) -> void:
	var k: String = "" if key == null else String(key)
	weapon = k
	if k != "" and not _weapon_nodes.has(k):
		var holder := _group(hand, Vector3.ZERO, "W_" + k)
		holder.add_child(WeaponModels.build(k, _make_mat))
		_weapon_nodes[k] = holder
	for wk in _weapon_nodes:
		_weapon_nodes[wk].visible = wk == k
	var wd: Dictionary = WobblerLooks.data("weapons").get(k, {})
	stiff = float(wd.get("stiff", 25.0)) if k != "" else 25.0


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
	if not _state_flash:
		flash = 1.0


# ================================================================ animate (Fighter.animate ~5619 + applyPose ~5882)
func animate(dt: float) -> void:
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

	# poses that steer the aiming arm: melee swing (meleeTick), falling over, lying trapped
	var st := stiff if _stiff_override < 0.0 else _stiff_override
	var target := aim_target
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
	rig.position = Vector3(pos.x, pos.y + lift + lie_k * 0.3, pos.z)
	var rx := lie_k * lie_side * PI / 2.0 * 0.98 + (-fall_side * TAU * clampf(d_p * 1.1, 0.0, 1.0) if dead else 0.0)
	var size_k := float(cls.get("size", 1.0))
	var stv := 0.0 if grounded else clampf(vel.y * 0.012, -0.08, 0.1)
	var sy := (1.0 - 0.3 * crouch_k * (1.0 - lie_k)) * (1.0 - squash + stv)
	var sxz := 1.0 + squash * 0.6 - stv * 0.5
	rig.basis = _euler_yxz(Vector3(rx, yaw, fall_a)).scaled_local(Vector3(sxz, sy, sxz) * size_k)
	body.position.y = body_y
	body.basis = _euler_xyz(Vector3(lean.x, 0, lean.y))
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
	_apply_flash()


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
