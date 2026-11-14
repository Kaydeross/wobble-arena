extends SceneTree
## Kids mode test (headless, logic only): auto-aim + auto-fire at the nearest enemy in range with line of sight, no fire
## at an enemy behind the camera or behind a wall, no auto-fire with kids mode off, the edge guard (walk + jump), half
## coins, the live Settings toggle and the HUD badge. docs/KIDS_MODE.md.
##   godot --headless --path godot --script res://tests/kids_test.gd -- --no-save   (npm run test:godot-kids)

const DT := 1.0 / 120.0
const FRAME := 1.0 / 60.0

var fails := 0
var checks := 0
var maps: Dictionary = {}

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _settings() -> Node:
	return root.get_node("Settings")

## The animation points the world writes every frame (fighters read them back); a hand-stepped logic sim has to write
## them too or the aim/LOS math reads zeros.
func _pose(f: FighterState) -> void:
	var p := f.phys
	f.head_x = p.px; f.head_y = p.py + 1.95; f.head_z = p.pz
	f.chest_x = p.px; f.chest_y = p.py + 1.22; f.chest_z = p.pz
	f.hand_x = p.px + sin(f.face_yaw) * 0.5; f.hand_y = p.py + 1.3; f.hand_z = p.pz + cos(f.face_yaw) * 0.5
	f.shoulder_x = p.px; f.shoulder_y = p.py + 1.55; f.shoulder_z = p.pz
	f.update_leg()

func _sim(bots := 0) -> MatchSim:
	if maps.is_empty(): maps = load("res://autoload/content.gd").load_json("maps")
	var m: Dictionary = maps["arena"]
	var g: Dictionary = m["geometry"]
	var sim := MatchSim.new()
	sim.combat.rng = CombatRng.new(77)
	sim.setup("arena", m, g.get("ladders", []), g.get("bouncePads", []), "wobbler", PlayerControl.new(InputState.new()), bots)
	return sim

## A scripted player with an SMG in hand, on the arena floor at (0, 0), camera facing +z.
func _duel() -> Dictionary:
	var sim := _sim()
	var p := sim.player
	sim.combat.pickup(p, "smg")
	p.phys.place(0.0, 0.01, 0.0)
	p.face_yaw = 0.0
	var pc: PlayerControl = sim.controllers[p]
	pc.cam_yaw = 0.0
	return {"sim": sim, "p": p, "pc": pc}

## A standing enemy placed at (x, z) on the floor.
func _enemy(sim: MatchSim, x: float, z: float) -> FighterState:
	var e := sim.add_fighter("wobbler")
	sim.combat.place_at(e, x, z)
	e.hp = sim.combat.max_hp(e)
	return e

func _run() -> void:
	var st := _settings()
	st.set_value("kids_mode", false)
	_off()
	_on()
	_blocked()
	_melee()
	_edge()
	_coins()
	_live()
	await _badge()
	st.set_value("kids_mode", false)
	print("KIDS %s" % ("ok (%d checks)" % checks if fails == 0 else "failed (%d checks, %d failed)" % [checks, fails]))
	quit(0 if fails == 0 else 1)

## Kids mode off: no auto-fire, no auto-aim.
func _off() -> void:
	var d := _duel()
	var sim: MatchSim = d["sim"]
	var p: FighterState = d["p"]
	var e := _enemy(sim, 0.0, 8.0)
	var hp0 := e.hp
	for i in 30:
		_pose(p); _pose(e)
		sim.step(DT)
	check(int(p.st["shots"]) == 0, "kids mode off: no auto-fire (%d shots)" % int(p.st["shots"]))
	check(is_equal_approx(e.hp, hp0), "kids mode off: the enemy is untouched")
	check(p.aim_pt.is_empty(), "kids mode off: the manual aim point is kept (none set in this test)")
	sim.dispose()

## Kids mode on: hold fire at the nearest enemy in range, aim at its chest, do not hit the one behind it.
func _on() -> void:
	_settings().set_value("kids_mode", true)
	var d := _duel()
	var sim: MatchSim = d["sim"]
	var p: FighterState = d["p"]
	var near := _enemy(sim, 2.0, 6.0)
	var far := _enemy(sim, -4.0, 14.0)
	var nhp := near.hp
	var fhp := far.hp
	for i in 60:
		_pose(p); _pose(near); _pose(far)
		sim.step(DT)
	check(int(p.st["shots"]) > 0, "kids mode: auto-fire (%d shots)" % int(p.st["shots"]))
	check(near.hp < nhp, "kids mode: the nearest enemy takes the shots (%.0f -> %.0f hp)" % [nhp, near.hp])
	check(is_equal_approx(far.hp, fhp), "kids mode: the enemy behind the first one is not hit")
	check(p.aim_pt.size() == 3, "kids mode: the assist writes the firing aim point")
	if p.aim_pt.size() == 3:
		var ch: Array = KidsAssist.chest(near)
		var dx := float(p.aim_pt[0]) - float(ch[0])
		var dz := float(p.aim_pt[2]) - float(ch[2])
		check(sqrt(dx * dx + dz * dz) <= KidsAssist.AIM_ERR + 0.2, "kids mode: aim point is on the nearest enemy's chest")
	sim.dispose()

