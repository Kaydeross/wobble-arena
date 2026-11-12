extends SceneTree
## Renders UI screenshots for visual review (needs a real renderer, opens a window):
##   godot --path godot --resolution 852x393 --script res://tests/ui_shots.gd -- --no-save --shot match --out FILE.png
## Shots: title (scenes/main.tscn), title-online (its Play online panel), title-settings (the gear sheet), wizard-mode /
## wizard-arena / wizard-players / wizard-character / wizard-start (the five offline setup wizard pages in order,
## ui/setup_wizard.gd; the character page waits for its 3D renders), match (offline world with the HUD), touch (same with the touch layer forced on and
## a few fingers down), touch-lefty (the same in left-handed mode), fps (match with the FPS overlay on), pause (the pause menu), title-construction (the title with the
## wizard on Construction), construction (a Construction match on Site Yard, mid hammer swing), newmodes-mode (the game
## type page scrolled to the Godot-only modes, Chaos picked), newmodes-players (Players page in Team Deathmatch),
## teams (Team Deathmatch with the team scoreboard), locker-skin / locker-hat / locker-color / locker-emote /
## locker-class (the Locker tabs, ui/locker.gd, with 1500 coins and a card picked), shop (the Shop, an outfit tried on),
## shop-confirm (its Buy card), emote-wheel (a match with the emote wheel open while the player dances), results (the
## end-of-match panel with the coins and unlock progress), spectate (Sudden Death after the player fell off: spectator camera + line, touch layer on),
## account-guest / account-signed (the Account sheet from the title chip; signed in, saved to the cloud 2 min ago),
## killcam (a fast K.O. by the player, mid replay in slow-mo). Used by tools/shoot-godot-ui.sh.
## modes2-mode (the game type page scrolled to the end, Pillars picked), modes2-pillars (a Pillars match across the ring
## after the first weapon handout), modes2-lowg (Moon Drift on Crater Dome, the player high in the air),
## modes2-practice (the Practice Range: the player with a rack AK shooting down the range at the dummies).

const FRAME := 1.0 / 60.0

var shot := "title"
var out := "shot.png"
var frames := 0
var world: Node
var i := 0

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for k in a.size():
		if a[k] == "--shot" and k + 1 < a.size(): shot = a[k + 1]
		elif a[k] == "--out" and k + 1 < a.size(): out = a[k + 1]
	process_frame.connect(_start, CONNECT_ONE_SHOT)

func _settings() -> Node:
	return root.get_node("Settings")

func _start() -> void:
	if shot.begins_with("locker") or shot.begins_with("shop"):
		var sv: Node = root.get_node("Save")
		sv.add_coins(1000)
		for id in ["griddy", "dab", "flip"]: sv.buy("emote", id)
		if shot.begins_with("shop"): sv.add_coins(700)
		var m: Node = load("res://scenes/main.tscn").instantiate()
		root.add_child(m)
		var shop := shot.begins_with("shop")
		var tab: String = "skin" if shop else shot.substr(7)
		m.open_locker(shop, tab)
		var pick: String = {"skin": "cowboy", "hat": "crown", "color": "", "emote": "griddy", "class": "bruiser"}.get(tab, "")
		if shop: pick = "pirate"
		if pick != "" and m.locker.cards.has(pick): m.locker._select_card(pick)
		if shot == "shop-confirm": m.locker.act()
		frames = 150
		process_frame.connect(_wait)
		return
	if shot.begins_with("account"):
		var m: Node = load("res://scenes/main.tscn").instantiate()
		root.add_child(m)
		if shot == "account-signed":
			var c: Node = root.get_node("Save").cloud
			c.setv("token", "ab".repeat(32)); c.setv("user", "WobbleQueen"); c.setv("email", "queen@example.com")
			c.setv("cloud_t", int((Time.get_unix_time_from_system() - 130.0) * 1000.0))
			m._refresh_login()
		m.open_account()
		frames = 40
		process_frame.connect(_wait)
		return
	if shot == "title-construction": _settings().set_value("mode", "construction")
	if shot == "modes2-mode": shot = "newmodes-mode2"
	if shot.begins_with("title") or shot.begins_with("wizard") or shot.begins_with("newmodes"):
		if shot.begins_with("wizard") or shot.begins_with("newmodes"):   # a fixed setup so the shots are comparable
			var md: String = {"newmodes-mode": "chaos", "newmodes-players": "tdm", "newmodes-mode2": "pillars"}.get(shot, "classic")
			for kv in [["offline_map", "pillars" if md == "pillars" else "arena"], ["mode", md], ["dyn", "random"], ["bots", 5], ["difficulty", "normal"], ["class", "wobbler"]]:
				_settings().set_value(kv[0], kv[1])
		var m: Node = load("res://scenes/main.tscn").instantiate()
		root.add_child(m)
		if shot == "title-online":
			m.show_tab(true)
			m.get_node("Safe/Col/Body/Online/Box/Roster").text = "In the room: Alice, Bob"
		elif shot == "title-settings":
			m.show_settings(true)
		elif shot.begins_with("wizard"):
			m.open_wizard(["wizard-mode", "wizard-arena", "wizard-players", "wizard-character", "wizard-start"].find(shot))
		elif shot.begins_with("newmodes"):
			m.open_wizard(2 if shot == "newmodes-players" else 0)
			if shot != "newmodes-players": _scroll_wizard = m.wizard
		frames = 40
		process_frame.connect(_wait)
		return
	var touch_shot := shot == "touch" or shot == "touch-lefty" or shot == "spectate" or shot == "emote-wheel"
	_settings().set_value("touch_mode", "on" if touch_shot else "off")
	_settings().set_value("touch_lefty", shot == "touch-lefty")
	_settings().set_value("show_fps", shot == "fps")
	world = load("res://world/world.tscn").instantiate()
	world.map_id = "siteyard" if shot == "construction" else "arena"
	if shot == "construction":
		world.mode_id = "construction"
		world.dyn_choice = "off"
	if shot == "spectate":
		world.mode_id = "sudden"
		world.dyn_choice = "off"
	if shot == "teams":                                  # Team Deathmatch: the TeamBoard (colour chips, YOU tag)
		world.mode_id = "tdm"
		world.dyn_choice = "off"
	if shot.begins_with("modes2-"):                      # Pillars / Moon Drift / Practice Range
		var mm: Array = {"modes2-pillars": ["pillars", "pillars"], "modes2-lowg": ["lowg", "craterdome"], "modes2-practice": ["practice", "practice"]}[shot]
		world.mode_id = mm[0]; world.map_id = mm[1]
		world.dyn_choice = "off"
	world.auto_run = false
	world.kill_cam_in_tests = shot == "killcam"
	world.bot_count = 3
	world.player_class = "wobbler"
	world.rng_seed = 777
	world.hp_setting = 200.0
	root.add_child(world)
	if not touch_shot:
		world.touch.visible = false
	process_frame.connect(_frame)

