extends Node3D
## Offline match world: builds a map with MapBuilder, runs a MatchSim (the player + bots, combat, crates) at the web
## game's fixed step (SIM = 1/120, one accumulator, like `frame`/`simStep` in public/index.html ~10077 / ~9630),
## presents every fighter with a Wobbler, drains Combat events into effects, and draws a minimal HUD.
## Per frame (like `frame`): camera -> sim steps -> animate/applyPose (Fighter.present) -> melee sweep -> effects/HUD.
## Command line (after `--`): --map=<id> --class=<id> --bots=<n> --seed=<n>.

const SIM := 1.0 / 120.0
const FEED_TIME := 5.0
const FX_DMG_LIFE := 0.9

@export var map_id := "arena"
## false = the sim only advances when tick()/sim_step() is called (headless tests)
@export var auto_run := true
@export var bot_count := 3
@export var player_class := ""     ## "" = Settings "class"
@export var rng_seed := 0          ## 0 = random
@export var hp_setting := 200.0    ## cfg.hp (the web menu offers 100 / 150 / 200 / 300 / 500)

@onready var env_node: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun
@onready var cam: FollowCamera = $Camera
@onready var input: PlayerInput = $PlayerInput
@onready var touch: TouchControls = $UI/TouchControls
@onready var hud: Label = $UI/Hud
@onready var pause_menu: Control = $UI/Pause

var sim: MatchSim
var control: PlayerControl
var map_node: MapBuilder.MapNode
var solids: Array = []
var views := {}                    ## FighterState -> Fighter
var player_view: Fighter
var acc := 0.0
var paused := false
var falls := 0                     ## times the player fell out of the map
var feed: Array = []               ## [text, time left]
var counts := {}                   ## Combat event type -> how many (tests and debugging)
var _crates := {}                  ## crate id -> Node3D
var _fx: Array = []                ## {node, life, max, vel, kind}
var _fx_root: Node3D
var _fighters_root: Node3D
var _toast_t := 0.0
var _fps_t := 0.0
var _touch_was := false
var _ui := {}
var _mats := {}

## The player's physics (tests and the camera read it).
var phys: FighterPhysics:
	get: return sim.player.phys if sim else null

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="): map_id = a.substr(6)
		elif a.begins_with("--class="): player_class = a.substr(8)
		elif a.begins_with("--bots="): bot_count = int(a.substr(7))
		elif a.begins_with("--seed="): rng_seed = int(a.substr(7))
	Tier.configure_viewport(get_viewport())
	touch.state = input.state
	touch.pause_pressed.connect(_toggle_pause)
	input.pause_requested.connect(_toggle_pause)
	$UI/Pause/Box/Resume.pressed.connect(_toggle_pause)
	$UI/Pause/Box/Title.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main.tscn"))
	pause_menu.visible = false
	_fx_root = Node3D.new(); _fx_root.name = "Fx"; add_child(_fx_root)
	_fighters_root = Node3D.new(); _fighters_root.name = "Fighters"; add_child(_fighters_root)
	_build_hud()
	load_map(map_id)

func _exit_tree() -> void:
	if sim:
		sim.dispose()

## loadMap: a fresh match on `id`.
func load_map(id: String) -> void:
	if map_node:
		map_node.queue_free()
	for v in views.values(): v.queue_free()
	views.clear()
	for c in _crates.values(): c.queue_free()
	_crates.clear()
	if sim: sim.dispose()
	map_id = id
	map_node = MapBuilder.build(id)
	add_child(map_node)
	solids = map_node.solids
	env_node.environment = MapBuilder.make_environment(map_node.map)
	MapBuilder.setup_sun(sun, map_node.map)
	Tier.configure_sun(sun, map_node.shadow_area)
	sim = MatchSim.new()
	if rng_seed > 0: sim.combat.rng = CombatRng.new(rng_seed)
	sim.combat.hp_setting = hp_setting
	control = PlayerControl.new(input.state)
	var cid := player_class if player_class != "" else str(Settings.get_value("class", "wobbler"))
	if not sim.combat.classes.has(cid): cid = "wobbler"
	sim.setup(id, map_node.map, map_node.ladders, map_node.pads, cid, control, bot_count)
	var scene: PackedScene = load("res://actors/fighter.tscn")
	for f: FighterState in sim.fighters:
		var v: Fighter = scene.instantiate()
		_fighters_root.add_child(v)
		var lk: Dictionary = sim.looks.get(f, {"skin": "none", "hat": "none", "color": int(Settings.get_value("color", 0x39b5a8))})
		v.bind(f, lk)
		views[f] = v
	player_view = views[sim.player]
	cam.yaw = PI; cam.pitch = -0.2
	feed.clear()
	acc = 0.0

