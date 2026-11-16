class_name ControlProfile
extends RefCounted
## Which control scheme the player is using right now, and the REAL binding of every action in it (docs/CONTROLS.md).
##
## Profile = "touch" | "keyboard" | "gamepad":
##   touch     the on-screen controls are in use (TouchControls.wanted(): a phone / tablet, a web page on a touch device,
##             or Settings > Controls > Touch buttons "On"). Touch devices stay touch.
##   keyboard  desktop (and a desktop browser): keyboard + mouse. The default.
##   gamepad   desktop with a controller: the profile follows the LAST device used, live: a pad button / a pushed stick
##             switches to gamepad, a key / mouse click or move switches back to keyboard.
## No autoload: the first current() call hangs a tiny listener node on the root (it sees input before the UI does, so
## it also works over menus). `force` pins a profile (tests, screenshots).
##
## Labels are READ from the live bindings, never copied: the InputMap actions that PlayerInput.ensure_actions() seeded
## from its KEYS / MOUSE / PAD / PAD_AXES tables (so a rebinding shows up at once), the emote keys from EmoteWheel.KEYS,
## and the touch buttons from TouchControls.BUTTONS. Names go through tr() for the words ("Left mouse", "Left stick");
## key and button letters (E, Space, RB) are never translated.

const TOUCH := "touch"
const KEYBOARD := "keyboard"
const GAMEPAD := "gamepad"
const ALL := [TOUCH, KEYBOARD, GAMEPAD]
const HINT_MATCHES := 2         ## real matches that still show the control hint line (HUD) to a player who skipped training
const LOOK_STICK := "Right stick"   ## PlayerInput reads JOY_AXIS_RIGHT_X / Y directly (no InputMap action)

static var force := ""          ## tests / screenshots: pin a profile ("" = automatic)
static var _last := KEYBOARD    ## the last desktop device used: keyboard | gamepad
static var _watch: Watcher = null

## The node that watches the devices; `changed(profile)` fires when the desktop device switches.
class Watcher extends Node:
	signal changed(profile: String)
	func _init() -> void:
		name = "ControlProfileWatcher"
		process_mode = Node.PROCESS_MODE_ALWAYS
	func _input(e: InputEvent) -> void:
		ControlProfile.note_event(e)

static func watcher() -> Watcher:
	if _watch != null and is_instance_valid(_watch):
		return _watch
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	_watch = Watcher.new()
	tree.root.add_child.call_deferred(_watch)
	return _watch

## Feeds one input event into the "last device" tracking (the watcher calls this; tests may too).
static func note_event(e: InputEvent) -> void:
	var dev := ""
	if e is InputEventJoypadButton and e.pressed: dev = GAMEPAD
	elif e is InputEventJoypadMotion and absf(e.axis_value) > 0.6: dev = GAMEPAD
	elif e is InputEventKey and e.pressed: dev = KEYBOARD
	elif e is InputEventMouseButton and e.pressed and e.device != InputEvent.DEVICE_ID_EMULATION: dev = KEYBOARD
	elif e is InputEventMouseMotion and e.device != InputEvent.DEVICE_ID_EMULATION and (e as InputEventMouseMotion).relative.length() > 2.0: dev = KEYBOARD
	if dev == "" or dev == _last: return
	var before := current()
	_last = dev
	var after := current()
	if before != after and _watch != null and is_instance_valid(_watch):
		_watch.changed.emit(after)

static func reset() -> void:
	force = ""
	_last = KEYBOARD

static func current() -> String:
	if force != "": return force
	if TouchControls.wanted(): return TOUCH
	watcher()
	return _last

static func is_valid(p: String) -> bool:
	return ALL.has(p)

static func display_name(p: String) -> String:
	return tr_("Touch") if p == TOUCH else tr_("Keyboard & mouse") if p == KEYBOARD else tr_("Gamepad")

static func tr_(s: String) -> String:
	return TranslationServer.translate(s)

# ---------------- names of the real bindings ----------------