var _scroll_wizard: Node = null

func _wait() -> void:
	if _scroll_wizard != null and frames == 20:       # scroll the game type grid to its end (the new modes)
		var sc: ScrollContainer = _scroll_wizard.scroll_of(0)
		sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)
	frames -= 1
	if frames == 0:
		process_frame.disconnect(_wait)
		_save()

func _nearest(me: FighterState) -> FighterState:
	var best: FighterState = null
	var bd := 1e9
	for f: FighterState in world.sim.fighters:
		if f == me or f.dead: continue
		var d := Vector2(f.phys.px - me.phys.px, f.phys.pz - me.phys.pz).length()
		if d < bd: bd = d; best = f
	return best

func _touch(idx: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx; e.position = pos; e.pressed = pressed
	world.touch._input(e)

func _frame() -> void:
	var sim: MatchSim = world.sim
	var p := sim.player
	var st: InputState = world.input.state
	if shot == "construction":
		_hammer_frame(sim, p, st)
		return
	if shot == "spectate":
		_spectate_frame(sim, p)
		return
<<<<<<< HEAD
	if shot == "killcam" and i == 100:
		for f: FighterState in sim.fighters:
			if f != p: f.hp = 1.0                       # the next hit is a fast K.O.
	if shot == "killcam" and world.kill_cam.active:
		world.tick(FRAME)
		i += 1
		if world.kill_cam.shown > 1.5:
			process_frame.disconnect(_frame)
			_save()
=======
	if shot.begins_with("modes2-"):
		_modes2_frame(sim, p, st)
>>>>>>> origin/main
		return
	if i == 2:
		sim.combat.pickup(p, "katana")
		sim.combat.pickup(p, "smg")      # the last pickup is the active slot
		if not shot.begins_with("touch"): world.hud.last_touch = false
	var go := Vector2.ZERO
	var fire := false
	var tg := _nearest(p)
	if tg:
		var d := Vector2(tg.phys.px - p.phys.px, tg.phys.pz - p.phys.pz)
		world.cam.yaw = lerp_angle(world.cam.yaw, atan2(d.x, d.y) + 0.25, 0.1)
		world.cam.pitch = -0.12
		go = Vector2(0, 0.7) if d.length() > 9.0 else Vector2.ZERO
		fire = d.length() < 16.0 and i > 120 and i < 330
	st.set_move("script", go)
	st.hold("script", "fire", fire)
	world.tick(FRAME)
	i += 1
	if i == 200:
		world._toast("K.O.!")
	if i == 330 and not p.dead:
		p.hp = sim.combat.max_hp(p) * 0.22   # show the damage trail and the low-health pulse
	if shot.begins_with("touch") and i == 340:
		var vs: Vector2 = world.touch.get_viewport_rect().size
		var sx := vs.x * (0.84 if shot == "touch-lefty" else 0.16)
		_touch(7, Vector2(sx, vs.y * 0.62), true)
		var e := InputEventScreenDrag.new()
		e.index = 7; e.position = Vector2(sx + 40, vs.y * 0.62 - 50)
		world.touch._input(e)
		_touch(8, world.touch.button_rect(world.touch.button("fire"))[0], true)
	if shot == "emote-wheel" and i == 300:
		var sv: Node = root.get_node("Save")
		sv.add_coins(3000)
		for id in ["griddy", "dab", "flip", "floss", "robot", "galaxy"]: sv.buy("emote", id)
		st.set_move("script", Vector2.ZERO); st.hold("script", "fire", false)
		world.player_view.wobbler.play_emote("griddy")
		world.emote_wheel.open_wheel(true)
	if shot == "emote-wheel" and i > 300:
		st.set_move("script", Vector2.ZERO); st.hold("script", "fire", false)
	if shot == "results" and i == 340:
		var sv: Node = root.get_node("Save")
		sv.on_ko(true, false); sv.on_ko(true, false)
		world._reward = sv.finish_match(true, "Classic", "Arena")
		world._show_offline_results(true, "")
	if shot == "pause" and i == 345:
		world._toggle_pause()
	if i == 352 and shot != "killcam" or i == 900:
		process_frame.disconnect(_frame)
		_save()

## Construction: walk up to the nearest bot with the Claw Hammer and save mid swing (or after 12 s).
func _hammer_frame(sim: MatchSim, p: FighterState, st: InputState) -> void:
	if i == 2: world.hud.last_touch = false
	var tg := _nearest(p)
	var go := Vector2.ZERO
	var fire := false
	var dist := 99.0
	if tg:
		var d := Vector2(tg.phys.px - p.phys.px, tg.phys.pz - p.phys.pz)
		dist = d.length()
		world.cam.yaw = lerp_angle(world.cam.yaw, atan2(d.x, d.y) + 0.35, 0.1)
		world.cam.pitch = -0.16
		go = Vector2(0, 1) if dist > 1.7 else Vector2.ZERO
		fire = dist < 2.6 and i > 240
	st.set_move("script", go)
	st.hold("script", "fire", fire)
	world.tick(FRAME)
	i += 1
	if (i > 260 and p.weapon == "hammer" and p.swing > 0.35 and p.swing < 0.6 and dist < 3.0) or i == 720:
		process_frame.disconnect(_frame)
		_save()

## Sudden Death: the player is pushed off the edge at 2 s, the camera spectates a survivor; save 4 s later.
func _spectate_frame(sim: MatchSim, p: FighterState) -> void:
	if i == 120 and not p.elim:
		p.phys.place(60.0, -30.0, 0.0); p.last_attacker = null
	world.tick(FRAME)
	i += 1
	if world.spectating != null:
		var sp: FighterState = world.spectating
		var d := Vector2(sp.phys.px, sp.phys.pz)
		world.cam.yaw = lerp_angle(world.cam.yaw, atan2(-d.x, -d.y) + PI, 0.05)
		world.cam.pitch = -0.2
	if i == 400 or (i > 140 and sim.combat.rules.match_over):
		process_frame.disconnect(_frame)
		_save()

## The new modes: Pillars looks across the ring at the next pillars, Moon Drift jumps and saves high in the air, the
## Practice Range takes an AK and shoots down the range.
func _modes2_frame(sim: MatchSim, p: FighterState, st: InputState) -> void:
	if i == 2: world.hud.last_touch = false
	var go := Vector2.ZERO
	var fire := false
	var done := false
	match shot:
		"modes2-pillars":
			world.cam.yaw = lerp_angle(world.cam.yaw, atan2(-p.phys.px, -p.phys.pz) + 0.55, 0.1)
			world.cam.pitch = -0.08
			done = i == 330
		"modes2-lowg":
			if i == 2: sim.combat.pickup(p, "shotgun")
			var tg := _nearest(p)
			if tg:
				var d := Vector2(tg.phys.px - p.phys.px, tg.phys.pz - p.phys.pz)
				world.cam.yaw = lerp_angle(world.cam.yaw, atan2(d.x, d.y) + 0.3, 0.1)
				go = Vector2(0, 0.6) if d.length() > 8.0 else Vector2.ZERO
			world.cam.pitch = -0.25
			st.hold("script", "jump", i > 150 and i < 160)
			done = (i > 170 and p.phys.py > 6.0 and p.phys.vy < 0.5) or i == 600
		"modes2-practice":
			if i == 2: sim.combat.pickup(p, "ak")
			world.cam.yaw = lerp_angle(world.cam.yaw, PI + 0.12, 0.2)
			world.cam.pitch = -0.06
			fire = i > 200 and i < 300
			done = i == 290
	st.set_move("script", go)
	st.hold("script", "fire", fire)
	world.tick(FRAME)
	i += 1
	if done:
		process_frame.disconnect(_frame)
		_save()

func _save() -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("SHOT ", out, " ", img.get_size())
	quit(0)
