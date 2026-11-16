class_name WinnerPodium
extends Node3D
## The 3D winner podium at the results moment (docs/GODOT_ARCH.md "Results podium"): a raised platform for the winner,
## a 2nd and a 3rd step, and everyone else standing beside it on the arena floor. The winners play the "pump" victory
## emote through the Wobbler API (the 2D results moment already did this on the local winner, ui/results_rewards.gd).
##
## Presentation only: it builds fresh Wobblers for the result (the live match views are hidden by World) and never
## touches the simulation, physics or Combat. No RNG is drawn, so the match state is identical with and without it.
##
## Ordering is the ordering the results/scoreboard already uses: the match winner first (ModeRules.end_match), then
## every fighter by K.O.s and damage dealt (the web result's rank sort, public/index.html renderResult). In team modes
## the whole winning team stands on the top platform and the other team beside it.
##
## World setup call order: `setup(...)` once, then `update(dt)` and `camera_shot()` per rendered frame while the results
## are up; the node is freed with the next match / the closed result.

const WINNER_TOP := 0.9            ## m: the winner platform's top above the arena floor
const SECOND_TOP := 0.62
const THIRD_TOP := 0.42
const WINNER_MIN_W := 4.4          ## m: the winner platform's width for one winner (it grows for a winning team)
const WINNER_D := 2.6
const WINNER_SPACING := 1.5        ## m between winners standing on the top platform
const STEP_W := 2.3
const STEP_D := 2.2
const SIDE_GAP := 0.25             ## m between the winner platform and a side step
const LOSER_GAP := 1.2             ## m from the side step to the first fighter beside the podium
const LOSER_SPACING := 1.35
const TOP_SLAB := 0.08             ## m: the bright cap on every platform
const EMOTE := "pump"              ## victory emote (Wobbler.play_emote ids, data/extra/locker.json)
## The results camera: distance and height from the podium, look height, and a slow sway so the shot is not a still.
const CAM_DIST := 8.6
const CAM_HEIGHT := 2.7
const CAM_LOOK_Y := 1.25
const CAM_SWAY := 0.10             ## rad: how far the shot swings either side of straight-on
const CAM_SWAY_SPEED := 0.28       ## rad/s

const WINNER_COL := 0xd9a441       ## gold
const WINNER_CAP := 0xffd479
const SECOND_COL := 0x9aa3ad       ## silver
const SECOND_CAP := 0xc9d2dc
const THIRD_COL := 0x9a6a43        ## bronze
const THIRD_CAP := 0xc98a58

var standings: Array = []          ## FighterState, in ranked order (winners first)
var slots: Array = []              ## {f: FighterState, place: int, pos: Vector3, wob: Wobbler}
var emote_requests: Array = []     ## FighterState asked to play the victory emote (winners only)
var winner_count := 0
var team_mode := false
var base := Vector3.ZERO           ## the podium's foot, on the arena floor
var face_yaw := 0.0                ## the podium's facing: the camera stands on this side and sees the arena behind
var width := 0.0                   ## m: the whole set's width (losers beside it included)
var _set: Node3D                   ## the platforms (positioned/rotated at `base` / `face_yaw`)
var _wobs: Node3D                  ## the podium Wobblers (identity transform: Wobbler takes world positions)
var _t := 0.0

## `looks` = FighterState -> {skin, hat, color} (World's resolved looks, team colour included); `teams` / `winning_team`
## decide the team result; `match_winner` = the ModeRules winner (null for a guest that only got the result message).
func setup(fighters: Array, looks: Dictionary, p_base: Vector3, p_yaw: float, teams: bool, winning_team: int, match_winner: Variant) -> void:
	base = p_base
	face_yaw = p_yaw
	team_mode = teams and winning_team >= 0
	name = "Podium"
	_set = Node3D.new()
	_set.name = "Set"
	_set.position = base
	_set.rotation.y = face_yaw
	add_child(_set)
	_wobs = Node3D.new()
	_wobs.name = "PodiumFighters"
	add_child(_wobs)
	var ranked := rank(fighters)
	var winners: Array = []
	var rest: Array = []
	if team_mode:
		for f: FighterState in ranked:
			if f.team == winning_team: winners.append(f)
			else: rest.append(f)
	elif match_winner is FighterState and ranked.has(match_winner):
		winners = [match_winner]
		for f: FighterState in ranked:
			if f != match_winner: rest.append(f)
	else:                                    # a guest without the host's winner: the result ranking decides
		if ranked.size() > 0: winners = [ranked[0]]
		if ranked.size() > 1: rest = ranked.slice(1)
	winner_count = winners.size()
	standings = winners + rest
	# geometry: the winner platform grows with the winning team; the side steps sit outside it
	var ww := maxf(WINNER_MIN_W, WINNER_SPACING * float(maxi(0, winner_count - 1)) + 2.2)
	var sx := ww / 2.0 + SIDE_GAP + STEP_W / 2.0
	_platform(Vector3.ZERO, Vector3(ww, WINNER_TOP, WINNER_D), WINNER_COL, WINNER_CAP)
	_platform(Vector3(-sx, 0.0, 0.1), Vector3(STEP_W, SECOND_TOP, STEP_D), SECOND_COL, SECOND_CAP)
	_platform(Vector3(sx, 0.0, 0.1), Vector3(STEP_W, THIRD_TOP, STEP_D), THIRD_COL, THIRD_CAP)
	# winners on the top platform; FFA's 2nd / 3rd on the side steps; everyone else beside the podium
	for i in winner_count:
		var lx := 0.0
		if winner_count > 1: lx = (float(i) - float(winner_count - 1) / 2.0) * WINNER_SPACING
		_add_fighter(winners[i], looks, Vector3(lx, WINNER_TOP, 0.15), 0.0, 1, true)
	var beside: Array = []                    # [{i: standings index, place: int}] placed beside the podium
	var next_place := 2
	for i in range(winner_count, standings.size()):
		if not team_mode and i == winner_count:
			_add_fighter(standings[i], looks, Vector3(-sx, SECOND_TOP, 0.15), 0.10, 2, false)
			next_place = 3
		elif not team_mode and i == winner_count + 1:
			_add_fighter(standings[i], looks, Vector3(sx, THIRD_TOP, 0.15), -0.10, 3, false)
			next_place = 4
		else:
			beside.append({"i": i, "place": next_place})
			next_place += 1
	var max_x := sx + STEP_W / 2.0 + 1.0
	for j in beside.size():
		var b: Dictionary = beside[j]
		var side := -1.0 if j % 2 == 0 else 1.0
		var row := j / 2
		var lx: float = side * (sx + STEP_W / 2.0 + LOSER_GAP + float(row) * LOSER_SPACING)
		max_x = maxf(max_x, absf(lx) + 1.0)
		_add_fighter(standings[int(b["i"])], looks, Vector3(lx, 0.0, -0.2), side * 0.12, int(b["place"]), false)
	width = max_x * 2.0
	update(0.0)

