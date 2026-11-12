extends Node3D
## Offline match world: builds a map with MapBuilder, runs a MatchSim (the player + bots, combat, crates) at the web
## game's fixed step (SIM = 1/120, one accumulator, like `frame`/`simStep` in public/index.html ~10077 / ~9630),
## presents every fighter with a Wobbler, drains Combat events into effects, and feeds the HUD (ui/hud.tscn).
## Per frame (like `frame`): camera -> sim steps -> animate/applyPose (Fighter.present) -> melee sweep -> effects/HUD.
## Command line (after `--`): --map=<id> --class=<id> --bots=<n> --seed=<n> --dyn=<off|random|wobble|tilt|quake|drift>
## --mode=<id> --limit=<n>. Game modes (logic/mode_rules.gd): offline the mode comes from Settings "mode" and the K.O.
## limit from Settings "limit" (-1 = the mode's preset); this node adds team colours, the mode line, the dash puff,
## the shrinking floor mesh, the end-of-match banner and the offline results panel.
## Dynamic arenas: MatchSim.dyn moves the collision; this node moves the tile / block meshes to match (_dyn_views).
## Online: set `session` (GuestSession or HostSession that got / sent `start`) and `start_msg` before adding the
## world; the map, rules and slots come from that start message. Guests see ghosts for every other seat; the host
## runs bots and ghosts only the human seats (NetMatch.is_host).

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
@export var mode_id := ""          ## game mode offline: "" = Settings "mode" (default classic); see ModeRules.PLAYABLE
@export var ko_limit := -1         ## K.O. limit offline: -1 = Settings "limit" (where -1 = the mode's preset), 0 = none
@export var difficulty := ""       ## bot skill offline: "" = Settings "difficulty" (easy / normal / hard / insane, default normal)

@onready var env_node: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun
@onready var cam: FollowCamera = $Camera
@onready var input: PlayerInput = $PlayerInput
@onready var touch: TouchControls = $UI/TouchControls
@onready var hud: MatchHud = $UI/Hud
@onready var pause_menu: Control = $UI/Pause

