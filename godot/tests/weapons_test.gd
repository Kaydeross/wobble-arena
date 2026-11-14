extends SceneTree
## Weapons and aim modes (docs/AIM.md), headless logic:
##   1. the spatula is a real slot: the swap key cycles through it and back with a gun in hand, pressing the slot key
##      of the weapon you hold returns to it (web parity), the touch Spatula tile equips it (TouchControls presses
##      "spatula_equip"; tapping it again returns to the previous weapon), it swings and hurts as a normal melee
##      weapon, a picked-up weapon still fills its slot while `spatula_lock` keeps the spatula in the hand, and a
##      dropped/broken weapon falls back to it
##   2. aim modes at the PlayerControl level: Normal pulls the crosshair point toward a near enemy (and only then);
##      Advanced is manual aim; neither an online match nor an Advanced player is assisted
##   3. Settings: `aim_mode` defaults to normal, the old hold|toggle value migrates to `aim_button`, saves live
##   4. the HUD's Advanced badge follows the setting in a match
##   godot --headless --path godot --script res://tests/weapons_test.gd -- --no-save

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
	if not OS.get_cmdline_user_args().has("--no-save"):
		print("WEAPONS needs --no-save (it changes Settings)")
		quit(1)
		return
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _settings() -> Node:
	return root.get_node("Settings")

## The animation points the world writes every frame (fighters read them back); a hand-stepped logic sim writes them too.
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
	sim.combat.rng = CombatRng.new(11)
	sim.setup("arena", m, g.get("ladders", []), g.get("bouncePads", []), "wobbler", PlayerControl.new(InputState.new()), bots)
	return sim

## The scripted player on the arena floor at (0, 0), camera facing +z, no weapon picked up yet.
func _duel() -> Dictionary:
	var sim := _sim()
	var p := sim.player
	sim.combat.clear_inventory(p)
	p.phys.place(0.0, 0.01, 0.0)
	p.face_yaw = 0.0
	var pc: PlayerControl = sim.controllers[p]
	pc.cam_yaw = 0.0
	return {"sim": sim, "p": p, "pc": pc}

func _enemy(sim: MatchSim, x: float, z: float) -> FighterState:
	var e := sim.add_fighter("wobbler")
	sim.combat.place_at(e, x, z)
	e.hp = sim.combat.max_hp(e)
	return e

## Cos of the angle between the shot direction (shoulder -> `pt`) and the shoulder -> enemy chest direction.
func _aim_dot(p: FighterState, e: FighterState, pt: Array) -> float:
	if pt.size() != 3: return -2.0
	var sd := Combat.norm3(pt[0] - p.shoulder_x, pt[1] - p.shoulder_y, pt[2] - p.shoulder_z)
	var td := Combat.norm3(e.chest_x - p.shoulder_x, e.chest_y - p.shoulder_y, e.chest_z - p.shoulder_z)
	return sd[0] * td[0] + sd[1] * td[1] + sd[2] * td[2]

func _same3(a: Array, b: Array) -> bool:
	if a.size() != 3 or b.size() != 3: return false
	for i in 3:
		if not is_equal_approx(float(a[i]), float(b[i])): return false
	return true

func _run() -> void:
	_spatula()
	_touch()
	_assist()
	_settings_checks()
	await _badge()
	_settings().set_value("aim_mode", "normal")
	print("WEAPONS %s" % ("ok (%d checks)" % checks if fails == 0 else "failed (%d checks, %d failed)" % [checks, fails]))
	quit(0 if fails == 0 else 1)

# ============================== 1. the spatula as a real slot ==============================