## The results/scoreboard order: K.O.s first, then damage dealt, then the setup order (a stable tie-break). No sorting
## by name or anything new: the web result panel's rank does exactly this (public/index.html renderResult).
static func rank(fighters: Array) -> Array:
	var out := fighters.duplicate()
	out.sort_custom(func(a, b) -> bool:
		if a.ko != b.ko: return a.ko > b.ko
		var ad := float(a.st.get("dmg", 0.0))
		var bd := float(b.st.get("dmg", 0.0))
		if not is_equal_approx(ad, bd): return ad > bd
		return a.id < b.id)
	return out

## Per rendered frame: pose every podium Wobbler (idle wobble, and the winners' emote) from a fixed stage state. The
## simulation is never read, so the match behind the result cannot move the podium.
func update(dt: float) -> void:
	_t += maxf(dt, 0.0)
	for s: Dictionary in slots:
		var w: Wobbler = s["wob"]
		if w == null or not is_instance_valid(w): continue
		var p: Vector3 = s["pos"]
		w.apply_state({
			"pos": p, "vel": Vector3.ZERO, "yaw": face_yaw, "aim": Vector3(0.0, -1.0, 0.2).normalized(),
			"grounded": true, "crouch": 0.0, "dead": false, "down_t": 0.0, "weapon": "", "swing": -1.0,
			"kick_t": -1.0, "invuln": false, "flash": 0.0, "wish": Vector2.ZERO,
			"class_id": s["class_id"], "skin": s["skin"], "hat": s["hat"], "color": s["color"],
		})
		w.animate(dt)

## Where the results camera stands and what it looks at, when the podium is set up (the closing transition is the
## camera's, world/follow_camera.gd frame_podium). A slow sway keeps the shot alive without turning into an orbit.
func camera_shot() -> Dictionary:
	var a := sin(_t * CAM_SWAY_SPEED) * CAM_SWAY
	var d := CAM_DIST + maxf(0.0, width - 12.0) * 0.45
	var local_pos := Vector3(sin(a) * d, CAM_HEIGHT, cos(a) * d)
	var local_look := Vector3(0.0, CAM_LOOK_Y, 0.0)
	return {"pos": _to_world(local_pos), "look": _to_world(local_look)}

## A platform: a coloured body from the floor up to `size.y`, with a brighter cap slab on top.
func _platform(local_pos: Vector3, size: Vector3, body_col: int, cap_col: int) -> void:
	_box(local_pos + Vector3(0.0, size.y / 2.0, 0.0), size, body_col)
	_box(local_pos + Vector3(0.0, size.y - TOP_SLAB / 2.0, 0.0), Vector3(size.x + 0.06, TOP_SLAB, size.z + 0.06), cap_col)

func _box(center: Vector3, size: Vector3, color: int) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Step_%06x" % color
	mi.mesh = MapBuilder.box_mesh(size)
	mi.material_override = MapBuilder.box_view_material(color)
	mi.position = center
	_set.add_child(mi)

## One podium fighter: its own Wobbler (never the live match view) at `local_pos`, facing the camera; the winners play
## the victory emote once, right away (the Wobbler API the 2D results moment used).
func _add_fighter(f: FighterState, looks: Dictionary, local_pos: Vector3, local_yaw: float, place: int, is_winner: bool) -> void:
	var lk: Dictionary = looks.get(f, {})
	var col := int(lk.get("color", WobblerLooks.DEFAULT_COLOR))
	var w := Wobbler.new()
	w.name = "PodiumFighter_%d" % f.id
	_wobs.add_child(w)
	w.setup(f.class_id, str(lk.get("skin", "none")), str(lk.get("hat", "none")), col)
	if team_mode: w.recolor(col, true)       # team modes keep the team-colour outfit, like the live fighters
	var p := _to_world(local_pos)
	var s := {
		"f": f, "place": place, "pos": p, "wob": w, "class_id": f.class_id,
		"skin": str(lk.get("skin", "none")), "hat": str(lk.get("hat", "none")), "color": col,
	}
	slots.append(s)
	if is_winner and w.play_emote(EMOTE):
		emote_requests.append(f)

func _to_world(local: Vector3) -> Vector3:
	return base + Basis(Vector3.UP, face_yaw) * local
