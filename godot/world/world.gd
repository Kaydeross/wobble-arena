extends Node3D
## Offline match world: builds a map with MapBuilder, runs a MatchSim (the player + bots, combat, crates) at the web
## game's fixed step (SIM = 1/120, one accumulator, like `frame`/`simStep` in public/index.html ~10077 / ~9630),
## presents every fighter with a Wobbler, drains Combat events into effects, and draws a minimal HUD.
## Per frame (like `frame`): camera -> sim steps -> animate/applyPose (Fighter.present) -> melee sweep -> effects/HUD.
## Command line (after `--`): --map=<id> --class=<id> --bots=<n> --seed=<n> --dyn=<off|random|wobble|tilt|quake|drift>.
## Dynamic arenas: MatchSim.dyn moves the collision; this node moves the tile / block meshes to match (_dyn_views).
## Online (guest): set `session` (a GuestSession that got `start`) and `start_msg` before adding the world; the map,
## rules and slots then come from the host, the other players are ghosts driven by a NetMatch (net/net_match.gd).

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
@export var dyn_choice := ""       ## dynamic arena offline: "" = Settings "dyn" (default random), or off/random/wobble/tilt/quake/drift

@onready var env_node: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun
@onready var cam: FollowCamera = $Camera
@onready var input: PlayerInput = $PlayerInput
@onready var touch: TouchControls = $UI/TouchControls
@onready var hud: Label = $UI/Hud
@onready var pause_menu: Control = $UI/Pause

var sim: MatchSim
var session: GuestSession = null   ## online guest session (null = offline)
var start_msg := {}                ## the cleaned `start` this match was built from
var net_match: NetMatch = null
var _results: Control = null
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
var _dyn_tiles: Array = []         ## MeshInstance3D per sim.dyn.tiles entry (same order)
var _dyn_blocks: Array = []        ## MeshInstance3D per sim.dyn.drift entry
var _dyn_riders: Array = []        ## {node, y0, ti}: small floor decor riding a tile

## The player's physics (tests and the camera read it).
var phys: FighterPhysics:
	get: return sim.player.phys if sim else null

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="): map_id = a.substr(6)
		elif a.begins_with("--class="): player_class = a.substr(8)
		elif a.begins_with("--bots="): bot_count = int(a.substr(7))
		elif a.begins_with("--seed="): rng_seed = int(a.substr(7))
		elif a.begins_with("--dyn="): dyn_choice = a.substr(6)
	Tier.configure_viewport(get_viewport())
	touch.state = input.state
	touch.pause_pressed.connect(_toggle_pause)
	input.pause_requested.connect(_toggle_pause)
	$UI/Pause/Box/Resume.pressed.connect(_toggle_pause)
	$UI/Pause/Box/Title.pressed.connect(_on_title_pressed)
	pause_menu.visible = false
	_fx_root = Node3D.new(); _fx_root.name = "Fx"; add_child(_fx_root)
	_fighters_root = Node3D.new(); _fighters_root.name = "Fighters"; add_child(_fighters_root)
	_build_hud()
	if session != null:
		map_id = start_msg.get("map", map_id)
		session.match_started.connect(_on_net_start)
		session.match_message.connect(_on_net_message)
		session.votes_changed.connect(_on_net_votes)
		session.ended.connect(_on_net_ended)
		session.rehosted.connect(_on_net_rehosted)
		$UI/Pause/Box/Title.text = "Leave room"
	load_map(map_id)

