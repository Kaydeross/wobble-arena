class_name InputState
extends RefCounted
## The one input state every source writes into (keyboard/mouse, gamepad, touch) and World reads.
## Sources are kept apart so releasing a key does not cancel the same action held on the touch screen.
##
## Held actions:  jump, fire, sprint, crouch      -> is_held(action)
## Taps (edges):  swap, reload, shove, kick, dash, pause, spatula, slot1..3 -> consume(action) once per press
## Toggles:       aim (scope toggle on touch; held on mouse/gamepad) -> aiming()
## Move:          move = Vector2(right, forward), length <= 1
## Look:          look = radians to add to (yaw, pitch) this frame (already scaled by sensitivity); World calls take_look()

const SOURCES := ["key", "pad", "touch", "script"]

var _move := {}            ## source -> Vector2
var _held := {}            ## source -> {action: true}
var _pressed := {}         ## action -> pending press count
var _look := Vector2.ZERO
var aim_toggle := false    ## touch AIM button / scope toggle

func _init() -> void:
	for s in SOURCES:
		_move[s] = Vector2.ZERO
		_held[s] = {}

func set_move(source: String, v: Vector2) -> void:
	_move[source] = v.limit_length(1.0)

## Combined move vector (x = right, y = forward), clamped to length 1.
func move() -> Vector2:
	var v := Vector2.ZERO
	for s in SOURCES:
		v += _move[s]
	return v.limit_length(1.0)

func hold(source: String, action: String, on: bool) -> void:
	if on:
		_held[source][action] = true
	else:
		_held[source].erase(action)

func is_held(action: String) -> bool:
	for s in SOURCES:
		if _held[s].has(action):
			return true
	return false

## The actions held right now, per source: "touch fire+jump | key sprint". Empty sources are omitted; "" when nothing
## is held. Shown by the performance readout (ui/perf_overlay.gd) so a stuck touch control is visible on device.
func held_report() -> String:
	var parts := PackedStringArray()
	for s in SOURCES:
		var acts := PackedStringArray()
		for a in _held[s].keys():
			acts.append(str(a))
		if acts.is_empty():
			continue
		acts.sort()
		parts.append("%s %s" % [s, "+".join(acts)])
	return " | ".join(parts)

func press(action: String) -> void:
	_pressed[action] = int(_pressed.get(action, 0)) + 1

## True once per press (taps are queued until the sim reads them).
func consume(action: String) -> bool:
	var n := int(_pressed.get(action, 0))
	if n <= 0:
		return false
	_pressed[action] = n - 1
	return true

func peek(action: String) -> bool:
	return int(_pressed.get(action, 0)) > 0

func aiming() -> bool:
	return aim_toggle or is_held("aim")

func add_look(yaw: float, pitch: float) -> void:
	_look += Vector2(yaw, pitch)

## Look delta accumulated since the last call (x = yaw, y = pitch), then reset.
func take_look() -> Vector2:
	var l := _look
	_look = Vector2.ZERO
	return l

## Let go of everything (pause, focus lost, leaving the match).
func clear() -> void:
	for s in SOURCES:
		_move[s] = Vector2.ZERO
		_held[s].clear()
	_pressed.clear()
	_look = Vector2.ZERO
	aim_toggle = false