var sim: MatchSim
var session = null                 ## GuestSession or HostSession (null = offline)
var start_msg := {}                ## the cleaned `start` this match was built from
var net_match: NetMatch = null
var hosting := false               ## true when session is a HostSession
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
var proj_views: ProjectileViews     ## rockets, grenades, arrows, nets, knives, explosions, flames
var _touch_was := false
var _mats := {}
var _dyn_tiles: Array = []         ## MeshInstance3D per sim.dyn.tiles entry (same order)
var _dyn_blocks: Array = []        ## MeshInstance3D per sim.dyn.drift entry
var _dyn_riders: Array = []        ## {node, y0, ti}: small floor decor riding a tile
var _mode_l: Label                 ## the mode line (lives, team score, ladder rung, arena size, dashes)
var _banner: Label                 ## "YOU WIN!" at the end of a match
var _banner_t := 0.0
var _shrink_mesh: MeshInstance3D   ## the shrinking floor (shrink / squeeze maps)

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
		elif a.begins_with("--mode="): mode_id = a.substr(7)
		elif a.begins_with("--limit="): ko_limit = int(a.substr(8))
	Tier.configure_viewport(get_viewport())
	touch.state = input.state
	touch.pause_pressed.connect(_toggle_pause)
	input.pause_requested.connect(_toggle_pause)
	$UI/Pause/Panel/Box/Resume.pressed.connect(_toggle_pause)
	$UI/Pause/Panel/Box/Title.pressed.connect(_on_title_pressed)
	var fps: CheckButton = $UI/Pause/Panel/Box/Fps
	fps.button_pressed = bool(Settings.get_value("show_fps", false))
	fps.toggled.connect(func(on: bool): Settings.set_value("show_fps", on))
	Settings.changed.connect(_on_setting)
	JuicyButton.attach_all(pause_menu)
	pause_menu.visible = false
	_fx_root = Node3D.new(); _fx_root.name = "Fx"; add_child(_fx_root)
	_fighters_root = Node3D.new(); _fighters_root.name = "Fighters"; add_child(_fighters_root)
	proj_views = ProjectileViews.new(); proj_views.name = "Projectiles"; add_child(proj_views)
	_build_mode_ui()
	if session != null:
		hosting = session is HostSession
		map_id = start_msg.get("map", map_id)
		session.match_started.connect(_on_net_start)
		session.match_message.connect(_on_net_message)
		session.votes_changed.connect(_on_net_votes)
		session.ended.connect(_on_net_ended)
		if session.has_signal("rehosted"):
			session.rehosted.connect(_on_net_rehosted)
		if hosting:
			session.guest_joined.connect(_on_host_guest_joined)
			session.guest_left.connect(_on_host_guest_left)
		$UI/Pause/Panel/Box/Title.text = "Leave room"
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
	if proj_views: proj_views.clear()
	if net_match: net_match.dispose(); net_match = null
	if sim: sim.dispose()
	if _results: _results.queue_free(); _results = null
	if _shrink_mesh: _shrink_mesh.queue_free(); _shrink_mesh = null
	_banner_t = 0.0
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
		NetMatch.apply_rules(sim.combat, start_msg.get("rules", {}), hosting)
		var rd := NetMatch.rule_dyn(start_msg.get("rules", {}))
		sim.dyn_choice = rd["choice"]; sim.dyn_seed = rd["seed"]; sim.dyn_t0 = rd["t0"]
	else:
		var mode := mode_id if mode_id != "" else str(Settings.get_value("mode", "classic"))
		sim.combat.set_mode(mode if sim.combat.modes.has(mode) else "classic")   # the start weapon and crate pool follow it
		sim.dyn_choice = dyn_choice if dyn_choice != "" else str(Settings.get_value("dyn", "random"))
		sim.dyn_seed = Dynamics.hash32(rng_seed, 9, 0, 0) if rng_seed > 0 else randi()   # a fresh arena every match
	control = PlayerControl.new(input.state)
	var cid := player_class if player_class != "" else str(Settings.get_value("class", "wobbler"))
	if not sim.combat.classes.has(cid): cid = "wobbler"
	var bots := bot_count
	var skill := difficulty if difficulty != "" else str(Settings.get_value("difficulty", "normal"))
	if not Content.difficulties.has(skill): skill = "normal"
	if session == null:                    # offline game mode (pickMode / setBotCfg)
		var mid := mode_id if mode_id != "" else str(Settings.get_value("mode", "classic"))
		if not sim.combat.modes.has(mid): mid = "classic"
		sim.configure(mid, ko_limit if ko_limit >= 0 else int(Settings.get_value("limit", -1)))
		bots = ModeRules.bot_count(mid, sim.combat.modes, bot_count)
	elif hosting:
		var rules: Dictionary = start_msg.get("rules", {})
		var mid2: String = str(rules.get("mode", "classic"))
		if not sim.combat.modes.has(mid2): mid2 = "classic"
		sim.configure(mid2, int(start_msg.get("limit", 0)))
		bots = maxi(0, start_msg.get("slots", []).size() - 1)
		if session is HostSession:
			skill = str(session.diff)
			if not Content.difficulties.has(skill): skill = "normal"
	else:
		bots = 0
	sim.setup(id, map_node.map, map_node.ladders, map_node.pads, cid, control, bots if session == null or hosting else 0, skill)
	solids = sim.solids                   # the live collision (moving tiles / blocks) for the camera too
	_build_dyn_views()
	if session != null:
		net_match = NetMatch.new(sim, session.send, session.slot, hosting)
		if hosting and session is HostSession:
			net_match.host_session = session
			session.set_crate_check(func(c: int) -> bool: return sim.pickups.find_cid(c) >= 0 or _host_crate_id_exists(c))
		net_match.setup(start_msg)
		sim.player.name = str(Settings.get_value("name", "Player"))
	var scene: PackedScene = load("res://actors/fighter.tscn")
	for f: FighterState in sim.fighters:
		var v: Fighter = scene.instantiate()
		_fighters_root.add_child(v)
		var lk: Dictionary = sim.looks.get(f, _my_look())
		v.bind(f, lk)
		if v.tag:   # the HUD draws the nameplates (ui/hud_nameplates.gd)
			v.tag.queue_free(); v.tag = null
		var tc := sim.combat.rules.team_color(f)
		if tc >= 0:                      # team modes: everyone wears the team colour (recolor(TEAM_COL[team], true))
			v.look["color"] = tc; v.wobbler.recolor(tc, true)
		views[f] = v
	player_view = views[sim.player]
	_build_shrink_view()
	cam.reset_view()
	feed.clear()
	acc = 0.0
	hud.bind(self)

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
	control.cam_yaw = cam.move_basis()   # the camera yaw, held while auto-centre turns it under a held stick
	var ap := cam.aim_point
	control.aim_point = [ap.x, ap.y, ap.z] if ap != Vector3.ZERO else []
	var before: int = sim.player.st["falls"]
	sim.step(dt)
	if sim.player.st["falls"] != before:
		falls += 1