func player_pos() -> Vector3:
	var p := sim.player.phys
	return Vector3(p.px, p.py, p.pz)

## One fixed simulation step.
func sim_step(dt: float) -> void:
	control.cam_yaw = cam.yaw
	var ap := cam.aim_point
	control.aim_point = [ap.x, ap.y, ap.z] if ap != Vector3.ZERO else []
	var before: int = sim.player.st["falls"]
	sim.step(dt)
	if sim.player.st["falls"] != before:
		falls += 1

## One rendered frame: sim steps from the accumulator, then the presentation (animation, melee sweep, effects, HUD).
func tick(delta: float) -> void:
	var dt := minf(delta, 0.05)
	if not paused:
		cam.add_look(input.state.take_look())
		cam.follow(dt, player_pos(), input.state.aiming(), solids)
		acc += minf(dt, 0.1)
		while acc >= SIM:
			sim_step(SIM)
			acc -= SIM
	present(dt if not paused else 0.0)
	_update_hud(delta)

func _process(delta: float) -> void:
	if auto_run:
		tick(delta)
	else:
		cam.follow(minf(delta, 0.05), player_pos(), false, solids)
		_update_hud(delta)

## applyPose + meleeSweep + effects (also used by tests that step the sim by hand).
func present(dt: float) -> void:
	for v: Fighter in views.values():
		v.present(dt)
	sim.sweep()
	_drain_events()
	_update_crates(dt)
	_update_fx(dt)

# ============================== combat events -> visuals ==============================

func _drain_events() -> void:
	var evs: Array = sim.combat.events
	for e: Dictionary in evs:
		counts[e["type"]] = int(counts.get(e["type"], 0)) + 1
		var f: FighterState = e.get("f") if e.get("f") is FighterState else null
		match String(e["type"]):
			"lean", "head", "arm":
				if views.has(f): views[f].on_event(e)
			"dmg_number":
				if f: _dmg_number(Vector3(f.head_x, f.head_y + 0.5, f.head_z), float(e["dmg"]), bool(e["head"]))
			"hit":
				if f: _puff(Vector3(f.chest_x, f.chest_y, f.chest_z), Color(1, 0.95, 0.8), 4, 3.0)
			"ko":
				_on_ko(e)
			"ko_burst":
				if f: _puff(Vector3(f.phys.px, f.phys.py + 1.0, f.phys.pz), Color(1, 0.85, 0.3), 14, 7.0)
			"tracer":
				_tracer(Vector3(e["ox"], e["oy"], e["oz"]), Vector3(e["ex"], e["ey"], e["ez"]))
			"crate":
				_crate_view(e["crate"])
			"crate_land":
				var c: Dictionary = e["crate"]
				_puff(Vector3(c["x"], c["gy"] + 0.3, c["z"]), Color(1, 0.82, 0.29), 10, 5.0)
			"crate_take", "crate_gone":
				var c2: Dictionary = e["crate"]
				if _crates.has(c2["id"]):
					_crates[c2["id"]].queue_free(); _crates.erase(c2["id"])
				if e["type"] == "crate_take" and e["f"] == sim.player:
					_toast("Got " + sim.pickups.label(c2["key"]))
			"pad":
				if f: _puff(Vector3(f.phys.px, 0.15, f.phys.pz), Color(0.62, 0.96, 0.92), 6, 3.0)
			"toast":
				_toast(str(e["text"]))
	evs.clear()

func _on_ko(e: Dictionary) -> void:
	var k: FighterState = e.get("killer")
	var v: FighterState = e.get("victim")
	if v == null: return
	var txt := ""
	if k == null: txt = "%s fell off" % v.name if e.get("fall", false) else "%s was K.O.'d" % v.name
	else: txt = "%s  [%s]  %s" % [k.name, e.get("weapon", ""), v.name]
	feed.push_front([txt, FEED_TIME])
	if feed.size() > 5: feed.resize(5)
	if k == sim.player: _toast("K.O.!")

# ============================== effects (minimal: the art pass replaces them) ==============================

func _mat(c: Color, unshaded := true) -> StandardMaterial3D:
	var key := c.to_html()
	if _mats.has(key): return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if unshaded: m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if c.a < 1.0: m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m

func _add_fx(n: Node3D, life: float, vel := Vector3.ZERO, kind := "") -> void:
	_fx_root.add_child(n)
	_fx.append({"node": n, "life": life, "max": life, "vel": vel, "kind": kind})

