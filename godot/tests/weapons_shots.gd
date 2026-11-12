extends SceneTree
## Weapons batch 1 (rocket, meteor, grenade + cluster launchers, bow, net gun, flamethrower) in a real offline match.
##   godot --headless --path godot --script res://tests/weapons_shots.gd -- --no-save --smoke
##       bots armed with every batch-1 weapon fight for 40 s; checks they fire, things blow up, nets land and burn,
##       and nothing errors (prints WSMOKE ... ok/FAILED).
##   godot --path godot --resolution 1280x720 --script res://tests/weapons_shots.gd -- --no-save --shot rocket|net --out FILE.png
##       renders an in-match screenshot (needs a real renderer: opens a window for a moment).

const FRAME := 1.0 / 60.0
const BATCH := ["rocket", "meteor", "glauncher", "cluster", "bow", "net", "flame"]

var mode := "smoke"
var out := "shot.png"
var world: Node
var i := 0
var hold_until := -1
var saved_at := -1

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for k in a.size():
		if a[k] == "--shot" and k + 1 < a.size(): mode = a[k + 1]
		elif a[k] == "--out" and k + 1 < a.size(): out = a[k + 1]
	process_frame.connect(_start, CONNECT_ONE_SHOT)

func _start() -> void:
	var settings := root.get_node("Settings")
	settings.set_value("touch_mode", "off")
	settings.set_value("show_fps", false)
	settings.set_value("dyn", "off")
	world = load("res://world/world.tscn").instantiate()
	world.map_id = "arena"
	world.auto_run = false
	world.bot_count = 6 if mode == "smoke" else 3
	world.player_class = "wobbler"
	world.rng_seed = 4242
	world.dyn_choice = "off"
	root.add_child(world)
	world.touch.visible = false
	process_frame.connect(_smoke if mode == "smoke" else _shot)

func _nearest(me: FighterState) -> FighterState:
	var best: FighterState = null
	var bd := 1e9
	for f: FighterState in world.sim.fighters:
		if f == me or f.dead: continue
		var d := Vector2(f.phys.px - me.phys.px, f.phys.pz - me.phys.pz).length()
		if d < bd: bd = d; best = f
	return best

func _arm_bots() -> void:
	var k := 0
	for f: FighterState in world.sim.fighters:
		if f.is_player or f.dead: continue
		if f.slot < 0 or world.sim.combat.wdata(f.weapon).get("type", "") == "melee":
			world.sim.combat.pickup(f, BATCH[k % BATCH.size()])
		k += 1

# ============================== smoke ==============================

func _smoke() -> void:
	var sim: MatchSim = world.sim
	if i % 120 == 0: _arm_bots()               # re-arm (weapons run dry, bots die and respawn)
	var p := sim.player
	if i % 240 == 0 and not p.dead: sim.combat.pickup(p, BATCH[(i / 240) % BATCH.size()])
	var tg := _nearest(p)
	var fire := false
	if tg:
		var d := Vector2(tg.phys.px - p.phys.px, tg.phys.pz - p.phys.pz)
		world.cam.yaw = lerp_angle(world.cam.yaw, atan2(d.x, d.y), 0.2)
		world.cam.pitch = -0.1
		fire = (i % 90) < 60
	var st: InputState = world.input.state
	st.hold("script", "fire", fire)
	world.tick(FRAME)
	i += 1
	if i < 60 * 40: return
	process_frame.disconnect(_smoke)
	var c: Dictionary = world.counts
	var kinds := {}
	for e: String in ["explode", "net_land", "flame", "projectile", "projectile_end", "net_end"]: kinds[e] = int(c.get(e, 0))
	var fails := []
	if kinds["explode"] < 3: fails.append("explosions")
	if kinds["net_land"] < 1: fails.append("nets landed")
	if kinds["flame"] < 30: fails.append("flames")
	if kinds["projectile"] < 10: fails.append("projectiles")
	var w: Weapons = sim.combat.weapons
	var live := w.rockets.size() + w.grenades.size() + w.arrows.size() + w.nets.size() + w.projectiles.size()
	var views: int = world.proj_views._views.size()
	if views != live: fails.append("views %d != live projectiles %d" % [views, live])
	print("WSMOKE counts=%s live=%d views=%d fx=%d %s" % [str(kinds), live, views, world.proj_views._fx.size(), "ok" if fails.is_empty() else "FAILED " + str(fails)])
	quit(0 if fails.is_empty() else 1)

# ============================== screenshots ==============================

func _shot() -> void:
	var sim: MatchSim = world.sim
	var p := sim.player
	var st: InputState = world.input.state
	if i == 2:
		var k := 0
		for f: FighterState in sim.fighters:           # bots: bow, grenade launcher, rocket
			if not f.is_player: sim.combat.pickup(f, ["bow", "glauncher", "rocket"][k % 3]); k += 1
		sim.combat.pickup(p, "net" if mode == "net" else "rocket")
	var tg := _nearest(p)
	var fire := false
	if tg:
		var d := Vector2(tg.phys.px - p.phys.px, tg.phys.pz - p.phys.pz)
		world.cam.yaw = lerp_angle(world.cam.yaw, atan2(d.x, d.y) + 0.12, 0.15)
		world.cam.pitch = -0.16
		var go := Vector2(0, 0.8) if d.length() > 11.0 else Vector2.ZERO
		st.set_move("script", go)
		if mode == "rocket":
			fire = i > 150 and d.length() < 18.0 and int(world.counts.get("explode", 0)) == 0
		else:
			if i > 150 and int(world.counts.get("net_land", 0)) == 0: fire = d.length() < 14.0
			elif int(world.counts.get("net_land", 0)) > 0:
				if p.weapon != "flame": sim.combat.pickup(p, "flame"); p.cool = 0.0; hold_until = i + 50
				fire = i < hold_until
				world.cam.pitch = -0.38          # look down on the net from higher up
	st.hold("script", "fire", fire)
	world.tick(FRAME)
	i += 1
	var done := false
	if mode == "rocket" and int(world.counts.get("explode", 0)) > 0:
		if saved_at < 0: saved_at = i + 5
		done = i >= saved_at
	elif mode == "net" and hold_until > 0 and i >= hold_until - 4:
		done = true
	if done or i > 1500:
		process_frame.disconnect(_shot)
		_save()

func _save() -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("SHOT ", out, " ", img.get_size(), " frame ", i)
	quit(0)
