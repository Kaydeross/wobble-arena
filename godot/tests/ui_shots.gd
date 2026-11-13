extends SceneTree
## Renders UI screenshots for visual review (needs a real renderer, opens a window):
##   godot --path godot --resolution 852x393 --script res://tests/ui_shots.gd -- --no-save --shot match --out FILE.png
## Shots: title (scenes/main.tscn), title-online (its Play online panel), title-settings (the gear sheet), wizard-mode / wizard-team (a Team section pick) /
## wizard-arena / wizard-players / wizard-character / wizard-start (the five offline setup wizard pages in order,
## ui/setup_wizard.gd; the character page waits for its 3D renders), match (offline world with the HUD), touch (same with the touch layer forced on and
## a few fingers down), touch-lefty (the same in left-handed mode), fps (match with the FPS overlay on), pause (the pause menu), title-construction (the title with the
## Construction banner, same as title), dlc-hub-locked / dlc-hub-poor / dlc-hub (the Construction hub: locked with enough coins, locked
## and short of coins, unlocked) / dlc-prematch (the Classic pre-match card) / dlc-code (the code sheet), construction (a Construction match on Site Yard, mid hammer swing), newmodes-mode (the game
## type page scrolled to the Godot-only modes, Chaos picked), newmodes-players (Players page in Team Deathmatch),
## teams (Team Deathmatch with the team scoreboard), locker-skin / locker-hat / locker-color / locker-emote /
## locker-class (the Walldrobe tabs, ui/locker.gd: a few outfits, emotes and a class bought first, a card picked; --pick
## KEY picks another card), shop (the Shop, an outfit tried on), shop-class (the Shop's Class tab, a class tried on),
## shop-confirm (its Buy card), goals (the Goals screen after a won match: some goals to claim, one claimed), emote-wheel (a match with the emote wheel open while the player dances), results (the
## end-of-match panel with the coins and unlock progress), spectate (Sudden Death after the player fell off: spectator camera + line, touch layer on),
## account-guest (Pick a name) / account-signed (signed in, saved to the cloud 2 min ago) / account-signed-np (a name with no password yet); --lang ja|fr,
## perf (match with the performance readout on, top-left), soak (a real 20 s soak run and its summary card),
## killcam (a fast K.O. by the player, mid replay in slow-mo). Used by tools/shoot-godot-ui.sh.
## modes2-mode (the game type page scrolled to the end, Pillars picked), modes2-pillars (a Pillars match across the ring
## after the first weapon handout), modes2-lowg (Moon Drift on Crater Dome, the player high in the air),
## modes2-practice (the Practice Range: the player with a rack AK shooting down the range at the dummies).
## recover (touch layer on, a rocket launcher with its burst pips, knocked into the air and mid "boing burst": the
## RECOVER context button refilling, logic/skills.gd).

const FRAME := 1.0 / 60.0

var shot := "title"
var out := "shot.png"
var pick_arg := ""             ## --pick KEY: the Locker card to pick (locker-* shots), instead of the default one
var diff_arg := "nightmare"    ## --diff easy|normal|nightmare: the Arcade difficulty of the arcade-* shots
var frames := 0
var world: Node
var i := 0

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for k in a.size():
		if a[k] == "--shot" and k + 1 < a.size(): shot = a[k + 1]
		elif a[k] == "--out" and k + 1 < a.size(): out = a[k + 1]
		elif a[k] == "--pick" and k + 1 < a.size(): pick_arg = a[k + 1]
		elif a[k] == "--diff" and k + 1 < a.size(): diff_arg = a[k + 1]
		elif a[k] == "--lang" and k + 1 < a.size(): TranslationServer.set_locale(a[k + 1])   # e.g. ja, fr
	process_frame.connect(_start, CONNECT_ONE_SHOT)

func _settings() -> Node:
	return root.get_node("Settings")

