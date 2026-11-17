extends RefCounted
## Construction: the existing hazard-tape wipe (ui/dlc_transition.gd) and its banner, driven by the transition's `p` instead
## of its own tween (the tape, the stagger and the banner pop are the DlcTransition's, untouched). One eased curve: the tape
## covers over the first half (easing to a stop at p = 0.5 with the banner up while the hub opens) and slides off over the second.

var cues := [[0.3, "clink", 0.8], [0.62, "land", 0.5]]
var _tape: DlcTransition

func setup(t: PackTransition) -> void:
	_tape = DlcTransition.new()
	_tape.name = "Tape"
	t.add_child(_tape)
	_tape.visible = true
	_tape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tape.z_index = 0
	_tape._font = UiTheme.font(700)

func tick(t: PackTransition) -> void:
	if _tape == null: return
	# DlcTransition's p: 0 -> 1 covers, 1 -> 2 uncovers (its banner shows around p == 1)
	var v := PackTransition.smooth(PackTransition.seg(t.p, 0.0, 0.5)) + PackTransition.smooth(PackTransition.seg(t.p, 0.5, 1.0))
	_tape.p = v

func draw(_t: PackTransition) -> void:
	pass