func _spatula() -> void:
	var d := _duel()
	var sim: MatchSim = d["sim"]
	var p: FighterState = d["p"]
	var pc: PlayerControl = d["pc"]
	var c := sim.combat
	c.pickup(p, "ak")
	check(p.slot == 0, "spatula: a gun goes into its slot and the hand")
	pc.input.press("swap"); pc.think(p, sim, DT)
	check(p.slot == -1 and p.weapon == "spatula" and p.spatula_lock, "spatula: the swap key reaches it with a gun in hand")
	pc.input.press("swap"); pc.think(p, sim, DT)
	check(p.slot == 0 and p.weapon == "ak" and not p.spatula_lock, "spatula: swap leaves it again")
	pc.input.press("slot1"); pc.think(p, sim, DT)
	check(p.slot == -1 and p.weapon == "spatula", "spatula: the slot key of the weapon in hand returns to it")
	pc.input.press("slot1"); pc.think(p, sim, DT)
	check(p.slot == 0 and p.weapon == "ak", "spatula: the slot key enters the gun again")
	pc.input.press("spatula_equip"); pc.think(p, sim, DT)
	check(p.slot == -1 and p.weapon == "spatula", "spatula: the touch Spatula tile equips it")
	# it swings and hurts as any other real melee weapon (not only as the quick melee tap)
	var e := _enemy(sim, 0.0, 1.1)
	_pose(p); _pose(e)
	p.cool = 0.0; p.swing = -1.0
	check(c.try_melee(p, 0.0) and p.swing >= 0.0 and p.weapon == "spatula", "spatula: a swing starts after switching")
	p.swing = 0.5
	p.hand_x = 0.0; p.hand_y = 1.3; p.hand_z = 0.0
	p.arm_x = 0.0; p.arm_y = 0.0; p.arm_z = 1.0
	p.assist_on = false
	for i in FighterState.BAT_N * 3: p.bat_prev[i] = 50.0
	p.bat_valid = true
	var hp0 := e.hp
	c.melee_sweep(p)
	check(e.hp < hp0, "spatula: the swing hurts the enemy in front (%.1f -> %.1f)" % [hp0, e.hp])
	# a pickup fills its slot while the spatula stays chosen; entering that slot unlocks the spatula
	c.clear_inventory(p)
	c.pickup(p, "ak")
	pc.input.press("spatula_equip"); pc.think(p, sim, DT)
	c.pickup(p, "revolver")
	check(p.slot == -1 and p.weapon == "spatula", "spatula: a pickup does not pull it out of the hand")
	var ri := -1
	for i in 3:
		if p.slots[i] != null and p.slots[i]["key"] == "revolver": ri = i
	check(ri >= 0, "spatula: the picked-up weapon is in a slot")
	c.equip_slot(p, ri)
	check(p.weapon == "revolver" and not p.spatula_lock, "spatula: entering the picked-up slot unlocks it")
	# a weapon that runs out / breaks falls back to the spatula
	c.clear_inventory(p)
	c.pickup(p, "ak")
	p.slots[p.slot]["ammo"] = 0
	c.drop_slot(p)
	check(p.slot == -1 and p.weapon == "spatula" and not p.spatula_lock, "spatula: a dropped/broken weapon falls back to it")
	sim.dispose()

# ============================== the touch hotbar tile (logic only) ==============================

## A stand-in for ui/hud_hotbar.gd: TouchControls reads `slots` [{empty, active}] and slot_rect().
class FakeHotbar extends Control:
	var slots: Array = []
	func slot_rect(_i: int) -> Rect2: return Rect2()

func _touch() -> void:
	# loaded at runtime: the test script itself is compiled before the autoload singletons exist, and TouchControls
	# reads Settings at compile time.
	var tc: Variant = load("res://input/touch_controls.gd").new()
	tc.state = InputState.new()
	var hb := FakeHotbar.new()
	tc.hotbar = hb
	hb.slots = [{"empty": false, "active": true}, {"empty": true, "active": false}, {"empty": true, "active": false},
		{"empty": false, "active": false}]
	tc._hotbar_tap(3)
	check(tc.state.consume("spatula_equip"), "touch: the Spatula tile equips the spatula with a gun in hand")
	hb.slots = [{"empty": false, "active": false}, {"empty": true, "active": false}, {"empty": true, "active": false},
		{"empty": false, "active": true}]
	tc._hotbar_tap(3)
	check(tc.state.consume("slot1"), "touch: tapping it again returns to the weapon it replaced")
	tc.state.clear()
	hb.slots = [{"empty": true, "active": false}, {"empty": true, "active": false}, {"empty": true, "active": false},
		{"empty": false, "active": true}]
	tc._hotbar_tap(3)
	check(not tc.state.peek("spatula_equip") and not tc.state.peek("slot1"), "touch: with no previous weapon the tile does nothing")
	tc.free()
	hb.free()

# ============================== 2. aim modes at the PlayerControl level ==============================