func _exit_tree() -> void:
	if net_match:
		net_match.dispose()
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
	if net_match: net_match.dispose(); net_match = null
	if sim: sim.dispose()
	if _results: _results.queue_free(); _results = null
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
	if session != null:
		NetMatch.apply_rules(sim.combat, start_msg.get("rules", {}))
		var rd := NetMatch.rule_dyn(start_msg.get("rules", {}))
		sim.dyn_choice = rd["choice"]; sim.dyn_seed = rd["seed"]; sim.dyn_t0 = rd["t0"]
	else:
		sim.dyn_choice = dyn_choice if dyn_choice != "" else str(Settings.get_value("dyn", "random"))
		sim.dyn_seed = Dynamics.hash32(rng_seed, 9, 0, 0) if rng_seed > 0 else randi()   # a fresh arena every match
	control = PlayerControl.new(input.state)
	var cid := player_class if player_class != "" else str(Settings.get_value("class", "wobbler"))
	if not sim.combat.classes.has(cid): cid = "wobbler"
	sim.setup(id, map_node.map, map_node.ladders, map_node.pads, cid, control, 0 if session != null else bot_count)
	solids = sim.solids                   # the live collision (moving tiles / blocks) for the camera too
	_build_dyn_views()
	if session != null:
		net_match = NetMatch.new(sim, session.send, session.slot)
		net_match.setup(start_msg)
		sim.player.name = str(Settings.get_value("name", "Player"))
	var scene: PackedScene = load("res://actors/fighter.tscn")
	for f: FighterState in sim.fighters:
		var v: Fighter = scene.instantiate()
		_fighters_root.add_child(v)
		var lk: Dictionary = sim.looks.get(f, _my_look())
		v.bind(f, lk)
		views[f] = v
	player_view = views[sim.player]
	cam.yaw = PI; cam.pitch = -0.2
	feed.clear()
	acc = 0.0

func _my_look() -> Dictionary:
	var col := int(Settings.get_value("color", 0x39b5a8))
	var sk: Dictionary = Content.cosmetics.get("skins", {}).get(str(Settings.get_value("skin", "none")), {})
	if sk.has("col"): col = int(sk["col"])
	return {"skin": str(Settings.get_value("skin", "none")), "hat": str(Settings.get_value("hat", "none")), "color": col}

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
	if not paused or net_match != null:      # online the match keeps running behind the menu
		if not paused: cam.add_look(input.state.take_look())
		cam.follow(dt, player_pos(), input.state.aiming(), solids)
		acc += minf(dt, 0.1)
		while acc >= SIM:
			sim_step(SIM)
			acc -= SIM
	present(dt if (not paused or net_match != null) else 0.0)
	_update_hud(delta)

func _process(delta: float) -> void:
	if session != null:
		session.poll(delta)
		if not is_inside_tree() or sim == null: return
	if auto_run:
		tick(delta)
	else:
		cam.follow(minf(delta, 0.05), player_pos(), false, solids)
		_update_hud(delta)

## applyPose + meleeSweep + effects (also used by tests that step the sim by hand).
func present(dt: float) -> void:
	for v: Fighter in views.values():
		v.visible = not v.state.left
		v.present(dt)
	sim.sweep()
	_drain_events()
	_update_crates(dt)
	_update_dyn_views()
	_update_fx(dt)

# ============================== combat events -> visuals ==============================

func _drain_events() -> void:
	var evs: Array = sim.combat.events
	for e: Dictionary in evs:
		counts[e["type"]] = int(counts.get(e["type"], 0)) + 1
		Sfx.on_event(e, sim)
		if net_match != null: net_match.on_event(e)
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
			"match_end":
				_show_results(str(e["name"]))
			"relook":
				_relook(f)
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

# ============================== dynamic arenas (dynBuildTiles / dynBuildDrift, visual half) ==============================