## One rendered frame: sim steps from the accumulator, then the presentation (animation, melee sweep, effects, HUD).
func tick(delta: float) -> void:
	var dt := minf(delta, 0.05)
	var finished := _results != null and session == null     # offline results panel up: finishMatch left the match
	if (not paused or net_match != null) and not finished:      # online the match keeps running behind the menu
		if not paused:
			var st := input.state
			var look := st.take_look()
			cam.add_look(look)
			var p := sim.player.phys
			cam.auto_center(dt, look, st.move(), Vector2(p.vx, p.vz), st.aiming() or st.is_held("fire") or touch.look_held(), st.is_held("sprint"))
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
	_update_shrink_view()
	_update_fx(dt)
	proj_views.update(dt)

# ============================== combat events -> visuals ==============================

func _drain_events() -> void:
	var evs: Array = sim.combat.events
	for e: Dictionary in evs:
		counts[e["type"]] = int(counts.get(e["type"], 0)) + 1
		Sfx.on_event(e, sim)
		if net_match != null: net_match.on_event(e)
		var f: FighterState = e.get("f") if e.get("f") is FighterState else null
		proj_views.on_event(e)
		match String(e["type"]):
			"lean", "head", "arm":
				if views.has(f): views[f].on_event(e)
			"dmg_number":
				if f: _dmg_number(Vector3(f.head_x, f.head_y + 0.5, f.head_z), float(e["dmg"]), String(e.get("part", "head" if e["head"] else "")), int(e.get("pct", 0)))
			"hit":
				if f:
					_puff(Vector3(f.chest_x, f.chest_y, f.chest_z), Color(1, 0.95, 0.8), 4, 3.0)
					if e.has("x") and PART_COL.has(String(e.get("part", ""))):   # body-part flash where it struck
						_puff(Vector3(e["x"], e["y"], e["z"]), PART_COL[e["part"]], 3, 1.5)
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
			"puff":                       # Combat/Weapons puffs (dash, Air Blower gusts along `dir`)
				_puff(Vector3(e["x"], e["y"], e["z"]), Color.hex((int(e.get("color", 0xffffff)) << 8) | 0xff), int(e.get("n", 4)),
					float(e.get("spd", 3.0)), e.get("dir", []))
			"pad":
				if f: _puff(Vector3(f.phys.px, 0.15, f.phys.pz), Color(0.62, 0.96, 0.92), 6, 3.0)
			"toast":
				_toast(str(e["text"]))
			"match_end":
				_show_results(str(e["name"]))
			"match_over":
				_show_banner(str(e["title"]), str(e["sub"]), bool(e["won"]))
			"match_finished":
				if session == null: _show_offline_results(bool(e["won"]), str(e["winner"].name) if e.get("winner") else "")
			"eliminated":
				if f:
					hud.add_feed(null, f, "", false)
					_toast("You're out!" if f == sim.player else "%s is out!" % f.name)
			"puff":
				if str(e.get("kind", "")) == "dash": _puff(Vector3(e["x"], e["y"], e["z"]), Color(0.85, 0.92, 1.0), 6, 3.5)
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
	hud.add_feed(k, v, str(e.get("weapon", "")), bool(e.get("fall", false)))
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

func _puff(at: Vector3, col: Color, n: int, spd: float, dir: Array = []) -> void:
	if Tier.is_web() and _fx.size() > 80: return
	for i in n:
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3.ONE * 0.16
		m.mesh = bm
		m.material_override = _mat(col)
		m.position = at
		var d := Vector3(randf_range(-1, 1), randf_range(0.2, 1.2), randf_range(-1, 1)).normalized() * spd * randf_range(0.4, 1.0)
		if dir.size() == 3: d = (Vector3(dir[0], dir[1], dir[2]) * 1.6 + d.normalized() * 0.35).normalized() * spd * randf_range(0.6, 1.0)
		_add_fx(m, randf_range(0.3, 0.6), d, "puff")

## Damage-number colour and size per body part (Combat.body_part; docs/DAMAGE.md). "" = whole body (splash, flame).
const PART_COL := {"head": Color(1, 0.35, 0.25), "torso": Color(1, 0.95, 0.4), "arms": Color(0.55, 0.85, 1), "legs": Color(0.75, 0.8, 0.9)}
const PART_SIZE := {"head": 56, "torso": 44, "arms": 40, "legs": 38}