## Kids mode on, but no valid target: an enemy behind the camera, then one behind a wall (the tall block at 9, 6).
func _blocked() -> void:
	_settings().set_value("kids_mode", true)
	var d := _duel()
	var sim: MatchSim = d["sim"]
	var p: FighterState = d["p"]
	var behind := _enemy(sim, 0.0, -8.0)
	var hp0 := behind.hp
	for i in 30:
		_pose(p); _pose(behind)
		sim.step(DT)
	check(int(p.st["shots"]) == 0, "kids mode: no fire at an enemy behind the camera (%d shots)" % int(p.st["shots"]))
	check(is_equal_approx(behind.hp, hp0), "kids mode: the enemy behind the camera is untouched")
	sim.dispose()

	var d2 := _duel()
	var sim2: MatchSim = d2["sim"]
	var p2: FighterState = d2["p"]
	var walled := _enemy(sim2, 18.0, 12.0)          # the (9, 6) block is 3 m tall: line of sight is blocked
	var whp := walled.hp
	for i in 30:
		_pose(p2); _pose(walled)
		sim2.step(DT)
	check(int(p2.st["shots"]) == 0, "kids mode: no fire through a wall (%d shots)" % int(p2.st["shots"]))
	check(is_equal_approx(walled.hp, whp), "kids mode: the enemy behind the wall is untouched")
	sim2.dispose()

## Kids mode on with a melee weapon: swing once the enemy is inside the weapon's tip.
func _melee() -> void:
	_settings().set_value("kids_mode", true)
	var sim := _sim()
	var p := sim.player
	p.phys.place(0.0, 0.01, 0.0)
	p.face_yaw = 0.0
	var pc: PlayerControl = sim.controllers[p]
	pc.cam_yaw = 0.0
	var e := _enemy(sim, 0.0, 2.0)
	for i in 3:
		_pose(p); _pose(e)
		sim.step(DT)
	check(p.swing >= 0.0 or p.kick_t >= 0.0, "kids mode: a melee swing starts with the enemy in reach")
	sim.dispose()

## The edge guard: walk at the open +x edge of the arena (floor ends at x = 20), never fall, slide but never stick,
## and walk back inward freely; jumping outward is cancelled too.
func _edge() -> void:
	_settings().set_value("kids_mode", true)
	var sim := _sim()
	var p := sim.player
	var pc: PlayerControl = sim.controllers[p]
	p.phys.place(16.0, 0.01, 0.0)
	pc.cam_yaw = PI                              # stick right = +x
	pc.input.set_move("script", Vector2.ZERO)
	for i in 4:
		_pose(p)
		sim.step(DT)
	check(p.phys.grounded and p.phys.py > -0.5, "edge guard: the player is standing on the floor")
	pc.input.set_move("script", Vector2(1, 0))   # walk towards the void
	for i in 240:
		_pose(p)
		sim.step(DT)
	check(p.phys.px > 16.3, "edge guard: the player walks towards the edge (x %.2f)" % p.phys.px)
	check(p.phys.px < 19.6 and p.phys.py > -1.0, "edge guard: never walks off (x %.2f, y %.2f)" % [p.phys.px, p.phys.py])
	pc.input.set_move("script", Vector2(-1, 0))  # walk back in: always allowed
	var x0 := p.phys.px
	for i in 60:
		_pose(p)
		sim.step(DT)
	check(p.phys.px < x0 - 2.0, "edge guard: walking inward is allowed (%.2f -> %.2f)" % [x0, p.phys.px])
	# hold jump while walking out: no hop into the void
	pc.input.set_move("script", Vector2(1, 0))
	pc.input.hold("script", "jump", true)
	var fell := false
	for i in 240:
		_pose(p)
		sim.step(DT)
		if p.phys.py < -1.0: fell = true
	pc.input.hold("script", "jump", false)
	check(not fell and p.phys.py > -1.0, "edge guard: no jump into the void (y %.2f)" % p.phys.py)
	# a corner is not a trap: push into it, then walk back out
	p.phys.place(18.0, 0.01, 18.0)
	pc.cam_yaw = PI * 0.75                      # stick right = +x, +z: into the open corner
	pc.input.set_move("script", Vector2(1, 0))
	for i in 120:
		_pose(p)
		sim.step(DT)
	var cx := p.phys.px
	var cz := p.phys.pz
	pc.input.set_move("script", Vector2(-1, 0))
	for i in 60:
		_pose(p)
		sim.step(DT)
	check((cx - p.phys.px) > 0.8 or (cz - p.phys.pz) > 0.8, "edge guard: a corner is not a trap (walks back out)")
	check(p.phys.py > -1.0, "edge guard: the corner guard keeps the player on the floor")
	sim.dispose()

