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
## Effects (docs/GRAPHICS.md "Effects"): FxSystem (world/fx.gd: pooled particles, rings, streaks, damage numbers,
## specks), Trails (world/trails.gd: melee / projectile ribbons), FighterJuice per fighter (squash / stretch, hitstop
## pose freeze), camera shake. All presentation only: `fx_enabled = false` drops them and the sim plays the same.
## Online: set `session` (a GuestSession that got `start`, or a HostSession that started the match) and `start_msg` before adding the world; the map,
## rules and slots then come from the host, the other players are ghosts driven by a NetMatch (net/net_match.gd).

const SIM := 1.0 / 120.0
const FEED_TIME := 5.0

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
@export var fx_enabled := true     ## false = no particles, trails, squash / stretch, hitstop or shake (tests: sim hash)
## Sandbox build mode (ui/build_hud.gd): the 'custom' arena without bots, crates or a moving floor, the block palette
## instead of the score / radar / health / hotbar. Its Play saves and reloads the arena as a Sandbox match with bots.
@export var build_mode := false
var build_hud: BuildHud = null

@onready var env_node: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun
@onready var cam: FollowCamera = $Camera
@onready var input: PlayerInput = $PlayerInput
@onready var touch: TouchControls = $UI/TouchControls
@onready var hud: MatchHud = $UI/Hud
@onready var pause_menu: PauseMenu = $UI/Pause