## The number floats up from the head; a non-zero part bonus adds a second line ("+50%", "-25%").
func _dmg_number(at: Vector3, dmg: float, part: String, pct: int = 0) -> void:
	var l := Label3D.new()
	l.text = str(int(round(dmg))) + ("\n%+d%%" % pct if pct != 0 else "")
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = PART_SIZE.get(part, 44)
	l.pixel_size = 0.006
	l.outline_size = 12
	l.modulate = PART_COL.get(part, Color(1, 0.95, 0.4))
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

# ============================== HUD (ui/hud.tscn) ==============================

func _toast(t: String) -> void:
	hud.toast(t)

func _update_hud(delta: float) -> void:
	hud.update(delta)
	_update_mode_ui(delta)

# ============================== game modes (logic/mode_rules.gd) ==============================

func _build_mode_ui() -> void:
	_mode_l = Label.new()
	_mode_l.name = "ModeLine"
	_mode_l.theme_type_variation = &"HudLabel"
	_mode_l.add_theme_font_size_override("font_size", 22)
	_mode_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UI.add_child(_mode_l)
	$UI.move_child(_mode_l, hud.get_index() + 1)
	_banner = Label.new()
	_banner.name = "Banner"
	_banner.theme_type_variation = &"TitleLabel"
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	$UI.add_child(_banner)
	$UI.move_child(_banner, hud.get_index() + 1)

func _update_mode_ui(delta: float) -> void:
	if sim == null or _mode_l == null: return
	var vs := get_viewport().get_visible_rect().size
	var ins := SafeArea.insets(get_viewport())
	var t := sim.combat.rules.hud_text(sim.player) if session == null else ""
	if _mode_l.text != t: _mode_l.text = t
	_mode_l.visible = t != ""
	_mode_l.reset_size()
	_mode_l.position = Vector2(vs.x / 2.0 - _mode_l.size.x / 2.0, float(ins[1]) + 44.0)      # under the crate toast (hud.gd keeps that at the very top)
	if _banner.visible:
		_banner_t -= delta
		_banner.reset_size()
		_banner.position = Vector2(vs.x / 2.0 - _banner.size.x / 2.0, vs.y * 0.3)
		if _banner_t <= 0.0: _banner.visible = false

## endMatch's "YOU WIN!" pop (shown while the match runs on for ModeRules.END_TIME).
func _show_banner(title: String, sub: String, won: bool) -> void:
	_banner.text = title + "\n" + sub
	_banner.add_theme_color_override("font_color", UiTheme.ACCENT if won else Color(1, 0.85, 0.8))
	_banner.visible = true
	_banner_t = ModeRules.END_TIME + 0.5

