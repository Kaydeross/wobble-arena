extends SceneTree
## Headless kill-cam test (world/kill_cam.gd + world.gd, run by tools/test-killcam.js):
##   godot --headless --path godot --script res://tests/killcam_test.gd -- --no-save
## Records at ~30 Hz into a ring buffer that never grows past REC_MAX; a fast K.O. by the player starts the replay
## AFTER seconds later; the match is frozen while it plays (sim time, FighterStates untouched); the camera films both
## fighters from the side; slow-mo makes it last longer than the recording; the HUD comes back and the camera ends on
## the follow camera (same yaw / pitch as before, follow distance, FOV); a tap skips it; a slow kill, the cooldown, the
## setting off and team modes give no replay; recording stays cheap.

const FRAME := 1.0 / 60.0

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("KC ok   " if ok else "FAIL ") + what)
	if not ok: fails += 1

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _world(mode: String) -> Node:
	var w: Node = load("res://world/world.tscn").instantiate()
	w.map_id = "arena"
	w.auto_run = false
	w.bot_count = 1
	w.dyn_choice = "off"
	w.mode_id = mode
	w.rng_seed = 7
	w.kill_cam_in_tests = true
	root.add_child(w)
	return w

func _ko(w: Node, victim: FighterState) -> void:
	w.sim.combat.events.append({"type": "ko", "killer": w.sim.player, "victim": victim, "weapon": "Spatula"})