var sim: MatchSim
var session: GuestSession = null   ## online guest session (null = offline)
var start_msg := {}                ## the cleaned `start` this match was built from
var net_match: NetMatch = null
var _results: Control = null
var _reward := {}                  ## Save.finish_match() summary for the results panel (ui/results_rewards.gd)
var emote_wheel: EmoteWheel        ## the in-match emote button + wheel (ui/emote_wheel.gd)
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
var fx: FxSystem = null            ## pooled combat effects (world/fx.gd); null when fx_enabled is false
var trails: Trails = null          ## melee / projectile ribbons (world/trails.gd)
var _hitstop := 0                  ## rendered frames the presentation stays frozen (hitstop)
var _fighters_root: Node3D
var proj_views: ProjectileViews     ## rockets, grenades, arrows, nets, knives, explosions, flames
var _touch_was := false
var _mats := {}
var _dyn_tiles: Array = []         ## MeshInstance3D per sim.dyn.tiles entry (same order)
var _dyn_blocks: Array = []        ## MeshInstance3D per sim.dyn.drift entry
var _dyn_riders: Array = []        ## {node, y0, ti}: small floor decor riding a tile
var _mode_l: Label                 ## the mode line (lives, ladder rung, arena size, dashes, chaos event)
var _team_board: TeamBoard         ## team modes: coloured chips with each team's score and a YOU tag on yours
var _banner: Label                 ## "YOU WIN!" at the end of a match
var _banner_t := 0.0
var _shrink_mesh: MeshInstance3D   ## the shrinking floor (shrink / squeeze maps)
## Spectator mode (Sudden Death, or any match the player is out of but that plays on): the camera follows this
## surviving fighter; tap / click / jump cycles to the next one (spectate_next). null = following the player.
var spectating: FighterState = null
var _spect_jump := false
## Kill cam (world/kill_cam.gd): a short side-on slow-mo replay after a fast K.O. you score. Offline only, Settings
## `kill_cam` (default on), not in team modes, not while spectating or once the match is over; a tap skips it.
var kill_cam := KillCam.new()
var kill_cam_in_tests := false
var _kc_l: Label                   ## "REPLAY · tap to skip"
var _kc_hud := true                ## HUD visibility to restore after the replay

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
	Gfx.add_post(self)                   # MID / HIGH vignette (docs/GRAPHICS.md)
	touch.state = input.state
	touch.pause_pressed.connect(_toggle_pause)
	touch.spectate_tap.connect(_on_spectate_tap)
	input.pause_requested.connect(_toggle_pause)
	# the pause menu (ui/pause_menu.gd): Resume, Settings, Controls, Quit to title (asks while the match runs)
	pause_menu.resume_requested.connect(_toggle_pause)
	pause_menu.quit_requested.connect(_on_title_pressed)
	pause_menu.match_running = func() -> bool: return _results == null
	pause_menu.visible = false
	_fighters_root = Node3D.new(); _fighters_root.name = "Fighters"; add_child(_fighters_root)
	proj_views = ProjectileViews.new(); proj_views.name = "Projectiles"; add_child(proj_views)
	if fx_enabled:
		fx = FxSystem.new(); fx.world = self; add_child(fx)
		trails = Trails.new(fx.lv); add_child(trails)
		proj_views.fx = fx
	_build_mode_ui()
	emote_wheel = EmoteWheel.new()
	emote_wheel.world = self
	emote_wheel.played.connect(func(id: String) -> void: if net_match != null: net_match.send_emote(id))   # online: everyone sees it
	$UI.add_child(emote_wheel)               # last in UI: its _input runs before the touch layer's
	if session != null:
		map_id = start_msg.get("map", map_id)
		_bind_net()
		pause_menu.online = true
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
	if fx: fx.clear()
	if trails: trails.clear()
	_hitstop = 0
	if net_match: net_match.dispose(); net_match = null
	if sim: sim.dispose()
	if _results: _results.queue_free(); _results = null
	if _shrink_mesh: _shrink_mesh.queue_free(); _shrink_mesh = null
	_banner_t = 0.0
	spectating = null; touch.spectate_mode = false
	_reward = {}
	Save.begin_match()
	map_id = id
	if build_mode:                       # the blocks are BuildHud's (meshes + solids it can change); no crates
		id = "custom"; map_id = id
		var bm := MapBuilder.custom_map(MapBuilder.saved_custom().merged({"blocks": [], "blockCols": []}, true))
		bm["noCrates"] = true
		map_node = MapBuilder.build_from(id, bm)
	else:
		map_node = MapBuilder.build(id)
	add_child(map_node)
	solids = map_node.solids
	env_node.environment = MapBuilder.make_environment(map_node.map, id)
	if fx: fx.setup_map(id, map_node.map)
	MapBuilder.setup_sun(sun, map_node.map, id)
	Tier.configure_sun(sun, map_node.shadow_area)
	sim = MatchSim.new()
	if rng_seed > 0: sim.combat.rng = CombatRng.new(rng_seed)
	sim.combat.hp_setting = hp_setting
	if session != null:
		session.prepare_sim(sim, start_msg)   # rules + dynamic arena from `start` (the host also sets its mode / K.O. limit)
	else:
		var mode := "sandbox" if build_mode else (mode_id if mode_id != "" else str(Settings.get_value("mode", "classic")))
		sim.combat.set_mode(mode if sim.combat.modes.has(mode) else "classic")   # the start weapon and crate pool follow it
		sim.dyn_choice = "off" if build_mode else (dyn_choice if dyn_choice != "" else str(Settings.get_value("dyn", "random")))
		if dyn_choice == "" and sim.combat.mode.get("chaos", false) and sim.dyn_choice == "off":
			sim.dyn_choice = "random"            # Chaos: a random floor unless the player picked a moving one
		sim.dyn_seed = Dynamics.hash32(rng_seed, 9, 0, 0) if rng_seed > 0 else randi()   # a fresh arena every match
	control = PlayerControl.new(input.state)
	var cid := player_class if player_class != "" else str(Settings.get_value("class", "wobbler"))
	if not sim.combat.classes.has(cid): cid = "wobbler"
	var bots := bot_count
	if session == null:                    # offline game mode (pickMode / setBotCfg)
		var mid := "sandbox" if build_mode else (mode_id if mode_id != "" else str(Settings.get_value("mode", "classic")))
		if not sim.combat.modes.has(mid): mid = "classic"
		sim.configure(mid, 0 if build_mode else (ko_limit if ko_limit >= 0 else int(Settings.get_value("limit", -1))))
		bots = 0 if build_mode else ModeRules.bot_count(mid, sim.combat.modes, bot_count)
	var skill := difficulty if difficulty != "" else str(Settings.get_value("difficulty", "normal"))
	if not Content.difficulties.has(skill): skill = "normal"
	sim.setup(id, map_node.map, map_node.ladders, map_node.pads, cid, control, session.sim_bots(start_msg) if session != null else bots, skill)
	solids = sim.solids                   # the live collision (moving tiles / blocks) for the camera too
	_build_dyn_views()
	if session != null:
		net_match = session.make_match(sim)   # NetMatch (guest) or HostMatch (net/host_match.gd: bots, relaying)
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
		Gfx.dress_fighter(v)             # LOW tier: blob shadow (docs/GRAPHICS.md)
		if fx: v.juice = FighterJuice.new()
		views[f] = v
	player_view = views[sim.player]
	kill_cam.stop()
	kill_cam.setup(views.values())
	if _kc_l: _kc_l.visible = false
	_build_shrink_view()
	cam.reset_view()
	feed.clear()
	acc = 0.0
	hud.bind(self)
	_setup_build()