## finishMatch offline: the result with Play again / Title (themed, centred, over the HUD).
func _show_offline_results(won: bool, winner_name: String) -> void:
	if _results: _results.queue_free()
	_banner.visible = false
	var p := PanelContainer.new()
	p.name = "Results"
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.custom_minimum_size = Vector2(380, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	p.add_child(box)
	var l := Label.new()
	l.theme_type_variation = &"TitleLabel"
	l.add_theme_color_override("font_color", UiTheme.ACCENT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var teams := sim.combat.teams != 0
	l.text = ("Your team wins!" if won else "Enemy team wins!") if teams else ("You win!" if won else winner_name + " wins!")
	box.add_child(l)
	var info := Label.new()
	info.theme_type_variation = &"MutedLabel"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.text = "%s  ·  %d K.O.s  ·  %d deaths" % [str(sim.combat.mode.get("name", sim.combat.mode_id)), sim.player.ko, int(sim.player.st["deaths"])]
	box.add_child(info)
	var again := Button.new(); again.text = "Play again"; again.custom_minimum_size = Vector2(0, 58)
	again.theme_type_variation = &"PrimaryButton"
	again.add_theme_font_size_override("font_size", 26)
	again.pressed.connect(func() -> void: load_map.call_deferred(map_id))
	box.add_child(again)
	var lv := Button.new(); lv.text = "Title"; lv.custom_minimum_size = Vector2(0, 54)
	lv.pressed.connect(_on_title_pressed)
	box.add_child(lv)
	JuicyButton.attach_all(box)
	$UI.add_child(p)
	$UI.move_child(p, pause_menu.get_index())
	_results = p
	touch.release_all()
	input.release_mouse()

## The shrinking floor: the map's first box is drawn by its own mesh, scaled to ModeRules.shrink every frame.
func _build_shrink_view() -> void:
	var s: Dictionary = sim.combat.rules.shrink
	if s.is_empty(): return
	var boxes: Array = map_node.map.get("geometry", {}).get("boxes", [])
	MapBuilder.rebuild_boxes(map_node, boxes, {0: true})
	var b: Dictionary = boxes[0]
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(float(b["w"]), float(b["h"]), float(b["d"]))
	mi.mesh = bm; mi.material_override = MapBuilder.material(int(b["color"])); mi.name = "ShrinkFloor"
	mi.position = Vector3(float(b["x"]), float(b["y"]) + float(b["h"]) / 2.0, float(b["z"]))
	map_node.add_child(mi)
	_shrink_mesh = mi
	_update_shrink_view()

func _update_shrink_view() -> void:
	if _shrink_mesh == null: return
	var s: Dictionary = sim.combat.rules.shrink
	var k: float = s["size"] / s["S0"]
	_shrink_mesh.scale = Vector3(k, 1.0, k if s["both"] else 1.0)

func _on_setting(key: String, v: Variant) -> void:
	if key == "show_fps":
		($UI/Pause/Panel/Box/Fps as CheckButton).set_pressed_no_signal(bool(v))

# ============================== online (guest / host) ==============================

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

func _on_host_guest_joined(s: int, info: Dictionary) -> void:
	if net_match == null: return
	var f := net_match.slot_changed(s, "human", info)
	if f != null: _relook(f)

func _on_host_guest_left(s: int, kind: String) -> void:
	if net_match == null: return
	var info: Dictionary = start_msg.get("slots", [])[s] if s < start_msg.get("slots", []).size() else {"name": "Bot", "skin": "none", "hat": "none", "color": 0xf08a3c, "cls": "wobbler"}
	if net_match.slots.size() > s: info = net_match.slots[s]
	var f := net_match.slot_changed(s, kind, info)
	if f != null: _relook(f)

func _host_crate_id_exists(cid: int) -> bool:
	for p: Dictionary in sim.pickups.list:
		if int(p.get("cid", p.get("id", -1))) == cid: return true
	return false

func _on_title_pressed() -> void:
	if session != null:
		session.leave("You left the room.")     # _on_net_ended goes to the title
	else:
		get_tree().change_scene_to_file("res://scenes/main.tscn")

## Back to the title screen; an active session (re-hosting) stays alive there.
func _to_title(msg: String) -> void:
	if not is_inside_tree(): return
	if session != null:
		var pairs: Array = [[session.match_started, _on_net_start], [session.match_message, _on_net_message], [session.votes_changed, _on_net_votes], [session.ended, _on_net_ended]]
		if session.has_signal("rehosted"): pairs.append([session.rehosted, _on_net_rehosted])
		if hosting:
			pairs.append([session.guest_joined, _on_host_guest_joined])
			pairs.append([session.guest_left, _on_host_guest_left])
		for sig: Array in pairs:
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

## pend: the host ended the match. Results + rematch vote (themed panel, centred, over the HUD).
func _show_results(winner: String) -> void:
	if _results: _results.queue_free()
	var p := PanelContainer.new()
	p.name = "Results"
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.custom_minimum_size = Vector2(380, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	p.add_child(box)
	var l := Label.new()
	l.theme_type_variation = &"TitleLabel"
	l.add_theme_color_override("font_color", UiTheme.ACCENT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text = ("You win!" if winner == "You" else winner + " wins!")
	box.add_child(l)
	var votes := Label.new()
	votes.theme_type_variation = &"MutedLabel"
	votes.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	votes.name = "Votes"
	box.add_child(votes)
	var rm := Button.new(); rm.text = "Rematch"; rm.custom_minimum_size = Vector2(0, 58)
	rm.theme_type_variation = &"PrimaryButton"
	rm.add_theme_font_size_override("font_size", 26)
	rm.pressed.connect(func() -> void:
		if session: session.vote_rematch()
		rm.disabled = true; rm.text = "Waiting for the others…")
	box.add_child(rm)
	var lv := Button.new(); lv.text = "Leave room"; lv.custom_minimum_size = Vector2(0, 54)
	lv.pressed.connect(_on_title_pressed)
	box.add_child(lv)
	JuicyButton.attach_all(box)
	$UI.add_child(p)
	$UI.move_child(p, pause_menu.get_index())   # under the pause menu, over the HUD and touch layer
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