func _puff(at: Vector3, col: Color, n: int, spd: float) -> void:
	if Tier.is_web() and _fx.size() > 80: return
	for i in n:
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3.ONE * 0.16
		m.mesh = bm
		m.material_override = _mat(col)
		m.position = at
		var d := Vector3(randf_range(-1, 1), randf_range(0.2, 1.2), randf_range(-1, 1)).normalized() * spd * randf_range(0.4, 1.0)
		_add_fx(m, randf_range(0.3, 0.6), d, "puff")

func _dmg_number(at: Vector3, dmg: float, head: bool) -> void:
	var l := Label3D.new()
	l.text = str(int(round(dmg)))
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 56 if head else 44
	l.pixel_size = 0.006
	l.outline_size = 12
	l.modulate = Color(1, 0.35, 0.25) if head else Color(1, 0.95, 0.4)
	l.position = at
	_add_fx(l, FX_DMG_LIFE, Vector3(0, 1.6, 0), "text")

func _tracer(o: Vector3, e: Vector3) -> void:
	var len := o.distance_to(e)
	if len < 0.05: return
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(0.035, 0.035, len)
	m.mesh = bm
	m.material_override = _mat(Color(1, 0.93, 0.6))
	var mid := (o + e) * 0.5
	m.look_at_from_position(mid, e, Vector3.UP if absf((e - o).normalized().y) < 0.99 else Vector3.RIGHT)
	_add_fx(m, 0.06, Vector3.ZERO, "tracer")

func _update_fx(dt: float) -> void:
	for i in range(_fx.size() - 1, -1, -1):
		var x: Dictionary = _fx[i]
		x["life"] -= dt
		var n: Node3D = x["node"]
		if x["life"] <= 0.0:
			n.queue_free(); _fx.remove_at(i); continue
		if x["kind"] == "puff":
			x["vel"] += Vector3(0, -9.0, 0) * dt
			n.scale = Vector3.ONE * clampf(x["life"] / x["max"], 0.05, 1.0)
		elif x["kind"] == "text":
			(n as Label3D).modulate.a = clampf(x["life"] / x["max"] * 1.5, 0.0, 1.0)
		n.position += x["vel"] * dt

# ============================== crates ==============================

func _crate_view(c: Dictionary) -> void:
	var key: String = c["key"]
	var pu: Dictionary = sim.pickups.drops.get("powerups", {})
	var col := Color.hex(0xffd24aff)
	var band := Color.hex(0xf29a2eff)
	if key == "heal": col = Color.hex(0xf4fff6ff); band = Color.hex(0x3ed36aff)
	elif pu.has(key): col = Color.hex(0xf4f8ffff); band = Color.hex((int(pu[key]["color"]) << 8) | 0xff)
	var g := Node3D.new()
	g.name = "Crate_%d" % c["id"]
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(0.8, 0.8, 0.8)
	box.mesh = bm; box.material_override = _mat(col, false); box.name = "Box"
	g.add_child(box)
	var strap := MeshInstance3D.new()
	var sm := BoxMesh.new(); sm.size = Vector3(0.84, 0.18, 0.84)
	strap.mesh = sm; strap.material_override = _mat(band, false)
	box.add_child(strap)
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = 0.45; cm.bottom_radius = 0.45; cm.height = 40.0; cm.radial_segments = 8
	beam.mesh = cm
	var wc := Color(band.r, band.g, band.b, 0.2)
	beam.material_override = _mat(wc)
	beam.position.y = 20.0; beam.name = "Beam"
	g.add_child(beam)
	var l := Label3D.new()
	l.text = sim.pickups.label(key)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 36; l.pixel_size = 0.006; l.outline_size = 10
	l.position.y = 1.3; l.name = "Label"
	g.add_child(l)
	add_child(g)
	g.position = Vector3(c["x"], c["y"] - 0.4, c["z"])
	_crates[c["id"]] = g

func _update_crates(_dt: float) -> void:
	for c: Dictionary in sim.pickups.list:
		var g: Node3D = _crates.get(c["id"])
		if g == null: continue
		g.position = Vector3(c["x"], c["y"] - 0.4, c["z"])
		var box: Node3D = g.get_node("Box")
		box.position.y = 0.4 + (sin(float(c["t"]) * 3.0) * 0.08 + float(c["open"]) * 0.3 if c["grounded"] else 0.0)
		box.rotation.y = float(c["t"]) * (2.0 if c["grounded"] else 1.2)
		var beam: Node3D = g.get_node("Beam")
		if c["grounded"]:
			beam.scale = Vector3(0.45, 0.07, 0.45); beam.position.y = 1.4

# ============================== HUD ==============================

func _label(parent: Node, size: int, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0.06, 0.17, 0.21))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