## Build mode on: the palette (BuildHud, last in UI so it sees touches first). Off: back to the normal HUD panels.
func _setup_build() -> void:
	if build_mode:
		if build_hud == null:
			build_hud = BuildHud.new()
			build_hud.play_requested.connect(play_built)
			$UI.add_child(build_hud)
		build_hud.bind(self)
	elif build_hud != null:
		build_hud.queue_free(); build_hud = null
		for n: String in ["Score", "Radar", "Health", "Hotbar", "Feed"]:
			var c: Node = hud.get_node_or_null(n)
			if c: c.visible = true

## Build mode's Play: a Sandbox match with bots on the arena just built (saved first by BuildHud).
func play_built() -> void:
	build_mode = false
	mode_id = "sandbox"
	load_map.call_deferred("custom")

## Back from a Sandbox match to building the same arena.
func edit_arena() -> void:
	build_mode = true
	load_map.call_deferred("custom")

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
	if kill_cam.active:                      # the replay: the match waits (the pause menu pauses the replay too)
		if not paused and not kill_cam.step(dt, cam, solids): _end_kill_cam()
		return
	var finished := _results != null and session == null     # offline results panel up: finishMatch left the match
	if (not paused or net_match != null) and not finished:      # online the match keeps running behind the menu
		if not paused:
			var st := input.state
			var look := st.take_look()
			cam.add_look(look)
			if spectating == null:          # the auto-recentre follows the player's own walk, not a spectated fighter's
				var p := sim.player.phys
				cam.auto_center(dt, look, st.move(), Vector2(p.vx, p.vz), st.aiming() or st.is_held("fire") or touch.look_held(), st.is_held("sprint"))
		cam.follow(dt, cam_target(), input.state.aiming() and spectating == null, solids)
		acc += minf(dt, 0.1)
		if not paused: Save.add_play_time(dt)
		while acc >= SIM:
			sim_step(SIM)
			acc -= SIM
	present(dt if (not paused or net_match != null) else 0.0)
	_update_spectate()
	_update_hud(delta)
	if kill_cam_enabled() and not paused and not finished:
		kill_cam.record(dt)
		if kill_cam.due():
			if spectating == null and not sim.combat.rules.match_over and _results == null: start_kill_cam()
			else: kill_cam.pending = {}

func _process(delta: float) -> void:
	if session != null:
		session.poll(delta)
		if not is_inside_tree() or sim == null: return
	if auto_run:
		tick(delta)
	elif not kill_cam.active:
		cam.follow(minf(delta, 0.05), cam_target(), false, solids)
		_update_hud(delta)