func _start() -> void:
	var la := OS.get_cmdline_user_args()
	for k in la.size():
		if la[k] == "--lang" and k + 1 < la.size(): root.get_node("Lang").apply(la[k + 1])   # (the Lang autoload picks the device language otherwise)
	if "--phone" in OS.get_cmdline_user_args():          # like a touch device: the 44 pt UI scale and the touch layer (docs/UI_REVIEW.md)
		_settings().set_value("ui_scale", "normal")
		_settings().set_value("touch_mode", "on")
	if shot == "goals":
		var sv: Node = root.get_node("Save")
		sv.begin_match()
		for k in 3: sv.on_ko(true, false, k == 0)
		sv.on_hit(true)
		sv.finish_match(true, "Classic", "Arena", false, "classic")
		sv.claim_goal("a:first_win")
		var m: Node = load("res://scenes/main.tscn").instantiate()
		root.add_child(m)
		m.open_goals()
		frames = 40
		process_frame.connect(_wait)
		return
	if shot.begins_with("locker") or shot.begins_with("shop"):
		var sv: Node = root.get_node("Save")
		var shop := shot.begins_with("shop")
		if not shop:                       # the Walldrobe only shows what you own: buy a few things first
			sv.add_coins(3400)
			for id in ["griddy", "dab", "flip"]: sv.buy("emote", id)
			sv.buy("skin", "pirate"); sv.buy("skin", "cowboy"); sv.buy("class", "tank")
			sv.wear_skin("none"); sv.set_class("wobbler")
		else:
			sv.add_coins(1000)
			for id in ["griddy", "dab", "flip"]: sv.buy("emote", id)
			sv.add_coins(700)
		var m: Node = load("res://scenes/main.tscn").instantiate()
		root.add_child(m)
		var tab: String = ("class" if shot == "shop-class" else "skin") if shop else shot.substr(7)
		m.open_locker(shop, tab)
		var pick: String = {"skin": "cowboy", "hat": "crown", "color": "", "emote": "griddy", "class": "tank"}.get(tab, "")
		if shop: pick = "dash" if tab == "class" else "pirate"
		if pick_arg != "": pick = pick_arg
		if pick != "" and m.locker.cards.has(pick): m.locker._select_card(pick)
		if shot == "shop-confirm": m.locker.act()
		frames = 150
		process_frame.connect(_wait)
		return
	if shot.begins_with("dlc-"):
		var sv: Node = root.get_node("Save")
		sv.coins = 800 if shot == "dlc-hub-poor" else 2300
		if shot in ["dlc-hub", "dlc-prematch", "dlc-arc-class", "dlc-arc-diff"]: sv.dlc["owned"] = true
		if shot == "dlc-arc-diff":
			sv.dlc["arcade_best"]["easy"] = 6
			sv.dlc["arcade_best"]["normal"] = 4
		var m: Node = load("res://scenes/main.tscn").instantiate()
		m.auto_intro = false
		root.add_child(m)
		m.open_hub()
		if shot == "dlc-prematch": m.hub.open_pre()
		if shot == "dlc-code": m.hub.open_code()
		if shot == "dlc-arc-class": m.hub.show_arcade(1)
		if shot == "dlc-arc-diff": m.hub.show_arcade(2)
		frames = 90 if shot == "dlc-arc-class" else 40
		process_frame.connect(_wait)
		return
	if shot == "news":                                    # the What's new card over the title
		var m: Node = load("res://scenes/main.tscn").instantiate()
		root.add_child(m)
		m.open_news()
		frames = 40
		process_frame.connect(_wait)
		return
	if shot == "soak":                       # a real 20 s soak run (the device run is 900 s), then its summary card
		var w: Node = SoakRun.make_world(20.0, ["arenaxl", "colosseum"], "user://soak_shot")
		root.add_child(w)
		_soak = w.soak
		process_frame.connect(_wait_soak)
		return
	if shot.begins_with("account"):
		var m: Node = load("res://scenes/main.tscn").instantiate()
		root.add_child(m)
		if shot == "account-signed" or shot == "account-signed-np":
			var c: Node = root.get_node("Save").cloud
			c.setv("token", "ab".repeat(32)); c.setv("user", "WobbleQueen"); c.setv("email", "queen@example.com" if shot == "account-signed" else "")
			c.setv("cloud_t", int((Time.get_unix_time_from_system() - 130.0) * 1000.0))
			c.has_password = shot == "account-signed"
			m._refresh_login()
		m.open_account()
		frames = 40
		process_frame.connect(_wait)
		return
	if (shot.begins_with("polish-") and not shot.begins_with("polish-pause")) or shot.begins_with("online-"):
		_polish()
		return
	if shot == "modes2-mode": shot = "newmodes-mode2"
	if shot.begins_with("title") or shot.begins_with("wizard") or shot.begins_with("newmodes"):
		if shot.begins_with("wizard") or shot.begins_with("newmodes"):   # a fixed setup so the shots are comparable
			var md: String = {"newmodes-mode": "chaos", "newmodes-players": "tdm", "newmodes-mode2": "pillars", "wizard-team": "tdm"}.get(shot, "classic")
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
			m.open_wizard(maxi(0, ["wizard-mode", "wizard-arena", "wizard-players", "wizard-character", "wizard-start"].find(shot)))   # (wizard-team: Team Deathmatch picked, its section scrolled into view)
		elif shot.begins_with("newmodes"):
			m.open_wizard(2 if shot == "newmodes-players" else 0)
			if shot != "newmodes-players": _scroll_wizard = m.wizard
		frames = 40
		process_frame.connect(_wait)
		return
	if shot.begins_with("arcade-"):
		_arcade_start()
		return
	var phone: bool = "--phone" in OS.get_cmdline_user_args()
	var touch_shot := phone or shot == "touch" or shot == "touch-lefty" or shot == "spectate" or shot == "emote-wheel" or shot == "recover" or shot.begins_with("hud-")
	_settings().set_value("touch_mode", "on" if touch_shot else "off")
	_settings().set_value("touch_lefty", shot == "touch-lefty")
	_settings().set_value("show_fps", shot == "fps")
	_settings().set_value("perf_overlay", shot == "perf")     # the device readout (ui/perf_overlay.gd)
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
	if shot.begins_with("hud-"):                         # touch HUD per mode: hud-classic / hud-tdm / hud-chaos / hud-pillars
		world.mode_id = shot.substr(4)
		if world.mode_id == "pillars": world.map_id = "pillars"
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

