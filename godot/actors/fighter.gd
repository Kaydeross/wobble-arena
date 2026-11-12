class_name Fighter
extends Node3D
## One fighter on screen: composes the logic (FighterState with its FighterPhysics, simulated by MatchSim) with the
## Wobbler (visual only). Per rendered frame `present(dt)` feeds the state to the wobbler, animates it, then writes the
## points the combat code reads back (hand, arm direction, shoulder, head, chest, legs), like the web game's
## animate + applyPose (public/index.html ~5619, ~5882). Keep this node at the identity transform: the wobbler places
## itself in world space from `pos`.

var state: FighterState
var wobbler: Wobbler
var look := {"skin": "none", "hat": "none", "color": 0x39b5a8}
var tag: Label3D                  ## name over bots (null for the player)

func _ready() -> void:
	wobbler = $Wobbler

## Bind the logic state and the look (class from the state, outfit/hat/colour from `p_look`).
func bind(p_state: FighterState, p_look: Dictionary) -> void:
	if wobbler == null:
		wobbler = $Wobbler
	state = p_state
	look.merge(p_look, true)
	name = "Fighter_%d" % state.id
	wobbler.setup(state.class_id, look["skin"], look["hat"], look["color"])
	wobbler.set_weapon(state.weapon)
	if not state.is_player:
		tag = Label3D.new()
		tag.text = state.name
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.font_size = 40
		tag.pixel_size = 0.006
		tag.outline_size = 10
		tag.modulate = Color(1, 1, 1, 0.95)
		tag.no_depth_test = false
		add_child(tag)
	present(0.0)

## What the wobbler needs this frame (docs/GODOT_ARCH.md FighterState contract + wish, trap, fall_side, flash seconds).
func visual_state() -> Dictionary:
	var f := state
	var p := f.phys
	var v := f.to_visual()
	v["yaw"] = f.face_yaw              # the wobbler smooths toward it like Fighter.animate
	v["wish"] = Vector2(p.wish_x, p.wish_z)
	v["trap"] = f.trap_t > 0.0
	v["fall_side"] = float(f.fall_side)
	v["skin"] = look["skin"]; v["hat"] = look["hat"]; v["color"] = look["color"]
	return v

## Feed + animate the wobbler, then read the animation points back into the state (before the melee sweep).
func present(dt: float) -> void:
	wobbler.apply_state(visual_state())
	wobbler.animate(dt)
	var f := state
	var hp := wobbler.hand.global_position
	f.hand_x = hp.x; f.hand_y = hp.y; f.hand_z = hp.z
	var ad := wobbler.arm_dir
	f.arm_x = ad.x; f.arm_y = ad.y; f.arm_z = ad.z
	var sp := wobbler.arm.global_position
	f.shoulder_x = sp.x; f.shoulder_y = sp.y; f.shoulder_z = sp.z
	var hd := wobbler.head_mesh.global_position
	f.head_x = hd.x; f.head_y = hd.y; f.head_z = hd.z
	var ch := wobbler.torso.global_position
	f.chest_x = ch.x; f.chest_y = ch.y; f.chest_z = ch.z
	f.update_leg()
	if tag:
		tag.visible = not f.dead
		tag.position = Vector3(f.phys.px, f.phys.py + 3.0 * float(wobbler.cls.get("size", 1.0)), f.phys.pz)

## A Combat event aimed at this fighter's body (lean/head spring kicks, arm shoves).
func on_event(e: Dictionary) -> void:
	match String(e["type"]):
		"lean": wobbler.lean.kick(e["a"], e["b"])
		"head": wobbler.head.kick(e["a"], e["b"])
		"arm": wobbler.arm_vel += Vector3(e["x"], e["y"], e["z"])