## applyPose + meleeSweep + effects (also used by tests that step the sim by hand).
## Hitstop freezes the presentation only (fighters' visible pose, particles, trails, projectile views); the fighters
## still animate underneath (the gameplay points come from that) and the sim keeps its own clock.
func present(dt: float) -> void:
	var frozen := _hitstop > 0 and dt > 0.0
	for v: Fighter in views.values():
		v.visible = not v.state.left
		var k := 1.5 if v.state.big_t > 0.0 else 1.0           # Chaos giant
		if v.scale.x != k: v.scale = Vector3.ONE * k
		v.frozen = frozen
		v.present(dt)
	sim.sweep()
	_drain_events()
	_update_crates(dt)
	_update_dyn_views()
	_update_shrink_view()
	if not frozen: proj_views.update(dt)
	if fx:
		fx.watch(views, dt)
		fx.update(0.0 if frozen else dt, cam.global_position)
		trails.update(dt, self, cam.global_position, frozen)
		cam.apply_shake(dt)
	if frozen: _hitstop -= 1

## Freeze the presentation for `frames` rendered frames (2-4: a hit that lands, a K.O.).
func hitstop(frames: int) -> void:
	if fx: _hitstop = maxi(_hitstop, frames)

## A camera shake pulse (Settings "screen_shake" gates it in FollowCamera).
func add_shake(a: float) -> void:
	if fx: cam.add_shake(a)

# ============================== combat events -> visuals ==============================

func _drain_events() -> void:
	var evs: Array = sim.combat.events
	for e: Dictionary in evs:
		counts[e["type"]] = int(counts.get(e["type"], 0)) + 1
		Sfx.on_event(e, sim)
		if net_match != null: net_match.on_event(e)
		var f: FighterState = e.get("f") if e.get("f") is FighterState else null
		proj_views.on_event(e)
		if fx and not (String(e.get("type", "")) == "dmg_number" and not bool(Settings.get_value("damage_numbers", true))):
			fx.on_event(e)             # hits, damage numbers (Settings damage_numbers), K.O.s, tracers, puffs, pads, muzzle flashes
		match String(e["type"]):
			"lean", "head", "arm":
				if views.has(f): views[f].on_event(e)
			"hit":
				if e.get("attacker") == sim.player and f != sim.player:
					Save.on_hit(bool(e.get("head", false)))
					if f: kill_cam.note_hit(f)         # (hit puffs and flashes are drawn by FxSystem)
			"ko":
				_on_ko(e)
			"crate":
				_crate_view(e["crate"])
			"crate_take", "crate_gone":
				var c2: Dictionary = e["crate"]
				if _crates.has(c2["id"]):
					_crates[c2["id"]].queue_free(); _crates.erase(c2["id"])
				if e["type"] == "crate_take" and e["f"] == sim.player:
					_toast("Got " + sim.pickups.label(c2["key"]))
			"toast":
				_toast(str(e["text"]))
			"match_end":
				_reward = Save.finish_match(str(e["name"]) == "You", "", map_id, true, sim.combat.mode_id)
				_show_results(str(e["name"]))
			"match_over":
				_show_banner(str(e["title"]), str(e["sub"]), bool(e["won"]))
				if session == null:
					_reward = Save.finish_match(bool(e["won"]), str(sim.combat.mode.get("name", sim.combat.mode_id)), str(map_node.map.get("name", map_id)), false, sim.combat.mode_id)
			"match_finished":
				if session == null: _show_offline_results(bool(e["won"]), str(e["winner"].name) if e.get("winner") else "")
				elif session.is_host(): _show_results("You" if e["won"] else (str(e["winner"].name) if e.get("winner") else "?"))
			"eliminated":
				if f:
					hud.add_feed(null, f, "", false)
					_toast("You're out!" if f == sim.player else "%s is out!" % f.name)
			"relook":
				_relook(f)
			"emote":                         # another player's emote (online)
				if views.has(f): views[f].wobbler.play_emote(str(e["id"]))
			"chaos_warn":
				_show_banner(str(e["name"]).to_upper() + "!", "in %d…" % ceili(float(e["in"])), true, float(e["in"]))
			"chaos":
				if e["id"] == "giant" and f: _toast("You are a giant!" if f == sim.player else "%s is a giant!" % f.name)
				else: _toast(str(e["name"]) + "!")
			"chaos_end":
				if e["id"] != "crates": _toast("Back to normal")
	evs.clear()