## Construction Arcade shots (dlc/construction/arcade_*): arcade-intro (stage 1 intro card), arcade-fight (stage 1 mid fight), arcade-engineer
## (the Engineer with load test crates falling), arcade-pm (Project Manager: bar, shrinking floor line), arcade-client / -client2 / -client3 (The Client with the
## boss bar at full health, after phase 1 and after phase 2), arcade-clear (stage clear card), arcade-victory (the victory card), arcade-failed. --phone = touch layer.
func _arcade_start() -> void:
	var phone: bool = "--phone" in OS.get_cmdline_user_args()
	_settings().set_value("touch_mode", "on" if phone else "off")
	_settings().set_value("touch_lefty", false)
	root.get_node("Save").dlc["owned"] = true
	var AM: GDScript = load("res://dlc/construction/arcade_manager.gd")
	world = AM.call("launch", 4242, diff_arg)
	var arc = world.arcade
	arc.stage = {"arcade-engineer": 1, "arcade-pm": 4, "arcade-client": 5, "arcade-client2": 5, "arcade-client3": 5, "arcade-clear": 1, "arcade-victory": 5, "arcade-failed": 1}.get(shot, 0)
	arc.fixed_seed = 777
	if shot in ["arcade-clear", "arcade-victory"]: arc.player_dmg = 40.0
	world.auto_run = false
	world.player_class = "wobbler"
	root.add_child(world)
	if not phone: world.touch.visible = false
	process_frame.connect(_arcade_frame)

