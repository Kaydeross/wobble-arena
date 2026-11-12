class_name KillCam
extends RefCounted
## Kill cam (the web game's kcActive / startKillCam / kcSegments / kcCamera, public/index.html ~10338, turned round:
## here it plays when YOU score a fast K.O.): every fighter's look (Fighter.visual_state()) is kept for the last
## REC_MAX / REC_HZ seconds in a ring buffer; AFTER seconds after a fast K.O. the match pauses and the last BACK seconds
## replay from the side (both fighters in frame, a slow orbit), normal speed and slow-mo (SLOW) round the hit, then
## the camera goes back to the follow camera and the match carries on. A tap / click / key skips it.
## Only the wobblers are posed from the recording: the FighterStates are never touched, so the match resumes exactly
## where it stopped. World decides when it runs (offline, Settings `kill_cam`, not in team modes, not while
## spectating or after the match is over).

const REC_HZ := 30.0
const REC_MAX := 120             ## 4 s of frames
const BACK := 1.4                ## s of match shown before the K.O.
const AFTER := 0.6               ## s of match after the K.O. (the replay starts this long after it)
const SLOW := 0.4                ## slow-mo speed round the K.O.
const SLOW_BEFORE := 0.3         ## s before the K.O. the slow-mo starts
const SLOW_AFTER := 0.35         ## s after the K.O. it ends
const HOLD := 0.3                ## s the last frame stays up
const FAST_KILL := 3.0           ## s from your first hit on the victim to the K.O.: a "fast kill"
const COOLDOWN := 15.0           ## s between two kill cams
const FOV := 58.0
const ORBIT := 0.9               ## rad the camera drifts round over the replay

var views: Array = []            ## Fighter per recorded slot (fixed order)
var ring: Array = []             ## {n, s: Array of visual_state()} (oldest at `head` when full)
var head := 0
var n := 0                       ## frames recorded so far
var time := 0.0                  ## match seconds recorded (pauses with the match)
var _acc := 0.0

var first_hit := {}              ## FighterState -> time of your first hit in this exchange
var pending := {}                ## {k, v, n, at}: a fast K.O. waiting for its AFTER seconds
var last_at := -1.0e9

var active := false
var frames: Array = []           ## the replay (oldest first)
var idx := 0.0                   ## replay position (frame index, fractional)
var ko_i := 0
var from_i := 0
var to_i := 0
var hold := 0.0
var ki := 0                      ## killer / victim slots
var vi := 0
var cam_pos := Vector3.ZERO
var look_at := Vector3.ZERO
var _has_cam := false
var shown := 0.0                 ## seconds the replay has been on screen

func setup(p_views: Array) -> void:
	views = p_views.duplicate()
	ring.clear(); head = 0; n = 0; time = 0.0; _acc = 0.0
	first_hit.clear(); pending = {}; active = false; frames = []

func slot_of(f: FighterState) -> int:
	for i in views.size():
		if views[i].state == f: return i
	return -1

## Per rendered frame while the match runs: keep REC_HZ snapshots.
func record(dt: float) -> void:
	time += dt
	_acc += dt
	if _acc < 1.0 / REC_HZ: return
	_acc = fmod(_acc, 1.0 / REC_HZ)
	var s: Array = []
	s.resize(views.size())
	for i in views.size(): s[i] = views[i].visual_state()
	var fr := {"n": n, "s": s}
	n += 1
	if ring.size() < REC_MAX: ring.append(fr)
	else:
		ring[head] = fr
		head = (head + 1) % REC_MAX

## Oldest first.
func recorded() -> Array:
	if ring.size() < REC_MAX: return ring.duplicate()
	return ring.slice(head) + ring.slice(0, head)

## You hit `victim`.
func note_hit(victim: FighterState) -> void:
	if not first_hit.has(victim) or time - float(first_hit[victim]) > FAST_KILL:
		first_hit[victim] = time

## You K.O.'d `victim`: a fast one (and not too soon after the last replay) is queued. true if queued.
func on_ko(killer: FighterState, victim: FighterState) -> bool:
	var t0: float = first_hit.get(victim, -1.0e9)
	first_hit.erase(victim)
	var fast := time - t0 <= FAST_KILL
	if not fast or time - last_at < COOLDOWN or ring.size() < int(REC_HZ) or not pending.is_empty(): return false
	var k := slot_of(killer)
	var v := slot_of(victim)
	if k < 0 or v < 0: return false
	pending = {"k": k, "v": v, "n": n, "at": time + AFTER}
	return true