func _on_ko(e: Dictionary) -> void:
	var k: FighterState = e.get("killer")
	var v: FighterState = e.get("victim")
	if v == null: return
	var melee := k != null and (k.weapon == "" or str(sim.combat.wdata(k.weapon).get("type", "")) == "melee")
	Save.on_ko(k == sim.player and v != sim.player, v == sim.player, melee)
	var txt := ""
	if k == null: txt = "%s fell off" % v.name if e.get("fall", false) else "%s was K.O.'d" % v.name
	else: txt = "%s  [%s]  %s" % [k.name, e.get("weapon", ""), v.name]
	feed.push_front([txt, FEED_TIME])
	if feed.size() > 5: feed.resize(5)
	hud.add_feed(k, v, str(e.get("weapon", "")), bool(e.get("fall", false)))
	if k == sim.player: _toast("K.O.!")
	if k == sim.player and v != sim.player and kill_cam_enabled(): kill_cam.on_ko(k, v)

# ============================== materials (crates) ==============================

## Damage-number / impact colours per body part (moved to FxSystem; kept here for older callers).
const PART_COL := FxSystem.PART_COL

func _mat(c: Color, unshaded := true) -> StandardMaterial3D:
	var key := c.to_html()
	if _mats.has(key): return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if unshaded: m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if c.a < 1.0: m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m

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
		if fx == null: continue
		if q["type"] == "drop": fx.puff(Vector3(q["x"], q["y"], q["z"]), Color.hex(0xb9a88cff), 8, 3.0)
		else: fx.puff(Vector3(q["x"], q["y"] + 0.1, q["z"]), Color.hex(0xd8cdb8ff), 6, 2.5)
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
	_team_board = TeamBoard.new()
	_team_board.name = "TeamBoard"
	_team_board.visible = false
	$UI.add_child(_team_board)
	$UI.move_child(_team_board, hud.get_index() + 1)
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
	var board := session == null and sim.combat.teams > 0 and spectating == null
	var t := sim.combat.rules.hud_text(sim.player, not board) if session == null else ""
	if _mode_l.text != t: _mode_l.text = t
	_mode_l.visible = t != ""
	_mode_l.reset_size()
	var top := float(ins[1]) + 44.0                  # under the crate toast (hud.gd keeps that at the very top)
	_team_board.visible = board
	if board:
		var rules := sim.combat.rules
		_team_board.set_data(rules.team_ko(0), rules.team_ko(1), maxi(sim.player.team, 0), rules.limit)
		_team_board.position = Vector2(vs.x / 2.0 - _team_board.size.x / 2.0, top + 4.0)
		top += _team_board.size.y + 4.0
	_mode_l.position = Vector2(vs.x / 2.0 - _mode_l.size.x / 2.0, top)
	if spectating != null:                      # spectator line: who, how many left, how to switch
		_mode_l.text = "Spectating %s  ·  %d left  ·  tap to switch" % [spectating.name, sim.combat.rules.survivors().size()]
		_mode_l.visible = true
		_mode_l.reset_size()
		_mode_l.position = Vector2(vs.x / 2.0 - _mode_l.size.x / 2.0, float(ins[1]) + 44.0)
	if _banner.visible:
		var ct := sim.combat.rules.chaos
		if not ct.is_empty() and float(ct.get("warn", 0.0)) > 0.0:   # the Chaos countdown ticks in the banner
			_banner.text = "%s!\nin %d…" % [sim.combat.rules.chaos_name(ct["id"]).to_upper(), ceili(float(ct["warn"]))]
		_banner_t -= delta
		_banner.reset_size()
		_banner.position = Vector2(vs.x / 2.0 - _banner.size.x / 2.0, vs.y * 0.3)
		if _banner_t <= 0.0: _banner.visible = false