## Anchor a control to a fraction of the screen (ax, ay) with a pixel rect around that point.
static func _pin(c: Control, ax: float, ay: float, rect: Rect2) -> void:
	c.anchor_left = ax; c.anchor_right = ax; c.anchor_top = ay; c.anchor_bottom = ay
	c.offset_left = rect.position.x; c.offset_top = rect.position.y
	c.offset_right = rect.end.x; c.offset_bottom = rect.end.y

func _build_hud() -> void:
	var ui: CanvasLayer = $UI
	var root := Control.new()
	root.name = "MatchHud"
	root.anchor_right = 1.0; root.anchor_bottom = 1.0
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	ui.move_child(root, 0)
	# health bar with the class's max hp, bottom left
	var bar := Control.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	_pin(bar, 0.0, 1.0, Rect2(24, -70, 300, 26))
	var bg := ColorRect.new(); bg.color = Color(0.06, 0.08, 0.12, 0.7); bg.size = Vector2(300, 26); bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(bg)
	var fill := ColorRect.new(); fill.color = Color(0.36, 0.89, 0.48); fill.position = Vector2(3, 3); fill.size = Vector2(294, 20)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(fill)
	var hp_l := _label(bar, 18, HORIZONTAL_ALIGNMENT_CENTER); hp_l.size = Vector2(300, 26); hp_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var cls_l := _label(bar, 16); cls_l.position = Vector2(0, -26)
	# weapon + ammo, bottom right
	var wl := _label(root, 24, HORIZONTAL_ALIGNMENT_RIGHT)
	wl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_pin(wl, 1.0, 1.0, Rect2(-424, -90, 400, 60))
	# K.O. count + match clock, top centre
	var top := _label(root, 26, HORIZONTAL_ALIGNMENT_CENTER)
	_pin(top, 0.5, 0.0, Rect2(-200, 10, 400, 40))
	# kill feed, top right
	var fd := _label(root, 18, HORIZONTAL_ALIGNMENT_RIGHT)
	_pin(fd, 1.0, 0.0, Rect2(-524, 14, 500, 160))
	# toast, upper middle
	var ts := _label(root, 30, HORIZONTAL_ALIGNMENT_CENTER)
	_pin(ts, 0.5, 0.0, Rect2(-400, 64, 800, 50))
	_ui = {"fill": fill, "fill_w": 294.0, "hp": hp_l, "cls": cls_l, "weapon": wl, "top": top, "feed": fd, "toast": ts}

func _toast(t: String) -> void:
	_ui["toast"].text = t
	_toast_t = 2.2

func _update_hud(delta: float) -> void:
	if sim == null: return
	var p := sim.player
	var mx := sim.combat.max_hp(p)
	var k := clampf(p.hp / mx, 0.0, 1.0) if not p.dead else 0.0
	_ui["fill"].size.x = _ui["fill_w"] * k
	_ui["fill"].color = Color(0.36, 0.89, 0.48) if k > 0.5 else (Color(1.0, 0.8, 0.25) if k > 0.25 else Color(1.0, 0.35, 0.3))
	_ui["hp"].text = "%d / %d" % [ceili(maxf(p.hp, 0.0)) if not p.dead else 0, roundi(mx)]
	_ui["cls"].text = str(sim.combat.classes.get(p.class_id, {}).get("name", p.class_id))
	var wtxt := ""
	if p.dead: wtxt = "Respawning..."
	else:
		var w := sim.combat.wdata(p.weapon if p.weapon != "" else "spatula")
		wtxt = str(w.get("name", p.weapon))
		var s: Variant = p.current_slot()
		if s != null:
			if int(s["mag"]) >= 0: wtxt += "  %d / %d" % [int(s["mag"]), int(s["ammo"])]
			else: wtxt += "  x%d" % int(s["ammo"])
		if p.reloading: wtxt += "  (reloading)"
	_ui["weapon"].text = wtxt
	var t := int(sim.elapsed())
	_ui["top"].text = "K.O. %d    %d:%02d" % [p.ko, t / 60, t % 60]
	var lines: Array = []
	for i in range(feed.size() - 1, -1, -1):
		feed[i][1] -= delta
		if feed[i][1] <= 0.0: feed.remove_at(i)
	for it: Array in feed: lines.append(it[0])
	_ui["feed"].text = "\n".join(lines)
	_toast_t -= delta
	_ui["toast"].visible = _toast_t > 0.0
	_fps_t += delta
	if _fps_t < 0.25: return
	_fps_t = 0.0
	var name_s := str(map_node.map.get("name", map_id)) if map_node else map_id
	var hint := ""
	if Tier.is_pc() and not touch.visible and not input.mouse_captured() and not paused:
		hint = "\nClick to look around (Esc: menu)"
	hud.text = "%s  |  %s  |  %d fps%s" % [name_s, Tier.tier_name(), Engine.get_frames_per_second(), hint]

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
