class_name Tutorial
extends Node
## The controls training ("Training"): a guided practice in the real world (docs/CONTROLS.md). The world runs the Practice
## Range (flat, dummies that never fight back, no K.O. limit, no clock) with `trial = true`, so nothing is ever written:
## no coins, stats, goals, history or ranking. This node adds what makes it a lesson:
##   - the loadout: an AK-47 in hand and a Ninja Katana in slot 2 (no rack, no crates), endless ammo, the player cannot be
##     K.O.'d, and each step gets the weapon it needs;
##   - the steps (logic/tutorial_steps.gd): Move, Look, Jump, Fire, Aim, Reload, Shove, Kick, Switch weapon, Dash, back to
##     the spatula, Pause. A step is done when the REAL input happens: it listens to the shared InputState (every device
##     writes into it: keyboard / mouse, gamepad, touch) and to the sim for the weapon in hand and the pause menu;
##   - the coach card (ui/tutorial_card.gd) with the active control profile's prompt (input/control_profile.gd), which is
##     redone the moment the player switches device (keyboard <-> gamepad), and on touch a pulse ring over the real control;
##   - the finish card: Play / Replay / Back. Finishing sets Settings `seen_tutorial` (the only thing the training writes).
## Start one with Tutorial.launch(tree).

signal step_changed(index: int)
signal finished

const CHEER_TIME := 0.9
const WORLD := "res://world/world.tscn"

var world: Node
var state: InputState
var card: TutorialCard
var index := 0
var is_done := false
var profile := ""
var cheering := false
var cheer_time := CHEER_TIME  ## how long the cheer shows between steps (tests shorten it)
var _cheer_t := 0.0
var _move_t := 0.0
var _look := 0.0
var _hit := false             ## a switch input happened during a weapon step
var _wait_resume := false     ## the pause step is done: the finish card waits until the menu closes
var _cheers := 0

## A fresh training world (the Practice Range, trial = true, tutorial = true). Used by the title's offer, Settings > Controls
## and the pause menu's Controls page.
static func make_world() -> Node:
	var w: Node = load(WORLD).instantiate()
	w.map_id = "practice"
	w.mode_id = "practice"
	w.bot_count = 10
	w.difficulty = "easy"
	w.ko_limit = 0
	w.dyn_choice = "off"
	w.trial = true
	w.tutorial = true
	return w

static func launch(tree: SceneTree) -> void:
	if tree == null: return
	tree.paused = false
	tree.change_scene_to_node(make_world())

## Called by the world once its map is loaded (and again after Replay).
func setup(w: Node) -> void:
	world = w
	name = "Tutorial"
	process_mode = Node.PROCESS_MODE_ALWAYS
	state = world.input.state
	if card == null:
		card = TutorialCard.new()
		world.get_node("UI").add_child(card)
		world.get_node("UI").move_child(card, world.pause_menu.get_index())
		card.skip_pressed.connect(skip)
		card.exit_pressed.connect(exit)
		card.play_pressed.connect(play)
		card.replay_pressed.connect(replay)
		card.back_pressed.connect(exit)
		state.action_down.connect(_on_action)
		state.looked.connect(_on_look)
	restart()

func restart() -> void:
	index = 0
	is_done = false
	cheering = false
	_wait_resume = false
	card.hide_finish()
	_begin_step()

func current_id() -> String:
	return str(TutorialSteps.step(index).get("id", ""))

func progress() -> Array:
	return [index, TutorialSteps.count()]

## The sentence on the card right now (tests read it).
func prompt_text() -> String:
	return TutorialSteps.plain(current_id(), ControlProfile.current())

func _begin_step() -> void:
	_move_t = 0.0; _look = 0.0; _hit = false; cheering = false
	profile = ControlProfile.current()
	var st := TutorialSteps.step(index)
	_prepare(st)
	var d := TutorialSteps.prompt(str(st["id"]), profile)
	card.set_prompt(str(d["text"]), d["keys"], index, TutorialSteps.count())
	step_changed.emit(index)

## What the step needs in the player's hands (so a skipped step never leaves the next one stuck).
func _prepare(st: Dictionary) -> void:
	if world == null or world.sim == null: return
	var c: Combat = world.sim.combat
	var p: FighterState = world.sim.player
	match str(st.get("loadout", "")):
		"gun": if p.weapon != TutorialSteps.GUN: c.equip_slot(p, 0)
		"katana": if p.weapon != TutorialSteps.NINJA: c.equip_slot(p, 1)
	if st.get("drain", false) and p.slot >= 0 and p.slots[p.slot] != null:
		var s: Dictionary = p.slots[p.slot]
		if int(s["mag"]) > 4: s["mag"] = 4     # a part-empty magazine: the reload has something to do

## Complete the current step (the player did it, or Skip).
func complete(cheer := true) -> void:
	if is_done or cheering: return
	cheering = true
	_cheer_t = cheer_time if cheer else 0.0
	var n := TutorialSteps.count()
	card.set_cheer(TutorialSteps.cheer(_cheers), index, n)
	_cheers += 1