## The names of what is bound to `action` on this profile, best first ("Left mouse", "Z"): the mouse before the keys
## for fire / aim / the wheel, then the keys in InputMap order. Touch: the on-screen control that does it.
static func names(action: String, profile := "") -> Array:
	var p := profile if profile != "" else current()
	if p == TOUCH:
		return [touch_name(action)]
	var out: Array = []
	var mouse: Array = []
	var keys: Array = []
	if p == KEYBOARD:
		for e: InputEvent in _events(action):
			if e is InputEventMouseButton: mouse.append(mouse_name((e as InputEventMouseButton).button_index))
			elif e is InputEventKey: keys.append(key_name(e as InputEventKey))
		out = mouse + keys
		if out.is_empty() and action.begins_with("emote"):
			var i := int(action.substr(5)) - 1
			if i >= 0 and i < EmoteWheel.KEYS.size(): out = [OS.get_keycode_string(EmoteWheel.KEYS[i])]
	else:
		for e: InputEvent in _events(action):
			if e is InputEventJoypadButton: out.append(pad_button_name((e as InputEventJoypadButton).button_index))
			elif e is InputEventJoypadMotion: out.append(pad_axis_name(e as InputEventJoypadMotion))
	var seen := {}
	var uniq: Array = []
	for n in out:
		if not seen.has(n): seen[n] = true; uniq.append(n)
	return uniq

## The first (best) name, "" when the action has nothing on this profile.
static func name_of(action: String, profile := "") -> String:
	var n := names(action, profile)
	return str(n[0]) if not n.is_empty() else ""

## "Left mouse / Z": every name of the action on this profile.
static func all_text(action: String, profile := "") -> String:
	return " / ".join(PackedStringArray(names(action, profile)))

static func _events(action: String) -> Array:
	if not InputMap.has_action(action):
		PlayerInput.ensure_actions()      # the title has no PlayerInput node yet: register the defaults (idempotent)
	return InputMap.action_get_events(action) if InputMap.has_action(action) else []

## The real keycode of a key event (the key under the physical position on this layout, so AZERTY shows Z for W's place).
static func key_name(e: InputEventKey) -> String:
	var code: int = e.keycode
	if code == 0:
		var pk: int = e.physical_keycode
		code = DisplayServer.keyboard_get_keycode_from_physical(pk) if pk != 0 and DisplayServer.get_name() != "headless" else 0
		if code == 0: code = pk
	return keycode_name(code)

static func keycode_name(code: int) -> String:
	match code:
		KEY_SPACE: return "Space"
		KEY_ESCAPE: return "Esc"
		KEY_SHIFT: return "Shift"
		KEY_CTRL: return "Ctrl"
		KEY_ALT: return "Alt"
		KEY_TAB: return "Tab"
		KEY_ENTER, KEY_KP_ENTER: return "Enter"
		KEY_UP: return "↑"
		KEY_DOWN: return "↓"
		KEY_LEFT: return "←"
		KEY_RIGHT: return "→"
	return OS.get_keycode_string(code).to_upper()

static func mouse_name(i: int) -> String:
	match i:
		MOUSE_BUTTON_LEFT: return tr_("Left mouse")
		MOUSE_BUTTON_RIGHT: return tr_("Right mouse")
		MOUSE_BUTTON_MIDDLE: return tr_("Middle mouse")
		MOUSE_BUTTON_WHEEL_UP: return tr_("Wheel up")
		MOUSE_BUTTON_WHEEL_DOWN: return tr_("Wheel down")
	return tr_("Mouse %d") % i

## Xbox-style names (the pad is named the same way in the old help text: RT fire, RB shove ...).
static func pad_button_name(i: int) -> String:
	match i:
		JOY_BUTTON_A: return "A"
		JOY_BUTTON_B: return "B"
		JOY_BUTTON_X: return "X"
		JOY_BUTTON_Y: return "Y"
		JOY_BUTTON_LEFT_SHOULDER: return "LB"
		JOY_BUTTON_RIGHT_SHOULDER: return "RB"
		JOY_BUTTON_LEFT_STICK: return "L3"
		JOY_BUTTON_RIGHT_STICK: return "R3"
		JOY_BUTTON_START: return "Start"     # the printed name on the pad: not translated
		JOY_BUTTON_BACK: return "Select"
		JOY_BUTTON_DPAD_UP: return tr_("D-pad up")
		JOY_BUTTON_DPAD_DOWN: return tr_("D-pad down")
		JOY_BUTTON_DPAD_LEFT: return tr_("D-pad left")
		JOY_BUTTON_DPAD_RIGHT: return tr_("D-pad right")
	return "B%d" % i