## Half coins: add_coins rounds down, match rewards follow, normal mode is unchanged.
func _coins() -> void:
	var st := _settings()
	st.set_value("kids_mode", false)
	var p := SaveProfile.new()
	p.path = "user://kids_test_profile.json"
	p.persist = false
	p.coins = 0
	p.add_coins(101)
	check(p.coins == 101, "normal mode: add_coins is unchanged (%d)" % p.coins)
	check(SaveProfile.award_coins(101) == 101, "normal mode: award_coins is the full amount")
	st.set_value("kids_mode", true)
	check(SaveProfile.award_coins(101) == 50, "kids mode: an odd award rounds down (101 -> 50)")
	check(SaveProfile.award_coins(1) == 0, "kids mode: a 1-coin award pays 0")
	check(SaveProfile.award_coins(0) == 0, "kids mode: a 0-coin award stays 0")
	p.coins = 0
	p.add_coins(101)
	check(p.coins == 50, "kids mode: add_coins(101) pays 50, not 101 (%d)" % p.coins)
	p.add_coins(1)
	check(p.coins == 50, "kids mode: add_coins(1) pays 0")
	# the match payout goes through the same helper: a K.O. pays 2, a win pays 50 instead of 100
	var r := SaveProfile.new()
	r.persist = false
	r.coins = 0
	r.on_ko(true, false)
	check(r.coins == 2, "kids mode: a K.O. pays 2 (5 / 2 rounded down, %d)" % r.coins)
	var sum := r.finish_match(true, "Classic", "Arena")
	check(int(sum["coins"]) == 2 + 50, "kids mode: the results report halved coins (%d)" % int(sum["coins"]))
	check(r.coins == 2 + 50 + SaveProfile.award_coins(int(sum["streak"])), "kids mode: the wallet gets the halved coins (%d)" % r.coins)
	st.set_value("kids_mode", false)
	check(SaveProfile.award_coins(101) == 101, "turning kids mode off restores full coins at once")
	var n := SaveProfile.new()
	n.persist = false
	n.coins = 0
	n.on_ko(true, false)
	check(n.coins == 5, "normal mode: a K.O. still pays 5")
	for node: Node in [p, r, n]: node.free()      # SaveProfile is a Node: free the test profiles by hand

## The live setting toggle: switching kids mode on mid-match starts the assist, switching it off stops it.
func _live() -> void:
	var st := _settings()
	st.set_value("kids_mode", false)
	var d := _duel()
	var sim: MatchSim = d["sim"]
	var p: FighterState = d["p"]
	var e := _enemy(sim, 0.0, 8.0)
	for i in 20:
		_pose(p); _pose(e)
		sim.step(DT)
	check(int(p.st["shots"]) == 0, "live toggle: no assist before the setting is on")
	st.set_value("kids_mode", true)
	for i in 20:
		_pose(p); _pose(e)
		sim.step(DT)
	check(int(p.st["shots"]) > 0, "live toggle: turning kids mode on applies at once")
	st.set_value("kids_mode", false)
	var shots := int(p.st["shots"])
	for i in 30:
		_pose(p); _pose(e)
		sim.step(DT)
	check(int(p.st["shots"]) == shots, "live toggle: turning kids mode off stops the auto-fire at once")
	sim.dispose()

## The HUD badge (ui/hud.gd) shows "kids mode" and follows the setting.
func _badge() -> void:
	var st := _settings()
	st.set_value("kids_mode", true)
	var world: Node = load("res://world/world.tscn").instantiate()
	world.auto_run = false
	world.bot_count = 0
	world.dyn_choice = "off"
	root.add_child(world)
	await process_frame
	world.tick(FRAME)
	world.tick(FRAME)
	var hud: Control = world.hud
	var badge: Label = hud.find_child("KidsBadge", true, false)
	check(badge != null, "the HUD has the kids badge")
	if badge != null:
		check(badge.visible, "the kids badge shows in kids mode")
		st.set_value("kids_mode", false)
		world.tick(FRAME)
		world.tick(FRAME)
		check(not badge.visible, "the kids badge hides outside kids mode")
		st.set_value("kids_mode", true)
		world.tick(FRAME)
		check(badge.visible, "the kids badge follows the setting live")
	world.free()
	await process_frame