## Tile / block meshes for the moving parts MatchSim.dyn set up. The static merged boxes are rebuilt without them.
func _build_dyn_views() -> void:
	_dyn_tiles = []; _dyn_blocks = []; _dyn_riders = []
	var d := sim.dyn
	if d.kind == "off": return
	var boxes: Array = map_node.map.get("geometry", {}).get("boxes", [])
	var exclude := {}
	if d.kind == "drift":
		for e: Dictionary in d.drift: exclude[e["i"]] = true
	else:
		exclude[d.plan["floor"]] = true
	MapBuilder.rebuild_boxes(map_node, boxes, exclude)
	if d.kind == "drift":
		for e: Dictionary in d.drift:
			var b: Dictionary = boxes[e["i"]]
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new(); bm.size = Vector3(float(b["w"]), float(b["h"]), float(b["d"]))
			mi.mesh = bm; mi.material_override = MapBuilder.material(int(b["color"])); mi.name = "Drift_%d" % e["i"]
			map_node.add_child(mi)
			_dyn_blocks.append(mi)
		_update_dyn_views()
		return
	var P := d.plan
	var nx: int = P["nx"]
	var nz: int = P["nz"]
	var tw: float = P["tw"]
	var td: float = P["td"]
	var base := int(boxes[P["floor"]]["color"])
	# flat paint on the floor (floor pads) cannot follow the tiles: small pieces ride the tile under them, big ones are
	# hidden and their colour goes onto the tiles they cover
	var tint: Array = []; tint.resize(nx * nz); tint.fill(-1)
	var pads: Array = map_node.map.get("geometry", {}).get("floorPads", [])
	var pad_nodes: Array = []
	for c in map_node.get_children():
		if str(c.name).begins_with("FloorPad"): pad_nodes.append(c)
	for k in mini(pads.size(), pad_nodes.size()):
		var sz := float(pads[k]["size"])
		var node: Node3D = pad_nodes[k]
		var ix := int(floor((0.0 - float(P["x0"])) / tw))
		var iz := int(floor((0.0 - float(P["z0"])) / td))
		if ix < 0 or ix >= nx or iz < 0 or iz >= nz: continue
		if sz <= tw * 1.2 and sz <= td * 1.2:
			_dyn_riders.append({"node": node, "y0": node.position.y, "ti": iz * nx + ix}); continue
		node.visible = false
		for t in nx * nz:
			var x := float(P["x0"]) + (t % nx + 0.5) * tw
			var z := float(P["z0"]) + (t / nx + 0.5) * td
			if x > -sz / 2.0 and x < sz / 2.0 and z > -sz / 2.0 and z < sz / 2.0: tint[t] = int(pads[k]["color"])
	var h: float = P["top"] - P["bottom"]
	var bm := BoxMesh.new(); bm.size = Vector3(tw, h, td)
	var mats := {}
	for e: Dictionary in d.tiles:
		var k: int = e["iz"] * nx + e["ix"]
		var hexc: int = tint[k] if tint[k] >= 0 else base
		var odd: int = (e["ix"] + e["iz"]) & 1
		var key := "%d_%d" % [hexc, odd]
		if not mats.has(key):
			var m: StandardMaterial3D = MapBuilder.material(hexc).duplicate()
			m.albedo_color = _offset_l(MapBuilder.hex(hexc), 0.035 if odd else -0.01)
			mats[key] = m
		var mi := MeshInstance3D.new()
		mi.mesh = bm; mi.material_override = mats[key]; mi.name = "Tile_%d_%d" % [e["ix"], e["iz"]]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		map_node.add_child(mi)
		_dyn_tiles.append(mi)
	_update_dyn_views()

## three.js Color.offsetHSL(0, 0, dl) on an sRGB colour.
static func _offset_l(c: Color, dl: float) -> Color:
	var mx := maxf(c.r, maxf(c.g, c.b)); var mn := minf(c.r, minf(c.g, c.b))
	var l := (mx + mn) / 2.0
	var s := 0.0
	if mx != mn: s = (mx - mn) / (2.0 - mx - mn) if l > 0.5 else (mx - mn) / (mx + mn)
	var l2 := clampf(l + dl, 0.0, 1.0)
	if s == 0.0: return Color(l2, l2, l2)
	var k := (1.0 - absf(2.0 * l2 - 1.0)) * s / maxf(1e-9, (1.0 - absf(2.0 * l - 1.0)))
	return Color(clampf(l2 + (c.r - l) * k, 0, 1), clampf(l2 + (c.g - l) * k, 0, 1), clampf(l2 + (c.b - l) * k, 0, 1))