## endMatch's "YOU WIN!" pop (shown while the match runs on for ModeRules.END_TIME).
func _show_banner(title: String, sub: String, won: bool, dur: float = ModeRules.END_TIME + 0.5) -> void:
	_banner.text = title + "\n" + sub
	_banner.add_theme_color_override("font_color", UiTheme.ACCENT if won else Color(1, 0.85, 0.8))
	_banner.visible = true
	_banner_t = dur

# ============================== spectator mode ==============================

## Where the camera looks: the spectated fighter, else the player.
func cam_target() -> Vector3:
	if spectating != null:
		var p := spectating.phys
		return Vector3(p.px, p.py, p.pz)
	return player_pos()

## Fighters the spectator can follow: still in, not the player.
func spectate_candidates() -> Array:
	var out: Array = []
	for f: FighterState in sim.combat.rules.survivors():
		if f != sim.player and not f.is_ghost: out.append(f)
	if out.is_empty() and sim.combat.rules.winner != null and sim.combat.rules.winner != sim.player: out.append(sim.combat.rules.winner)
	return out

## Follow `f` (null = stop spectating, the camera goes back to the player).
func spectate(f: FighterState) -> void:
	if f == spectating: return
	if spectating == null and f != null: input.state.clear()
	touch.spectate_mode = f != null             # no controls: the touch layer keeps only pause, taps switch
	spectating = f

## The next fighter still in (after the current one, wrapping).
func spectate_next() -> void:
	var list := spectate_candidates()
	if list.is_empty(): return
	var i := list.find(spectating)
	spectate(list[(i + 1) % list.size()])

## Each frame offline: the player is out but the match plays on -> spectate; the followed fighter went out -> next.
func _update_spectate() -> void:
	if session != null or sim == null: return
	var out := sim.player.elim
	if not out:
		if spectating != null: spectate(null)
		return
	if spectating == null or (spectating.elim and not (sim.combat.rules.match_over and spectating == sim.combat.rules.winner)):
		var list := spectate_candidates()
		if list.is_empty(): return
		spectate(list[0])
	var j := input.state.is_held("jump")          # keyboard / pad: jump switches too
	if j and not _spect_jump: spectate_next()
	_spect_jump = j

func _on_spectate_tap() -> void:
	if kill_cam.active:
		if not paused: skip_kill_cam()
		return
	if spectating != null and not paused and _results == null: spectate_next()

## Mouse: a left click switches too (touch taps come through the touch layer's spectate_tap).
func _unhandled_input(e: InputEvent) -> void:
	if kill_cam.active and not paused:          # any click / key / button skips the replay (pause still pauses)
		if (e is InputEventMouseButton or e is InputEventKey or e is InputEventJoypadButton) and e.is_pressed() and not e.is_echo() \
				and not e.is_action("pause"):
			skip_kill_cam()
			get_viewport().set_input_as_handled()
		return
	if spectating == null or paused or _results != null: return
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		spectate_next()
		get_viewport().set_input_as_handled()

# ============================== kill cam ==============================

## (Tests that step the world by hand, auto_run = false, get no replay unless they set `kill_cam_in_tests`: their
## match clocks must not stop.)
func kill_cam_enabled() -> bool:
	return session == null and (auto_run or kill_cam_in_tests) and bool(Settings.get_value("kill_cam", true)) and sim != null and sim.combat.teams == 0

