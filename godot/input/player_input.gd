class_name PlayerInput
extends Node
## Keyboard + mouse and gamepad -> InputState. Touch (input/touch_controls.gd) writes into the same `state`.
## Default keys copy the web game's DEF_BINDS (public/index.html ~1445). Actions are registered at runtime so a later
## rebinding screen can replace them; mouse look matches the web game (0.0022 rad per pixel * sens, pitch -1.1..0.8).

signal pause_requested

const MOUSE_K := 0.0022
const PAD_LOOK_RATE := 3.2      ## rad/s at full stick deflection (sens 1)
const PAD_DEADZONE := 0.15

var state := InputState.new()
var _aim_was := false            ## aim held last frame (toggle mode flips on the press)
var enabled := true:
	set(v):
		enabled = v
		if not v:
			state.clear()
			release_mouse()

const KEYS := {
	"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN], "move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "crouch": [KEY_C], "aim": [KEY_Z], "spatula": [KEY_Q], "shove": [KEY_E],
	"kick": [KEY_F], "dash": [KEY_V], "recover": [KEY_X], "reload": [KEY_R], "slot1": [KEY_1], "slot2": [KEY_2], "slot3": [KEY_3], "pause": [KEY_ESCAPE],
}
const MOUSE := { "fire": MOUSE_BUTTON_LEFT, "aim": MOUSE_BUTTON_RIGHT, "swap": MOUSE_BUTTON_WHEEL_DOWN }
const PAD := {
	"jump": JOY_BUTTON_A, "reload": JOY_BUTTON_X, "swap": JOY_BUTTON_Y, "kick": JOY_BUTTON_B,
	"shove": JOY_BUTTON_RIGHT_SHOULDER, "dash": JOY_BUTTON_LEFT_SHOULDER, "sprint": JOY_BUTTON_LEFT_STICK,
	"crouch": JOY_BUTTON_RIGHT_STICK, "pause": JOY_BUTTON_START,
}
const PAD_AXES := { "fire": JOY_AXIS_TRIGGER_RIGHT, "aim": JOY_AXIS_TRIGGER_LEFT }
const MOVE_AXES := { "move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0], "move_forward": [JOY_AXIS_LEFT_Y, -1.0], "move_back": [JOY_AXIS_LEFT_Y, 1.0] }
const HELD := ["jump", "sprint", "crouch", "fire", "aim"]
const TAPS := ["spatula", "shove", "kick", "dash", "recover", "reload", "slot1", "slot2", "slot3", "swap"]

static func ensure_actions() -> void:
	var all := {}
	for a in KEYS: all[a] = true
	for a in MOUSE: all[a] = true
	for a in PAD: all[a] = true
	for a in PAD_AXES: all[a] = true
	for a in all:
		if InputMap.has_action(a):
			continue
		InputMap.add_action(a, 0.2)
		for k in KEYS.get(a, []):
			var e := InputEventKey.new(); e.physical_keycode = k; InputMap.action_add_event(a, e)
		if MOUSE.has(a):
			var m := InputEventMouseButton.new(); m.button_index = MOUSE[a]; InputMap.action_add_event(a, m)
		if PAD.has(a):
			var j := InputEventJoypadButton.new(); j.button_index = PAD[a]; j.device = -1; InputMap.action_add_event(a, j)
		if PAD_AXES.has(a):
			var x := InputEventJoypadMotion.new(); x.axis = PAD_AXES[a]; x.axis_value = 1.0; x.device = -1; InputMap.action_add_event(a, x)
		if MOVE_AXES.has(a):
			var mx := InputEventJoypadMotion.new(); mx.axis = MOVE_AXES[a][0]; mx.axis_value = MOVE_AXES[a][1]; mx.device = -1; InputMap.action_add_event(a, mx)

func _ready() -> void:
	ensure_actions()
	process_mode = Node.PROCESS_MODE_ALWAYS

func capture_mouse() -> void:
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func release_mouse() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

## Mouse and controller look speed (Settings `mouse_sens`; touch has its own `sens`).
func _sens() -> float:
	return float(Settings.get_value("mouse_sens", 1.0))

## Settings `aim_mode` "toggle": a press of the aim key / button / trigger turns the scope on or off.
func _aim_toggles() -> bool:
	return str(Settings.get_value("aim_mode", "hold")) == "toggle"

func _inv() -> float:
	return -1.0 if bool(Settings.get_value("invert_y", false)) else 1.0

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause") and not e.is_echo():
		pause_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if not enabled:
		return
	if e is InputEventMouseButton and e.device == InputEvent.DEVICE_ID_EMULATION:
		return   # touches are handled by the touch layer
	if e is InputEventMouseButton and e.pressed and not mouse_captured():
		capture_mouse()   # first click only grabs the mouse (like pointer lock on the web)
		get_viewport().set_input_as_handled()
		return
	if e is InputEventMouseMotion and mouse_captured():
		var d: Vector2 = e.screen_relative
		state.add_look(-d.x * MOUSE_K * _sens(), -d.y * MOUSE_K * _sens() * _inv())
		return
	for a in TAPS:
		if e.is_action_pressed(a) and not e.is_echo():
			if e is InputEventMouseButton and not mouse_captured():
				continue
			state.press(a)

func _process(dt: float) -> void:
	if not enabled:
		return
	var mouse_ok := mouse_captured()
	# digital/analog move (keys + left stick share the actions)
	state.set_move("key", Input.get_vector("move_left", "move_right", "move_back", "move_forward"))
	for a in HELD:
		var on := Input.is_action_pressed(a)
		if a == "fire" or a == "aim":   # mouse buttons only count while the mouse is captured
			on = on and (mouse_ok or _pad_action(a) or (a == "aim" and Input.is_physical_key_pressed(KEY_Z)))
		if a == "aim" and _aim_toggles():
			if on and not _aim_was: state.aim_toggle = not state.aim_toggle
			_aim_was = on
			on = false
		state.hold("key", a, on)
	# right stick look
	var pads := Input.get_connected_joypads()
	if pads.size() > 0:
		var v := Vector2(Input.get_joy_axis(pads[0], JOY_AXIS_RIGHT_X), Input.get_joy_axis(pads[0], JOY_AXIS_RIGHT_Y))
		var l := v.length()
		if l > PAD_DEADZONE:
			v = v / l * pow((l - PAD_DEADZONE) / (1.0 - PAD_DEADZONE), 2.0)
			state.add_look(-v.x * PAD_LOOK_RATE * _sens() * dt, -v.y * PAD_LOOK_RATE * 0.7 * _sens() * _inv() * dt)

func _pad_action(a: String) -> bool:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return false
	if PAD_AXES.has(a):
		return Input.get_joy_axis(pads[0], PAD_AXES[a]) > 0.2
	return false