func due() -> bool:
	return not pending.is_empty() and time >= float(pending["at"])

## Start the replay of the queued K.O.
func start() -> bool:
	if pending.is_empty(): return false
	frames = recorded()
	ki = int(pending["k"]); vi = int(pending["v"])
	ko_i = frames.size() - 1
	for i in frames.size():
		if int(frames[i]["n"]) >= int(pending["n"]):
			ko_i = i; break
	from_i = maxi(0, ko_i - int(BACK * REC_HZ))
	to_i = frames.size() - 1
	pending = {}
	if to_i - from_i < 8: frames = []; return false
	idx = float(from_i); hold = 0.0; shown = 0.0
	_has_cam = false
	active = true
	last_at = time
	for v: Fighter in views:
		if v.tag: v.tag.visible = false
	return true

func speed_at(i: float) -> float:
	return SLOW if i > ko_i - SLOW_BEFORE * REC_HZ and i < ko_i + SLOW_AFTER * REC_HZ else 1.0

## 0..1 through the replay.
func progress() -> float:
	return clampf((idx - from_i) / maxf(1.0, to_i - from_i), 0.0, 1.0)

## One rendered frame of the replay: poses the wobblers and moves `cam`. false when it has ended.
func step(dt: float, cam: Camera3D, solids: Array) -> bool:
	if not active: return false
	shown += dt
	var sp := speed_at(idx)
	idx = minf(float(to_i), idx + dt * REC_HZ * sp)
	if idx >= to_i:
		hold += dt
		if hold > HOLD:
			stop()
			return false
	var i := mini(to_i, floori(idx))
	var j := mini(to_i, i + 1)
	var t := idx - i
	for k in views.size():
		var a: Dictionary = frames[i]["s"][k]
		var b: Dictionary = frames[j]["s"][k]
		var d := a.duplicate()
		d["pos"] = (a["pos"] as Vector3).lerp(b["pos"], t)
		d["yaw"] = lerp_angle(float(a["yaw"]), float(b["yaw"]), t)
		var w: Wobbler = views[k].wobbler
		w.apply_state(d)
		w.animate(dt * sp)
		if w.rig_mode == "ragdoll": w.overlay(dt * sp)
	_camera(dt, cam, solids, frames[i]["s"], frames[j]["s"], t)
	return true

## From the side of the killer and the victim, both in frame, drifting round; pulled in front of walls.
func _camera(dt: float, cam: Camera3D, solids: Array, sa: Array, sb: Array, t: float) -> void:
	var kp := (sa[ki]["pos"] as Vector3).lerp(sb[ki]["pos"], t)
	var vp := (sa[vi]["pos"] as Vector3).lerp(sb[vi]["pos"], t)
	if vp.y < kp.y - 6.0: vp.y = kp.y - 6.0           # a victim falling off: keep the killer in frame
	var mid := (kp + vp) * 0.5
	var dx := vp.x - kp.x
	var dz := vp.z - kp.z
	var sep := Vector2(dx, dz).length()
	var side := Vector2(-dz, dx) / sep if sep > 0.5 else Vector2(1, 0)
	var ang := atan2(side.x, side.y) + (progress() - 0.5) * ORBIT
	var dist := clampf(sep * 0.85 + 5.0, 6.0, 14.0)
	var pivot := mid + Vector3(0, 1.1, 0)
	var want := mid + Vector3(sin(ang) * dist, 2.4, cos(ang) * dist)
	var dir := want - pivot
	var l := dir.length()
	var hit := FollowCamera.ray_solids(pivot, dir / l, l, solids)
	if hit < l: want = pivot + dir / l * maxf(1.5, hit - 0.3)
	if not _has_cam:
		cam_pos = want; _has_cam = true
	else:
		cam_pos = cam_pos.lerp(want, 1.0 - exp(-5.0 * dt))
	look_at = pivot
	cam.look_at_from_position(cam_pos, look_at, Vector3.UP)
	cam.fov = FOV

func stop() -> void:
	if not active: return
	active = false
	frames = []
	for v: Fighter in views:
		if v.tag: v.tag.visible = not v.state.dead