func start_kill_cam() -> void:
	if not kill_cam.start(): return
	input.state.clear()
	touch.release_all()
	touch.spectate_mode = true                   # no controls; a tap anywhere but pause skips (spectate_tap)
	_kc_hud = hud.visible
	hud.visible = false
	_mode_l.visible = false                      # (the mode line comes back with the next _update_mode_ui)
	_team_board.visible = false
	if _kc_l == null:
		_kc_l = Label.new()
		_kc_l.name = "KillCam"
		_kc_l.theme_type_variation = &"HudLabel"
		_kc_l.add_theme_font_size_override("font_size", 26)
		_kc_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_kc_l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_kc_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		$UI.add_child(_kc_l)
		$UI.move_child(_kc_l, pause_menu.get_index())
	var v: FighterState = kill_cam.views[kill_cam.vi].state
	_kc_l.text = "REPLAY · you K.O.'d %s · tap to skip" % v.name
	var top := SafeArea.insets(get_viewport())[1] as float
	_kc_l.position = Vector2(get_viewport().get_visible_rect().size.x / 2.0 - _kc_l.get_minimum_size().x / 2.0, top + 14.0)
	_kc_l.size = _kc_l.get_minimum_size()
	_kc_l.visible = true

func skip_kill_cam() -> void:
	kill_cam.stop()
	_end_kill_cam()

func _end_kill_cam() -> void:
	hud.visible = _kc_hud
	touch.spectate_mode = spectating != null
	if _kc_l: _kc_l.visible = false
	input.state.clear()
	acc = 0.0
	cam.follow(0.0, cam_target(), false, solids)   # straight back to the follow camera

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
	box.add_child(ResultsRewards.make(_reward))
	var again := Button.new(); again.text = "Play again"; again.custom_minimum_size = Vector2(0, 58)
	again.theme_type_variation = &"PrimaryButton"
	again.add_theme_font_size_override("font_size", 26)
	again.pressed.connect(func() -> void: load_map.call_deferred(map_id))
	box.add_child(again)
	if sim.combat.mode_id == "sandbox":   # the arena you built: back to the build palette
		var ed := Button.new(); ed.name = "EditArena"; ed.text = "Edit arena"; ed.custom_minimum_size = Vector2(0, 54)
		ed.pressed.connect(edit_arena)
		box.add_child(ed)
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

# ============================== online (guest) ==============================

## The session's signals (also after a host migration swapped the session).
func _net_signals() -> Array:
	return [[session.match_started, _on_net_start], [session.match_message, _on_net_message], [session.votes_changed, _on_net_votes],
		[session.ended, _on_net_ended], [session.rehosted, _on_net_rehosted], [session.host_changing, _on_net_host_changing],
		[session.promoted, _on_net_promoted]]

func _bind_net() -> void:
	for sig: Array in _net_signals():
		if not (sig[0] as Signal).is_connected(sig[1]): (sig[0] as Signal).connect(sig[1])
	session.resume_provider = _resume_state

func _unbind_net() -> void:
	for sig: Array in _net_signals():
		if (sig[0] as Signal).is_connected(sig[1]): (sig[0] as Signal).disconnect(sig[1])
	session.resume_provider = Callable()

## Host migration: the running match as this client sees it (NetMatch.capture_resume).
func _resume_state() -> Dictionary:
	return net_match.capture_resume() if net_match != null and _results == null else {}

## The host left and another player hosts now: the arena stays until their `start` (or `rehosted` ends it).
func _on_net_host_changing(old_host: String) -> void:
	_show_banner("HOST CHANGED", "%s left. Waiting for the new host…" % old_host, true, 4.0)

## The relay made me the host: the HostSession carries the match on (its `start` rebuilds the arena) or, with no
## match running, the lobby takes over.
func _on_net_promoted(hs: GuestSession) -> void:
	_unbind_net()
	session = hs
	_bind_net()
	if (hs as HostSession).resuming():
		_show_banner("HOST CHANGED", "%s left. You are the host now!" % str(hs.get("migrated")), true, 4.0)
	elif not hs.started:
		_to_title(hs.status)

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
		_unbind_net()
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
	Gfx.dress_fighter(v)
	if fx: v.juice = FighterJuice.new()
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
	box.add_child(ResultsRewards.make(_reward))
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
	if paused: (pause_menu as PauseMenu).open()
	else: pause_menu.visible = false
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
