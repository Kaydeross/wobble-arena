class_name TutorialSteps
extends RefCounted
## The steps of the controls training (world/tutorial.gd) and the words each one shows on each control profile
## (input/control_profile.gd). Pure data + text: no nodes. The prompts take their key / button names from the LIVE bindings
## (ControlProfile reads InputMap and the touch button table), so they stay true when a binding changes.
##
## A step is {id, kind, actions}: it is done when the real input actually happens:
##   move    the move input (stick / keys) was held for MOVE_SECS
##   look    the look input moved the camera by LOOK_RADS (mouse, right stick, drag)
##   press   one of `actions` was pressed or started being held (InputState.action_down)
##   aim     the scope is on (held, or toggled by double-tap)
##   weapon  the held weapon became `want` after a switch input
##   pause   the pause menu opened
## `loadout` says what the step needs in the player's hands: "gun" (AK, magazine part empty for a reload), "katana" or
## "any" (anything but the spatula).

const MOVE_SECS := 0.9
const LOOK_RADS := 1.0
const GUN := "ak"
const NINJA := "katana"

const STEPS := [
	{"id": "move", "kind": "move", "actions": []},
	{"id": "look", "kind": "look", "actions": []},
	{"id": "jump", "kind": "press", "actions": ["jump"]},
	{"id": "fire", "kind": "press", "actions": ["fire"], "loadout": "gun"},
	{"id": "aim", "kind": "aim", "actions": ["aim"], "loadout": "gun"},
	{"id": "reload", "kind": "press", "actions": ["reload"], "loadout": "gun", "drain": true},
	{"id": "shove", "kind": "press", "actions": ["shove"]},
	{"id": "kick", "kind": "press", "actions": ["kick"]},
	{"id": "weapon", "kind": "weapon", "want": "katana", "actions": ["slot1", "slot2", "slot3", "swap", "swap_back", "spatula_equip", "spatula"], "loadout": "gun"},
	{"id": "dash", "kind": "press", "actions": ["dash"], "loadout": "katana"},
	{"id": "spatula", "kind": "weapon", "want": "spatula", "actions": ["slot1", "slot2", "slot3", "swap", "swap_back", "spatula_equip", "spatula"], "loadout": "katana"},
	{"id": "pause", "kind": "pause", "actions": ["pause"]},
]
const CHEERS := ["Nice!", "Great!", "Boom!", "You got it!", "Smooth!", "Perfect!"]

static func count() -> int:
	return STEPS.size()

static func step(i: int) -> Dictionary:
	return STEPS[i] if i >= 0 and i < STEPS.size() else {}

static func index_of(id: String) -> int:
	for i in STEPS.size():
		if STEPS[i]["id"] == id: return i
	return -1

static func cheer(i: int) -> String:
	return TranslationServer.translate(CHEERS[i % CHEERS.size()])

static func _t(s: String) -> String:
	return TranslationServer.translate(s)

## The prompt for step `id` on `profile`: {text: translated sentence with %s holes, keys: names that fill the holes
## (the card highlights them)}. `String(text) % keys` is the plain sentence.
static func prompt(id: String, profile: String) -> Dictionary:
	var C := ControlProfile
	var touch: bool = profile == ControlProfile.TOUCH
	var pad: bool = profile == ControlProfile.GAMEPAD
	var toggle := str(Settings.get_value("aim_button", "hold")) == "toggle"
	match id:
		"move":
			if touch: return _p("Drag on the left side of the screen to move", [])
			if pad: return _p("Push %s to move", [C.move_text(profile)])
			return _p("Move with %s", [C.move_text(profile)])
		"look":
			if touch: return _p("Drag on the right side of the screen to look around", [])
			if pad: return _p("Push %s to look around", [C.look_text(profile)])
			return _p("Move the %s to look around", [C.look_text(profile)])
		"jump":
			return _p("Tap %s to jump" if touch else "Press %s to jump", [C.name_of("jump", profile)])
		"fire":
			if pad: return _p("Pull %s to fire at the dummy", [C.name_of("fire", profile)])
			return _p("Hold %s to fire at the dummy", [C.name_of("fire", profile)])
		"aim":
			if touch: return _p("Double-tap the right side of the screen to aim", [])
			return _p("Press %s to aim" if toggle else "Hold %s to aim", [C.name_of("aim", profile)])
		"reload":
			return _p("Tap %s to reload" if touch else "Press %s to reload", [C.name_of("reload", profile)])
		"shove":
			return _p("Tap %s to shove" if touch else "Press %s to shove", [C.name_of("shove", profile)])
		"kick":
			return _p("Hold %s to kick" if touch else "Press %s to kick", [C.name_of("kick", profile)])
		"weapon":
			if touch: return _p("Tap the katana tile to switch weapon", [])
			if pad: return _p("Press %s to switch weapon", [C.name_of("swap", profile)])
			return _p("Press %s to switch to the katana", [C.name_of("slot2", profile)])
		"dash":
			return _p("Tap %s to dash" if touch else "Press %s to dash", [C.name_of("dash", profile)])
		"spatula":
			if touch: return _p("Tap the spatula tile to go back to it", [])
			if pad: return _p("Press %s to switch back to the spatula", [C.name_of("swap", profile)])
			return _p("Press %s again to go back to the spatula", [C.name_of("slot2", profile)])
		"pause":
			if touch: return _p("Tap the pause button in the top corner", [])
			return _p("Press %s to pause", [C.name_of("pause", profile)])
	return {"text": "", "keys": []}

static func _p(text: String, keys: Array) -> Dictionary:
	return {"text": _t(text), "keys": keys}

## The sentence with the names filled in, no markup.
static func plain(id: String, profile: String) -> String:
	var d := prompt(id, profile)
	var keys: Array = d["keys"]
	return str(d["text"]) % keys if not keys.is_empty() else str(d["text"])