func _arcade_frame() -> void:
	var arc = world.arcade
	var sim: MatchSim = world.sim
	var p := sim.player
	var st: InputState = world.input.state
	i += 1
	if shot == "arcade-intro":
		world.tick(FRAME)
		if i == 8:
			process_frame.disconnect(_arcade_frame)
			_save()
		return
	if i == 2: arc.begin_fight()
	if i == 3 and arc.boss != null and shot in ["arcade-client", "arcade-client2", "arcade-client3", "arcade-engineer", "arcade-pm"]:
		var bp: FighterPhysics = arc.boss.phys                  # the player a few metres from the boss, facing it
		p.phys.place(bp.px + 5.0, bp.py + 0.05, bp.pz)
	if i > 2:
		var tg: FighterState = null
		var bd := 1e9
		for f: FighterState in arc.enemies:
			if f.dead or arc.downed.has(f): continue
			var d := Vector2(f.phys.px - p.phys.px, f.phys.pz - p.phys.pz).length()
			if d < bd: bd = d; tg = f
		var go := Vector2.ZERO
		var fire := false
		if tg != null and shot not in ["arcade-client", "arcade-client2", "arcade-client3", "arcade-engineer", "arcade-pm"]:
			var dd := Vector2(tg.phys.px - p.phys.px, tg.phys.pz - p.phys.pz)
			world.cam.yaw = atan2(dd.x, dd.y)
			world.cam.pitch = -0.1
			if dd.length() > 7.0 and i % 40 == 0:
				var away := (-dd).normalized() * 1.7
				p.phys.place(tg.phys.px + away.x, tg.phys.py + 0.05, tg.phys.pz + away.y)
			go = Vector2(0, 1) if dd.length() > 1.6 else Vector2.ZERO
			fire = dd.length() < 2.6
		elif tg != null:                         # boss shots: the player faces the boss, on a spot a few metres away
			var dd := Vector2(tg.phys.px - p.phys.px, tg.phys.pz - p.phys.pz)
			world.cam.yaw = atan2(dd.x, dd.y)
			world.cam.pitch = -0.12
			p.invuln = 5.0
		st.set_move("script", go)
		st.hold("script", "fire", fire)
	if shot == "arcade-engineer" and i == 30:
		arc.events._load_test({"crate_count": 3, "warning_time": 2.5})
	if shot == "arcade-client2" and i == 30: arc.boss.hp = sim.combat.max_hp(arc.boss) * 0.6
	if shot == "arcade-client3" and i == 30: arc.boss.hp = sim.combat.max_hp(arc.boss) * 0.3
	if shot == "arcade-pm" and i == 3: arc.events._creep({"spawn_extra": 1, "max_extra": 3})
	if shot == "arcade-failed" and i == 40:
		p.invuln = 0.0
		sim.combat.hit(p, 1e6, 0.0, 1.0, 0.0, 5.0, false, null)
	world.tick(FRAME)
	var wait: int = {"arcade-fight": 160, "arcade-engineer": 70, "arcade-pm": 150, "arcade-client": 60, "arcade-client2": 110, "arcade-client3": 110}.get(shot, 0)
	if wait > 0 and i >= wait:
		process_frame.disconnect(_arcade_frame)
		_save()
	elif shot == "arcade-clear" or shot == "arcade-victory" or shot == "arcade-failed":
		var up: bool = world.get_node("UI").get_node_or_null({"arcade-clear": "ArcadeClear", "arcade-victory": "ArcadeVictory", "arcade-failed": "ArcadeFailed"}[shot]) != null
		if up:
			frames += 1
			if frames > 12:
				process_frame.disconnect(_arcade_frame)
				_save()
		if i > 2400:
			process_frame.disconnect(_arcade_frame)
			_save()

var _scroll_wizard: Node = null
var _soak: SoakRun = null

func _wait_soak() -> void:
	if not _soak.done: return
	process_frame.disconnect(_wait_soak)
	frames = 30
	process_frame.connect(_wait)