## Meshes follow the live solids; quake drops/rises puff a little dust.
func _update_dyn_views() -> void:
	var d := sim.dyn
	if d.kind == "off": return
	if d.kind == "drift":
		for i in _dyn_blocks.size():
			var s: Dictionary = d.drift[i]["s"]
			_dyn_blocks[i].position = Vector3((s.minX + s.maxX) * 0.5, (s.top + s.bottom) * 0.5, (s.minZ + s.maxZ) * 0.5)
		return
	for i in _dyn_tiles.size():
		var s: Dictionary = d.tiles[i]["s"]
		_dyn_tiles[i].position = Vector3((s.minX + s.maxX) * 0.5, (s.top + s.bottom) * 0.5, (s.minZ + s.maxZ) * 0.5)
	for r: Dictionary in _dyn_riders:
		r["node"].position.y = r["y0"] + maxf(d.tiles[r["ti"]]["off"], -1.0)
	for q: Dictionary in d.fx:
		if q["type"] == "drop": _puff(Vector3(q["x"], q["y"], q["z"]), Color.hex(0xb9a88cff), 8, 3.0)
		else: _puff(Vector3(q["x"], q["y"] + 0.1, q["z"]), Color.hex(0xd8cdb8ff), 6, 2.5)
	d.fx.clear()

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
		if c["grounded"] and absf(float(c["gy"])) < 0.05:          # crates ride the moving floor tiles
			g.position.y += maxf(sim.dyn.floor_dy(c["x"], c["z"]), -1.0)
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

# ============================== online (guest) ==============================

func _on_net_message(m: Dictionary) -> void:
	if net_match != null: net_match.handle(m)

## `start` again: a rematch (or the host restarted). Rebuild the match from it.
func _on_net_start(s: Dictionary) -> void:
	start_msg = s
	load_map.call_deferred(str(s["map"]))

func _on_net_ended(reason: String) -> void:
	_to_title(reason)

func _on_net_rehosted() -> void:
	_to_title("The host left. Waiting for the new host to start…")

func _on_title_pressed() -> void:
	if session != null:
		session.leave("You left the room.")     # _on_net_ended goes to the title
	else:
		get_tree().change_scene_to_file("res://scenes/main.tscn")

## Back to the title screen; an active session (re-hosting) stays alive there.
func _to_title(msg: String) -> void:
	if not is_inside_tree(): return
	if session != null:
		for sig: Array in [[session.match_started, _on_net_start], [session.match_message, _on_net_message], [session.votes_changed, _on_net_votes], [session.ended, _on_net_ended], [session.rehosted, _on_net_rehosted]]:
			if (sig[0] as Signal).is_connected(sig[1]): (sig[0] as Signal).disconnect(sig[1])
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.set("session", session if session != null and session.is_active() else null)
	main.set("notice", msg)
	session = null
	get_tree().change_scene_to_node.call_deferred(main)

## A ghost's owner changed (slot): rebuild its look.
func _relook(f: FighterState) -> void:
	if f == null or not views.has(f): return
	views[f].queue_free()
	var v: Fighter = load("res://actors/fighter.tscn").instantiate()
	_fighters_root.add_child(v)
	v.bind(f, sim.looks.get(f, {}))
	views[f] = v

## pend: the host ended the match. Results + rematch vote (placeholder UI).
func _show_results(winner: String) -> void:
	if _results: _results.queue_free()
	var p := PanelContainer.new()
	p.name = "Results"
	_pin(p, 0.5, 0.5, Rect2(-220, -110, 440, 220))
	var box := VBoxContainer.new()
	p.add_child(box)
	var l := _label(box, 30, HORIZONTAL_ALIGNMENT_CENTER)
	l.text = ("You win!" if winner == "You" else winner + " wins!")
	var votes := _label(box, 18, HORIZONTAL_ALIGNMENT_CENTER)
	votes.name = "Votes"
	var rm := Button.new(); rm.text = "Rematch"; rm.custom_minimum_size = Vector2(0, 54)
	rm.pressed.connect(func() -> void:
		if session: session.vote_rematch()
		rm.disabled = true; rm.text = "Waiting for the others…")
	box.add_child(rm)
	var lv := Button.new(); lv.text = "Leave room"; lv.custom_minimum_size = Vector2(0, 54)
	lv.pressed.connect(_on_title_pressed)
	box.add_child(lv)
	$UI.add_child(p)
	_results = p

func _on_net_votes(list: Array, total: int) -> void:
	if _results: (_results.find_child("Votes", true, false) as Label).text = "Rematch votes: %d / %d" % [list.size(), total]

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