static func pad_axis_name(e: InputEventJoypadMotion) -> String:
	match e.axis:
		JOY_AXIS_TRIGGER_LEFT: return "LT"
		JOY_AXIS_TRIGGER_RIGHT: return "RT"
		JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y: return tr_("Left stick")
		JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y: return tr_(LOOK_STICK)
	return "Axis %d" % e.axis

## The touch control that does `action` (read from TouchControls.BUTTONS where the action has a button of its own).
static func touch_name(action: String) -> String:
	for b: Array in TouchControls.BUTTONS:
		if b[2] == action or (action == "kick" and b[0] == "melee"):
			return tr_(str(b[1]).capitalize())      # "MELEE" -> "Melee" (the word the touch picture uses)
	match action:
		"dash": return tr_("Dash")
		"reload": return tr_("Reload")
		"recover": return tr_("Recover")
		"signature": return tr_("Class move")
		"aim": return tr_("Double-tap")
		"pause": return tr_("Pause")
		"slot1", "slot2", "slot3": return tr_("Weapon tile")
		"spatula", "spatula_equip": return tr_("Spatula tile")
	return ""

# ---------------- composed pieces ----------------

## "W A S D" / "Left stick" / "the stick": how you move on this profile (one name per direction, the first binding of each).
static func move_text(profile := "") -> String:
	var p := profile if profile != "" else current()
	if p == TOUCH: return tr_("the stick")
	if p == GAMEPAD: return name_of("move_forward", p)
	var parts: Array = []
	for a: String in ["move_forward", "move_left", "move_back", "move_right"]:
		var n := name_of(a, p)
		if n != "": parts.append(n)
	return " ".join(PackedStringArray(parts))

static func look_text(profile := "") -> String:
	var p := profile if profile != "" else current()
	return tr_(LOOK_STICK) if p == GAMEPAD else tr_("Mouse") if p == KEYBOARD else tr_("drag")

## True when the mouse wheel (up and down) is what cycles the weapons: both "swap" and "swap_back" are wheel buttons.
static func wheel_pair() -> bool:
	var up := false
	var down := false
	for e: InputEvent in _events("swap_back"):
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_UP: up = true
	for e: InputEvent in _events("swap"):
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_DOWN: down = true
	return up and down

## "1 2 3": the three slot keys (touch: the tiles).
static func slots_text(profile := "") -> String:
	var p := profile if profile != "" else current()
	var parts: Array = []
	for a: String in ["slot1", "slot2", "slot3"]:
		var n := name_of(a, p)
		if n != "" and not parts.has(n): parts.append(n)
	return "-".join(PackedStringArray([parts[0], parts[-1]])) if parts.size() >= 3 else " ".join(PackedStringArray(parts))

static func emote_text(profile := "") -> String:
	var p := profile if profile != "" else current()
	if p != KEYBOARD: return tr_("emote button")
	var parts: Array = []
	for k: int in EmoteWheel.KEYS: parts.append(OS.get_keycode_string(k))
	return " ".join(PackedStringArray(parts))

# ---------------- the match hint line ----------------

## The HUD hint line: what shove / kick are on this device. "" for a player who did the training or has seen it twice.
static func hint_line(profile := "") -> String:
	var p := profile if profile != "" else current()
	if p == TOUCH:
		return tr_("Melee: tap to shove, hold to kick")
	var line := tr_("%s shove  ·  %s kick  ·  %s jump") % [name_of("shove", p), name_of("kick", p), name_of("jump", p)]
	return line

## True while the hint line should show in a real match: not trained yet and fewer than HINT_MATCHES matches seen.
static func hint_wanted() -> bool:
	if bool(Settings.get_value("seen_tutorial", false)): return false
	return int(Settings.get_value("ctl_hint_matches", 0)) <= HINT_MATCHES

## A real (non-training) match starts: counts it towards the two hinted matches. Persistent profiles only.
static func note_match() -> void:
	if not Settings.persist or bool(Settings.get_value("seen_tutorial", false)): return
	var n := int(Settings.get_value("ctl_hint_matches", 0))
	if n <= HINT_MATCHES: Settings.set_value("ctl_hint_matches", n + 1)