func skip() -> void:
	if is_done or world == null: return
	complete(false)
	_cheer_t = 0.0
	_advance()

func exit() -> void:
	if world != null: world.call("leave_training")

func play() -> void:
	if world != null: world.call("start_match_from_training")

func replay() -> void:
	if world != null: world.call("replay_training")

func _advance() -> void:
	cheering = false
	if index + 1 >= TutorialSteps.count():
		_finish()
		return
	index += 1
	_begin_step()

func _finish() -> void:
	is_done = true
	Settings.set_value("seen_tutorial", true)
	card.pulse.target = {}
	if world.paused:
		_wait_resume = true
		return
	card.show_finish()
	finished.emit()

func _live() -> bool:
	return world != null and not is_done and not cheering and not world.paused and not world.countdown_locked()

func _on_action(a: String) -> void:
	if not _live(): return
	var st := TutorialSteps.step(index)
	if not (st["actions"] as Array).has(a): return
	match str(st["kind"]):
		"press": complete()
		"weapon": _hit = true

func _on_look(d: Vector2) -> void:
	if _live() and current_id() == "look":
		_look += d.length()
		if _look >= TutorialSteps.LOOK_RADS: complete()

func _process(dt: float) -> void:
	if world == null or world.sim == null: return
	if not is_done: _keep_alive()
	# no score, clock or mode line: it is practice, nothing counts
	var ml: Control = world.get("_mode_l")
	if ml != null: ml.visible = false
	var sc: Node = world.hud.get_node_or_null("Score")
	if sc != null: (sc as Control).visible = false
	# the player switched device (keyboard <-> gamepad) or the touch setting: the prompt follows
	var now := ControlProfile.current()
	if now != profile and not is_done and not cheering:
		profile = now
		var d := TutorialSteps.prompt(current_id(), profile)
		card.set_prompt(str(d["text"]), d["keys"], index, TutorialSteps.count())
	elif now != profile:
		profile = now
	if profile == ControlProfile.TOUCH and world.touch != null and not world.touch.visible:
		world.touch.visible = true
	if _wait_resume and not world.paused:
		_wait_resume = false
		card.show_finish()
		finished.emit()
	if is_done: return
	if cheering:
		_cheer_t -= dt
		if _cheer_t <= 0.0: _advance()
		card.pulse.target = {}
		return
	var st := TutorialSteps.step(index)
	if str(st["kind"]) == "pause":
		if world.paused: complete()
		card.pulse.target = _target(st) if profile == ControlProfile.TOUCH else {}
		return
	if _live():
		match str(st["kind"]):
			"move":
				if state.move().length() > 0.3:
					_move_t += dt
					if _move_t >= TutorialSteps.MOVE_SECS: complete()
			"aim":
				if state.aiming(): complete()
			"weapon":
				if _hit and world.sim.player.weapon == str(st["want"]): complete()
	card.pulse.target = _target(st) if profile == ControlProfile.TOUCH and _live() else {}

## Endless ammo and no K.O.: the player is topped up every frame (the magazine still runs down, so a reload means something).
func _keep_alive() -> void:
	var p: FighterState = world.sim.player
	for s: Variant in p.slots:
		if s != null: s["ammo"] = maxi(int(s["ammo"]), 99)
	p.hp = world.sim.combat.max_hp(p)
	# the class signature move is not part of the lesson: keep it recharging so the touch context button is free for RELOAD / DASH
	p.skill_n[Skills.SIG_ID] = 0
	p.skill_cd[Skills.SIG_ID] = Skills.SIGNATURE_CD

# ---------------- the pulse ring over the real touch control ----------------

func _target(st: Dictionary) -> Dictionary:
	var t: TouchControls = world.touch
	if t == null or not t.visible: return {}
	var vs: Vector2 = world.get_viewport().get_visible_rect().size
	match str(st["id"]):
		"move": return {"c": t.stick_home(), "r": TouchControls.STICK_R * TouchControls.UNIT * t.scale_k}
		"look", "aim": return {"c": Vector2(vs.x * (0.38 if t.lefty else 0.62), vs.y * 0.34), "r": 92.0}
		"jump": return _btn(t, "jump")
		"fire": return _btn(t, "fire")
		"shove", "kick": return _btn(t, "melee")
		"reload", "dash": return _btn(t, "context") if t.context_action() != "" else {}
		"weapon": return _slot(t, 1)
		"spatula": return _slot(t, 3)
		"pause": return {"rect": t.pause_rect()}
	return {}

func _btn(t: TouchControls, id: String) -> Dictionary:
	var b := t.button(id)
	if b.is_empty(): return {}
	var r: Array = t.button_rect(b)
	return {"c": r[0], "r": float(r[1])}

func _slot(t: TouchControls, i: int) -> Dictionary:
	var r := t.hotbar_slot_rect(i)
	return {} if r.size.x <= 0.0 else {"rect": r}