## Menu polish shots (docs/style/godot-polish-*.png): polish-rooms / polish-rooms-empty / polish-rooms-error (the
## online panel's room list), polish-settings-<section>, polish-help (the controls picture), polish-intro-1..3;
## polish-pause, polish-pause-confirm, polish-pause-settings, polish-pause-help run in a match (see _frame).
func _polish() -> void:
	var m: Node = load("res://scenes/main.tscn").instantiate()
	m.auto_intro = false
	root.add_child(m)
	m.browser.auto_refresh = false
	if shot.begins_with("online-host"):                 # the Host sheet tabs (docs/style/godot-online-*.png)
		m.show_tab(true)
		m.show_host(true)
		if shot == "online-host-mode":
			m.set_host_mode("tdm"); m._host_bs["lim_4"].pressed.emit(); m._host_bs["dyn_wobble"].pressed.emit()
			m.show_host_tab("Mode")
		elif shot == "online-host-rules":
			m._host_bs["hp_300"].pressed.emit(); m._host_bs["kb_3"].pressed.emit(); m._host_bs["inf_1"].pressed.emit()
			m.show_host_tab("Rules")
	elif shot == "online-lobby" or shot == "online-lobby-web":   # the lobby with its rules line (a web player: Classic)
		m.show_tab(true)
		var hs := HostSession.new()
		hs.room_code = "K7QXP"; hs.room_name = "Friday Knockouts"; hs.opt_max = 6
		hs.my_info = {"id": 0, "name": "Kedros", "gd": 1}
		hs.roster = [hs.my_info, {"id": 1, "name": "Alice", "gd": 1}, {"id": 2, "name": "Bob", "gd": 1}]
		if shot == "online-lobby-web": hs.roster.append({"id": 3, "name": "WebWendy"})
		hs.set_rules({"mode": "tdm", "lim": 20, "hp": 300, "grav": 1.0, "kb": 1.5, "crate": "fast", "inf": false, "dyn": "wobble", "map": "rooftops"})
		m.session = hs
		m._fill_lobby()
		m.show_lobby(true)
	elif shot.begins_with("polish-rooms"):
		m.show_tab(true)
		if shot == "polish-rooms":
			m.browser.show_rooms(load("res://net/room_list.gd").clean([
				{"id": "r1", "name": "Wobble Party", "host": "Alice", "modeName": "Classic", "map": "Bouncy Rooftop", "n": 5, "max": 8, "started": true, "build": "b77.0"},
				{"id": "r2", "name": "Friday Knockouts", "host": "Bob", "modeName": "2 vs 2", "map": "Arena", "n": 3, "max": 4, "started": false, "build": "b77.0"},
				{"id": "r3", "name": "Full House", "host": "Carol", "modeName": "Classic", "map": "Farm", "n": 4, "max": 4, "started": true, "build": "b77.0"},
				{"id": "r4", "name": "Old Version Room", "host": "Dan", "modeName": "Sudden Death", "map": "Volcano", "n": 2, "max": 6, "started": false, "build": "b70.2"},
				{"id": "r5", "name": "Chill", "host": "Eve", "modeName": "Classic", "map": "Candy", "n": 1, "max": 8, "started": false, "build": "b77.0"}]))
		elif shot == "polish-rooms-empty": m.browser.show_rooms([])
		else: m.browser.show_rooms([], load("res://net/room_list.gd").ERR_REACH)
	elif shot.begins_with("polish-settings-"):
		m.show_settings(true, shot.substr(16))
	elif shot == "polish-help":
		m.show_settings(true, "controls")
		m.settings.open_help()
	elif shot.begins_with("polish-intro-"):
		m.intro.open()
		m.intro.go(int(shot.substr(13)) - 1)
	frames = 40
	process_frame.connect(_wait)

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
	if shot == "killcam" and i == 100:
		for f: FighterState in sim.fighters:
			if f != p: f.hp = 1.0                       # the next hit is a fast K.O.
	if shot == "killcam" and world.kill_cam.active:
		world.tick(FRAME)
		i += 1
		if world.kill_cam.shown > 1.5:
			process_frame.disconnect(_frame)
			_save()
		return
	if shot.begins_with("modes2-"):
		_modes2_frame(sim, p, st)
		return
	if i == 2:
		sim.combat.pickup(p, "katana")
		sim.combat.pickup(p, "smg")      # the last pickup is the active slot
		if shot == "recover" or shot.begins_with("hud-"): sim.combat.pickup(p, "rocket")
		if not shot.begins_with("touch") and not shot.begins_with("hud-") and shot != "recover": world.hud.last_touch = false
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
	if shot.begins_with("hud-") and i == 346:       # a second toast under the K.O. one
		world._toast("Got Rocket Launcher")
	if shot == "recover" and i == 346: world._toast("Boing burst!")
	if (shot.begins_with("touch") or shot.begins_with("hud-")) and i == 340:
		var vs: Vector2 = world.touch.get_viewport_rect().size
		var sx := vs.x * (0.84 if shot == "touch-lefty" else 0.16)
		_touch(7, Vector2(sx, vs.y * 0.62), true)
		var e := InputEventScreenDrag.new()
		e.index = 7; e.position = Vector2(sx + 40, vs.y * 0.62 - 50)
		world.touch._input(e)
		_touch(8, world.touch.button_rect(world.touch.button("fire"))[0], true)
	if (shot == "recover" or shot.begins_with("hud-")) and i >= 300 and i < 344 and p.weapon != "rocket":   # rocket in hand (no dash gear)
		for k in 3:
			if p.slots[k] != null and p.slots[k]["key"] == "rocket": sim.combat.equip_slot(p, k)
	if (shot == "recover" or shot.begins_with("hud-")) and i == 334 and not p.dead:   # knocked up and away, then the context button (RECOVER)
		p.phys.vy = 11.0; p.phys.vx = 9.0; p.phys.grounded = false; p.last_hit_time = sim.combat.time
	if (shot == "recover" or shot.begins_with("hud-")) and i == 344:
		_touch(9, world.touch.button_rect(world.touch.button("context"))[0], true)
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
	if (shot == "pause" or shot.begins_with("polish-pause")) and i == 345:
		world._toggle_pause()
		match shot:
			"polish-pause-confirm": world.pause_menu.ask_quit()
			"polish-pause-settings": world.pause_menu.open_settings()
			"polish-pause-help": world.pause_menu.open_help()
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