func _assist() -> void:
	var st := _settings()
	st.set_value("aim_mode", "normal")
	var d := _duel()
	var sim: MatchSim = d["sim"]
	var p: FighterState = d["p"]
	var pc: PlayerControl = d["pc"]
	var e := _enemy(sim, 0.0, 10.0)
	var raw := [0.70, 1.22, 10.0]                 # crosshair ~4 deg off the enemy's chest
	pc.aim_point = raw
	pc.input.hold("script", "fire", true)
	_pose(p); _pose(e)
	pc.think(p, sim, DT)
	var got := p.aim_pt.duplicate()
	check(got.size() == 3, "aim assist: Normal writes the firing aim point")
	if got.size() == 3:
		var pulled := _aim_dot(p, e, got)
		var straight := _aim_dot(p, e, raw)
		check(pulled > straight and pulled > 0.999, "aim assist: Normal pulls the crosshair toward the near enemy (%.5f -> %.5f)" % [straight, pulled])
	# Advanced: no assist: the point stays exactly where the player aimed
	st.set_value("aim_mode", "advanced")
	pc.aim_point = raw
	pc.think(p, sim, DT)
	check(_same3(p.aim_pt, raw), "aim assist: Advanced is manual aim, the crosshair point is untouched")
	check(sim.combat.aim_mode == "advanced" and sim.combat.aim_advanced(), "aim mode: the player's step applies the Settings row live")
	check(not Combat.new().aim_advanced(), "aim mode: a bare Combat stays Normal (the JS parity fixtures are deterministic)")
	# Normal again, but the target is 30 deg off the crosshair: no pull
	st.set_value("aim_mode", "normal")
	var ahead := [0.0, 1.22, 10.0]
	e.phys.place(5.77, 0.01, 10.0)
	pc.aim_point = ahead
	_pose(p); _pose(e)
	pc.think(p, sim, DT)
	check(sim.combat.aim_mode == "normal", "aim mode: switching back to Normal applies live too")
	check(_same3(p.aim_pt, ahead), "aim assist: a target far from the crosshair is not pulled")
	# online (a real match): no client-side assist
	sim.combat.net_started = true
	e.phys.place(0.0, 0.01, 10.0)
	pc.aim_point = raw
	_pose(p); _pose(e)
	pc.think(p, sim, DT)
	check(_same3(p.aim_pt, raw), "aim assist: online keeps manual aim (no client-side help)")
	sim.combat.net_started = false
	pc.input.hold("script", "fire", false)
	sim.dispose()
	st.set_value("aim_mode", "normal")

# ============================== 3. settings ==============================

func _settings_checks() -> void:
	var st := _settings()
	check(str(st.DEFAULTS["aim_mode"]) == "normal", "settings: aim_mode defaults to normal")
	check(str(st.DEFAULTS["aim_button"]) == "hold", "settings: the aim button preference is aim_button")
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "aim_mode", "toggle")
	check(bool(st.migrate_aim_button(cfg)), "settings: an old hold/toggle aim_mode migrates")
	check(str(cfg.get_value("settings", "aim_button")) == "toggle" and not cfg.has_section_key("settings", "aim_mode"),
		"settings: the old value moves to aim_button")
	var cfg2 := ConfigFile.new()
	cfg2.set_value("settings", "aim_mode", "normal")
	check(not bool(st.migrate_aim_button(cfg2)) and str(cfg2.get_value("settings", "aim_mode")) == "normal",
		"settings: a Normal/Advanced value is left alone")
	st.set_value("aim_mode", "advanced")
	check(str(st.get_value("aim_mode")) == "advanced", "settings: aim_mode saves at once")
	st.set_value("aim_mode", "normal")

# ============================== 4. the HUD badge ==============================

func _badge() -> void:
	var st := _settings()
	st.set_value("aim_mode", "advanced")
	var world: Node = load("res://world/world.tscn").instantiate()
	world.auto_run = false
	world.bot_count = 0
	world.dyn_choice = "off"
	root.add_child(world)
	await process_frame
	world.tick(FRAME); world.tick(FRAME)
	var hotbar: Control = world.hud.find_child("Hotbar", true, false)
	check(hotbar != null and hotbar.get("slots").size() == 4, "HUD: four hotbar slots")
	if hotbar != null:
		var sp_named := false
		var sp_active := false
		for i in 4:
			var sl: Dictionary = hotbar.get("slots")[i]
			if str(sl["name"]).to_lower().contains("spatula"):
				sp_named = true; sp_active = bool(sl["active"])
		check(sp_named, "HUD: the spatula is one of the slots")
		check(sp_active, "HUD: the spatula slot is highlighted when it is in hand")
	var badge: Label = world.hud.find_child("AimBadge", true, false)
	check(badge != null, "HUD: the Advanced aim badge exists")
	if badge != null:
		check(badge.visible and badge.text.contains("+25%"), "HUD: the badge shows +25%% offline (%s)" % badge.text)
		st.set_value("aim_mode", "normal")
		world.tick(FRAME); world.tick(FRAME)
		check(not badge.visible, "HUD: the badge hides in Normal")
	world.free()
	await process_frame