func _run() -> void:
	var st: Node = root.get_node("Settings")
	st.set_value("kill_cam", true)
	var w := _world("classic")
	var kc = w.kill_cam                     # (untyped: KillCam needs the autoloads, which a --script compile has not got yet)
	var sim = w.sim
	var bot: FighterState = null
	for f: FighterState in sim.fighters:
		if f != sim.player: bot = f
	check(w.kill_cam_enabled(), "on offline in Classic")
	for i in 180: w.tick(FRAME)
	check(kc.ring.size() >= 86 and kc.ring.size() <= 92, "~30 Hz recording (%d frames in 3 s)" % kc.ring.size())
	for i in 120: w.tick(FRAME)
	check(kc.ring.size() == kc.REC_MAX and kc.n > kc.REC_MAX, "ring buffer capped at %d (%d recorded)" % [kc.ring.size(), kc.n])
	var rec: Array = kc.recorded()
	check(int(rec[0]["n"]) == kc.n - kc.REC_MAX and int(rec[-1]["n"]) == kc.n - 1, "oldest first")
	# a slow kill: no replay
	_ko(w, bot)
	w.tick(FRAME)
	check(kc.pending.is_empty(), "a K.O. without a recent hit is not a fast kill")
	# a fast kill: the replay starts AFTER seconds later
	var yaw0: float = w.cam.yaw
	var pitch0: float = w.cam.pitch
	kc.note_hit(bot)
	for i in 30: w.tick(FRAME)
	_ko(w, bot)
	w.tick(FRAME)
	check(not kc.pending.is_empty(), "fast kill queued")
	var waited := 0
	while not kc.active and waited < 120:
		w.tick(FRAME); waited += 1
	check(kc.active and absf(waited * FRAME - kc.AFTER) < 0.1, "replay starts %.2f s after the K.O." % (waited * FRAME))
	check(not w.hud.visible and w._kc_l.visible and w._kc_l.text.contains("tap to skip"), "HUD hidden, replay line shown (%s)" % w._kc_l.text)
	var t_sim: float = sim.combat.time
	var px: float = sim.player.phys.px
	var frames := 0
	var side_ok := 0
	var dist_ok := 0
	var fov_ok := true
	var slow_frames := 0
	while kc.active and frames < 600:
		w.tick(FRAME); frames += 1
		if not kc.active: break
		var i: int = floori(kc.idx)
		var k: Vector3 = kc.frames[i]["s"][kc.ki]["pos"]
		var v: Vector3 = kc.frames[i]["s"][kc.vi]["pos"]
		var mid := (k + v) * 0.5
		var cp: Vector3 = w.cam.global_position
		var d := Vector2(cp.x - mid.x, cp.z - mid.z).length()
		if d > 1.4 and d < 15.5: dist_ok += 1
		var line := Vector2(v.x - k.x, v.z - k.z)
		var to_cam := Vector2(cp.x - mid.x, cp.z - mid.z)
		if line.length() < 0.5 or absf(line.normalized().dot(to_cam.normalized())) < 0.75: side_ok += 1
		if absf(w.cam.fov - kc.FOV) > 0.01: fov_ok = false
		if kc.speed_at(kc.idx) < 1.0: slow_frames += 1
	var secs: float = frames * FRAME
	print("KC replay %.2f s (%d frames), slow-mo %d frames, side %d, framed %d" % [secs, frames, slow_frames, side_ok, dist_ok])
	check(secs > kc.BACK + kc.AFTER and secs < 5.0, "slow-mo replay lasts %.2f s (recording %.2f s)" % [secs, kc.BACK + kc.AFTER])
	check(slow_frames > 20, "slow-mo round the K.O. (%d frames)" % slow_frames)
	check(side_ok >= frames * 0.8 and dist_ok >= frames * 0.9, "camera films both from the side (%d / %d side, %d framed)" % [side_ok, frames, dist_ok])
	check(fov_ok, "replay FOV %.0f" % kc.FOV)
	check(is_equal_approx(sim.combat.time, t_sim) and is_equal_approx(sim.player.phys.px, px), "the match is frozen during the replay")
	check(not kc.active and w.hud.visible and not w._kc_l.visible, "replay ended, HUD back")
	w.tick(FRAME)
	check(sim.combat.time > t_sim, "the match carries on")
	var piv: Vector3 = w.player_pos() + Vector3(0, 2.0, 0)
	var cd: float = w.cam.global_position.distance_to(piv)
	check(absf(cd - 6.2 * float(st.get_value("cam_dist", 1.0))) < 0.8, "camera back on the follow camera (%.2f m from the player)" % cd)
	check(is_equal_approx(w.cam.yaw, yaw0) and is_equal_approx(w.cam.pitch, pitch0), "camera yaw / pitch as before the replay")
	check(absf(w.cam.fov - float(st.get_value("fov", 72.0))) < 0.5, "FOV back (%.1f)" % w.cam.fov)
	# cooldown, then a skip by tap
	kc.note_hit(bot)
	_ko(w, bot)
	w.tick(FRAME)
	check(kc.pending.is_empty(), "no second replay inside the cooldown")
	kc.last_at = -1.0e9
	kc.note_hit(bot)
	_ko(w, bot)
	for i in 50: w.tick(FRAME)
	check(kc.active, "another fast kill after the cooldown")
	w._on_spectate_tap()
	check(not kc.active and w.hud.visible and not w.touch.spectate_mode, "a tap skips it")
	# off: the setting, team modes
	st.set_value("kill_cam", false)
	check(not w.kill_cam_enabled(), "Settings kill_cam off")
	st.set_value("kill_cam", true)
	# recording cost (iPhone budget: well under a millisecond per snapshot)
	var t0 := Time.get_ticks_usec()
	for i in 200:
		kc._acc = 1.0
		kc.record(0.0)
	var us := float(Time.get_ticks_usec() - t0) / 200.0
	check(us < 400.0, "snapshot of %d fighters takes %.0f us" % [kc.views.size(), us])
	w.queue_free()
	await process_frame
	var t := _world("tdm")
	check(not t.kill_cam_enabled(), "off in team modes")
	t.queue_free()
	await process_frame
	print("KILLCAM %s" % ("ok" if fails == 0 else "FAILED (%d)" % fails))
	quit(0 if fails == 0 else 1)
