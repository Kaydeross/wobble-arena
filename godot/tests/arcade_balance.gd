extends SceneTree
## Arcade difficulty balance probe (not part of npm test; numbers go in docs/CONSTRUCTION_DLC.md "Difficulty tuning"):
##   godot --headless --path godot --script res://tests/arcade_balance.gd -- --no-save [--seeds=5] [--diffs=easy,normal,nightmare] [--stages=1,2,3,4,5,6] [--class=wobbler] [--limit=100]
## The scripted melee player of arcade_test.gd with NORMAL damage (no boost) and no healing fights each stage once (one life) per seed
## against the stage table's own bot skills; prints win / lose, the player's health left and the time.
const FRAME := 1.0 / 60.0
var AM: GDScript

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % k): return a.substr(k.length() + 3)
	return d

func _nearest(w: Node) -> FighterState:
	var arc = w.arcade
	var p: FighterState = w.sim.player
	var best: FighterState = null
	var bd := 1e9
	for f: FighterState in arc.enemies:
		if f.dead or arc.downed.has(f): continue
		var d := Vector2(f.phys.px - p.phys.px, f.phys.pz - p.phys.pz).length()
		if d < bd: bd = d; best = f
	return best

func _frame(w: Node, i: int) -> void:
	var p: FighterState = w.sim.player
	var st: InputState = w.input.state
	var tg := _nearest(w)
	var go := Vector2.ZERO
	var fire := false
	if tg != null:
		var d := Vector2(tg.phys.px - p.phys.px, tg.phys.pz - p.phys.pz)
		w.cam.yaw = atan2(d.x, d.y)
		w.cam.pitch = -0.1
		if d.length() > 7.0 and i % 40 == 0:
			var away := (-d).normalized() * 1.7
			p.phys.place(tg.phys.px + away.x, tg.phys.py + 0.05, tg.phys.pz + away.y)
		go = Vector2(0, 1) if d.length() > 1.6 else Vector2.ZERO
		fire = d.length() < 2.6
		if i % 131 == 0: st.press("kick")
	st.set_move("script", go)
	st.hold("script", "fire", fire)
	st.hold("script", "jump", i % 197 < 3)

func _run() -> void:
	AM = load("res://dlc/construction/arcade_manager.gd")
	var sv := root.get_node("Save")
	var seeds := int(_arg("seeds", "5"))
	var limit := float(_arg("limit", "100"))
	var cls := _arg("class", "wobbler")
	var diffs: PackedStringArray = _arg("diffs", "easy,normal,nightmare").split(",")
	var stages: PackedStringArray = _arg("stages", "1,2,3,4,5,6").split(",")
	for dn in diffs:
		for sn in stages:
			var wins := 0
			var hp_sum := 0.0
			var t_sum := 0.0
			var parts: Array = []
			for sd in seeds:
				sv.reset()
				sv.dlc["owned"] = true
				var w: Node = AM.call("launch", 7000 + sd * 31, dn, cls)
				var arc = w.arcade
				arc.stage = int(sn) - 1
				arc.fixed_seed = 500 + sd * 13
				w.auto_run = false
				root.add_child(w)
				arc.begin_fight()
				var t := -1.0
				for i in int(limit / FRAME):
					_frame(w, i)
					w.tick(FRAME)
					if arc.state != "fight":
						t = i * FRAME
						break
				var p: FighterState = w.sim.player
				var left := clampf(p.hp / w.sim.combat.max_hp(p), 0.0, 1.0) if arc.state == "clearing" else 0.0
				var won: bool = arc.state == "clearing"
				if won: wins += 1; hp_sum += left; t_sum += t
				parts.append("%s%d%%" % ["W" if won else "L", int(left * 100)])
				w.queue_free()
				await process_frame
				await process_frame
			print("BAL %-9s stage %s wins %d/%d  avg hp left %3d%%  avg time %3ds  [%s]" % [dn, sn, wins, seeds, int(100.0 * hp_sum / maxf(1, wins)), int(t_sum / maxf(1, wins)), " ".join(parts)])
	quit(0)
